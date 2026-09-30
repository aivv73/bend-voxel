---
name: verify-bend-voxel
description: Verify Bend Voxel through Megascene's public admission and supervised Vulkan replay commands and Light Atelier's real X11 controls. Capture world and mesh checks, screenshots, logs, durable evidence, and cleanup. Use after world, rendering, gameplay, camera, or native bridge changes, or when asked to verify either scene.
---

# Verify Bend Voxel

Read [the feature index](features/README.md) and the relevant feature recipes before choosing coverage. Use Megascene for district admission, world/mesh correctness, frozen rendering, picking and destruction replays. Use Light Atelier for physical keyboard/mouse controls and its sculptures. Rendering or native bridge changes should include Megascene; record each scene's coverage separately.

For Megascene, first read [the evidence ladder](references/megascene-proof-ladder.md). Choose the claim and required rung, audit existing scope-bound evidence, then run only missing checks. The short static command below reaches E3 smoke; a complete behavioral replay requires E4, reviewed implementation acceptance E7, qualified performance E8 and confirmed bounds E9. The retained acceptance already covers 45 configurations; its insufficient calibration remains a separate performance gap.

## Launch

Run from the repository root. Requirements are Linux, an accessible X11/XWayland `DISPLAY`, Vulkan 1.3 with Xlib surface support, Bend **2.0.34**, `glslc`, `g++`, Python 3 with Pillow, and libX11. Megascene additionally needs clang, OpenSSL/Vulkan/X11 development libraries, libatomic, NVIDIA NVML, `VK_EXT_memory_budget`, and `VK_EXT_pci_bus_info`. Light Atelier's helper needs `make` and ImageMagick's `import`. Do not update the compiler automatically.

### Megascene

Use the public runner, which builds and archives its own runtime; a prior `make build` is unnecessary. Preserve the established archive root and its allowance. Set `MEGASCENE_ARCHIVE` to the existing campaign location if this checkout uses a different one. Check [supervision](../../../docs/megascene-supervision.md) and the ladder's shared-allowance rules before launching or resuming. A new archive does not reset the shared allowance retained across earlier Megascene tickets.

```sh
bend guide
VERIFY_RUN_ID=$(date -u +%Y%m%dT%H%M%S)-$$
export VERIFY_RUN_ID
MEGASCENE_ARCHIVE="$HOME/megascene-evidence"
export MEGASCENE_ARCHIVE
.agents/skills/verify-bend-voxel/scripts/verify.py doctor --surface megascene --archive "$MEGASCENE_ARCHIVE"
python3 scripts/megascene.py --case static --preset small --seed 45 \
  --threads 6 --resolution 1920x1080 --profile full --warmup 1 --frames 2 \
  --archive "$MEGASCENE_ARCHIVE" --capture-opening \
  --output "build/verification/${VERIFY_RUN_ID}-megascene-static"
```

This is a declared development prefix: startup, one warm-up frame and two measured frames, validated in a separate Vulkan process, followed by fresh timing and opening-capture processes. Readiness comes from a usable rendered frame and valid process-attributed supervisor samples. Require a zero runner exit, passing initialization/state/rendering/schedule checks and the requested opening capture. Inspect the original capture and report before accepting the run. It checks this configuration only; ordinary populations, calibration, responsiveness and capacity can remain insufficient or inconclusive.

The archive must be explicit, durable, outside build/dist/tmp and separate from the fresh local output tree. Keep the X11 window visible for captures. Run without another benchmark or interactive drive. Each process is owned and stopped by the existing supervisor. The frozen workload ignores normal camera/edit input; use its declared schedules to drive behavior. Complete traversal, picking, localized, support and history recipes are in the feature map.

### Light Atelier

```sh
bend guide
make build
VERIFY_RUN_ID=$(date -u +%Y%m%dT%H%M%S)-$$
export VERIFY_RUN_ID
.agents/skills/verify-bend-voxel/scripts/verify.py doctor
.agents/skills/verify-bend-voxel/scripts/verify.py run --feature opening --evidence "build/verification/${VERIFY_RUN_ID}-opening"
```

`run` launches `build/voxel-demo --gpu off --threads 1` from this checkout, at 640 × 360. Bend gameplay runs on the CPU; rendering and presentation still use real Vulkan. The helper clears inherited `VOXEL_*` and `MEGASCENE_*` settings and enables `VOXEL_VULKAN_TRACE=1` and `VOXEL_VERIFY_BEND_MESH=1`. The latter compares production Bend meshes with the native reference expansion. This verification configuration is unsuitable for throughput measurements.

