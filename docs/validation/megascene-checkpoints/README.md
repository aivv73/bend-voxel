# Static checkpoint validation evidence

This directory retains the issue #51 verification summary. Full runtime artifacts,
frozen inputs, canonical payloads, frame/resource streams and unsuccessful
attempts remain in the durable archive identified by `results.json`. The compact
files here are an index, not a replacement for those reproduction bundles.

The real runs use the accepted static schedule: one startup frame, 120 warm-up
frames and 3,600 measured frames, seed 45, full geometry, 1920 × 1080, protected
anchors and a 2,048 detached-fragment budget. Each configuration has its own
complete separate validation replay and a fresh timed process. The thread
comparison checks the same application artifacts at 1, 6 and 12 threads.

The final numeric results and exact archive references are in
[results.json](results.json), including canonical checkpoint/per-body hashes.
[thread-comparison.json](thread-comparison.json) retains the exact logical
comparison outcome and separate raw work inventories.
[failures.json](failures.json) indexes retained unsuccessful
observations; none supplies a passing benchmark result.

| Preset | Threads | Occupied cells | Owners | Replay frames | Validation duration | Timed frames | State/native checks |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Small | 1 | 10,503,360 | 21 | 3,721 | 62.817 s | 3,721 | Pass |
| Small | 6 | 10,503,360 | 21 | 3,721 | 60.152 s | 3,721 | Pass |
| Small | 12 | 10,503,360 | 21 | 3,721 | 58.244 s | 3,721 | Pass |
| Large | 6 | 42,096,576 | 81 | 3,721 | 221.693 s | 3,721 | Pass |

Validation duration includes independent references, replay and its checks; it is
not a timed benchmark result. Small runs retained 204 cuboids, 387 tree nodes,
1,164 surface rectangles and 6,984 vertices. The large run retained 816 cuboids,
1,551 tree nodes, 4,592 surface rectangles and 27,552 vertices. The final matrix
required one additional validation attempt for small/12 and one for large/6
after monitoring failures. Their raw evidence and failure summaries remain
alongside the successful attempts. Earlier development failures are also indexed;
outer failure summaries and their validation summaries describe the same worker.

## Scope

Passing static state, surface, native-cache and visibility checks do not establish
visual feature quality, instrumentation calibration, responsiveness, a capacity
endpoint, or the complete implementation acceptance of issue #47. Timed checkpoint
construction is included in frame work. Validation duration is separate and
charged to the campaign. Hash equality is practical runtime evidence, not a
formal proof of unsafe Bend or native geometry.

Small references independently expand seven tractable fixtures: signed partial
face contact, material interfaces, edge separation, corner separation, unanchored
material, protected support, and a cavity. The full districts use sparse sweeps,
actual tree/geometry checks and per-frame native evidence without dense expansion.
Native fixtures reject overlap, missing/duplicate coverage, incorrect material,
wrong winding, wrong tree counts and stale mesh contents. Equivalent cuboid and
rectangle partitions preserve canonical equality and retain distinct work counts.

## Regression and runner checks

- [Regression suite](tests-final.log): Bend runtime suites, native cache checks,
  independent admission/reference checks and 48 Python tests; the two opt-in
  Vulkan tests are exercised separately below.
- [Checkpoint fixtures](checkpoints-final.log): exact encoding, signed zero,
  equivalent partitions, corrupted/incomplete evidence, sparse references and
  artifact/configuration reuse guards.
- [Static Vulkan integration](static-integration-final.log): complete short public
  invocation, separate capture, archived-runtime relocation and controlled display
  failure.
- [Validation Vulkan integration](validation-integration-final.log): validation-only
  operation followed by a fresh timed process, exact agreement, changed-thread
  rejection, corrupted validation resources and stale executable rejection.
- [Proof check](proof-final.log) and [verdict](verdict-final.log): both report
  `ALL PROOFS CHECK`; their formal scope remains the existing safe Bend claims.
- `make build` completed successfully for the ordinary application after the
  final Vulkan matrix.

The supervisor keeps full raw checkpoint records on disk while retaining only
CPU sequence/time metadata and complete frame records in memory. This avoids
large checkpoint payloads delaying required resource supervision. The retained
monitoring stops remain failures; the one-second freshness rule was not relaxed.

The original campaign allowance was 7,200 seconds. An unnecessary early
600-second development entry was explicitly cancelled. A later prelaunch
coordinator import interruption was retained and recovered with a labelled
summary; resumption explicitly added 300 seconds without resetting prior elapsed
time. The campaign ledger records every addition, cancellation and attempt.
