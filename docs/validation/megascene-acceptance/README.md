# Issue #68 implementation acceptance inventory

Issue [#68](https://github.com/aivv73/bend-voxel/issues/68) remains **incomplete**.
The [index](index.json) links retained campaign attempts to actual runtime
artifacts, validations, raw records, captures, reviews, summaries and calibration
assessments. It locates evidence and audits runtime coverage; it does not turn
an observed row into an implementation or performance acceptance pass. Archive
roots live under `/home/aivv/megascene*`, outside disposable `build/`.

## Coverage and outcomes

The final index includes 32 campaign ledgers and 224 archived attempt bundles.
Its exact runtime coverage is:

| Required group | Observed rows | Required rows |
| --- | ---: | ---: |
| Primary small/large configurations | 19 | 24 |
| Small 640 × 360 static/history | 2 | 2 |
| Mixed-world and compact-reference full/proxy pairs | 8 | 8 |
| Prescribed diagnostic controls | 11 | 11 |

The five missing primary rows are large traversal, picking, localized, support
and history at six threads. The 1- and 12-thread small traversal rows completed
in this campaign, with separate validation and timed observations; their named
visual reviews are still pending.

The static calibration matrix has all six configurations with six controls and
separate on/off validations. The small history matrix has all three. Every
completed assessment is **insufficient** because its measured intervals are
shorter than the accepted ten-second minimum. Large history at one thread has
four retained incomplete series: an initial numeric guard rejection and three
monitoring failures. Large history at six and twelve threads has no complete
series. These outcomes cannot qualify performance or be pooled into a pass.

The large history action-5 guard rejection is documented in
[large-history-guard.md](large-history-guard.md). The bound now agrees with the
existing half-cell rounding tolerance, with a native regression test. A later
diagnostic replay completed 3,721 frames and 120 edits after CPU JSON parsing
was deferred to the final audit, with no slow supervisor loops. That replay used
an older frozen runtime with the current host supervisor. It is diagnostic
evidence, not an eligible member of a fresh six-control calibration series.
The failed and incomplete attempts remain in the archives.

The 640 × 360 small static and history configurations now have their own
validation, timed replay and named visual reviews. The static opening shows
the building, spans and major shadows. The 123 history captures show the cuts,
exposed surfaces, retained geometry and settled fragments. The history review
exposed a report recomputation error: a preflight device-free sample was
compared with the supervisor's live extrema. The report code now uses the same
sample scope and preserves source errors separately from derived errors so a
second classification cannot degrade a passing schedule. The original
misclassified summary and an audit record remain with the repaired bundle.

The [small history thread comparison](history-small-threads.json) has exact
state and geometry equality at 1, 6 and 12 threads. Named feature reviews have
also passed for the static opening, small history on control, support span and
fill controls, and localized material detail. Some byte-identical attempts
reuse those review results through [visual-reuse.json](visual-reuse.json).
The mixed-world traversal full/proxy visual reviews are explicitly
**insufficient_readability**: the accepted far captures do not make all required
ground and shadow features discernible. Their otherwise complete runtime
evidence remains separate from that unresolved fidelity gate.

The full proof/runtime suite, face diagnostic, both-seed/both-preset generation
admission, and all five unchanged Light Atelier cases at 640 × 360 and
1920 × 1080 were exercised in this campaign. Light Atelier interactive controls,
lighting and reset were reviewed. The safe Bend proof result does not establish
unsafe carving or native Vulkan correctness; those properties use runtime and
independent reference evidence.

## Remaining acceptance work

The index's `coverage` rows identify exact missing primary configurations and
repeat counts. Large traversal, picking, localized, support and history at six
threads require their own positive runs. The large history calibration
configurations need complete
fresh series under the repaired supervisor. Every positive row still needs its
named fidelity review, and the mixed-world traversal captures need a readable
remedy. A qualified performance claim also needs sufficient and applicable
calibration results. Production implementation acceptance and qualified
performance are therefore both unestablished; future limit discovery remains
separate from #68.

## Allowance and archive policy

The accepted handoff starts with 7,200 seconds. The user approved one additional
28,800 seconds for the shared issue #68 campaign, superseding the earlier
14,400-second suggestion. The [allowance ledger](allowance.json) conservatively
charges the gross time of all 27 retained earlier campaign roots, including
development and failures, plus new wrapped checks and runner overhead. Its
36,000-second total is shared across roots; a fresh root's internal two-hour
cap never resets that total. No further acceptance run may be started after the
shared allowance is insufficient without another explicitly declared extension.

The index preserves incomplete and failed attempts alongside successes. Its
runtime row rule requires the exact seed-45 configuration, accepted 120/3,600
schedule, linked validation, complete archive entries, and passing schedule,
state and rendering outcomes. Repeat observations must share runtime/input
hashes and instrumentation mode. See the individual archive manifest and raw
files before interpreting any row as correct or qualified.
