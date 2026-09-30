# Megascene performance protocol v2 result

Stage 0 is complete for the selected static and history configurations. Four separate full validations and twelve selected controls have completed. Every selected control has at least ten seconds summed over ordinary frames. Three instrumented repetitions agree on canonical checkpoints and work in both cases. All twelve reader rows are usable, with no evidence errors.

Both calibration results are `failed`. Static responsiveness passes its applicable latency gates, but interactive qualification remains inconclusive because calibration failed. History responsiveness and interactive qualification are `fail` because all three on repetitions exceed the 100 ms ordinary-maximum gate. History visual quality remains `inconclusive` after a bounded sample inspection. These are observations, not qualified performance claims.

The scopes are small, seed 45, six threads, full geometry and 1920x1080. Both freeze 120 warmup and 21600 measured frames. History has 120 cuts at an explicit average density of one cut per 180 measured frames, with 20328 ordinary, 1152 motion and 120 edit frames. The final 179-frame suffix is the normal observation gap. No pacing or long empty tail was added. The [design](design.md) describes the domain and transport choices.

The table gives minimum and maximum over the three repeats in each mode. CPU values are frame-effect return intervals. GPU values are submitted top-to-bottom intervals. RSS is the sampled worker peak, not an exact peak or the complete verification-tool memory footprint.

| Case | CPU ordinary mean off, ms | CPU ordinary mean on, ms | CPU ordinary p95 on, ms | GPU ordinary mean on, ms | Sampled RSS on, MiB |
| --- | --- | --- | --- | --- | --- |
| static | 0.565..0.578 | 1.577..1.594 | 2.141..2.223 | 0.294..0.298 | 144.7..149.2 |
| history | 0.667..0.695 | 4.846..4.889 | 7.978..8.027 | 0.741..0.746 | 162.1..167.7 |

Static ordinary duration is 12.203..34.438 seconds per control. History ordinary duration is 13.556..99.393 seconds. History scripted edit-to-return p95 is 5.943..6.157 ms off and 41.281..42.269 ms on. Its ordinary maximum is 108.335..152.597 ms on. Full edit frames, motion populations, CPU stages, GPU populations, heap samples and explicit allocation ledgers remain in [results.json](results.json). [metrics.json](metrics.json) binds this digest to the durable comparison hash.

The [public commands](../../megascene-performance-v2.md) recompute the selected series. A frozen copy of the comparison reader and its Python helpers is retained at `/home/aivv/megascene-evidence/performance-v2/reader/`; [reader-source.json](reader-source.json) records its hashes. The durable comparison is `/home/aivv/megascene-evidence/performance-v2/comparison.json`.

The first static series stopped before controls at a runtime-binding mismatch; [its two completed validations](initial-static-failure.json) remain retained. The first history validation stopped at the old 300-second cap after 18905 frames; [its failed prefix](initial-history-failure.json) remains retained. The replacement history validations completed 21721 frames each under their separate 480-second cap. Timed workers retain 300 seconds.

A coordinator-boundary mistake let a Light Atelier build overlap history R2's third control. [That successful native attempt](history-interference.json) is explicitly excluded from calibration. R3 retains the complete validations and two clean controls, then runs four fresh remaining controls, including the replacement third control. [recover_history_prefix.py](recover_history_prefix.py) checks this prefix. The comparison carries `continuation_from` and `excluded_attempts`. There are thirteen actual timed controls, of which twelve are selected. Series calibration and resume reject exclusions. Standalone bundle reports retain raw native evidence and do not infer this series-level context.

The user authorized and the public runner applied [6000 additional seconds](allowance.json) to the same campaign. All selected native workers ended normally before their applicable campaign deadlines. The final reader was read-only and launched no native workload. [cleanup.json](cleanup.json) records stopped PID/start-tick instances and final durability barriers for all sixteen selected native workers. Light Atelier's [opening compatibility check](light-atelier-compat.json) also passed with real X11, Vulkan, native mesh reference, inspected HUD and exit code 0.

The [69 historical acceptance/ledger hashes and two old calibration assessments](historical-immutability.json) still match. Acceptance #68 remains the historical functional `pass`, with unqualified performance. Its [selected durations](historical-baseline.json) use different runtime and schedule identities and do not establish a speedup against v2.

[checks.json](checks.json) binds the full local checks, final 17-test protocol suite, native compilations and proof/verdict runs to retained logs. [decisions.tsv](decisions.tsv) preserves decisions and corrections. [recovery-review.md](recovery-review.md) records independent same-model source/archive/trail review. Design notes and the sparse feasibility check are retained at `/home/aivv/megascene-evidence/performance-v2/design-notes/`.

Off controls establish endpoint and scalar-action agreement; transient equality remains unproven. RSS excludes the Python reader/validator and supervisor. Query-pool device bytes are not measured. Scripted edit-return timing does not measure physical input-to-display latency. [History's sampled visual inspection](history-visual-sample.json) is not complete named-feature acceptance. Unsafe/native invariants use runtime/reference evidence only.
