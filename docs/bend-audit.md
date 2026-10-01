# Bend idiom and parallelism audit (2026-09-27)

This audit used the then-installed, project-pinned Bend 2.0.32: `bend guide`,
`bend guide shaders`, `bend --help`, and `bend base`. It covers every repository
`.bend` file (including generated assets, tests, laws, and proofs), plus
`src/vulkan/native.cpp`, its header, and the native bridge. Existing uncommitted
palette and bridge changes were part of the baseline and were preserved.

## Stress diagnostic migration

The stress diagnostic now uses `scripts/benchmark_stress.sh` and
`src/stress_tool.bend`. The runner keeps the five-case CLI, raw CSV and stderr,
source and binary hashes, presentation checks, and JSON report fields.
`src/stress_parser.bend` owns timing, view, world, mesh, LOD, body, and lighting
validation. `src/stress_metrics.bend` owns the stress statistics.

The runner reuses the existing Bend benchmark file, path, hashing, and JSON
operations. GNU `timeout` runs each case with a fixed shell redirect program.
Paths and executable arguments travel as positional arguments. Partial logs
remain after a deadline or nonzero exit, and later cases still run.

Binary64 decoding and arithmetic remain in the existing numeric host boundary.
Its behavior needs runtime and reference tests. Proof success does not prove
those foreign operations, world/cache telemetry, process cleanup, or report
parity. This migration adds no production parallelism. The dated measurements
and validation results below remain the original audit record.

## Current idioms

The application already puts simulation, sparse geometry, material colors,
body triangles, and input state in pure Bend. IO stays in typed effects; the
world retains cached geometry across camera and translation changes. Scalar
selectors in `math.bend` avoid generic `Bool.pick` boxing. There are no GPU
bangs: the irregular tree work runs on the CPU and Vulkan rasterizes the scene.
This agrees with the installed shader guide's advice about divergent tree walks
and avoiding CPU/GPU ownership transfers.

The largest mismatch is termination structure. There are 31 explicit `@unsafe`
definitions in `src/` and two in the original world tests. Several are helper
cycles (`build`, `take`, `flood`, `cut`, `faces.hide`, `contains`, local faces,
classification, ray traversal); some express structural recursion indirectly.
Future cleanup should put the decreasing tree/list/fuel parameter first and
combine mutually recursive helpers, or supply a justified finite fuel bound.
Do not hide exhaustion by returning incomplete geometry. Termination cleanup
and a proof of geometric correctness are separate tasks.

The existing `world.assemblies` fork builds one body beside the remaining list.
It exposes useful startup work, but a head-versus-tail list fork does not promise
balanced work: the three large sculptures dominate the small courtyard bodies.
Adding forks at every tree node, face, vertex, or physics body is not an idiomatic
improvement. Each fork adds tasks and a join, and shared `+Data` may add reference
count work. Keep sequential leaf loops and tune coarse tasks against this scene.
The measurements below do not isolate scheduler cost from sharing/allocation.

Other small opportunities are replacing the local append implementation with
Base's equivalent, removing unnecessary `+` annotations in single-use vector
parameters, and fusing the four telemetry list sums. These are not reasons to
rewrite hot paths without measurement. Floating-point reductions must preserve
order; algebraic associativity over real numbers does not apply to F32.

## Complete code inventory and dependency audit

