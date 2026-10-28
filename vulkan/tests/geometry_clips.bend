import Base
import ../src/exterior.bend as E

def rect(+n: U32) -> E.Rect2:
  E.Rect2{(n % 5 : U32),(n / 5 % 5 : U32),(n / 25 % 5 : U32),(n / 125 : U32)}

def valid(r: E.Rect2) -> Bool:
  E.Rect2{a,b,c,d} = r
  (a < b : U32) && (c < d : U32)

def text(r: E.Rect2) -> String:
  E.Rect2{a,b,c,d} = r
  "[" ++ U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d) ++ "]"

def texts(rs: List<&2,E.Rect2>) -> String:
  match rs:
    case Nil{}: ""
    case r <> Nil{}: text(r)
    case r <> rest: text(r) ++ "," ++ texts(rest)

def maybe_emit(valid: Bool, +a: E.Rect2, +b: E.Rect2) -> IO(Unit):
  match valid:
    case False{}: IO.pure(Unit,Unit{})
    case True{}: IO.print("[" ++ text(a) ++ "," ++ text(b) ++ ",[" ++ texts(E.subtract(a,b)) ++ "]]")

def inner(fuel: Nat, +a: E.Rect2, +j: U32) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+k:
      +b = rect(j)
      do IO<Unit>:
        maybe_emit(valid(a) && valid(b),a,b)
        inner(k,a,(j + 1 : U32))

def outer(fuel: Nat, +i: U32) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+k:
      do IO<Unit>:
        inner(625n,rect(i),0)
        outer(k,(i + 1 : U32))

def main() -> IO(Unit):
  outer(625n,0)
