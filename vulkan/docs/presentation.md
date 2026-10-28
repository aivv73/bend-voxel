# X11 presentation

Native adapter source paths below are relative to `deps/bend-vulkan/` in the
bend-voxel repository. Renderer commands run from `vulkan/`.

The interactive consumer displays the full editable Atelier scene in a native Vulkan window. `--cube` selects the earlier basic 8³ cube regression mode.
Bend owns the world, controls, camera, picking, mesh, uploads, target generation, and frame loop.
The native wrapper owns checked handles and Vulkan dispatch. Production draws materials, sun shadows, ground and grid, exact yellow selection and three depth-aware brush rings.

## Run and verify

Use Bend 2.0.39, Linux X11, Vulkan headers, X11 headers, `libX11.so.6`, and a Vulkan driver with `VK_EXT_swapchain_maintenance1`.
The optional `src/x11.c` adapter loads Xlib through `libdl`. The generator bundles it with the guarded core in `src/window.c` for Bend's single C import.
Headless effects import only `src/native.c`.
The adapter initializes Xlib threading before opening a display and locks its pointer-warp request sequences. Vulkan may use the same display from presentation threads, as the [Xlib WSI contract](https://docs.vulkan.org/spec/latest/chapters/VK_KHR_surface/wsi.html) requires. Manual C builds still link `-ldl`, without `-lX11`.
Headless clients require no display or X11 runtime library. They retain the Vulkan 1.0 device and submission constructors.

```sh
cd vulkan
mkdir -p build
bend examples/voxel_interactive.bend -o build/voxel-interactive
./build/voxel-interactive
```

The default uses `Camera.atelier()`. Use WASD and Q/E to move the camera. Hold RMB for relative look. Left click cuts the hovered surface with a fixed 20 cm sphere. Space cuts the current hover. R reconstructs the selected original Body while preserving the camera and controls. In `--cube` mode Space retains its fixed demo cut.
Escape and WM close exit. Capture refusal leaves the application running with look disabled.
Focus loss and unmap release capture and held movement controls. Window polling never draws CPU pixels.
Add `--trace` to print per-turn `STATE` diagnostics with camera, mesh, upload, and wrapper counters.
The window acceptance driver enables this flag, including actual graphics and presentation queue output. Normal runs are quiet.

From `vulkan`:

```sh
python3 tools/verify.py --sanitize --presentation
python3 tools/verify.py --sanitize --presentation --isolated-display
```

The isolated option starts and stops a private rootful Xwayland server on the current Wayland desktop.
It avoids pointer grabs held by other X11 applications. It requires `Xwayland`, Python Pillow, and ImageMagick `import`.
The driver sends X11 key and button events to the spawned window identified by its `_NET_WM_PID`.
It uses actual pointer warps, capture, focus, configure, map, unmap, and WM close delivery.
It captures only the application window. Each run leaves its log and PNGs under `build/window-*`.

The consumer’s default `tools/verify.py` suite remains headless and checks that discovery and voxel binaries have no X11 or xcb dependency. `--presentation` requires real window acceptance and never treats a skipped run as a pass.
The driver runs shared graphics/present families, distinct families, and close while suspended sequentially.
The `--split` application flag requires a distinct present family for verification.

## API profile

A presentation instance enables these extensions:

- `VK_KHR_surface`.
- `VK_KHR_xlib_surface`.
- `VK_KHR_get_physical_device_properties2`.
- `VK_KHR_get_surface_capabilities2`.
- `VK_EXT_surface_maintenance1`.

`Instance.presentation_supported` checks the swapchain extension and maintenance feature through `vkGetPhysicalDeviceFeatures2KHR`.
`Instance.create_presentation_device` enables `VK_KHR_swapchain`, `VK_EXT_swapchain_maintenance1`, and `swapchainMaintenance1`.
Missing support fails startup explicitly. The wrapper exposes no idle-based fallback for presentation retirement.

| Operation | Result or contract |
| --- | --- |
| `Entry.open_window` | Checked `NativeWindow` owned by the Entry. |
| `NativeWindow.poll` | Dimensions, mapped/focus/capture state, and Base events. A wait is bounded to at most 1,000 ms. |
| `NativeWindow.capture` | The resulting capture state. Refused capture returns `False`. |
| `Instance.create_surface` | Surface owned by the Instance, retaining a window from the same Entry. |
| `Instance.surface_capabilities`, `surface_formats`, `present_modes`, `present_support` | Queries on a physical device and surface from the same Instance. |
| `Instance.create_presentation_device` | Graphics and present families, deduplicated when equal. |
| `Device.create_swapchain` | Validated format/color-space pair, count, extent, usage, transform, alpha, and present mode. |
| `Device.swapchain_images` | Interned borrowed `ImageHandle` keys. |
| `Device.acquire` | Explicit acquisition outcome, using a caller fence and U64 timeout. |
| `Device.release_acquired` | Maintenance release after acquisition and any rendering complete. |
| `Device.submit_synced` | One command and fence with binary wait/stage and signal lists. |
| `Device.present` | Matching rendered lease, render-finished semaphore, and maintenance presentation fence. |

Separate queue families use concurrent swapchain sharing. Command pools and submission use the graphics queue.
Presentation uses the present queue. Surface policy prefers a common family and otherwise chooses distinct supported families.
The selection checks supported surface formats and FIFO mode before creating a device.
UNORM formats are preferred for the existing packed palette. A single undefined surface format permits BGRA8 UNORM with the reported color space.

Borrowed images support views before acquisition and barriers/rendering after acquisition completion.
They reject direct destruction, memory requirements, and binding. Stale keys and wrong-owner handles reject before Vulkan dispatch.
Destroy views and reset recorded references before destroying a swapchain. Destroy the surface before its window.
`Entry.with` closes the complete dependency tree after either a successful callback or a callback failure.

## Frame and failure states

Each slot has separate acquisition, rendering, and presentation fences, plus one binary render-finished semaphore.
Its phases are Free, Acquiring, Submitted, Presenting, and Discarding. Each pending phase returns to native event processing.
The rendering fence resets after recording succeeds and immediately before submission. Acquisition paths that skip submission never reset it.

Acquisition returns `Acquired{acquisition, index, suboptimal}`, `AcquireOutOfDate`, `AcquireNotReady`, `AcquireTimeout`, or `AcquireSurfaceLost`.
Suboptimal and out-of-date request recreation. Timeout and not-ready preserve the generation.
Surface loss ends this checkpoint with an explicit error and cleanup. Full surface and device recovery remain outside its scope.
An acquired frame may be released after its acquire fence completes, without draining an acquire semaphore.

Presentation returns `Presented`, `PresentSuboptimal`, `PresentOutOfDate`, or `PresentSurfaceLost`.
Accepted out-of-date and surface-lost results retain their queued semaphore waits until presentation-fence evidence.
Present OOM leaves the rendered lease and semaphore unchanged for retry.
Semaphore signal provenance includes the acquisition sequence, so a signal from an earlier lease cannot present a later image.
Unknown acquire, submit, and present failures retain uncertain ownership. Fallible metadata reservation precedes irreversible dispatch.
A failed reset preserves recorded references. Known device loss permits scoped teardown.

A render fence proves graphics completion. It does not retire a present wait.
`Device.wait_idle` completes graphics state while preserving presentation associations.
Every present supplies `VkSwapchainPresentFenceInfoEXT`. Its fence proves that the associated resources can be released.
That fence does not prove visible scanout. It completes only the matching acquisition; independent acquisitions may remain pending.
The [Khronos fence contract](https://docs.vulkan.org/refpages/latest/refpages/source/VkSwapchainPresentFenceInfoKHR.html) defines this distinction.
If cleanup cannot establish completion, it reports a failure and keeps the resource tree live.

Resize and suspension mark the target obsolete before servicing slots. A suboptimal or out-of-date outcome makes that knowledge visible to later slots in the same traversal. No further present is issued for that target. Already-issued presents retain their exact resource fences. A rendered packet that has not been presented consumes its render-finished semaphore through an empty wait submission. After that submission's fence is observed, the slot releases its exact acquisition lease. These discarded packets consume their submission positions without increasing frame or completed-revision counters.

Recreation observes every matching completion owner, resets commands, destroys the old target, and requeries the surface.
It creates with `oldSwapchain = NULL`. A failed target build destroys its partial resources and produces no target.
Each generation rebuilds format-compatible passes/pipelines and extent-dependent depth, views, and framebuffers.
Unmapped and zero-sized windows suspend acquisition before extent clamping and poll with a 50 ms timeout.

## Projection and editing

The viewport centers rays at half the actual width and height and keeps the upstream half-pixel offset.
Focal pixels scale by height divided by 512. The camera matrix uses the same scale with the actual aspect ratio. Pointer coordinates map to the current target extent during recreation.
Picking scans front-facing intersections without the upstream renderer's fixed-512 tile or projection cull. It follows the renderer's back-face culling when the camera enters solid geometry.
Landscape and portrait resize therefore preserve agreement between displayed faces and edits.

The consumer reuses the packed mesh, upload, publication, and indexed draw helpers used by the offscreen renderer.
Each cut and reset prepares the CPU body and picking mesh together, so queued clicks use the current surface before upload.
World owns the authoritative Body and derived ChunkSet, original scene choice, camera, controls, pointer and CPU revision. Session owns a nonempty fleet of independently owned slots and the latest immutable GPU generation. Camera changes retain chunk buffers and mesh upload counts.
After acquisition-fence SUCCESS, the loop reuses the installed generation when the authoritative body revision is unchanged. Otherwise it prepares the latest CPU chunks. It computes hover, exact selection, camera, viewport and all 2,336 appearance bytes from that same revision. Upload, record and submit finish before another event batch. Each slot keeps those bytes frozen in its own uniform and attachments. The immutable submitted receipt carries the acquisition, image index, body revision, CPU start time, active query view and submission sequence. Native recorded references retain its geometry through completion and successful reset. Inputs during Submitted or Presenting update World for a later acquisition. A presented slot becomes reusable after observing its matching presentation-resource fence and successfully resetting its command. That fence can signal before the full present operation completes. Packets receive consecutive U64 submission sequences. A ready packet waits until its sequence is the next present call, independent of slot index, acquisition serial or body revision. Every resolved present outcome consumes that position; completion fences remain independently observable. UINT64_MAX is never submitted, so exhaustion fails before another upload or recording.

Move and button events refresh the uncaptured pointer. Captured look and edits deliberately use the current viewport center. Ground is not pickable and does not write the voxel depth that hides rings.

Programs, schemas, sampler and ring indices are immutable shared resources. Every slot separately owns commands, acquisition/render/presentation fences, semaphore, reusable staging, uniform/descriptors, fixed 512-square shadow attachment, depth attachment and per-image framebuffers. Trace-enabled slots also own independent query pools; quiet product runs allocate none. A target recreation stops acquisition, drains every matching lease and resets recorded references before releasing local framebuffers and the shared target. The shared `Target` owns the swapchain, borrowed-image views and compatible programs. Each `SlotTarget` owns only its depth attachment and framebuffers and has a distinct destructor. The shared target allocates no unused depth or framebuffers. Both native presentation and offscreen readback call `Scene.record`.

## Evidence boundaries

`tests/semaphores.bend` verifies binary signal-to-wait submission with literal GPU readback.
`tests/interactive.bend` checks literal occupied-voxel counts after queued cuts and reset before upload, plus a cavity hit within 0.001 cm.
`tests/viewport.bend` checks off-center landscape and portrait hits against literal intersections with the cube's y=0 plane within 0.001 cm.
`tests/presentation_abi.bend` checks emitted records, Boolean fields, events, outcomes, wait descriptions, and U64 limbs.
`tools/check_native.py` controls semaphore allocation failure, OOM, uncertainty, and signal retention beside actual GPU tests.
`vulkan/tools/check_presentation.py` controls changing image counts, interning, allocation rollback, uncertain acquisition, present OOM retry, accepted errors, and independent presentation retention.
It also injects a pipeline failure into the Bend target builder and checks that every partial resource is released.
These injected outcomes do not claim driver or hardware failure coverage.

`vulkan/tools/check_window.py` requires visible image changes and model changes for camera and edits.
Each resized edit must change pixels, and reset must restore the intact image at the same camera and extent.
Its `--product` check builds the ordinary executable, verifies default quiet output, compares actual cut and reset pixels, and closes the unmapped window.
It checks capture loss, repeated non-square recreation, suspension, restore, continued input, Escape, and WM close.
A native dispatch counter verifies that acquisition stops while the window is unmapped.
The emitted test allocator bounds wrapper metadata and requires zero allocations and zero registry rows after shutdown.
ASan driver-global leak detection is disabled. Wrapper counters remain explicit.
Pure laws cover queue selection, formats, image counts, suspension, extent selection, and pixel-center units.
They do not prove floating-point calculations, native effects, Vulkan drivers, or shaders.

`vulkan/tools/check_atelier_window.py` drives actual default Atelier runs with graphics and presentation queue families 0/0 and 0/2. It checks images after settled-hover clicks, Space and reset, revisions and upload counts, flight and relative look, resize, suspension and remapping and zero-row shutdown. `vulkan/tools/check_window.py` retains explicit `--cube` regression invocations; its quiet-product check uses default Atelier and settles hover before capturing the intact image. A pointer-only image change cannot count as carving.

`tests/appearance_acquisition.bend` runs four real-device sessions. The first
queues an acquisition-time edit, submits two distinct geometry/camera packets,
rejects host reads of both uniforms before either render fence is observed,
then compares every uniform byte, distinct actual D32 shadow readbacks and the
latest installed geometry. The second changes camera/pointer state during
Presenting and checks that a later acquisition uses it without uploading
geometry. The third checks dispatch order for camera-only packets with equal body revision. The fourth drains two obsolete submitted packets through their semaphore waits and exact acquisition releases without presenting or counting them. Each Entry scope checks zero remaining rows. `tests/interactive.bend`
retains literal queued cut/cut/reset/cut picking checks.

The complete milestone 6 gate passed with `env -u DISPLAY python3 tools/verify.py --sanitize --presentation --isolated-display`. Actual Atelier app-only captures and traces remain under `build/milestone-6-atelier-window-*`; quiet product captures remain under `build/window-product-*`. The [appearance contract](voxel.md#production-appearance-and-evidence) states exact identity, lighting and shadow comparison limits.


Each successful `Device.acquire` returns an `Acquisition{swapchain, serial}`
beside its image index and suboptimal flag. A swapchain preallocates independent
lease storage for its images. The serial is never reused. `CommandBuffer.use_acquisition`
binds the completed acquisition explicitly after begin and before recording
borrowed-image commands. Recording and submission reject mismatched or stale
acquisition generations.

`Device.present(device, acquisition, wait, fence)` and
`Device.release_acquired(device, acquisition)` require that exact token. Acquire,
render and presentation fence completion update only their associated lease.
A fence cannot be reused while a command or WSI operation owns it. Semaphore
provenance retains the exact acquisition serial. Uncertain WSI ownership remains
quarantined through recovery and requires the affected swapchain to be drained
and destroyed when its image ownership cannot be recovered.

A successful presentation retains its own completion owner, while a later acquisition may own the same image index. Current-image checks exclude retained presentation owners. Each swapchain preallocates twice its image count in lease records. Exhausting those records rejects a new acquire before dispatch. Observing an older presentation fence releases only its matching serial and semaphore.


The native loop services every slot and fills free acquisitions before it polls
new render submissions. `--slots=1` and `--slots=2` select one or two owners.
Normal event polling waits up to 1 ms after slot work; suspension waits up to
50 ms. `STATE completed_revision` is the newest body revision with an observed matching
presentation-resource fence after a successful present call. An older completion cannot overwrite it.
Installation alone does not advance the tag, and physical scanout is outside
this observation. UINT32_MAX means unavailable and is never a body revision.
The last valid revision is UINT32_MAX-1; a further edit fails before changing
Body, so completion ordering never crosses a revision wrap.

With `--trace`, CPU scopes use CLOCK_MONOTONIC U64 nanoseconds. Event/mesh work,
allocation/staging/uniform upload, command recording/submission and the present
call are disjoint scopes. Fence waiting and display latency are separate from
those CPU calls. Upload preparation includes any deferred realization of packed
source arrays; the event scope alone does not claim all meshing cost. GPU timestamp windows bracket upload, shadow and main command groups with
TOP_OF_PIPE starts and BOTTOM_OF_PIPE ends. These inclusive windows can include
preceding work still completing and overlap following work. They do not isolate
exclusive stage costs, and neither the windows nor CPU and GPU samples can be
added. The [timestamp command contract](https://docs.vulkan.org/refpages/latest/refpages/source/vkCmdWriteTimestamp.html) defines those synchronization scopes. Display timing remains unmeasured. Capabilities report the actual valid bits and period.
Unsupported timestamps, unavailable results, failed query reset and ambiguous
half-wrap bounds emit explicit unavailable diagnostics and preserve rendering.
A failed reset disables that frame's query view, so old completed values cannot
be attributed to a new frame. `vulkan/tools/check_timing.py` injects that exact failure.
`vulkan/tools/measure_m7.py` decodes the known integer-limb/F32 protocol and preserves
the producer scope labels. No absent baseline attribution is inferred.

The complete milestone 7 sanitizer and isolated-display gate passed on NVIDIA
GeForce GTX 1660 with Khronos and synchronization validation. Its log is
`build/milestone-7-final-verification.log`. Shared and split queue pairs 0/0 and
0/2 passed actual Atelier edits, flight, resize, suspension, remap and close.
The acquisition fixture verifies both pending uniform owners before either
render fence is observed, all 2,336 bytes after completion, distinct shadow
readbacks, equal-revision camera ordering and discarded-packet cleanup.

The measurement driver alternates fresh native processes and requires exact
static RGB, geometry and view signatures across each pair. A mismatch excludes
that pair from comparative timing. Its flight workload shares scripted input
duration across sides, while time-driven camera poses can differ. Reported
throughput counts observed matching presentation-resource fences. It does not
measure physical scanout or establish identical per-frame GPU work.
