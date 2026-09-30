import Base
import ./math.bend as R
import ./megascene_recipe.bend as Recipe

def vec(v: R.Vec) -> String:
  R.Vec{x,y,z} = v
  "[" ++ F32.show(x) ++ "," ++ F32.show(y) ++ "," ++ F32.show(z) ++ "]"
def box(b: Recipe.Box) -> String:
  Recipe.Box{lo,hi,m} = b
  "{\"lo\":" ++ vec(lo) ++ ",\"hi\":" ++ vec(hi) ++ ",\"material\":" ++ U32.show(m) ++ "}"
def boxes.tail(bs: List<&2,Recipe.Box>) -> String:
  match bs:
    case Nil{}: "]"
    case b <> rest: "," ++ box(b) ++ boxes.tail(rest)
def boxes(bs: List<&2,Recipe.Box>) -> String:
  match bs:
    case Nil{}: "[]"
    case b <> rest: "[" ++ box(b) ++ boxes.tail(rest)
def neighborhood(n: Maybe<&2,U32>) -> String:
  match n:
    case None{}: "null"
    case Some{x}: U32.show(x)
def emit(bs: List<&2,Recipe.Owner>) -> IO(Unit):
  match bs:
    case Nil{}: IO.print("{\"record_type\":\"complete\"}")
    case Recipe.Owner{role,n,source} <> rest:
      do IO<Unit>:
        IO.print("{\"record_type\":\"owner\",\"role\":\"" ++ role ++ "\",\"neighborhood\":" ++
          neighborhood(n) ++ ",\"boxes\":" ++ boxes(source) ++ "}")
        emit(rest)
def generate(d: Maybe<&2,Recipe.District>) -> IO(Unit):
  match d:
    case None{}: IO.die(Unit,2,"unsupported district scale or seed")
    case Some{+d}:
      Recipe.District{+q,seed,+c} = d
      do IO<Unit>:
        IO.print("{\"record_type\":\"source\",\"schema\":\"megascene-source/1\",\"side\":" ++
          U32.show(q) ++ ",\"seed\":" ++ U32.show(seed) ++ ",\"control\":\"" ++ Recipe.control.name(c) ++
          "\",\"envelope_cells\":" ++ U32.show(Recipe.envelope(q,c)) ++ "}")
        emit(Recipe.owners(d))
def parsed(q: Maybe<&2,U32>, seed: Maybe<&2,U32>, c: Maybe<&2,Recipe.Control>) -> IO(Unit):
  match q seed c:
    case Some{q} Some{seed} Some{c}: generate(Recipe.district(q,seed,c))
    case _ _ _: IO.die(Unit,2,"unsupported source arguments")
def args(xs: List<String>) -> IO(Unit):
  match xs:
    case _ <> q <> seed <> c <> Nil{}: parsed(U32.read(q),U32.read(seed),Recipe.control(c))
    case _: IO.die(Unit,2,"usage: megascene-source SIDE SEED CONTROL")
def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<String> <- IO.args()
    args(xs)
