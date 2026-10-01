import Base
import ../src/stress_metrics.bend as N
import ../src/megascene_scale.bend as S
import ./schedule-test-io.bend as T

def same(actual: Maybe<&2,String>, expected: String, label: String) -> IO(Unit):
  match actual:
    case None{}: IO.die(Unit,1,"literal rejected " ++ label)
    case Some{value}: T.check(String.eq(value,expected),"literal value " ++ label)
def accepted(+input: String, expected: String) -> IO(Unit):
  do IO<Unit>:
    actual : Maybe<&2,String> <- N.literal(input)
    same(actual,expected,input)
def invalid(actual: Maybe<&2,String>, label: String) -> IO(Unit):
  match actual:
    case None{}: IO.pure(Unit,Unit{})
    case Some{_}: IO.die(Unit,1,"literal accepted " ++ label)
def rejected(values: List<&2,String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case +input <> rest:
      do IO<Unit>:
        actual : Maybe<&2,String> <- N.literal(input)
        invalid(actual,input)
        rejected(rest)
def literals() -> IO(Unit):
  do IO<Unit>:
    accepted("  +1_2.5e-1\t","0x1.4p+0")
    accepted("-.25E+2","-0x1.9p+4")
    accepted("1.","0x1p+0")
    accepted("16777217","0x1.000001p+24")
    accepted("1.0000000000000002","0x1.0000000000001p+0")
    accepted("-0.0","-0x0p+0")
    accepted("-1e-9999","-0x0p+0")
    accepted("5e-324","0x0.0000000000001p-1022")
    accepted(" ١.٢ ","0x1.3333333333333p+0")
    accepted(String.from_list([Chr{194},Chr{160},Chr{217},Chr{161},'.',Chr{217},Chr{162},Chr{194},Chr{160}]),"0x1.3333333333333p+0")
    rejected(["","+","-",".","-.",".e1","1e","1e+","1..0","1__0","_1","1_","1._0",
      "1e_0","1e+_1","1e1_","nan","Inf","-Infinity","0x1p+0","1,2","1 2","1e309","-1e309",
      SCon{'1',SCon{Chr{0},SNil{}}}])
def integer(s: String) -> S.Integer:
  Maybe.default(&2,S.Integer,S.Integer.read(s),S.Integer.zero())
def ratio.check(n: String, d: String, expected: String) -> IO(Unit):
  do IO<Unit>:
    value : String <- N.ratio.hex(integer(n),integer(d))
    T.check(String.eq(value,expected),"exact integer ratio")
def ratios() -> IO(Unit):
  do IO<Unit>:
    ratio.check("9007199254740995","1000","0x1.0624dd2f1a9fdp+43")
    ratio.check("18014398509481985","1000","0x1.0624dd2f1a9fcp+44")
    ratio.check("9007199254740993","1","0x1p+53")
    ratio.check("9007199254740995","1","0x1.0000000000002p+53")
    ratio.check("1","3","0x1.5555555555555p-2")
    ratio.check("0","1000","0x0p+0")
    value : String <- N.ratio(integer("9007199254740995"),integer("1000"))
    T.check(String.eq(value,"9007199254740.994"),"wide ratio decimal")
    value : String <- N.ratio(integer("1"),integer("0"))
    T.check(String.eq(value,"null"),"zero ratio denominator")
    value : String <- N.ratio.hex(N.integer.shift(S.Integer.one(),2000n),N.integer.shift(S.Integer.one(),2001n))
    T.check(String.eq(value,"0x1p-1"),"huge operands retain finite ratio")
    +tiny : S.Integer = N.integer.shift(S.Integer.one(),1075n)
    value : String <- N.ratio.hex(S.Integer.one(),tiny)
    T.check(String.eq(value,"0x0p+0"),"subnormal tie rounds to even zero")
    value : String <- N.ratio.hex(integer("3"),tiny)
    T.check(String.eq(value,"0x0.0000000000002p-1022"),"subnormal tie rounds to even significand")
def values.take(value: Maybe<&2,String>, rest: List<&2,String>) -> IO(List<&2,String>):
  match value:
    case None{}: IO.die(List<&2,String>,1,"invalid numeric test input")
    case Some{value}: IO.pure(List<&2,String>,value <> rest)
def values(xs: List<&2,String>) -> IO(List<&2,String>):
  match xs:
    case Nil{}: IO.pure(List<&2,String>,Nil{})
    case h <> rest:
      do IO<List<&2,String>>:
        h : Maybe<&2,String> <- N.literal(h)
        rest : List<&2,String> <- values(rest)
        values.take(h,rest)
def statistics() -> IO(Unit):
  do IO<Unit>:
    value : String <- N.stats(Nil{},"ms")
    T.check(String.eq(value,"{\"samples\":0,\"p50_ms\":null,\"p95_ms\":null,\"p99_ms\":null,\"max_ms\":null,\"mean_ms\":null,\"total_ms\":0}"),"empty stats")
    xs : List<&2,String> <- values(["2","1"])
    value : String <- N.stats(xs,"ms")
    T.check(String.eq(value,"{\"samples\":2,\"p50_ms\":1.0,\"p95_ms\":2.0,\"p99_ms\":2.0,\"max_ms\":2.0,\"mean_ms\":1.5,\"total_ms\":3.0}"),"nearest rank does not average")
    xs : List<&2,String> <- values(["20","19","18","17","16","15","14","13","12","11","10","9","8","7","6","5","4","3","2","1"])
    value : String <- N.stats(xs,"ms")
    T.check(String.eq(value,"{\"samples\":20,\"p50_ms\":10.0,\"p95_ms\":19.0,\"p99_ms\":20.0,\"max_ms\":20.0,\"mean_ms\":10.5,\"total_ms\":210.0}"),"nearest rank percentiles")
    xs : List<&2,String> <- values(["0.1","0.1","0.1","0.1","0.1","0.1"])
    value : String <- N.stats(xs,"ms")
    T.check(String.eq(value,"{\"samples\":6,\"p50_ms\":0.1,\"p95_ms\":0.1,\"p99_ms\":0.1,\"max_ms\":0.1,\"mean_ms\":0.10000000000000002,\"total_ms\":0.6000000000000001}"),"compensated sum of converted values")
    xs : List<&2,String> <- N.scaled([integer("4294967295"),integer("4294967295")],"1000")
    value : String <- N.stats(xs,"ms")
    T.check(String.eq(value,"{\"samples\":2,\"p50_ms\":4294967.295,\"p95_ms\":4294967.295,\"p99_ms\":4294967.295,\"max_ms\":4294967.295,\"mean_ms\":4294967.295,\"total_ms\":8589934.59}"),"wide converted timing total")
    xs : List<&2,String> <- N.scaled([integer("1048576"),integer("3145728")],"1048576")
    value : String <- N.stats(xs,"mib")
    T.check(String.eq(value,"{\"samples\":2,\"p50_mib\":1.0,\"p95_mib\":3.0,\"p99_mib\":3.0,\"max_mib\":3.0,\"mean_mib\":2.0,\"total_mib\":4.0}"),"upload MiB field names")
    xs : List<&2,String> <- values(["0","-1","-100000","-0.00001","-1e-300"])
    value : String <- N.minimum(xs)
    T.check(String.eq(value,"-100000.0"),"minimum negative offset")
    xs : List<&2,String> <- values(["-0","0"])
    value : String <- N.minimum(xs)
    T.check(String.eq(value,"-0.0"),"minimum preserves first negative zero")
    xs : List<&2,String> <- values(["0","-0"])
    value : String <- N.minimum(xs)
    T.check(String.eq(value,"0.0"),"minimum preserves first positive zero")
    T.check(String.eq(N.identity("-0x0p+0"),"0x0p+0"),"view identity normalizes zero signs")
    xs : List<&2,String> <- values(["1e-300","1e-310","5e-324"])
    value : String <- N.minimum(xs)
    T.check(String.eq(value,"5e-324"),"subnormal minimum")
    value : String <- N.stats(["0x1.fffffffffffffp+1023","0x1.fffffffffffffp+1023"],"ms")
    T.check(String.eq(value,"{\"samples\":2,\"p50_ms\":1.7976931348623157e+308,\"p95_ms\":1.7976931348623157e+308,\"p99_ms\":1.7976931348623157e+308,\"max_ms\":1.7976931348623157e+308,\"mean_ms\":Infinity,\"total_ms\":Infinity}"),"positive timing overflow matches Python")
def main() -> IO(Unit):
  do IO<Unit>:
    literals()
    ratios()
    statistics()
    IO.print("Stress binary64 statistics passed")
