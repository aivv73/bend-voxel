# Bend Voxel

A destructible voxel demo built with [Bend 2](https://github.com/bendlang/bend) and a native Vulkan renderer. Explore and carve three sculptures in **Light Atelier**.

![Light Atelier](docs/validation/light-atelier/day.png)

## Run

Requires [Bend 2.0.32](https://github.com/bendlang/bend/releases/tag/v2.0.32), Linux with X11 or XWayland, a Vulkan 1.3 driver with Xlib surface support, Vulkan and X11 development headers, `glslc`, `g++`, and `make`.

```sh
make run
```

Set `VOXEL_RESOLUTION=1280x720` before `make run` to change the render resolution.

## Controls

| Input | Action |
| --- | --- |
| Pointer / left click | Aim / carve |
| Right drag | Look around |
| W / A / S / D, Q / E | Move horizontally, down / up |
| Shift | Move faster |
| L | Preview night lighting |
| R or RESET | Restore the scene |
| Escape | Release controls; click the scene to resume |

## Verify

```sh
make test
make benchmark-stress
make benchmark-faces
```

The benchmarks need Python 3. See the [Light Atelier guide](docs/showcase.md) for Blender assets, the [benchmark guide](docs/stress-benchmark.md) for workloads and results, and the [renderer guide](docs/vulkan-renderer.md) for implementation details.
