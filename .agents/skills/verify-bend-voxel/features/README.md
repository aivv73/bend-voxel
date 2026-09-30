# Bend Voxel verification map

This map covers Megascene's public CLI and frozen Vulkan workloads, plus Light Atelier's desktop controls. Use Megascene for district/world/native rendering verification and Light Atelier for keyboard/mouse behavior. Read a matching feature file before driving the app. The public README, [Megascene admission guide](../../../../docs/megascene-admission.md), [showcase guide](../../../../docs/showcase.md), and [renderer guide](../../../../docs/vulkan-renderer.md) ground these recipes.

For Megascene, choose scope and strength with [the evidence ladder](../references/megascene-proof-ladder.md) before selecting a recipe. It distinguishes E3 smoke, E4 complete behavior, E7 implementation acceptance, E8 qualified performance and E9 confirmed bounds, with a hash-bound audit of the retained current record.

## Megascene preconditions

- Set `VERIFY_RUN_ID` and `MEGASCENE_ARCHIVE` using `../SKILL.md`. Reuse the established durable campaign root; never move archives to escape an exhausted allowance.
- Run the full helper path with `doctor --surface megascene --archive "$MEGASCENE_ARCHIVE"`. Admission alone requires no display; Vulkan recipes require X11, real Vulkan and valid required resource monitors.
- Use a fresh local output for every attempt. The runner builds and archives its own runtime; `make build` and Light Atelier artifact checks are unnecessary.
- Run Vulkan workloads sequentially with no competing benchmark or interactive helper. Keep captures visible and do not rebuild application inputs during a run.
- The bounded static recipe validates only its declared development prefix. Traversal, picking and destruction require complete primary schedules. Report unexecuted cases, seeds, resolutions, scales and thread configurations explicitly.

## Light Atelier preconditions

- Run `make build` with Bend 2.0.34 and pass `scripts/verify.py doctor` using the full repository-relative helper path in `../SKILL.md`.
- Use an accessible X11/XWayland display and a real Vulkan driver. The helper's resolution is exactly 640 × 360.
- Set `VERIFY_RUN_ID` as shown in `../SKILL.md`; use a new evidence directory for every attempt.
- Each interactive recipe launches a fresh owned process and restores the world through the visible RESET control before its baseline capture.
- The opening scene has **803,970** occupied cells, **zero detached fragments**, and a HUD body budget of **2,048**. The six anchored scene bodies are not the HUD fragment counter.
- Do not run two helper drives on the same display or rebuild the same checkout while a verification process is alive.

## Light Atelier driving conventions

- All commands run from the repository root. The helper path is `.agents/skills/verify-bend-voxel/scripts/verify.py`.
- Target coordinates refer to the 640 × 360 client area, excluding the desktop title bar. Inspect the named aiming capture before accepting a coordinate-based interaction as the intended target.
- Each recipe drives real X11 events into the normal interactive demo. The separate stress recipe uses the repo's frozen diagnostic workloads; it does not prove physical mouse/keyboard bindings.
- An automatic `mechanical_pass` and zero process exit are required. Visual review remains a separate obligation.

## Proof and skip reporting

- Keep original screenshots, action events, runtime logs, checks, and exit code together.
- Read the actual HUD and visible scene; do not substitute a source-code expectation for what the window displayed.
- Record visual findings in `review.json` beside the helper report. Name the feature IDs, entry points and captures reviewed.
- Report unexercised controls and resolutions explicitly. A pass at 640 × 360 does not establish 1280 × 720 behavior.
- Opening detail and pixel changes are mechanical smoke checks. Named geometry, readability, protection, and counts require the feature's stated visual or reference evidence.
- Keep state correctness, rendering correctness, visual quality, schedule completion and performance/capacity qualification separate. Recompute Megascene reports from the archived bundle and submit named review through the repo's review tool.
- Do not classify a short stress/static run as a performance result or a Light Atelier run as Megascene coverage. `@unsafe` and native properties require runtime/reference evidence.

## Features

- [Megascene admission](megascene-admission.md): constructs the real sparse district and checks numeric bounds, owners, materials and independent geometry references without Vulkan.
- [Megascene rendering and traversal](megascene-rendering.md): short static verification, complete frozen route, native mesh/shadow checks and captures.
- [Megascene picking and destruction](megascene-editing.md): picking-v2, localized cut, support motion and 120-cut history with complete separate validation.
- [Megascene evidence and recovery](megascene-evidence.md): durable archive, truthful reports, named visual review, cleanup and reproduction.
- [Opening scene](opening.md): launches the default scene, identifies the three sculptures and cast shadows, and reads initial HUD counts.
- [Lighting](lighting.md): holds L for the night view and releases it to restore daylight.
- [Carve and reset](carve-reset.md): aims and clicks a removable sculpture, then restores through R and the visible RESET button.
- [Navigation and aim](navigation.md): keyboard movement, RMB look, pointer aiming, Escape release and click-to-resume.
- [Stress diagnostics](stress.md): existing static, night, camera, aim and six-cut runtime/reference checks.
