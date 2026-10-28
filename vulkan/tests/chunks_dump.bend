import Base
import ./geometry_dump.bend as D
import ../src/chunks.bend as C
import ../src/mesh.bend as M
import ../src/exterior.bend as E
import ../../voxel.bend as X
import ../../atelier.bend as Atelier

def key(k: C.ChunkKey) -> String:
  C.ChunkKey{x,y,z,e} = k
  "[" ++ D.numbers([x,y,z,e]) ++ "]"

def chunk(c: C.Chunk) -> C.Chunk & String:
  C.Chunk{+k,+version,+domains,M.Mesh{+fs,+size,+bounds,vs,ix},M.Mesh{+sf,+ss,+sb,sv,si}} = c
  (C.Chunk{k,version,domains,M.Mesh{fs,size,bounds,vs,ix},M.Mesh{sf,ss,sb,sv,si}},"{\"key\":" ++ key(k) ++ ",\"version\":" ++ U32.show(version) ++ ",\"faces\":[" ++ D.faces(fs) ++ "],\"shadow\":[" ++ D.faces(sf) ++ "]}")

def chunk_next(head: C.Chunk & String, tail: List<C.Chunk> & List<String>) -> List<C.Chunk> & List<String>:
  (c,json) = head
  (cs,js) = tail
  (c <> cs,json <> js)

def chunks(xs: List<C.Chunk>) -> List<C.Chunk> & List<String>:
  match xs:
    case Nil{}: (Nil{},Nil{})
    case c <> rest: chunk_next(chunk(c),chunks(rest))

def joined(xs: List<String>) -> String:
  match xs:
    case Nil{}: ""
    case s <> Nil{}: s
    case s <> rest: s ++ "," ++ joined(rest)

def runs(xs: List<&2,C.Run>) -> String:
  match xs:
    case Nil{}: ""
    case C.Run{k,first,count} <> Nil{}: "[" ++ key(k) ++ "," ++ D.numbers([first,count]) ++ "]"
    case C.Run{k,first,count} <> rest: "[" ++ key(k) ++ "," ++ D.numbers([first,count]) ++ "]," ++ runs(rest)

def emitted(+name: String, body: X.Body, expected_body: String, returned_body: String, +primitives: List<&2,C.Primitive>, +fs: List<&2,X.Face>, bounds: Maybe<&2,M.Extent>, +q: U32, +sq: U32, +rebuilt: U32, +retained: U32, pair: List<C.Chunk> & List<String>) -> IO(X.Body & C.ChunkSet):
  (cs,json) = pair
  do IO<X.Body & C.ChunkSet>:
    IO.print("{\"case\":\"" ++ name ++ "\",\"expected_body\":" ++ expected_body ++ ",\"returned_body\":" ++ returned_body ++ ",\"faces\":[" ++ D.faces(fs) ++ "],\"counts\":[" ++ D.numbers([q,sq,rebuilt,retained]) ++ "],\"runs\":[" ++ runs(C.runs(primitives)) ++ "],\"chunks\":[" ++ joined(json) ++ "]}")
    return (body,C.ChunkSet{cs,primitives,fs,bounds,q,sq,rebuilt,retained})

def failed(name: String, error: E.Error, body: X.Body) -> IO(X.Body & C.ChunkSet):
  do IO<X.Body & C.ChunkSet>:
    IO.print("ERROR " ++ name ++ " " ++ E.error_show(error))
    return (body,C.ChunkSet{Nil{},Nil{},Nil{},None{},0,0,0,0})

def baseline(+name: String, actual: X.Body, expected_body: String, returned_body: String, set: C.ChunkSet, pair: X.Body & Result<&2,&1,E.Error,M.Mesh>) -> IO(X.Body & C.ChunkSet):
  C.ChunkSet{cs,primitives,faces,bounds,q,sq,rebuilt,retained} = set
  (reference,result) = pair
  match result:
    case Fail{error}: failed(name,error,actual)
    case Done{M.Mesh{fs,s,b,vs,ix}}:
      do IO<X.Body & C.ChunkSet>:
        IO.print("{\"baseline\":\"" ++ name ++ "\",\"faces\":[" ++ D.faces(fs) ++ "]}")
        emitted(name,actual,expected_body,returned_body,primitives,faces,bounds,q,sq,rebuilt,retained,chunks(cs))

def returned(name: String, reference: X.Body, expected_body: String, set: C.ChunkSet, pair: X.Body & String) -> IO(X.Body & C.ChunkSet):
  (actual,returned_body) = pair
  baseline(name,actual,expected_body,returned_body,set,M.build(reference))

def result(name: String, reference: X.Body, expected_body: String, pair: X.Body & Result<&2,&1,E.Error,C.ChunkSet>) -> IO(X.Body & C.ChunkSet):
  (body,status) = pair
  match status:
    case Fail{error}: failed(name,error,body)
    case Done{set}: returned(name,reference,expected_body,set,D.body(body))

