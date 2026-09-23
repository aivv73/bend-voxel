# Vulkan face raster prototype

**Question:** Can a native Vulkan raster pass draw Bend's cached, merged voxel faces with comparable images and sufficiently low raster cost to justify a deeper integration experiment?

This is throwaway code on `prototype/vulkan-raster`. Gameplay, ownership, picking, cuts, connectivity, and face merging remain in Bend. `vulkan-scene.bend` exports four states from the existing fixed-clock replay. `vulkan_offscreen.cpp` expands the cached face rectangles into triangles, moves falling bodies with a per-draw offset, and renders at the demo's 640 × 360 resolution. It uses Vulkan 1.3 dynamic rendering and GPU timestamp queries. The runner builds an independent Bend/CUDA reference image for each state and compares raw RGB pixels.

## Run

From this branch, with Bend 2.0.26, CUDA, a Vulkan 1.3 graphics driver and development headers, `glslc`, `g++`, and Python 3 installed:

```sh
make prototype-vulkan
```

The command rebuilds the exporter, reference renderer, shaders, and native Vulkan program. Results go to `build/vulkan-prototype/`: `report.json`, scene fixtures, reference and Vulkan PNGs, red difference maps, and compressed Bend image trees. Override the timed frame count with `make prototype-vulkan VULKAN_ARGS='--frames 200'`.

## Result on the local GTX 1660

| Replay tick | State | Merged faces | Different RGB pixels | Vulkan wall median | GPU draw median |
| ---: | --- | ---: | ---: | ---: | ---: |
| 0 | Initial | 184 | 0.816% | 0.172 ms | 0.011 ms |
| 408 | Cut with moving body | 324 | 0.783% | 0.167 ms | 0.013 ms |
| 540 | Landed body | 342 | 0.849% | 0.171 ms | 0.013 ms |
| 1140 | Orbit view | 342 | 0.392% | 0.185 ms | 0.013 ms |

The raw pixel mismatches are concentrated in two known areas. This pass does not render the yellow brush preview or the selected voxel highlights. A thin floor edge also lands on different pixels than Bend3D's software rasterizer. The landed scene's [Bend image](../../docs/validation/vulkan-prototype/tick-0540-bend.png), [Vulkan image](../../docs/validation/vulkan-prototype/tick-0540-vulkan.png), and [difference map](../../docs/validation/vulkan-prototype/tick-0540-difference.png) are retained with the [machine-readable report](../../docs/validation/vulkan-prototype/report.json).

These timings cover command recording, submission, color readback, and fence wait with geometry already on the GPU. The GPU timestamp covers the draw pass. They exclude Bend scene extraction, edit/rebuild work, a window, presentation, the preview, and HUD text. The run uses a fixed mesh for each timed scene; it does not measure replacement of a mesh after a cut. The 0.17–0.19 ms wall numbers therefore cannot be compared directly to the complete CUDA demo frame time or used as an acceptance result.

**Verdict:** The cached face format is suitable for a Vulkan raster backend, and its isolated draw cost is small on this machine. A replacement decision requires a persistent Bend-to-native scene bridge, live mesh updates after cuts, brush/HUD parity, a Vulkan swapchain, and the existing 65-second end-to-end replay gates. This branch is a reference for that integration experiment, not a renderer switch.
