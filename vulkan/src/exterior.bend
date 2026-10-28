import Base
import ../../voxel.bend as X

type Error is Data:
  InvalidBox{index: U32}
  CoordinateLimit{index: U32}
  OverlappingBoxes{first: U32, second: U32}
  InvalidDense{}
  InvalidFace{}
  GeometryTooLarge{}

type Rect2 is Data:
  Rect2{u0: U32, u1: U32, v0: U32, v1: U32}
type Patch is Data:
  Patch{normal: U32, direction: X.Direction, material: U32, rect: Rect2}

def coordinate_limit() -> U32:
  1048576

def quad_limit() -> U32:
  26843545

def direction(d: X.Direction) -> U32:
  match d:
    case X.NegX{}: 0
    case X.PosX{}: 1
    case X.NegY{}: 2
    case X.PosY{}: 3
    case X.NegZ{}: 4
    case X.PosZ{}: 5

def append(xs: List<&2,X.Face>, ys: List<&2,X.Face>) -> List<&2,X.Face>:
  match xs:
    case Nil{}: ys
    case x <> rest: x <> append(rest,ys)

def rect_append(xs: List<&2,Rect2>, ys: List<&2,Rect2>) -> List<&2,Rect2>:
  match xs:
    case Nil{}: ys
    case x <> rest: x <> rect_append(rest,ys)

def positive(+r: Rect2, +tail: List<&2,Rect2>) -> List<&2,Rect2>:
  Rect2{u0,u1,v0,v1} = r
  Bool.pick(List<&2,Rect2>,(u0 < u1 : U32) && (v0 < v1 : U32),r <> tail,tail)

def difference(intersects: Bool, +r: Rect2, intersection: Rect2) -> List<&2,Rect2>:
  match intersects:
    case False{}: [r]
    case True{}:
      Rect2{+u0,+u1,+v0,+v1} = r
      Rect2{+a,+b,+c,+d} = intersection
      positive(Rect2{u0,a,v0,v1},positive(Rect2{b,u1,v0,v1},positive(Rect2{a,b,v0,c},positive(Rect2{a,b,d,v1},Nil{}))))

def subtract(+r: Rect2, blocker: Rect2) -> List<&2,Rect2>:
  Rect2{+u0,+u1,+v0,+v1} = r
  Rect2{a,b,c,d} = blocker
  +lo = U32.max(u0,a)
  +hi = U32.min(u1,b)
  +bottom = U32.max(v0,c)
  +top = U32.min(v1,d)
  difference((lo < hi : U32) && (bottom < top : U32),r,Rect2{lo,hi,bottom,top})

def subtract_all(rectangles: List<&2,Rect2>, +blocker: Rect2) -> List<&2,Rect2>:
  match rectangles:
    case Nil{}: Nil{}
    case r <> rest: rect_append(subtract(r,blocker),subtract_all(rest,blocker))

def box_valid(box: X.Cuboid) -> Bool:
  X.Cuboid{X.Cell{x,y,z},X.Cell{hx,hy,hz},m} = box
  (x < hx : U32) && (y < hy : U32) && (z < hz : U32)

def box_bounded(box: X.Cuboid) -> Bool:
  X.Cuboid{X.Cell{x,y,z},X.Cell{hx,hy,hz},m} = box
  (x <= coordinate_limit() : U32) && (y <= coordinate_limit() : U32) && (z <= coordinate_limit() : U32) && (hx <= coordinate_limit() : U32) && (hy <= coordinate_limit() : U32) && (hz <= coordinate_limit() : U32)

def overlaps(a: X.Cuboid, b: X.Cuboid) -> Bool:
  X.Cuboid{X.Cell{+x,+y,+z},X.Cell{+hx,+hy,+hz},ma} = a
  X.Cuboid{X.Cell{+u,+v,+w},X.Cell{+hu,+hv,+hw},mb} = b
  U32.is_ne(ma,0) && U32.is_ne(mb,0) && (x < hu : U32) && (u < hx : U32) && (y < hv : U32) && (v < hy : U32) && (z < hw : U32) && (w < hz : U32)

def no_overlap(xs: List<&2,X.Cuboid>, +box: X.Cuboid, +i: U32, +j: U32) -> Result<&2,&2,Error,Unit>:
  match xs:
    case Nil{}: Done{Unit{}}
    case head <> rest:
      do Result<&2,&2,Error,Unit>:
        ok : Unit <- Bool.pick(Result<&2,&2,Error,Unit>,overlaps(box,head),Fail{OverlappingBoxes{i,j}},Done{Unit{}})
        no_overlap(rest,box,i,(j + 1 : U32))

