# Live Vulkan renderer

Vulkan is the renderer for the demo, which defaults to a 640 × 360 logical view and accepts `VOXEL_RESOLUTION=WIDTHxHEIGHT` at startup. Bend owns voxel ownership, cuts, connected components, cached face merging, body triangle construction, falling bodies, camera input, and picking. The application loop in `src/main.bend` uses `vulkan.frame` to render each current world state.

## Run and measure

```sh
make run
make benchmark-stress
```

The build requires Bend 2.0.31, Linux/X11 or XWayland, Vulkan 1.3 with Xlib surface support, Vulkan headers and loader, `glslc`, `g++`, and X11 development headers. `make run` uses Bend's CPU execution mode for gameplay; scene rasterization and presentation run in Vulkan. `make benchmark-stress` measures larger and more exposed scenes with unpaced presentation; see the [stress benchmark guide](stress-benchmark.md). The earlier 65-second acceptance replay described below is historical and is no longer runnable.

## Frame path

1. Bend updates the world, builds six local-space vertices per exposed face when a body's surfaces change, and computes the camera aim and HUD text.
2. The pinned native effect reads cached `Body`, `Face`, and `Vertex` values from Bend's heap. It copies faces and vertices only when a body revision changes, then passes them with the camera, aim, and HUD to `libvoxel_vulkan.so`.
3. The native renderer assigns palette colors to Bend's vertices and caches full meshes by body ID, revision, and anchor status; translation changes only the draw transform. Native code still builds render-tile proxies, brush preview cells, aim rings, ground, and HUD glyphs.
4. Vulkan 1.3 dynamic rendering fills a depth-only sun shadow map when body geometry or position changes. The main pass samples that map while shading voxel faces with sunlight, sky ambient light, and a camera work light, then draws triangles with depth testing, brush lines, and screen-space bitmap text into the Xlib swapchain image. The backend handles acquire, submission, presentation, and resize recreation. It uses a present wait semaphore per swapchain image, following [Khronos's swapchain reuse guidance](https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html).
5. The X11 adapter synchronizes the X server and sends key, mouse, focus, and close events back to Bend. Pointer positions are mapped to the selected logical resolution after resize.

Initial body meshes are independent Bend CPU tasks. An edit keeps unchanged bodies verbatim and builds faces and vertices only for newly classified bodies. Per-body parallel tasks on edits increased surface-stage time in the 512-fragment workload, so that short dirty list remains sequential.

The native effect returns the same Bend state it received. The effect depends on Bend 2.0.31's generated C layout; it checks the relevant constructor arities at runtime. Changes to Bend or the `State`, `World`, `Control`, `Aim`, `Body`, `Face`, or `Vertex` definitions require reviewing that bridge. `VOXEL_VERIFY_BEND_MESH=1` compares rebuilt body vertices against the previous native face expansion and fails on a mismatch; it is a validation mode, not a throughput setting.

## Render LOD

The native renderer keeps full meshes for every body and groups small anchored bodies into 64 m render tiles. A distant tile can use one draw containing a bounding box for each member, colored by that member's largest exposed material. A tile switches to its proxy below an 80-pixel projected diameter and returns to full meshes above 100 pixels. The gap prevents rapid switching near the threshold. Aimed-at tiles and all detached or large bodies use full meshes.

Proxy meshes are cached by member body IDs and revisions. Camera movement and aim changes select meshes without rebuilding them; edits and detachments update only affected tiles. This LOD changes the main rendering pass alone: the sun shadow map uses full body meshes, and Bend still simulates, cuts, and picks the full-resolution world. Both full and proxy meshes occupy the renderer's vertex arena, so LOD trades some memory for fewer distant draw calls. The box proxies simplify small open structures at a distance; they are meant for the demo's overview scale rather than close inspection.

## Material colors

`src/material.bend` names the five stable voxel IDs and defines which one marks protected foundations. The Light Atelier adds pale plaster as ID 5. `src/vulkan/material.hpp` gives each ID an OKLCH base color. The renderer builds linear RGB base swatches once for each material and anchor state. Detached bodies get a lightness/chroma adjustment in OKLCH, so their material hue remains visible. Out-of-gamut colors keep lightness and hue while chroma is reduced to fit sRGB.

Each cached vertex carries its face direction alongside its linear base color. The fragment shader applies cool sky ambient light, warm directional sunlight, and a distance-attenuated work light near the camera, then encodes for a UNORM attachment or leaves linear output for Vulkan's automatic sRGB attachment encoding. The ground receives light and shadows; HUD, aim rings, and the cut preview remain flat display colors. Holding L switches to a darker night setup with a stronger work light.

The 2,048 × 2,048 depth-only sun map uses an orthographic projection fitted to the occupied world. A three-by-three depth comparison softens shadow edges; each tap compares against the receiver plane at its texel center to prevent self-shadow stripes. It is cached by body ID, revision, anchor state, and vertical offset: camera, aim, and lighting changes reuse it, while cuts, detachments, and falling bodies update it. The shadow pass draws full body meshes so the main view's LOD selection cannot change a cached shadow. The nearby work light does not cast shadows. The palette is static; changing its definitions requires a rebuild. `VOXEL_VULKAN_TRACE=1` logs shadow refreshes alongside the opening camera trace.

## Validation

### Light Atelier (2026-09-27)

`make export-atelier-assets`, `make build`, `make test`, and `make test-blender` passed. Live day/night captures were inspected at 1280 × 720, with an additional default 640 × 360 capture. A 15-cell cut and reset each rebuilt one body's mesh and refreshed the shadow map; reset restored the pre-cut scene pixels. The [validation record](validation/light-atelier/README.md) includes the Blender source preview, engine captures, counts, and runtime trace.

### Startup resolution (2026-09-27)

`make build` and `make test` passed with resolution parsing, camera projection, reset target, and native cache checks. The Material Works Yard rendered three frames at both 1280 × 720 and 1024 × 768, and a 1024 × 768 window capture was inspected for correct layout. An invalid `1920X1080` value exited with a clear error before opening a window. The 16-district camera and aim stress workloads passed a short 24-frame run at the runner's default 640 × 360 resolution.

### Bend 2.0.31 update (2026-09-27)

The project pin was updated to [Bend 2.0.31](https://github.com/bendlang/bend/releases/tag/v2.0.31). The generated C now gives imported effects module-qualified constructor IDs and uses `u64` for heap locations; the native timer and Vulkan effects were adjusted to match. `make build` and `make test` passed. A three-frame live run rendered the 1,009-body Material Works Yard. Short 24-frame stress runs for district camera motion, aim sweep, and bridge severing all passed their workload and cache checks. These are compatibility checks, not a controlled compiler performance comparison. The local smoke report is under `build/bend-2.0.31-smoke/`.

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

[Machine-readable report](validation/vulkan-renderer/report.json), raw samples: [run 1](validation/vulkan-renderer/run-1.csv.gz), [run 2](validation/vulkan-renderer/run-2.csv.gz), [run 3](validation/vulkan-renderer/run-3.csv.gz). The [interactive cut](validation/vulkan-renderer/interactive-cut.png) and [resized window](validation/vulkan-renderer/resized.png) screenshots document the native presentation path. The archived report records the tested commit and source hashes. The later retired replay used the same workload but a shorter stage row without the removed image-tree rendering and disposal stages.

After making Vulkan the default, a local replay run also passed all three gates in each of its three runs. Frame p95 was 7.825, 7.779, and 7.718 ms; accepted-cut p95 was 48.885, 48.974, and 49.953 ms. Its report and raw samples were written to `build/benchmarks/`. This retired replay used a shorter stage row without the removed image-tree rendering and disposal stages.

The benchmark's `vulkan_frame_effect` stage includes Bend heap traversal, native rectangle and HUD geometry expansion, vertex upload, command recording, Vulkan submission/presentation, event polling, and X11 synchronization. The stage does not isolate GPU execution time. The frame interval includes all application work; accepted-cut latency starts at each scheduled replay action and ends after frame presentation and X11 synchronization. X11 synchronization does not timestamp physical display scanout.

The benchmark runs Bend gameplay with `--gpu off` and renders through Vulkan. The recorded end-to-end results establish that this route met the agreed limits on the tested desktop. They do not isolate Vulkan raster time from scene upload, presentation, input polling, or X11 synchronization.

## Current boundaries

The renderer caches scene triangles across unchanged inputs and updates bitmap HUD glyphs each frame. It uses one frame in flight and a host-visible vertex buffer. The implementation is Linux/X11-specific and does not use the Bend3D image tree. The preview matches the affected-cell/ring behavior, but the live image has not been given a pixel-by-pixel parity gate against Bend3D. Vulkan validation layers are not installed on the tested desktop; the live path has been exercised through window, edit, reset, resize, and historical replay checks.
