import Base
import ./src/megascene_admission.bend as Admission
import ./src/color.bend as Color
import ./src/math.bend as R
import ./src/material.bend as Material
import ./src/resolution.bend as Resolution
import ./src/megascene_recipe.bend as Recipe
import ./src/megascene_scale.bend as Scale
import ./src/schedule_points.bend as Points
import ./src/schedule_binary.bend as Binary
import ./src/schedule_json.bend as Json
import ./src/megascene_operational.bend as Operational
import ./src/megascene_configuration.bend as Configuration

law operational_u32_limit:
  {Operational.counter("4294967295","count") == Done{4294967295} : Result<&2,&2,String,U32>}

law operational_u32_overflow:
  {Operational.counter("4294967296","count") ==
    Fail{"unsupported count: exceeds checked U32/native size envelope"} : Result<&2,&2,String,U32>}

law operational_negative_rejected:
  {Operational.counter("-1","count") ==
    Fail{"unsupported count: exceeds checked U32/native size envelope"} : Result<&2,&2,String,U32>}

law configuration_wrapped_seed_rejected:
  {Configuration.exact(Configuration.Decimal{45,True{}},45) == False{} : Bool}

law operational_u64_limit:
  {Scale.Integer.show(Operational.clock.limit()) == "18446744073709551615" : String}

law canonical_json_newline:
  {Json.quote("\n") == "\"\\n\"" : String}

law canonical_json_non_bmp:
  {Json.quote(SCon{Chr{128512},SNil{}}) == "\"\\ud83d\\ude00\"" : String}

law canonical_schedule_field_order:
  {Json.object([Json.field("phase_offset","null"),Json.field("phase","false")]) ==
    "{\"phase\":false,\"phase_offset\":null}" : String}

law checkpoint_coincident_order:
  for a: String
  for b: String
  {Points.sort([Points.Point{0,a},Points.Point{0,b}]) ==
    [Points.Point{0,a},Points.Point{0,b}] : List<&2,Points.Point>}

law runtime_signed_zero_word:
  {Binary.byte(2147483648) == [0,0,0,128] : List<&2,U32>}

law runtime_null_action_word:
  {Binary.byte(4294967295) == [255,255,255,255] : List<&2,U32>}

# Schedule policy lives in Bend. Python independently checks source geometry
# and evolving edit/motion references, then annotates the frozen plan.
# Preserve complete schedule bytes, binary64 operation order, binary32 rounding
# barriers, signed zero, and checkpoint/review ordering across every route.
# Native consumers read frozen frame, checkpoint and review tables. They cannot
# infer phases or capture frames from route names. Foreign libm arithmetic and
# unsafe world/geometry invariants require runtime/reference tests. They are not
# established by the proof kernel. scripts/megascene_schedule_parity.py compares
# complete schedules against the pre-migration hashes.

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
# - Native geometry timing separates mesh/cache updates from audit work.
#   Audit mesh checks, visibility, proxy checks, hashing and output use actual
#   contiguous monotonic intervals nested in the audit. Keep the aggregate
#   geometry marker and legacy timing ABI; never add parent/child durations.
#   These foreign timing contracts require runtime/reference checks.
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
# - The primary traversal freezes every startup, warm-up and measured camera
#   in binary32 before replay. Picking and edits remain disabled. Validation
#   checks every view, and timing retains named route checkpoints and return
#   geometry. Moving views cannot rebuild unchanged full meshes or shadow fit.
# - The user-approved issue #53 cavity-framing remedy uses traversal-v2 with
#   eye (256,70,210), look (256,12,272) at both cavity visits. Preserve the
#   exact traversal-v1 route and its failed readability review as evidence.
#   Route versions cannot share validation or be silently interchanged.
# - Issue #54 picking uses the same versioned camera route. Enable only the
#   declared wall/interior/cavity/assembly/sky holds; preserve strict <256 m
#   reach, target identity, explicit disabled samples and unchanged geometry.
#   Admit frozen targets with an independent reference before timing; guard
#   actual cell/metre/offset/distance operations before unsafe ray traversal.
#   Picking, native caches and these guards require runtime/reference evidence.
# - Required route captures occur in the separate validation process. Assess
#   each named feature's geometry and readability with a bound capture, shadow
#   fit and texel evidence. Missing review cannot pass visual quality; wrong
#   rendering and insufficient readability have different outcomes. These are
#   runtime/reference/human checks, never unsafe-dependent formal proofs.
# - Accepted #45 refinements: proxy thresholds retain render-pixel scaling.
#   Calibration-off controls may omit intermediate timed checkpoints only as
#   diagnostics with explicit limited equivalence evidence; they never qualify
#   benchmark passes or endpoints. Qualifying runs retain all required checks.
#   See docs/megascene-spec.md for the handoff and calibration protocol.
# - Issue #65 calibration uses 12 exact static/history × preset × thread
#   configurations at full 1080p. Each has six fresh controls in
#   off/on/on/off/off/on order, with separate complete mode validations.
#   Each applicable ordinary mean/p95/p99 and history accepted-edit p95 must
#   have sufficient populations and valid off denominators. Above 5% off
#   variation is inconclusive; otherwise every paired increase must be at
#   most 5%. Do not pool attempts, subtract cost or rerun without allowance.
#   These unsafe/native-dependent properties require runtime/reference tests;
#   Bend proof checks do not establish calibration or transient off equality.
# - Issue #68 implementation acceptance needs a separate complete validation,
#   timed workload and named visual review for every positive matrix row.
#   Insufficient calibration or responsiveness can leave performance unqualified
#   while completed functional evidence remains valid. A missing or failed
#   positive row keeps implementation acceptance incomplete. Retain failed runs
#   and charge all eligible earlier and new work to the shared declared allowance.
#   Unsafe carving and native Vulkan fidelity need runtime/reference evidence;
#   these are not formal Bend proof claims.
# - Fixed-preset initial admission now checks disjointness, positive-face
#   connectivity, anchors, arithmetic bounds and actual production inventory.
#   See docs/megascene-admission.md. These are runtime/reference checks only;
#   admission does not prove unsafe geometry or qualify a Vulkan attempt.

