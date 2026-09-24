import Base
import ./math.bend as R

# Bounds are half-open, integral cell coordinates (one cell = 0.1 meters).
# Signed F32 integers are exact over the supported +/- 2^23-cell range.
# Leaves are disjoint solid cuboids; air occupies no storage. Material 1 is
# an explicit protected anchor. The tree is both storage and spatial index.
type Box is Data:
  Box{lo: R.Vec, hi: R.Vec, material: U32}
type Tree is Data:
  Empty{}
  Leaf{box: Box}
  Branch{bounds: Box, left: Tree, right: Tree}
type Face is Data:
  Face{lo: R.Vec, hi: R.Vec, side: U32, material: U32}

def axis(v: R.Vec, a: U32) -> F32:
  match v a:
    case R.Vec{x,_,_} 0: x
    case R.Vec{_,y,_} 1: y
    case R.Vec{_,_,z} _: z
def put(v: R.Vec, a: U32, q: F32) -> R.Vec:
  match v a:
    case R.Vec{_,y,z} 0: R.Vec{q,y,z}
    case R.Vec{x,_,z} 1: R.Vec{x,q,z}
    case R.Vec{x,y,_} _: R.Vec{x,y,q}
def minimum(a: R.Vec, b: R.Vec) -> R.Vec:
  R.Vec{x,y,z} = a
  R.Vec{u,v,w} = b
  R.Vec{R.min(x,u),R.min(y,v),R.min(z,w)}
def maximum(a: R.Vec, b: R.Vec) -> R.Vec:
  R.Vec{x,y,z} = a
  R.Vec{u,v,w} = b
  R.Vec{R.max(x,u),R.max(y,v),R.max(z,w)}
def bounds(t: Tree) -> Box:
  match t:
    case Empty{}: Box{R.Vec{0.0,0.0,0.0},R.Vec{0.0,0.0,0.0},0}
    case Leaf{b}: b
    case Branch{b,_,_}: b
def merge(a: Box, b: Box) -> Box:
  Box{al,ah,_} = a
  Box{bl,bh,_} = b
  Box{minimum(al,bl),maximum(ah,bh),0}
def branch(a: Tree, b: Tree) -> Tree:
  match a b:
    case Empty{} _: b
    case _ Empty{}: a
    case +a +b: Branch{merge(bounds(a),bounds(b)),a,b}
def volume.vec(v: R.Vec) -> U32:
  R.Vec{x,y,z} = v
  (F32.to_u32(x) * F32.to_u32(y) * F32.to_u32(z) : U32)
def volume(b: Box) -> U32:
  Box{l,h,_} = b
  volume.vec(R.Vec.sub(h,l))
def count(t: Tree) -> U32:
  match t:
    case Empty{}: 0
    case Leaf{b}: volume(b)
    case Branch{_,a,b}: (count(a) + count(b) : U32)
def leaves(t: Tree) -> U32:
  match t:
    case Empty{}: 0
    case Leaf{_}: 1
    case Branch{_,a,b}: (leaves(a) + leaves(b) : U32)
def anchored(t: Tree) -> Bool:
  match t:
    case Empty{}: False{}
    case Leaf{Box{_,_,m}}: U32.is_eq(m,1)
    case Branch{_,a,b}: (anchored(a) || anchored(b))
def boxes(t: Tree, tail: List<&2,Box>) -> List<&2,Box>:
  match t:
    case Empty{}: tail
    case Leaf{b}: b <> tail
    case Branch{_,a,b}: boxes(a,boxes(b,tail))
def list.bounds(bs: List<&2,Box>, b: Box) -> Box:
  match bs:
    case Nil{}: b
    case h <> t: list.bounds(t,merge(b,h))
def longest.vec(v: R.Vec) -> U32:
  R.Vec{+x,+y,+z} = v
  R.word(((x >= y) && (x >= z) : F32),0,R.word((y >= z : F32),1,2))
def longest(b: Box) -> U32:
  Box{l,h,_} = b
  longest.vec(R.Vec.sub(h,l))
type Split is Data:
  Split{left: List<&2,Box>, right: List<&2,Box>}
def partition.add(on: Bool, b: Box, s: Split) -> Split:
  match on s:
    case True{} Split{a,c}: Split{b <> a,c}
    case False{} Split{a,c}: Split{a,b <> c}
