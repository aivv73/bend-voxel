# Megascene workload recipe

**Accepted annex to [the implementation handoff](megascene-spec.md), 2026-09-28.**
The final handoff decision includes these exact shapes, targets, camera poses
and diagnostic controls as well as the preset sizes and action cadences.

This specifies future implementation, not an achieved benchmark. All
bounds are half-open integer cell coordinates at 10 cells/metre. Box notation
lists X range / Y range / Z range, excluding each high endpoint.

Add origin `(320*ix-160*q, 0, 320*iz-160*q)` to every local box and target.
The baseline world is centered on X/Z=[-160*q,160*q). This places four eligible
assemblies in the same existing proxy tile. Fixed presets use q=2 or 4,
N=q*q and seed s=45 or 46. Neighborhood index is `n=ix+q*iz`, with geometric
variation `v=(3*ix+5*iz+s-45) mod 4`.

Initial owner order is terrain first, then each row-major neighborhood's
building, spans 0/1/2 and irregular assembly. Allocate initial IDs sequentially
from 1 in this order through the existing allocator; retain its component/ID
rules during edits and freeze actual expected IDs in validation. Material IDs
are 1 foundation (protected), 2 concrete, 3 frame, 4 machinery and 5 plaster.

Source boxes must be disjoint. Face contact between different owners does not
merge ownership. Every initial owner must be six-connected and anchored;
generation checks establish this rather than trusting the recipe. All terrain
boxes across neighborhoods share one owner.

## Terrain (one continuous owner)

Per neighborhood:
- [0,320)/[0,1)/[0,320), material 1.
- [0,320)/[1,8)/[0,320), material 2.
- [0,224)/[8,24)/[0,320), material 2.
- [288,320)/[8,24)/[0,320), material 2.
- [224,288)/[8,24)/[0,240), material 2.
- [224,288)/[8,24)/[304,320), material 2.
- Cavity bridge [224,288)/[22,24)/[271,273), material 2. It touches both cavity sidewalls and spans the air above the y=8 cavity floor. The open cavity envelope is [224,288)/[8,24)/[240,304), except the bridge.
- L-shaped raised relief: [160,208)/[24,32+2v)/[16,64) and [160,184)/[24,32+2v)/[64,96), material 2.
- Lower relief terrace: [184,208)/[24,28)/[64,96), material 2.

The y<8 layers connect all neighborhoods through positive-area faces. The foundation touches the removable base. The cavity is a real empty volume, with an actual thin traversing bridge, not a painted hole. General terrain surface away from relief/cavity is y=24. The localized-edit patch around (160,24,160) is clear of structures and relief.

## Building owner

Let H=80+2v. Footprint X/Z=[16,136).
- Four material 1 footings: X in {[16,24),[128,136)}, Z in the same set, Y=[24,26).
- Floor [16,136)/[26,28)/[16,136), material 5.
- Left wall [16,20)/[28,H)/[20,132), material 5.
- Back wall [16,136)/[28,H)/[132,136), material 5.
- Front wall: [16,64)/[28,H)/[16,20); [88,136)/[28,H)/[16,20); door header [64,88)/[60,H)/[16,20), all material 5. Door void is X=[64,88),Y=[28,60),Z=[16,20).
- Right wall: [132,136)/[28,H)/[20,56); [132,136)/[28,H)/[80,132); [132,136)/[28,44)/[56,80); [132,136)/[64,H)/[56,80), material 5. Window void is X=[132,136),Y=[44,64),Z=[56,80).
- Interior partition: [76,80)/[28,H)/[48,72); [76,80)/[28,H)/[88,112); header [76,80)/[60,H)/[72,88), material 2. This has a real interior doorway.
- Roof, material 3, Y=[H,H+3): X=[16,48),Z=[16,136); X=[72,136),Z=[16,136); X=[48,72),Z=[16,96); X=[48,72),Z=[120,136). The skylight void is X=[48,72),Z=[96,120).

All walls and the partition touch the common floor/roof. Four footings anchor the owner. Other initial owners only contact the building/terrain at non-overlapping boundaries.

## Span owner j=0,1,2

Let Zj=176+24*j; Bj=72+v.
- Two footings, material 1: [22,28)/[24,26)/[Zj+1,Zj+7) and [124,130)/[24,26)/[Zj+1,Zj+7).
- Two thin supports, material 3: [24,26)/[26,Bj)/[Zj+3,Zj+5) and [126,128)/[26,Bj)/[Zj+3,Zj+5).
- Beam, material 2: [16,136)/[Bj,Bj+4)/[Zj,Zj+8).

