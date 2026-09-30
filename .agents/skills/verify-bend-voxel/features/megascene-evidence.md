# Megascene evidence, review and recovery

Megascene retains actual runtime bytes, frozen inputs, supervised streams and captures in a durable attempt bundle. Follow [supervision](../../../../docs/megascene-supervision.md), [reports](../../../../docs/megascene-report.md), [visual assessment](../../../../docs/megascene-traversal.md#captures-and-review) and [reproduction](../../../../docs/megascene-reproduction.md).

Use [the evidence ladder](../references/megascene-proof-ladder.md) to determine what these records support. Preserve each public outcome and its scope; a passing short prefix does not advance to complete-case, matrix or confirmed-bound claims.

## Sub-features

- `megascene-retention` preserves successful and failed prefixes with source/runtime hashes, process status and resource evidence.
- `megascene-report` recomputes separate correctness, completion, visual, population and qualification outcomes.
- `megascene-visual-review` binds named geometry/readability assessments to original capture hashes.
- `megascene-recovery` restores a static/localized archive into new validation and timed attempts without generating replacement inputs.

## How to get to it (user POV)

Run a public Megascene case with explicit `--archive` and a new `--output`. Read the local manifest's `reproduction.archive` to locate the authoritative retained attempt. Use the public report, review and reproduction CLIs on that archived directory.

## Driving it with Megascene evidence tools

- **Locate and verify.** Require the durable path recorded by the manifest to exist after the runner exits. Retain runtime/source/shader/library hashes, invocation, frozen schedule, validation/comparison records, original CPU/GPU/resource/reference/allocation streams, captures and termination. The root `campaign.json` and lock must remain intact.
- **Recompute classification.** Set `MEGASCENE_ATTEMPT` to the exact `reproduction.archive` path read from the current manifest. Run `python3 scripts/megascene_report.py --bundle "$MEGASCENE_ATTEMPT"`. Compare its separate outcomes to the retained summary and read any first mismatch or incomplete-prefix reason. Do not modify the original streams or invent a missing measurement.
- **Review complete replay features.** Inspect every original view and feature listed in the archived `review.json`. Write a complete assessments JSON with schema `megascene-feature-assessments/1`, a `views` map keyed by those exact view/feature names, and each entry's `geometry` (`correct`/`incorrect`) and `readability` (`readable`/`insufficient`/`unassessable`). Add a note for every nonpassing entry. Run `python3 scripts/megascene_review.py --bundle "$MEGASCENE_ATTEMPT" --assessments "build/verification/${VERIFY_RUN_ID}-megascene-assessments.json" --reviewer "Codex visual review"`. The tool retains input and updates review, summary and manifest hashes. Keep an occluded overview's honest assessment; only an explicitly linked supplementary view can satisfy the same feature's readability.
- **Review the static smoke capture.** Static's separate `captures/opening.ppm` uses a single-view review shape. Read `schedule.json` → `review_views` for its exact required names: opening's building silhouettes, span silhouettes and major shadows. Inspect the original image and submit all three through the same assessments schema and review command above. The tool verifies the original capture hash and updates official classification. Read the archived summary after review; the local copy is older. This review covers the static opening, not traversal cavities, picking overlays or destruction views.
- **Recover only when required.** For a static/localized reproduction request, use `python3 scripts/megascene.py --reproduce-from "$MEGASCENE_ATTEMPT" --archive "$MEGASCENE_REPRODUCTION_ARCHIVE" --output "build/verification/${VERIFY_RUN_ID}-megascene-reproduction"`. Set the destination to the established durable reproduction campaign, checking its existing allowance first. Recovery takes settings from the source and runs fresh validation/timing; require passing reproduction comparisons and retained source evidence. It does not compare timings for equality.
- **Verify cleanup.** Read `supervision.json` termination, exit/signal, completed reference prefix and final durability barrier. Check recorded owned workers/monitors have exited. Keep archives, local reports, assessment inputs and damaged tails after teardown. Stop only your own runner on interruption and let its supervisor clean up its groups.

## Gotchas

- The initial campaign allowance is 7200 wall-clock seconds, including build, validation, captures, retries and idle time between invocations. New output directories do not reset it. Do not switch archives or add allowance to evade exhaustion; explicit additional time needs authorization.
- Required monitor, reserve, persistence or deadline failures cannot pass schedule completion. A signal alone does not establish memory exhaustion.
- Pending/missing views leave visual quality inconclusive; incorrect geometry and insufficient readability are separate failures. Synthetic report fixtures establish validator behavior only.
- At least 1000 ordinary frames and ten measured seconds are required for the ordinary population gate; applicable edit percentiles require 100 accepted edits in one attempt. Calibration and endpoint repetition/search remain separate.
- Archive relocation preserves application bytes and frozen inputs, but the host Vulkan driver, kernel and X11 session remain platform dependencies. Runtime/native evidence never becomes a formal proof of `@unsafe` definitions.
