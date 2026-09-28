import Base
import ./math.bend as R
import ./spatial.bend as S
import ./mesh.bend as Mesh
import ./world.bend as W

# Admission worker transport. The separate runner checks source bounds, U32
# sums, IDs and conservative surface/vertex/allocation bounds BEFORE compiling
# its frozen input. This path exercises existing production constructors and
# cached geometry; it does not run a renderer or claim formal geometry proofs.
def quote(s: String) -> String:
  "\"" ++ s ++ "\""
def word(n: U32) -> String:
  quote(U32.show(n))
def hex(n: Nat, +value: U32, tail: String) -> String:
  match n:
    case 0n: quote("0x" ++ tail)
    case 1n+k:
      +d = (value % 16 : U32)
      hex(k,(value / 16 : U32),SCon{Char.from_u32((d + R.word((d < 10 : U32),48,87) : U32)),tail})
def real(value: F32) -> String:
  hex(8n,F32.bits(value),"")
def boolean(b: Bool) -> String:
  match b:
    case True{}: "true"
    case False{}: "false"
def vec(v: R.Vec) -> String:
  R.Vec{x,y,z} = v
  real(x) ++ "," ++ real(y) ++ "," ++ real(z)
def box(b: S.Box) -> String:
  S.Box{lo,hi,m} = b
  "[" ++ vec(lo) ++ "," ++ vec(hi) ++ "," ++ word(m) ++ "]"
def face(f: S.Face) -> String:
  S.Face{lo,hi,side,m} = f
  "[" ++ vec(lo) ++ "," ++ vec(hi) ++ "," ++ word(side) ++ "," ++ word(m) ++ "]"
def vertex(v: Mesh.Vertex) -> String:
  Mesh.Vertex{p,side,m} = v
  "[" ++ vec(p) ++ "," ++ word(side) ++ "," ++ word(m) ++ "]"
def box.strings(bs: List<&2,S.Box>) -> List<&2,String>:
  match bs:
    case Nil{}: Nil{}
    case b <> rest: box(b) <> box.strings(rest)
def face.strings(fs: List<&2,S.Face>) -> List<&2,String>:
  match fs:
    case Nil{}: Nil{}
    case f <> rest: face(f) <> face.strings(rest)
def vertex.strings(vs: List<&2,Mesh.Vertex>) -> List<&2,String>:
  match vs:
    case Nil{}: Nil{}
    case v <> rest: vertex(v) <> vertex.strings(rest)
def array.tail(xs: List<&2,String>) -> String:
  match xs:
    case Nil{}: "]"
    case x <> rest: "," ++ x ++ array.tail(rest)
def array(xs: List<&2,String>) -> String:
  match xs:
    case Nil{}: "[]"
    case x <> rest: "[" ++ x ++ array.tail(rest)
def connected(c: S.Component) -> Bool:
  match c:
    case S.Component{S.Empty{},_}: True{}
    case _: False{}
def nodes(t: S.Tree) -> U32:
  match t:
    case S.Empty{}: 0
    case S.Leaf{_}: 1
    case S.Branch{_,a,b}: (1 + nodes(a) + nodes(b) : U32)
def body(b: W.Body) -> String:
  W.Body{id,revision,offset,speed,anchored,+tree,+faces,+vertices} = b
  "{\"record_type\":\"body\",\"id\":" ++ word(id) ++
    ",\"revision\":" ++ word(revision) ++ ",\"offset\":" ++ real(offset) ++
    ",\"speed\":" ++ real(speed) ++ ",\"anchored\":" ++ boolean(anchored) ++
    ",\"connected\":" ++ boolean(connected(S.component(tree))) ++
    ",\"cells\":" ++ word(S.count(tree)) ++ ",\"cuboids\":" ++ word(S.leaves(tree)) ++
    ",\"tree_nodes\":" ++ word(nodes(tree)) ++
    ",\"boxes\":" ++ array(box.strings(S.boxes(tree,Nil{}))) ++
    ",\"faces\":" ++ array(face.strings(faces)) ++
    ",\"vertices\":" ++ array(vertex.strings(vertices)) ++ "}"
def bodies(bs: List<&2,W.Body>) -> IO(Unit):
  match bs:
    case Nil{}: IO.print("{\"record_type\":\"complete\"}")
    case b <> rest:
      do IO<Unit>:
        IO.print(body(b))
        bodies(rest)
def emit(w: W.World) -> IO(Unit):
  W.World{bs,cells,fragments,removed,status,next,budget} = w
  do IO<Unit>:
    threads : U32 <- IO.thread_count()
    IO.print("{\"schema\":\"megascene-worker/1\",\"record_type\":\"world\",\"threads\":" ++ word(threads) ++
      ",\"cells\":" ++ word(cells) ++ ",\"fragments\":" ++ word(fragments) ++
      ",\"removed\":" ++ word(removed) ++ ",\"status\":" ++ word(status) ++
      ",\"next_id\":" ++ word(next) ++ ",\"budget\":" ++ word(budget) ++ "}")
    bodies(bs)
