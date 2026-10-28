import Base
import ./exterior.bend as E
import ./mesh.bend as M
import ./greedy.bend as G
import ../../voxel.bend as X

type ChunkKey is Data:
  ChunkKey{x: U32, y: U32, z: U32, edge: U32}
type Domain is Data:
  Domain{source: X.Cuboid, first: U32, faces: List<&2,X.Face>}
type Halo is Data:
  Halo{low: X.Cell, edge: U32, capacity: U32, cells: X.Snapshot}
type Source is Data:
  Dense{halo: Halo}
  Cuboids{sources: List<&2,X.Cuboid>, blockers: List<&2,X.Cuboid>}
type Input is Data:
  Input{key: ChunkKey, source: Source}
type Chunk is Type:
  Chunk{key: ChunkKey, version: U32, domains: List<&2,Domain>, color: M.Mesh, shadow: M.Mesh}
type ChunkSet is Type:
  ChunkSet{chunks: List<Chunk>, primitives: List<&2,Primitive>, faces: List<&2,X.Face>, bounds: Maybe<&2,M.Extent>, quads: U32, shadow_quads: U32, rebuilt: U32, retained: U32}
type Primitive is Data:
  Primitive{key: ChunkKey, first: U32, face: X.Face}
type Run is Data:
  Run{key: ChunkKey, first: U32, count: U32}

def key_equal(a: ChunkKey, b: ChunkKey) -> Bool:
  ChunkKey{x,y,z,e} = a
  ChunkKey{u,v,w,f} = b
  U32.is_eq(x,u) && U32.is_eq(y,v) && U32.is_eq(z,w) && U32.is_eq(e,f)

def cell_equal(a: X.Cell, b: X.Cell) -> Bool:
  X.Cell{x,y,z} = a
  X.Cell{u,v,w} = b
  U32.is_eq(x,u) && U32.is_eq(y,v) && U32.is_eq(z,w)

def box_equal(a: X.Cuboid, b: X.Cuboid) -> Bool:
  X.Cuboid{lo,hi,m} = a
  X.Cuboid{low,high,n} = b
  cell_equal(lo,low) && cell_equal(hi,high) && U32.is_eq(m,n)

