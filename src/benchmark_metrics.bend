import Base
import ./schedule_float.bend as F
import ./schedule_json.bend as J
import ./megascene_scale.bend as S

type Cut is Data:
  Cut{counts: List<&2,U32>}
type Sample is Data:
  Sample{cuts: List<&2,Cut>, ms: List<&2,String>}

def names() -> List<&2,String>:
  ["ordinal","body_id","removed_cells","carve_us","connectivity_us","surface_us","finalize_us","audit_us","cuboids","candidate_faces","tree_nodes","cuboid_candidates","face_checks","face_clips","output_faces","reference_faces"]
def stages() -> List<&2,String>: ["carve","connectivity","surface","finalize","init","edit"]
def get(xs: List<&2,U32>, n: Nat) -> U32: Maybe.default(&2,U32,List.get(&2,U32,xs,n),0)
def text(xs: List<&2,String>, n: Nat) -> String: Maybe.default(&2,String,List.get(&2,String,xs,n),"")
def exhibit.index(n: U32) -> String:
  match n:
    case 0: "Suzanne"
    case 1: "Oculus"
    case _: "Twist"
def exhibit(n: U32) -> String: exhibit.index((n % 3 : U32))
def require(ok: Bool) -> Result<&2,&2,String,Unit>:
  match ok:
    case True{}: Done{Unit{}}
    case False{}: Fail{"Inconsistent face-builder sample"}
def number.parsed(parsed: Maybe<&2,U32>) -> Result<&2,&2,String,U32>:
  match parsed:
    case Some{n}: Done{n}
    case None{}: Fail{"Invalid profiler counts"}
def unquote(+s: String) -> String:
  Bool.pick(String,String.starts_with(s,"\"") && String.ends_with(s,"\""),String.take(String.drop(s,1n),Nat.sub(String.length(s),2n)),s)
def guard(ok: Bool) -> Maybe<&2,Unit>:
  match ok:
    case True{}: Some{Unit{}}
    case False{}: None{}
def digits(s: String, +previous: Bool) -> Maybe<&2,String>:
  match s:
    case SNil{}: Some{""}
    case SCon{'_',SCon{+c,rest}}:
      do Maybe<&2,String>:
        _ : Unit <- guard(previous && Char.is_digit(c))
        digits(SCon{c,rest},False{})
    case SCon{+c,rest}:
      do Maybe<&2,String>:
        _ : Unit <- guard(Char.is_digit(c))
        tail : String <- digits(rest,True{})
        return SCon{c,tail}
def integer.sign(s: String) -> Maybe<&2,String>:
  match s:
    case SCon{'+',rest}: digits(rest,False{})
    case SCon{'-',rest}:
      do Maybe<&2,String>:
        +value : String <- digits(rest,False{})
        _ : Unit <- guard(String.eq(String.join(String.split(value,'0'),""),""))
        return value
    case _: digits(s,False{})
def integer(s: String) -> Maybe<&2,String>: integer.sign(String.trim(unquote(String.trim(s))))
def number(s: String) -> Result<&2,&2,String,U32>:
  number.parsed(Maybe.bind(&2,String,U32,integer(s),U32.read))
def argument(s: String) -> Result<&2,&2,String,U32>:
  number.parsed(Maybe.bind(&2,String,U32,integer.sign(String.trim(s)),U32.read))
def numbers(xs: List<&2,String>) -> Result<&2,&2,String,List<&2,U32>>:
  match xs:
    case Nil{}: Done{Nil{}}
    case h <> rest:
      do Result<&2,&2,String,List<&2,U32>>:
        h : U32 <- number(h)
        rest : List<&2,U32> <- numbers(rest)
        return h <> rest
