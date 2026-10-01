from dataclasses import dataclass
import math
import json
import struct
from megascene_scale import side_count, preset_for, _decimal
from megascene_bend import run, run_input

U32_MAX = 2**32 - 1


def checked(value, label, maximum=U32_MAX):
    if type(value) is not int or not 0 <= value <= maximum:
        raise ValueError(f"{label}: unsigned integer exceeds supported range")
    return value


def f32(value):
    return struct.unpack("<f", struct.pack("<f", value))[0]


def bits(value):
    if not math.isfinite(value):
        raise ValueError("nonfinite binary32 value")
    return "0x" + struct.pack(">f", value).hex()


@dataclass(frozen=True)
class Box:
    lo: tuple
    hi: tuple
    material: int

    def record(self):
        return {"lo": list(map(str, self.lo)), "hi": list(map(str, self.hi)),
                "material": str(self.material)}


@dataclass
class Owner:
    role: str
    neighborhood: int | None
    boxes: list


CONTROLS = ("spread", "material-detail", "surface-detail", "fill", "body-rich")


def envelope_cells(preset, control=None):
    q = side_count(preset)
    return 640 * (q-1) + 320 if control == "spread" else 320 * q


def _source(q, seed, control):
    return run("megascene_source", q, seed, control or "base")


def source_owners(text, q, seed, control=None):
    """Decode a complete source stream; callers receive fresh mutable owners."""
    if not text.endswith("\n"):
        raise ValueError("truncated Bend source stream")
    def object_pairs(pairs):
        result = dict(pairs)
        if len(result) != len(pairs):
            raise ValueError("duplicate Bend source field")
        return result
    records = [json.loads(line, object_pairs_hook=object_pairs) for line in text.splitlines()]
    if len(records) < 3 or records[-1] != {"record_type": "complete"}:
        raise ValueError("incomplete Bend source stream")
    header = records[0]
    expected_extent = 640*(q-1)+320 if control == "spread" else 320*q
    roles = (("building_left", "building_right") if control == "body-rich" else ("building",)) + (
        "span0", "span1", "span2", "irregular")
    expected_owners = [("terrain", None)] + [(role, n) for n in range(q*q) for role in roles]
    if control == "compact-reference":
        if q != 2:
            raise ValueError("compact source requires q=2")
        expected_owners = [("irregular", n) for n in range(4)]
    if (type(header) is not dict or
            set(header) != {"record_type", "schema", "side", "seed", "control", "envelope_cells"} or
            header["record_type"] != "source" or header["schema"] != "megascene-source/1" or
            type(header["side"]) is not int or type(header["seed"]) is not int or
            header["side"] != q or header["seed"] != seed or
            header["control"] != (control or "base") or
            type(header["envelope_cells"]) is not int or header["envelope_cells"] != expected_extent or
            len(records) != len(expected_owners)+2):
        raise ValueError("Bend source identity mismatch")
    owners = []
    def coordinate(value):
        if (type(value) not in (int, float) or abs(value) > 2**23 or
                not math.isfinite(value) or value != int(value)):
            raise ValueError("inexact Bend source coordinate")
        return int(value)
    for record, expected_owner in zip(records[1:-1], expected_owners):
        if (type(record) is not dict or set(record) != {"record_type", "role", "neighborhood", "boxes"} or
                record["record_type"] != "owner" or type(record["role"]) is not str or
                (record["role"], record["neighborhood"]) != expected_owner or
                type(record["boxes"]) is not list or not record["boxes"]):
            raise ValueError("invalid Bend source owner")
        n = record["neighborhood"]
        if (n is None and record["role"] != "terrain" or
                n is not None and (type(n) is not int or not 0 <= n < q*q or record["role"] == "terrain")):
            raise ValueError("invalid Bend source neighborhood")
        boxes = []
        for b in record["boxes"]:
            if (type(b) is not dict or set(b) != {"lo", "hi", "material"} or type(b["lo"]) is not list or
                    type(b["hi"]) is not list or len(b["lo"]) != 3 or len(b["hi"]) != 3 or
                    type(b["material"]) is not int or not 1 <= b["material"] <= 5):
                raise ValueError("invalid Bend source box")
            boxes.append(Box(tuple(map(coordinate,b["lo"])),tuple(map(coordinate,b["hi"])),b["material"]))
        owners.append(Owner(record["role"],n,boxes))
    if control != "compact-reference" and (owners[0].role != "terrain" or sum(o.role == "terrain" for o in owners) != 1):
        raise ValueError("invalid Bend terrain ownership")
    return owners


