import Base
import ../src/mesh.bend as G
import ../src/exterior.bend as E
import ../src/viewport.bend as View
import ../../voxel.bend as X
import ../../atelier.bend as Atelier
import ../../render.bend as R
import ../../material.bend as P
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W

def numbers(xs: List<U32>) -> String:
  match xs:
    case Nil{}: ""
    case x <> Nil{}: U32.show(x)
    case x <> rest: U32.show(x) ++ "," ++ numbers(rest)

def words(a: Array<U32>) -> String:
  "[" ++ numbers(Array.to_list(~U32,a)) ++ "]"

def cell(c: X.Cell) -> String:
  X.Cell{x,y,z} = c
  numbers([x,y,z])

def box(b: X.Cuboid) -> String:
  X.Cuboid{lo,hi,m} = b
  "[" ++ cell(lo) ++ "," ++ cell(hi) ++ "," ++ U32.show(m) ++ "]"

def boxes(bs: List<&2,X.Cuboid>) -> String:
  match bs:
    case Nil{}: ""
    case b <> Nil{}: box(b)
    case b <> rest: box(b) ++ "," ++ boxes(rest)

def dense_body(+side: U32, pair: Array<U32> & Array<U32>) -> X.Body & String:
  (cells,copy) = pair
  (X.Body{side,cells},"{\"side\":" ++ U32.show(side) ++ ",\"cells\":" ++ words(copy) ++ "}")

def body(b: X.Body) -> X.Body & String:
  match b:
    case X.Body{side,cells}: dense_body(side,Array.clone(U32,cells))
    case X.Cuboids{+bs}: (X.Cuboids{bs},"{\"boxes\":[" ++ boxes(bs) ++ "]}")

def face(f: X.Face) -> String:
  match f:
    case X.Face{c,d,m}: "[0," ++ cell(c) ++ "," ++ numbers([E.direction(d),m,1,1]) ++ "]"
    case X.Rectangle{c,d,m,w,h}: "[1," ++ cell(c) ++ "," ++ numbers([E.direction(d),m,w,h]) ++ "]"

def faces(fs: List<&2,X.Face>) -> String:
  match fs:
    case Nil{}: ""
    case f <> Nil{}: face(f)
    case f <> rest: face(f) ++ "," ++ faces(rest)

def limbs(n: W.U64) -> String:
  W.U64{lo,hi} = n
  "[" ++ numbers([lo,hi]) ++ "]"

def size(s: G.PackedSize) -> String:
  G.PackedSize{q,vc,ic,vw,iw,vb,ib,vs,iscap,vd,id} = s
  "{\"counts\":[" ++ numbers([q,vc,ic,vw,iw,vs,iscap,U32.from_nat(vd),U32.from_nat(id)]) ++ "],\"vertex_bytes\":" ++ limbs(vb) ++ ",\"index_bytes\":" ++ limbs(ib) ++ "}"

def bounds(b: Maybe<&2,G.Extent>) -> String:
  match b:
    case None{}: "null"
    case Some{G.Extent{low,high}}: "[" ++ cell(low) ++ "," ++ cell(high) ++ "]"

def mesh(m: G.Mesh) -> String & List<&2,X.Face>:
  G.Mesh{+fs,s,b,vs,ix} = m
  ("{\"faces\":[" ++ faces(fs) ++ "],\"size\":" ++ size(s) ++ ",\"bounds\":" ++ bounds(b) ++ ",\"vertices\":" ++ words(vs) ++ ",\"indices\":" ++ words(ix) ++ "}",fs)

def emit_mesh(name: String, b: X.Body, source: String, pair: String & List<&2,X.Face>) -> IO(X.Body & List<&2,X.Face>):
  (json,fs) = pair
  do IO<X.Body & List<&2,X.Face>>:
    IO.print("{\"case\":\"" ++ name ++ "\",\"body\":" ++ source ++ ",\"mesh\":" ++ json ++ "}")
    return (b,fs)

def emit_status(name: String, pair: X.Body & String, result: Result<&2,&1,E.Error,G.Mesh>) -> IO(X.Body & List<&2,X.Face>):
  (b,source) = pair
  match result:
    case Fail{e}:
      do IO<X.Body & List<&2,X.Face>>:
        IO.print("{\"case\":\"" ++ name ++ "\",\"body\":" ++ source ++ ",\"error\":\"" ++ E.error_show(e) ++ "\"}")
        return (b,Nil{})
    case Done{m}: emit_mesh(name,b,source,mesh(m))

