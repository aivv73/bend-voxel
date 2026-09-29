# Static Megascene Vulkan observations

Issue #49 adds `--case static` to the separate public Megascene runner. It
constructs a fresh district in a new Vulkan process and holds the accepted
`opening(0)` camera. The default schedule contains one first usable startup
frame, 120 warm-up frames and 3,600 measured frames. Physics advances by
binary32 `0x3c888889` (1/60 second) before view preparation and rendering.
Picking and edits are disabled; window input cannot move the camera or modify
the world. Closing the window retains an incomplete prefix.

These are **unqualified development observations**. [Static replay validation and canonical timed checkpoints](megascene-validation.md)
are implemented in issue #51. [GPU timestamp evidence](megascene-gpu.md) is
implemented in issue #52; feature qualification and instrumentation calibration
remain later slices of #47. None of their absent results is a pass. Completing the
static schedule is independent of benchmark, capacity or interactive qualification.
The existing default demo and all five Light Atelier benchmarks retain their
settings and report meanings.

## Run a bounded observation

Use Linux/X11, a Vulkan 1.3 device, Python 3.10+, Bend 2.0.32, clang, g++,
glslc, and the Vulkan/X11/OpenSSL development libraries. `vulkaninfo` supplies optional
additional environment provenance. Supervised runs also require NVIDIA NVML,
`VK_EXT_memory_budget`, `VK_EXT_pci_bus_info`, and Linux libatomic. Missing
required monitoring prevents launch; see [supervision](megascene-supervision.md).
The command builds and archives its own
actual runtime; a prior `make build` is unnecessary.

```sh
python3 scripts/megascene.py --case static --preset small --seed 45 \
  --threads 6 --resolution 1920x1080 --profile full \
  --output build/megascene/development/static/small-45 \
  --archive "$HOME/megascene-evidence" --capture-opening
```

`--output` must be new. `--archive` is required and must explicitly name durable
storage outside disposable build/dist/tmp directories and outside the output
tree. Runtime inputs are copied and hash-verified there **before invocation**.
The example uses a persistent home directory; moving or deleting that directory
removes its retrieval guarantee. No remote storage or publication is implied.

The defaults are small, seed 45, six threads, 1920x1080, full geometry and a
2,048 detached-fragment budget. Fixed presets small/large, seeds 45/46, threads
1/6/12 and resolutions 640x360/1920x1080 are admitted. The budget is separate
from the initial 21/81 anchored owners. This slice performs no scale search.

For a short smoke check, add `--warmup 1 --frames 2` and choose a new output.
Explicit development schedules accept 0..120 warm-up and 1..3600 measured frames;
a shortened run reports `declared_development_prefix`, never completion of the
accepted 120/3600 configuration. Other schedules, profiles, diagnostics,
calibration and search requests are rejected. Counts are never clamped.
`--deadline` optionally lowers the 300-second case deadline. Basic bounds also
stop startup after 120 seconds and a lack of completed frames after 30 seconds.
The [resource supervisor](megascene-supervision.md) enforces reserves, sample
freshness, shared reference persistence, and the persistent campaign allowance.

`--capture-opening` launches another fresh process from the same archived
executable, world, profile and frozen opening view. It captures the startup
view through X11 to `captures/opening.ppm`, then exits. No screenshot work or
capture delay enters the timed attempt. Keep the window visible for this X11
capture. A missing capture or incomplete capture process fails the requested
capture operation. `review.json` identifies its separate attempt and the
building/span silhouettes and major shadows for review; capture availability
alone does not qualify visual quality.

## Rendering and measurement

The primary profile forces every visible body to use its full mesh. It retains
eligibility, group membership, hysteresis and proxy cache construction/storage.
The fixed y=0 ground covers the generation envelope plus 8 m on every side:
[-40,40] m for small and [-72,72] m for large. It does not change floor physics.
The 2048-square shadow map fits occupied geometry with the baseline margins,
sun direction, receiver-plane PCF, material palette and daylight lighting.
Ground padding does not enter the shadow fit.

Presentation requests immediate, then mailbox if immediate is unsupported.
There is no FIFO fallback. The native renderer records the actual swapchain
size, presentation mode, device/driver properties, palette bits, profile and
shadow work. A resized or out-of-date swapchain fails the frozen observation.
Shadow fitted extents and world-space texel coverage use binary32 bit strings;
main body draws, full meshes, proxy storage/rebuilds, shadow draws and uploaded
bytes have distinct counters.

