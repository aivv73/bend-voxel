"""Independent sparse canonicalization, replay applicability and mismatch reports.

Native code constructs timed checkpoints. This Python implementation checks their
bytes and compares actual initialization with integer reference geometry. Hashes
are practical runtime evidence, never formal proofs of unsafe/native behavior.
"""
from collections import defaultdict
import hashlib
import re

from megascene_inventory import (SCHEMA, canonical, coordinate, digest, integer,
    plane_sweep, read_json, real, require, surface_actual, surface_reference, verify_vertices,
    occupancy_sweep as occupancy)
from megascene_recipe import Box

CHECKPOINT_SCHEMA = "megascene-checkpoint/1"


def checkpoint_bytes(value):
    def check(v):
        if isinstance(v, str):
            require(re.fullmatch(r"[A-Za-z0-9_./:+-]+", v) is not None, "checkpoint string vocabulary")
        elif isinstance(v, dict):
            for k, item in v.items():
                check(k)
                check(item)
        elif isinstance(v, list):
            for item in v:
                check(item)
        else:
            require(v is None or type(v) is bool, "JSON numeric token in checkpoint")
    check(value)
    require(isinstance(value, dict), "checkpoint payload object required")
    require(value.get("schema") == CHECKPOINT_SCHEMA, "unsupported checkpoint schema")
    return canonical(value)




def strings(v):
    return [strings(item) for item in v] if isinstance(v, (list, tuple)) else str(v)


def surface(planes):
    groups = {}
    for (side, plane), strips in planes.items():
        by_material = defaultdict(list)
        for lo, hi, intervals in strips:
            for start, end, material in intervals:
                by_material[material].append((lo, hi, start, end, material))
        for material, rectangles in by_material.items():
            groups[side, material, plane] = plane_sweep(rectangles)
    return [[str(side), str(material), str(plane), strings(content)]
            for (side, material, plane), content in sorted(groups.items())]


def initial_payload(text, frozen, schedule_hash, config):
    records = [read_json(line) for line in text.splitlines()]
    world, *bodies, end = records
    require(end == {"record_type": "complete"}, "incomplete initial world")
    result, work, all_boxes = [], [], []
    for body in sorted(bodies, key=lambda b: integer(b["id"])):
        boxes = [Box(tuple(map(coordinate, b[:3])), tuple(map(coordinate, b[3:6])), integer(b[6])) for b in body["boxes"]]
        faces = [(tuple(map(coordinate, f[:3])), tuple(map(coordinate, f[3:6])), integer(f[6]), integer(f[7])) for f in body["faces"]]
        all_boxes.extend(boxes)
        actual = surface_actual(faces)
        require(actual == surface_reference(boxes), f"body {body['id']}: exposed surface mismatch")
        verify_vertices(faces, body["vertices"])
        # Preserve signed zero, IDs and revision; allocation/tree order is absent.
        for key in ("offset", "speed"):
            real(body[key])
        result.append({"anchored": body["anchored"], "id": body["id"], "revision": body["revision"],
                       "offset_m": body["offset"], "velocity_m_s": body["speed"],
                       "occupancy": strings(occupancy(boxes)), "surface": surface(actual)})
        work.append({"id": body["id"], "cells": body["cells"], "cuboids": str(len(boxes)),
                     "tree_nodes": body["tree_nodes"], "surface_rectangles": str(len(faces)),
                     "vertices": str(len(body["vertices"])),
                     "protected_cells": str(sum((b.hi[0]-b.lo[0])*(b.hi[1]-b.lo[1])*(b.hi[2]-b.lo[2]) for b in boxes if b.material == 1))})
    occupancy(all_boxes)  # Reject overlapping initial ownership before any union.
    width, height = config["resolution"].split("x")
    value = {"schema": CHECKPOINT_SCHEMA, "bodies": result,
             **{k: world[k] for k in ("budget", "cells", "fragments", "next_id", "removed", "status")},
             "action_outcomes": [], "fixed_step": frozen["fixed_step"], "schedule_sha256": schedule_hash,
             "view": {**frozen["opening"], "width": width, "height": height,
                      "aim": {"kind": "0", "position_m": ["0x00000000"]*3, "radius_m": "0x00000000"}}}
    checkpoint_bytes(value)
    return value, work


