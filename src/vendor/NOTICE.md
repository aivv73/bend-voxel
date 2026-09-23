# Third-party code

`bend3d.bend` is copied without modification from `bendlang/bend`, commit `a49524265bdfa5753a4bf38e25f0574a705dd868`, path `demos/app_slash_boss_3d/bend3d.bend`. Its Apache-2.0 license is included as `LICENSE`.

`../platform/present.c` adapts the native `window_frame.c` effect distributed with Bend 2.0.16 (the same Bend project). Changes include the effect name, the fixed Bend3D image-tree extent, focus/leave notifications, native HUD text and presentation synchronization. It is covered by the included Apache-2.0 license. The adapter uses the installed runtime's `BendWin` layout and therefore requires the pinned compiler. Its `io_seal` calls pass the constructor ID `CID_CON`, matching the API introduced in Bend 2.0.25; the unchanged adapter builds and runs with the current Bend 2.0.26 pin.

All world, control and demo-specific renderer logic is separate from the vendored Bend3D source.
