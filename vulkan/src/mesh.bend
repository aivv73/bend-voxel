import Base
import ./exterior.bend as E
import ../../voxel.bend as X
import ../../material.bend as M
import ../../render.bend as R
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W

type Extent is Data:
  Extent{low: X.Cell, high: X.Cell}
type PackedSize is Data:
  PackedSize{quads: U32, vertices: U32, indices: U32, vertex_words: U32, index_words: U32, vertex_bytes: W.U64, index_bytes: W.U64, vertex_capacity: U32, index_capacity: U32, vertex_depth: Nat, index_depth: Nat}
type Mesh is Type:
  Mesh{faces: List<&2,X.Face>, size: PackedSize, bounds: Maybe<&2,Extent>, vertices: Array<U32>, indices: Array<U32>}

def capacity(fuel: Nat, +n: U32, +size: U32, +depth: Nat) -> U32 & Nat:
  match fuel:
    case 0n: (size,depth)
    case 1n+rest:
      +grow = (size < n : U32)
      capacity(rest,n,Bool.pick(U32,grow,(size * 2 : U32),size),Bool.pick(Nat,grow,1n+depth,depth))

def word_bytes(+words: U32) -> W.U64:
  W.U64{(words << 2n : U32),(words >> 30n : U32)}

def sized(+q: U32, vc: U32 & Nat, ic: U32 & Nat) -> PackedSize:
  (vsize,vd) = vc
  (isize,id) = ic
  PackedSize{q,(q * 4 : U32),(q * 6 : U32),(q * 40 : U32),(q * 6 : U32),word_bytes((q * 40 : U32)),word_bytes((q * 6 : U32)),vsize,isize,vd,id}

def size(+q: U32) -> Result<&2,&2,E.Error,PackedSize>:
  do Result<&2,&2,E.Error,PackedSize>:
    ok : Unit <- Bool.pick(Result<&2,&2,E.Error,Unit>,(q <= E.quad_limit() : U32),Done{Unit{}},Fail{E.GeometryTooLarge{}})
    return sized(q,capacity(30n,(q * 40 : U32),1,0n),capacity(30n,(q * 6 : U32),1,0n))

def face_valid(cell: X.Cell, d: X.Direction, +m: U32, +w: U32, +h: U32) -> Bool:
  X.Cell{+x,+y,+z} = cell
  +limit = E.coordinate_limit()
  +di = E.direction(d)
  +u = Bool.pick(U32,(di < 2 : U32),y,x)
  +v = Bool.pick(U32,(di < 4 : U32),z,y)
  U32.is_ne(m,0) && (x < limit : U32) && (y < limit : U32) && (z < limit : U32) && (w > 0 : U32) && (h > 0 : U32) && (w <= limit - u : U32) && (h <= limit - v : U32)

def faces_valid(fs: List<&2,X.Face>) -> Result<&2,&2,E.Error,Unit>:
  match fs:
    case Nil{}: Done{Unit{}}
    case X.Face{cell,d,m} <> rest:
      do Result<&2,&2,E.Error,Unit>:
        ok : Unit <- Bool.pick(Result<&2,&2,E.Error,Unit>,face_valid(cell,d,m,1,1),Done{Unit{}},Fail{E.InvalidFace{}})
        faces_valid(rest)
    case X.Rectangle{cell,d,m,w,h} <> rest:
      do Result<&2,&2,E.Error,Unit>:
        ok : Unit <- Bool.pick(Result<&2,&2,E.Error,Unit>,face_valid(cell,d,m,w,h),Done{Unit{}},Fail{E.InvalidFace{}})
        faces_valid(rest)

def rgbd(+rgb: U32, d: U32) -> U32:
  ((rgb >> 16n) .|. ((rgb >> 8n .&. 255) << 8n) .|. ((rgb .&. 255) << 16n) .|. (d << 24n) : U32)

def corner_axes(d: U32, +a: U32, +b: U32, +w: U32, +h: U32) -> X.Cell:
  match d:
    case 0: X.Cell{0,(b * w : U32),(a * h : U32)}
    case 1: X.Cell{1,(a * w : U32),(b * h : U32)}
    case 2: X.Cell{(a * w : U32),0,(b * h : U32)}
    case 3: X.Cell{(b * w : U32),1,(a * h : U32)}
    case 4: X.Cell{(b * w : U32),(a * h : U32),0}
    case _: X.Cell{(a * w : U32),(b * h : U32),1}

