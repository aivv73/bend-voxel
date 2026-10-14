# Explicit zero-event guard evaluation

Explicit zero-event short-circuiting was implemented and checked, then rejected. Broader guards regress on GPU; affine thunks regress on CPU. The smallest prototype avoids 1,985,759 advancement plane calculations per opening frame, but CPU6 is slower in all ten paired runs across two batches, CPU1 has higher medians in both batches, and GPU rendering is neutral. The root `dda.bend`, `LAWS.bend`, and `PROOF.bend` remain byte-identical to the frozen baseline. Checked prototypes and measurements are preserved for review.

This work concerns the experimental compressed-region DDA in `scripts/dda_compare.bend`. The production face renderer, world representation, geometry, F32 operation order for nonzero events, and frame decomposition retain their existing behavior.

## Candidate shapes

The first prototype matches a numeric event count before either predicate or advancement plane arithmetic. Its general zero-predicate and zero-advancement claims pass the kernel, and all seven views retain exact surfaces and image bytes. CPU12 improves in two batches, but longer GPU measurements regress in every pair with non-overlapping ranges. The [literal source and evidence](dda-zero-data/u32-match/candidate-dda.bend) remain archived. Replacing the numeric catch-all with a wildcard emits byte-identical native C and GPU sidecar artifacts, so it does not create another performance candidate.

Three configured gpt-6.1-sol design delegates and a separate judge compared scalar Boolean helpers with affine thunks. The [design synthesis](dda-zero-data/design.md) records their proposal scores and subsequent measured rejection. Those scores assess architecture, not speed. A computed Boolean match is invalid in Bend's parameter-only match model; the checked helper form branches on a Boolean parameter. Its scalar native code avoids numeric reconstruction but still regresses in both GPU decompositions. The [helper evidence](dda-zero-data/boolean-helpers/gpu6.tsv) is separate from the literal variant.

Affine thunks keep the choice inside existing functions but lower to captured environments, heap allocation, and indirect closure application. Their [CPU12 measurements](dda-zero-data/thunks/cpu12.tsv) regress in all five pairs. The actual emitted sites are retained in the [compiler excerpt](dda-zero-data/thunks/predicate-emission.txt).

The last [prototype](dda-zero-data/candidate.patch) changes one argument:

```bend
+crosses = U32.is_ne(count,0) &&
    F32.is_eq(Axis.next(U32.is_ne(count,0),positive,origin,delta,previous),time)
```

The previous expression passed `True{}` to `Axis.next`. A zero count now selects that function's existing `1.0e30` sentinel without plane conversion or division. The outer nonzero predicate still makes the crossing false. Nonzero events use the original plane formula and order. Integer next/previous formulas are unchanged. The predicate function remains eager; this narrower prototype does not skip its zero-event plane arithmetic.

## Actual work

The [28-field diagnostic adapter](dda-zero-data/profile.bend) validates generated function bindings and the derived moving flag before writing instrumented C. It rejects the unguarded baseline C before creating output. It belongs only to this last prototype and Bend 2.0.34; inspect fresh emitted C before using it with another compiler or source.

| Work per opening 512×512 frame | Count |
| --- | ---: |
| Region lookups | 3,824,783 |
| Tree lookups | 3,740,969 |
| Tree branches | 59,823,748 |
| Region crossings | 3,562,639 |
| Advancement calls | 10,687,917 |
| Zero-count advancement calls | 1,985,759 |
| Predicate plane evaluations | 17,952,681 |
| Predicate planes evaluated for zero events | 2,029,727 |
| Rendered rays / pixels | 262,144 |

These are [actual native frame counters](dda-zero-data/candidate-counters-frame.tsv). Every field in a separate four-warmup, one-measured-frame window run is exactly five times its single-export value. The instrumented export equals the frozen baseline image byte for byte. The [validation record](dda-zero-data/counter-validation.txt) includes those checks and adapter rejection.

The advancement counters count calls, rather than retired division instructions. The emitted `Axis.advanced` passes `count != 0` into `Axis.next`, whose false branch precedes conversion and division. In the [actual native assembly](dda-zero-data/axis-assembly.txt), the count-zero jump at `121155` bypasses the plane `divss` at `121171`. Combining that inspected control flow with the measured zero-call count establishes 1,985,759 avoided advancement plane calculations for this frame. It does not attribute GPU instructions or count every division in the shared `Axis.next` function.

The literal and helper variants also skip 2,029,727 predicate planes, for 4,015,486 omitted planes per opening frame. That larger arithmetic reduction did not outweigh their complete-frame GPU regressions.

## Correctness

