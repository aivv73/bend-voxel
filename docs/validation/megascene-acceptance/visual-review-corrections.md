# Visual review corrections

The earlier blanket passing reviews for small history at 1920 × 1080 and
640 × 360 were too broad. Original captures for cuts 88, 89, 98, 99, 108, 109,
118 and 119 show ground and shadows without a discernible exposed cut face.
Their independent reference and native state/geometry checks pass, but those
checks do not establish visual readability.

Both reviews now report **insufficient_readability**. The correction helper
retains the complete prior `review.json`, `assessments.json`, `summary.json`
and `manifest.json` under each bundle's `review-revisions/` directory. The
current manifest binds those original files and the correction audit by hash.
An invalid correction restores all four canonical files. The helper's retention
and rollback tests pass.

The corrected inputs are [history-small-on-corrected.json](reviews/history-small-on-corrected.json)
and [history-small-360-corrected.json](reviews/history-small-360-corrected.json).
The original inputs remain in this directory. The archive batch record is
`/home/aivv/megascene-acceptance-68-extension2/checks/review-corrections-and-controls.json`.
The acceptance index links these records and retained revisions.

## Additional named reviews

All 123 named captures in each history control were inspected. Fill-history and
body-rich-history have the same eight unreadable late bridge cuts. The 12-cut
prefix passes its named review. The 48-cut prefix also passes after an audited
correction of a reviewer error at cut 41. Original-resolution inspection of its
bound capture clearly shows the rectangular wall opening and exposed rim and
interior. The fresh replay's corresponding capture has the same SHA-256, as do
all 123 named captures. Both prior insufficient assessments remain archived;
no capture synchronization defect was observed. The corrected input is
[history-48-corrected.json](reviews/history-48-corrected.json), and the correction
batch is `/home/aivv/megascene-acceptance-68-extension3/checks/cut41-review-corrections.json`.

Original-resolution inspection of all unique compact traversal captures finds
the stepped full-source silhouettes, selected rectangular proxy silhouettes
and dark ground shadows discernible. Both profiles pass their named reviews.
The mixed-world traversal far captures retain their insufficient-readability
verdicts.

The large-history review passes all 123 named views, including its late bridge
cuts. Its byte-identical captures reuse that review across eligible controls.
The corrected small-history insufficient verdicts are also reused only where
the scope, schedule, named features and capture hashes match. The historical
48-cut reuse record retains its earlier insufficient verdict and links the
subsequent correction audit. See [visual-reuse-extension.json](visual-reuse-extension.json).

The remaining complete positive bundles have explicit named reviews, including
the earlier compact traversal pair and body-rich control. The supplementary
[history](history-review-proposal.md) and [proxy](proxy-review-proposal.md)
view proposals require an explicit decision before execution because the
accepted exception in the specification covers support cuts only.
