# Reusing boundary event counts

The region DDA now carries each already computed axis boundary time into `Axis.advance`. A moving axis whose time equals the selected region exit can use its full integer event limit. An explicit selector skips `Axis.count` on that branch. Reconstruction still uses `Axis.advanced`, preserving crossing flags, previous cells, and X/Y/Z face priority.

The change is retained. CPU12 complete-window median frame time decreases by 2.9% in the first batch and 3.3% in a longer repeat. Nine of ten paired processes favor the candidate. CPU1 and CPU6 also improve in both batches. These results concern the experimental comparison renderer. GPU and carved-cube gains remain inconclusive.

## Arithmetic and formal scope

The shortcut requires `low <= cell < high <= 16777216` and exact F32 time equality. The coordinate cap keeps all relevant integer planes exactly representable. Stationary axes return before evaluating the shortcut. Other axes and larger coordinates use the existing estimate and correction algorithm. The preceding floor-removal optimization remains intact.

The cap is necessary. With `origin=0`, `delta=1`, `low=cell=16777217`, and `high=16777218`, the boundary expression produces `16777216`. Counting uses a different rounded endpoint and returns zero rather than the integer limit one. The executable sweep records this counterexample.

The new laws prove true selection, exact false fallback, reconstruction given an explicit count-equality premise, and exact fallback when the coordinate guard is rejected. The stationary law accepts the new ignored argument. Both [ordinary](dda-boundary-data/proof-check.txt) and [kernel checking](dda-boundary-data/proof-verdict.txt) pass. These laws do not prove the generic F32 arithmetic premise.

The [arithmetic verifier](dda-boundary-data/property.bend) calls the frozen actual `Axis.next` and `Axis.count`. Its 2,247,951 checks cover small regions, narrow regions around the precision cap and large U32 coordinates, every exponent field with five mantissas and both signs, neighboring times, ties, signed zeros, subnormals, infinities, and NaNs. It finds zero mismatches in 487,852 guarded reuses and 13,183 disagreements outside the cap. Every count limit is at most sixteen. The [CPU](dda-boundary-data/property-cpu.txt) and [CUDA-enabled forced GPU](dda-boundary-data/property-gpu-run.txt) `Scan!()` runs produce identical counters. The delegate's first build used CPU fallback for dispatch; the parent rebuilt with `CUDA_HOME=/opt/cuda` and required `--gpu on`.

The [advancement verifier](dda-boundary-data/advancement.bend) compares complete results from the candidate and frozen baseline. [All 260,694 axis samples and 5,777 region crossings](dda-boundary-data/advancement-parent.txt) match exact depth bits, cells, previous cells, flags, and directions. Its count limits are at most eight. Coverage includes malformed narrow bounds, stopped sentinel equality, moving sentinel equality, two-axis and three-axis ties, all six face directions, and negative exits through coordinate zero. Both published verifiers were rebuilt and executed after adjusting only their import paths.

These finite checks do not exhaust all F32 combinations or wider event limits. No unsafe proof, mock algorithm, or conventional test suite was added. CUDA was the available physical GPU lane. Metal and future WebGPU performance were not measured.

Seven full scans compare region traversal with unit DDA on opening, cut, cube, carved cube, inside, axis-aligned, and opposite views. [All 1,835,008 rays](dda-boundary-data/verification.txt) match exact surfaces. The candidate CPU12 and GPU fork-six images match the frozen baseline and unit reference byte for byte in every view. Opening exports also match on CPU1, CPU6, and GPU fork seven. [Image hashes](dda-boundary-data/image-hashes.txt) identify the exports. The actual native window captures have [zero pixel differences](dda-boundary-data/window-parity.txt).

## Complete-window measurements

The unchanged `scripts/dda_ab.bend` runs five process pairs per batch in alternating AB/BA order. Each process warms four frames. The interval includes rendering, native X11 presentation, and image disposal. Scene construction is excluded. The driver requires successful processes and the requested frame count. Release timing does not overlap compilation, proofs, arithmetic checks, image checks, or profiling.

Both sides use Bend 2.0.34 release builds with CUDA enabled, identical scene inputs, and identical settings within each pair. The machine has a Ryzen 5 1600 with six physical cores and twelve logical CPUs, and a GTX 1660. CPU1, CPU6, CPU12, and GPU fork depths six and seven are separate measurements. Desktop applications remain active. Per-batch load captures and complete process output accompany the samples.

The initial same-binary control had medians 111.1875 and 113.25 ms/frame across five pairs. `updatedb` was active during that control. This roughly 1.9% separation illustrates session variation and is not an implementation comparison.

