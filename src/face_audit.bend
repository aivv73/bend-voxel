import Base
import ./math.bend as R
import ./spatial.bend as S

# Diagnostic mirror of the full S.faces builder. It counts clipping work
# after the timed production edit, outside the surface-stage measurement.
type Counts is Data:
  Counts{treeNodes: U32, cuboidCandidates: U32, faceChecks: U32, faceClips: U32}
type Work is Data:
  Work{faces: List<&2,S.Face>, counts: Counts}
type FaceProfile is Data:
  FaceProfile{faces: List<&2,S.Face>, cuboids: U32, candidateFaces: U32,
    treeNodes: U32, cuboidCandidates: U32, faceChecks: U32, faceClips: U32, outputFaces: U32}
def zero() -> Counts:
  Counts{0,0,0,0}
def add(a: Counts, b: Counts) -> Counts:
  Counts{an,ab,ac,as} = a
  Counts{bn,bb,bc,bs} = b
  Counts{(an + bn : U32),(ab + bb : U32),(ac + bc : U32),(as + bs : U32)}
def checked(c: Counts, covered: Bool) -> Counts:
  Counts{n,b,checks,clips} = c
  Counts{n,b,(checks + 1 : U32),(clips + R.word(covered,1,0) : U32)}
def use(-T: Type, w: Work, k: List<&2,S.Face> -> Counts -> T) -> T:
  Work{fs,c} = w
  k(fs,c)
def clipped(fs: List<&2,S.Face>, +b: S.Box) -> Work:
  match fs:
    case Nil{}: Work{Nil{},zero()}
    case +f <> rest:
      +covered = S.face.covered(f,b)
      use(Work,clipped(rest,b),tail => counts =>
        Work{S.face.clip(covered,f,b,tail),checked(counts,covered)})
@unsafe
def hidden(on: Bool, t: S.Tree, +q: S.Box, fs: List<&2,S.Face>) -> Work:
  match on t:
    case False{} _: Work{fs,Counts{1,0,0,0}}
    case True{} S.Empty{}: Work{fs,Counts{1,0,0,0}}
    case True{} S.Leaf{b}:
      use(Work,clipped(fs,b),out => counts =>
        Work{out,add(counts,Counts{1,1,0,0})})
    case True{} S.Branch{_,+a,+b}:
      use(Work,hidden(S.overlaps(S.bounds(a),q),a,q,fs),left => lc =>
        use(Work,hidden(S.overlaps(S.bounds(b),q),b,q,left),right => rc =>
          Work{right,add(Counts{1,0,0,0},add(lc,rc))}))
def sides(n: Nat, +side: U32, +b: S.Box, +t: S.Tree, fs: List<&2,S.Face>) -> Work:
  match n:
    case 0n: Work{fs,zero()}
    case 1n+k:
      +f = S.face(b,side)
      +q = S.face.bounds(f)
      use(Work,hidden(S.overlaps(S.bounds(t),q),t,q,[f]),generated => first =>
        use(Work,sides(k,(side + 1 : U32),b,t,S.append(S.Face,generated,fs)),out => rest =>
          Work{out,add(first,rest)}))
def go(bs: List<&2,S.Box>, +t: S.Tree, fs: List<&2,S.Face>) -> Work:
  match bs:
    case Nil{}: Work{fs,zero()}
    case b <> rest:
      use(Work,sides(6n,0,b,t,fs),partial => first =>
        use(Work,go(rest,t,partial),out => later =>
          Work{out,add(first,later)}))
def face.count(fs: List<&2,S.Face>) -> U32:
  match fs:
    case Nil{}: 0
    case _ <> rest: (1 + face.count(rest) : U32)
def result(+t: S.Tree, w: Work) -> FaceProfile:
  Work{+fs,Counts{nodes,candidates,checks,clips}} = w
  +cuboids = S.leaves(t)
  FaceProfile{fs,cuboids,(cuboids * 6 : U32),nodes,candidates,checks,clips,face.count(fs)}
def faces(+t: S.Tree) -> FaceProfile:
  result(t,go(S.boxes(t,Nil{}),t,Nil{}))

def vec.same(a: R.Vec, b: R.Vec) -> Bool:
  R.Vec{ax,ay,az} = a
  R.Vec{bx,by,bz} = b
  (F32.is_eq(ax,bx) && F32.is_eq(ay,by) && F32.is_eq(az,bz))
def face.same(a: S.Face, b: S.Face) -> Bool:
  S.Face{al,ah,as,am} = a
  S.Face{bl,bh,bs,bm} = b
  (vec.same(al,bl) && vec.same(ah,bh) && U32.is_eq(as,bs) && U32.is_eq(am,bm))
def same(a: List<&2,S.Face>, b: List<&2,S.Face>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: (face.same(x,y) && same(xs,ys))
    case _ _: False{}

# A local rebuild may split a large rectangle at the cut window. Compare
# covered surface area per rectangle, side, and material instead of list order.
def area(f: S.Face) -> U32:
  S.Face{l,h,+s,_} = f
  +u = ((s / 2 + 1) % 3 : U32)
  +v = ((s / 2 + 2) % 3 : U32)
  +d = R.Vec.sub(h,l)
  F32.to_u32((S.axis(d,u) * S.axis(d,v) : F32))
def intersection(a: S.Face, b: S.Face) -> U32:
  S.Face{+al,ah,+as,+am} = a
  S.Face{+bl,bh,bs,bm} = b
  +u = ((as / 2 + 1) % 3 : U32)
  +v = ((as / 2 + 2) % 3 : U32)
  +lo = S.maximum(al,bl)
  +hi = S.minimum(ah,bh)
  +x = R.max(0.0,(S.axis(hi,u) - S.axis(lo,u) : F32))
  +y = R.max(0.0,(S.axis(hi,v) - S.axis(lo,v) : F32))
  R.word((U32.is_eq(as,bs) && U32.is_eq(am,bm) &&
    F32.is_eq(S.axis(al,(as / 2 : U32)),S.axis(bl,(as / 2 : U32)))),
    F32.to_u32((x * y : F32)),0)
def overlaps.sum(+f: S.Face, fs: List<&2,S.Face>) -> U32:
  match fs:
    case Nil{}: 0
    case b <> rest: (intersection(f,b) + overlaps.sum(f,rest) : U32)
def covered.by(fs: List<&2,S.Face>, +other: List<&2,S.Face>) -> Bool:
  match fs:
    case Nil{}: True{}
    case +f <> rest: (U32.is_eq(area(f),overlaps.sum(f,other)) && covered.by(rest,other))
def equivalent(+a: List<&2,S.Face>, +b: List<&2,S.Face>) -> Bool:
  (covered.by(a,b) && covered.by(b,a))
