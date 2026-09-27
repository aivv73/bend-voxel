# Voxel ray-casting prototype: retain the rasterizer

The direct voxel DDA prototype explored a different rendering path. Its correctness and image comparisons did not justify replacing the production rasterizer. The experiment does not rule out a different voxel layout or acceleration structure.

Prototype code is preserved on local branch **`prototype/voxel-ray-casting`**.
The production renderer, simulation, and launch default were not changed.

## Implementation and one corrective iteration

The prototype consumes the owner array into an immutable binary tree, transforms
each ray into each candidate body's local lattice by subtracting its vertical
offset, clips to body bounds, and walks cells with an 84-step DDA bound. A cell
only hits when its owner matches the candidate body. It retains the nearest hit
across bodies, intersects the finite floor separately, and uses the same flat
face colors. Work forks down to 4 × 4 pixel tiles on CPU or CUDA.

The first version used `W.vec` continuations to unpack slab and color results.
Generated C showed heap-allocated closures and reference-counted ownership in
the ray/body loop. Replacing those with direct helpers made the tracing path
compile into native flat functions. Grid reads use `term_peek`; the grid getter
already borrowed in the first version, so per-node atomic counting is not an
established explanation of the residual cost. See
[generated-code excerpts and hashes](validation/ray-casting/generated-code-evidence.json).

The implementation variants produced [identical images](validation/ray-casting/refactor-image-checks.json). [Compiled source/binary fingerprints](validation/ray-casting/fingerprint-checks.json) were checked during validation.

Remaining structural costs include testing every body's bounds for every ray,
a binary-tree read at each visited cell, divergent traversal, and constructing
the output image. At 64 bodies, the unculled upper bound is 14.7 million body
candidates per frame. Their individual contribution was not isolated. A future experiment should change candidate culling and data layout
(e.g. per-tile candidates and packed voxel columns) before another renderer swap
is considered.

## Correctness and image differences

- All 14,424 sampled camera/axis comparisons pass across four scenes.
- [Thirteen analytic checks](validation/ray-casting/analytic-checks.txt) pass,
  including non-cell-aligned translation, nearest-body ordering, owner filtering,
  six signed axes, parallel misses, corner entry, occupied origins, and finite floor.
- [Exhaustive checks](validation/ray-casting/full-checks.json) compare 921,600
  pixel rays with the existing face picker. Falling, fragmented and landed scenes
  each have zero disagreements. The initial scene has **two**; its strict check
  intentionally remains exit code 1.
- CPU/CUDA images match byte-for-byte within each renderer in all four scenes.
  The main workspace's `make test` also passes, including 10 Python tests.

The [two strict oracle disagreements](validation/ray-casting/edge-cases.csv) are
at pixels (376, 268) and (407, 139). The face picker reports points at
x = 1.3000078 and y = 2.4000082 respectively, just outside the exact x = 1.3
pillar boundary and y = 2.4 roof boundary. Its face-extent tolerance accepts those
points; exact voxel traversal misses them. The oracle tolerance was not relaxed
to make the check pass.

Raster and DDA images are **not pixel-equivalent**: 2,295 initial, 1,326 falling,
2,540 fragmented, and 2,361 landed pixels differ (0.58–1.10% of each image).
[Color-pair counts](validation/ray-casting/pixel-differences.json) show that floor
versus sky accounts for most differences in the first three scenes. Landed
material differences are consistent with overlapping/coincident surfaces, but
all raster coverage and tie-breaking differences have not been resolved.
This is another reason the prototype is not a production replacement.

| Scene | Existing raster | Voxel DDA |
| --- | --- | --- |
| Initial | [Image](validation/ray-casting/initial-cpu-raster.png) | [Image](validation/ray-casting/initial-cpu-dda.png) |
| Falling | [Image](validation/ray-casting/falling-cpu-raster.png) | [Image](validation/ray-casting/falling-cpu-dda.png) |
| Fragmented | [Image](validation/ray-casting/64-fragments-cpu-raster.png) | [Image](validation/ray-casting/64-fragments-cpu-dda.png) |
| Landed | [Image](validation/ray-casting/landed-cpu-raster.png) | [Image](validation/ray-casting/landed-cpu-dda.png) |

## Reproduce

The prototype branch contains code and validation artifacts. To inspect it without switching the current working tree:

```sh
git worktree add --detach /tmp/bend-voxel-ray prototype/voxel-ray-casting
cd /tmp/bend-voxel-ray
make prototype-ray
```

Bend 2.0.25 and CUDA are required; no display server is needed. Subsequent runs
need a fresh output directory, for example
`make prototype-ray RAY_ARGS='--output build/repeat'`.
See `src/prototype/README.md` on that branch for the analytic and exhaustive
checks, including the documented nonzero initial-scene oracle result.

The prototype started from `65d7197`, before the uncommitted lookup optimization.
Both compared renderers use the same world source. `body.find` is only involved
in untimed fixture editing here; it is not in either timed rendering path.