| Configuration | Measured frames per process | Baseline median and range, ms/frame | Candidate median and range, ms/frame |
| --- | ---: | ---: | ---: |
| [CPU12, fork 6](dda-boundary-data/cpu12.tsv) | 32 | 105.875, 104.75 to 106.15625 | 102.78125, 101.90625 to 105.84375 |
| [CPU12 repeat, fork 6](dda-boundary-data/cpu12-repeat.tsv) | 64 | 106.28125, 105.609375 to 106.578125 | 102.796875, 102.265625 to 106.046875 |
| [CPU1, fork 0](dda-boundary-data/cpu1.tsv) | 16 | 704.6875, 700.3125 to 712.1875 | 676.625, 673.375 to 687.1875 |
| [CPU1 repeat, fork 0](dda-boundary-data/cpu1-repeat.tsv) | 16 | 709.875, 706.0625 to 716.25 | 681.25, 675.9375 to 683.5625 |
| [CPU6, fork 6](dda-boundary-data/cpu6.tsv) | 32 | 147.90625, 147.5 to 149.75 | 142.6875, 140.4375 to 145.90625 |
| [CPU6 repeat, fork 6](dda-boundary-data/cpu6-repeat.tsv) | 64 | 143.28125, 142.0 to 148.453125 | 139.6875, 138.234375 to 142.625 |
| [GPU, fork 6](dda-boundary-data/gpu6.tsv) | 8 | 548.25, 532.625 to 552.875 | 537.5, 529.875 to 547.0 |
| [GPU, fork 7](dda-boundary-data/gpu7.tsv) | 8 | 537.125, 519.875 to 544.25 | 524.625, 511.375 to 533.75 |
| [GPU repeat, fork 7](dda-boundary-data/gpu7-repeat.tsv) | 16 | 515.0625, 509.8125 to 531.8125 | 514.375, 500.0625 to 520.0625 |
| [Carved cube, CPU12, fork 6](dda-boundary-data/carved-cpu12.tsv) | 64 | 17.453125, 17.0 to 17.546875 | 17.359375, 17.265625 to 17.609375 |

CPU1 improves in all ten pairs, with separate ranges that do not overlap in either batch. CPU6 also improves in all ten pairs. CPU12 improves in four initial pairs and all five repeat pairs. Its ranges overlap because each batch contains one slower candidate sample. The [paired changes](dda-boundary-data/paired-summary.tsv) retain those samples.

GPU fork seven has a 2.3% lower initial median and only a 0.13% lower repeat median. It favors the candidate in eight of ten pairs, but its repeat gap is small relative to its spread. GPU fork six has only one batch and overlapping ranges. No repeatable GPU gain is established. The carved cube has a 0.54% median difference and favors the baseline in three of five pairs. Its result is inconclusive.

Separate CPU profiles contain twelve frames each, including warmup and initialization. [Baseline](dda-boundary-data/baseline-gprof.txt) and [candidate](dda-boundary-data/candidate-gprof.txt) profiles put region lookup first and axis advancement second. Both profiles record 45,897,396 region lookups, 128,255,004 axis advances, and 42,751,668 region crossings. Their absolute profile times are not speed measurements. The [compiled candidate branch](dda-boundary-data/candidate-axis-assembly.txt) bypasses the estimate and correction arithmetic before reaching the unchanged reconstruction. Separate GPU stage diagnostics also place most time in rendering. Those diagnostics overlap other verification work and do not establish a stage speedup.

## Reproduction

Frozen release binaries, emitted C, original source copies, native window captures, and the decision trail remain in `.audit/dda-boundary/`. Published baseline and candidate DDA snapshots change only root-relative imports. The published verifiers import those snapshots and the unchanged shared engine modules. [Source hashes](dda-boundary-data/source-hashes.txt), [release build hashes](dda-boundary-data/build-hashes.txt), and [installed hashes](dda-boundary-data/installed-hashes.txt) identify the checked artifacts. The [patch](dda-boundary-data/candidate.patch) includes the three engine and proof files.

```sh
bend PROOF.bend
bend PROOF.bend --verdict
bend docs/dda-boundary-data/property.bend -o build/dda-boundary-property
build/dda-boundary-property --gpu off --threads 1
CUDA_HOME=/opt/cuda bend docs/dda-boundary-data/property.bend -o build/dda-boundary-property-gpu
build/dda-boundary-property-gpu --gpu on --threads 1 -- --dispatch
bend docs/dda-boundary-data/advancement.bend -o build/dda-boundary-advancement
build/dda-boundary-advancement --gpu off --threads 1
make build/dda-compare build/dda-ab
build/dda-compare --gpu off --threads 12 -- --verify-steps
bash .audit/dda-boundary/run-matrix.sh cpu12-reproduction 12 off 6 64
```

Model the Domain kept the existing `Region` and `Advance` records. Laziness Protocol favored one selector and existing boundary times over a new record or repeated division. Exhaust the Design Space compared three independent sketches and an independent judge before selecting that shape. Separate Before Serializing Shared State gave each writer a separate directory. Type System Discipline kept the formal reconstruction premise explicit. Sequence Work into Verifiable Units required correctness before timing. Prove It Works required actual arithmetic, surfaces, and native window parity. Explain the Number requires the repeated complete-window evidence above.

Comment review found zero deletions, restored comments, refactor flags, reruns, fixes, encoding offers, encodings, or open constraints. Three architecture sketches preceded implementation; no comment-driven architecture work was needed.

The [independent evidence review](dda-boundary-data/review.md) used the configured `gpt-6.1-sol` model and approved the change with no flags. It reconciled all 100 measured processes, checked artifact identities, and confirmed correctness and timing preceded installation. The finite arithmetic scope and inconclusive GPU results remain disclosed above. The canonical trail is `.audit/dda-boundary/decisions.tsv`. This checkout has no Git metadata, so delivery is local.