| Files | Independent work / safe parallelization shape | Decision or dependency |
| --- | --- | --- |
| `src/spatial.bend`: `faces`, `faces.go`, `faces.side` | Separate cuboids and their six candidate faces can be generated independently against the same read-only tree; concatenate in the original reverse cuboid/side order. A bounded subtree fork offers coarser tasks. | Tested two fork levels; rejected on the default twelve-thread workload. Per-face forks are finer and not justified. |
| `src/spatial.bend`: `faces.patch`, `faces.old`, `faces.local.tree` | Retained rectangles outside the window and newly generated rectangles inside it are independent. The retained-face map can also be batched contiguously. | Tested fresh/retained fork; rejected. Parallel local subtrees require independent output lists and deterministic concatenation. |
| `src/spatial.bend`: `build.split`, `cut.split`, branch cutting, `count`, `leaves`, `anchored` | Left/right subtrees are independent. Use a depth or size cutoff; for cuts, prune before creating tasks. | Not changed: tree construction and small reductions are much smaller than surface work, and localized cuts are unbalanced. Do not fork every node. Bounds and integer sum overflow assumptions remain mandatory. |
| `src/spatial.bend`: `take`, `flood`, `component`, `faces.hide`, `boxes`, `partition`, `alternate` | `take` could collect independent left/right results and then join them. Tree flattening and partitioning admit separate buffers. | The current flood frontier/visited set and successive face subtractions are stateful folds. Directly forking their recursive calls is incorrect; a redesign needs reference tests for coverage and deterministic component/ID order. `faces.hide` must pass the clipped output to the next subtree. |
| `src/world.bend`: `assemblies`, `meshes`, `meshes.local`, `prepare.bs`, `bodies.step`, body counts | Bodies can be prepared, meshed, and advanced independently; partition large lists into balanced batches. Preparation results need an ordered merge and a removed-cell sum. | Startup already forks. Real cuts generally rebuild one body; per-dirty-body forks add little work. Six-body physics/counts are too small to justify tasks. Revisit using an actual many-fragment workload rather than a synthetic claim. |
| `src/world.bend`: classification, commit/finalize | Connectivity within separate edited bodies can run independently before deterministic ID assignment. | Current classification threads `next` and paired body/job lists; commit is an atomic budget decision. Preserve rollback, order, inherited velocity, and cache identity. |
| `src/showcase.bend`, `src/atelier_assets.bend` | Three comparable sculpture imports/builds/translations can run independently; translation branches are independent. | Generated asset files contain box literals and three `S.build` entry points, not hidden loops. Tested coarse sculpture tasks; rejected after the Vulkan comparison. Five ribs and nine slats stay sequential. |
| `src/mesh.bend` | Independent face-to-six-vertex expansion can use contiguous batches and ordered concatenation. | Each face has little work; avoid one task per triangle/vertex. Faces are cached and only rebuilt after geometry changes. |
| `src/render.bend` | Independent rays would be a good batch; subtree hits could be computed separately and reduced with a stable nearest-hit rule. | There is one pointer ray. Current traversal threads the best hit for pruning and strict-distance tie behavior. A naive parallel rewrite loses that pruning and can change equal-distance material selection. |
| `src/input.bend`, `src/demo.bend` | World physics and camera movement in `advance` are independent; telemetry reductions can be fused. | Tiny jobs. Input events, button latches, reset/cut handling, pending edit samples and IO logs are ordered folds. |
| `src/main.bend`, `src/probe.bend`, `src/platform.bend`, `src/vulkan.bend` | Pure preparation could be reorganized around larger tasks if profiling warrants it. | Frame timing, prepare/classify/surface/commit stages, rendering, event feedback and affine window ownership are dependencies. Do not parallelize ordered IO or move timers across measured work. |
| `src/color.bend`, `src/material.bend`, `src/math.bend`, `src/resolution.bend`, `src/atelier_workload.bend` | Palette entries/channels are independent; scalar vector components are independent. | Small startup/constant work. Gamut fitting is a dependent binary search. Parsing is a short ordered scan. Stable material IDs and palette slot order are ABI contracts. |
| `src/face_audit.bend`, `src/face_profile.bend` | Counts and independent reference comparisons could be batched. | Keep the diagnostic reference sequential and outside measured stages; successive clipping and sequential six-cut world evolution are dependencies. |
| `tests/world.bend`, `tests/face-audit.bend`, `tests/mesh.bend`, `tests/input-aim.bend`, `tests/probe.bend`, `tests/resolution.bend`, `tests/color.bend` | Independent test fixtures may run separately. | Dense/reference loops intentionally remain simple sequential oracles. Never run test executables concurrently with performance measurements. |
| `tests/invariants.bend`, `tests/parallel-profile.bend`, `LAWS.bend`, `PROOF.bend` | New audit support: runtime state invariants, measured production initialization/cuts, and checked safe equalities. | Proofs and runtime tests have distinct scopes below. |

