# Stage probe and deterministic snapshots

The probe follows the official [Slash Boss timing and image-tree dump pattern](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/demos/app_slash_boss_3d/main.bend): complete an operation through `IO.pure`, then read the clock. It uses the voxel demo's existing workload and presentation path. This is diagnostic instrumentation, not a change to the acceptance thresholds.

## Timings

Run `make benchmark`. Bend 2.0.25 and the CUDA backend are required. The native window uses the existing 640 × 360 viewport. Each of three runs records five seconds of warm-up and sixty seconds of measured work.

Every duration is a wall-clock microsecond interval. CUDA rendering includes the invocation's host/device work and synchronization; it is not a kernel-only GPU timer. Presentation ends after X11 `XSync`, which confirms server processing rather than physical display scanout.

The raw CSV contains these rows (without a header):

```text
frame,elapsed_us,frame_us,solids,bodies
stage,elapsed_us,carve_us,rebuild_us,update_other_us,scene_us,render_us,dispose_us,present_us,overhead_us
cut,scheduled_absolute_us,latency_us,status,kind
attempt,scheduled_absolute_us,latency_us,status,kind
edit,frame_elapsed_us,scheduled_absolute_us,kind,status,carve_us,rebuild_us
```

`frame_us` remains the entire interval between completed presentations. The first frame starts at the benchmark epoch. Cut/attempt latency still starts at the scheduled command time and ends at completed presentation, including queueing. Absolute timestamps are wrapping U32 microseconds; durations use modular subtraction in Bend. No slow samples are removed. The final frame crossing the 65-second boundary is retained.

The eight exclusive stage components add up exactly to each frame's end-to-end duration:

| Stage | Boundary |
| --- | --- |
| Carving | Clone the candidate voxel array and remove eligible cells. |
| Connectivity/meshing | Six-face connectivity, body assignment, face rebuilding, commit or rollback, and transaction cleanup. A no-op transaction still finalizes here. |
| Other update | Physics, command lookup/validation, reset, camera update, and surrounding timing/control work. |
| Scene preparation | Picking, body transforms, clipping, render-cell construction, brush preview and HUD preparation. |
| CUDA rendering | `V.frame`, including its completed CUDA invocation and image result. |
| Cell disposal | Dispose of the render cells returned with the image. |
| Presentation | Image-tree expansion, pacing, event processing, X11 image/HUD submission and `XSync`. |
| Overhead | The remaining frame interval, including previous-frame CSV output and loop/control overhead. |

Carving and rebuilding use the same `W.carve.prepare` / `W.carve.finish` transaction as interactive carving. Protected and empty-target commands skip that transaction and record zero for both stages. Multiple edits within one frame produce individual `edit` rows and summed frame-stage durations.

The report validates frame/stage joins, uninterrupted end-to-end intervals, stage sums, per-edit sums, and edit/latency correspondence. `instrumentation_pass`, `workload_pass` and `performance_pass` are separate. Statistics exclude warm-up frames ending before five seconds; the raw CSV retains them. `active_edits` reports accepted-edit timings separately, avoiding zero-heavy frame distributions hiding expensive edits. Stage percentiles are not additive.

Instrumentation and CSV output have a cost. That cost remains in end-to-end measurements; do not subtract it to claim an acceptance pass. These instrumented results should not be treated as an uninstrumented compiler comparison.

## Snapshots

```sh
make snapshots
# After building, choose specific ticks (0–1199):
python3 scripts/snapshot.py --ticks 0 408 540 --output build/snapshots
```

`src/snapshot.bend` runs the same replay commands and world/scene code at a fixed 60 Hz, starting at the first replay cycle's reset. Tick 0 is the initial scene; tick 408 is the moving-body cut; tick 540 is the landed-body cut. Defaults also cover the partial cut, support severing and orbit. This deterministic simulation clock differs from the benchmark's real elapsed clock.

Snapshots run in a separate process without opening a window; no snapshot file output occurs in the timed benchmark. CUDA is forced on by default; `--gpu off` supports an explicitly labeled CPU comparison. No display server is needed for snapshots.

Each tick writes:

- A 640 × 360 RGB PNG, cropped from Bend3D's 2048-square image root.
- A `.tree.gz` preserving the complete dump and state/HUD text.
- JSON containing voxel/body state, transforms/velocities, backend, compiler version, source hashes and pixel SHA-256.
- A stderr file for runtime diagnostics.

The tree format is the official probe's preorder protocol: `Q` followed by top-left, top-right, bottom-left and bottom-right children; a decimal RGB value fills a leaf square. The decoder rejects malformed, truncated, over-deep and surplus data. PNG output uses Python's standard library.

Native X11 HUD text is recorded in JSON and the dump, but is not painted into the snapshot PNG. HUD frame/cut times are zero on the fixed-clock path. Compare pixel hashes and state at the same tick/backend to check repeatability; cross-backend or cross-driver floating-point equivalence is not assumed.

## Controlled CPU/CUDA comparison

```sh
make compare-backends
# Customize the sweep and preserve an earlier experiment:
make compare-backends COMPARE_ARGS='--threads 1 2 4 6 12 --rounds 2 --output build/comparison-next'
```

The runner builds each executable once and uses those same binaries with explicit `--gpu off/on` and `--threads N`. Default counts cover one worker, intermediate counts, six physical cores and twelve logical CPUs on the validation machine. Choose counts appropriate to another host. It sanitizes inherited `VOXEL_*` overrides and records hardware, CPU affinity, display, compiler, source and binary hashes. The output directory must be empty to avoid overwriting evidence.

Before timing, all seven fixed-clock snapshots run at every backend/thread configuration, with `DISPLAY` unset. Decoded RGB hashes, HUD text, voxel/body counts and recorded body transforms/velocities must exactly match the first CPU configuration at the same tick. Dumps, PNGs and metadata are retained. A mismatch or failed snapshot prevents timing. This is bounded regression evidence, not proof of complete world-state equivalence; the snapshots do not serialize every voxel.

Each measured process uses the existing five-second warm-up and sixty-second native-window replay. Adjacent CPU/CUDA pairs use the same thread count. Round 1 traverses counts forward with CPU first; round 2 reverses counts and runs CUDA first. Further rounds alternate these orders; an even number balances first/last positions. Runs execute serially, after all builds and snapshot work. Keep other workloads idle and avoid interacting with the benchmark window. GPU telemetry before each run and host load afterward provide context but do not remove desktop, clock, thermal or scheduling noise. The script does not lock clocks or reserve the machine.

`report.json` is checkpointed after each probe and run. Raw CSV/stderr and individual percentiles remain available; the summary lists each run's frame/cut p95 and the median of frame-p95 values, without pooling frames across runs. `diagnostic_pass` requires matching snapshots, valid workloads/instrumentation and unchanged source/binary hashes. Performance misses remain visible but do not fail this diagnostic command. Timeout/failed runs remain in the report and invalidate the diagnostic result. The legacy stage key `cuda_rendering` refers to CPU rendering in CPU runs.

The event schedule, viewport and code are shared, but the native benchmark advances physics with real elapsed time: backends do not render identical frame-by-frame states. Fixed-clock checks are a separate correctness control. Interpret windowed results as end-to-end behavior under the same scheduled workload, not isolated renderer or compiler speedup. Two rounds are an initial ordering-controlled diagnostic, not a confidence interval. Use more balanced rounds to establish small differences. CPU results and a tuned CUDA thread count do not replace the agreed three-run forced-CUDA acceptance test.
