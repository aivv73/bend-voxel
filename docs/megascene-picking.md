# Bounded primary Megascene picking

Issue #54 adds `--case picking` to the public runner. `picking-v2` uses the
exact `traversal-v2` camera history, including the accepted cavity framing.
`picking-v1` retains the original camera history for reproduction. Versions
have distinct schedule identities and cannot share validation. Both routes
require startup, 120 warm-up frames and all 3,600 measured frames.

```sh
python3 scripts/megascene.py --case picking --schedule picking-v2 \
  --preset small --seed 45 --threads 6 --resolution 1920x1080 \
  --validation-only --output build/picking-validation \
  --archive "$HOME/megascene-picking-evidence"
python3 scripts/megascene.py --case picking --schedule picking-v2 \
  --preset small --seed 45 --threads 6 --resolution 1920x1080 \
  --validated build/picking-validation --output build/picking-timed \
  --archive "$HOME/megascene-picking-evidence"
```

Validation and timing use separate fresh processes. The runner preserves the
existing supervision, archive, exact checkpoint, GPU and resource evidence
boundaries. An incomplete validation cannot launch a timed attempt. Passing
picking checks alone does not qualify responsiveness or capacity; population
duration, calibration and visual review remain separate gates.

The complete replay exposed disk-flush stalls in the existing supervisor.
Durability now uses one background I/O task with at most one flush in flight;
resource polling and reserve/deadline checks continue while the disk flushes.
Records are appended unbuffered and committed shared slots are never reused.
The final durability barrier waits for the pending flush and synchronizes the
final evidence prefix. Any flush failure still fails persistence. This changes
no resource threshold, freshness limit, worker geometry or workload timing
schedule; it prevents disk latency from blocking the resource supervisor.

## Declared rays and results

Only offsets 0 through 119 of the following measured phases enable the center
ray. Every other frame records picking as disabled, including startup,
warm-up, interpolation, opening and far views. No edits occur.

| Phase | Pose | Required result |
| --- | --- | --- |
| 1 | Wall, neighborhood 0 | Owner 2, material 5, left exterior face |
| 2 | Interior, neighborhood 0 | Through the doorway to owner 2, material 5, left wall interior face |
| 3 | Cavity, neighborhood 0 | Owner 1, material 2, floor at 0.8 m |
| 4 | Assembly, neighborhood 0 | Owner 6, material 3, upper lobe |
| 7 | Cavity, last neighborhood | Owner 1, material 2, floor at 0.8 m |
| 8 | Sky, neighborhood 0 | Miss |

This is 600 required hits, 120 required misses and 3,001 disabled frames.
Reach stays strictly less than 256 m. Misses use the existing 256 m sentinel;
disabled frames retain the traversal's zero aim. Protected material retains
kind 2, removable material kind 1, and the unbounded y=0 floor kind 3.

`schedule.json` retains every camera, expected ray, named target (including
owner, material and neighborhood), expected point/distance bits and outcome.
`camera.bin` and `rays.bin` retain the binary32 input words. The worker derives
the actual center ray with the same projection and normalization used by the
interactive picker. `cpu.jsonl` records its actual origin/direction, enabled
status, winning owner/material, point, distance and kind for every frame.
Comparison requires exact agreement with the frozen inputs and expected
results. No ray is retargeted, skipped or extended to satisfy an expectation.

The picker carries the winning leaf identity through the existing traversal;
its strict distance comparison and traversal tie order are unchanged. The
interactive `Aim` API remains unchanged. Canonical checkpoints include exact
aim bits (the legacy `radius_m` field holds `Aim.distance`). Body hashes,
geometry inventories, native mesh ownership and shadow caches must stay
unchanged through aim transitions and the final return. Preview overlays may
change independently of full body meshes.

## Independent references and numeric admission

Before compiling or running a candidate, an independent oracle enumerates
face intersections using rational arithmetic on integer source cells, their
metre scale, body offsets and the frozen binary32 rays. It checks the declared
owner, material and face, including whether the cavity framing still hits the
floor. A separate binary32 operation model supplies exact expected recorder
bits; it must agree with the independent oracle in identity, hit/miss and a
bounded distance/point tolerance. Exact runtime bits are then checked against
the real production picker during the complete validation replay.

The retained `picking-reference-worker` executes small fixtures before Vulkan
validation. The reference uses rational face intersections and independently
expanded unit cells, covering empty and ground rays, protected material,
signed coordinates, positive/negative body offsets, half-open parallel
boundaries, an eye inside a cell, nearest-owner selection and distances just
below, at and beyond 256 m. These are runtime comparisons with production
Bend, not synthetic reports. Tests additionally compare fixture output at
1, 6 and 12 threads and check actual center-ray bits for both fixed presets
and seeds.

Immediately before each enabled unsafe traversal, the native guard reads the
actual Bend tree bounds and body offsets. It checks the ray normalization,
finite values, cell multiplication by binary32 0.1, offset addition, endpoint
subtraction, slab division, ground distance and accepted-hit multiply/add
operations against double arithmetic. It rejects fractional cells, collapsed
extents, unsupported magnitudes or excessive rounding. The conservative
bounds are +/-8,192 cells, +/-1,024 m offsets and +/-2,048 m origins; these
bounds alone do not admit a configuration. The independent target/reach
checks remain required. Representable endpoints that lose cell separation
or swallow a cell after adding an offset are explicit rejection fixtures.
Unsafe and native behavior is never described as formally proven.

## Named review points

The separate validation replay captures the same 14 views and 16 checkpoint
occurrences as traversal. Picking is active at the six declared hold review
points, so their captures include the actual aim overlay. Review each named
feature using `scripts/megascene_review.py` as described in
[the traversal workflow](megascene-traversal.md#captures-and-review). Capture
hashes, shadow coverage, geometry correctness and readability remain explicit;
missing assessments cannot pass visual quality.

The [2026-09-28 small-preset evidence](validation/megascene-picking/README.md)
retains the complete validation and timed replay, actual picking results,
named visual review and the explicit limits on benchmark qualification.