def validate(xs: List<&2,X.Cuboid>, +i: U32) -> Result<&2,&2,Error,Unit>:
  match xs:
    case Nil{}: Done{Unit{}}
    case +box <> +rest:
      do Result<&2,&2,Error,Unit>:
        valid : Unit <- Bool.pick(Result<&2,&2,Error,Unit>,box_valid(box),Done{Unit{}},Fail{InvalidBox{i}})
        bounded : Unit <- Bool.pick(Result<&2,&2,Error,Unit>,box_bounded(box),Done{Unit{}},Fail{CoordinateLimit{i}})
        disjoint : Unit <- no_overlap(rest,box,i,(i + 1 : U32))
        validate(rest,(i + 1 : U32))

def patch_cell(cell: X.Cell, d: X.Direction, m: U32, +w: U32, +h: U32) -> Patch:
  X.Cell{+x,+y,+z} = cell
  match d:
    case X.NegX{}: Patch{x,X.NegX{},m,Rect2{y,(y + w : U32),z,(z + h : U32)}}
    case X.PosX{}: Patch{x,X.PosX{},m,Rect2{y,(y + w : U32),z,(z + h : U32)}}
    case X.NegY{}: Patch{y,X.NegY{},m,Rect2{x,(x + w : U32),z,(z + h : U32)}}
    case X.PosY{}: Patch{y,X.PosY{},m,Rect2{x,(x + w : U32),z,(z + h : U32)}}
    case X.NegZ{}: Patch{z,X.NegZ{},m,Rect2{x,(x + w : U32),y,(y + h : U32)}}
    case X.PosZ{}: Patch{z,X.PosZ{},m,Rect2{x,(x + w : U32),y,(y + h : U32)}}

def patch(face: X.Face) -> Patch:
  match face:
    case X.Face{cell,d,m}: patch_cell(cell,d,m,1,1)
    case X.Rectangle{cell,d,m,w,h}: patch_cell(cell,d,m,w,h)

def face_cell(normal: U32, d: X.Direction, u: U32, v: U32) -> X.Cell:
  match d:
    case X.NegX{}: X.Cell{normal,u,v}
    case X.PosX{}: X.Cell{normal,u,v}
    case X.NegY{}: X.Cell{u,normal,v}
    case X.PosY{}: X.Cell{u,normal,v}
    case X.NegZ{}: X.Cell{u,v,normal}
    case X.PosZ{}: X.Cell{u,v,normal}

def face(normal: U32, +d: X.Direction, m: U32, r: Rect2) -> X.Face:
  Rect2{+u0,u1,+v0,v1} = r
  X.Rectangle{face_cell(normal,d,u0,v0),d,m,(u1 - u0 : U32),(v1 - v0 : U32)}

def blocker_axis(+p: U32, positive: Bool, lo: U32, hi: U32) -> Bool:
  match positive:
    case False{}: (lo < p : U32) && (p <= hi : U32)
    case True{}: (lo <= p : U32) && (p < hi : U32)

def blocker(patch: Patch, box: X.Cuboid) -> Maybe<&2,Rect2>:
  Patch{+normal,+d,m,r} = patch
  X.Cuboid{X.Cell{+x,+y,+z},X.Cell{+hx,+hy,+hz},mat} = box
  +di = direction(d)
  +p = (normal + di % 2 : U32)
  +positive = U32.is_ne((di % 2 : U32),0)
  +low = Bool.pick(U32,(di < 2 : U32),x,Bool.pick(U32,(di < 4 : U32),y,z))
  +high = Bool.pick(U32,(di < 2 : U32),hx,Bool.pick(U32,(di < 4 : U32),hy,hz))
  +rect = Bool.pick(Rect2,(di < 2 : U32),Rect2{y,hy,z,hz},Bool.pick(Rect2,(di < 4 : U32),Rect2{x,hx,z,hz},Rect2{x,hx,y,hy}))
  Bool.pick(Maybe<&2,Rect2>,U32.is_ne(mat,0) && blocker_axis(p,positive,low,high),Some{rect},None{})

def clipped(block: Maybe<&2,Rect2>, rectangles: List<&2,Rect2>) -> List<&2,Rect2>:
  match block:
    case None{}: rectangles
    case Some{r}: subtract_all(rectangles,r)

def count(xs: List<&2,X.Face>, +n: U32) -> Result<&2,&2,Error,U32>:
  match xs:
    case Nil{}: Done{n}
    case head <> rest:
      do Result<&2,&2,Error,U32>:
        ok : Unit <- Bool.pick(Result<&2,&2,Error,Unit>,(n < quad_limit() : U32),Done{Unit{}},Fail{GeometryTooLarge{}})
        count(rest,(n + 1 : U32))

