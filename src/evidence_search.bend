import Base
import ./evidence_value.bend as E
import ./megascene_scale.bend as Scale
import ./evidence_thresholds.bend as T

def choose(+condition: Bool, yes: Unit -> E.Value, no: Unit -> E.Value) -> E.Value:
  match condition:
    case True{}: yes(Unit{})
    case False{}: no(Unit{})

def choose_text(+condition: Bool, yes: Unit -> String, no: Unit -> String) -> String:
  match condition:
    case True{}: yes(Unit{})
    case False{}: no(Unit{})

def choose_list(+condition: Bool, yes: Unit -> List<&2,E.Value>, no: Unit -> List<&2,E.Value>) -> List<&2,E.Value>:
  match condition:
    case True{}: yes(Unit{})
    case False{}: no(Unit{})

def cases() -> List<&2,String>:
  ["static","traversal","picking","localized","support","history"]

def dimensions() -> List<&2,String>:
  ["interactive","time_budget","capacity","observed_capacity_failure"]

def one_of(+text: String, choices: List<&2,String>) -> Bool:
  match choices:
    case Nil{}: False{}
    case choice <> +rest: String.eq(text,choice) || one_of(text,rest)

def select(~C: Data, ~predicate: C -> E.Value -> Bool, +context: C, rows: List<&2,E.Value>) -> List<&2,E.Value>:
  match rows:
    case Nil{}: Nil{}
    case +row <> +rest: List.filter.put(E.Value,row,select(~C,~predicate,context,rest),predicate(context,row))

def map(~C: Data, ~function: C -> E.Value -> E.Value, +context: C, rows: List<&2,E.Value>) -> List<&2,E.Value>:
  match rows:
    case Nil{}: Nil{}
    case +row <> +rest: function(context,row) <> map(~C,~function,context,rest)

def any(~C: Data, ~predicate: C -> E.Value -> Bool, +context: C, rows: List<&2,E.Value>) -> Bool:
  match rows:
    case Nil{}: False{}
    case +row <> +rest: predicate(context,row) || any(~C,~predicate,context,rest)

def all(~C: Data, ~predicate: C -> E.Value -> Bool, +context: C, rows: List<&2,E.Value>) -> Bool:
  match rows:
    case Nil{}: True{}
    case +row <> +rest: predicate(context,row) && all(~C,~predicate,context,rest)

def contains(rows: List<&2,E.Value>, +value: E.Value) -> Bool:
  any(~E.Value,~(value => row => E.eq(row,value)),value,rows)

def unique(rows: List<&2,E.Value>, +result: List<&2,E.Value>) -> List<&2,E.Value>:
  match rows:
    case Nil{}: result
    case +row <> +rest:
      unique(rest,Bool.pick(List<&2,E.Value>,contains(result,row),result,List.append(&2,E.Value,result,[row])))

def preset(+q: U32) -> String:
  match q:
    case 2: "small"
    case 4: "large"
    case q: "scale-" ++ U32.show(q)

def point_fields(+kind: String, +q: U32, +seed: E.Value, +threads: E.Value, +diagnostic: E.Value, +route: E.Value) -> E.Value:
  +default = Bool.pick(String,E.truth(diagnostic),E.text(diagnostic) ++ "-" ++ kind ++ "-v1",
    kind ++ Bool.pick(String,one_of(kind,["traversal","picking"]) ||
      (String.eq(kind,"history") && Bool.not(U32.is_eq(q,2) || U32.is_eq(q,4))),"-v2","-v1"))
  E.object([("case",E.string(kind)),("q",E.number(U32.show(q))),("preset",E.string(preset(q))),
    ("seed",seed),("threads",threads),("resolution",E.string("1920x1080")),("profile",E.string("full")),
    ("fragment_budget",E.string("2048")),("warmup",E.string("120")),("frames",E.string("3600")),
    ("diagnostic",diagnostic),("schedule",Bool.pick(E.Value,E.truth(route),route,E.string(default)))])

def point_parsed(parsed: Maybe<&2,U32>, +kind: String, +seed: E.Value, +threads: E.Value, +diagnostic: E.Value, +route: E.Value) -> E.Value:
  match parsed:
    case Some{+q}:
      Bool.pick(E.Value,((q >= 2) && (q <= 5) : U32),point_fields(kind,q,seed,threads,diagnostic,route),
        E.Error{"square neighborhood scale unsupported: supported q=2..5; no physical capacity claim"})
    case None{}: E.Error{"square neighborhood scale unsupported: supported q=2..5; no physical capacity claim"}

def point_read(+kind: String, +value: E.Value, +seed: E.Value, +threads: E.Value, +diagnostic: E.Value, +route: E.Value) -> E.Value:
  match value:
    case E.Number{text}: point_parsed(U32.read(text),kind,seed,threads,diagnostic,route)
    case _: E.Error{"square neighborhood scale unsupported: supported q=2..5; no physical capacity claim"}

def point(+kind: String, +q: U32) -> E.Value:
  point_fields(kind,q,E.number("45"),E.number("6"),E.Null{},E.Null{})

def label(+row: E.Value, +dimension: String) -> E.Value:
  E.get(E.get(row,"labels"),dimension)

def labels(+report: E.Value) -> E.Value:
  +cause = E.text(E.get(E.get(report,"termination"),"cause"))
  +passing = String.eq(cause,"normal_exit") &&
    String.eq(E.text(E.get(E.get(report,"qualified_capacity"),"status")),"pass")
  +capacity = Bool.pick(String,passing,"pass","inconclusive")
  +interactive = Bool.pick(String,passing,
    Bool.pick(String,String.eq(E.text(E.get(E.get(report,"interactive_pass"),"status")),"pass"),"pass",
      Bool.pick(String,String.eq(E.text(E.get(E.get(report,"responsiveness"),"status")),"fail"),"fail:responsiveness","inconclusive")),"inconclusive")
  +time = Bool.pick(String,passing,"pass",Bool.pick(String,
    one_of(cause,["startup_deadline","completion_watchdog","case_deadline","campaign_deadline"]),"fail:" ++ cause,"inconclusive"))
  +allocation = Bool.pick(String,passing,"pass",Bool.pick(String,String.eq(cause,"allocation_error") &&
    String.eq(E.text(E.get(E.get(report,"observed_capacity_failure"),"status")),"inconclusive"),"fail:allocation_error","inconclusive"))
  E.object([("capacity",E.string(capacity)),("interactive",E.string(interactive)),
    ("time_budget",E.string(time)),("observed_capacity_failure",E.string(allocation))])

def outcome_status(+status: String, ids: List<&2,E.Value>, +reason: String) -> E.Value:
  E.object([("status",E.string(status)),("attempts",E.Array{ids}),("reason",E.string(reason))])

def field_problem(+row: E.Value, +name: String) -> E.Value:
  Bool.pick(E.Value,E.has(row,name),E.Null{},E.Error{"missing field:" ++ name})

def first_problem(+left: E.Value, right: E.Value) -> E.Value:
  Bool.pick(E.Value,E.is_null(left),right,left)

def ids_problem(rows: List<&2,E.Value>) -> E.Value:
  match rows:
    case Nil{}: E.Null{}
    case row <> rest: first_problem(field_problem(row,"attempt_id"),ids_problem(rest))

def label_problem(rows: List<&2,E.Value>, +dimension: String) -> E.Value:
  match rows:
    case Nil{}: E.Null{}
    case +row <> rest:
      first_problem(field_problem(row,"labels"),first_problem(field_problem(E.get(row,"labels"),dimension),
        label_problem(rest,dimension)))