# Mixed-district scale admission (issue #66; runtime/reference scope):
# - A square scale q>=2 has q*q neighborhoods, each retaining its 320-cell
#   patch, five initial structure owners, cell size, vertical envelope and
#   row-major ownership. Supported q=2..5 is an operational range, not a
#   measured physical ceiling; unsupported requests retain rejection evidence.
# - Growth minimizes distance to twice q^2; area-midpoint refinement uses
#   interior integer q and lower ties. Adjacent q values stop discretely.
# - History uses the smallest stride >=5 coprime to q^2, and each group's
#   revisit index counts actual prior visits to its mapped neighborhood.
# - Freeze all case cameras, rays, targets and required actions before unsafe
#   replay. Reject unreachable or unsupported numeric operations; do not
#   shrink, skip or retarget. Evolving edit/pick/native checks remain necessary.
# - Scale properties that depend on unsafe/native code require retained
#   runtime and independent reference evidence, never a formal proof claim.
# - Issue #67 search orders six real Vulkan cases breadth first through the
#   supported discrete scales, then confirms observations within one exact
#   workload identity. Three agreeing process attempts establish ordinary
#   endpoints; explicit allocation failures permit only one diagnostic retry.
#   Calibration, independent seed, diagnostics and thread comparisons keep
#   separate scopes. Resource, monitoring, numeric and fragment-budget stops
#   are policy observations, never physical exhaustion. Chronological search
#   evidence and an explicit added allowance govern resume. Later review or
#   calibration reclassification appends evidence rather than replacing an
#   attempt. These are
#   runtime/reference rules, not formal claims about unsafe/native execution.

