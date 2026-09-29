# Issue #64 calibration control evidence

The [results index](results.json) identifies the real Vulkan bundles, validation
replays, application and schedule hashes, evidence digests and local durable
archive locations. The archive retains actual executable/native/shader bytes,
frozen inputs, full validation evidence, resource/allocation streams and the
preallocated common recorder's shared buffer and drained JSONL. This index
does not replace those bundles.
The [static pair](static-pair.json) and [history pair](history-pair.json) contain
descriptive on/off mean and percentile values with sample counts and ratios.
They subtract no instrumentation cost and make no calibration pass claim.

| Real pair | Validation | Common frame/action records per control | Endpoint and scalar outcome agreement | Qualification |
| --- | --- | ---: | --- | --- |
| Small static, 6 threads, 1 warm-up + 2 measured | Separate complete replays of the declared development prefix pass | 4 / 0 | Pass | Diagnostic prefix only |
| Small history, 6 threads, 120 warm-up + 3,600 measured | Separate complete 3,721-frame replays of both modes pass before gated controls | 3,721 / 120 | Pass | Off is diagnostic; no calibration pass |

The full history pair used the same worker and schedule hashes in both modes.
Each control persisted 4,081 common records. The off stream has only worker
start, initial/final canonical checkpoints and completion; it has no GPU query
stream or detailed stage, frame, action, native-audit or intermediate checkpoint
records. Its mandatory resource and allocation streams remained active. The
on stream retained the full qualifying instrumentation and checkpoints. Both
controls finished normally, and the paired reader found identical initial/final
canonical digests and all 120 scalar action outcomes.

The off result explicitly reports intermediate checkpoints, detailed inventory
transitions, stage timing, GPU queries and ordinary logging as disabled. Matching
endpoints and action outcomes do not establish equal transient state. Off state
correctness, capacity and interactive results remain inconclusive; this pair is
not a benchmark calibration pass or endpoint. The accepted 72-control matrix,
noise bounds and performance qualification belong to later calibration work.
No instrumented cost is subtracted from either observation.

Synthetic off-report tests corrupt endpoint records, insert disabled fields,
lose committed slots, remove mandatory resources, add an unexpected GPU stream
and simulate worker loss. The supervisor crash fixture independently retrieves
committed reference records after the worker exits. These runtime/reference
checks cover the unsafe-dependent invariants; the Bend proof result does not
claim to prove them.
