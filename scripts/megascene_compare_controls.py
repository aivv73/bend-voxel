#!/usr/bin/env python3
"""Compare independently validated terrain-control work with a matching baseline."""

import argparse
from pathlib import Path

from megascene_inventory import SCHEMA, canonical, integer, read_evidence, require
from megascene_checkpoints import identity, verify_evidence


def load(path):
    manifest = read_evidence(path/"manifest.json")
    validation = read_evidence(path/"validation.json")
    verify_evidence(manifest, path, ("summary.json", "validation.json", "validation/inventory.json"))
    summary = read_evidence(path/"summary.json")
    inventory = read_evidence(path/"validation/inventory.json")
    require(summary["attempt_kind"] == "development_observation" and not summary["synthetic"] and
            summary["attempt_id"] == manifest["attempt_id"] and
            all(summary[name]["status"] == "pass" for name in ("state_correctness","schedule_completion","rendering_correctness")),
            "complete nonsynthetic timed Vulkan attempt required")
    require(validation["status"] == "pass" and not validation["synthetic"], "complete nonsynthetic validation required")
    require(validation["identity"] == identity(manifest,path,manifest["effective"]), "validation/runtime identity mismatch")
    require(inventory["validation"] == "validation.json", "inventory validation link missing")
    return manifest,validation,inventory


def compare(baseline, control):
    base_manifest,base_validation,base = load(Path(baseline))
    variant_manifest,variant_validation,variant = load(Path(control))
    a,b = base_manifest["effective"],variant_manifest["effective"]
    require(a["control"] is None and b["control"] in ("spread","material-detail","surface-detail"),
            "expected baseline and terrain control")
    for key in ("case","preset","seed","threads","resolution","profile","fragment_budget","warmup","frames"):
        require(a[key] == b[key], "baseline/control mismatch: "+key)
    require(a["schedule"] == a["case"]+"-v1" and b["schedule"] == b["control"]+"-"+b["case"]+"-v1",
            "unexpected frozen schedule identities")
    require(base_manifest["attempt_id"] != variant_manifest["attempt_id"] and
            base_validation["attempt_id"] != variant_validation["attempt_id"], "reused attempt identity")
    require(a["preset"] == "small" and a["seed"] == "45" and a["threads"] == "6" and
            a["resolution"] == "1920x1080" and a["profile"] == "full", "unsupported control comparison")
    if b["control"] == "material-detail":
        require(b["case"] in ("static","localized"), "unsupported material control case")
    else:
        require(b["case"] == "static", "unsupported control case")
    effects = variant["control_comparison"]
    require(effects["control"] == b["control"] and effects["control_source"]["cells"] == variant["cells"]
            and effects["baseline_source"]["cells"] == base["cells"], "source/achieved inventory mismatch")
    metrics = ("cells","protected_cells","cuboids","surface_rectangles","exposed_area_cell_faces","vertices")
    delta = {key: str(integer(variant[key],signed=False)-integer(base[key],signed=False)) for key in metrics}
    require(base["bodies"]["initial_owners"] == variant["bodies"]["initial_owners"] == "21",
            "terrain control changed owner count")
    if b["control"] == "spread":
        require(delta["cells"] == "46080" and integer(delta["protected_cells"],signed=True) == 1920 and
                variant["generation_envelope_cells"]["lo"] == ["-480","0","-480"] and
                integer(delta["cuboids"],signed=True) > 0 and
                integer(delta["surface_rectangles"],signed=True) > 0, "spread work mismatch")
    elif b["control"] == "material-detail":
        require(delta["cells"] == delta["protected_cells"] == "0" and
                base["generation_envelope_cells"] == variant["generation_envelope_cells"] and
                base["occupied_bounds_cells"] == variant["occupied_bounds_cells"] and
                base["cells_by_material"] != variant["cells_by_material"] and
                base["exposed_area_by_material_cell_faces"] != variant["exposed_area_by_material_cell_faces"] and
                integer(delta["cuboids"],signed=True) > 0 and
                integer(delta["surface_rectangles"],signed=True) > 0, "material control invariants mismatch")
    else:
        require(delta["cells"] == "-2048" and delta["protected_cells"] == "0" and
                base["generation_envelope_cells"] == variant["generation_envelope_cells"] and
                base["occupied_bounds_cells"] == variant["occupied_bounds_cells"] and
                integer(delta["exposed_area_cell_faces"],signed=True) > 0 and
                integer(delta["cuboids"],signed=True) > 0 and
                integer(delta["surface_rectangles"],signed=True) > 0, "surface control invariants mismatch")
    return {"schema": SCHEMA,"record_type":"terrain_control_comparison", "status":"pass",
            "scope":"validated achieved work comparison; unqualified development observations",
            "control":b["control"],"case":b["case"],
            "baseline":{"attempt_id":base_manifest["attempt_id"],"validation_id":base_validation["attempt_id"],
                        "schedule_sha256":base_manifest["worker_environment"]["MEGASCENE_SCHEDULE_SHA256"]},
            "variant":{"attempt_id":variant_manifest["attempt_id"],"validation_id":variant_validation["attempt_id"],
                       "schedule_sha256":variant_manifest["worker_environment"]["MEGASCENE_SCHEDULE_SHA256"]},
            "delta":delta,"materials":{"baseline":base["cells_by_material"],"variant":variant["cells_by_material"]},
            "exposed_area_by_material_cell_faces":{"baseline":base["exposed_area_by_material_cell_faces"],
                "variant":variant["exposed_area_by_material_cell_faces"]},
            "bounds":{"baseline":base["occupied_bounds_cells"],"variant":variant["occupied_bounds_cells"]},
            "source_effects":effects}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline",type=Path,required=True)
    parser.add_argument("--control",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    args = parser.parse_args()
    result = compare(args.baseline,args.control)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_bytes(canonical(result)+b"\n")
    print(args.output)


if __name__ == "__main__":
    main()