def generate(preset, seed, control=None):
    q = side_count(preset)
    preset_for(q)
    if type(seed) is not int or seed not in (45, 46):
        raise ValueError("only seeds 45/46 are supported")
    if control not in (None, *CONTROLS):
        raise ValueError("unsupported terrain control")
    return source_owners(_source(q,seed,control),q,seed,control)


def generation_inputs(config):
    args = ((config["preset"], config["seed"], config["side_m"], config["fragment_budget"], config["threads"], "none")
            if config.get("case") == "admission" else
            (config["preset"], config["seed"], config["side_m"], config["envelope_side_m"], config["control"] or "none",
             config["fragment_budget"], config.get("diagnostic") or "none"))
    module = "megascene_admission_inputs" if config.get("case") == "admission" else "megascene_inputs"
    record, source = run(module, *args, "source").split("\n", 1)
    control = "compact-reference" if config.get("diagnostic") == "compact-reference" else config.get("control")
    return (record + "\n").encode("ascii"), source_owners(source, side_count(config["preset"]), int(config["seed"]), control)


def signed_decimal(value):
    return ("-" if value < 0 else "") + _decimal(abs(value))


def admit_sources(owners, half_extent, budget):
    if type(budget) is not int:
        raise ValueError("fragment budget: unsigned integer exceeds supported range")
    if isinstance(half_extent, int):
        numerator, denominator = int(half_extent), 1
    else:
        try:
            numerator, denominator = half_extent.as_integer_ratio()
        except OverflowError:
            numerator, denominator = "inf" if half_extent > 0 else "-inf", 1
        except (AttributeError, ValueError):
            numerator, denominator = "invalid", 1
    tokens = ["megascene-admission/1", signed_decimal(numerator) if type(numerator) is int else numerator,
              signed_decimal(denominator), signed_decimal(budget), str(len(owners))]
    for owner in owners:
        tokens.append(str(len(owner.boxes)))
        for box in owner.boxes:
            material = box.material
            if isinstance(material, complex) and material.imag == 0:
                material = material.real
            try:
                integer = int(material)
                material = signed_decimal(integer) if material == integer else "invalid"
            except (TypeError, ValueError, OverflowError):
                material = "invalid"
            tokens.append(material)
            coordinates = (*box.lo, *box.hi) if len(box.lo) == len(box.hi) == 3 else (None,) * 6
            for value in coordinates:
                tokens.append(signed_decimal(value) if type(value) is int else "invalid")
    tokens.append("complete")
    try:
        text = run_input("megascene_admit", " ".join(tokens))
    except ValueError as error:
        message = str(error)
        if message.startswith("owner-index:"):
            _, index, reason = message.split(":", 2)
            if index.isdecimal() and int(index) < len(owners):
                message = f"{owners[int(index)].role}: {reason.strip()}"
        raise ValueError(message) from error

    def object_pairs(pairs):
        result = dict(pairs)
        if len(result) != len(pairs):
            raise ValueError("duplicate Bend admission field")
        return result

    if not text.endswith("\n") or len(text.splitlines()) != 1:
        raise ValueError("incomplete Bend admission report")
    result = json.loads(text, object_pairs_hook=object_pairs)
    if (type(result) is not dict or
            set(result) != {"cells", "surface_rectangle_bounds", "vertex_bound", "geometry_byte_bound"} or
            type(result["surface_rectangle_bounds"]) is not list or
            len(result["surface_rectangle_bounds"]) != len(owners)):
        raise ValueError("invalid Bend admission report")
    for value in (result["cells"], result["vertex_bound"], result["geometry_byte_bound"],
                  *result["surface_rectangle_bounds"]):
        if (type(value) is not str or not value.isascii() or not value.isdecimal() or
                len(value) > 10 or str(int(value)) != value or int(value) > U32_MAX):
            raise ValueError("invalid Bend admission count")
    return result


def worker_owner_tokens(owners):
    tokens = [str(len(owners))]
    for owner in owners:
        tokens.append(str(len(owner.boxes)))
        for box in owner.boxes:
            tokens.append(signed_decimal(box.material) if type(box.material) is int else "invalid")
            coordinates = (*box.lo, *box.hi) if len(box.lo) == len(box.hi) == 3 else (None,) * 6
            tokens.extend(signed_decimal(value) if type(value) is int else "invalid" for value in coordinates)
    tokens.append("complete")
    return tokens


def bend_program(owners, budget):
    tokens = ["megascene-worker/1", "admission",
              signed_decimal(budget) if type(budget) is int else "invalid", *worker_owner_tokens(owners)]
    return run_input("megascene_worker_source", " ".join(tokens))
