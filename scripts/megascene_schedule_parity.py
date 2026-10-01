"""Compare complete schedules against pre-migration canonical byte hashes."""
import argparse
import hashlib
import json
from pathlib import Path

from megascene_inventory import canonical
from megascene_static import schedule_document
from megascene_schedule import checkpoint_bytes, review_bytes, camera_bytes, policy_bytes, ray_bytes, supplementary_bytes


def configurations():
    base = dict(preset="small", side_m="64", seed="45", threads="6",
                fragment_budget="2048", resolution="1920x1080", profile="full",
                warmup="120", frames="3600")
    for preset, side in (("small", "64"), ("large", "128"), ("scale-3", "96"), ("scale-5", "160")):
        for seed in ("45", "46"):
            for case in ("static", "traversal", "picking", "localized", "support", "history"):
                route = case + ("-v2" if case in ("traversal", "picking") or
                                case == "history" and preset.startswith("scale-") else "-v1")
                yield {**base, "preset": preset, "side_m": side, "seed": seed, "case": case, "schedule": route}
    for case, routes in (("traversal", ("traversal-v1",)), ("picking", ("picking-v1",)),
                         ("history", ("history-12-v1", "history-48-v1", "history-perf-v2")),
                         ("support", ("support-1-span-v1", "support-2-span-v1")),
                         ("static", ("static-perf-v2",))):
        for route in routes:
            yield {**base, "case": case, "schedule": route,
                   "frames": "21600" if "perf" in route else "3600"}
    for case, control in (("static", "spread"), ("static", "material-detail"), ("static", "surface-detail"),
                          ("localized", "material-detail"), ("support", "fill"),
                          ("history", "fill"), ("history", "body-rich")):
        yield {**base, "case": case, "control": control, "schedule": f"{control}-{case}-v1",
               "envelope_side_m": "128" if control == "spread" else "64"}
    for diagnostic in ("compact-reference", "mixed-world"):
        for case in ("traversal", "picking"):
            yield {**base, "case": case, "diagnostic": diagnostic,
                   "schedule": f"proxy-{diagnostic}-{case}-v1"}
    for warmup, frames in (("0", "1"), ("1", "2"), ("120", "3599")):
        yield {**base, "case": "static", "schedule": "static-v1", "warmup": warmup, "frames": frames}
    for preset, side in (("small", "64"), ("large", "128"), ("scale-3", "96"), ("scale-5", "160")):
        for seed in ("45", "46"):
            if preset == "small" and seed == "45":
                continue
            for case in ("traversal", "picking"):
                yield {**base, "preset": preset, "side_m": side, "seed": seed,
                       "case": case, "schedule": case + "-v1"}


def signature(frozen):
    cameras = [{k: f[k] for k in ("camera", "ray") if k in f} for f in frozen["frames"]]
    return {"schedule_sha256": hashlib.sha256(canonical(frozen)).hexdigest(),
            "camera_ray_sha256": hashlib.sha256(canonical(cameras)).hexdigest(),
            "frames": len(frozen["frames"]), "actions": len(frozen["actions"])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, default=Path(__file__).resolve().parents[1] / "tests/fixtures/megascene_schedule_bits.json")
    parser.add_argument("--runtime-baseline", type=Path, default=Path(__file__).resolve().parents[1] / "tests/fixtures/megascene_runtime_artifact_bits.json")
    parser.add_argument("--capture", action="store_true")
    args = parser.parse_args()
    if args.capture and args.baseline.exists():
        parser.error("refusing to overwrite a retained baseline; choose a new --baseline path")
    expected = None if args.capture else json.loads(args.baseline.read_text())
    runtime_expected = None if args.capture else json.loads(args.runtime_baseline.read_text())
    if expected is not None and len(expected) != len(runtime_expected):
        raise AssertionError("runtime baseline configuration count differs")
    rows = []
    for index, config in enumerate(configurations()):
        frozen, data = schedule_document(config)
        if data is not None and data != canonical(frozen)+b"\n":
            raise AssertionError(f"Bend schedule document is not canonical for {config}")
        actual = {"config": config, **signature(frozen)}
        if expected is not None and actual != expected[index]:
            raise AssertionError(f"schedule parity differs for {config}\nexpected {expected[index]}\nactual {actual}")
        if runtime_expected is not None:
            if runtime_expected[index]["config"] != config:
                raise AssertionError("runtime baseline configuration differs")
            artifacts = {"checkpoints": checkpoint_bytes(frozen), "reviews": review_bytes(frozen),
                         "camera": camera_bytes(frozen), "policy": policy_bytes(frozen)}
            if "ray" in frozen["frames"][0]:
                artifacts["rays"] = ray_bytes(frozen)
            if frozen.get("supplementary_views"):
                artifacts["supplementary"] = supplementary_bytes(frozen["supplementary_views"])
            if set(artifacts) != set(runtime_expected[index]["artifacts"]):
                raise AssertionError("runtime baseline artifact set differs")
            for kind, data in artifacts.items():
                measured = {"sha256": hashlib.sha256(data).hexdigest(), "size_bytes": len(data)}
                if measured != runtime_expected[index]["artifacts"][kind]:
                    raise AssertionError(f"{kind} byte parity differs for {config}")
        rows.append(actual)
        print(f"{index + 1} {config['schedule']} {config['preset']} seed {config['seed']} schedule/runtime bytes exact", flush=True)
    if args.capture:
        args.baseline.write_text(json.dumps(rows, indent=2) + "\n")
    elif len(rows) != len(expected):
        raise AssertionError("baseline configuration count differs")


if __name__ == "__main__":
    main()
