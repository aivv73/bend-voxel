# Megascene static rendering and traversal

The public runner renders the real district with full meshes, daylight and world-fitted shadows, using separate validation and timed processes. The [static guide](../../../../docs/megascene-static.md), [checkpoint contract](../../../../docs/megascene-validation.md) and [traversal guide](../../../../docs/megascene-traversal.md) define the evidence.

## Sub-features

- `megascene-static` holds the frozen opening view and checks unchanged world/native geometry and caches.
- `megascene-traversal` runs traversal-v2's twelve frozen phases, including repeated cavities and changing visibility.
- `megascene-thread-equivalence` compares canonical state and per-body geometry across independently validated 1/6/12-thread attempts.

## How to get to it (user POV)

Use `python3 scripts/megascene.py --case static` or `--case traversal --schedule traversal-v2` from the repository root. Window input cannot move or edit these frozen workloads. Choose the bounded static recipe for initial smoke verification; select the complete route when camera/culling behavior is the target.

## Driving it with megascene.py

- **Doctor.** Run `.agents/skills/verify-bend-voxel/scripts/verify.py doctor --surface megascene --archive "$MEGASCENE_ARCHIVE"`. Require no competing Vulkan workload, a new output and visible X11 captures. The runner's real preflight must also pass resource/device monitoring.
- **Bounded static.** Run `python3 scripts/megascene.py --case static --preset small --seed 45 --threads 6 --resolution 1920x1080 --profile full --warmup 1 --frames 2 --archive "$MEGASCENE_ARCHIVE" --capture-opening --output "build/verification/${VERIFY_RUN_ID}-megascene-static"`. The runner validates that exact development prefix, then launches fresh timing and capture processes.
- **Check static evidence.** Require zero exit and passing initialization, state correctness, rendering correctness, numeric validity, schedule completion and opening-capture availability in the archived `summary.json`. Require `validation.json` and `comparison.json` to agree with the timed checkpoints. Inspect the original `captures/opening.ppm` and assess its three named opening features through [the evidence recipe](megascene-evidence.md). Retain all supervisor and GPU evidence.
- **Complete traversal validation.** When traversal coverage is required, run `python3 scripts/megascene.py --case traversal --schedule traversal-v2 --preset small --seed 45 --threads 6 --resolution 1920x1080 --validation-only --output "build/verification/${VERIFY_RUN_ID}-megascene-traversal-validation" --archive "$MEGASCENE_ARCHIVE"`.
- **Fresh timed traversal.** Run `python3 scripts/megascene.py --case traversal --schedule traversal-v2 --preset small --seed 45 --threads 6 --resolution 1920x1080 --validated "build/verification/${VERIFY_RUN_ID}-megascene-traversal-validation" --output "build/verification/${VERIFY_RUN_ID}-megascene-traversal-timed" --archive "$MEGASCENE_ARCHIVE"`. Require complete state/native agreement, unchanged world/per-body geometry, full mesh/shadow reuse, and all 14 retained review views. Submit every named feature assessment using [the evidence recipe](megascene-evidence.md).
- **Thread comparison when required.** Follow the checkpoint guide's `--runtime-from` 1/6/12-thread commands and `scripts/megascene_checkpoints.py --compare-threads`. Each thread count needs its own complete validation and fresh timing; preserve actual representation work as well as canonical logical equality.

## Gotchas

- Static shortening reports `declared_development_prefix`; it does not complete the accepted 120 warm-up/3600 measured configuration. Primary traversal rejects shortened schedules.
- Traversal-v1 preserves its historical failed cavity framing. Its validation is incompatible with traversal-v2.
- Captures belong to validation or a separate opening process; capture pauses are excluded from fresh timing. Visibility of a capture does not establish feature readability.
- Reuse verifies exact artifacts, schedule, settings and graphics platform. A changed executable, shader or scope requires fresh validation.
- Short samples do not establish performance; complete schedules can still have insufficient populations, missing calibration or inconclusive benchmark/capacity outcomes. Never flatten these into a blanket pass.
