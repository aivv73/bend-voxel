import Base
import ./math.bend as R
import ./megascene_recipe.bend as Recipe
import ./megascene_scale.bend as Scale

type Integer is Data:
  Integer{negative: Bool, magnitude: Scale.Integer}
  InvalidInteger{}
type Extent is Data:
  Finite{numerator: Integer, denominator: Scale.Integer}
  Infinite{negative: Bool}
  Vertical{}
  InvalidExtent{}
type ExactVec is Data:
  ExactVec{x: Integer, y: Integer, z: Integer}
type ExactBox is Data:
  ExactBox{lo: ExactVec, hi: ExactVec, material: Maybe<&2,Integer>}
type ExactOwner is Data:
  ExactOwner{boxes: List<&2,ExactBox>}
type Axis is Data:
  Axis{lo: F32, hi: F32, dimension: Scale.Integer}
type BoxVolume is Data:
  BoxVolume{box: Recipe.Box, cells: U32}
type BoxBatch is Data:
  BoxBatch{boxes: List<&2,Recipe.Box>, total: U32}
type Bounds is Data:
  Bounds{cells: U32, surface: List<&2,U32>, vertices: U32, bytes: U32}
type Face is Data:
  Face{axis: U32, positive: Bool, plane: F32, u0: F32, u1: F32, v0: F32, v1: F32}
type Frontier is Data:
  Frontier{pending: List<&2,Recipe.Box>, unseen: List<&2,Recipe.Box>}
type Search is Data:
  Complete{ok: Bool}
  Advance{frontier: Frontier}
type Edges is Data:
  Edges{us: List<&2,F32>, vs: List<&2,F32>}

def require(-A: Data, ok: Bool, message: String, value: A) -> Result<&2,&2,String,A>:
  match ok:
    case True{}: Done{value}
    case False{}: Fail{message}

def checked.add.if(a: U32, b: U32, label: String, ok: Bool) -> Result<&2,&2,String,U32>:
  match ok:
    case True{}: Done{(a + b : U32)}
    case False{}: Fail{label ++ ": unsigned integer exceeds supported range"}

def checked.add(+a: U32, +b: U32, label: String) -> Result<&2,&2,String,U32>:
  checked.add.if(a,b,label,(b <= 4294967295 - a : U32))

def checked.mul.if(a: U32, b: U32, label: String, ok: Bool) -> Result<&2,&2,String,U32>:
  match ok:
    case True{}: Done{(a * b : U32)}
    case False{}: Fail{label ++ ": unsigned integer exceeds supported range"}

def checked.mul.zero(+a: U32, +b: U32, label: String, zero: Bool) -> Result<&2,&2,String,U32>:
  match zero:
    case True{}: Done{0}
    case False{}: checked.mul.if(a,b,label,(b <= 4294967295 / a : U32))

def checked.mul(+a: U32, +b: U32, label: String) -> Result<&2,&2,String,U32>:
  checked.mul.zero(a,b,label,U32.is_eq(a,0))

def checked.magnitude.if(n: Scale.Integer, label: String, ok: Bool) -> Result<&2,&2,String,U32>:
  match ok:
    case True{}: Done{Scale.Integer.to_u32(n)}
    case False{}: Fail{label ++ ": unsigned integer exceeds supported range"}

def checked.magnitude(+n: Scale.Integer, label: String) -> Result<&2,&2,String,U32>:
  checked.magnitude.if(n,label,Scale.Integer.le(n,Scale.Integer.from_u32(32n,4294967295)))

def checked.integer(n: Integer, label: String) -> Result<&2,&2,String,U32>:
  match n:
    case Integer{False{},m}: checked.magnitude(m,label)
    case Integer{True{},_}: Fail{label ++ ": unsigned integer exceeds supported range"}
    case InvalidInteger{}: Fail{label ++ ": unsigned integer exceeds supported range"}

def checked.count(-A: Data, xs: List<&2,A>, acc: U32, +label: String) -> Result<&2,&2,String,U32>:
  match xs:
    case Nil{}: Done{acc}
    case _ <> rest:
      do Result<&2,&2,String,U32>:
        n : U32 <- checked.add(acc,1,label)
        checked.count(A,rest,n,label)

