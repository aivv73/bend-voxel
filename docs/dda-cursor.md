# Per-ray subtree cache evaluation

The depth-six ray cache is rejected. On the primary CPU12 configuration, the revised prototype increases complete frame time from **111.75 to 243 ms**, a **117.45% regression**. All five alternating process pairs regress. The [raw samples](dda-cursor-data/cpu12.tsv) have non-overlapping ranges, 110.4375–113.5 ms for the baseline and 242.125–274.71875 ms for the candidate. The original `dda.bend`, `LAWS.bend`, and `PROOF.bend` remain unchanged. The [prototype](dda-cursor-data/candidate-dda.bend) and [diff](dda-cursor-data/candidate.patch) are preserved for inspection.

This evaluates the first candidate from the upstream DDA investigation, retaining a subtree between region crossings. It changes the experimental region DDA used by `scripts/dda_compare.bend`. The production face renderer and frame decomposition are unchanged.

## Shape and ownership

The cache retains one subtree after at most six cyclic X/Y/Z splits. `Seed` carries the exact leaf `Region`, subtree, next split axis, absolute lower corner, and span. A contained next cell uses the retained subtree; an in-world cell outside those half-open bounds refreshes from the root. Containment is checked before unsigned coordinate subtraction. The anchor bounds never replace the exact leaf bounds used by `Crossing.region`.

Three independent designs considered full ancestry arrays and bounded subtrees. The [selected design](dda-cursor-data/design.md) combines one small anchor with a fused prefix descent and initial region lookup. The full ancestry arrays would initialize 128 tree slots and 1,024 metadata slots per ray; their performance was not measured. Cache depth is a private tuning definition, not a backend assumption. Unit traversal, event counting, simultaneous crossings, face priority, and inside-solid exit behavior retain their original algorithms.

The first implementation passed correctness checks but retained and dropped the shared world root at each query. Its [CPU12 batch](dda-cursor-data/attempt-1/cpu12.tsv) increased frame time from 133.4375 to 375.9375 ms; [CPU1](dda-cursor-data/attempt-1/cpu1.tsv) increased from 850.75 to 1,101.5 ms. These are separate batches with their own load and build artifacts, not a controlled comparison with the revised implementation.

The revision makes `Cursor{seed,grid}` one private affine ray state. Cache hits transfer the root unchanged. `Trace.cached` reconstructs `Region` directly rather than retaining a seed whose other fields must then be dropped. Actual emitted C has no `term_keep` calls in the hot trace loop, and suffix traversal uses borrowed `term_peek`. Cache refresh still retains the root once and consumes/copies every prefix branch through `ctr_take`. The [ownership report](dda-cursor-data/ownership-report.txt) gives the exact functions and line locations in `.audit/dda-cursor/candidate2.c`.

## Work and remaining cost

Counters cover one real opening frame. The [baseline](dda-cursor-data/baseline-counters-frame.tsv) and [candidate](dda-cursor-data/candidate-counters-frame.tsv) diagnostic binaries export the same image bytes as their release builds. Each independent native window counter run renders four warmups and one measured frame; [baseline](dda-cursor-data/baseline-counters-window.tsv) and [candidate](dda-cursor-data/candidate-counters-window.tsv) totals are exactly five times their respective frame counters.

| Work per opening frame | Baseline | Revised cache |
| --- | ---: | ---: |
| Root lookups / seed selections | 3,740,969 | 871,690 |
| Suffix branches | 59,823,748 | 37,448,694 |
| Cache prefix branches | 0 | 5,159,380 |
| Total tree branches | 59,823,748 | 42,608,074 |
| Cache hits after crossings | — | 2,869,279 |
| Cache refreshes after crossings | — | 609,546 |
| Region crossings | 3,562,639 | 3,562,639 |
| Axis advances | 10,687,917 | 10,687,917 |
| Plane predicate evaluations | 17,952,681 | 17,952,681 |
| Final hits / misses | 178,330 / 83,814 | 178,330 / 83,814 |
| Pixels / image quads | 262,144 / 87,381 | 262,144 / 87,381 |

Including prefix work, branch visits fall by **28.78%**. This does not reduce complete frame time. The separately instrumented [baseline profile](dda-cursor-data/baseline-gprof.txt) attributes 42.73% of exclusive CPU samples to tree lookup, 25.11% to axis advancement, and 16.74% to region crossing. In the [revised profile](dda-cursor-data/candidate-gprof.txt), suffix lookup takes 27.01%, axis advancement 20.49%, crossing 11.27%, query dispatch 6.64%, and seed selection 5.75%. `term_drop` and `span_fade` together account for 14.15%.

