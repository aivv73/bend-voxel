import Base
import ../src/megascene_inputs.bend as I
import ../src/megascene_admission_inputs.bend as A
import ../src/megascene_recipe.bend as R
import ../src/schedule_json.bend as J
import ../src/schedule_file.bend as F
import ./schedule-test-io.bend as T

def float.bits(bits: U32) -> F32:
  U32{word} = bits
  F32{word}
def exact(result: Result<&2,&2,String,String>, expected: String) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,1,message)
    case Done{text}: T.check(String.eq(text,expected),"canonical inputs literal")
def rejected(result: Result<&2,&2,String,String>) -> IO(Unit):
  match result:
    case Fail{_}: IO.pure(Unit,Unit{})
    case Done{_}: IO.die(Unit,1,"accepted invalid input coordinate/material")
def owner.literal(result: Result<&2,&2,String,List<&2,String>>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,1,message)
    case Done{values}: T.check(String.eq(J.array(values),
      "[{\"boxes\":[{\"hi\":[\"3\",\"4\",\"5\"],\"lo\":[\"-1\",\"0\",\"2\"],\"material\":\"2\"}],\"id\":\"1\",\"neighborhood\":null,\"role\":\"terrain\"}," ++
      "{\"boxes\":[{\"hi\":[\"6\",\"2\",\"8\"],\"lo\":[\"5\",\"1\",\"7\"],\"material\":\"4\"}],\"id\":\"2\",\"neighborhood\":\"3\",\"role\":\"irregular\"}]"),"distinct source owner order and types")
def compact.literal(owners: List<&2,R.Owner>) -> IO(Unit):
  match owners:
    case R.Owner{"irregular",Some{0},R.Box{a,_,_} <> _} <>
      R.Owner{"irregular",Some{1},_} <> R.Owner{"irregular",Some{2},_} <>
      R.Owner{"irregular",Some{3},_ <> _ <> _ <> _ <> R.Box{_,b,4} <> Nil{}} <> Nil{}:
      do IO<Unit>:
        _ : Unit <- exact(I.vector(a),"[\"8\",\"24\",\"8\"]")
        exact(I.vector(b),"[\"71\",\"50\",\"71\"]")
    case _: IO.die(Unit,1,"compact source count/owner order")
def literals() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- exact(I.coordinate((0.0 - 8388608.0 : F32)),"\"-8388608\"")
    _ : Unit <- exact(I.coordinate(float.bits(2147483648)),"\"0\"")
    _ : Unit <- rejected(I.coordinate(0.5))
    _ : Unit <- rejected(I.coordinate((0.0 - 1.5 : F32)))
    _ : Unit <- rejected(I.coordinate(8388609.0))
    _ : Unit <- rejected(I.coordinate(float.bits(2139095040)))
    _ : Unit <- rejected(I.coordinate(float.bits(2143289344)))
    _ : Unit <- rejected(I.box(R.box(0.0,1.0,0.0,1.0,0.0,1.0,0)))
    _ : Unit <- rejected(I.box(R.box(0.0,1.0,0.0,1.0,0.0,1.0,6)))
    _ : Unit <- rejected(A.record("small","45","64","2048","6","fill"))
    _ : Unit <- T.process("build/megascene-admission-inputs-generator",["--threads","1","--","small","45","64","2048","6","fill","source"],2,"","","admission control rejection preserves empty stdout")
    _ : Unit <- owner.literal(I.owners([R.Owner{"terrain",None{},[R.box((0.0 - 1.0 : F32),3.0,0.0,4.0,2.0,5.0,2)]},
      R.Owner{"irregular",Some{3},[R.box(5.0,6.0,1.0,2.0,7.0,8.0,4)]}],1))
    _ : Unit <- compact.literal(R.compact(4n,0))
    T.check(String.eq(J.quote(String.from_list([Chr{0},Chr{7},Chr{8},Chr{9},Chr{10},Chr{12},Chr{13},Chr{34},Chr{92},Chr{127},Chr{233},Chr{128512},Chr{57343}])),
      "\"\\u0000\\u0007\\b\\t\\n\\f\\r\\\"\\\\\\u007f\\u00e9\\ud83d\\ude00\\udfff\""),"canonical JSON escapes and surrogate pair")

def captured(result: Result<&1,&1,U32 & String,U32 & (String & String)>, next: String -> IO(Unit)) -> IO(Unit):
  match result:
    case Fail{(_,message)}: IO.die(Unit,1,message)
    case Done{(0,(text,error))}:
      do IO<Unit>:
        _ : Unit <- T.check(String.eq(error,""),"generator stderr")
        next(text)
    case _: IO.die(Unit,1,"input generator failed")
def hash(+text: String, expected: String, bytes: String) -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- T.check(String.eq(U32.show(U32.from_nat(String.length(text))),bytes),"inputs byte count")
    result : Result<&1,&1,U32 & String,U32 & (String & String)> <- Process.run("sha256sum",[],text,1024,10000)
    T.process.result(result,0,expected ++ "  -\n","","inputs SHA256")
