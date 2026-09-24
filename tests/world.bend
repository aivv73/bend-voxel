import Base
import ../src/world.bend as W
import ../src/spatial.bend as S
import ../src/district.bend as D
import ../src/math.bend as R

def check(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.print("PASS " ++ label)
    case False{}: IO.die(Unit,1,"FAIL " ++ label)
def inspect(+w: W.World, n: U32, c: U32, status: U32, label: String) -> IO(W.World):
  W.World{_,actualN,actualC,_,actualS,_,_,_} = w
  do IO<W.World>:
    Unit <- check((U32.is_eq(n,actualN) && U32.is_eq(c,actualC) && U32.is_eq(status,actualS)),label)
    IO.pure(W.World,w)
def fixture(+t: S.Tree, budget: U32, offset: F32, speed: F32) -> W.World:
  W.from.bodies([W.Body{1,0,offset,speed,S.anchored(t),t,S.faces(t)}],budget,1)
def bar(budget: U32, offset: F32, speed: F32) -> W.World:
  fixture(S.Leaf{D.box(0.0,100.0,0.0,11.0,1.0,1.0,2)},budget,offset,speed)
@unsafe
def components(t: S.Tree) -> U32:
  match t:
    case S.Empty{}: 0
    case t: components.next(S.component(t))
@unsafe
def components.next(c: S.Component) -> U32:
  S.Component{remaining,_} = c
  (1 + components(remaining) : U32)
def area(fs: List<&2,S.Face>) -> U32:
  match fs:
    case Nil{}: 0
    case S.Face{l,h,+s,_} <> rest:
      +d = R.Vec.sub(h,l)
      +u = ((s / 2 + 1) % 3 : U32)
      +v = ((s / 2 + 2) % 3 : U32)
      (F32.to_u32((S.axis(d,u) * S.axis(d,v) : F32)) + area(rest) : U32)
def dense.sides(n: Nat, +s: U32, +p: R.Vec, +t: S.Tree) -> U32:
  match n:
    case 0n: 0
    case 1n+k:
      +a = (s / 2 : U32)
      +q = S.put(p,a,(S.axis(p,a) + R.pick(U32.is_eq((s % 2 : U32),0),(0.0 - 1.0 : F32),1.0) : F32))
      (R.word((S.contains(t,p) && Bool.not(S.contains(t,q))),1,0) + dense.sides(k,(s + 1 : U32),p,t) : U32)
def dense.area(n: Nat, +i: U32, +t: S.Tree) -> U32:
  match n:
    case 0n: 0
    case 1n+k:
      +p = {R.Vec{(U32.to_f32((i % 8 : U32)) + 0.5 : F32),
        (U32.to_f32((i / 8 % 8 : U32)) + 0.5 : F32),(U32.to_f32((i / 64 : U32)) + 0.5 : F32)} : R.Vec}
      (dense.sides(6n,0,p,t) + dense.area(k,(i + 1 : U32),t) : U32)
def dense.cut(n: Nat, +i: U32, +old: S.Tree, +fresh: S.Tree, +p: R.Vec) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +q = {R.Vec{(U32.to_f32((i % 8 : U32)) + 0.5 : F32),
        (U32.to_f32((i / 8 % 8 : U32)) + 0.5 : F32),(U32.to_f32((i / 64 : U32)) + 0.5 : F32)} : R.Vec}
      +d = R.Vec.sub(q,p)
      (U32.is_eq(R.word(S.contains(fresh,q),1,0),R.word((S.contains(old,q) && (R.Vec.dot(d,d) > 4.00001 : F32)),1,0)) && dense.cut(k,(i + 1 : U32),old,fresh,p))
def motion(bs: List<&2,W.Body>, +offset: F32, +speed: F32) -> Bool:
  match bs:
    case Nil{}: True{}
    case W.Body{_,_,o,v,_,_,_} <> rest:
      ((F32.abs((o - offset : F32)) < 0.0001 : F32) && (F32.abs((v - speed : F32)) < 0.0001 : F32) && motion(rest,offset,speed))
def moving(w: W.World, offset: F32, speed: F32) -> Bool:
  W.World{bs,_,_,_,_,_,_,_} = w
  motion(bs,offset,speed)
def many(n: Nat, +i: U32) -> List<&2,W.Body>:
  match n:
    case 0n: Nil{}
    case 1n+k:
      +t = {S.Leaf{D.box((U32.to_f32(i) * 2.0 : F32),100.0,0.0,1.0,1.0,1.0,2)} : S.Tree}
      W.Body{i,0,0.0,0.0,False{},t,S.faces(t)} <> many(k,(i + 1 : U32))
def disjoint.box(+b: S.Box, rest: List<&2,S.Box>) -> Bool:
  match b rest:
    case _ Nil{}: True{}
    case S.Box{bl,bh,_} S.Box{l,h,_} <> tail:
      +lo = S.maximum(bl,l)
      +hi = S.minimum(bh,h)
      (Bool.not(((S.axis(lo,0) < S.axis(hi,0)) && (S.axis(lo,1) < S.axis(hi,1)) && (S.axis(lo,2) < S.axis(hi,2)) : F32)) && disjoint.box(b,tail))
def disjoint(bs: List<&2,S.Box>) -> Bool:
  match bs:
    case Nil{}: True{}
    case b <> +tail: (disjoint.box(b,tail) && disjoint(tail))
def falling.bodies(bs: List<&2,W.Body>) -> Bool:
  match bs:
    case Nil{}: False{}
    case W.Body{_,_,o,v,_,_,_} <> _: ((o < (0.0 - 10.0)) && (v < 0.0) : F32)
def falling(w: W.World) -> Bool:
  W.World{bs,_,_,_,_,_,_,_} = w
  falling.bodies(bs)
def connected.assemblies(bs: List<&2,D.Assembly>) -> Bool:
  match bs:
    case Nil{}: True{}
    case D.Assembly{+t} <> rest: (U32.is_eq(components(t),1) && disjoint(S.boxes(t,Nil{})) && connected.assemblies(rest))
def main() -> IO(Unit):
  +solid = {S.Leaf{D.box(0.0,0.0,0.0,8.0,8.0,8.0,2)} : S.Tree}
  +p = {R.Vec{3.5,4.5,2.5} : R.Vec}
  +cut = S.cut(solid,p,4.00001)
  +partial = S.build([D.box(0.0,0.0,0.0,4.0,4.0,4.0,2),D.box(4.0,1.0,1.0,2.0,2.0,2.0,3)])
  do IO<Unit>:
    Unit <- check(U32.is_eq(S.count(S.Leaf{D.box(0.0,0.0,0.0,257.0,257.0,257.0,2)}),16974593),"large cuboid cell counts use exact integer arithmetic")
    Unit <- check(dense.cut(512n,0,solid,cut,p),"sparse sphere agrees with every dense reference cell")
    Unit <- check(U32.is_eq(area(S.faces(cut)),dense.area(512n,0,cut)),"carved surface area agrees with dense exposed faces")
    Unit <- check(U32.is_eq(area(S.faces(partial)),dense.area(512n,0,partial)),"partial material boundary hides exactly shared faces")
    Unit <- check(U32.is_eq(components(S.build([D.box(0.0,0.0,0.0,1.0,1.0,1.0,2),D.box(1.0,1.0,0.0,1.0,1.0,1.0,2)])),2),"edge contact stays disconnected")
    Unit <- check(connected.assemblies(D.district()),"generated regions do not overlap and all assemblies are six-connected")
    w : W.World <- inspect(W.initial(),2261844,0,1,"district has more than two million real voxels")
    w : W.World <- inspect(W.carve(w,R.Vec{(0.0 - 15.9 : F32),16.25,(0.0 - 19.95 : F32)}),2261816,0,1,"first bridge fuse retains anchor path across regions")
    w : W.World <- inspect(W.carve(w,R.Vec{15.9,16.25,(0.0 - 19.95 : F32)}),2261788,1,1,"last bridge fuse detaches one fragment")
    w : W.World <- inspect(W.step(w,10.0),2261788,1,1,"falling bridge preserves all remaining cells")
    w : W.World <- inspect(W.carve(w,R.Vec{1000.0,1.0,1000.0}),2261788,1,2,"air cut is a no-op")
    w : W.World <- inspect(W.configured(4,2048),9047376,0,1,"four districts multiply simulated cells")
    w : W.World <- inspect(W.configured(16,2048),36189504,0,1,"sixteen districts multiply simulated cells")
    w : W.World <- inspect(W.carve(fixture(S.Leaf{D.box((0.0 - 80.0 : F32),100.0,0.0,2.0,2.0,2.0,1)},10,0.0,0.0),R.Vec{(0.0 - 7.9 : F32),10.1,0.1}),8,0,2,"explicit elevated anchor is protected")
    w : W.World <- inspect(W.carve(fixture(S.build([D.box((0.0 - 40.0 : F32),10.0,0.0,2.0,1.0,1.0,1),D.box((0.0 - 38.0 : F32),10.0,0.0,12.0,1.0,1.0,2)]),10,0.0,0.0),R.Vec{(0.0 - 3.15 : F32),1.05,0.05}),9,1,1,"signed coordinates and cross-region severing")
    w : W.World <- inspect(W.carve(bar(1,0.0,0.0),R.Vec{0.55,10.05,0.05}),11,1,3,"body budget overflow rolls back mass and ownership")
    w : W.World <- inspect(W.carve(bar(2,0.0,0.0),R.Vec{0.55,10.05,0.05}),6,2,1,"configured body budget admits the same split")
    w : W.World <- inspect(W.carve(bar(2,(0.0 - 1.0 : F32),(0.0 - 2.0 : F32)),R.Vec{0.55,9.05,0.05}),6,2,1,"moving fragment can be split again")
    Unit <- check(moving(w,(0.0 - 1.0 : F32),(0.0 - 2.0 : F32)),"split fragments inherit position and velocity")
    Unit <- check(moving(W.step(bar(2,0.0,0.0),10.0),(0.0 - 10.0 : F32),0.0),"falling body stops at ground")
    w : W.World <- inspect(W.from.bodies(many(512n,1),1024,1),512,512,1,"512 independent bodies exceed the removed 64-body cap")
    w : W.World <- inspect(W.step(w,0.1),512,512,1,"512 bodies move without losing material")
    w : W.World <- inspect(W.carve(fixture(S.Leaf{D.box(0.0,0.0,0.0,1.0,1.0,1.0,2)},10,0.0,0.0),R.Vec{0.05,0.05,0.05}),0,0,1,"ground-level cells are removable without explicit anchor material")
    w : W.World <- inspect(W.carve(fixture(S.Leaf{D.box(0.0,100.0,0.0,1.0,10.0,1.0,2)},10,(0.0 - 10.0 : F32),0.0),R.Vec{0.05,0.15,0.05}),6,1,1,"removing the lowest cells updates the landing bound")
    Unit <- check(falling(W.step(w,0.1)),"landed fragment resumes falling after its bottom is cut")
    IO.print("ALL SPARSE WORLD CHECKS PASSED")