def mismatch(expected, actual, path="payload"):
    """First useful field/body mismatch; keep the exact differing values."""
    if type(expected) is not type(actual):
        return {"field": path, "expected": expected, "actual": actual}
    if isinstance(expected, dict):
        for key in sorted(expected.keys() | actual.keys()):
            if key not in expected or key not in actual:
                return {"field": path+"/"+key, "expected": expected.get(key), "actual": actual.get(key), "missing": True}
            diff = mismatch(expected[key], actual[key], path+"/"+key)
            if diff:
                return diff
    elif isinstance(expected, list):
        if len(expected) != len(actual):
            return {"field": path+"/length", "expected": str(len(expected)), "actual": str(len(actual))}
        for i, (a, b) in enumerate(zip(expected, actual)):
            component = "body:"+a["id"] if (path.endswith("/bodies") or path.endswith("/work") or path == "work") and isinstance(a, dict) and "id" in a else str(i)
            diff = mismatch(a, b, path+"/"+component)
            if diff:
                return diff
    elif expected != actual:
        return {"field": path, "expected": expected, "actual": actual}
    return None


def identity(manifest, root, config):
    """Check the actual retrievable bytes, then identify all applicable inputs."""
    artifacts = {}
    for item in manifest["artifacts"]:
        path = root/item["path"]
        require(path.is_file(), f"missing runtime artifact: {item['path']}")
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        require(actual == item["sha256"] and str(path.stat().st_size) == item["size_bytes"],
                f"stale runtime artifact: {item['path']}")
        artifacts[item["path"]] = actual
    require(artifacts and "schedule.json" in artifacts and "runtime/worker" in artifacts, "incomplete runtime artifacts")
    env = manifest["worker_environment"]
    if "MEGASCENE_CHECKPOINT_FILE" in env or "MEGASCENE_REVIEW_FILE" in env:
        from megascene_schedule import checkpoint_bytes, review_bytes, policy_bytes
        frozen = read_json((root/"schedule.json").read_text())
        for name, key, expected in (("checkpoints.tsv", "MEGASCENE_CHECKPOINT_FILE", checkpoint_bytes(frozen)),
                                    ("reviews.tsv", "MEGASCENE_REVIEW_FILE", review_bytes(frozen)),
                                    ("frame-policy.bin", "MEGASCENE_FRAME_POLICY", policy_bytes(frozen))):
            require(env.get(key) == "../"+name and name in artifacts and (root/name).read_bytes() == expected,
                    "runtime plan does not match frozen schedule: "+name)
    from megascene_performance import enabled, admit, policy_bytes
    if enabled(config):
        admit(config)
        frozen=read_json((root/'schedule.json').read_text())
        expected_policy=policy_bytes(frozen)
        require('frame-policy.bin' in artifacts and (root/'frame-policy.bin').read_bytes()==expected_policy,
                'performance policy does not match frozen schedule')
        env=manifest['worker_environment']
        require(env.get('MEGASCENE_QUERY_PAIRS')==str(len(frozen['frames'])) and
                env.get('MEGASCENE_FRAME_POLICY')=='../frame-policy.bin', 'performance runtime counts mismatch')
        if config['case']=='history':
            require(env.get('MEGASCENE_HISTORY_OVERVIEW')==frozen['performance_protocol']['overview_frame'],
                    'performance runtime overview mismatch')
    return {"artifacts": artifacts, "configuration": {k: v for k,v in config.items()
            if k not in {"archive", "capture_opening", "validation_only", "validated", "runtime_from", "calibration_peer_validation"}},
            "worker_command": manifest["worker_command"], "worker_environment": manifest["worker_environment"],
            "runtime": manifest["runtime"], "constants": manifest["constants"]}


def verify_evidence(manifest, root, names):
    entries = {entry["path"]: entry for entry in manifest["evidence"]}
    require(set(names) <= entries.keys(), "incomplete archived validation evidence")
    for name in names:
        entry = entries[name]
        path = root/name
        require(path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == entry["sha256"]
                and str(path.stat().st_size) == entry["size_bytes"], "stale validation evidence: "+name)


def checkpoint_catalog(frozen):
    return {point["name"]: point["frame"] for point in frozen["required_checkpoints"]}


