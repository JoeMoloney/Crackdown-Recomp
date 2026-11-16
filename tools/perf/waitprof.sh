#!/usr/bin/env bash
# Wait/fault profile of the running game (ported from Fable-2-Recomp tools/perf/waitprof.sh).
#
#   sudo tools/perf/waitprof.sh [CAPTURE_DIR]
#
# Start the game with tools/profile-linux.sh, go to the test spot, keep the camera still, then run this in a second
# terminal. It takes about 45 s; stay still until it prints "done". CAPTURE_DIR defaults to the newest
# out/perf-capture/<stamp> folder (the one tools/profile-linux.sh just made), so everything lands in one place.
#
# Step 1 (no root): per-thread user/kernel CPU, run-queue wait, context switches, R/S state -> waitprof.txt, plus the
#   FPS of the same seconds from the MangoHud log -> fps-summary.txt.
# Step 2 (root only): SIGSEGV rate (the GPU write-watch faults) -> signals.txt; who wakes whom (perf sched) ->
#   sched-*.txt; a 10 s CPU profile including kernel time -> perf-kernel-report.txt and the lines for the fault path
#   (QueryProtect, FindEntryForAddress, /proc/self/maps parsing, the MMIO exception handler) -> fault-path.txt.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
NAME=crackdown
fail() { echo "ERROR: $*" >&2; exit 1; }

OUT="${1:-}"
if [[ -z "$OUT" ]]; then
  OUT="$(ls -d "$ROOT"/out/perf-capture/*/ 2>/dev/null | sort | tail -1)"
  [[ -n "$OUT" ]] || fail "no out/perf-capture folder; start the game with tools/profile-linux.sh or pass a folder"
fi
OUT="${OUT%/}"
mkdir -p "$OUT"
PID="$(pgrep -n -x "$NAME" || true)"
[[ -n "$PID" ]] || fail "the game ($NAME) is not running"
echo "pid=$PID -> $OUT"

echo "== Step 1: per-thread wait profile, 20 s (keep still)"
python3 -I "$ROOT/tools/perf/waitprof.py" "$OUT" 20 "$NAME"
python3 -I "$ROOT/tools/perf/fps-summary.py" "$OUT" | tee "$OUT/fps-summary.txt" || true

if [[ $EUID -eq 0 ]]; then
  command -v perf >/dev/null || fail "perf not found"
  echo "== Step 2a: signals, 5 s (write-watch faults arrive as SIGSEGV, signal 11)"
  perf stat -e signal:signal_deliver --filter 'sig == 11' -p "$PID" -o "$OUT/signals.txt" -- sleep 5 || true
  perf stat -e signal:signal_deliver -p "$PID" -o "$OUT/signals-all.txt" -- sleep 2 || true
  grep -E 'signal_deliver|seconds' "$OUT/signals.txt" || true

  echo "== Step 2b: perf sched, 5 s"
  perf sched record -o "$OUT/sched.data" -p "$PID" -- sleep 5 2> "$OUT/sched.err" || true
  perf sched timehist -i "$OUT/sched.data" -s 2>/dev/null > "$OUT/sched-summary.txt" || true
  perf sched timehist -i "$OUT/sched.data" -w 2>/dev/null > "$OUT/sched-wakeups.txt" || true

  echo "== Step 2c: cycles including kernel, 10 s"
  # LBR call stacks work without frame pointers on Intel; fall back to flat samples elsewhere.
  if ! perf record -e cycles -F 999 --call-graph lbr -p "$PID" -o "$OUT/perf-kernel.data" -- sleep 10 \
      2> "$OUT/perf-kernel.err"; then
    perf record -e cycles -F 999 -p "$PID" -o "$OUT/perf-kernel.data" -- sleep 10 2>> "$OUT/perf-kernel.err" || true
  fi
  perf report --stdio --no-children --sort comm,dso,symbol --percent-limit 0.3 -g none -i "$OUT/perf-kernel.data" \
    > "$OUT/perf-kernel-report.txt" 2>/dev/null || true
  perf report --stdio --children --sort symbol -g none -i "$OUT/perf-kernel.data" 2>/dev/null |
    grep -E 'QueryProtect|FindEntryForAddress|ParseMapsLine|ExceptionCallback|MMIOHandler|SharedMemory|WatchRange|basic_ifstream|__isoc23_sscanf|sscanf|show_map|sched_yield|futex' \
    > "$OUT/fault-path.txt" || true
  echo "-- fault path (% of samples, incl. children):"
  head -20 "$OUT/fault-path.txt" || true
  chown -R "${SUDO_UID:-1000}:${SUDO_GID:-1000}" "$OUT"
else
  echo "(not root: skipped signals / perf sched / kernel profile. Re-run with sudo for those.)"
fi
echo "done -> $OUT"
