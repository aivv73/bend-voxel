# About the first voxel slice

The slice stores one body and derives a rendered scene after each edit. The body remains the only authority for occupancy.

`voxel.bend` owns `Body`, `Cell`, `Sphere`, six face directions, and explicit `Surface` faces. `Body` holds a dense affine `Array<U32>`. Zero means empty. A positive value identifies a material. An edit moves the body through the destruction operation and returns the next body.

Surface extraction creates a temporary immutable snapshot for neighbor reads. The snapshot stays inside the geometry module and disappears after extraction. Bounds checks prevent wrapped array indices from connecting opposite body edges. `Body.destroy` accepts a center inside the body and a radius no larger than its side. Invalid brush inputs leave the body unchanged.

`render.bend` projects the exposed faces into `RenderScene`. Its tile tree holds short lists of projected faces. Pixels inspect those lists and never query editable occupancy. Back faces are culled for the fixed isometric camera. The renderer tests face coverage and depth before it creates the pure Bend `Image`.

`main.bend` owns the affine `Model` and native events. The edit reducer replaces the body, surface, and scene together. Frames reuse the scene until another edit. Window effects stay outside geometry and rendering.

`scripts/ui_check.bend` owns a native test window and drives the slice's shared view and reducer through `App.step`. The fork's `Window.capture` reads its client pixels. `scripts/ui_capture.bend` consumes the affine RGB array and builds the existing `Image` used by assertions and screenshot export. It admits only the checker's 512x512 frame and its exact pixel capacity. Row-major reads pass the array owner sequentially through the four image quadrants. The checker passes the exported `WindowRef` directly to the public API of [bend-ui-test](https://github.com/aivv73/bend-ui-test). The library owns native input, close requests, and expiry checks. The checker keeps the scenario, the choice of close method, and pixel assertions. The ordinary application still builds with upstream Bend.

The `deps/bend-ui-test` git submodule pins the library without copying its native implementation into this project's sources. A sibling checkout would require separate version and import-path configuration. Vendoring would duplicate upstream source and its update work. The build lists all four library source files as prerequisites. Only the UI checker imports the dependency.

Projection uses integer-valued `F32` arithmetic within the exact integer range. Pixel centers, face coverage numerators, and depth numerators remain exact. Stable face identifiers resolve depth ties. CPU and GPU calls use the same algorithm and produce exactly equal pixels in the checked cases.

## Accepted limits

The slice has one fixed 8³ body, one spherical destruction operation, one material, and one fixed camera. Each edit rebuilds the complete surface and scene. There is no perspective camera, smooth meshing, physics, streaming, or incremental surface update.

The displayed-frame benchmark includes `Window.frame`, image disposal, and scripted edit rebuilds. The native display can limit CPU results to its refresh interval. The selected CPU and GPU configurations reach the development display cadence. Those results do not establish a GPU compute speedup.

Core algorithms contain no backend intrinsics, hardware lane counts, or backend-specific synchronization. Tile and fork depths are runtime configuration. The Linux SDK path appears only in the build setup.

## Examples considered

The [official Bend demos](https://github.com/bendlang/bend/tree/main/demos) show native events, pure `Image` quadtrees, and GPU dispatch. The triangle, Pong, ray tracer, and Slash Boss examples informed the app and tile renderer shapes. This project contains original source and does not copy the large demo renderer.

The [Bend hub](https://hub.bend-lang.com/) and [awesome-bend](https://github.com/777genius/awesome-bend) were inspected for reusable packages. The inspected candidates included bendlib, Jonlib, bend-collections, bend-parallel, and WordLib. The engine and ordinary application require only Base. Native UI checks also use bend-ui-test.

## Principles applied

Model the Domain shaped the affine body, explicit faces, tile lists, and edit reducer. Boundary Discipline kept input and Window effects outside the pure geometry and renderer. Sequence Work into Verifiable Units placed exact geometry checks before native rendering. Test Behavior, Not Implementation shaped complete face-set and image assertions. Prove It Works required forced GPU execution and actual native input with screenshots.

For the library migration, Model the Domain keeps `WindowRef` as the test address and `Window` as the application's owner. Boundary Discipline puts native event delivery in UITest. Migrate Callers Then Delete Legacy APIs removes every local `Desktop` caller and the three adapter files together. Laziness Protocol and Minimize Reader Load remove the key, click, and alive forwarding helpers. The close helper remains because it selects between Escape and a window close request. Exhaust the Design Space compared a pinned submodule, a sibling checkout, and vendored source. Prove It Works compares actual window screenshots before and after the migration.