Support edit centers in cells: A_j=(25,40,Zj+4), B_j=(127,40,Zj+4). Use the existing fixed 20 cm sphere semantics (squared radius 4.00001 cell^2; do not replace with an independently rounded radius policy). A cut removes four full support layers [38,42) in a 2 x 2 column. Cutting A alone leaves the beam anchored through B. Cutting B afterwards detaches the beam and upper supports; its local lower bound is42 cells. Six support-family cuts are A0,B0,A1,B1,A2,B2 at measured frames 0, 6, 12, 18, 24, 30 in neighborhood0. Physics runs before the frame's cut, so releases are6,18,30 and first motion is7,19,31. Require >=3 moving fragments on EACH measured frames 31..42, not merely an observed max.

## Compact irregular assembly owner

Let T=58+(v%2), R=302+(v%2).
- Footing [280,288)/[24,26)/[176,184), material 1.
- Stem [280,288)/[26,42)/[176,184), material 4.
- Lower left lobe [272,288)/[42,50)/[168,184), material 4.
- Upper connecting lobe [280,296)/[50,T)/[176,192), material 3.
- Lower right lobe [288,R)/[34,50)/[184,199), material 4.

The right lobe joins the underside of the upper lobe through X=[288,296),
Z=[184,192), Y=50. The upper and lower left lobes share X=[280,288),
Z=[176,184), Y=50. Bounds are at most 31 x 35 x 31 cells, with anchors and
zero initial translation. The native key is
`floor((body_center_cells+320)/640)` in X/Z, centered on multiples of 640 cells.

All four assemblies of the 64 m world lie in tile (0,0). At 128 m, per-axis
memberships have counts 1/2/1 in tiles -1/0/1, so only the central four-member
group is eligible; the other 12 assemblies retain full geometry. Eligibility
does not establish actual proxy selection. Validate projected size, hysteresis
and the complete camera/aim path separately.

## Localized edit and 120-cut history

Localized edit is precisely one cut at local (160,24,160), neighborhood0, measured frame 0. It removes the top of a large connected terrain owner, away from protected material, buildings, relief and the cavity.

For history, k=0..119, measured frame=12*k. Let b=floor(k/10), a=k%10, n=(5*b+s-45)%N, r=floor(b/N). With N=4, each neighborhood is visited three times and r=0,1,2 selects distinct spans; with N=16, twelve distributed neighborhoods are visited once and r=0. Let j=r, Zj=176+24j, Bj=72+v for the selected neighborhood. Local target table:

| a | target in cells | intended action |
|---|---|---|
|0|(160+12r,24,160+8r)|terrain shallow cut|
|1|(18,48,48+12r)|building exterior wall|
|2|(25,40,Zj+4)|first support path of span j|
|3|(163+12r,24,160+8r)|overlaps a0's old damage but extends 3 cells into fresh terrain|
|4|(127,40,Zj+4)|last support path; detach span j|
|5|(76,Bj+2+10*offset12,Zj+4)|cut the moving beam after exactly 12 fixed physics steps since release|
|6|(78,48,54+3r)|interior partition, away from its doorway|
|7|(284+3r,T,180+3r)|top lobe of irregular assembly|
|8|(Lr,23,272), L=[236,230,226]|first cavity-bridge cut, or subsequent left-stub damage|
|9|(Rr,23,272), R=[276,282,286]|second cavity-bridge cut, or subsequent right-stub damage|

All integer local targets are converted to world metres by dividing by 10 after adding the neighborhood origin. For a5, resolve the WORLD METRE target directly: y=(Bj+2)*0.1+offset12 using declared F32 operations, where offset12 is obtained from the existing body-step recurrence from offset 0, speed 0 for 12 steps using dt bits 0x3c888889. Freeze the resulting F32 bits in the resolved schedule; do not recalculate from wall time or chase the body's live observed position. The intended oracle independently verifies that the frozen point hits that moved beam. The explanatory cell expression in the table must not introduce an extra cell/metre round trip.

At r0, bridge cuts sever a central segment. Later r1 and r2 cuts address remaining anchored end stubs, not vanished centers or landed bodies. Every target must remove actual unprotected cells; rejection/no-op cannot advance history. Actions 0/3 are genuine spatially overlapping old-damage revisits. Actions 6 at successive r also revisit/extend partition damage. Checkpoints after accepted edits 12/48/120 occur at measured frames 132/564/1428. All remaining measured frames are unchanged-world observations except normal motion/floor stopping; do not treat settled frames as moving-window samples.

