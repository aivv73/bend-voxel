# Issue #65 calibration series evidence

The [plan](plan.json) contains the exact 12 static/history × small/large ×
1/6/12-thread configurations and 72 ordered controls. The
[results index](results.json) identifies a complete real Vulkan series, its
durable campaign archive, both separate validation replays, six control
bundles, hashes of their retained evidence, and the computed assessment.
The index is a locator; the actual runtime bytes and raw records remain in
the durable archive.

The demonstrated series is primary small/static, seed 45, 6 threads, full
geometry at 1920 × 1080, with the accepted 120 warm-up and 3,600 measured
frames. Both mode validations passed their complete 3,721-frame replays.
The six fresh controls completed normally in `off/on/on/off/off/on` order.
All three adjacent pairs passed the initial/final canonical-state and scalar
action-outcome comparison. Static has no accepted-edit statistic.

Each control has 3,600 ordinary frames, but the measured intervals lasted only
2.016–5.526 seconds. The required ten-second minimum therefore makes every
statistic **insufficient**. The assessment retains all individual mean/p95/p99
values, off variation and paired on/off ratios as observations. In this series,
observed off p95 and p99 variation also exceeds 5%, and every observed on/off
ratio exceeds 2. The short intervals prevent those observations from becoming
a qualifying noise or overhead decision. No cost was subtracted, no retry was
launched, and no calibration pass or performance readiness is claimed.

The archive's `assessment.json` records each pair and individual statistic.
Its `calibration.json` can be passed to the existing report reader, where its
exact scope and `insufficient` status keep the performance gate unqualified.
The three on controls remain candidates for separate functional acceptance
review. Off controls establish no transient-state equality and cannot enter
benchmark passes or endpoints.