## C++ computations that could move into Bend

The palette and ordinary body triangle expansion already live in Bend in this
checkout. C++ still contains the following pure computations mixed with vector
appends/cache management. This audit identifies migration boundaries; it does
not claim a speedup or change the native ABI to move them.

| Priority | Native functions | Candidate Bend boundary and validation |
| --- | --- | --- |
| 1 | `preview_face`, `near_aim` | Brush cell selection and preview rectangles. Reuse the protected material, cell-center sphere test, local offset, and 20 cm radius rules. Compare selected cells, clipped face positions, and visible output on `atelier-aim` and moving fragments; measure extra bridge traffic. |
| 2 | `shadow_matrix`, `view_position`, `view_depth`, `visible` | World bounds, camera basis, frustum tests and sun projection are pure. Camera formulas duplicate Bend's camera. Pass a small matrix/visibility result; preserve cache refresh rules and column-major packing. Six bodies/eight corners offer little useful parallelism. |
| 3 | `proxy_material`, `proxy_eligible`, `proxy_key`, `proxy_pixels`, `proxy_near_aim`, `proxy_visible`, `proxy_box` | Pure LOD eligibility, projected size, dominant material, and proxy geometry. Preserve negative-coordinate tile rounding, lowest-ID material ties, 80/100-pixel hysteresis and full-resolution shadows. Atelier currently produces no proxies, so its timings alone cannot validate this migration; use native proxy fixtures plus a representative distant-tile workload. |
| 4 | `ring_point`, `glyph`, `hud_text`, `add_hud`, ground `quad` | Aim rings and HUD/ground geometry. Return compact primitive descriptions or cache glyph meshes, then compare pixels and overlay vertex order. Transporting thousands of newly boxed vertices each frame may cost more than the current contiguous native append. |
| Boundary | `body_vertices`, `material_color`, `face_quad` | Palette lookup and copying remain in C++; face expansion also serves native fixtures and the optional independent `VOXEL_VERIFY_BEND_MESH` oracle. Keep that reference when migrating more production work. |

Vulkan resource creation, command recording, synchronization, buffer allocation,
cache mutation, native transport validation, and X11 event delivery are effectful
backend responsibilities. They are not pure computation migration candidates.

## Proof scope and checks

`LAWS.bend` records project rules and safe claims; `PROOF.bend` supplies proofs.
The checked claims cover palette length and anchored/detached material ordering,
stable material IDs/protection, ordered-list append identity/associativity/length,
scalar selector identity, gamut search fuel exhaustion, and resolution
acceptance/rejection. The append lemmas state the join algebra; they do not
prove the unsafe face builder or its custom append wrapper.

Properties depending on `@unsafe` are **not formally proven**. Runtime tests
cover dense cell-by-cell carving and face area, partial material boundaries,
connectivity/disjointness, protected anchors, component motion, body budgets,
mesh winding, native caches, and local/full face coverage. The new invariant
suite compares complete body state after rollback/no-op and cached geometry
after translation. Palette gamut is also checked at runtime: F32 arithmetic and
transcendentals do not normalize to a Boolean proof in this compiler.

`make test` now requires a positive proof verdict, including when Bend returns
exit code zero with `SOME PROOFS FAIL`. `make proof` runs the ordinary gate and
adds `--safe` when the installed CLI advertises it. Bend 2.0.32 rejects `--safe`
as an unknown option. `make proof-verdict` invokes the separate Lean-backed
kernel check; `lean-toolchain` pins its required Lean 4.34.0.

