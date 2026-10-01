"""Frozen primary picking and an independent exact face-intersection oracle.

The oracle enumerates box faces using rational arithmetic. A separate binary32
operation model predicts exact recorder bits; it cannot establish correctness
without agreeing with the independent geometric result and declared target.
"""
from fractions import Fraction as Q
import math
import struct

from megascene_inventory import require
from megascene_recipe import bits, f32, generate
from megascene_scale import side_count
from megascene_schedule import numeric, plan, ray_bytes

ROUTES = ("picking-v1", "picking-v2")
ZERO = "0x00000000"


def value(word):
    return struct.unpack(">f", bytes.fromhex(word[2:]))[0]


def center(camera):
    return numeric("center", *(value(word).hex() for word in
                   [*camera["eye_m"], camera["yaw"], camera["pitch"]]))


def exact_pick(boxes, origin, direction):
    """Enumerate all face intersections; no production tree/slab traversal."""
    o, d = list(map(Q,origin)), list(map(Q,direction))
    candidates = []
    if d[1] < 0:
        t = -o[1]/d[1]
        if 0 <= t < 256:
            candidates.append((t, 0, 0, 3))
    for owner, box, offset in boxes:
        lo = [Q(c,10)+(Q(offset) if k==1 else 0) for k,c in enumerate(box.lo)]
        hi = [Q(c,10)+(Q(offset) if k==1 else 0) for k,c in enumerate(box.hi)]
        if any(d[k] == 0 and not lo[k] <= o[k] < hi[k] for k in range(3)):
            continue
        for axis in range(3):
            if not d[axis]:
                continue
            for plane in (lo[axis], hi[axis]):
                t = (plane-o[axis])/d[axis]
                if not 0 <= t < 256:
                    continue
                point = [a+t*b for a,b in zip(o,d)]
                if all(lo[k] <= point[k] <= hi[k] for k in range(3)):
                    candidates.append((t, owner, box.material, 2 if box.material==1 else 1))
    if not candidates:
        return {"owner":"0", "material":"0", "kind":"0", "distance":256., "point":[0.,0.,0.]}
    t, owner, material, kind = min(candidates, key=lambda hit: hit[0])
    return {"owner":str(owner), "material":str(material), "kind":str(kind), "distance":float(t),
            "point":[float(a+t*b) for a,b in zip(o,d)]}


def rounded_pick(boxes, origin, direction):
    """Predict bits only; checked against exact_pick and actual Bend execution."""
    best = {"owner":"0", "material":"0", "kind":"0", "distance":256., "point":[0.,0.,0.]}
    def accept(t, owner, material, kind):
        nonlocal best
        if 0 <= t < best["distance"]:
            best = {"owner":str(owner), "material":str(material), "kind":str(kind), "distance":t,
                    "point":[f32(a+f32(b*t)) for a,b in zip(origin,direction)]}
    divisor = direction[1] if abs(direction[1]) > f32(.000001) else f32(.000001)
    ground = f32(0-f32(origin[1]/divisor))
    if direction[1] < 0:
        accept(ground,0,0,3)
    for owner, box, offset in boxes:
        near, far = -1000000., 1000000.
        for axis in range(3):
            lo, hi = (f32(f32(c*f32(.1))+(offset if axis==1 else 0)) for c in (box.lo[axis],box.hi[axis]))
            o, d = origin[axis], direction[axis]
            if abs(d) < f32(.0000001):
                a,b = (-1000000.,1000000.) if lo<=o<hi else (1000000.,-1000000.)
            else:
                a,b = sorted((f32(f32(lo-o)/d),f32(f32(hi-o)/d)))
            near,far = max(near,a),min(far,b)
        if far >= max(0,near) and near < best["distance"]:
            accept(near if near>=0 else far,owner,box.material,2 if box.material==1 else 1)
    return best


def result_bits(result):
    return {k:result[k] for k in ("owner","material","kind")} | {
        "distance_m": bits(result["distance"]), "position_m": list(map(bits,result["point"]))}