# - Static Vulkan development observations freeze the binary32 opening view
#   and 1/60 step, disable picking/edits, and preserve physics-before-render.
#   Full geometry retains proxy bookkeeping, fixed ground and 2048^2 shadows.
#   Archive actual runtime artifacts and inputs before invocation; preserve
#   frame-return intervals, missing evidence and abnormal completed prefixes.
#   See docs/megascene-static.md. Static correctness is separate from
#   calibration and performance qualification; missing evidence is not a pass.
# - Validate each static artifact/workload/schedule/profile/thread configuration
#   in a fresh complete replay before timing another fresh process. Reuse only
#   matching actual artifact and execution identities. Charge validation time.
# - Check actual ownership, tree summaries, material/anchor conservation,
#   connectivity, drawable coverage/winding, native caches and visibility.
#   Small independent dense references and large sparse checks have distinct
#   scopes. Retain required timed checkpoints within normal frame work.
# - Canonical occupancy/surfaces ignore equivalent partitions, never IDs,
#   revisions, owners, anchors, motion bits, budget, next ID or view/schedule.
#   Keep raw work inventories and useful field/body mismatch evidence.
#   See docs/megascene-validation.md; all these checks are runtime evidence.
# - Supervision samples host/device/process-attributed heaps every 100 ms,
#   stops on required monitoring failure or data older than one second, and
#   enforces independent reserves and the earliest applicable deadline.
# - Commit minimal reference records to bounded preallocated shared slots.
#   Never reuse a slot or discard committed evidence after worker termination.
#   Overflow, gaps, damaged required records or persistence failure invalidate
#   completion; preserve raw bytes and the usable prefix.
# - Vulkan allocation identities and exact ledger totals are distinct from
#   process residency and driver-estimated heap budgets. An exit signal alone
#   never establishes allocation exhaustion. Retain the known supervisor cause.
# - Campaign validation/control/attempt time shares one persisted allowance;
#   interruption/exhaustion requires an explicit addition, never a ticket reset.
#   These native/OS rules require runtime/reference tests, not formal claims.
#   See docs/megascene-supervision.md.
# - GPU timestamps belong to their submitted frame, including delayed results
#   and teardown collection. Retain raw ticks, period, valid bits and scope.
#   Use existing synchronization only; never add a query wait to frame work.
# - Resolve only available pairs with valid CPU bounds and unambiguous wrap.
#   Unsupported, disabled, not-ready, incomplete and failed collection are
#   distinct from measured zero. Missing required tails prevent completion.
#   CPU waits are not GPU execution or display latency. GPU availability never
#   establishes calibration, validation, supervision or benchmark qualification.
#   See docs/megascene-gpu.md; native timestamp rules use runtime/reference tests.

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

# - Issue #55 localized-v1 executes exactly one 20 cm terrain cut at measured
#   frame 0 after physics, then holds its frozen view for unchanged-world
#   observations. Its 16 removed concrete cells must agree with an independent
#   reference. A required rejection/no-op cannot satisfy schedule completion.
# - Preserve every action outcome in canonical checkpoint history, including
#   rejection and no-op. Atomic rejection preserves body geometry/cache data,
#   IDs/revisions, next ID, budget, materials, anchors and motion; only the
#   documented status/removal telemetry changes.
# - Guard actual carve predicates, counts, ID growth and native size bounds
#   before unsafe work. Validate local surfaces and unchanged full/proxy mesh
#   contents at runtime. These rules are never unsafe-dependent formal proofs.
# - Edit response runs from before the scripted operation through its rendered
#   frame return, including required checks/logging; CPU/GPU ordinary samples
#   exclude that frame. One accepted edit leaves percentile qualification
#   inconclusive; never add cuts or pool attempts to manufacture a pass.

# Megascene support-v1 runtime contract (issue #56; not a formal claim):
# - Cut A0/B0/A1/B1/A2/B2 at measured ordinals 0/6/12/18/24/30.
#   Each cut removes exactly 16 material-3 cells. A first cut leaves an
#   anchored 120-cell stump and an anchored span; a second leaves another
#   anchored stump and releases the span with inherited offset/velocity.
# - Actual distinct released body identities must move on every frame 31..42.
#   Persist motion bits and canonical checkpoints, and compare them with the
#   separately validated replay. Intended release times never establish motion.
# - Existing vertical gravity and y=0 stopping remain unchanged. Translation
#   preserves local occupancy/surfaces, IDs/revisions and full-mesh bytes/slots.
#   Native draw/shadow evidence and named beam-feature captures cover rendering.
# - Six edits remain percentile-inconclusive. Missing/rejected/no-op cuts or
#   absent motion evidence cannot qualify schedule completion. See
#   docs/megascene-support.md for independent reference/runtime evidence scope.

# Megascene history-v1 runtime contract (issue #57; not a formal claim):
# - Freeze 120 binary32 targets and the camera track before replay. Cut at
#   measured ordinals 12*k for k=0..119. Every cut must remove fresh editable
#   material in the evolving world; a rejected/no-op cut stops the worker.
# - Revisit prior terrain damage, release and then cut each moving beam, and
#   address the remaining anchored bridge stubs. Compare every intermediate
#   owner, component, material, surface, motion bit and lifetime ID with an
#   independent reference, including the twelve release-to-target windows.
# - Preserve every cut checkpoint, checkpoints after cuts 12/48/120, and the
#   far/completion views. Check actual mesh/proxy/shadow transitions and keep
#   ordinary, edit, moving, overview and settled-tail populations separate.
# - Numeric guards and native/cache behavior depend on unsafe/foreign code;
#   only runtime/reference and retained Vulkan evidence can establish them.
# - An unchanged checkpoint body may reuse its canonical geometry check only
#   after exact raw boxes, faces, vertices, bounds, revision and anchor match a
#   previously audited body. Re-read motion and view each frame; changing
#   geometry under the same revision must miss this validation cache.

