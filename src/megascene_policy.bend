import Base
import ./megascene_scale.bend as Scale

def parse.result(result: Maybe<&2,Scale.Integer>) -> IO(Scale.Integer):
  match result:
    case None{}: IO.die(Scale.Integer,2,"policy requires decimal integers")
    case Some{n}: IO.pure(Scale.Integer,n)

def parse(text: String) -> IO(Scale.Integer):
  parse.result(Scale.Integer.read(text))

def checked(valid: Bool, message: String, action: Unit -> IO(Unit)) -> IO(Unit):
  match valid:
    case False{}: IO.die(Unit,2,message)
    case True{}: action(Unit{})

def growth(q: String) -> IO(Unit):
  do IO<Unit>:
    +side : Scale.Integer <- parse(q)
    checked(Scale.Integer.le(Scale.Integer.two(),side),"growth requires q>=2",
      u => IO.print(Scale.Integer.show(Scale.next_growth(side))))

def refinement.result(result: Maybe<&2,Scale.Integer>) -> IO(Unit):
  match result:
    case None{}: IO.print("null")
    case Some{side}: IO.print(Scale.Integer.show(side))

def refinement(low: String, high: String) -> IO(Unit):
  do IO<Unit>:
    +lo : Scale.Integer <- parse(low)
    +hi : Scale.Integer <- parse(high)
    checked(Scale.Integer.le(Scale.Integer.two(),lo) &&
      Bool.not(Scale.Integer.le(hi,lo)),"refinement requires ordered square neighborhood scales",
      u => refinement.result(Scale.midpoint_refinement(lo,hi)))

def stride(count: String) -> IO(Unit):
  do IO<Unit>:
    +n : Scale.Integer <- parse(count)
    checked(Scale.Integer.le(Scale.Integer.four(),n),"history needs at least four neighborhoods",
      u => IO.print(Scale.Integer.show(Scale.history_stride(n))))

def visit.result(result: Scale.Integer & U32) -> IO(Unit):
  (neighborhood,prior) = result
  IO.print("[" ++ Scale.Integer.show(neighborhood) ++ "," ++ U32.show(prior) ++ "]")

def visit.parsed(group: Maybe<&2,U32>, seed: Maybe<&2,U32>, +count: Scale.Integer) -> IO(Unit):
  match group seed:
    case Some{+g} Some{+s}:
      checked((g < 12 : U32) && (U32.is_eq(s,45) || U32.is_eq(s,46)),
        "unsupported history group or seed",u =>
          checked(Scale.Integer.le(Scale.Integer.four(),count),"history needs at least four neighborhoods",
            u => visit.result(Scale.history_visit(g,count,s))))
    case _ _: IO.die(Unit,2,"unsupported history group or seed")

def visit(group: String, count: String, seed: String) -> IO(Unit):
  do IO<Unit>:
    n : Scale.Integer <- parse(count)
    visit.parsed(U32.read(group),U32.read(seed),n)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case _ <> "growth" <> q <> Nil{}: growth(q)
    case _ <> "refinement" <> low <> high <> Nil{}: refinement(low,high)
    case _ <> "stride" <> count <> Nil{}: stride(count)
    case _ <> "visit" <> group <> count <> seed <> Nil{}: visit(group,count,seed)
    case _: IO.die(Unit,2,"usage: megascene-policy growth Q | refinement LOW HIGH | stride COUNT | visit GROUP COUNT SEED")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