## Reproducing a parallel comparison

Build each revision's `tests/parallel-profile.bend` to a distinct executable,
then run (without other CPU benchmarks/compilations):

```sh
bend tests/parallel-profile.bend -o build/profile-before
# Apply one candidate, then build it:
bend tests/parallel-profile.bend -o build/profile-after
./scripts/benchmark_parallel.sh build/profile-before build/profile-after \
  --runs 4 --threads 1 6 12 --output build/parallel
```

The driver times real six-body initialization and the six fixed Atelier cuts.
The independent full-face audit checks each edited surface after timing. The
runner warms both executables, alternates AB/BA order, retains every raw row,
checks every non-timing count against the baseline, and reports medians of
initialization and summed six-cut stages. It records binary SHA-256 hashes.
`edit` is the per-run sum of carve/connectivity/surface/finalize, not the sum of
stage medians. This is a CPU experiment, not evidence of a GPU speedup.

Both benchmark drivers now compile `src/benchmark_tool.bend` with pinned Bend
2.0.34 and run its parsing, counter checks, F64 statistics and reports. The
shell entry points only compile and launch it; Linux GNU core utilities provide
directory, hash and formatting effects. The profiler arguments, warmups,
alternating order and JSON/CSV field order are retained. Timings use the existing
F64 effect, including compensated sums and shortest round-trip decimal output;
profiler timing/count words remain U32. Initialization retains arbitrary integer
input until the F64 division. A separate mode of the existing numeric effect
retains positive infinity for overflowing benchmark medians and decimal
round-trip candidates; schedule F64/F32 modes still reject nonfinite values.
The process effect supports a positive timeout up
to 4,294,967 seconds; larger timeouts fail explicitly before multiplication into
milliseconds. Faces outputs are relative to the repository; parallel outputs
and executable paths are relative to the invoking directory.
The Base process effect caps combined captured stdout/stderr at 1 MiB, well
above the fixed six-row profiler protocol. The frozen byte and negative-input
checks run in `make test`; they qualify no performance improvement.

Follow headless results with all five Vulkan stress cases and geometry checks
before retaining a candidate. Use A/A comparisons when gains are close to noise.

## Headless measurements

Hardware: AMD Ryzen 5 1600, six physical cores / twelve logical threads, Linux
x86-64, Bend 2.0.32 native CPU execution. Each entry is a median of four measured
runs per binary after warm-up, with alternating AB/BA order. Times are milliseconds.
The baseline is the original dirty checkout, not repository HEAD. The raw records
and binary hashes are under `build/bend-audit/`.

| Experiment | Threads | Init before | Init after | Six edits before | Six edits after | Decision |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Full faces, two fork levels | 1 | 45.997 | 49.023 | 79.137 | 80.441 | Rejected |
| Full faces, two fork levels | 6 | 32.199 | 29.100 | 83.307 | 81.727 | Rejected |
| Full faces, two fork levels | 12 | 33.211 | 42.316 | 86.148 | 84.456 | Rejected |
| Fresh/retained face fork | 1 | 49.171 | 45.961 | 79.640 | 80.892 | Rejected |
| Fresh/retained face fork | 6 | 34.323 | 33.462 | 83.672 | 102.430 | Rejected |
| Fresh/retained face fork | 12 | 35.035 | 32.125 | 83.686 | 113.414 | Rejected |
| Three sculpture builds | 1 | 52.757 | 48.787 | 79.726 | 79.617 | Rejected |
| Three sculpture builds | 6 | 31.581 | 31.048 | 86.429 | 84.616 | Rejected |
| Three sculpture builds | 12 | 35.212 | 31.529 | 85.862 | 85.267 | Rejected |

