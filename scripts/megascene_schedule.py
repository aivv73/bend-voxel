import json

from megascene_bend import run, run_binary
from megascene_inventory import require


def document(operation, *arguments):
    return run("megascene_schedule", operation, *arguments).encode("ascii")


def plan(operation, *arguments):
    frozen = json.loads(document(operation, *arguments))
    require(len(frozen["frames"]) == 1 + int(frozen["warmup_frames"]) + int(frozen["measured_frames"]),
            "incomplete Bend schedule")
    return frozen


def numeric(operation, *arguments):
    return json.loads(run("megascene_schedule", operation, *arguments))


def exact_vector(vector):
    return tuple(float.fromhex(word) for word in vector)


def _points_bytes(frozen, field, protocol):
    arguments = [protocol, len(frozen["frames"])]
    for point in frozen[field]:
        require(isinstance(point["frame"], str) and isinstance(point["name"], str),
                "point transport requires string fields")
        arguments.extend((point["frame"], point["name"]))
    return run("schedule_points", *arguments).encode("ascii")


def checkpoint_bytes(frozen):
    return _points_bytes(frozen, "required_checkpoints", "megascene-checkpoints/1")


def review_bytes(frozen):
    return _points_bytes(frozen, "review_views", "megascene-reviews/1")


def binary_bytes(kind, rows):
    tokens = ["megascene-binary/1", kind, str(len(rows))]
    for row in rows:
        require(all(isinstance(word, str) for word in row), "binary transport requires string fields")
        tokens.extend(("row", *row))
    return run_binary("schedule_binary", " ".join((*tokens, "complete")))


def camera_bytes(frozen):
    return binary_bytes("camera", [(*f["camera"]["eye_m"], f["camera"]["yaw"], f["camera"]["pitch"])
                                   for f in frozen["frames"]])


def policy_bytes(frozen):
    return binary_bytes("policy", [(f["phase"], f.get("policy_flags", "0")) for f in frozen["frames"]])


def ray_bytes(frozen):
    rows = []
    for frame in frozen["frames"]:
        require(isinstance(frame["picking"], bool), "ray transport requires a boolean picking flag")
        ray = frame["ray"] or {"origin_m": ["0x00000000"]*3, "direction": ["0x00000000"]*3}
        rows.append(("true" if frame["picking"] else "false", *ray["origin_m"], *ray["direction"]))
    return binary_bytes("ray", rows)


def supplementary_bytes(views):
    return binary_bytes("supplementary", [(v["frame"], "none" if v["action"] is None else v["action"],
        *v["camera"]["eye_m"], v["camera"]["yaw"], v["camera"]["pitch"]) for v in views])
