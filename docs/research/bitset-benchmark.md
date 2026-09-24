# Flood-fill bitset benchmark

Date: 2026-09-24. This experiment tested the [published `bend-collections` bitset](https://hub.bend-lang.com/0x9ee2e9a299991dcc089fe22c7f3ceb5f/src/containers/bitset.bend) as a replacement for the `seen: Array<U32>` field used by connectivity in `src/world.bend`. It did not change the production world implementation.

## Method

The baseline was revision `ac415e9` with Bend 2.0.27. The [trial patch](../validation/bitset-2026-09-24/bitset-world.patch) imported the immutable Hub package and changed only the visited-cell representation and its get/set calls. The bitset has 32,768 logical positions because out-of-world neighbors use cell 32767 as an empty sentinel. Both variants therefore support the same indices. Raw visited-state payload is 4 KiB for the bitset's 1,024 words versus 128 KiB for the baseline's 32,768 `U32` words; neither total process memory nor allocation count was measured. The bitset's public API also requires `U32` to `Nat` conversion and returns a checked `Result` on each access.

The bitset variant passed `make test`, including connectivity, fragmentation, cap rollback, and timed edit tests. Both variants were rebuilt with the same compiler and ran the existing 65-second Vulkan replay in **array, bitset, bitset, array** order on the Ryzen 5 1600 / GTX 1660 Linux desktop. Each run had five seconds of warm-up and sixty measured seconds, including 33 accepted cuts and six protected or empty attempts. The two runs per variant yielded 66 accepted-cut samples each. Every run passed the benchmark parser's instrumentation, workload, and performance checks. Event types, statuses, kinds, and the solid/body counts after each event matched in all four runs. The runner's overall `acceptance_pass` is false by design for each `--runs 1` invocation; this comparison did not execute the standard three-run acceptance protocol.

The table pools the two measured runs of each variant and uses the benchmark parser's nearest-rank percentiles. Connectivity and cut values are from accepted edits only. [Combined report with source hashes and per-run statistics](../validation/bitset-2026-09-24/report.json); raw CSV: [array 1](../validation/bitset-2026-09-24/array-1.csv.gz), [bitset 1](../validation/bitset-2026-09-24/bitset-1.csv.gz), [bitset 2](../validation/bitset-2026-09-24/bitset-2.csv.gz), [array 2](../validation/bitset-2026-09-24/array-2.csv.gz).

| Measure | Array p50 / p95 | Bitset p50 / p95 | Change at p50 / p95 |
| --- | ---: | ---: | ---: |
| Connectivity | 8.439 / 15.898 ms | 12.338 / 26.922 ms | +46% / +69% |
| Accepted-cut latency | 29.564 / 46.984 ms | 40.088 / 64.319 ms | +36% / +37% |
| Carving | 5.481 / 8.704 ms | 6.021 / 9.133 ms | +10% / +5% |
| Surface generation | 10.910 / 20.740 ms | 10.054 / 20.472 ms | −8% / −1% |

Per-run connectivity p50 was 8.756 and 8.383 ms for the array, versus 15.280 and 12.205 ms for the bitset. In same-position comparisons across the two replays, the bitset's connectivity interval was longer for 58 of 66 accepted cuts. The accepted-cut p95 stayed below the 100 ms performance gate in every run, but the bitset reduced headroom.

## Decision

Keep the existing `Array<U32>` for this bounded world. The tested package bitset reduced raw visited-state payload but made connectivity and accepted cuts slower. The experiment measures the complete public-API substitution; it does not separate bit packing, bounds checking, `Result` handling, `U32`/`Nat` conversion, compiler lowering, or allocation cost. A specialized `U32`-indexed bitset would be a different implementation and needs its own benchmark if memory pressure becomes important.

The replay was subject to normal desktop load and display pacing; measured frame p50 was near 16.67 ms in all four runs. The ABBA order limits simple time drift but does not eliminate environmental noise. The recorded source hashes and raw samples define the result's scope.
