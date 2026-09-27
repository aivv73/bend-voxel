import Base
import ../src/face_audit.bend as Audit
import ../src/spatial.bend as S
import ../src/math.bend as R
import ../src/material.bend as M
import ../src/world.bend as W
import ../src/mesh.bend as Mesh

def box(+x: F32, +y: F32, +z: F32, dx: F32, dy: F32, dz: F32, material: U32) -> S.Box:
  S.Box{R.Vec{x,y,z},R.Vec{(x + dx : F32),(y + dy : F32),(z + dz : F32)},material}
def check(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.print("PASS " ++ label)
    case False{}: IO.die(Unit,1,"FAIL " ++ label)
def compare.result(r: Audit.FaceProfile, reference: List<&2,S.Face>, label: String) -> IO(Unit):
  Audit.FaceProfile{profile,cuboids,candidates,nodes,boxes,checks,clips,output} = r
  check((Audit.same(profile,reference) && U32.is_eq(candidates,(cuboids * 6 : U32)) &&
    (nodes >= boxes : U32) && (checks >= clips : U32) && (output > 0 : U32)),label)
def compare(+t: S.Tree, label: String) -> IO(Unit):
  compare.result(Audit.faces(t),S.faces(t),label)
def patch.compare(+t: S.Tree, +p: R.Vec, label: String) -> IO(Unit):
  +next = S.cut(t,p,4.00001)
  check(Audit.equivalent(S.faces.patch(next,S.faces(t),S.cut.window(p,4.00001)),S.faces(next)),label)
def vertex.same(a: Mesh.Vertex, b: Mesh.Vertex) -> Bool:
  Mesh.Vertex{R.Vec{ax,ay,az},as,am} = a
  Mesh.Vertex{R.Vec{bx,by,bz},bs,bm} = b
  (F32.is_eq(ax,bx) && F32.is_eq(ay,by) && F32.is_eq(az,bz) &&
    U32.is_eq(as,bs) && U32.is_eq(am,bm))
def vertices.same(a: List<&2,Mesh.Vertex>, b: List<&2,Mesh.Vertex>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: (vertex.same(x,y) && vertices.same(xs,ys))
    case _ _: False{}
def bodies.match(bs: List<&2,W.Body>) -> Bool:
  match bs:
    case Nil{}: True{}
    case W.Body{_,_,_,_,_,t,+fs,vs} <> rest:
      (Audit.equivalent(fs,S.faces(t)) && vertices.same(vs,Mesh.vertices(fs)) && bodies.match(rest))
def world.match(w: W.World) -> Bool:
  W.World{bs,_,_,_,_,_,_} = w
  bodies.match(bs)
def main() -> IO(Unit):
  +t = S.build([
    box(0.0,0.0,0.0,8.0,4.0,5.0,M.plaster()),
    box(8.0,1.0,1.0,3.0,2.0,3.0,M.frame()),
    box(2.0,4.0,2.0,4.0,2.0,2.0,M.machinery())])
  +bar = {S.Leaf{box(0.0,100.0,0.0,11.0,1.0,1.0,M.concrete())} : S.Tree}
  +barFaces = S.faces(bar)
  +split = W.carve(W.from.bodies([W.Body{1,0,0.0,0.0,False{},bar,barFaces,Mesh.vertices(barFaces)}],2),
    R.Vec{0.55,10.05,0.05})
  do IO<Unit>:
    Unit <- compare(t,"profile matches partial face coverage and materials")
    Unit <- compare(S.cut(t,R.Vec{4.5,3.5,2.5},4.00001),"profile matches carved face splitting")
    Unit <- patch.compare(t,R.Vec{4.5,3.5,2.5},"local rebuild matches mixed-material carved surface")
    Unit <- patch.compare(t,R.Vec{9.5,1.5,2.5},"local rebuild matches edge cut")
    Unit <- patch.compare(S.build([
      box((0.0 - 40.0 : F32),10.0,0.0,2.0,1.0,1.0,M.foundation()),
      box((0.0 - 38.0 : F32),10.0,0.0,12.0,1.0,1.0,M.concrete())]),
      R.Vec{(0.0 - 31.5 : F32),10.5,0.5},"local rebuild matches signed-coordinate cut")
    Unit <- check(world.match(split),"split components cache local surfaces and matching vertices")
    IO.print("ALL FACE AUDIT CHECKS PASSED")
