#!/usr/bin/env bash
# Launch the Release build with MangoHud and collect CPU/GPU/PipeWire data alongside it.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GAME="$ROOT/out/build/linux-amd64-release/crackdown"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/out/perf-capture/$STAMP"
CPU_PROFILE=0
SKIP_LAUNCHER=1

fail() { echo "ERROR: $*" >&2; exit 1; }

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    echo "Usage: $0 [--cpu-profile] [--launcher] [game arguments...]"
    echo "The launcher is skipped (--crackdown_skip_launcher=true; saved launcher settings still apply); --launcher shows it."
    echo "Launch the Release build with MangoHud and save CPU, GPU, and PipeWire samples under out/perf-capture/."
    echo "--cpu-profile additionally records sampled call stacks and writes perf-report.txt."
    exit 0
fi
while [[ "${1:-}" == --cpu-profile || "${1:-}" == --launcher ]]; do
    [[ "$1" == --cpu-profile ]] && CPU_PROFILE=1
    [[ "$1" == --launcher ]] && SKIP_LAUNCHER=0
    shift
done
GAME_ARGS=("$@")
(( SKIP_LAUNCHER )) && GAME_ARGS=(--crackdown_skip_launcher=true "${GAME_ARGS[@]}")

[[ -x "$GAME" ]] || fail "Release executable not found: $GAME (build it with tools/build.sh release)"
for tool in mangohud nvidia-smi top pw-top; do
    command -v "$tool" >/dev/null 2>&1 || fail "required capture tool not found: $tool"
done
if (( CPU_PROFILE )); then
    command -v perf >/dev/null 2>&1 || fail "perf is required for --cpu-profile"
fi

mkdir -p "$OUT"
cat > "$OUT/README.txt" <<EOF
Crackdown Recompiled performance capture
Started: $(date --iso-8601=seconds)
Executable: $GAME
The game was launched with MangoHud. Reproduce the slowdown, then exit normally.
cpu-threads.txt: top CPU/thread samples
gpu.csv: NVIDIA utilization, clocks, power, and temperature
pipewire.txt: PipeWire graph samples (if pw-top can connect)
 MangoHud logs frame timing to mangohud_log.csv at 100 ms intervals.
$(if (( CPU_PROFILE )); then echo 'perf.data and perf-report.txt: sampled CPU call stacks'; fi)
EOF

# MangoHud's benchmark log gives frame-time/FPS data that can be aligned with the
# timestamped per-thread CPU samples when the slowdown occurs.
cat > "$OUT/MangoHud.conf" <<EOF
fps
frametime
frame_timing
cpu_stats
gpu_stats
core_load
autostart_log=1
log_interval=100
output_folder=$OUT
output_file=mangohud_log.csv
EOF

echo "Capture folder: $OUT"
echo "Reproduce the slowdown, then exit the game normally. MangoHud shows frame time and CPU/GPU stats."
echo "For the wait/fault profile: at the test spot, keep still and run in a second terminal: sudo tools/perf/waitprof.sh"

MANGOHUD=1 MANGOHUD_CONFIGFILE="$OUT/MangoHud.conf" \
    "$GAME" "${GAME_ARGS[@]}" &
GAME_PID=$!
COLLECTORS=()
PERF_PID=""

cleanup() {
    for pid in "${COLLECTORS[@]:-}"; do
        kill "$pid" 2>/dev/null || true
    done
    if [[ -n "$PERF_PID" ]]; then
        kill -INT "$PERF_PID" 2>/dev/null || true
    fi
    for pid in "${COLLECTORS[@]:-}"; do
        wait "$pid" 2>/dev/null || true
    done
    if [[ -n "$PERF_PID" ]]; then
        wait "$PERF_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

# Keep per-thread CPU samples; this helps separate a saturated emulation thread from a GPU wait.
top -b -H -d 0.5 -p "$GAME_PID" > "$OUT/cpu-threads.txt" 2>&1 &
COLLECTORS+=("$!")

nvidia-smi --query-gpu=timestamp,utilization.gpu,utilization.memory,clocks.gr,clocks.mem,power.draw,temperature.gpu \
    --format=csv -l 1 > "$OUT/gpu.csv" 2> "$OUT/nvidia-smi-errors.txt" &
COLLECTORS+=("$!")

pw-top -b > "$OUT/pipewire.txt" 2>&1 &
COLLECTORS+=("$!")

if (( CPU_PROFILE )); then
    # DWARF callchains resolve into the Release binary's available debug symbols.
    perf record -F 49 --call-graph dwarf,8192 -p "$GAME_PID" -o "$OUT/perf.data" \
        > "$OUT/perf-record.txt" 2>&1 &
    PERF_PID="$!"
    echo "CPU call-stack sampling is active."
fi

set +e
wait "$GAME_PID"
RESULT=$?
set -e
cleanup
trap - EXIT INT TERM
if (( CPU_PROFILE )) && [[ -s "$OUT/perf.data" ]]; then
    perf report --stdio --children --sort comm,dso,symbol --percent-limit 1 -i "$OUT/perf.data" \
        > "$OUT/perf-report.txt" 2> "$OUT/perf-report-errors.txt" || true
fi
echo "Capture saved to: $OUT"
exit "$RESULT"
