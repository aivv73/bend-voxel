# Proposed supplementary proxy validation views

Status: accepted by the user on 2026-09-30; fresh validation and visual review
completed. See [the execution record](supplementary-views.md).

Original-resolution review of the mixed-world diagnostic shows that the
horizontal far camera does not expose enough ground to assess every required
major shadow. The original captures and their insufficient-readability
assessments must remain in the acceptance archive. A passing geometry or
selection audit cannot replace this visual gate.

## Concrete proposed decision

Apply the accepted supplementary-view approach to all eight proxy configurations:
mixed-world and compact-reference, traversal and picking, full and proxy.
The user's approval expands the original four-configuration proposal. Retain
the compact-reference original passing assessments as well as mixed-world
insufficient assessments.

- Preserve every primary camera, picking ray, hold, checkpoint and timed frame.
- Freeze a supplementary camera for each named review frame before replay.
  Look downward at the unchanged source world from a distance that makes its
  ground and major shadows discernible; bind the camera's binary32 values,
  source checkpoint and original named view in the frozen schedule.
- Render this view only during validation, without advancing physics, edits or
  action ordinals. Restore the original view and verify unchanged world,
  geometry and full-mesh shadow state.
- Assess both original and supplementary captures. Only the same frame's
  major-shadow feature may obtain readability coverage from its supplementary
  view. Primary silhouettes and source-geometry features retain their original
  assessments. Any incorrect geometry fails rendering correctness.
- Exclude supplementary renders and restoration work from timed CPU/GPU
  populations. Run fresh applicable validation and retain original failed
  reviews, pairing audits and all attempts.

The user approved this extension of the former support-only exception.
The decision does not itself establish a visual pass or qualified performance.
