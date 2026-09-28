# Megascene evidence specification

**Accepted annex to [the implementation handoff](megascene-spec.md), 2026-09-28.**
The final handoff decision includes this concrete schema and its examples,
explicit statuses, exact representations and durable archives.
The canonical measurement and correctness policies linked by the handoff govern
which evidence qualifies; serialization does not weaken them.

## Files and identity

Use schema identity `megascene-evidence/1`. A reader must reject an unsupported
major schema for qualification; it may retain the uninterpreted artifact.
Extensions go under an `extensions` object and cannot override required fields.

| Artifact | Required content |
| --- | --- |
| `campaign.json` | Campaign ID, UTC start, policy-resolution links, initial allowance, append-only records of any explicitly declared additional allowance, reference platform and archive location. |
| `series.json` | Series ID, ordered control and attainable settings, fixed seed/profile/thread/resolution, generator and schedule identities, diagnostic invariants/tolerances and search state references. |
| `manifest.json` | Attempt ID and kind, parent series, requested and effective configuration, actual executable/library/shader/generator hashes and retrievable locations, source/dirty/build provenance, hardware/software/runtime environment, clocks and counter capabilities, numeric admission and evidence references. |
| `inventory.json` | Requested controls, achieved envelope and occupied bounds, cell size, exact cells by material/role, protected cells, total/anchored/detached/moving bodies, cuboids, exposed area and surface rectangles, density numerator/denominator, validation identities. |
| `schedule.json` | Fixed step bits, warm-up and measured frame counts, explicit per-frame camera/aim states, actions with exact resolved target/radius/ordinal/expectations, review views, required checkpoints and named moving/history populations. |
| `cpu.jsonl` | Frame/stage/edit records with originating frame/action, clock identity, interval boundaries, duration, population and status. |
| `reference.jsonl` | For calibration controls, the common minimal frame/edit recorder and scalar action outcomes, drained and persisted during execution through the identical reference path in both modes. |
| `gpu.jsonl` | Originating submission/frame, query interval definition, raw ticks, period, valid bits, availability/range status and resolved interval. |
| `resources.jsonl` | Actual sample times, source, scope/device/heap attribution, process-tree RSS, available RAM, device free VRAM, heap usage/budgets, errors/gaps and observed reserve crossings. |
| `allocations.jsonl` | Every successful Vulkan allocation/free, stable allocation ID, size/type/heap, live and peak ledger totals; allocation errors are separate failed-operation records. |
| `actions.jsonl` | Scheduled/actual action identity, expected/actual target, acceptance/removal status, before/after inventory, and rejection/no-op details. |
| `checkpoints.jsonl` | Checkpoint/schema/schedule identities, frame/action phase, canonical state/geometry digests, validation reference, comparison status and mismatch artifact references. |
| `validation.json` | Independent-reference identities/results, complete configuration-specific replay checks, execution duration, numeric-envelope evidence, checkpoint catalog and reuse eligibility. |
| `review.json` and `captures/` | Named feature/view/profile, expected readability, actual result and reviewer, screenshot hash/location, shadow fit and texel coverage; paired full/proxy differences where applicable. |
| `summary.json` | Separate outcome dimensions, applicable sample counts/distributions, validation and calibration references, termination cause, completed prefix, explicit limitations and raw evidence references. |
| `stdout.log`, `stderr.log` | Captured process output, including partial output and explicit collection failures. |
| `search.jsonl` | Chronological proposals/attempts, all results, endpoint confirmation references, unstable/non-monotonic points, tested bounds, gaps, stops and declared resumes. |

Artifact content hashes identify the bytes actually used. Retain the executable,
loaded native library, shaders and generation inputs themselves or immutable
retrievable copies. A source commit, a hash with no recoverable content, or a
saved executable that loads today's library does not reproduce the old runtime.

