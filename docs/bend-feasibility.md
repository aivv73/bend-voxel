# Bend 2: Constraints for the Voxel Engine

## Compiler update

On 2026-09-22, the project was updated to **Bend 2.0.25** at the user's request. The 2.0.16 observations below are historical; they have not been relabeled as checks of the new compiler. See [demo validation](demo-validation.md) for current validation.

Checked on 2026-09-21. **Bend 2.0.16** is installed locally; upstream was inspected at commit `a49524265bdfa5753a4bf38e25f0574a705dd868`. Compatibility of the complete demo scene with the local version has not yet been checked. Numbers in the upstream shader guide are the authors' measurements on other machines, not this engine's budget. EFFECTS/SHADERS themselves warn that they were written by AI and await human review; APIs were additionally checked against Base and source code.

## Verified capabilities

- `App.run`, `Window.open/frame/close`, and `Image = Pix | Qua` are available; `Window.frame` returns the window, image, and events. Input events are `Key`, `Mouse`, `Move`, and `Close`. This provides an application loop and image presentation, not a hardware triangle rasterizer API. Use `Window` directly for a custom fixed-step loop and image reuse. [Base](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/bend2/base.bend#L352).
- On Linux, the window uses X11; the frame is expanded from `Image` and displayed with `XPutImage`. Base has no public relative mouse / pointer lock operation; `Move` contains absolute coordinates. An orbit/drag camera or limited controls suit the first version; full FPS mouse-look requires a separate platform effect. [Window.frame](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/bend2/effs/window_frame.c#L184), [Window.open](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/bend2/effs/window_open.c#L179).
- Native GPU backends are Metal on Apple and CUDA on Linux/NVIDIA. Vulkan is not provided; WSL is suggested for Windows. JavaScript executes computations sequentially. Without a GPU, a `!` call can run on the CPU, so successful execution alone does not establish GPU use. [Guide](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/guide/GUIDE.md#L156), [WONTFIX](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/WONTFIX.txt#L53).
- `Array<T>` supports in-place mutation with a single owner. Reading returns the array together with the element; the size is a power of two and indices **wrap around**, so coordinates must be validated before indexing. The entire mutable world cannot simply be marked `+` and distributed to tasks as ordinary shared data. [Guide / Arrays](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/guide/GUIDE.md#L169).
- Pinned upstream already has `@unsafe Array.fork/join` and atomic operations. **Locally, on 2.0.16, `bend base Array.fork` reports that the name does not exist.** Do not base the initial design on these new operations; they also relax some single-owner guarantees. [Base / unsafe arrays](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/bend2/base.bend#L2280).
- Host effects execute in the event loop, not on the GPU. Adding C/JS effects is supported, but the C API depends on the compiler version and a stable ABI is not promised; custom opaque handles are currently restricted to Base types. This is a route to a future platform backend, not effortless FFI to an arbitrary engine. [Effects](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/guide/EFFECTS.md), [handle limitation](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/WONTFIX.txt#L47).
- File persistence is feasible: `File.read_bytes/write_bytes/read_at/size` also exist locally. The API uses `U32` sizes/offsets and a list of words for bytes, so format versioning, packing, and splitting large worlds into files are engine responsibilities. Do not silently treat this API as unrestricted 64-bit file storage. [Base / File](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/bend2/base.bend#L257).

## Architectural implications — design inferences

Keep mutable chunks under explicit ownership; publish separate immutable packages or meshes for rendering. Split updates by independent chunks, preventing simultaneous writes to neighboring chunks; pass boundary data as a separate snapshot. Do not rely on cheap cloning of the entire world.

Building the initial renderer from voxel surfaces through the existing `bend3d` is reasonable, followed by measuring alternatives. This does not prove that meshes are superior. The upstream shader guide specifically recommends preparing candidates on the CPU for screen tiles and warns about the cost of per-ray traversal of a shared tree, divergent work, and reference counts. CUDA adds the cost of managed-memory page migration over PCIe: M4 results do not transfer to the GTX 1660. [Shader guide](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/guide/SHADERS.md).

Test CPU and GPU as separate modes. Do not promise world size or FPS based on the demo; measure dirty-chunk updates, package construction, rasterization, presentation, and peak memory. For packed voxel words, account for runtime size separately from material bit count: a Bend term representation is not automatically equivalent to a densely packed C `uint32_t`. [Runtime model](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/guide/GUIDE.md#L582).

## Local CUDA verification

The temporary program `/tmp/bend-voxel-gpu-probe.bend` computes `pow2!(16n)` using recursive parallel calls and prints the result through `IO.print`.

- A regular build, `bend ... -o /tmp/bend-voxel-gpu-probe`, produced `65536`, but no `.gpu` file appeared. Forcing `--gpu on` exited with code 1: `bend: --gpu on, but this binary found no GPU device`.
- The machine has no `/usr/local/cuda`; the installed toolkit is at `/opt/cuda`. The compiler supports `CUDA_HOME`. [CUDA selection in the compiler](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/bend2/main.ts).
- Building with the variable set **for that command only**, `CUDA_HOME=/opt/cuda bend /tmp/bend-voxel-gpu-probe.bend -o /tmp/bend-voxel-gpu-probe-cuda`, created a 34296-byte `.gpu` file.
- `/tmp/bend-voxel-gpu-probe-cuda --gpu on` successfully printed `65536` (exit code 0); the binary is linked to `libcuda.so.1` and `libnvrtc.so.13`.

The minimal native CUDA path therefore works on the current machine. This is an installation and backend smoke test, **not a voxel-scene or FPS benchmark**. Bend and the toolkit were not updated, and system settings were not changed.