def outcome_for(+rows: List<&2,E.Value>, +dimension: String, +simulation: Bool) -> E.Value:
  +ids = map(~Unit,~(u => row => E.get(row,"attempt_id")),Unit{},rows)
  +values = map(~String,~(dimension => row => label(row,dimension)),dimension,rows)
  +observed = select(~Unit,~(u => value => Bool.not(String.eq(E.text(value),"inconclusive"))),Unit{},values)
  +fingerprints = unique(map(~Unit,~(u => row => E.get(row,"workload_fingerprint")),Unit{},select(~String,~(dimension => row => Bool.not(String.eq(E.text(label(row,dimension)),"inconclusive"))),dimension,rows)),Nil{})
  +needed = Bool.pick(U32,String.eq(dimension,"observed_capacity_failure"),2,3)
  choose(List.is_empty(&2,E.Value,rows),
    +u =>
      E.object([("status",E.string("untested")),("attempts",E.Array{Nil{}})]),
    +u =>
      choose(any(~Unit,~(u => row => E.truth(E.get(row,"synthetic"))),Unit{},rows) && Bool.not(simulation),
        +u =>
          outcome_status("excluded",ids,"synthetic attempt cannot establish a measured endpoint"),
        +u =>
          choose(Bool.not(U32.is_eq(E.count(ids),E.count(unique(ids,Nil{})))) || (E.count(fingerprints) > 1 : U32),
            +u =>
              outcome_status("unstable",ids,"attempt or workload identity differs"),
            +u =>
              choose(contains(fingerprints,E.Null{}),
                +u =>
                  outcome_status("observed",ids,"frozen workload or actual inventory identity unavailable"),
                +u =>
                  choose((E.count(unique(observed,Nil{})) > 1 : U32),
                    +u =>
                      outcome_status("unstable",ids,"mixed pass/fail or failure causes"),
                    +u =>
                      choose(any(~Unit,~(u => value => String.eq(E.text(value),"inconclusive")),Unit{},values),
                        +u =>
                          outcome_status("unstable",ids,"incomplete or unqualified evidence"),
                        +u =>
                          choose((E.count(rows) >= needed : U32) && Bool.not(List.is_empty(&2,E.Value,observed)),
                            +u =>
                              E.object([("status",E.string("confirmed")),("result",E.at(observed,0)),
                                ("attempts",E.Array{List.take(&2,E.Value,ids,U32.to_nat(needed))}),
                                ("evidence_count",E.number(U32.show(needed)))]),
                            +u =>
                              E.object([("status",E.string("observed")),("result",Bool.pick(E.Value,
                                List.is_empty(&2,E.Value,observed),E.string("inconclusive"),E.at(observed,0))),
                                ("attempts",E.Array{ids})]))))))))

def outcome_checked(+rows: List<&2,E.Value>, +dimension: String, +simulation: Bool) -> E.Value:
  +synthetic = any(~Unit,~(u => row => E.truth(E.get(row,"synthetic"))),Unit{},rows) && Bool.not(simulation)
  +problem = first_problem(Bool.pick(E.Value,synthetic,E.Null{},label_problem(rows,dimension)),ids_problem(rows))
  Bool.pick(E.Value,E.is_null(problem),outcome_for(rows,dimension,simulation),problem)

def events_problem(events: List<&2,E.Value>, +reassessment: Bool) -> E.Value:
  match events:
    case Nil{}: E.Null{}
    case +event <> rest:
      first_problem(field_problem(event,"kind"),first_problem(Bool.pick(E.Value,reassessment &&
        String.eq(E.text(E.get(event,"kind")),"reassessment"),first_problem(field_problem(event,"attempt_id"),
          field_problem(event,"observed")),E.Null{}),events_problem(rest,reassessment)))

def attempt_events_problem(events: List<&2,E.Value>, +points: Bool) -> E.Value:
  match events:
    case Nil{}: E.Null{}
    case +event <> rest:
      first_problem(Bool.pick(E.Value,String.eq(E.text(E.get(event,"kind")),"attempt"),
        first_problem(Bool.pick(E.Value,points,field_problem(event,"point"),E.Null{}),field_problem(event,"attempt_id")),
        E.Null{}),attempt_events_problem(rest,points))
def admitted_problem(parsed: Maybe<&2,U32>) -> E.Value:
  match parsed:
    case Some{+q}: Bool.pick(E.Value,((q >= 2) && (q <= 5) : U32),E.Null{},
      E.Error{"square neighborhood scale unsupported: supported q=2..5; no physical capacity claim"})
    case None{}: E.Error{"square neighborhood scale unsupported: supported q=2..5; no physical capacity claim"}

def scale_problem(value: E.Value) -> E.Value:
  match value:
    case E.Number{text}: admitted_problem(U32.read(text))
    case _: E.Error{"square neighborhood scale unsupported: supported q=2..5; no physical capacity claim"}

def spec_problem(+spec: E.Value) -> E.Value:
  choose(E.has(spec,"case"),
    +u => choose(one_of(E.text(E.get(spec,"case")),cases()),
      +u => first_problem(field_problem(spec,"seed"),choose(E.eq(E.get(spec,"seed"),E.number("45")),
        +u => first_problem(field_problem(spec,"threads"),choose(E.eq(E.get(spec,"threads"),E.number("6")),
          +u => first_problem(field_problem(spec,"diagnostic"),choose(E.is_null(E.get(spec,"diagnostic")),
            +u => first_problem(field_problem(spec,"schedule"),first_problem(field_problem(spec,"q"),
              scale_problem(E.get(spec,"q")))),+u => E.Null{})),+u => E.Null{})),+u => E.Null{})),
      +u => E.Null{}),
    +u => E.Error{"missing field:case"})

def specs_problem(events: List<&2,E.Value>) -> E.Value:
  match events:
    case Nil{}: E.Null{}
    case +event <> rest:
      first_problem(Bool.pick(E.Value,String.eq(E.text(E.get(event,"kind")),"attempt"),
        spec_problem(E.get(event,"point")),E.Null{}),specs_problem(rest))

def kind_is(+event: E.Value, +kind: String) -> Bool:
  E.eq(E.get(event,"kind"),E.string(kind))

def events_of(+events: List<&2,E.Value>, +kind: String) -> List<&2,E.Value>:
  select(~String,~(kind => event => kind_is(event,kind)),kind,events)

def last_matching(events: List<&2,E.Value>, +kind: String, +identifier: E.Value, +result: E.Value) -> E.Value:
  match events:
    case Nil{}: result
    case +event <> rest: last_matching(rest,kind,identifier,Bool.pick(E.Value,
      kind_is(event,kind) && E.eq(E.get(event,"attempt_id"),identifier),event,result))

def reassessments(events: List<&2,E.Value>, result: E.Value) -> E.Value:
  E.Array{events_of(events,"reassessment")}

def observed_for(+updated: E.Value, +identifier: E.Value) -> E.Value:
  E.get(last_matching(E.array(updated),"reassessment",identifier,E.Null{}),"observed")

def all_attempts(+events: List<&2,E.Value>) -> List<&2,E.Value>:
  +updated = reassessments(events,E.object(Nil{}))
  map(~E.Value,~(updated => +event => E.merge(event,observed_for(updated,E.get(event,"attempt_id")))),updated,select(~Unit,~(u => event => String.eq(E.text(E.get(event,"kind")),"attempt")),Unit{},events))

def attempts(+events: List<&2,E.Value>, +spec: E.Value) -> List<&2,E.Value>:
  select(~E.Value,~(spec => event => E.eq(E.get(event,"point"),spec)),spec,all_attempts(events))

def point_key(+index: U32, pairs: List<&2,E.Value>) -> String:
  match pairs:
    case Nil{}: ""
    case +pair <> +rest:
      choose_text(E.eq(E.number(U32.show(index)),E.get(pair,"event_index")),
        +u =>
          E.text(E.get(pair,"key")),
        +u =>
          point_key(index,rest))
def group(events: List<&2,E.Value>, +updated: E.Value, +keys: List<&2,E.Value>, +index: U32, +result: E.Value) -> E.Value:
  match events:
    case Nil{}: result
    case +event <> +rest:
      choose(String.eq(E.text(E.get(event,"kind")),"attempt"),
        +u =>
          +spec = E.get(event,"point")
          +key = point_key(index,keys)
          +previous = E.get(result,key)
          +entry = Bool.pick(E.Value,E.is_null(previous),
            E.object([("point",spec),("attempts",E.Array{Nil{}})]),previous)
          +observed = E.merge(event,observed_for(updated,E.get(event,"attempt_id")))
          group(rest,updated,keys,(index + 1 : U32),E.put(result,key,E.put(entry,"attempts",
            E.Array{List.append(&2,E.Value,E.array(E.get(entry,"attempts")),[observed])}))),
        +u =>
          group(rest,updated,keys,(index + 1 : U32),result))
def outcomes(+rows: List<&2,E.Value>, names: List<&2,String>, +simulation: Bool) -> List<&2,E.Field()>:
  match names:
    case Nil{}: Nil{}
    case +name <> +rest: (name,outcome_checked(rows,name,simulation)) <> outcomes(rows,rest,simulation)

