# Vulkan replay profiling

Run `make benchmark` after installing the dependencies listed in the [README](../README.md). The native window uses a 640 × 360 logical viewport. Each of three runs records five seconds of warm-up and sixty seconds of measured work. A single diagnostic run can be requested with `python3 scripts/benchmark.py --runs 1 --output build/pilot` after `make build`; three passing runs are required for acceptance.

Every duration is a wall-clock microsecond interval. The Vulkan frame effect includes Bend heap traversal, native scene and HUD geometry preparation, upload, draw submission, presentation, event handling, and X11 synchronization. The frame interval includes gameplay, scene preparation, and the effect. X11 synchronization confirms server processing rather than physical display scanout.

The raw CSV contains these rows without a header:

```text
frame,elapsed_us,frame_us,solids,bodies
stage,elapsed_us,carve_us,connectivity_us,surface_us,finalize_us,update_other_us,scene_us,vulkan_frame_us,overhead_us
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

The timed path uses the same `W.carve.prepare`, `W.carve.classify`, `W.carve.surfaces`, and `W.carve.finalize` transaction as interactive carving. Each phase is forced through `IO.pure` before its end timestamp. Protected and empty-target commands skip the transaction and record zero for all four edit stages. Multiple edits within one frame produce individual `edit` rows and summed frame-stage durations.

The report validates frame/stage joins, uninterrupted frame intervals, stage sums, per-edit sums, and edit/latency correspondence. `instrumentation_pass`, `workload_pass`, and `performance_pass` are separate. Statistics exclude warm-up frames ending before five seconds; the raw CSV retains them. Stage percentiles are not additive. Instrumentation and CSV output cost remains in the end-to-end measurements.

Historical Bend3D snapshot and CPU/CUDA comparison procedures are documented in [the earlier validation](demo-validation.md) and [the controlled comparison](research/controlled-cpu-cuda.md). Their commands are no longer part of the current build.