def record(xs: List<&2,String>, ordinal: U32) -> Result<&2,&2,String,List<&2,U32>>:
  match xs:
    case +tag <> +rest:
      do Result<&2,&2,String,List<&2,U32>>:
        _ : Unit <- require(String.eq(unquote(tag),"face_build"))
        _ : Unit <- require(Nat.is_eq(List.length(&2,String,rest),16n))
        +v : List<&2,U32> <- numbers(rest)
        +boxes : U32 = get(v,8n)
        +candidates : U32 = get(v,9n)
        +leaves : U32 = get(v,11n)
        +checks : U32 = get(v,12n)
        _ : Unit <- require(U32.is_eq(get(v,0n),ordinal) && (boxes <= 715827882 : U32) && U32.is_eq(candidates,(6 * boxes : U32)) &&
          (get(v,13n) <= checks : U32) && ((leaves > (4294967295 / U32.max(candidates,1) : U32)) || (checks <= (leaves * candidates : U32)) : U32) &&
          U32.is_ne(get(v,2n),0) && U32.is_ne(boxes,0) && U32.is_ne(checks,0) && U32.is_ne(get(v,13n),0) && U32.is_ne(get(v,14n),0) && U32.is_ne(get(v,15n),0))
        return v
    case _: Fail{"Unexpected profiler row"}
def rows.finish(done: Bool) -> Result<&2,&2,String,List<&2,List<&2,U32>>>:
  match done:
    case True{}: Done{Nil{}}
    case False{}: Fail{"Expected six profiled cuts"}
def rows(xs: List<&2,String>, +ordinal: U32) -> Result<&2,&2,String,List<&2,List<&2,U32>>>:
  match xs:
    case Nil{}: rows.finish(U32.is_eq(ordinal,6))
    case "" <> Nil{}: rows(Nil{},ordinal)
    case h <> rest:
      do Result<&2,&2,String,List<&2,List<&2,U32>>>:
        _ : Unit <- require((ordinal < 6 : U32))
        row : List<&2,U32> <- record(String.split(h,','),ordinal)
        tail : List<&2,List<&2,U32>> <- rows(rest,(ordinal + 1 : U32))
        return row <> tail

def pad3(+n: U32) -> String:
  Bool.pick(String,(n < 10 : U32),"00",Bool.pick(String,(n < 100 : U32),"0","")) ++ U32.show(n)
def milliseconds.parts(q: String, +r: U32) -> String:
  q ++ "." ++ Bool.pick(String,U32.is_eq(r,0),"0",Bool.pick(String,U32.is_eq((r % 100 : U32),0),U32.show((r / 100 : U32)),
    Bool.pick(String,U32.is_eq((r % 10 : U32),0),String.take(pad3(r),2n),pad3(r))))
def milliseconds(+n: U32) -> String: milliseconds.parts(U32.show((n / 1000 : U32)),(n % 1000 : U32))
def cuts(xs: List<&2,List<&2,U32>>) -> List<&2,Cut>:
  match xs:
    case Nil{}: Nil{}
    case v <> rest: Cut{v} <> cuts(rest)

def sum.finish(+hi: String, +lo: String) -> IO(String):
  match lo:
    case "0x0p+0": IO.pure(String,hi)
    case _: F.evaluate(F.Add{F.Literal{hi},F.Literal{lo}})
def sum.error(+next: String, hi: String, lo: String, value: String, larger: Bool, continuation: String -> String -> IO(String)) -> IO(String):
  +a = {F.Literal{hi} : F.Expr}
  +b = {F.Literal{value} : F.Expr}
  +n = {F.Literal{next} : F.Expr}
  do IO<String>:
    error : String <- F.evaluate(Bool.pick(F.Expr,larger,F.Add{F.Sub{a,n},b},F.Add{F.Sub{b,n},a}))
    lo : String <- F.evaluate(F.Add{F.Literal{lo},F.Literal{error}})
    continuation(next,lo)
def sum.go(xs: List<&2,String>, +hi: String, lo: String) -> IO(String):
  match xs:
    case Nil{}: sum.finish(hi,lo)
    case +value <> rest:
      do IO<String>:
        next : String <- F.evaluate(F.Add{F.Literal{hi},F.Literal{value}})
        greatest : String <- F.evaluate(F.Max{F.Literal{hi},F.Literal{value}})
        sum.error(next,hi,lo,value,String.eq(greatest,hi),hi => lo => sum.go(rest,hi,lo))
def sum(xs: List<&2,String>) -> IO(String): sum.go(xs,"0x0p+0","0x0p+0")

