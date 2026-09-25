# Render LOD stress validation (2026-09-25)

The baseline is commit `9ce55b7` with a clean tree. The LOD build uses the same Bend 2.0.27 compiler and benchmark workloads; its report contains source hashes for the modified renderer and scripts. Each case used 30 warm-up and 180 measured frames with immediate presentation on the development Ryzen 5 1600 / GTX 1660 desktop. These are single runs, so the FPS differences describe this measurement rather than a stable hardware ratio.

| Workload | Baseline FPS | LOD FPS | Mean draws, baseline → LOD | Mean bodies represented by proxies |
| --- | ---: | ---: | ---: | ---: |
| 16-district overview | 236.4 | 263.1 | 2,317 → 666 | 1,664 |
| 16-district camera motion | 235.3 | 264.2 | 2,286.5 → 711.5 | 1,587.6 |
| 16-district aim sweep | 731.0 | 1,027.4 | 61 → 61 | 0 |
| Four-district fragment burst | 346.0 | 363.2 | 124.7 → 124.7 | 0 |

All 12 workloads in the LOD run passed. No view-only frame after warm-up rebuilt a body or proxy mesh. The four-district fragment burst rebuilt 16 proxy tiles during edits and retained full-detail draws for moving bodies. The aim and fragment throughput changes also include the camera view-transform optimization; they are not effects of proxy draws. CPU frame timing includes Vulkan presentation and synchronization, not isolated GPU execution.

[Baseline report](baseline-report.json) and [LOD report](lod-report.json) contain stage timings, workloads, and source hashes. Compressed raw CSV samples for the four baseline and all 12 LOD workloads are in this directory.
