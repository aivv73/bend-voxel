import Base
import ../src/world.bend as W
import ../src/spatial.bend as S
import ../src/math.bend as R
import ../src/face_audit.bend as Audit
import ./face-audit.bend as Faces
import ./world.bend as Fixture

# Runtime/reference checks: world edits rely on @unsafe and are not formal
# theorems. Compare complete cached geometry, identity, and motion on rollback.
def box.same(a: S.Box, b: S.Box) -> Bool:
  S.Box{al,ah,am} = a
  S.Box{bl,bh,bm} = b
  (Audit.vec.same(al,bl) && Audit.vec.same(ah,bh) && U32.is_eq(am,bm))
def tree.same(a: S.Tree, b: S.Tree) -> Bool:
  match a b:
    case S.Empty{} S.Empty{}: True{}
    case S.Leaf{x} S.Leaf{y}: box.same(x,y)
    case S.Branch{ab,al,ar} S.Branch{bb,bl,br}:
      (box.same(ab,bb) && tree.same(al,bl) && tree.same(ar,br))
    case _ _: False{}
def geometry.same(a: W.Body, b: W.Body) -> Bool:
  W.Body{ai,ar,_,_,aa,at,af,av} = a
  W.Body{bi,br,_,_,ba,bt,bf,bv} = b
  (U32.is_eq(ai,bi) && U32.is_eq(ar,br) &&
    U32.is_eq(R.word(aa,1,0),R.word(ba,1,0)) &&
    tree.same(at,bt) &&
    Audit.same(af,bf) && Faces.vertices.same(av,bv))
def body.same(+a: W.Body, +b: W.Body) -> Bool:
  W.Body{_,_,ao,av,_,_,_,_} = a
  W.Body{_,_,bo,bv,_,_,_,_} = b
  (F32.is_eq(ao,bo) && F32.is_eq(av,bv) && geometry.same(a,b))
def bodies.same(a: List<&2,W.Body>, b: List<&2,W.Body>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: (body.same(x,y) && bodies.same(xs,ys))
    case _ _: False{}
def unchanged(before: W.World, after: W.World, expectedStatus: U32) -> Bool:
  W.World{ab,an,ac,_,_,ai,al} = before
  W.World{bb,bn,bc,removed,status,bi,bl} = after
  (bodies.same(ab,bb) && U32.is_eq(an,bn) && U32.is_eq(ac,bc) &&
    U32.is_eq(ai,bi) && U32.is_eq(al,bl) && U32.is_eq(removed,0) &&
    U32.is_eq(status,expectedStatus))
def first(w: W.World) -> W.Body:
  W.World{bs,_,_,_,_,_,_} = w
  match bs:
    case b <> _: b
    case Nil{}: W.Body{0,0,0.0,0.0,False{},S.Empty{},Nil{},Nil{}}
def main() -> IO(Unit):
  +moving = Fixture.bar(1,(0.0 - 1.0 : F32),(0.0 - 2.0 : F32))
  do IO<Unit>:
    Unit <- Fixture.check(unchanged(moving,
      W.carve(moving,R.Vec{0.55,9.05,0.05}),3),
      "budget rollback preserves IDs, next ID, budget, motion, materials, faces and vertices")
    Unit <- Fixture.check(unchanged(moving,
      W.carve(moving,R.Vec{20.0,20.0,20.0}),2),
      "no-op edit preserves complete body state")
    Unit <- Fixture.check(geometry.same(first(moving),first(W.step(moving,0.1))),
      "translation preserves geometry identity and cached faces/vertices")
    IO.print("ALL RUNTIME INVARIANTS PASSED")
