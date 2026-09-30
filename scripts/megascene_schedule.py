import json

from megascene_bend import run
from megascene_inventory import require


def plan(operation, *arguments):
    records = [json.loads(line) for line in run("megascene_schedule", operation, *arguments).splitlines()]
    require(records and records[0].get("record_type") == "schedule", "missing Bend schedule header")
    frozen = records[0]
    frozen["frames"] = []
    frozen["actions"] = []
    for record in records[1:]:
        kind = record.pop("record_type")
        require(kind in ("frame", "action", "reference_action"), "unsupported Bend schedule record")
        key = {"frame": "frames", "action": "actions", "reference_action": "_reference_actions"}[kind]
        frozen.setdefault(key, []).append(record)
    require(len(frozen["frames"]) == 1 + int(frozen["warmup_frames"]) + int(frozen["measured_frames"]),
            "incomplete Bend schedule")
    return frozen


def numeric(operation, *arguments):
    return json.loads(run("megascene_schedule", operation, *arguments))


def exact_vector(vector):
    return tuple(float.fromhex(word) for word in vector)
