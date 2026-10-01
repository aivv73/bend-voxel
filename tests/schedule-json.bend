import Base
import ../src/schedule_json.bend as J
import ../src/schedule_route.bend as R
import ../src/schedule_policy.bend as P
import ../src/schedule_file.bend as F
import ./schedule-test-io.bend as T

def literals() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- T.check(String.eq(J.object([J.field("phase_offset","null"),J.field("phase",J.quote("ordinary")),J.field("actions","[]")]),
      "{\"actions\":[],\"phase\":\"ordinary\",\"phase_offset\":null}"),"ASCII field prefix order")
    _ : Unit <- T.check(String.eq(J.object([J.field("bool","false"),J.field("quoted",J.quote("0")),J.field("native","0"),J.field("negative","-1"),J.field("float","-0.0")]),
      "{\"bool\":false,\"float\":-0.0,\"native\":0,\"negative\":-1,\"quoted\":\"0\"}"),"JSON value tokens retain their types")
    _ : Unit <- T.check(String.eq(J.array(R.static.frames(4n,0,1,3,False{},"null")),
      "[{\"actions\":[],\"camera\":null,\"frame\":\"0\",\"measured_ordinal\":null,\"phase\":\"startup\",\"picking\":false}," ++
      "{\"actions\":[],\"camera\":null,\"frame\":\"1\",\"measured_ordinal\":null,\"phase\":\"warmup\",\"picking\":false}," ++
      "{\"actions\":[],\"camera\":null,\"frame\":\"2\",\"measured_ordinal\":\"0\",\"phase\":\"ordinary\",\"picking\":false}," ++
      "{\"actions\":[],\"camera\":null,\"frame\":\"3\",\"measured_ordinal\":\"1\",\"phase\":\"ordinary\",\"picking\":false}]"),"complete startup/warmup/measurement event order")
    _ : Unit <- T.check(String.eq(J.array(R.static.frames(1n,120,120,21720,True{},"null")),
      "[{\"actions\":[],\"camera\":null,\"frame\":\"120\",\"measured_ordinal\":null,\"phase\":\"warmup\",\"picking\":false,\"policy_flags\":\"2\"}]"),"performance warmup checkpoint boundary")
    _ : Unit <- T.check(String.eq(J.array(R.static.frames(1n,21720,120,21720,True{},"null")),
      "[{\"actions\":[],\"camera\":null,\"frame\":\"21720\",\"measured_ordinal\":\"21599\",\"phase\":\"ordinary\",\"picking\":false,\"policy_flags\":\"2\"}]"),"performance last frame and completion checkpoint")
    _ : Unit <- T.check(String.eq(P.phase(True{},True{},True{},True{}),"startup") &&
      String.eq(P.phase(False{},True{},True{},True{}),"warmup") &&
      String.eq(P.phase(False{},False{},True{},True{}),"edit"),"phase precedence")
    T.check(Bool.not(R.origin.valid("-0")) && R.origin.valid("0") &&
      R.origin.valid("-8388608") && Bool.not(R.origin.valid("8388609")),"signed decimal origin boundaries")

def hashed(value: Result<&1,&1,U32 & String,U32 & (String & String)>, sha: String, bytes: String) -> IO(Unit):
  match value:
    case Done{(0,(+text,""))}:
      do IO<Unit>:
        _ : Unit <- T.check(String.eq(U32.show(U32.from_nat(String.length(text))),bytes),"schedule byte count")
        digest : Result<&1,&1,U32 & String,U32 & (String & String)> <- Process.run("sha256sum",[],text,1024,10000)
        T.process.result(digest,0,sha ++ "  -\n","","pre-change schedule byte hash")
    case Fail{(_,message)}: IO.die(Unit,1,message)
    case _: IO.die(Unit,1,"schedule generator failed")
def fixture.generate(args: List<&2,String>, sha: String, bytes: String) -> IO(Unit):
  do IO<Unit>:
    result : Result<&1,&1,U32 & String,U32 & (String & String)> <- Process.run("build/megascene-schedule-generator",T.linear(R.append(["--threads","1","--"],args)),"",5000000,30000)
    hashed(result,sha,bytes)
def fixture.row(xs: List<&2,String>) -> IO(Unit):
  match xs:
    case "static" <> a <> b <> c <> d <> sha <> bytes <> Nil{}: fixture.generate(["static",a,b,c,d],sha,bytes)
    case "traversal" <> a <> b <> c <> sha <> bytes <> Nil{}: fixture.generate(["traversal",a,b,c],sha,bytes)
    case _: IO.die(Unit,1,"invalid schedule byte fixture row")
