# Support severing evidence, 2026-09-28

Issue #56's small, seed-45 `support-v1` replay runs at 1920 × 1080 with full
geometry and the fixed 2048 × 2048 shadow map. Each of 1, 6 and 12 threads
receives a separate complete validation process and a fresh timed process.
Every process renders startup, 120 warm-up frames and 3,600 measured frames.
The six accepted cuts occur at measured ordinals 0, 6, 12, 18, 24 and 30.

[results.json](results.json) records the final attempt identities, durable
archive locations, verified artifact/evidence counts, independent references,
populations and review outcomes. [thread-comparison.json](thread-comparison.json)
compares exact canonical checkpoints, component/work inventories, actual motion
identities and bits, and beam-feature/full-mesh evidence across all three thread
counts. This is correctness evidence; it is not a speedup comparison.

All three final runs pass state, rendering, visual review and schedule completion.
The frozen schedule SHA-256 is
`9e55070b076f3acb882e5b073e6137912d9df4e70db4d5c1000b72d448d3d936`.
Each archive retains 98 runtime/input artifacts. The host is a Ryzen 5 1600
with a GeForce GTX 1660 under Linux/X11.

| Threads | Timed attempt |
| --- | --- |
| 1 | `c47f5b28-90a6-4285-b2d0-97260bbd68ae` |
| 6 | `77fa347a-da84-4780-a44e-064e32a75cbd` |
| 12 | `b51619bb-307a-44e7-ad96-7ff22d8f5b76` |

## Components, motion and rendering

Each cut removes exactly 16 material-3 cells, for 96 removed cells in total.
After its first cut, each span remains anchored through its other support path
and leaves a separate 120-cell anchored stump. The second cut leaves another
120-cell anchored stump and releases the 4,080-cell span. Protected material
remains unchanged. The final inventory has 10,503,264 cells, 24 anchored bodies,
three detached bodies and next ID 34.

The actual released IDs are 24, 28 and 32. Their release ordinals are 6, 18 and
30; their first motion ordinals are 7, 19 and 31. All three have negative
velocity and nonzero displacement at **every** ordinal 31–42. Their local mesh
bytes, revisions and native mesh slots remain unchanged through translation.
At ordinal 42 the earliest span's offset is `0xbfe205bb` (approximately
−1.7658 m), leaving its lower bound approximately 2.4342 m above y=0.

All three stop at offset `0xc0866667` and velocity `0x00000000` when their
local bottoms reach y=0. Terrain and body intersections are expected under the
unchanged collision-free vertical model. No rotation, stacking or reattachment
was introduced. Every edit rebuilds two component meshes; each subsequent
offset change refreshes shadows without rebuilding local geometry or proxies.
Shadows stop refreshing once the spans settle.

Each validation checks all 3,721 canonical states and native frames. Each timed
replay retains 21 distinct checkpoint frames (22 named occurrences), all 3,721
native audits and every actual detached-body motion sample. The independent
90-frame Bend fixture covers cuts, connectivity, materials, exposed unit faces,
pre-contact motion and floor stopping. The existing moved-body split and atomic
budget-rejection fixtures also pass, covering inherited nonzero motion and exact
rollback. These are runtime/reference checks of unsafe/native behavior, not
formal proofs.

[actions-motion-rendering.json](actions-motion-rendering.json) retains primary
timed action intervals plus native, mesh, shadow and actual motion evidence for
ordinals 31 and 42. Full streams, source inputs, executable workers, native
libraries, shaders, reference output and hashes remain in each durable archive.

## Overview and approved supplementary captures

The original [opening](opening.png), six cut overviews, [frame 31](motion_31.png),
[frame 42](motion_42.png) and [completion](completion.png) remain unchanged.
All ten primary captures are byte-identical to the run before supplementary
views were added. All corresponding final captures are also byte-identical
across the three thread counts. The PNG files here are lossless copies of the
raw archived PPM images. [overview-compatibility.json](overview-compatibility.json)
records unchanged checkpoint payloads after excluding only the schedule hash,
which now includes the supplementary camera inputs.

The prescribed overview hides some new cut surfaces at actions 1, 2 and 3.
Those overview assessments remain **insufficient**, with geometry correctness
recorded separately. The user explicitly approved supplementary validation
views on 2026-09-28. Their fixed cameras render the same post-cut state, then
restore the primary camera without advancing physics or actions. The extra
renders produce no GPU measurement samples and never enter the timed replay.
Native evidence checks unchanged mesh bytes/slots, proxy contents, shadow state
and restored primary draws.

| Action | Measured ordinal | Required overview | Supplementary cut and stump view |
| --- | ---: | --- | --- |
| A0 | 0 | [cut 0](cut_0.png) | [detail 0](detail_0.png) |
| B0 | 6 | [cut 1](cut_1.png) | [detail 1](detail_1.png) |
| A1 | 12 | [cut 2](cut_2.png) | [detail 2](detail_2.png) |
| B1 | 18 | [cut 3](cut_3.png) | [detail 3](detail_3.png) |
| A2 | 24 | [cut 4](cut_4.png) | [detail 4](detail_4.png) |
| B2 | 30 | [cut 5](cut_5.png) | [detail 5](detail_5.png) |

Codex inspected every full-resolution overview and close-up. The foreground cut
ends and lower stump tops are readable in all six close-ups. Narrower supports
visible behind some gaps belong to other spans. Major shadows remain visible;
fine shadow edges are coarse at the specified map resolution. Each close-up is
bound to its camera, action, capture hash and primary checkpoint hash.
[review.json](review.json) and [assessments.json](assessments.json) preserve the
individual assessments and explicit supplementary coverage. A close-up cannot
override incorrect geometry. This is an agent visual assessment; the user's
approval authorized the extra views, rather than certifying the rendered result.

## Boundaries and retrieval

Each timed attempt has 3,582 ordinary, six edit and twelve named motion samples,
with CPU and GPU populations kept separate. The six-edit percentile gate stays
**inconclusive**. Instrumentation is uncalibrated; no run is an interactive
benchmark pass or qualified capacity endpoint. No attempts or populations were
pooled, and the schedule was not extended. The broader matrix, diagnostics and
calibration remain in #68, #59 and #65; parent #47 is not complete.

The primary six-thread archive is:

```text
/home/aivv/megascene-support-56/ffac9c21-68b7-43dc-a844-4786c0591aaa/ec7e8db9-a6d6-46f8-be5e-707d3e7cd76d/77fa347a-da84-4780-a44e-064e32a75cbd
```

`results.json` also retains the initial build failure and all four earlier runs
whose world/motion checks passed but whose overview-only cut review was
insufficient. Their evidence is preserved and excluded from the final comparison.
Final check sources, logs and this evidence directory are additionally retained
at `/home/aivv/megascene-support-56/issue56-final-checks`.

`make build` and `make test` passed, including all Bend/native suites and 95
Python tests (three opt-in integrations skipped; the complete support Vulkan
replays were executed separately above). Both `bend PROOF.bend` and
`bend PROOF.bend --verdict` passed. `git diff --check` is clean.

Verification logs: [build](build.log), [tests](tests.log), [Bend proof](proof.log),
[proof verdict](verdict.log) and [retention](retention.log).