The full-face fork regressed default twelve-thread initialization by 27.4%.
The fresh/retained fork regressed six-edit time by 35.5% at twelve threads (and
22.4% at six). Both production changes were reverted. Their source snapshots
remain in `build/bend-audit/spatial-faces-parallel.bend` and
`build/bend-audit/spatial-patch-parallel.bend` for local review.

The sculpture build fork reduced headless twelve-thread startup by 10.5%, while
edits remained similar. One- and six-thread headless runs also looked acceptable,
but the Vulkan comparison below did not establish a reliable overall gain. This
candidate was reverted too; its snapshot is
`build/bend-audit/showcase-assets-parallel.bend`. No new production parallelization
is retained. The existing startup body-meshing parallelism is unchanged.

## Vulkan comparison and final decision

The promising sculpture candidate was compared against the baseline in four
AB/BA pairs, each running all five cases at 640x360 with 30 warm-up and 180
measured frames, immediate presentation, and six real cuts in the carve case.
All 40 case runs passed correctness/cache/shadow checks. Both executables used
the same native library and shaders. The following are medians across runs,
in milliseconds. Raw per-frame samples and reports are under
`build/bend-audit/stress-{baseline,candidate}-{0..3}/`; the aggregate is
`build/bend-audit/stress-comparison.json`.

| Case | Init before | Init after | Mean frame before | Mean frame after | Frame p95 before | Frame p95 after |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| atelier | 35.469 | 32.897 | 0.622 | 0.670 | 1.106 | 1.149 |
| atelier-night | 32.692 | 32.309 | 0.644 | 0.659 | 1.061 | 1.100 |
| atelier-camera | 33.694 | 37.673 | 0.683 | 0.685 | 1.107 | 1.228 |
| atelier-aim | 31.883 | 31.391 | 0.693 | 0.709 | 1.095 | 1.299 |
| atelier-carve | 36.252 | 35.500 | 1.177 | 1.190 | 1.429 | 1.432 |

The static-frame median mean increased 7.7%; camera initialization also increased
in these samples. Carve CPU stages remained similar (83.460 -> 82.347 ms summed
over six edits). Window/compositor timing is noisy, and these measurements do
not establish that scheduling caused every observed difference. They do fail to
establish non-regression on real workloads, so the conservative decision is to
keep sequential sculpture generation. A future attempt needs longer, interleaved
runs and an A/A noise control before claiming an overall gain. No A/A control was
needed to accept a change here because no candidate was accepted.

An extra candidate carve run with `VOXEL_VERIFY_BEND_MESH=1` passed the native
vertex oracle. The sculpture experiment also passed an exact comparison of every
ordered cuboid/material against the original sequential generator before it was
reverted. Formal proof success does not replace these runtime checks.

## Final validation

- `bend PROOF.bend`: **ALL PROOFS CHECK** for 16 laws.
- `bend PROOF.bend --verdict` and `make proof-verdict`: **ALL PROOFS CHECK** with Lean 4.34.0.
- `--safe`: unsupported by Bend 2.0.32; the proof script enables it if a future CLI advertises it.
- `make test`: Bend runtime suites, native geometry/cache tests, and eight Python tests passed. The gate was also tested against a simulated zero-exit `SOME PROOFS FAIL` and correctly rejected it.
- `make build`: passed after restoring the original production algorithms.
- Final five-case Vulkan suite: passed, including the six cuts, mesh invalidation, unchanged-frame reuse, and shadow refresh checks (`build/bend-audit/final-stress/report.json`).
- No new `@unsafe` definitions, native ABI changes, or production parallelization remain from this audit. Earlier user changes are preserved.

Lean 4.34.0 is installed and selected as the local default, with a repository
`lean-toolchain` pin. The official GitHub release asset was verified against its
published SHA-256 (`caaa98356098c85dc0fcbbd28e1ec66f39eb6551829972b752ff20e1286b646b`).
The existing Lean 4.19.0 and 4.32.0 installations were preserved and their Elan
registrations repaired; both still report their original versions.
