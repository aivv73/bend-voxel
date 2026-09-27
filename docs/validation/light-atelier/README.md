# Light Atelier validation

Validated on 2026-09-27 using the local Vulkan/X11 desktop and Blender 5.2.2 LTS.

## Scene

The default world is a 44 × 34 meter courtyard containing a floor, backdrop, slatted canopy, and three Blender-voxelized sculptures. The opening camera is at `(9, 11, 25)` meters, with yaw `-2.8084` and pitch `-0.30` radians.

| Quantity | Initial value |
| --- | ---: |
| Occupied 10 cm cells | 803,970 |
| Anchored bodies | 6 |
| Sparse cuboids | 2,034 |
| Full-resolution surface rectangles | 10,341 |

These counts come from the compiled Bend world. The HUD's body counter reports detached fragments, so it starts at zero.

## Checks

The following commands passed:

```sh
make export-atelier-assets
make build
make test
make test-blender
```

The tests verify disjoint and connected exhibit geometry, protected anchors, the empty center and occupied rim of Oculus, reset behavior, camera aiming, plaster material handling in full meshes and LOD proxies, and mesh voxelization. Suzanne explicitly enables removal of isolated sample cells; the final export discarded one such cell.

## Visual inspection

- [Day, 1280 × 720](day.png): curved sculpture silhouettes and voxel steps are visible immediately. The canopy casts parallel stripes, Oculus casts an open elliptical shadow, and Twist casts a separate curved silhouette. Pale walls are free of the earlier diagonal self-shadow stripes.
- [Night, 1280 × 720](night.png): holding L reduces the sun contribution and exposes the cool ambient and warm camera work light. The work light does not cast shadows.
- [Default resolution, 640 × 360](default-640.png): all three exhibits, the cast shadows, and the controls remain readable.
- [Blender source preview](blender.png): the editable meshes rendered directly from `assets/light_atelier.blend`, before engine voxelization. Preview scenery and labels are excluded from export.

## Interactive edit and reset

A pointer cut on the right rim of Oculus removed 15 voxels, reducing the world to 803,955 cells. The [edited view](after-cut.png) has 49 changed pixels in the scene region compared with the day capture. Reset restored all 803,970 cells; the [reset view](reset.png) matches the pre-cut scene exactly in rows 150–614, excluding the HUD.

The [runtime trace](capture.log) records three shadow-map refreshes:

```text
vulkan shadow refresh bodies 6 rebuilt 6
vulkan shadow refresh bodies 6 rebuilt 1
vulkan shadow refresh bodies 6 rebuilt 1
```

These correspond to initial upload, the edit, and reset. The intervening day/night comparison and pointer motion did not rebuild the shadow map. This is a visual and behavior check, not a performance benchmark.

## Benchmark run

The remade default benchmark ran on the same Ryzen 5 1600 / GTX 1660 desktop with Bend 2.0.31 and Vulkan immediate presentation. Each case used 30 warm-up and 180 measured frames at 640 × 360. This is one run per case on a working tree with uncommitted benchmark changes; the [report](benchmark-report.json) records the source hashes and raw timing distributions. The numbers describe this machine and workload, not GPU-only time or a stable speedup ratio.

```sh
make build
python3 scripts/benchmark_stress.py --output build/stress
```

| Case | Throughput (FPS) | Frame p95 (ms) | Accepted cuts | Shadow refreshes |
| --- | ---: | ---: | ---: | ---: |
| `atelier` | 1863.2 | 0.629 | 0 | 1 |
| `atelier-night` | 1795.5 | 0.693 | 0 | 1 |
| `atelier-camera` | 1742.7 | 0.688 | 0 | 1 |
| `atelier-aim` | 1626.1 | 0.704 | 0 | 1 |
| `atelier-carve` | 809.9 | 1.013 | 6 | 7 |

All five cases passed inventory, timing, view, cache, and lighting checks. The aim case previewed removable cells in 170 of 180 measured frames. The six cuts removed 151 cells in total and rebuilt six meshes; the shadow map refreshed once for each cut. Raw samples and stderr logs are archived beside the report as `benchmark-<case>.csv.gz` and `benchmark-<case>.stderr`.

## Face-builder profile

Before local surface rebuilding, `make benchmark-faces` replayed the six cuts headlessly with CPU Bend 2.0.31. Each row timed a full surface build, then counted the same work in a separate diagnostic pass. The diagnostic produced an ordered face list identical to the production builder for every cut. This historical [full-rebuild report](faces-report.json) and [raw samples](faces.csv) include source hashes and all counters.

| Exhibit | Cut | Surface (ms) | Cuboids | Tree nodes visited | Face checks | Face clips | Output faces |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Suzanne | 1 | 26.918 | 783 | 1,674,340 | 26,936 | 4,036 | 3,795 |
| Oculus | 1 | 8.529 | 675 | 585,718 | 22,394 | 3,277 | 3,430 |
| Twist | 1 | 10.604 | 684 | 684,542 | 22,871 | 3,991 | 3,103 |
| Suzanne | 2 | 27.460 | 816 | 1,746,662 | 28,751 | 4,335 | 3,855 |
| Oculus | 2 | 8.939 | 685 | 599,386 | 22,950 | 3,378 | 3,440 |
| Twist | 2 | 11.521 | 713 | 729,626 | 24,401 | 4,219 | 3,140 |

The two Suzanne builds each visited about 2.4–2.9 times as many tree nodes as an Oculus or Twist build, while their cuboid counts were only moderately larger. This motivated rebuilding surfaces only near the cut.

The new builder retains cached face rectangles outside an integer-aligned cut window, assigns them to surviving components, and generates faces only for cuboids intersecting the window. `make benchmark-faces` now measures this production path and checks complete surface coverage, sides, and materials against a full diagnostic rebuild on every cut. Window clipping can change rectangle counts without changing geometry. The [local-rebuild report](faces-local-report.json) and [raw samples](faces-local.csv) record the run and source hashes.

| Exhibit | Cut | Full surface (ms) | Local surface (ms) | Full rectangles | Local rectangles |
| --- | ---: | ---: | ---: | ---: | ---: |
| Suzanne | 1 | 26.918 | 17.518 | 3,795 | 3,793 |
| Oculus | 1 | 8.529 | 5.659 | 3,430 | 3,443 |
| Twist | 1 | 10.604 | 5.052 | 3,103 | 3,100 |
| Suzanne | 2 | 27.460 | 17.778 | 3,855 | 3,854 |
| Oculus | 2 | 8.939 | 4.488 | 3,440 | 3,450 |
| Twist | 2 | 11.521 | 5.295 | 3,140 | 3,139 |

Both profiles are single headless runs. The counted full pass runs after the timed edit, so its audit time is excluded from the local surface stage.

The standard windowed `atelier-carve` workload also passed with six edits and seven shadow refreshes. Its [local-rebuild report](benchmark-atelier-carve-local-report.json), [raw frames](benchmark-atelier-carve-local.csv.gz), and [stderr](benchmark-atelier-carve-local.stderr) can be compared with the earlier windowed carve row above. Total surface time across the 180 measured frames was 95.752 ms before and 56.874 ms after; surface p99 was 27.374 ms before and 16.650 ms after. Frame p99 was 32.941 ms before and 22.224 ms after, while frame p95 rose from 1.013 ms to 1.327 ms. These are separate single runs, so the frame figures show observed behavior rather than a stable speedup estimate.

These archived timing runs predate the cached Bend body vertices now on `main`. On the combined code, the surface stage also constructs vertices, so the historical timings do not measure its current speedup. Re-run `make benchmark-faces` for current timings.