Both profiles render twelve complete native frames on CPU1, including four warmups. Recorded `term_drop` calls increase from 4,703,412 to 119,570,880. The emitted prefix descent and these call counts identify added ownership work; increased contention on a shared root is an inference, not a measured contention rate. [Symbol bindings](dda-cursor-data/symbols.tsv) map profile functions to Bend definitions. Absolute sampled times cannot establish a speedup because profiling and background load differ. No profiler or counter hooks run in the release measurements.

## Complete-frame measurements

The unchanged [Bend A/B driver](../scripts/dda_ab.bend) runs five process pairs in order `AB, BA, AB, BA, AB`. Every process warms four frames. The measured interval covers 512×512 rendering, native window presentation, and image disposal, excluding world construction. [Process output](dda-cursor-data/cpu12-run.txt) records successful completion of all requested frames. Release timing runs are serial, without compilation, proof checking, profiling, or verification alongside them.

Both final native binaries use captured, unmodified compiler output and identical release flags:

```sh
clang -DBEND_CUDA=1 -I/opt/cuda/include -L/opt/cuda/lib64 -std=c11 -O3 INPUT.c -o OUTPUT -lpthread -lm -lX11 -lcuda -lnvrtc -ldl
```

The revised delegate's first build omitted `CUDA_HOME` and was CPU-only. It was replaced before release timing. The frozen baseline C was rebuilt with the same flags as the final CUDA-enabled candidate. [Build hashes](dda-cursor-data/build-hashes.txt) identify the actual C, native binaries, and GPU sidecars used. CUDA settings belong to the existing runtime boundary; the candidate engine contains only portable Bend.

The [machine](dda-cursor-data/machine.txt) is a Ryzen 5 1600, six physical cores and twelve logical CPUs, with a GTX 1660 and Bend 2.0.34. Dota 2, desktop, and browser applications remained active. The [CPU12 load capture](dda-cursor-data/load-cpu12.txt) records Dota 2 consuming about 3.8 CPU cores and 4.3 GB of GPU memory in use. Alternating pairs expose both sides to that load; the measurements describe this shared desktop session, not an idle machine.

| Configuration | Measured frames per process | Baseline median, min–max, ms/frame | Cache median, min–max, ms/frame |
| --- | ---: | ---: | ---: |
| [CPU12, fork 6](dda-cursor-data/cpu12.tsv) | 32 | 111.75, 110.4375–113.5 | 243, 242.125–274.71875 |
| [CPU1, fork 0](dda-cursor-data/cpu1.tsv) | 4 | 780.75, 765.75–857 | 951.5, 936.75–1,033.75 |
| [GPU, fork 6](dda-cursor-data/gpu6.tsv) | 2 | 762.5, 520–848.5 | 1,006.5, 789–1,100.5 |
| [GPU, fork 7](dda-cursor-data/gpu7.tsv) | 2 | 655.5, 633–746.5 | 1,073.5, 690.5–1,180.5 |

The final CPU1 build also regresses in all five paired processes, by 21.87% at the median. Its [process output](dda-cursor-data/cpu1-run.txt) and [load capture](dda-cursor-data/load-cpu1.txt) are retained. The larger CPU12 penalty is consistent with shared ownership overhead, but no direct contention measurement establishes that explanation.

GPU fork-six measures 32% higher median frame time; fork-seven measures 63.77% higher. The cache is slower in all five paired processes at each decomposition. Separate strict GPU runs retain [fork-six output](dda-cursor-data/gpu6-run.txt), [fork-seven output](dda-cursor-data/gpu7-run.txt), and their [fork-six](dda-cursor-data/load-gpu6.txt) and [fork-seven](dda-cursor-data/load-gpu7.txt) load captures. Overall ranges overlap under game load; idle GPU performance and the GPU-specific limiter are unmeasured. These batches provide no evidence for retaining the cache on GPU. CPU scaling is not used to predict GPU behavior.

The primary CPU12 gate requires a repeatable improvement and fails. CPU6, carved-cube timing, and alternate cache depths three and nine are therefore skipped. All seven correctness views include the carved cube. This rejection applies to the measured depth-six design; it does not establish that every possible ancestor cache is slower.

## Correctness and reproduction

