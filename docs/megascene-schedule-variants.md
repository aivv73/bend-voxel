# History and concurrent-span controls

The four issue #61 controls retain the small preset, seed 45, 1920 x 1080 full
profile and six-thread observation. Each has 120 warm-up and 3,600 measured
frames, a separate validation replay and a fresh timed replay. Select one
explicit schedule ID with the ordinary Megascene runner:

```sh
python3 scripts/megascene.py --case history --schedule history-12-v1 \
  --preset small --seed 45 --threads 6 --resolution 1920x1080 \
  --archive "$HOME/megascene-issue61" --output build/megascene/history12
```

The other IDs are `history-48-v1`, `support-1-span-v1`, and
`support-2-span-v1`, with the matching `--case`. Use a fresh output directory
for each invocation. The durable archive keeps the actual runtime and frozen
inputs, validation, timed CPU/GPU records, motion, work inventories,
checkpoints, and required feature captures.

| Schedule | Required actions | Unchanged frame route | Specific checks |
| --- | ---: | --- | --- |
| `history-12-v1` | First 12 of 120 | Full `history-v1` camera track | Every edit and after-cut-12 checkpoint; later cut sites remain unedited. |
| `history-48-v1` | First 48 of 120 | Full `history-v1` camera track | Every edit and after-cut-12/48 checkpoints; later cut sites remain unedited. |
| `support-1-span-v1` | First 2 of 6 | Full `support-v1` overview | One released body moves on every measured frame 31–42; two later spans remain supported. |
| `support-2-span-v1` | First 4 of 6 | Full `support-v1` overview | Two distinct released bodies move on every measured frame 31–42; the last span remains supported. |

The frozen schedule names omitted actions and marks them as not required for
that variant. Its `schedule_completion` refers to the variant ID; the report
marks baseline completion as not applicable. Physics advances throughout the
full observation. Per-frame validation checks evolving material, ownership,
surfaces, motion and native geometry. Timed evidence retains cut intervals,
ordinary/moving/edit populations, named checkpoints and changed feature
expectations separately. An edit population below 100 remains insufficient
for an edit percentile pass.

Compare a variant with a completed baseline using
`scripts/megascene_compare_schedules.py --baseline ARCHIVE --variant ARCHIVE
--output comparison.json`. It verifies both archived attempts and separate
validations, identical initial inventory, the action prefix and frozen camera
track. It also compares exact reference removed-cell sets and final canonical
body occupancy, surfaces and position. These shortened schedules intentionally
change final state. An absent identical-final-geometry witness leaves any
retention-specific cost attribution unavailable.

Completion and state correctness are development evidence. Named feature
review, calibration and benchmark qualification retain their own outcomes.
All checks involving unsafe Bend or native renderer behavior are
runtime/reference checks, not formal proofs.