def fixture.generate(program: String, args: List<String>, sha: String, bytes: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1,&1,U32 & String,U32 & (String & String)> <- Process.run(program,args,"",524288,10000)
    captured(result,text => hash(text,sha,bytes))
def fixture.row(xs: List<&2,String>, admission: Bool) -> IO(Unit):
  match xs admission:
    case a <> b <> c <> d <> e <> f <> g <> sha <> bytes <> Nil{} False{}:
      fixture.generate("build/megascene-inputs-generator",["--threads","1","--",a,b,c,d,e,f,g],sha,bytes)
    case a <> b <> c <> d <> e <> sha <> bytes <> Nil{} True{}:
      fixture.generate("build/megascene-admission-inputs-generator",["--threads","1","--",a,b,c,d,e,"none"],sha,bytes)
    case _ _: IO.die(Unit,1,"invalid inputs byte fixture row")
def fixture.rows(lines: List<&2,String>, +count: U32, +admission: Bool) -> IO(Unit):
  match lines:
    case "complete\t54" <> "" <> Nil{}: T.check((U32.is_eq(count,54) && Bool.not(admission)),"complete inputs fixture count")
    case "complete\t12" <> "" <> Nil{}: T.check((U32.is_eq(count,12) && admission),"complete admission fixture count")
    case line <> rest:
      do IO<Unit>:
        _ : Unit <- T.check((count < Bool.pick(U32,admission,12,54) : U32),"extra inputs fixtures")
        _ : Unit <- fixture.row(String.split(line,'\t'),admission)
        fixture.rows(rest,(count + 1 : U32),admission)
    case _: IO.die(Unit,1,"incomplete inputs byte fixtures")
def fixture.header(lines: List<&2,String>) -> IO(Unit):
  match lines:
    case "megascene-inputs-baseline/1" <> rest: fixture.rows(rest,0,False{})
    case "megascene-admission-inputs-baseline/1" <> rest: fixture.rows(rest,0,True{})
    case _: IO.die(Unit,1,"invalid inputs fixture header")
def invalid(+program: String, +args: List<&2,String>) -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- T.process(program,T.linear(List.append(&2,String,["--threads","1","--"],args)),2,"","","invalid inputs CLI")
    T.process(program,T.linear(List.append(&2,String,["--threads","1","--"],List.append(&2,String,args,["source"]))),2,"","","invalid paired inputs CLI")
def invalid.case(args: List<&2,String>) -> IO(Unit):
  match args:
    case "admission" <> rest: invalid("build/megascene-admission-inputs-generator",List.append(&2,String,rest,["none"]))
    case args: invalid("build/megascene-inputs-generator",args)
def invalids(cases: List<&2,List<&2,String>>) -> IO(Unit):
  match cases:
    case Nil{}: IO.pure(Unit,Unit{})
    case args <> rest:
      do IO<Unit>:
        _ : Unit <- invalid.case(args)
        invalids(rest)
def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- literals()
    small : String <- F.read("tests/fixtures/megascene_inputs_small_seed45.json")
    _ : Unit <- exact(I.record("small","45","64","64","none","2048","none"),small)
    admission : String <- F.read("tests/fixtures/megascene_admission_inputs_small_seed45.json")
    _ : Unit <- exact(A.record("small","45","64","2048","6","none"),admission)
    _ : Unit <- invalids([[],["small","45","64","64","none","2048"],
      ["small","45","64","64","none","2048","none","extra"],
      ["unknown","45","64","64","none","2048","none"],["large","45","64","64","none","2048","none"],
      ["small","47","64","64","none","2048","none"],["small","045","64","64","none","2048","none"],
      ["small","45","65","64","none","2048","none"],["scale-6","45","192","192","none","2048","none"],
      ["small","45","64","00","none","2048","none"],["small","45","64","-1","none","2048","none"],
      ["small","45","64","64","base","2048","none"],["small","45","64","64","bad\"control","2048","none"],
      ["small","45","64","64","none","4294967296","none"],["small","45","64","64","none","-1","none"],
      ["small","45","64","64","none","1.0","none"],["small","45","64","64","none","2048","unknown"],
      ["small","45","64","64","fill","2048","compact-reference"],["large","45","128","128","none","2048","mixed-world"],
      ["admission"],["admission","small","45","64","2048"],
      ["admission","small","45","64","2048","0"],["admission","small","45","64","2048","2"],
      ["admission","small","45","64","2048","06"],["admission","small","45","64","2048","4294967296"],
      ["admission","small","45","64","-1","6"],["admission","small","45","65","2048","6"]])
    text : String <- F.read("tests/fixtures/megascene_inputs_bits.tsv")
    _ : Unit <- fixture.header(String.split(text,'\n'))
    text : String <- F.read("tests/fixtures/megascene_admission_inputs_bits.tsv")
    _ : Unit <- fixture.header(String.split(text,'\n'))
    IO.print("ALL 66 CANONICAL INPUTS AND MALFORMED/LITERAL CHECKS PASSED")
