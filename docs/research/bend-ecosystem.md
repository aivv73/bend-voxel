# Bend ecosystem resources for the voxel engine

## Subsequent compiler update

On 2026-09-22, the project was updated to **Bend 2.0.25** at the user's request. The 2.0.16 observations below are historical; they have not been relabeled as checks of the new compiler. See [demo validation](../demo-validation.md) for current validation.

Reviewed 2026-09-22. Discovery sources: [awesome-bend](https://github.com/777genius/awesome-bend) and [BendHub](https://hub.bend-lang.com/). Findings below distinguish upstream claims, local compatibility checks, and proposed applications.

At review time, the engine was pinned to Bend 2.0.16, Linux/X11, GTX 1660 and forced CUDA. Its [three-run baseline](../demo-validation.md) misses both frame-p95 and cut-p95 targets. The best immediate ecosystem contribution is a better profiling and correctness workflow. No dependency or compiler was installed or upgraded, and no engine code was changed by this review.

## Highest-value references

| Resource | Verified upstream evidence | Application to this engine |
| --- | --- | --- |
| [portal-bend GPU investigation](https://github.com/danielhe4rt/portal-bend/blob/fa130db948ec01f882c84781271cf1c7dfb0dd8f/docs/guide/GPU.md) | Separates empty GPU launch, ray computation and image construction; checks emitted C and CPU/GPU image agreement. Its headless probe reads the image on the host only at the end. | Adapt its measurement design to distinguish scene preparation, rasterization, allocation/transfer and presentation. Its small 2.5D map and headless timings cannot predict our destructible 3D windowed workload. |
| [portal-bend CPU investigation](https://github.com/danielhe4rt/portal-bend/blob/fa130db948ec01f882c84781271cf1c7dfb0dd8f/docs/guide/CPU.md) | Tests changes independently, preserves snapshots, and reports both wins and regressions. It uses Bend 2.0.10 and a Ryzen 9 7950X; some tile and selector changes made its renderer slower. | Sweep thread counts and compare backends diagnostically. Retain forced CUDA for the agreed acceptance test. Do not assume a CPU optimization helps CUDA, or that more workers are faster. |
| [Official shader guide](https://github.com/bendlang/bend/blob/main/guide/SHADERS.md) | Describes host-prepared tile candidates, flat device loops, ownership costs and generated-C inspection. Its voxel section recommends staging compact column data instead of having each GPU ray traverse a shared world tree. | Audit ownership and per-tile candidate volume first. Explore packed occupancy only as an experiment: our mutable ownership grid and moving bodies need more information than occupancy bits. |
| [bend-night-train](https://github.com/kvcop/bend-night-train/tree/8db048b50dca0bba0aaebb6969405338e75ff54a) | MIT-licensed tile rasterizer, with per-tile triangle/billboard candidates, reference-image comparison and explicit known image differences. Its README reports CPU timings, not demonstrated GPU performance. | Useful reference for image regression tests and separating visibility from shading. Not an established faster replacement for Bend3D. [Architecture](https://github.com/kvcop/bend-night-train/blob/8db048b50dca0bba0aaebb6969405338e75ff54a/docs/structure.md), [measurement method](https://github.com/kvcop/bend-night-train/blob/8db048b50dca0bba0aaebb6969405338e75ff54a/docs/benchmarks.md). |
| [raytracing-bend2](https://github.com/aguspiza/raytracing-bend2/tree/cd79fdcd8280f6b050cb8137faceda2af072fc44) | Splits interleaved image rows across parallel branches and proves structural properties, including equivalence to its sequential row renderer. It explicitly excludes floating-point shading from those proofs. | A model for balancing independent work and proving traversal transformations. It is an offline path tracer, not a real-time voxel renderer. |

Our renderer already uses the Bend3D tile tree and an IO boundary before its GPU call (`src/render.bend`, `src/demo.bend`). Merely adding another GPU call would not implement a new optimization. The next useful check is whether the actual compiled ownership and task structure match the intended design.

No explicit license was identified in the inspected portal-bend or raytracing-bend2 repository metadata/root listings. Use their findings as references; clarify reuse terms before copying source into the engine.

## Tools and proofs

**Bolt — trial first.** [Bolt 0.7.0](https://github.com/Emerging-Patterns/bolt/tree/1085266c5d531c2798c21b965043ebe01800b1c8) is an MIT-licensed linter/check wrapper/LSP. Its current README requires a source-built Bend; compatibility with our installed 2.0.16 was not tested. Its [rules](https://github.com/Emerging-Patterns/bolt/blob/1085266c5d531c2798c21b965043ebe01800b1c8/bolt/README.md) cover eager selectors, recursion inside strict boolean expressions, repeated list indexing, append accumulators, unary-Nat costs and unsafe declarations. Start with those review rules before making Bolt a build dependency.

A concrete local audit candidate is `src/world.bend:body.find`: it passes the recursive lookup as an argument to `vec.choose`. `remove.scan` invokes it for each lattice cell. Check the eager evaluation and traversal cost, then measure an early-return or indexed lookup variant. This is a performance hypothesis, not an established explanation of the observed frame or cut latency.

**bend-lemmas — useful for specific future laws.** [The inspected revision](https://github.com/caiodomingues/bend-lemmas/tree/b34ec002455d139ad9a32a42ac2ed65e737f0265) is MIT licensed and supplies reusable Nat/List/Bool/String proofs. Its [README](https://github.com/caiodomingues/bend-lemmas/blob/b34ec002455d139ad9a32a42ac2ed65e737f0265/README.md) reports template-proof validation on Bend **2.0.23**, newer than our pin at review time. Potential applications are body-list length preservation, filter count bounds and traversal equivalence. It does not supply proofs of voxel connectivity or floating-point collision. Map get/set laws remain open and their module is excluded from the aggregate import. Check selected modules against the current project compiler when an actual engine law needs them.

**bend2-fuzzer — compiler diagnostics.** [Its README](https://github.com/nicolas-abril/bend2-fuzzer/blob/b4504fe64d1e154eab6b8ef340b21bf91be28867/README.md) describes generated typed programs, differential backend checks, shrinking and optional CUDA checks. It needs Bun and a compiler source checkout. It is useful for a compiler upgrade or CPU/GPU disagreement, but does not generate voxel edits or validate game behavior. Compatibility and reuse licensing were not established here.

## What the Hub actually offers

The Hub uses content-hash identities and caches fetched packages locally. Its current front page loads a paginated list from [`index.json`](https://hub.bend-lang.com/index.json); it is browsable even though it has no conventional name/version search. This review retrieved **121 package snapshots**, including multiple snapshots of the same project. That is not 121 distinct libraries. [Hub documentation](https://hub.bend-lang.com/).

The following exact published sources were downloaded into temporary directories and checked with the installed **Bend 2.0.16**. No project imports were added. These checks establish that the inspected modules pass the checker; they are not runtime benchmarks, semantic audits, or complete proofs.

| Candidate and immutable source | Local checker result | Potential use and limit |
| --- | --- | --- |
| [Deque](https://hub.bend-lang.com/0x12ed1da25aa4f36622687d603aeb34e0/deque.bend) | Exit 0, `All terms check.` | Two-list double-ended queue; future edit/job queues or breadth-first work. Our existing flood uses a stack, so this is not automatically an improvement. |
| [Heap](https://hub.bend-lang.com/0x010f315b70bbac62ddd97e2e3de5f9cc/heap.bend) | Exit 0, **4 unsafe annotations** | Comparator-driven skew heap; possible prioritized chunk rebuilding or streaming. Not required for the current bounded scene. |
| [PRNG](https://hub.bend-lang.com/0xfd7037736e4fa1794a671d0278638da7/lib.bend) | Exit 0, `All terms check.` | Seeded xorshift32; reproducible generated carving tests and later procedural scenes. The checked entry is `lib.bend`, not its separate proof suite; bounded sampling uses modulo. |
| [U64 package](https://hub.bend-lang.com/0x0f1da4e80677f1d50e6f638a7d6f27ef/package.bend) | Entry plus imported implementation: exit 0, `All terms check.` | Pure `Word(64n)` representation; candidate for wider persistent IDs or spatial keys. Do not assume native machine-word speed; its repeated shifts are folds. |
| [I64 package](https://hub.bend-lang.com/0x9f15483a7cabc6e91e5092cc41829c43/package.bend) | Entry plus imported implementation: exit 0, `All terms check.` | Signed two's-complement operations over `Word(64n)`; possible future world coordinates. Current bounded coordinates do not require it. |

Example import for a future isolated experiment:

```bend
import 0x12ed1da25aa4f36622687d603aeb34e0/deque.bend as Queue
```

The numeric package headers identify [bend-u64](https://github.com/phenomenon0/bend-u64) and [bend-i64](https://github.com/phenomenon0/bend-i64) as their source repositories. Resolve provenance/licensing and pin the exact hash before adopting any candidate. The small queue/heap/PRNG package snapshots inspected here do not include a license file.

No dedicated voxel, octree, meshing or rigid-body package was identified in the awesome list and the Hub index descriptions/filenames reviewed. This is a bounded discovery result, not a claim that no such Bend project exists.

## Alternatives to defer

[godot-bend](https://github.com/aricarmo/godot-bend/blob/2936baf7605779271b6d641c6d56f5dc4150c44d/README.md) is an MIT-licensed GDExtension proof of concept. It could support a future architecture in which Bend owns simulation and Godot owns presentation. Its documentation says GPU-marked Bend functions are not expected to build with its current build script, performance is unmeasured, and runtime internals are pinned. It is not a drop-in fix for our current standalone CUDA engine.

The inspected [bend2-nix flake](https://github.com/nicolas-abril/bend2-nix/blob/e9f69b76e3a16bfd68b79499d203576aaeab8686/README.md) offers pinned compiler source but says full build validation is incomplete and does not install CUDA. Keep the working compiler/CUDA setup while investigating performance.

## Official demos: follow-up review

The [official demo directory](https://github.com/bendlang/bend/tree/a49524265bdfa5753a4bf38e25f0574a705dd868/demos) is especially relevant. At this review, `main` resolved to **a49524265bdfa5753a4bf38e25f0574a705dd868**, our existing renderer pin. A fresh download of its `app_slash_boss_3d/bend3d.bend` was byte-identical to `src/vendor/bend3d.bend`. The additional opportunity is in the application and testing code around that library.

### Use first: Slash Boss's profiling and replay harness

[Slash Boss main.bend](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/demos/app_slash_boss_3d/main.bend) provides several concrete patterns:

- `Probe.frame`, `Probe.loop` and `Sums`: separate scene build, render, simulation, audio and whole-turn measurements; eight initial warm-up frames.
- `SLASH_PROBE`, `Script.tick` and `Probe.watch`: scripted input with state/cue traces.
- `SLASH_DUMP` and `Dump.tree`: headless image-tree output for snapshots.
- `Live.steps`, `Live.after` and `Live.view`: 60 Hz simulation with interpolation between the previous and current tick. Elapsed time is capped at 100 ms; only the fractional tick remainder is carried forward.
- `Scene.build` and `Play.loop`: independent scene branches, old-scene disposal alongside construction, an IO boundary, and one frame render.

Adapt the stage boundaries and snapshot mechanism first. Its probe reports averages derived from millisecond clocks and omits native-window presentation, so it cannot replace our microsecond samples, latency percentiles or end-to-end acceptance test. Fixed-step simulation is a separate engine change requiring replay validation.

### Other useful official examples

| Demo | What to reuse or study | Limits for our engine |
| --- | --- | --- |
| [app_triangle_2d](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/demos/app_triangle_2d/main.bend) | A tiny reference for emitting one image leaf for a uniform region and subdividing only when needed. Useful for image-tree regression fixtures. | It handles a single 2D triangle and tally overlay; it does not establish a 3D depth/visibility shortcut. |
| [app_ray_tracer_3d](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/demos/app_ray_tracer_3d/main.bend) | Compact free-flight camera, held-key state and an SDF ray-marching scene, rendered by a root GPU call. | It builds a full image tree down to pixel leaves. Treat it as a small alternative-renderer experiment, not evidence that voxel ray tracing beats our tiled rasterizer. |
| [app_pong_game_2d laws](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/demos/app_pong_game_2d/LAWS.bend) | Examples of proving event-fold behavior and that the latest key update wins. | Our Escape releases controls rather than quits, so write our own law. The demo does not prove our mouse latches, focus handling or physics. |
| [pure_par_sum](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/demos/pure_par_sum/main.bend) | Minimal balanced fork/join and root GPU-call pattern; potential model for independent chunk counts or bounds. | Our owned array needs a partition/read representation before parallel work. Its Nat equivalence proof says nothing about F32 reduction order or speedup. |
| [pure_par_sort laws](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/demos/pure_par_sort/LAWS.bend) | Bitonic-sort teaching example for a later measured sorting workload. | The laws establish sum preservation, not general sortedness or permutation. Do not treat them as a complete sorting-correctness proof. |
| [proof_numerics](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/demos/proof_numerics/LAWS.bend) | Nat algebra and quotient/remainder specifications; a starting point for coordinate-index laws. | A bridge to bounded U32 arithmetic is still needed. No proof here covers array safety, U32 overflow or F32 carving/gravity. |

### Rollback: use the testing pattern before networking

The [rollback demo](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/demos/io_rollback_netcode/README.md) models tick-based inputs, prediction and replay. Its [headless walkers test](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/demos/io_rollback_netcode/walkers_test.bend) drives the same tick function as the interactive application and emits state hashes. We can use that pattern for repeatable carving traces before considering multiplayer.

Direct integration has a concrete obstacle: [Net.Game requires `State: Data`](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/demos/io_rollback_netcode/netcode.bend), while our array-owning `World` is `Type`. We would need a snapshot representation, deterministic tick timing and validation of cross-backend numeric behavior. Replaying destruction also repeats expensive rebuilds. Defer networking; hashes are useful regression signals, not proofs of equal state.

### Local compatibility evidence

Checked the official `PROOF.bend` entries in temporary directories using installed Bend 2.0.16:

| Entry | Result |
| --- | --- |
| app_triangle_2d | Exit 0; all terms check, with 2 unsafe annotations |
| app_pong_game_2d | Exit 0; all terms check, with 2 unsafe annotations |
| app_ray_tracer_3d | Exit 0; all terms check, with 2 unsafe annotations |
| app_slash_boss_3d | Exit 0; all terms check, with 30 unsafe annotations |

These are checker results, not native/CUDA execution or performance results. The unsafe counts include reachable imports; they must not be described as complete formal verification of graphics or simulation. The ray-tracer laws explicitly concern keys and Escape, not its F32 scene. The [Slash Boss README](https://github.com/bendlang/bend/blob/a49524265bdfa5753a4bf38e25f0574a705dd868/demos/app_slash_boss_3d/README.md) similarly scopes its laws to pause/event behavior and selected sanity facts.

## Recommended next work

1. Model stage instrumentation and snapshot output on the official Slash Boss probe. Add timings for carving, connectivity/meshing, scene preparation, CUDA rendering and presentation; retain the complete end-to-end samples.
2. Use portal-bend's controlled comparison method: same replay, same pixels/state checks, interleaved runs, thread-count sweep. CPU runs are diagnostic, not substitutes for CUDA acceptance.
3. Audit eager recursive selectors and repeated owner lookups using Bolt's documented rules; measure one change at a time.
4. Add deterministic generated edit sequences and image snapshots. Consider the small PRNG or selected proof lemmas only when those tests/laws need them.
5. Defer new containers, Godot integration and packaging changes until a measured requirement justifies them.
