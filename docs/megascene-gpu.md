# Static Megascene GPU execution evidence

Issue #52 adds actual Vulkan timestamp queries to static observations, their
separate validation replays, and opening captures. The normal public invocation
in [the static guide](megascene-static.md) enables collection. The legacy demo
and Light Atelier benchmark paths do not allocate timestamp queries.

The selected graphics/presentation queue supplies `timestampValidBits`; the
selected physical device supplies `timestampPeriod`. Queue support is determined
by nonzero valid bits, without requiring timestamps on every graphics queue.
The Vulkan [timestamp query specification](https://docs.vulkan.org/spec/latest/chapters/queries.html#queries-timestamps)
defines these properties and marker/availability behavior.

## Scope and collection

The coarse interval `submitted_frame_top_to_bottom` starts at `TOP_OF_PIPE`
after resetting that submission's query pair and ends at `BOTTOM_OF_PIPE`
after the final presentation-layout barrier. It covers submitted main/ground/HUD
work, a shadow refresh when required, and intervening GPU dependencies. A reused
shadow map does not imply an executed shadow pass. The scope excludes host mesh
preparation/copying, command recording, submission calls and presentation-engine
completion. Queue dependencies can contribute elapsed time; this is not a hardware
utilization counter or physical display latency.

Each successful submission records its own ordinal and the explicit Bend frame
ordinal. A fixed pool holds 3,721 unique pairs, the maximum admitted static
schedule. Pairs are never reused within an attempt. Collection requests 64-bit
results with per-query availability, without `WAIT_BIT`, after the renderer's
existing frame fence. An unavailable pair stays pending and retains its original
identity when collected later. The first successful synchronization time bounds
execution even if query retrieval is delayed further.

Normal teardown uses the existing device-idle wait, resolves every remaining
pair, then destroys the pool. No measurement-only GPU wait is added. Teardown
collection is outside the CPU frame population and remains attached to the
originating submission. A failed synchronization or query read is retained as
`collection_failure`; a still-unavailable final pair is `incomplete`. Process
termination can leave only a submission or a `not_ready` observation. Reporting
retains that missing final interval instead of dropping it.

CPU `fence_wait`, `acquire`, and `submit_present` remain host wall-time stages.
Query retrieval/logging occurs after the fence marker and is included in the
following CPU `vertex_upload` grouping and enclosing renderer/frame interval.
Query recording is included in command-record time; successful submission
logging is included in submit/present time. Startup query setup is included in
native geometry/renderer time. Stage sums do not define total frame time.

## Raw evidence and validity

`gpu.jsonl` is an append-only, flushed `megascene-evidence/1` stream in the
durable attempt directory. It has its own contiguous sequence and the same
campaign/series/attempt identities as other streams. Records are:

- `gpu_capability`: queue family, capability/collection status, nanoseconds per
  tick and exact binary32 period bits, valid-bit width, capacity, scope and stages.
- `gpu_submission`: successful submission, originating frame, and monotonic CPU
  time immediately before the submit call.
- `gpu_interval`: origin, collection frame or teardown phase, first completion
  bound, raw tick/availability pair, Vulkan result, status/reason, range status,
  exact modular tick delta and resolved nanoseconds when valid.
- `gpu_complete`: total successful submissions after final collection.

All integer counters/times use exact decimal strings. Unavailable ticks are null;
available zero ticks and zero intervals remain numeric zero. Resolved nanoseconds
are a derived finite JSON number because a binary32 period may be fractional.
Raw ticks and period bits retain the exact inputs for independent reconstruction.
The timestamp period is a conversion factor, not an accuracy claim.

The native resolver and independent Python reader check valid bits, finite
positive period, unsigned 64-bit CPU bounds, available raw ticks within range,
and a CPU submission-to-completion envelope shorter than one full GPU wrap.
Modular subtraction then admits a single wrap. A GPU duration must fit the CPU
envelope with one tick for endpoint quantization and the unsigned 64-bit
nanosecond range. Ambiguous wrap, invalid CPU intervals and out-of-range ticks
carry no measured value. This does not correlate CPU and GPU clock epochs.

The reader checks origins, stream identities/order, metadata consistency,
availability, exact tick arithmetic, resolved values and terminal uniqueness.
Damaged tails stay on disk and only their valid prefix is consumed. The attempt
result checks submission times against their originating CPU frame and exposes
`gpu_execution` with capability, per-origin intervals, status counts and separate
startup/warm-up/ordinary descriptive distributions. The manifest also exposes
the actual capability. Missing submission or final records remain incomplete.

Unsupported queues preserve valid CPU observations while preventing GPU
conclusions. Disabled, failed or incomplete required collection prevents complete
required evidence. No timestamp availability result overrides missing supervision,
state validation, fidelity review, sample minimums or instrumentation calibration.
All benchmark/performance qualification remains explicitly unqualified.

## Verification

`tests/native_gpu.cpp` supplies deterministic Vulkan driver responses to the
production query recorder. Its serialized evidence is independently checked by
`tests/test_megascene_gpu.py`: supported and unsupported queues, disabled
collection, zero/fractional values, 64-bit counters, one wrap, ambiguous wrap,
invalid CPU bounds, out-of-range bits, delayed availability, pool/read/sync
failure and missing tails. Synthetic report fixtures reject corruption,
duplicates, changed origins and forged intervals. They never represent real
benchmark samples.

The opt-in static Vulkan integration checks all four submitted intervals,
including the last pair collected during teardown, along with archived-runtime
recovery, separate capture and controlled startup failure. Retained full-schedule
evidence is indexed in [the issue #52 validation directory](validation/megascene-gpu/README.md).
These native/driver invariants are runtime/reference evidence. Existing safe Bend
proofs do not formally prove them.
