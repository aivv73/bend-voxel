import Base
import ./math.bend as R
import ./spatial.bend as S
import ./district.bend as District

# Each body owns a sparse spatial tree and immutable local-space faces.
# IDs remain stable until an edit changes that body's geometry. Translation
# never changes geometry identity. Unrelated bodies survive an edit verbatim.
type Body is Data:
  Body{id: U32, revision: U32, offset: F32, speed: F32, anchored: Bool, tree: S.Tree, faces: List<&2,S.Face>}
type World is Data:
  World{bodies: List<&2,Body>, solids: U32, fragments: U32, removed: U32, status: U32, next: U32, budget: U32, districts: U32}
def use.world(-C: Type, w: World, k: List<&2,Body> -> U32 -> U32 -> U32 -> U32 -> U32 -> U32 -> U32 -> C) -> C:
  World{a,b,c,d,e,f,g,h} = w
  k(a,b,c,d,e,f,g,h)
def bodies.count(bs: List<&2,Body>) -> U32:
  match bs:
    case Nil{}: 0
    case _ <> rest: (1 + bodies.count(rest) : U32)
def bodies.solids(bs: List<&2,Body>) -> U32:
  match bs:
    case Nil{}: 0
    case Body{_,_,_,_,_,t,_} <> rest: (S.count(t) + bodies.solids(rest) : U32)
def bodies.fragments(bs: List<&2,Body>) -> U32:
  match bs:
    case Nil{}: 0
    case Body{_,_,_,_,anchor,_,_} <> rest: (R.word(anchor,0,1) + bodies.fragments(rest) : U32)
def bodies.regions(bs: List<&2,Body>) -> U32:
  match bs:
    case Nil{}: 0
    case Body{_,_,_,_,_,t,_} <> rest: (S.leaves(t) + bodies.regions(rest) : U32)
def mesh(b: Body) -> Body:
  match b:
    case Body{id,r,o,v,a,+t,Nil{}}: Body{id,r,o,v,a,t,S.faces(t)}
    case b: b
def meshes(bs: List<&2,Body>) -> List<&2,Body>:
  match bs:
    case Nil{}: Nil{}
    case b <> rest: mesh(b) <> meshes(rest)
def assemblies(bs: List<&2,District.Assembly>, +id: U32) -> List<&2,Body>:
  match bs:
    case Nil{}: Nil{}
    case District.Assembly{+t} <> rest:
      Body{id,0,0.0,0.0,S.anchored(t),t,S.faces(t)} <> assemblies(rest,(id + 1 : U32))
def bodies.next(bs: List<&2,Body>) -> U32:
  match bs:
    case Nil{}: 1
    case Body{+id,_,_,_,_,_,_} <> rest:
      +next = bodies.next(rest)
      R.word((next > id : U32),next,(id + 1 : U32))
def from.bodies(+bs: List<&2,Body>, budget: U32, districts: U32) -> World:
  World{bs,bodies.solids(bs),bodies.fragments(bs),0,1,bodies.next(bs),budget,districts}
def configured(+districts: U32, budget: U32) -> World:
  from.bodies(assemblies(District.generate(districts),1),budget,districts)
def initial() -> World:
  configured(1,2048)
def reset(w: World) -> World:
  World{_,_,_,_,_,_,budget,districts} = w
  configured(districts,budget)
def status(w: World, status: U32) -> World:
  World{bs,n,c,_,_,next,budget,districts} = w
  World{bs,n,c,0,status,next,budget,districts}

type Pending is Data:
  Pending{body: Body, tree: S.Tree}
type Prepared is Data:
  Prepared{unchanged: List<&2,Body>, changed: List<&2,Pending>, removed: U32}
def prepare.add(same: Bool, b: Body, t: S.Tree, removed: U32, r: Prepared) -> Prepared:
  match same r:
    case True{} Prepared{bs,dirty,n}: Prepared{b <> bs,dirty,n}
    case False{} Prepared{bs,dirty,n}: Prepared{bs,Pending{b,t} <> dirty,(n + removed : U32)}
def prepare.body(+b: Body, +p: R.Vec, r: Prepared) -> Prepared:
  Body{_,_,offset,_,_,+t,_} = b
  +candidate = S.cut(t,R.Vec.scale(R.Vec.sub(p,R.Vec{0.0,offset,0.0}),10.0),4.00001)
  +removed = (S.count(t) - S.count(candidate) : U32)
  prepare.add(U32.is_eq(removed,0),b,candidate,removed,r)
