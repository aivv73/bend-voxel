#!/usr/bin/env python3
"""Compare independently validated terrain-control work with a matching baseline."""

import argparse
from pathlib import Path

from megascene_inventory import canonical, read_evidence
from megascene_evidence import run
from megascene_checkpoints import identity, verify_evidence


def load(path):
    manifest = read_evidence(path/"manifest.json")
    validation = read_evidence(path/"validation.json")
    verify_evidence(manifest, path, ("summary.json", "validation.json", "validation/inventory.json"))
    summary = read_evidence(path/"summary.json")
    inventory = read_evidence(path/"validation/inventory.json")
    run("controls_load", {"manifest": manifest, "summary": summary,
                          "validation": validation, "inventory": inventory,
                          "expected_identity": identity(manifest, path, manifest["effective"])},
        "evidence_comparison")
    return manifest,validation,inventory


def compare(baseline, control):
    base_manifest,base_validation,base = load(Path(baseline))
    variant_manifest,variant_validation,variant = load(Path(control))
    return run("controls", {"baseline": [base_manifest, base_validation, base],
                            "variant": [variant_manifest, variant_validation, variant]},
               "evidence_comparison")


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
