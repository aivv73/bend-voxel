# Light Atelier benchmark

```sh
make benchmark-stress
```

The default suite runs **five Light Atelier workloads**, with 30 warm-up frames and 180 measured frames each. It writes raw CSV samples, stderr logs, and `build/stress/report.json`. A smaller run:

```sh
make build
python3 scripts/benchmark_stress.py --cases atelier-camera atelier-aim atelier-carve --warmup 10 --frames 60 --output build/stress-pilot
```

To measure at 1920 × 1080, run `make build` and then `python3 scripts/benchmark_stress.py --resolution 1920x1080 --output build/stress-1920x1080`. The default is 640 × 360. Camera paths and aim pointer coordinates scale with the selected resolution. Compare throughput between resolutions as separate workloads.

## Light Atelier workloads

The six-body courtyard starts with 803,970 occupied cells, 2,034 sparse cuboids, and 10,341 full-resolution surface rectangles. It contains the floor, backdrop, canopy, Suzanne, Oculus, and Twist. All five cases render the actual sunlit or night scene through Vulkan; no render copies are used.

| Case | Workload |
| --- | --- |
| `atelier` | Fixed opening camera in daylight, aim disabled |
| `atelier-night` | Same view with the night work light enabled |
| `atelier-camera` | Orbit the courtyard at 0.5° per frame, aim disabled |
| `atelier-aim` | Sweep the pointer across the exhibits at the fixed opening camera |
| `atelier-carve` | Six 20 cm sphere cuts across Suzanne, Oculus, and Twist, spaced by `--edit-every` frames |

The cuts use fixed world-space points on the three exhibit bodies. At the default 30-frame interval, all six occur during the 180 measured frames. The runner confirms that each cut was accepted, removed cells, rebuilt only affected meshes, and refreshed the sun shadow map. It also checks that day/night changes, camera motion, and aim sweeps do not refresh an unchanged shadow map. Lighting rows record the night flag and shadow refresh decision for every frame.

### Face-builder diagnostic

```sh
make benchmark-faces
```

This headless CPU run applies the same six cuts in the same order and writes `build/faces/raw.csv` and `build/faces/report.json`. For each rebuilt exhibit body it records ordinary carve, connectivity, surface, and finalize times. The surface stage includes Bend vertex construction from the rebuilt faces. A separate counted full face pass reports cuboids, six candidate faces per cuboid, tree nodes visited, cuboid leaves reached during face hiding, face-coverage checks, actual face subtractions, and output rectangles. The production edit reuses cached rectangles outside a cut window and generates only the surface inside it. The diagnostic checks that both outputs cover identical surfaces with the same sides and materials; their rectangle counts may differ. Its `audit_ms` is diagnostic overhead and is excluded from `surface_ms`.

Use the windowed benchmark above for edit-to-present latency; the headless run separates edit stages and full face-builder work counts.

## Repeatable workloads

Physics advances by exactly 1/60 second per benchmark frame. Camera paths, pointer positions, cut scheduling, and support coordinates depend on frame indices. Interactive motion still uses elapsed time.

- **Atelier camera:** 0.5° per frame around the sculptures. The day, night, and carve views keep the opening camera fixed.
- **Atelier aim:** five logical pixels per frame across a 480-pixel span. The fixed opening camera previews removable geometry on the exhibits.
- **Atelier carve:** one cut at each requested interval, beginning at the first measured frame, for up to six cuts distributed across the three sculptures.
`--edit-every` controls the carve case; zero disables edits. Use `--cases`, `--warmup`, `--frames`, `--body-budget`, `--timeout`, `--resolution`, and `--output` to select a run. The default body budget is 2,048. Camera and aim cases require at least four measured frames.

## Measurements and validation

The runner requests Vulkan **immediate** presentation, falling back to **mailbox**, and fails if neither is available. Interactive presentation is unchanged. Frame throughput includes Bend simulation, picking, editing, native transport, Vulkan work, and X11 synchronization. CPU fence/acquisition/presentation waits can include GPU or compositor backpressure; these are wall-clock intervals, not GPU timestamps.

Reports include frame percentiles, throughput, initialization, voxel and region counts, body counts, simultaneous moving bodies, view samples, accepted edit latency, each edit phase, and native render stages. Surface generation includes Bend's local-space triangle construction for newly classified bodies; unchanged bodies retain their cached faces and vertices. Initial body construction uses Bend CPU parallel calls. Cache telemetry records rebuilt meshes, visible bodies, arena vertices, uploaded bytes, proxy draws, proxied bodies, proxy rebuilds, and actual draw calls. The native arena retains a slot for each body mesh and eligible render tile proxy; body transforms and camera changes affect draw commands. Overlays still upload each frame.

Validation checks:

- Every expected frame, timing stage, edit batch, and latency sample is present and accounted for.
- Inventory matches Light Atelier; cell counts never increase during destruction.
- Reported anchors, fragments, moving bodies, and live meshes agree.
- Camera/aim/follow workloads actually move or hit removable material as specified.
- Frames without edits rebuild zero body meshes after the initial frame, including while fragments fall.
- Frames without edits rebuild zero render proxies after the initial frame.
- Edits rebuild only affected bodies.
- Atelier lighting mode matches the requested workload; static frames reuse the shadow map, while edits refresh it.
- The body budget is respected and cuts are accepted.

There is no FPS acceptance threshold. The purpose is to reveal rendering, editing, and scaling costs. Run the same cases on each revision when comparing changes, and keep generated reports under `build/`.