def partition(bs: List<&2,Box>, +a: U32, +mid: F32, s: Split) -> Split:
  match bs:
    case Nil{}: s
    case +b <> rest:
      Box{l,h,_} = b
      partition(rest,a,mid,partition.add(((axis(l,a) + axis(h,a)) < (mid * 2.0) : F32),b,s))
def alternate(bs: List<&2,Box>, a: List<&2,Box>, b: List<&2,Box>) -> Split:
  match bs:
    case Nil{}: Split{a,b}
    case h <> t: alternate(t,b,h <> a)
@unsafe
def build.split(s: Split) -> Tree:
  Split{a,b} = s
  branch(build(a),build(b))
@unsafe
def build.partition(s: Split, original: List<&2,Box>) -> Tree:
  match s:
    case Split{Nil{},_}: build.split(alternate(original,Nil{},Nil{}))
    case Split{_,Nil{}}: build.split(alternate(original,Nil{},Nil{}))
    case s: build.split(s)
@unsafe
def build.at(+bs: List<&2,Box>, +b: Box) -> Tree:
  Box{l,h,_} = b
  +a = longest(b)
  build.partition(partition(bs,a,((axis(l,a) + axis(h,a)) * 0.5 : F32),Split{Nil{},Nil{}}),bs)
@unsafe
def build(bs: List<&2,Box>) -> Tree:
  match bs:
    case Nil{}: Empty{}
    case b <> Nil{}: Leaf{b}
    case +b <> +rest: build.at(b <> rest,list.bounds(rest,b))

def overlaps(a: Box, b: Box) -> Bool:
  Box{R.Vec{ax,ay,az},R.Vec{au,av,aw},_} = a
  Box{R.Vec{bx,by,bz},R.Vec{bu,bv,bw},_} = b
  (((ax <= bu) && (au >= bx) && (ay <= bv) && (av >= by) && (az <= bw) && (aw >= bz)) : F32)
def adjacent(a: Box, b: Box) -> Bool:
  Box{R.Vec{+ax,+ay,+az},R.Vec{+au,+av,+aw},_} = a
  Box{R.Vec{+bx,+by,+bz},R.Vec{+bu,+bv,+bw},_} = b
  +x = ((ax < bu) && (au > bx) : F32)
  +y = ((ay < bv) && (av > by) : F32)
  +z = ((az < bw) && (aw > bz) : F32)
  ((((F32.is_eq(ax,bu) || F32.is_eq(au,bx)) && y && z) ||
    ((F32.is_eq(ay,bv) || F32.is_eq(av,by)) && x && z) ||
    ((F32.is_eq(az,bw) || F32.is_eq(aw,bz)) && x && y)))
# Connectivity visits compressed occupied regions, across every shared face.
# Extracting reached leaves from the tree also acts as the visited set.
type Taken is Data:
  Taken{remaining: Tree, found: List<&2,Box>}
def take.leaf(on: Bool, b: Box, todo: List<&2,Box>) -> Taken:
  match on:
    case True{}: Taken{Empty{},b <> todo}
    case False{}: Taken{Leaf{b},todo}
def take.right(a: Tree, r: Taken) -> Taken:
  Taken{b,found} = r
  Taken{branch(a,b),found}
@unsafe
def take.left(r: Taken, b: Tree, q: Box) -> Taken:
  Taken{a,todo} = r
  take.right(a,take(b,q,todo))
@unsafe
def take.go(on: Bool, t: Tree, +q: Box, todo: List<&2,Box>) -> Taken:
  match on t:
    case False{} _: Taken{t,todo}
    case True{} Empty{}: Taken{Empty{},todo}
    case True{} Leaf{+b}: take.leaf(adjacent(q,b),b,todo)
    case True{} Branch{_,a,b}: take.left(take(a,q,todo),b,q)
@unsafe
def take(+t: Tree, +q: Box, todo: List<&2,Box>) -> Taken:
  take.go(overlaps(bounds(t),q),t,q,todo)
type Component is Data:
  Component{remaining: Tree, connected: Tree}
@unsafe
def flood.taken(r: Taken, done: List<&2,Box>) -> Component:
  Taken{t,todo} = r
  flood(t,todo,done)
@unsafe
def flood(t: Tree, todo: List<&2,Box>, done: List<&2,Box>) -> Component:
  match todo:
    case Nil{}: Component{t,build(done)}
    case +b <> rest: flood.taken(take(t,b,rest),b <> done)