## Exact camera, picking and review schedule

Poses in this table use local cell-space eye/look coordinates. Add the selected
neighborhood origin before conversion to metres. `far` is already in world
metres, with `L` equal to the actual horizontal envelope side in metres (baseline `32*q`). Preserve the current camera basis, focal length,
0.05 m near plane and infinite-far projection. Resolve yaw with `atan2(dx,dz)`
and pitch with `atan2(dy,hypot(dx,dz))`, then freeze the actual binary32 poses
for every frame. Reject a degenerate eye/look vector; do not silently substitute
a direction. Resolved binary32 schedules are retained artifacts, not recomputed
through a possibly different math library during comparison runs.

| Pose | Eye | Look target | Named feature / picking expectation |
| --- | --- | --- | --- |
| `opening` | (150,120,310) | (76,48,76) | Mixed district, building/span silhouettes and their major shadows. |
| `wall` | (8,48,60) | (16,48,60) | Exterior plaster wall; center ray hits material 5 at the left exterior face. |
| `interior` | (116,44,80) | (20,44,80) | Clear interior doorway; center ray passes through it and hits the left wall's interior face. |
| `cavity` | (256,44,244) | (256,8,256) | Cavity depth and open air; center ray hits removable floor material 2. |
| `assembly` | (284,90,160) | (284,T,180) | Irregular lobes and material distinctions; center ray hits the upper lobe. |
| `sky` | (160,120,160) | (160,220,260) | Known miss above all scene geometry. |
| `far` | (0,0.75*L,1.25*L) m | (0,2.4,0) m | Whole occupied district extent and major structure/shadow relationships. No required picking hit. |

The table records the original `traversal-v1` route. Issue #53's 1080p
captures showed its cavity bridge above the image and insufficient cavity
readability. The user accepted a camera-framing remedy. `traversal-v2`
substitutes eye `(256,70,210)` and look target `(256,12,272)` for `cavity`
at both neighborhood visits. All other poses, phase lengths, interpolation,
startup, warm-up, picking and edit rules remain as stated here. Resolve and
freeze new binary32 camera bits under the distinct `traversal-v2` schedule ID;
retain `traversal-v1` and its failing visual review as separate evidence.

The traversal and picking cases share the same 12-phase route, each phase
lasting 300 measured frames:

`opening(0), wall(0), interior(0), cavity(0), assembly(0), far,
opening(N-1), cavity(N-1), sky(0), opening(0), opening(0), opening(0)`.

Here `(0)` and `(N-1)` select the first and last row-major neighborhoods.
For each phase, hold its pose for offsets 0..119. At offsets 120..299,
interpolate the eye and look point to the next pose using
`t = (offset - 119) / 180`; the final phase interpolates to itself. Resolve
these expressions before timing and freeze each pose. Camera travel is free
flight in a fully resident world, not streaming or a collision test.

In the picking case only, enable the center ray during the held portions of
`wall`, `interior`, both `cavity` visits, `assembly` and `sky`. The first five
hold types require the listed hits; `sky` requires misses. Picking is disabled
during interpolation, opening and far holds, with that status recorded. This
avoids turning increasing far-view distance into an unreachable required hit.
The traversal control keeps picking disabled throughout. Both cases have
identical complete camera histories.

Startup and all 120 warm-up frames use `opening(0)` with no edits/picking.
The static case keeps that pose. The localized case switches at measured frame
0 to eye (160,44,170), look (160,24,160), in neighborhood 0, and holds it.
The support case uses eye (160,180,300), look (76,55,204), in neighborhood 0,
throughout measured execution to show all three spans and the moving window.

For history, switch to the following target view at each scheduled edit and
hold it until the next edit. Coordinates are local cells unless stated otherwise;
the target is the corresponding frozen edit target, never a live retarget.

| History action within group | Eye / look |
| --- | --- |
| 0, 3: terrain | Eye = target + (0,20,10); look = target. |
| 1: exterior wall | Eye = (8,48,target.z); look = target. |
| 2, 4: support | Eye = (target.x,40,Zj+16); look = target. |
| 5: moved beam | Eye = frozen world-metre target + (0,2,1.2) m; look = that target. |
| 6: partition | Eye = (100,48,target.z); look = target. |
| 7: assembly | Eye = (target.x,T+32,target.z-20); look = target. |
| 8, 9: cavity bridge | Eye = (target.x,44,256); look = target. |

