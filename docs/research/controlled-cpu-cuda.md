# Controlled CPU/CUDA comparison and thread-count sweep

Measured 2026-09-22 with Bend 2.0.25 on the Ryzen 5 1600 (6 cores / 12 logical CPUs), GTX 1660, driver 610.57.04, Linux/XWayland, at 640 × 360. This implements the controlled-comparison follow-up from [the ecosystem review](bend-ecosystem.md). It changes measurement tooling, not engine behavior or backend defaults.

## Protocol and evidence

Built the demo and snapshot executables once, then ran:

```sh
python3 scripts/compare_backends.py --output build/backend-comparison-2026-09-22
```

Each backend used the same executable with explicit `--gpu off/on` and `--threads N`. Thread counts were 1, 2, 4, 6 and 12. Round 1 visited counts ascending, CPU then CUDA at each count. Round 2 visited counts descending, CUDA then CPU. Every process used five seconds of warm-up and sixty seconds measured, with the existing scripted destruction/camera workload and native presentation. No compilation, tests or snapshot rendering overlapped the timed sweep.

Before timing, all seven fixed-clock states (ticks 0, 60, 216, 396, 408, 540 and 1140) ran on every backend/thread configuration. All **70** probes matched the first CPU configuration's decoded RGB hash, HUD text and recorded state, including body transforms and velocities. These checks cover sampled visible/state behavior, not every voxel or every frame of the wall-clock workload.

All **20** windowed runs passed workload and instrumentation checks, including 33 accepted cuts, protected/no-target attempts, and stage/sample accounting. The final source/binary fingerprint check passed. `make test` subsequently passed all **35 Bend checks and 10 Python tests**. The new tests cover paired/reversed scheduling, explicit runtime flags, and invalid-run aggregation.

The [archived report](../validation/backend-comparison/report.json) contains the complete schedule, commands, compiler/hardware/source/binary metadata, snapshot comparisons, per-run telemetry, samples counts, percentiles and stage statistics. Neighboring `run-*.csv.gz` files preserve all raw samples, including warm-up; `.stderr` files preserve runtime diagnostics. Each `snapshots-*/tick-*.tree.gz` preserves the full tree and recorded state/HUD, from which the PNG can be reconstructed. Uncompressed CSVs and generated PNGs remain in the local build output. The archive is approximately 2 MB.

## Results

Cells list **round 1 / round 2**, in milliseconds. These are per-run percentiles, not percentiles pooled across runs.

| CPU workers | CPU frame p95 | CUDA frame p95 | CPU cut p95 | CUDA cut p95 |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 26.028 / 21.145 | 52.834 / 50.094 | 80.478 / 82.351 | 165.933 / 150.286 |
| 2 | 20.104 / 23.322 | 44.512 / 43.565 | 77.071 / 87.960 | 151.855 / 161.342 |
| 4 | 22.248 / 20.872 | 45.793 / 44.150 | 74.957 / 75.885 | 152.672 / 159.068 |
| 6 | 21.956 / 21.177 | 45.665 / 45.526 | 78.322 / 78.941 | 159.675 / 168.967 |
| 12 | 22.139 / 22.063 | 46.323 / 43.511 | 76.404 / 77.667 | 166.470 / 153.785 |

CUDA frame p95 was **1.87–2.37 times CPU frame p95** within the same-round, same-thread pairs. Every CPU diagnostic run met the numerical frame-p95, cut-p95 and maximum-cut thresholds. Every CUDA run missed frame p95 ≤ 33.3 ms and cut p95 ≤ 100 ms; CUDA maximum cuts remained below 250 ms (155.4–179.7 ms). **Forced-CUDA acceptance remains open.** Neither this two-round sweep nor CPU results replace the agreed three-run CUDA acceptance protocol.

One worker consistently worsened CUDA frame p95 versus 2–12 workers. Beyond one worker, the differences are small compared with observed repeat variation: for example, CUDA at twelve workers moved from 46.323 to 43.511 ms. CPU also has no convincing unique optimum: its initial two-worker lead disappeared in round 2. Do not choose a new default from these two observations per configuration. Two workers is a useful low-worker baseline for a larger diagnostic experiment, but not an established optimum.

## Stage interpretation and limits

Across runs, CPU mean render-stage time was 6.17–8.70 ms versus CUDA's 16.28–17.98 ms. Other stages also differ: CPU scene preparation averaged 0.70–0.82 ms and disposal 0.18–0.31 ms, versus CUDA's 6.02–7.51 ms and 6.54–11.37 ms respectively. The report retains the historical `cuda_rendering` key for both backends; on CPU it measures CPU rendering. These are completed wall-clock stages, not kernel timings or proof of a specific allocator/ownership bottleneck.

The same event schedule and viewport do not imply identical frames: the native replay uses real elapsed physics steps, so CPU and CUDA render different frame counts and potentially different intermediate states. Faster CPU runs also spend more time in presentation/pacing (mean 8.41–9.92 ms versus CUDA's 4.27–4.63 ms). Fixed-clock pixel/state agreement is a separate control. Consequently, interpret this as an end-to-end comparison of the scheduled workload; do not derive a kernel speedup from it.

The machine remained an active desktop. CPU/GPU clocks were not locked, workloads were not isolated with affinity reservations, and the sample is only two ordering-balanced rounds. GPU telemetry and host load are recorded but do not eliminate interference. No confidence interval or causal attribution to the compiler is claimed.

The next useful performance investigation is generated-code/ownership and allocation inspection around scene preparation, the render boundary and cell disposal, followed by one-change-at-a-time measurement with the same controls. Increasing CPU worker count alone did not resolve CUDA latency.

See [the profiling guide](../profiling.md#controlled-cpucuda-comparison) for reproducible commands and failure semantics.