def entries(rows: List<&2,E.Field()>, +events: List<&2,E.Value>, +simulation: Bool) -> List<&2,E.Field()>:
  match rows:
    case Nil{}: Nil{}
    case (key,+entry) <> +rest:
      +attempts = E.array(E.get(entry,"attempts"))
      +ids = map(~Unit,~(u => row => E.get(row,"attempt_id")),Unit{},attempts)
      +diagnostics = select(~E.Value,~(+context => +event => String.eq(E.text(E.get(event,"kind")),"diagnostic_assessment") &&
        contains(E.array(context),E.get(event,"attempt_id"))),E.Array{ids},events)
      (key,E.merge(entry,E.object([("outcomes",E.object(outcomes(attempts,dimensions(),simulation))),
        ("diagnostic_assessments",E.Array{diagnostics})]))) <> entries(rest,events,simulation)

def object_values(fields: List<&2,E.Field()>) -> List<&2,E.Value>:
  match fields:
    case Nil{}: Nil{}
    case (_,value) <> +rest: value <> object_values(rest)

def read_word(result: Maybe<&2,U32>) -> U32:
  match result:
    case Some{number}: number
    case None{}: 0

def q(+entry: E.Value) -> U32:
  read_word(U32.read(E.text(E.get(E.get(entry,"point"),"q"))))

def primary(+entry: E.Value, +kind: String) -> Bool:
  +spec = E.get(entry,"point")
  String.eq(E.text(E.get(spec,"case")),kind) && E.eq(E.get(spec,"seed"),E.number("45")) &&
    E.eq(E.get(spec,"threads"),E.number("6")) && E.is_null(E.get(spec,"diagnostic"))

def order(a: E.Value, b: E.Value) -> Bool:
  (q(a) <= q(b) : U32)

def canonical_primary(+entry: E.Value, +kind: String) -> Bool:
  primary(entry,kind) && E.eq(E.get(E.get(entry,"point"),"schedule"),E.get(point(kind,q(entry)),"schedule"))

def confirmed(+entry: E.Value, +dimension: String, +passing: Bool) -> Bool:
  +result = E.get(E.get(entry,"outcomes"),dimension)
  String.eq(E.text(E.get(result,"status")),"confirmed") &&
    Bool.pick(Bool,passing,String.eq(E.text(E.get(result,"result")),"pass"),
      String.starts_with(E.text(E.get(result,"result")),"fail:"))

def last_result(result: Maybe<&2,E.Value>) -> E.Value:
  match result:
    case None{}: E.Null{}
    case Some{row}: row

def last(rows: List<&2,E.Value>) -> E.Value:
  last_result(List.last(&2,E.Value,rows))

def bound(+entry: E.Value, +dimension: String) -> E.Value:
  choose(E.is_null(entry),
    +u =>
      E.Null{},
    +u =>
      +outcome = E.get(E.get(entry,"outcomes"),dimension)
      +ids = E.array(E.get(outcome,"attempts"))
      +inventories = map(~Unit,~(u => row => E.get(row,"inventory")),Unit{},select(~E.Value,~(context => row => contains(E.array(context),E.get(row,"attempt_id"))),E.Array{ids},E.array(E.get(entry,"attempts"))))
      E.object([("point",E.get(entry,"point")),("outcome",outcome),("inventories",E.Array{inventories})]))
def nonmonotonic_passes(+failure: E.Value, passed: List<&2,E.Value>) -> List<&2,E.Value>:
  match passed:
    case Nil{}: Nil{}
    case +pass <> +rest:
      List.filter.put(E.Value,E.Array{[E.number(U32.show(q(failure))),E.number(U32.show(q(pass)))]},
        nonmonotonic_passes(failure,rest),(q(failure) < q(pass) : U32))

def nonmonotonic(failed: List<&2,E.Value>, +passed: List<&2,E.Value>) -> List<&2,E.Value>:
  match failed:
    case Nil{}: Nil{}
    case failure <> +rest: List.append(&2,E.Value,nonmonotonic_passes(failure,passed),nonmonotonic(rest,passed))

def range(fuel: Nat, +from: U32, +to: U32) -> List<&2,E.Value>:
  match fuel:
    case 0n: Nil{}
    case 1n+rest:
      choose_list((from < to : U32),
        +u =>
          E.number(U32.show(from)) <> range(rest,(from + 1 : U32),to),
        +u =>
          Nil{})
def close(+lower: U32, +upper: U32) -> Bool:
  T.bracket(Scale.Integer.from_u32(32n,lower),Scale.Integer.from_u32(32n,upper))

def category(+rows: List<&2,E.Value>, +dimension: String) -> E.Value:
  +passed = select(~String,~(dimension => row => confirmed(row,dimension,True{})),dimension,rows)
  +failed = select(~String,~(dimension => row => confirmed(row,dimension,False{})),dimension,rows)
  +low = last(passed)
  +high = E.at(select(~E.Value,~(+low => row => E.is_null(low) || (q(row) > q(low) : U32)),low,failed),0)
  +pairs = nonmonotonic(failed,passed)
  +has_pair = Bool.not(List.is_empty(&2,E.Value,pairs))
  +bounded = Bool.not(E.is_null(low) || E.is_null(high))
  +adjacent = bounded && U32.is_eq(q(high),(q(low) + 1 : U32))
  +narrow = bounded && close(q(low),q(high))
  +status = Bool.pick(String,has_pair,"nonmonotonic",Bool.pick(String,adjacent,"adjacent",
    Bool.pick(String,narrow,"within_ten_percent",Bool.pick(String,bounded,"unfinished","unbounded_observation"))))
  +note = Bool.pick(String,E.is_null(low),"no passing bound established",Bool.pick(String,E.is_null(high),
    "no failing bound observed",Bool.pick(String,has_pair,"separate tested regions; no single maximum","discrete observed bracket")))
  E.object([("largest_confirmed_pass",bound(low,dimension)),("nearest_confirmed_larger_failure",bound(high,dimension)),
    ("untested_q_between",E.Array{Bool.pick(List<&2,E.Value>,bounded,
      range(U32.to_nat(q(high)),(q(low) + 1 : U32),q(high)),Nil{})}),
    ("nonmonotonic_fail_then_pass",E.Array{pairs}),("refinement_status",E.string(status)),("note",E.string(note))])

def categories(+rows: List<&2,E.Value>, names: List<&2,String>) -> List<&2,E.Field()>:
  match names:
    case Nil{}: Nil{}
    case +name <> +rest: (name,category(rows,name)) <> categories(rows,rest)

def bounds(+points: List<&2,E.Value>, kinds: List<&2,String>) -> List<&2,E.Field()>:
  match kinds:
    case Nil{}: Nil{}
    case +kind <> +rest:
      +rows = List.sort(~E.Value,~order,select(~String,~(kind => row => canonical_primary(row,kind)),kind,points))
      (kind,E.object(categories(rows,dimensions()))) <> bounds(points,rest)

def candidate_key(keys: List<&2,E.Value>, +spec: E.Value) -> String:
  match keys:
    case Nil{}: ""
    case +pair <> rest:
      choose_text(E.eq(E.get(pair,"point"),spec),+u => E.text(E.get(pair,"key")),
        +u => candidate_key(rest,spec))

def has_point(+points: E.Value, +keys: List<&2,E.Value>, +spec: E.Value) -> Bool:
  E.has(points,candidate_key(keys,spec))

def untested_cases(+points: E.Value, +keys: List<&2,E.Value>, +side: U32, kinds: List<&2,String>) -> List<&2,E.Value>:
  match kinds:
    case Nil{}: Nil{}
    case kind <> +rest:
      +spec = point(kind,side)
      List.filter.put(E.Value,spec,untested_cases(points,keys,side,rest),Bool.not(has_point(points,keys,spec)))

def untested(+points: E.Value, +keys: List<&2,E.Value>, sides: List<&2,U32>) -> List<&2,E.Value>:
  match sides:
    case Nil{}: Nil{}
    case side <> +rest: List.append(&2,E.Value,untested_cases(points,keys,side,cases()),untested(points,keys,rest))