def corner(d: U32, +i: U32, w: U32, h: U32) -> X.Cell:
  corner_axes(d,Bool.pick(U32,U32.is_eq(i,1) || U32.is_eq(i,2),1,0),Bool.pick(U32,(i >= 2 : U32),1,0),w,h)

def vertex_at(cell: X.Cell, delta: X.Cell, metadata: U32, material: U32, width: U32, height: U32, +offset: U32, words: Array<U32>) -> Array<U32>:
  X.Cell{+x,+y,+z} = cell
  X.Cell{dx,dy,dz} = delta
  words[offset] <- F32.bits(U32.to_f32((x + dx : U32)))
  words[(offset + 1 : U32)] <- F32.bits(U32.to_f32((y + dy : U32)))
  words[(offset + 2 : U32)] <- F32.bits(U32.to_f32((z + dz : U32)))
  words[(offset + 3 : U32)] <- metadata
  words[(offset + 4 : U32)] <- material
  words[(offset + 5 : U32)] <- F32.bits(U32.to_f32(x))
  words[(offset + 6 : U32)] <- F32.bits(U32.to_f32(y))
  words[(offset + 7 : U32)] <- F32.bits(U32.to_f32(z))
  words[(offset + 8 : U32)] <- F32.bits(U32.to_f32(width))
  words[(offset + 9 : U32)] <- F32.bits(U32.to_f32(height))
  words

def vertex(+cell: X.Cell, +d: U32, i: U32, metadata: U32, material: U32, +w: U32, +h: U32, offset: U32, words: Array<U32>) -> Array<U32>:
  vertex_at(cell,corner(d,i,w,h),metadata,material,w,h,offset,words)

def quad(+cell: X.Cell, +d: U32, +metadata: U32, +material: U32, +w: U32, +h: U32, +base: U32, words: Array<U32>) -> Array<U32>:
  words = vertex(cell,d,0,metadata,material,w,h,base,words)
  words = vertex(cell,d,1,metadata,material,w,h,(base + 10 : U32),words)
  words = vertex(cell,d,2,metadata,material,w,h,(base + 20 : U32),words)
  vertex(cell,d,3,metadata,material,w,h,(base + 30 : U32),words)

def index_quad(+base: U32, +offset: U32, words: Array<U32>) -> Array<U32>:
  words[offset] <- base
  words[(offset + 1 : U32)] <- (base + 1 : U32)
  words[(offset + 2 : U32)] <- (base + 2 : U32)
  words[(offset + 3 : U32)] <- (base + 2 : U32)
  words[(offset + 4 : U32)] <- (base + 3 : U32)
  words[(offset + 5 : U32)] <- base
  words

def vertices(faces: List<&2,X.Face>, +palette: M.Palette, +base: U32, words: Array<U32>) -> Array<U32>:
  match faces:
    case Nil{}: words
    case X.Face{cell,+d,+material} <> rest:
      vertices(rest,palette,(base + 40 : U32),quad(cell,E.direction(d),rgbd(M.Palette.surface(palette,material,R.Face.light(d)),E.direction(d)),material,1,1,base,words))
    case X.Rectangle{cell,+d,+material,w,h} <> rest:
      vertices(rest,palette,(base + 40 : U32),quad(cell,E.direction(d),rgbd(M.Palette.surface(palette,material,R.Face.light(d)),E.direction(d)),material,w,h,base,words))

def indices(faces: List<&2,X.Face>, +base: U32, +offset: U32, words: Array<U32>) -> Array<U32>:
  match faces:
    case Nil{}: words
    case face <> rest: indices(rest,(base + 4 : U32),(offset + 6 : U32),index_quad(base,offset,words))

def extent(p: E.Patch) -> Extent:
  E.Patch{+n,+d,m,E.Rect2{+u0,u1,+v0,v1}} = p
  Extent{E.face_cell(n,d,u0,v0),E.face_cell((n + 1 : U32),d,u1,v1)}

def union(a: Extent, b: Extent) -> Extent:
  Extent{X.Cell{x,y,z},X.Cell{hx,hy,hz}} = a
  Extent{X.Cell{u,v,w},X.Cell{hu,hv,hw}} = b
  Extent{X.Cell{U32.min(x,u),U32.min(y,v),U32.min(z,w)},X.Cell{U32.max(hx,hu),U32.max(hy,hv),U32.max(hz,hw)}}