Require an explicitly configured archive destination outside disposable build
and dist directories before a retained campaign starts. Archive runtime inputs
before execution and completed attempt evidence as the campaign progresses;
verify content hashes and never overwrite a different artifact at the same
identity. Record retrieval paths in the manifest. Do not mark reproduction
complete while required artifacts exist only in a disposable working directory.

Every JSONL record carries `schema`, `record_type`, `campaign_id`, `series_id`,
`attempt_id`, an increasing `sequence`, and `clock_id`/`time_ns` when applicable.
Flush complete records during execution. Write JSON snapshots via temporary file
plus atomic replacement. After interruption, retain a truncated tail as damaged
evidence; consume only complete validated records and never count the tail as a
sample. Record what was lost. Persist completed attempts before launching another.

Under the calibration exception accepted in the handoff, off controls
identify `attempt_kind: calibration_off` and explicitly mark intermediate
checkpoints, detailed inventory transitions, detailed timing/GPU queries and
ordinary logging as disabled. They still retain mandatory resource/allocation
evidence, persisted common reference records and the specified initial/final
state evidence. Do not reconstruct missing checks as passes or reintroduce the
disabled work merely to fill fields. These controls cannot enter benchmark
endpoints. On controls retain all qualifying-run requirements. This is an
explicitly accepted exception, not an implication of choosing JSONL.

## Types, units and missing values

- All discrete counts, frame/action ordinals, raw ticks, integer cell coordinates,
  sizes and integer nanosecond times are canonical decimal strings: `0`, positive
  digits without leading zeroes, or a minus sign followed by a positive integer.
  Unsigned fields reject negative values. No scientific notation or silent
  narrowing is allowed. This also keeps small and large values on one exact path.
- All deterministic binary32 values use eight lowercase hexadecimal digits after
  `0x`. Retain signed zero bits. Reject nonfinite world/view/motion values.
  The fixed simulation step is `0x3c888889`.
- Derived statistical summaries may use finite JSON numbers with an explicit
  unit. Retain exact raw integer samples from which they were calculated. Ratios
  such as density retain their exact numerator and denominator as well.
- Artifact and checkpoint digests are lowercase SHA-256 hexadecimal strings.
  Paths in an attempt are relative to its directory; immutable remote references
  explicitly identify their retrieval location. Do not record unrelated secrets
  from the environment.
- A measurement is `{status, reason, scope, unit, value}`. Its status is one of
  `measured`, `unsupported`, `disabled`, `not_ready`, `not_executed`, `incomplete`,
  or `collection_failure`. Only `measured` carries a numeric value; other statuses
  carry `value: null` and a nonempty reason. A genuine measured zero stays zero.
  Scope names the interval, frame/action, population, process tree, device or heap.
- Check outcomes use `pass`, `fail`, `inconclusive`, or `not_applicable`, with
  reason, scope and supporting evidence. A passing prefix check is explicitly
  scoped to that prefix; it cannot imply complete-case validation.

Record a common monotonic clock identity for supervisor deadlines and CPU event
correlation, plus UTC start time for provenance. Preserve clock resolution and
range evidence. Integer nanosecond storage does not establish nanosecond accuracy.
Decode any native wrapping counter with checked, unambiguous interval arithmetic;
a wider output field alone does not fix a narrow source clock. Keep GPU clocks
separate and retain valid-bit/period evidence rather than inventing CPU correlation.

## Frame and phase definitions

The first usable startup frame contains the complete world and enabled
interactions. Its frame-effect return ends startup. Warm-up then runs the fixed
number of frames; measured ordinal zero follows warm-up. A zero-warm-up explicit
configuration begins its measured interval at that startup return.

An ordinary application frame interval runs from the previous frame-effect return
to the current return. It therefore includes intervening bookkeeping, scheduled
work, required timed checks, logging and waits. Measure an accepted edit from
immediately before its scripted operation through the return containing its
result. Record stages with real begin/end markers and nesting/overlap information;
do not require their sum to equal the frame if they overlap or omit identified
work. Initial generation, initial surfaces, renderer setup, initial upload and
first-frame work have distinct markers within launch-to-first-usable time.