def summarize(+events: List<&2,E.Value>, keys: List<&2,E.Value>, +main_keys: List<&2,E.Value>, +simulation: Bool) -> E.Value:
  +updated = reassessments(events,E.object(Nil{}))
  +points = E.object(entries(E.fields(group(events,updated,keys,0,E.object(Nil{}))),events,simulation))
  +values = object_values(E.fields(points))
  +stops = select(~Unit,~(u => event => String.eq(E.text(E.get(event,"kind")),"stop")),Unit{},events)
  E.object([("schema",E.string("megascene-evidence/1")),("record_type",E.string("search_state")),
    ("simulation",E.boolean(simulation)),("campaign_id",E.get(E.at(events,0),"campaign_id")),
    ("points",points),("bounds",E.object(bounds(values,cases()))),("stops",E.Array{stops}),
    ("operational_cap",E.object([("largest_supported_q",E.number("5")),
      ("next_coarse_growth_q",E.number(Scale.Integer.show(Scale.next_growth(Scale.Integer.four())))),
      ("meaning",E.string("runner admission cap, not observed physical exhaustion"))])),
    ("untested_main",E.Array{untested(points,main_keys,[2,3,4,5])}),
    ("scope",E.string("tested configurations only; no architectural maximum inferred"))])

def refinement_result(result: Maybe<&2,Scale.Integer>, +state: E.Value, +main_keys: List<&2,E.Value>, +kind: String) -> E.Value:
  match result:
    case None{}: E.Null{}
    case Some{side}:
      +value = Scale.Integer.to_u32(side)
      choose((value >= 2 : U32) && (value <= 5 : U32),
        +u => Bool.pick(E.Value,E.has(state,"points"),
          Bool.pick(E.Value,has_point(E.get(state,"points"),main_keys,point(kind,value)),E.Null{},E.number(U32.show(value))),
          E.Error{"missing field:points"}),
        +u => E.Error{"square neighborhood scale unsupported: supported q=2..5; no physical capacity claim"})

def bracket_fields_problem(+state: E.Value, +kind: String, +dimension: String) -> E.Value:
  +bounds = E.get(state,"bounds")
  +family = E.get(bounds,kind)
  +entry = E.get(family,dimension)
  first_problem(field_problem(state,"bounds"),first_problem(field_problem(bounds,kind),
    first_problem(field_problem(family,dimension),first_problem(field_problem(entry,"largest_confirmed_pass"),
      field_problem(entry,"nearest_confirmed_larger_failure")))))

def bracket_point_problem(+bound: E.Value) -> E.Value:
  first_problem(field_problem(bound,"point"),field_problem(E.get(bound,"point"),"q"))

def integer_value(value: E.Value) -> Bool:
  match value:
    case E.Number{_}: True{}
    case _: False{}

def bracket_close(+lower: E.Value, +upper: E.Value) -> Bool:
  +low = E.rational(lower)
  +high = E.rational(upper)
  +low_area = E.rational_mul(low,low)
  +high_area = E.rational_mul(high,high)
  E.rational_le(E.rational_mul(E.rational_sub(high_area,low_area),E.rational(E.number("10"))),low_area)

def refine_ordered(+lower: E.Value, +upper: E.Value, +state: E.Value, +main_keys: List<&2,E.Value>, +kind: String) -> E.Value:
  +valid = integer_value(lower) && integer_value(upper) && E.int_ge(E.int(lower),E.int_u32(2)) &&
    E.int_gt(E.int(upper),E.int(lower))
  choose(valid,
    +u => refinement_result(Scale.midpoint_refinement(E.int_abs(E.int(lower)),E.int_abs(E.int(upper))),state,main_keys,kind),
    +u => E.Error{"refinement requires ordered square neighborhood scales"})

def refinement(+state: E.Value, +main_keys: List<&2,E.Value>, +kind: String, +dimension: String) -> E.Value:
  +problem = bracket_fields_problem(state,kind,dimension)
  +entry = E.get(E.get(E.get(state,"bounds"),kind),dimension)
  +low = E.get(entry,"largest_confirmed_pass")
  +high = E.get(entry,"nearest_confirmed_larger_failure")
  choose(E.is_null(problem),
    +u => choose(Bool.not(E.truth(low) && E.truth(high)),+u => E.Null{},
      +u => choose(E.has(entry,"nonmonotonic_fail_then_pass"),
        +u => choose(E.truth(E.get(entry,"nonmonotonic_fail_then_pass")),+u => E.Null{},
          +u =>
            +point_problem = first_problem(bracket_point_problem(low),bracket_point_problem(high))
            +lower = E.get(E.get(low,"point"),"q")
            +upper = E.get(E.get(high,"point"),"q")
            choose(E.is_null(point_problem),
              +u => choose(bracket_close(lower,upper),+u => E.Null{},
                +u => refine_ordered(lower,upper,state,main_keys,kind)),+u => point_problem)),
        +u => E.Error{"missing field:nonmonotonic_fail_then_pass"})),
    +u => problem)

def task(+spec: E.Value, +reason: String) -> E.Value:
  E.Array{[spec,E.string(reason)]}

def coarse_cases(+events: List<&2,E.Value>, +side: U32, kinds: List<&2,String>) -> E.Value:
  match kinds:
    case Nil{}: E.Null{}
    case +kind <> +rest:
      +spec = point(kind,side)
      +previous = select(~E.Value,~(+context => +row => primary(row,E.text(E.get(context,"case"))) && (q(row) < read_word(U32.read(E.text(E.get(context,"q")))) : U32)),E.object([("case",E.string(kind)),("q",E.number(U32.show(side)))]),all_attempts(events))
      choose(Bool.not(List.is_empty(&2,E.Value,attempts(events,spec))) || any(~Unit,~(u => row => Bool.not(String.eq(E.text(label(row,"capacity")),"pass"))),Unit{},previous),
        +u =>
          coarse_cases(events,side,rest),
        +u =>
          task(spec,"coarse_growth"))
def coarse(+events: List<&2,E.Value>, sides: List<&2,U32>) -> E.Value:
  match sides:
    case Nil{}: E.Null{}
    case side <> +rest:
      +candidate = coarse_cases(events,side,cases())
      choose(E.is_null(candidate),
        +u =>
          coarse(events,rest),
        +u =>
          candidate)
def failure(+row: E.Value) -> Bool:
  String.starts_with(E.text(label(row,"interactive")),"fail:") ||
    String.starts_with(E.text(label(row,"time_budget")),"fail:") ||
    String.starts_with(E.text(label(row,"observed_capacity_failure")),"fail:")

def repetition_candidates(rows: List<&2,E.Value>) -> E.Value:
  match rows:
    case Nil{}: E.Null{}
    case +row <> +rest:
      +runs = E.array(E.get(row,"attempts"))
      +first = E.at(runs,0)
      +allocation = String.eq(E.text(E.get(first,"cause")),"allocation_error")
      +needed = Bool.pick(U32,allocation,2,3)
      choose((E.count(runs) < needed : U32) && all(~E.Value,~(first => run => E.eq(E.get(run,"labels"),E.get(first,"labels"))),first,runs),
        +u =>
          task(E.get(row,"point"),Bool.pick(String,allocation,"allocation_diagnostic_retry","endpoint_repetition")),
        +u =>
          repetition_candidates(rest))
def repetitions(+points: List<&2,E.Value>, kinds: List<&2,String>) -> E.Value:
  match kinds:
    case Nil{}: E.Null{}
    case +kind <> +rest:
      +rows = List.sort(~E.Value,~order,select(~String,~(kind => row => primary(row,kind)),kind,points))
      +passes = select(~Unit,~(u => row => String.eq(E.text(label(E.at(E.array(E.get(row,"attempts")),0),"capacity")),"pass")),Unit{},rows)
      +failures = select(~Unit,~(u => row => failure(E.at(E.array(E.get(row,"attempts")),0))),Unit{},rows)
      +last_pass = last(passes)
      +candidates = unique(List.concat(&2,E.Value,[List.take(&2,E.Value,List.reverse(&2,E.Value,passes),1n),
        List.take(&2,E.Value,failures,1n),Bool.pick(List<&2,E.Value>,E.is_null(last_pass),Nil{},
          List.take(&2,E.Value,select(~E.Value,~(last_pass => row => (q(row) > q(last_pass) : U32)),last_pass,failures),1n))]),Nil{})
      +candidate = repetition_candidates(candidates)
      choose(E.is_null(candidate),
        +u =>
          repetitions(points,rest),
        +u =>
          candidate)
