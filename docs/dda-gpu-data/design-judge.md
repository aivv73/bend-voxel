Recommend runner 2 as the base for a square-contiguous versus interleaved-weave sweep. It changes pixel ownership and restores spatial placement at existing joins.

I am gpt-6.1-sol with xhigh reasoning effort. I read all three `design.md` and `sketch.bend` packages, shared `frame.md` and `grounding.md`, baseline screen stdout, A/A evidence, and the installed shader guide. This review performed no writes, delegation, or execution. Scores assess design quality; all proposed proofs remain open and sketches are unchecked.

| Criterion, 0..4 | [Runner 1](/home/aivv/Документы/projects/bend-voxel-main/.audit/dda-gpu/designs/1/design.md) | [Runner 2](/home/aivv/Документы/projects/bend-voxel-main/.audit/dda-gpu/designs/2/design.md) | [Runner 3](/home/aivv/Документы/projects/bend-voxel-main/.audit/dda-gpu/designs/3/design.md) |
|---|---:|---:|---:|
| Exact spatial semantics and provable assignment | 4 | 4 | 4 |
| Portable reusable ownership | 4 | 4 | 4 |
| Real distribution change and measurable work | 1 | 4 | 4 |
| Small maintainer interface | 3 | 3 | 2 |
| Reproducible comparison without label drift | 3 | 4 | 3 |
| **Total** | **15/20** | **19/20** | **17/20** |

Runner 1 has the smallest scheduling change and immediate canonical assembly. Its sibling permutations retain identical square ownership. They provide optional launch-order controls, but cannot satisfy the second assignment-shape requirement.

Runner 2 supplies bounded forward/inverse coordinate maps and a concrete weave recurrence. Native `Pix/Qua` remain the production representation. Its design derives 114,660 extra quadrant opens and allocations each at fork six, plus substantial possible `Four` construction overhead. These are algorithmic counts, not timings. Sequential weave continuations may erase any balancing benefit.

Runner 3 provides another real ownership shape through row or column batches. Its job-matched comparisons are useful because equal numeric depths have different work counts. Its indexed binary forest, transposes, equality transports, and final serial packing impose the largest implementation and maintenance burden. Keep it archived as a distinct alternative; do not graft that machinery into runner 2.

Useful grafts are runner 1’s scalar hot arguments, separate control/candidate binaries, and reporting control whose exports first match the frozen binary. Take runner 3’s explicit jobs, pixels-per-job, and assembly-cost accounting. The Laziness Protocol favors finite assignment/depth types and typed scenes while keeping generic verification trees outside production. Explain the Number requires assembly costs and observed execution evidence beside every comparison.

The [baseline screen](/home/aivv/Документы/projects/bend-voxel-main/.audit/dda-gpu/baseline-screen-stdout.txt) puts GPU depths six through nine around 514..520 ms/frame in one process per depth. Recorded depth-four-through-nine exports have identical hashes. The [five-pair A/A TSV](/home/aivv/Документы/projects/bend-voxel-main/.audit/dda-gpu/aa-gpu7.tsv) has medians 498.25 and 509.125 ms/frame, approximately 2.2% apart, with overlapping ranges. Neither establishes a winner or a universal acceptance threshold.

Before implementation, revise the selected package to commit to these gates:

1. Define one finite schedule and one resolved scene consumed by draw and reporting. Unpack resources at the boundary; preserve scalar hot parameters and borrowed Grid reads.
2. Specify contiguous and interleaved ownership at intermediate depths. Depth nine gives identical ownership. Inspect generated forks and terminal coordinates; logical tasks are not physical GPU lanes, and deeper forks may execute sequentially.
3. Scope formal claims to bounds, both assignment inverses, canonical weave placement, complete coverage, and retained-scene identity. Avoid arbitrary path codecs and broad configuration theorems. Keep claims in `LAWS.bend`; require `bend PROOF.bend` before committing.
4. Derive each endpoint’s argv independently. Validate actual parsed scene, schedule, warm count, measured count, completed frames, and successful exit. Require reporting-control exports to match the old frozen binary before timing.
5. Preserve accepted floor/boundary behavior, Grid, rays, shading, and world state. Require exact full-frame exports, native X11 evidence, CPU1/6/12 validation, separate GPU depth4..9 measurements, complete-window assembly/presentation/disposal, five alternating pairs, and an independent repeat before changing defaults.

Reject unsafe arrays, backend constants, and premature default changes. The guide’s flat-leaf advice permits one later controlled sequential-unrolling experiment; its published hardware timings cannot select our winner.
