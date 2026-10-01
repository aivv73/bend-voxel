"""Diagnostic on/off evidence; an off control never qualifies an endpoint."""
import argparse
from pathlib import Path

from megascene_evidence import run as _run
from megascene_inventory import read_json
from megascene_report import read_stream

DISABLED = ("intermediate_checkpoints", "detailed_inventory_transitions", "stage_timing",
            "gpu_queries", "ordinary_logging")


def _policy(operation, payload):
    return _run(operation, payload, module="evidence_calibration")


def verify_peer_validation(config, manifest, archive):
    from megascene_checkpoints import applicable, identity, verify_evidence
    from megascene_validation import verify_host_artifacts
    peer = Path(config["calibration_peer_validation"]).expanduser().resolve()
    peer_manifest = read_json((peer / "manifest.json").read_text())
    request = {"config": config, "peer_manifest": peer_manifest, "source": str(peer)}
    _policy("peer_workload", request)
    request.update(peer_identity=identity(peer_manifest, peer, peer_manifest["effective"]),
                   own_identity=identity(manifest, archive, config))
    required = {"validation.json"} | {a["path"] for a in peer_manifest.get("evidence", [])
                                     if a["path"].startswith("validation/")}
    request["has_validation_files"] = any(p.startswith("validation/") for p in required)
    _policy("peer_binding", request)
    verify_evidence(peer_manifest, peer, required)
    validation = read_json((peer / "validation.json").read_text())
    applicable(validation, request["peer_identity"])
    verify_host_artifacts(validation)
    request["validation"] = validation
    return _policy("peer_validation", request)


def reference_sequence(records, frozen):
    return tuple(_policy("reference_sequence", {"records": records, "frozen": frozen}))


def off_result(config, archive, manifest, validation, supervised, cpu, problems):
    frozen = read_json((archive / "schedule.json").read_text())
    reference, ref_errors = read_stream(archive / "reference.jsonl", manifest)
    resource, resource_errors = read_stream(archive / "resources.jsonl", manifest)
    allocations, allocation_errors = read_stream(archive / "allocations.jsonl", manifest)
    errors = list(problems) + ref_errors + resource_errors + allocation_errors
    if manifest.get("evidence"):
        try:
            from megascene_checkpoints import verify_evidence
            verify_evidence(manifest, archive, {"summary.json", "validation.json", "cpu.jsonl",
                "reference.jsonl", "resources.jsonl", "allocations.jsonl", "supervision.json"})
        except (ValueError, KeyError, OSError) as exc:
            errors.append(str(exc))
    gpu = archive / "gpu.jsonl"
    return _policy("off_result", {
        "config": config, "manifest": manifest, "validation": validation,
        "supervised": supervised, "cpu": cpu, "frozen": frozen, "reference": reference,
        "resource": resource, "allocations": allocations, "errors": errors,
        "resource_errors": resource_errors, "allocation_errors": allocation_errors,
        "gpu_nonempty": gpu.exists() and bool(gpu.stat().st_size),
    })


def compare_modes(off_path, on_path):
    from megascene_checkpoints import identity, verify_evidence
    off_path, on_path = Path(off_path), Path(on_path)
    off_manifest, on_manifest = (read_json((p / "manifest.json").read_text())
                                 for p in (off_path, on_path))
    request = {"off_manifest": off_manifest, "on_manifest": on_manifest}
    _policy("pair_kinds", request)
    for root, manifest in ((off_path, off_manifest), (on_path, on_manifest)):
        identity(manifest, root, manifest["effective"])
        verify_evidence(manifest, root, {"summary.json", "validation.json", "cpu.jsonl",
            "reference.jsonl", "resources.jsonl", "allocations.jsonl", "supervision.json"})
    request["off_summary"], request["on_summary"] = (
        read_json((p / "summary.json").read_text()) for p in (off_path, on_path))
    _policy("pair_header", request)
    request["off_ref"], request["off_ref_errors"] = read_stream(off_path / "reference.jsonl", off_manifest)
    request["on_ref"], request["on_ref_errors"] = read_stream(on_path / "reference.jsonl", on_manifest)
    _policy("pair_reference", request)
    request["off_cpu"], request["off_cpu_errors"] = read_stream(off_path / "cpu.jsonl", off_manifest)
    request["on_cpu"], request["on_cpu_errors"] = read_stream(on_path / "cpu.jsonl", on_manifest)
    return _policy("compare_modes", request)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--off", required=True)
    p.add_argument("--on", required=True)
    args = p.parse_args()
    import json
    print(json.dumps(compare_modes(args.off, args.on), sort_keys=True))
