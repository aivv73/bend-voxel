"""Small independent rational/dense picking fixtures executed by native Bend."""
import json
from itertools import product

from megascene_inventory import require
from megascene_recipe import Box, bits, f32
from megascene_picking import checked_result, exact_pick, result_bits, value


def fixtures():
    box = Box((0,10,0),(1,11,1),2)
    reach = Box((2560,10,0),(2561,11,1),5)
    return [
        ("empty", [], (0.,2.,0.), (0.,1.,0.)),
        ("ground", [], (0.,2.,0.), (0.,-1.,0.)),
        ("protected", [(7,Box((0,10,0),(1,11,1),1),0.)], (-1.,1.05,.05), (1.,0.,0.)),
        ("signed", [(9,Box((-21,-11,-31),(-20,-10,-30),3),0.)], (-3.,-1.05,-3.05), (1.,0.,0.)),
        ("translated_up", [(4,box,2.)], (-1.,3.05,.05), (1.,0.,0.)),
        ("translated_down", [(4,box,-2.)], (-1.,-.95,.05), (1.,0.,0.)),
        ("parallel_upper_face", [(4,box,0.)], (-1.,1.1,.05), (1.,0.,0.)),
        ("inside", [(4,box,0.)], (.05,1.05,.05), (1.,0.,0.)),
        ("nearest_owner", [(8,Box((20,10,0),(21,11,1),1),0.),(9,box,0.)], (-1.,1.05,.05), (1.,0.,0.)),
        ("reach_below", [(5,reach,0.)], (2**-16,1.05,.05), (1.,0.,0.)),
        ("reach_at", [(5,reach,0.)], (0.,1.05,.05), (1.,0.,0.)),
        ("reach_beyond", [(5,reach,0.)], (-2**-15,1.05,.05), (1.,0.,0.)),
        ("translated_reach", [(5,reach,-2.)], (0.,-.95,.05), (1.,0.,0.)),
    ]


def real(x):
    return f"(0.0 - {float(abs(x))!r} : F32)" if x<0 else repr(float(x))


def vec(v):
    return "R.Vec{"+",".join(map(real,v))+"}"


def program():
    source='''import Base
import ./world.bend as W
import ./spatial.bend as S
import ./math.bend as R
import ./render.bend as V
import ./megascene.bend as M
import ./megascene_picking.bend as P

def emit(name: String, h: V.Hit) -> IO(Unit):
  V.Hit{V.Aim{point,distance,kind},owner,material} = h
  IO.print("{\\"name\\":" ++ M.quote(name) ++ ",\\"owner\\":" ++ M.word(owner) ++
    ",\\"material\\":" ++ M.word(material) ++ ",\\"kind\\":" ++ M.word(kind) ++
    ",\\"distance_m\\":" ++ M.real(distance) ++ ",\\"position_m\\":[" ++ M.vec(point) ++ "]}")

def main() -> IO(Unit):
  do IO<Unit>:
'''
    for i,(name,boxes,origin,direction) in enumerate(fixtures()):
        ray={"origin_m":list(map(bits,origin)),"direction":list(map(bits,direction))}
        checked_result(boxes,ray)  # Admission before the fixture builds any tree.
        bodies=[]
        for owner,box,offset in boxes:
            tree=f"S.Leaf{{S.Box{{{vec(box.lo)},{vec(box.hi)},{box.material}}}}}"
            bodies.append(f"W.Body{{{owner},0,{real(offset)},0.0,True{{}},{tree},Nil{{}},Nil{{}}}}")
        source+=f'    hit{i} : V.Hit <- P.pick([{",".join(bodies)}],P.Ray{{True{{}},{vec(origin)},{vec(direction)}}})\n'
        source+=f'    emit("{name}",hit{i})\n'
    return source


def check(text):
    records=[json.loads(line) for line in text.splitlines()]
    require(text.endswith("\n") and len(records)==len(fixtures()), "incomplete picking reference worker")
    evidence=[]
    for actual,(name,boxes,origin,direction) in zip(records,fixtures()):
        ray={"origin_m":list(map(bits,origin)),"direction":list(map(bits,direction))}
        expected,reference=checked_result(boxes,ray)
        # Dense independent unit cells also confirm the small occupied geometry.
        cells=[(owner,Box(p,tuple(c+1 for c in p),box.material),offset)
               for owner,box,offset in boxes for p in product(*(range(a,b) for a,b in zip(box.lo,box.hi)))]
        dense=exact_pick(cells,list(map(f32,origin)),list(map(f32,direction)))
        require(dense==reference, "dense reference disagreement: "+name)
        require(actual=={"name":name,**expected}, "Bend picking differs from independent reference: "+name)
        evidence.append({"name":name,"status":"pass","ray":ray,"actual":actual,"reference_distance_m":reference["distance"]})
    return {"status":"pass","scope":"independent rational face/unit-cell intersections versus guarded production Bend picking", "fixtures":evidence}
