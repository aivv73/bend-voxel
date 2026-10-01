import Base
import ./megascene_inputs.bend as I
import ./megascene_recipe.bend as Recipe
import ./schedule_points.bend as P
import ./schedule_json.bend as J

def record(+name: String, +seed: String, +side: String, +budget: String, +threads: String, +c: String) -> Result<&2,&2,String,String>:
  do Result<&2,&2,String,String>:
    +s : U32 <- P.number(side)
    seedn : U32 <- P.number(seed)
    _ : U32 <- P.number(budget)
    +t : U32 <- P.number(threads)
    _ : Unit <- I.require((U32.is_eq(t,1) || U32.is_eq(t,6) || U32.is_eq(t,12)))
    _ : Unit <- I.require((U32.is_eq((s % 32 : U32),0) && String.eq(c,"none")))
    +q : U32 = (s / 32 : U32)
    _ : Unit <- I.require(String.eq(name,I.preset(q)))
    d : Recipe.District <- I.district(q,seedn,I.control(c))
    source : List<&2,String> <- I.owners(Recipe.owners(d),1)
    return J.object([J.field("configuration",J.object([J.field("case",J.quote("admission")),J.field("fragment_budget",J.quote(budget)),
      J.field("neighborhoods_per_side",J.number(q)),J.field("preset",J.quote(name)),J.field("seed",J.quote(seed)),
      J.field("side_m",J.quote(side)),J.field("threads",J.quote(threads))])),J.field("owners",J.array(source)),
      J.field("record_type",J.quote("generation_inputs")),J.field("schema",J.quote("megascene-evidence/1"))]) ++ "\n"
def arguments(args: List<String>) -> IO(Unit):
  match args:
    case _ <> name <> +seed <> +side <> budget <> threads <> +c <> "source" <> Nil{}:
      I.emit.source(record(name,seed,side,budget,threads,c),side,seed,c,"none")
    case _ <> name <> seed <> side <> budget <> threads <> c <> Nil{}:
      I.emit(record(name,seed,side,budget,threads,c))
    case _: IO.die(Unit,2,"usage: megascene-admission-inputs PRESET SEED SIDE BUDGET THREADS none [source]")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