def Integer.make(negative: Bool, magnitude: Scale.Integer) -> Integer:
  match magnitude:
    case Scale.ScaleZero{}: Integer{False{},Scale.ScaleZero{}}
    case Scale.ScaleBit{b,t}: Integer{negative,Scale.ScaleBit{b,t}}

def Integer.neg(n: Integer) -> Integer:
  match n:
    case Integer{negative,magnitude}: Integer.make(Bool.not(negative),magnitude)
    case InvalidInteger{}: InvalidInteger{}

def Integer.le(a: Integer, b: Integer) -> Bool:
  match a b:
    case Integer{False{},a} Integer{False{},b}: Scale.Integer.le(a,b)
    case Integer{True{},a} Integer{True{},b}: Scale.Integer.le(b,a)
    case Integer{True{},_} Integer{False{},_}: True{}
    case Integer{False{},_} Integer{True{},_}: False{}
    case _ _: False{}

def Integer.add.op.if(negative: Bool, a: Scale.Integer, b: Scale.Integer, order: Bool) -> Integer:
  match order:
    case True{}: Integer.make(negative,Scale.Integer.sub(a,b))
    case False{}: Integer.make(Bool.not(negative),Scale.Integer.sub(b,a))

def Integer.add.op(negative: Bool, +a: Scale.Integer, +b: Scale.Integer) -> Integer:
  Integer.add.op.if(negative,a,b,Scale.Integer.le(b,a))

def Integer.add(a: Integer, b: Integer) -> Integer:
  match a b:
    case Integer{False{},a} Integer{False{},b}: Integer.make(False{},Scale.Integer.add(a,b))
    case Integer{True{},a} Integer{True{},b}: Integer.make(True{},Scale.Integer.add(a,b))
    case Integer{False{},a} Integer{True{},b}: Integer.add.op(False{},a,b)
    case Integer{True{},a} Integer{False{},b}: Integer.add.op(True{},a,b)
    case _ _: InvalidInteger{}

def Integer.scale(n: Integer, denominator: Scale.Integer) -> Integer:
  match n:
    case Integer{negative,magnitude}: Integer.make(negative,Scale.Integer.mul(magnitude,denominator))
    case InvalidInteger{}: InvalidInteger{}

def Integer.drop.exact(fuel: Nat, magnitude: Scale.Integer) -> Maybe<&2,Scale.Integer>:
  match fuel magnitude:
    case 0n m: Some{m}
    case 1n+p Scale.ScaleBit{False{},rest}: Integer.drop.exact(p,rest)
    case _ _: None{}

def f32.bits(bits: U32) -> F32:
  U32{word} = bits
  F32{word}

def Integer.f32.significant(negative: Bool, +bits: Nat, result: Maybe<&2,Scale.Integer>) -> Maybe<&2,F32>:
  match result:
    case None{}: None{}
    case Some{m}:
      +significand_bits = Nat.min(bits,24n)
      +mantissa = (Scale.Integer.to_u32(m) << Nat.sub(24n,significand_bits) : U32)
      +exponent = (U32.from_nat(bits) + 126 : U32)
      Some{f32.bits(((Bool.to_u32(negative) << 31n) .|. (exponent << 23n) .|. (mantissa - 8388608) : U32))}

def Integer.f32.range(negative: Bool, +m: Scale.Integer, +bits: Nat, ok: Bool) -> Maybe<&2,F32>:
  match ok:
    case False{}: None{}
    case True{}: Integer.f32.significant(negative,bits,Integer.drop.exact(Nat.sub(bits,24n),m))

def Integer.f32(n: Integer) -> Maybe<&2,F32>:
  match n:
    case Integer{_,Scale.ScaleZero{}}: Some{0.0}
    case Integer{negative,+m}:
      +bits = Scale.Integer.bits(m)
      Integer.f32.range(negative,m,bits,Nat.is_le(bits,128n))
    case InvalidInteger{}: None{}

def exact.result(result: Maybe<&2,F32>, message: String) -> Result<&2,&2,String,F32>:
  match result:
    case None{}: Fail{message}
    case Some{f}: Done{f}

