# Localized cut evidence, 2026-09-28

Issue #55's small, seed-45 `localized-v1` replay completed at 1920 × 1080 with
full geometry on the Ryzen 5 1600 / GeForce GTX 1660 Linux/X11 host. Each of
1, 6 and 12 threads received its own separate complete validation process and
fresh timed process. Each process rendered startup, 120 warm-up frames, one
accepted edit at measured frame 0, and 3,599 unchanged-world frames.

The frozen schedule SHA-256 is
`3d3b5eb5befad07196de614b118b068ee7072bb5bfee1eb2ba7f0a7922f3b2fc`.
All three runs agree on exact canonical state, geometry and actual edited work.
[thread-comparison.json](thread-comparison.json) records the comparison;
[results.json](results.json) records identities, outcomes, references, captures
and verified artifact/evidence counts.

| Threads | Accepted edit response (ms) | Ordinary observation interval (s) | Timed attempt |
| --- | ---: | ---: | --- |
| 1 | 17.199443 | 5.829998788 | `445e8094-6111-4495-8892-b28e13117df1` |
| 6 | 16.994674 | 5.922642727 | `41a670a9-7e9c-4934-bf59-d5c30ea8c09d` |
| 12 | 16.935408 | 5.958362743 | `2146920e-3339-42e0-b5ac-c8683ebec55b` |

These are individual uncalibrated observations, not speedup estimates. Each
accepted-edit population has exactly one sample and its percentile gate is
**inconclusive**. Each ordinary population has 3,599 frames and less than the
required ten seconds. No attempt was lengthened or pooled, and none is a
benchmark pass or qualified capacity endpoint.

## Geometry, rollback and captures

The independent reference and production agree on exactly 16 removed concrete
cells. Terrain remains one anchored connected body: ID 1 becomes ID 22,
revision 0, and next ID becomes 23. Protected cells and all 20 other owners
remain unchanged. The native renderer rebuilds exactly one full mesh on the
edit frame, preserves unaffected mesh slots and proxy contents, and refreshes
shadows once. All subsequent frames retain the edited state and caches.

Each validation checked all 3,721 canonical states and native frames. Each timed
run retained all five named checkpoint occurrences and 3,721 native audits.
The final stricter checker was also applied to all six retained CPU streams:
a named checkpoint must contain its canonical payload. Its additional source
and audit results are archived separately without rewriting the original
runtime bytes or attempt identities.

The compiled independent edit reference worker covers signed coordinates,
protected material, partial faces, repeated-damage no-op, air no-op, a moving
split, complete removal and atomic budget rollback. Its before/after output is
retained as `validation/edit-reference.stdout.log` in every attempt archive.
Budget rejection preserves exact body lists, IDs/revisions, next ID, budget,
materials, anchors, offset/velocity bits, faces and vertices. Unit tests also
exercise the real recorder's rejected/no-op history, canonical rejection
checkpoints, pre-unsafe numeric rejection, and synthetic report failures for
missing/duplicate actions, incorrect intervals, missing canonical payloads,
changed geometry and stale caches. These are runtime/reference checks, not
formal proofs of unsafe or native code.

The [opening](opening.png), [cut](cut.png) and [completion](completion.png)
captures are lossless PNG copies of the raw validation PPM captures. Cut and
completion are byte-identical; all three thread configurations also produced
byte-identical corresponding captures. Codex reviewed the full-resolution
captures and recorded all eight named features as correct and readable in
[review.json](review.json) and [assessments.json](assessments.json). This is a
visual assessment, not separate user confirmation. Fixed shadow texel edges
are coarse and lower contrast around the cut, but its stepped rim and exposed
faces remain distinguishable.

## Retrieval and scope

The primary six-thread archive is:

```text
/home/aivv/megascene-issue55/41412612-0c02-4cb4-ac06-dbd576b7afe6/d2bc5641-2861-4198-a137-0302e322154f/41a670a9-7e9c-4934-bf59-d5c30ea8c09d
```

All three final attempts retain 91 runtime/input artifacts each, including actual
executables, native libraries, shaders, sources, frozen inputs and reference
workers. All artifact and evidence hashes were verified after visual review.
`results.json` links the other two archives and two earlier successful development
iterations, which remain separate and are excluded from the final comparison.
The final payload checker and consolidated results are additionally retained at:

```text
/home/aivv/megascene-issue55/issue55-final-checks
```

[action-and-stages.json](action-and-stages.json) contains the primary timed
operation markers and action/response records. Edit response starts before the
scripted operation and ends at its rendered frame return. Carving includes its
numeric guard; transport contains checkpoint time, and renderer contains its
native stages. Nested intervals are not additive. CPU/GPU ordinary distributions
exclude the edit frame; the common reference stream retains the action and response.

This evidence covers issue #55's localized behavior and thread equality.
Large-preset Vulkan matrix completion, the material-detail diagnostic, calibrated
performance qualification and archived-run recovery remain in the separate
#68, #59, #65 and #63 work items. Both presets and both seeds pass frozen-target
and removal preflight tests here. This does not claim completion of parent #47.

`make build` and `make test` passed, including all Bend/native suites and 86
Python tests (two optional integrations skipped; complete localized Vulkan
replays were executed separately above). Both `bend PROOF.bend` and
`bend PROOF.bend --verdict` passed.

Verification logs are [tests.log](tests.log), [build.log](build.log),
[proof.log](proof.log), [verdict.log](verdict.log) and [retention.log](retention.log).
