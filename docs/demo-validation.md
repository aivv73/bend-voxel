# First demo validation

## Scope

The demo implements the scene and interaction decisions from GitHub issues #2–#6 in `aivv73/bend-voxel`. Planning completion is separate from executable acceptance.

This is a Linux/X11 and CUDA implementation, pinned to Bend 2.0.26 and upstream Bend3D commit `a49524265bdfa5753a4bf38e25f0574a705dd868`. The native adapter draws HUD text after the CUDA-rendered image. The sphere preview uses three twelve-segment rings, with individual affected voxel cells highlighted in yellow. Gameplay, ownership, meshing, picking, clipping and preview construction are Bend code.

The fixed lattice is 40 × 24 × 20 cells with 10 cm spacing. The 4 × 2 × 0.4 m slab starts at y = 2 m. Two 0.6 m square supports extend from the floor to the slab. Their 72 base cells are protected.

Detached bodies have only vertical translation and velocity. Floor contact clamps the lowest occupied cell to y = 0. Pieces can overlap other pieces and the remaining structure. Those are deliberate first-demo physics limits.

## Correctness checks

`make test` builds and executes native Bend tests. Failure exits nonzero. Coverage includes:

- Initial population, partial cuts, remaining support and final detachment.
- Protected anchors, floor contact, moving-body split velocity inheritance, and renewed falling when the bottom of a landed body is removed.
- Face connectivity, separation of edge contacts, and no merging across existing owners.
- A 64-body fixture, rejected over-cap split, removal freeing a slot, and a subsequent split exactly at the cap.
- Exposed surface area preserved by rectangle and row merging.
- Left-button edge triggering, right-look suppression, Escape/focus loss, refocusing and reset hit area.
- Movement speed, near-plane clipping and picking at the far end of a merged surface row.

These are executable checks, not a formal proof of the engine. Flood/rebuild loops and inherited renderer code use explicitly marked unsafe recursion where Bend's structural checker cannot establish termination.

## Performance protocol

`make benchmark` rebuilds before measurement and forces `--gpu on`. Each of three independent native-window runs lasts 65 seconds: 5 seconds warm-up, then 60 seconds measured. The measured workload repeats three twenty-second cycles containing reset, partial cut, severing both supports, a moving-body cut, a landed-body cut, protected/no-target attempts, and camera movement.

Frames include application work, CUDA rendering, image transfer, HUD drawing and X11 synchronization. Cut latency runs from the scheduled action time to completed presentation, including queue delay. X11 synchronization confirms server processing; it is not a hardware scanout timestamp. Raw frame and accepted-cut samples are retained. Protected/no-target attempts are logged separately and are not included in accepted-cut latency percentiles. The replay verifies downward velocity for the moving-body cut and floor contact for the landed-body cut.

Each run must have frame p95 ≤ 33.3 ms, accepted-cut p95 ≤ 100 ms and maximum ≤ 250 ms, all 33 expected accepted cuts, and a complete measurement window. Overall performance acceptance requires all three runs. Correctness and native interaction inspection are separate gates.

The replay invokes the same world-edit operation at scripted world coordinates. It does not synthesize the mouse movements needed to acquire every target; picking and input are checked separately. The timed workload does not intentionally fill all 64 body slots; the cap is exercised by the correctness fixture.

## Compiler update to Bend 2.0.26 (2026-09-23)