def exact(n: Integer, message: String) -> Result<&2,&2,String,F32>:
  exact.result(Integer.f32(n),message)

def envelope(+lo: Integer, +hi: Integer, extent: Extent) -> Bool:
  match extent:
    case Infinite{negative}: Bool.not(negative)
    case Vertical{}: Integer.le(Integer{False{},Scale.Integer.zero()},lo) &&
      Integer.le(hi,Integer{False{},Scale.Integer.from_u32(8n,128)})
    case InvalidExtent{}: False{}
    case Finite{+numerator,+denominator}:
      Integer.le(Integer.neg(numerator),Integer.scale(lo,denominator)) &&
        Integer.le(Integer.scale(hi,denominator),numerator)

def axis.difference(+lo: Integer, +hi: Integer, extent: Extent, difference: Integer) -> Result<&2,&2,String,Axis>:
  match difference:
    case InvalidInteger{}: Fail{"box outside supported fixed generation envelope"}
    case Integer{+negative,+dimension}:
      do Result<&2,&2,String,Axis>:
        _ : Unit <- require(Unit,Bool.not(negative) &&
          Bool.not(Scale.Integer.eq(dimension,Scale.Integer.zero())) && envelope(lo,hi,extent),
          "box outside supported fixed generation envelope",Unit{})
        low : F32 <- exact(lo,"inexact coordinate conversion")
        high : F32 <- exact(hi,"inexact coordinate conversion")
        _ : F32 <- exact(Integer{negative,dimension},"inexact coordinate conversion")
        _ : F32 <- exact(Integer.add(lo,hi),"inexact spatial split")
        return Axis{low,high,dimension}

def axis(+lo: Integer, +hi: Integer, extent: Extent) -> Result<&2,&2,String,Axis>:
  axis.difference(lo,hi,extent,Integer.add(hi,Integer.neg(lo)))

def material.range(m: Scale.Integer, ok: Bool) -> Result<&2,&2,String,U32>:
  match ok:
    case True{}: Done{Scale.Integer.to_u32(m)}
    case False{}: Fail{"unsupported material"}

def material(value: Maybe<&2,Integer>) -> Result<&2,&2,String,U32>:
  match value:
    case Some{Integer{False{},+m}}:
      material.range(m,Scale.Integer.le(Scale.Integer.one(),m) && Scale.Integer.le(m,Scale.Integer.five()))
    case _: Fail{"unsupported material"}

def box.axes(ax: Axis, ay: Axis, az: Axis, m: U32) -> Result<&2,&2,String,BoxVolume>:
  Axis{x,u,dx} = ax
  Axis{y,v,dy} = ay
  Axis{z,w,dz} = az
  do Result<&2,&2,String,BoxVolume>:
    dx : U32 <- checked.magnitude(dx,"box dimension")
    cells : U32 <- checked.mul(1,dx,"box volume")
    dy : U32 <- checked.magnitude(dy,"box dimension")
    cells : U32 <- checked.mul(cells,dy,"box volume")
    dz : U32 <- checked.magnitude(dz,"box dimension")
    cells : U32 <- checked.mul(cells,dz,"box volume")
    return BoxVolume{Recipe.Box{R.Vec{x,y,z},R.Vec{u,v,w},m},cells}

def box(value: ExactBox, +extent: Extent) -> Result<&2,&2,String,BoxVolume>:
  ExactBox{ExactVec{x,y,z},ExactVec{u,v,w},m} = value
  do Result<&2,&2,String,BoxVolume>:
    m : U32 <- material(m)
    ax : Axis <- axis(x,u,extent)
    ay : Axis <- axis(y,v,Vertical{})
    az : Axis <- axis(z,w,extent)
    box.axes(ax,ay,az,m)

def boxes.cons(source: Recipe.Box, result: BoxBatch) -> BoxBatch:
  BoxBatch{tail,total} = result
  BoxBatch{source <> tail,total}

