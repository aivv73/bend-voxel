# History and span control evidence, 2026-09-29

Issue #61's four small/seed-45/1920 x 1080/full-profile/six-thread variants
completed separate 3,721-frame Vulkan validations and timed replays, with 120
warm-up and 3,600 measured frames each. All four have passing schedule, state,
rendering and GPU evidence checks. [Results](results.json) list the retained
archive paths, actual worker and schedule hashes, validation IDs, frame/edit
populations, and review status.

| Variant | Required edits | Ordinary frames | Moving window | Final cells | Compared with baseline |
| --- | ---: | ---: | --- | ---: | --- |
| [12-edit history](history-12-comparison.json) | 12 | 3,588 | One release window | 10,503,106 | Different removed cells and final geometry |
| [48-edit history](history-48-comparison.json) | 48 | 3,552 | Five release windows | 10,502,366 | Different removed cells and final geometry |
| [One span](support-1-span-comparison.json) | 2 | 3,586 | One span on every frame 31–42 | 10,503,328 | Different removed cells and final geometry |
| [Two spans](support-2-span-comparison.json) | 4 | 3,584 | Two spans on every frame 31–42 | 10,503,296 | Different removed cells and final geometry |

The history prefixes retain the entire baseline camera track, including the
later cut-site visits and final overview. Those later visits have named
captures and explicit no-new-cut expectations. Support variants retain the
unchanged overview, with named captures of uncut later support sites. Normal
physics continues in all four full-duration replays. Every scheduled cut has
an independent removal reference, actual accepted outcome, edit interval,
checkpoint and retained work inventory. The one/two-span references use actual
Bend transitions against dense connectivity and motion checks. All variants
explicitly mark omitted cuts as outside their required action schedule and
report baseline completion as not applicable.

The comparison command checks both actual archived attempts and their
distinct complete validations, equal initial world/work, exact action prefix
and unchanged camera track. It compares the removed-cell sets and final
canonical occupancy, exposed surfaces and body positions without relying on
lifetime IDs. All four comparisons found changed final geometry; there is no
identical-final-geometry witness. Retention-specific performance attribution is
therefore unavailable.

The first 12-edit attempt passed validation but stopped before timing because
the review list omitted captures at later camera visits. The first one-span
validation stopped after the native supplementary-camera reader assumed six
cuts. Both failures remain in the durable campaign archive; the corrected
schedules and reader completed in fresh attempts. Visual feature assessment
and instrumentation calibration remain outstanding. Each edit population has
fewer than 100 samples, so edit percentile qualification is inconclusive.
These are correctness and workload observations, not benchmark or capacity
passes. Unsafe Bend and native behavior is supported by runtime/reference
evidence, not formal proof.
