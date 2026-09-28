# Static GPU timestamp verification

Issue #52 was exercised on the actual NVIDIA GeForce GTX 1660 Vulkan queue at
small/seed 45, six threads, full geometry and 1920 × 1080. The accepted schedule
contains one startup frame, 120 warm-up frames and 3,600 ordinary frames.

[results.json](results.json) indexes the durable runtime/evidence archive and
SHA-256 identities. Both the separate validation replay and timed invocation
completed with 3,721 measured GPU pairs, no missing intervals and no GPU evidence
errors. The final pair retains frame/submission `3720` and collection phase
`teardown`; it does not become another CPU frame. The selected queue reported
64 valid bits and a 1 ns tick period. Raw ticks and resolved intervals remain in
each archived `gpu.jsonl`. The final reader independently rechecked both streams,
and all manifest runtime/evidence hashes were verified.

State/geometry checkpoints, native caches and visibility checks passed. The
ordinary GPU distribution is descriptive only: calibration and feature review
remain unqualified, and completing this static schedule does not establish a
benchmark pass, responsiveness gate, capacity endpoint or full #47 acceptance.

The retained short public invocation also completed its validation, four-frame
timed observation and separate opening capture. A relocated archived runtime
completed another four-frame observation with all GPU intervals, including its
tail. [recovery.json](recovery.json) identifies those durable artifacts.

## Checks and unsuccessful attempts

- [Regression suite](tests.log): Bend runtime suites, native geometry/reference
  checks, and 59 Python tests passed; two opt-in Vulkan tests were skipped here.
- `bend PROOF.bend` and `bend PROOF.bend --verdict` both returned
  `ALL PROOFS CHECK`. These cover existing safe Bend laws, not native queries.
- [The ordinary application build](build.log) completed. The final
  [checkpoint/reference checks](checkpoints.log) passed after adding GPU evidence
  to the required validation-reuse artifacts; their opt-in Vulkan test was skipped.
- Native driver fixtures cover unsupported/disabled collection, genuine zero,
  fractional periods, wide ticks, unambiguous/ambiguous wrap, invalid CPU bounds,
  query creation/read/synchronization failures, delayed availability and missing
  tails. Synthetic readers reject forged intervals and malformed streams.
  [The final GPU fixture run](gpu-fixtures.log) passed all seven test groups.
- The first opt-in integration attempt reported incomplete completion; its
  temporary attempt evidence was removed by the test harness, so its specific
  cause cannot be recovered. [integration-initial.log](integration-initial.log)
  retains the unsuccessful test result.
- The next integration reached archived-runtime recovery and retained four valid
  GPU intervals, but failed the unchanged resource freshness rule: a heap-sample
  gap was 1,007,383,440 ns, exceeding one second.
  [integration-failure.json](integration-failure.json) retains the classification;
  [the test log](integration-monitoring-failure.log) contains its embedded summary.
  This is an incomplete attempt despite available GPU measurements. Neither
  failure is promoted to success by the later completed invocations.
- [An additional recovery test](integration-confirmation.log) also retained four
  measured GPU intervals but observed a 1,043,769,686 ns heap-sampling gap.
  [Its classification](integration-confirmation-failure.json) remains a monitoring
  failure. The combined opt-in suite therefore remains unsuccessful on this
  environment; the separately retained public/capture/recovery successes above
  do not replace those failures or weaken the freshness requirement.

Full artifacts live outside disposable build output under
`/home/aivv/megascene-gpu-evidence`. The compact index here is not a substitute
for that archive. The native runtime and frozen inputs were copied before each
retained invocation. The full-schedule run preceded reader hardening and an
additional query-error forwarding path; the final reader recheck and subsequent
integration checks are recorded separately rather than relabeling those bytes.
