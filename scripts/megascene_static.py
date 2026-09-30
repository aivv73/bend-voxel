"""Bounded Vulkan observations through the public Megascene runner."""
import hashlib
import math
import os
from pathlib import Path
import re
import shutil
import signal
import struct
import subprocess
import time
import uuid

from megascene_inventory import SCHEMA, canonical, integer, inventory, measurement, outcome, read_json, require
from megascene_recipe import admit_sources, bend_program, bits, checked, envelope_cells, generate, CONTROLS
from megascene_scale import side_count, operational_bounds, admit_schedule, preflight
from megascene_gpu import u64

AUDIT_STAGES = ("audit_mesh_validation", "audit_visibility", "audit_proxy", "audit_hashing", "audit_output")
GEOMETRY_STAGES = {"geometry_mesh_update", "geometry_audit", *AUDIT_STAGES}


def settings(args, base):
    from megascene_performance import SCHEDULES, admit as admit_performance
    performance = args.schedule in SCHEDULES
    for name in ("search",):
        require(getattr(args, name) is None, f"--{name} is not implemented")
    require(args.calibration in (None, "on", "off"), "--calibration must be on or off")
    if args.calibration:
        require(args.case in ("static", "history") and args.diagnostic is None and
                args.profile in (None, "full") and args.resolution in (None, "1920x1080") and
                not args.capture_opening, "calibration requires primary static/history full geometry at 1920x1080")
    else:
        require(args.calibration_peer_validation is None, "peer validation requires a calibration mode")
    control = args.diagnostic if args.diagnostic in CONTROLS else None
    diagnostic = None if control else args.diagnostic
    if control:
        require((args.case, control) in (("static", "spread"), ("static", "material-detail"),
                ("localized", "material-detail"), ("static", "surface-detail"),
                ("support", "fill"), ("history", "fill"), ("history", "body-rich")), "unsupported control/case combination")
        require(base["preset"] == "small" and base["seed"] == "45" and base["threads"] == "6"
                and args.resolution in (None, "1920x1080"), "terrain controls require small/seed-45/1080p/6 threads")
    if diagnostic is not None:
        from megascene_proxy import DIAGNOSTICS
        require(diagnostic in DIAGNOSTICS and args.case in ("traversal", "picking"), "proxy diagnostics require traversal or picking")
        require(args.profile in ("full", "proxy"), "proxy diagnostic requires explicit full or proxy profile")
        require(base["preset"] == "small" and args.resolution in (None,"1920x1080"), "proxy diagnostic requires small/1080p")
    else:
        require(args.profile in (None, "full"), "primary replays require --profile full")
    if performance:
        schedule_id = args.schedule
    elif args.case in ("traversal", "picking"):
        if args.case == "picking":
            from megascene_picking import ROUTES
        else:
            from megascene_traversal import ROUTES
        schedule_id = f"proxy-{diagnostic}-{args.case}-v1" if diagnostic else args.schedule or args.case+"-v2"
        require(args.schedule is None or args.schedule == schedule_id, "unsupported frozen schedule")
    elif args.case in ("localized", "support", "history"):
        variants = {"history-12-v1", "history-48-v1", "support-1-span-v1", "support-2-span-v1"}
        schedule_id = (args.schedule if args.schedule in variants and not control else
                       f"{control}-{args.case}-v1" if control else
                       "history-v2" if args.case == "history" and base["preset"] not in ("small","large") else
                       args.case+"-v1")
        if schedule_id in variants:
            require((args.case == "history" and schedule_id.startswith("history-")) or
                    (args.case == "support" and schedule_id.startswith("support-")),
                    "variant schedule/case mismatch")
            require(base["preset"] == "small" and base["seed"] == "45" and base["threads"] == "6"
                    and args.resolution in (None, "1920x1080"),
                    "history/span controls require small/seed-45/1080p/6 threads")
        require(args.schedule in (None, schedule_id), "unsupported frozen schedule")
    else:
        schedule_id = f"{control}-static-v1" if control else "static-v1"
        require(args.schedule in (None, schedule_id), "unsupported frozen schedule")
    require(args.resolution in (None, "640x360", "1920x1080"), "supported replay resolutions are 640x360 and 1920x1080")
    warmup = integer(args.warmup if args.warmup is not None else "120")
    frames = integer(args.frames if args.frames is not None else "21600" if performance else "3600")
    deadline = integer(args.deadline if args.deadline is not None else "300")
    require(0 <= warmup <= 120 and 1 <= frames <= (21600 if performance else 3600), "unsupported replay frame count")
    if args.case in ("traversal", "picking", "localized", "support", "history") and not performance:
        require((warmup, frames) == (120, 3600), "primary replay requires the complete 120/3600 schedule")
        require(not args.capture_opening, "replay captures come from the separate validation replay")
    if control:
        require((warmup, frames) == (120, 3600), "terrain controls require the complete 120/3600 schedule")
    if args.calibration and (performance or (warmup, frames) == (120, 3600)) and not args.validation_only:
        require(args.calibration_peer_validation is not None,
                "complete calibration controls require prior opposite-mode validation")
    require(1 <= deadline <= 300, "development deadline must be 1..300 seconds")
    require(args.archive, "Vulkan replays require an explicit durable --archive destination")
    archive = Path(args.archive).expanduser().resolve()
    output = Path(args.output).expanduser().resolve()
    require(not any(p in ("build", "dist", "tmp") for p in archive.parts), "archive must be outside disposable build/dist/tmp directories")
    require(archive != output and output not in archive.parents and archive not in output.parents,
            "archive and output must be separate directory trees")
    require(not (args.validated and args.runtime_from), "choose --validated or --runtime-from")
    require(not (args.validation_only and (args.validated or args.capture_opening)), "validation-only cannot reuse validation or request capture")
    config = {**base, "validation_only": args.validation_only, "validated": args.validated, "runtime_from": args.runtime_from, "case": args.case, "diagnostic": diagnostic, "control": control, "calibration_mode": args.calibration, "calibration_peer_validation": args.calibration_peer_validation, "envelope_side_m": str(envelope_cells(base["preset"], control)//10), "profile": args.profile or "full", "resolution": args.resolution or "1920x1080",
            "warmup": str(warmup), "frames": str(frames), "schedule": schedule_id, "deadline_s": str(deadline),
            "capture_opening": args.capture_opening, "archive": str(archive),
            "schedule_kind": "performance_v2" if performance else "declared_control" if schedule_id in {"history-12-v1", "history-48-v1",
                                                                    "support-1-span-v1", "support-2-span-v1"} else
                             "accepted" if (warmup, frames) == (120, 3600) else "declared_development_prefix"}
    if performance:
        admit_performance(config)
        require(not args.capture_opening, "performance captures use separate validation evidence")
        if args.case == 'history':
            config['validation_deadline_s'] = str(deadline if args.deadline is not None else 480)
    return config


def schedule(config, owners=None):
    if config.get("diagnostic"):
        from megascene_proxy import schedule as proxy_schedule, owners as proxy_owners
        return proxy_schedule(config, owners if owners is not None else proxy_owners(config))
    if config.get("case") == "history":
        from megascene_history import schedule as history_schedule
        return history_schedule(config)
    if config.get("case") == "support":
        from megascene_support import schedule as support_schedule
        return support_schedule(config)
    if config.get("case") == "localized":
        from megascene_localized import schedule as localized_schedule
        return localized_schedule(config)
    if config.get("case") == "picking":
        from megascene_picking import schedule as picking_schedule
        return picking_schedule(config)
    if config.get("case") == "traversal":
        from megascene_traversal import schedule as traversal_schedule
        return traversal_schedule(config)
    origin = -int(config.get("envelope_side_m", config["side_m"]))*5
    eye = [(150+origin)/10, 12, (310+origin)/10]
    delta = [-74, -72, -234]
    camera = {"eye_m": list(map(bits, eye)), "yaw": bits(math.atan2(delta[0], delta[2])),
              "pitch": bits(math.atan2(delta[1], math.hypot(delta[0], delta[2])))}
    frames = [{"frame": str(i), "phase": "startup" if i == 0 else "warmup" if i <= int(config["warmup"]) else "ordinary",
               "measured_ordinal": str(i-1-int(config["warmup"])) if i > int(config["warmup"]) else None,
               "camera": camera, "picking": False, "actions": []}
              for i in range(1+int(config["warmup"])+int(config["frames"]))]
    frozen = {"schema": SCHEMA, "record_type": "schedule", "fixed_step": "0x3c888889",
            "schedule_id": config.get("schedule", "static-v1"), "warmup_frames": config["warmup"], "measured_frames": config["frames"],
            "opening": camera, "frames": frames, "actions": [],
            "review_views": [{"name": "opening", "frame": "0", "features": ["building silhouettes", "span silhouettes", "major shadows"]}],
            "required_checkpoints": [{"name": "initialization", "frame": "0"}, {"name": "review_opening", "frame": "0"},
                                     {"name": "warmup_end", "frame": config["warmup"]},
                                     {"name": "completion", "frame": str(int(config["warmup"])+int(config["frames"]))}],
            "checkpoint_implementation": "megascene-checkpoint/1",
            "update_order": ["physics", "edit_disabled", "view_picking_disabled", "render"]}
    from megascene_performance import enabled, finish
    return finish(frozen) if enabled(config) else frozen


def worker_program(owners, config, frozen):
    source = bend_program(owners, int(config["fragment_budget"])).split("def main()", 1)[0]
    module = {"history":"megascene_history", "support":"megascene_support", "localized":"megascene_localized", "picking":"megascene_picking_replay", "traversal":"megascene_traversal", "static":"megascene_static"}[config["case"]]
    source = source.replace("import Base", f"import Base\nimport ./src/{module}.bend as Static\nimport ./src/vulkan.bend as VK\nimport ./src/render.bend as V")
    def real(value):
        decoded = struct.unpack(">f", bytes.fromhex(value[2:]))[0]
        return f"(0.0 - {abs(decoded)!r} : F32)" if decoded < 0 else repr(decoded)
    camera = frozen["opening"]
    width, height = config["resolution"].split("x")
    cam = "V.Camera{R.Vec{"+",".join(map(real, camera["eye_m"]))+"},"+real(camera["yaw"])+","+real(camera["pitch"])+f",{width},{height}"+"}"
    start_args = f"{width},{height}" if config['case'] in ('traversal','picking','localized','support','history') else f"{cam},{width},{height}"
    if config['case'] == 'localized':
        point = "R.Vec{"+",".join(map(real,frozen['actions'][0]['target_m']))+"}"
        start_args = point+","+start_args
    if config['case'] in ('support','history'):
        cuts = ["Static.Cut{"+a['frame']+","+a['action']+",R.Vec{"+",".join(map(real,a['target_m']))+"}"+
                (","+a['expected_removed_cells'] if config['case']=='history' else "")+"}" for a in frozen['actions']]
        start_args = "["+",".join(cuts)+"],"+start_args
    entry = "Static.start.proxy" if config["case"] == "picking" and config.get("diagnostic") else "Static.start"
    source += f'''def main() -> IO(Unit):
  do IO<Unit>:
    VK.vulkan.mark(0)
    VK.vulkan.mark(1)
    sources : List<&2,Showcase.Assembly> <- IO.pure(List<&2,Showcase.Assembly>,[{','.join(f'owner{i}()' for i in range(len(owners)))}])
    VK.vulkan.mark(2)
    VK.vulkan.mark(3)
    +world : W.World <- IO.pure(W.World,W.from.bodies(W.assemblies(sources,1),{config['fragment_budget']}))
    VK.vulkan.mark(4)
    VK.vulkan.mark(5)
    M.emit(world)
    VK.vulkan.mark(6)
    {entry}(world,{start_args},{int(config['warmup'])+int(config['frames'])}n)
'''
    return source.replace("./src/", "./")


def read_stream(path, attempt_id):
    """Consume only a contiguous, validated prefix; retain damaged bytes in place."""
    records, problems = [], []
    if not path.exists():
        return [], ["worker evidence stream unavailable"]
    for line in path.read_bytes().splitlines(keepends=True):
        try:
            require(line.endswith(b"\n"), "truncated evidence tail")
            r = read_json(line.decode())
            require(r["schema"] == SCHEMA, "unsupported evidence schema")
            require(r["attempt_id"] == attempt_id, "attempt identity mismatch")
            require(not records or all(r[k] == records[0][k] for k in ("campaign_id", "series_id")), "campaign/series identity mismatch")
            require(integer(r["sequence"]) == len(records), "sequence gap or duplicate")
            require(r["clock_id"] == "linux.CLOCK_MONOTONIC", "unexpected clock")
            now = u64(r["time_ns"])
            require(not records or now >= integer(records[-1]["time_ns"]), "nonmonotonic record time")
            integer(r["frame"])
            require(r["record_type"] in {"worker_start", "stage", "static_state", "render_settings", "palette", "render_work", "frame", "opening_capture", "capture", "complete", "window_closed", "checkpoint", "static_audit", "native_audit", "presentation_status", "picking", "edit_begin", "action", "edit", "body_motion", "detail_render", "detail_capture"}, "unknown evidence record type")
            if r["record_type"] in ("frame", "stage", "edit"):
                begin, end = u64(r["begin_ns"]), u64(r["end_ns"])
                require(begin <= end <= now, "invalid interval boundaries")
                require(integer(r["duration_ns"]) == end-begin and r["status"] == "measured" and r["unit"] == "ns", "invalid duration/status/unit")
            if r["record_type"] == "checkpoint":
                from megascene_checkpoints import checkpoint_bytes
                import json
                encoded = line.decode()
                marker = encoded.index('"payload":')+len('"payload":')
                _, end = json.JSONDecoder().raw_decode(encoded[marker:])
                require(encoded[marker:marker+end].encode() == checkpoint_bytes(r["payload"]), "noncanonical checkpoint payload bytes")
            records.append(r)
        except (ValueError, KeyError, UnicodeError, TypeError) as exc:
            problems.append(str(exc))
            break
    return records, problems


def audit_observation(records, config, frames, frozen=None):
    errors = []
    try:
        settings_records = [r for r in records if r["record_type"] == "render_settings"]
        if frames:
            require(len(settings_records) == 1, "missing or duplicate effective render settings")
            actual = settings_records[0]
            width, height = config["resolution"].split("x")
            require((actual["width"], actual["height"], actual["profile"], actual["shadow_size"], actual["night"]) ==
                    (width, height, config["profile"], "2048", "0"), "effective rendering settings mismatch")
            require(actual["present_mode"] in ("immediate", "mailbox"), "unsupported presentation mode")
            require(str(actual["ground_half_extent_m"]) == str(int(config.get("envelope_side_m", config["side_m"]))//2+8), "ground bounds mismatch")
        frozen = frozen if frozen is not None else schedule(config)
        q = side_count(config["preset"])
        owners = (4 if config.get("diagnostic") == "compact-reference" else
                  1+6*q*q if config.get("control") == "body-rich" else 1+5*q*q)
        require(q in (2,4) or "source_cells" in config,
                "actual candidate source cell count required for observation audit")
        source_cells = int(config.get("source_cells", "10503360" if q == 2 else "42096576"))
        by_frame = {}
        for r in records:
            by_frame.setdefault(r["frame"], []).append(r)
        # Archived workers have only the aggregate geometry marker. A worker
        # declaring detailed timing must supply the full set on every frame,
        # even when all its detailed records are missing from the stream.
        detailed_geometry = any(r["record_type"] == "stage" and r["stage"] in GEOMETRY_STAGES for r in records)
        if frames:
            timing_schema = actual.get("geometry_timing_schema")
            require(timing_schema in (None, "native-geometry-timing/1"), "unsupported native geometry timing schema")
            detailed_geometry |= timing_schema is not None
        for f in frames:
            items = by_frame[f["frame"]]
            state = [r for r in items if r["record_type"] == "static_state"]
            work = [r for r in items if r["record_type"] == "render_work"]
            require(len(state) == len(work) == 1, "missing or duplicate state/render work")
            state, work = state[0], work[0]
            planned = frozen["frames"][int(f["frame"])]
            camera = planned["camera"]
            require(state["aim_kind"] == planned.get("expected_pick", {"kind":"0"})["kind"], "actual picking kind mismatch")
            require({k:state[k] for k in camera} == camera, "actual view differs from frozen camera schedule")
            if config.get("case") == "support":
                from megascene_support import CUT_FRAMES, motion, value
                i=int(f['frame']);cut_frames=tuple(int(a['frame']) for a in frozen['actions'])
                cuts=sum(at<=i for at in cut_frames)
                released=[at for at in cut_frames[1::2] if at<=i]
                moving=sum(value(motion(min(i-at,80),42+(8 if config.get('control')=='fill' else 0))[1])!=0 for at in released)
                translated=sum(i>at for at in released)
                require((state['anchored'],state['fragments'],state['moving'],state['translated'])==
                        tuple(map(str,(owners+(cuts+1)//2,len(released),moving,translated))), 'support inventory/moving count mismatch')
                require((state['cells'],state['removed'],state['next_id'],state['budget'])==
                        (str(source_cells-cuts*16),'16' if cuts else '0',str(owners+1+2*cuts),config['fragment_budget']), 'support material/identity inventory mismatch')
                require(work['body_count']==work['full_meshes']==str(owners+cuts),'support full meshes missing')
            elif config.get("case") == "history":
                require(state['budget']==config['fragment_budget'] and int(state['cells'])>0 and
                        work['body_count']==work['full_meshes'], 'history scalar/native inventory mismatch')
            else:
                edited = config.get("case") == "localized" and int(f["frame"]) >= 121
                removed = 16 if edited else 0
                require(state["anchored"] == str(owners) and all(state[k] == "0" for k in ("moving", "translated", "fragments")) and state["removed"] == str(removed), "world state mismatch")
                require(state["cells"] == str(source_cells-removed) and state["next_id"] == str(owners+1+int(edited)) and state["budget"] == config["fragment_budget"], "world inventory mismatch")
                require(work["body_count"] == work["full_meshes"] == str(owners), "full meshes missing")
            if config["profile"] == "full":
                require(work["proxy_draws"] == "0" and work["main_body_draws"] == work["visible_bodies"], "full geometry substitution")
            else:
                require(int(work["main_body_draws"])+int(work["proxied_bodies"])==int(work["visible_bodies"]), "proxy/main visibility coverage mismatch")
            stages = [r for r in items if r["record_type"] == "stage"]
            required = {"transport", "renderer", "geometry", "fence_wait", "vertex_upload", "acquire", "command_record", "submit_present", "events"}
            if detailed_geometry:
                required |= GEOMETRY_STAGES
            required |= {"generation", "initial_surfaces", "initial_inventory", "window_setup", "renderer_setup"} if f["frame"] == "0" else {"physics", "view"}
            if planned["actions"]:
                required |= {"carve", "connectivity", "surfaces", "commit"}
            if any(r["record_type"] in ("checkpoint", "static_audit") for r in items):
                required.add("checkpoint")
            require({r["stage"] for r in stages} == required and len(stages) == len(required), "missing or duplicate CPU stage")
            if detailed_geometry:
                intervals = {r["stage"]: (u64(r["begin_ns"]), u64(r["end_ns"])) for r in stages}
                geometry, mesh, audit = (intervals[name] for name in ("geometry", "geometry_mesh_update", "geometry_audit"))
                require(geometry[0] <= mesh[0] <= mesh[1] == audit[0] <= audit[1] == geometry[1],
                        "invalid geometry update/audit boundaries")
                previous = None
                for name in AUDIT_STAGES:
                    begin, end = intervals[name]
                    require(audit[0] <= begin <= end <= audit[1], "CPU audit stage outside geometry audit")
                    require(previous is None or begin == previous, "CPU audit phases overlap or have a gap")
                    previous = end
            for r in stages:
                require(int(r["end_ns"]) <= int(f["end_ns"]), "CPU stage ends outside its frame")
                if f["frame"] != "0":
                    require(int(r["begin_ns"]) >= int(f["begin_ns"]), "CPU stage begins outside its frame")
    except (ValueError, KeyError, TypeError) as exc:
        errors.append(str(exc))
    return errors


def distribution(values):
    if not values:
        return {"count": "0", "unit": "ns", **{k: None for k in ("mean", "p50", "p95", "p99", "max")}}
    ordered = sorted(values)
    return {"count": str(len(values)), "unit": "ns", "mean": sum(values)/len(values),
            **{f"p{p}": ordered[math.ceil(len(values)*p/100)-1] for p in (50,95,99)}, "max": max(values)}


def report(records, problems, config, exit_code, cause, launch_ns, attempt_id, review=False, gpu_records=None, gpu_problems=None, frozen=None):
    from megascene_performance import enabled
    performance=enabled(config)
    frames = [r for r in records if r["record_type"] == "frame"]
    prefix = []
    frozen = frozen if frozen is not None else schedule(config)
    for r in frames:
        i = len(prefix)
        expected = frozen["frames"][i]["phase"] if i<len(frozen["frames"]) else None
        if (r["frame"] != str(i) or r["population"] != expected or
            (i and r["begin_ns"] != prefix[-1]["end_ns"])):
            problems.append("frame sequence/population/boundary mismatch")
            break
        prefix.append(r)
    problems = list(problems) + audit_observation(records, config, prefix, frozen)
    proxy_result = None
    if config.get("diagnostic") and len(prefix) == len(frozen["frames"]):
        try:
            from megascene_proxy import audit as audit_proxy
            proxy_result = audit_proxy(records, frozen, config)
        except (ValueError, KeyError, TypeError) as exc:
            problems.append(str(exc))
    if config.get("case") == "localized":
        from megascene_localized import audit_actions
        try:
            audit_actions(records, frozen)
        except (ValueError, KeyError, TypeError, StopIteration) as exc:
            problems.append(str(exc) or "missing required action evidence")
    if config.get("case") == "support":
        from megascene_support import audit_actions, audit_window
        try:
            audit_actions(records, frozen)
            audit_window(records, frozen)
        except (ValueError, KeyError, TypeError, StopIteration) as exc:
            problems.append(str(exc) or "missing required support evidence")
    if config.get("case") == "history":
        from megascene_history import audit_actions
        try:
            audit_actions(records, frozen)
        except (ValueError, KeyError, TypeError, StopIteration) as exc:
            problems.append(str(exc) or "missing required history evidence")
    completions = [r for r in records if r["record_type"] == "complete"]
    if completions:
        expected_count = 1 if review else 1+int(config["warmup"])+int(config["frames"])
        teardown = [r for r in records if r.get("stage") == "teardown"]
        if (len(completions) != 1 or records[-1] != completions[0] or completions[0]["frame"] != str(expected_count) or
            len(teardown) != 1 or teardown[0]["frame"] != str(expected_count) or
            (prefix and int(teardown[0]["begin_ns"]) < int(prefix[-1]["end_ns"])) or
            records[0]["record_type"] != "worker_start" or sum(r["record_type"] == "worker_start" for r in records) != 1):
            problems.append("invalid startup/teardown/completion markers")
    if prefix and int(prefix[0]["end_ns"]) < launch_ns:
        problems.append("startup frame predates process launch")
    complete = (not problems and exit_code == 0 and cause == "normal_exit" and
                any(r["record_type"] == "complete" for r in records) and
                len(prefix) == (1 if review else 1+int(config["warmup"])+int(config["frames"])))
    completion_scope = frozen["schedule_id"] if frozen.get("variant") else config.get("schedule_kind", "accepted")
    missing = outcome("inconclusive", "not implemented in static development slice", "complete qualified attempt")
    result = {"schema": SCHEMA, "record_type": "summary", "attempt_id": attempt_id,
              "attempt_kind": "opening_capture" if review else "development_observation", "synthetic": any(r.get("synthetic", False) for r in records),
              "qualification": "unqualified_development_observation",
              **{k: dict(missing) for k in ("state_correctness", "rendering_correctness", "visual_quality", "numeric_validity",
                  "population_qualification", "calibration", "responsiveness", "qualified_capacity", "interactive_pass")},
              "schedule_completion": outcome("pass" if complete else "inconclusive", "declared schedule completed" if complete else "incomplete or invalid evidence",
                                             "opening capture only" if review else completion_scope, ["cpu.jsonl", "gpu.jsonl"]),
              "completed_prefix": {"startup": bool(prefix), "warmup": str(min(max(0,len(prefix)-1),int(config["warmup"]))),
                                   "measured": str(max(0,len(prefix)-1-int(config["warmup"])))},
              "termination": {"cause": cause, "exit_code": str(exit_code) if exit_code >= 0 else None,
                              "signal": str(-exit_code) if exit_code < 0 else None},
              "evidence_errors": problems,
              "limitations": ["No instrumentation calibration; GPU queries and supervised resources are separate evidence.",
                              "CPU intervals include instrumentation; no physical display latency claim.", "Unsafe/native behavior is runtime evidence, never a formal proof."],
              "measurement_availability": measurement("measured", "CPU frame-effect boundaries", "completed frame prefix", "frames", str(len(prefix)))
                  if prefix else measurement("not_executed", "no frame returned", "attempt", "frames")}
    if config.get("diagnostic"):
        result["proxy_diagnostic"] = proxy_result if proxy_result is not None else {
            "status": "inconclusive", "reason": "required native proxy evidence incomplete or invalid"}
    populations = {}
    for name in (("warmup", "ordinary", "edit", "motion") if performance or config.get("case")=="support" else ("warmup", "ordinary", "edit")):
        values = [int(r["end_ns"])-int(r["begin_ns"]) for r in prefix if
                  r["population"] == name or not performance and name == "ordinary" and r["population"] == "motion"]
        populations[name] = {**distribution(values), "observation_interval_ns": str(sum(values))}
    result["populations"] = populations
    ordinary = populations["ordinary"]
    enough = int(ordinary["count"]) >= 1000 and int(ordinary["observation_interval_ns"]) >= 10_000_000_000
    result["population_qualification"] = outcome("inconclusive",
        "sample minimums reached; validation and measurement qualification unavailable" if enough else
        "insufficient population: requires 1000 ordinary frames and 10 measured seconds without extending the frozen schedule",
        "ordinary population", ["cpu.jsonl"])
    result["edit_response"] = outcome("not_applicable", "static schedule disables edits", "accepted edits")
    if config.get("case") in ("localized", "support", "history"):
        accepted = [r for r in records if r["record_type"] == "edit" and r["accepted"]]
        result["accepted_edits"] = distribution([int(r["duration_ns"]) for r in accepted])
        edit_reason = (f"{len(accepted)} accepted edits; fewer than 100 required for edit percentiles"
                       if len(accepted)<100 else
                       f"{len(accepted)} accepted edits; correctness and instrumentation calibration still govern qualification")
        result["edit_response"] = outcome("inconclusive",edit_reason, "accepted edits", ["cpu.jsonl", "reference.jsonl"])
        result["combined_frames"] = distribution([int(r["duration_ns"]) for r in prefix if r["population"] in ("ordinary", "edit", "motion")])
        result["edit_stages"] = [r for r in records if r["record_type"] == "stage" and r["frame"] in {a["frame"] for a in frozen["actions"]}]
    result["cold_startup"] = measurement("measured", "process launch to first usable frame-effect return", "startup", "ns",
                                           str(int(prefix[0]["end_ns"])-launch_ns)) if prefix and int(prefix[0]["end_ns"]) >= launch_ns else measurement("incomplete", "first usable frame unavailable", "startup", "ns")
    result["startup_stages"] = [r for r in records if r["record_type"] == "stage" and r["frame"] == "0"]
    result["teardown"] = [r for r in records if r.get("stage") == "teardown"]
    tail = next((r for r in records if r.get("stage") == "teardown"), None)
    result["final_bookkeeping"] = measurement("measured", "last frame-effect return to teardown begin; excluded from frame populations", "final bookkeeping", "ns",
        str(int(tail["begin_ns"])-int(prefix[-1]["end_ns"]))) if tail and prefix else measurement("incomplete", "final boundary unavailable", "final bookkeeping", "ns")
    result["effective_render_settings"] = next((r for r in records if r["record_type"] == "render_settings"), None)
    from megascene_gpu import summarize
    result["gpu_execution"] = summarize(gpu_records or [], gpu_problems or [], prefix, config, frozen)
    gpu = result["gpu_execution"]
    if config.get("case") == "history":
        named={}
        windows={name:range(int(pair[0]),int(pair[1])+1) for name,pair in frozen['history_populations'].items()}
        windows['moved_span_window']={int(a['frame'])-121+step for a in frozen['actions']
                                      if int(a['action'])%10==4 for step in range(1,12)}
        for name,ordinals in windows.items():
            selected=[r for r in prefix if r['frame']!='0' and int(r['frame'])-121 in ordinals]
            named[name]={kind:distribution([int(r['duration_ns']) for r in selected if kind=='all' or r['population']==kind])
                         for kind in (('all','ordinary','edit','motion') if performance else ('all','ordinary','edit'))}
            named[name]['observed_frames']=str(len(selected))
        result['history_populations']=named
        gpu['history_populations']={name:{'measured':distribution([r['value'] for r in gpu['intervals']
              if r['status']=='measured' and int(r['frame'])>120 and int(r['frame'])-121 in ordinals]),
              'incomplete':str(sum(r['status'] not in ('measured','unsupported') for r in gpu['intervals']
              if int(r['frame'])>120 and int(r['frame'])-121 in ordinals))} for name,ordinals in windows.items()}
    by_frame = {r["frame"]: r for r in prefix}
    for r in gpu["intervals"]:
        frame = by_frame.get(r["frame"])
        if frame and "submit_begin_ns" in r and not int(frame["begin_ns"]) <= int(r["submit_begin_ns"]) <= int(frame["end_ns"]):
            gpu["errors"].append("GPU submission outside originating CPU frame")
    if complete and len(gpu["intervals"]) != len(prefix):
        gpu["errors"].append("GPU submission count differs from completed schedule")
    if gpu["errors"]:
        gpu["required_evidence_complete"] = False
        gpu["status"] = "incomplete"
    result["evidence_errors"] += ["GPU: "+e for e in result["gpu_execution"]["errors"]]
    if prefix and not result["gpu_execution"]["required_evidence_complete"]:
        result["schedule_completion"] = outcome("inconclusive", "required GPU evidence incomplete; CPU prefix retained",
                                                completion_scope, ["cpu.jsonl", "gpu.jsonl"])
    if frozen.get("variant") and not frozen["variant"]["baseline_completion_equivalence"]:
        result["baseline_schedule_completion"] = outcome("not_applicable", "shortened action schedule cannot complete its baseline",
                                                         frozen["variant"]["baseline_schedule_id"])
    return result


def retained_copy(source, target):
    """Publish immutable runtime artifacts before any retained invocation."""
    target.mkdir(parents=True, exist_ok=False)
    for file in sorted(source.rglob("*")):
        if file.is_file():
            dest = target/file.relative_to(source)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(file,dest)
            require(hashlib.sha256(file.read_bytes()).digest() == hashlib.sha256(dest.read_bytes()).digest(), "archive content hash mismatch")
            with dest.open("rb") as stream:
                os.fsync(stream.fileno())


def execute(config, output, manifest, campaign):
    # Import common admission utilities only at execution to keep the CLI stable.
    from megascene import ROOT, artifact, provenance, run, snapshot
    mode = config.get("calibration_mode")
    manifest.update(attempt_kind="calibration_"+mode if mode else "development_observation", campaign_id=campaign.value["campaign_id"], series_id=str(uuid.uuid4()))
    manifest["qualification"] = "unqualified_development_observation"
    manifest["extensions"]["phase"] = "static_build"
    if config.get("diagnostic"):
        from megascene_proxy import owners as diagnostic_owners
        owners = diagnostic_owners(config)
    else:
        owners = preflight(generate,config["preset"], int(config["seed"]), config.get("control"))
    bounds = preflight(admit_sources,owners, int(config["envelope_side_m"])*5, int(config["fragment_budget"]))
    bounds["operational"] = preflight(operational_bounds,side_count(config["preset"]),len(owners),int(bounds["cells"]),
        sum(map(int,bounds["surface_rectangle_bounds"])),int(bounds["vertex_bound"]),
        int(config["warmup"])+int(config["frames"])+1,int(config["fragment_budget"]),
        tuple(map(int,config["resolution"].split("x"))))
    config["source_cells"] = bounds["cells"]
    if config.get("control"):
        from megascene_controls import source_effects
        bounds["control_effects"] = source_effects(config, owners)
    # This initial-state bound covers full meshes, retained box proxies, ground
    # and HUD. Edit cases additionally rely on evolving pre-edit native guards.
    render_vertices = checked(int(bounds["vertex_bound"])+36*len(owners)+6+50000, "static render vertices")
    bounds["static_native_byte_bound"] = str(checked(render_vertices*64*2, "static native arena capacity"))
    manifest["numeric_bounds"] = bounds
    manifest["numeric_admission"] = outcome("pass", "checked source and declared operational scale envelope",
                                             "candidate source, frame and native sizes", ["inputs.json"])
    frozen = preflight(schedule,config, owners)
    bounds["frozen_schedule"] = preflight(admit_schedule,config,frozen)
    if config["case"] == "history":
        created=sum(int(a["reference_components"]) for a in frozen["actions"])
        removed=sum(int(a["expected_removed_cells"]) for a in frozen["actions"])
        next_id=checked(len(owners)+1+created,"history lifetime next ID")
        live=checked(len(owners)+created-len(frozen["actions"]),"history live bodies")
        require(live<=len(owners)+int(config["fragment_budget"]),"history fragment budget preflight")
        bounds["history_evolving"]={"accepted_actions":str(len(frozen["actions"])),
                                    "planned_removed_cells":str(removed),
                                    "planned_final_cells":str(int(bounds["cells"])-removed),
                                    "planned_lifetime_next_id":str(next_id),
                                    "planned_final_live_bodies":str(live),
                                    "scope":"independent sparse preflight; each actual edit is re-guarded before unsafe code"}
    if config["case"] == "picking":
        bounds["picking"] = frozen["picking_admission"]
        manifest["numeric_admission"] = outcome("pass", "frozen target/operation preflight plus actual runtime guards before picking",
            "fixed-preset construction and bounded picking", ["inputs.json", "schedule.json"])
    if config["case"] in ("localized", "support", "history"):
        manifest["numeric_admission"] = outcome("pass", "frozen brush/reference removal; actual count, ID, predicate and native-size guards before unsafe edit", "bounded half-cell edits plus separated translated bodies", ["inputs.json", "schedule.json"])
    snapshot(output/"schedule.json", frozen)
    if config["case"] == "picking":
        from megascene_picking import ray_bytes
        (output/"rays.bin").write_bytes(ray_bytes(frozen))
    if config['case']=='support':
        from megascene_traversal import camera_bytes
        (output/'support-review.bin').write_bytes(camera_bytes({'frames':frozen['supplementary_views']}))
    extra_views = frozen.get('supplementary_views', []) if config['case'] != 'support' else []
    if extra_views:
        from megascene_supplementary import camera_bytes
        (output/'supplementary-review.bin').write_bytes(camera_bytes(extra_views))
    input_names = (("support-review.bin",) if config['case']=='support' else ()) + ("inputs.json", "schedule.json") + (("camera.bin",) if config["case"] in ("traversal", "picking", "localized", "support", "history") else ()) + (("rays.bin",) if config["case"] == "picking" else ())
    from megascene_performance import enabled, policy_bytes
    if enabled(config):
        (output/"frame-policy.bin").write_bytes(policy_bytes(frozen))
        input_names += ("frame-policy.bin",)
    if extra_views:
        input_names += ('supplementary-review.bin',)
    if config["case"] in ("traversal", "picking", "localized", "support", "history"):
        from megascene_traversal import camera_bytes
        (output/"camera.bin").write_bytes(camera_bytes(frozen))
    snapshot(output/"inputs.json", {"schema": SCHEMA, "record_type": "generation_inputs", "configuration": {k: config[k] for k in ("preset", "seed", "side_m", "envelope_side_m", "control", "fragment_budget")},
                                    "owners": [{"id": str(i), "role": owner.role,
                                                "neighborhood": None if owner.neighborhood is None else str(owner.neighborhood),
                                                "boxes": [b.record() for b in owner.boxes]} for i,owner in enumerate(owners,1)]})
    runtime = output/"runtime"
    reuse = config.get("validated") or config.get("runtime_from")
    source = None
    if reuse:
        from megascene_checkpoints import identity
        source = Path(reuse).expanduser().resolve()
        original = read_json((source/"manifest.json").read_text())
        identity(original, source, original["effective"])
        keys = ("case", "preset", "side_m", "envelope_side_m", "seed", "fragment_budget", "resolution", "diagnostic", "control", "warmup", "frames", "schedule")
        if config.get("validated"):
            keys += ("profile",)
        for key in keys:
            previous = original["effective"].get(key, original["effective"]["side_m"] if key == "envelope_side_m" else None)
            require(config.get(key) == previous, f"archived runtime configuration mismatch: {key}")
        require(canonical(frozen) == canonical(read_json((source/"schedule.json").read_text())), "archived schedule mismatch")
        shutil.copytree(source/"runtime", runtime)
        manifest["build"] = original["build"]
        manifest["source"] = original["source"]
        loader = Path(original["worker_command"][0]).name
        if not config.get("validated") and not enabled(config):
            from megascene_bend import retain_sources
            retain_sources(runtime)
            for name in ("megascene.py", "megascene_recipe.py", "megascene_bend.py", "megascene_scale.py", "megascene_controls.py", "megascene_inventory.py", "megascene_static.py", "megascene_report.py", "megascene_calibration.py", "megascene_calibration_series.py", "megascene_traversal.py", "megascene_picking.py", "megascene_proxy.py", "megascene_picking_references.py", "megascene_localized.py", "megascene_support.py", "megascene_history.py", "megascene_history_references.py", "megascene_support_references.py", "megascene_support_review.py", "megascene_supplementary.py", "megascene_edit_references.py", "megascene_gpu.py", "megascene_performance.py", "megascene_supervisor.py", "megascene_monitor.py", "megascene_checkpoints.py", "megascene_references.py", "megascene_validation.py"):
                shutil.copy2(ROOT/"scripts"/name, runtime/name)
        manifest["artifacts"] = [artifact(p,output) for p in sorted(runtime.rglob("*")) if p.is_file()]
        manifest["artifacts"] += [artifact(output/name,output) for name in input_names]
    else:
        runtime.mkdir()
        shutil.copytree(ROOT/"src", runtime/"src")
        (runtime/"build").mkdir()
        for name in ("megascene.py", "megascene_recipe.py", "megascene_bend.py", "megascene_scale.py", "megascene_controls.py", "megascene_inventory.py", "megascene_static.py", "megascene_report.py", "megascene_calibration.py", "megascene_calibration_series.py", "megascene_traversal.py", "megascene_picking.py", "megascene_proxy.py", "megascene_picking_references.py", "megascene_localized.py", "megascene_support.py", "megascene_history.py", "megascene_history_references.py", "megascene_support_references.py", "megascene_support_review.py", "megascene_supplementary.py", "megascene_edit_references.py", "megascene_gpu.py", "megascene_performance.py", "megascene_supervisor.py", "megascene_monitor.py", "megascene_checkpoints.py", "megascene_references.py", "megascene_validation.py"):
            shutil.copy2(ROOT/"scripts"/name, runtime/name)
        from megascene_references import program as reference_program
        (runtime/"src/megascene_reference_entry.bend").write_text(reference_program())
        if config["case"] == "picking":
            from megascene_picking_references import program as picking_reference_program
            (runtime/"src/megascene_picking_reference_entry.bend").write_text(picking_reference_program())
        if config["case"] in ("localized", "support", "history"):
            from megascene_edit_references import program as edit_reference_program
            (runtime/"src/megascene_edit_reference_entry.bend").write_text(edit_reference_program())
        if config["case"] == "support":
            from megascene_support_references import program as support_reference_program
            (runtime/"src/megascene_support_reference_entry.bend").write_text(support_reference_program(config))
        if config["case"] == "history":
            from megascene_history_references import program as history_reference_program
            (runtime/"src/megascene_history_reference_entry.bend").write_text(history_reference_program())
        (runtime/"src/megascene_entry.bend").write_text(worker_program(owners,config,frozen))
        require(subprocess.check_output(["bend", "version"], text=True).strip() == "bend 2.0.34", "Megascene requires Bend 2.0.34")
        commands = [["glslc", "--target-env=vulkan1.3", f"src/vulkan/{name}", "-o", f"build/vulkan-{name}.spv"] for name in ("scene.vert", "scene.frag", "shadow.vert")]
        commands += [["g++", "-O2", "-std=c++17", "-fPIC", "-shared", "-Wall", "-Wextra", "-Wno-missing-field-initializers", "src/vulkan/native.cpp", "-lvulkan", "-lX11", "-lcrypto", "-o", "build/libvoxel_vulkan.so"],
                     ["bend", "src/megascene_entry.bend", "-o", "worker.c"], ["bend", "src/megascene_entry.bend", "-o", "worker"],
                     ["bend", "src/megascene_reference_entry.bend", "-o", "reference-worker"]]
        if config["case"] == "picking":
            commands.append(["bend", "src/megascene_picking_reference_entry.bend", "-o", "picking-reference-worker"])
        if config["case"] in ("localized", "support", "history"):
            commands.append(["bend", "src/megascene_edit_reference_entry.bend", "-o", "edit-reference-worker"])
        if config["case"] == "support":
            commands.append(["bend", "src/megascene_support_reference_entry.bend", "-o", "support-reference-worker"])
        if config["case"] == "history":
            commands.append(["bend", "src/megascene_history_reference_entry.bend", "-o", "history-reference-worker"])
        manifest["build"] = {"commands": commands, "working_directory": "runtime", "bend": "bend 2.0.34",
                             "compilers": {name: subprocess.check_output([name, "--version"], text=True).splitlines()[0] for name in ("g++", "clang", "glslc")}}
        manifest["source"] = provenance()
        snapshot(output/"manifest.json",manifest)
        for i,command in enumerate(commands):
            run(command,runtime,output/f"build-{i}.stdout.log",output/f"build-{i}.stderr.log",120)
        libs = runtime/"lib"
        libs.mkdir()
        dependencies = subprocess.check_output(["ldd", str(runtime/"worker"), str(runtime/"build/libvoxel_vulkan.so")], text=True)
        (output/"dependencies.log").write_text(dependencies)
        loader = None
        for name in re.findall(r"(/[^\s:]+)",dependencies):
            path = Path(name)
            if path in (runtime/"worker", runtime/"build/libvoxel_vulkan.so"):
                continue
            if (libs/path.name).exists():
                require((libs/path.name).read_bytes() == path.read_bytes(), "conflicting dependency names")
            else:
                shutil.copy2(path,libs/path.name)
            if path.name.startswith("ld-linux"):
                loader = path.name
        require(loader, "static runner requires Linux/glibc")
        manifest["artifacts"] = [artifact(p,output) for p in sorted(runtime.rglob("*")) if p.is_file()]
        manifest["artifacts"] += [artifact(output/name,output) for name in input_names]
    manifest["runtime"]["graphics_requirements"] = "compatible host Vulkan ICD/driver, kernel and X11 session; application libraries are retained"
    if shutil.which("vulkaninfo"):
        driver = subprocess.run(["vulkaninfo", "--summary"], capture_output=True, text=True, timeout=20)
        (output/"vulkan-environment.log").write_text(driver.stdout+driver.stderr)
        manifest["runtime"]["vulkan_environment"] = {"path": "vulkan-environment.log", "exit_code": str(driver.returncode)}
    else:
        manifest["runtime"]["vulkan_environment"] = {"status": "unsupported", "reason": "vulkaninfo unavailable; actual renderer device properties are recorded"}
    manifest["runtime"]["display"] = os.environ.get("DISPLAY")
    manifest["clocks"] = {"cpu": "linux.CLOCK_MONOTONIC", "resolution_ns": str(round(time.get_clock_info("monotonic").resolution*1e9)),
                          "range": "unsigned 64-bit nanoseconds; no U32 microsecond conversion", "scope": "launch/frame/stage CPU wall time"}
    manifest["capabilities"] = {name: measurement("not_executed", "later capability", name, unit) for name,unit in
                                 (("gpu", "ns"), ("resources", "bytes"), ("allocations", "bytes"), ("calibration", "ratio"), ("validation_replay", "frames"))}
    for name in ("resources", "allocations"):
        manifest["capabilities"][name] = measurement("not_ready", "required supervision checked before work; see supervision.json", name, "bytes")
    manifest["capabilities"]["gpu"] = measurement("not_ready", "queried from the selected render queue during invocation", "submitted_frame_top_to_bottom", "ns")
    archive = Path(config["archive"])/manifest["campaign_id"]/manifest["series_id"]/manifest["attempt_id"]
    manifest["reproduction"] = {"archive": str(archive), "status": "preparing_archive",
                                "scope": "actual application executable/native library/shaders/source/frozen inputs and linked libraries; host graphics stack required"}
    manifest["worker_command"] = [f"runtime/lib/{loader}", "--library-path", "runtime/lib", "runtime/worker", "--gpu", "off", "--threads", config["threads"]]
    manifest["worker_environment"] = {"VOXEL_VULKAN_LIBRARY": "runtime/build/libvoxel_vulkan.so", "VOXEL_STRESS_PRESENT": "unpaced",
                                      "MEGASCENE_WARMUP": config["warmup"], "MEGASCENE_MEASURED": config["frames"],
                                      "MEGASCENE_GROUND": str(int(config["envelope_side_m"])//2+8),
                                      "MEGASCENE_SCHEDULE_SHA256": artifact(output/"schedule.json",output)["sha256"]}
    if enabled(config):
        manifest["worker_environment"].update(MEGASCENE_FRAME_POLICY="../frame-policy.bin",
            MEGASCENE_QUERY_PAIRS=str(len(frozen["frames"])))
        if config['case']=='history':
            manifest["worker_environment"]["MEGASCENE_HISTORY_OVERVIEW"]=frozen['performance_protocol']['overview_frame']
    if mode:
        manifest["worker_environment"]["MEGASCENE_CALIBRATION"] = mode
    if config.get("diagnostic"):
        manifest["worker_environment"]["MEGASCENE_PROXY_DIAGNOSTIC"] = config["diagnostic"]
        manifest["worker_environment"]["MEGASCENE_PROFILE"] = config["profile"]
    if config["case"] in ("traversal", "picking", "localized", "support", "history"):
        manifest["worker_environment"]["MEGASCENE_CAMERA_FILE"] = "../camera.bin"
    if config['case']=='support':
        manifest['worker_environment']['MEGASCENE_DETAIL_CAMERA_FILE']='../support-review.bin'
        manifest['worker_environment']['MEGASCENE_DETAIL_CAMERA_COUNT']=str(len(frozen['supplementary_views']))
    if extra_views:
        manifest['worker_environment']['MEGASCENE_SUPPLEMENTARY_FILE']='../supplementary-review.bin'
        manifest['worker_environment']['MEGASCENE_SUPPLEMENTARY_COUNT']=str(len(extra_views))
    if config["case"] == "picking":
        manifest["worker_environment"]["MEGASCENE_RAY_FILE"] = "../rays.bin"
    if config["case"] in ("localized", "support", "history"):
        manifest["worker_environment"]["MEGASCENE_"+config["case"].upper()] = "1"
    manifest["constants"] = {"lighting": "baseline-8c3ffad-daylight", "shadow_size": ["2048","2048"], "shadow_filter": "nearest compare LEQUAL; 3x3 receiver-plane PCF; depth bias 0.00005",
                             "projection": "0.05m near, infinite far, baseline focal 400 at 360px", "picking": config["case"] == "picking", "edits": config["case"] in ("localized", "support", "history"),
                             "palette": "runtime/src/color.bend", "lighting_constants": "runtime/src/vulkan/scene.frag",
                             "shadow_fit": "runtime/src/vulkan/native.cpp:shadow_matrix", "fixed_step": frozen["fixed_step"],
                             "proxy_bookkeeping": "retained; visible full meshes forced" if config["profile"] == "full" else "retained; actual 80/100 render-pixel selection", "ground_half_extent_m": str(int(config["envelope_side_m"])//2+8)}
    snapshot(output/"manifest.json",manifest)
    snapshot(output/"campaign.json", campaign.value)
    snapshot(output/"series.json", {"schema": SCHEMA, "record_type": "series", "series_id": manifest["series_id"],
        "configuration": config, "schedule_sha256": artifact(output/"schedule.json", output)["sha256"]})
    retained_copy(output,archive)
    manifest["reproduction"]["status"] = "runtime_archived_before_execution"
    snapshot(archive/"manifest.json",manifest)
    snapshot(output/"manifest.json",manifest)
    if config.get("calibration_peer_validation"):
        from megascene_calibration import verify_peer_validation
        peer = verify_peer_validation(config, manifest, archive)
        manifest["calibration_peer_validation"] = peer
        snapshot(archive/"manifest.json",manifest)
        snapshot(output/"manifest.json",manifest)
    # Run directly from archived bytes. Raw committed records survive local cleanup.
    from megascene_validation import validate_or_reuse, compare_attempt
    validation = validate_or_reuse(config, archive, manifest, loader, campaign, source, owners, bounds)
    snapshot(archive/"validation.json", validation)
    traversal_review = None
    if enabled(config) or config["case"] in ("traversal", "picking", "localized", "support", "history"):
        from megascene_traversal import review_evidence
        replay_records, _ = read_stream(archive/"validation"/"cpu.jsonl", validation["attempt_id"])
        traversal_review = review_evidence(archive, frozen, replay_records, config["profile"])
        if config['case']=='support':
            for view in traversal_review['views']:
                view['body_features']=[f for f in validation.get('beam_features',[]) if f['frame']==view['frame']]
        if config['case']=='support':
            from megascene_support_review import review_details
            review_details(archive,frozen,replay_records,traversal_review)
        elif extra_views:
            from megascene_supplementary import review_details
            review_details(archive,frozen,replay_records,traversal_review)
        snapshot(archive/"review.json", traversal_review)
    manifest["capabilities"]["validation_replay"] = measurement(
        "measured" if validation["status"] == "pass" else "incomplete",
        "separate complete "+config["case"]+" replay; see validation.json", config["case"]+" configuration", "frames",
        validation.get("checked_frames") if validation["status"] == "pass" else None)
    if config["validation_only"] or validation["status"] != "pass":
        report_value = read_json((archive/"validation/summary.json").read_text()) if (archive/"validation/summary.json").exists() else report([],[],config,2,"prelaunch_failure",0,manifest["attempt_id"])
        report_value["attempt_id"] = manifest["attempt_id"]
        report_value["attempt_kind"] = "validation_only" if config["validation_only"] else "validation_failed"
        report_value["measurement_scope"] = "validation execution cost; excluded from performance populations"
        manifest["extensions"]["phase"] = "validation_complete" if validation["status"] == "pass" else "validation_failed"
        report_value["state_correctness"] = outcome(validation["status"], "separate "+config["case"]+" validation", "complete declared "+config["case"]+" schedule", ["validation.json"])
        from megascene_performance import enabled
        if enabled(config) or config["case"] in ("traversal", "picking", "localized", "support", "history"):
            report_value["rendering_correctness"] = outcome(validation["status"], "native visibility, cache and shadow fit replay", "complete declared "+config["case"]+" schedule", ["validation.json", "validation/comparison.json"])
        report_value["validation"] = {"path": "validation.json", "status": validation["status"]}
        if traversal_review is not None:
            report_value["visual_quality"] = outcome("inconclusive", "named feature assessments remain pending" if not traversal_review["missing"] else "required traversal captures missing",
                "primary traversal full-profile fidelity", ["review.json"])
            report_value["review"] = {"path": "review.json", "status": traversal_review["status"]}
        snapshot(archive/"summary.json",report_value)
        finish_archive(archive,output,manifest)
        require(validation["status"] == "pass", config["case"]+" validation failed; see validation.json")
        return
    from megascene_checkpoints import applicable, identity
    from megascene_validation import verify_host_artifacts
    applicable(validation,identity(manifest,archive,config))
    verify_host_artifacts(validation)
    report_value, records = launch(config,archive,manifest,loader,campaign=campaign)
    if mode != "off":
        compare_attempt(config,archive,manifest,validation,report_value,records)
    if traversal_review is not None:
        report_value["visual_quality"] = outcome("inconclusive", "named feature assessments remain pending" if not traversal_review["missing"] else "required traversal captures missing",
            "primary traversal full-profile fidelity", ["review.json"])
        report_value["review"] = {"path": "review.json", "status": traversal_review["status"]}

    try:
        achieved = inventory((archive/"stdout.log").read_text(),owners,config,bounds)
        snapshot(archive/"inventory.json",achieved)
        report_value["initialization"] = outcome("pass", "actual initial world matches independent inventory reference", "initialization only", ["inventory.json", "stdout.log"])
    except (ValueError,KeyError,TypeError) as exc:
        report_value["initialization"] = outcome("fail",str(exc),"initialization only",["stdout.log"])
    manifest["admission"] = report_value["initialization"]
    report_value["numeric_validity"] = manifest["numeric_admission"]
    manifest["effective_render_settings"] = (report_value["effective_render_settings"] if mode != "off" else
        {"status": "disabled", "reason": "off control suppresses detailed render logging; frozen settings and runtime artifacts retained"})
    supervised = report_value["supervision"]
    for name in ("resources", "allocations"):
        manifest["capabilities"][name] = measurement(
            "measured" if supervised["termination"]["cause"] == "normal_exit" else "incomplete",
            "see supervision.json and attributed raw streams", name,
            "records", supervised["resource_samples" if name == "resources" else "allocation_records"]
            if supervised["termination"]["cause"] == "normal_exit" else None)
    manifest["extensions"]["phase"] = "complete"
    snapshot(archive/"summary.json",report_value)
    capture_ok = True
    report_value["opening_capture"] = outcome("inconclusive" if config["capture_opening"] else "not_applicable",
        "requested capture not executed after incomplete timed observation" if config["capture_opening"] else "capture not requested",
        "separate opening process")
    if config["capture_opening"] and report_value["schedule_completion"]["status"] == "pass":
        capture_manifest = {**manifest, "attempt_id": str(uuid.uuid4()), "attempt_kind": "opening_capture"}
        capture = archive/"captures"
        capture.mkdir()
        capture_manifest["artifacts"] = [{**entry, "path": "../"+entry["path"]} for entry in manifest["artifacts"]]
        capture_manifest["parent_attempt_id"] = manifest["attempt_id"]
        snapshot(capture/"manifest.json",capture_manifest)
        capture_report, _ = launch(config,archive,capture_manifest,loader,review=True,campaign=campaign)
        snapshot(capture/"summary.json",capture_report)
        capture_ok = capture_report["schedule_completion"]["status"] == "pass" and (capture/"opening.ppm").exists()
        ppm = capture/"opening.ppm"
        review = {"schema": SCHEMA, "record_type": "review", "attempt_id": capture_manifest["attempt_id"],
                  "schedule_sha256": artifact(archive/"schedule.json",archive)["sha256"], "profile": "full", "view": "opening",
                  "capture": artifact(ppm,archive) if ppm.exists() else None,
                  "assessment": outcome("inconclusive", "capture retained for feature review; no qualification implied", "opening silhouettes and major shadows"),
                  "timing_scope": "separate fresh process; excluded from timed observations"}
        snapshot(archive/"review.json",review)
        report_value["opening_capture"] = outcome("pass" if capture_ok else "fail",
            "separate opening capture retained" if capture_ok else "requested opening capture incomplete",
            "capture availability only; visual quality remains unqualified", ["review.json", "captures/summary.json"])
    snapshot(archive/"summary.json",report_value)
    if mode != "off":
        from megascene_report import report_bundle
        report_value = report_bundle(archive)
    snapshot(archive/"summary.json",report_value)
    manifest["qualification"] = report_value["qualification"]
    finish_archive(archive,output,manifest)
    require(capture_ok and report_value["schedule_completion"]["status"] == "pass" and report_value["initialization"]["status"] == "pass" and
            (report_value["endpoint_agreement"]["status"] == "pass" if mode == "off" else report_value["state_correctness"]["status"] == "pass"),
            config["case"]+" invocation did not complete correctly; retained summary describes the prefix")


def finish_archive(archive,output,manifest):
    from megascene import artifact, snapshot
    summary = read_json((archive/"summary.json").read_text())
    manifest["capabilities"]["gpu"] = summary.get("gpu_execution", {}).get("capability") or measurement(
        "not_executed", "render queue capability not observed; see summary.json", "submitted_frame_top_to_bottom", "ns")
    manifest["evidence"] = [artifact(p,archive) for p in sorted(archive.rglob("*")) if p.is_file() and "runtime" not in p.relative_to(archive).parts and p.relative_to(archive).as_posix() != "manifest.json"]
    snapshot(archive/"manifest.json",manifest)
    for p in archive.rglob("*"):
        if p.is_file() and "runtime" not in p.relative_to(archive).parts:
            dest = output/p.relative_to(archive)
            dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(p,dest)



def launch(config, archive, manifest, loader, review=False, campaign=None, validation=False):
    from megascene import snapshot
    destination = archive/"captures" if review else archive/"validation" if validation else archive
    env = {k:v for k,v in os.environ.items() if not k.startswith(("VOXEL_", "MEGASCENE_", "VK_", "LD_"))}
    env.update(manifest["worker_environment"])
    env.update(VOXEL_VULKAN_LIBRARY=str(archive/"runtime/build/libvoxel_vulkan.so"),
               MEGASCENE_EVENTS=str(destination/"cpu.jsonl"), MEGASCENE_ATTEMPT=manifest["attempt_id"],
               MEGASCENE_GPU=str(destination/"gpu.jsonl"),
               MEGASCENE_CAMPAIGN=manifest["campaign_id"], MEGASCENE_SERIES=manifest["series_id"],
               VK_LOADER_LAYERS_DISABLE="~all~")
    if validation:
        env["MEGASCENE_VALIDATE"] = "1"
        from megascene_performance import enabled
        if enabled(config) or config["case"] in ("traversal", "picking", "localized", "support", "history"):
            captures = destination/"captures"
            captures.mkdir(exist_ok=True)
            env["MEGASCENE_CAPTURE_DIR"] = str(captures)
    if review:
        env["MEGASCENE_CAPTURE"] = str(destination/"opening.ppm")
    command = [str(archive/f"runtime/lib/{loader}"), "--library-path", str(archive/"runtime/lib"), str(archive/"runtime/worker"),
               "--gpu", "off", "--threads", config["threads"]]
    from megascene_supervisor import supervise
    remaining = campaign.remaining_ns() if campaign is not None else 0
    supervised = supervise(command, archive/"runtime", env, destination, manifest, config, remaining)
    records, problems = read_stream(destination/"cpu.jsonl", manifest["attempt_id"])
    problems += supervised["errors"]
    termination = supervised["termination"]
    code = int(termination["exit_code"]) if termination["exit_code"] is not None else -int(termination["signal"]) if termination["signal"] else 2
    cause = termination["cause"]
    if config.get("calibration_mode") == "off" and not validation and not review:
        from megascene_calibration import off_result
        value = off_result(config, archive, manifest, read_json((archive/"validation.json").read_text()),
                           supervised, records, problems)
        snapshot(destination/"summary.json", value)
        if campaign is not None:
            campaign.attempt(manifest["attempt_id"], destination/"summary.json", cause)
        return value, records
    if cause == "worker_error" and "unpaced Vulkan present mode unavailable" in (destination/"stderr.log").read_text(errors="replace"):
        cause = "unsupported_presentation"
        termination["cause"] = cause
    from megascene_gpu import read_stream as read_gpu
    gpu_records, gpu_problems = read_gpu(destination/"gpu.jsonl", manifest)
    frozen = read_json((archive/"schedule.json").read_text())
    result = report(records, problems, config, code, cause, int(supervised["launch_ns"]), manifest["attempt_id"], review,
                    gpu_records, gpu_problems, frozen)
    result["termination"] = termination
    result["supervision"] = supervised
    result["reference_completed_prefix"] = {"frames": supervised["completed_frame_prefix"], "actions": supervised["completed_actions"]}
    snapshot(destination/"summary.json", result)
    if campaign is not None:
        campaign.attempt(manifest["attempt_id"], destination/"summary.json", cause)
    return result, records