def boxes.next(value: BoxVolume, total: U32, continuation: U32 -> Result<&2,&2,String,BoxBatch>) ->
  Result<&2,&2,String,BoxBatch>:
  BoxVolume{source,cells} = value
  do Result<&2,&2,String,BoxBatch>:
    total : U32 <- checked.add(total,cells,"world cell sum")
    result : BoxBatch <- continuation(total)
    return boxes.cons(source,result)

def boxes(xs: List<&2,ExactBox>, +extent: Extent, total: U32) -> Result<&2,&2,String,BoxBatch>:
  match xs:
    case Nil{}: Done{BoxBatch{Nil{},total}}
    case b <> rest:
      do Result<&2,&2,String,BoxBatch>:
        value : BoxVolume <- box(b,extent)
        boxes.next(value,total,n => boxes(rest,extent,n))

def component(v: R.Vec, axis: U32) -> F32:
  R.Vec{x,y,z} = v
  match axis:
    case 0: x
    case 1: y
    case _: z

def low(b: Recipe.Box, axis: U32) -> F32:
  Recipe.Box{lo,_,_} = b
  component(lo,axis)
def high(b: Recipe.Box, axis: U32) -> F32:
  Recipe.Box{_,hi,_} = b
  component(hi,axis)

def interval(+a: Recipe.Box, +b: Recipe.Box, +axis: U32) -> Bool:
  (R.max(low(a,axis),low(b,axis)) < R.min(high(a,axis),high(b,axis)) : F32)

def adjacent.axis(+a: Recipe.Box, +b: Recipe.Box, +axis: U32) -> Bool:
  (F32.is_eq(high(a,axis),low(b,axis)) || F32.is_eq(high(b,axis),low(a,axis))) &&
    interval(a,b,((axis + 1) % 3 : U32)) && interval(a,b,((axis + 2) % 3 : U32))

def adjacent(+a: Recipe.Box, +b: Recipe.Box) -> Bool:
  adjacent.axis(a,b,0) || adjacent.axis(a,b,1) || adjacent.axis(a,b,2)

def discover.choice(ok: Bool, b: Recipe.Box, pending: List<&2,Recipe.Box>, remaining: List<&2,Recipe.Box>) -> Frontier:
  match ok:
    case True{}: Frontier{b <> pending,remaining}
    case False{}: Frontier{pending,b <> remaining}

def discover.next(result: Frontier, continuation: List<&2,Recipe.Box> -> List<&2,Recipe.Box> -> Frontier) -> Frontier:
  Frontier{pending,remaining} = result
  continuation(pending,remaining)

def discover(+a: Recipe.Box, unseen: List<&2,Recipe.Box>, pending: List<&2,Recipe.Box>, remaining: List<&2,Recipe.Box>) ->
  Frontier:
  match unseen:
    case Nil{}: Frontier{pending,remaining}
    case +b <> rest:
      discover.next(discover.choice(adjacent(a,b),b,pending,remaining),
        pending => remaining => discover(a,rest,pending,remaining))

def connected.pending(pending: List<&2,Recipe.Box>, unseen: List<&2,Recipe.Box>) -> Search:
  match pending:
    case Nil{}: Complete{List.is_empty(&2,Recipe.Box,unseen)}
    case a <> rest: Advance{discover(a,unseen,rest,Nil{})}

def connected.result(result: Search, continuation: List<&2,Recipe.Box> -> List<&2,Recipe.Box> -> Bool) -> Bool:
  match result:
    case Complete{ok}: ok
    case Advance{Frontier{pending,unseen}}: continuation(pending,unseen)

def connected.go(fuel: Nat, pending: List<&2,Recipe.Box>, unseen: List<&2,Recipe.Box>) -> Bool:
  match fuel:
    case 0n: List.is_empty(&2,Recipe.Box,pending) && List.is_empty(&2,Recipe.Box,unseen)
    case 1n+p: connected.result(connected.pending(pending,unseen),
      pending => unseen => connected.go(p,pending,unseen))

def connected(xs: List<&2,Recipe.Box>) -> Bool:
  match xs:
    case Nil{}: False{}
    case +a <> +rest: connected.go(1n+List.length(&2,Recipe.Box,rest),[a],rest)

