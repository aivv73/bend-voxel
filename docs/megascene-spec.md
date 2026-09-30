# Megascene implementation handoff

**Status: accepted for [#45](https://github.com/aivv73/bend-voxel/issues/45) on 2026-09-28.**
This is planning work. Production implementation, architectural optimization,
and the final scale measurements remain outside this effort. The user accepted
the complete handoff, including both annexes and the implementation acceptance
checklist, and confirmed shared understanding before publication.

## Authority and traceability

This file is the implementation entry point. It owns the concrete presets,
schedules, evidence schema and acceptance checklist resolved in #45. Existing
policies remain authoritative in the exact decision resolutions below; this
file links them instead of reproducing competing copies. A conflict must be
resolved explicitly before implementation, not silently interpreted away.

The concrete [workload recipe](megascene-workload.md) and
[evidence schema/examples](megascene-evidence.md) are annexes owned by this
handoff, not competing policy sources. This decision explicitly corrects the
proxy-pixel wording in #44 and supplies the narrow calibration-control exception
below. All other earlier policy requirements remain in force.

| Subject | Canonical resolution |
| --- | --- |
| World composition and independent scale dimensions | [#38](https://github.com/aivv73/bend-voxel/issues/38#issuecomment-5858504682) |
| Limit categories, responsiveness, resources and stopping | [#39](https://github.com/aivv73/bend-voxel/issues/39#issuecomment-5858595531) |
| GPU timing and memory research | [#40](https://github.com/aivv73/bend-voxel/issues/40#issuecomment-5858414952) |
| Scenario families and scale search | [#41](https://github.com/aivv73/bend-voxel/issues/41#issuecomment-5862387197) |
| Measurement populations, calibration and reproduction | [#42](https://github.com/aivv73/bend-voxel/issues/42#issuecomment-5862953507) |
| Accepted representative world sketch | [#43](https://github.com/aivv73/bend-voxel/issues/43#issuecomment-5863131984) |
| State correctness and rendering fidelity | [#44](https://github.com/aivv73/bend-voxel/issues/44#issuecomment-5863570351) |

The reviewed [prototype at c60a880](https://github.com/aivv73/bend-voxel/blob/c60a880/docs/prototypes/megascene-43.md)
establishes representativeness, not exact geometry, measured inventories or
approved scale presets. Domain terms follow [CONTEXT.md](../CONTEXT.md); the
current representation follows [ADR 0001](adr/0001-sparse-cuboid-world.md).

## Compatibility and scenario coverage

### Light Atelier compatibility

Preserve the default Light Atelier demo, its controls and behavior, all five
legacy benchmark cases, their defaults, and existing report fields and meanings.
Compatible additive fields are allowed. Megascene uses a separate entry point
and versioned reports. Elapsed times remain observations, not frozen expected
values. The existing [benchmark guide](stress-benchmark.md) describes the legacy
interface.

In particular, do not reinterpret the legacy `max_bodies` field: it counts
detached fragments, not all live owners. Megascene must distinguish total,
anchored, detached and moving body counts explicitly. Legacy measurements do
not acquire Megascene qualification merely by retaining their old passing flag.

### Six cases cover seven families

Launch six independent behavioral cases: static rendering, camera traversal,
picking, localized edit, support severing with concurrent fragments, and long
irregular destruction history. Each case supplies cold-start evidence from its
fresh process. No additional startup-only case is required. Each case still
needs its own applicable validation and evidence.

### Single-event measurement limitations

Keep the localized workload at one cut and preserve the intended support
sequence. A case with fewer than 100 accepted edits in its declared population
reports its edit percentile gate as inconclusive. Correctness and capacity may
qualify; an applicable inconclusive edit gate prevents a full interactive pass.
Observed edit latencies and the worst-edit observation remain reportable.

Do not add cuts, pool ordinary attempts, or borrow the history case's edit
population to manufacture a passing percentile. A qualifying single-event
repetition study is a separate future decision, not a prerequisite for accepting
an implementation that truthfully reports this limitation.

## Accepted presets, schedules and evidence format

### Fixed world presets

Primary seed: **45**. Independent diagnostic seed: **46**.
These identify reproducible content, not statistical coverage.

| Preset | Horizontal envelope | Neighborhoods | Initial owners |
| --- | --- | --- | --- |
| `small` | 640 x 640 cells (64 x 64 m) | 2 x 2 | 21 |
| `large` | 1,280 x 1,280 cells (128 x 128 m) | 4 x 4 | 81 |

Each 32 x 32 m neighborhood contains one building with an interior, three
independently owned supported spans, and one irregular assembly. One continuous
terrain owner crosses the whole district, giving `1 + 5 * neighborhood_count`
initial owners. All start anchored; protected footings and removable terrain
retain the accepted material policy. Each span has two real support paths.

The recipe supplies genuine relief, cavities and geometric/material
variation between neighborhoods. Seeds change actual content rather than merely
relabel identical geometry. Exact boxes, targets, cameras and diagnostic controls
are specified in the workload annex. Its independently calculated
source inventories are expectations to verify against the future generator,
not claims of achieved production geometry or measured limits.

`large` is a fixed acceptance candidate, not an assertion that it runs successfully
or is demanding on every machine. Unexpected admission/completion failures remain
visible and cannot be hidden by automatically shrinking either preset.

### Replay lengths and action cadence

Use **120 warm-up frames and 3,600 measured frames**, with a fixed simulation
step of binary32 `1 / 60` seconds. Measured frame ordinals below are zero-based.
Startup and warm-up remain outside measured populations.

| Case | Accepted action cadence |
| --- | --- |
| Static | Fixed opening view; picking and edits disabled. |
| Traversal | Frozen near, interior, cavity, far and return camera route; picking disabled. |
| Picking | The same camera route with a frozen expected hit/miss ray sequence. |
| Localized edit | One 20 cm terrain cut at measured frame 0, then unchanged-world observations. |
| Support | Six 20 cm support cuts at frames 0, 6, 12, 18, 24 and 30; each pair severs the two paths of a different span. Require all three released spans to be moving throughout frames 31 through 42 inclusive. |
| History | 120 accepted 20 cm cuts at frames `12 * i`, for `i = 0..119`; terrain and structures, irregular placement and revisits to prior damage. Named history checkpoints after cuts 12, 48 and 120, in addition to every required edit checkpoint. |

Retain the engine's update order: physics first, then edit, then view/picking and
rendering. A newly released body first moves on the next frame. Geometry and
target placement must make the specified support overlap possible under actual
floor stopping; an intended window is not evidence that it occurred.

All exact coordinates, camera poses, rays, expected targets, per-frame views and
checkpoint locations must be deterministically resolved and frozen before timed
execution. Missing or unreachable targets invalidate a configuration.

The frame preset does not guarantee ten seconds of measured wall time. A faster
run remains population-insufficient where applicable. A longer fixed schedule
requires a newly declared configuration and fresh applicable validation; never
extend an active schedule based on elapsed time. Short moving windows retain
their own sample counts. The legacy 5,000-total-frame cap must not silently clamp
a separately requested Megascene schedule.

## Minimum implementation acceptance coverage

Accept the suite by demonstrated behavior and truthful evidence,
without requiring a discovered limit or every case meeting responsiveness gates.
Every required positive case must successfully complete validation and the full
intended timed workload, with correct state, rendering and required visual
quality. Truthfully reporting an unexpected failure or incomplete positive case
does not satisfy that acceptance item. Explicitly insufficient timing populations
or failed responsiveness gates may remain acceptable for implementation acceptance
while preventing the corresponding performance or interactive claim. Deliberate
negative fixtures instead pass by producing their specified outcome and evidence.

| Coverage | Required minimum |
| --- | --- |
| Existing behavior | Existing proof/runtime tests and face diagnostic; all five unchanged Light Atelier cases at 640 x 360 and 1920 x 1080; interactive control, lighting and reset review. |
| Small preset | All six cases at 1920 x 1080, at each of 1, 6 and 12 threads; a separate complete validation replay and one timed attempt per configuration. |
| Repeatable comparisons | Static and history small-preset cases at each of 1, 6 and 12 threads: three timed attempts total per configuration, including the preceding attempt when eligible. |
| Larger preset | All six cases at 1920 x 1080 and 6 threads; validation plus one timed attempt each. |
| Lower-resolution diagnostic | Small-preset static and history at 640 x 360 and 6 threads; validation plus one timed attempt each. |
| Proxy diagnostic | Paired full-geometry/proxy traversal and picking on the small preset's separate proxy route at 1920 x 1080 and 6 threads; validation plus one timed attempt per profile/case. Also run the four paired compact-reference configurations that exercise hysteresis and aimed-at suppression within reach. These new routes cannot reuse the primary traversal's validation. |
| Diagnostic controls | At small/seed 45/1080p/6 threads, validate and complete: spread-static; fill-support and fill-history; body-rich-history; material-detail-static and localized; surface-detail-static; 12- and 48-edit history prefixes; one- and two-span release variants. Record all achieved couplings and declared schedule changes. |
| Independent references | Small exact occupancy/material, connectivity, carving, picking and exposed-surface fixtures covering #44, including numeric boundaries and rollback. |
| Failure handling | Deterministic/injected cases for malformed requests, unsupported numerics, rejected edits, incorrect state/rendering, quality failure, missing evidence, monitoring loss, reserves, deadlines, allocation failure and crash/device loss. Do not force physical exhaustion. |
| Search and persistence | Report fixtures for only passes, only failures, mixed causes, non-monotonic results, repetition rules, refinement, interruption and resume with an explicitly declared additional allowance. |
| Reproduction | Recover archived runtime artifacts and a frozen workload/schedule, reproduce inventory and state/geometry checkpoints, and retain all failed/incomplete attempts. |

Run generation/reference admission checks for both seeds on both fixed presets.
The Vulkan matrix uses primary seed 45; the additional-seed check near a future
consequential boundary remains required by #41. The acceptance matrix does not
require finding such a boundary merely to exercise seed 46.

Run the accepted 72-control calibration matrix, applying its evidence and noise
rules. Calibration outcomes remain separate from functional implementation
acceptance: a faithfully executed but noisy, insufficient or excessive-overhead
calibration leaves the affected performance comparisons unqualified. It cannot
be called a calibration pass. The reference recorder, metric arithmetic, pairing,
threshold classification and persistence must also pass deterministic tests.
Any claim that implementation acceptance additionally guarantees performance
readiness must require the applicable actual calibration passes and sample
minimums; the functional checklist alone supplies no such guarantee.

One attempt is coverage evidence, not a confirmed endpoint. Three attempts do not
override failed gates or incomplete evidence. Performance calibration is separate
and must cover the configurations used for performance claims. Any required
acceptance item left unfinished means implementation acceptance is incomplete.

The initial campaign allowance remains two hours, including validation and
calibration. If required acceptance work does not fit, preserve progress and
request a declared further allowance; do not drop checks, extend automatically,
or call incomplete acceptance complete. No acceptance run must discover an
architectural limit.

## Accepted proxy-threshold reconciliation

The #44 resolution calls the existing 80/100 thresholds logical pixels. The
current renderer actually evaluates
`800 * (render_height / 360) * group_radius / (view_depth - group_radius)`
against 80/100. Therefore the switching metric scales with render resolution:
the same world/view has three times the value at 1080p as at 360p. This is a
discrepancy between that wording and the simultaneously accepted requirement to
freeze the existing rules. See [the current implementation](../src/vulkan/native.cpp).

Preserve the current resolution-dependent behavior and
explicitly correct the #44 description to render-pixel thresholds. Do not
silently normalize away the height factor. A resolution-independent 80/100
logical-pixel rule would instead be a newly chosen diagnostic profile.

Also preserve the actual tile-key origin: each X/Z index is
`floor((body_bounds_center_in_cells + 320) / 640)`. Four eligible members must
share that key; merely placing four small bodies inside a nominal 64 m envelope
does not establish a proxy group. Eligibility, actual selection, hysteresis,
aim suppression and retained full-mesh/shadow work require explicit validation.
The review poses must use this accepted render-pixel metric.

## Accepted evidence format

Use a versioned JSON manifest and per-attempt summary, with append-only JSONL
streams for raw samples, resource/allocation events, action/checkpoint evidence
and search progress. Store local generated results under
`build/megascene/<campaign>/<series>/<attempt>/`. Retained campaigns must also
have an archive or immutable retrieval location; an ignored build directory
alone is not durable reproduction evidence.

Use explicit status/reason/scope fields and separate correctness, rendering,
quality, completion, numeric validity, measurement qualification, responsiveness
and termination results. Preserve measured zero as a value, never a missing-data
sentinel. Exact large integer fields use canonical decimal strings; deterministic
floating-state records use their binary32 bit patterns. Use SHA-256 for artifact
and canonical checkpoint identities, with schema identity and mismatch evidence.
Hash agreement is runtime evidence, not a formal proof.

The field definitions and clearly marked synthetic success,
insufficient-population, rejection, policy-stop and interrupted-search examples
are in the [evidence annex](megascene-evidence.md). No synthetic example is an
observed Megascene run.

## Accepted calibration protocol

The implemented on/off control interface and diagnostic equality scope are
described in [diagnostic calibration controls](megascene-calibration-controls.md).

This handoff accepts an **explicit, narrow exception to #44 for diagnostic calibration
controls only**. Keeping all checkpoints enabled
in both variants cannot measure their cost, while omitting them cannot establish
the full intermediate-state evidence required of qualifying benchmark attempts.

Calibrate static and history cases on both fixed presets at 1, 6 and 12 threads,
using the primary full-geometry profile at 1920 x 1080. These are 12 distinct
configurations. Each receives six fresh-process controls in the order **off, on,
on, off, off, on**, forming three adjacent pairs with alternating order: **72
controls** in total. Eligible identical on runs may also supply acceptance
evidence; do not rerun them merely to fill another checklist row.

Both variants use the same runtime artifacts, workload, schedule, warm-up and
rendering settings. Required resource monitoring and continuous allocation
accounting stay enabled. Both retain an identical minimal reference recorder:
monotonic timestamps at frame/edit boundaries, frame/action ordinals, population
classification and actual action acceptance/removal outcomes, written to a
preallocated shared buffer. A supervisor drains committed records to
`reference.jsonl` during execution and after termination, including a worker
crash. Use the same bounded recording/draining path in both variants and retain
sequence/gap evidence. Preflight its capacity; overflow, lost committed records
or failure of required persistence invalidates the control. This common recorder
and its persistence cost are part of the comparison baseline, not free work.

**On** enables the complete qualifying path: detailed stage timing, supported
GPU queries, intermediate state/geometry checkpoint construction and comparison,
and ordinary logging/reporting. Checkpoint costs remain inside their normal
measured paths. All #44 qualifying-run requirements remain in force.

**Off** disables that additional work, including intermediate checkpoint
construction. It is a diagnostic control, never a qualifying benchmark attempt,
capacity endpoint or interactive endpoint. Record disabled evidence explicitly.
Before controls, perform separate complete validation replays of both modes,
with thorough auditing outside performance samples. Each actual off control
also verifies initial/final canonical state outside steady-state measurements
and retains its complete scalar action-outcome sequence. Compare these with the
validated schedule and paired on run. This supplies initial/final and outcome
agreement; it does **not** establish intermediate state equality in that actual
off control. No audit pauses enter its measured schedule.

Compare applicable ordinary mean/p95/p99 and accepted-edit p95 without pooling
raw populations or subtracting overhead. Require sufficient ordinary populations
in every control, sufficient accepted-edit populations for history's edit
statistic, and the applicable equivalence evidence above. For each statistic,
declare the controls noisy when the largest off value exceeds the smallest by
more than 5%; noisy controls leave calibration inconclusive. Otherwise every
paired increase must be at most 5% for that configuration to qualify. This is a
conservative operational rule, not a statistical confidence claim. Preserve all
individual values and maxima. Invalid or zero denominators cannot pass a ratio.

Calibration does not relax the two-hour initial allowance. Missing, failed or
inapplicable calibration prevents the associated performance claim while
preserving independently valid correctness/capacity evidence.

The supported claim is added cost relative to the documented common recorder
and mandatory resource accounting, not zero total measurement cost. Calibration
qualifies only its actual tested workload regimes/configurations. The `large`
name alone does not demonstrate broader demanding-regime coverage. Traversal,
picking, localized/support, proxy, other resolutions and further scale regimes
need their own applicable calibration before trusted performance comparisons;
the minimum acceptance observations do not silently acquire that qualification.

## Implementation boundaries and planning acceptance

Provide a separate Megascene runner/configuration surface. Strictly reject
malformed, unsupported or contradictory requests and record requested/effective
settings; do not inherit legacy numeric defaulting/clamping. Freeze the complete
resolved schedule before validation/timing. Engineering choices such as module
layout, transport buffering and helper implementation remain implementation work
provided they satisfy the specified workload, evidence, resource and timing
contracts. They do not authorize new geometry, altered quality, weakened checks
or a different measurement population.

Implement instrumented workload generation, replay, validation, capture/review,
resource supervision, reporting, recovery and bounded search. Preserve Light
Atelier. Do not add streaming, indexing/representation replacement, compaction,
cache redesign, new rigid-body behavior or performance optimizations as hidden
parts of this handoff. Any later parallelism change follows the repository's
representative Vulkan and 1/6/12-thread evidence requirements.

The user accepted the concrete annexes and minimum implementation acceptance
checklist and confirmed shared understanding on 2026-09-28. All exposed planning
choices and policy conflicts are resolved. Successful recipe probes, document
checks and existing Bend proofs support this handoff; they do not establish
production implementation acceptance. Any later change to these product or
measurement requirements needs an explicit new decision.

Implementation acceptance is a later evidence-backed checklist result, distinct
from both planning acceptance and qualified performance results. Discovering
limits is a subsequent bounded campaign: preserve the tested configurations,
confirmed endpoints, unstable points, policy stops and untested ranges. Neither
this document nor successful suite acceptance asserts an architectural maximum.

No universal proof of unsafe/native geometry is claimed. Such properties need
the runtime/reference evidence in #44 and this handoff. Preserve existing safe
claims in `LAWS.bend`; add only a brief scope-qualified pointer to accepted
planning rules, without turning those rules into unsupported formal claims.

## Issue #56 supplementary validation views

On 2026-09-28, the user approved six supplementary close-up validation captures
because the specified support overview occludes some new cut surfaces. Preserve
the primary camera, all six cut times, timed workload, and frames 31/42 overview
captures. Freeze one close-up per action before execution, render the unchanged
post-cut world only in validation, and restore the primary view without advancing
physics or action ordinals. Retain both overview and close-up assessments; a
readable close-up can cover the same action's occluded cut feature, while any
incorrect geometry still fails rendering correctness. These extra renders do not
enter CPU/GPU performance populations. The primary schedule remains support-v1;
its complete archived schedule identity includes the supplementary view inputs.

## Issue #68 supplementary validation views

On 2026-09-30 the user approved frozen supplementary shadow views for all eight
proxy configurations (both worlds, traversal/picking, full/proxy), and frozen
exposed-face views for cuts 88, 89, 98, 99, 108, 109, 118 and 119 in the six
affected small-history configurations. The accepted proposals are
[proxy review](validation/megascene-acceptance/proxy-review-proposal.md) and
[history review](validation/megascene-acceptance/history-review-proposal.md).

Freeze each camera before execution and bind it to the original named feature,
frame, action where applicable, and actual state/geometry checkpoint. Render the
same world/frame during validation only. Preserve every primary camera, picking
ray, action time, physics step and timed workload. Retain original captures and
corrected assessments; supplementary coverage applies only to major proxy
shadows or the named history cuts' removed material and exposed surfaces.
Incorrect geometry still fails.

Restore and audit the original view, world geometry, cache, proxy hysteresis and
full-mesh shadow state. Exclude supplementary rendering/restoration from timed
CPU/GPU populations. Require fresh applicable validation; approval alone cannot
turn an original unreadable capture into a visual pass.
