"""Frozen primary Megascene traversal views and independent route checks."""
import hashlib
import math
import struct

from megascene_inventory import SCHEMA, canonical, digest, integer, require
from megascene_recipe import bits

PHASES = (("opening", 0), ("wall", 0), ("interior", 0), ("cavity", 0),
          ("assembly", 0), ("far", None), ("opening", -1), ("cavity", -1),
          ("sky", 0), ("opening", 0), ("opening", 0), ("opening", 0))
FEATURES = {
    "opening": ["building silhouettes", "span silhouettes", "major shadows"],
    "wall": ["exterior plaster wall"],
    "interior": ["clear interior doorway", "interior wall"],
    "cavity": ["cavity depth", "open air", "cavity bridge"],
    "assembly": ["irregular lobes", "material distinctions"],
    "far": ["whole district extent", "major structures", "major shadows"],
    "sky": ["open sky"],
}
ROUTES = ("traversal-v1", "traversal-v2")


def f32(value):
    return struct.unpack("<f", struct.pack("<f", value))[0]


def pose(name, neighborhood, preset, seed, route):
    require(route in ROUTES, "unsupported traversal route")
    q = 2 if preset == "small" else 4
    if name == "far":
        side = 32 * q
        eye, look = (0, .75*side, 1.25*side), (0, 2.4, 0)
    else:
        n = q*q-1 if neighborhood == -1 else neighborhood
        ix, iz = n % q, n // q
        ox, oz = 320*ix-160*q, 320*iz-160*q
        variation = (3*ix+5*iz+seed-45) % 4
        top = 58+variation%2
        local = {
            "opening": ((150,120,310),(76,48,76)),
            "wall": ((8,48,60),(16,48,60)),
            "interior": ((116,44,80),(20,44,80)),
            "cavity": (((256,70,210),(256,12,272)) if route == "traversal-v2"
                       else ((256,44,244),(256,8,256))),
            "assembly": ((284,90,160),(284,top,180)),
            "sky": ((160,120,160),(160,220,260)),
        }
        source, target = local[name]
        eye = ((source[0]+ox)/10,source[1]/10,(source[2]+oz)/10)
        look = ((target[0]+ox)/10,target[1]/10,(target[2]+oz)/10)
    return eye, look


def camera(eye, look):
    delta = [b-a for a,b in zip(eye,look)]
    require(any(delta), "degenerate traversal camera")
    return {"eye_m": [bits(x) for x in eye],
            "yaw": bits(math.atan2(delta[0],delta[2])),
            "pitch": bits(math.atan2(delta[1],math.hypot(delta[0],delta[2])))}


def schedule(config):
    warmup, measured = int(config["warmup"]), int(config["frames"])
    require(warmup == 120 and measured == 3600, "primary traversal requires the complete 120/3600 schedule")
    route = config.get("schedule", "traversal-v2")
    require(route in ROUTES, "unsupported traversal route")
    endpoints = [pose(name,n,config["preset"],int(config["seed"]),route) for name,n in PHASES]
    opening = camera(*endpoints[0])
    frames = []
    for frame in range(1+warmup+measured):
        if frame <= warmup:
            view, phase, offset = opening, "opening", None
        else:
            measured_frame = frame-warmup-1
            phase_index, offset = divmod(measured_frame,300)
            phase = PHASES[phase_index][0]
            if offset < 120:
                eye, look = endpoints[phase_index]
            else:
                t = (offset-119)/180
                first, second = endpoints[phase_index], endpoints[min(phase_index+1,11)]
                if offset == 299:
                    eye, look = second
                else:
                    eye = tuple(f32(a+(b-a)*t) for a,b in zip(first[0],second[0]))
                    look = tuple(f32(a+(b-a)*t) for a,b in zip(first[1],second[1]))
            view = camera(eye,look)
        frames.append({"frame": str(frame), "phase": "startup" if frame == 0 else "warmup" if frame <= warmup else "ordinary",
                       "measured_ordinal": str(frame-warmup-1) if frame>warmup else None,
                       "route_phase": phase if frame>warmup else None,
                       "phase_offset": str(offset) if offset is not None else None,
                       "camera": view, "picking": False, "actions": []})
    reviews = [{"name": "opening", "frame": "0", "features": FEATURES["opening"]}]
    checkpoints = [{"name": "initialization", "frame": "0"},
                   {"name": "review_opening", "frame": "0"},
                   {"name": "warmup_end", "frame": str(warmup)}]
    for i,(name,n) in enumerate(PHASES):
        frame = str(warmup+1+300*i+60)
        review_name = f"review_route_{i:02d}"
        features = FEATURES[name]+(["unchanged return geometry"] if i >= 6 else [])
        reviews.append({"name": review_name, "frame": frame, "pose": name,
                        "neighborhood": None if n is None else str((2 if config["preset"] == "small" else 4)**2-1 if n == -1 else n),
                        "features": features})
        checkpoints.append({"name": review_name, "frame": frame})
    reviews.append({"name": "completion", "frame": str(warmup+measured),
                    "pose": "opening", "features": ["unchanged return geometry", "major shadows"]})
    checkpoints.append({"name": "completion", "frame": str(warmup+measured)})
    return {"schema": SCHEMA, "record_type": "schedule", "fixed_step": "0x3c888889",
            "schedule_id": route, "warmup_frames": str(warmup), "measured_frames": str(measured),
            "opening": opening, "frames": frames, "actions": [], "review_views": reviews,
            "required_checkpoints": checkpoints, "checkpoint_implementation": "megascene-checkpoint/1",
            "update_order": ["physics", "edit_disabled", "view_picking_disabled", "render"]}


