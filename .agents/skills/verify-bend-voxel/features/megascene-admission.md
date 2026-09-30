# Megascene district admission

The public Megascene CLI constructs the actual sparse district and validates its initial world and geometry before any rendering. Follow [the admission guide](../../../../docs/megascene-admission.md) and [numeric scale/search rules](../../../../docs/megascene-search.md).

## Sub-features

- `megascene-admission` generates actual Bend world trees, owners, materials, faces and vertices.
- `megascene-initial-reference` checks disjointness, connectivity, anchors, arithmetic and independent geometry references.
- `megascene-request-rejection` preserves malformed or unsupported requests as rejected evidence rather than silently changing settings.

## How to get to it (user POV)

Run `python3 scripts/megascene.py --case admission` from the repository root, choosing an admitted scale, seed, thread count and new output. This CLI needs no desktop window or Vulkan device.

## Driving it with megascene.py

- **Check the compiler.** Require `bend version` to report `bend 2.0.34`. Read `bend guide` before using Bend. Use the repo's existing toolchain; do not upgrade it as verification scaffolding.
- **Construct the district.** Run `python3 scripts/megascene.py --case admission --preset small --seed 45 --threads 6 --campaign "$MEGASCENE_ARCHIVE" --output "build/verification/${VERIFY_RUN_ID}-megascene-admission"`. Read the existing campaign ledger first; admission can charge the same persistent allowance as Vulkan work.
- **Read the result.** Require exit code zero and passing `admission`, initialization-scoped `state_correctness`, and `numeric_validity` in `summary.json`. Inspect the independent geometry results in `validation.json`, `inventory.json`, generated inputs, manifest hashes and worker logs. Small initially has 21 anchored owners and 10,503,360 occupied cells; large has 81 and 42,096,576. Totals alone do not replace the independent checks.
- **Retain and stop.** The owned worker exits on completion. Keep the complete output bundle and campaign record after cleanup.

## Gotchas

- Seeds are 45/46; thread counts are 1/6/12. Small/large are 64/128 m. Supported integer scales use `--side-m 32*q`; consult the scale guide before selecting one.
- Admission rejects rendering, diagnostic, capture and replay flags. A rejection is evidence of the guard, never a district/rendering pass.
- Initialization checks do not establish later cuts, motion, Vulkan rendering, visual readability, calibration or capacity.
- Geometry depending on `@unsafe` is runtime/reference evidence. Keep safe laws and proof checks separate.
