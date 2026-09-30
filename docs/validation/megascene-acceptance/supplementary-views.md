# Approved supplementary fidelity views

On 2026-09-30 the user approved frozen, validation-only shadow views for all
eight proxy configurations and exposed-surface views for the eight affected
late bridge cuts in six small-history configurations. The accepted decisions
are recorded in the [proxy proposal](proxy-review-proposal.md),
[history proposal](history-review-proposal.md) and
[specification](../../megascene-spec.md#issue-68-supplementary-validation-views).

The frozen schedule retains every primary frame, camera, ray, action and action
time. Added cameras bind to an original named feature and its same-frame state
and geometry checkpoint. Native rendering reuses that world, preserves proxy
selection hysteresis, restores the primary view and excludes added rendering
from GPU samples. Runtime/reference audits check unchanged mesh slots and
vertices, proxy cache identity, full-mesh shadows and restored visibility and
selection. Numeric admission checks include the additional binary32 cameras.

The first history attempt failed because the C bridge retained the current
frame only for support. Its partial replay and raw evidence remain archived;
the bridge now retains the current frame and its HUD for approved generic views.
The next complete validation and timed observation passed state, geometry and
restoration checks, but all eight close-ups lacked enough context for readability.
Their insufficient assessments remain retained. All 123 primary captures were
byte-identical to an already corrected original review.

The independent sparse reference explains these late cuts: they remove the
last bridge connections and expose parts of a long ground wall. Tight views of
that wall show broad planes. Wider frozen cameras include the wall edge and
trench, making the exposed section and empty connection region assessable.
The context views retain the original insufficient primary assessments;
readability coverage comes only from separately inspected supplementary views.
Incorrect geometry cannot receive supplementary coverage.

Archive root: `/home/aivv/megascene-acceptance-68-extension4`.
Its `checks/original-index.json` preserves the pre-extension evidence locator;
`checks/retained-first-preservation.json` binds the initial complete observation
to unchanged primary schedules and captures. Camera previews and independent
reference diagnostics are retained under `diagnostics/`. Intentionally stopped
previews and any truncated image tails supply no acceptance or timing evidence.
Fresh complete validation and timed observations remain required for every
configuration. Final outcomes are recorded after the matrix and image review.

## Completed configuration reviews

All fourteen affected configurations completed their own validation and a full
120-warmup/3,600-measured-frame observation. Their named feature reviews pass:
six history configurations and all eight proxy configurations. The
[preservation audit](supplementary-preservation.json) binds every original
schedule and capture to its new bundle. Every primary capture is byte-identical;
original insufficient assessments remain insufficient, with explicit same-frame
supplementary coverage for the affected features. The 48 new history views and
64 new shadow views were inspected. Compact-reference original passes remain
retained, and its new views receive their own assessments.

The four new full/proxy comparisons pass:
[mixed traversal](mixed-world-traversal-supplementary-pair.json),
[mixed picking](mixed-world-picking-supplementary-pair.json),
[compact traversal](compact-reference-traversal-supplementary-pair.json), and
[compact picking](compact-reference-picking-supplementary-pair.json).
The [new history thread comparison](history-small-supplementary-threads.json)
confirms exact state and geometry at 1, 6 and 12 threads. None of these results
qualifies timings; the accepted calibration outcomes remain insufficient.

The required final-runtime history observations use the same validated source
for each thread count. Each repeat keeps its frozen inputs and instrumentation
mode; its named review is recorded separately only after all 131 capture hashes
and the complete review scope match the inspected source. See the
[repeat review bindings](supplementary-repeat-reviews.json). Earlier observations
remain archived, including the insufficient initial framing attempt.
