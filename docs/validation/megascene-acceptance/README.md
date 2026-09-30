# Issue #68 implementation acceptance inventory

Issue [#68](https://github.com/aivv73/bend-voxel/issues/68) remains **incomplete**.
The [index](index.json) links retained campaign attempts to actual runtime
artifacts, validations, raw records, captures, reviews, summaries and calibration
assessments. It locates evidence and audits runtime coverage; it does not turn
an observed row into an implementation or performance acceptance pass. Archive
roots live under `/home/aivv/megascene*`, outside disposable `build/`.

## Coverage and outcomes

The index includes 34 campaign ledgers and 256 archived attempt bundles.
Its exact runtime coverage is:

| Required group | Observed rows | Required rows |
| --- | ---: | ---: |
| Primary small/large configurations | 24 | 24 |
| Small 640 × 360 static/history | 2 | 2 |
| Mixed-world and compact-reference full/proxy pairs | 8 | 8 |
| Prescribed diagnostic controls | 11 | 11 |

All 45 required runtime rows are observed, including eligible groups of three
identical static/history small-preset observations at each thread count. The
remaining large traversal, picking, localized, support and history rows at six
threads now have their own validation and timed observations. The large named
reviews pass, as do the small traversal reviews at one and twelve threads.
Runtime coverage does not override the ten unresolved fidelity rows below.

The [calibration summary](calibration-summary.json) binds one complete eligible
six-control series for each of the 12 static/history, small/large and 1/6/12-thread
configurations: **72 controls**, with separate applicable on/off validations.
Every assessment is **insufficient** because measured intervals miss the
accepted ten-second minimum. Earlier incomplete large-history series, including
the numeric guard rejection and monitoring failures, remain archived. These
outcomes cannot qualify performance or be pooled into a pass.

The large history action-5 guard rejection is documented in
[large-history-guard.md](large-history-guard.md). The bound now agrees with the
existing half-cell rounding tolerance, with a native regression test. A later
diagnostic replay completed 3,721 frames and 120 edits after CPU JSON parsing
was deferred to the final audit, with no slow supervisor loops. That replay used
an older frozen runtime with the current host supervisor. It is diagnostic
evidence, not an eligible member of a fresh six-control calibration series.
The failed and incomplete attempts remain in the archives.

The 640 × 360 small static and history configurations have their own
validation, timed replay and named visual reviews. The static opening shows
the building, spans and major shadows. The earlier blanket small-history visual
passes at both resolutions were corrected after eight late bridge views proved
unreadable. Original reviews remain archived; see
[visual-review-corrections.md](visual-review-corrections.md). The history review
also exposed a report recomputation error: a preflight device-free sample was
compared with the supervisor's live extrema. The report code now uses the same
sample scope and preserves source errors separately from derived errors so a
second classification cannot degrade a passing schedule. The original
misclassified summary and an audit record remain with the repaired bundle.

The [small](history-small-threads.json) and
[large](history-large-threads.json) history thread comparisons have exact state
and geometry equality at 1, 6 and 12 threads, with separate validations and
identical applicable runtime artifacts. Named feature reviews also pass for
static openings, large primary workloads, support and fill-support controls,
both history prefixes, all four compact-reference configurations and localized
material detail. The 48-cut prefix verdict was corrected after original-resolution
inspection showed that its cut-41 opening was readable; original and fresh
captures are byte-identical, and both earlier insufficient verdicts remain
archived.

Small history, fill-history and body-rich-history remain insufficient for
readability at eight late bridge cuts. The four mixed-world traversal/picking,
full/proxy visual reviews are explicitly
**insufficient_readability**: the accepted far captures do not make all required
major shadows discernible. Their otherwise complete runtime evidence remains
separate from that unresolved fidelity gate. Some byte-identical attempts reuse
review results through [visual-reuse.json](visual-reuse.json) and
[visual-reuse-extension.json](visual-reuse-extension.json); scope, schedule,
feature names and capture hashes must match, and each target is assessed
separately. The historical cut-41 reuse record links its later correction.

The full proof/runtime suite, face diagnostic, both-seed/both-preset generation
admission, and all five unchanged Light Atelier cases at 640 × 360 and
1920 × 1080 were exercised in this campaign. Light Atelier interactive controls,
lighting and reset were reviewed. The safe Bend proof result does not establish
unsafe carving or native Vulkan correctness; those properties use runtime and
independent reference evidence. The final current-code `make test` run passes
all eight Bend runtime suites, native geometry checks and 167 Python tests
(four skipped). Both `bend PROOF.bend` and `bend PROOF.bend --verdict` report
`ALL PROOFS CHECK`. Their retained logs and hashes are linked by the index and
allowance ledger.

## Remaining acceptance work

The ten unresolved fidelity rows are small history at 1080p/1, 6 and 12 threads,
small history at 360p/6 threads, fill-history, body-rich-history, and the four
mixed-world proxy diagnostic configurations. Complete positive bundles with
named captures have explicit assessments; these failures are retained rather
than left awaiting review.

The concrete [history](history-review-proposal.md) and
[proxy](proxy-review-proposal.md) supplementary-view proposals await an explicit
decision. The accepted exception in `docs/megascene-spec.md` currently covers
support cuts only. Added validation views would preserve the primary timed
workload and retain the original insufficient assessments. Production
implementation acceptance remains incomplete. Qualified performance remains
unestablished because calibration is insufficient; future limit discovery
remains separate from #68.

## Allowance and archive policy

The accepted handoff starts with 7,200 seconds. The user approved an additional
28,800 seconds for the shared issue #68 campaign, superseding the earlier
14,400-second suggestion, and later approved another 14,400 seconds. The
[allowance ledger](allowance.json) conservatively
charges the gross time of all 27 retained earlier campaign roots, including
development and failures, plus new wrapped checks, active visual review work
and runner overhead. Closed roots do not charge the pause before a new root;
resuming the same root preserves its supervisor's gross lease charge. Tagged
wrapped work is charged once when reconciling that gross time. Its
50,400-second total is shared across roots; a fresh root's internal two-hour
cap never resets that total. No further acceptance run may be started after the
shared allowance is insufficient without another explicitly declared extension.

The index preserves incomplete and failed attempts alongside successes. Its
runtime row rule requires the exact seed-45 configuration, accepted 120/3,600
schedule, linked validation, complete archive entries, and passing schedule,
state and rendering outcomes. Repeat observations must share runtime/input
hashes and instrumentation mode. See the individual archive manifest and raw
files before interpreting any row as correct or qualified.