Ready means the owned process remains alive, exactly one new window has the application's full title, the trace contains `vulkan shadow refresh bodies`, and a screenshot has the expected dimensions and scene detail. Startup is bounded to 30 seconds. A new evidence directory is required for each run.

The helper selects a newly created window by its exact title and its absence before this process was launched. Bend does not publish `_NET_WM_PID`; the helper refuses multiple candidates rather than guessing ownership. A lock serializes helper runs on the same display. Keep manual input out of the running demo; separate worktrees are required for simultaneous builds. Existing demo windows are never selected.

Each run starts from a real click on the visible RESET button, then moves the aim to `(12,100)`. This restores the opening world and camera and resumes controls. It does not alter world state through an internal setter. The baseline HUD therefore reads `READY / CUT APPLIED`, even before a verification cut.

## Doctor

```sh
.agents/skills/verify-bend-voxel/scripts/verify.py doctor
```

The default read-only check covers Light Atelier: pinned compiler, all five build artifacts, build timestamps newer than `src/`, `Makefile`, and `scripts/build.sh`, ImageMagick, and an accessible display. It prints artifact SHA-256 hashes and the display identity. It does not launch a window or certify that the GPU can present; the first real rendered capture supplies that evidence.

For Megascene use `scripts/verify.py doctor --surface megascene --archive "$MEGASCENE_ARCHIVE"` through the full helper path above. It checks compiler/tool/library availability, the X11 connection, archive location and the existing campaign's state and remaining allowance without creating a lease or changing evidence. The public runner then checks actual Vulkan capabilities, NVML/device attribution, heap monitoring and resource reserves before releasing its worker. A doctor pass alone does not certify these runtime conditions. An active, interrupted or exhausted ledger fails doctor; inspect it and follow the existing supervision contract. Do not create a different archive, reset a ledger, or add time to bypass the limit. Additional allowance requires explicit authorization.

Doctor reports the selected root's lease only. Also inspect the established shared acceptance ledger and prior charges as described in the evidence ladder; a per-root remaining-time value does not approve a new campaign-wide allowance.

Run `doctor` first when a build, display, or capture looks wrong. For a Vulkan startup failure, retain `stderr.log` and run `vulkaninfo --summary` if available. Do not turn missing display/driver evidence into a rendering pass.

## Drive

For Megascene, drive `scripts/megascene.py` with the exact public arguments in [admission](features/megascene-admission.md), [rendering and traversal](features/megascene-rendering.md), and [picking and destruction](features/megascene-editing.md). Its own input guard, archive builder, references and supervisor are the harness. Static can be shortened explicitly for smoke verification; historical primary cases require their complete 120/3600 schedule. [Performance v2](../../../docs/megascene-performance-v2.md) separately admits only static/history at small/seed45/six threads/full/1080p with fixed 120/21600 schedules. Validate their disjoint ordinary/edit/motion populations and ordinary-duration gate; retain failed/noisy calibration. Select the relevant case rather than launching every campaign by default. Read [evidence and review](features/megascene-evidence.md) before making a correctness or visual claim.

The executable [helper](scripts/verify.py) sends X11 keyboard, pointer, and button events only to the window created by its own process. It does not warp the system pointer or use global keyboard injection. Recipes use the fixed opening camera and 640 × 360 client coordinates; named captures verify what those coordinates actually hit.

```sh
.agents/skills/verify-bend-voxel/scripts/verify.py run --feature lighting --evidence "build/verification/${VERIFY_RUN_ID}-lighting"
.agents/skills/verify-bend-voxel/scripts/verify.py run --feature carve-reset --evidence "build/verification/${VERIFY_RUN_ID}-carve-reset"
.agents/skills/verify-bend-voxel/scripts/verify.py run --feature navigation --evidence "build/verification/${VERIFY_RUN_ID}-navigation"
```

Use a fresh process for each feature. Stop at a failed recipe, retain its artifacts, resolve the observed problem, and retry under a new evidence path. `report.json` separates automatic pixel checks from `visual_review: pending`. A successful exit alone does not prove the HUD, target identity, or visual quality.

For additional resolutions or modified layouts, use the normal documented `VOXEL_RESOLUTION=1280x720 make run` path in an owned session and capture its actual controls. The helper deliberately fixes 640 × 360; scaling its known coordinates without checking the target is not proof of the other resolution.

