# Proposed supplementary history validation views

Status: proposed; no added view has been accepted or executed.

Review of all 123 named small-history images, both diagnostic history controls,
and both history-prefix controls found a definite readability failure in late
bridge cuts 88, 89, 98, 99, 108, 109, 118 and 119. Their primary views show ground
and shadows without a discernible remaining cut face. The independent sparse
reference and native geometry checks pass; that does not establish visual
readability. The earlier blanket passing small-history assessments have been
corrected, with their original files retained in audited revisions.

## Concrete proposed decision

Extend the accepted support-cut supplementary-view exception to unreadable
history cut features in the affected configurations. The known targets are
small history at 1/6/12 threads and 1080p, small history at 6 threads and 360p,
fill-history, and body-rich-history. Inspection of all 123 large-history images
finds their required cut surfaces discernible, so added large-history views are
not currently needed:

- Keep the complete primary camera track, action times, physics, frame count,
  materials, quality profile and measured workload unchanged.
- Freeze an additional camera at each affected named cut frame before replay.
  Select its view from the independent post-cut source bounds and exposed
  faces; bind the binary32 camera, frame, action and state/geometry checkpoint.
- During validation only, render the same post-cut world from that camera,
  capture it, then restore the primary view without advancing state.
- Keep both captures and both assessments. A supplementary view can cover
  only the same action/frame's unreadable removed-material or exposed-surface
  feature. Incorrect geometry continues to fail.
- Verify unchanged world, geometry, cache and shadow state after restoration;
  exclude added rendering and capture work from all timed populations.
- Preserve failed and earlier incorrect review revisions. Require new
  applicable validation rather than inventing evidence for old captures.

The 48-cut control passes. Original-resolution reinspection corrected a reviewer
error at cut 41: its bound capture clearly shows the opening and exposed faces.
The original and fresh captures have identical hashes. Both prior insufficient
assessments remain archived; no capture synchronization defect was observed.

An explicit decision is required because `docs/megascene-spec.md` currently
limits this exception to support cuts. This proposal changes the validation
view coverage, not the timed schedule or the required fidelity standard.
