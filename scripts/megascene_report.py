#!/usr/bin/env python3
"""Classify a retained Megascene attempt from its raw evidence.

This reader never combines attempts or promotes an observation to an endpoint.
It can be called by the runner after validation/review, or directly on an
archived attempt with ``--bundle``. Synthetic bundles remain synthetic.
"""
import argparse
from pathlib import Path

from megascene_inventory import read_json, require
from megascene_evidence import run as evidence

SCOPE_KEYS = ("case", "preset", "seed", "threads", "resolution", "profile",
              "schedule", "diagnostic", "control", "fragment_budget")


def distribution(values):
    return evidence("distribution", list(values))


def checked_object(value, kind):
    return evidence("checked_object", dict(value=value, kind=kind))


def read_stream(path, manifest):
    """Return the valid committed prefix and every detected stream problem."""
    if not path.is_file():
        return [], [path.name+" missing"]
    records, parse_error = [], None
    for raw in path.read_bytes().splitlines(keepends=True):
        try:
            require(raw.endswith(b"\n"), "truncated "+path.name+" tail")
            records.append(read_json(raw.decode("utf-8")))
        except (ValueError, KeyError, TypeError, UnicodeError) as exc:
            parse_error = str(exc)
            break
    result = evidence("stream", dict(name=path.name, manifest=manifest, records=records, parse_error=parse_error))
    return result["records"], result["errors"]


def calibration_result(value, config, attempt_kind):
    return evidence("calibration_result", dict(value=value, config=config, attempt_kind=attempt_kind))


def classify(summary, manifest, cpu, cpu_errors=(), gpu_errors=(), resources=(), resource_errors=(),
             allocations=(), allocation_errors=(), reference=(), reference_errors=(),
             validation=None, review=None, calibration=None, comparison=None, schedule=None):
    return evidence("finalize", evidence("prepare", locals()))


def report_bundle(bundle, calibration=None):
    """Public read-only report boundary for a retained attempt directory."""
    bundle = Path(bundle)
    manifest = checked_object(read_json((bundle/"manifest.json").read_text()),"manifest")
    summary = checked_object(read_json((bundle/"summary.json").read_text()),"summary")
    if manifest["attempt_kind"] == "calibration_off":
        from megascene_calibration import off_result
        from megascene_static import read_stream as read_cpu
        cpu, errors = read_cpu(bundle/"cpu.jsonl",manifest["attempt_id"])
        validation = read_json((bundle/"validation.json").read_text()) if (bundle/"validation.json").is_file() else None
        return {**summary, **off_result(manifest["effective"],bundle,manifest,validation,
                          read_json((bundle/"supervision.json").read_text()),cpu,errors)}
    cpu, cpu_errors = read_stream(bundle/"cpu.jsonl",manifest)
    from megascene_gpu import read_stream as read_gpu
    gpu, gpu_errors = read_gpu(bundle/"gpu.jsonl",manifest)
    resources, resource_errors = read_stream(bundle/"resources.jsonl",manifest)
    allocations, allocation_errors = read_stream(bundle/"allocations.jsonl",manifest)
    reference, reference_errors = read_stream(bundle/"reference.jsonl",manifest)
    from megascene_gpu import summarize
    frozen=read_json((bundle/'schedule.json').read_text()) if (bundle/'schedule.json').exists() else None
    gpu_result = summarize(gpu,gpu_errors,[r for r in cpu if r["record_type"] == "frame"],manifest["effective"],frozen)
    summary = dict(summary)
    summary["gpu_execution"] = gpu_result
    def optional(name):
        path = bundle/name
        return checked_object(read_json(path.read_text()),name) if path.is_file() else None
    if calibration is None:
        calibration = optional("calibration.json")
    from megascene_performance import enabled
    if enabled(manifest['effective']) and calibration is not None:
        from megascene_checkpoints import identity
        from hashlib import sha256
        actual=identity(manifest,bundle,manifest['effective'])['artifacts']
        if evidence("calibration_binding", dict(calibration=calibration, artifacts=actual)):
            reference_path=Path(calibration['reference'])
            require(sha256(reference_path.read_bytes()).hexdigest()==calibration.get('reference_sha256'),
                    'performance calibration assessment bytes mismatch')
            assessment=read_json(reference_path.read_text())
            evidence("calibration_assessment", dict(assessment=assessment, calibration=calibration))
    return classify(summary,manifest,cpu,cpu_errors,gpu_result["errors"],resources,resource_errors,
                    allocations,allocation_errors,reference,reference_errors,
                    optional("validation.json"),optional("review.json"),calibration,optional("comparison.json"),
                    optional("schedule.json"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle",required=True)
    parser.add_argument("--calibration",help="explicit calibration status/reference/scope JSON")
    args = parser.parse_args()
    cal = read_json(Path(args.calibration).read_text()) if args.calibration else None
    import json
    print(json.dumps(report_bundle(args.bundle,cal),sort_keys=True,indent=2))


if __name__ == "__main__":
    main()
