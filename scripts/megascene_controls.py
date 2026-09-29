"""Source-level coupling record for the accepted terrain pressure controls."""

from collections import Counter

from megascene_recipe import generate, volume


def source_effects(config, transformed):
    baseline = generate(config["preset"], int(config["seed"]))

    def summary(owners):
        boxes = [box for owner in owners for box in owner.boxes]
        materials = Counter()
        for box in boxes:
            materials[str(box.material)] += volume(box)
        return {"cells": str(sum(materials.values())),
                "cells_by_material": {str(m): str(materials[str(m)]) for m in range(1, 6)},
                "owners": str(len(owners)), "source_boxes": str(len(boxes)),
                "bounds_cells": {"lo": [str(min(box.lo[k] for box in boxes)) for k in range(3)],
                                 "hi": [str(max(box.hi[k] for box in boxes)) for k in range(3)]}}

    before, after = summary(baseline), summary(transformed)
    return {"control": config["control"], "baseline_source": before,
            "control_source": after, "added_cells": str(int(after["cells"])-int(before["cells"])),
            "source_scope": "actual authored cells/materials/owners/boxes/bounds; production cuboids and exposed surfaces are recorded in inventory.json"}