Hold the last history action view through frame 1439. Interpolate it to `far`
over frames 1440..1559 with `t=(frame-1439)/120`, then hold `far` to completion.
These are direct scripted cuts, as in the existing benchmark, not assertions
that a mouse click would place the brush at the identical inset coordinate.
Resolve a separate pre-edit ray/visibility check from each declared edit view
and verify that its intended removable owner is reachable within 256 m. An
after-edit hole is not a reason to retarget the already scheduled operation.

Retain validation captures at initialization, route phase offsets 60 (frames
60,360,...,3360), every edit, support frames 31 and 42, history checkpoints
132/564/1428, history overview 1560, and completion. Captures are outside timed
attempts; the corresponding view/state schedule remains identical. Review the
listed feature per view, cuts and new exposed surfaces at edit views, three
distinct detached spans at support captures, and unchanged geometry on return.
For each support span, name the beam top-center feature at local
`(76,Bj+4,Zj+4)` plus its declared motion offset. Require its correct body to be
visible at frames 31 and 42; freeze the actual expected pose from validation.
Mark visibility/readability per named feature rather than accepting a generic
"looks good" result. Fine shadow-detail loss may be recorded as allowed; missing
geometry or unreadable required major features cannot pass.

## Rendering and numeric defaults

Use primary daylight, the material palette and lighting/filtering
configuration at baseline `8c3ffad`, full body geometry, and world-fitted
2048 x 2048 shadows. Record hashes and effective constants; do not auto-tune them
with scale. The full profile forces every visible body to use its full mesh;
retain the baseline eligibility/proxy-cache bookkeeping and report its actual
work/storage. Do not silently add a cache-elimination optimization to this
fidelity switch. The proxy diagnostic instead enables the existing selection
rules, keeping full body meshes and full-mesh shadow draws resident.

The visual y=0 ground is fixed per case to the horizontal generation
envelope plus an 80-cell (8 m) border on each side. Fit shadows to occupied
geometry including body offsets, not to the visual-ground padding. Preserve the
unbounded y=0 picking/floor model; this does not introduce terrain collision.

Request immediate presentation, falling back to mailbox as in the existing
stress runner. If neither is available, record unsupported presentation and do
not substitute FIFO silently. Record the actual mode and keep it fixed across
comparisons; a changed mode is a separate configuration. Primary runs use
1920 x 1080; 640 x 360 remains a separately recorded diagnostic.

The default detached-fragment budget is 2,048. It is separate from
initial owners and resource limits, never silently raised. The declared vertical
generation envelope is [0,128) cells; tight occupied bounds are measured separately.
Recipe cells and source-owner counts must match exactly. Cuboid/surface counts
come from actual production geometry, with source-box counts recorded separately.

Before a candidate runs, substantiate its operational numeric envelope with
checked integer reference arithmetic and tests for the actual operations and
frozen targets. Cover coordinate conversions, distance/carve predicates, volume
and surface sums, native vertex/index/allocation sizes, IDs, counters and clocks.
In particular, exactly representable endpoints within +/-2^23 do not prove
all intermediate products or cell/metre round trips valid. Check each evolving
quantity before an unsafe operation, and reject unsupported requests. Testing
the fixed presets does not admit all larger coordinates automatically.

## Proxy diagnostic views and compact reference fixture

The handoff preserves the renderer's actual render-pixel metric and centered tile origin.
The four eligible assemblies in the small world share tile (0,0); in the large
world only the central four form a qualifying group. Outer groups have fewer
than four members. Record actual membership and selected bodies, not just a
nominal tile count.

For the paired full/proxy **mixed-world** diagnostic, start with the same opening
warm-up, then hold a view 1,000 m along +Z from the central group's exact bounds
center, looking at that center, for measured frames 0..1199. Move to a 100 m
offset for frames 1200..2399, then return to 1,000 m for 2400..3599. These three
poses are frozen before timing. This separate diagnostic route replaces neither
the primary traversal nor its required views. At the far pose, require actual
proxy entry in the diagnostic profile; at the near pose require full geometry.
The paired full profile never substitutes proxies. Picking, when enabled in the
paired picking case, uses the top-center ray only if an independent preflight
confirms the declared miss; a failed miss expectation invalidates the schedule,
not permission to find another ray. It cannot require a hit beyond 256 m.