## Evidence

For Megascene, the authoritative bundle is the durable attempt directory named by `manifest.json` → `reproduction.archive`; local output is a synchronized copy. Retain its exact invocation, frozen runtime/source hashes, validation and comparison records, CPU/GPU/reference/resource/allocation streams, termination and exit information, screenshots, and campaign ledger. Use `scripts/megascene_report.py --bundle ARCHIVED_ATTEMPT` to recompute classification. Review named replay views and static's separate opening capture with the repo's `scripts/megascene_review.py`, which preserves assessments and updates manifest hashes. For static, read the required opening feature names from `schedule.json`; the initial single-view `review.json` has a different shape from complete route reviews. Read the authoritative archived summary after review, since the local copy predates that update. Never replace the repo's outcomes with a helper's blanket pass. The [evidence recipe](features/megascene-evidence.md) explains review and recovery.

Each `run` retains `report.json`, `actions.jsonl`, `stdout.log`, `stderr.log`, and named PNG captures under its requested `build/verification/` directory. The report records the feature, git revision, working tree status, build and harness hashes, display, checks, and process exit status. The action log records the launched PID, selected window, actual events, capture hashes, and cleanup.

Inspect the original captures with an image viewer. Require the action and its resulting state, not only a final picture. Read the actual HUD counts and statuses in carving/reset captures, compare the named target before clicking, and check shadow refreshes in the runtime log. Record visual findings and any skipped entry point in a separate `review.json` beside the report, naming the files inspected and the reviewer. Leave the helper's `visual_review: pending` report intact.

The pixel comparisons cover rows 90–299 of the fixed view, excluding changing HUD timings. They establish changes and restoration in that region only; they cannot certify the whole image, every shadow, or voxel counts. Pixel comparisons and native mesh checks are runtime/reference evidence, never formal proofs of `@unsafe` geometry or foreign IO.

Use the existing repo checks when their scope matches the change:

```sh
make test
make proof
make proof-verdict
```

`make test` includes the Bend proof gate, Bend runtime suites, native geometry fixtures, and Python reference tests. `make proof-verdict` needs the `lean-toolchain` pin, Lean 4.34.0. Before a commit, require `bend PROOF.bend` and its supported `--verdict` check, as the project's instructions specify; `make proof` and `make proof-verdict` wrap those checks and require a positive verdict. Keep important contracts in `LAWS.bend`; do not weaken its claims to obtain a pass.

Use [the stress recipe](features/stress.md) for short numeric checks. Performance work must follow the repository's existing 1, 6, and 12 thread comparison protocol with representative Vulkan runs and identical world/geometry state. Independence alone does not justify a new fork, and a smoke run does not establish an improvement.

## Cleanup

Megascene exits after its declared schedule and supervisor finalization. Require retained termination/exit records and the supervisor's final durability barrier; check that its recorded worker and monitor instances have stopped. Keep both the durable bundle and local output. On failure, retain the completed prefix, damaged tails and stopping reason. Send interruption only to the runner you launched and let its supervisor stop its owned process groups. Never kill unrelated demo/benchmark processes or delete/reset the campaign ledger. Check evidence remains readable after teardown.

`run` sends `WM_DELETE_WINDOW` to the selected owned window, waits for the owned process, and falls back to terminating only its separately created process group if closure stalls. It records the exit and preserves all evidence, including failures. Normal verification requires an application exit code of zero.

After a run, require a cleanup event with `process_stopped: true` in `actions.jsonl` and verify the evidence files still exist. Never use `pkill`, kill by application name, or delete `build/verification/` as teardown. If the helper itself is killed before cleanup can execute, inspect the recorded launch PID and its process identity before stopping that specific owned instance; do not infer ownership from a matching window title alone.

## Helpers

`scripts/verify.py doctor` checks Light Atelier's prerequisites. `scripts/verify.py doctor --surface megascene --archive DURABLE_ROOT` checks Megascene's prerequisites and existing allowance without mutation. `scripts/verify.py run --feature opening|lighting|carve-reset|navigation --evidence NEW_DIRECTORY` owns Light Atelier's launch, drive, capture, and cleanup lifecycle. Megascene uses the existing public runner directly. Call helpers through the repository-relative paths shown above. Pillow and ImageMagick are capture/comparison dependencies, not mocks of the app.

Keep the recipes synchronized with the actual app. Use `$pstack:maintain-verification-skill` when controls or user-visible behavior change.