GPU records identify the submitted work actually bracketed by queries. Read them
after existing synchronization, never add a timing-only GPU wait. A final result
retrieved at teardown retains its original frame identity. Final output flush
and teardown are separately reported, never added as fictitious frames or used
to reach the ten-second measured-duration minimum.

Ordinary frames exclude edit frames and include moving frames. Keep the combined
distribution, edit responses, moving window and history phases separate. Record
sample count, elapsed population observation interval, mean, nearest-rank
p50/p95/p99 and maximum. Empty populations have null summaries. Descriptive
percentiles for small populations do not change their qualification status.

## Canonical state and geometry checkpoints

Use canonical UTF-8 JSON with keys in ascending ASCII byte order, no insignificant
whitespace and the exact numeric encodings above. Checkpoint keys and string
values use only the ASCII characters `A-Z`, `a-z`, `0-9`, `_`, `.`, `/`, `:`, `+`
and `-`; free text belongs in separate diagnostic records. Emit these characters
literally, with unescaped slash and no optional Unicode escapes. Reject duplicate
keys, unsupported characters and JSON numeric tokens in a checkpoint payload;
discrete and floating values use the specified decimal/hex strings. Booleans and
null use lowercase JSON tokens. Arrays have specified semantic order; never
serialize pointer addresses or tree allocation order.

The canonical payload contains the mandatory field
`schema: megascene-checkpoint/1`. Compute SHA-256 over that payload object's exact
canonical UTF-8 bytes, without a BOM, prefix, newline or digest field. Store the
digest in the enclosing evidence record, outside the payload. Artifact hashes
still hash the artifact bytes directly; general manifest/log strings need not
obey the restricted checkpoint string vocabulary.

State records include world budget, next ID, action outcomes/history, camera/aim
and schedule identity, then bodies sorted by numeric ID with revision, anchor state,
offset/velocity bits and canonical local material occupancy. IDs/revisions and
ownership remain significant even when total geometry is equal.

Canonicalize material occupancy independently of cuboid partitioning by an exact
boundary sweep: X slabs contain Y slabs containing sorted disjoint Z intervals
labeled with material. Merge touching intervals of equal material, then adjacent
Y slabs with identical Z content, then adjacent X slabs with identical Y content.
Omit empty intervals. Check initial source cuboids for overlap before
canonicalization; a union must not hide duplicated source ownership. During
motion, apply local occupancy checks within each body: different moving owners
can spatially interpenetrate under the existing no-collision model, which is not
in itself duplicated ownership. Use checked integer arithmetic
and sparse boundaries, not dense expansion of the whole large world.

Canonicalize each body's drawable surface coverage separately for each side, material and
integer face plane, using the corresponding two-dimensional interval sweep.
Check missing/duplicate coverage and winding before normalization. Equivalent
rectangle partitions may compare equal; raw cuboid and rectangle counts remain
in the work inventory so equivalent geometry does not conceal changed work.
Record per-body hashes and sufficient canonical data or reproducible inputs to
produce a field/body mismatch report. Hash equality is practical evidence, not
a universal mathematical proof or a replacement for independent references.

Required logical checkpoints include initialization, end of warm-up, each edit,
deliberate rejection/no-op, named motion/history and visual-review points, and
completion. Record post-physics/post-edit logical state and the view used for
that frame. Retain native geometry/cache/draw evidence associated with the same
frame separately; allocation/layout differences are not logical state mismatches.
The complete validation replay checks intermediate evolution even where the timed
schedule has no named checkpoint.

## Summary and search semantics

Keep `state_correctness`, `rendering_correctness`, `visual_quality`,
`numeric_validity`, `schedule_completion`, `measurement_availability`,
`population_qualification`, `calibration`, `responsiveness` and `termination`
separately assessable. Also record whether the complete workload supplies
qualified capacity evidence and whether it supplies an interactive pass, with
explicit reasons. Missing GPU evidence need not erase valid CPU evidence; failed
calibration need not erase independently valid correctness/capacity evidence.