def exponent(s: String) -> U32:
  match s:
    case SCon{'-',rest}: (1024 - Maybe.default(&2,U32,U32.read(rest),0) : U32)
    case SCon{'+',rest}: (1024 + Maybe.default(&2,U32,U32.read(rest),0) : U32)
    case _: 0
def key.parts(parts: List<&2,String>) -> String:
  match parts:
    case "0x0" <> _: "0000"
    case mantissa <> e <> Nil{}: U32.show(exponent(e)) ++ mantissa
    case _: ""
def key(s: String) -> String: key.parts(String.split(s,'p'))
def less(a: String, b: String) -> Bool: String.is_le(key(a),key(b))
def median.result(+a: String, b: String, even: Bool) -> IO(String):
  match even:
    case False{}: IO.pure(String,a)
    case True{}: F.host(F.encode(F.Div{F.Add{F.Literal{b},F.Literal{a}},F.Literal{"2"}}),2)
def median.middle(+xs: List<&2,String>, +half: Nat, even: Bool) -> IO(String):
  median.result(text(xs,half),text(xs,Nat.sub(half,1n)),even)
def median(+xs: List<&2,String>) -> IO(String):
  +n = List.length(&2,String,xs)
  median.middle(List.sort(String,less,xs),Nat.div(n,2n),Nat.is_eq(Nat.mod(n,2n),0n))

def checked(result: Result<&1,&1,U32 & String,U32 & (String & String)>) -> IO(String):
  match result:
    case Done{(0,(out,_))}: IO.pure(String,out)
    case _: IO.die(String,1,"benchmark system operation failed")
def decimal.args(n: Nat, +value: String) -> List<String>:
  match n:
    case 0n: Nil{}
    case 1n+p:
      +p = p
      Nat.show(Nat.sub(17n,p)) <> value <> decimal.args(p,value)
def decimal.expand(negative: Bool, +n: Nat, +digits: String) -> String:
  match negative:
    case True{}: "0." ++ String.repeat("0",Nat.sub(n,1n)) ++ digits
    case False{}:
      Bool.pick(String,Nat.is_ge(n,String.length(digits)),digits ++ String.repeat("0",Nat.sub(n,String.length(digits))) ++ ".0",
        String.take(digits,n) ++ "." ++ String.drop(digits,n))
def decimal.scientific(+mantissa: String, +e: String, +negative: Bool, +n: Nat) -> String:
  Bool.pick(String,Bool.pick(Bool,negative,Nat.is_ge(n,5n),Nat.is_ge(n,16n)),mantissa ++ "e" ++ e,
    decimal.expand(negative,Bool.pick(Nat,negative,n,1n+n),String.join(String.split(mantissa,'.'),"")))
def decimal.exponent(mantissa: String, +e: String) -> String:
  match e:
    case SCon{'-',rest}: decimal.scientific(mantissa,e,True{},Maybe.default(&2,Nat,Nat.read(rest),0n))
    case SCon{'+',rest}: decimal.scientific(mantissa,e,False{},Maybe.default(&2,Nat,Nat.read(rest),0n))
    case _: mantissa
def decimal.parts(+s: String, parts: List<&2,String>) -> String:
  match parts:
    case +fixed <> Nil{}: Bool.pick(String,String.contains(fixed,"."),fixed,fixed ++ ".0")
    case mantissa <> e <> Nil{}: decimal.exponent(mantissa,e)
    case _: s
def decimal.normalize(+s: String) -> String: decimal.parts(s,String.split(s,'e'))
def decimal.same(same: Bool, candidate: String, next: Unit -> IO(String)) -> IO(String):
  match same:
    case True{}: IO.pure(String,decimal.normalize(candidate))
    case False{}: next(Unit{})
def decimal.choose(xs: List<&2,String>, +value: String) -> IO(String):
  match xs:
    case Nil{}: IO.die(String,1,"benchmark decimal rounding failed")
    case +candidate <> rest:
      do IO<String>:
        actual : String <- F.host(F.encode(F.Literal{candidate}),2)
        decimal.same(String.eq(actual,value),candidate,_ => decimal.choose(rest,value))
