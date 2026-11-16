# Port Fable II's Linux perf fixes to Crackdown — multi-session plan (START HERE)

Started 2026-11-15. Source of the fixes: Fable-2-Recomp `plans/done/PERF_SESSIONS.md` (Fable went
16 → solid 30 FPS on the same desktop: i9-10900K, RTX 3090, CachyOS). Its SDK changes are commits on
the `fable2` branch of the rexglue-sdk fork (`gitlab.com/JoeMoloney/rexglue-sdk`). Crackdown can't
cherry-pick them: it pins Himdo `c04750f` and applies `patches/rexglue-sdk/*.patch`, so every port
becomes a **new patch file** in that series.

**Goal:** find out which missing Fable fixes help Crackdown, keeping the ones that do. Budget: **~6–8 game
boots** (10 max).

**Working style:** one unit per session. The user drives the game and launches; Claude edits, rebuilds and
reads the numbers. Every port sits **behind a cvar** (launch flag), so a single build covers several A/B runs.
Use **the same save, spot and camera angle** for every boot (in Fable a small angle change moved FPS 24 ↔ 31).
Measure with the in-game guest FPS where available, plus MangoHud median/p10 (see
`docs/linux-performance-investigation.md` for why the mean is misleading).

## Already in Crackdown (don't port)

| Fable fix | Crackdown equivalent |
|---|---|
| `clear_memory_page_state` default false | `0025-gpu-draw-path.patch` |
| Batch type-0 register writes | `0024-gpu-register-write-bulk-path.patch` |
| Cap UI presenter on Linux | `0023-ui-repaint-with-guest-frames.patch` + Himdo host frame limit |
| Blocking TimerQueue | `0015-timer-queue-blocking-wait.patch` |
| Guest vblank pacing / memexport readback | Fable-specific, not relevant |

## To port (Fable SDK commit → what it does)

