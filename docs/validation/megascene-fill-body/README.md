# Fill and initial body-count pressure evidence, 2026-09-29

Issue #60's three prescribed small/seed-45/1920 x 1080/full-geometry/six-thread
variants completed separate 3,721-frame Vulkan validations and timed replays
with 120 warm-up and 3,600 measured frames. All three have passing schedule,
state and rendering checks. Fill-support released all three spans and checked
their motion on each measured frame 31–42. Both history variants accepted all
120 required actions. [Results](results.json) retain archive paths, attempt and
validation IDs, schedule and worker hashes, inventories, and review status.

| Variant | Initial owners | Cell delta | Cuboid delta | Surface rectangle delta | Exposed-area delta |
| --- | ---: | ---: | ---: | ---: | ---: |
| [Fill support](fill-support-comparison.json) | 21 | +3,276,800 | +4 | +8 | +20,480 |
| [Fill history](fill-history-comparison.json) | 21 | +3,276,800 | +4 | +8 | +20,480 |
| [Body-rich history](body-rich-history-comparison.json) | 25 | −76,032 | 0 | −28 | −38,400 |

Fill adds only material-2 cells and preserves the protected-cell count and
X/Z generation bounds. The occupied top rises from Y=89 to Y=97 cells; the
declared vertical envelope stays [0,128). The cavity remains sixteen cells
deep above the inserted layer, and shifted support fragments stop at world
y=0. Body-rich retains all protected cells and the other scene roles. Its real
eight-cell building gap creates two independently anchored owners per
neighborhood. The gap has new facing surfaces, although total exposed area and
surface rectangle counts decrease because material was removed. Its frozen
schedule records the remaining-wall interior view and checks each action-6
back-wall removal against actual geometry.

The comparison reports verify each nonsynthetic timed attempt, its distinct
complete validation, and achieved inventory before recording deltas. The
support baseline is the existing validated six-thread run from issue #56. A
matching six-thread history baseline completed fresh validation and timing
using the retained history runtime and byte-identical frozen schedule. The
results also list a failed fill-support development attempt, whose scalar
settlement audit was corrected, and a preliminary body-rich attempt superseded
by the schedule with the explicit interior-view record.

These are complete correctness and workload observations. Named visual-feature
review and applicable instrumentation calibration remain outstanding; no
benchmark responsiveness, capacity or visual-quality pass is claimed. Unsafe
Bend and native behavior is supported by independent reference fixtures and
runtime replay, not formal proof.
