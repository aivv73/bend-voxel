# Localized cut and atomic rejection

Issue #55 adds `--case localized` to the separate Megascene runner. It uses the
accepted `localized-v1` schedule: startup and 120 warm-up frames at the opening
view, one 20 cm cut at measured frame 0, then 3,599 unchanged-world observations.
The complete schedule, target bits, pre-edit visibility ray, required outcome,
review views and checkpoints are archived before either process starts.

```sh
python3 scripts/megascene.py --case localized --preset small --threads 6 \
  --archive "$HOME/megascene-localized" \
  --output build/megascene/localized/first
```

A new output directory is required. This launches a complete validation replay
with captures, followed by a fresh timed replay under the existing resource and
campaign supervisor. Primary output is 1920 × 1080, full meshes, baseline daylight
and 2048 × 2048 world-fitted shadows. `--validation-only`, `--validated` and
`--runtime-from` retain their existing applicability and artifact checks. Each
thread configuration needs its own validation. Shortened localized schedules,
changed targets, proxy profiles and automatic retargeting are unsupported.

## Frozen operation and exact state

Physics runs first using binary32 step `0x3c888889`. At absolute frame 121
(measured ordinal 0), the direct scripted operation cuts local cell
`(160,24,160)` in neighborhood 0. It then installs the frozen eye
`(160,44,170)` looking at that target and renders. View/picking input cannot
change the operation; interactive picking stays disabled. An independent
preflight checks that the pre-edit center ray reaches terrain material 2 within
the strict 256 m reach.

The independent reference enumerates the small brush neighborhood and subtracts
unit cells from sparse source boxes. It expects exactly **16 concrete cells**,
no protected removal and one connected anchored terrain body. Small-preset
terrain ID 1 becomes ID 22, revision 0, and next ID becomes 23. All 20 other
owners retain their identities, revisions, geometry and caches. Large-preset
identities follow the same allocation rule starting at next ID 82.

Canonical `megascene-checkpoint/1` state now includes accumulated action outcomes:
action and frame identities, exact target bits, acceptance, outcome and removed
cells. Required checkpoints include initialization, opening, warm-up end, the
action frame and completion. Validation also checks every intermediate frame.
The independent sparse expected state checks ownership, material occupancy,
anchors, motion and exposed surfaces. Actual partition/work inventories remain
separate and must match the separately validated timed execution.

Native checks compare fresh Bend transport, full mesh vertices/materials,
visibility, draw ranges and retained proxy contents. On the accepted cut, exactly
one full mesh is rebuilt and shadows refresh once. Unaffected native mesh slots
and proxy content hashes remain unchanged. Subsequent frames do not rebuild
geometry or shadows. These checks run in actual Vulkan replays.

## Rejection, no-op and numeric boundaries

The production world edit remains atomic on fragment-budget rejection. Runtime
fixtures compare complete before/after bodies and all relevant world fields;
only status/removal telemetry may differ. The fixtures include signed coordinates,
protected material, partial faces, repeated damage, a moved-body split, complete
body removal, an air no-op and a rejected split with nonzero motion. A dense
six-neighbor and exposed-unit-face reference checks material and ownership
independently of tree splitting and local face patching.

Rejected and no-op actions are recorded and preserved in canonical history.
They cannot count as the required accepted cut or advance successful completion.
Synthetic report fixtures reject missing, duplicate, rejected or no-op actions,
incorrect edit boundaries and changed update order. They are explicitly separate
from actual Vulkan observations. The negative world/recorder fixtures are native
runtime tests; they are not additional cuts pooled into the localized workload.

Before unsafe carving/classification/surface generation, the runtime guard checks
actual world counts, current IDs and conservative growth, finite motion,
coordinate operations, every potentially visited near/far carve predicate,
subdivision, vertex/count and native-byte bounds. Its intentionally narrow
operational envelope uses integral bounds within ±1,024 cells and a half-cell
local brush grid whose metre/offset conversion error is at most 0.00001 cells.
The frozen targets for both presets and seeds are admitted explicitly. This is
not a universal admission rule for arbitrary coordinates or later histories.

All geometry, native cache and numerical claims are runtime/reference evidence.
They are **not formal proofs** of definitions depending on `@unsafe` or foreign
code. Safe laws remain checked by `PROOF.bend` and its verdict kernel.

## Intervals and interpretation

The edit response begins immediately before the scripted operation and ends at
the frame-effect return containing its result. It includes the runtime guard,
carving, connectivity, local surfaces, commit, view, checkpoint, transport and
renderer work. Begin/end markers record carve (including its guard), connectivity,
surfaces and commit separately. Transport contains checkpoint work; renderer
contains native geometry/upload/wait/submit stages. These nested intervals must
not be summed as independent frame work.

CPU and GPU ordinary populations exclude the edit frame. Reports retain warm-up,
ordinary, edit-frame, accepted-edit-response and combined measured CPU populations,
plus exact action and stage records. Minimal action/response evidence is committed
to the supervisor's preallocated reference recorder as well as the detailed stream.

There is one accepted edit per complete attempt. Its observed latency and maximum
are reportable; its edit-percentile gate remains **inconclusive** because the
accepted minimum is 100. Attempts are neither pooled nor lengthened. Instrumentation
calibration remains unavailable, so correctness and completion do not imply an
interactive benchmark pass or a qualified capacity endpoint.

Captures at initialization, the cut and completion belong to the separate
validation process. Named feature review distinguishes rendering correctness
from readability. Retained evidence is documented in
[the issue #55 validation record](validation/megascene-localized/README.md).
The broader matrix and material-detail diagnostic remain tracked by #68 and #59.

```sh
python3 -m unittest discover -s tests -p test_megascene_localized.py -v
make test
bend PROOF.bend
bend PROOF.bend --verdict
```
