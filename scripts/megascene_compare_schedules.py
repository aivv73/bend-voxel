#!/usr/bin/env python3
"""Compare a completed shortened schedule with its validated baseline."""

import argparse
import hashlib
from pathlib import Path

from megascene_checkpoints import verify_evidence
from megascene_inventory import canonical, digest, read_json, require
from megascene_evidence import run


def load(path):
    root=Path(path)
    manifest=read_json((root/'manifest.json').read_text())
    verify_evidence(manifest,root,('summary.json','validation.json','validation/inventory.json','cpu.jsonl'))
    artifact=next(a for a in manifest['artifacts'] if a['path']=='schedule.json')
    schedule_path=root/'schedule.json'
    require(hashlib.sha256(schedule_path.read_bytes()).hexdigest()==artifact['sha256'],
            'stale frozen schedule')
    summary=read_json((root/'summary.json').read_text())
    validation=read_json((root/'validation.json').read_text())
    inventory=read_json((root/'validation/inventory.json').read_text())
    frozen=read_json(schedule_path.read_text())
    with (root / "cpu.jsonl").open() as stream:
        records = [read_json(line) for line in stream]
    completion = run("schedule_load", {"manifest": manifest, "summary": summary,
        "validation": validation, "inventory": inventory, "frozen": frozen,
        "records": records}, "evidence_comparison")
    return manifest,summary,validation,inventory,frozen,completion


def geometry(payload):
    return run("geometry", payload, "evidence_comparison")


def removed(frozen):
    return [tuple(row) for row in run("removed", frozen, "evidence_comparison")]


def compare(baseline,variant):
    left, right = load(baseline), load(variant)
    result = run("schedules", {"baseline": left, "variant": right}, "evidence_comparison")
    witnesses = result.pop("_witnesses")
    result["baseline"]["final_geometry_sha256"] = digest(witnesses["base_geometry"])
    result["baseline"]["removed_cell_set_sha256"] = digest(witnesses["base_removed"])
    result["variant"]["final_geometry_sha256"] = digest(witnesses["variant_geometry"])
    result["variant"]["removed_cell_set_sha256"] = digest(witnesses["variant_removed"])
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline',type=Path,required=True)
    p.add_argument('--variant',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args()
    result=compare(args.baseline,args.variant)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_bytes(canonical(result)+b'\n')
    print(args.output)


if __name__=='__main__': main()