def copied_dense(+side: U32, pair: Array<U32> & Array<U32>) -> X.Body & X.Body:
  (reference,input) = pair
  (X.Body{side,reference},X.Body{side,input})

def copies(body: X.Body) -> X.Body & X.Body:
  match body:
    case X.Body{side,cells}: copied_dense(side,Array.clone(U32,cells))
    case X.Cuboids{+boxes}: (X.Cuboids{boxes},X.Cuboids{boxes})

def captured(name: String, input: X.Body, pair: X.Body & String) -> IO(X.Body & C.ChunkSet):
  (reference,expected_body) = pair
  result(name,reference,expected_body,C.build(input,0))

def build_copies(name: String, pair: X.Body & X.Body) -> IO(X.Body & C.ChunkSet):
  (reference,input) = pair
  captured(name,input,D.body(reference))

def build(name: String, body: X.Body) -> IO(X.Body & C.ChunkSet):
  build_copies(name,copies(body))

def run(name: String, body: X.Body) -> IO(Unit):
  do IO<Unit>:
    pair : X.Body & C.ChunkSet <- build(name,body)
    return Unit{}

def boundary() -> X.Body:
  b = X.Body.empty(6n)
  b = X.Body.write(b,X.Cell{31,3,3},1)
  b = X.Body.write(b,X.Cell{32,3,3},1)
  b = X.Body.write(b,X.Cell{3,31,3},2147483648)
  b = X.Body.write(b,X.Cell{3,32,3},4294967295)
  b = X.Body.write(b,X.Cell{3,3,31},2309737967)
  b = X.Body.write(b,X.Cell{3,3,32},2309737967)
  X.Body.write(b,X.Cell{63,63,63},2)

def cut_captured(name: String, input: X.Body, set: C.ChunkSet, sphere: X.MetricSphere, version: U32, pair: X.Body & String) -> IO(X.Body & C.ChunkSet):
  (reference,expected_body) = pair
  result(name,reference,expected_body,C.cut(input,set,sphere,version))

def cut_copies(name: String, set: C.ChunkSet, +sphere: X.MetricSphere, version: U32, pair: X.Body & X.Body) -> IO(X.Body & C.ChunkSet):
  (reference,input) = pair
  cut_captured(name,input,set,sphere,version,D.body(X.Body.cut(reference,sphere)))

def edit(name: String, sphere: X.MetricSphere, pair: X.Body & C.ChunkSet, version: U32) -> IO(X.Body & C.ChunkSet):
  (body,set) = pair
  cut_copies(name,set,sphere,version,copies(body))

def edits() -> IO(Unit):
  do IO<Unit>:
    a : X.Body & C.ChunkSet <- build("boundary",boundary())
    b : X.Body & C.ChunkSet <- edit("boundary-cut",X.MetricSphere{X.PointCm{315.0,35.0,35.0},0.0},a,1)
    c : X.Body & C.ChunkSet <- edit("boundary-repeat",X.MetricSphere{X.PointCm{315.0,35.0,35.0},0.0},b,2)
    d : X.Body & C.ChunkSet <- edit("boundary-miss",X.MetricSphere{X.PointCm{10000.0,10000.0,10000.0},0.0},c,3)
    return Unit{}

def remote() -> X.Body:
  X.Cuboids{[D.cuboid(0,0,0,128,1,4,1),D.cuboid(20,1,0,24,2,4,2),D.cuboid(120,1,0,124,2,4,3),D.cuboid(200,0,0,204,4,4,4)]}

def remote_edits() -> IO(Unit):
  do IO<Unit>:
    a : X.Body & C.ChunkSet <- build("remote",remote())
    b : X.Body & C.ChunkSet <- edit("remote-cut",X.MetricSphere{X.PointCm{5.0,5.0,5.0},0.0},a,1)
    c : X.Body & C.ChunkSet <- edit("remote-repeat",X.MetricSphere{X.PointCm{5.0,5.0,5.0},0.0},b,2)
    return Unit{}

def merge_boxes() -> X.Body:
  X.Cuboids{[D.cuboid(0,0,0,2,4,4,1),D.cuboid(2,0,0,4,4,4,1)]}

def main() -> IO(Unit):
  do IO<Unit>:
    run("empty",X.Cuboids{Nil{}})
    run("cube",X.Body.solid(3n))
    run("dense-materials",D.dense_materials())
    run("touching",D.touching())
    run("cavity",D.cavity())
    run("merge-boxes",merge_boxes())
    run("huge",X.Cuboids{[D.cuboid(0,0,0,1048576,1048576,1048576,4294967295)]})
    edits()
    remote_edits()
    run("atelier",Atelier.body())
