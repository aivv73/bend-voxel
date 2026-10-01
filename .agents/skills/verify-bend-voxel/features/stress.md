# Bounded stress diagnostics

The repo's existing stress command replays daylight, night, moving camera, aiming and six frozen cuts through the real Vulkan renderer, with numeric world, mesh-cache and timing-record checks.

## Sub-features

- `stress-static` retains the opening world under repeated rendering.
- `stress-night` changes lighting without changing geometry.
- `stress-camera` moves the camera with aiming disabled.
- `stress-aim` sweeps removable targets with a fixed camera.
- `stress-carve` accepts the six scheduled edits with expected world and geometry outcomes.

## How to get to it (user POV)

- Run `make benchmark-stress` for the normal documented diagnostic command.
- Use `scripts/benchmark_stress.sh` to request explicit cases, frame counts and an evidence path.

## Driving it with benchmark_stress.sh

Preconditions:

- Complete `make build` and the helper's Doctor check.
- Use an available X11/Vulkan display, no active helper drive, a fresh evidence path and no inherited `VOXEL_*` or `MEGASCENE_*` overrides.

- **Run bounded cases.** Run `scripts/benchmark_stress.sh --cases atelier atelier-night atelier-camera atelier-aim atelier-carve --warmup 2 --frames 24 --edit-every 4 --timeout 30 --output "build/verification/${VERIFY_RUN_ID}-stress"`. This schedules six cuts within the 24 measured carve frames.
- **Read numeric evidence.** Require exit code zero, top-level `pass: true`, all five case passes and empty error lists in `report.json`. Inspect the per-case CSV and stderr logs. The runner requires actual unpaced immediate/mailbox presentation and validates complete frame/stage records and expected world/cache behavior.
- **Retain evidence.** Keep every CSV, stderr file, the report and the exact invocation. Each workload process exits after its bounded schedule; no persistent app session is needed.

## Gotchas

- Stress mode supplies frozen camera/edit inputs rather than physical keyboard/mouse bindings. It complements the interactive recipes.
- The normal benchmark requires unpaced presentation. Missing driver support is a precondition failure, not a functional pass.
- Twenty-four measured frames are a smoke check, not enough evidence for a performance claim.
- Performance changes need the separate repository protocol at 1, 6 and 12 threads, representative end-to-end Vulkan runs and preserved observable world/geometry state.
- Light Atelier diagnostic results do not qualify any Megascene validation or campaign endpoint.
