# Light Atelier and scale benchmark

```sh
make benchmark-stress
```

The default suite runs **five Light Atelier workloads**, with 30 warm-up frames and 180 measured frames each. It writes raw CSV samples, stderr logs, and `build/stress/report.json`. A smaller run:

```sh
make build
python3 scripts/benchmark_stress.py --cases atelier-camera atelier-aim atelier-carve --warmup 10 --frames 60 --output build/stress-pilot
```

To measure at 1920 × 1080, run `make build` and then `python3 scripts/benchmark_stress.py --resolution 1920x1080 --output build/stress-1920x1080`. The default is 640 × 360. Camera paths and aim pointer coordinates scale with the selected resolution. Higher resolutions can keep distant district tiles on full meshes where the 640 × 360 view selects LOD proxies. Compare throughput between resolutions as separate workloads.

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

The [Light Atelier face-profile record](validation/light-atelier/README.md#face-builder-profile) contains the six measured cuts. Use the windowed benchmark above for edit-to-present latency; the headless run separates edit stages and full face-builder work counts.

## Optional district scale workloads

The earlier demolition district cases remain selectable by name. For example:

```sh
python3 scripts/benchmark_stress.py --cases district district-4 district-16 district-camera district-bridge district-fragments --output build/district-stress
```

Each district occupies a 64 × 64 × 32 meter content envelope at 10 cm resolution. Its 2,443,284 occupied cells are compressed into 3,434 solid regions, forming 154 anchored assemblies and 20,374 exposed surface rectangles. Districts are placed 64 meters apart on a square grid. Every district contributes independently editable material and bodies.

| Cases | Districts | Occupied cells | Workload |
| --- | ---: | ---: | --- |
| `district`, `district-4`, `district-16` | 1 / 4 / 16 | 2.44 / 9.77 / 39.09 million | Fixed overview, aim disabled |
| `district-camera`, `district-camera-4`, `district-camera-16` | 1 / 4 / 16 | Same real scale | Orbit sized to the whole district grid, aim disabled |
| `district-aim`, `district-aim-16` | 1 / 16 | 2.44 / 39.09 million | Fixed camera; pointer sweeps the machinery racks |
| `district-carve` | 1 | 2.44 million initially | Cuts through shared floor/column region boundaries |
| `district-bridge` | 1 | 2.44 million initially | Sever the two bridge fuses and let the detached bridge fall |
| `district-fragments`, `district-fragments-4` | 1 / 4 | 2.44 / 9.77 million initially | Detach and follow 128 / 512 simultaneously falling bodies |

The former small dense/comb scenes and overlapping render copies are retired. Their archived results characterize the earlier renderer; they are not direct throughput baselines for these larger worlds.

## Repeatable workloads

Physics advances by exactly 1/60 second per benchmark frame. Camera paths, pointer positions, cut scheduling, and support coordinates depend on frame indices. Interactive motion still uses elapsed time.

- **Atelier camera:** 0.5° per frame around the sculptures. The day, night, and carve views keep the opening camera fixed.
- **Atelier aim:** five logical pixels per frame across a 480-pixel span. The fixed opening camera previews removable geometry on the exhibits.
- **Atelier carve:** one cut at each requested interval, beginning at the first measured frame, for up to six cuts distributed across the three sculptures.
- **District camera:** 0.5° per frame, with radius and center determined by district count.
- **District aim:** five pixels per frame across a 440-pixel span, viewing the rack field. Picking uses body bounds and the sparse spatial trees.
- **District carve:** one cut at each requested interval, beginning at the first measured frame. Up to 75 distinct floor/column junctions are cut. These edits cross the regions' shared faces.
- **District bridge:** two cuts at the requested interval. The first preserves a path to an anchor; the second detaches exactly one bridge. Total removed material is 56 cells.
- **District fragments:** eight support cuts per district per frame for the first 16 measured frames. Each is a normal, timed sphere edit. Motion continues while the camera follows the most recently detached body, including its vertical translation. The burst produces 128 or 512 bodies before the first ones land.

`--edit-every` controls carve/bridge cases; zero disables their edits. Fragment bursts always use their fixed schedule. Use `--cases`, `--warmup`, `--frames`, `--body-budget`, `--timeout`, `--resolution`, and `--output` to select a run. The default body budget is 2,048. Moving-view cases require at least four measured frames; 17 or more are needed to observe the full simultaneous district fragment population.

## Measurements and validation

The runner requests Vulkan **immediate** presentation, falling back to **mailbox**, and fails if neither is available. Interactive presentation is unchanged. Frame throughput includes Bend simulation, picking, editing, native transport, Vulkan work, and X11 synchronization. CPU fence/acquisition/presentation waits can include GPU or compositor backpressure; these are wall-clock intervals, not GPU timestamps.

Reports include frame percentiles, throughput, initialization, voxel and region counts, body counts, simultaneous moving bodies, view samples, accepted edit latency, each edit phase, and native render stages. Surface generation includes Bend's local-space triangle construction for newly classified bodies; unchanged bodies retain their cached faces and vertices. Initial body construction uses Bend CPU parallel calls. Cache telemetry records rebuilt meshes, visible bodies, arena vertices, uploaded bytes, proxy draws, proxied bodies, proxy rebuilds, and actual draw calls. The native arena retains a slot for each body mesh and eligible render tile proxy; body transforms and camera changes affect draw commands. Overlays still upload each frame.

Validation checks:

- Every expected frame, timing stage, edit batch, and latency sample is present and accounted for.
- Inventory matches the selected Light Atelier or real district scene; cell counts never increase during destruction.
- Reported anchors, fragments, moving bodies, and live meshes agree.
- Camera/aim/follow workloads actually move or hit removable material as specified.
- Frames without edits rebuild zero body meshes after the initial frame, including while fragments fall.
- Frames without edits rebuild zero render proxies after the initial frame; the default-resolution 16-district overview and camera workloads must select proxies.
- Edits rebuild only affected bodies, and bridge/fragment workloads produce the required components.
- Atelier lighting mode matches the requested workload; static frames reuse the shadow map, while edits refresh it.
- The body budget is respected and cuts are accepted.

There is no FPS acceptance threshold. The purpose is to reveal rendering, editing, and scaling costs. The [Light Atelier benchmark record](validation/light-atelier/README.md#benchmark-run) includes a full five-case run and raw samples. The [district validation report](validation/demolition-district/report.json) records the earlier 12-case run on the development machine.

The [render LOD validation](validation/render-lod-2026-09-25/README.md) compares the world-only mesh cache with the distant render proxies on the 16-district overview, camera, and aim workloads, and records a complete 12-workload run with raw samples.

## Historical measurements

The previous fixed-duration replay is archived in [Vulkan validation](vulkan-renderer.md). The following comparison used the former comb scene and overlapping render copies, before sparse districts were implemented.

## Camera and aim cache comparison (2026-09-24)

The new view workloads were run against the [#20 scene cache](https://github.com/aivv73/bend-voxel/pull/20) and the [world-only cache from #21](https://github.com/aivv73/bend-voxel/pull/21) on the Ryzen 5 1600 / GTX 1660 desktop. The workload, parser, and bridge source hashes match between variants; only `src/vulkan/native.cpp` differs. Each variant ran twice with 30 warm-up and 180 measured frames per case, no edits, and immediate presentation. The order was #20, world-only, world-only, #20. Throughput below pools each variant's 360 measured frames.

| Workload | #20 cache | World-only cache | Ratio |
| --- | ---: | ---: | ---: |
| Camera motion, 1× | 596.3 FPS | 1428.3 FPS | 2.40× |
| Camera motion, 16× | 65.3 FPS | 253.3 FPS | 3.88× |
| Aim sweep, 1× | 223.4 FPS | 267.9 FPS | 1.20× |
| Aim sweep, 16× | 53.8 FPS | 229.9 FPS | 4.27× |

All runs passed the workload checks. The camera cases recorded 180 distinct camera positions per run with aim disabled. The aim cases kept one camera position and previewed removable targets in 174 of 180 measured frames, across 46 distinct hit points. At 16× copies, median native geometry generation fell from 12.375 to 0.358 ms for camera motion and from 12.589 to 0.482 ms for aim sweep. The smaller 1× aim gain reflects roughly 2.7 ms of scene preparation, including picking, in both variants. These are end-to-end CPU wall-clock measurements on one machine, not GPU execution times.

[Comparison summary](validation/cache-view-2026-09-24/summary.json) and per-run reports ([#20 run 1](validation/cache-view-2026-09-24/20-run-1-report.json), [#20 run 2](validation/cache-view-2026-09-24/20-run-2-report.json), [world-only run 1](validation/cache-view-2026-09-24/world-run-1-report.json), [world-only run 2](validation/cache-view-2026-09-24/world-run-2-report.json)) include source hashes and timings. Compressed raw CSV files for each case and run are stored alongside them.
