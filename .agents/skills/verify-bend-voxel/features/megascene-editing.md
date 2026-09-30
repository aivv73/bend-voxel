# Megascene picking, cuts and motion

The public Megascene cases exercise frozen rays, accepted edits, component identities and actual motion in a real district. Read [picking](../../../../docs/megascene-picking.md), [localized cuts](../../../../docs/megascene-localized.md), [support severing](../../../../docs/megascene-support.md) or [history](../../../../docs/megascene-history.md) for the selected case.

## Sub-features

- `megascene-picking` uses picking-v2's declared frozen center rays with no edits.
- `megascene-localized` removes exactly 16 concrete cells while preserving protected material and unaffected owners/caches.
- `megascene-support` performs six cuts, releases three spans and checks the declared simultaneous-motion window.
- `megascene-history` performs the accepted 120-cut history, including overlap, support release and a moved-beam target.

## How to get to it (user POV)

Run `python3 scripts/megascene.py --case picking|localized|support|history` using one actual case name. Each public invocation creates a separate complete validation replay with captures and a fresh timed process. These are scripted workload operations; use Light Atelier's interaction recipes to verify physical input bindings.

## Driving it with megascene.py

- **Doctor and select coverage.** Read the relevant case guide, inspect the existing archive allowance, and run `.agents/skills/verify-bend-voxel/scripts/verify.py doctor --surface megascene --archive "$MEGASCENE_ARCHIVE"`. Choose only cases needed by the change. Run sequentially without another benchmark.
- **Picking.** Run `python3 scripts/megascene.py --case picking --schedule picking-v2 --preset small --seed 45 --threads 6 --resolution 1920x1080 --archive "$MEGASCENE_ARCHIVE" --output "build/verification/${VERIFY_RUN_ID}-megascene-picking"`. Require the independent target/ray oracle, complete aim transitions, unchanged world geometry and all declared overlay captures.
- **Localized cut.** Run `python3 scripts/megascene.py --case localized --schedule localized-v1 --preset small --seed 45 --threads 6 --resolution 1920x1080 --archive "$MEGASCENE_ARCHIVE" --output "build/verification/${VERIFY_RUN_ID}-megascene-localized"`. Require the accepted 16-cell concrete removal, no protected removal, terrain ID 1 replaced by ID 22 with next ID 23, one anchored terrain component, one rebuilt full mesh and one edit shadow refresh. All 20 unaffected owners/caches must remain unchanged.
- **Support motion.** Run `python3 scripts/megascene.py --case support --schedule support-v1 --preset small --seed 45 --threads 6 --resolution 1920x1080 --archive "$MEGASCENE_ARCHIVE" --output "build/verification/${VERIFY_RUN_ID}-megascene-support"`. Require all six accepted 16-cell material-3 cuts, independently matched components, protected footings, monotonic IDs and actual offset/velocity samples. The three released spans must all move at ordinals 31–42. Review both fixed overview and the linked supplementary cut captures; full mesh bytes remain unchanged by translation while transforms/shadows update.
- **Destruction history.** Run `python3 scripts/megascene.py --case history --schedule history-v1 --preset small --seed 45 --threads 6 --resolution 1920x1080 --archive "$MEGASCENE_ARCHIVE" --output "build/verification/${VERIFY_RUN_ID}-megascene-history"`. Require 120 accepted actions, their intermediate world/material/owner/motion checks, correct moved-beam target and canonical timed agreement. Inspect every required named capture rather than accepting only the final world.
- **Observe and clean up.** Require zero exit, complete declared schedules and passing state/native/numeric checks. Read original action/reference streams, validation/checkpoint comparisons and supervisor termination. Submit named visual assessment with [the evidence recipe](megascene-evidence.md), then verify the runner's owned processes have stopped and the durable evidence remains.

## Gotchas

- Primary cases require 120 warm-up and 3600 measured frames. Do not shorten, retarget, add cuts or pool attempts to obtain a pass. Explicit diagnostic variants have separate identities and evidence contracts.
- Rejected/no-op actions cannot count as required accepted edits. Atomic rejection and unsafe geometry require the repo's independent runtime/reference fixtures, not formal-proof claims.
- One localized or six support cuts leave edit-percentile qualification inconclusive. Calibration, populations, responsiveness and capacity are distinct report outcomes.
- Support physics has no terrain/body collision, rotation, stacking or reattachment; passing through anchored geometry follows the documented model.
- Scripted inset cuts do not prove a mouse click can reach the inset. Picking-v1 and picking-v2 cannot share validation. Record all unexecuted cases and scales.