def camera_bytes(frozen):
    data = bytearray()
    for frame in frozen["frames"]:
        view = frame["camera"]
        data.extend(struct.pack("<5I", *(int(value,16) for value in (*view["eye_m"],view["yaw"],view["pitch"]))))
    return bytes(data)


def expected_payload(initial, frame):
    view = frame["camera"]
    return {**initial, "view": {**initial["view"], **view}}


def review_evidence(archive, frozen, records, profile="full"):
    """Bind off-sample captures and shadow coverage to each named review view."""
    import pathlib
    archive = pathlib.Path(archive)
    capture_records = [r for r in records if r["record_type"] == "capture"]
    by_frame = {r["frame"]: r for r in records if r["record_type"] == "render_work"}
    entries, missing = [], []
    expected_frames = {r["frame"] for r in frozen["review_views"]}
    seen_frames = [r["rendered_frame"] for r in capture_records]
    require(len(seen_frames) == len(set(seen_frames)), "duplicate traversal capture")
    require(set(seen_frames) <= expected_frames, "unexpected traversal capture")
    for review in frozen["review_views"]:
        frame = review["frame"]
        path = archive/"validation"/"captures"/f"frame-{int(frame):04d}.ppm"
        recorded = frame in seen_frames
        captured = path.is_file() and path.stat().st_size > 16
        if not recorded or not captured or frame not in by_frame:
            missing.append(review["name"])
        work = by_frame.get(frame)
        entries.append({"name": review["name"], "frame": frame,
                        "pose": review.get("pose", "opening"),
                        "features": [{"name": feature, "geometry": "pending", "readability": "pending"}
                                     for feature in review["features"]],
                        "capture": {"path": path.relative_to(archive).as_posix(),
                                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                                    "size_bytes": str(path.stat().st_size)} if captured else None,
                        "shadow_extent_m": work["shadow_extent_m"] if work else None,
                        "shadow_texel_m": work["shadow_texel_m"] if work else None,
                        "shadow_fit_min_margin_texels": work.get("shadow_fit_min_margin_texels") if work else None,
                        "capture_recorded": recorded})
    return {"schema": SCHEMA, "record_type": "review", "schedule_sha256": hashlib.sha256(canonical(frozen)+b"\n").hexdigest(),
            "profile": profile, "timing_scope": "separate complete validation replay; captures excluded from measured attempt",
            "status": "incomplete" if missing else "awaiting_named_feature_review",
            "missing": missing, "views": entries,
            "classification_rule": "missing/stale geometry fails rendering_correctness; correctly rendered but unreadable major features fail visual_quality; pending review cannot pass fidelity"}