The last prototype adds one [formal claim](dda-zero-data/laws.patch) and [paired proof](dda-zero-data/proof.patch): for arbitrary Boolean moving flag and all remaining arguments, gating both the crossing conjunction and `Axis.next` preserves the crossing Boolean. The existing inactive-plane sentinel law remains. [Ordinary checking](dda-zero-data/combined-proof-check.txt) and [BendTT kernel checking](dda-zero-data/kernel-verdict.txt) both pass.

An earlier attempt to prove a zero-advancement record by reflexivity failed because modular `cell + 0` and `cell - 0` did not normalize to `cell` in that proof. The rejected attempt is retained under `.audit/dda-zero/next-guard-cell-proof-attempt/`. It is not a runtime counterexample. The final theorem proves the changed Boolean expression, not a general theorem of full floating-point trace equivalence.

[Seven complete scans](dda-zero-data/verification.txt) cover opening, cut, cube, carved cube, inside, axis-aligned, and opposite views: all 1,835,008 rays match the unit DDA's hit presence, exact F32 depth, cell, direction, and material. CPU12 and GPU fork-six image exports for every view equal frozen baseline and unit-reference bytes. CPU1/fork-zero and GPU/fork-seven opening exports also match, with distinct filenames. The [lane record](dda-zero-data/lane-parity.txt) and [image hashes](dda-zero-data/image-hashes.txt) preserve these comparisons.

## Complete-frame measurements

All results use the existing Bend A/B driver, four warmups per process, and five process pairs in AB, BA, AB, BA, AB order. Frame time includes drawing, native window presentation, and image disposal; it excludes world construction. For the last existing-branch prototype, CPU12 uses 64 measured frames per process, CPU6 initially 32, CPU1 initially four, and GPU forks six and seven eight. Its CPU1 and CPU6 follow-ups use eight and 64 respectively. Earlier predicate-only CPU12 runs use 32 frames, thunk CPU12 runs four, and the initial literal GPU batches two. The literal and helper GPU rejection rows below use longer eight-frame batches. Native flags match: clang 23, `-std=c11 -O3`, Bend 2.0.34, and the existing native/CUDA libraries. [Build hashes](dda-zero-data/build-hashes.txt) identify release and diagnostic artifacts separately.

No proof checking, compilation, profiling, or replay overlaps release measurements. The machine is a Ryzen 5 1600 with 12 logical CPUs and GTX 1660. Desktop, browser, chat, and Steam processes remain running; these are interleaved desktop measurements, not idle-machine results. Each batch retains load captures. Parallel schedules are measured as configured and are not changed by a candidate.

| Last prototype / opening scene | Baseline median, range (ms/frame) | Candidate median, range (ms/frame) |
| --- | --- | --- |
| [CPU12](dda-zero-data/cpu12.tsv) | 107.953125, 107.6875–109.1875 | 108.421875, 107.65625–109.078125 |
| [CPU12 repeat](dda-zero-data/cpu12-repeat.tsv) | 107.734375, 107.078125–108.234375 | 108.21875, 107.796875–109.453125 |
| [CPU1](dda-zero-data/cpu1.tsv) | 714.75, 709.5–725.25 | 724.75, 722.5–741 |
| [CPU1 repeat](dda-zero-data/cpu1-repeat.tsv) | 716.375, 713.875–720.875 | 722.5, 719.875–724.25 |
| [CPU6](dda-zero-data/cpu6.tsv) | 143.90625, 141.28125–144.40625 | 145.9375, 143.34375–146.28125 |
| [CPU6 repeat](dda-zero-data/cpu6-repeat.tsv) | 144.921875, 143.71875–145.609375 | 145.359375, 144.921875–145.6875 |
| [GPU / fork 6](dda-zero-data/gpu6.tsv) | 508, 494.5–509.5 | 507.375, 502.75–508.25 |
| [GPU / fork 7](dda-zero-data/gpu7.tsv) | 512.125, 505.75–519 | 512, 507.75–515.5 |
| [Carved cube / CPU12](dda-zero-data/carved-cpu12.tsv) | 16.734375, 16.6875–16.828125 | 16.75, 16.71875–17.5 |

The GPU ranges overlap and their paired samples do not establish a speedup. CPU12 is about 0.4% slower by median in both batches, with seven of ten pairs slower and overlapping ranges. CPU1 is about 1.4% slower initially and 0.85% slower in the longer repeat; eight of ten paired runs are slower. CPU6 is about 1.4% slower initially and 0.30% slower in the longer repeat; every one of its ten paired runs is slower. Although CPU ranges overlap, the repeated paired CPU6 cost and absence of a frame-time win reject this last candidate. The small carved scene remains near the window presentation floor. No speedup is claimed for any retained change because no engine change is retained.