def emit_result(name: String, pair: X.Body & Result<&2,&1,E.Error,G.Mesh>) -> IO(X.Body & List<&2,X.Face>):
  (b,result) = pair
  emit_status(name,body(b),result)

def emit_original(+name: String, pair: X.Body & String) -> IO(X.Body & List<&2,X.Face>):
  (b,original) = pair
  do IO<X.Body & List<&2,X.Face>>:
    IO.print("{\"original_case\":\"" ++ name ++ "\",\"source_body\":" ++ original ++ "}")
    emit_result(name,G.build(b))

def emit(name: String, b: X.Body) -> IO(X.Body & List<&2,X.Face>):
  emit_original(name,body(b))

def run(name: String, b: X.Body) -> IO(Unit):
  do IO<Unit>:
    pair : X.Body & List<&2,X.Face> <- emit(name,b)
    return Unit{}

def cuboid(+x: U32, +y: U32, +z: U32, hx: U32, hy: U32, hz: U32, m: U32) -> X.Cuboid:
  X.Cuboid{X.Cell{x,y,z},X.Cell{hx,hy,hz},m}

def touching() -> X.Body:
  X.Cuboids{[cuboid(2,2,2,5,7,9,1),cuboid(5,3,4,8,6,8,2),cuboid(0,4,3,2,6,7,3),cuboid(3,7,3,4,9,8,4),cuboid(3,0,3,4,2,8,5),cuboid(3,4,9,4,6,12,2147483648),cuboid(3,4,0,4,6,2,4294967295)]}

def tiled() -> X.Body:
  X.Cuboids{[cuboid(0,0,0,2,2,2,1),cuboid(2,0,0,4,1,2,2),cuboid(2,1,0,4,2,2,3),cuboid(0,2,0,4,3,2,4),cuboid(0,0,2,4,3,3,5),cuboid(8,8,8,9,9,9,0)]}

def cavity() -> X.Body:
  X.Cuboids{[cuboid(0,0,0,5,5,1,1),cuboid(0,0,4,5,5,5,2),cuboid(0,0,1,1,5,4,3),cuboid(4,0,1,5,5,4,4),cuboid(1,0,1,4,1,4,5),cuboid(1,4,1,4,5,4,4294967295)]}

def dense_materials() -> X.Body:
  b = X.Body.empty(3n)
  b = X.Body.write(b,X.Cell{0,3,3},1)
  b = X.Body.write(b,X.Cell{1,3,3},2)
  b = X.Body.write(b,X.Cell{2,3,3},3)
  b = X.Body.write(b,X.Cell{3,3,3},4)
  b = X.Body.write(b,X.Cell{4,3,3},5)
  b = X.Body.write(b,X.Cell{5,3,3},2147483648)
  b = X.Body.write(b,X.Cell{6,3,3},2309737967)
  X.Body.write(b,X.Cell{7,3,3},4294967295)

def brush(sphere: Maybe<&2,X.MetricSphere>) -> IO(Unit):
  match sphere:
    case None{}: IO.print("{\"brush\":null}")
    case Some{X.MetricSphere{X.PointCm{x,y,z},r}}: IO.print("{\"brush_bits\":[" ++ numbers([F32.bits(x),F32.bits(y),F32.bits(z),F32.bits(r)]) ++ "]}")

def cut(b: X.Body, sphere: Maybe<&2,X.MetricSphere>) -> X.Body:
  match sphere:
    case None{}: b
    case Some{s}: X.Body.cut(b,s)

def repeat(sphere: Maybe<&2,X.MetricSphere>, pair: X.Body & List<&2,X.Face>) -> IO(Unit):
  (b,fs) = pair
  run("atelier-repeat",cut(b,sphere))

def atelier_cut(pair: X.Body & List<&2,X.Face>) -> IO(Unit):
  (b,+fs) = pair
  +sphere = View.target(View.Viewport{512,512},R.Camera.atelier(),fs,226,224)
  do IO<Unit>:
    brush(sphere)
    carved : X.Body & List<&2,X.Face> <- emit("atelier-carved",cut(b,sphere))
    repeat(sphere,carved)
    run("atelier-reset",Atelier.body())

