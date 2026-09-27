import Base
import ../src/mesh.bend as Mesh
import ../src/spatial.bend as S
import ../src/math.bend as R

def check(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.print("PASS " ++ label)
    case False{}: IO.die(Unit,1,"FAIL " ++ label)

def close(a: F32, b: F32) -> Bool:
  (F32.abs((a - b : F32)) < 0.00001 : F32)
def vertex.equal(a: Mesh.Vertex, b: Mesh.Vertex) -> Bool:
  Mesh.Vertex{R.Vec{ax,ay,az},as,am} = a
  Mesh.Vertex{R.Vec{bx,by,bz},bs,bm} = b
  (close(ax,bx) && close(ay,by) && close(az,bz) &&
    U32.is_eq(as,bs) && U32.is_eq(am,bm))
def vertices.equal(a: List<&2,Mesh.Vertex>, b: List<&2,Mesh.Vertex>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: (vertex.equal(x,y) && vertices.equal(xs,ys))
    case _ _: False{}
def expected(+side: U32, +a: R.Vec, b: R.Vec, +c: R.Vec, d: R.Vec) -> List<&2,Mesh.Vertex>:
  [Mesh.vertex(a,side,5),Mesh.vertex(b,side,5),Mesh.vertex(c,side,5),
   Mesh.vertex(a,side,5),Mesh.vertex(c,side,5),Mesh.vertex(d,side,5)]
def main() -> IO(Unit):
  +lo = {R.Vec{1.0,2.0,3.0} : R.Vec}
  +hi = {R.Vec{4.0,2.0,5.0} : R.Vec}
  +p0 = {R.Vec{0.1,0.2,0.3} : R.Vec}
  +p1 = {R.Vec{0.1,0.2,0.5} : R.Vec}
  +p2 = {R.Vec{0.4,0.2,0.5} : R.Vec}
  +p3 = {R.Vec{0.4,0.2,0.3} : R.Vec}
  do IO<Unit>:
    Unit <- check(vertices.equal(Mesh.vertices([S.Face{lo,hi,3,5}]),
      expected(3,p0,p1,p2,p3)),"positive face expands to outward triangles")
    Unit <- check(vertices.equal(Mesh.vertices([S.Face{lo,hi,2,5}]),
      expected(2,p3,p2,p1,p0)),"negative face reverses winding")
    Unit <- check(vertices.equal(Mesh.vertices(Nil{}),Nil{}),"empty surface emits no vertices")
    IO.print("ALL BEND MESH CHECKS PASSED")
