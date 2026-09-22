# Voxel ray-casting prototype: retain the rasterizer

The direct voxel DDA prototype was **5.4–38.2× slower** than the existing
rasterizer across the measured scenes and backends, even after removing closure
allocation from its ray loop. Do not replace the production renderer with this
implementation. The experiment does not rule out a different voxel layout or
acceleration structure.

Prototype code is preserved on local branch **`prototype/voxel-ray-casting`**.
The production renderer, simulation, and launch default were not changed.

## Final measurements

Bend 2.0.25; Ryzen 5 1600; GTX 1660; 640 × 360; two CPU workers on both backends.
Values are median-of-run-medians in milliseconds, including preparation/render-cell
disposal for the raster path and retirement of the previous image for both paths.

| Scene | CPU raster | CPU DDA | CUDA raster | CUDA DDA |
| --- | ---: | ---: | ---: | ---: |
| Initial, 4,640 voxels | 2.97 | 23.35 | 9.03 | 100.16 |
| Falling, replay tick 408 | 4.06 | 21.86 | 11.40 | 70.09 |
| 64 fragments, 512 voxels | 5.01 | 191.54 | 9.45 | 131.60 |

[Final report: raw samples, per-run p95, hardware and source/binary hashes](validation/ray-casting/report.json).
There were four rounds, reversing configuration order on alternate rounds,
with five warm-up and twenty measured frames per process: 48 processes and
960 measured frames. Correctness checks and compilation did not overlap timing.
No clocks were locked and the desktop machine was not isolated.

These are **fixed-scene headless frame costs**, not interactive FPS or acceptance
results. Both variants omit HUD, brush overlay and presentation. Fixture
construction, physics, carving, meshing, and final process teardown are outside
the timed frame. Falling bodies are frozen at the same replay instant in both
variants; the stress scene has 64 disconnected 2 × 2 × 2 bodies after 0.15 s of
falling. The landed scene (tick 540) is an additional correctness control.

DDA retains its immutable voxel snapshot between frames. Snapshot conversion and
body-bound extraction are measured separately: 0.58–3.99 ms across timed
processes (median 2.26 ms). Initial device access is in the retained warm-up
samples. Destruction would require refreshing this representation. Bounds are
extracted from the existing meshes, so this prototype does **not** demonstrate
elimination of meshing cost. These favorable reuse conditions still did not
produce a rendering win.

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

The initial four-round experiment is retained on the prototype branch at
`docs/validation/ray-casting-initial/` (commit `c969afd`). The two implementation
experiments ran sequentially; the table above uses only the final interleaved
raster/DDA experiment. All sixteen images are
[identical before and after that refactor](validation/ray-casting/refactor-image-checks.json).
[Compiled source/binary fingerprints](validation/ray-casting/fingerprint-checks.json)
were checked after timing.

Remaining structural costs include testing every body's bounds for every ray,
a binary-tree read at each visited cell, divergent traversal, and constructing
the output image. At 64 bodies, the unculled upper bound is 14.7 million body
candidates per frame. Stage timings do not isolate the contribution of each
cost. A future experiment should change candidate culling and data layout
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

The prototype branch contains code, raw nonempty logs, PNG/tree dumps and both
experiments. To inspect it without switching the current working tree:

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
