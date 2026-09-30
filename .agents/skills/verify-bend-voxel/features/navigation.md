# Move, look and aim

Keyboard movement and right-drag look let a user inspect the courtyard. Pointer aiming identifies carveable and protected surfaces; Escape releases controls, and clicking the scene resumes them.

## Sub-features

- `navigation-move` changes the camera through movement keys.
- `navigation-look` changes the view through a right-button drag.
- `navigation-aim` shows the actual sculpture target under the pointer.
- `navigation-release` removes the target while controls are released with Escape.
- `navigation-resume` restores targeting through a click.

## How to get to it (user POV)

- Use W/A/S/D to move horizontally, Q/E to move vertically and Shift to move faster.
- Hold the right mouse button and move the pointer to look.
- Move the pointer over a sculpture to aim.
- Press Escape to release controls, then click the scene to resume. RESET is also a visible click target and restores the camera.

## Driving it with verify.py

Preconditions:

- Complete Launch and Doctor in `../SKILL.md`.
- Use the fixed 640 × 360 opening scene.

- **Drive.** Run `.agents/skills/verify-bend-voxel/scripts/verify.py run --feature navigation --evidence "build/verification/${VERIFY_RUN_ID}-navigation"`.
- **Move.** Inspect `moved-forward.png` against `before.png`; W must have moved the view without carving. The action log records the held key and release.
- **Look.** Inspect `looked-right.png`. A right-button drag from `(320,180)` to `(340,180)` must change the camera. `navigation-reset.png` must restore the baseline comparison region.
- **Aim.** Read `aim-sculpture.png`. The Oculus rim at `(360,186)` must identify `CARVE / 20 CM` and show a brush preview.
- **Release.** Read `controls-released.png`; the same pointer position must show `NO TARGET` after Escape.
- **Resume.** Read `controls-resumed.png`; the helper clicks RESET, then aims at the same rim again. Require `CARVE / 20 CM` and unchanged world counts.

## Gotchas

- This automated recipe exercises W, right-drag, pointer aim, Escape and resume via RESET. A/S/D, Q/E, Shift speed and resume through a non-RESET scene click remain separate entry points to exercise and record when a change affects them.
- Right-drag disables aiming during the drag. A missing preview while looking is expected.
- A released-control screenshot must be compared with a prior confirmed removable-target screenshot, not a prior miss.
- Navigation pixel changes do not establish speed or exact camera coordinates. Use `tests/input-aim.bend` and the existing moving-view stress case for numeric coverage.
