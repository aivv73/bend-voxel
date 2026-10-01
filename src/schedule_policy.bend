import Base
import ./schedule_json.bend as J

def select(-T: Data, flag: Bool, yes: T, no: T) -> T:
  match flag:
    case True{}: yes
    case False{}: no
def phase(start: Bool,warm: Bool,edit: Bool,moving: Bool) -> String:
  match start warm edit moving:
    case True{} _ _ _: "startup"
    case _ True{} _ _: "warmup"
    case _ _ True{} _: "edit"
    case _ _ _ True{}: "motion"
    case _ _ _ _: "ordinary"

def contains(xs: List<&2,U32>,+i: U32) -> Bool:
  match xs:
    case Nil{}: False{}
    case x <> rest: U32.is_eq(x,i) || contains(rest,i)
def preceding(xs: List<&2,U32>,+i: U32) -> U32:
  match xs:
    case Nil{}: 0
    case x <> rest: (Bool.to_u32((i >= x : U32)) + preceding(rest,i) : U32)
def at(n: Nat,xs: List<&2,U32>) -> U32:
  match n xs:
    case 0n x <> _: x
    case 1n+p _ <> rest: at(p,rest)
    case _ Nil{}: 0
def number.result(x: Maybe<&2,U32>) -> IO(U32):
  match x:
    case Some{n}: IO.pure(U32,n)
    case None{}: IO.die(U32,2,"policy requires unsigned decimal integers")
def protocol(+history: Bool) -> String:
  J.object([J.field("version",J.quote("megascene-performance/2")),J.field("query_pairs",J.number(21721)),J.field("ordinary_duration_min_ns",J.quote("10000000000")),J.field("ordinary_count_min",J.number(1000)),J.field("history_group_frames",select(String,history,J.number(1800),"null")),J.field("history_action_offsets",select(String,history,J.array([J.number(0),J.number(180),J.number(360),J.number(540),J.number(720),J.number(732),J.number(1080),J.number(1260),J.number(1440),J.number(1620)]),"null")),J.field("history_actions_per_measured_frame",select(String,history,J.object([J.field("numerator",J.number(1)),J.field("denominator",J.number(180))]),"null")),J.field("history_final_suffix_frames",select(String,history,J.number(179),"null")),J.field("overview_frame",select(String,history,J.number(21661),"null"))])
def rows(n: Nat,+i: U32,+warmup: U32,+performance: Bool,+cuts: List<&2,U32>,+moving: List<&2,U32>,+reviews: List<&2,U32>,+points: List<&2,U32>,+overview: U32) -> List<&2,String>:
  match n:
    case 0n: Nil{}
    case 1n+p:
      +stage = preceding(cuts,i)
      flags = select(U32,performance,(Bool.to_u32(contains(reviews,i)) + 2 * Bool.to_u32(contains(points,i)) + 4 * Bool.to_u32(U32.is_eq(i,overview)) : U32),0)
      changing = (stage > 0 : U32) && (i <= at(U32.to_nat((stage - 1 : U32)),moving) : U32)
      J.object([J.field("phase",J.quote(phase(U32.is_eq(i,0),(i <= warmup : U32),contains(cuts,i),changing))),J.field("policy_flags",J.number(flags))]) <> rows(p,(i + 1 : U32),warmup,performance,cuts,moving,reviews,points,overview)
def numbers.parts(xs: List<&2,String>) -> IO(List<&2,U32>):
  match xs:
    case Nil{}: IO.pure(List<&2,U32>,Nil{})
    case "" <> rest: numbers.parts(rest)
    case x <> rest:
      do IO<List<&2,U32>>:
        n : U32 <- number.result(U32.read(x))
        ns : List<&2,U32> <- numbers.parts(rest)
        return n <> ns
def numbers(xs: String) -> IO(List<&2,U32>): numbers.parts(String.split(xs,','))
def policy(warmup: String,measured: String,performance: String,cuts: String,moving: String,reviews: String,points: String,overview: String) -> IO(Unit):
  do IO<Unit>:
    +w : U32 <- number.result(U32.read(warmup))
    m : U32 <- number.result(U32.read(measured))
    cs : List<&2,U32> <- numbers(cuts)
    ms : List<&2,U32> <- numbers(moving)
    rs : List<&2,U32> <- numbers(reviews)
    ps : List<&2,U32> <- numbers(points)
    o : U32 <- number.result(U32.read(overview))
    IO.print(J.array(rows(U32.to_nat((1 + w + m : U32)),0,w,String.eq(performance,"true"),cs,ms,rs,ps,o)))
