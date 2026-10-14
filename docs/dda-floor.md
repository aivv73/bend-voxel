# Redundant floor removal

`Axis.count` now converts its clamped F32 estimate directly to U32. The explicit `F32.floor` is removed. The F32 clamp, integer minimum, and exact plane correction remain intact. The [engine diff](dda-floor-data/candidate.patch) changes one line.

The change is retained. At GPU fork depth seven, complete-window median frame time decreases by 6.3% in the initial batch and 2.0% in a longer repeat. All ten paired processes favor the candidate. CPU12 gains are not established. These results concern the experimental comparison renderer, not the application's projected-face renderer.

## Conversion and correctness

For nonnegative values within the conversion range, the native [checked conversion](dda-floor-data/conversion-runtime.txt) truncates toward zero. JavaScript conversion already calls `Math.floor`. The [baseline assembly](dda-floor-data/baseline-axis-assembly.txt) calls `floorf` before integer truncation. The [candidate assembly](dda-floor-data/candidate-axis-assembly.txt) removes that call from `Axis.advance` and retains the checked conversion.

The [arithmetic-property verifier](dda-floor-data/property.bend) uses the actual Bend primitives. Native CPU and JavaScript runs both report zero mismatches. The boundary sweep checks 18,856 raw conversions and 9,937,112 clamped estimates. It covers neighboring bit patterns around every integer from zero through 512, every limit in that range, power-of-two and conversion-range boundaries, every exponent field, signed zero, subnormals, infinities, and NaNs.

A second sweep exhausts every representable F32 value in `[256,512]` and its sign mirror. It checks 16,777,218 raw conversions and 117,440,526 clamped estimates against seven selected limits. Counts include repeated patterns between sweep families. This is finite runtime evidence, not a universal theorem. See [native output](dda-floor-data/property-native.txt) and [JavaScript output](dda-floor-data/property-js.txt).

The installed Base primitives expose return types without a theorem relating floor and conversion. A generic reflexivity proof therefore does not close. Existing `LAWS.bend` and `PROOF.bend` remain unchanged. Both [normal checking](dda-floor-data/proof-check.txt) and [kernel checking](dda-floor-data/proof-verdict.txt) report `ALL PROOFS CHECK` for the candidate.

[Seven complete scans](dda-floor-data/verification.txt) compare region traversal with unit DDA on opening, cut, cube, carved cube, inside, axis-aligned, and opposite views. All 1,835,008 rays match hit presence, exact F32 depth, cell, direction, and material. Baseline, unit reference, candidate CPU12, and candidate GPU fork-six images match byte for byte in every view. Additional opening exports match on CPU1, CPU6, and GPU fork seven. [Image hashes](dda-floor-data/image-hashes.txt) identify the files. Native window captures also have [zero pixel differences](dda-floor-data/window-parity.txt).

## Complete-window measurements

The unchanged `scripts/dda_ab.bend` runs five process pairs per batch in alternating AB/BA order. Each process warms four frames. The measured interval includes rendering, native X11 presentation, and image disposal. Scene construction is excluded. Every requested frame completes successfully. Release measurements do not overlap builds, proof checks, property sweeps, profiling, or geometry/image verification. GPU stage profiling runs after the timing matrix.

Both release builds use Bend 2.0.34 with CUDA enabled and identical build settings. The machine has a Ryzen 5 1600, twelve logical CPUs, and a GTX 1660. Dota 2 and desktop applications remain active. Per-batch load captures and process output are stored beside the samples. These are measurements of that shared desktop session.