def prepare.bs(bs: List<&2,Body>, +p: R.Vec) -> Prepared:
  match bs:
    case Nil{}: Prepared{Nil{},Nil{},0}
    case b <> rest: prepare.body(b,p,prepare.bs(rest,p))
type Edit is Data:
  Edit{old: World, prepared: Prepared}
def carve.prepare(+w: World, p: R.Vec) -> Edit:
  World{bs,_,_,_,_,_,_,_} = w
  Edit{w,prepare.bs(bs,p)}

type Classified is Data:
  Classified{bodies: List<&2,Body>, next: U32}
@unsafe
def classify.component(r: S.Component, +offset: F32, +speed: F32, +next: U32, bs: List<&2,Body>) -> Classified:
  S.Component{rest,+t} = r
  classify.tree(rest,offset,speed,(next + 1 : U32),Body{next,0,offset,speed,S.anchored(t),t,Nil{}} <> bs)
@unsafe
def classify.tree(t: S.Tree, offset: F32, speed: F32, next: U32, bs: List<&2,Body>) -> Classified:
  match t:
    case S.Empty{}: Classified{bs,next}
    case t: classify.component(S.component(t),offset,speed,next,bs)
@unsafe
def classify.next(r: Classified, rest: List<&2,Pending>) -> Classified:
  Classified{bs,next} = r
  classify.bs(rest,next,bs)
@unsafe
def classify.bs(ps: List<&2,Pending>, next: U32, bs: List<&2,Body>) -> Classified:
  match ps:
    case Nil{}: Classified{bs,next}
    case Pending{Body{_,_,o,v,_,_,_},t} <> rest:
      classify.next(classify.tree(t,o,v,next,bs),rest)
type EditClassification is Data:
  EditClassification{old: World, classified: Classified, removed: U32}
def carve.classify.prepared(+w: World, prepared: Prepared) -> EditClassification:
  World{_,_,_,_,_,next,_,_} = w
  Prepared{bs,dirty,removed} = prepared
  EditClassification{w,classify.bs(dirty,next,bs),removed}
def carve.classify(edit: Edit) -> EditClassification:
  Edit{w,p} = edit
  carve.classify.prepared(w,p)
type EditSurfaces is Data:
  EditSurfaces{old: World, bodies: List<&2,Body>, next: U32, removed: U32}
def carve.surfaces(edit: EditClassification) -> EditSurfaces:
  EditClassification{w,Classified{bs,next},removed} = edit
  EditSurfaces{w,meshes(bs),next,removed}
def carve.commit(ok: Bool, old: World, bs: List<&2,Body>, next: U32, +removed: U32) -> World:
  match ok:
    case False{}: status(old,3)
    case True{}:
      World{_,n,_,_,_,_,budget,districts} = old
      +bs = bs
      World{bs,(n - removed : U32),bodies.fragments(bs),removed,1,next,budget,districts}
def carve.finish.changed(changed: Bool, +old: World, +bs: List<&2,Body>, next: U32, +removed: U32) -> World:
  match changed:
    case False{}: status(old,2)
    case True{}:
      World{_,_,_,_,_,_,budget,_} = old
      carve.commit((bodies.fragments(bs) <= budget : U32),old,bs,next,removed)
def carve.finalize(edit: EditSurfaces) -> World:
  EditSurfaces{w,bs,next,+removed} = edit
  carve.finish.changed((removed > 0 : U32),w,bs,next,removed)
def carve(w: World, p: R.Vec) -> World:
  carve.finalize(carve.surfaces(carve.classify(carve.prepare(w,p))))
def bottom.box(b: S.Box) -> F32:
  S.Box{R.Vec{_,y,_},_,_} = b
  (y * 0.1 : F32)
def bottom(t: S.Tree) -> F32:
  bottom.box(S.bounds(t))
def body.step(+dt: F32, b: Body) -> Body:
  match b:
    case Body{id,r,o,v,True{},t,fs}: Body{id,r,o,v,True{},t,fs}
    case Body{id,r,+o,+v,False{},+t,fs}:
      +floor = (0.0 - bottom(t) : F32)
      +y = (o + v * dt - 4.905 * dt * dt : F32)
      Body{id,r,R.max(floor,y),R.pick((y > floor : F32),(v - 9.81 * dt : F32),0.0),False{},t,fs}
def bodies.step(bs: List<&2,Body>, +dt: F32) -> List<&2,Body>:
  match bs:
    case Nil{}: Nil{}
    case b <> rest: body.step(dt,b) <> bodies.step(rest,dt)
def step(w: World, dt: F32) -> World:
  World{bs,n,c,r,s,next,budget,districts} = w
  World{bodies.step(bs,dt),n,c,r,s,next,budget,districts}