# Megascene history/span controls (issue #61; runtime/reference evidence):
# - History-12 and history-48 require only their first 12/48 baseline cuts.
#   Preserve the full baseline binary32 camera track and all 3,600 measured
#   frames; omitted cuts are not required actions. Normal physics continues.
# - Support-1-span and support-2-span require only the first 2/4 support cuts.
#   Preserve the baseline overview and require exactly 1/2 distinct released
#   spans moving on every measured frame 31..42.
# - Keep variant schedule, state, work, motion/edit populations, checkpoints
#   and visual expectations separate. Variant completion never qualifies its
#   full baseline. Fewer than 100 edits cannot qualify edit percentiles.
# - Changed history/state is not a witness of identical final geometry.
#   Retention-specific attribution requires checked equal removed-cell sets
#   and final canonical geometry; otherwise it remains unavailable. These
#   unsafe/native-dependent rules are never formal proofs.

# Proxy diagnostics for issue #58 (runtime/reference rules, not formal laws):
# - Keep mixed-world and compact-reference routes separate from the primary
#   traversal/picking routes. Pair full and proxy profiles on identical frozen
#   world, physics, camera, warm-up and picking histories.
# - Use the centered 640-cell tile key and existing 80/100 render-pixel
#   hysteresis, including render-height scaling. Check actual eligible member
#   IDs, measured pixel margins, selected IDs, aim suppression and re-entry.
# - The compact right-lobe ray must hit actual body 4 within 256 m. A declared
#   miss that turns into a hit invalidates that picking hold; do not retarget.
# - Keep full meshes and full-mesh shadow draws resident in proxy runs. Count
#   main-pass full and proxy draws separately, with uploads, rebuilds, resident
#   vertex arena and Vulkan allocations in their actual scopes. Camera/aim
#   switches must not alter world or shadow geometry.
# - Required midpoint captures and separate validation are necessary for each
#   profile/case. Missing evidence or wrong hysteresis never passes. Fewer
#   draws do not establish equal appearance, less resident world state, or a
#   performance pass without applicable calibration.

# Megascene terrain pressure controls (issue #59; runtime/reference scope):
# - Spread uses 640-cell neighborhood spacing, a centered 960-cell small
#   envelope, and real two-cell-wide protected/removable terrain connectors.
#   Its terrain remains one positive-face-connected owner; empty gaps contribute
#   no occupied work. Ground coverage follows the changed envelope.
# - Material detail alternates materials 2 and 5 in four-cell local-X bands
#   only on removable terrain. Occupancy, ownership, protected cells and bounds
#   remain fixed. The localized brush target remains fixed; its camera aims
#   inside the even band to avoid a material-boundary ray.
# - Surface detail removes 64 disjoint two-by-two-by-two pits per neighborhood,
#   exactly 512 cells each. Terrain remains connected and anchored.
# - Each control has a separate frozen schedule and validation identity. Record
#   actual cells, material inventory, cuboids, exposed surfaces, ownership and
#   bounds. Nominal control labels and missing Vulkan evidence never pass.
# - These claims depend on unsafe Bend and native rendering; independent source
#   references, runtime inventory and complete Vulkan replay provide evidence,
#   not formal proofs.

# Megascene fill and initial-owner pressure controls (issue #60; runtime/reference scope):
# - Fill inserts an eight-cell concrete layer at Y=[8,16), shifts the original
#   terrain above Y=8 and all structures, local targets and views upward eight
#   cells, and leaves the protected foundation at Y=0. The cavity retains its
#   sixteen-cell depth and the declared Y=[0,128) envelope.
# - Body-rich splits each building at X=[72,80), discards that real gap and
#   retains two separately anchored connected owners. Initial owners become
#   1+6*N (25 for the small preset); other source roles stay in place.
# - Body-rich history action 6 targets the remaining back wall and uses its
#   declared eye. Every required removal is checked against actual occupancy
#   before replay; failed or missing evidence cannot complete the variant.
# - Each variant has separate schedule, admission, checkpoint and achieved
#   material/owner/surface/density/bounds evidence. Native/unsafe behavior is
#   covered by independent reference and complete Vulkan replay, not proof.

