# Vulkan renderer ownership

The renderer was moved from bend-vulkan into this repository's `vulkan/`
directory. It imports the owning repository's voxel, material, Atelier and
reference-rendering modules directly. There is no nested bend-voxel dependency.

The existing Bend-native renderer, root laws and default Makefile targets are
unchanged. Vulkan-specific laws and proofs remain in `vulkan/LAWS.bend` and
`vulkan/PROOF.bend`; `make vulkan-proof` checks them separately.

The Vulkan library is a submodule at `deps/bend-vulkan`, pinned to
`753f8f49549b6eb17c6e609346fed5a580bdc8a1`. That commit removes the library's reverse
bend-voxel dependency. Its nested bend-collections pin supplies the same U64
implementation to both the API and this renderer. Publish the library commit
before publishing a consumer commit that references it.

The source renderer originally used bend-voxel revision
`cdfd92d356229c5de5f4aaddd358f15ec3686dd4`. The destination checkout was at
`c48f2e25376c4c377e706e2201aaa82186c6b963`; its root voxel/rendering modules are
unchanged from that original reference. The verifier no longer demands a fixed
revision of its own repository. Reference and production checks hash the actual
owning source files instead.

## Validation after relocation

Run from the bend-voxel root:

- `bend PROOF.bend`: passed.
- `bend vulkan/PROOF.bend`: passed.
- `python3 vulkan/tools/build_shaders.py --check`: passed.
- `python3 vulkan/tools/check_measurement.py`: passed.
- `python3 vulkan/tools/check_timing.py --sanitize`: passed.
- `python3 vulkan/tools/check_appearance_gpu.py`: passed, including the validation run.
- `python3 vulkan/tools/check_reference_lighting.py`: passed.
- `python3 vulkan/tools/check_window.py --product --isolated-display`: rebuilt the
  application at its new path and passed quiet startup, carving, exact reset and
  suspended close.

All migrated Bend imports resolve inside this repository and its dependencies.
The 75 moved Bend/C/GLSL source bodies match the original library revision
`65c79f6a70f8b6c9069bbee108d97540d464bba5` after excluding import declarations.
Production source hashing includes this repository's voxel modules and the
pinned Vulkan library, while excluding generated build artifacts.

The library's proofs and import-boundary check passed after removing the
consumer and its submodule. The earlier full library sanitizer run, and its run
with all voxel files absent, are recorded in
[the library split report](../../deps/bend-vulkan/.audit/library-split.md).

This relocation did not repeat the entire consumer suite. The earlier production
sanitizer compilation was stopped during a long Clang compile; it remains an
incomplete optional gate. No compiler flags, checks or tolerances were weakened.
The full verifier remains available as `python3 vulkan/tools/verify.py`, with
`--sanitize`, `--presentation` and `--isolated-display` options.

Existing logs and captures moved with the renderer into ignored `vulkan/build/`.
Only `move-*` logs describe the post-relocation runs; older logs retain their
original source paths.