CPU measurements use Linux `CLOCK_MONOTONIC` with unsigned 64-bit nanoseconds,
shared with Python's monotonic launch/deadline clock. Resolution is recorded;
nanosecond storage does not imply nanosecond accuracy. The first frame-effect
return ends cold startup. Subsequent frame intervals span consecutive returns,
including the preceding boundary record, loop bookkeeping, static state checks,
physics, view preparation, transport, native logging, submission and waits.
They are CPU wall time, not GPU execution or physical presentation latency.
`gpu.jsonl` separately records submitted work with its originating frame,
timestamp capability, raw ticks, availability and checked resolved interval.
The final pair is collected after existing teardown synchronization; it remains
associated with the final frame and adds no measured CPU frame.

Generation/tree construction, initial surfaces/vertices, inventory transport,
window setup, renderer setup, initial upload and first-frame work have separate
markers. Native stages nest inside the renderer stage. Stage sums are not a
frame total. Final bookkeeping and teardown are separate from measured frames.
The reported initial inventory check compares actual Bend trees, faces and
vertices with the existing independent integer reference after execution; it
is scoped to initialization. Separate complete validation and timed canonical
checkpoints now cover the full static schedule; see the validation guide.

The schedule never extends itself to reach ten seconds. Fewer than 1,000
ordinary frames or ten measured seconds yields an explicitly insufficient
population. Nearest-rank percentiles remain descriptive. Calibration,
responsiveness, visual quality, capacity and interactive outcomes
remain inconclusive even when the observed schedule completes.

## Evidence and recovery

The manifest uses `megascene-evidence/1` and identifies campaign, series and
attempt. It retains requested/effective settings, source revision and dirty
state, compiler commands/versions, CPU/OS and graphics environment, constants,
frozen source inputs and every frame's exact camera/aim/action schedule.
`cpu.jsonl` carries increasing sequence numbers, identities and actual CPU
boundaries, plus typed state/settings/render-work records. Records are flushed
during execution directly in the durable attempt directory; the local output
is synchronized after completion or a handled failure. A damaged tail remains
on disk and is excluded from the validated prefix.

The archive contains the actual executable, generated C and Bend inputs,
application native library, shaders, source/generator/reference code and linked
ELF libraries/loader. Execution uses those archived application bytes and
shader working directory. The host Vulkan ICD, driver/kernel and X11 session
remain platform requirements; sampled loaded-object paths and actual
renderer device/driver properties document them. This is not a self-contained
OS/graphics-driver image. Unrelated environment variables and secrets are not
recorded. Inherited `VOXEL_*`, `MEGASCENE_*`, `VK_*` and loader overrides are
removed; configured settings and disabled implicit Vulkan layers are recorded.

`invocation.json` stores the exact executable command, working directory,
controlled environment and launch time. Use the [archive reproduction command](megascene-reproduction.md)
to retrieve and verify the complete runtime and frozen inputs in a clean
location. It creates new validation and timed attempts through the supervisor.
Recorders refuse to overwrite existing streams. The opt-in integration test
exercises relocation without compiling or loading the checkout's application
library/shaders.

Failures retain stdout/stderr, actual exit code or signal, known deadline or
external-stop cause, and completed frame prefix. A signal alone is not evidence
of memory exhaustion. Required evidence errors prevent observed schedule
completion. Build/prelaunch failures are distinct from worker failures.

## Checks

```sh
make test
bend PROOF.bend
bend PROOF.bend --verdict
MEGASCENE_VULKAN_TEST=1 python3 -m unittest discover -s tests -p test_megascene_static.py -v
```

The opt-in Vulkan test runs a tiny public invocation and opening capture,
verifies archived hashes, recovers the archived runtime at another path, and
checks a controlled display failure. Synthetic report tests cover absent and
corrupt evidence, changed settings/state, frame gaps, truncated tails, wide
clocks and abnormal prefixes. Native reference tests verify full/proxy cache
retention, ground bounds, shadow equivalence and presentation selection.
Unsafe/native properties remain runtime/reference evidence, not formal proofs.

See the [retained issue #49 observations](validation/megascene-static/README.md)
for the bounded demonstration and regression results, and the
[issue #51 validation evidence](validation/megascene-checkpoints/README.md)
for complete replay and canonical checkpoint comparisons. The accepted
[handoff](megascene-spec.md), [workload](megascene-workload.md) and
[evidence contract](megascene-evidence.md) remain authoritative for later
qualification work.