def refine_dimensions(+state: E.Value, +main_keys: List<&2,E.Value>, +kind: String, names: List<&2,String>) -> E.Value:
  match names:
    case Nil{}: E.Null{}
    case name <> +rest:
      +side = refinement(state,main_keys,kind,name)
      choose(E.is_null(side),
        +u =>
          refine_dimensions(state,main_keys,kind,rest),
        +u =>
          task(point(kind,read_word(U32.read(E.text(side)))),"area_midpoint_refinement"))
def refinements(+state: E.Value, +main_keys: List<&2,E.Value>, kinds: List<&2,String>) -> E.Value:
  match kinds:
    case Nil{}: E.Null{}
    case +kind <> +rest:
      +candidate = refine_dimensions(state,main_keys,kind,dimensions())
      choose(E.is_null(candidate),
        +u =>
          refinements(state,main_keys,rest),
        +u =>
          candidate)
def Variant() -> Data:
  Sigma<&2,&2,E.Value,_ => E.Value>

def Crosscheck() -> Data:
  Sigma<&2,&2,U32,_ => U32>

def diagnostics(+kind: String) -> List<&2,Variant()>:
  match kind:
    case "static": [(E.string("spread"),E.Null{}),(E.string("material-detail"),E.Null{}),(E.string("surface-detail"),E.Null{})]
    case "localized": [(E.string("material-detail"),E.Null{})]
    case "support": [(E.string("fill"),E.Null{}),(E.Null{},E.string("support-1-span-v1")),(E.Null{},E.string("support-2-span-v1"))]
    case "history": [(E.string("fill"),E.Null{}),(E.string("body-rich"),E.Null{}),
      (E.Null{},E.string("history-12-v1")),(E.Null{},E.string("history-48-v1"))]
    case _: Nil{}

def diagnostic_variants(+events: List<&2,E.Value>, +kind: String, variants: List<&2,Variant()>) -> E.Value:
  match variants:
    case Nil{}: E.Null{}
    case (diagnostic,route) <> +rest:
      +spec = point_fields(kind,2,E.number("45"),E.number("6"),diagnostic,route)
      choose(List.is_empty(&2,E.Value,attempts(events,spec)),
        +u =>
          task(spec,"targeted_diagnostic"),
        +u =>
          diagnostic_variants(events,kind,rest))
def diagnostic_tasks(+events: List<&2,E.Value>, kinds: List<&2,String>) -> E.Value:
  match kinds:
    case Nil{}: E.Null{}
    case +kind <> +rest:
      +main = select(~String,~(kind => row => primary(row,kind)),kind,all_attempts(events))
      choose(any(~Unit,~(u => row => failure(row)),Unit{},main),
        +u =>
          +candidate = diagnostic_variants(events,kind,diagnostics(kind))
          choose(E.is_null(candidate),
            +u =>
              diagnostic_tasks(events,rest),
            +u =>
              candidate),
        +u =>
          diagnostic_tasks(events,rest))
def crosscheck_variants(+events: List<&2,E.Value>, +kind: String, +side: U32, variants: List<&2,Crosscheck()>) -> E.Value:
  match variants:
    case Nil{}: E.Null{}
    case (seed,threads) <> +rest:
      +spec = point_fields(kind,side,E.number(U32.show(seed)),E.number(U32.show(threads)),E.Null{},E.Null{})
      choose(List.is_empty(&2,E.Value,attempts(events,spec)),
        +u =>
          task(spec,"boundary_crosscheck"),
        +u =>
          crosscheck_variants(events,kind,side,rest))
def crosschecks(+events: List<&2,E.Value>, +state: E.Value, kinds: List<&2,String>) -> E.Value:
  match kinds:
    case Nil{}: E.Null{}
    case +kind <> +rest:
      +bounds = E.get(E.get(state,"bounds"),kind)
      +capacity = E.get(E.get(bounds,"capacity"),"nearest_confirmed_larger_failure")
      +boundary = Bool.pick(E.Value,E.is_null(capacity),
        E.get(E.get(bounds,"interactive"),"nearest_confirmed_larger_failure"),capacity)
      choose(E.is_null(boundary),
        +u =>
          crosschecks(events,state,rest),
        +u =>
          +candidate = crosscheck_variants(events,kind,q(boundary),[(46,6),(45,1),(45,12)])
          choose(E.is_null(candidate),
            +u =>
              crosschecks(events,state,rest),
            +u =>
              candidate))
def next_task(+events: List<&2,E.Value>, keys: List<&2,E.Value>, +main_keys: List<&2,E.Value>, +simulation: Bool) -> E.Value:
  +state = summarize(events,keys,main_keys,simulation)
  +points = object_values(E.fields(E.get(state,"points")))
  +growth = coarse(events,[2,3,4,5])
  choose(E.is_null(growth),
    +u =>
      +repeat = repetitions(points,cases())
      choose(E.is_null(repeat),
        +u =>
          +refine = refinements(state,main_keys,cases())
          choose(E.is_null(refine),
            +u =>
              +diagnostic = diagnostic_tasks(events,["static","localized","support","history"])
              choose(E.is_null(diagnostic),
                +u =>
                  +crosscheck = crosschecks(events,state,cases())
                  Bool.pick(E.Value,E.is_null(crosscheck),E.Array{[E.Null{},E.Null{}]},crosscheck),
                +u =>
                  diagnostic),
            +u =>
              refine),
        +u =>
          repeat),
    +u =>
      growth)
def policy_stop(+observed: E.Value) -> Bool:
  +cause = E.text(E.get(observed,"cause"))
  one_of(cause,["required_edit_rejection","monitoring_failure","external_interruption","process_rss_reserve",
    "available_ram_reserve","device_free_reserve","heap_budget_reserve","rejected_request","prelaunch_failure",
    "device_loss","evidence_failure"]) || all(~Unit,~(u => value => String.eq(E.text(value),"inconclusive")),Unit{},object_values(E.fields(E.get(observed,"labels"))))

def dispatch_limit(+payload: E.Value) -> E.Value:
  +limit = E.get(payload,"limit")
  Bool.pick(E.Value,Bool.not(E.is_null(limit)) && E.int_le(E.int(limit),E.int(E.get(payload,"count"))),
    E.object([("reason",E.string("declared_dispatch_limit")),("next_point",E.get(payload,"point"))]),E.Null{})

def campaign_gate(+payload: E.Value) -> E.Value:
  +remaining = E.get(payload,"remaining_ns")
  stopped = Bool.not(E.truth(E.get(payload,"simulation"))) && Bool.not(E.truth(E.get(payload,"additional"))) &&
    (E.int_le(E.int(remaining),E.int_zero()) || String.eq(E.text(E.get(payload,"state")),"interrupted"))
  Bool.pick(E.Value,stopped,E.object([("reason",E.string("campaign_allowance_or_interruption")),
    ("remaining_ns",E.int_string(E.int(remaining))),("next_point",E.get(payload,"point"))]),E.Null{})

def fields_problem(+value: E.Value, names: List<&2,String>) -> E.Value:
  match names:
    case Nil{}: E.Null{}
    case +name <> rest: first_problem(field_problem(value,name),fields_problem(value,rest))

def python_string(value: E.Value) -> E.Value:
  match value:
    case E.Number{text}: E.string(text)
    case E.Real{_,decimal}: E.string(decimal)
    case E.Text{text}: E.string(text)
    case E.Boolean{flag}: E.string(Bool.pick(String,flag,"True","False"))
    case E.Null{}: E.string("None")
    case _: E.Error{"unsupported scope scalar"}

def control_value(+diagnostic: E.Value) -> Bool:
  one_of(E.text(diagnostic),["spread","fill","body-rich","material-detail","surface-detail"])

def inspect_expected(+expected: E.Value) -> E.Value:
  +diagnostic = E.get(expected,"diagnostic")
  E.object([("case",E.get(expected,"case")),("preset",E.get(expected,"preset")),
    ("side_m",E.int_string(E.int_mul(E.int_u32(32),E.int(E.get(expected,"q"))))),
    ("seed",python_string(E.get(expected,"seed"))),("threads",python_string(E.get(expected,"threads"))),
    ("resolution",E.get(expected,"resolution")),("profile",E.get(expected,"profile")),
    ("fragment_budget",E.get(expected,"fragment_budget")),("warmup",E.get(expected,"warmup")),
    ("frames",E.get(expected,"frames")),("diagnostic",Bool.pick(E.Value,control_value(diagnostic),E.Null{},diagnostic)),
    ("schedule",E.get(expected,"schedule"))])

