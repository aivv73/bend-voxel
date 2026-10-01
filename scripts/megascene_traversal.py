"""Frozen primary Megascene traversal views and independent route checks."""
import hashlib

from megascene_inventory import SCHEMA, canonical, digest, integer, require
from megascene_recipe import bits
from megascene_scale import side_count
from megascene_schedule import camera_bytes

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


def pose(name, neighborhood, preset, seed, route, control=None):
    from megascene_schedule import numeric, exact_vector
    require(route in ROUTES, "unsupported traversal route")
    q = side_count(preset)
    n = q*q-1 if neighborhood == -1 else neighborhood or 0
    eye, look = numeric("pose", name, n, q, seed, route, control or "base")
    return exact_vector(eye), exact_vector(look)


def camera(eye, look):
    from megascene_schedule import numeric
    require(any(b-a for a,b in zip(eye, look)), "degenerate traversal camera")
    return numeric("camera", *(float(x).hex() for x in (*eye, *look)))


def arguments(config):
    warmup, measured = int(config["warmup"]), int(config["frames"])
    require(warmup == 120 and measured == 3600, "primary traversal requires the complete 120/3600 schedule")
    route = config.get("schedule", "traversal-v2")
    require(route in ROUTES, "unsupported traversal route")
    return "traversal", side_count(config["preset"]), int(config["seed"]), route


def schedule(config):
    from megascene_schedule import plan
    return plan(*arguments(config))


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
