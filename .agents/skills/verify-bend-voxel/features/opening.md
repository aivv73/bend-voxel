# Opening scene

Launching Bend Voxel opens the Light Atelier courtyard with Suzanne, Oculus and Twist, visible cast shadows and an informative HUD.

## Sub-features

- `opening-launch` presents the default scene through real Vulkan/X11.
- `opening-exhibits` shows the monkey head, open torus and twisted column.
- `opening-shadows` shows canopy stripes and distinct sculpture shadows on the pale floor.
- `opening-hud` displays 803,970 cells, 0/2048 detached fragments and zero removed cells.

## How to get to it (user POV)

- Run `make run` from the checkout.
- Run `VOXEL_RESOLUTION=1280x720 make run` for the documented larger view; this is a separate resolution path.

## Driving it with verify.py

Preconditions:

- Complete Launch and Doctor in `../SKILL.md`.
- Keep the default scene and fresh evidence path.

- **Open.** Run `.agents/skills/verify-bend-voxel/scripts/verify.py run --feature opening --evidence "build/verification/${VERIFY_RUN_ID}-opening"`. The helper launches the normal demo and restores it through the visible RESET button.
- **Confirm scene.** Inspect `before.png`. Suzanne is left, the open golden Oculus is center, and Twist is right. The courtyard and sculpture shadows must be rendered and readable.
- **Confirm state.** Read `VOXELS 803970`, `BODIES 0/2048`, and `REMOVED 0` in the actual screenshot.
- **Confirm lifecycle.** Require `mechanical_pass: true`, `exit_code: 0`, and the retained cleanup event. Record the visual findings separately.

## Gotchas

- The HUD's body counter counts detached fragments, not the six anchored scene bodies.
- The helper restores through RESET before the baseline, so `READY / CUT APPLIED` is a normal baseline status.
- An image with enough colors can still render the wrong scene. Identify the actual exhibits and shadows.
- The helper tests only the default 640 × 360 view. Capture the larger user path separately when resolution or projection changes.
