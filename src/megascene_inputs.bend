import Base
import ./math.bend as R
import ./megascene_recipe.bend as Recipe
import ./schedule_points.bend as P
import ./schedule_json.bend as J
import ./megascene_source.bend as Source

def require(ok: Bool) -> Result<&2,&2,String,Unit>:
  match ok:
    case True{}: Done{Unit{}}
    case False{}: Fail{"invalid generation inputs"}

def coordinate.absolute(+v: F32, negative: Bool) -> Result<&2,&2,String,String>:
  do Result<&2,&2,String,String>:
    _ : Unit <- require(((v >= 0.0) && (v <= 8388608.0) : F32))
    +n : U32 = F32.to_u32(v)
    _ : Unit <- require(F32.is_eq(U32.to_f32(n),v))
    return J.quote(Bool.pick(String,negative,"-","") ++ U32.show(n))
def coordinate(+v: F32) -> Result<&2,&2,String,String>:
  coordinate.absolute(F32.abs(v),(v < 0.0 : F32))
def vector(v: R.Vec) -> Result<&2,&2,String,String>:
  R.Vec{x,y,z} = v
  do Result<&2,&2,String,String>:
    x : String <- coordinate(x)
    y : String <- coordinate(y)
    z : String <- coordinate(z)
    return J.array([x,y,z])
def box(b: Recipe.Box) -> Result<&2,&2,String,String>:
  Recipe.Box{lo,hi,+m} = b
  do Result<&2,&2,String,String>:
    _ : Unit <- require(((m >= 1) && (m <= 5) : U32))
    lo : String <- vector(lo)
    hi : String <- vector(hi)
    return J.object([J.field("hi",hi),J.field("lo",lo),J.field("material",J.number(m))])
def boxes(bs: List<&2,Recipe.Box>) -> Result<&2,&2,String,List<&2,String>>:
  match bs:
    case Nil{}: Done{Nil{}}
    case b <> rest:
      do Result<&2,&2,String,List<&2,String>>:
        b : String <- box(b)
        rest : List<&2,String> <- boxes(rest)
        return b <> rest
def neighborhood(n: Maybe<&2,U32>) -> String:
  match n:
    case None{}: "null"
    case Some{n}: J.number(n)
def owners(bs: List<&2,Recipe.Owner>, +id: U32) -> Result<&2,&2,String,List<&2,String>>:
  match bs:
    case Nil{}: Done{Nil{}}
    case Recipe.Owner{role,n,source} <> rest:
      do Result<&2,&2,String,List<&2,String>>:
        source : List<&2,String> <- boxes(source)
        rest : List<&2,String> <- owners(rest,(id + 1 : U32))
        return J.object([J.field("boxes",J.array(source)),J.field("id",J.number(id)),
          J.field("neighborhood",neighborhood(n)),J.field("role",J.quote(role))]) <> rest
def preset(q: U32) -> String:
  match q:
    case 2: "small"
    case 4: "large"
    case q: "scale-" ++ U32.show(q)
def control(s: String) -> Maybe<&2,Recipe.Control>:
  match s:
    case "none": Some{Recipe.Plain{}}
    case "base": None{}
    case s: Recipe.control(s)
def district.checked(d: Maybe<&2,Recipe.District>) -> Result<&2,&2,String,Recipe.District>:
  match d:
    case None{}: Fail{"invalid generation district"}
    case Some{d}: Done{d}
def district(q: U32, seed: U32, c: Maybe<&2,Recipe.Control>) -> Result<&2,&2,String,Recipe.District>:
  match c:
    case None{}: Fail{"invalid generation control"}
    case Some{c}: district.checked(Recipe.district(q,seed,c))
def record(+name: String, +seed: String, +side: String, +envelope: String, +c: String, +budget: String, +diagnostic: String) -> Result<&2,&2,String,String>:
  do Result<&2,&2,String,String>:
    +s : U32 <- P.number(side)
    seedn : U32 <- P.number(seed)
    _ : U32 <- P.number(envelope)
    _ : U32 <- P.number(budget)
    _ : Unit <- require(U32.is_eq((s % 32 : U32),0))
    +q : U32 = (s / 32 : U32)
    _ : Unit <- require(String.eq(name,preset(q)))
    +d : Recipe.District <- district(q,seedn,control(c))
    _ : Unit <- require((String.eq(diagnostic,"none") ||
      ((String.eq(diagnostic,"compact-reference") || String.eq(diagnostic,"mixed-world")) && U32.is_eq(q,2) && String.eq(c,"none"))))
    source : List<&2,String> <- owners(Bool.pick(List<&2,Recipe.Owner>,String.eq(diagnostic,"compact-reference"),Recipe.compact(4n,0),Recipe.owners(d)),1)
    return J.object([J.field("configuration",J.object([
      J.field("control",Bool.pick(String,String.eq(c,"none"),"null",J.quote(c))),J.field("envelope_side_m",J.quote(envelope)),
      J.field("fragment_budget",J.quote(budget)),J.field("preset",J.quote(name)),J.field("seed",J.quote(seed)),J.field("side_m",J.quote(side))])),
      J.field("owners",J.array(source)),J.field("record_type",J.quote("generation_inputs")),J.field("schema",J.quote("megascene-evidence/1"))]) ++ "\n"
def emit(result: Result<&2,&2,String,String>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{text}: IO.write(text)
def emit.source(result: Result<&2,&2,String,String>, side: String, seed: String, +c: String, diagnostic: String) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{text}:
      q : U32 = (Maybe.default(&2,U32,U32.read(side),0) / 32 : U32)
      cname : String = Bool.pick(String,String.eq(diagnostic,"compact-reference"),"compact-reference",
        Bool.pick(String,String.eq(c,"none"),"base",c))
      do IO<Unit>:
        _ : Unit <- IO.write(text)
        Source.args(["megascene-source",U32.show(q),seed,cname])
def arguments(args: List<String>) -> IO(Unit):
  match args:
    case _ <> name <> +seed <> +side <> envelope <> +c <> budget <> +diagnostic <> "source" <> Nil{}:
      emit.source(record(name,seed,side,envelope,c,budget,diagnostic),side,seed,c,diagnostic)
    case _ <> name <> seed <> side <> envelope <> c <> budget <> diagnostic <> Nil{}: emit(record(name,seed,side,envelope,c,budget,diagnostic))
    case _: IO.die(Unit,2,"usage: megascene-inputs PRESET SEED SIDE ENVELOPE CONTROL BUDGET DIAGNOSTIC")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