def audit(records, frozen, expected, expected_work, complete, thorough=False):
    """Verify every replay frame, or the timed checkpoint catalog, with evidence."""
    if frozen["schedule_id"] in ("history-perf-v2", "history-v1", "history-12-v1", "history-48-v1", "fill-history-v1", "body-rich-history-v1"):
        from megascene_history import audit as audit_history
        return audit_history(records, frozen, expected, expected_work, complete, thorough)
    if frozen["schedule_id"] in ("support-v1", "support-1-span-v1", "support-2-span-v1", "fill-support-v1"):
        from megascene_support import audit as audit_support
        return audit_support(records, frozen, expected, expected_work, complete, thorough)
    if frozen["schedule_id"] in ("localized-v1", "material-detail-localized-v1"):
        from megascene_localized import audit as audit_localized
        return audit_localized(records, frozen, expected, expected_work, complete, thorough)
    failures, catalog = [], []
    diagnostic = frozen.get("diagnostic") in ("mixed-world", "compact-reference")
    picking = frozen["schedule_id"] in ("picking-v1", "picking-v2") or diagnostic and "-picking-" in frozen["schedule_id"]
    traversal = picking or frozen["schedule_id"] in ("traversal-v1", "traversal-v2") or diagnostic
    if picking:
        from megascene_picking import expected_payload, audit as audit_picking
    elif traversal:
        from megascene_traversal import expected_payload
    expected_hash = hashlib.sha256(checkpoint_bytes(expected)).hexdigest()
    body_hashes = {body["id"]: digest(body) for body in expected["bodies"]}
    required = checkpoint_catalog(frozen)
    seen, frames = set(), set()
    native = [r for r in records if r["record_type"] == "native_audit"]
    checks = [r for r in records if r["record_type"] in ("checkpoint", "static_audit")]
    observed_work = next((r["work"] for r in checks if r["record_type"] == "checkpoint" and r["frame"] == "0"), expected_work)
    representation_diff = mismatch(expected_work, observed_work, "work")
    rendered = [r for r in records if r["record_type"] == "render_work"]
    frame_records = [r for r in records if r["record_type"] == "frame"]
    try:
        require(complete, "complete declared schedule unavailable")
        if picking:
            audit_picking(records, frozen)
        require([w["id"] for w in observed_work] == [w["id"] for w in expected_work], "work inventory ownership mismatch")
        for actual, reference in zip(observed_work, expected_work):
            require(actual.keys() == reference.keys(), "incomplete actual work inventory")
            for key, value in actual.items():
                integer(value)
                if key in ("cells", "protected_cells"):
                    require(value == reference[key], "work conservation mismatch")
        if thorough:
            require(representation_diff is None, "independent initial work inventory mismatch")
        require(len(native) == len(rendered) == len(frame_records) == len(frozen["frames"]), "incomplete native validation replay")
        for r in records:
            if r["record_type"] == "presentation_status":
                require(r["result"] == "1000001003" and r["frozen_surface_unchanged"] is True, "frozen presentation properties changed")
        previous = None
        for ordinal, (n, work) in enumerate(zip(native, rendered)):
            require(n["frame"] == work["frame"] == str(ordinal), "native audit frame mismatch")
            ids = n["drawn_ids"]
            require(len(ids) == len(set(ids)) and set(ids) <= set(body_hashes), "duplicate/unknown native draw")
            require(str(len(ids)) == work["main_body_draws"], "native draw inventory mismatch")
            require(integer(n["vertices_checked"]) == sum(integer(w["vertices"]) for w in observed_work), "incomplete native mesh checks")
            require(integer(n["reference_visible"]) <= len(ids)+len(n.get("proxied_ids",[])), "visible reference geometry missing")
            require(work["mesh_rebuilt"] == (str(len(body_hashes)) if ordinal == 0 else "0"), "static mesh cache invalidation mismatch")
            require(work["shadow_refresh"] is (ordinal == 0) and work["shadow_body_draws"] == (str(len(body_hashes)) if ordinal == 0 else "0"), "static shadow cache invalidation mismatch")
            if previous:
                require(work["proxy_rebuilt"] == "0", "static proxy cache rebuilt")
                for key in ("proxy_groups", "proxy_vertices", "shadow_extent_m", "shadow_texel_m"):
                    require(work[key] == previous[key], f"static {key} changed")
            previous = work
        for record in checks:
            frame = record["frame"]
            require(frame not in frames, "duplicate checkpoint frame")
            frames.add(frame)
            work_diff = mismatch(observed_work, record["work"], "work")
            if work_diff:
                failures.append({"frame": frame, **work_diff})
                require(False, "static actual work inventory changed")
            if record["record_type"] == "checkpoint":
                require(hashlib.sha256(checkpoint_bytes(record["payload"])).hexdigest() == record["sha256"], "checkpoint digest mismatch")
                frame_expected = expected_payload(expected, frozen["frames"][int(frame)]) if traversal else expected
                diff = mismatch(frame_expected, record["payload"])
                if diff:
                    failures.append({"frame": frame, "names": record["names"], **diff})
                for name in record["names"]:
                    require(name in required and required[name] == frame and name not in seen, "unexpected or duplicate checkpoint name/frame")
                    seen.add(name)
                    catalog.append({"name": name, "frame": frame, "sha256": record["sha256"], "body_sha256": record["body_sha256"]})
            if "payload" in record:
                require(record["body_sha256"] == {b["id"]: digest(b) for b in record["payload"]["bodies"]}, "per-body digest mismatch")
            frame_hash = hashlib.sha256(checkpoint_bytes(expected_payload(expected, frozen["frames"][int(frame)]))).hexdigest() if traversal else expected_hash
            require(record["sha256"] == frame_hash and record["body_sha256"] == body_hashes, f"state/geometry mismatch at frame {frame}")
        require(seen == set(required), "missing required checkpoints")
        if thorough:
            require(frames == {f["frame"] for f in frozen["frames"]}, "incomplete intermediate state validation")
        else:
            require(frames == set(required.values()), "unexpected timed checkpoint schedule")
    except (ValueError, KeyError, TypeError) as exc:
        failures.append({"reason": str(exc)})
    return {"schema": SCHEMA, "record_type": "checkpoint_comparison", "synthetic": any(r.get("synthetic", False) for r in records), "status": "fail" if failures else "pass",
            "scope": ("complete picking replay" if picking else "complete traversal replay" if traversal else "complete static replay") if thorough else "required checkpoints and native frames",
            "failures": failures, "checkpoints": catalog, "checked_frames": str(len(frames)),
            "native_frames": str(len(native)), "actual_work": observed_work,
            "representation_work": {"equal_to_validation": representation_diff is None, "first_difference": representation_diff}}


