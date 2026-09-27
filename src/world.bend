import Base
import ./math.bend as R
import ./spatial.bend as S
import ./mesh.bend as Mesh
import ./showcase.bend as Showcase

# Each body owns a sparse spatial tree, local-space faces, and render vertices.
# IDs remain stable until an edit changes that body's geometry. Translation
# never changes geometry identity. Unrelated bodies survive an edit verbatim.
type Body is Data:
  Body{id: U32, revision: U32, offset: F32, speed: F32, anchored: Bool, tree: S.Tree, faces: List<&2,S.Face>, vertices: List<&2,Mesh.Vertex>}
type World is Data:
  World{bodies: List<&2,Body>, solids: U32, fragments: U32, removed: U32, status: U32, next: U32, budget: U32}
def use.world(-C: Type, w: World, k: List<&2,Body> -> U32 -> U32 -> U32 -> U32 -> U32 -> U32 -> C) -> C:
  World{a,b,c,d,e,f,g} = w
  k(a,b,c,d,e,f,g)
def bodies.count(bs: List<&2,Body>) -> U32:
  match bs:
    case Nil{}: 0
    case _ <> rest: (1 + bodies.count(rest) : U32)
def bodies.solids(bs: List<&2,Body>) -> U32:
  match bs:
    case Nil{}: 0
    case Body{_,_,_,_,_,t,_,_} <> rest: (S.count(t) + bodies.solids(rest) : U32)
def bodies.fragments(bs: List<&2,Body>) -> U32:
  match bs:
    case Nil{}: 0
    case Body{_,_,_,_,anchor,_,_,_} <> rest: (R.word(anchor,0,1) + bodies.fragments(rest) : U32)
def bodies.regions(bs: List<&2,Body>) -> U32:
  match bs:
    case Nil{}: 0
    case Body{_,_,_,_,_,t,_,_} <> rest: (S.leaves(t) + bodies.regions(rest) : U32)
def mesh(b: Body) -> Body:
  match b:
    case Body{id,r,o,v,a,+t,Nil{},Nil{}}:
      +fs = S.faces(t)
      Body{id,r,o,v,a,t,fs,Mesh.vertices(fs)}
    case b: b
def meshes(bs: List<&2,Body>) -> List<&2,Body>:
  match bs:
    case Nil{}: Nil{}
    case b <> rest: mesh(b) <> meshes(rest)
def assembly.body(a: Showcase.Assembly, id: U32) -> Body:
  Showcase.Assembly{+t} = a
  +fs = S.faces(t)
  Body{id,0,0.0,0.0,S.anchored(t),t,fs,Mesh.vertices(fs)}
def assemblies(bs: List<&2,Showcase.Assembly>, +id: U32) -> List<&2,Body>:
  match bs:
    case Nil{}: Nil{}
    case a <> rest:
      # Initial bodies are independent; the CPU pool builds them beside the list tail.
      body tail = assembly.body(a,id) assemblies(rest,(id + 1 : U32))
      body <> tail
def bodies.next(bs: List<&2,Body>) -> U32:
  match bs:
    case Nil{}: 1
    case Body{+id,_,_,_,_,_,_,_} <> rest:
      +next = bodies.next(rest)
      R.word((next > id : U32),next,(id + 1 : U32))
def from.bodies(+bs: List<&2,Body>, budget: U32) -> World:
  World{bs,bodies.solids(bs),bodies.fragments(bs),0,1,bodies.next(bs),budget}
def showcase(budget: U32) -> World:
  from.bodies(assemblies(Showcase.generate(),1),budget)
def initial() -> World:
  showcase(2048)
def reset(w: World) -> World:
  World{_,_,_,_,_,_,budget} = w
  showcase(budget)
def status(w: World, status: U32) -> World:
  World{bs,n,c,_,_,next,budget} = w
  World{bs,n,c,0,status,next,budget}

type Pending is Data:
  Pending{body: Body, tree: S.Tree, window: S.Box}
type Prepared is Data:
  Prepared{unchanged: List<&2,Body>, changed: List<&2,Pending>, removed: U32}
def prepare.add(same: Bool, b: Body, t: S.Tree, window: S.Box, removed: U32, r: Prepared) -> Prepared:
  match same r:
    case True{} Prepared{bs,dirty,n}: Prepared{b <> bs,dirty,n}
    case False{} Prepared{bs,dirty,n}: Prepared{bs,Pending{b,t,window} <> dirty,(n + removed : U32)}
def prepare.body(+b: Body, +p: R.Vec, r: Prepared) -> Prepared:
  Body{_,_,offset,_,_,+t,_,_} = b
  +local = R.Vec.scale(R.Vec.sub(p,R.Vec{0.0,offset,0.0}),10.0)
  +candidate = S.cut(t,local,4.00001)
  +removed = (S.count(t) - S.count(candidate) : U32)
  prepare.add(U32.is_eq(removed,0),b,candidate,S.cut.window(local,4.00001),removed,r)
