# Day and night lighting

Holding L previews the darker night setup with cool ambient light and a warm camera work light. Releasing L restores daylight without editing the world.

## Sub-features

- `lighting-night` changes the lighting while L is held.
- `lighting-release` restores daylight when L is released.
- `lighting-preserve` leaves scene geometry and occupied-cell counts unchanged.

## How to get to it (user POV)

- Open the demo, resume controls if necessary, and hold L.
- Release L to return to daylight.

## Driving it with verify.py

Preconditions:

- Complete Launch and Doctor in `../SKILL.md`.
- Use the opening camera and fresh scene without cuts.

- **Hold L.** Run `.agents/skills/verify-bend-voxel/scripts/verify.py run --feature lighting --evidence "build/verification/${VERIFY_RUN_ID}-lighting"`. `actions.jsonl` records L press, the `night.png` capture, and L release.
- **Inspect night.** Compare `before.png` with `night.png`. The same three exhibits must remain visible under the cool ambient and stronger warm nearby light.
- **Inspect release.** Compare `day-restored.png` with `before.png`. The helper requires at least 1,000 changed scene pixels for the night view and zero changed pixels in rows 90–299 after release.
- **Confirm state.** Read 803,970 occupied cells and zero removed cells in all three HUDs. Record visual quality separately from the pixel result.

## Gotchas

- L is a held-key preview, not a persistent lighting toggle.
- Escape or a focus/leave event releases controls; the helper clicks RESET first to resume them.
- The camera work light does not cast shadows. Do not expect a new camera-light shadow map.
- The pixel comparison excludes the HUD and covers part of the scene; it is not a complete visual-quality verdict.