def applicable(validation, actual_identity):
    require(validation.get("status") == "pass" and validation.get("synthetic") is False, "successful real validation required")
    diff = mismatch(validation["identity"], actual_identity, "identity")
    require(diff is None, "validation identity mismatch: "+str(diff))


def compare_threads(bundles):
    """A report operation; each thread count must already have its own replay."""
    from pathlib import Path
    summaries = []
    for bundle in bundles:
        root = Path(bundle)
        manifest = read_json((root/"manifest.json").read_text())
        verify_evidence(manifest, root, ("validation.json", "summary.json", "comparison.json"))
        validation = read_json((root/"validation.json").read_text())
        applicable(validation, identity(manifest, root, manifest["effective"]))
        summary = read_json((root/"summary.json").read_text())
        require(summary["state_correctness"]["status"] == "pass" and
                summary["attempt_kind"] in ("development_observation", "calibration_on"),
                "thread comparison requires validated timed attempt")
        comparison = read_json((root/"comparison.json").read_text())
        require(comparison["status"] == "pass", "thread comparison has failed checkpoints")
        summaries.append((manifest, validation, comparison))
    require(sorted(m["effective"]["threads"] for m,_,_ in summaries) == ["1", "12", "6"], "thread comparison requires 1/6/12 separately")
    require(len({m["attempt_kind"] for m,_,_ in summaries}) == 1,
            "thread comparison requires one attempt kind")
    first = summaries[0]
    differences = []
    for manifest, validation, comparison in summaries[1:]:
        require(first[1]["effective_render_identity"] == validation["effective_render_identity"] and
                first[1]["loaded_host_artifacts"] == validation["loaded_host_artifacts"],
                "thread comparison changed effective renderer or loaded host libraries")
        a, b = first[1]["identity"], validation["identity"]
        # Runtime executable/source/shaders and frozen inputs must be identical;
        # only actual thread execution settings differ.
        import copy
        a, b = copy.deepcopy(a), copy.deepcopy(b)
        for value in (a, b):
            value["configuration"].pop("threads")
            value["worker_command"][-1] = "THREADS"
        require(mismatch(a,b) is None, "thread comparison changed workload/runtime/settings")
        diff = mismatch(first[2]["checkpoints"], comparison["checkpoints"], "checkpoints")
        if diff:
            differences.append({"threads": manifest["effective"]["threads"], **diff})
    return {"schema": SCHEMA, "record_type": "thread_comparison", "synthetic": False,
            "status": "fail" if differences else "pass", "threads": ["1", "6", "12"],
            "scope": "exact logical state and geometry; separate validation per thread count",
            "differences": differences, "bundles": list(map(str,bundles)),
            "work_inventories": {m["effective"]["threads"]: c["actual_work"] for m,_,c in summaries}}


if __name__ == "__main__":
    import argparse
    from pathlib import Path
    from megascene import snapshot
    parser = argparse.ArgumentParser(description="Compare separately validated static 1/6/12-thread attempts")
    parser.add_argument("--compare-threads", nargs=3, required=True, metavar="BUNDLE")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    target = Path(args.output)
    require(not target.exists(), "thread comparison output already exists")
    result = compare_threads(args.compare_threads)
    snapshot(target, result)
    print(result["status"]+": "+str(target))
    raise SystemExit(0 if result["status"] == "pass" else 2)