def extend(a: Maybe<&2,Extent>, b: Extent) -> Maybe<&2,Extent>:
  match a:
    case None{}: Some{b}
    case Some{old}: Some{union(old,b)}

def bounds(faces: List<&2,X.Face>, current: Maybe<&2,Extent>) -> Maybe<&2,Extent>:
  match faces:
    case Nil{}: current
    case f <> rest: bounds(rest,extend(current,extent(E.patch(f))))

def packed(+faces: List<&2,X.Face>, +s: PackedSize) -> Mesh:
  PackedSize{q,vc,ic,vw,iw,vb,ib,vs,iscap,vd,id} = s
  vertices indices = vertices(faces,M.Palette.build(),0,Array.new(U32,vd,0)) indices(faces,0,0,Array.new(U32,id,0))
  Mesh{faces,s,bounds(faces,None{}),vertices,indices}

def affine(~A: Data, result: Result<&2,&2,E.Error,A>) -> Result<&2,&1,E.Error,A>:
  match result:
    case Fail{e}: Fail{e}
    case Done{value}: Done{value}

def pack(+faces: List<&2,X.Face>) -> Result<&2,&1,E.Error,Mesh>:
  do Result<&2,&1,E.Error,Mesh>:
    ok : Unit <- affine(~Unit,faces_valid(faces))
    n : U32 <- affine(~U32,E.count(faces,0))
    s : PackedSize <- affine(~PackedSize,size(n))
    return packed(faces,s)

def dense_join(left: Array<U32> & Bool, right: Array<U32> & Bool) -> Array<U32> & Bool:
  (a,ok) = left
  (b,valid) = right
  (ANode{a,b},ok && valid)

def dense_tree(+depth: Nat, cells: Array<U32>) -> Array<U32> & Bool:
  match depth cells:
    case 0n ALeaf{m}: (ALeaf{m},True{})
    case 0n ANode{a,b}: (ANode{a,b},False{})
    case 1n+k ALeaf{m}: (ALeaf{m},False{})
    case 1n+k ANode{a,b}: dense_join(dense_tree(k,a),dense_tree(k,b))

def finish(body: X.Body, surface: X.Surface) -> X.Body & Result<&2,&1,E.Error,Mesh>:
  X.Surface{faces} = surface
  (body,pack(faces))

def dense_built(pair: X.Body & X.Surface) -> X.Body & Result<&2,&1,E.Error,Mesh>:
  (body,surface) = pair
  finish(body,surface)

def dense_checked(side: U32, pair: Array<U32> & Bool) -> X.Body & Result<&2,&1,E.Error,Mesh>:
  (cells,ok) = pair
  match ok:
    case False{}: (X.Body{side,cells},Fail{E.InvalidDense{}})
    case True{}: dense_built(X.Surface.build(X.Body{side,cells}))

def dense(valid: Bool, +side: U32, cells: Array<U32>) -> X.Body & Result<&2,&1,E.Error,Mesh>:
  match valid:
    case False{}: (X.Body{side,cells},Fail{E.InvalidDense{}})
    case True{}: dense_checked(side,dense_tree(Nat.mul(3n,U32.log2(side)),cells))

def boxes_result(+boxes: List<&2,X.Cuboid>, result: Result<&2,&2,E.Error,List<&2,X.Face>>) -> X.Body & Result<&2,&1,E.Error,Mesh>:
  match result:
    case Fail{error}: (X.Cuboids{boxes},Fail{error})
    case Done{faces}: (X.Cuboids{boxes},pack(faces))

def build(body: X.Body) -> X.Body & Result<&2,&1,E.Error,Mesh>:
  match body:
    case X.Body{+side,cells}: dense((side > 0 : U32) && (side <= 1024 : U32) && U32.is_eq((side .&. (side - 1) : U32),0),side,cells)
    case X.Cuboids{+boxes}: boxes_result(boxes,E.exterior(boxes))

def material_read(pair: Array<U32> & U32) -> U32:
  (words,value) = pair
  value

def material_word(words: Array<U32>) -> U32:
  material_read(Array.get(U32,words,4))
