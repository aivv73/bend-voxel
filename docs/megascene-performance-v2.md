# Megascene performance protocol v2

This Stage 0 protocol preserves [acceptance #68](validation/megascene-acceptance/acceptance.json) and its `120/3600` workloads. It introduces two fixed schedules, `static-perf-v2` and `history-perf-v2`, for small, seed 45, six threads, full geometry, 1920x1080, and fragment budget 2048. It does not qualify other configurations or propose production parallelism.

Each attempt has startup, 120 warmup frames and 21600 measured frames. The frozen schedule, native frame policy, recorder capacity, GPU query capacity, validation and readers agree on 21721 total frames. The GPU pool has 21721 timestamp pairs. The policy file has one eight-byte phase/flag entry per frame. Existing native frame/state ABI layouts remain unchanged.

History has twelve groups of 1800 measured frames. Each group has ten cuts at offsets `0,180,360,540,720,732,1080,1260,1440,1620`. This gives 120 cuts and a declared average density of one cut per 180 measured frames. The twelve-step release-to-moving-target gap remains explicit. The final action occurs at frame 21541, followed by 120 camera-transition frames and 59 settled overview frames. Every group has the same final observation gap; the schedule adds no long empty tail and no pacing sleep.

Measured populations are disjoint. An action frame is `edit`. A remaining frame with fragment velocity or a changed fragment offset is `motion`, including the settling/contact frame. Other measured frames are `ordinary`. The reference schedule has 20328 ordinary, 1152 motion and 120 edit frames for history, and 21600 ordinary frames for static. Runtime validation checks the declared motion against actual body offsets and velocities.

Every control needs at least 1000 ordinary frames and ten seconds summed over those ordinary frame intervals. The measured wall interval is retained separately and cannot qualify ordinary duration. History also needs 100 accepted edits. Repeated attempts are assessed separately. No attempt is extended to reach a stopwatch target, and no instrumentation cost is subtracted.

## Reproduce the comparison

Inspect the plan without launching work.

```sh
python3 scripts/megascene_calibration_series.py plan --protocol performance-v2
```

Use the established durable archive. Each configuration runs fresh separate on/off validations followed by six fresh controls in `off,on,on,off,off,on` order. Controls execute the same archived runtime and schedule bytes. Failed attempts remain retained and block automatic reruns of their series.

```sh
python3 scripts/megascene_calibration_series.py run --protocol performance-v2 \
  --case static --preset small --threads 6 \
  --archive /home/aivv/megascene-evidence \
  --work /home/aivv/.t3/worktrees/bend-voxel/t3code-bfd3d7ae/build/performance-v2/static-r2 \
  --series /home/aivv/megascene-evidence/calibration-series-v2/static-small-6/revision-2/series.json
python3 scripts/megascene_calibration_series.py run --protocol performance-v2 \
  --case history --preset small --threads 6 \
  --archive /home/aivv/megascene-evidence \
  --work /home/aivv/.t3/worktrees/bend-voxel/t3code-bfd3d7ae/build/performance-v2/history-r3 \
  --series /home/aivv/megascene-evidence/calibration-series-v2/history-small-6/revision-3/series.json
python3 scripts/megascene_performance.py report \
  --static-series /home/aivv/megascene-evidence/calibration-series-v2/static-small-6/revision-2/series.json \
  --history-series /home/aivv/megascene-evidence/calibration-series-v2/history-small-6/revision-3/series.json \
  --output /home/aivv/megascene-evidence/performance-v2/comparison.json
```

The selected series are complete. Running their existing locators recomputes assessment. Fresh native measurements use unused work and series locators inside the same configuration namespace and funded existing campaign.

An exhausted or interrupted campaign requires explicitly authorized `--additional-allowance SECONDS`; the commands above do not grant it. This session's [authorization](validation/megascene-performance-v2/allowance.json) approves 6000 additional seconds in total. The first 3600 seconds were transferred as 2400 plus 1200 for bounded correction. Two further additions of 1200 seconds were explicitly authorized to finish history in the same campaign. See [supervision](megascene-supervision.md) and the [execution record](validation/megascene-performance-v2/README.md).

The first static series stopped before controls because runtime reuse added five generator files to the off archive. [Its record](validation/megascene-performance-v2/initial-static-failure.json) and both completed validations remain retained. V2 reuse now preserves the copied runtime bytes. The explicit `--series` locator selects a fresh correction below the same case's v2 namespace; it cannot reset or leave the existing campaign. The chosen static series above is that separately retained revision.

The first history validation hit the old 300-second worker deadline after 18905 completed frames. [Its prefix](validation/megascene-performance-v2/initial-history-failure.json) remains failed and retained. History v2 now declares a separate 480-second full-validation cap. Timed workers and static/legacy validation keep their 300-second cap. An explicit smaller `--deadline` also bounds history validation. Startup, watchdog, resource freshness/reserves and the campaign deadline still apply, and the earliest stop wins. All 21721 frames and native audits remain required; validation time is excluded from performance observations.

History revision 2 retained a third control that overlapped a Light Atelier build after a coordinator-boundary mistake. [Its exclusion](validation/megascene-performance-v2/history-interference.json) remains explicit. Revision 3 keeps the two complete validations and two clean controls, then executes four fresh controls in the remaining declared order. The [prefix recovery tool](validation/megascene-performance-v2/recover_history_prefix.py) checks the retained prefix and preserves the excluded attempt. Series calibration and coordinator resume reject a control with `measurement_exclusion`; standalone bundle reports retain raw native evidence and do not infer this series-level exclusion; the comparison exports continuation and exclusion provenance.

At an allowance boundary, pause only the owned coordinator, identify its current child from the process tree, and wait for that child to exit and the campaign lock to be released before any other verification. Check current ownership and completion at that boundary. A previously completed child does not establish that its successor has stopped.

The comparison recomputes public calibration and per-attempt reports, verifies retained evidence and canonical agreement between the three instrumented controls, and keeps every qualification status. It reports CPU frame-effect intervals, scripted edit-to-return latency, CPU stage intervals, and GPU submitted top-to-bottom intervals. These timings do not measure physical input-to-display latency. GPU evidence is disabled in off controls.

Memory includes sampled process RSS, device free memory and Vulkan heap extrema across the whole attempt, plus audited explicit Vulkan allocation totals. Sampled maxima are observations rather than exact peaks. The RSS scope covers the worker and its observed resident descendants, and excludes the Python validation/comparison readers and supervisor. The reserved reference mapping and policy file sizes are separate bookkeeping quantities. Query-pool device bytes are not measured. History reserves 22081 reference slots of 1024 bytes plus a 32-byte header; the same reservation applies to both modes.

Calibration preserves the existing five-percent noise and paired-overhead gates. A sufficiently long series can honestly be `failed` or `noisy`. Such outcomes remain useful observations and cannot become qualified responsiveness or performance claims. The [historical baseline](validation/megascene-performance-v2/historical-baseline.json) has different runtime/schedule identities and does not establish a speedup against this regime. All unsafe/native invariants use runtime/reference evidence, not formal proof.