def anchor(xs: List<&2,Recipe.Box>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Recipe.Box{_,_,m} <> rest: U32.is_eq(m,1) || anchor(rest)

def face(+b: Recipe.Box, +axis: U32, +positive: Bool) -> Face:
  +u = ((axis + 1) % 3 : U32)
  +v = ((axis + 2) % 3 : U32)
  Face{axis,positive,R.pick(positive,high(b,axis),low(b,axis)),low(b,u),high(b,u),low(b,v),high(b,v)}

def face.edges.choose(ok: Bool, cu0: F32, cu1: F32, cv0: F32, cv1: F32,
    us: List<&2,F32>, vs: List<&2,F32>) -> Edges:
  match ok:
    case True{}: Edges{cu0 <> cu1 <> us,cv0 <> cv1 <> vs}
    case False{}: Edges{us,vs}

def face.edges.box(f: Face, +b: Recipe.Box, us: List<&2,F32>, vs: List<&2,F32>) -> Edges:
  Face{+axis,positive,plane,+u0,+u1,+v0,+v1} = f
  +u = ((axis + 1) % 3 : U32)
  +v = ((axis + 2) % 3 : U32)
  +cu0 = R.max(u0,low(b,u))
  +cu1 = R.min(u1,high(b,u))
  +cv0 = R.max(v0,low(b,v))
  +cv1 = R.min(v1,high(b,v))
  face.edges.choose(
    F32.is_eq(plane,R.pick(positive,low(b,axis),high(b,axis))) && ((cu0 < cu1) && (cv0 < cv1) : F32),
    cu0,cu1,cv0,cv1,us,vs)

def face.edges.next(result: Edges, continuation: List<&2,F32> -> List<&2,F32> -> Edges) -> Edges:
  Edges{us,vs} = result
  continuation(us,vs)

def face.edges(+f: Face, boxes: List<&2,Recipe.Box>, us: List<&2,F32>, vs: List<&2,F32>) ->
  Edges:
  match boxes:
    case Nil{}: Edges{us,vs}
    case b <> rest: face.edges.next(face.edges.box(f,b,us,vs),
      us => vs => face.edges(f,rest,us,vs))

def intervals.next(total: U32, equal: Bool) -> Result<&2,&2,String,U32>:
  match equal:
    case True{}: Done{total}
    case False{}: checked.add(total,1,"face grid")

def intervals(xs: List<&2,F32>, +previous: F32, total: U32) -> Result<&2,&2,String,U32>:
  match xs:
    case Nil{}: Done{total}
    case +x <> rest:
      do Result<&2,&2,String,U32>:
        n : U32 <- intervals.next(total,F32.is_eq(previous,x))
        intervals(rest,x,n)

def intervals.first(xs: List<&2,F32>) -> Result<&2,&2,String,U32>:
  match xs:
    case Nil{}: Done{0}
    case x <> rest: intervals(rest,x,0)

def intervals.sorted(xs: List<&2,F32>) -> Result<&2,&2,String,U32>:
  intervals.first(List.sort(~F32,~F32.is_le,xs))

def face.bound.edges(result: Edges) -> Result<&2,&2,String,U32>:
  Edges{us,vs} = result
  do Result<&2,&2,String,U32>:
    nu : U32 <- intervals.sorted(us)
    nv : U32 <- intervals.sorted(vs)
    checked.mul(nu,nv,"face grid")

def face.bound(+f: Face, boxes: List<&2,Recipe.Box>) -> Result<&2,&2,String,U32>:
  Face{_,_,_,u0,u1,v0,v1} = f
  face.bound.edges(face.edges(f,boxes,[u0,u1],[v0,v1]))

def surface.faces(fuel: Nat, +index: U32, +b: Recipe.Box, +all: List<&2,Recipe.Box>, total: U32) ->
  Result<&2,&2,String,U32>:
  match fuel:
    case 0n: Done{total}
    case 1n+p:
      do Result<&2,&2,String,U32>:
        n : U32 <- face.bound(face(b,(index / 2 : U32),U32.is_ne((index % 2 : U32),0)),all)
        total : U32 <- checked.add(total,n,"surface bound")
        surface.faces(p,(index + 1 : U32),b,all,total)

def surface.boxes(xs: List<&2,Recipe.Box>, +all: List<&2,Recipe.Box>, total: U32) -> Result<&2,&2,String,U32>:
  match xs:
    case Nil{}: Done{total}
    case b <> rest:
      do Result<&2,&2,String,U32>:
        total : U32 <- surface.faces(6n,0,b,all,total)
        surface.boxes(rest,all,total)

def owner(+boxes: List<&2,Recipe.Box>, +index: U32) -> Result<&2,&2,String,U32>:
  +prefix = "owner-index:" ++ U32.show(index) ++ ": "
  do Result<&2,&2,String,U32>:
    _ : Unit <- require(Unit,connected(boxes),prefix ++ "not positive-face connected",Unit{})
    _ : Unit <- require(Unit,anchor(boxes),prefix ++ "missing protected anchor",Unit{})
    +n : U32 <- checked.count(Recipe.Box,boxes,0,"tree nodes")
    _ : U32 <- checked.add(n,(n - 1 : U32),"tree nodes")
    +bound : U32 <- surface.boxes(boxes,boxes,0)
    vertices : U32 <- checked.mul(bound,6,"generated vertices")
    _ : U32 <- checked.mul(vertices,64,"potential geometry bytes")
    return bound

def overlaps(+a: Recipe.Box, +b: Recipe.Box) -> Bool:
  interval(a,b,0) && interval(a,b,1) && interval(a,b,2)

def overlaps.any(+a: Recipe.Box, xs: List<&2,Recipe.Box>) -> Bool:
  match xs:
    case Nil{}: False{}
    case b <> rest: overlaps(a,b) || overlaps.any(a,rest)

def disjoint(xs: List<&2,Recipe.Box>) -> Bool:
  match xs:
    case Nil{}: True{}
    case +a <> +rest: Bool.not(overlaps.any(a,rest)) && disjoint(rest)

def sum(xs: List<&2,U32>, total: U32) -> Result<&2,&2,String,U32>:
  match xs:
    case Nil{}: Done{total}
    case n <> rest:
      do Result<&2,&2,String,U32>:
        total : U32 <- checked.add(total,n,"world surface bound")
        sum(rest,total)

def owners.next(index: U32, all: List<&2,Recipe.Box>, bounds: List<&2,U32>, result: BoxBatch,
    continuation: U32 -> List<&2,Recipe.Box> -> List<&2,U32> -> Result<&2,&2,String,Bounds>) ->
  Result<&2,&2,String,Bounds>:
  BoxBatch{+source,total} = result
  do Result<&2,&2,String,Bounds>:
    bound : U32 <- owner(source,index)
    continuation(total,List.append(&2,Recipe.Box,source,all),bound <> bounds)

def owners(xs: List<&2,ExactOwner>, +extent: Extent, +index: U32, total: U32,
    all: List<&2,Recipe.Box>, bounds: List<&2,U32>) -> Result<&2,&2,String,Bounds>:
  match xs:
    case Nil{}:
      do Result<&2,&2,String,Bounds>:
        _ : Unit <- require(Unit,disjoint(all),"overlapping source ownership",Unit{})
        +bounds : List<&2,U32> = List.reverse(&2,U32,bounds)
        n : U32 <- sum(bounds,0)
        +vertices : U32 <- checked.mul(n,6,"world geometry byte bound")
        bytes : U32 <- checked.mul(vertices,64,"world geometry byte bound")
        return Bounds{total,bounds,vertices,bytes}
    case ExactOwner{source} <> rest:
      do Result<&2,&2,String,Bounds>:
        result : BoxBatch <- boxes(source,extent,total)
        owners.next(index,all,bounds,result,
          total => all => bounds => owners(rest,extent,(index + 1 : U32),total,all,bounds))

def admit(+source: List<&2,ExactOwner>, extent: Extent, budget: Integer) -> Result<&2,&2,String,Bounds>:
  do Result<&2,&2,String,Bounds>:
    _ : U32 <- checked.integer(budget,"fragment budget")
    _ : U32 <- checked.count(ExactOwner,source,1,"next ownership ID")
    owners(source,extent,0,0,Nil{},Nil{})