Termination records distinguish normal completion, explicit rejected request,
required-edit rejection, each timeout, each reserve stop, monitoring failure,
allocation error, device loss, unexplained crash and external interruption.
Preserve exit code/signal separately. A known supervisor stop takes precedence
over interpreting its resulting signal as an unexplained crash. A signal alone
is never evidence of allocation exhaustion.

A search point references every attempt and its achieved inventory. A confirmed
endpoint references the exact qualifying repetitions required by #39. Maintain
separate interactive, time-budget and observed-capacity bounds. Unsupported
numeric requests and policy stops remain explicitly categorized; they are not
physical capacity endpoints. Preserve unstable and non-monotonic observations.
An isolated qualifying attempt is not a confirmed endpoint.

## Synthetic reporting examples

The following are **summary excerpts for schema/reporter tests, not measured
results and not complete reproduction bundles**. Fields omitted here still
belong in the full records described above. Each fixture's manifest must mark
`synthetic: true` and keep it out of measured campaign searches.

| Example | Expected report |
| --- | --- |
| Completed static case | 3,600 ordinary frames over 54 s; ordinary mean/p95/p99/max 15/16/20/32 ms; startup 2 s; no edits. With required validation, fidelity, monitoring and applicable calibration passing, capacity and interactive attempt pass. Edit gate is inapplicable. One attempt does not confirm an endpoint. |
| Completed localized cut | One accepted edit at 80 ms; valid complete replay and sufficient ordinary samples. Capacity qualifies; edit p95 is descriptive and population-insufficient, so full interactive status is inconclusive. Three ordinary repetitions cannot manufacture 100 single-event edits. |
| Completed slow history | All 120 cuts accepted, 3,480 ordinary frames over 90 s; ordinary mean/p95/p99/max 25/40/70/125 ms; edit p95/max 200/300 ms; startup 34 s. Correct completion within reserves/deadlines qualifies capacity, while responsiveness fails. |
| Required edit rejected | Rollback checks pass, zero cells removed, required action not accepted. Stop the destruction sequence. Full schedule does not pass; capacity is not qualified. Report fragment-budget policy, not an architectural ceiling. A separately declared negative rollback fixture may pass its own expectation. |
| Stale resource monitor | The last required resource sample becomes more than one second old. Stop and report monitoring failure/inconclusive evidence, retaining the completed prefix and last valid samples. Do not label the resulting termination signal as an unexplained crash or memory exhaustion. |
| Reserve stop | Process-tree RSS reaches the declared reserve threshold. Report the exact source/time/value, partial schedule and policy stop. No observed physical ceiling follows. |
| Allocation failure | Preserve explicit failed allocation, device/heap/size and current resources. Only a permitted matching diagnostic retry can confirm the special two-observation failure endpoint; a lone failure remains an observation. |
| Missing GPU tail | Completed CPU intervals remain measured. Missing last required GPU interval is `incomplete`, not zero; GPU evidence stays incomplete even after normal process exit. |
| Rendering or quality failure | Stale/missing geometry fails rendering correctness. Correct rendering whose declared features fail readability instead fails visual quality. Neither supplies a passing endpoint for the required profile; retain independently valid state evidence. |
| Interrupted search | Three qualifying passes at area A, one ordinary failure at larger B, then campaign allowance exhausted. A is a confirmed passing point; B is an unconfirmed observation, not a confirmed failing bound. Preserve the tested observation and untested gap; require an explicitly declared allowance to resume. |

Report-only tests also cover only-pass and only-fail histories, mixed failure
causes, non-monotonic points, adjacent discrete settings, the ten-percent bracket
rule, malformed/truncated records and unsupported schema versions. They validate
classification and persistence, not Vulkan performance or an architectural limit.
