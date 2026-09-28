"""Bounded static Vulkan development observations through the public runner.

This slice never qualifies a benchmark: visual review qualification and calibration remain separate.
"""
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
from megascene_recipe import admit_sources, bend_program, bits, checked, generate
from megascene_gpu import u64


def settings(args, base):
    for name in ("diagnostic", "calibration", "search"):
        require(getattr(args, name) is None, f"--{name} is not implemented")
    require(args.profile in (None, "full"), "static supports only --profile full")
    if args.case == "traversal":
        from megascene_traversal import ROUTES
        require(args.schedule is None or args.schedule in ROUTES, "unsupported frozen schedule")
        schedule_id = args.schedule or "traversal-v2"
    else:
        schedule_id = "static-v1"
        require(args.schedule in (None, schedule_id), "unsupported frozen schedule")
    require(args.resolution in (None, "640x360", "1920x1080"), "static resolutions are 640x360 and 1920x1080")
    warmup = integer(args.warmup if args.warmup is not None else "120")
    frames = integer(args.frames if args.frames is not None else "3600")
    deadline = integer(args.deadline if args.deadline is not None else "300")
    require(0 <= warmup <= 120 and 1 <= frames <= 3600, "development schedules require 0..120 warmup and 1..3600 measured frames")
    if args.case == "traversal":
        require((warmup, frames) == (120, 3600), "primary traversal requires the complete 120/3600 schedule")
        require(not args.capture_opening, "traversal captures come from the separate validation replay")
    require(1 <= deadline <= 300, "development deadline must be 1..300 seconds")
    require(args.archive, "--case static requires an explicit durable --archive destination")
    archive = Path(args.archive).expanduser().resolve()
    output = Path(args.output).expanduser().resolve()
    require(not any(p in ("build", "dist", "tmp") for p in archive.parts), "archive must be outside disposable build/dist/tmp directories")
    require(archive != output and output not in archive.parents and archive not in output.parents,
            "archive and output must be separate directory trees")
    require(not (args.validated and args.runtime_from), "choose --validated or --runtime-from")
    require(not (args.validation_only and (args.validated or args.capture_opening)), "validation-only cannot reuse validation or request capture")
    return {**base, "validation_only": args.validation_only, "validated": args.validated, "runtime_from": args.runtime_from, "case": args.case, "profile": "full", "resolution": args.resolution or "1920x1080",
            "warmup": str(warmup), "frames": str(frames), "schedule": schedule_id, "deadline_s": str(deadline),
            "capture_opening": args.capture_opening, "archive": str(archive),
            "schedule_kind": "accepted" if (warmup, frames) == (120, 3600) else "declared_development_prefix"}


def schedule(config):
    if config.get("case") == "traversal":
        from megascene_traversal import schedule as traversal_schedule
        return traversal_schedule(config)
    origin = -int(config["side_m"])*5
    eye = [(150+origin)/10, 12, (310+origin)/10]
    delta = [-74, -72, -234]
    camera = {"eye_m": list(map(bits, eye)), "yaw": bits(math.atan2(delta[0], delta[2])),
              "pitch": bits(math.atan2(delta[1], math.hypot(delta[0], delta[2])))}
    frames = [{"frame": str(i), "phase": "startup" if i == 0 else "warmup" if i <= int(config["warmup"]) else "ordinary",
               "measured_ordinal": str(i-1-int(config["warmup"])) if i > int(config["warmup"]) else None,
               "camera": camera, "picking": False, "actions": []}
              for i in range(1+int(config["warmup"])+int(config["frames"]))]
    return {"schema": SCHEMA, "record_type": "schedule", "fixed_step": "0x3c888889",
            "schedule_id": "static-v1", "warmup_frames": config["warmup"], "measured_frames": config["frames"],
            "opening": camera, "frames": frames, "actions": [],
            "review_views": [{"name": "opening", "frame": "0", "features": ["building silhouettes", "span silhouettes", "major shadows"]}],
            "required_checkpoints": [{"name": "initialization", "frame": "0"}, {"name": "review_opening", "frame": "0"},
                                     {"name": "warmup_end", "frame": config["warmup"]},
                                     {"name": "completion", "frame": str(int(config["warmup"])+int(config["frames"]))}],
            "checkpoint_implementation": "megascene-checkpoint/1",
            "update_order": ["physics", "edit_disabled", "view_picking_disabled", "render"]}


