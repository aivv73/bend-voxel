import Base
import ../src/terrain.bend as T

def check(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.print("PASS " ++ label)
    case False{}: IO.die(Unit,1,"FAIL " ++ label)
def samples(n: Nat, +i: U32, +t: T.Tree) -> Bool:
  match n:
    case 0n: True{}
    case 1n+k:
      +x = (i % 32 : U32)
      +y = (i / 32 % 32 : U32)
      +z = (i / 1024 : U32)
      (U32.is_eq(T.sample(t,x,y,z),T.material(x,y,z)) && samples(k,(i + 1 : U32),t))
def face.valid(f: T.Face, +t: T.Tree) -> Bool:
  T.Face{+x,+y,+z,+s,+m} = f
  ((m > 0 : U32) && (s < 6 : U32) && U32.is_eq(T.sample(t,x,y,z),m) && U32.is_eq(T.neighbor(t,x,y,z,s),0))
def faces.valid(fs: List<&2,T.Face>, +t: T.Tree) -> Bool:
  match fs:
    case Nil{}: True{}
    case f <> rest: (face.valid(f,t) && faces.valid(rest,t))
def count(fs: List<&2,T.Face>) -> U32:
  match fs:
    case Nil{}: 0
    case _ <> rest: (1 + count(rest) : U32)
# Independent height-column oracle: top/bottom plus exposed vertical walls.
def difference.choose(on: Bool, a: U32, b: U32) -> U32:
  match on:
    case True{}: (a - b : U32)
    case False{}: 0
def difference(+a: U32, +b: U32) -> U32:
  difference.choose((a > b : U32),a,b)
def height.inside(on: Bool, x: U32, z: U32) -> U32:
  match on:
    case True{}: T.height(x,z)
    case False{}: 0
def height(+x: U32, +z: U32) -> U32:
  height.inside(((x < 32) && (z < 32) : U32),x,z)
def expected(n: Nat, +i: U32) -> U32:
  match n:
    case 0n: 0
    case 1n+k:
      +x = (i % 32 : U32)
      +z = (i / 32 : U32)
      +h = T.height(x,z)
      (2 + difference(h,height((x - 1 : U32),z)) + difference(h,height((x + 1 : U32),z)) + difference(h,height(x,(z - 1 : U32))) + difference(h,height(x,(z + 1 : U32))) + expected(k,(i + 1 : U32)) : U32)
def volume(n: Nat, +i: U32) -> U32:
  match n:
    case 0n: 0
    case 1n+k: (T.height((i % 32 : U32),(i / 32 : U32)) + volume(k,(i + 1 : U32)) : U32)
def main() -> IO(Unit):
  +t = T.initial()
  +fs = T.surface(t)
  do IO<Unit>:
    Unit <- check(samples(32768n,0,t),"all 32768 SVO samples match terrain generator")
    Unit <- check((U32.is_eq(T.sample(t,32,0,0),0) && U32.is_eq(T.sample(t,0,32,0),0) && U32.is_eq(T.sample(t,0,0,32),0) && U32.is_eq(T.sample(t,4294967295,0,0),0)),"outside domain is empty")
    Unit <- check((T.nodes(t) < 32768 : U32),"SVO compresses terrain")
    Unit <- check(T.uniform(T.merge(T.Leaf{2},T.Leaf{2},T.Leaf{2},T.Leaf{2},T.Leaf{2},T.Leaf{2},T.Leaf{2},T.Leaf{2}),2),"uniform children collapse")
    Unit <- check(U32.is_eq(T.nodes(T.merge(T.Leaf{0},T.Leaf{1},T.Leaf{0},T.Leaf{0},T.Leaf{0},T.Leaf{0},T.Leaf{0},T.Leaf{0})),9),"mixed children remain a branch")
    Unit <- check(U32.is_eq(T.solids(t,32),volume(1024n,0)),"SVO volume matches height columns")
    Unit <- check(faces.valid(fs,t),"every cached face borders air")
    Unit <- check(U32.is_eq(count(fs),expected(1024n,0)),"surface face count matches independent oracle")
    IO.print("NODES " ++ U32.show(T.nodes(t)) ++ " SOLIDS " ++ U32.show(T.solids(t,32)) ++ " FACES " ++ U32.show(count(fs)))