| Configuration | Measured frames per process | Baseline median and range, ms/frame | Candidate median and range, ms/frame |
| --- | ---: | ---: | ---: |
| [CPU12, fork 6](dda-floor-data/cpu12.tsv) | 32 | 157.21875, 147.90625 to 158.84375 | 158.78125, 153.3125 to 161.0625 |
| [CPU12 repeat, fork 6](dda-floor-data/cpu12-repeat.tsv) | 32 | 165.0625, 145.65625 to 173.34375 | 164.5, 154.875 to 177.0625 |
| [CPU1, fork 0](dda-floor-data/cpu1.tsv) | 8 | 865, 791.875 to 918 | 828, 771.125 to 901.625 |
| [CPU1 repeat, fork 0](dda-floor-data/cpu1-repeat.tsv) | 16 | 818.25, 786.5625 to 831.3125 | 809.625, 783.25 to 830.375 |
| [CPU6, fork 6](dda-floor-data/cpu6.tsv) | 32 | 204.59375, 195.1875 to 208.84375 | 205.46875, 199.8125 to 208.40625 |
| [GPU, fork 6](dda-floor-data/gpu6.tsv) | 4 | 828.25, 710.5 to 884 | 758.25, 703.5 to 864.25 |
| [GPU, fork 7](dda-floor-data/gpu7.tsv) | 4 | 900, 870 to 918 | 843.25, 823.25 to 896.5 |
| [GPU repeat, fork 7](dda-floor-data/gpu7-repeat.tsv) | 8 | 777.25, 766.125 to 795.5 | 761.625, 750 to 764.25 |
| [Carved cube, CPU12, fork 6](dda-floor-data/carved-cpu12.tsv) | 64 | 29.21875, 26.171875 to 31.515625 | 28.734375, 27.96875 to 29.75 |

GPU fork seven is faster in all five pairs in each batch. Its repeat ranges do not overlap. GPU fork six favors the candidate in only three pairs, so its lower median does not establish a repeatable gain.

CPU1 medians are lower in both batches, but only seven of ten pairs improve. CPU12 is slower in eight of ten pairs, and CPU6 is slower in four of five. The CPU12 median paired increases are 3.53125 ms and 3.375 ms in the two batches, even though the repeat's separate candidate median is lower. Overlapping ranges do not erase that unfavorable paired pattern. No CPU neutrality or speedup is claimed. A small parallel-CPU regression remains a retention risk; desktop load prevents attributing a hardware cause. The carved-cube result is also inconclusive.

Separate native CPU profiles include twelve frames each, including warmups and initialization. [Baseline](dda-floor-data/baseline-gprof.txt) and [candidate](dda-floor-data/candidate-gprof.txt) profiles place region lookup first and axis advancement second. Profiling overhead and different desktop load prevent using their absolute times as speed measurements.

Separate GPU fork-seven stage profiles place most time inside rendering. The [baseline diagnostic](dda-floor-data/baseline-gpu7-profile.txt) reports 850 ms rendering, 160 ms presentation, and 2 ms disposal. The [candidate diagnostic](dda-floor-data/candidate-gpu7-profile.txt) reports 793, 164, and 3 ms respectively. These one-frame diagnostics identify the dominant stage. They do not replace the repeated release measurements or isolate GPU instruction costs.

## Reproduction

Frozen binaries and emitted C remain in `.audit/dda-floor/`. [Source hashes](dda-floor-data/source-hashes.txt) and [build hashes](dda-floor-data/build-hashes.txt) identify them. The installed `build/dda-compare` matches the checked candidate binary. Archived engine snapshots retain root-relative imports and belong in separate project copies when rebuilding.

```sh
bend PROOF.bend
bend PROOF.bend --verdict
bend docs/dda-floor-data/property.bend
make build/dda-compare build/dda-ab
build/dda-compare --gpu off --threads 12 -- --verify-steps
build/dda-ab --gpu off --threads 1 -- .audit/dda-floor/baseline-renderer build/dda-compare 12 off 6 32 build/dda-floor-cpu12.tsv
build/dda-ab --gpu off --threads 1 -- .audit/dda-floor/baseline-renderer build/dda-compare 1 on 7 8 build/dda-floor-gpu7.tsv
```

Laziness Protocol favored one deletion. Sequence Work into Verifiable Units required correctness before timing. Prove It Works required exact scans and live window parity. Explain the Number limits the performance claim to the repeated GPU configuration. The canonical decision trail is `.audit/dda-floor/decisions.tsv`. This checkout has no Git metadata, so delivery is local.

Independent review used the configured `gpt-6.1-sol` model. The [evidence review](dda-floor-data/review.txt) supported retention and identified one chronology correction. The [confirmation](dda-floor-data/review-confirmation.txt) verifies that correction and the stronger paired CPU risk statement. No unresolved evidence issue remains. The disclosed parallel CPU regression risk still applies.
