"""Small dense-cell oracle: intentionally independent of production geometry."""
from itertools import product

from megascene_inventory import coordinate, integer, read_json, require, verify_vertices
from megascene_recipe import Box, Owner, bend_program


def fixtures():
    return [
        Owner("signed_partial", None, [Box((-3,-2,-2),(-1,2,2),1), Box((-1,-1,-1),(2,1,1),2)]),
        Owner("material_interface", None, [Box((0,0,0),(2,2,2),1), Box((2,0,0),(4,2,2),5)]),
        Owner("edge_separation", None, [Box((0,0,0),(1,1,1),1), Box((1,1,0),(2,2,1),2)]),
        Owner("corner_separation", None, [Box((-1,-1,-1),(0,0,0),1), Box((0,0,0),(1,1,1),3)]),
        Owner("unanchored", None, [Box((0,0,0),(1,1,1),4)]),
        Owner("protected_support", None, [Box((0,0,0),(1,1,1),1), Box((0,1,0),(1,3,1),3), Box((-1,3,0),(2,4,1),2)]),
        Owner("cavity", None, [Box((3,0,0),(7,1,4),1), Box((3,1,0),(4,4,4),3),
                               Box((6,1,0),(7,4,4),2), Box((4,3,0),(6,4,4),5)])]


def program():
    return bend_program(fixtures(), 2048).replace("./src/", "./")


def dense(boxes):
    cells = {}
    for box in boxes:
        for point in product(*(range(a,b) for a,b in zip(box.lo,box.hi))):
            require(point not in cells, "dense duplicate ownership")
            cells[point] = box.material
    return cells


def neighbors(point):
    for side in range(6):
        yield side, tuple(c+(1 if side%2 else -1) if k==side//2 else c for k,c in enumerate(point))


def reference(cells):
    components = []
    remaining = set(cells)
    while remaining:
        seen, pending = set(), [min(remaining)]
        while pending:
            point = pending.pop()
            if point in seen:
                continue
            seen.add(point)
            pending += [n for _,n in neighbors(point) if n in cells and n not in seen]
        remaining -= seen
        components.append(seen)
    exposed = {(point, side): material for point,material in cells.items()
               for side,neighbor in neighbors(point) if neighbor not in cells}
    return components, exposed


def check(text):
    records = [read_json(line) for line in text.splitlines()]
    require(text.endswith("\n") and len(records) == len(fixtures())+2 and records[-1] == {"record_type":"complete"}, "incomplete reference worker")
    evidence = []
    for source, body in zip(fixtures(), records[1:-1]):
        expected = dense(source.boxes)
        actual = dense([Box(tuple(map(coordinate,b[:3])),tuple(map(coordinate,b[3:6])),integer(b[6])) for b in body["boxes"]])
        require(actual == expected, source.role+": dense occupancy/material mismatch")
        components, exposed = reference(expected)
        require(body["connected"] is (len(components)==1), source.role+": six-neighbor connectivity mismatch")
        require(body["anchored"] is (1 in expected.values()), source.role+": protected anchor mismatch")
        require(body["cells"] == str(len(expected)), source.role+": cells mismatch")
        drawn, faces = {}, []
        for f in body["faces"]:
            lo, hi = tuple(map(coordinate,f[:3])), tuple(map(coordinate,f[3:6]))
            side, material = integer(f[6]),integer(f[7]); axis=side//2
            faces.append((lo,hi,side,material))
            require(side<6 and lo[axis]==hi[axis], "nonplanar reference surface")
            for point in product(*(range(lo[k],hi[k]) if k!=axis else [lo[k]-(side%2)] for k in range(3))):
                require((point,side) not in drawn, "duplicate dense drawable coverage")
                drawn[point,side]=material
        require(drawn==exposed, source.role+": dense exposed surface mismatch")
        verify_vertices(faces,body["vertices"])
        evidence.append({"name":source.role,"cells":str(len(expected)),"components":str(len(components)),
                         "protected_cells":str(sum(m==1 for m in expected.values())),"unit_faces":str(len(exposed)),"status":"pass"})
    return {"status":"pass","scope":"independent dense static generation fixtures","fixtures":evidence}
