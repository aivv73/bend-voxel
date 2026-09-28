# Cavity-framed traversal evidence, 2026-09-28

The original [`traversal-v1` result](../megascene-traversal/README.md) remains
insufficient for cavity depth and bridge readability. After the user accepted a
camera-framing remedy, `traversal-v2` moved only the two cavity endpoints to
local eye `(256,70,210)` and look `(256,12,272)`. All world geometry, materials,
daylight, other endpoints and phase timing stayed the same. The new binary32
schedule SHA-256 is
`71a24174868c840dca4fa42ef78762263b4e893c67909bba1b42a3d74f4a53f9`.
The original schedule and its failed review were retained, not reclassified.

The small, seed-45 district was run at 1920 × 1080, six CPU threads, full body
geometry and 2048 × 2048 shadows on the same Ryzen 5 1600 / GeForce GTX 1660
Linux/X11 host. The separate validation replay passed all 3,721 frames; its
replay ID is `efbf5d61-a637-4a28-a4df-c14effac939e`. A fresh timed attempt
completed all 3,600 measured frames, 16 named checkpoint occurrences, 3,721
native frame audits and the unchanged-geometry return. Its attempt ID is
`bfb53a28-121f-4114-b573-3aaf0c244d62`.

The [first cavity capture](cavity-first.png) and
[return cavity capture](cavity-return.png) are lossless derived PNGs from the
archived 1080p PPM captures at frames 1081 and 2281. The bridge spans the open
cavity in both views; the lower floor, rim and sidewalls are individually
visible. Codex reviewed all 14 captures and 41 named feature assessments,
marking cavity depth and bridge correct and readable at both visits. This is an
operator visual judgment, not a formal proof or a second user review. The raw
captures, input assessments, capture hashes and updated `review.json` remain in
the attempt archive. State correctness, rendering correctness and visual quality
all passed. The occupied-body shadow fit retained at least 232.99 texels of
margin with 0.05675 × 0.04395 m texels.

The ordinary-frame observation interval was 4.35 seconds, below the accepted
ten-second minimum. This is not a benchmark pass or a qualified capacity
endpoint. The campaign archive is
`/home/aivv/megascene-issue53-v2/13f036f9-b271-432b-9e4a-d1126685e730/907efea6-31c1-4426-8b1f-9f580b58065e/bfb53a28-121f-4114-b573-3aaf0c244d62`.
Earlier attempts stopped on stale resource monitoring and retain their
incomplete evidence in the same campaign. The passing attempt's 56 evidence
hashes and all runtime artifacts were reverified after visual review.

The camera change does not alter the renderer or canonical world state. Native
and `@unsafe`-dependent checks rely on runtime/reference evidence rather than
formal Bend proofs.

Verification: `make test` passed 66 Python tests and the Bend/native suites
(two optional tests skipped). `bend PROOF.bend` and
`bend PROOF.bend --verdict` passed. The route test independently projects the
bridge, floor and rim into both 1080p cavity frames and confirms the original
`traversal-v1` bridge center projects outside its frame.
