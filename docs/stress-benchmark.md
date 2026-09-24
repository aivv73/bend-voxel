# Stress and scale benchmark

Run the throughput suite after installing the demo's build dependencies:

```sh
make benchmark-stress
```

The runner writes one raw CSV and stderr log per case, plus `build/stress/report.json`. A short diagnostic run is:

```sh
make build
python3 scripts/benchmark_stress.py --cases demo comb-4x --warmup 10 --frames 60 --output build/stress-pilot
```

The default suite runs 30 warm-up frames and 180 measured frames per case. One carve is requested every 30 frames during measurement. The cases are:

| Case | World | Render copies |
| --- | --- | ---: |
| `demo` | Original 4,640-solid scene | 1 |
| `dense` | Upper half filled, with supports below | 1 |
| `full` | All 19,200 lattice cells filled | 1 |
| `comb` | Floor joined to alternating vertical columns | 1 |
| `comb-4x` | Same comb scene | 4 |
| `comb-16x` | Same comb scene | 16 |

The world stays within the current 40 × 24 × 20 lattice. The dense and full cases increase traversal and edit work. The comb exposes many surface rectangles. Render copies draw the same faces at the same positions, increasing render work without adding simulated cells or bodies. `face_inputs_per_rebuild` counts input rectangles times copies. The renderer reuses native scene geometry and uploads only dynamic overlays while the face records, including body offsets, remain unchanged. Camera and aim changes leave the world mesh cached; aim preview, ring, and HUD geometry are updated separately. Edits and moving bodies can trigger a full geometry rebuild and upload. This suite characterizes the current bounded implementation, rather than establishing an unbounded world scale limit.

The stress runner requests Vulkan immediate presentation, falling back to mailbox. It fails if neither is available, records the selected mode, and does not silently publish FIFO-paced throughput. It does not change the presentation mode of `make run`.

`throughput_fps` is measured frames divided by the sum of their full frame intervals. Frame p50/p95/p99, accepted edit latency, initialization, solid count, surface rectangle count, maximum body count, and stage timings are reported per case. `acquire_wait_fraction` is the share of frame time inside swapchain image acquisition. Fence waits and presentation may still apply backpressure; these are wall-clock CPU intervals, not GPU execution timestamps. The suite checks completion, sample accounting, edit acceptance, and an unpaced mode. It has no FPS acceptance threshold, because its purpose is to show the throughput curve and bottlenecks.

Use `--cases`, `--warmup`, `--frames`, `--edit-every`, and `--output` to select a smaller or larger run. `--edit-every 0` measures steady rendering without carving. The previous fixed-duration replay has been retired; its historical results remain in the [Vulkan validation archive](vulkan-renderer.md).