def decimal.finite(+value: String) -> IO(String):
  do IO<String>:
    result : Result<&1,&1,U32 & String,U32 & (String & String)> <- Process.run("env","LC_ALL=C" <> "printf" <> String.repeat("%.*g\n",17n) <> decimal.args(17n,value),"",8192,10000)
    printed : String <- checked(result)
    decimal.choose(String.lines(printed),value)
def decimal(value: String) -> IO(String):
  match value:
    case "inf": IO.pure(String,"Infinity")
    case _: decimal.finite(value)
def fields(keys: List<&2,String>, values: List<&2,U32>) -> List<&2,String>:
  match keys values:
    case k <> ks v <> vs: J.field(k,U32.show(v)) <> fields(ks,vs)
    case _ _: Nil{}
def float.fields(keys: List<&2,String>, values: List<&2,String>) -> IO(List<&2,String>):
  match keys values:
    case k <> ks v <> vs:
      do IO<List<&2,String>>:
        v : String <- decimal(v)
        tail : List<&2,String> <- float.fields(ks,vs)
        return J.field(k,v) <> tail
    case _ _: IO.pure(List<&2,String>,Nil{})
def object(fields: List<&2,String>) -> String: "{" ++ J.fields(fields)
def ms.fields(keys: List<&2,String>, values: List<&2,U32>) -> List<&2,String>:
  match keys values:
    case k <> ks v <> vs: J.field(k,milliseconds(v)) <> ms.fields(ks,vs)
    case _ _: Nil{}
def cut.json(cut: Cut) -> String:
  Cut{+counts} = cut
  +ordinal = get(counts,0n)
  ms = ms.fields(["carve_ms","connectivity_ms","surface_ms","finalize_ms","audit_ms"],List.take(&2,U32,List.drop(&2,U32,counts,3n),5n))
  object(List.append(&2,String,fields(names(),counts),J.field("exhibit",J.quote(exhibit(ordinal))) <> J.field("cut_number",U32.show((ordinal / 3 + 1 : U32))) <> ms))
def cuts.json(xs: List<&2,Cut>) -> List<&2,String>:
  match xs:
    case Nil{}: Nil{}
    case h <> rest: cut.json(h) <> cuts.json(rest)

def parse.result(result: Result<&2,&2,String,List<&2,List<&2,U32>>>) -> IO(List<&2,Cut>):
  match result:
    case Fail{message}: IO.die(List<&2,Cut>,1,message)
    case Done{rows}: IO.pure(List<&2,Cut>,cuts(rows))
def parse(s: String) -> IO(List<&2,Cut>): parse.result(rows(String.lines(s),0))
def column(xs: List<&2,Cut>, +i: Nat) -> List<&2,String>:
  match xs:
    case Nil{}: Nil{}
    case Cut{counts} <> rest: milliseconds(get(counts,3n+i)) <> column(rest,i)
def totals(n: Nat, +i: Nat, +xs: List<&2,Cut>) -> IO(List<&2,String>):
  match n:
    case 0n: IO.pure(List<&2,String>,Nil{})
    case 1n+p:
      do IO<List<&2,String>>:
        value : String <- sum(column(xs,i))
        tail : List<&2,String> <- totals(p,1n+i,xs)
        return value <> tail
def initial.parsed(n: Maybe<&2,S.Integer>) -> IO(String):
  match n:
    case None{}: IO.die(String,1,"Invalid initialization row")
    case Some{n}: F.evaluate(F.Literal{S.Integer.show(n) ++ "e-3"})
def sample(+xs: List<&2,Cut>, initial: String) -> IO(Sample):
  do IO<Sample>:
    +stages : List<&2,String> <- totals(4n,0n,xs)
    init : String <- initial.parsed(Maybe.bind(&2,String,S.Integer,integer.sign(String.trim(initial)),S.Integer.read))
    edit : String <- sum(stages)
    return Sample{xs,List.append(&2,String,stages,[init,edit])}
def sample.json(value: Sample) -> IO(String):
  Sample{cuts,ms} = value
  do IO<String>:
    ms : List<&2,String> <- float.fields(stages(),ms)
    return object([J.field("ms",object(ms)),J.field("cuts",J.array(cuts.json(cuts)))])
