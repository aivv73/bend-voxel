# Megascene schedule generation

`src/megascene_schedule.bend` owns the generated frame phases, cut times,
targets, camera routes, rays, review frames, and checkpoint names. Its route,
cut, history, proxy, and policy modules emit a schedule header and ordered
frame/action records. Short history variants emit omitted actions as reference
records so the independent geometry checks can still validate the full camera
track.

The Python adapters decode those records and annotate them with independent
sparse geometry, picking, removal, connectivity, and motion evidence. The
performance adapter supplies reference settlement boundaries to Bend, which
selects the frame populations and policy flags. Fixed Python timing constants
remain only in independent admission and replay checks.

`src/schedule_float.bend` represents binary64 calculations as expressions. Its
native effect evaluates generic arithmetic and libm operations in the specified
order. Explicit `Round32` expressions preserve the original rounding barriers.
The effect also preserves signed zero and the compensated sums and hypot used
by the Python reference. The JavaScript effect fails with an explicit native
backend requirement. Foreign arithmetic is verified by runtime/reference
comparisons and does not constitute a formal proof.

Native replay reads `frame-policy.bin`, `checkpoints.tsv`, and `reviews.tsv`.
The checkpoint and review files preserve name ordering within each frame.
Supplementary camera records carry explicit frame and action numbers, including
support close-ups. Archive identity checks bind all three policy files to the
frozen schedule. Generator cache keys and retained sources include the numeric
effect's C and JavaScript files.

`--validated` and `--runtime-from` require a runtime that supports these tables.
The runner rejects older runtimes before launch. Existing archived bundles
retain their original runtime and environment for the supported reproduction
workflow.

Run `python3 scripts/megascene_schedule_parity.py` to compare complete canonical
schedule and camera/ray hashes against the 84 pre-migration configurations.
The retained matrix covers both seeds, q=2/3/4/5, both traversal/picking route
versions, controls, shortened variants, proxy diagnostics, performance
schedules, and static prefixes. `--capture` requires a new destination and
cannot overwrite the retained baseline.

Run `make test`, `bend PROOF.bend`, and `bend PROOF.bend --verdict` for the project
gates. Supervised Vulkan replay remains a separate runtime check.
