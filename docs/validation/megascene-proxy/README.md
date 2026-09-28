# Proxy diagnostic evidence, 2026-09-28

Issue #58's small/seed-45 diagnostics completed at 1920 × 1080 with six threads
on the Linux/X11 Vulkan host. Each of the eight profile/case configurations
had a separate complete 3,721-frame validation replay followed by a fresh
timed process with 120 warm-up and 3,600 measured frames. All eight completed
their declared schedules and passed state, rendering, native proxy and
checkpoint checks. The four [pair reports](results.json) verify identical
source worlds, camera and aim histories, picking results, canonical
world/geometry checkpoints, shadow fit and full-mesh shadow work.

| Diagnostic | Case | Pair report | Validation captures per profile |
| --- | --- | --- | ---: |
| Compact reference | Traversal | [report](compact-reference-traversal-pair.json) | 11 |
| Compact reference | Picking | [report](compact-reference-picking-pair.json) | 11 |
| Mixed world | Traversal | [report](mixed-world-traversal-pair.json) | 5 |
| Mixed world | Picking | [report](mixed-world-picking-pair.json) | 5 |

The compact fixture has four disjoint anchored owners, 35,424 cells and a
71 × 35 × 71-cell union bound. The actual native group contains IDs 1–4 in
centered tile `(0,0)`. Traversal selected proxies on holds 1, 2, 5, 6 and 7;
picking selected them on holds 1, 2, 5 and 7. During picking hold 6, the
independent source-face oracle and the actual Bend ray both hit the right-lobe
face of body 4 at about 172 m. Native aimed-at suppression selected full
meshes for that hold; hold 7's declared miss re-entered proxy mode. The 75,
90 and 105 render-pixel poses retained measured margins on both sides of the
80/100 hysteresis thresholds.

The mixed-world central group contains IDs 6, 11, 16 and 21 in tile `(0,0)`.
Its opening warm-up matches the primary traversal camera. Both diagnostic
cases selected proxies at the 1,000 m holds and full geometry at the 100 m
hold. Mixed picking retained 2,400 checked far misses. The top-center ray
would hit owner 20 at 100 m, so picking was explicitly disabled during that
near hold; the compact fixture supplies the reachable aim suppression case.

## Retained work and appearance

In the compact reference, each profile retained 744 full-mesh vertices and
144 proxy vertices. A selected proxy hold changed the main pass from four
full-body draws to one proxy draw. The mixed world retained 6,984 full-mesh
vertices and 144 proxy vertices; at its far hold, the main pass changed from
21 full-body draws to 17 full-body draws plus one proxy draw. The full profile
kept the same proxy cache bookkeeping. All profiles retained the full-mesh
shadow draw list: four compact or 21 mixed bodies. Each run issued those
full-mesh shadow draws on its initial shadow refresh and reused the map as the
camera and aim changed.

The paired total native vertex uploads matched within each case, including
dynamic overlay uploads; the proxy route did not reduce those bytes. Each
profile rebuilt all four or 21 full meshes and one proxy group at startup,
then reused them. The explicit Vulkan allocation peak was 26,673,152 bytes
in these runs. The pair reports separate that allocation scope from native
CPU vertex-arena capacity and process-tree RSS. None of these figures is a
claim that proxy selection reduced resident world storage.

The unaltered capture previews show [full geometry](compact-full-selected-hold.png)
beside the [selected proxy](compact-proxy-selected-hold.png) at compact hold 1.
The proxy presents coarse material-colored boxes and loses the full surface
detail and silhouette. The [aimed-at hold](compact-proxy-aim-suppressed-hold.png)
uses full geometry, and the [next miss](compact-proxy-reentry-hold.png) returns
to the box proxy. These PNGs are previews; all midpoint PPM captures and
their hashes remain in the archived validation bundles listed in
[results.json](results.json). Visual-quality assessments remain pending, and
no equal-fidelity claim follows from the paired correctness checks.

The [negative fixtures](../../../tests/test_megascene_proxy.py) reject wrong
80/100 selections and missing native frame evidence. The pair CLI also writes
an inconclusive report for missing bundles. Earlier development failures are
retained in the same campaign and are excluded from the passing index.

All timings are unqualified development observations. Applicable calibration
has not passed for these configurations, so none of the pair reports claims a
benchmark or capacity pass. The selection, picking, native cache and shadow
invariants depend on unsafe or foreign code and have runtime/reference
evidence, not formal proofs.