| Rejected broader prototype / lane | Baseline median (ms/frame) | Candidate median (ms/frame) | Paired result |
| --- | ---: | ---: | --- |
| [Literal guards / GPU fork 6](dda-zero-data/u32-match/gpu6-repeat.tsv) | 504.75 | 535 | Every pair slower |
| [Literal guards / GPU fork 7](dda-zero-data/u32-match/gpu7-repeat.tsv) | 509.375 | 540.5 | Every pair slower |
| [Boolean helpers / GPU fork 6](dda-zero-data/boolean-helpers/gpu6.tsv) | 502.375 | 525.375 | Every pair slower |
| [Boolean helpers / GPU fork 7](dda-zero-data/boolean-helpers/gpu7.tsv) | 509.5 | 538 | Every pair slower |
| [Affine thunks / CPU12](dda-zero-data/thunks/cpu12.tsv) | 105.75 | 387.25 | Every pair slower |

These rejection rows have non-overlapping ranges in their linked five-pair batches. Do not compare their absolute medians across batches as controlled measurements of one candidate against another.

The [baseline CPU profile](dda-zero-data/baseline-gprof.txt), collected separately during the earlier cursor evaluation, attributes approximately 43% of sampled self time to `Grid.region`, 25% to `Axis.advance`, and 17% to `Crossing.region`. The [provenance hashes](dda-zero-data/profile-provenance.txt) establish that its baseline emitted C and copied profile are byte-identical to the earlier artifacts. Inlined leaf work is included in these hosts, so this does not isolate the changed division's cost. Traversal still performs almost 60 million tree branches per frame. There is no isolated GPU instruction-cost profile; the GPU rejection decisions concern completed frame time, not a claimed hardware cause.

## Reproduction and provenance

The final prototype, laws, proofs, diagnostic adapter, raw samples, and diffs remain in `docs/dda-zero-data/`. Top-level candidate artifacts identify the last existing-branch prototype. `u32-match/`, `boolean-helpers/`, and `thunks/` preserve earlier variants. Local full source copies, emitted C, native executables, and GPU sidecars remain under `.audit/dda-zero/`.

To rebuild a rejected prototype, use a separate copy of the project. Install the archived candidate engine as `dda.bend`, candidate laws as `LAWS.bend`, and candidate proof as `PROOF.bend`. For the last candidate, install its diagnostic adapter as `scripts/dda_zero_profile.bend`. Preserve root-relative imports. Run:

```sh
bend guide
bend PROOF.bend
bend PROOF.bend --verdict
bend scripts/dda_compare.bend -o build/dda-zero.c
clang -DBEND_CUDA=1 -I/opt/cuda/include -L/opt/cuda/lib64 -std=c11 -O3 build/dda-zero.c -o build/dda-zero -lpthread -lm -lX11 -lcuda -lnvrtc -ldl
build/dda-zero --gpu-build
build/dda-zero --gpu off --threads 12 -- --verify-steps
```

The frozen local release binaries can be compared without rebuilding:

```sh
.audit/dda-zero/ab --gpu off --threads 1 -- .audit/dda-zero/baseline-renderer .audit/dda-zero/next-guard-renderer 12 off 6 64 build/dda-zero-cpu12.tsv
.audit/dda-zero/ab --gpu off --threads 1 -- .audit/dda-zero/baseline-renderer .audit/dda-zero/next-guard-renderer 1 on 6 8 build/dda-zero-gpu6.tsv
.audit/dda-zero/ab --gpu off --threads 1 -- .audit/dda-zero/baseline-renderer .audit/dda-zero/next-guard-renderer 1 on 7 8 build/dda-zero-gpu7.tsv
```

The diagnostic adapter and its temporary Makefile target are removed from the root after rejection. The archived adapter remains usable in an isolated candidate copy. [Source hashes](dda-zero-data/source-hashes.txt) distinguish the unchanged root, frozen baseline, and last rejected prototype.

Laziness Protocol led to reusing one existing branch rather than adding helpers. Explain the Number required measuring actual work separately from release frame time. Attack the Premise narrowed the opportunity after multiple GPU failures and stopped further guard variations after the smaller form also failed retention. Prove It Works required exact runtime surfaces, image bytes, native control flow, and real windows. The canonical append-only trail is `.audit/dda-zero/decisions.tsv`, with an [archived copy](dda-zero-data/decisions.tsv). User role overrides require gpt-6.1-sol for all delegates, including review; this is a separate reviewer on the same configured model. There is no Git metadata in this directory.

The independent [evidence review](dda-zero-data/evidence-review.txt) supports rejection and baseline retention. Its two documentation findings were corrected, and the [follow-up confirmation](dda-zero-data/evidence-review-confirmation.txt) reports no unresolved flags. The remaining limits are desktop timing variation, no GPU instruction-cost attribution, and a Boolean-expression theorem rather than full trace equivalence.
