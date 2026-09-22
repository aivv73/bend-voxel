import Base
import ../src/world.bend as W
import ../src/vendor/bend3d.bend as R
import ../src/render.bend as V
import ../src/input.bend as I

def check(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("PASS " ++ label)
    case False{}:
      IO.die(Unit, 1, "FAIL " ++ label)
def area.faces(fs: List<&2,W.Face>) -> U32:
  match fs:
    case Nil{}: 0
    case W.Face{_,_,len,rows} <> rest: (len * rows + area.faces(rest) : U32)
def area.bodies(bs: List<&2,W.Body>) -> U32:
  match bs:
    case Nil{}: 0
    case W.Body{_,_,_,_,fs} <> rest: (area.faces(fs) + area.bodies(rest) : U32)
def area.sides(n: Nat, +side: U32, +i: U32, +owner: U32, a: Array<U32>, +count: U32) -> Array<U32> & U32:
  match n:
    case 0n: (a,count)
    case 1n+k:
      W.pair(Array<U32>,U32,Array<U32> & U32,Array.get(U32,a,W.neighbor(i,side)),a => other =>
        area.sides(k,(side + 1 : U32),i,owner,a,(count + R.word(((owner > 0 : U32) && U32.is_ne(owner,other)),1,0) : U32)))
def area.grid(n: Nat, +i: U32, a: Array<U32>, count: U32) -> U32:
  match n:
    case 0n: count
    case 1n+k:
      W.pair(Array<U32>,U32,U32,Array.get(U32,a,i),a => owner =>
        W.pair(Array<U32>,U32,U32,area.sides(6n,0,i,owner,a,count),a => count => area.grid(k,(i + 1 : U32),a,count)))
def verify.mesh(w: W.World) -> IO(Unit):
  W.World{a,bs,_,_,_,_} = w
  check(U32.is_eq(area.grid(19200n,0,a,0),area.bodies(bs)),"merged mesh preserves exposed voxel-face area")
def inspect(w: W.World, +n0: U32, +c0: U32, +s0: U32, label: String) -> IO(W.World):
  W.World{a, bs, +n, +c, r, +s} = w
  do IO<W.World>:
    Unit <- check((U32.is_eq(n,n0) && U32.is_eq(c,c0) && U32.is_eq(s,s0)), label)
    IO.pure(W.World, W.World{a, bs, n, c, r, s})
def sever(w: W.World, +x: F32) -> W.World:
  w = W.carve(w, R.Vec{(x - 0.15 : F32), 1.05, (0.0 - 0.15 : F32)})
  w = W.carve(w, R.Vec{(x - 0.15 : F32), 1.05, 0.15})
  w = W.carve(w, R.Vec{(x + 0.15 : F32), 1.05, (0.0 - 0.15 : F32)})
  W.carve(w, R.Vec{(x + 0.15 : F32), 1.05, 0.15})
def anchors(n: Nat, +i: U32, a: Array<U32>, +count: U32) -> U32:
  match n:
    case 0n: count
    case 1n+k:
      W.pair(Array<U32>, U32, U32, Array.get(U32,a,i), a => owner =>
        anchors(k,(i + 1 : U32),a,(count + R.word((U32.is_eq(owner,1) && U32.is_eq((i / 40 % 24 : U32),0)),1,0) : U32)))
def landed(bs: List<&2,W.Body>) -> Bool:
  match bs:
    case Nil{}: True{}
    case W.Body{id, offset, speed, bottom, _} <> rest:
      ((U32.is_eq(id,1) || ((F32.abs((offset + bottom : F32)) < 0.00001) && (F32.abs(speed) < 0.00001) : F32)) && landed(rest))
def inheritance(bs: List<&2,W.Body>) -> Bool:
  match bs:
    case Nil{}: True{}
    case W.Body{_, _, speed, _, _} <> rest:
      ((F32.abs((speed + 0.981 : F32)) < 0.0001 : F32) && inheritance(rest))
def verify.landed(w: W.World) -> IO(Unit):
  W.World{a, bs, _, _, _, _} = w
  do IO<Unit>:
    Unit <- check(landed(bs), "floor clamp and zero velocity")
    check(U32.is_eq(anchors(19200n,0,a,0),72), "all protected anchors remain")
def fixture.two(+second: U32, owner: U32) -> W.World:
  a = Array.new(U32,15n,0)
  a = Array.set(U32,a,40,2)
  W.rebuild(Array.set(U32,a,second,owner),Nil{},2,0)
def fixture.singles(n: Nat, +j: U32, a: Array<U32>) -> Array<U32>:
  match n:
    case 0n: a
    case 1n+k:
      +i = ((j % 7 * 5 + 2) + 40 * (j / 7 % 3 * 5 + 5) + 960 * (j / 21 * 5 + 2) : U32)
      fixture.singles(k,(j + 1 : U32),Array.set(U32,a,i,2))
def fixture.bar(n: Nat, +j: U32, a: Array<U32>) -> Array<U32>:
  match n:
    case 0n: a
    case 1n+k:
      fixture.bar(k,(j + 1 : U32),Array.set(U32,a,(j + 40 * 22 + 960 * 19 : U32),2))
def fixture.cap() -> W.World:
  W.rebuild(fixture.bar(11n,0,fixture.singles(63n,0,Array.new(U32,15n,0))),Nil{},74,0)
def fixture.vertical(n: Nat, +y: U32, a: Array<U32>) -> Array<U32>:
  match n:
    case 0n: a
    case 1n+k:
      fixture.vertical(k,(y + 1 : U32),Array.set(U32,a,(10 + y * 40 + 10 * 960 : U32),2))
def verify.inherit(w: W.World) -> IO(Unit):
  W.World{_, bs, n, c, _, _} = w
  check((U32.is_eq(n,3) && U32.is_eq(c,2) && inheritance(bs)), "split moving body preserves velocity")
def verify.resume(w: W.World) -> IO(Unit):
  W.World{_, bs, _, _, _, _} = w
  check(Bool.not(landed(bs)), "removing landed body's bottom resumes fall")
def main() -> IO(Unit):
  do IO<Unit>:
    w : W.World <- inspect(W.initial(),4640,0,1,"initial scene")
    w : W.World <- inspect(W.carve(w,R.Vec{(0.0 - 1.0 : F32),1.05,0.3}),4622,0,1,"partial cut")
    w : W.World <- inspect(sever(w,(0.0 - 1.0 : F32)),4524,0,1,"one support remains")
    w : W.World <- inspect(sever(w,1.0),4408,1,1,"last support detaches")
    Unit <- verify.landed(W.step(w,2.0))
    Unit <- verify.mesh(W.initial())
    Unit <- verify.mesh(sever(W.initial(),1.0))
    w : W.World <- inspect(fixture.two(41,2),2,1,1,"face connectivity")
    w : W.World <- inspect(fixture.two(81,2),2,2,1,"edge contact is not connectivity")
    w : W.World <- inspect(fixture.two(41,3),2,2,1,"different owners do not merge")
    w : W.World <- inspect(fixture.cap(),74,64,1,"64 body fixture")
    w : W.World <- inspect(W.carve(w,W.xyz(19125)),74,64,3,"over-cap cut rolls back")
    w : W.World <- inspect(W.carve(w,W.xyz(2122)),73,63,1,"removing body frees slot")
    w : W.World <- inspect(W.carve(w,W.xyz(19125)),68,64,1,"split at cap commits")
    Unit <- verify.inherit(W.carve(W.step(W.rebuild(fixture.vertical(8n,10,Array.new(U32,15n,0)),Nil{},8,0),0.1),R.Vec{(0.0 - 0.95 : F32),1.30095,0.05}))
    Unit <- verify.resume(W.carve(W.step(W.rebuild(fixture.vertical(6n,5,Array.new(U32,15n,0)),Nil{},6,0),2.0),R.Vec{(0.0 - 0.95 : F32),0.05,0.05}))
    w : W.World <- inspect(W.carve(W.initial(),R.Vec{20.0,20.0,20.0}),4640,0,2,"empty cut changes nothing")
    IO.print("ALL WORLD CHECKS PASSED")
