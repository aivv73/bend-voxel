import Base
import ./benchmark_metrics.bend as M
import ./schedule_float.bend as F
import ./schedule_json.bend as J
import ./megascene_scale.bend as S
import ./frozen_admission.bend as A
import ./stress_contract.bend as C

type FloatState is Data:
  Whole{digit: Bool, previous: Bool}
  Fraction{digit: Bool, previous: Bool}
  ExponentStart{}
  ExponentSign{}
  ExponentDigits{}

def float.accept(state: FloatState) -> Bool:
  match state:
    case Whole{digit,_}: digit
    case Fraction{digit,_}: digit
    case ExponentDigits{}: True{}
    case _: False{}
def float.digit(state: FloatState) -> FloatState:
  match state:
    case Whole{_,_}: Whole{True{},True{}}
    case Fraction{_,_}: Fraction{True{},True{}}
    case _: ExponentDigits{}
def float.separator(state: FloatState) -> Bool:
  match state:
    case Whole{_,previous}: previous
    case Fraction{_,previous}: previous
    case ExponentDigits{}: True{}
    case _: False{}
def float.step(state: FloatState, +c: Char) -> Maybe<&2,FloatState>:
  match state c:
    case Whole{digit,_} '.': Some{Fraction{digit,False{}}}
    case Whole{True{},_} 'e': Some{ExponentStart{}}
    case Whole{True{},_} 'E': Some{ExponentStart{}}
    case Fraction{True{},_} 'e': Some{ExponentStart{}}
    case Fraction{True{},_} 'E': Some{ExponentStart{}}
    case ExponentStart{} '+': Some{ExponentSign{}}
    case ExponentStart{} '-': Some{ExponentSign{}}
    case _ _: Bool.pick(Maybe<&2,FloatState>,Char.is_digit(c),Some{float.digit(state)},None{})
def float.scan(s: String, +state: FloatState) -> Maybe<&2,String>:
  match s:
    case SNil{}: Bool.pick(Maybe<&2,String>,float.accept(state),Some{""},None{})
    case SCon{'_',SCon{+c,rest}}:
      do Maybe<&2,String>:
        _ : Unit <- M.guard(float.separator(state) && Char.is_digit(c))
        tail : String <- float.scan(rest,float.digit(state))
        return SCon{c,tail}
    case SCon{+c,rest}:
      do Maybe<&2,String>:
        state : FloatState <- float.step(state,c)
        tail : String <- float.scan(rest,state)
        return SCon{c,tail}
def float.sign(s: String) -> Maybe<&2,String>:
  match s:
    case SCon{'+',rest}: float.scan(rest,Whole{False{},False{}})
    case SCon{'-',rest}:
      do Maybe<&2,String>:
        tail : String <- float.scan(rest,Whole{False{},False{}})
        return "-" ++ tail
    case _: float.scan(s,Whole{False{},False{}})
def literal.parsed(value: Maybe<&2,String>) -> IO(Maybe<&2,String>):
  match value:
    case None{}: IO.pure(Maybe<&2,String>,None{})
    case Some{s}: F.literal.finite(s)