def fixture.rows(lines: List<&2,String>, +count: U32) -> IO(Unit):
  match lines:
    case "complete\t31" <> "" <> Nil{}: T.check(U32.is_eq(count,31),"complete schedule fixture count")
    case line <> rest:
      do IO<Unit>:
        _ : Unit <- T.check((count < 31 : U32),"extra schedule fixtures")
        _ : Unit <- fixture.row(String.split(line,'\t'))
        fixture.rows(rest,(count + 1 : U32))
    case _: IO.die(Unit,1,"incomplete schedule fixtures")
def fixture.header(lines: List<&2,String>) -> IO(Unit):
  match lines:
    case "megascene-schedule-baseline/1" <> rest: fixture.rows(rest,0)
    case _: IO.die(Unit,1,"invalid schedule fixture header")
def invalids(cases: List<&2,List<&2,String>>) -> IO(Unit):
  match cases:
    case Nil{}: IO.pure(Unit,Unit{})
    case args <> rest:
      do IO<Unit>:
        _ : Unit <- T.process("build/megascene-schedule-generator",T.linear(R.append(["--threads","1","--"],args)),2,"","","invalid schedule CLI preserves empty stdout")
        invalids(rest)
def fixture.file(path: String) -> IO(Unit):
  do IO<Unit>:
    text : String <- F.read(path)
    fixture.header(String.split(text,'\n'))
def malformed.fixtures(+path: String,cases: List<&2,String>) -> IO(Unit):
  match cases:
    case Nil{}: IO.pure(Unit,Unit{})
    case text <> rest:
      do IO<Unit>:
        _ : Unit <- T.text.write(path,text)
        _ : Unit <- T.process("build/schedule-json-tests",["--threads","1","--","fixture-check",path],1,"","","malformed schedule fixture rejected")
        malformed.fixtures(path,rest)
def run(root: String) -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- literals()
    small : String <- F.read("tests/fixtures/megascene_schedule_static_prefix.json")
    _ : Unit <- T.process("build/megascene-schedule-generator",["--threads","1","--","static","-320","0","1","static-v1"],0,small,"","complete canonical prefix literal")
    _ : Unit <- invalids([[],["static","-320","0","1"],["static","-320","0","1","static-v1","extra"],
      ["static","-0","0","1","static-v1"],["static","-0320","0","1","static-v1"],
      ["static","nan","0","1","static-v1"],["static","-inf","0","1","static-v1"],
      ["static","-8388609","0","1","static-v1"],["static","-320.0","0","1","static-v1"],
      ["static","-320","00","1","static-v1"],["static","-320","121","1","static-v1"],
      ["static","-320","0","0","static-v1"],["static","-320","0","3601","static-v1"],
      ["static","-320","0","4294967296","static-v1"],["static","-320","0","1","unknown"],
      ["static","-320","120","21601","static-perf-v2"],["static","-320","119","21600","static-perf-v2"],
      ["static","-320","120","3600","static-perf-v2"],["traversal","2","45"],
      ["traversal","0","45","traversal-v2"],["traversal","6","45","traversal-v2"],
      ["traversal","02","45","traversal-v2"],["traversal","2","47","traversal-v2"],
      ["traversal","2","045","traversal-v2"],["traversal","2","45","unknown"]])
    text : String <- F.read("tests/fixtures/megascene_schedule_json_bits.tsv")
    _ : Unit <- fixture.header(String.split(text,'\n'))
    +header : String = "megascene-schedule-baseline/1\n"
    +path : String = root ++ "/schedule-fixture.tsv"
    _ : Unit <- T.text.write(path,"")
    _ : Unit <- T.process("build/schedule-json-tests",["--threads","1","--","fixture-check",path],2,"","invalid runtime artifact input","empty fixture follows bounded reader rejection")
    _ : Unit <- malformed.fixtures(path,[header,
      header ++ "complete\t31\n",header ++ "complete\t32\n",
      header ++ "static\t-320\t0\t1\tstatic-v1\ncomplete\t31\n",
      header ++ "static\t-320\t0\t1\tstatic-v1\t9502b6c2cb4b0bd7abf59fed36ec10fe004b8f0e82cfcf03acc2ea708726889a\t1065\ncomplete\t31\n",
      header ++ "complete\t31\n\nextra\n"])
    IO.print("schedule JSON: 31 frozen byte fixtures, event/policy literals and malformed arguments passed")
def arguments(args: List<String>) -> IO(Unit):
  match args:
    case _ <> "fixture-check" <> path <> Nil{}: fixture.file(path)
    case _ <> root <> Nil{}: run(root)
    case _: IO.die(Unit,2,"usage: schedule-json-tests TEMP_DIRECTORY")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
