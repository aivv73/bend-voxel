# Bend Voxel

An interactive, destructible voxel demo built with [Bend 2](https://github.com/bendlang/bend) and a native Vulkan renderer. Carve through the two supports to detach the slab, then cut the falling or landed fragment again. Voxel ownership, connectivity, carving, and motion run in Bend on the CPU; Vulkan draws the scene. CUDA is not required.

![Native Bend voxel demo](docs/validation/vulkan-renderer/initial-vulkan.png)

This bounded Linux demo is listed in [Awesome Bend's community demos](https://github.com/777genius/awesome-bend#community-demos). See an [interactive cut](docs/validation/vulkan-renderer/interactive-cut.png).

## Quick start

You need **[Bend 2.0.27](https://github.com/bendlang/bend/releases/tag/v2.0.27)**, Linux with X11 or XWayland, a Vulkan 1.3 graphics driver with Xlib surface support, Vulkan and X11 development headers, `glslc`, `g++`, and `make`. The benchmark also needs Python 3. Check that `bend version` prints `bend 2.0.27`; the build does not install or update Bend.

```sh
make run
```

This compiles the shaders, native Vulkan library, and Bend application, then opens a resizable window with a 640 × 360 logical view. To build once and launch separately:

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
| R or RESET | Restore the scene and camera |
| Escape | Release controls; click the scene to resume |

Green voxels are protected anchors. Purple geometry is detached. The floor is indestructible. Detached bodies fall vertically and stop on the floor; they do not rotate, collide with each other, or reattach. The camera has bounded movement and no collision.

The scene contains 4,640 ten-centimeter voxels. Connectivity uses shared faces. A cut that would exceed **64 detached bodies, including landed bodies**, is rejected without changing the world.

## Verify

```sh
make test
make benchmark
```

The benchmark opens the Vulkan window and runs the same scripted destruction and camera sequence three times. Each run has a five-second warm-up and sixty-second measurement. Raw samples and the report are saved under `build/benchmarks/`; a failed acceptance gate returns a nonzero exit code.

On the Ryzen 5 1600 / GTX 1660 Linux desktop, the Bend 2.0.27 Vulkan replay passed all three runs: frame p95 was **7.8–8.2 ms** (limit 33.3 ms), and accepted-cut p95 was **49–51 ms** (limit 100 ms). These results cover the fixed 640 × 360 workload on that machine. See the [Vulkan validation](docs/vulkan-renderer.md), [full report](docs/validation/bend-2.0.27-vulkan/report.json), and [profiling guide](docs/profiling.md).

For throughput and scale measurements, run `make benchmark-stress`. It uses larger and more exposed scenes, render overdraw multipliers, and an unpaced Vulkan presentation mode; results go to `build/stress/`. See the [stress benchmark guide](docs/stress-benchmark.md) for workloads and timing limits.

## Implementation

- `src/world.bend`: voxel ownership, carving, connectivity, atomic cap enforcement, vertical motion, and cached surface rectangles.
- `src/render.bend`: camera geometry and face picking used by gameplay.
- `src/input.bend`: controls, movement, and focus handling.
- `src/demo.bend`: gameplay state, HUD content, and timed replay.
- `src/main.bend` and `src/vulkan/`: application loop, native Vulkan renderer, and swapchain.
- `src/math.bend`: vector and camera primitives adapted from Bend3D; see the [third-party notice](src/vendor/NOTICE.md).

The broader engine design remains exploratory; this demo uses a bounded dense lattice rather than implementing the proposed sparse world:

- [Architecture and implementation sequence](docs/architecture.md)
- [Demo baseline research](docs/research/demo-baseline.md)
- [World model glossary](CONTEXT.md)

Earlier CPU/CUDA renderer experiments and measurements remain in `docs/` as historical research. All project documentation is maintained in English.