def unicode.characters(s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{Chr{c},rest}: SCon{Chr{A.unicode.codepoint(c)},unicode.characters(rest)}
def normalize(+s: String) -> String:
  Maybe.default(&2,String,A.unicode.normalize(s),unicode.characters(s))
def literal.syntax.choose(primary: Maybe<&2,String>, s: String) -> Maybe<&2,String>:
  match primary:
    case Some{value}: Some{value}
    case None{}: Maybe.bind(&2,String,String,A.unicode.normalize(s),s => float.sign(String.trim(s)))
def literal.syntax(+s: String) -> Maybe<&2,String>:
  literal.syntax.choose(float.sign(String.trim(unicode.characters(s))),s)
def literal(s: String) -> IO(Maybe<&2,String>):
  literal.parsed(literal.syntax(s))
def identity(s: String) -> String:
  match s:
    case "-0x0p+0": "0x0p+0"
    case _: s

def exponent.key(+s: String) -> String:
  +value = U32.show(M.exponent(s))
  String.repeat("0",Nat.sub(4n,String.length(value))) ++ value
def magnitude.key(parts: List<&2,String>) -> String:
  match parts:
    case "0x0" <> _: "0000"
    case mantissa <> exponent <> Nil{}: exponent.key(exponent) ++ mantissa
    case _: ""
def magnitude(+s: String) -> String:
  Bool.pick(String,String.starts_with(s,"-"),String.drop(s,1n),s)
def less.sign(negative_a: Bool, negative_b: Bool, +ka: String, +kb: String) -> Bool:
  match negative_a negative_b:
    case True{} False{}: True{}
    case False{} True{}: False{}
    case True{} True{}: String.is_le(kb,ka)
    case False{} False{}: String.is_le(ka,kb)
def less.keys(a: String, b: String, +ka: String, +kb: String) -> Bool:
  less.sign(String.starts_with(a,"-") && Bool.not(String.eq(ka,"0000")),
    String.starts_with(b,"-") && Bool.not(String.eq(kb,"0000")),ka,kb)
def less(a: String, b: String) -> Bool:
  +a = a
  +b = b
  less.keys(a,b,magnitude.key(String.split(magnitude(a),'p')),magnitude.key(String.split(magnitude(b),'p')))
def decimal(+s: String) -> IO(String):
  match s:
    case SCon{'-',rest}:
      do IO<String>:
        value : String <- M.decimal(rest)
        return "-" ++ value
    case _: M.decimal(s)

def integer.shift(value: S.Integer, n: Nat) -> S.Integer:
  match n:
    case 0n: value
    case 1n+p: S.Integer.double(integer.shift(value,p))
def integer.hex.step(value: S.Integer & S.Integer, acc: String,
  next: S.Integer -> String -> String) -> String:
  (q,r) = value
  next(q,SCon{J.hex(S.Integer.to_u32(r)),acc})
def integer.hex.go(fuel: Nat, value: S.Integer, acc: String) -> String:
  match fuel value:
    case _ S.ScaleZero{}: acc
    case 0n _: acc
    case 1n+p _: integer.hex.step(S.Integer.divmod(value,S.Integer.from_u32(5n,16)),acc,
      q => acc => integer.hex.go(p,q,acc))
def integer.hex(+value: S.Integer) -> String:
  match value:
    case S.ScaleZero{}: "0"
    case _: integer.hex.go(1n+S.Integer.bits(value),value,"")
def integer.odd(value: S.Integer) -> Bool:
  match value:
    case S.ScaleZero{}: False{}
    case S.ScaleBit{low,_}: low
def rounded.cmp(+q: S.Integer, comparison: Cmp) -> S.Integer:
  match comparison:
    case LT{}: q
    case EQ{}: Bool.pick(S.Integer,integer.odd(q),S.Integer.inc(q),q)
    case GT{}: S.Integer.inc(q)
def rounded(denominator: S.Integer, qr: S.Integer & S.Integer) -> S.Integer:
  (+q,r) = qr
  rounded.cmp(q,S.Integer.cmp(S.Integer.double(r),denominator))

type BinaryExponent is Data:
  Positive{power: Nat}
  Negative{power: Nat}
def exponent.lower(power: Nat) -> BinaryExponent:
  match power:
    case 0n: Negative{1n}
    case 1n+p: Positive{p}
def exponent.positive(power: Nat, enough: Bool) -> BinaryExponent:
  match enough:
    case True{}: Positive{power}
    case False{}: exponent.lower(power)
def exponent.negative(+delta: Nat, enough: Bool) -> BinaryExponent:
  Negative{Bool.pick(Nat,enough,delta,1n+delta)}
def ratio.exponent.bits(+n: S.Integer, +d: S.Integer, +nb: Nat, +db: Nat, positive: Bool) -> BinaryExponent:
  match positive:
    case True{}:
      +delta = Nat.sub(nb,db)
      exponent.positive(delta,S.Integer.le(integer.shift(d,delta),n))
    case False{}:
      +delta = Nat.sub(db,nb)
      exponent.negative(delta,S.Integer.le(d,integer.shift(n,delta)))
def ratio.exponent(+n: S.Integer, +d: S.Integer, +nb: Nat, +db: Nat) -> BinaryExponent:
  ratio.exponent.bits(n,d,nb,db,Nat.is_ge(nb,db))
def ratio.shifted(n: S.Integer, +d: S.Integer, shift: Nat, negative: Bool) -> IO(String):
  +q = rounded(d,S.Integer.divmod(n,d))
  F.host("0x" ++ integer.hex(q) ++ "p" ++ Bool.pick(String,negative,"-","+") ++ Nat.show(shift),2)
def ratio.positive(n: S.Integer, d: S.Integer, +power: Nat, large: Bool) -> IO(String):
  match large:
    case True{}: ratio.shifted(n,integer.shift(d,Nat.sub(power,52n)),Nat.sub(power,52n),False{})
    case False{}: ratio.shifted(integer.shift(n,Nat.sub(52n,power)),d,Nat.sub(52n,power),True{})
def ratio.normal(n: S.Integer, d: S.Integer, exponent: BinaryExponent) -> IO(String):
  match exponent:
    case Positive{+power}:
      ratio.positive(n,d,power,Nat.is_ge(power,52n))
    case Negative{power}:
      +shift = Nat.min(1074n,52n+power)
      ratio.shifted(integer.shift(n,shift),d,shift,True{})
def ratio.zeros(+n: S.Integer, +d: S.Integer, zero_n: Bool, zero_d: Bool) -> IO(String):
  match zero_n zero_d:
    case _ True{}: IO.pure(String,"invalid")
    case True{} False{}: IO.pure(String,"0x0p+0")
    case False{} False{}: ratio.normal(n,d,ratio.exponent(n,d,S.Integer.bits(n),S.Integer.bits(d)))
def ratio.hex(+n: S.Integer, +d: S.Integer) -> IO(String):
  ratio.zeros(n,d,S.Integer.eq(n,S.Integer.zero()),S.Integer.eq(d,S.Integer.zero()))
def ratio.value(s: String) -> IO(String):
  match s:
    case "invalid": IO.pure(String,"null")
    case _: decimal(s)
def ratio(numerator: S.Integer, denominator: S.Integer) -> IO(String):
  do IO<String>:
    value : String <- ratio.hex(numerator,denominator)
    ratio.value(value)
def scaled.by(values: List<&2,S.Integer>, +divisor: S.Integer) -> IO(List<&2,String>):
  match values:
    case Nil{}: IO.pure(List<&2,String>,Nil{})
    case h <> rest:
      do IO<List<&2,String>>:
        h : String <- ratio.hex(h,divisor)
        tail : List<&2,String> <- scaled.by(rest,divisor)
        return h <> tail
def scaled(values: List<&2,S.Integer>, divisor: String) -> IO(List<&2,String>):
  scaled.by(values,Maybe.default(&2,S.Integer,S.Integer.read(divisor),S.Integer.one()))

def statistic.keys(+suffix: String) -> List<&2,String>:
  ["p50_" ++ suffix,"p95_" ++ suffix,"p99_" ++ suffix,"max_" ++ suffix,"mean_" ++ suffix,"total_" ++ suffix]
def statistic.fields(keys: List<&2,String>, values: List<&2,String>) -> IO(List<&2,String>):
  match keys values:
    case key <> keys value <> values:
      do IO<List<&2,String>>:
        value : String <- decimal(value)
        tail : List<&2,String> <- statistic.fields(keys,values)
        return J.field(key,value) <> tail
    case _ _: IO.pure(List<&2,String>,Nil{})
def sum.code(values: List<&2,String>) -> String:
  match values:
    case Nil{}: ""
    case value <> rest: value ++ " add " ++ sum.code(rest)
def sum.checked(naive: String, values: List<&2,String>) -> IO(String):
  match naive:
    case "inf": IO.pure(String,"inf")
    case _: M.sum(values)
def sum(+values: List<&2,String>) -> IO(String):
  do IO<String>:
    naive : String <- F.host("0 " ++ sum.code(values),2)
    sum.checked(naive,values)
def stats.nonempty(+values: List<&2,String>, suffix: String, +count: Nat) -> IO(String):
  +ordered = List.sort(String,less,values)
  do IO<String>:
    +total : String <- sum(values)
    mean : String <- F.host(F.encode(F.Div{F.Literal{total},F.Literal{Nat.show(count)}}),2)
    fields : List<&2,String> <- statistic.fields(statistic.keys(suffix),
      [M.text(ordered,C.rank(count,50n)),M.text(ordered,C.rank(count,95n)),M.text(ordered,C.rank(count,99n)),
       M.text(ordered,Nat.sub(count,1n)),mean,total])
    return M.object(J.field("samples",Nat.show(count)) <> fields)
def stats.empty(+suffix: String) -> String:
  M.object([J.field("samples","0"),J.field("p50_" ++ suffix,"null"),J.field("p95_" ++ suffix,"null"),
    J.field("p99_" ++ suffix,"null"),J.field("max_" ++ suffix,"null"),J.field("mean_" ++ suffix,"null"),J.field("total_" ++ suffix,"0")])
def stats(+values: List<&2,String>, suffix: String) -> IO(String):
  match values:
    case Nil{}: IO.pure(String,stats.empty(suffix))
    case _: stats.nonempty(values,suffix,List.length(&2,String,values))
def minimum.ordered(values: List<&2,String>) -> IO(String):
  match values:
    case Nil{}: IO.pure(String,"null")
    case value <> _: decimal(value)
def minimum(values: List<&2,String>) -> IO(String): minimum.ordered(List.sort(String,less,values))