type First is Data:
  First{remaining: Tree, box: Box}
def first.left(r: First, b: Tree) -> First:
  First{a,box} = r
  First{branch(a,b),box}
def first(t: Tree) -> First:
  match t:
    case Empty{}: First{Empty{},Box{R.Vec{0.0,0.0,0.0},R.Vec{0.0,0.0,0.0},0}}
    case Leaf{b}: First{Empty{},b}
    case Branch{_,a,b}: first.left(first(a),b)
def component.first(r: First) -> Component:
  First{t,b} = r
  flood(t,[b],Nil{})
def component(t: Tree) -> Component:
  component.first(first(t))

# Carving subdivides only leaves intersecting the sphere. Tests use centers,
# just as the original cell-by-cell removal did. Protected material survives.
def farthest(a: R.Vec, b: R.Vec) -> F32:
  R.Vec{x,y,z} = a
  R.Vec{u,v,w} = b
  +d = {R.Vec{R.max(F32.abs(x),F32.abs(u)),R.max(F32.abs(y),F32.abs(v)),R.max(F32.abs(z),F32.abs(w))} : R.Vec}
  R.Vec.dot(d,d)
def distance(+p: R.Vec, b: Box, far: Bool) -> F32:
  Box{l,h,_} = b
  +lo = R.Vec.add(l,R.Vec{0.5,0.5,0.5})
  +hi = R.Vec.sub(h,R.Vec{0.5,0.5,0.5})
  +near = R.Vec.sub(p,maximum(lo,minimum(p,hi)))
  +d0 = R.Vec.sub(p,lo)
  +d1 = R.Vec.sub(p,hi)
  R.pick(far,farthest(d0,d1),R.Vec.dot(near,near))
@unsafe
def cut.split(+b: Box, +p: R.Vec, +r2: F32) -> Tree:
  Box{+l,+h,+m} = b
  +a = longest(b)
  +mid = F32.floor(((axis(l,a) + axis(h,a)) * 0.5 : F32))
  branch(cut(Leaf{Box{l,put(h,a,mid),m}},p,r2),cut(Leaf{Box{put(l,a,mid),h,m}},p,r2))
@unsafe
def cut.leaf(remove: Bool, b: Box, p: R.Vec, r2: F32) -> Tree:
  match remove:
    case True{}: Empty{}
    case False{}: cut.split(b,p,r2)
@unsafe
def cut.go(hit: Bool, t: Tree, +p: R.Vec, +r2: F32) -> Tree:
  match hit t:
    case False{} _: t
    case True{} Empty{}: Empty{}
    case True{} Leaf{Box{l,h,1}}: Leaf{Box{l,h,1}}
    case True{} Leaf{+b}: cut.leaf((distance(p,b,True{}) <= r2 : F32),b,p,r2)
    case True{} Branch{_,a,b}: branch(cut(a,p,r2),cut(b,p,r2))
@unsafe
def cut(+t: Tree, +p: R.Vec, +r2: F32) -> Tree:
  cut.go((distance(p,bounds(t),False{}) <= r2 : F32),t,p,r2)

# A face has zero thickness on its normal axis. Subtracting neighboring
# boxes hides internal surfaces without expanding their voxels.
def face(b: Box, +s: U32) -> Face:
  Box{+l,+h,m} = b
  +a = (s / 2 : U32)
  +q = R.pick(U32.is_eq((s % 2 : U32),0),axis(l,a),axis(h,a))
  Face{put(l,a,q),put(h,a,q),s,m}
def face.valid(+f: Face) -> Bool:
  Face{l,h,+s,_} = f
  +u = ((s / 2 + 1) % 3 : U32)
  +v = ((s / 2 + 2) % 3 : U32)
  ((axis(h,u) > axis(l,u)) && (axis(h,v) > axis(l,v)) : F32)
def face.emit(on: Bool, f: Face, tail: List<&2,Face>) -> List<&2,Face>:
  match on:
    case True{}: f <> tail
    case False{}: tail
def face.add(+f: Face, tail: List<&2,Face>) -> List<&2,Face>:
  face.emit(face.valid(f),f,tail)
