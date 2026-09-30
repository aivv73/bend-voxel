"""Discrete mixed-district scales and the checked operational admission range.

The range is an implementation support limit, not a measured machine ceiling.
All search choices use integer squared area, avoiding floating-point ties.
"""

import json
import math
import struct
import time

from megascene_bend import run


MAX_NEIGHBORHOODS_PER_SIDE = 5
U32_MAX = (1 << 32) - 1
U64_MAX = (1 << 64) - 1


class NumericRejection(ValueError):
    """Requested work is outside the checked representation before execution."""


def preflight(call, *args, **kwargs):
    try:
        return call(*args, **kwargs)
    except ValueError as exc:
        raise NumericRejection(str(exc)) from exc


def side_count(preset):
    if preset == "small":
        return 2
    if preset == "large":
        return 4
    if isinstance(preset, str) and preset.startswith("scale-"):
        suffix = preset[6:]
        if suffix.isdecimal() and str(int(suffix)) == suffix and int(suffix) >= 2:
            return int(suffix)
    raise ValueError("unsupported square neighborhood scale")


def preset_for(q):
    if type(q) is not int or not 2 <= q <= MAX_NEIGHBORHOODS_PER_SIDE:
        raise ValueError(f"square neighborhood scale unsupported: supported q=2..{MAX_NEIGHBORHOODS_PER_SIDE}; no physical capacity claim")
    return {2: "small", 4: "large"}.get(q, f"scale-{q}")


def next_growth(q):
    """Next q minimizing distance to twice the current area; lower ties win."""
    if type(q) is not int or q < 2:
        raise ValueError("growth requires q>=2")
    return _policy("growth", q)


def midpoint_refinement(low, high):
    """Closest interior discrete area midpoint, or None at adjacent scales."""
    if type(low) is not int or type(high) is not int or low < 2 or high <= low:
        raise ValueError("refinement requires ordered square neighborhood scales")
    return _policy("refinement", low, high)


def history_stride(count):
    if type(count) is not int or count < 4:
        raise ValueError("history needs at least four neighborhoods")
    return _policy("stride", count)


def history_visit(group, count, seed):
    """Return neighborhood and actual number of its earlier visits."""
    if type(group) is not int or not 0 <= group < 12 or seed not in (45, 46):
        raise ValueError("unsupported history group or seed")
    if type(count) is not int or count < 4:
        raise ValueError("history needs at least four neighborhoods")
    neighborhood, prior = _policy("visit", group, count, int(seed))
    return neighborhood + (seed - seed), prior


def _policy(operation, *arguments):
    return json.loads(run("megascene_policy", operation, *map(_decimal, arguments)),
                      parse_int=_integer)


def _decimal(value):
    # Each chunk fits below Python's minimum decimal conversion guard.
    parts = []
    while value:
        value, part = divmod(value, 10**500)
        parts.append(str(part).zfill(500) if value else str(part))
    return "".join(reversed(parts)) or "0"


def _integer(digits):
    value = 0
    for start in range(0, len(digits), 500):
        part = digits[start:start+500]
        value = value * 10**len(part) + int(part)
    return value


def operational_bounds(q, owners, cells, surface_rectangles, vertices, frame_count, budget,
                       resolution=(1920, 1080)):
    """Conservative before-unsafe bounds for the currently validated q range."""
    preset_for(q)
    width, height = resolution
    values = {"neighborhoods": q*q, "initial_owners": owners, "source_cells": cells,
              "source_surface_bound": surface_rectangles, "source_vertices": vertices,
              "frames_including_startup": frame_count, "fragment_budget": budget,
              "initial_next_id": owners + 1,
              "live_body_upper_bound": owners + budget,
              "initial_native_geometry_bytes_bound": vertices*128 + owners*36*128 + 50000*128,
              "maximum_edit_vertex_count": cells*36,
              "framebuffer_byte_bound": width*height*16,
              "shadow_byte_bound": 2048*2048*4,
              "frame_counter_upper_bound": frame_count+1}
    for name, value in values.items():
        if type(value) is not int or value < 0 or value > U32_MAX:
            raise ValueError(f"unsupported {name}: exceeds checked U32/native size envelope")
    # Each side's endpoints and split sums, squared brush offsets and metres
    # stay in the small, tested binary32 range. The source guard checks every
    # actual coordinate, product, surface and native byte count separately.
    extent = 160*q
    if extent > 800 or 2*extent > 2**23:
        raise ValueError("unsupported spatial split/coordinate envelope")
    if (width,height) not in ((640,360),(1920,1080)):
        raise ValueError("unsupported native framebuffer resolution")
    now = time.monotonic_ns()
    deadline = 300 * 1_000_000_000
    if now < 0 or now + deadline + frame_count*1_000_000_000 > U64_MAX:
        raise ValueError("unsupported monotonic clock arithmetic")
    return {key: str(value) for key, value in values.items()} | {
        "signed_cell_extent": str(extent), "maximum_split_sum": str(2*extent),
        "monotonic_admission_ns": str(now), "monotonic_deadline_upper_ns": str(now+deadline),
        "scope": "q=2..5 source/frame representation; actual edits and native allocation have evolving guards; not a physical capacity ceiling"}