Both `bend PROOF.bend` and kernel `--verdict` return `ALL PROOFS CHECK` for the isolated candidate. The added [formal claims](dda-cursor-data/laws.patch) and [proofs](dda-cursor-data/proof.patch) establish that seeding preserves the full `Region`, for any fuel and tree, and that grid seeding preserves the outside sentinel and in-world result. See the [ordinary check](dda-cursor-data/proof-check.txt) and [kernel verdict](dda-cursor-data/proof-verdict.txt). They do not prove cache reuse for a different cell or full trace equivalence.

[Seven complete scans](dda-cursor-data/verification.txt) compare the revised region DDA against independent unit DDA on Atelier opening, cut, cube, carved cube, inside, axis-aligned, and opposite views. All **1,835,008 rays** match exact hit presence, F32 depth, cell, direction, and material. Candidate CPU12 and GPU fork-six exports match both frozen baseline and unit-reference images byte for byte. The opening also matches on CPU1/fork-zero and GPU/fork-seven. [Image hashes](dda-cursor-data/image-hashes.txt) preserve those identities. Cross-cell and complete-trace correctness are runtime evidence on these views, not a general theorem.

The initial revised CPU1 export filename was later reused by the CPU12 scan. Independent review caught that provenance gap. After release timings drained, CPU1/fork-zero was rerun into the distinct `opening-candidate2-cpu1.ppm`; its [identity](dda-cursor-data/cpu1-image-hash.txt) and comparisons against baseline and unit reference are retained.

The frozen baseline `dda.bend` has SHA-256 `0a20e959d87eec22b4c182e2eca7cb520d586c157c1366fa4a399d7bbf6f00d8`; the revised prototype has `bd24e23e864aaa4162cbac7089d2692ec97a1617440a404e00936ce916b88c88`. [Source hashes](dda-cursor-data/source-hashes.txt) identify the snapshots. Root engine and proof files remain byte-identical to the pre-experiment snapshots.

The local frozen executables and actual emitted C remain in `.audit/dda-cursor/`. Repeat their primary native measurement with:

```sh
.audit/dda-cursor/ab --gpu off --threads 1 -- .audit/dda-cursor/baseline2-renderer .audit/dda-cursor/candidate2-renderer 12 off 6 32 build/dda-cursor-cpu12.tsv
.audit/dda-cursor/ab --gpu off --threads 1 -- .audit/dda-cursor/baseline2-renderer .audit/dda-cursor/candidate2-renderer 1 off 0 4 build/dda-cursor-cpu1.tsv
.audit/dda-cursor/ab --gpu off --threads 1 -- .audit/dda-cursor/baseline2-renderer .audit/dda-cursor/candidate2-renderer 1 on 6 2 build/dda-cursor-gpu6.tsv
.audit/dda-cursor/ab --gpu off --threads 1 -- .audit/dda-cursor/baseline2-renderer .audit/dda-cursor/candidate2-renderer 1 on 7 2 build/dda-cursor-gpu7.tsv
.audit/dda-cursor/candidate2-renderer --gpu off --threads 12 -- --verify-steps
```

Source snapshots preserve root-relative imports. To rebuild, copy the candidate engine, laws, and proofs into a separate copy of this project and run `CUDA_HOME=/opt/cuda bend scripts/dda_compare.bend -o build/dda-cursor`. Run both proof commands in that copy. Do not overwrite the retained root engine merely to run the prototype.

The archived [Bend counter adapter](dda-cursor-data/candidate-profile.bend) belongs at `scripts/dda_cursor_profile.bend` in that isolated copy. It validates generated function bindings before injecting CPU-only atomic diagnostics into emitted C and rejects the baseline C. Those diagnostics are absent from portable engine code and release binaries. Its bindings are specific to this compiler output; a fresh emission must be checked before reuse.

Model the Domain led to one cursor carrying cache and grid together. Explain the Number required counting prefix work and inspecting ownership rather than treating fewer tree visits as a win. Attack the Premise stopped a third implementation after two failures of that assumption. The canonical append-only decision trail remains `.audit/dda-cursor/decisions.tsv`, with an [archived copy](dda-cursor-data/decisions.tsv). This directory has no Git metadata, so delivery is local evidence rather than a commit or PR.

The [independent evidence review](dda-cursor-data/review.txt) has no remaining flags after correcting the CPU1 export and abbreviated trail paths. Project model overrides require `gpt-6.1-sol` for the reviewer, so model-family diversity is limited. The reviewer inspected the current-task parent T3 timeline and retained artifacts; full child build/proof timelines were outside its scope.
