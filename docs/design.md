# About the first voxel slice

The slice stores one body and derives a rendered scene after each edit. The body remains the only authority for occupancy.

`voxel.bend` owns `Body`, `Cell`, `Sphere`, six face directions, and explicit `Surface` faces. `Body` holds a dense affine `Array<U32>`. Zero means empty. A positive value identifies a material. An edit moves the body through the destruction operation and returns the next body.

Surface extraction creates a temporary immutable snapshot for neighbor reads. The snapshot stays inside the geometry module and disappears after extraction. Bounds checks prevent wrapped array indices from connecting opposite body edges. `Body.destroy` accepts a center inside the body and a radius no larger than its side. Invalid brush inputs leave the body unchanged.

`render.bend` projects the exposed faces into `RenderScene`. Its tile tree holds short lists of projected faces. Pixels inspect those lists and never query editable occupancy. Back faces are culled for the fixed isometric camera. The renderer tests face coverage and depth before it creates the pure Bend `Image`.

`main.bend` owns the affine `Model` and native events. The edit reducer replaces the body, surface, and scene together. Frames reuse the scene until another edit. Window effects stay outside geometry and rendering.

`scripts/ui_check.bend` owns a native test window and exports its reference with the fork's `Window.export_ref`. The test drives the slice's shared view and reducer through `App.step`. A C adapter addresses that exact window through a separate X11 connection; Bend owns the assertions and screenshot export. Platform details stay inside the test adapter. The ordinary application still builds with upstream Bend.

Projection uses integer-valued `F32` arithmetic within the exact integer range. Pixel centers, face coverage numerators, and depth numerators remain exact. Stable face identifiers resolve depth ties. CPU and GPU calls use the same algorithm and produce exactly equal pixels in the checked cases.

## Accepted limits

The slice has one fixed 8³ body, one spherical destruction operation, one material, and one fixed camera. Each edit rebuilds the complete surface and scene. There is no perspective camera, smooth meshing, physics, streaming, or incremental surface update.

The displayed-frame benchmark includes `Window.frame`, image disposal, and scripted edit rebuilds. The native display can limit CPU results to its refresh interval. The selected CPU and GPU configurations reach the development display cadence. Those results do not establish a GPU compute speedup.

Core algorithms contain no backend intrinsics, hardware lane counts, or backend-specific synchronization. Tile and fork depths are runtime configuration. The Linux SDK path appears only in the build setup.

## Examples considered

The [official Bend demos](https://github.com/bendlang/bend/tree/main/demos) show native events, pure `Image` quadtrees, and GPU dispatch. The triangle, Pong, ray tracer, and Slash Boss examples informed the app and tile renderer shapes. This project contains original source and does not copy the large demo renderer.

The [Bend hub](https://hub.bend-lang.com/) and [awesome-bend](https://github.com/777genius/awesome-bend) were inspected for reusable packages. The inspected candidates included bendlib, Jonlib, bend-collections, bend-parallel, and WordLib. The first slice requires no external package.

## Principles applied

Model the Domain shaped the affine body, explicit faces, tile lists, and edit reducer. Boundary Discipline kept input and Window effects outside the pure geometry and renderer. Sequence Work into Verifiable Units placed exact geometry checks before native rendering. Test Behavior, Not Implementation shaped complete face-set and image assertions. Prove It Works required forced GPU execution and actual native input with screenshots.