def scope_problem(+config: E.Value, wanted: List<&2,E.Field()>) -> E.Value:
  match wanted:
    case Nil{}: E.Null{}
    case (+name,value) <> rest:
      first_problem(Bool.pick(E.Value,E.eq(E.get(config,name),value),E.Null{},
        E.Error{"attempt scope mismatch: " ++ name}),scope_problem(config,rest))

def inspect_scope(+payload: E.Value) -> E.Value:
  +manifest = E.get(payload,"manifest")
  +summary = E.get(payload,"summary")
  +expected = E.get(payload,"expected")
  +config = E.get(manifest,"effective")
  +synthetic = E.truth(E.get(manifest,"synthetic")) || E.truth(E.get(summary,"synthetic"))
  +identity = E.eq(E.get(manifest,"schema"),E.string("megascene-evidence/1")) &&
    E.eq(E.get(summary,"schema"),E.string("megascene-evidence/1")) &&
    E.eq(E.get(manifest,"attempt_id"),E.get(summary,"attempt_id"))
  +expected_problem = fields_problem(expected,["case","preset","q","seed","threads","resolution",
    "profile","fragment_budget","warmup","frames","diagnostic","schedule"])
  +binding = scope_problem(config,E.fields(inspect_expected(expected)))
  +diagnostic = E.get(expected,"diagnostic")
  +control = Bool.pick(E.Value,control_value(diagnostic),diagnostic,E.Null{})
  choose(identity,
    +u => choose(E.is_null(expected_problem),
      +u => choose(E.is_null(binding),
        +u => choose(E.eq(E.get(config,"control"),control),
          +u => choose(E.truth(E.get(payload,"fixture")) || Bool.not(synthetic),
            +u => E.object([("config",Bool.pick(E.Value,E.truth(config),config,E.object(Nil{}))),
              ("synthetic",E.boolean(synthetic))]),
            +u => E.Error{"synthetic attempt excluded from measured search"}),
          +u => E.Error{"attempt control mismatch"}),
        +u => binding),
      +u => expected_problem),
    +u => E.Error{"attempt identity/schema mismatch"})

def validation_gate(+payload: E.Value) -> E.Value:
  +validation = E.get(payload,"validation")
  choose(E.eq(E.get(validation,"status"),E.string("pass")),
    +u => Bool.pick(E.Value,E.truth(E.get(payload,"fixture")) ||
      (E.is_bool(E.get(validation,"synthetic")) && E.eq(E.get(validation,"synthetic"),E.boolean(False{}))),
      E.Null{},E.Error{"complete real validation required"}),
    +u => E.Error{"complete validation required"})

def capacity_inventory_gate(+payload: E.Value) -> E.Value:
  +report = E.get(payload,"report")
  Bool.pick(E.Value,Bool.not(E.eq(E.get(E.get(report,"qualified_capacity"),"status"),E.string("pass"))) ||
    (E.eq(E.get(payload,"inventory_source"),E.string("inventory.json")) &&
      E.eq(E.get(E.get(report,"initialization"),"status"),E.string("pass"))),E.Null{},
    E.Error{"capacity pass lacks actual timed initial inventory"})

def calibration_binding(+payload: E.Value) -> E.Value:
  +value = E.get(payload,"calibration")
  +assessment = E.get(payload,"assessment")
  +problem = first_problem(field_problem(assessment,"status"),choose(E.eq(E.get(assessment,"status"),E.string("pass")),
    +u => first_problem(field_problem(assessment,"scope"),first_problem(field_problem(value,"scope"),
      choose(E.eq(E.get(assessment,"scope"),E.get(value,"scope")),+u => field_problem(value,"reference"),
        +u => E.Null{}))),+u => E.Null{}))
  Bool.pick(E.Value,E.is_null(problem),Bool.pick(E.Value,
    E.eq(E.get(assessment,"status"),E.string("pass")) && E.eq(E.get(assessment,"scope"),E.get(value,"scope")) &&
      E.eq(E.get(value,"reference"),E.get(payload,"reference")),E.Null{},
      E.Error{"calibration result no longer agrees with retained controls"}),problem)

def inconclusive() -> E.Value:
  E.object([("interactive",E.string("inconclusive")),("time_budget",E.string("inconclusive")),
    ("capacity",E.string("inconclusive")),("observed_capacity_failure",E.string("inconclusive"))])

def evidence_gates(+report: E.Value, names: List<&2,String>) -> List<&2,E.Field()>:
  match names:
    case Nil{}: Nil{}
    case +name <> rest: (name,E.get(E.get(report,name),"status")) <> evidence_gates(report,rest)

def inspect_result(+payload: E.Value) -> E.Value:
  +manifest = E.get(payload,"manifest")
  +expected = E.get(payload,"expected")
  +report = E.get(payload,"report")
  +complete = E.truth(E.get(payload,"complete"))
  +fixture = E.truth(E.get(payload,"fixture"))
  +classified = Bool.pick(E.Value,complete,labels(report),inconclusive())
  +partial = E.get(payload,"partial")
  +classified = Bool.pick(E.Value,Bool.not(complete || fixture) && E.truth(partial),
    E.merge(classified,E.object([("time_budget",E.get(labels(report),"time_budget")),
      ("observed_capacity_failure",E.get(labels(report),"observed_capacity_failure"))])),classified)
  +canonical = E.eq(E.get(expected,"warmup"),E.string("120")) && E.eq(E.get(expected,"frames"),E.string("3600")) &&
    (fixture || E.eq(E.get(manifest,"attempt_kind"),E.string("development_observation")))
  +classified = Bool.pick(E.Value,canonical,classified,inconclusive())
  +cause = Bool.pick(E.Value,E.has(E.get(report,"termination"),"cause"),E.get(E.get(report,"termination"),"cause"),E.string("unknown"))
  Bool.pick(E.Value,E.has(manifest,"attempt_id"),
    E.object([("attempt_id",E.get(manifest,"attempt_id")),("campaign_id",E.get(manifest,"campaign_id")),
      ("series_id",E.get(manifest,"series_id")),("attempt_kind",E.get(manifest,"attempt_kind")),
      ("effective_scope",E.get(payload,"config")),("archive",E.get(payload,"archive")),
      ("inventory",E.get(payload,"inventory")),("inventory_source",E.get(payload,"inventory_source")),
      ("workload_fingerprint",E.get(payload,"fingerprint")),("labels",classified),("cause",cause),
      ("synthetic",E.get(payload,"synthetic")),("evidence_gates",E.object(evidence_gates(report,
        ["state_correctness","rendering_correctness","visual_quality","numeric_validity","schedule_completion","workload_completion"]))),
      ("calibration",E.get(report,"calibration")),("calibration_source",E.get(payload,"calibration_source")),
      ("report_status",E.get(report,"qualification")),("validation_attempt_id",Bool.pick(E.Value,complete,
        E.get(E.get(payload,"validation"),"attempt_id"),E.Null{})),
      ("source_control_effects",E.get(E.get(manifest,"numeric_bounds"),"control_effects"))]),
    E.Error{"missing field:attempt_id"})

def returncode_suppression(+payload: E.Value) -> E.Value:
  +observed = E.get(payload,"observed")
  +code = E.get(payload,"returncode")
  +reassessment = E.truth(E.get(payload,"reassessment"))
  +failed = Bool.not(E.eq(code,E.number("0")) || (reassessment && E.is_null(code)))
  Bool.pick(E.Value,failed,E.merge(observed,Bool.pick(E.Value,reassessment,
    E.object([("labels",inconclusive())]),E.object([("labels",inconclusive()),
      ("runner_failure",E.string("nonzero runner return code"))]))),observed)

def inspection_failure(+payload: E.Value) -> E.Value:
  E.object([("attempt_id",E.get(payload,"attempt_id")),("archive",E.get(payload,"archive")),
    ("inventory",E.Null{}),("workload_fingerprint",E.Null{}),("labels",inconclusive()),
    ("cause",E.get(payload,"cause")),("synthetic",E.get(payload,"fixture")),
    ("inspection_error",E.get(payload,"error"))])

