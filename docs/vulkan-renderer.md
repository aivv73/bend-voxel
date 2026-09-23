# Live Vulkan renderer

This branch adds a second native renderer for the existing 640 × 360 demo. Gameplay remains in Bend: voxel ownership, cuts, connected components, cached face merging, falling bodies, camera input, and picking use the same code as the Bend3D version. The Vulkan route has its own application loop in `src/demo_vulkan.bend` and uses `vulkan.frame` to render each current world state. The original `make run` and `make benchmark` routes remain available.

## Run and measure

```sh
make vulkan-run
make vulkan-benchmark
```

The build requires Bend 2.0.26, Linux/X11 or XWayland, Vulkan 1.3 with Xlib surface support, Vulkan headers and loader, `glslc`, `g++`, and X11 development headers. `make vulkan-run` uses Bend's CPU execution mode for gameplay; scene rasterization and presentation run in Vulkan. The benchmark opens a window and runs three independent 65-second replays: five seconds warm-up and sixty seconds measured. It retains each frame and edit sample under `build/vulkan-benchmarks/` and checks the same 33 accepted cuts, six protected/empty attempts, 33.3 ms frame p95, 100 ms accepted-cut p95, and 250 ms cut maximum gates as the CUDA demo. One diagnostic pass can be requested with `make vulkan-benchmark VULKAN_BENCH_ARGS='--runs 1 --output build/vulkan-pilot'`.

## Frame path

1. Bend updates the world and computes the camera aim and HUD text.
2. The pinned native effect reads the current cached `Body` and merged `Face` values from Bend's heap. It passes a flat face list, camera, aim, and HUD to `libvoxel_vulkan.so`.
3. The native renderer expands visible rectangles into triangles and highlights affected voxel cells near the brush. Falling-body offsets are applied to current vertices. Three twelve-segment rings show the brush location.
4. Vulkan 1.3 dynamic rendering draws triangles with depth testing, brush lines, and screen-space bitmap text into the same Xlib swapchain image. The backend handles acquire, submission, presentation, and resize recreation. It uses a present wait semaphore per swapchain image, following [Khronos's swapchain reuse guidance](https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html).
5. The X11 adapter synchronizes the X server and sends key, mouse, focus, and close events back to Bend. Pointer positions are mapped to the demo's 640 × 360 logical space after resize.

The native effect returns the same Bend state it received. This preserves the existing simulation and lets the two renderers use the same replay operations. The effect depends on Bend 2.0.26's generated C layout; it checks the relevant constructor arities at runtime. Changes to Bend or the `State`, `World`, `Control`, `Aim`, `Body`, or `Face` definitions require reviewing that bridge.

## Validation

`make test` still checks world, input, render geometry, timed edits, and the snapshot parser. A finite Vulkan window run, pointer cut, reset, and 800 × 450 resize were inspected on the local GTX 1660/XWayland desktop. The pointer cut removed 17 voxels and reset restored all 4,640. The fixed-scene [offscreen prototype](../src/prototype/README.md) retains Bend/CUDA image comparisons for four replay states; the live route uses the same face geometry but adds the swapchain, current-state bridge, brush, HUD, and input loop.

Live [Bend3D](validation/vulkan-renderer/initial-bend.png) and [Vulkan](validation/vulkan-renderer/initial-vulkan.png) captures of the initial state use the same default camera. The captures were taken at different times and use different text drawing methods. They are a visual diagnostic, not a synchronized pixel parity gate. The Vulkan HUD was also checked in repeated captures without input and after an 800 × 450 resize.

The fresh three-run replay passed all workload, instrumentation, and performance gates. Each run had 33 accepted cuts, six expected protected/empty attempts, and a complete 60-second measured window.

| Run | Frame p95 (ms) | Accepted-cut p95 (ms) | Cut maximum (ms) | Result |
| --- | ---: | ---: | ---: | --- |
| 1 | 8.093 | 53.162 | 56.270 | Pass |
| 2 | 8.076 | 51.845 | 52.043 | Pass |
| 3 | 8.229 | 52.513 | 57.318 | Pass |

[Machine-readable report](validation/vulkan-renderer/report.json), raw samples: [run 1](validation/vulkan-renderer/run-1.csv.gz), [run 2](validation/vulkan-renderer/run-2.csv.gz), [run 3](validation/vulkan-renderer/run-3.csv.gz). The [interactive cut](validation/vulkan-renderer/interactive-cut.png) and [resized window](validation/vulkan-renderer/resized.png) screenshots document the native presentation path. The report records source hashes because the branch was uncommitted during measurement.

The benchmark's `vulkan_frame_effect` stage includes Bend heap traversal, native rectangle and HUD geometry expansion, vertex upload, command recording, Vulkan submission/presentation, event polling, and X11 synchronization. The stage does not isolate GPU execution time. The frame interval includes all application work; accepted-cut latency starts at each scheduled replay action and ends after frame presentation and X11 synchronization. X11 synchronization does not timestamp physical display scanout.

This benchmark runs Bend gameplay with `--gpu off`, while the existing acceptance benchmark forces Bend/CUDA execution and renders with Bend3D. The end-to-end results establish that this Vulkan route meets the agreed limits on this desktop; they do not isolate Vulkan's contribution to the difference between the two routes.

## Current boundaries

The renderer currently expands and uploads visible rectangles and bitmap HUD glyphs each frame. It uses one frame in flight and a host-visible vertex buffer. The implementation is Linux/X11-specific and does not use the Bend3D image tree. The preview matches the affected-cell/ring behavior, but the live image has not been given a pixel-by-pixel parity gate against Bend3D. Vulkan validation layers are not installed on the tested desktop; the live path has been exercised through window, edit, reset, resize, and replay checks.
