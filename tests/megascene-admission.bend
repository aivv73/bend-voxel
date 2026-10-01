import Base
import ../src/megascene_admission.bend as Admission
import ../src/megascene_scale.bend as Scale
import ../src/megascene_admit.bend as Parser
import ./schedule-test-io.bend as T

def power(n: Nat) -> Scale.Integer:
  match n:
    case 0n: Scale.Integer.one()
    case 1n+p: Scale.Integer.double(power(p))

def integer(negative: Bool, value: U32) -> Admission.Integer:
  Admission.Integer{negative,Scale.Integer.from_u32(32n,value)}

def bits(value: Maybe<&2,F32>, expected: U32) -> IO(Unit):
  match value:
    case None{}: IO.die(Unit,1,"exact integer conversion rejected")
    case Some{value}: T.check(U32.is_eq(F32.bits(value),expected),"integer conversion bits mismatch")

def rejected(value: Maybe<&2,F32>) -> IO(Unit):
  match value:
    case None{}: IO.pure(Unit,Unit{})
    case Some{_}: IO.die(Unit,1,"inexact integer conversion accepted")

def request(extent: String, budget: String, owners: String) -> String:
  "megascene-admission/1 " ++ extent ++ " 1 " ++ budget ++ " " ++ owners ++ " complete"

def bounds(result: Result<&2,&2,String,Admission.Bounds>, cells: U32, surface: List<&2,U32>, vertices: U32, bytes: U32) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,1,message)
    case Done{Admission.Bounds{c,s,v,b}}:
      T.check(U32.is_eq(c,cells) && T.bytes.same(s,surface) && U32.is_eq(v,vertices) && U32.is_eq(b,bytes),"independent admission bounds mismatch")

def accepts(text: String, cells: U32, surface: List<&2,U32>, vertices: U32, bytes: U32) -> IO(Unit):
  bounds(Parser.request(text),cells,surface,vertices,bytes)

def failure(result: Result<&2,&2,String,Admission.Bounds>, reason: String) -> IO(Unit):
  match result:
    case Done{_}: IO.die(Unit,1,"invalid admission accepted")
    case Fail{+message}: T.check(String.contains(message,reason),"unexpected admission rejection: " ++ message)

def rejects(text: String, reason: String) -> IO(Unit): failure(Parser.request(text),reason)

def transport(+text: String) -> IO(Unit):
  do IO<Unit>:
    rejects(text,"invalid admission input")
    T.text.write("build/megascene-admission.request",text)
    T.process("build/megascene-admission-generator",["build/megascene-admission.request"],2,"","invalid admission input","damaged admission worker transport")

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
    accepts(request("320","0","1 1 1 0 0 0 1 1 1"),1,[6],36,2304)
    accepts(request("320","0","1 2 1 0 0 0 2 1 2 2 1 1 0 3 2 1"),6,[16],96,6144)
    accepts(request("320","0","1 3 1 0 0 0 1 1 1 2 2 0 0 3 1 1 2 1 0 0 2 1 1"),3,[18],108,6912)
    accepts(request("320","4294967295","2 1 1 0 0 0 1 1 1 2 1 1 0 0 2 1 1 1 2 0 0 3 1 1"),3,[6,12],108,6912)
    accepts(request("320","4294967295","2 2 1 1 0 0 2 1 1 1 2 0 0 3 1 1 1 1 0 0 0 1 1 1"),3,[12,6],108,6912)
    accepts(request("320","0","0"),0,[],0,0)
    accepts(request("320","0","1 3 1 0 0 0 4 1 4 2 1 1 0 3 2 1 2 1 1 2 3 2 4"),22,[26],156,9984)
    accepts(request("1099511889920","0","1 1 1 1099511627776 0 0 1099511889920 1 1"),262144,[6],36,2304)
    accepts(request("1099511889920","0","1 1 1 -1099511889920 0 0 -1099511627776 1 1"),262144,[6],36,2304)
    rejects(request("320","2048","1 0"),"connected")
    rejects(request("320","2048","1 2 1 0 0 0 1 1 1 2 1 1 0 2 2 1"),"connected")
    rejects(request("320","2048","1 2 1 0 0 0 1 1 1 2 1 1 1 2 2 2"),"connected")
    rejects(request("320","2048","1 2 1 0 0 0 1 1 1 1 0 0 0 1 1 1"),"connected")
    rejects(request("320","2048","1 1 2 0 0 0 1 1 1"),"anchor")
    rejects(request("320","2048","1 1 6 0 0 0 1 1 1"),"material")
    rejects(request("320","2048","1 1 1 0 0 0 0 1 1"),"envelope")
    rejects(request("320","2048","1 1 1 -321 0 0 1 1 1"),"envelope")
    rejects(request("320","2048","1 1 1 0 0 0 1 129 1"),"envelope")
    rejects(request("320","2048","1 3 1 0 0 0 1 1 1 1 0 0 0 1 2 1 2 1 0 0 2 2 1"),"overlapping")
    rejects(request("320","2048","2 1 1 0 0 0 1 1 1 1 1 0 0 0 1 1 1"),"overlapping")
    rejects(request("320","-1","1 1 1 0 0 0 1 1 1"),"fragment budget")
    rejects(request("320","4294967296","1 1 1 0 0 0 1 1 1"),"fragment budget")
    rejects(request("33554432","2048","1 1 1 16777217 0 0 16777218 1 1"),"coordinate")
    rejects(request("33554432","2048","1 1 1 8388608 0 0 8388609 1 1"),"spatial split")
    rejects(request("33554432","2048","1 1 1 0 0 0 65536 1 65536"),"box volume")
    rejects(request("65536","2048","2 1 1 -65536 0 -65536 0 1 -32768 1 1 0 0 0 65536 1 32768"),"world cell sum")
    transport("megascene-admission/1 320 1 0 1 1 1 0 0 0 1 1 1")
    transport(request("320","0","1 1 1 0 0 0 1 1 1") ++ " extra")
    transport(request("320","0","2 1 1 0 0 0 1 1 1"))
    transport(request("10/","0","1 1 1 0 0 0 1 1 1"))
    transport(request("320","0","4294967295 1 1 0 0 0 1 1 1"))
    transport("megascene-admission/2 320 1 0 1 1 1 0 0 0 1 1 1 complete")
    transport(request("0320","0","0"))
    transport(request("320","-0","0"))
    transport("megascene-admission/1 320 0 0 0 complete")
    transport(request("320","0","0") ++ " ")
    transport(" megascene-admission/1 320 1 0 0 complete")
    transport("megascene-admission/1 320  1 0 0 complete")
    T.text.write("build/megascene-admission.request",request("320","0","1 1 1 0 0 0 1 1 1"))
    T.process("build/megascene-admission-generator",["build/megascene-admission.request"],0,"{\"cells\":\"1\",\"surface_rectangle_bounds\":[\"6\"],\"vertex_bound\":\"36\",\"geometry_byte_bound\":\"2304\"}\n","","literal admission worker bytes")
    IO.print("Megascene admission: 9 integer, 9 bounds, 17 geometry/numeric, 12 malformed worker and literal byte checks passed")
