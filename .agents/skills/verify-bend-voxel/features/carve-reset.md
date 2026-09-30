# Carve and restore a sculpture

A left click on a removable sculpture carves a 20 cm brush region. R and the visible RESET button both restore the default world and opening camera.

## Sub-features

- `carve-aim` displays a removable target and brush preview on the Oculus rim.
- `carve-click` changes the visible geometry and decreases the occupied-cell count.
- `reset-key` restores geometry, counters and camera through R.
- `reset-button` restores the same state through the visible RESET button.

## How to get to it (user POV)

- Point at a sculpture and click the left mouse button once.
- Press R to restore the scene.
- Click RESET in the upper-right HUD to restore the scene through the other entry point.

## Driving it with verify.py

Preconditions:

- Complete Launch and Doctor in `../SKILL.md`.
- Use the fixed 640 × 360 opening camera. This recipe's rim target is client coordinate `(360,186)`.

- **Aim.** Run `.agents/skills/verify-bend-voxel/scripts/verify.py run --feature carve-reset --evidence "build/verification/${VERIFY_RUN_ID}-carve-reset"`. Inspect `aim-before-cut.png`: the pointer must be on Oculus and the HUD must show `CARVE / 20 CM`.
- **Cut.** Inspect `after-cut.png` and the recorded button press/release. Require a smaller occupied-cell count, a positive `REMOVED` count, `READY / CUT APPLIED`, and a visible change at the target. Read the removal value from the screenshot rather than assuming a particular cut size.
- **R reset.** Inspect `keyboard-reset.png`. Require the original 803,970 cells, zero removed cells and the restored opening view. The helper requires zero changed pixels in its comparison region.
- **RESET button.** Inspect `second-cut.png` and `button-reset.png`. The second cut must actually have changed geometry before the click at `(610,12)` restores the original counts and view.
- **Mesh and shadows.** Read `stderr.log`. Initial rendering and accepted edits/reset must remain free of native mesh-reference errors, and shadow refreshes must accompany geometry changes. Preserve the original trace and capture hashes.

## Gotchas

- A pointer coordinate is not a stable target after camera movement or resizing. The aiming capture is required.
- Foundation and floor targets are protected; their HUD labels are not removable-target proof.
- A successful initial RESET sets `CUT APPLIED` without proving a new carve. Require decreased cells and changed target geometry for each cut.
- Pixel equality alone does not prove reset counters or off-screen world state. Read the HUD and use existing world/reference tests for changes to those invariants.
