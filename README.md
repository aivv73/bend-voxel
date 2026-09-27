# Bend Voxel

An interactive destructible voxel world built with [Bend 2](https://github.com/bendlang/bend) and a native Vulkan renderer. The default **Light Atelier** puts three large Blender-voxelized sculptures in a sunlit courtyard: Suzanne, a hollow ring, and a twisted column. Pale plaster receives their cast shadows, and a slatted canopy paints shadow stripes across the floor. CUDA is not required.

![Light Atelier](docs/validation/light-atelier/day.png)

The 44 × 34 meter showcase opens close to its editable 10 cm voxel sculptures. [Its Blender source and voxelization workflow](docs/showcase.md) let you replace or extend the exhibits. Hold L to compare the night lighting. The benchmark exercises this scene by default. The demolition district remains available through `VOXEL_DISTRICTS=1`, `4`, or `16` for scale and fragment workloads.

## Quick start

You need **[Bend 2.0.31](https://github.com/bendlang/bend/releases/tag/v2.0.31)**, Linux with X11 or XWayland, a Vulkan 1.3 graphics driver with Xlib surface support, Vulkan and X11 development headers, `glslc`, `g++`, and `make`. The benchmark also needs Python 3. Check that `bend version` prints `bend 2.0.31`; the build does not install or update Bend.

```sh
make run
```

This compiles the shaders, native Vulkan library, and Bend application, then opens a resizable window with a 640 × 360 logical view. Choose the startup render resolution with `VOXEL_RESOLUTION=WIDTHxHEIGHT`, for example:

```sh
VOXEL_RESOLUTION=1920x1080 make run
```

The minimum is 640 × 360; the maximum is 8,294,400 pixels, with width at most 7,680 and height at most 4,320. The camera, picking, HUD, and reset control use the selected size. Resizing the window afterward scales that logical view. The stress benchmark defaults to 640 × 360 and accepts `--resolution WIDTHxHEIGHT`. To build once and launch separately:

```sh
make build
./scripts/run.sh
```

## Controls

| Input | Action |
| --- | --- |
| Pointer | Aim; yellow cells show the removal preview |
| Left click | One 20 cm radius spherical cut |
| Hold right mouse + drag | Look; carving is disabled while looking |
| W / A / S / D | Move horizontally |
| Q / E | Move down / up |
| Hold Shift | Travel five times faster |
| Hold L | Preview night lighting with a nearby work light |
| R or RESET | Restore the scene and camera |
| Escape | Release controls; click the scene to resume |

Green foundation material marks protected anchors; concrete is tan, frames are blue, machinery is orange, and plaster is pale. The material palette is authored in OKLCH. Detached bodies retain their material hue with a lighter, softer appearance. Sunlight casts sculpture and canopy shadows across the courtyard; sky ambient light and a nearby work light shade surfaces in linear RGB. Hold L to inspect the scene at night. The underlying floor is indestructible; the plaster platform is editable. Bodies fall vertically and stop at the floor. Rotation, body collisions, stacking, and reattachment are not implemented. The camera travels at 12 m/s, or 60 m/s while Shift is held, without collision or horizontal bounds.

```sh
VOXEL_DISTRICTS=1 ./scripts/run.sh
VOXEL_DISTRICTS=4 ./scripts/run.sh
VOXEL_DISTRICTS=16 VOXEL_BODY_BUDGET=4096 ./scripts/run.sh
```

With `VOXEL_DISTRICTS` unset, the new showcase opens. Values 1, 4, or 16 select the earlier demolition district at those real scales. The default detached-body budget is 2,048, configurable up to 65,536. An edit that exceeds the budget is rejected atomically. Reset restores the selected scene and budget.

In the earlier district, the bridge is 16 meters above ground between the northern towers. Its two orange fuses are near **(−15.9, 16.25, −19.95)** and **(15.9, 16.25, −19.95)** meters. Cut both to detach it; the repeatable bridge workload performs the same edits automatically.

## Verify

```sh
make test
make benchmark-stress
make benchmark-faces
```

The default benchmark opens the Vulkan window and measures the Light Atelier in daylight and at night, camera motion, aim sweeps, and six edits across the sculptures. It checks shadow-map refreshes and mesh-cache behavior and saves samples and a report under `build/stress/`. The district scale, bridge, and 128/512-body fragment cases remain selectable with `--cases`. See the [benchmark guide](docs/stress-benchmark.md).

`make benchmark-faces` runs a headless diagnostic over the same six cuts. It reports surface-stage time, including Bend vertex construction, and full face-builder work counts separately for Suzanne, Oculus, and Twist under `build/faces/`.

## Implementation

- `src/spatial.bend`: sparse solid cuboids, spatial trees, sphere subtraction, shared-face connectivity, and exposed rectangles.
- `src/world.bend`: body ownership, transactional edits, configurable budget, and vertical motion.
- `src/showcase.bend`, `src/atelier_assets.bend`: the sculpture courtyard and Blender-voxelized exhibits.
- `src/district.bend`: deterministic district generation and real spatial replication.
- `src/render.bend`: camera and spatial picking.
- `src/mesh.bend`: body-face expansion into local-space triangle vertices.
- `src/input.bend`, `src/demo.bend`, `src/main.bend`: controls, HUD, application loop, and repeatable workloads.
- `src/vulkan/`: per-body transport/mesh caches, proxy and overlay geometry, dirty mesh uploads, GPU lighting, transform draws, and Vulkan presentation.
- `src/math.bend`: vector/camera primitives adapted from Bend3D; see the [third-party notice](src/vendor/NOTICE.md).

See the [sparse storage decision](docs/adr/0001-sparse-cuboid-world.md), [world model glossary](CONTEXT.md), and [earlier architecture exploration](docs/architecture.md). Irregular destruction can grow the number of stored regions and surfaces; the suite measures this representation rather than promising an arbitrary-world scale limit.

The original bounded demo and earlier renderer experiments remain documented in the [Vulkan validation archive](docs/vulkan-renderer.md). The project is listed in [Awesome Bend's community demos](https://github.com/777genius/awesome-bend#community-demos). All project documentation is maintained in English.