The mixed-world group is too wide to exercise aimed-at suppression while it is
selected at 1080p and within picking reach. Add a separate compact **reference
fixture**, not a replacement Megascene: four copies of the irregular-assembly
recipe with variation `v = ix + 2*iz`, for `ix,iz` in {0,1}, translated by
(-272+40*ix,0,-168+40*iz) cells. Its four disjoint anchored bodies occupy one
tile, span at most 71 x 35 x 71 cells, and provide nearby reachable proxy members.

Let C and r be that fixture's exact union-bounds center and bounding-sphere
radius in metres. Resolve the three views looking at C from C+(0,0,D), where
`D = r + 800*(render_height/360)*r/P`, for P=105,75,90. Freeze binary32 views
and validate actual metric margins against 80/100. Use nine 120-frame holds:
105,75,90,105,90,75,75,75,105, then remain at 105 until frame 3599. Warm-up at
105 establishes full geometry. With no aim, the expected selections are
full/proxy/proxy/full/full/proxy/proxy/proxy/full. For the picking variant,
hold 7 (zero-based 6, frames 720..839) aims at the nearest right-lobe face at
(60,42,71) cells; selection must become full while the hit is active. Hold 8
returns to a declared miss and selects proxies again. All other miss rays use
the top-center pointer and must be reference-validated. At these distances the
required hit stays below 256 m. Record the actual pointed member and ray rather
than claiming suppression from a synthetic aim flag alone.

Pair both reference variants with full-geometry runs using identical histories.
Capture each hold midpoint, report allowed proxy appearance differences and
unchanged world/picking/shadow semantics, and verify actual hysteresis/cache
behavior. These are correctness diagnostics; performance claims need applicable
calibration beyond the accepted static/history matrix.

## Scale series and independent diagnostic controls

