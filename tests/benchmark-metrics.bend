import Base
import ../src/benchmark_metrics.bend as M
import ../src/schedule_json.bend as J
import ../src/schedule_file.bend as Files
import ../src/schedule_float.bend as F
import ./schedule-test-io.bend as T

def changed(n: Nat, +value: String, xs: List<&2,String>) -> List<&2,String>:
  match n xs:
    case _ Nil{}: Nil{}
    case 0n _ <> rest: value <> rest
    case 1n+p h <> rest: h <> changed(p,value,rest)
def rejected(result: Result<&2,&2,String,List<&2,U32>>) -> Bool:
  match result:
    case Fail{_}: True{}
    case _: False{}
type Mutation is Data:
  Mutation{index: Nat, value: String}
def mutations(xs: List<&2,Mutation>, +row: List<&2,String>) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit,Unit{})
    case Mutation{+n,+value} <> rest:
      do IO<Unit>:
        T.check(rejected(M.record(changed(n,value,row),0)),"reject malformed field " ++ Nat.show(n) ++ "=" ++ value)
        mutations(rest,row)
def rows.rejected(result: Result<&2,&2,String,List<&2,List<&2,U32>>>) -> Bool:
  match result:
    case Fail{_}: True{}
    case _: False{}
def negatives(+source: String) -> IO(Unit):
  +lines = List.take(&2,String,String.lines(source),6n)
  +row = String.split(M.text(lines,0n),',')
  do IO<Unit>:
    mutations([Mutation{0n,"bad"},Mutation{1n,"1"},Mutation{2n,"-1"},Mutation{3n,"0"},Mutation{4n,"4294967296"},Mutation{4n,"abc"},Mutation{9n,"0"},Mutation{9n,"715827883"},Mutation{10n,"11"},Mutation{12n,"0"},Mutation{13n,"73"},Mutation{13n,"0"},Mutation{14n,"5"},Mutation{14n,"0"},Mutation{15n,"0"},Mutation{16n,"0"}],row)
    T.check(rejected(M.record(List.take(&2,String,row,16n),0)),"reject short row")
    T.check(rows.rejected(M.rows(List.take(&2,String,lines,5n),0)),"reject missing cut")
    T.check(rows.rejected(M.rows(List.append(&2,String,lines,[M.text(lines,0n)]),0)),"reject extra cut")
    T.check(rows.rejected(M.rows("" <> lines,0)),"reject blank interior row")
    T.check(rows.rejected(M.rows(M.text(lines,0n) <> M.text(lines,0n) <> List.drop(&2,String,lines,2n),0)),"reject duplicate ordinal")
    T.check(Bool.not(rejected(M.record(changed(12n,"4294967295",row),0))),"wide count product is not wrapped")
    T.check(Bool.not(rejected(M.record(changed(4n,"\"+1_00\"",row),0))),"quoted integer spelling")
    T.check(Bool.not(rejected(M.record(changed(4n," -0_0 ",row),0))),"signed zero spelling")
    T.check(rejected(M.record(changed(4n,"1__0",row),0)),"reject duplicate separator")
def statistics() -> IO(Unit):
  do IO<Unit>:
    value : String <- M.sum(["0.1","0.1","0.1","0.1","0.1","0.1"])
    T.check(String.eq(value,"0x1.3333333333334p-1"),"literal compensated sum bits")
    value : String <- M.median(["0x1p+1","0x1p+0"])
    T.check(String.eq(value,"0x1.8p+0"),"literal even median bits")
    value : String <- M.median(["0x1p+1","0x1p+0","0x1.8p+0"])
    T.check(String.eq(value,"0x1.8p+0"),"literal odd median bits")
    value : String <- M.median(["0x1.fffffffffffffp+1023","0x1.fffffffffffffp+1023"])
    value : String <- M.decimal(value)
    T.check(String.eq(value,"Infinity"),"legacy even median overflow spelling")
def decimal.fixture.parts(parts: List<&2,String>) -> IO(Unit):
  match parts:
    case hex <> +expected <> Nil{}:
      do IO<Unit>:
        actual : String <- M.decimal(hex)
        T.check(String.eq(actual,expected),"decimal fixture " ++ expected)
    case _: IO.die(Unit,1,"malformed decimal fixture")
def decimal.fixtures(xs: List<&2,String>) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit,Unit{})
    case "" <> Nil{}: IO.pure(Unit,Unit{})
    case h <> rest:
      do IO<Unit>:
        decimal.fixture.parts(String.split(h,'\t'))
        decimal.fixtures(rest)
def fixture(+root: String, +name: String) -> IO(Unit):
  do IO<Unit>:
    +source : String <- Files.read(root ++ "/" ++ name ++ ".csv")
    negatives(source)
    +cuts : List<&2,M.Cut> <- M.parse(source)
    expected : String <- Files.read(root ++ "/" ++ name ++ ".cuts.json")
    T.check(String.eq(J.array(M.cuts.json(cuts)) ++ "\n",expected),name ++ " cut bytes")
    value : M.Sample <- M.sample(cuts,"18014398509481985")
    actual : String <- M.sample.json(value)
    expected : String <- Files.read(root ++ "/" ++ name ++ ".sample.json")
    T.check(String.eq(actual ++ "\n",expected),name ++ " sample bytes")
def arguments(args: List<String>) -> IO(Unit):
  match args:
    case _ <> "--schedule-overflow" <> Nil{}:
      do IO<Unit>:
        _ : String <- F.evaluate(F.Add{F.Literal{"0x1.fffffffffffffp+1023"},F.Literal{"0x1.fffffffffffffp+1023"}})
        IO.die(Unit,3,"schedule overflow accepted")
    case _ <> "--schedule-infinity" <> Nil{}:
      do IO<Unit>:
        _ : String <- F.evaluate(F.Literal{"inf"})
        IO.die(Unit,3,"schedule infinity accepted")
    case _ <> +root <> Nil{}:
      do IO<Unit>:
        fixture(root,"ordinary")
        fixture(root,"rounding")
        fixture(root,"varying")
        statistics()
        decimals : String <- Files.read(root ++ "/decimal.tsv")
        decimal.fixtures(String.lines(decimals))
        IO.print("Frozen benchmark numeric fixtures passed")
    case _: IO.die(Unit,1,"expected benchmark fixture directory")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