def recover_pending(+events: List<&2,E.Value>) -> E.Value:
  +completed = map(~Unit,~(u => event => E.get(event,"attempt_token")),Unit{},select(~Unit,
    ~(u => event => E.has(event,"attempt_token")),Unit{},events_of(events,"attempt")))
  E.Array{select(~E.Value,~(completed => event => Bool.not(contains(E.array(completed),E.get(event,"attempt_token")))),
    E.Array{completed},events_of(events,"proposal"))}

def recover_diagnostics(+events: List<&2,E.Value>) -> E.Value:
  +assessed = map(~Unit,~(u => event => E.get(event,"attempt_id")),Unit{},events_of(events,"diagnostic_assessment"))
  E.Array{select(~E.Value,~(assessed => event => E.eq(E.get(event,"reason"),E.string("targeted_diagnostic")) &&
    Bool.not(contains(E.array(assessed),E.get(event,"attempt_id")))),E.Array{assessed},events_of(events,"attempt"))}

def orphaned_diagnostic(+payload: E.Value) -> E.Value:
  +result = E.get(payload,"result")
  +attempt = E.get(payload,"attempt")
  +problem = first_problem(field_problem(result,"schema"),choose(E.eq(E.get(result,"schema"),E.string("megascene-evidence/1")),
    +u => first_problem(field_problem(result,"attempt_id"),field_problem(attempt,"attempt_id")),+u => E.Null{}))
  Bool.pick(E.Value,E.is_null(problem),Bool.pick(E.Value,
    E.eq(E.get(result,"schema"),E.string("megascene-evidence/1")) &&
      E.eq(E.get(result,"attempt_id"),E.get(attempt,"attempt_id")),E.Null{},
      E.Error{"orphaned diagnostic assessment identity mismatch"}),problem)

def reassessment_failure(+original: E.Value) -> E.Value:
  Bool.pick(E.Value,E.has(original,"labels"),E.boolean(all(~Unit,
    ~(u => value => E.eq(value,E.string("inconclusive"))),Unit{},object_values(E.fields(E.get(original,"labels"))))),
    E.Error{"missing field:labels"})

def changed_fields(fields: List<&2,E.Field()>, +previous: E.Value) -> Bool:
  match fields:
    case Nil{}: False{}
    case (+name,value) <> rest: Bool.not(E.eq(value,E.get(previous,name))) || changed_fields(rest,previous)

def reassessment(+payload: E.Value) -> E.Value:
  +original = E.get(payload,"original")
  +events = E.array(E.get(payload,"events"))
  +updated = returncode_suppression(E.object([("observed",E.get(payload,"updated")),
    ("returncode",E.get(original,"returncode")),("reassessment",E.boolean(True{}))]))
  +prior = last_matching(events,"reassessment",E.get(original,"attempt_id"),E.Null{})
  +previous = Bool.pick(E.Value,E.is_null(prior),original,E.get(prior,"observed"))
  +updated = Bool.pick(E.Value,E.truth(E.get(previous,"workload_fingerprint")),
    E.put(updated,"workload_fingerprint",E.get(previous,"workload_fingerprint")),updated)
  Bool.pick(E.Value,changed_fields(E.fields(updated),previous),
    E.object([("attempt_id",E.get(original,"attempt_id")),("point",E.get(original,"point")),
      ("observed",updated),("reason",E.string("archived review/calibration or evidence changed"))]),E.Null{})

def diagnostic_reassessment_candidate(+events: E.Value, +attempt: E.Value) -> Bool:
  +prior = last_matching(E.array(events),"diagnostic_assessment",E.get(attempt,"attempt_id"),E.Null{})
  +baseline = attempts(E.array(events),point(E.text(E.get(E.get(attempt,"point"),"case")),2))
  E.eq(E.get(attempt,"reason"),E.string("targeted_diagnostic")) && E.eq(label(attempt,"capacity"),E.string("pass")) &&
    Bool.not(E.truth(prior) && E.eq(E.get(prior,"status"),E.string("pass"))) &&
      any(~Unit,~(u => row => E.eq(label(row,"capacity"),E.string("pass"))),Unit{},baseline)

def reassess_diagnostics(+events: List<&2,E.Value>) -> E.Value:
  E.Array{select(~E.Value,~(events => attempt => diagnostic_reassessment_candidate(events,attempt)),E.Array{events},all_attempts(events))}

def diagnostic_prepare(+payload: E.Value) -> E.Value:
  +events = E.array(E.get(payload,"events"))
  +spec = E.get(payload,"point")
  +observed = E.get(payload,"observed")
  +baseline = E.at(select(~Unit,~(u => event => E.truth(E.get(event,"validation_attempt_id")) &&
    E.truth(E.get(event,"inventory")) && E.eq(label(event,"capacity"),E.string("pass"))),Unit{},
      attempts(events,point(E.text(E.get(spec,"case")),2))),0)
  +result = E.object([("schema",E.string("megascene-evidence/1")),
    ("record_type",E.string("search_diagnostic_assessment")),("point",spec),
    ("baseline_attempt_id",E.get(baseline,"attempt_id")),("attempt_id",E.get(observed,"attempt_id")),
    ("baseline_validation_id",E.get(baseline,"validation_attempt_id")),
    ("validation_id",E.get(observed,"validation_attempt_id")),("baseline_inventory",E.get(baseline,"inventory")),
    ("control_inventory",E.get(observed,"inventory")),("source_control_effects",E.get(observed,"source_control_effects")),
    ("status",E.string("inconclusive"))])
  +problem = first_problem(field_problem(spec,"case"),field_problem(observed,"attempt_id"))
  Bool.pick(E.Value,E.is_null(problem),E.object([("baseline",baseline),("result",result)]),problem)

def diagnostic_gate(+payload: E.Value) -> E.Value:
  +baseline = E.get(payload,"baseline")
  +observed = E.get(payload,"observed")
  +fixture = E.truth(E.get(payload,"fixture"))
  +valid = Bool.not(E.is_null(baseline)) && E.truth(E.get(observed,"validation_attempt_id")) &&
    Bool.not(E.eq(E.get(observed,"validation_attempt_id"),E.get(baseline,"validation_attempt_id")))
  choose(valid,
    +u => Bool.pick(E.Value,fixture,
      E.object([("mode",E.string("simulated")),("result",E.merge(E.get(payload,"result"),E.object([
        ("status",E.string("simulated")),("reason",E.string("controlled synthetic inventories; no measured comparison"))])))]),
      Bool.pick(E.Value,E.has(E.get(payload,"point"),"diagnostic"),
        E.object([("mode",E.string(Bool.pick(String,E.truth(E.get(E.get(payload,"point"),"diagnostic")),"control","schedule"))),
          ("result",E.get(payload,"result"))]),E.Error{"missing field:diagnostic"})),
    +u => E.Error{"separate complete baseline and control validations required"})

def diagnostic_finish(+payload: E.Value) -> E.Value:
  +result = E.get(payload,"result")
  +comparison = E.get(payload,"comparison")
  +error = E.get(payload,"error")
  choose(Bool.not(E.is_null(error)),
    +u => E.put(result,"reason",error),
    +u => choose(E.is_null(comparison),+u => result,
      +u => Bool.pick(E.Value,E.has(comparison,"status"),E.merge(result,E.object([
        ("status",E.get(comparison,"status")),("comparison",comparison)])),E.Error{"missing field:status"})))

def series_attempt(+attempt: E.Value) -> E.Value:
  +problem = fields_problem(attempt,["attempt_id","archive","inventory","labels"])
  Bool.pick(E.Value,E.is_null(problem),E.object([("attempt_id",E.get(attempt,"attempt_id")),
    ("archive",E.get(attempt,"archive")),("inventory",E.get(attempt,"inventory")),
    ("workload_fingerprint",E.get(attempt,"workload_fingerprint")),
    ("validation_attempt_id",E.get(attempt,"validation_attempt_id")),
    ("calibration",E.get(attempt,"calibration")),("labels",E.get(attempt,"labels"))]),problem)

def series_records(rows: List<&2,E.Field()>, +simulation: E.Value) -> List<&2,E.Field()>:
  match rows:
    case Nil{}: Nil{}
    case (identifier,+entry) <> rest:
      (identifier,E.object([("schema",E.string("megascene-evidence/1")),("record_type",E.string("search_series")),
        ("scope",E.get(entry,"point")),("attempts",E.Array{map(~Unit,~(u => row => series_attempt(row)),Unit{},E.array(E.get(entry,"attempts")))}),
        ("outcomes",E.get(entry,"outcomes")),("diagnostic_assessments",E.get(entry,"diagnostic_assessments")),
        ("synthetic_simulation",simulation)])) <> series_records(rest,simulation)