Main mixed growth permits square neighborhood counts q >= 2. Its ordered area is
`(320*q)^2` cells. Choose the next integer q'>q minimizing `abs(q'^2-2*q^2)`,
breaking ties toward the smaller q'. For refinement, choose an interior integer
q' nearest the midpoint in area, again with the lower tie break. Adjacent q
values satisfy the accepted discrete stopping alternative when a ten-percent
gap is unattainable. Preserve vertical policy and neighborhood composition.

The baseline history has 12 ten-action groups. For every q >= 2, select groups
by `n=(5*b+s-45) mod N` as above; if 5 and N are not coprime, this can revisit
the same neighborhood more often than the formula's r assumes. Therefore the
generalized rule is to choose the smallest integer stride >=5 coprime
to N and use `n=(stride*b+s-45) mod N`; let r be the count of prior visits to n,
not merely a quotient. It agrees with both accepted fixed presets and keeps
r in {0,1,2} for all q >= 2. Freeze it in the generator/schedule version.

Define the following one-control diagnostics as separate configurations. Their
starting inventories and couplings are reported, never claimed constant merely
because they were targets. Validate each transformed fixture and its separately
resolved schedule before using it; no silent fallback to baseline geometry.

| Diagnostic | Exact control and transformation | Intended invariants and admitted coupling |
| --- | --- | --- |
| Spread | Use spacing 640 instead of 320 cells between unchanged 320-cell neighborhood patches. Center the envelope, whose side is `640*(q-1)+320`. Connect successive X neighbors in each row with a 2-cell-wide Z band at local Z=[158,160), and connect successive rows only at first-column local X=[158,160). Connectors fill the open gaps only, with material 1 at Y=[0,1) and material 2 at Y=[1,24). | Same structure shapes/count, source roles and cell size; one connected terrain owner. Added real connector cells/cuboids/surfaces are measured coupling. Empty gaps are not counted as occupied work. |
| Fill/density | Increase flat terrain top from 24 to 32 cells: insert concrete Y=[8,16) over the whole neighborhood, shift all original terrain boxes with low Y>=8 upward 8 cells, and retain original Y<8 layers. Shift every structure and every declared local target/view Y by 8 cells; derive moving targets from the correspondingly shifted geometry. | Same X/Z envelope, owner count and cell size. More real material and the same cavity depth at a higher elevation; report occupied cells, density, bounds and surface changes. Fixed declared vertical envelope remains [0,128). |
| Body count | Replace each building by its intersections with X<72 and X>=80, discarding the real 8-cell-wide gap. Give each nonempty connected half its own initial owner, retaining its protected footings. Other roles stay unchanged. Initial count becomes `1+6*N`. | Same envelope and other roles; material decreases and new exposed faces appear. Record the exact differences. History action 6 uses the back wall at (40+3*r,48,134) instead of the removed partition; separate preflight proves each removal. |
| Cuboid/material detail | On removable terrain only, alternate material 2 and 5 in 4-cell X bands, selecting 2 for even `floor(local_x/4)` and 5 for odd. Preserve protected cells. | Exact occupancy, ownership and bounds preserved; genuine material boundaries change cuboid/surface-material work. Record achieved counts and colors; do not claim identical material state. |
| Surface complexity | Add 64 pits per neighborhood: for u,w in 0..7, remove X=[224+6*u,226+6*u), Y=[22,24), Z=[16+6*w,18+6*w) from terrain. These patches avoid relief, structures and primary action targets. | Same envelope and owner count; removes exactly 512 cells per neighborhood, adds real exposed faces, changes cuboids. Validate connectivity and report the measured surface increase. |
| History | Execute only the first 12, 48 or 120 accepted edits. Retain the full baseline history's already resolved camera track for all 3,600 frames, including later views and the final overview; omit later cuts, not their camera visits. Normal physics continues. Label each prefix as its own configured workload. | Identical initial recipe/seed/camera track. State, IDs, fragments, surfaces and retained memory intentionally evolve. Omitted cuts are not required actions or expected visual changes in that prefix. A prefix does not qualify completion of the 120-edit main case. |
| Concurrent spans | Release the first 1, 2 or 3 spans using the corresponding prefix of the six support cuts. Keep the same overview and record the named frames 31..42. | Identical initial world; require exactly the intended number of released spans moving in that window. Lower-pressure variants do not replace the three-span main case. |

The body-rich diagnostic intentionally changes its target mapping. Its interior
view instead observes a remaining room wall; freeze eye (40,48,80), look
(40,48,132), with the expected removable back-wall hit. In history action 6 use
eye (40+3*r,48,120), look at its revised target. These are declared diagnostic
changes, not opportunistic retargeting after failure. Any diagnostic feature
changed by design has a correspondingly named review expectation, while unchanged
features retain their requirements.

No shorter history reaching the identical final geometry has been established
by this planning audit. During implementation, compare the exact removed-cell
sets and final canonical geometry for a proposed shorter same-radius action
sequence; retain a witness if one exists. If none is supplied, report the absence
and the checked candidates, and do not attribute observed cost specifically to
ID/cache retention. This diagnostic is not a prerequisite for the essential
history family and does not authorize unrelated optimization work.

## Scope of the recipe checks

The [independent scratch model](validation/megascene-spec/recipe_audit.py) and
[its output](validation/megascene-spec/recipe-audit.json) check the baseline
integer recipe, not a production generator. For all four variations, initial
boxes are disjoint and every owner is anchored and positive-face connected.
Cross-neighborhood terrain connectivity follows the touching full-width lower
layers. The localized target removes 16 unprotected cells.

| Fixed preset | Initial owners | Recipe cells, either seed | Authored source boxes |
| --- | ---: | ---: | ---: |
| 64 x 64 m | 21 | 10,503,360 | 204 |
| 128 x 128 m | 81 | 42,096,576 | 816 |

Seeds change geometry despite equal aggregate counts. Source-box counts are not
production tree-leaf or exposed-surface counts. Dense span checks show that the
first cut removes 16 cells and leaves two anchored components: a 120-cell stump
and the still-supported rest. The second removes another 16 and leaves two
anchored 120-cell stumps plus a detached `4080+8*v`-cell body with lower bound
42 cells. Do not assume unchanged anchored-body inventory after the first cut.

The binary32 recurrence gives offset after 12 steps about -0.196200043 m. At
frame 42, the first released span's lower bound is about 2.4342 m above y=0,
with negative velocity; the later releases are higher. This checks the specified
timing margin, not production replay determinism.

The scoped occupancy reference finds material at all 120 history targets for
both presets and seeds: 2,440 cells removed at 64 m, 2,472 at 128 m. The overlapping
terrain revisit removes 16 then 14 cells. It evaluates the moved-beam point in
the known local frame; it does not simulate every component's evolving global
state, IDs, geometry caches or checkpoints. These are recipe reference
expectations, not completed implementation acceptance.

The audit does not validate production tree/surface generation, the diagnostic
transformations, picking/projection, Vulkan visibility, captures, proxy selection,
shadows, operational numeric guards, performance or measurement instrumentation.
All of those remain required implementation work under the handoff.
