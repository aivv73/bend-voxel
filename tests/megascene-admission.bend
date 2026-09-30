import Base
import ../src/megascene_admission.bend as Admission
import ../src/megascene_scale.bend as Scale

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,message)

def power(n: Nat) -> Scale.Integer:
  match n:
    case 0n: Scale.Integer.one()
    case 1n+p: Scale.Integer.double(power(p))

def integer(negative: Bool, value: U32) -> Admission.Integer:
  Admission.Integer{negative,Scale.Integer.from_u32(32n,value)}

def bits(value: Maybe<&2,F32>, expected: U32) -> IO(Unit):
  match value:
    case None{}: IO.die(Unit,1,"exact integer conversion rejected")
    case Some{value}: check(U32.is_eq(F32.bits(value),expected),"integer conversion bits mismatch")

def rejected(value: Maybe<&2,F32>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit,Unit{})
    case Some{_}: IO.die(Unit,1,"inexact integer conversion accepted")

def main() -> IO(Unit):
  do IO<Unit>:
    bits(Admission.Integer.f32(integer(False{},0)),0)
    bits(Admission.Integer.f32(integer(False{},1)),1065353216)
    bits(Admission.Integer.f32(integer(True{},1)),3212836864)
    bits(Admission.Integer.f32(integer(False{},16777216)),1266679808)
    bits(Admission.Integer.f32(Admission.Integer{False{},power(40n)}),1400897536)
    bits(Admission.Integer.f32(Admission.Integer{True{},power(40n)}),3548381184)
    bits(Admission.Integer.f32(Admission.Integer{False{},Scale.Integer.sub(power(128n),power(104n))}),2139095039)
    rejected(Admission.Integer.f32(integer(False{},16777217)))
    rejected(Admission.Integer.f32(Admission.Integer{False{},power(128n)}))
    IO.print("Megascene admission integer conversions passed")
