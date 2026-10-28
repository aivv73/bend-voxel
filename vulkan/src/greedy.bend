import Base
import ./exterior.bend as E
import ../../voxel.bend as X

type Axis is Data:
  Horizontal{}
  Vertical{}

def order(+a: U32, +b: U32, tie: Bool) -> Bool:
  Bool.pick(Bool,U32.is_eq(a,b),tie,(a < b : U32))

def before(a: E.Patch, b: E.Patch, axis: Axis) -> Bool:
  E.Patch{n,d,m,E.Rect2{+u0,+u1,+v0,+v1}} = a
  E.Patch{k,f,c,E.Rect2{+x0,+x1,+y0,+y1}} = b
  match axis:
    case Horizontal{}:
      order(E.direction(d),E.direction(f),order(n,k,order(m,c,order(v0,y0,order(v1,y1,order(u0,x0,order(u1,x1,True{})))))))
    case Vertical{}:
      order(E.direction(d),E.direction(f),order(n,k,order(m,c,order(u0,x0,order(u1,x1,order(v0,y0,order(v1,y1,True{})))))))

def horizontal(a: E.Patch, b: E.Patch) -> Bool:
  before(a,b,Horizontal{})

def vertical(a: E.Patch, b: E.Patch) -> Bool:
  before(a,b,Vertical{})

def join(a: E.Patch, b: E.Patch, axis: Axis) -> Maybe<&2,E.Patch>:
  E.Patch{+n,+d,+m,E.Rect2{+u0,+u1,+v0,+v1}} = a
  E.Patch{k,f,c,E.Rect2{+x0,+x1,+y0,+y1}} = b
  match axis:
    case Horizontal{}:
      Bool.pick(Maybe<&2,E.Patch>,U32.is_eq(n,k) && U32.is_eq(E.direction(d),E.direction(f)) && U32.is_eq(m,c) && U32.is_eq(v0,y0) && U32.is_eq(v1,y1) && U32.is_eq(u1,x0),Some{E.Patch{n,d,m,E.Rect2{u0,x1,v0,v1}}},None{})
    case Vertical{}:
      Bool.pick(Maybe<&2,E.Patch>,U32.is_eq(n,k) && U32.is_eq(E.direction(d),E.direction(f)) && U32.is_eq(m,c) && U32.is_eq(u0,x0) && U32.is_eq(u1,x1) && U32.is_eq(v1,y0),Some{E.Patch{n,d,m,E.Rect2{u0,u1,v0,y1}}},None{})

def scan_step(merged: Maybe<&2,E.Patch>, head: E.Patch, tail: E.Patch, next: E.Patch -> List<&2,E.Patch>) -> List<&2,E.Patch>:
  match merged:
    case Some{patch}: next(patch)
    case None{}: head <> next(tail)

def scan(xs: List<&2,E.Patch>, +axis: Axis, +head: E.Patch) -> List<&2,E.Patch>:
  match xs:
    case Nil{}: [head]
    case +tail <> rest: scan_step(join(head,tail,axis),head,tail,patch => scan(rest,axis,patch))

def coalesce(xs: List<&2,E.Patch>, +axis: Axis) -> List<&2,E.Patch>:
  match xs:
    case Nil{}: Nil{}
    case head <> rest: scan(rest,axis,head)

def patches(xs: List<&2,X.Face>) -> List<&2,E.Patch>:
  match xs:
    case Nil{}: Nil{}
    case face <> rest: E.patch(face) <> patches(rest)

def faces(xs: List<&2,E.Patch>) -> List<&2,X.Face>:
  match xs:
    case Nil{}: Nil{}
    case E.Patch{n,d,m,r} <> rest: E.face(n,d,m,r) <> faces(rest)

def finish(smaller: Bool, patches: List<&2,E.Patch>, next: List<&2,E.Patch> -> List<&2,E.Patch>) -> List<&2,E.Patch>:
  match smaller:
    case False{}: patches
    case True{}: next(patches)

def passes(fuel: Nat, +xs: List<&2,E.Patch>, +count: Nat) -> List<&2,E.Patch>:
  match fuel:
    case 0n: xs
    case 1n+rest:
      +next = coalesce(List.sort(~E.Patch,~vertical,coalesce(List.sort(~E.Patch,~horizontal,xs),Horizontal{})),Vertical{})
      +size = List.length(&2,E.Patch,next)
      finish(Nat.is_lt(size,count),next,items => passes(rest,items,size))

def merge_faces(+xs: List<&2,X.Face>) -> List<&2,X.Face>:
  +count = List.length(&2,X.Face,xs)
  faces(passes(count,patches(xs),count))
