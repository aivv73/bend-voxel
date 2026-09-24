# Vulkan replay profiling

Run `make benchmark` after installing the dependencies listed in the [README](../README.md). The native window uses a 640 × 360 logical viewport. Each of three runs records five seconds of warm-up and sixty seconds of measured work. A single diagnostic run can be requested with `python3 scripts/benchmark.py --runs 1 --output build/pilot` after `make build`; three passing runs are required for acceptance.

Every duration is a wall-clock microsecond interval. The Vulkan frame effect includes Bend heap traversal, native scene and HUD geometry preparation, upload, draw submission, presentation, event handling, and X11 synchronization. The frame interval includes gameplay, scene preparation, and the effect. X11 synchronization confirms server processing rather than physical display scanout.

The raw CSV contains these rows without a header:

```text
frame,elapsed_us,frame_us,solids,bodies
stage,elapsed_us,carve_us,connectivity_us,surface_us,finalize_us,update_other_us,scene_us,vulkan_frame_us,overhead_us
vulkan_stage,frame_index,bridge_prepare_us,geometry_us,fence_wait_us,vertex_upload_us,acquire_us,command_record_us,submit_present_us,renderer_other_us,events_x11_sync_us
cut,scheduled_absolute_us,latency_us,status,kind
attempt,scheduled_absolute_us,latency_us,status,kind
edit,frame_elapsed_us,scheduled_absolute_us,kind,status,carve_us,connectivity_us,surface_us,finalize_us
```

`frame_us` is the entire interval between completed presentations. The first frame starts at the benchmark epoch. Cut and attempt latency starts at the scheduled command time and ends after presentation, including queueing. Absolute timestamps are wrapping U32 microseconds; durations use modular subtraction in Bend. No slow samples are removed. The final frame crossing the 65-second boundary is retained.

The eight exclusive stage components add up to each frame's interval:

| Stage | Boundary |
| --- | --- |
| Carving | Clone the candidate voxel array and remove eligible cells. |
| Connectivity | Full-grid scan, six-face flood fill, component classification, and body ID assignment. |
| Surface generation | Build cached, merged exposed-face rectangles for classified bodies. |
| Edit finalization | Commit the candidate or roll back at the body cap. |
| Other update | Physics, command lookup, reset, camera update, and surrounding timing work. |
| Scene preparation | Picking and HUD text preparation. |
| Vulkan frame effect | Expand and upload geometry, record and submit draws, present, poll events, and synchronize X11. |
| Overhead | Remaining interval, including prior-frame CSV output and loop control. |

Each `vulkan_stage` row splits the Vulkan frame effect into nested CPU wall-clock intervals. `frame_index` is zero-based and joins to `frame` rows in output order; all frames, including warm-up, have one detail row. The nine detail components are:

| Component | Boundary |
| --- | --- |
| Bridge preparation | Bend effect synchronization, HUD conversion, and traversal of Bend body and face lists. |
| Geometry generation | CPU expansion of faces, aim geometry, and HUD glyphs into vertices. |
| Fence wait | Wait for the previous frame's Vulkan fence. |
| Vertex upload | Grow the host-visible vertex buffer if needed and copy vertices. |
| Image acquire | Wait for and acquire a swapchain image. |
| Command recording | Record the render pass and draw commands. |
| Submit and present | Submit commands and call `vkQueuePresentKHR`. |
| Renderer other | Renderer initialization, swapchain recreation, and time outside the measured renderer sections. |
| Events and X11 sync | Free the HUD copy, poll input, materialize events, and synchronize with X11. |

The report includes per-component statistics under `vulkan_stages`, plus `bend_effect_overhead` for the difference between the parent Vulkan effect and the nested intervals. The parser checks row coverage and rejects detail sums larger than their parent frame effect. These measurements identify CPU work and API blocking time. They do not measure GPU execution or physical display scanout. First-frame renderer initialization remains in `renderer_other` and warm-up frames remain in the raw CSV.

The swapchain uses [`VK_PRESENT_MODE_FIFO_KHR`](https://docs.vulkan.org/refpages/latest/refpages/source/VkPresentModeKHR.html), which schedules presentation at display refresh intervals. `vkAcquireNextImageKHR` can wait for a swapchain image to become available. A frame interval close to the display period, with most time in `image_acquire`, can therefore reflect presentation pacing rather than scene processing cost. For example, 143.88 Hz corresponds to about 6.95 ms per refresh. Compare frame timings under the same display, compositor, and presentation settings; use the other stages to locate application work.

The timed path uses the same `W.carve.prepare`, `W.carve.classify`, `W.carve.surfaces`, and `W.carve.finalize` transaction as interactive carving. Each phase is forced through `IO.pure` before its end timestamp. Protected and empty-target commands skip the transaction and record zero for all four edit stages. Multiple edits within one frame produce individual `edit` rows and summed frame-stage durations.

The report validates frame/stage joins, uninterrupted frame intervals, stage sums, Vulkan detail coverage and containment, per-edit sums, and edit/latency correspondence. `instrumentation_pass`, `workload_pass`, and `performance_pass` are separate. Statistics exclude warm-up frames ending before five seconds; the raw CSV retains them. Stage percentiles are not additive. Instrumentation and CSV output cost remains in the end-to-end measurements.

Historical Bend3D snapshot and CPU/CUDA comparison procedures are documented in [the earlier validation](demo-validation.md) and [the controlled comparison](research/controlled-cpu-cuda.md). Their commands are no longer part of the current build.