def worker_program(owners, config, frozen):
    source = bend_program(owners, int(config["fragment_budget"])).split("def main()", 1)[0]
    module = "megascene_traversal" if config["case"] == "traversal" else "megascene_static"
    source = source.replace("import Base", f"import Base\nimport ./src/{module}.bend as Static\nimport ./src/vulkan.bend as VK\nimport ./src/render.bend as V")
    def real(value):
        decoded = struct.unpack(">f", bytes.fromhex(value[2:]))[0]
        return f"(0.0 - {abs(decoded)!r} : F32)" if decoded < 0 else repr(decoded)
    camera = frozen["opening"]
    width, height = config["resolution"].split("x")
    cam = "V.Camera{R.Vec{"+",".join(map(real, camera["eye_m"]))+"},"+real(camera["yaw"])+","+real(camera["pitch"])+f",{width},{height}"+"}"
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
    Static.start(world,{f'{width},{height}' if config['case'] == 'traversal' else f'{cam},{width},{height}'},{int(config['warmup'])+int(config['frames'])}n)
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
            require(r["record_type"] in {"worker_start", "stage", "static_state", "render_settings", "palette", "render_work", "frame", "opening_capture", "capture", "complete", "window_closed", "checkpoint", "static_audit", "native_audit", "presentation_status"}, "unknown evidence record type")
            if r["record_type"] in ("frame", "stage"):
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