def boxes_equal(a: List<&2,X.Cuboid>, b: List<&2,X.Cuboid>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Con{x,xs} Con{y,ys}: box_equal(x,y) && boxes_equal(xs,ys)
    case _ _: False{}

def face_equal(a: X.Face, b: X.Face) -> Bool:
  match a b:
    case X.Face{c,d,m} X.Face{k,f,n}: cell_equal(c,k) && U32.is_eq(E.direction(d),E.direction(f)) && U32.is_eq(m,n)
    case X.Rectangle{c,d,m,w,h} X.Rectangle{k,f,n,u,v}: cell_equal(c,k) && U32.is_eq(E.direction(d),E.direction(f)) && U32.is_eq(m,n) && U32.is_eq(w,u) && U32.is_eq(h,v)
    case _ _: False{}

def faces_equal(a: List<&2,X.Face>, b: List<&2,X.Face>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Con{x,xs} Con{y,ys}: face_equal(x,y) && faces_equal(xs,ys)
    case _ _: False{}

def region(+edge: U32, cell: X.Cell) -> ChunkKey:
  X.Cell{x,y,z} = cell
  ChunkKey{(x / edge * edge : U32),(y / edge * edge : U32),(z / edge * edge : U32),edge}

def choose_region(fits: Bool, key: ChunkKey, next: Unit -> ChunkKey) -> ChunkKey:
  match fits:
    case True{}: key
    case False{}: next(Unit{})

def enclosing(fuel: Nat, +low: X.Cell, +high: X.Cell, +edge: U32) -> ChunkKey:
  match fuel:
    case 0n: region(edge,low)
    case 1n+rest:
      X.Cell{x,y,z} = high
      +fits = key_equal(region(edge,low),region(edge,X.Cell{(x - 1 : U32),(y - 1 : U32),(z - 1 : U32)}))
      choose_region(fits,region(edge,low),unit => enclosing(rest,low,high,(edge * 2 : U32)))

def sampled(pair: Array<U32> & U32) -> Array<U32> & X.Snapshot:
  (cells,material) = pair
  (cells,X.Leaf{material})

def sample(inside: Bool, cells: Array<U32>, index: U32) -> Array<U32> & X.Snapshot:
  match inside:
    case False{}: (cells,X.Leaf{0})
    case True{}: sampled(Array.get(U32,cells,index))

def gather_leaf(+side: U32, low: X.Cell, +edge: U32, +at: U32, cells: Array<U32>) -> Array<U32> & X.Snapshot:
  X.Cell{x,y,z} = low
  +cell : X.Cell = X.Cell{(x + at % edge - 1 : U32),(y + at / edge % edge - 1 : U32),(z + at / (edge * edge) - 1 : U32)}
  sample((at < edge * edge * edge : U32) && X.Cell.inside(side,cell),cells,X.Body.index(side,cell))

def gather_join(left: X.Snapshot, pair: Array<U32> & X.Snapshot) -> Array<U32> & X.Snapshot:
  (cells,right) = pair
  (cells,X.Node{left,right})

def gather_right(pair: Array<U32> & X.Snapshot, next: Array<U32> -> Array<U32> & X.Snapshot) -> Array<U32> & X.Snapshot:
  (cells,left) = pair
  gather_join(left,next(cells))

def gather(+depth: Nat, +side: U32, +low: X.Cell, +edge: U32, +at: U32, cells: Array<U32>) -> Array<U32> & X.Snapshot:
  match depth:
    case 0n: gather_leaf(side,low,edge,at,cells)
    case 1n+rest:
      gather_right(gather(rest,side,low,edge,at,cells),array => gather(rest,side,low,edge,(at + (1 << rest) : U32),array))

def gathered(key: ChunkKey, low: X.Cell, edge: U32, capacity: U32, pair: Array<U32> & X.Snapshot) -> Array<U32> & Input:
  (cells,snapshot) = pair
  (cells,Input{key,Dense{Halo{low,edge,capacity,snapshot}}})

def gather_capacity(+side: U32, +key: ChunkKey, cells: Array<U32>, size: U32 & Nat) -> Array<U32> & Input:
  ChunkKey{x,y,z,+span} = key
  (capacity,depth) = size
  +low : X.Cell = X.Cell{x,y,z}
  +edge = (span + 2 : U32)
  gathered(key,low,edge,capacity,gather(depth,side,low,edge,0,cells))

def gather_input(+side: U32, +key: ChunkKey, cells: Array<U32>) -> Array<U32> & Input:
  ChunkKey{x,y,z,+span} = key
  +edge = (span + 2 : U32)
  gather_capacity(side,key,cells,M.capacity(30n,(edge * edge * edge : U32),1,0n))

def halo_read(halo: Halo, cell: X.Cell) -> U32:
  Halo{X.Cell{x,y,z},+edge,+capacity,cells} = halo
  X.Cell{u,v,w} = cell
  +index = ((u - x + 1) + (v - y + 1) * edge + (w - z + 1) * edge * edge : U32)
  X.Snapshot.get(cells,index,capacity,(index < capacity / 2 : U32))

def dense_cell(material: U32, +halo: Halo, +cell: X.Cell, faces: List<&2,X.Face>) -> List<&2,X.Face>:
  match material:
    case 0: faces
    case +m:
      X.Cell{+x,+y,+z} = cell
      faces = X.Face.add(U32.is_zero(halo_read(halo,X.Cell{(x - 1 : U32),y,z})),X.Face{cell,X.NegX{},m},faces)
      faces = X.Face.add(U32.is_zero(halo_read(halo,X.Cell{(x + 1 : U32),y,z})),X.Face{cell,X.PosX{},m},faces)
      faces = X.Face.add(U32.is_zero(halo_read(halo,X.Cell{x,(y - 1 : U32),z})),X.Face{cell,X.NegY{},m},faces)
      faces = X.Face.add(U32.is_zero(halo_read(halo,X.Cell{x,(y + 1 : U32),z})),X.Face{cell,X.PosY{},m},faces)
      faces = X.Face.add(U32.is_zero(halo_read(halo,X.Cell{x,y,(z - 1 : U32)})),X.Face{cell,X.NegZ{},m},faces)
      X.Face.add(U32.is_zero(halo_read(halo,X.Cell{x,y,(z + 1 : U32)})),X.Face{cell,X.PosZ{},m},faces)

def dense_scan(fuel: Nat, +low: X.Cell, +span: U32, +halo: Halo, +at: U32, faces: List<&2,X.Face>) -> List<&2,X.Face>:
  match fuel:
    case 0n: faces
    case 1n+rest:
      X.Cell{x,y,z} = low
      +cell : X.Cell = X.Cell{(x + at % span : U32),(y + at / span % span : U32),(z + at / (span * span) : U32)}
      dense_scan(rest,low,span,halo,(at + 1 : U32),dense_cell(halo_read(halo,cell),halo,cell,faces))

def source_key(box: X.Cuboid) -> ChunkKey:
  X.Cuboid{low,high,material} = box
  enclosing(16n,low,high,32)

def box_append(xs: List<&2,X.Cuboid>, ys: List<&2,X.Cuboid>) -> List<&2,X.Cuboid>:
  match xs:
    case Nil{}: ys
    case head <> rest: head <> box_append(rest,ys)

def add_source(equal: Bool, head: Input, tail: List<&2,Input>, +box: X.Cuboid, +blockers: List<&2,X.Cuboid>, next: Unit -> List<&2,Input>) -> List<&2,Input>:
  match equal head:
    case True{} Input{key,Cuboids{sources,old}}: Input{key,Cuboids{box_append(sources,[box]),blockers}} <> tail
    case _ _: head <> next(Unit{})

def group(xs: List<&2,Input>, +box: X.Cuboid, +blockers: List<&2,X.Cuboid>, +key: ChunkKey) -> List<&2,Input>:
  match xs:
    case Nil{}: [Input{key,Cuboids{[box],blockers}}]
    case +head <> +rest:
      Input{+old,source} = head
      add_source(key_equal(old,key),head,rest,box,blockers,unit => group(rest,box,blockers,key))

def cuboid_inputs(xs: List<&2,X.Cuboid>, +all: List<&2,X.Cuboid>, inputs: List<&2,Input>) -> List<&2,Input>:
  match xs:
    case Nil{}: inputs
    case X.Cuboid{low,high,0} <> rest: cuboid_inputs(rest,all,inputs)
    case +box <> rest: cuboid_inputs(rest,all,group(inputs,box,all,source_key(box)))

def domains_faces(xs: List<&2,Domain>) -> List<&2,X.Face>:
  match xs:
    case Nil{}: Nil{}
    case Domain{box,first,faces} <> rest: E.append(faces,domains_faces(rest))

def source_domain(box: X.Cuboid, +first: U32, result: Result<&2,&2,E.Error,List<&2,X.Face>>, next: U32 -> Result<&2,&2,E.Error,List<&2,Domain>>) -> Result<&2,&2,E.Error,List<&2,Domain>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{+faces}:
      do Result<&2,&2,E.Error,List<&2,Domain>>:
        count : U32 <- E.count(faces,0)
        rest : List<&2,Domain> <- next((first + count : U32))
        return Domain{box,first,faces} <> rest

def cuboid_domains(xs: List<&2,X.Cuboid>, +blockers: List<&2,X.Cuboid>, +first: U32) -> Result<&2,&2,E.Error,List<&2,Domain>>:
  match xs:
    case Nil{}: Done{Nil{}}
    case +box <> rest: source_domain(box,first,E.parallel_six(X.Cuboid.surface(box,Nil{}),blockers),at => cuboid_domains(rest,blockers,at))

def packed_shadow(key: ChunkKey, version: U32, domains: List<&2,Domain>, color: M.Mesh, shadow: Result<&2,&1,E.Error,M.Mesh>) -> Result<&2,&1,E.Error,Chunk>:
  match shadow:
    case Fail{error}: Fail{error}
    case Done{mesh}: Done{Chunk{key,version,domains,color,mesh}}

def packed_color(key: ChunkKey, version: U32, domains: List<&2,Domain>, faces: List<&2,X.Face>, color: Result<&2,&1,E.Error,M.Mesh>) -> Result<&2,&1,E.Error,Chunk>:
  match color:
    case Fail{error}: Fail{error}
    case Done{mesh}: packed_shadow(key,version,domains,mesh,M.pack(G.merge_faces(faces)))

def pack(+key: ChunkKey, version: U32, domains: List<&2,Domain>, +faces: List<&2,X.Face>) -> Result<&2,&1,E.Error,Chunk>:
  packed_color(key,version,domains,faces,M.pack(faces))

def built_domains(key: ChunkKey, version: U32, result: Result<&2,&2,E.Error,List<&2,Domain>>) -> Result<&2,&1,E.Error,Chunk>:
  match result:
    case Fail{error}: Fail{error}
    case Done{+domains}: pack(key,version,domains,domains_faces(domains))

def build_chunk(input: Input, version: U32) -> Result<&2,&1,E.Error,Chunk>:
  match input:
    case Input{ChunkKey{+x,+y,+z,+span},Dense{halo}}:
      pack(ChunkKey{x,y,z,span},version,Nil{},dense_scan(U32.to_nat((span * span * span : U32)),X.Cell{x,y,z},span,halo,0,Nil{}))
    case Input{key,Cuboids{sources,blockers}}: built_domains(key,version,cuboid_domains(sources,blockers,0))

type Work is Type:
  Keep{chunk: Chunk}
  Rebuild{input: Input, old: Maybe<&1,Chunk>}
type Built is Type:
  Built{chunk: Maybe<&1,Chunk>, rebuilt: Bool}

def restore(chunk: Maybe<&1,Chunk>, rest: List<Chunk>) -> List<Chunk>:
  match chunk:
    case None{}: rest
    case Some{head}: head <> rest

def select_take(equal: Bool, head: Chunk, found: Maybe<&1,Chunk>, rest: List<Chunk>) -> Maybe<&1,Chunk> & List<Chunk>:
  match equal:
    case True{}: (Some{head},restore(found,rest))
    case False{}: (found,head <> rest)

def take_head(+key: ChunkKey, head: Chunk, pair: Maybe<&1,Chunk> & List<Chunk>) -> Maybe<&1,Chunk> & List<Chunk>:
  Chunk{+own,version,domains,color,shadow} = head
  (found,rest) = pair
  select_take(key_equal(key,own),Chunk{own,version,domains,color,shadow},found,rest)

def take(xs: List<Chunk>, +key: ChunkKey) -> Maybe<&1,Chunk> & List<Chunk>:
  match xs:
    case Nil{}: (None{},Nil{})
    case head <> rest: take_head(key,head,take(rest,key))

def domains_sources(xs: List<&2,Domain>) -> List<&2,X.Cuboid>:
  match xs:
    case Nil{}: Nil{}
    case Domain{box,first,faces} <> rest: box <> domains_sources(rest)

def touching(a: X.Cuboid, b: X.Cuboid) -> Bool:
  X.Cuboid{X.Cell{+x,+y,+z},X.Cell{+hx,+hy,+hz},m} = a
  X.Cuboid{X.Cell{+u,+v,+w},X.Cell{+hu,+hv,+hw},n} = b
  (x <= hu : U32) && (u <= hx : U32) && (y <= hv : U32) && (v <= hy : U32) && (z <= hw : U32) && (w <= hz : U32)

def touches(xs: List<&2,X.Cuboid>, +box: X.Cuboid) -> Bool:
  match xs:
    case Nil{}: False{}
    case head <> rest: touching(head,box) || touches(rest,box)

def affected(xs: List<&2,X.Cuboid>, +changes: List<&2,X.Cuboid>) -> Bool:
  match xs:
    case Nil{}: False{}
    case box <> rest: touches(changes,box) || affected(rest,changes)

def unchanged(source: Source, domains: List<&2,Domain>, +changes: List<&2,X.Cuboid>) -> Bool:
  match source:
    case Dense{halo}: False{}
    case Cuboids{+sources,blockers}: boxes_equal(sources,domains_sources(domains)) && Bool.not(affected(sources,changes))

def existing(keep: Bool, input: Input, old: Chunk) -> Work:
  match keep:
    case True{}: Keep{old}
    case False{}: Rebuild{input,Some{old}}

def request(+input: Input, found: Maybe<&1,Chunk>, changes: List<&2,X.Cuboid>) -> Work:
  Input{key,+source} = input
  match found:
    case None{}: Rebuild{input,None{}}
    case Some{Chunk{key,version,+domains,color,shadow}}:
      existing(unchanged(source,domains,changes),input,Chunk{key,version,domains,color,shadow})

def keep_all(xs: List<Chunk>) -> List<Work>:
  match xs:
    case Nil{}: Nil{}
    case head <> rest: Keep{head} <> keep_all(rest)

def requested(input: Input, pair: Maybe<&1,Chunk> & List<Chunk>, changes: List<&2,X.Cuboid>, next: List<Chunk> -> List<Work>) -> List<Work>:
  (found,rest) = pair
  request(input,found,changes) <> next(rest)

def requests(inputs: List<&2,Input>, old: List<Chunk>, +changes: List<&2,X.Cuboid>, preserve: Bool) -> List<Work>:
  match inputs:
    case Nil{}: Bool.pick(List<Work>,preserve,keep_all(old),Nil{})
    case +input <> rest:
      Input{key,source} = input
      requested(input,take(old,key),changes,remaining => requests(rest,remaining,changes,preserve))

def packed_built(result: Result<&2,&1,E.Error,Chunk>) -> Result<&2,&1,E.Error,Built>:
  match result:
    case Fail{error}: Fail{error}
    case Done{chunk}: Done{Built{Some{chunk},True{}}}

def choose_rebuilt(same: Bool, old: Chunk, next: Unit -> Result<&2,&1,E.Error,Built>) -> Result<&2,&1,E.Error,Built>:
  match same:
    case True{}: Done{Built{Some{old},False{}}}
    case False{}: next(Unit{})

def rebuilt_faces(+key: ChunkKey, +version: U32, +domains: List<&2,Domain>, +faces: List<&2,X.Face>, old: Maybe<&1,Chunk>) -> Result<&2,&1,E.Error,Built>:
  match faces old:
    case Nil{} None{}: Done{Built{None{},False{}}}
    case Nil{} _: Done{Built{None{},True{}}}
    case _ None{}: packed_built(pack(key,version,domains,faces))
    case _ Some{Chunk{old_key,old_version,old_domains,M.Mesh{+previous,size,bounds,vs,ix},shadow}}:
      choose_rebuilt(faces_equal(previous,faces),Chunk{old_key,old_version,domains,M.Mesh{previous,size,bounds,vs,ix},shadow},unit => packed_built(pack(key,version,domains,faces)))

def rebuilt_domains(key: ChunkKey, version: U32, old: Maybe<&1,Chunk>, result: Result<&2,&2,E.Error,List<&2,Domain>>) -> Result<&2,&1,E.Error,Built>:
  match result:
    case Fail{error}: Fail{error}
    case Done{+domains}: rebuilt_faces(key,version,domains,domains_faces(domains),old)

def build_work(work: Work, version: U32) -> Result<&2,&1,E.Error,Built>:
  match work:
    case Keep{chunk}: Done{Built{Some{chunk},False{}}}
    case Rebuild{Input{ChunkKey{+x,+y,+z,+span},Dense{halo}},old}:
      rebuilt_faces(ChunkKey{x,y,z,span},version,Nil{},dense_scan(U32.to_nat((span * span * span : U32)),X.Cell{x,y,z},span,halo,0,Nil{}),old)
    case Rebuild{Input{key,Cuboids{sources,blockers}},old}: rebuilt_domains(key,version,old,cuboid_domains(sources,blockers,0))

def built_cons(head: Result<&2,&1,E.Error,Built>, rest: Result<&2,&1,E.Error,List<Built>>) -> Result<&2,&1,E.Error,List<Built>>:
  do Result<&2,&1,E.Error,List<Built>>:
    value : Built <- head
    tail : List<Built> <- rest
    return value <> tail

def build_sequential(xs: List<Work>, +version: U32) -> Result<&2,&1,E.Error,List<Built>>:
  match xs:
    case Nil{}: Done{Nil{}}
    case head <> rest: built_cons(build_work(head,version),build_sequential(rest,version))

def split_work(xs: List<Work>, left: List<Work>, right: List<Work>) -> List<Work> & List<Work>:
  match xs:
    case Nil{}: (left,right)
    case a <> Nil{}: (a <> left,right)
    case a <> b <> rest: split_work(rest,a <> left,b <> right)

def built_append(xs: List<Built>, ys: List<Built>) -> List<Built>:
  match xs:
    case Nil{}: ys
    case head <> rest: head <> built_append(rest,ys)

def built_join(a: Result<&2,&1,E.Error,List<Built>>, b: Result<&2,&1,E.Error,List<Built>>) -> Result<&2,&1,E.Error,List<Built>>:
  do Result<&2,&1,E.Error,List<Built>>:
    left : List<Built> <- a
    right : List<Built> <- b
    return built_append(left,right)

def build_parts(pair: List<Work> & List<Work>, first: List<Work> -> Result<&2,&1,E.Error,List<Built>>, second: List<Work> -> Result<&2,&1,E.Error,List<Built>>) -> Result<&2,&1,E.Error,List<Built>>:
  (left,right) = pair
  a b = first(left) second(right)
  built_join(a,b)

def build_parallel(+depth: Nat, xs: List<Work>, +version: U32) -> Result<&2,&1,E.Error,List<Built>>:
  match depth:
    case 0n: build_sequential(xs,version)
    case 1n+rest: build_parts(split_work(xs,Nil{},Nil{}),left => build_parallel(rest,left,version),right => build_parallel(rest,right,version))

type Order is Data:
  DenseOrder{}
  CuboidOrder{sources: List<&2,X.Cuboid>}
type Metadata is Data:
  Metadata{key: ChunkKey, domains: List<&2,Domain>, faces: List<&2,X.Face>, shadow_quads: U32}

def face_cell(face: X.Face) -> X.Cell:
  match face:
    case X.Face{cell,d,m}: cell
    case X.Rectangle{cell,d,m,w,h}: cell

def face_direction(face: X.Face) -> U32:
  match face:
    case X.Face{cell,d,m}: E.direction(d)
    case X.Rectangle{cell,d,m,w,h}: E.direction(d)

def cell_rank(cell: X.Cell) -> U32:
  X.Cell{x,y,z} = cell
  (x .|. (y << 10n) .|. (z << 20n) : U32)

def primitive_before(a: Primitive, b: Primitive) -> Bool:
  Primitive{key,at,+face} = a
  Primitive{other,index,+next} = b
  G.order(cell_rank(face_cell(next)),cell_rank(face_cell(face)),G.order(face_direction(next),face_direction(face),True{}))

def tag(faces: List<&2,X.Face>, +key: ChunkKey, +first: U32) -> List<&2,Primitive>:
  match faces:
    case Nil{}: Nil{}
    case face <> rest: Primitive{key,first,face} <> tag(rest,key,(first + 1 : U32))

def primitive_append(xs: List<&2,Primitive>, ys: List<&2,Primitive>) -> List<&2,Primitive>:
  match xs:
    case Nil{}: ys
    case head <> rest: head <> primitive_append(rest,ys)

def metadata_head(chunk: Chunk, pair: List<Chunk> & List<&2,Metadata>) -> List<Chunk> & List<&2,Metadata>:
  Chunk{+key,version,+domains,M.Mesh{+faces,size,bounds,vs,ix},M.Mesh{sf,+ss,sb,sv,si}} = chunk
  M.PackedSize{sq,vc,ic,vw,iw,vb,ib,vsize,isize,vd,id} = ss
  (rest,metadata) = pair
  (Chunk{key,version,domains,M.Mesh{faces,size,bounds,vs,ix},M.Mesh{sf,ss,sb,sv,si}} <> rest,Metadata{key,domains,faces,sq} <> metadata)

def metadata(chunks: List<Chunk>) -> List<Chunk> & List<&2,Metadata>:
  match chunks:
    case Nil{}: (Nil{},Nil{})
    case head <> rest: metadata_head(head,metadata(rest))

def all_primitives(xs: List<&2,Metadata>) -> List<&2,Primitive>:
  match xs:
    case Nil{}: Nil{}
    case Metadata{key,domains,faces,sq} <> rest: primitive_append(tag(faces,key,0),all_primitives(rest))

def source_match(equal: Bool, faces: List<&2,X.Face>, key: ChunkKey, first: U32, next: Unit -> Maybe<&2,List<&2,Primitive>>) -> Maybe<&2,List<&2,Primitive>>:
  match equal:
    case True{}: Some{tag(faces,key,first)}
    case False{}: next(Unit{})

def source_find(domains: List<&2,Domain>, +source: X.Cuboid, +key: ChunkKey) -> Maybe<&2,List<&2,Primitive>>:
  match domains:
    case Nil{}: None{}
    case Domain{box,first,faces} <> rest:
      source_match(box_equal(box,source),faces,key,first,unit => source_find(rest,source,key))

def source_found(found: Maybe<&2,List<&2,Primitive>>, next: Unit -> List<&2,Primitive>) -> List<&2,Primitive>:
  match found:
    case Some{faces}: faces
    case None{}: next(Unit{})

def source_primitives(xs: List<&2,Metadata>, +box: X.Cuboid) -> List<&2,Primitive>:
  match xs:
    case Nil{}: Nil{}
    case Metadata{key,domains,faces,sq} <> rest: source_found(source_find(domains,box,key),unit => source_primitives(rest,box))

def ordered_sources(xs: List<&2,X.Cuboid>, +metadata: List<&2,Metadata>) -> List<&2,Primitive>:
  match xs:
    case Nil{}: Nil{}
    case X.Cuboid{lo,hi,0} <> rest: ordered_sources(rest,metadata)
    case box <> rest: primitive_append(source_primitives(metadata,box),ordered_sources(rest,metadata))

def ordered(order: Order, metadata: List<&2,Metadata>) -> List<&2,Primitive>:
  match order:
    case DenseOrder{}: List.sort(~Primitive,~primitive_before,all_primitives(metadata))
    case CuboidOrder{sources}: ordered_sources(sources,metadata)

def primitive_faces(xs: List<&2,Primitive>) -> List<&2,X.Face>:
  match xs:
    case Nil{}: Nil{}
    case Primitive{key,first,face} <> rest: face <> primitive_faces(rest)

def shadow_count(xs: List<&2,Metadata>, +total: U32) -> U32:
  match xs:
    case Nil{}: total
    case Metadata{key,domains,faces,count} <> rest: shadow_count(rest,(total + count : U32))

def collapse(xs: List<Built>, chunks: List<Chunk>, +rebuilt: U32, +retained: U32) -> List<Chunk> & (U32 & U32):
  match xs:
    case Nil{}: (List.reverse(&1,Chunk,chunks),(rebuilt,retained))
    case Built{None{},changed} <> rest: collapse(rest,chunks,(rebuilt + Bool.to_u32(changed) : U32),retained)
    case Built{Some{chunk},+changed} <> rest: collapse(rest,chunk <> chunks,(rebuilt + Bool.to_u32(changed) : U32),(retained + Bool.to_u32(Bool.not(changed)) : U32))

def counted(body: X.Body, chunks: List<Chunk>, primitives: List<&2,Primitive>, +faces: List<&2,X.Face>, metadata: List<&2,Metadata>, rebuilt: U32, retained: U32, count: Result<&2,&2,E.Error,U32>) -> X.Body & Result<&2,&1,E.Error,ChunkSet>:
  match count:
    case Fail{error}: (body,Fail{error})
    case Done{quads}: (body,Done{ChunkSet{chunks,primitives,faces,M.bounds(faces,None{}),quads,shadow_count(metadata,0),rebuilt,retained}})

def with_primitives(body: X.Body, chunks: List<Chunk>, +primitives: List<&2,Primitive>, metadata: List<&2,Metadata>, rebuilt: U32, retained: U32) -> X.Body & Result<&2,&1,E.Error,ChunkSet>:
  +faces = primitive_faces(primitives)
  counted(body,chunks,primitives,faces,metadata,rebuilt,retained,E.count(faces,0))

def with_metadata(body: X.Body, order: Order, pair: List<Chunk> & List<&2,Metadata>, rebuilt: U32, retained: U32) -> X.Body & Result<&2,&1,E.Error,ChunkSet>:
  (chunks,+meta) = pair
  with_primitives(body,chunks,ordered(order,meta),meta,rebuilt,retained)

def collapsed(body: X.Body, order: Order, pair: List<Chunk> & (U32 & U32)) -> X.Body & Result<&2,&1,E.Error,ChunkSet>:
  (chunks,(rebuilt,retained)) = pair
  with_metadata(body,order,metadata(chunks),rebuilt,retained)

def finished(body: X.Body, order: Order, result: Result<&2,&1,E.Error,List<Built>>) -> X.Body & Result<&2,&1,E.Error,ChunkSet>:
  match result:
    case Fail{error}: (body,Fail{error})
    case Done{chunks}: collapsed(body,order,collapse(chunks,Nil{},0,0))

def dependency_region(key: ChunkKey, +side: U32) -> X.Cuboid:
  ChunkKey{+x,+y,+z,+span} = key
  X.Cuboid{X.Cell{(x - U32.min(x,1) : U32),(y - U32.min(y,1) : U32),(z - U32.min(z,1) : U32)},X.Cell{U32.min(side,(x + span + 1 : U32)),U32.min(side,(y + span + 1 : U32)),U32.min(side,(z + span + 1 : U32))},1}

def selected(key: ChunkKey, side: U32, sphere: Maybe<&2,X.MetricSphere>) -> Bool:
  match sphere:
    case None{}: True{}
    case Some{+brush}: X.MetricSphere.valid(brush) && X.Cuboid.overlaps(dependency_region(key,side),brush)

def select_key(include: Bool, key: ChunkKey, rest: List<&2,ChunkKey>) -> List<&2,ChunkKey>:
  match include:
    case True{}: key <> rest
    case False{}: rest

def dense_keys(fuel: Nat, +side: U32, +span: U32, +across: U32, +at: U32, +sphere: Maybe<&2,X.MetricSphere>) -> List<&2,ChunkKey>:
  match fuel:
    case 0n: Nil{}
    case 1n+rest:
      +key : ChunkKey = ChunkKey{(at % across * span : U32),(at / across % across * span : U32),(at / (across * across) * span : U32),span}
      select_key(selected(key,side,sphere),key,dense_keys(rest,side,span,across,(at + 1 : U32),sphere))

def keys(+side: U32, sphere: Maybe<&2,X.MetricSphere>) -> List<&2,ChunkKey>:
  +span = U32.min(side,32)
  +across = (side / span : U32)
  dense_keys(U32.to_nat((across * across * across : U32)),side,span,across,0,sphere)

def gather_next(pair: Array<U32> & Input, next: Array<U32> -> Input -> Array<U32> & List<&2,Input>) -> Array<U32> & List<&2,Input>:
  (cells,input) = pair
  next(cells,input)

def gather_inputs(xs: List<&2,ChunkKey>, +side: U32, cells: Array<U32>, inputs: List<&2,Input>) -> Array<U32> & List<&2,Input>:
  match xs:
    case Nil{}: (cells,List.reverse(&2,Input,inputs))
    case key <> rest: gather_next(gather_input(side,key,cells),array => input => gather_inputs(rest,side,array,input <> inputs))

def parallel_depth(count: Nat) -> Nat:
  Nat.min(3n,U32.log2(U32.max(1,(U32.from_nat(count) / 2 : U32))))

def dense_inputs(+side: U32, old: List<Chunk>, +version: U32, pair: Array<U32> & List<&2,Input>) -> X.Body & Result<&2,&1,E.Error,ChunkSet>:
  (cells,+inputs) = pair
  finished(X.Body{side,cells},DenseOrder{},build_parallel(parallel_depth(List.length(&2,Input,inputs)),requests(inputs,old,Nil{},True{}),version))

def dense_checked(+side: U32, version: U32, pair: Array<U32> & Bool) -> X.Body & Result<&2,&1,E.Error,ChunkSet>:
  (cells,valid) = pair
  match valid:
    case False{}: (X.Body{side,cells},Fail{E.InvalidDense{}})
    case True{}: dense_inputs(side,Nil{},version,gather_inputs(keys(side,None{}),side,cells,Nil{}))

def dense_valid(valid: Bool, +side: U32, cells: Array<U32>, version: U32) -> X.Body & Result<&2,&1,E.Error,ChunkSet>:
  match valid:
    case False{}: (X.Body{side,cells},Fail{E.InvalidDense{}})
    case True{}: dense_checked(side,version,M.dense_tree(Nat.mul(3n,U32.log2(side)),cells))

def validate_boxes(+boxes: List<&2,X.Cuboid>) -> Result<&2,&2,E.Error,Unit>:
  do Result<&2,&2,E.Error,Unit>:
    size : Unit <- E.source_count(boxes,0)
    E.validate(boxes,0)

def cuboids_checked(+boxes: List<&2,X.Cuboid>, version: U32, result: Result<&2,&2,E.Error,Unit>) -> X.Body & Result<&2,&1,E.Error,ChunkSet>:
  match result:
    case Fail{error}: (X.Cuboids{boxes},Fail{error})
    case Done{unit}:
      +inputs = cuboid_inputs(boxes,boxes,Nil{})
      finished(X.Cuboids{boxes},CuboidOrder{boxes},build_parallel(parallel_depth(List.length(&2,Input,inputs)),requests(inputs,Nil{},Nil{},False{}),version))

def build(body: X.Body, version: U32) -> X.Body & Result<&2,&1,E.Error,ChunkSet>:
  match body:
    case X.Body{+side,cells}: dense_valid((side > 0 : U32) && (side <= 1024 : U32) && U32.is_eq((side .&. (side - 1) : U32),0),side,cells,version)
    case X.Cuboids{+boxes}: cuboids_checked(boxes,version,validate_boxes(boxes))

def contains_box(xs: List<&2,X.Cuboid>, +box: X.Cuboid) -> Bool:
  match xs:
    case Nil{}: False{}
    case head <> rest: box_equal(head,box) || contains_box(rest,box)

def different(xs: List<&2,X.Cuboid>, +other: List<&2,X.Cuboid>) -> List<&2,X.Cuboid>:
  match xs:
    case Nil{}: Nil{}
    case +box <> rest:
      +tail = different(rest,other)
      Bool.pick(List<&2,X.Cuboid>,contains_box(other,box),tail,box <> tail)

def edited(+old_boxes: List<&2,X.Cuboid>, old: ChunkSet, +sphere: X.MetricSphere, version: U32, body: X.Body) -> X.Body & Result<&2,&1,E.Error,ChunkSet>:
  ChunkSet{chunks,primitives,faces,bounds,quads,shadow,rebuilt,retained} = old
  match body:
    case X.Body{+side,cells}: dense_inputs(side,chunks,version,gather_inputs(keys(side,Some{sphere}),side,cells,Nil{}))
    case X.Cuboids{+boxes}:
      +changes = box_append(different(old_boxes,boxes),different(boxes,old_boxes))
      +inputs = cuboid_inputs(boxes,boxes,Nil{})
      finished(X.Cuboids{boxes},CuboidOrder{boxes},build_parallel(parallel_depth(List.length(&2,Input,inputs)),requests(inputs,chunks,changes,False{}),version))

def cut(body: X.Body, old: ChunkSet, +sphere: X.MetricSphere, version: U32) -> X.Body & Result<&2,&1,E.Error,ChunkSet>:
  match body:
    case X.Body{side,cells}: edited(Nil{},old,sphere,version,X.Body.cut(X.Body{side,cells},sphere))
    case X.Cuboids{+boxes}: edited(boxes,old,sphere,version,X.Body.cut(X.Cuboids{boxes},sphere))

def run_step(joined: Bool, key: ChunkKey, first: U32, count: U32, primitive: Primitive, next: Run -> List<&2,Run>) -> List<&2,Run>:
  match joined primitive:
    case True{} _: next(Run{key,first,(count + 1 : U32)})
    case False{} Primitive{own,at,face}: Run{key,first,count} <> next(Run{own,at,1})

def run_scan(xs: List<&2,Primitive>, current: Run) -> List<&2,Run>:
  match xs:
    case Nil{}: [current]
    case +primitive <> rest:
      Primitive{own,+at,face} = primitive
      Run{+key,+first,+count} = current
      run_step(key_equal(key,own) && U32.is_eq(at,(first + count : U32)),key,first,count,primitive,run => run_scan(rest,run))

def runs(xs: List<&2,Primitive>) -> List<&2,Run>:
  match xs:
    case Nil{}: Nil{}
    case Primitive{key,first,face} <> rest: run_scan(rest,Run{key,first,1})
