# Live Vulkan renderer

Vulkan is the renderer for the 640 × 360 demo. Gameplay remains in Bend: voxel ownership, cuts, connected components, cached face merging, falling bodies, camera input, and picking. The application loop in `src/main.bend` uses `vulkan.frame` to render each current world state.

## Run and measure

```sh
make run
make benchmark
```

The build requires Bend 2.0.27, Linux/X11 or XWayland, Vulkan 1.3 with Xlib surface support, Vulkan headers and loader, `glslc`, `g++`, and X11 development headers. `make run` uses Bend's CPU execution mode for gameplay; scene rasterization and presentation run in Vulkan. The benchmark opens a window and runs three independent 65-second replays: five seconds warm-up and sixty seconds measured. It retains each frame and edit sample under `build/benchmarks/` and checks the same 33 accepted cuts, six protected/empty attempts, 33.3 ms frame p95, 100 ms accepted-cut p95, and 250 ms cut maximum gates as the original demo. One diagnostic pass can be requested with `python3 scripts/benchmark.py --runs 1 --output build/vulkan-pilot` after `make build`.

## Frame path

1. Bend updates the world and computes the camera aim and HUD text.
2. The pinned native effect reads the current cached `Body` and merged `Face` values from Bend's heap. It passes a flat face list, camera, aim, and HUD to `libvoxel_vulkan.so`.
3. The native renderer expands visible rectangles into triangles and highlights affected voxel cells near the brush. Falling-body offsets are applied to current vertices. Three twelve-segment rings show the brush location.
4. Vulkan 1.3 dynamic rendering draws triangles with depth testing, brush lines, and screen-space bitmap text into the same Xlib swapchain image. The backend handles acquire, submission, presentation, and resize recreation. It uses a present wait semaphore per swapchain image, following [Khronos's swapchain reuse guidance](https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html).
5. The X11 adapter synchronizes the X server and sends key, mouse, focus, and close events back to Bend. Pointer positions are mapped to the demo's 640 × 360 logical space after resize.

The native effect returns the same Bend state it received. The effect depends on Bend 2.0.27's generated C layout; it checks the relevant constructor arities at runtime. Changes to Bend or the `State`, `World`, `Control`, `Aim`, `Body`, or `Face` definitions require reviewing that bridge.

## Validation

### Bend 2.0.27 update (2026-09-24)

The compiler and build pin were updated to [Bend 2.0.27](https://github.com/bendlang/bend/releases/tag/v2.0.27). `make build` and `make test` passed without source changes to the native bridge. A fresh three-run `make benchmark` replay exercised the Bend state traversal and Vulkan effect; every run passed instrumentation, workload, and performance checks, including 33 accepted cuts and six protected/empty attempts per run.

| Run | Frame p95 (ms) | Accepted-cut p95 (ms) | Cut maximum (ms) |
| --- | ---: | ---: | ---: |
| 1 | 7.785 | 49.167 | 50.665 |
| 2 | 8.062 | 50.693 | 51.260 |
| 3 | 8.160 | 49.846 | 50.517 |

The results establish that the updated binary completes the measured replay on the tested desktop; they are not a controlled compiler-speed comparison or a new pixel-parity check. [Report and source hashes](validation/bend-2.0.27-vulkan/report.json); raw samples: [run 1](validation/bend-2.0.27-vulkan/run-1.csv.gz), [run 2](validation/bend-2.0.27-vulkan/run-2.csv.gz), [run 3](validation/bend-2.0.27-vulkan/run-3.csv.gz).

`make test` checks world behavior, input and picking, timed edits, and benchmark sample accounting. Earlier renderer validation inspected a finite Vulkan window run, pointer cut, reset, and 800 × 450 resize on the local GTX 1660/XWayland desktop. The pointer cut removed 16 voxels and reset restored all 4,640. Earlier fixed-scene Vulkan and Bend3D image comparisons remain in the archived [prototype report](validation/vulkan-prototype/report.json).

Live [Bend3D](validation/vulkan-renderer/initial-bend.png) and [Vulkan](validation/vulkan-renderer/initial-vulkan.png) captures of the initial state use the same default camera. The captures were taken at different times and use different text drawing methods. They are a visual diagnostic, not a synchronized pixel parity gate. The Vulkan HUD was also checked in repeated captures without input and after an 800 × 450 resize.

The archived integration replay passed all workload, instrumentation, and performance gates. Each run had 33 accepted cuts, six expected protected/empty attempts, and a complete 60-second measured window.

| Run | Frame p95 (ms) | Accepted-cut p95 (ms) | Cut maximum (ms) | Result |
| --- | ---: | ---: | ---: | --- |
| 1 | 7.732 | 49.614 | 50.696 | Pass |
| 2 | 8.192 | 47.490 | 48.052 | Pass |
| 3 | 8.185 | 47.946 | 52.592 | Pass |

[Machine-readable report](validation/vulkan-renderer/report.json), raw samples: [run 1](validation/vulkan-renderer/run-1.csv.gz), [run 2](validation/vulkan-renderer/run-2.csv.gz), [run 3](validation/vulkan-renderer/run-3.csv.gz). The [interactive cut](validation/vulkan-renderer/interactive-cut.png) and [resized window](validation/vulkan-renderer/resized.png) screenshots document the native presentation path. The archived report records the tested commit and source hashes. The current benchmark uses the same workload but a shorter stage row without the removed image-tree rendering and disposal stages.

After making Vulkan the default, a local `make benchmark` run also passed all three gates in each of its three runs. Frame p95 was 7.825, 7.779, and 7.718 ms; accepted-cut p95 was 48.885, 48.974, and 49.953 ms. Its report and raw samples were written to `build/benchmarks/`. The current benchmark uses the same workload but a shorter stage row without the removed image-tree rendering and disposal stages.

The benchmark's `vulkan_frame_effect` stage includes Bend heap traversal, native rectangle and HUD geometry expansion, vertex upload, command recording, Vulkan submission/presentation, event polling, and X11 synchronization. The stage does not isolate GPU execution time. The frame interval includes all application work; accepted-cut latency starts at each scheduled replay action and ends after frame presentation and X11 synchronization. X11 synchronization does not timestamp physical display scanout.

The benchmark runs Bend gameplay with `--gpu off` and renders through Vulkan. The recorded end-to-end results establish that this route met the agreed limits on the tested desktop. They do not isolate Vulkan raster time from scene upload, presentation, input polling, or X11 synchronization.

## Current boundaries

The renderer expands and uploads visible rectangles and bitmap HUD glyphs each frame. It uses one frame in flight and a host-visible vertex buffer. The implementation is Linux/X11-specific and does not use the Bend3D image tree. The preview matches the affected-cell/ring behavior, but the live image has not been given a pixel-by-pixel parity gate against Bend3D. Vulkan validation layers are not installed on the tested desktop; the live path has been exercised through window, edit, reset, resize, and replay checks.