def asymmetric() -> List<&2,X.Face>:
  [X.Rectangle{X.Cell{3,5,7},X.NegX{},1,2,3},X.Rectangle{X.Cell{11,13,17},X.PosX{},2,2,3},X.Rectangle{X.Cell{23,29,31},X.NegY{},3,2,3},X.Rectangle{X.Cell{37,41,43},X.PosY{},4,2,3},X.Rectangle{X.Cell{47,53,59},X.NegZ{},5,2,3},X.Rectangle{X.Cell{61,67,71},X.PosZ{},2309737967,2,3}]

def mesh_only_status(name: String, result: Result<&2,&1,E.Error,G.Mesh>) -> IO(Unit):
  match result:
    case Fail{e}: IO.print("{\"case\":\"" ++ name ++ "\",\"error\":\"" ++ E.error_show(e) ++ "\"}")
    case Done{m}:
      do IO<Unit>:
        ignored : X.Body & List<&2,X.Face> <- emit_mesh(name,X.Cuboids{Nil{}},"null",mesh(m))
        return Unit{}

def mesh_only(name: String, fs: List<&2,X.Face>) -> IO(Unit):
  mesh_only_status(name,G.pack(fs))

def size_status(q: U32, result: Result<&2,&2,E.Error,G.PackedSize>) -> IO(Unit):
  match result:
    case Fail{e}: IO.print("{\"size_q\":" ++ U32.show(q) ++ ",\"error\":\"" ++ E.error_show(e) ++ "\"}")
    case Done{s}: IO.print("{\"size_q\":" ++ U32.show(q) ++ ",\"size\":" ++ size(s) ++ "}")

def main() -> IO(Unit):
  do IO<Unit>:
    run("empty-boxes",X.Cuboids{Nil{}})
    run("all-air-boxes",X.Cuboids{[cuboid(0,0,0,2,3,4,0)]})
    run("air-overlap-first",X.Cuboids{[cuboid(0,0,0,5,5,5,0),cuboid(1,1,1,3,4,5,2309737967)]})
    run("air-overlap-last",X.Cuboids{[cuboid(1,1,1,3,4,5,2309737967),cuboid(0,0,0,5,5,5,0)]})
    run("empty-dense",X.Body.empty(2n))
    run("cube",X.Body.solid(3n))
    run("cube-carved",X.Body.cut(X.Body.solid(3n),X.MetricSphere.demo()))
    run("dense-materials",dense_materials())
    run("touching",touching())
    run("touching-cut",X.Body.cut(touching(),X.MetricSphere{X.PointCm{50.0,50.0,60.0},20.0}))
    run("dense-cavity",X.Body.cut(X.Body.solid(3n),X.MetricSphere{X.PointCm{35.0,35.0,35.0},0.0}))
    run("tiled",tiled())
    run("cavity",cavity())
    run("overlap",X.Cuboids{[cuboid(0,0,0,4,4,4,1),cuboid(2,2,2,6,6,6,2)]})
    run("contained",X.Cuboids{[cuboid(0,0,0,4,4,4,1),cuboid(1,1,1,3,3,3,2)]})
    run("duplicate",X.Cuboids{[cuboid(0,0,0,4,4,4,1),cuboid(0,0,0,4,4,4,2)]})
    run("invalid-box",X.Cuboids{[cuboid(0,0,0,0,2,3,1)]})
    run("inverted-box",X.Cuboids{[cuboid(3,0,0,2,2,3,1)]})
    run("coordinate-over",X.Cuboids{[cuboid(1048576,0,0,1048577,1,1,1)]})
    run("coordinate-limit",X.Cuboids{[cuboid(1048575,2,3,1048576,4,6,4294967295)]})
    run("invalid-dense-side",X.Body{3,[1 : U32^5n]})
    run("invalid-dense-shape",X.Body{2,ANode{ALeaf{1},ALeaf{2}}})
    mesh_only("asymmetric",asymmetric())
    mesh_only("zero-width",[X.Rectangle{X.Cell{1,2,3},X.NegX{},1,0,3}])
    mesh_only("extent-over",[X.Rectangle{X.Cell{1,1048575,3},X.NegX{},1,2,3}])
    mesh_only("extent-wrap",[X.Rectangle{X.Cell{1,2,3},X.NegX{},1,4294967295,3}])
    size_status(0,G.size(0))
    size_status(1,G.size(1))
    size_status(26843545,G.size(26843545))
    size_status(26843546,G.size(26843546))
    size_status(4294967295,G.size(4294967295))
    intact : X.Body & List<&2,X.Face> <- emit("atelier-intact",Atelier.body())
    atelier_cut(intact)