def prepare.bs(bs: List<&2,Body>, +p: R.Vec) -> Prepared:
  match bs:
    case Nil{}: Prepared{Nil{},Nil{},0}
    case b <> rest: prepare.body(b,p,prepare.bs(rest,p))
type Edit is Data:
  Edit{old: World, prepared: Prepared}
def carve.prepare(+w: World, p: R.Vec) -> Edit:
  World{bs,_,_,_,_,_,_} = w
  Edit{w,prepare.bs(bs,p)}

type Classified is Data:
  Classified{unchanged: List<&2,Body>, dirty: List<&2,Body>, jobs: List<&2,SurfaceJob>, next: U32}
type SurfaceJob is Data:
  SurfaceJob{oldFaces: List<&2,S.Face>, window: S.Box}
@unsafe
def classify.component(r: S.Component, +offset: F32, +speed: F32,
  +oldFaces: List<&2,S.Face>, +window: S.Box, state: Classified) -> Classified:
  S.Component{rest,+t} = r
  Classified{same,dirty,jobs,+next} = state
  classify.tree(rest,offset,speed,oldFaces,window,
    Classified{same,Body{next,0,offset,speed,S.anchored(t),t,Nil{},Nil{}} <> dirty,
      SurfaceJob{oldFaces,window} <> jobs,(next + 1 : U32)})
@unsafe
def classify.tree(t: S.Tree, offset: F32, speed: F32,
  oldFaces: List<&2,S.Face>, window: S.Box, state: Classified) -> Classified:
  match t:
    case S.Empty{}: state
    case t: classify.component(S.component(t),offset,speed,oldFaces,window,state)
@unsafe
def classify.next(r: Classified, rest: List<&2,Pending>) -> Classified:
  classify.bs(rest,r)
@unsafe
def classify.bs(ps: List<&2,Pending>, state: Classified) -> Classified:
  match ps:
    case Nil{}: state
    case Pending{Body{_,_,o,v,_,_,fs,_},t,window} <> rest:
      classify.next(classify.tree(t,o,v,fs,window,state),rest)
type EditClassification is Data:
  EditClassification{old: World, classified: Classified, removed: U32}
def carve.classify.prepared(+w: World, prepared: Prepared) -> EditClassification:
  World{_,_,_,_,_,next,_} = w
  Prepared{bs,dirty,removed} = prepared
  EditClassification{w,classify.bs(dirty,Classified{bs,Nil{},Nil{},next}),removed}
def carve.classify(edit: Edit) -> EditClassification:
  Edit{w,p} = edit
  carve.classify.prepared(w,p)
type EditSurfaces is Data:
  EditSurfaces{old: World, bodies: List<&2,Body>, next: U32, removed: U32}
def mesh.local(b: Body, job: SurfaceJob) -> Body:
  Body{id,r,o,v,a,+t,_,_} = b
  SurfaceJob{oldFaces,window} = job
  +fs = S.faces.patch(t,oldFaces,window)
  Body{id,r,o,v,a,t,fs,Mesh.vertices(fs)}
def meshes.local(bs: List<&2,Body>, jobs: List<&2,SurfaceJob>) -> List<&2,Body>:
  match bs jobs:
    case Nil{} _: Nil{}
    case b <> rest job <> more: mesh.local(b,job) <> meshes.local(rest,more)
    case bs Nil{}: meshes(bs)
def carve.surfaces(edit: EditClassification) -> EditSurfaces:
  EditClassification{w,Classified{same,dirty,jobs,next},removed} = edit
  # Edits rebuild only new bodies; per-body forks cost more for this short list.
  EditSurfaces{w,S.append(Body,meshes.local(dirty,jobs),same),next,removed}
def carve.commit(ok: Bool, old: World, bs: List<&2,Body>, next: U32, +removed: U32) -> World:
  match ok:
    case False{}: status(old,3)
    case True{}:
      World{_,n,_,_,_,_,budget} = old
      +bs = bs
      World{bs,(n - removed : U32),bodies.fragments(bs),removed,1,next,budget}
def carve.finish.changed(changed: Bool, +old: World, +bs: List<&2,Body>, next: U32, +removed: U32) -> World:
  match changed:
    case False{}: status(old,2)
    case True{}:
      World{_,_,_,_,_,_,budget} = old
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
    case Body{id,r,o,v,True{},t,fs,vs}: Body{id,r,o,v,True{},t,fs,vs}
    case Body{id,r,+o,+v,False{},+t,fs,vs}:
      +floor = (0.0 - bottom(t) : F32)
      +y = (o + v * dt - 4.905 * dt * dt : F32)
      Body{id,r,R.max(floor,y),R.pick((y > floor : F32),(v - 9.81 * dt : F32),0.0),False{},t,fs,vs}
def bodies.step(bs: List<&2,Body>, +dt: F32) -> List<&2,Body>:
  match bs:
    case Nil{}: Nil{}
    case b <> rest: body.step(dt,b) <> bodies.step(rest,dt)
def step(w: World, dt: F32) -> World:
  World{bs,n,c,r,s,next,budget} = w
  World{bodies.step(bs,dt),n,c,r,s,next,budget}
