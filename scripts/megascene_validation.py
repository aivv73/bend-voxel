"""Static validation orchestration; separate processes and retained failure data."""
import hashlib
from pathlib import Path
import shutil
import subprocess
import time
import uuid

from megascene_checkpoints import applicable, audit, identity, initial_payload, mismatch, verify_evidence
from megascene_inventory import SCHEMA, inventory, outcome, read_json, require


def render_identity(records):
    ignored = {"schema", "record_type", "campaign_id", "series_id", "attempt_id", "sequence", "clock_id", "time_ns", "frame"}
    return [{k:v for k,v in r.items() if k not in ignored} for r in records if r["record_type"] in ("render_settings", "palette")]


def host_artifacts(invocation, archive):
    """Bind reuse to the actually sampled host loader/graphics libraries too."""
    result = {}
    for name in invocation["loaded_objects"]:
        path = Path(name)
        if archive in path.parents or ".so" not in path.name:
            continue
        require(path.is_file(), "loaded host artifact unavailable: "+name)
        result[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    require(result, "loaded host artifact evidence unavailable")
    return result


def verify_host_artifacts(validation):
    for name, expected in validation["loaded_host_artifacts"].items():
        require(Path(name).is_file() and hashlib.sha256(Path(name).read_bytes()).hexdigest() == expected,
                "stale loaded host artifact: "+name)


def validate_or_reuse(config, archive, manifest, loader, campaign, source, owners, bounds):
    from megascene import run, snapshot
    from megascene_static import launch
    from megascene_references import check
    started = time.monotonic_ns()
    value = {"schema": SCHEMA, "record_type": "validation", "synthetic": False,
             "status": "fail", "attempt_id": None, "reused": False,
             "scope": "complete declared "+config["case"]+" schedule; independent dense fixtures and sparse/runtime/native checks",
             "failures": [], "checked_frames": "0"}
    try:
        actual_identity = identity(manifest, archive, config)
        value["identity"] = actual_identity
        if config.get("validated"):
            original = read_json((source/"manifest.json").read_text())
            # Validate retained evidence bytes as well as runtime identities. A
            # successful flag in an edited/incomplete file is insufficient.
            required = {"validation.json"} | {"validation/"+name for name in (
                "manifest.json", "summary.json", "cpu.jsonl", "gpu.jsonl", "stdout.log", "stderr.log", "reference.stdout.log",
                "reference.stderr.log", "comparison.json", "inventory.json", "invocation.json", "supervision.json",
                "resources.jsonl", "heaps.jsonl", "allocations.jsonl", "reference.jsonl", "reference.shared")}
            required |= {a["path"] for a in original["evidence"] if a["path"].startswith("validation/")}
            verify_evidence(original, source, required)
            previous = read_json((source/"validation.json").read_text())
            applicable(previous, actual_identity)
            verify_host_artifacts(previous)
            value = {**previous, "reused": True, "source": str(source), "reuse_verification_ns": str(time.monotonic_ns()-started)}
            shutil.copytree(source/"validation", archive/"validation")
            return value
        destination = archive/"validation"
        destination.mkdir()
        validation_manifest = {**manifest, "attempt_id": str(uuid.uuid4()), "attempt_kind": "validation_replay"}
        validation_manifest["artifacts"] = [{**entry, "path": "../"+entry["path"]} for entry in manifest["artifacts"]]
        value["attempt_id"] = validation_manifest["attempt_id"]
        snapshot(destination/"manifest.json", validation_manifest)
        reference_start = time.monotonic_ns()
        run([str(archive/f"runtime/lib/{loader}"), "--library-path", str(archive/"runtime/lib"),
             str(archive/"runtime/reference-worker"), "--gpu", "off", "--threads", config["threads"]],
            archive/"runtime", destination/"reference.stdout.log", destination/"reference.stderr.log", 30)
        value["independent_references"] = check((destination/"reference.stdout.log").read_text())
        value["independent_references"]["duration_ns"] = str(time.monotonic_ns()-reference_start)
        if config["case"] == "picking":
            from megascene_picking_references import check as check_picking
            run([str(archive/f"runtime/lib/{loader}"), "--library-path", str(archive/"runtime/lib"),
                 str(archive/"runtime/picking-reference-worker"), "--gpu", "off", "--threads", config["threads"]],
                archive/"runtime", destination/"picking-reference.stdout.log", destination/"picking-reference.stderr.log", 30)
            value["picking_references"] = check_picking((destination/"picking-reference.stdout.log").read_text())
        if config["case"] in ("localized", "support", "history"):
            from megascene_edit_references import check as check_edits
            run([str(archive/f"runtime/lib/{loader}"), "--library-path", str(archive/"runtime/lib"),
                 str(archive/"runtime/edit-reference-worker"), "--gpu", "off", "--threads", config["threads"]],
                archive/"runtime", destination/"edit-reference.stdout.log", destination/"edit-reference.stderr.log", 30)
            value["edit_references"] = check_edits((destination/"edit-reference.stdout.log").read_text())
        if config["case"] == "support":
            from megascene_support_references import check as check_support
            run([str(archive/f"runtime/lib/{loader}"), "--library-path", str(archive/"runtime/lib"),
                 str(archive/"runtime/support-reference-worker"), "--gpu", "off", "--threads", config["threads"]],
                archive/"runtime", destination/"support-reference.stdout.log", destination/"support-reference.stderr.log", 30)
            value["support_references"] = check_support((destination/"support-reference.stdout.log").read_text(),config)
        if config["case"] == "history":
            from megascene_history_references import check as check_history
            run([str(archive/f"runtime/lib/{loader}"), "--library-path", str(archive/"runtime/lib"),
                 str(archive/"runtime/history-reference-worker"), "--gpu", "off", "--threads", config["threads"]],
                archive/"runtime", destination/"history-reference.stdout.log", destination/"history-reference.stderr.log", 30)
            value["history_references"] = check_history((destination/"history-reference.stdout.log").read_text())
        summary, records = launch(config, archive, validation_manifest, loader, campaign=campaign, validation=True)
        summary["attempt_kind"] = "validation_replay"
        frozen = read_json((archive/"schedule.json").read_text())
        text = (destination/"stdout.log").read_text()
        achieved = inventory(text, owners, config, bounds)
        snapshot(destination/"inventory.json", achieved)
        expected, work = initial_payload(text, frozen, manifest["worker_environment"]["MEGASCENE_SCHEDULE_SHA256"], config)
        result = audit(records, frozen, expected, work, summary["schedule_completion"]["status"] == "pass", thorough=True)
        require(not result["synthetic"], "synthetic replay cannot validate a real configuration")
        snapshot(destination/"comparison.json", result)
        value["loaded_host_artifacts"] = host_artifacts(read_json((destination/"invocation.json").read_text()), archive)
        value.update(status=result["status"], checked_frames=result["checked_frames"], native_frames=result["native_frames"],
                     failures=result["failures"], checkpoints=result["checkpoints"], expected=expected, actual_work=work,
                     effective_render_identity=render_identity(records), numeric_evidence=bounds,
                     invariant_coverage=["tree_bounds_and_counts", "six_neighbor_connectivity", "protected_anchors",
                        "source_ownership", "material_conservation", "finite_motion_bits", "drawable_coverage_and_winding",
                        "fresh_bend_native_transport", "native_mesh_slots_and_draw_ranges", "unculled_triangle_visibility",
                        "full_proxy_shadow_cache_transitions"])
        if config.get("diagnostic"):
            require(summary.get("proxy_diagnostic",{}).get("status") == "pass", "native proxy diagnostic failed")
            value["proxy_diagnostic"] = summary["proxy_diagnostic"]
            value["invariant_coverage"] += ["actual_proxy_membership", "render_pixel_80_100_hysteresis",
                                            "reachable_aim_suppression", "retained_full_meshes_and_shadows"]
        if config["case"] in ("localized", "support", "history"):
            value["edited_work"] = result.get("edited_work")
            value["invariant_coverage"] += [config["case"]+"_exact_removal", "atomic_budget_rejection", "edit_history_and_intervals", "unchanged_geometry_caches", "pre_unsafe_edit_guards"]
        if config["case"] == "support":
            value["moving_window"] = result.get("moving_window")
            value["beam_features"] = result.get("beam_features")
            value["invariant_coverage"] += ["two_support_paths_and_stumps", frozen["moving_window"]["distinct_spans"]+"_distinct_spans_frames_31_42", "binary32_motion_and_floor", "translation_preserves_full_mesh"]
        if config["case"] == "history":
            value["moving_window"] = result.get("moving_window")
            value["moved_targets"] = result.get("moved_targets")
            value["invariant_coverage"] += [str(sum(int(a["action"])%10==4 for a in frozen["actions"]))+
                                             "_moving_spans_and_targets", "bridge_stub_revisits", "every_cut_state_and_geometry"]
        if config["case"] == "picking":
            from megascene_picking import audit as audit_picking
            value["picking"] = audit_picking(records, frozen)
            summary["picking"] = value["picking"]
            value["invariant_coverage"] += ["declared_picking_targets", "strict_256m_reach", "actual_ray_and_owner_material", "pre_unsafe_numeric_guards"]
        summary["state_correctness"] = outcome(value["status"], "independent initial references and every-frame sparse checks", "complete declared "+config["case"]+" schedule", ["comparison.json"])
        snapshot(destination/"summary.json", summary)
        # No artifact is permitted to change during validation.
        require(identity(manifest, archive, config) == actual_identity, "artifacts changed during validation")
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as exc:
        value["status"] = "fail"
        value["failures"].append({"reason": str(exc)})
    value["duration_ns"] = str(time.monotonic_ns()-started)
    snapshot(archive/"validation.json", value)
    return value


def compare_attempt(config, archive, manifest, validation, summary, records):
    from megascene import snapshot
    failures = []
    try:
        applicable(validation, identity(manifest, archive, config))
        verify_host_artifacts(validation)
        actual_host = host_artifacts(read_json((archive/"invocation.json").read_text()), archive)
        require(actual_host == validation["loaded_host_artifacts"], "loaded host artifacts differ from validation")
        frozen = read_json((archive/"schedule.json").read_text())
        result = audit(records, frozen, validation["expected"], validation["actual_work"],
                       summary["schedule_completion"]["status"] == "pass")
        if config["case"] in ("localized", "support", "history"):
            require(result.get("edited_work") == validation.get("edited_work"), "post-edit work differs from validation")
        if config["case"] == "support":
            for field in ("checkpoints", "moving_window", "beam_features"):
                require(result.get(field) == validation.get(field), "support "+field+" differs from validation")
        if config["case"] == "history":
            for field in ("checkpoints", "moving_window", "moved_targets"):
                require(result.get(field) == validation.get(field),
                        "history "+field+" differs from validation")
        require(not result["synthetic"], "synthetic checkpoints cannot qualify a real attempt")
        if config.get("diagnostic"):
            require(summary.get("proxy_diagnostic",{}).get("status") == "pass", "timed native proxy diagnostic failed")
            require(mismatch(validation["proxy_diagnostic"], summary["proxy_diagnostic"], "proxy_diagnostic") is None,
                    "timed proxy decisions/work differ from validation")
        diff = mismatch(validation["effective_render_identity"], render_identity(records), "effective_render_settings")
        if diff:
            result["failures"].append(diff)
            result["status"] = "fail"
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as exc:
        failures.append({"reason": str(exc)})
        result = {"schema": SCHEMA, "record_type": "checkpoint_comparison", "status": "fail", "failures": failures}
    if config["case"] == "picking" and result["status"] == "pass":
        from megascene_picking import audit as audit_picking
        summary["picking"] = audit_picking(records, frozen)
    if config["case"] in ("support", "history"):
        summary["moving_window"] = result.get("moving_window")
        if result["status"] != "pass":
            summary["schedule_completion"] = outcome("inconclusive", "required replay evidence failed", "complete "+config["case"]+" schedule", ["comparison.json"])
    snapshot(archive/"comparison.json", result)
    summary["validation"] = {"path": "validation.json", "attempt_id": validation["attempt_id"],
                             "reused": validation["reused"], "duration_ns": validation.get("duration_ns")}
    summary["state_correctness"] = outcome(result["status"], "exact required checkpoints agree with separately validated configuration" if result["status"] == "pass" else "checkpoint/validation mismatch",
        "complete declared "+config["case"]+" schedule", ["validation.json", "comparison.json", "cpu.jsonl"])
    summary["rendering_correctness"] = outcome(result["status"], "drawable geometry, native cache and unculled visibility checks" if result["status"] == "pass" else "geometry/native evidence incomplete or mismatched",
        config["case"]+" geometry/cache/visibility; visual quality remains separate", ["validation.json", "comparison.json"])
    # Correctness never promotes calibration, visual quality, performance,
    # capacity qualification, or the parent feature's implementation acceptance.
    snapshot(archive/"summary.json", summary)
