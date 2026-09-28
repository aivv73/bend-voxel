# Support severing and concurrent motion

Issue #56 adds `--case support` and the frozen `support-v1` schedule. The case
runs six 20 cm cuts at measured ordinals 0, 6, 12, 18, 24 and 30. Each pair
severs the two support paths of one of neighborhood 0's three spans. Startup
and 120 warm-up frames precede the 3,600 measured frames. The binary32 step
remains `0x3c888889`, with physics before edits, view and rendering.

```sh
python3 scripts/megascene.py --case support --preset small --threads 6 \
  --archive "$HOME/megascene-support" \
  --output build/megascene/support/first
```

Use a fresh output directory. The runner archives the actual executable, native
library, shaders, sources, reference workers and resolved schedule before
execution. It then launches a separate complete validation replay with captures
and a fresh timed replay. Resource monitoring, action/interval persistence and
campaign limits use the existing supervisor. `--runtime-from`, `--validated` and
`--validation-only` retain their configuration/artifact applicability checks.
Shortened support schedules, proxy profiles, changed targets and automatic
retargeting are unsupported. Full rendering at 1920 × 1080 is the primary case;
640 × 360 is a separately declared diagnostic.

## Components and actual motion

Each cut removes exactly 16 material-3 cells. Independent six-neighbor traversal
of the small span owners establishes their components; the district stays sparse.
The first cut creates an anchored 120-cell stump while the span retains its
other support path. The second creates another anchored 120-cell stump and a
released body of `4080 + 8*v` cells with local lower bound 42 cells. Protected
footings remain unchanged. Changed components inherit the parent's motion and
receive fresh, monotonic IDs; all unaffected bodies retain their IDs and geometry.

The checker matches independently computed occupancy/material components to
actual allocated IDs at each action checkpoint. It retains that mapping and
requires exact agreement with the separately validated timed run. It compares
all observable state, exposed surfaces, action history and representation work;
matching totals alone do not pass.

Released spans first move on ordinals 7, 19 and 31. Every rendered frame records
each detached body's actual ID, revision, offset and velocity bits. Required
canonical checkpoints cover all twelve ordinals 31–42, in addition to startup,
warm-up, each cut and completion. Missing motion, duplicate identities, an
incorrect span, early detachment or a landed span invalidates the required window.
Failed, rejected, no-op or missing cuts cannot satisfy schedule completion.

A binary32 reference checks every motion sample. A separate analytic parabola
checks pre-contact motion within 0.0001 m and m/s; production/reference state
comparisons remain bit-exact. Floor contact clamps the local bottom to y=0 and
sets speed to zero. There is no terrain/body collision, rotation, stacking or
reattachment. The unchanged production physics therefore allows spans to pass
through terrain and anchored stumps; those intersections are expected.

The real Bend reference worker executes 90 post-warm-up frames, including every
cut, the moving window and floor stopping. Its material, components and exposed
faces are also checked by a dense cell oracle. The existing moved-body split
and atomic-rejection fixtures check nonzero inherited offsets/velocities and
complete rollback. These checks cover unsafe/native behavior at runtime; they
are **not formal proofs**. Safe laws remain checked by `PROOF.bend`.

## Rendering and review

The measured overview is the accepted eye `(160,180,300)` looking at
`(76,55,204)` in neighborhood-local cells. Direct scripted cuts preserve their
exact inset coordinates. A separate pre-edit ray from this overview to the
span's beam top verifies that the intended removable owner is visible and within
256 m. Some inset support points are occluded by beams; the visibility ray does
not claim a mouse click would place the brush at the scripted inset point.
The evolving independent world verifies these rays again before each cut.

Validation retains ten overview captures: initialization, all six edits, measured
frames 31 and 42, and completion. At frames 31 and 42 it binds each named beam
top-center to the actual released ID, offset/velocity, world position and full
mesh hash. An independent visibility ray must reach that body, and its native
full-mesh draw must be present. Named feature review records geometry correctness
and readability separately; pending or failed review cannot pass visual quality.

Native checks compare fresh Bend transport, full mesh data, draw offsets,
visibility, full-mesh slots and retained proxy contents. Each edit builds exactly
two new component meshes. Translation changes transforms and shadow draws while
preserving local full-mesh bytes and slots. Shadow refresh is required at edits
and every offset change, and stops after all three spans settle. World-fitted
2048 × 2048 shadow coverage and texel evidence accompany the captures. Coarse
fine-detail shadows remain a documented quality limitation of the fixed profile.

## Populations and evidence boundaries

A complete measured schedule contains 3,582 ordinary frames, six edit frames
and twelve named motion frames. CPU and GPU populations remain separate.
Accepted edit responses run from before the scripted operation through the
rendered frame-effect return; stage records preserve nested interval boundaries.
Six accepted edits leave the edit-percentile gate **inconclusive**. Neither
attempts nor populations are pooled, and no cuts are added to obtain a pass.
Instrumentation remains uncalibrated; successful correctness, rendering and
completion checks do not imply an interactive benchmark pass or capacity endpoint.

Synthetic report tests deliberately omit, duplicate or corrupt cuts, motion,
checkpoints, anchors, meshes, shadows and surfaces. They validate reporting gates,
never actual Vulkan behavior. The [retained validation record](validation/megascene-support/README.md)
identifies actual completed replays, captures, unsuccessful development attempts,
thread comparisons and archive hashes. The broader matrix, diagnostic variants
and calibration remain in #68, #59 and #65; this slice does not complete #47.

```sh
python3 -m unittest discover -s tests -p test_megascene_support.py -v
make test
bend PROOF.bend
bend PROOF.bend --verdict
```

## Approved supplementary cut views

The user approved supplementary validation captures on 2026-09-28 after the
initial fixed-overview review found cut surfaces occluded at actions 1, 2 and 3.
Each action now has a frozen close-up from 1.2 m in front of its target, at the
same target elevation. The original ten overview captures and timed replay are
preserved. Six additional captures render exactly the already checked post-cut
world, then restore the overview. No extra physics, cuts or GPU measurement
submissions occur. Separate nested records retain close-up/restoration native
mesh, draw, shadow and stage evidence without mixing them with primary frame
records. The checker requires unchanged full mesh bytes/slots, proxy contents,
shadow state and restored overview draws.

Review retains the honest "insufficient" assessment where an overview hides a
cut surface. The explicitly linked close-up may satisfy readability of that
same action's feature, but cannot override incorrect geometry. Every close-up
has its own capture hash, camera bits, action identity, primary checkpoint hash
and named assessments. This is the limited view addition accepted by the user,
not a change to the primary workload or a performance qualification.
