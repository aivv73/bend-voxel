# Megascene terrain pressure controls

Issue #59 adds four distinct replay configurations at small/seed 45/1920 x
1080/full geometry/six threads. Each uses the existing fresh-process runner,
complete 120 warm-up plus 3,600 measured frame schedule, separate validation
replay, checkpoint identity and archived runtime. The controls are selected by
`--diagnostic` and retain the six primary cases and proxy diagnostics unchanged.

| Case | Command options | Frozen schedule |
| --- | --- | --- |
| Spread | `--case static --diagnostic spread` | `spread-static-v1` |
| Material static | `--case static --diagnostic material-detail` | `material-detail-static-v1` |
| Material cut | `--case localized --diagnostic material-detail` | `material-detail-localized-v1` |
| Surface | `--case static --diagnostic surface-detail` | `surface-detail-static-v1` |

For each row, add distinct `--output` and durable `--archive` paths:

```sh
python3 scripts/megascene.py --case static --diagnostic spread \
  --preset small --seed 45 --threads 6 --resolution 1920x1080 \
  --profile full --archive "$HOME/megascene-controls" \
  --output build/megascene/controls/spread
```

Spread spaces 320-cell neighborhoods 640 cells apart in a centered 960-cell
envelope. Three pairs of 320 x 2 x 1 protected and 320 x 2 x 23 removable
connector boxes occupy the open gaps, adding 46,080 cells. The connectors
join all four patches into the same connected terrain owner. Ground coverage
extends to the new envelope plus the fixed 8 m border.

Material detail splits removable terrain into local four-cell X bands, with
material 2 on even bands and 5 on odd bands. It preserves cell occupancy,
protected material, bounds, structure shapes and owner IDs. The localized
cut keeps its target at local `(160,24,160)` and removes 16 cells across two
material bands. Its pre-edit camera aims one cell into the even band to avoid
an ambiguous ray along their shared boundary.

Surface detail removes 64 disjoint 2 x 2 x 2 pits from each neighborhood at
the specified X/Z coordinates and Y=[22,24), removing exactly 512 cells per
neighborhood. The source and actual terrain remain anchored and connected.

`inputs.json` contains the exact transformed boxes. `numeric_bounds.control_effects`
records baseline and changed source cell, material, owner, box and bounds
inventories. `validation/inventory.json` records achieved occupancy, material,
production cuboids, exposed surfaces, vertices and bounds, including a
`control_comparison` section. The separate validation and timed attempt carry
the frozen schedule, capture and checkpoint identities. Source invariants have
independent tests; a nominal control label or absent Vulkan replay cannot pass
completion or benchmark qualification. Current runner results remain
unqualified development observations until the accepted review and calibration
gates are satisfied.

Run a separate baseline timed replay for `static` and `localized` as applicable. The
comparison command checks both archived timed attempts and their complete validation
identities, then writes actual deltas for cells, protected cells, cuboids,
exposed surfaces, vertices, material inventories and bounds:

```sh
python3 scripts/megascene_compare_controls.py \
  --baseline /path/to/baseline/attempt --control /path/to/control/attempt \
  --output /path/to/comparison.json
```

The comparison status describes verified work differences. It does not qualify
performance or visual quality.

The [issue #59 evidence index](validation/megascene-controls/README.md) records
the completed control and baseline Vulkan attempts, comparison reports and
capture previews.