def checked_result(boxes, ray):
    origin, direction = list(map(value,ray["origin_m"])), list(map(value,ray["direction"]))
    require(all(math.isfinite(x) and abs(x)<=2048 for x in origin), "unsupported picking origin")
    require(all(math.isfinite(x) for x in direction) and abs(sum(x*x for x in direction)-1)<2e-6, "invalid picking direction")
    for _,box,offset in boxes:
        require(math.isfinite(offset) and abs(offset)<=1024, "unsupported picking offset")
        for k in range(3):
            require(all(type(c) is int and abs(c)<=8192 for c in (box.lo[k],box.hi[k])), "unsupported picking cells")
            require(box.hi[k]>box.lo[k], "invalid picking box")
            for cell in (box.lo[k],box.hi[k]):
                converted=f32(f32(cell*f32(.1))+(offset if k==1 else 0))
                require(abs(converted-(cell/10+(offset if k==1 else 0)))<=.0002, "unsupported cell/metre/offset conversion")
    reference, rounded = exact_pick(boxes,origin,direction), rounded_pick(boxes,origin,direction)
    require(all(reference[k] == rounded[k] for k in ("owner","material","kind")), "rounded picking changes exact target/reach")
    require(abs(reference["distance"]-rounded["distance"])<=.0005 and
            all(abs(a-b)<=.0005 for a,b in zip(reference["point"],rounded["point"])), "unsupported picking distance/point error")
    return result_bits(rounded), reference


def schedule(config, owners=None):
    route = config.get("schedule", "picking-v2")
    require(route in ROUTES, "unsupported frozen picking schedule")
    require(int(config["warmup"]) == 120 and int(config["frames"]) == 3600,
            "primary traversal requires the complete 120/3600 schedule")
    q=side_count(config["preset"])
    frozen = plan("traversal",q,int(config["seed"]),route)
    owners = owners if owners is not None else generate(config["preset"],int(config["seed"]))
    boxes = [(i,b,0.) for i,owner in enumerate(owners,1) for b in owner.boxes]
    cache = {}
    for frame in frozen["frames"]:
        frame["expected_pick"] = {"owner":"0","material":"0","kind":"0","distance_m":ZERO,"position_m":[ZERO]*3}
        if not frame["picking"]:
            continue
        key=tuple(frame["ray"]["origin_m"]+frame["ray"]["direction"])
        if key not in cache:
            result, reference = checked_result(boxes,frame["ray"])
            pose = frame["route_phase"]
            target = frame["target"]
            expected = (target["owner"],target["material"],"0" if target["outcome"]=="miss" else "1")
            require(tuple(result[k] for k in ("owner","material","kind")) == expected, f"unreachable or incorrect declared {pose} target")
            if pose in ("wall","interior","cavity","assembly"):
                axis,plane = {"wall":(0,(16-160*q)/10),"interior":(0,(20-160*q)/10),
                              "cavity":(1,.8),"assembly":(1,(58+(int(config['seed'])-45)%2)/10)}[pose]
                require(abs(reference["point"][axis]-plane)<1e-6, f"wrong declared {pose} face")
            cache[key] = result
        frame["expected_pick"] = cache[key]
    frozen["picking_admission"] = {"status":"pass","enabled_samples":"720","required_hits":"600","required_misses":"120",
        "reach_m":"256","reach_comparison":"strictly_less", "reference":"rational face intersections against source geometry",
        "runtime_guard":"actual tree bounds and F32 cell/metre/offset/slab/hit arithmetic before unsafe traversal"}
    return frozen


def expected_payload(initial,frame):
    result=frame["expected_pick"]
    return {**initial,"view":{**initial["view"],**frame["camera"],
        "aim":{"kind":result["kind"],"position_m":result["position_m"],"radius_m":result["distance_m"]}}}


def audit(records,frozen):
    actual=[r for r in records if r["record_type"]=="picking"]
    require(len(actual)==len(frozen["frames"]),"missing picking samples (including disabled frames)")
    for record,frame in zip(actual,frozen["frames"]):
        require(record["frame"]==frame["frame"],"duplicate or out-of-order picking sample")
        require(record["enabled"] is frame["picking"],"picking enable schedule mismatch")
        require(record["ray"]==frame["ray"],"actual ray differs from frozen center ray")
        require(record["result"]==frame["expected_pick"],"picking target/outcome mismatch at frame "+frame["frame"])
    enabled = [f for f in frozen["frames"] if f["picking"]]
    hits = sum(f["expected_pick"]["kind"] != "0" for f in enabled)
    return {"status":"pass","samples":str(len(actual)),"enabled":str(len(enabled)),
            "hits":str(hits),"misses":str(len(enabled)-hits),"disabled":str(len(actual)-len(enabled))}