def admit_schedule(config, frozen):
    """Check the complete frozen input stream before any unsafe replay."""
    def binary32(word):
        if not isinstance(word, str) or len(word) != 10 or not word.startswith("0x"):
            raise ValueError("malformed frozen binary32")
        try:
            result = struct.unpack(">f", bytes.fromhex(word[2:]))[0]
        except (ValueError, struct.error) as exc:
            raise ValueError("malformed frozen binary32") from exc
        if not math.isfinite(result):
            raise ValueError("nonfinite frozen binary32")
        return result

    frames = frozen["frames"]
    expected = 1+int(config["warmup"])+int(config["frames"])
    if len(frames) != expected or expected > U32_MAX-1:
        raise ValueError("unsupported frozen frame count")
    max_eye = 0.
    for index, frame in enumerate(frames):
        if frame["frame"] != str(index):
            raise ValueError("frozen frame order mismatch")
        view = frame["camera"]
        eye = [binary32(x) for x in view["eye_m"]]
        yaw, pitch = binary32(view["yaw"]), binary32(view["pitch"])
        if abs(yaw) > math.pi+1e-6 or abs(pitch) > math.pi/2+1e-6:
            raise ValueError("frozen camera angle outside supported range")
        max_eye = max(max_eye, *(abs(x) for x in eye))
        if max_eye > 2048:
            raise ValueError("frozen camera outside supported numeric envelope")
        ray = frame.get("ray")
        if ray is not None:
            if any(abs(binary32(x)) > 2048 for x in ray["origin_m"]):
                raise ValueError("frozen ray origin outside supported numeric envelope")
            direction = [binary32(x) for x in ray["direction"]]
            if abs(sum(x*x for x in direction)-1) > 2e-6:
                raise ValueError("frozen ray direction invalid")
        pick = frame.get("expected_pick")
        if pick and pick["kind"] != "0" and not 0 <= binary32(pick["distance_m"]) < 256:
            raise ValueError("required picking result outside strict reach")
    seen_details = set()
    for detail in frozen.get("supplementary_views", []):
        frame = int(detail["frame"])
        if not 0 <= frame < expected or frame in seen_details:
            raise ValueError("invalid supplementary frame")
        seen_details.add(frame)
        view = detail["camera"]
        eye = [binary32(x) for x in view["eye_m"]]
        yaw, pitch = binary32(view["yaw"]), binary32(view["pitch"])
        if max(map(abs, eye)) > 2048 or abs(yaw) > math.pi+1e-6 or abs(pitch) > math.pi/2+1e-6:
            raise ValueError("supplementary camera outside supported envelope")
        max_eye = max(max_eye, *map(abs, eye))
        if detail.get("action") is not None and detail["action"] not in frames[frame]["actions"]:
            raise ValueError("supplementary action missing from its frame")
        original = next((v for v in frozen["review_views"] if v["name"] == detail["supplementary_to"]), None)
        if original is None or original["frame"] != detail["frame"] or not set(detail["features"]) <= set(original["features"]):
            raise ValueError("supplementary view does not bind an original feature")
    required = set()
    for action in frozen["actions"]:
        if not action.get("required", False):
            raise ValueError("frozen action silently optional")
        frame = int(action["frame"])
        if frame <= int(config["warmup"]) or frame >= expected or action["action"] not in frames[frame]["actions"]:
            raise ValueError("frozen action missing from its frame")
        if (frame, action["action"]) in required:
            raise ValueError("duplicate frozen action")
        required.add((frame, action["action"]))
        if any(abs(binary32(x)) > 1024 for x in action["target_m"]):
            raise ValueError("frozen edit target outside supported numeric envelope")
        hit = action.get("pre_edit_hit")
        if hit is not None:
            distance = binary32(hit["distance_m"]) if "distance_m" in hit else float(hit["distance"])
            if not math.isfinite(distance) or not 0 <= distance < 256:
                raise ValueError("required edit target outside strict reach")
    return {"frozen_frames":str(len(frames)), "frozen_actions":str(len(required)),
            "maximum_camera_coordinate_m":repr(max_eye),
            "scope":"all camera/ray/action values frozen before unsafe replay; actual evolving edit/pick guards remain required"}
