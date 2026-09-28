import Base
import ./src/color.bend as Color
import ./src/math.bend as R
import ./src/material.bend as Material
import ./src/resolution.bend as Resolution

# The Vulkan bridge reads ten material colors, then surfaces and overlays.
law palette_length:
  {List.length(&2, R.Vec, Color.palette()) == 19n : Nat}

# Project rules from the Bend 2.0.32 audit:
# - Fork independent, similarly sized jobs; cap fork depth and keep small work
#   sequential. Benchmark initialization, six real cuts, and Vulkan workloads
#   in alternating orders. Reject regressions; GPU speedups need GPU evidence.
# - Keep event folds, flood frontiers, ID allocation, and successive face
#   subtraction ordered. Parallel readers must not change tie/order behavior.
# - Preserve half-open, disjoint integer cuboids and face side/material order.
#   Coordinates stay within +/-2^23 cells; aggregate counts must fit U32.
# - One cell is 0.1 m. Carving tests cell centers with radius squared 4.00001;
#   foundation material is protected. Splits retain offset and velocity.
# - A rejected edit preserves geometry, ownership, next ID, and motion. Only
#   status/removal telemetry changes. IDs cannot alias different live geometry.
# - Cache faces/vertices by geometry identity; translation/camera/aim changes
#   must not rebuild body meshes. Each exposed rectangle emits six vertices.
# - Use + only for actual reuse, shrinking arguments first, and Nat fuel for
#   bounded loops. Do not add @unsafe merely to make a proof type-check.
# - Foreign IO and existing @unsafe geometry algorithms are outside these
#   formal claims. make test covers dense carving, connectivity, rollback,
#   mesh winding, cache identity, and local/full surface equivalence at runtime.
# - This file states the accepted contract. Change claims only when the user
#   authorizes a contract change; implement proofs in PROOF.bend.

# Future Megascene qualification rules (runtime evidence, not formal claims):
# - Require independent small references, a separate validation replay per
#   configuration, and matching state/geometry checkpoints in timed attempts.
# - Preserve exact workload/state across 1, 6, and 12 threads; reject silent
#   clamping, unsupported numeric operations, overflow, and truncated evidence.
# - Primary fidelity uses full body geometry, picking strictly below 256 m,
#   declared-world visual ground coverage, and world-fitted 2048^2 shadows.
#   Proxy LOD is a separate diagnostic; quality limits are distinct from
#   incorrect state/rendering. These future gates are not yet implemented.
# - Canonical decision: https://github.com/aivv73/bend-voxel/issues/44
#   Runtime/reference checks must cover all unsafe/native-dependent properties.
# - Accepted #45 refinements: proxy thresholds retain render-pixel scaling.
#   Calibration-off controls may omit intermediate timed checkpoints only as
#   diagnostics with explicit limited equivalence evidence; they never qualify
#   benchmark passes or endpoints. Qualifying runs retain all required checks.
#   See docs/megascene-spec.md for the handoff and calibration protocol.
# - Fixed-preset initial admission now checks disjointness, positive-face
#   connectivity, anchors, arithmetic bounds and actual production inventory.
#   See docs/megascene-admission.md. These are runtime/reference checks only;
#   admission does not prove unsafe geometry or qualify a Vulkan attempt.

# - Static Vulkan development observations freeze the binary32 opening view
#   and 1/60 step, disable picking/edits, and preserve physics-before-render.
#   Full geometry retains proxy bookkeeping, fixed ground and 2048^2 shadows.
#   Archive actual runtime artifacts and inputs before invocation; preserve
#   frame-return intervals, missing evidence and abnormal completed prefixes.
#   See docs/megascene-static.md. Full replay/checkpoint, resource and calibration
#   qualification remain future work: static observations cannot pass them.

# Stable material IDs are shared by the native bridge and generated assets.
law material_ids:
  {[Material.foundation(),Material.concrete(),Material.frame(),
    Material.machinery(),Material.plaster()] == [1,2,3,4,5] : List<&2,U32>}
law foundation_anchor:
  {Material.is_anchor(Material.foundation()) == True{} : Bool}
law editable_materials:
  {(Material.is_anchor(Material.concrete()) || Material.is_anchor(Material.frame()) ||
    Material.is_anchor(Material.machinery()) || Material.is_anchor(Material.plaster())) == False{} : Bool}

# Joining independent ordered batches must neither lose nor reorder elements.
law append_empty:
  for -A: Data
  for xs: List<&2,A>
  {List.append(&2,A,xs,Nil{}) == xs : List<&2,A>}
law append_associative:
  for -A: Data
  for xs: List<&2,A>
  for ys: List<&2,A>
  for zs: List<&2,A>
  {List.append(&2,A,List.append(&2,A,xs,ys),zs) ==
    List.append(&2,A,xs,List.append(&2,A,ys,zs)) : List<&2,A>}
law append_length:
  for -A: Data
  for xs: List<&2,A>
  for ys: List<&2,A>
  {List.length(&2,A,List.append(&2,A,xs,ys)) ==
    Nat.add(List.length(&2,A,xs),List.length(&2,A,ys)) : Nat}

# Selecting an unchanged scalar must preserve it for either branch.
law word_same:
  for c: Bool
  for value: U32
  {R.word(c,value,value) == value : U32}
law pick_same:
  for c: Bool
  for value: F32
  {R.pick(c,value,value) == value : F32}

# A gamut search with exhausted fuel retains its known lower bound.
law gamut_fuel:
  for lightness: F32
  for hue: F32
  for lo: F32
  for hi: F32
  {Color.fit(0n,lightness,hue,lo,hi) == lo : F32}

# Resolution rejection is unconditional; accepted dimensions are unchanged.
law resolution_rejected:
  for width: U32
  for height: U32
  {Resolution.pair.valid(False{},width,height) == None{} : Maybe<&2,Resolution.Size>}
law resolution_preserved:
  for width: U32
  for height: U32
  {Resolution.pair.valid(True{},width,height) == Some{Resolution.Size{width,height}} : Maybe<&2,Resolution.Size>}
law resolution_default:
  {Resolution.parse("640x360") == Some{Resolution.default()} : Maybe<&2,Resolution.Size>}
law resolution_pixel_limit:
  {Resolution.parse("3840x2161") == None{} : Maybe<&2,Resolution.Size>}
law resolution_malformed:
  {Resolution.parse("1920x1080x1") == None{} : Maybe<&2,Resolution.Size>}

# Material slots are anchored/detached pairs in the native ABI order.
law palette_material_order:
  {List.take(&2,R.Vec,Color.palette(),10n) ==
    [Color.surface(Color.foundation(),False{}),Color.surface(Color.foundation(),True{}),
     Color.surface(Color.concrete(),False{}),Color.surface(Color.concrete(),True{}),
     Color.surface(Color.frame(),False{}),Color.surface(Color.frame(),True{}),
     Color.surface(Color.machinery(),False{}),Color.surface(Color.machinery(),True{}),
     Color.surface(Color.plaster(),False{}),Color.surface(Color.plaster(),True{})] : List<&2,R.Vec>}