def face.subtract(+f: Face, b: Box, tail: List<&2,Face>) -> List<&2,Face>:
  Face{+l,+h,+s,+m} = f
  Box{bl,bh,_} = b
  +u = ((s / 2 + 1) % 3 : U32)
  +v = ((s / 2 + 2) % 3 : U32)
  +lo = maximum(l,bl)
  +hi = minimum(h,bh)
  +middleL = put(l,u,axis(lo,u))
  +middleH = put(h,u,axis(hi,u))
  face.add(Face{l,put(h,u,axis(lo,u)),s,m},
    face.add(Face{put(l,u,axis(hi,u)),h,s,m},
      face.add(Face{middleL,put(middleH,v,axis(lo,v)),s,m},
        face.add(Face{put(middleL,v,axis(hi,v)),middleH,s,m},tail))))
def face.covered(f: Face, b: Box) -> Bool:
  Face{+l,+h,+s,_} = f
  Box{+bl,+bh,_} = b
  +a = (s / 2 : U32)
  +u = ((a + 1) % 3 : U32)
  +v = ((a + 2) % 3 : U32)
  (F32.is_eq(axis(l,a),R.pick(U32.is_eq((s % 2 : U32),0),axis(bh,a),axis(bl,a))) &&
    ((axis(l,u) < axis(bh,u)) && (axis(h,u) > axis(bl,u)) &&
     (axis(l,v) < axis(bh,v)) && (axis(h,v) > axis(bl,v)) : F32))
def face.clip(on: Bool, f: Face, b: Box, tail: List<&2,Face>) -> List<&2,Face>:
  match on:
    case True{}: face.subtract(f,b,tail)
    case False{}: f <> tail
def faces.clip(fs: List<&2,Face>, +b: Box) -> List<&2,Face>:
  match fs:
    case Nil{}: Nil{}
    case +f <> rest: face.clip(face.covered(f,b),f,b,faces.clip(rest,b))
def face.bounds(f: Face) -> Box:
  Face{l,h,_,_} = f
  Box{l,h,0}
@unsafe
def faces.hide.go(on: Bool, t: Tree, +q: Box, fs: List<&2,Face>) -> List<&2,Face>:
  match on t:
    case False{} _: fs
    case True{} Empty{}: fs
    case True{} Leaf{b}: faces.clip(fs,b)
    case True{} Branch{_,a,b}: faces.hide(b,q,faces.hide(a,q,fs))
@unsafe
def faces.hide(+t: Tree, +q: Box, fs: List<&2,Face>) -> List<&2,Face>:
  faces.hide.go(overlaps(bounds(t),q),t,q,fs)
def append(-T: Data, xs: List<&2,T>, ys: List<&2,T>) -> List<&2,T>:
  match xs:
    case Nil{}: ys
    case x <> rest: x <> append(T,rest,ys)
def faces.side(n: Nat, +s: U32, +b: Box, +t: Tree, fs: List<&2,Face>) -> List<&2,Face>:
  match n:
    case 0n: fs
    case 1n+k:
      +f = face(b,s)
      faces.side(k,(s + 1 : U32),b,t,append(Face,faces.hide(t,face.bounds(f),[f]),fs))
def faces.go(bs: List<&2,Box>, +t: Tree, fs: List<&2,Face>) -> List<&2,Face>:
  match bs:
    case Nil{}: fs
    case b <> rest: faces.go(rest,t,faces.side(6n,0,b,t,fs))
def faces(+t: Tree) -> List<&2,Face>:
  faces.go(boxes(t,Nil{}),t,Nil{})

# Occupancy queries are useful for diagnostics and dense-reference tests.
def contains.box(b: Box, p: R.Vec) -> Bool:
  Box{R.Vec{lx,ly,lz},R.Vec{hx,hy,hz},_} = b
  R.Vec{+x,+y,+z} = p
  (((x >= lx) && (x < hx) && (y >= ly) && (y < hy) && (z >= lz) && (z < hz)) : F32)
@unsafe
def contains.go(on: Bool, t: Tree, +p: R.Vec) -> Bool:
  match on t:
    case False{} _: False{}
    case True{} Empty{}: False{}
    case True{} Leaf{_}: True{}
    case True{} Branch{_,a,b}: (contains(a,p) || contains(b,p))
@unsafe
def contains(+t: Tree, +p: R.Vec) -> Bool:
  contains.go(contains.box(bounds(t),p),t,p)