def audit_observation(records, config, frames):
    errors = []
    try:
        settings_records = [r for r in records if r["record_type"] == "render_settings"]
        if frames:
            require(len(settings_records) == 1, "missing or duplicate effective render settings")
            actual = settings_records[0]
            width, height = config["resolution"].split("x")
            require((actual["width"], actual["height"], actual["profile"], actual["shadow_size"], actual["night"]) ==
                    (width, height, "full", "2048", "0"), "effective rendering settings mismatch")
            require(actual["present_mode"] in ("immediate", "mailbox"), "unsupported presentation mode")
            require(str(actual["ground_half_extent_m"]) == str(int(config["side_m"])//2+8), "ground bounds mismatch")
        frozen = schedule(config)
        owners = 21 if config["preset"] == "small" else 81
        by_frame = {}
        for r in records:
            by_frame.setdefault(r["frame"], []).append(r)
        for f in frames:
            items = by_frame[f["frame"]]
            state = [r for r in items if r["record_type"] == "static_state"]
            work = [r for r in items if r["record_type"] == "render_work"]
            require(len(state) == len(work) == 1, "missing or duplicate state/render work")
            state, work = state[0], work[0]
            camera = frozen["frames"][int(f["frame"])]["camera"]
            require({k:state[k] for k in camera} == camera, "actual view differs from frozen camera schedule")
            require(state["anchored"] == str(owners) and all(state[k] == "0" for k in ("moving", "translated", "aim_kind", "fragments", "removed")), "static state mismatch")
            require(state["cells"] == ("10503360" if owners == 21 else "42096576") and state["next_id"] == str(owners+1) and state["budget"] == config["fragment_budget"], "static world inventory mismatch")
            require(work["body_count"] == work["full_meshes"] == str(owners), "full meshes missing")
            require(work["proxy_draws"] == "0" and work["main_body_draws"] == work["visible_bodies"], "full geometry substitution")
            stages = [r for r in items if r["record_type"] == "stage"]
            required = {"transport", "renderer", "geometry", "fence_wait", "vertex_upload", "acquire", "command_record", "submit_present", "events"}
            required |= {"generation", "initial_surfaces", "initial_inventory", "window_setup", "renderer_setup"} if f["frame"] == "0" else {"physics", "view"}
            if any(r["record_type"] in ("checkpoint", "static_audit") for r in items):
                required.add("checkpoint")
            require({r["stage"] for r in stages} == required and len(stages) == len(required), "missing or duplicate CPU stage")
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


def report(records, problems, config, exit_code, cause, launch_ns, attempt_id, review=False, gpu_records=None, gpu_problems=None):
    frames = [r for r in records if r["record_type"] == "frame"]
    prefix = []
    for r in frames:
        i = len(prefix)
        expected = "startup" if i == 0 else "warmup" if i <= int(config["warmup"]) else "ordinary"
        if (r["frame"] != str(i) or r["population"] != expected or
            (i and r["begin_ns"] != prefix[-1]["end_ns"])):
            problems.append("frame sequence/population/boundary mismatch")
            break
        prefix.append(r)
    problems = list(problems) + audit_observation(records, config, prefix)
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
    missing = outcome("inconclusive", "not implemented in static development slice", "complete qualified attempt")
    result = {"schema": SCHEMA, "record_type": "summary", "attempt_id": attempt_id,
              "attempt_kind": "opening_capture" if review else "development_observation", "synthetic": False,
              "qualification": "unqualified_development_observation",
              **{k: dict(missing) for k in ("state_correctness", "rendering_correctness", "visual_quality", "numeric_validity",
                  "population_qualification", "calibration", "responsiveness", "qualified_capacity", "interactive_pass")},
              "schedule_completion": outcome("pass" if complete else "inconclusive", "declared schedule completed" if complete else "incomplete or invalid evidence",
                                             "opening capture only" if review else config["schedule_kind"], ["cpu.jsonl", "gpu.jsonl"]),
              "completed_prefix": {"startup": bool(prefix), "warmup": str(min(max(0,len(prefix)-1),int(config["warmup"]))),
                                   "measured": str(max(0,len(prefix)-1-int(config["warmup"])))},
              "termination": {"cause": cause, "exit_code": str(exit_code) if exit_code >= 0 else None,
                              "signal": str(-exit_code) if exit_code < 0 else None},
              "evidence_errors": problems,
              "limitations": ["No instrumentation calibration; GPU queries and supervised resources are separate evidence.",
                              "CPU intervals include instrumentation; no physical display latency claim.", "Unsafe/native behavior is runtime evidence, never a formal proof."],
              "measurement_availability": measurement("measured", "CPU frame-effect boundaries", "completed frame prefix", "frames", str(len(prefix)))
                  if prefix else measurement("not_executed", "no frame returned", "attempt", "frames")}
    populations = {}
    for name in ("warmup", "ordinary"):
        values = [int(r["end_ns"])-int(r["begin_ns"]) for r in prefix if r["population"] == name]
        populations[name] = {**distribution(values), "observation_interval_ns": str(sum(values))}
    result["populations"] = populations
    ordinary = populations["ordinary"]
    enough = int(ordinary["count"]) >= 1000 and int(ordinary["observation_interval_ns"]) >= 10_000_000_000
    result["population_qualification"] = outcome("inconclusive",
        "sample minimums reached; validation and measurement qualification unavailable" if enough else
        "insufficient population: requires 1000 ordinary frames and 10 measured seconds without extending the frozen schedule",
        "ordinary population", ["cpu.jsonl"])
    result["edit_response"] = outcome("not_applicable", "static schedule disables edits", "accepted edits")
    result["cold_startup"] = measurement("measured", "process launch to first usable frame-effect return", "startup", "ns",
                                           str(int(prefix[0]["end_ns"])-launch_ns)) if prefix and int(prefix[0]["end_ns"]) >= launch_ns else measurement("incomplete", "first usable frame unavailable", "startup", "ns")
    result["startup_stages"] = [r for r in records if r["record_type"] == "stage" and r["frame"] == "0"]
    result["teardown"] = [r for r in records if r.get("stage") == "teardown"]
    tail = next((r for r in records if r.get("stage") == "teardown"), None)
    result["final_bookkeeping"] = measurement("measured", "last frame-effect return to teardown begin; excluded from frame populations", "final bookkeeping", "ns",
        str(int(tail["begin_ns"])-int(prefix[-1]["end_ns"]))) if tail and prefix else measurement("incomplete", "final boundary unavailable", "final bookkeeping", "ns")
    result["effective_render_settings"] = next((r for r in records if r["record_type"] == "render_settings"), None)
    from megascene_gpu import summarize
    result["gpu_execution"] = summarize(gpu_records or [], gpu_problems or [], prefix, config)
    gpu = result["gpu_execution"]
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
                                                config["schedule_kind"], ["cpu.jsonl", "gpu.jsonl"])
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
    manifest.update(attempt_kind="development_observation", campaign_id=campaign.value["campaign_id"], series_id=str(uuid.uuid4()))
    manifest["qualification"] = "unqualified_development_observation"
    manifest["extensions"]["phase"] = "static_build"
    owners = generate(config["preset"], int(config["seed"]))
    bounds = admit_sources(owners, int(config["side_m"])*5, int(config["fragment_budget"]))
    # Static worlds have no lifetime ID growth or moving offsets. Account for
    # full meshes, retained box proxies, ground and the fixed short HUD, plus
    # arena growth slack; the two presets stay far inside U32 and size_t.
    render_vertices = checked(int(bounds["vertex_bound"])+36*len(owners)+6+50000, "static render vertices")
    bounds["static_native_byte_bound"] = str(checked(render_vertices*64*2, "static native arena capacity"))
    manifest["numeric_bounds"] = bounds
    manifest["numeric_admission"] = outcome("pass", "fixed all-anchored inputs; no edits/motion; bounded frame and native sizes",
                                             "static fixed-preset initialization", ["inputs.json"])
    frozen = schedule(config)
    snapshot(output/"schedule.json", frozen)
    if config["case"] == "traversal":
        from megascene_traversal import camera_bytes
        (output/"camera.bin").write_bytes(camera_bytes(frozen))
    snapshot(output/"inputs.json", {"schema": SCHEMA, "record_type": "generation_inputs", "configuration": {k: config[k] for k in ("preset", "seed", "side_m", "fragment_budget")},
                                    "owners": [{"id": str(i), "role": owner.role, "boxes": [b.record() for b in owner.boxes]} for i,owner in enumerate(owners,1)]})
    runtime = output/"runtime"
    reuse = config.get("validated") or config.get("runtime_from")
    source = None
    if reuse:
        from megascene_checkpoints import identity
        source = Path(reuse).expanduser().resolve()
        original = read_json((source/"manifest.json").read_text())
        identity(original, source, original["effective"])
        for key in ("case", "preset", "side_m", "seed", "fragment_budget", "resolution", "profile", "warmup", "frames", "schedule"):
            require(config[key] == original["effective"][key], f"archived runtime configuration mismatch: {key}")
        require(canonical(frozen) == canonical(read_json((source/"schedule.json").read_text())), "archived schedule mismatch")
        shutil.copytree(source/"runtime", runtime)
        manifest["build"] = original["build"]
        manifest["source"] = original["source"]
        loader = Path(original["worker_command"][0]).name
        for name in ("megascene.py", "megascene_recipe.py", "megascene_inventory.py", "megascene_static.py", "megascene_traversal.py", "megascene_gpu.py", "megascene_supervisor.py", "megascene_monitor.py", "megascene_checkpoints.py", "megascene_references.py", "megascene_validation.py"):
            shutil.copy2(ROOT/"scripts"/name, runtime/name)
        manifest["artifacts"] = [artifact(p,output) for p in sorted(runtime.rglob("*")) if p.is_file()]
        manifest["artifacts"] += [artifact(output/name,output) for name in (("inputs.json", "schedule.json", "camera.bin") if config["case"] == "traversal" else ("inputs.json", "schedule.json"))]
    else:
        runtime.mkdir()
        shutil.copytree(ROOT/"src", runtime/"src")
        (runtime/"build").mkdir()
        for name in ("megascene.py", "megascene_recipe.py", "megascene_inventory.py", "megascene_static.py", "megascene_traversal.py", "megascene_gpu.py", "megascene_supervisor.py", "megascene_monitor.py", "megascene_checkpoints.py", "megascene_references.py", "megascene_validation.py"):
            shutil.copy2(ROOT/"scripts"/name, runtime/name)
        from megascene_references import program as reference_program
        (runtime/"src/megascene_reference_entry.bend").write_text(reference_program())
        (runtime/"src/megascene_entry.bend").write_text(worker_program(owners,config,frozen))
        require(subprocess.check_output(["bend", "version"], text=True).strip() == "bend 2.0.32", "Megascene requires Bend 2.0.32")
        commands = [["glslc", "--target-env=vulkan1.3", f"src/vulkan/{name}", "-o", f"build/vulkan-{name}.spv"] for name in ("scene.vert", "scene.frag", "shadow.vert")]
        commands += [["g++", "-O2", "-std=c++17", "-fPIC", "-shared", "-Wall", "-Wextra", "-Wno-missing-field-initializers", "src/vulkan/native.cpp", "-lvulkan", "-lX11", "-lcrypto", "-o", "build/libvoxel_vulkan.so"],
                     ["bend", "src/megascene_entry.bend", "-o", "worker.c"], ["bend", "src/megascene_entry.bend", "-o", "worker"],
                     ["bend", "src/megascene_reference_entry.bend", "-o", "reference-worker"]]
        manifest["build"] = {"commands": commands, "working_directory": "runtime", "bend": "bend 2.0.32",
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
        manifest["artifacts"] += [artifact(output/name,output) for name in (("inputs.json", "schedule.json", "camera.bin") if config["case"] == "traversal" else ("inputs.json", "schedule.json"))]
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
                                      "MEGASCENE_GROUND": str(int(config["side_m"])//2+8),
                                      "MEGASCENE_SCHEDULE_SHA256": artifact(output/"schedule.json",output)["sha256"]}
    if config["case"] == "traversal":
        manifest["worker_environment"]["MEGASCENE_CAMERA_FILE"] = "../camera.bin"
    manifest["constants"] = {"lighting": "baseline-8c3ffad-daylight", "shadow_size": ["2048","2048"], "shadow_filter": "nearest compare LEQUAL; 3x3 receiver-plane PCF; depth bias 0.00005",
                             "projection": "0.05m near, infinite far, baseline focal 400 at 360px", "picking": False, "edits": False,
                             "palette": "runtime/src/color.bend", "lighting_constants": "runtime/src/vulkan/scene.frag",
                             "shadow_fit": "runtime/src/vulkan/native.cpp:shadow_matrix", "fixed_step": frozen["fixed_step"],
                             "proxy_bookkeeping": "retained; visible full meshes forced", "ground_half_extent_m": str(int(config["side_m"])//2+8)}
    snapshot(output/"manifest.json",manifest)
    snapshot(output/"campaign.json", campaign.value)
    snapshot(output/"series.json", {"schema": SCHEMA, "record_type": "series", "series_id": manifest["series_id"],
        "configuration": config, "schedule_sha256": artifact(output/"schedule.json", output)["sha256"]})
    retained_copy(output,archive)
    manifest["reproduction"]["status"] = "runtime_archived_before_execution"
    snapshot(archive/"manifest.json",manifest)
    snapshot(output/"manifest.json",manifest)
    # Run directly from archived bytes. Raw committed records survive local cleanup.
    from megascene_validation import validate_or_reuse, compare_attempt
    validation = validate_or_reuse(config, archive, manifest, loader, campaign, source, owners, bounds)
    snapshot(archive/"validation.json", validation)
    traversal_review = None
    if config["case"] == "traversal":
        from megascene_traversal import review_evidence
        replay_records, _ = read_stream(archive/"validation"/"cpu.jsonl", validation["attempt_id"])
        traversal_review = review_evidence(archive, frozen, replay_records)
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
        if config["case"] == "traversal":
            report_value["rendering_correctness"] = outcome(validation["status"], "native visibility, cache and shadow fit replay", "complete declared traversal schedule", ["validation.json", "validation/comparison.json"])
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
    manifest["effective_render_settings"] = report_value["effective_render_settings"]
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
    finish_archive(archive,output,manifest)
    require(capture_ok and report_value["schedule_completion"]["status"] == "pass" and report_value["initialization"]["status"] == "pass" and report_value["state_correctness"]["status"] == "pass",
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
        if config["case"] == "traversal":
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
    if cause == "worker_error" and "unpaced Vulkan present mode unavailable" in (destination/"stderr.log").read_text(errors="replace"):
        cause = "unsupported_presentation"
        termination["cause"] = cause
    from megascene_gpu import read_stream as read_gpu
    gpu_records, gpu_problems = read_gpu(destination/"gpu.jsonl", manifest)
    result = report(records, problems, config, code, cause, int(supervised["launch_ns"]), manifest["attempt_id"], review,
                    gpu_records, gpu_problems)
    result["termination"] = termination
    result["supervision"] = supervised
    result["reference_completed_prefix"] = {"frames": supervised["completed_frame_prefix"], "actions": supervised["completed_actions"]}
    snapshot(destination/"summary.json", result)
    if campaign is not None:
        campaign.attempt(manifest["attempt_id"], destination/"summary.json", cause)
    return result, records