def rect_count(xs: List<&2,Rect2>, +n: U32) -> Result<&2,&2,Error,Unit>:
  match xs:
    case Nil{}: Done{Unit{}}
    case head <> rest:
      do Result<&2,&2,Error,Unit>:
        ok : Unit <- Bool.pick(Result<&2,&2,Error,Unit>,(n < quad_limit() : U32),Done{Unit{}},Fail{GeometryTooLarge{}})
        rect_count(rest,(n + 1 : U32))

def clip(boxes: List<&2,X.Cuboid>, +p: Patch, +rectangles: List<&2,Rect2>) -> Result<&2,&2,Error,List<&2,Rect2>>:
  match boxes:
    case Nil{}: Done{rectangles}
    case box <> rest:
      +next = clipped(blocker(p,box),rectangles)
      do Result<&2,&2,Error,List<&2,Rect2>>:
        ok : Unit <- rect_count(next,0)
        clip(rest,p,next)

def lift(rectangles: List<&2,Rect2>, +p: Patch) -> List<&2,X.Face>:
  match rectangles:
    case Nil{}: Nil{}
    case r <> rest:
      Patch{normal,d,m,old} = p
      face(normal,d,m,r) <> lift(rest,p)

def one(+p: Patch, boxes: List<&2,X.Cuboid>) -> Result<&2,&2,Error,List<&2,X.Face>>:
  Patch{normal,d,m,r} = p
  do Result<&2,&2,Error,List<&2,X.Face>>:
    rectangles : List<&2,Rect2> <- clip(boxes,p,[r])
    return lift(rectangles,p)

def join(a: Result<&2,&2,Error,List<&2,X.Face>>, b: Result<&2,&2,Error,List<&2,X.Face>>) -> Result<&2,&2,Error,List<&2,X.Face>>:
  do Result<&2,&2,Error,List<&2,X.Face>>:
    +left : List<&2,X.Face> <- a
    right : List<&2,X.Face> <- b
    +joined : List<&2,X.Face> = append(left,right)
    n : U32 <- count(joined,0)
    return joined

def parallel_two(+boxes: List<&2,X.Cuboid>, a: X.Face, b: X.Face) -> Result<&2,&2,Error,List<&2,X.Face>>:
  left right = one(patch(a),boxes) one(patch(b),boxes)
  join(left,right)

def parallel_four(+boxes: List<&2,X.Cuboid>, a: X.Face, b: X.Face, c: X.Face, d: X.Face) -> Result<&2,&2,Error,List<&2,X.Face>>:
  left right = parallel_two(boxes,a,b) parallel_two(boxes,c,d)
  join(left,right)

def parallel_six(faces: List<&2,X.Face>, +boxes: List<&2,X.Cuboid>) -> Result<&2,&2,Error,List<&2,X.Face>>:
  match faces:
    case a <> b <> c <> d <> e <> f <> Nil{}:
      abcd ef = parallel_four(boxes,a,b,c,d) parallel_two(boxes,e,f)
      join(abcd,ef)
    case _: Fail{InvalidFace{}}

def extract(xs: List<&2,X.Cuboid>, +boxes: List<&2,X.Cuboid>) -> Result<&2,&2,Error,List<&2,X.Face>>:
  match xs:
    case Nil{}: Done{Nil{}}
    case X.Cuboid{lo,hi,0} <> rest: extract(rest,boxes)
    case box <> rest: join(parallel_six(X.Cuboid.surface(box,Nil{}),boxes),extract(rest,boxes))

def source_count(xs: List<&2,X.Cuboid>, +n: U32) -> Result<&2,&2,Error,Unit>:
  match xs:
    case Nil{}: Done{Unit{}}
    case head <> rest:
      do Result<&2,&2,Error,Unit>:
        ok : Unit <- Bool.pick(Result<&2,&2,Error,Unit>,(n < quad_limit() : U32),Done{Unit{}},Fail{GeometryTooLarge{}})
        source_count(rest,(n + 1 : U32))

def exterior(+boxes: List<&2,X.Cuboid>) -> Result<&2,&2,Error,List<&2,X.Face>>:
  do Result<&2,&2,Error,List<&2,X.Face>>:
    bounded : Unit <- source_count(boxes,0)
    ok : Unit <- validate(boxes,0)
    extract(boxes,boxes)

def error_show(e: Error) -> String:
  match e:
    case InvalidBox{i}: "invalid nonempty cuboid bounds at source " ++ U32.show(i)
    case CoordinateLimit{i}: "cuboid coordinates exceed 2^20 at source " ++ U32.show(i)
    case OverlappingBoxes{i,j}: "overlapping nonair cuboids at sources " ++ U32.show(i) ++ " and " ++ U32.show(j)
    case InvalidDense{}: "dense body must be a balanced side^3 array with a positive power-of-two side <= 1024"
    case InvalidFace{}: "invalid face material, extent or coordinate bounds"
    case GeometryTooLarge{}: "geometry exceeds checked logical count or 2^30-word array capacity"