def search_initial_gate(+payload: E.Value) -> E.Value:
  +additional = E.truth(E.get(payload,"additional"))
  +existing = E.truth(E.get(payload,"existing"))
  +campaign = E.truth(E.get(payload,"campaign"))
  Bool.pick(E.Value,Bool.not(additional) || existing || campaign,E.Null{},
    E.Error{"additional allowance requires an existing search or campaign"})

def search_new_gate(+payload: E.Value) -> E.Value:
  Bool.pick(E.Value,Bool.not(E.truth(E.get(payload,"additional"))) || Bool.not(E.truth(E.get(payload,"fixture"))),E.Null{},
    E.Error{"additional allowance requires an existing search"})

def search_resume_gate(+payload: E.Value) -> E.Value:
  +first = E.get(payload,"first")
  +problem = first_problem(field_problem(first,"archive"),choose(E.eq(E.get(first,"archive"),E.get(payload,"archive")),
    +u => first_problem(field_problem(first,"work"),choose(E.eq(E.get(first,"work"),E.get(payload,"work")),
      +u => field_problem(first,"simulation"),+u => E.Null{})),+u => E.Null{}))
  +scope = E.eq(E.get(first,"archive"),E.get(payload,"archive")) && E.eq(E.get(first,"work"),E.get(payload,"work")) &&
    E.eq(E.get(first,"simulation"),E.get(payload,"fixture"))
  Bool.pick(E.Value,E.is_null(problem),choose(scope,
    +u => Bool.pick(E.Value,Bool.not(E.truth(E.get(payload,"existing"))) || E.int_gt(E.int(E.get(payload,"additional")),E.int_zero()),
      E.Null{},E.Error{"resuming search requires --additional-allowance SECONDS"}),
    +u => E.Error{"search resume scope differs"}),problem)

def event_record_gate(+payload: E.Value) -> E.Value:
  +event = E.get(payload,"event")
  +problem = first_problem(field_problem(event,"schema"),choose(E.eq(E.get(event,"schema"),E.string("megascene-evidence/1")),
    +u => field_problem(event,"sequence"),+u => E.Null{}))
  Bool.pick(E.Value,E.is_null(problem),Bool.pick(E.Value,E.eq(E.get(event,"schema"),E.string("megascene-evidence/1")) &&
    E.eq(E.get(event,"sequence"),E.int_string(E.int(E.get(payload,"sequence")))),E.Null{},
      E.Error{"search evidence schema/sequence mismatch"}),problem)

def plan_complete(+payload: E.Value) -> E.Value:
  E.object([("reason",E.string("search_plan_complete")),("operational_cap_q",E.string("5")),
    ("next_unsupported_growth_q",E.string(Scale.Integer.show(Scale.next_growth(Scale.Integer.four())))),
    ("physical_exhaustion_established",E.boolean(False{})),("untested_gaps",E.get(payload,"untested_main"))])

def policy_stop_record(+payload: E.Value) -> E.Value:
  +observed = E.get(payload,"observed")
  +problem = fields_problem(observed,["cause","attempt_id"])
  Bool.pick(E.Value,E.is_null(problem),E.object([("reason",E.string("policy_or_evidence_stop")),
    ("cause",E.get(observed,"cause")),("point",E.get(payload,"point")),("attempt_id",E.get(observed,"attempt_id"))]),problem)

def cli_gate(+payload: E.Value) -> E.Value:
  +additional = E.int(E.get(payload,"additional"))
  +limit = E.get(payload,"limit")
  Bool.pick(E.Value,E.int_ge(additional,E.int_zero()) && E.int_le(additional,E.int_u32(86400)) &&
    (E.is_null(limit) || E.int_ge(E.int(limit),E.int_u32(1))),E.Null{},E.Error{"invalid allowance/dispatch limit"})

def handle(operation: String, +payload: E.Value) -> E.Value:
  match operation:
    case "series_records": E.object(series_records(E.fields(E.get(payload,"points")),E.get(payload,"simulation")))
    case "search_initial_gate": search_initial_gate(payload)
    case "search_new_gate": search_new_gate(payload)
    case "search_resume_gate": search_resume_gate(payload)
    case "event_record_gate": event_record_gate(payload)
    case "plan_complete": plan_complete(payload)
    case "policy_stop_record": policy_stop_record(payload)
    case "cli_gate": cli_gate(payload)
    case "events_of": E.Array{events_of(E.array(E.get(payload,"events")),E.text(E.get(payload,"kind")))}
    case "recover_pending": recover_pending(E.array(payload))
    case "recover_diagnostics": recover_diagnostics(E.array(payload))
    case "orphaned_diagnostic": orphaned_diagnostic(payload)
    case "reassessment_failure": reassessment_failure(payload)
    case "reassessment": reassessment(payload)
    case "reassess_diagnostics": reassess_diagnostics(E.array(payload))
    case "diagnostic_prepare": diagnostic_prepare(payload)
    case "diagnostic_gate": diagnostic_gate(payload)
    case "diagnostic_finish": diagnostic_finish(payload)
    case "inspection_failure": inspection_failure(payload)
    case "returncode_suppression": returncode_suppression(payload)
    case "calibration_reassess": E.boolean(E.eq(E.get(payload,"status"),E.string("pass")))
    case "validation_pass": E.boolean(E.eq(E.get(payload,"status"),E.string("pass")))
    case "inspect_scope": inspect_scope(payload)
    case "validation_gate": validation_gate(payload)
    case "timed_inventory_gate": Bool.pick(E.Value,E.eq(E.get(payload,"timed"),E.get(payload,"validated")),
      E.Null{},E.Error{"timed and validated initial inventories differ"})
    case "capacity_inventory_gate": capacity_inventory_gate(payload)
    case "calibration_binding": calibration_binding(payload)
    case "inspect_result": inspect_result(payload)
    case "main_points": E.Array{untested(E.object(Nil{}),Nil{},[2,3,4,5])}
    case "point": point_read(E.text(E.get(payload,"case")),E.get(payload,"q"),E.get(payload,"seed"),
      E.get(payload,"threads"),E.get(payload,"diagnostic"),E.get(payload,"schedule"))
    case "labels": labels(payload)
    case "outcome_for": outcome_checked(E.array(E.get(payload,"rows")),E.text(E.get(payload,"dimension")),E.bool(E.get(payload,"simulation")))
    case "all_attempts":
      +events = E.array(payload)
      +problem = first_problem(events_problem(events,True{}),attempt_events_problem(events,False{}))
      Bool.pick(E.Value,E.is_null(problem),E.Array{all_attempts(events)},problem)
    case "attempts":
      +events = E.array(E.get(payload,"events"))
      +problem = first_problem(events_problem(events,True{}),attempt_events_problem(events,True{}))
      Bool.pick(E.Value,E.is_null(problem),E.Array{attempts(events,E.get(payload,"point"))},problem)
    case "summarize":
      +events = E.array(E.get(payload,"events"))
      +problem = first_problem(events_problem(events,True{}),first_problem(attempt_events_problem(events,True{}),specs_problem(events)))
      Bool.pick(E.Value,E.is_null(problem),summarize(events,E.array(E.get(payload,"keys")),E.array(E.get(payload,"main_keys")),E.bool(E.get(payload,"simulation"))),problem)
    case "refinement_candidate": refinement(E.get(payload,"state"),E.array(E.get(payload,"main_keys")),E.text(E.get(payload,"case")),E.text(E.get(payload,"dimension")))
    case "next_task":
      +events = E.array(E.get(payload,"events"))
      +problem = first_problem(events_problem(events,True{}),first_problem(attempt_events_problem(events,True{}),specs_problem(events)))
      Bool.pick(E.Value,E.is_null(problem),next_task(events,E.array(E.get(payload,"keys")),E.array(E.get(payload,"main_keys")),E.bool(E.get(payload,"simulation"))),problem)
    case "policy_stop": E.boolean(policy_stop(payload))
    case "dispatch_limit": dispatch_limit(payload)
    case "campaign_gate": campaign_gate(payload)
    case _: E.Error{"unknown search evidence operation"}

def main() -> IO(Unit):
  E.main(~handle)
