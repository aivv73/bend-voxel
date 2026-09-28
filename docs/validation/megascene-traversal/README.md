# Small-preset `traversal-v1` evidence, 2026-09-28

This report preserves the original failed cavity review. The later
[`traversal-v2` camera-framing evidence](../megascene-traversal-v2/README.md)
uses a distinct frozen schedule and does not change this result.

The accepted `traversal-v1` route was executed on the small, seed-45 district at
1920 × 1080, six CPU threads, full body geometry and 2048 × 2048 shadows. The
machine was an AMD Ryzen 5 1600 with an NVIDIA GeForce GTX 1660 on Linux/X11.
The persisted schedule SHA-256 is
`20a66f5b0d1b90bc9f9064a57713df1f64ebd158dab63948d37d7da7fb4d8b73`.
Runtime binaries, libraries, shaders, frozen inputs and all raw records are in
the durable `/home/aivv/megascene-issue53/` campaign archive. The final timed
attempt ID is `a77fd17b-eb90-40a0-abec-bba7dfd27585`; its separate validation
replay ID is `0c9b5f31-a3d3-47e1-9ffa-9ff54303eb90`.

The separate validation replay passed all 3,721 startup, warm-up and measured
frames. The fresh timed process returned all 3,600 measured frames, all 16
named checkpoint occurrences, and native audit evidence for every frame.
Canonical per-body geometry stayed unchanged on the return route. Unculled
triangle visibility, native full-mesh cache reuse and occupied-world shadow fit
checks passed. The shadow extent was 116.23 × 90.01 m, with 0.05675 × 0.04395 m
per texel and at least 232.99 texels of occupied-body margin.

The [contact sheet](contact-sheet.png) is a derived aid for inspection; all 14
raw full-resolution PPM captures and their hashes are retained in the attempt's
`validation/captures/` directory. Named feature review found **correct geometry
with insufficient readability** for cavity depth and the cavity bridge at both
required cavity views (`review_route_03` and `review_route_07`). The user
confirmed this readability judgment. Other named features were assessed as
correct and readable. Rendering correctness and state correctness passed;
visual quality failed. This distinction is recorded in the archived
`review.json`, `assessments.json` and `summary.json`.

The measured ordinary-frame interval was 5.02 seconds. The accepted ten-second
minimum was not reached, so this run is not a benchmark pass or a qualified
capacity endpoint. No schedule was extended to obtain one. The fixed route's
cavity readability failure also left the original primary fidelity outcome
unmet. An earlier
retry stopped on stale resource monitoring and its incomplete evidence remains
in the same campaign archive.

Verification: `make test` passed 64 Python tests and the Bend/native suites
(two optional tests skipped); `bend PROOF.bend` and
`bend PROOF.bend --verdict` passed. Frustum-boundary, eye-inside,
signed/translated and near-plane fixtures use the unculled triangle reference.
These native and unsafe-dependent properties are runtime/reference evidence,
not formal proofs.
