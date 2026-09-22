# First demo: Bend and Bend3D integration baseline

## Subsequent compiler update

On 2026-09-22, the project was updated to **Bend 2.0.25** at the user's request. The 2.0.16 observations below are historical; they have not been relabeled as checks of the new compiler. See [demo validation](../demo-validation.md) for current validation.

Date: 2026-09-21. Resolution of [Determine a compatible Bend and Bend3D integration baseline](https://github.com/aivv73/bend-voxel/issues/3), under [Find the way to the first destructible voxel demo](https://github.com/aivv73/bend-voxel/issues/1).

## Recommendation

Retain the installed **Bend 2.0.16** and use Bend3D from upstream commit **`a49524265bdfa5753a4bf38e25f0574a705dd868`** as the initial renderer source. Build CUDA binaries with `CUDA_HOME=/opt/cuda` and force `--gpu on` when validating the GPU path. No installation changes are justified by the compatibility evidence below; none were made.

The complete upstream application checks and compiles with this pairing. A small, separate adapter probe also submits an explicit triangle directly to `Mesh.raster`, renders through `Frame.show`, and returns the same nonzero image-tree checksum on CPU and GPU. This establishes a usable integration starting point, not a complete engine, visual correctness proof, or a 30 FPS result.

Use a new small application loop and an explicit voxel-triangle adapter; the boss game's simulation, surface tessellation, audio, and assets are unnecessary dependencies for our demo. Preserve upstream attribution and the [pinned license](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/LICENSE) when importing source.

## Evidence and reproducibility

The existing [feasibility notes](../bend-feasibility.md) already establish this machine's minimal CUDA execution. That power-of-two test was not repeated. The new checks test the actual renderer and its upstream client.

Primary source files fetched from the pinned revision, compared byte-for-byte by SHA-256 with the previously inspected local copies:

| File | SHA-256 |
|---|---|
| [bend3d.bend](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/demos/app_slash_boss_3d/bend3d.bend) | `166202415b6253382d0cdfd5ccb2184880540075bde6117809a5fbacd4adb3ad` |
| [main.bend](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/demos/app_slash_boss_3d/main.bend) | `3bdd4d07d5342ce8649fd4ae2af1f918a3e2f4806d3ae19247805f05454e7612` |

The installed CLI, queried directly, reports `bend 2.0.16`. Its update notice advertises 2.0.24, which was neither installed nor evaluated.

### Complete upstream application

With both pinned files in `/tmp/bend-voxel-research/`:

```sh
CUDA_HOME=/opt/cuda bend /tmp/bend-voxel-research/main.bend -o /tmp/bend-voxel-demo-baseline-upstream
SLASH_PROBE=1 timeout 45 /tmp/bend-voxel-demo-baseline-upstream --gpu on
```

Build exit code: **0**. Checker output: `All terms check, with 30 unsafe annotations.` Generated executable: **4,163,392 bytes**; `.gpu` companion: **984,328 bytes**. This is an actual native build, not source inspection alone.

Headless run exit code: **0**. It emitted simulation state at ticks 0 and 1, missing audio-asset notices with silent fallback, and `frames 0 build 0 draw 0 tick 0 mix 0 whole 0`. That final zero count is expected: upstream `Probe.loop` builds and draws the requested frame, but excludes its first eight frames from timing aggregation. One frame therefore produces no measured sample. This run must not be cited as a benchmark. Source: pinned `main.bend`, `Probe.loop`, `Probe.frame`, `Probe.report`, and `Sound.open`.

### Direct triangle adapter probe

Save the following as `compat-probe.bend` alongside the pinned `bend3d.bend`. It does not require a window or game assets. It preserves an IO effect between triangle preparation and the device call and consumes the resulting image via a simple leaf-color checksum.

```bend
import Base
import ./bend3d.bend as R

def sky(+x: U32, +y: U32, +h: U32) -> U32:
  0

def mixed(+s: U32, +x: U32, +y: U32, +h: U32) -> Bool:
  False{}

def column(per: Bool, +x: U32, +s: U32) -> U32:
  s

def pixel(+x: U32, +y: U32, +s: U32) -> U32:
  s

def width() -> U32:
  64

def height() -> U32:
  64

def checksum(image: Image) -> U32:
  match image:
    case Pix{c}:
      c
    case Qua{a, b, c, d}:
      (checksum(a) + checksum(b) + checksum(c) + checksum(d) : U32)

def report(drawn: Image & R.Cells) -> IO(Unit):
  (image, cells) = drawn
  IO.print(U32.show(checksum(image)))

def main() -> IO(Unit):
  do IO<Unit>:
    cells : R.Cells = R.Mesh.raster(R.Vert{8.0, 8.0, 1.0, 1.0, 0.0, 0.0},
      R.Vert{8.0, 56.0, 1.0, 1.0, 0.0, 0.0},
      R.Vert{56.0, 8.0, 1.0, 1.0, 0.0, 0.0}, 0, 1.0, 63.0, 63.0, R.CNil{})
    seam : Nat <- IO.now()
    drawn : Image & R.Cells <- IO.pure(Image & R.Cells,
      R.Frame.show(~U32, ~sky, ~mixed, ~column, ~pixel, ~width, ~height, cells, Pix{0}))
    report(drawn)
```

```sh
CUDA_HOME=/opt/cuda bend /tmp/bend-voxel-research/compat-probe.bend -o /tmp/bend-voxel-renderer-compat
/tmp/bend-voxel-renderer-compat --gpu on
/tmp/bend-voxel-renderer-compat --gpu off
```

Build exit code: **0**. Checker output: `All terms check, with 13 unsafe annotations.` Both executions exit **0** and print **`1520697344`**. The checksum is deliberately modest evidence: one triangle, a 64 × 64 active area, one frame, integer addition over image-tree leaves. It confirms observable rendering and agreement for this input; it is not a collision-resistant image hash or a pixel-for-pixel regression suite. The probe's source is preserved above; generated binaries are disposable and are not committed.

## Required integration adaptation

### Explicit triangles and near-plane clipping

Bend3D already exposes `Vert` and `Mesh.raster`, so voxel faces can bypass `Surf`, `Grid`, and their parametric tessellation. Transform cached local voxel vertices to world/view space, shade opaque faces, clip, project, and submit projected `Vert` triples into `Cells`. Use mode `0` and opacity `1.0` for the first opaque demo. The successful probe exercises this direct entry point. `Mesh.raster` accepts opaque faces only when its projected signed area is negative, so test the adapter's winding. Source: pinned [renderer](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/demos/app_slash_boss_3d/bend3d.bend), `Vert`, `Mesh.raster`, and `Grid.strip`.

The upstream near-plane behavior needs a real adaptation: `Cam.proj` emits zero reciprocal depth unless depth is strictly greater than `near`; `Mesh.raster` rejects a triangle if any reciprocal depth is nonpositive. Clip in camera space before projection, retaining zero, one, or two triangles and interpolating attributes. Define a consistent boundary convention: simply creating vertices exactly at `near` and feeding the existing strict projection test would reject them again. Handle degenerate results and preserve winding. This is a required correctness change, not something this compatibility probe implements or validates. Source: same renderer, `Cam.proj` and `Mesh.raster`.

`Frame.show` fixes a root of 32 × 32 cells of 64 pixels each (2048-square coverage). The agreed 640 × 360 internal frame fits; provide constant dimension hooks and a simple background. This source constraint does not measure the cost of processing or presenting that image. Source: same renderer, `Frame.show`, `Frame.node`, and `Hook.dim`.

### Window and input

The installed library was queried with `bend base Window` and `bend base Event`. It has:

- `Window.open(title, width, height)` returning an IO result containing an owned window;
- `Window.frame(window, image)` returning `Window & Image & List<Event>`;
- `Window.set_title` and `Window.close`;
- events `Key{code, down}`, `Mouse{x, y, button, down}`, `Move{x, y}`, and `Close{}`.

These locally confirmed types match the required keyboard and drag-to-look design. Keep key/button state in the host loop and compute drag deltas from successive absolute positions. Retain the returned window and image; handle close explicitly. No installed pointer-lock operation was found in the Window API. Source: installed Base output above, corroborated by [pinned Base](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/bend2/base.bend) and the [Linux window effect](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/bend2/effs/window_frame.c).

The complete application build includes the platform effect integration. **An interactive window was not opened for this investigation**, so input codes, focus behavior, presentation, and visual output still need a playable smoke test. This research does not claim they have been exercised.

### Single-owner arrays

`bend base Array` confirms the installed API has `new`, `get`, `set`, `swap`, `clone`, `size`, `map`, and `to_list`. In particular, reads return `Array<T> & T`; updates return ownership, and `Array.new` takes a depth. `Array.get.at` and `Array.swap.at` mask indices with `n - 1`, so bounds checking belongs to the caller. `bend base Array.fork` exits **1** with `bend: Base has no Array.fork (see bend --help)`.

Consequently, retain explicit ownership of voxel arrays through simulation and meshing; construct a separate immutable render package. Do not use upstream unsafe array fork/join or atomics introduced beyond this installed API, or assume arbitrary parallel readers of a mutable world. Choosing a concrete storage representation is a separate decision. Sources: installed Base command output and existing [feasibility notes](../bend-feasibility.md); current pinned upstream Base must not substitute for the installed version's API.

### Host/device ordering

Preserve the upstream ordering: build `Cells` on the host, cross an effect boundary (the demo uses `IO.now`), evaluate `Frame.show` through `IO.pure`, then present with `Window.frame`. `Frame.show` invokes one `Frame.node!` and returns both image and cells. Its upstream client specifically warns against letting the bang follow host forks in one evaluation. Reuse the previous image as the renderer expects and keep the returned cells' lifetime explicit. Do not infer that `IO.pure` alone is the host/device barrier. Sources: pinned [main.bend](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/demos/app_slash_boss_3d/main.bend), `Play.loop`, `Play.frame`, `Play.blit`; pinned renderer, `Frame.show`.

This probe follows that pattern successfully; it does not establish a general runtime scheduling theorem or validate asynchronous multiple-frame submission. The recommended first loop has one frame in flight.

## Remaining decisions and limits

The compatibility question is answered: installed compiler plus pinned renderer is sufficient to start implementation without an upgrade. The following remain outside this research result:

- Pick the demo's concrete scene dimensions, voxel counts, fragment cap, and owned storage representation. What smallest fixed scene and repeatable cuts should define the performance workload?
- Specify clipping boundary handling and test expectations as part of the renderer adapter contract.
- Define measurable budgets for meshing, connectivity, rendering, presentation, and destruction latency. Neither 30 FPS at 640 × 360 nor an acceptable carving latency has been demonstrated.
- Verify actual window/input behavior, camera motion through geometry, and material/winding correctness in the future playable demo.

No engine code was added, no performance promise made, and neither Bend nor CUDA was updated. This research is intentionally on its own branch; the root working tree's uncommitted documentation remains untouched.
