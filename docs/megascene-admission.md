# Megascene admission

Issue #48 adds a separate admission command. It constructs the actual initial
voxel bodies, cached surfaces and vertices through the existing Bend world
allocator and geometry engine, then checks the resulting inventory. Light
Atelier's default executable, controls and benchmark commands are unchanged.

```sh
python3 scripts/megascene.py --preset small --seed 45 --output build/megascene/small-45
python3 scripts/megascene.py --side-m 128 --seed 46 --threads 6 --output build/megascene/large-46
python3 scripts/megascene.py --side-m 96 --seed 45 --output build/megascene/intermediate-45
```

Use a new output directory for every invocation. The command requires Python
3.10+, Bend 2.0.34, its native C compiler, and Linux/glibc. No display or Vulkan
device is used. The explicit command is `--case admission`, which is also the
default. Small/large mean the accepted 64/128 metre centered districts; seeds
45/46 and thread counts 1/6/12 are supported. Integer square scales q=2..5
are admitted through `--side-m 32*q`; q=2 and q=4 retain the small/large preset
names. This operational range does not assert a physical capacity limit.
Defaults are small, seed 45, six
threads and a detached-fragment budget of 2,048. `--fragment-budget` accepts a
canonical unsigned decimal value, including zero, when the initial-owner plus
budget count fits the operational U32 guard; it never counts initial anchored
owners. `--side-m` selects a scale or corroborates a named preset.

Malformed, duplicate, contradictory and unsupported options fail with exit code
2. The requested argument vector and parsed options are retained, with effective
settings only after configuration acceptance. An available, uniquely specified
output directory receives a rejection manifest/summary even for malformed
arguments. An existing directory is never overwritten. Without a valid new
destination the rejection is emitted to stderr.

The admission case rejects rendering controls, including `--profile full`;
it never substitutes admission for a rendering workload. Issue #49 adds a
separate [static Vulkan case](megascene-static.md) with its own rendering,
schedule and archive controls. Other scenarios, diagnostics, calibration and
search remain later capabilities.

## Construction and numeric scope

The Bend generator implements the exact accepted [recipe](megascene-workload.md)
in integer coordinates. Its Python adapter checks the complete ordered source
stream before admission. All neighborhoods' terrain boxes belong to owner 1.
Subsequent IDs follow row-major neighborhoods, each contributing a building,
spans 0/1/2 and an irregular assembly. Seed variation changes the geometry.
Each body retains the existing protected-foundation and material semantics.

Before emitting a Bend input, admission checks the fixed envelope, positive
dimensions, exact coordinate and spatial-split arithmetic, checked U32 box
volumes/world sums, owner IDs, tree counts, disjointness across all owners,
positive-area face connectivity and protected anchors. Source face endpoint
grids give conservative bounds on every clipping stage's rectangle count.
Checked bounds cover six vertices per rectangle and a conservative 64-byte slot
larger than the current transport/native vertex and index elements, per body
and in aggregate. These guards run before the unsafe tree/surface routines.
No Vulkan allocation is performed or claimed.

The admitted integer input becomes a retained Bend entry file that calls
`S.build`, `W.assemblies` and `W.from.bodies`. Existing allocator behavior and
parallelism are preserved; this adds no performance optimization. The worker
emits its actual trees, cached faces, cached vertices, connectivity result and
world state. The independent integer reference compares source occupancy and
materials, checks IDs/anchors/connectivity, sweeps surface boundary events to
compare exact exposure, and checks binary32 vertex positions and winding.
Reported cuboids, tree nodes, surface rectangles, area and vertices are measured
from that output, separately from authored boxes. Surface area is per owner;
contacts between separate owners remain drawable, while internal material
interfaces within an owner are hidden by the production mesher.

The fixed-preset totals are 21/81 initial anchored owners and
10,503,360/42,096,576 cells. Other scales have `1+5*q*q` initial owners and
source-cell totals measured for the requested seed. Density uses the declared
[0,128) vertical envelope; tight occupied bounds are reported separately.
The q=2..5 source range checks actual boxes, products, surfaces, IDs, native-size
bounds and monotonic clock arithmetic before unsafe work. Replay cases freeze
their complete camera, ray and target schedules. Carving, motion, picking and
native rendering retain evolving guards and separate runtime/reference checks.

## Evidence and reproduction

`manifest.json`, `inventory.json`, `validation.json` and `summary.json` use
`megascene-evidence/1`, canonical decimal strings for integer counts and bounds,
and exact binary32 hex strings for cell size and motion. Requested/effective
controls, numeric bounds, content identities, scope and explicit outcomes are
retained. Per-body production record hashes identify the actual emitted
partition and cached geometry; they are not the later canonical logical
checkpoints under `megascene-checkpoint/1`.

The bundle includes `inputs.json`, generated Bend/C, the actual executable,
its loaded libraries and loader, the generator/reference source, Bend dependency
sources, build provenance and logs. SHA-256 hashes and relative retrieval paths
are recorded before worker execution. Run the manifest's `worker_command` from
the bundle directory to replay the retained executable against its retained
libraries on a compatible Linux kernel/CPU. Loader overrides from the invoking
environment are removed during admission. `stdout.log` is complete worker
transport under `megascene-worker/1`; missing, malformed, duplicate-key or
truncated records cannot pass validation. JSON snapshots use atomic replacement.

This local bundle is not a durable campaign archive. For durable storage, retain
the entire directory outside disposable build storage. No campaign, timed
replay, rendering, GPU measurement, resource qualification, calibration,
responsiveness or capacity pass is produced. Those outcomes remain explicitly
unexecuted/inconclusive, even when initial admission passes. Build/process/check
failures retain available logs and are admission failures, not capacity limits.

## Verification

`make test` includes runner-level checks of both presets with both seeds,
independent recipe comparisons, exact inventory and seed variation, recoverable
artifact hashes, small dense-cell surface fixtures, actual vertex winding,
thread determinism at 1/6/12, rejected requests, corrupt/truncated worker data,
and synthetic schema/status fixtures. The existing proof and runtime/reference
suites remain required. Runtime geometry depends on `@unsafe` definitions and
is not described as formally proven.

For just the admission tests:

```sh
python3 -m unittest discover -s tests -p test_megascene.py -v
```
