import re

from megascene_inventory import integer, require


def _bytes(frozen, field, protocol):
    count = len(frozen["frames"])
    require(1 <= count <= 21721, "checkpoint plan frame count outside native bound")
    points = frozen[field]
    require(1 <= len(points) <= 4096, "checkpoint plan name count outside native bound")
    seen = set()
    rows = []
    for point in points:
        frame, name = integer(point["frame"]), point["name"]
        require(0 <= frame < count, "checkpoint plan frame outside frozen schedule")
        require(isinstance(name, str) and re.fullmatch(r"[A-Za-z0-9_]{1,128}", name),
                "invalid checkpoint plan name")
        require(name not in seen, "duplicate checkpoint plan name")
        seen.add(name)
        rows.append((frame, name))
    rows.sort(key=lambda row: row[0])
    header = f"{protocol}\t{count}\t{len(rows)}\n"
    return (header + "".join(f"{frame}\t{name}\n" for frame, name in rows)).encode("ascii")


def checkpoint_bytes(frozen):
    return _bytes(frozen, "required_checkpoints", "megascene-checkpoints/1")


def review_bytes(frozen):
    return _bytes(frozen, "review_views", "megascene-reviews/1")
