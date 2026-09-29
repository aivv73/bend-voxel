# Megascene attempt reports

`scripts/megascene_report.py` reads a retained attempt through the public
archive boundary:

```sh
python3 scripts/megascene_report.py --bundle /path/to/attempt > attempt-report.json
```

The runner applies the same classifier to timed attempts after validation and
capture processing. `scripts/megascene_review.py` refreshes the report after
named feature assessment. The reader checks the evidence schema, identity,
stream sequence, complete JSONL lines, CPU intervals, GPU intervals, reference
frames/actions, allocation ledger, supervisor counts, complete validation and
timed checkpoints. A damaged tail stays in the raw archive and cannot become a
sample. Raw integer nanoseconds remain in the streams and in each reported
population's `samples_ns`; measured zero remains zero.

The report keeps state correctness, rendering correctness, visual quality,
numeric validity, schedule completion, qualified workload completion,
CPU/GPU/resource availability,
population qualification, calibration, responsiveness, capacity, termination,
interactive attempt status, endpoint eligibility and implementation acceptance
separate. Ordinary frames include the named moving window and exclude edit
frames. Startup is launch to first usable frame return. The measured interval
is first measured frame begin to last measured frame end; warm-up and teardown
do not count. Percentiles use nearest rank. An ordinary gate requires at least
1,000 ordinary frames and ten measured seconds in that attempt; an applicable
edit percentile requires 100 accepted edits in that attempt. Thresholds are
the accepted limits in [issue #39](https://github.com/aivv73/bend-voxel/issues/39#issuecomment-5858595531).

An optional calibration record may be supplied with `--calibration`, or placed
in the archive as `calibration.json`. It has schema `megascene-evidence/1`, an
explicit status (`pass`, `not_executed`, `insufficient`, `noisy`, `failed`, or
`inapplicable`), a reference, and a `scope` object matching the exact case,
preset, seed, threads, resolution, profile, schedule, diagnostic, control and
fragment budget. A passing status requires a nonempty reference and matching
scope. This reader consumes the result of the separate calibration protocol;
it does not run or validate that protocol. Calibration-off controls cannot
qualify an interactive attempt. The runner currently emits no calibration pass
by itself.

A correctly completed but slow attempt can retain capacity evidence. Missing
GPU intervals leave CPU values measured, while withholding a complete
interactive attempt. One cut stays edit-population inconclusive. A passing
attempt is only one observation; a confirmed endpoint still needs the separate
repetition and search rules. Synthetic reports exercise the classifier but are
excluded from measured searches. A truthful failure report does not complete
the full implementation acceptance matrix.

[Report verification](validation/megascene-report/README.md) includes synthetic
outcomes and retained static/localized attempt examples.
