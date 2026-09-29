# Bounded Megascene scale search

`scripts/megascene_search.py` coordinates the accepted scale search using the
existing Vulkan runner, report reader, calibration series and campaign timer.
It does not assert an architectural limit. The [handoff](megascene-spec.md) and
linked [search](https://github.com/aivv73/bend-voxel/issues/41#issuecomment-5862387197)
and [limit](https://github.com/aivv73/bend-voxel/issues/39#issuecomment-5858595531)
decisions define the policy.

```sh
python3 scripts/megascene_search.py \
  --archive "$HOME/megascene-campaign" \
  --work "$PWD/build/megascene/search" \
  --dispatch-limit 1
```

The archive must be durable and outside `build`, `dist` and `tmp`. The example
dispatches one complete primary candidate, including its independent reference
and validation replay. `--dispatch-limit` bounds only this invocation; it does
not qualify a partial attempt. Resume the saved search with a declared addition
to the shared campaign allowance:

```sh
python3 scripts/megascene_search.py \
  --archive "$HOME/megascene-campaign" \
  --work "$PWD/build/megascene/search" \
  --additional-allowance 600
```

Without `--dispatch-limit`, the search visits every eligible six-thread primary
case at each attainable coarse scale, breadth first. Growth is by square area
under the current `q=2..5` admission cap. It then repeats consequential points,
refines a confirmed nonadjacent bracket at an attainable area midpoint, runs
the declared case-specific small-scale controls when a main result needs
diagnosis, and checks a consequential boundary with seed 46 and one/twelve
threads when one exists. Diagnostics keep their own schedule and validation
identity. The supported-scale cap is an admission policy, not a physical limit.

The append-only `search/search.jsonl` is the chronological record of proposals,
attempts, stops and explicit resumes. `search/state.json` summarizes confirmed
and ordinary observations, separate interactive, time-budget and observed
capacity bounds, nonmonotonic or unstable points, actual inventories and untested
settings. `search/series/*.json` retains each exact configuration's attempts and
outcomes. The shared `campaign.json` accounts for build, validation, attempt and
idle time. A pending proposal left by an interruption is recovered from its
retained output if possible, and is otherwise recorded as an incomplete attempt.
No completed observation is overwritten or automatically rerun.

Static search attempts request the runner's separate opening capture. Review
the archived capture with `scripts/megascene_review.py --bundle ARCHIVE
--assessments ANSWERS.json --reviewer NAME`. The input uses
`megascene-feature-assessments/1` with `views.opening` entries for `building
silhouettes`, `span silhouettes` and `major shadows`; each gives `geometry`
(`correct` or `incorrect`) and `readability` (`readable`, `insufficient` or
`unassessable`). Other cases use their existing named feature review process.
On explicit resume, the search reclassifies archived attempts after review or
calibration evidence changes, appending a reassessment event while retaining
the original attempt record. Missing review cannot establish an endpoint.

Each targeted diagnostic also gets a `search/comparisons/*.json` assessment.
The existing control or schedule comparison checks verify actual changed work
and separate validation identities when both timed bundles are complete. A
missing baseline or incomplete comparison remains explicit and inconclusive.

An endpoint needs three independent matching process outcomes. An explicit
allocation failure gets at most one diagnostic retry, with two matching
observations required for its observed failure endpoint. Attempts must have the
same frozen schedule, input bytes, worker, scope and achieved initial inventory.
Synthetic records cannot establish measured endpoints. An ordinary failure,
deadline, resource reserve, monitoring loss, fragment-budget rejection, unsupported
numeric request or unexplained signal is never reported as physical exhaustion.
Missing calibration leaves affected interactive observations unqualified; the
search consumes a matching `calibration-series/<case>-<preset>-<threads>/calibration.json`
from the archive when present and reassesses a claimed calibration pass against
its retained controls. Each result remains conditional on its case, seed, thread
count, resolution, profile, budget and frozen schedule.

Deterministic controlled-worker tests cover ordering, repetitions, mixed causes,
nonmonotonicity, diagnostics and resume. Set `MEGASCENE_VULKAN_TEST=1` for the
bounded short static integration test. That short run checks real dispatch and
archiving only; its frame population cannot qualify a benchmark endpoint.
