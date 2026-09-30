# Parallelism

Parallelism laws for bend-voxel:

- Independence alone is not sufficient reason to fork.
- Prefer sequential execution unless representative end-to-end benchmarks
  demonstrate a repeatable improvement.
- Benchmark candidate parallelism at 1, 6, and 12 threads.
- Validate candidates in real Vulkan workloads, not only headless benchmarks.
- Reject performance changes that alter observable world/geometry state.
- Keep fine-grained work sequential at leaves.
