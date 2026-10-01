"""Discrete mixed-district scales and the checked operational admission range.

The range is an implementation support limit, not a measured machine ceiling.
All search choices use integer squared area, avoiding floating-point ties.
"""

import json
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
    width, height = resolution
    arguments = (q, owners, cells, surface_rectangles, vertices, frame_count, budget,
                 width, height, time.monotonic_ns())
    return json.loads(run("megascene_operational", *map(_counter_word, arguments)))


def _counter_word(value):
    return _decimal(value) if type(value) is int and value >= 0 else "invalid"


def native_geometry_bound(owners, vertices):
    return run("megascene_operational", "native", _counter_word(owners),
               _counter_word(vertices)).strip()


def history_bounds(owners, cells, budget, actions):
    arguments = [_counter_word(owners), _counter_word(cells), _counter_word(budget)]
    for action in actions:
        arguments.extend((action["reference_components"], action["expected_removed_cells"]))
    return json.loads(run("megascene_operational", "history", *arguments))


def admit_schedule(config, frozen):
    from megascene_bend import run_input
    from megascene_performance import enabled, admit, validate
    if enabled(config):
        admit(config)
        validate(frozen)

    def field(value):
        if value is None:
            return "n"
        if isinstance(value, str):
            return "s" + value.encode("utf-8").hex()
        if isinstance(value, bool):
            return "b1" if value else "b0"
        if type(value) is int:
            return "i" + str(value)
        if isinstance(value, float):
            return "f" + repr(value).encode("ascii").hex()
        if isinstance(value, (list, tuple)):
            return "l" + ",".join(field(x) for x in value)
        return "x"

    def camera(view):
        return [field(view["eye_m"]), field(view["yaw"]), field(view["pitch"])]

    try:
        frames = []
        for frame in frozen["frames"]:
            ray = frame.get("ray")
            pick = frame.get("expected_pick")
            kind = pick["kind"] if pick else None
            distance = pick.get("distance_m") if pick else None
            frames.append(" ".join(["F", field(frame["frame"]), *camera(frame["camera"]),
                field(ray is not None), field(ray["origin_m"] if ray is not None else []),
                field(ray["direction"] if ray is not None else []), field(kind), field(distance), field(frame["actions"])]))
        reviews = [" ".join(["R", field(view["name"]), field(view["frame"]), field(view["features"])])
                   for view in frozen.get("review_views", [])]
        details = [" ".join(["S", field(view["frame"]), *camera(view["camera"]),
                   field(view.get("action")), field(view["supplementary_to"]), field(view["features"])])
                   for view in frozen.get("supplementary_views", [])]
        actions = []
        for action in frozen["actions"]:
            hit = action.get("pre_edit_hit")
            kind, distance = (("n", None) if hit is None else
                              ("b", hit["distance_m"]) if "distance_m" in hit else ("d", hit["distance"]))
            actions.append(" ".join(["A", field(action["frame"]), field(action["action"]),
                field(action.get("required", False)), field(action["target_m"]), kind, field(distance)]))
        request = "\n".join([" ".join(["v1", field(config["warmup"]), field(config["frames"])]),
                              "|".join(frames), "|".join(reviews), "|".join(details), "|".join(actions)])
    except (KeyError, TypeError, AttributeError) as exc:
        raise ValueError("malformed frozen admission input") from exc
    report = json.loads(run_input("megascene_frozen_admit", request))
    maximum = struct.unpack(">f", int(report.pop("maximum_word")).to_bytes(4, "big"))[0]
    return report | {"maximum_camera_coordinate_m": repr(maximum),
        "scope": "all camera/ray/action values frozen before unsafe replay; actual evolving edit/pick guards remain required"}