| Fix | Fable commit | Fable gain | Cvar |
|---|---|---|---|
| A. `QueryProtect` via `PROCMAP_QUERY` ioctl instead of reading `/proc/self/maps` on every write fault | `aca9333` | 18 → 25 FPS | add one (e.g. `linux_procmap_query`, default on) |
| B. `gpu_write_fault_widen_kb` (smaller unprotect window per GPU write fault) | `33a5b17` | → 35–40 FPS uncapped | `--gpu_write_fault_widen_kb` (256 = old behaviour; Fable uses 16) |
| C. Vulkan async submit thread (Crackdown only has D3D12's, `0081`) | `ca59f4e` | −1.2 ms/frame | `--vulkan_async_submit` |
| D. Fully blocking `WaitMultiple` (per-handle waiter + condvar). Crackdown's `0028` still polls with 100 µs sleeps | `d5a7f9e` | Audio Worker 1 core → 0.03 | add one |
| E. (optional) Vulkan skip unchanged constant writes, cached device pointer (D3D12 equivalent `0099`) | `a0c7269`, `9fda9b4` | small | — |

## Session queue

| # | Unit | Boots | Status |
|---|---|---|---|
| 0 | **Finish the Himdo migration**: standard `tools/build.sh release` passes with the verifier on (2026-11-15). See "Unit 0 notes" below. | — | ✅ |
| 1 | Smoke test the migrated build **and** baseline profile at the heavy scene: FPS + wait profile (port Fable's `tools/perf/waitprof.sh` idea, or extend `tools/profile-linux.sh`). Look for: SIGSEGV/write-fault rate, `QueryProtect`/`/proc/self/maps` time, Audio Worker spin, GPU Commands work per frame. **Decision point:** if write faults are rare, skip A/B and investigate where it actually waits instead. | 1 | ✅ 2026-11-15: boot 1 found regressions → unit 0b; boot 2 on the 0b build = baseline (33 FPS), see "Baseline" |
| 0b | **Restore patches the Himdo port dropped** (found in unit 1): audit every old patch vs the Himdo tree, port the missing ones into `1105-himdo-port.patch`, rebuild. See "Unit 0b". | — | ✅ built 2026-11-15 (verifier on, fingerprint `f92b314f9a85`, tests 56/57 as before); boot = redo unit 1 |
| 2 | **Revised after baseline:** port **C** (Vulkan async submit) + **E** (Vulkan skip unchanged constant writes / cached device pointer) as cvar-gated changes in 1105. A, B, D skipped (see "Baseline"). Build, run `tools/test.sh`. | 0 | ✅ 2026-11-16: built (verifier on, fingerprint `9f0a59dd7543`), tests 56/57 as before. See "Unit 2" |
| 3 | C on (E off) vs baseline | 1 | ✅ 2026-11-16: 35.4 / 32.8, stable |
| 4 | + E | 1 | ✅ 2026-11-16: 36.2 / 35.1, stable. Keep both |
| 5 | spare / follow-up on whatever the C+E profile shows | 1 | ⏳ |
| 6 | (dropped: D not needed) | — | — |
| 7 | All kept fixes on, normal longer play: hitches, audio, visuals. Seed winning cvars as defaults. | 1 | 🔶 2026-11-16: both set in `config/crackdown.toml` (unit 5 skipped); play session pending. Also fixed: editing only the config never reached the staged build (now its own CMake target) |
| — | Spare boots for crashes / unclear results | 1–2 | |

## Unit 0 notes (2026-11-15)

- Done: Himdo codegen (`tools/codegen-linux.sh`), SDK (`tools/setup-linux-sdk.sh`), patched runtime + stamp
  (`ReXGlue patches: current (1 patches, fingerprint 30228e374044)`), and `tools/build.sh release` with the verifier on
  (it checked both the SDK and the copies staged next to `out/build/linux-amd64-release/crackdown`). All 264 objects
  were rebuilt. The generated guest C++ is byte-identical to the v0.10.0 output.
- Tests: `CRACKDOWN_TEST_BUILD=out/tests-linux-himdo tools/test.sh` → 56/57. `packaging_tests` fails on two text checks
  of `tools/package-release.ps1`; it was already failing before the migration (script untouched since `757ad47`).
- Script fixes made this session: codegen handles Himdo's libmspack submodule; setup + runtime build use the same
  compiler (a compiler mismatch made CMake drop `-march` → SSSE3 build errors); setup skips when `himdo-sdk.txt` matches
  (otherwise each `build.sh` reinstalled the plain runtime over the patched one); runtime build clears a CMake cache
  left by another compiler. Upgrade traps written up in `docs/linux.md`.
- Backup of the previous v0.10.0 build, its `user_data` and generated code: `out/known-good-v0.10.0/` (7.2 GB).
  Old codegen worktree moved to `out/rexglue-codegen-v0.10.0/`.
- **Not done:** an actual game boot (that's unit 1's first step). Windows scripts reviewed but not run.
- Known gaps (not needed for perf work): `tools/build.sh debug` won't link (Himdo SDK has no Debug runtime);
  Windows `-Restore`/stock-file checks still assume v0.10.0 stock DLLs; `THIRD-PARTY-LICENSES.txt` still names
  ReXGlue 0.10.0 (fix before any release).
- **Don't** use `tools/launch-linux-550.sh` with this build: it injects the old v0.10.0-based #550 runtime via
  `LD_LIBRARY_PATH`. Launch `out/build/linux-amd64-release/crackdown` directly or with `tools/profile-linux.sh`.

## Unit 1 procedure (tools ready 2026-11-15)

New: `tools/perf/waitprof.sh` + `waitprof.py` (port of Fable's wait profiler, attaches to the running `crackdown` by
name) and `tools/perf/fps-summary.py` (median/p10 FPS from the MangoHud log, cut to the same seconds as the profile).

1. Terminal 1: `tools/profile-linux.sh` (MangoHud + per-thread top + GPU). It skips the launcher (saved launcher settings
   still apply; `--launcher` shows it). Load the save, go to the spot.
2. Stand still with the fixed camera angle; note the in-game guest FPS.
3. Terminal 2: `sudo tools/perf/waitprof.sh` — about 45 s; don't move until it prints `done`.
4. Quit the game normally. Everything is in the newest `out/perf-capture/<stamp>/`: `waitprof.txt`, `fps-summary.txt`,
   `signals.txt` (SIGSEGV count over 5 s), `perf-kernel-report.txt`, `fault-path.txt`, `sched-*.txt`.

Reading it (decision point): SIGSEGV/s ÷ FPS = faults per frame (Fable: ~30/frame, ~0.5 ms each). If `fault-path.txt`
shows `QueryProtect`/`FindEntryForAddress` at several % → A and B are worth it. If faults are rare, skip A/B and look
at which thread in `waitprof.txt` is saturated (~1.0 core, R ~100%) and what the others wait on. Himdo still reads
`/proc/self/maps` as text in `FindEntryForAddress` (`src/core/memory_posix.cpp`), the path fix A replaces.

## Unit 1 findings (2026-11-15, `out/perf-capture/20261115-204932/`, Himdo build)

- **GPU Commands thread is the limiter**: 0.98 cores, R 99%, 96% user time. Guest threads ~0.2 cores each, main 0.35.
  44% of all CPU samples are on GPU Commands: emulator code 23%, libc (memcpy) 9%, NVIDIA driver 7%.
- **Write faults are frequent but cheap**: ~1,280 SIGSEGV/s, yet `MMIOHandler::ExceptionCallback` is 0.67% of samples and
  the `/proc/self/maps` parsing (`sscanf`) ~0.1%; thread kernel time is tiny. → **fix A: low value. B: maybe** (shared
  memory upload `RequestRanges`/`UploadRanges` is ~5.5%).
- **memcpy in `IssueCopy_ReadbackResolvePath` = 4.2% of all samples (~9% of GPU Commands)**: resolve readback copies
  every resolve back to guest memory, because:
- **Migration regression 1 — patches dropped from `1105-himdo-port.patch`.** Old-patch cvars missing in Himdo:
  `readback_resolve_max_bytes` (0056; `config/crackdown.toml` still sets 256 KB, now ignored), `gpu_invalidation_expand_pages`
  (0078, plus its lock-free validity check), `gpu_draw_state_memo` (0080). (`gpu_skip_unchanged_constant_writes`, 0099,
  is D3D12-only.) Only patches with cvars were checked; patches without cvars may be missing too.
- **Migration regression 2 — file system.** The game log has ~2,900 `ResolvePath(...) failed - device not found` and
  ~3,350 `NtCreateFile FAILED` (e.g. `config\npc\population`, `cache:\xuifrontend\en-US\scene.xzp`), vs 12 in a 6-minute
  v0.10.0 session (`crackdown_034.log`). Could mean missing NPC/mission config → not comparable to v0.10.0.
- MangoHud FPS (median 6,861) counts presenter repaints, not game frames: use the in-game guest FPS (~25 at the spot; user saw nothing visually wrong). Log says
  `Frame rate: 60 FPS, 1 vblank(s) per frame`.

## Unit 0b (2026-11-15): dropped patches restored

Audit: for every old `patches/rexglue-sdk/0*.patch`, the share of its added lines found in the patched Himdo tree, then
each low scorer checked by hand (a low score can also mean "rewritten for Himdo"). Restored into `1105-himdo-port.patch`
(previous version kept at `out/1105-himdo-port.before-0b.patch`):

| Patch | What it does | Note |
|---|---|---|
| 0020 | WAIT_REG_MEM wakes on vblank instead of 1 ms sleeps | applied as is |
| 0023 | caps UI-only repaints to the guest frame / display refresh | was the MangoHud ~6,900 FPS; `patch` had wrongly reported it applied |
| 0024 + 0079 | known-register table lookup; side-effect-free register ranges | Himdo already batches type-0 runs itself, so 0024's packet hunk is dropped |
| 0025 | `clear_memory_page_state` off (stops re-uploading every buffer each frame), `primitive_processor_cache_min_indices` 4096, a cache invalidation bug fix, reused merge vector | `execute_unclipped_draw_vs_on_cpu` is already on in Himdo |
| 0046 | Vulkan resolve deferred writeback hook | now driven by the 0056 size limit |
| 0056 + 0058 | `readback_resolve_max_bytes` (config sets 256 KB) | kept Himdo's `readback_resolve_force_addresses` working; D3D12 got the size check too (0057), untested |
| 0066 | file probe misses logged at debug level | the ~6,000 "device not found" errors were just this |
| 0078 | lock-free shared-memory validity check + `gpu_invalidation_expand_pages` (16) | ≈ Crackdown's own version of Fable fix B |
| 0080 | `gpu_draw_state_memo` | applied as is |

Present already (low score only from rewriting): 0044, 0059. **Not ported (Windows/D3D12-only, can't build or test
here):** 0035, 0045 (D3D12 deferred writeback), 0082, 0099, 0101. Script gap: `tools/codegen-linux.sh` doesn't re-apply a
changed 1105 in an existing `out/rexglue-codegen/source` (it only checks marker strings); fine while the codegen parts
are unchanged, as here.

## Baseline (2026-11-15, `out/perf-capture/20261115-211202/`, unit 0b build)

**Guest ~33 FPS (was ~25 before 0b).** MangoHud median 34.8 / p10 31.4 / min 21.7 FPS, frame time median 28.7 ms
(MangoHud now counts game frames because 0023 stopped the extra repaints; main `crackdown` thread 0.35 → 0.03 cores).

- GPU Commands still the limiter: 0.99 cores, R 100%, 52% of all samples. Inside it (incl., % of all samples):
  `IssueDraw` 33%, `UpdateBindings` 9.2%, **`EndSubmission` (vkQueueSubmit + driver) 6.8%**, register writes ~8%,
  `RenderTargetCache::Update` 5%, `RequestTextures` 4%; NVIDIA driver 10% of samples on this thread.
- Readback `memcpy` gone (libc on GPU Commands 9.2% → 2.7%).
- SIGSEGV 2,480/s (~71/frame; more than before, as 0078 drops smaller page groups and FPS is higher), still cheap:
  `ExceptionCallback` 1.1%, `/proc/self/maps` `sscanf` 0.18%, shared-memory requests/uploads ~5%.
- Audio Worker under 0.03 cores (not listed).

**Decision for unit 2:** port **C** (moves `EndSubmission`'s submit off the saturated thread; Fable −1.2 ms/frame) and
**E** (targets `UpdateBindings` / constant writes). Skip **A** (fault lookup ~0.2%), **B** (0078 already limits the
invalidation group; faults cheap), **D** (Audio Worker isn't spinning).

## Unit 2 (2026-11-16): C and E ported into 1105

Previous patch kept at `out/1105-himdo-port.before-unit2.patch`. Only the four Vulkan files below changed.

| Change | Cvar (default) | Fable source | Notes |
|---|---|---|---|
| C. Async submit: a "GPU Submit" thread replays the recorded commands and calls `vkQueueSubmit`; GPU Commands only does the bookkeeping. Fence waits wait for the worker first; swaps wait until the frame is submitted. | `--vulkan_async_submit` (false) | `ca59f4e` | Dropped Fable's RenderDoc-capture exclusion (Himdo has no RenderDoc capture) and `gpu_shared_memory_stats` |
| E. Skip constant-buffer / texture / vertex-residency invalidation for shader constant writes (float, fetch, bool/loop) that change nothing; narrow range writes to the changed registers | `--gpu_skip_unchanged_constant_writes` (false) | `a0c7269` (skip part only) | Not ported: `gpu_constant_write_stats`, `gpu_timing_stats`, PGO dump hook |
| Cached `VulkanDevice*` (no virtual `provider()` call per use); `DeferredCommandBuffer` keeps its storage and only grows, `WriteCommand` inlined | none (no behaviour change) | `9fda9b4` | always on |

Files: `include/rex/graphics/vulkan/command_processor.h`, `include/rex/graphics/vulkan/deferred_command_buffer.h`,
`src/graphics/vulkan/command_processor.cpp`, `src/graphics/vulkan/deferred_command_buffer.cpp`.

**Unit 3/4 launch:** `tools/profile-linux.sh --vulkan_async_submit=true` (unit 3), then add
`--gpu_skip_unchanged_constant_writes=true` (unit 4). Same save, spot, camera angle and procedure as the baseline.
Note the always-on `9fda9b4` changes mean "flags off" is no longer byte-identical to the baseline build; if unit 3 is
unclear, a flags-off boot re-measures the baseline.

## Results (fill in)

| Date | Build / flags | Spot | FPS (median / p10 / guest) | Notes |
|---|---|---|---|---|
| 2026-11-15 | Himdo (unit 0 build), no flags | heavy scene | MangoHud invalid / guest ~25 | GPU Commands-bound; 3 patches + VFS regressed — not a valid baseline |
| 2026-11-15 | Himdo + 0b restored patches, no flags | heavy scene | 34.8 / 31.4 / ~33 | **baseline**; GPU Commands-bound |
| 2026-11-16 | unit 2 build, `--vulkan_async_submit=true` | heavy scene | 35.4 / 32.8 / ~35 | `20261116-103351`; frame time p90 31.8 → 30.5 ms; GPU Commands 0.99 → 0.92 cores (R 93%), GPU Submit 0.14 |
| 2026-11-16 | + `--gpu_skip_unchanged_constant_writes=true` | heavy scene | 36.2 / 35.1 / ~35 | `20261116-103713`; frame time p90 28.5 ms, min 21.7 → 28.9; GPU Commands still 0.92 |

**Units 3–4 verdict:** both stable, keep both. Median gain is small (+1.4 FPS) but the slow frames improved a lot
(p10 31.4 → 35.1, p90 frame time 31.8 → 28.5 ms), i.e. smoother. GPU Commands is still the limiter but no longer
100% busy: it now sleeps ~7%, partly waiting on GPU Submit (the swap waits for the frame to be submitted; seen in
`sched-wakeups.txt`). Make both defaults in unit 7.

## Next session prompt

```
Crackdown perf port: read docs/perf-port-from-fable2.md (status table, unit 7). vulkan_async_submit and
gpu_skip_unchanged_constant_writes are now on in config/crackdown.toml. I've done a longer normal play session on the
current build; here's what I saw: <notes>. Record it, tick unit 7, and if anything regressed, find out which of the
two flags causes it (launch with --<flag>=false). Don't commit without asking. Explain simply (I'm a Java dev).
```
