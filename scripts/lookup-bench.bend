import Base
import ../src/world.bend as W
import ../src/platform.bend as P

# A bounded arena can have one anchored body and 64 fragments.
def bodies(n: Nat, +id: U32) -> List<&2,W.Body>:
  match n:
    case 0n: Nil{}
    case 1n+k:
      W.Body{id,U32.to_f32(id),2.0,3.0,Nil{}} <> bodies(k,(id + 1 : U32))
def lookups(n: Nat, +bs: List<&2,W.Body>, +id: U32, sum: F32) -> F32:
  match n:
    case 0n: sum
    case 1n+k:
      W.vec(F32,W.body.find(bs,id),x => y => z =>
        lookups(k,bs,id,(sum + x + y + z : F32)))
def verify(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,"lookup checksum mismatch")
def sample(label: String, bs: List<&2,W.Body>, id: U32, expected: F32) -> IO(Unit):
  do IO<Unit>:
    +start : U32 <- P.micros()
    +sum : F32 <- IO.pure(F32,lookups(19200n,bs,id,0.0))
    end : U32 <- P.micros()
    IO.print(label ++ "," ++ U32.show((end - start : U32)) ++ "," ++ F32.show(sum))
    verify(F32.is_eq(sum,expected))
def main() -> IO(Unit):
  do IO<Unit>:
    sample("empty",Nil{},0,0.0)
    sample("single",bodies(1n,1),1,115200.0)
    sample("head",bodies(65n,1),1,115200.0)
    sample("middle",bodies(65n,1),33,729600.0)
    sample("tail",bodies(65n,1),65,1344000.0)
    sample("missing",bodies(65n,1),0,0.0)
