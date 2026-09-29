# Live Vulkan renderer

Vulkan is the renderer for the demo, which defaults to a 640 × 360 logical view and accepts `VOXEL_RESOLUTION=WIDTHxHEIGHT` at startup. Bend owns voxel ownership, cuts, connected components, cached face merging, body triangle construction, falling bodies, camera input, and picking. The application loop in `src/main.bend` uses `vulkan.frame` to render each current world state.

## Run and measure

```sh
make run
make benchmark-stress
```

The build requires Bend 2.0.34, Linux/X11 or XWayland, Vulkan 1.3 with Xlib surface support, Vulkan headers and loader, `glslc`, `g++`, and X11 development headers. `make run` uses Bend's CPU execution mode for gameplay; scene rasterization and presentation run in Vulkan. `make benchmark-stress` measures the Light Atelier with unpaced presentation. See the [benchmark guide](stress-benchmark.md).

## Frame path

1. Bend updates the world, builds six local-space vertices per exposed face when a body's surfaces change, and computes the camera aim and HUD text.
2. At startup, Bend computes the palette and passes it to the pinned native effect. On each frame, that effect reads cached `Body`, `Face`, and `Vertex` values from Bend's heap. It copies faces and vertices only when a body revision changes, then passes them with the camera, aim, HUD, and stored colors to `libvoxel_vulkan.so`.
3. The native renderer applies Bend's palette to vertices and caches full meshes by body ID, revision, and anchor status; translation changes only the draw transform. Native code still builds render-tile proxies, brush preview cells, aim rings, ground, and HUD glyphs.
4. Vulkan 1.3 dynamic rendering fills a depth-only sun shadow map when body geometry or position changes. The main pass samples that map while shading voxel faces with sunlight, sky ambient light, and a camera work light, then draws triangles with depth testing, brush lines, and screen-space bitmap text into the Xlib swapchain image. The backend handles acquire, submission, presentation, and resize recreation. It uses a present wait semaphore per swapchain image, following [Khronos's swapchain reuse guidance](https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html).
5. The X11 adapter synchronizes the X server and sends key, mouse, focus, and close events back to Bend. Pointer positions are mapped to the selected logical resolution after resize.

Initial body meshes are independent Bend CPU tasks. An edit keeps unchanged bodies verbatim and builds faces and vertices only for newly classified bodies. The short dirty list on edits is built sequentially.

The native effect returns the same Bend state it received. The effect depends on Bend 2.0.34's generated C layout; it checks the relevant constructor arities at runtime. Changes to Bend or the `State`, `World`, `Control`, `Aim`, `Body`, `Face`, `Vertex`, or palette definitions require reviewing that bridge. `VOXEL_VERIFY_BEND_MESH=1` compares rebuilt body vertices against the previous native face expansion and fails on a mismatch; it is a validation mode, not a throughput setting.

## Render LOD

The native renderer keeps full meshes for every body and groups small anchored bodies into 64 m render tiles. A distant tile can use one draw containing a bounding box for each member, colored by that member's largest exposed material. A tile switches to its proxy below an 80-pixel projected diameter and returns to full meshes above 100 pixels. The gap prevents rapid switching near the threshold. Aimed-at tiles and all detached or large bodies use full meshes.

Proxy meshes are cached by member body IDs and revisions. Camera movement and aim changes select meshes without rebuilding them; edits and detachments update only affected tiles. This LOD changes the main rendering pass alone: the sun shadow map uses full body meshes, and Bend still simulates, cuts, and picks the full-resolution world. Both full and proxy meshes occupy the renderer's vertex arena, so LOD trades some memory for fewer distant draw calls. The box proxies simplify small open structures at a distance; they are meant for the demo's overview scale rather than close inspection.

## Material colors

`src/material.bend` names the five stable voxel IDs and defines which one marks protected foundations. The Light Atelier adds pale plaster as ID 5. `src/color.bend` gives each ID an OKLCH base color and computes linear RGB swatches for anchored and detached bodies. Detached bodies get a lightness/chroma adjustment in OKLCH, so their material hue remains visible. Out-of-gamut colors keep lightness and hue while chroma is reduced to fit sRGB. Bend also computes linear ground and background colors and the display colors for HUD, aim, and brush overlays. A startup effect supplies these 19 colors to the native bridge, which validates their layout and range and reuses them on every frame.

Each cached vertex carries its face direction alongside its linear base color. The fragment shader applies cool sky ambient light, warm directional sunlight, and a distance-attenuated work light near the camera, then encodes for a UNORM attachment or leaves linear output for Vulkan's automatic sRGB attachment encoding. The ground receives light and shadows; HUD, aim rings, and the cut preview remain flat display colors. Holding L switches to a darker night setup with a stronger work light.

The 2,048 × 2,048 depth-only sun map uses an orthographic projection fitted to the occupied world. A three-by-three depth comparison softens shadow edges; each tap compares against the receiver plane at its texel center to prevent self-shadow stripes. It is cached by body ID, revision, anchor state, and vertical offset: camera, aim, and lighting changes reuse it, while cuts, detachments, and falling bodies update it. The shadow pass draws full body meshes so the main view's LOD selection cannot change a cached shadow. The nearby work light does not cast shadows. The palette is static; changing its definitions requires a rebuild. `VOXEL_VULKAN_TRACE=1` logs shadow refreshes alongside the opening camera trace.

## Validation

### Light Atelier (2026-09-27)

`make export-atelier-assets`, `make build`, `make test`, and `make test-blender` passed. Live day/night captures were inspected at 1280 × 720, with an additional default 640 × 360 capture. A 15-cell cut and reset each rebuilt one body's mesh and refreshed the shadow map; reset restored the pre-cut scene pixels. The [validation record](validation/light-atelier/README.md) includes the Blender source preview, engine captures, counts, and runtime trace.

### Bend 2.0.31 checks (2026-09-27)

`make build` and `make test` passed with resolution parsing, camera projection, reset target, and native cache checks. Invalid resolution input exits before opening a window. The project pin was updated to [Bend 2.0.31](https://github.com/bendlang/bend/releases/tag/v2.0.31). Its generated C uses module-qualified constructor IDs and `u64` heap locations; the native timer and Vulkan effects were adjusted to match.

### Bend 2.0.32 update (2026-09-27)

The project pin and local compiler were updated to [Bend 2.0.32](https://github.com/bendlang/bend/releases/tag/v2.0.32). Its `Event` type adds `Look` and `Scroll`; the Linux demo ignores these unused events. The native bridge now uses Bend's `BendWin` definition and passes the heap to `term_peek`. `make build`, `make test`, and `make benchmark-faces` passed. Short Light Atelier static and carve stress runs passed through the Vulkan window.

### Bend 2.0.34 update (2026-09-29)

The project pin and local compiler were updated to [Bend 2.0.34](https://github.com/bendlang/bend/releases/tag/v2.0.34) using the release's verified Linux x64 archive. The generated C retains the constructor arities, `BendWin` type, and `term_peek` signature used by the native bridge. `bend PROOF.bend`, `bend PROOF.bend --verdict`, `make build`, `make test`, and the six-cut face audit passed. Short static and carve stress runs also passed through the Vulkan window at 640 × 360; these were compatibility checks, not performance comparisons.

## Current boundaries

The renderer caches scene triangles across unchanged inputs and updates bitmap HUD glyphs each frame. It uses one frame in flight and a host-visible vertex buffer. The implementation is Linux/X11-specific and does not use the Bend3D image tree. The live path has been exercised through window, edit, reset, and resize checks.
