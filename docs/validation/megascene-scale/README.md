# Mixed-district scale validation for issue #66

`--side-m 32*q` requests a square `q*q` neighborhood district. The runner
supports integer `q=2..5` (64, 96, 128 and 160 metres); `q=2` and `q=4` keep
the named small and large presets. This is a checked operational range, not an
observed physical scale ceiling. Requests outside it receive a retained
rejection. No case silently changes the requested district, actions or views.

`megascene_scale.py` implements integer area growth and refinement. From q=2,
nearest doubling selects q=3, then q=4, then q=6. Refinement uses the closest
interior squared area with lower ties; adjacent q values have no interior
candidate. The history-v2 schedule for the new scales records the smallest
stride at least five coprime to `q*q` and each group's actual prior visits.
For q=5 the stride is six, and its first six neighborhoods are
0, 6, 12, 18, 24, 5. The named presets retain history-v1 and its previous
schedule bytes.

Admission checks actual generated boxes, source cell and surface products,
IDs, initial native sizes, frame and clock arithmetic. Each replay freezes and
checks every camera, ray and required action before worker execution. Picking,
carving, body counts and native allocations still use their existing evolving
runtime guards. These are runtime/reference checks; Bend proof results do not
establish properties that depend on unsafe or native code.

## Intermediate-scale evidence

The 3×3, seed-45 admission bundle is retained at
`/home/aivv/megascene-issue-66-admission-archive/megascene-scale-3-admission-66`
(with a local copy at `build/megascene-scale-3-admission-66`). Its actual Bend worker and independent
inventory reference agree on 46 initial anchored owners, 23,663,488 occupied
cells, 459 cuboids, 2,595 exposed rectangles and 3,140,244 exposed cell faces.
The occupied source bounds are [-480,0,-480] to [480,89,480] cells.

The 5×5, seed-45 Bend admission bundle is retained at
`/home/aivv/megascene-issue-66-admission-archive/megascene-scale-5-admission-66`
(with a local copy at `build/megascene-scale-5-admission-66`). It records 126 initial anchored owners,
65,760,064 occupied cells, 1,275 cuboids, 7,155 exposed rectangles and
8,627,780 exposed cell faces. Its occupied bounds are [-800,0,-800] to
[800,89,800] cells. This confirms generated work and checked initial
inventory at the first scale where stride five would repeat neighborhoods.
It does not supply a 5×5 Vulkan replay or a performance claim.

The 3×3 full-geometry Vulkan static run is retained at
`/home/aivv/megascene-issue-66-archive/13e0327e-0560-4672-89bb-2ddb1dd39ce2/a89ad9ea-79ed-4944-91fb-583ee6e49179/7a8bec3f-b31b-4b2a-a6c7-24ae1e533ac6`.
Its local copy is `build/megascene-scale-3-static-final-66`. The requested and
effective settings were q=3, seed 45, six threads, 640×360, full geometry,
zero warm-up frames and one measured frame. A separate validation replay and
the timed attempt both completed; state correctness, schedule completion,
rendering correctness and numeric validity report pass. Visual quality,
responsiveness and interactive qualification remain inconclusive. This short
run is a bounded generation/replay witness, not a benchmark pass.

The tests in `tests/test_megascene_scale.py` independently enumerate discrete
area choices, check actual prior visits at q=2,3,4,5, exercise the q=5 history
target mapping, check U32/U64 boundaries, and preflight the 3×3 picking and
edit schedules. The full six-case schedules also resolved at q=3 and q=5 with
3,721 frames each and all required targets reachable; these schedule checks
are separate from Vulkan case completion. Larger regions remain unsupported.

The retained `megascene-scale-6-rejected-66` fixture in the admission archive records a requested
192-metre side, `effective: null` and `rejected_request`. The separate
`megascene-scale-3-numeric-rejected-66` fixture there records a requested and
effective 96-metre configuration but rejects a fragment budget of 4,294,967,295
before Bend execution because initial owners plus that budget exceed the
checked U32 live-body envelope. Neither result is a capacity observation.