The project build pin now matches the installed [Bend 2.0.26 release](https://github.com/bendlang/bend/releases/tag/v2.0.26). The vendored Bend3D and native window adapter needed no source changes. `make build` produced the CUDA module, and `make test` passed the world, input/render, probe and Python checks. Seven fixed-clock CUDA snapshots matched the archived 2.0.25 image hashes, state, body transforms and HUD text. Three CPU snapshots also matched the corresponding 2.0.26 CUDA images and state, covering the launcher's default backend. [Correctness output](validation/bend-2.0.26/correctness.txt), [snapshot comparison](validation/bend-2.0.26/snapshot-checks.txt).

A fresh three-run, forced-CUDA native-window benchmark completed the expected workload and passed instrumentation checks in every run. Performance acceptance remains open:

| Run | Frame p95 (ms) | Cut p95 (ms) | Cut maximum (ms) | Accepted cuts |
| --- | ---: | ---: | ---: | ---: |
| 1 | 46.206 | 151.050 | 171.794 | 33 |
| 2 | 45.385 | 151.075 | 164.163 | 33 |
| 3 | 46.062 | 159.565 | 162.035 | 33 |

Each run retained five seconds of warm-up and sixty seconds of measurement, plus all six expected protected/empty attempts. The frame and cut p95 targets failed in every run; maximum cut latency remained below 250 ms. These fresh runs validate the 2.0.26 build and workload. They are not an interleaved comparison that isolates a compiler performance change. [Report, source hashes and stage statistics](validation/bend-2.0.26/report.json); raw samples: [run 1](validation/bend-2.0.26/run-1.csv.gz), [run 2](validation/bend-2.0.26/run-2.csv.gz), [run 3](validation/bend-2.0.26/run-3.csv.gz).

## Surface-generation timing (2026-09-23)

The profiler now times connectivity and cached face generation as separate edit stages. A fresh three-run forced-CUDA benchmark used Bend 2.0.25 on the GTX 1660 at 640 × 360. Each run passed instrumentation and workload checks, with 33 accepted cuts and six protected/empty attempts. The performance gate still failed: frame p95 exceeded 33.3 ms and cut p95 exceeded 100 ms in every run.

| Run | Frame p95 (ms) | Cut p95 (ms) | Connectivity p50 / p95 (ms) | Surface generation p50 / p95 (ms) |
| --- | ---: | ---: | ---: | ---: |
| 1 | 44.646 | 150.199 | 15.625 / 16.925 | 19.036 / 19.701 |
| 2 | 45.262 | 153.677 | 15.199 / 18.306 | 18.888 / 21.244 |
| 3 | 46.303 | 150.961 | 15.832 / 18.338 | 19.714 / 22.358 |

The connectivity and surface percentiles include accepted edits only; they are separate wall-clock intervals and their percentiles should not be added. Surface generation is slightly costlier than connectivity in this workload. These runs measure a refactored two-phase rebuild, so direct performance attribution against earlier combined-stage reports is not established. The source tree was uncommitted during measurement; the report records source hashes. [Full report](validation/surface-generation-2026-09-23/report.json) and complete raw samples: [run 1](validation/surface-generation-2026-09-23/run-1.csv.gz), [run 2](validation/surface-generation-2026-09-23/run-2.csv.gz), [run 3](validation/surface-generation-2026-09-23/run-3.csv.gz).

## Compiler upgrade to Bend 2.0.25

On 2026-09-22, the installed compiler and project build pin were updated from 2.0.16 to [2.0.25](https://github.com/bendlang/bend/releases/tag/v2.0.25). The official installer verified the release archive checksum. The previous compiler, Base and guides were backed up locally under `build/toolchain-backup/bend-2.0.16.tar.gz`.

Integration changes:

- Build and benchmark scripts query `bend version`; `--version` is no longer accepted.
- The custom X11 presenter passes `CID_CON` to `io_seal`, matching 2.0.25's window effect API. The old `IO_HOTS` macro is no longer defined.
- Bend3D remains at the same upstream source revision. Gameplay and renderer algorithms were not changed for this upgrade.

The CUDA build and both native correctness suites pass. A finite native-window run completed with `--gpu on`. The compiler now reports unsafe/foreign dependencies differently; those diagnostics do not mean the whole engine is formally verified. Earlier 2.0.16 measurements and research checks are retained with their original version labels.

### Bend 2.0.25 performance results

| Run | Frame p95 (ms) | Cut p95 (ms) | Cut maximum (ms) | Accepted cuts | Performance |
| --- | ---: | ---: | ---: | ---: | --- |
| 1 | 45.829 | 170.322 | 190.079 | 33 | Fail |
| 2 | 44.407 | 157.459 | 179.814 | 33 | Fail |
| 3 | 43.672 | 153.217 | 156.298 | 33 | Fail |

All three runs completed the expected workload, including moving/landed target checks and protected/no-target attempts. Performance acceptance remains open: upgrading the compiler alone did not meet the frame-p95 and cut-p95 limits. These are fresh runs under the same protocol, not a controlled interleaved comparison that isolates compiler speedup.

[Upgrade report and source hashes](validation/bend-2.0.25/report.json), [30 passing correctness checks](validation/bend-2.0.25/correctness.txt), and raw samples: [run 1](validation/bend-2.0.25/run-1.csv.gz), [run 2](validation/bend-2.0.25/run-2.csv.gz), [run 3](validation/bend-2.0.25/run-3.csv.gz).

## Original Bend 2.0.16 results

Measured on 2026-09-22 on the target GTX 1660 / Ryzen 5 1600 Linux desktop. **Performance acceptance remains open.** All three workload runs completed, but frame p95 and cut p95 exceeded the agreed limits.

| Run | Frame p95 (ms) | Cut p95 (ms) | Cut maximum (ms) | Accepted cuts | Performance |
| --- | ---: | ---: | ---: | ---: | --- |
| 1 | 49.845 | 189.078 | 190.803 | 33 | Fail |
| 2 | 53.277 | 179.945 | 185.977 | 33 | Fail |
| 3 | 46.963 | 170.521 | 192.726 | 33 | Fail |

Every run completed all 33 accepted cuts plus three protected and three no-target attempts. The moving/landed target assertions passed. Maximum cut latency stayed below 250 ms. The 33.3 ms frame-p95 and 100 ms cut-p95 requirements did not pass; the benchmark correctly exited with status 1.

Both native correctness suites passed. Native-window inspection exercised carving, right-button suppression, camera movement and reset; the reset screenshot is included in the README. Automated input-state tests cover held-button repetition and focus release. A broader human playtest is still useful and is not implied by these checks.

The [machine-readable report](validation/first-demo/report.json) records environment details and SHA-256 hashes of the measured source files. Raw samples are preserved as [run 1](validation/first-demo/run-1.csv.gz), [run 2](validation/first-demo/run-2.csv.gz), and [run 3](validation/first-demo/run-3.csv.gz). [Correctness output](validation/first-demo/correctness.txt) is retained alongside them. The source tree was uncommitted during measurement; the Git revision alone does not identify the implementation, so use the recorded file hashes.

The earlier diagnostic reports under `build/*-pilot` are not acceptance evidence. Surface caching, row/rectangle merging, local preview subdivision, parallel cell disposal and native HUD text are already applied. Further work should profile remaining CPU preparation, CUDA rasterization and presentation costs using this workload; keep the scene, resolution, body semantics and acceptance limits unchanged.


## Stage probe and snapshot validation

For the subsequent Bend 2.0.25 CPU/CUDA diagnostic, see [controlled comparisons and thread-count sweep](research/controlled-cpu-cuda.md): 70 matching snapshot probes, 20 valid interleaved runs at five worker counts, and unchanged source/binary hashes. CUDA performance acceptance remains open; CPU numerical passes do not substitute for the forced-CUDA protocol.

The [profiling guide](profiling.md) documents the instrumentation modeled on the official Slash Boss probe. The [stage report](validation/stage-probe/report.json) retains the original acceptance gates and separates instrumentation, workload and performance results. Complete raw samples, including warm-up and every slow frame, are preserved as [run 1](validation/stage-probe/run-1.csv.gz), [run 2](validation/stage-probe/run-2.csv.gz), and [run 3](validation/stage-probe/run-3.csv.gz).

| Run | Raw frames (including warm-up) | Frame p95 | Cut p95 | Accounting / workload |
| --- | ---: | ---: | ---: | --- |
| 1 | 1,981 | 44.305 ms | 161.015 ms | Pass / pass |
| 2 | 1,923 | 43.769 ms | 157.242 ms | Pass / pass |
| 3 | 1,899 | 45.337 ms | 149.561 ms | Pass / pass |

All runs completed 33 accepted cuts and six expected protected/empty attempts. Every frame has matching stages that sum to its complete end-to-end duration; every edit matches its original latency sample. Performance acceptance still fails.

Across these runs, mean CUDA rendering was 15.1–16.5 ms per measured frame, cell disposal 7.2–7.3 ms, scene preparation 6.7–7.3 ms, and presentation 4.3–4.6 ms. Accepted edits averaged roughly 28 ms carving and 37 ms connectivity/meshing in run 1. These are wall-clock stage measurements, not kernel profiling. The instrumentation's own overhead remains in end-to-end samples. Snapshot compilation overlapped run 1's initial warm-up; no snapshot rendering ran concurrently with the measured workloads.


[Correctness output](validation/stage-probe/correctness.txt) records 35 Bend checks and seven Python parser/decoder tests passing. [Snapshot checks](validation/stage-probe/snapshot-checks.txt) cover seven expected world states, including the moving and landed cuts. Separate CUDA runs of ticks 0, 408 and 540 produced byte-identical PNGs, complete dumps and metadata with `DISPLAY` unset. Moving-body and orbit images were visually inspected. Archived examples: [initial](validation/stage-probe/snapshots/tick-0000.png), [moving cut](validation/stage-probe/snapshots/tick-0408.png), [landed cut](validation/stage-probe/snapshots/tick-0540.png), and [orbit](validation/stage-probe/snapshots/tick-1140.png). Their neighboring JSON and compressed tree files retain state, source hashes and raw output.