# Archived static/localized reproduction (issue #63; runtime/reference scope):
# - Retrieve the exact executable, native library, linked libraries, shaders,
#   generated source, generator, configuration and frozen schedule from the
#   recorded durable archive. Verify their SHA-256 bytes before execution.
# - A fresh validation and timed replay use those restored inputs and their
#   original thread/profile/frame settings. Compare initial inventory and
#   canonical state, action and geometry checkpoints with the source attempt.
# - A missing/tampered artifact, changed configuration, failed replay, damaged
#   stream or mismatch cannot pass reproduction. Keep incomplete attempts and
#   partial archive writes under distinct identities without overwriting bytes.
# - Actual host graphics dependencies and elapsed time are recorded separately;
#   reproduction does not prove cross-platform equality or performance gates.
#   Native/unsafe behavior remains runtime/reference evidence, not formal proof.

# Approved supplementary validation views must preserve world/frame, primary
# cameras, rays, action times, caches, proxy hysteresis and full-mesh shadows.
# These native/unsafe invariants require runtime/reference tests; they are not
# formally proven by this file. Supplementary work is excluded from timing.

# Bend district-source migration runtime contract:
# - Preserve exact owner roles, neighborhoods and ordered integer cuboids for
#   q=2..5, seeds 45/46 and every accepted terrain control. Freeze and check
#   those actual source records before unsafe construction or timed replay.
# - Growth/refinement retain exact squared-area choices and lower ties.
#   History retains coprime visitation and actual earlier-visit counts.
# - Keep independent Python occupancy, picking, edit and motion references.
#   Unsafe geometry and foreign rendering remain runtime/reference evidence.
# - Retain the Bend generator/policy and their adapter with archived inputs.

law district_rejected:
  for q: U32
  for seed: U32
  for control: Recipe.Control
  {Recipe.district.valid(False{},q,seed,control) == None{} : Maybe<&2,Recipe.District>}
law district_preserved:
  for q: U32
  for seed: U32
  for control: Recipe.Control
  {Recipe.district.valid(True{},q,seed,control) == Some{Recipe.District{q,seed,control}} : Maybe<&2,Recipe.District>}
law scale_half_double:
  for a: Scale.Integer
  {Scale.Integer.half(Scale.Integer.double(a)) == a : Scale.Integer}
law scale_sqrt_fuel:
  for target: Scale.Integer
  for lo: Scale.Integer
  for hi: Scale.Integer
  {Scale.sqrt.go(0n,target,lo,hi) == lo : Scale.Integer}
law history_no_prior_visits:
  for count: Scale.Integer
  for stride: Scale.Integer
  for offset: Scale.Integer
  for neighborhood: Scale.Integer
  for index: U32
  {Scale.history_visit.prior(0n,count,stride,offset,neighborhood,index) == 0 : U32}

law admission_add_limit:
  {Admission.checked.add(4294967295,0,"count") == Done{4294967295} : Result<&2,&2,String,U32>}
law admission_add_overflow:
  {Admission.checked.add(4294967295,1,"count") ==
    Fail{"count: unsigned integer exceeds supported range"} : Result<&2,&2,String,U32>}
law admission_mul_limit:
  {Admission.checked.mul(4294967295,1,"count") == Done{4294967295} : Result<&2,&2,String,U32>}
law admission_mul_overflow:
  {Admission.checked.mul(2147483648,2,"count") ==
    Fail{"count: unsigned integer exceeds supported range"} : Result<&2,&2,String,U32>}
law admission_mul_zero:
  for value: U32
  {Admission.checked.mul(0,value,"count") == Done{0} : Result<&2,&2,String,U32>}
law scale_midpoint_lower_tie:
  {Scale.midpoint_refinement(Scale.Integer.from_u32(4n,2),Scale.Integer.from_u32(4n,9)) ==
    Some{Scale.Integer.from_u32(4n,6)} : Maybe<&2,Scale.Integer>}

# Performance v2 is a runtime contract, never a formal proof of native code.
# - Keep historical schedules and acceptance #68 unchanged.
# - Freeze 120 warmup and 21600 measured frames for static/history small45/6/full/1080p.
# - Bound GPU queries to 21721 pairs and shared reference records to 32768 slots.
# - Admit every action and compare disjoint populations with evolving motion.
# - Require ten summed ordinary seconds in each calibration control.
# - Keep scripted edit-to-frame-return latency distinct from display latency.
# - Bound full history validation to 480 seconds and timed workers to 300.
# - Preserve every failed prefix and enforce the earlier campaign deadline.
