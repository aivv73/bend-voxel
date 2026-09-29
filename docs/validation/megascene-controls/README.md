# Terrain pressure evidence, 2026-09-29

Issue #59's four prescribed small/seed-45/1920 x 1080/six-thread variants
completed separate full Vulkan validation and timed replays. Each validation
checked 3,721 frames; each timed replay completed 120 warm-up and 3,600
measured frames with passing state, rendering and schedule checks. Matching
static and localized baselines ran under the same settings. The archived
attempt paths, distinct IDs, schedule hashes, capture hashes and achieved
inventories are in [results.json](results.json).

| Variant | Cells versus baseline | Cuboids versus baseline | Exposed area versus baseline | Surfaces versus baseline |
| --- | ---: | ---: | ---: | ---: |
| [Spread static](spread-captured-comparison.json) | +46,080 | +6 | +111,072 | +68 |
| [Material static](material-static-timed-comparison.json) | 0 | +828 | 0 | +1,628 |
| [Material localized](material-localized-timed-comparison.json) | 0 initially | +828 initially | 0 initially | +1,628 initially |
| [Surface static](surface-static-timed-comparison.json) | −2,048 | +320 | +4,096 | +1,692 |

Spread's real protected/removable connector boxes preserve one connected
terrain owner across the larger 960-cell envelope. Its protected-cell count
increases by 1,920. Material detail preserves initial occupancy, ownership,
protected cells and bounds; alternating concrete and plaster bands increase
actual cuboid and surface-material work. Its localized edit accepted the same
16-cell target removal, including cells of both materials, and retained the
complete checkpoint comparison. Surface detail removes exactly 512 cells per
neighborhood while preserving initial owners, protected cells, bounds and
terrain connectivity. Each row has its own frozen schedule and validation
identity. The comparison reports verify both archived timed runtimes and
their separate complete validations before reporting actual work differences.

The [opening previews](opening-comparison.png) show baseline, spread,
material detail and surface detail; the [cut previews](localized-comparison.png)
show baseline and material detail at frame 121. The underlying PPM captures and
hashes remain in the archived attempts listed in results.json. Named feature
review and visual-quality qualification remain pending. These observations
do not establish benchmark or capacity passes; applicable calibration has not
been completed. Source and native invariants depend on unsafe or foreign code
and have runtime/reference evidence rather than formal proof.
