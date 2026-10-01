import Base
import ./evidence_value.bend as E
import ./megascene_scale.bend as S
import ./evidence_report.bend as R
import ./evidence_thresholds.bend as T

def get(+v: E.Value, +k: String) -> E.Value: E.get(v,k)
def text(+v: E.Value, +k: String) -> String: E.text(get(v,k))
def array(+v: E.Value, +k: String) -> List<&2,E.Value>: E.array(get(v,k))
def field(+k: String, +v: E.Value) -> E.Field(): (k,v)
def str(+k: String, +s: String) -> E.Field(): (k,E.Text{s})
def status(+v: E.Value, +k: String) -> String: text(get(v,k),"status")
def eq(+v: E.Value, +k: String, +s: String) -> Bool: E.eq(get(v,k),E.Text{s})
def count(+xs: List<&2,E.Value>) -> E.Value: E.Text{U32.show(E.count(xs))}
def num(+n: U32) -> E.Value: E.Number{U32.show(n)}
def integer(+n: U32) -> E.Signed: E.int(num(n))
def zero() -> E.Signed: integer(0)
def nonzero(+v: E.Signed) -> Bool: Bool.not(E.int_le(v,zero()))
def le(+a: E.Value, +b: E.Value) -> Bool: E.int_le(E.int(a),E.int(b))
def same(+a: E.Value, +b: E.Value) -> Bool: E.eq(a,b)
def require(+ok: Bool, +reason: String) -> Result<&2,&2,String,Unit>:
  match ok:
    case True{}: Done{Unit{}}
    case False{}: Fail{reason}
def result(r: Result<&2,&2,String,E.Value>) -> E.Value:
  match r:
    case Done{v}: v
    case Fail{s}: E.Error{s}
def strings(+xs: List<&2,String>) -> List<&2,E.Value>:
  match xs:
    case Nil{}: Nil{}
    case +h <> +t: E.Text{h} <> strings(t)
def has_string(+xs: List<&2,E.Value>, +s: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case +h <> +t: String.eq(E.text(h),s) || has_string(t,s)
def type_rows(+xs: List<&2,E.Value>, +kind: String) -> List<&2,E.Value>:
  match xs:
    case Nil{}: Nil{}
    case +h <> t:
      +tail = type_rows(t,kind)
      Bool.pick(List<&2,E.Value>,eq(h,"record_type",kind),h <> tail,tail)
def matching(+a: E.Value, +b: E.Value, +keys: List<&2,String>) -> Bool:
  match keys:
    case Nil{}: True{}
    case +k <> +t: same(get(a,k),get(b,k)) && matching(a,b,t)
def keys() -> List<&2,String>:
  ["case","preset","seed","threads","resolution","profile","schedule","warmup","frames","fragment_budget"]
def performance(+c: E.Value) -> Bool:
  eq(c,"schedule","static-perf-v2") || eq(c,"schedule","history-perf-v2")
def scope_keys(+c: E.Value) -> List<&2,String>:
  List.append(&2,String,["case","preset","seed","threads","resolution","profile","schedule","diagnostic","control","fragment_budget"],
    Bool.pick(List<&2,String>,performance(c),["warmup","frames"],Nil{}))
def scope_fields(+c: E.Value, +keys: List<&2,String>) -> List<&2,E.Field()>:
  match keys:
    case Nil{}: Nil{}
    case +k <> +t: (k,get(c,k)) <> scope_fields(c,t)
def scope(+c: E.Value) -> E.Value: E.Object{scope_fields(c,scope_keys(c))}
def order() -> E.Value: E.Array{strings(["off","on","on","off","off","on"])}
def configuration(+kind: String, +preset: String, +thread: String, +perf: Bool) -> E.Value:
  E.Object{[str("case",kind),str("preset",preset),str("seed","45"),str("threads",thread),str("resolution","1920x1080"),
    str("profile","full"),str("schedule",kind ++ Bool.pick(String,perf,"-perf-v2","-v1")),field("diagnostic",E.Null{}),
    field("control",E.Null{}),str("fragment_budget","2048"),str("warmup","120"),str("frames",Bool.pick(String,perf,"21600","3600")),field("order",order())]}
def case_matrix(+kind: String) -> List<&2,E.Value>:
  [configuration(kind,"small","1",False{}),configuration(kind,"small","6",False{}),configuration(kind,"small","12",False{}),
   configuration(kind,"large","1",False{}),configuration(kind,"large","6",False{}),configuration(kind,"large","12",False{})]
def matrix(+protocol: String) -> Result<&2,&2,String,List<&2,E.Value>>:
  match protocol:
    case "legacy": Done{List.append(&2,E.Value,case_matrix("static"),case_matrix("history"))}
    case "performance-v2": Done{[configuration("static","small","6",True{}),configuration("history","small","6",True{})]}
    case _: Fail{"unsupported calibration protocol"}
def plan(+protocol: String) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    +configs : List<&2,E.Value> <- matrix(protocol)
    return E.Object{[str("schema","megascene-evidence/1"),str("record_type","calibration_plan"),field("configurations",E.Array{configs}),
      field("configuration_count",num(E.count(configs))),field("control_count",num((6 * E.count(configs) : U32))),field("control_order",order()),
      field("pairs",E.Array{[E.Array{[num(0),num(1)]},E.Array{[num(2),num(3)]},E.Array{[num(4),num(5)]}]}),
      str("qualification_scope","only the exact tested configuration and workload regime")]}

def required_fields(+value: E.Value, keys: List<&2,String>) -> Result<&2,&2,String,Unit>:
  match keys:
    case Nil{}: Done{Unit{}}
    case key <> rest:
      do Result<&2,&2,String,Unit>:
        _ : E.Value <- E.required(value,key)
        required_fields(value,rest)
def natural_field(+value: E.Value, key: String) -> Result<&2,&2,String,E.Signed>:
  do Result<&2,&2,String,E.Signed>:
    v : E.Value <- E.required(value,key)
    E.natural(v)
def required_matching(+a: E.Value, +b: E.Value, keys: List<&2,String>, +message: String) -> Result<&2,&2,String,Unit>:
  match keys:
    case Nil{}: Done{Unit{}}
    case +key <> rest:
      do Result<&2,&2,String,Unit>:
        left : E.Value <- E.required(a,key)
        right : E.Value <- E.required(b,key)
        _ : Unit <- require(E.eq(left,right),message)
        required_matching(a,b,rest,message)
def scope_checked(+config: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    _ : Unit <- required_fields(config,scope_keys(config))
    return scope(config)
def record_types(rows: List<&2,E.Value>) -> Result<&2,&2,String,Unit>:
  match rows:
    case Nil{}: Done{Unit{}}
    case row <> rest:
      do Result<&2,&2,String,Unit>:
        _ : E.Value <- E.required(row,"record_type")
        record_types(rest)
def frame_sequence(+rows: List<&2,E.Value>, +frozen: List<&2,E.Value>, +previous: E.Value, +index: U32) -> Result<&2,&2,String,Unit>:
  match rows frozen:
    case Nil{} Nil{}: Done{Unit{}}
    case +r <> rest +f <> +planned:
      do Result<&2,&2,String,Unit>:
        _ : Unit <- required_fields(r,["frame"])
        _ : Unit <- require(eq(r,"frame",U32.show(index)),"common recorder frame/population mismatch")
        population : E.Value <- E.required(r,"population")
        phase : E.Value <- E.required(f,"phase")
        _ : Unit <- require(same(population,phase),"common recorder frame/population mismatch")
        +begin : E.Signed <- natural_field(r,"begin_ns")
        +end : E.Signed <- natural_field(r,"end_ns")
        _ : Unit <- require(E.int_le(begin,end),"common recorder frame interval mismatch")
        duration : E.Signed <- natural_field(r,"duration_ns")
        _ : Unit <- require(E.int_eq(duration,E.int_sub(end,begin)),"common recorder frame interval mismatch")
        _ : Unit <- require(U32.is_eq(index,0) || same(get(r,"begin_ns"),previous),"common frame boundary gap")
        frame_sequence(rest,planned,get(r,"end_ns"),(index + 1 : U32))
    case _ _: Fail{"incomplete common frame recorder"}
def action_sequence(+planned: List<&2,E.Value>, +begins: List<&2,E.Value>, +actions: List<&2,E.Value>, +edits: List<&2,E.Value>) -> Result<&2,&2,String,Unit>:
  match planned begins actions edits:
    case Nil{} Nil{} Nil{} Nil{}: Done{Unit{}}
    case +p <> ps +b <> bs +a <> az +e <> +es:
      do Result<&2,&2,String,Unit>:
        _ : Unit <- required_fields(p,["action","frame"])
        _ : Unit <- required_fields(a,["action","frame"])
        _ : Unit <- required_fields(b,["action","frame"])
        _ : Unit <- required_fields(e,["action","frame"])
        _ : Unit <- require(matching(a,p,["action","frame"]) && matching(b,p,["action","frame"]) && matching(e,p,["action","frame"]),"common action identity mismatch")
        _ : Unit <- required_fields(a,["accepted","removed_cells","outcome"])
        _ : Unit <- required_fields(get(a,"outcome"),["target_m"])
        _ : Unit <- required_fields(p,["expected_removed_cells","target_m"])
        _ : Unit <- required_fields(e,["accepted","removed_cells"])
        _ : Unit <- require(E.bool(get(a,"accepted")) && same(get(a,"removed_cells"),get(p,"expected_removed_cells")) &&
          same(get(get(a,"outcome"),"target_m"),get(p,"target_m")) && E.bool(get(e,"accepted")) &&
          same(get(e,"removed_cells"),get(a,"removed_cells")),"common scalar action outcome mismatch")
        begin : E.Signed <- natural_field(b,"begin_ns")
        +end : E.Signed <- natural_field(e,"end_ns")
        _ : Unit <- require(E.int_le(begin,end),"common edit interval mismatch")
        duration : E.Signed <- natural_field(e,"duration_ns")
        begin : E.Signed <- natural_field(e,"begin_ns")
        _ : Unit <- require(E.int_eq(duration,E.int_sub(end,begin)),"common edit interval mismatch")
        action_sequence(ps,bs,az,es)
    case _ _ _ _: Fail{"common action outcome missing"}
def reference_sequence(+records: E.Value, +frozen: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    _ : Unit <- record_types(E.array(records))
    _ : Unit <- required_fields(frozen,["frames","actions"])
    +frames : List<&2,E.Value> = type_rows(E.array(records),"frame")
    +actions : List<&2,E.Value> = type_rows(E.array(records),"action")
    +begins : List<&2,E.Value> = type_rows(E.array(records),"edit_begin")
    +edits : List<&2,E.Value> = type_rows(E.array(records),"edit")
    +planned : List<&2,E.Value> = array(frozen,"actions")
    _ : Unit <- require(U32.is_eq(E.count(frames),E.count(array(frozen,"frames"))),"incomplete common frame recorder")
    _ : Unit <- frame_sequence(frames,array(frozen,"frames"),E.Null{},0)
    _ : Unit <- require(U32.is_eq(E.count(actions),E.count(begins)) && U32.is_eq(E.count(actions),E.count(edits)) &&
      U32.is_eq(E.count(actions),E.count(planned)),"common action outcome missing")
    _ : Unit <- action_sequence(planned,begins,actions,edits)
    return E.Array{[E.Array{frames},E.Array{actions},E.Array{edits}]}

def magnitude(+s: E.Signed) -> S.Integer:
  match s:
    case E.Sign{n,m}: m
def at_rational(xs: List<&2,E.Rational>, +index: U32) -> E.Rational:
  Maybe.default(&2,E.Rational,List.get(&2,E.Rational,xs,U32.to_nat(index)),E.Rational{zero(),S.Integer.one()})
def rint(+n: U32) -> E.Rational: E.rational(num(n))
def rgt(+a: E.Rational, +b: E.Rational) -> Bool: Bool.not(E.rational_le(a,b))
def rmin(+a: E.Rational, +b: E.Rational) -> E.Rational: Bool.pick(E.Rational,E.rational_le(a,b),a,b)
def rmax(+a: E.Rational, +b: E.Rational) -> E.Rational: Bool.pick(E.Rational,E.rational_le(a,b),b,a)
def rvalue(+r: E.Rational) -> E.Value:
  match r:
    case E.Rational{n,d}: E.ratio(n,d)
def observation_rows(+controls: List<&2,E.Value>, +name: String, +position: U32) -> List<&2,E.Value>:
  match controls:
    case Nil{}: Nil{}
    case +c <> +rest:
      E.Object{[field("position",num(position)),field("mode",get(c,"mode")),field("attempt_id",get(c,"attempt_id")),
        field("value_ns",get(get(c,"statistics"),name)),field("ordinary_count",get(c,"ordinary_count")),
        field("accepted_edit_count",get(c,"accepted_edit_count")),field("measured_duration_ns",get(c,"measured_duration_ns"))]} <>
        observation_rows(rest,name,(position + 1 : U32))
def sufficient(+controls: List<&2,E.Value>) -> Bool:
  match controls:
    case Nil{}: True{}
    case +c <> +rest: E.truth(get(c,"sufficient")) && sufficient(rest)
def within(+off: E.Rational, +on: E.Rational) -> Bool:
  match off on:
    case E.Rational{offn,offd} E.Rational{onn,ond}:
      E.int_negative(onn) || T.within_five_percent(S.Integer.mul(E.int_abs(offn),ond),S.Integer.mul(E.int_abs(onn),offd))
def gate(+state: String, +reason: String, +scope: String, +paths: List<&2,String>) -> E.Value:
  E.Object{[str("status",state),str("reason",reason),str("scope",scope),field("evidence",E.Array{strings(paths)})]}
def measurement(+state: String, +reason: String, +scope: String, +unit: String) -> E.Value:
  E.Object{[str("status",state),str("reason",reason),str("scope",scope),str("unit",unit),field("value",E.Null{})]}
def durations(+rows: List<&2,E.Value>, +population: String, +accepted: Bool) -> List<&2,E.Value>:
  match rows:
    case Nil{}: Nil{}
    case +r <> rest:
      +tail = durations(rest,population,accepted)
      Bool.pick(List<&2,E.Value>,Bool.pick(Bool,accepted,E.truth(get(r,"accepted")),eq(r,"population",population)),get(r,"duration_ns") <> tail,tail)
def measured_rows(+rows: List<&2,E.Value>) -> List<&2,E.Value>:
  match rows:
    case Nil{}: Nil{}
    case +r <> rest:
      +tail = measured_rows(rest)
      Bool.pick(List<&2,E.Value>,eq(r,"population","startup") || eq(r,"population","warmup"),tail,r <> tail)
def last(+rows: List<&2,E.Value>) -> E.Value:
  match rows:
    case Nil{}: E.Null{}
    case +h <> Nil{}: h
    case +h <> +rest: last(rest)
def population_count(+rows: List<&2,E.Value>, +kind: String) -> U32:
  match rows:
    case Nil{}: 0
    case +r <> +rest: (Bool.to_u32(eq(r,"population",kind)) + population_count(rest,kind) : U32)
def all_types(+rows: List<&2,E.Value>, +allowed: List<&2,E.Value>) -> Bool:
  match rows:
    case Nil{}: True{}
    case +r <> +rest: has_string(allowed,text(r,"record_type")) && all_types(rest,allowed)
def checkpoint_named(+rows: List<&2,E.Value>, +name: String, +current: E.Value) -> E.Value:
  match rows:
    case Nil{}: current
    case +r <> +rest: checkpoint_named(rest,name,Bool.pick(E.Value,eq(r,"name",name),r,current))
def append_error(+errors: List<&2,E.Value>, checked: Result<&2,&2,String,Unit>) -> List<&2,E.Value>:
  match checked:
    case Done{_}: errors
    case Fail{reason}: List.append(&2,E.Value,errors,[E.Text{E.exception_text(reason)}])
def duration_checks(+rows: List<&2,E.Value>) -> Result<&2,&2,String,Unit>:
  match rows:
    case Nil{}: Done{Unit{}}
    case +r <> +rest:
      do Result<&2,&2,String,Unit>:
        _ : E.Signed <- E.natural(get(r,"duration_ns"))
        duration_checks(rest)
def off_performance(+enabled: Bool, +result: E.Value, +frames: List<&2,E.Value>, +populations: E.Value) -> E.Value:
  match enabled:
    case False{}: result
    case True{}:
      +measured = measured_rows(frames)
      +populations = E.merge(populations,E.Object{[("edit",R.distribution(durations(frames,"edit",False{}))),
        ("motion",R.distribution(durations(frames,"motion",False{}))),("warmup",R.distribution(durations(frames,"warmup",False{}))),
        ("combined",R.distribution(R.duration_values(measured)))]})
      +interval = Bool.pick(E.Signed,U32.is_eq(E.count(measured),0),zero(),
        E.int_sub(E.int(get(last(measured),"end_ns")),E.int(get(E.at(measured,0),"begin_ns"))))
      E.merge(result,E.Object{[("populations",populations),("measured_interval_ns",E.int_string(interval))]})

def scalar_rows(rows: List<&2,E.Value>) -> List<&2,E.Value>:
  match rows:
    case Nil{}: Nil{}
    case +r <> rest: E.Array{[get(r,"frame"),get(r,"action"),get(r,"accepted"),get(r,"removed_cells"),get(r,"outcome")]} <> scalar_rows(rest)
def scalar(rows: List<&2,E.Value>) -> E.Value:
  E.Array{scalar_rows(type_rows(rows,"action"))}

def endpoint_rows(+rows: List<&2,E.Value>, +final: E.Signed) -> List<&2,E.Value>:
  match rows:
    case Nil{}: Nil{}
    case +r <> rest:
      +tail = endpoint_rows(rest,final)
      Bool.pick(List<&2,E.Value>,eq(r,"record_type","checkpoint") && (eq(r,"frame","0") || eq(r,"frame",E.int_show(final))),
        E.Array{[get(r,"frame"),get(r,"sha256"),get(r,"body_sha256")]} <> tail,tail)
def artifacts(+rows: List<&2,E.Value>, +accumulated: E.Value) -> E.Value:
  match rows:
    case Nil{}: accumulated
    case +r <> +rest: artifacts(rest,E.put(accumulated,text(r,"path"),get(r,"sha256")))
def valid_statistic(+value: E.Value) -> Bool:
  match value:
    case E.Null{}: True{}
    case E.Number{+s}: E.rational_le(rint(0),E.rational(E.Number{s}))
    case E.Real{+s,d}: Bool.not(String.contains(s,"inf") || String.contains(s,"nan")) && E.rational_le(rint(0),E.rational(E.Real{s,d}))
    case _: False{}
def edit_distribution(+summary: E.Value) -> E.Value:
  Bool.pick(E.Value,E.has(summary,"accepted_edits"),get(summary,"accepted_edits"),get(get(summary,"populations"),"accepted_edits"))
def paired_statistic(+off: E.Value, +on: E.Value, +field_name: String) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    +a : E.Value = get(off,field_name)
    +b : E.Value = get(on,field_name)
    _ : Unit <- require(valid_statistic(a),"invalid off statistic")
    _ : Unit <- require(valid_statistic(b),"invalid on statistic")
    return E.Object{[("off_ns",a),("on_ns",b),("off_count",get(off,"count")),("on_count",get(on,"count")),
      ("on_over_off",Bool.pick(E.Value,E.truth(a) && Bool.not(E.is_null(b)),E.Divide{b,a},E.Null{}))]}
def edit_statistics(+history: Bool, +result: E.Value, +off: E.Value, +on: E.Value) -> Result<&2,&2,String,E.Value>:
  match history:
    case False{}: Done{result}
    case True{}:
      do Result<&2,&2,String,E.Value>:
        edit : E.Value <- paired_statistic(edit_distribution(off),edit_distribution(on),"p95")
        return E.put(result,"accepted_edits_p95",edit)
def power10(+n: Nat) -> S.Integer:
  match n:
    case 0n: S.Integer.one()
    case 1n+p: S.Integer.mul(S.Integer.ten(),power10(p))
def decimal_parts(+parts: List<&2,String>) -> E.Rational:
  match parts:
    case +whole <> +fraction <> Nil{}:
      E.Rational{E.int_text(whole ++ fraction),power10(String.length(fraction))}
    case +whole <> Nil{}: E.Rational{E.int_text(whole),S.Integer.one()}
    case _: rint(0)
def exponent_text(+value: String) -> String:
  match value:
    case SCon{'+',rest}: rest
    case _: value
def decimal_exponent(+mantissa: E.Rational, +exponent: E.Signed) -> E.Rational:
  +factor = E.rational_integer(E.Sign{False{},power10(U32.to_nat(S.Integer.to_u32(E.int_abs(exponent))))})
  Bool.pick(E.Rational,E.int_negative(exponent),E.rational_div(mantissa,factor),E.rational_mul(mantissa,factor))
def decimal_read(+parts: List<&2,String>) -> E.Rational:
  match parts:
    case +mantissa <> +exponent <> Nil{}: decimal_exponent(decimal_parts(String.split(mantissa,'.')),E.int_text(exponent_text(exponent)))
    case +mantissa <> Nil{}: decimal_parts(String.split(mantissa,'.'))
    case _: rint(0)
def decimal(+value: E.Value) -> E.Rational: decimal_read(String.split(E.decimal_text(value),'e'))
def round_division_result(result: S.Integer & S.Integer, +d: S.Integer) -> S.Integer:
  (+q,+remainder) = result
  +twice = S.Integer.double(remainder)
  +above = Bool.not(S.Integer.le(twice,d))
  +odd = S.Integer.eq(S.Integer.mod(q,S.Integer.two()),S.Integer.one())
  Bool.pick(S.Integer,above || (S.Integer.eq(twice,d) && odd),S.Integer.inc(q),q)
def round_division(+n: S.Integer, +d: S.Integer) -> S.Integer:
  round_division_result(S.Integer.divmod(n,d),d)
@unsafe def decimal_small(+fuel: Nat, +n: S.Integer, +d: S.Integer, +scale: S.Integer) -> E.Rational:
  match fuel:
    case 0n: E.Rational{E.Sign{False{},round_division(n,d)},scale}
    case 1n+p:
      decimal_small_step(S.Integer.le(d,n),p,n,d,scale)
@unsafe def decimal_small_step(+enough: Bool, +fuel: Nat, +n: S.Integer, +d: S.Integer, +scale: S.Integer) -> E.Rational:
  match enough:
    case True{}:
      +factor = power10(27n)
      E.Rational{E.Sign{False{},round_division(S.Integer.mul(n,factor),d)},S.Integer.mul(scale,factor)}
    case False{}: decimal_small(fuel,S.Integer.mul(n,S.Integer.ten()),d,S.Integer.mul(scale,S.Integer.ten()))
def decimal_round_large(+large: Bool, +n: S.Integer, +d: S.Integer, +digits: Nat) -> E.Rational:
  match large:
    case True{}:
      +factor = power10(Nat.sub(digits,28n))
      E.Rational{E.Sign{False{},S.Integer.mul(round_division(n,S.Integer.mul(d,factor)),factor)},S.Integer.one()}
    case False{}:
      +factor = power10(Nat.sub(28n,digits))
      E.Rational{E.Sign{False{},round_division(S.Integer.mul(n,factor),d)},factor}
def decimal_round_sign(+negative: Bool, +value: E.Rational) -> E.Rational:
  match negative:
    case False{}: value
    case True{}: E.rational_neg(value)
def absolute(+r: E.Rational) -> E.Rational:
  match r:
    case E.Rational{E.Sign{_,n},d}: E.Rational{E.Sign{False{},n},d}
def sum(+samples: List<&2,E.Value>, +accumulated: E.Signed) -> E.Signed:
  match samples:
    case Nil{}: accumulated
    case +v <> +rest: sum(rest,E.int_add(accumulated,E.int(v)))
def percentile(+samples: List<&2,E.Value>, +rank: U32) -> E.Value:
  +ordered = List.sort(E.Value,+a => +b => E.int_le(E.int(a),E.int(b)),samples)
  Bool.pick(E.Value,U32.is_eq(E.count(samples),0),E.Null{},E.at(ordered,((E.count(samples) * rank + 99 : U32) / 100 - 1 : U32)))
def exact_pair(+r: E.Rational) -> E.Value:
  match r:
    case E.Rational{n,d}: E.Array{[E.int_value(n),E.Number{S.Integer.show(d)}]}
def reported_statistics(+summary: E.Value, +history: Bool) -> E.Value:
  +ordinary = get(get(summary,"populations"),"ordinary")
  +fields : List<&2,E.Field()> = [("ordinary_mean",get(ordinary,"mean")),("ordinary_p95",get(ordinary,"p95")),("ordinary_p99",get(ordinary,"p99"))]
  E.Object{Bool.pick(List<&2,E.Field()>,history,List.append(&2,E.Field(),fields,[("accepted_edits_p95",get(edit_distribution(summary),"p95"))]),fields)}
def series_scope(+configs: List<&2,E.Value>, +expected: E.Value) -> Bool:
  match configs:
    case Nil{}: False{}
    case +c <> +rest: same(scope(c),expected) || series_scope(rest,expected)
def series_order(+controls: List<&2,E.Value>, +index: U32) -> Bool:
  match controls:
    case Nil{}: True{}
    case +c <> +rest: same(get(c,"mode"),E.at(E.array(order()),index)) && series_order(rest,(index + 1 : U32))
def assessment_start(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    +series : E.Value = get(request,"series")
    _ : Unit <- require(eq(series,"schema","megascene-evidence/1") && same(get(series,"order"),order()),"unsupported series")
    +protocol : String = Bool.pick(String,E.has(series,"protocol"),text(series,"protocol"),"legacy")
    configs : List<&2,E.Value> <- matrix(protocol)
    _ : Unit <- require(series_scope(configs,get(series,"scope")),"series outside accepted calibration matrix")
    _ : Unit <- require((E.count(array(series,"controls")) <= 6 : U32) && series_order(array(series,"controls"),0),"control order mismatch")
    return E.Object{[str("schema","megascene-evidence/1"),str("record_type","calibration_assessment"),field("scope",get(series,"scope")),
      field("order",order()),str("status","insufficient"),field("control_count",num(E.count(array(series,"controls")))),
      field("controls",E.Array{Nil{}}),field("pairs",E.Array{Nil{}}),field("statistics",E.Object{Nil{}}),
      field("on_acceptance_candidates",E.Array{Nil{}}),field("reference",get(request,"path")),str("qualification_scope","exact tested configuration only"),
      str("transient_off_state_equality","unproven"),field("cost_subtraction",E.Boolean{False{}})]}
def states(+fields: List<&2,E.Field()>) -> List<&2,E.Value>:
  match fields:
    case Nil{}: Nil{}
    case (k,v) <> +rest: get(v,"status") <> states(rest)
def assessment_complete(+complete: Bool, +report: E.Value, +statistics: E.Value, +state: String) -> E.Value:
  match complete:
    case False{}: E.put(report,"reason",E.Text{"six complete controls and three equivalent pairs required"})
    case True{}: E.merge(report,E.Object{[("statistics",statistics),("status",E.Text{state}),("reason",E.Text{Bool.pick(String,String.eq(state,"pass"),
      "all applicable pairs within the accepted bound",Bool.pick(String,String.eq(state,"noisy"),"off controls vary by more than 5%",
      Bool.pick(String,String.eq(state,"failed"),"at least one paired increase exceeds 5%","required population or denominator missing")))})]})
def has_types(+rows: List<&2,E.Value>, +types: List<&2,String>) -> Bool:
  match rows:
    case Nil{}: False{}
    case +r <> +rest: R.one_of(text(r,"record_type"),types) || has_types(rest,types)
def ordinary_rows(rows: List<&2,E.Value>) -> List<&2,E.Value>:
  match rows:
    case Nil{}: Nil{}
    case +r <> rest:
      +tail = ordinary_rows(rest)
      Bool.pick(List<&2,E.Value>,eq(r,"population","ordinary"),r <> tail,tail)
def accepted_rows(rows: List<&2,E.Value>) -> List<&2,E.Value>:
  match rows:
    case Nil{}: Nil{}
    case +r <> rest:
      +tail = accepted_rows(rest)
      Bool.pick(List<&2,E.Value>,E.truth(get(r,"accepted")),r <> tail,tail)
def text_values(rows: List<&2,E.Value>) -> List<&2,String>:
  match rows:
    case Nil{}: Nil{}
    case r <> rest: E.text(r) <> text_values(rest)
def duration_valid(checked: Result<&2,&2,String,Unit>) -> Bool:
  match checked:
    case Done{_}: True{}
    case Fail{_}: False{}
def duration_errors(+errors: List<&2,E.Value>, checked: Result<&2,&2,String,Unit>) -> List<&2,E.Value>:
  match checked:
    case Done{_}: errors
    case Fail{message}: List.append(&2,E.Value,errors,[E.Text{"damaged common duration: " ++ E.exception_text(message)}])
def validation_run(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    +run : E.Value = get(request,"run")
    _ : Unit <- require(Bool.not(E.is_null(run)),"missing " ++ text(request,"mode") ++ " mode validation")
    _ : Unit <- require(E.eq(get(run,"returncode"),num(0)) && E.truth(get(run,"archive")),"missing mode validation")
    return E.Null{}
def control_entry(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    _ : Unit <- require(E.eq(get(request,"returncode"),num(0)) && E.truth(get(request,"archive")) && Bool.not(E.truth(get(request,"measurement_exclusion"))),"failed or excluded control")
    return E.Null{}
def report_control(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    +report : E.Value = get(request,"report")
    +value : E.Value = get(request,"value")
    +binding : E.Value = get(request,"binding")
    _ : Unit <- require(E.is_null(binding) || Bool.not(E.has(report,"binding")) || same(get(report,"binding"),binding),"performance calibration runtime/schedule differ")
    +report : E.Value = Bool.pick(E.Value,E.is_null(binding),report,E.put(report,"binding",binding))
    return Bool.pick(E.Value,eq(value,"mode","on"),E.put(report,"on_acceptance_candidates",E.Array{List.append(&2,E.Value,array(report,"on_acceptance_candidates"),
      [E.Object{[("attempt_id",get(value,"attempt_id")),("archive",get(value,"archive")),str("scope","complete instrumented observation; separate acceptance gates still apply")]}])}),report)
def pair_record(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    +pair : E.Value = get(request,"pair")
    +report : E.Value = get(request,"report")
    _ : Unit <- require(eq(pair,"status","pass"),"paired equivalence evidence unavailable")
    return E.put(report,"pairs",E.Array{List.append(&2,E.Value,array(report,"pairs"),[E.Object{[("positions",get(request,"positions")),
      ("off_attempt_id",get(pair,"off")),("on_attempt_id",get(pair,"on")),str("endpoint_and_action_agreement","pass")]}])})
def peer_workload(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    +config : E.Value = get(request,"config")
    +peer : E.Value = get(get(request,"peer_manifest"),"effective")
    _ : Unit <- require(eq(peer,"calibration_mode",Bool.pick(String,eq(config,"calibration_mode","off"),"on","off")),"peer validation mode mismatch")
    _ : Unit <- required_matching(peer,config,keys(),"peer validation workload mismatch")
    return E.Null{}
def pair_kinds(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    _ : Unit <- require(eq(get(request,"off_manifest"),"attempt_kind","calibration_off") && eq(get(request,"on_manifest"),"attempt_kind","calibration_on"),"paired attempt kinds must be calibration_off and calibration_on")
    return E.Null{}
def exact_sign(+n: E.Signed, +d: E.Signed) -> E.Rational:
  E.Rational{Bool.pick(E.Signed,E.int_negative(d),E.int_neg(n),n),magnitude(d)}
def endpoint_validation(+checkpoints: List<&2,E.Value>, +validation: E.Value, +names: List<&2,String>) -> Result<&2,&2,String,Unit>:
  match checkpoints names:
    case Nil{} Nil{}: Done{Unit{}}
    case +r <> rest +name <> +tail:
      do Result<&2,&2,String,Unit>:
        +catalog : E.Value = checkpoint_named(array(validation,"checkpoints"),name,E.Null{})
        _ : E.Value <- E.required(r,"sha256")
        _ : Unit <- require(Bool.not(E.is_null(catalog)),"missing field:" ++ name)
        _ : Unit <- required_matching(r,catalog,["sha256","body_sha256"],"off endpoint differs from complete validation: " ++ name)
        endpoint_validation(rest,validation,tail)
    case _ _: Fail{"off endpoint checkpoints missing or duplicated"}
def endpoints(+rows: List<&2,E.Value>, +final: E.Signed) -> E.Value:
  E.Array{endpoint_rows(rows,final)}
def pair_statistics(+off: E.Value, +on: E.Value, +history: Bool) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    +a : E.Value = get(get(off,"populations"),"ordinary")
    +b : E.Value = get(get(on,"populations"),"ordinary")
    mean : E.Value <- paired_statistic(a,b,"mean")
    p95 : E.Value <- paired_statistic(a,b,"p95")
    p99 : E.Value <- paired_statistic(a,b,"p99")
    edit_statistics(history,E.Object{[("ordinary_mean",mean),("ordinary_p95",p95),("ordinary_p99",p99)]},off,on)
def compare_modes(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    +offm : E.Value = get(request,"off_manifest")
    +onm : E.Value = get(request,"on_manifest")
    +offs : E.Value = get(request,"off_summary")
    +ons : E.Value = get(request,"on_summary")
    _ : Unit <- require(eq(offm,"attempt_kind","calibration_off") && eq(onm,"attempt_kind","calibration_on"),"paired attempt kinds must be calibration_off and calibration_on")
    _ : Unit <- required_matching(get(offm,"effective"),get(onm,"effective"),keys(),"paired workloads differ")
    _ : Unit <- require(same(artifacts(array(offm,"artifacts"),E.Object{Nil{}}),artifacts(array(onm,"artifacts"),E.Object{Nil{}})),"paired runtime artifacts differ")
    _ : Unit <- require(String.eq(status(offs,"endpoint_agreement"),"pass") && String.eq(status(ons,"state_correctness"),"pass"),"paired evidence incomplete")
    _ : Unit <- require(Bool.not(E.truth(get(request,"off_ref_errors")) || E.truth(get(request,"on_ref_errors"))),"paired reference stream damaged")
    _ : Unit <- require(same(scalar(array(request,"off_ref")),scalar(array(request,"on_ref"))),"paired scalar action outcomes differ")
    _ : Unit <- require(Bool.not(E.truth(get(request,"off_cpu_errors")) || E.truth(get(request,"on_cpu_errors"))),"paired endpoint stream damaged")
    +final : E.Signed = E.int_add(E.int(get(get(offm,"effective"),"warmup")),E.int(get(get(offm,"effective"),"frames")))
    _ : Unit <- require(same(endpoints(array(request,"off_cpu"),final),endpoints(array(request,"on_cpu"),final)),"paired initial/final canonical states differ")
    stats : E.Value <- pair_statistics(offs,ons,eq(get(offm,"effective"),"case","history"))
    return E.Object{[str("schema","megascene-evidence/1"),str("record_type","calibration_pair"),str("status","pass"),
      field("off",get(offm,"attempt_id")),field("on",get(onm,"attempt_id")),str("scope","initial/final canonical state and scalar action outcomes only"),
      str("transient_state_equality","unproven"),str("benchmark_qualification","not_applicable"),field("observed_statistics",stats),
      str("statistics_scope","descriptive paired values; no cost subtraction or calibration pass")]}

def decimal_round_integer(+small: Bool, +n: S.Integer, +d: S.Integer, +digits: Nat) -> E.Rational:
  match small:
    case True{}: decimal_small(1n+String.length(S.Integer.show(d)),n,d,S.Integer.one())
    case False{}: decimal_round_large(Nat.is_gt(digits,28n),n,d,digits)
def decimal_round_positive(+n: S.Integer, +d: S.Integer) -> E.Rational:
  +quotient = Pair.fst(S.Integer,S.Integer,S.Integer.divmod(n,d))
  +digits = String.length(S.Integer.show(quotient))
  decimal_round_integer(S.Integer.eq(quotient,S.Integer.zero()),n,d,digits)
def decimal_round(+value: E.Rational) -> E.Rational:
  match value:
    case E.Rational{E.Sign{negative,n},d}: decimal_round_sign(negative,decimal_round_positive(n,d))
def stats_check(+values: List<&2,E.Field()>, +reported: E.Value) -> Result<&2,&2,String,Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case (+name,+value) <> +rest:
      do Result<&2,&2,String,Unit>:
        +observed : E.Value = get(reported,name)
        _ : Unit <- require(Bool.not(E.is_null(value) || E.is_null(observed)) && E.rational_le(
          absolute(decimal_round(E.rational_sub(decimal(observed),E.rational(value)))),E.Rational{integer(1),magnitude(integer(1000))}),
          "reported statistic differs from common recorder: " ++ name)
        stats_check(rest,reported)
def expected_frame_count(+scope: E.Value, perf: Bool) -> Result<&2,&2,String,E.Signed>:
  match perf:
    case False{}: Done{integer(3721)}
    case True{}:
      do Result<&2,&2,String,E.Signed>:
        warmup : E.Signed <- natural_field(scope,"warmup")
        frames : E.Signed <- natural_field(scope,"frames")
        return E.int_add(integer(1),E.int_add(warmup,frames))
def validation_count(+validation: E.Value, +expected: E.Signed, +reason: String) -> Result<&2,&2,String,Unit>:
  do Result<&2,&2,String,Unit>:
    state : E.Value <- E.required(validation,"status")
    _ : Unit <- require(E.eq(state,E.Text{"pass"}),reason)
    frames : E.Signed <- natural_field(validation,"checked_frames")
    require(E.int_eq(frames,expected),reason)
def values_header(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    +manifest : E.Value = get(request,"manifest")
    +summary : E.Value = get(request,"summary")
    +validation : E.Value = get(request,"validation")
    +expected : E.Value = get(request,"scope")
    +mode : String = text(request,"mode")
    _ : Unit <- require(Bool.not(E.truth(get(manifest,"synthetic")) || E.truth(get(summary,"synthetic"))),"synthetic control")
    kind : E.Value <- E.required(manifest,"attempt_kind")
    _ : Unit <- require(E.eq(kind,E.Text{"calibration_" ++ mode}),"control scope/mode mismatch")
    effective : E.Value <- E.required(manifest,"effective")
    actual_scope : E.Value <- scope_checked(effective)
    _ : Unit <- require(same(actual_scope,expected),"control scope/mode mismatch")
    observed_id : E.Value <- E.required(summary,"attempt_id")
    admitted_id : E.Value <- E.required(manifest,"attempt_id")
    _ : Unit <- require(same(observed_id,admitted_id),"control incomplete")
    completion : E.Value <- E.required(summary,"schedule_completion")
    completion_status : E.Value <- E.required(completion,"status")
    _ : Unit <- require(E.eq(completion_status,E.Text{"pass"}),"control incomplete")
    expected_frames : E.Signed <- expected_frame_count(expected,performance(expected))
    _ : Unit <- validation_count(validation,expected_frames,"control lacks complete mode validation")
    termination : E.Value <- E.required(summary,"termination")
    cause : E.Value <- E.required(termination,"cause")
    _ : Unit <- require(E.eq(cause,E.Text{"normal_exit"}) && Bool.not(E.truth(get(summary,"evidence_errors"))),"control evidence/termination invalid")
    correctness : E.Value <- E.required(summary,Bool.pick(String,String.eq(mode,"off"),"endpoint_agreement","state_correctness"))
    correctness_status : E.Value <- E.required(correctness,"status")
    _ : Unit <- require(E.eq(correctness_status,E.Text{"pass"}),
      Bool.pick(String,String.eq(mode,"off"),"off endpoint evidence missing","on state evidence missing"))
    return E.Null{}
def pair_header(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    +offm : E.Value = get(request,"off_manifest")
    +onm : E.Value = get(request,"on_manifest")
    +offs : E.Value = get(request,"off_summary")
    +ons : E.Value = get(request,"on_summary")
    _ : Unit <- require(eq(offm,"attempt_kind","calibration_off") && eq(onm,"attempt_kind","calibration_on"),"paired attempt kinds must be calibration_off and calibration_on")
    _ : Unit <- required_matching(get(offm,"effective"),get(onm,"effective"),keys(),"paired workloads differ")
    _ : Unit <- require(same(artifacts(array(offm,"artifacts"),E.Object{Nil{}}),artifacts(array(onm,"artifacts"),E.Object{Nil{}})),"paired runtime artifacts differ")
    _ : Unit <- require(String.eq(status(offs,"endpoint_agreement"),"pass") && String.eq(status(ons,"state_correctness"),"pass"),"paired evidence incomplete")
    return E.Null{}
def peer_binding(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    +config : E.Value = get(request,"config")
    +peer : E.Value = get(get(request,"peer_manifest"),"effective")
    _ : Unit <- require(eq(peer,"calibration_mode",Bool.pick(String,eq(config,"calibration_mode","off"),"on","off")),"peer validation mode mismatch")
    _ : Unit <- required_matching(peer,config,keys(),"peer validation workload mismatch")
    _ : Unit <- require(same(get(get(request,"peer_identity"),"artifacts"),get(get(request,"own_identity"),"artifacts")),"peer validation runtime artifacts differ")
    _ : Unit <- require(E.truth(get(request,"has_validation_files")),"peer validation archive incomplete")
    return E.Null{}
def pair_reference(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    _ : Unit <- require(Bool.not(E.truth(get(request,"off_ref_errors")) || E.truth(get(request,"on_ref_errors"))),"paired reference stream damaged")
    _ : Unit <- require(same(scalar(array(request,"off_ref")),scalar(array(request,"on_ref"))),"paired scalar action outcomes differ")
    return E.Null{}
def pair_indices(request: E.Value) -> E.Value:
  +count = E.count(E.array(request))
  E.Array{List.append(&2,E.Value,Bool.pick(List<&2,E.Value>,(count >= 2 : U32),[E.Object{[("off",num(0)),("on",num(1)),("positions",E.Array{[num(1),num(2)]})]}],Nil{}),
    List.append(&2,E.Value,Bool.pick(List<&2,E.Value>,(count >= 4 : U32),[E.Object{[("off",num(3)),("on",num(2)),("positions",E.Array{[num(3),num(4)]})]}],Nil{}),
      Bool.pick(List<&2,E.Value>,(count >= 6 : U32),[E.Object{[("off",num(4)),("on",num(5)),("positions",E.Array{[num(5),num(6)]})]}],Nil{})))}
def exact(+control: E.Value, +name: String) -> E.Rational:
  +pair = E.array(get(get(control,"exact_statistics"),name))
  exact_sign(E.int(E.at(pair,0)),E.int(E.at(pair,1)))
def classify_statistic(+name: String, +controls: List<&2,E.Value>) -> E.Value:
  +a = exact(E.at(controls,0),name)
  +b = exact(E.at(controls,3),name)
  +c = exact(E.at(controls,4),name)
  +x = exact(E.at(controls,1),name)
  +y = exact(E.at(controls,2),name)
  +z = exact(E.at(controls,5),name)
  +valid = rgt(a,rint(0)) && rgt(b,rint(0)) && rgt(c,rint(0))
  +population = sufficient(controls)
  +noisy = Bool.not(within(rmin(a,rmin(b,c)),rmax(a,rmax(b,c))))
  +failed = Bool.not(within(a,x)) || Bool.not(within(b,y)) || Bool.not(within(c,z))
  +ratios : List<&2,E.Rational> = [E.rational_div(x,a),E.rational_div(y,b),E.rational_div(z,c)]
  +state = Bool.pick(String,Bool.not(population && valid),"insufficient",Bool.pick(String,noisy,"noisy",Bool.pick(String,failed,"failed","pass")))
  E.Object{[str("status",state),field("observations",E.Array{observation_rows(controls,name,1)}),
    field("off_variation",Bool.pick(E.Value,valid,rvalue(E.rational_sub(E.rational_div(rmax(a,rmax(b,c)),rmin(a,rmin(b,c))),rint(1))),E.Null{})),
    field("paired_on_over_off",E.Array{Bool.pick(List<&2,E.Value>,valid,[rvalue(at_rational(ratios,0)),rvalue(at_rational(ratios,1)),rvalue(at_rational(ratios,2))],Nil{})}),
    field("max_paired_on_over_off",Bool.pick(E.Value,valid,rvalue(rmax(at_rational(ratios,0),rmax(at_rational(ratios,1),at_rational(ratios,2)))),E.Null{})),
    field("population_sufficient",E.Boolean{population}),field("valid_denominators",E.Boolean{valid}),
    field("threshold",E.ratio(integer(5),magnitude(integer(100)))),str("reason",Bool.pick(String,Bool.not(population),"population below the required minimum",
      Bool.pick(String,Bool.not(valid),"zero or invalid off denominator",Bool.pick(String,String.eq(state,"noisy"),"off variation exceeds 5%",
        Bool.pick(String,String.eq(state,"failed"),"one or more paired increases exceed 5%","all paired increases are at most 5%")))))]}

def statistics_fields(+names: List<&2,String>, +controls: List<&2,E.Value>) -> List<&2,E.Field()>:
  match names:
    case Nil{}: Nil{}
    case +name <> +rest: (name,classify_statistic(name,controls)) <> statistics_fields(rest,controls)
def assessment_finish(+report: E.Value) -> E.Value:
  +statistics : E.Value = E.Object{statistics_fields(Bool.pick(List<&2,String>,eq(get(report,"scope"),"case","static"),
    ["ordinary_mean","ordinary_p95","ordinary_p99"],["ordinary_mean","ordinary_p95","ordinary_p99","accepted_edits_p95"]),array(report,"controls"))}
  +states = states(E.fields(statistics))
  +state = Bool.pick(String,has_string(states,"insufficient"),"insufficient",Bool.pick(String,has_string(states,"noisy"),"noisy",
    Bool.pick(String,has_string(states,"failed"),"failed","pass")))
  assessment_complete(U32.is_eq(E.count(array(report,"pairs")),3),report,statistics,state)
def select_configuration(+configs: List<&2,E.Value>, +request: E.Value) -> Result<&2,&2,String,E.Value>:
  match configs:
    case Nil{}: Fail{"configuration outside calibration protocol"}
    case +c <> rest:
      S.delayed(Result<&2,&2,String,E.Value>,matching(c,request,["case","preset","threads"]),
        _ => Done{c},_ => select_configuration(rest,request))
def series_configuration(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    configs : List<&2,E.Value> <- matrix(text(request,"protocol"))
    select_configuration(configs,request)
def resumable_runs(rows: List<&2,E.Value>) -> Result<&2,&2,String,Unit>:
  match rows:
    case Nil{}: Done{Unit{}}
    case +run <> rest:
      do Result<&2,&2,String,Unit>:
        code : E.Value <- E.required(run,"returncode")
        _ : Unit <- require(E.eq(code,num(0)) && Bool.not(E.truth(get(run,"binding_error"))) &&
          Bool.not(E.truth(get(run,"measurement_exclusion"))),"series contains a failed run; retain it without automatic rerun")
        resumable_runs(rest)
def series_roots(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    +series : E.Value = get(request,"series")
    archive : E.Value <- E.required(series,"archive_root")
    _ : Unit <- require(same(archive,get(request,"archive")),"resume paths differ from original series")
    work : E.Value <- E.required(series,"work_root")
    _ : Unit <- require(same(work,get(request,"work")),"resume paths differ from original series")
    return E.Null{}
def artifact_map_checked(rows: List<&2,E.Value>, +accumulated: E.Value) -> Result<&2,&2,String,E.Value>:
  match rows:
    case Nil{}: Done{accumulated}
    case +row <> rest:
      do Result<&2,&2,String,E.Value>:
        +path : E.Value <- E.required(row,"path")
        sha : E.Value <- E.required(row,"sha256")
        _ : Unit <- require(E.is_text(path),"performance series runtime/schedule bytes differ")
        artifact_map_checked(rest,E.put(accumulated,E.text(path),sha))
def series_runtime_prepare(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    +series : E.Value = get(request,"series")
    rows : E.Value <- E.required(get(request,"manifest"),"artifacts")
    +runtime : E.Value <- artifact_map_checked(E.array(rows),E.Object{Nil{}})
    +existing : Bool = E.has(series,"runtime_artifacts")
    _ : Unit <- require(Bool.not(existing) || same(get(series,"runtime_artifacts"),runtime),"performance series runtime/schedule bytes differ")
    return E.Object{[("series",Bool.pick(E.Value,existing,series,E.put(series,"runtime_artifacts",runtime))),
      ("new_binding",E.Boolean{Bool.not(existing)})]}
def series_runtime_schedule(+series: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    sha : E.Value <- E.required(get(series,"runtime_artifacts"),"schedule.json")
    return E.put(series,"schedule_sha256",sha)
def series_runtime_finish(+prepared: E.Value) -> Result<&2,&2,String,E.Value>:
  S.delayed(Result<&2,&2,String,E.Value>,E.bool(get(prepared,"new_binding")),
    _ => series_runtime_schedule(get(prepared,"series")),_ => Done{get(prepared,"series")})
def series_runtime(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    prepared : E.Value <- series_runtime_prepare(request)
    series_runtime_finish(prepared)
def record_status(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    _ : Unit <- require(E.eq(get(request,"returncode"),num(0)) && Bool.not(E.is_null(get(request,"archive"))),
      "runner failed; retained partial series: " ++ text(request,"output"))
    return E.Null{}
def series_continuation(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    _ : Unit <- require(Bool.not(E.truth(get(request,"resuming"))) || nonzero(E.int(get(request,"additional"))),
      "resuming an incomplete series requires --additional-allowance SECONDS")
    return E.Null{}
def campaign_continuation_state(+request: E.Value, exists: Bool) -> Result<&2,&2,String,E.Value>:
  match exists:
    case True{}:
      do Result<&2,&2,String,E.Value>:
        state : E.Value <- E.required(get(request,"campaign"),"state")
        _ : Unit <- require(E.eq(state,E.Text{"ready"}) || E.truth(get(request,"additional")),
          "campaign interrupted; declare --additional-allowance to resume")
        return E.Null{}
    case False{}:
      do Result<&2,&2,String,E.Value>:
        _ : Unit <- require(Bool.not(E.truth(get(request,"additional"))),"additional allowance requires an existing campaign")
        return E.Null{}
def campaign_continuation(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  campaign_continuation_state(request,E.truth(get(request,"exists")))
def run_evidence(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    state : E.Value <- E.required(get(request,"evidence"),"status")
    _ : Unit <- require(E.eq(state,E.Text{"pass"}),text(request,"reason"))
    return E.Null{}

def values(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    _ : E.Value <- values_header(request)
    +manifest : E.Value = get(request,"manifest")
    +summary : E.Value = get(request,"summary")
    +expected : E.Value = get(request,"scope")
    +mode : String = text(request,"mode")
    +perf : Bool = performance(expected)
    +history : Bool = eq(expected,"case","history")
    _ : Unit <- require(Bool.not(E.truth(get(request,"errors"))),"damaged common recorder: " ++ String.join(text_values(array(request,"errors")),", "))
    +sequence : E.Value <- reference_sequence(get(request,"records"),get(request,"frozen"))
    +frames : List<&2,E.Value> = E.array(E.at(E.array(sequence),0))
    +edits : List<&2,E.Value> = E.array(E.at(E.array(sequence),2))
    +ordinary : List<&2,E.Value> = durations(frames,"ordinary",False{})
    +accepted : List<&2,E.Value> = durations(edits,"",True{})
    +measured : List<&2,E.Value> = measured_rows(frames)
    +duration : E.Signed = Bool.pick(E.Signed,U32.is_eq(E.count(measured),0),zero(),E.int_sub(E.int(get(last(measured),"end_ns")),E.int(get(E.at(measured,0),"begin_ns"))))
    +ordinary_duration : E.Signed = sum(ordinary,zero())
    +enough : Bool = T.population(E.count(ordinary),magnitude(Bool.pick(E.Signed,perf,ordinary_duration,duration))) && (Bool.not(history) || T.edits(E.count(accepted)))
    +reported_ordinary : E.Value = get(get(summary,"populations"),"ordinary")
    _ : Unit <- require(eq(reported_ordinary,"count",U32.show(E.count(ordinary))) && same(get(reported_ordinary,"samples_ns"),E.Array{ordinary}),"ordinary samples differ from common recorder")
    _ : Unit <- require(Bool.not(history) || (eq(edit_distribution(summary),"count",U32.show(E.count(accepted))) &&
      same(get(edit_distribution(summary),"samples_ns"),E.Array{accepted})),"accepted-edit samples differ from common recorder")
    +mean : E.Rational = E.Rational{ordinary_duration,magnitude(integer(E.count(ordinary)))}
    +p95 : E.Value = percentile(ordinary,95)
    +p99 : E.Value = percentile(ordinary,99)
    +stats : E.Value = E.Object{[("ordinary_mean",Bool.pick(E.Value,U32.is_eq(E.count(ordinary),0),E.Null{},rvalue(decimal_round(mean)))),
      ("ordinary_p95",Bool.pick(E.Value,E.is_null(p95),E.Null{},rvalue(E.rational(p95)))),
      ("ordinary_p99",Bool.pick(E.Value,E.is_null(p99),E.Null{},rvalue(E.rational(p99))))]}
    +stats : E.Value = Bool.pick(E.Value,history,E.put(stats,"accepted_edits_p95",Bool.pick(E.Value,U32.is_eq(E.count(accepted),0),E.Null{},rvalue(E.rational(percentile(accepted,95))))),stats)
    _ : Unit <- stats_check(E.fields(stats),reported_statistics(summary,history))
    +exact_stats : E.Value = E.Object{[("ordinary_mean",exact_pair(mean)),("ordinary_p95",exact_pair(E.rational(p95))),("ordinary_p99",exact_pair(E.rational(p99)))]}
    +exact_stats : E.Value = Bool.pick(E.Value,history,E.put(exact_stats,"accepted_edits_p95",exact_pair(E.rational(percentile(accepted,95)))),exact_stats)
    +output : E.Value = E.Object{[("attempt_id",get(manifest,"attempt_id")),("archive",get(request,"archive")),("mode",E.Text{mode}),
      ("ordinary_count",num(E.count(ordinary))),("accepted_edit_count",num(E.count(accepted))),("measured_duration_ns",E.int_value(duration)),
      ("sufficient",E.Boolean{enough}),("statistics",stats),("exact_statistics",exact_stats)]}
    return Bool.pick(E.Value,perf,E.put(output,"ordinary_duration_ns",E.int_value(ordinary_duration)),output)

def off_check(+request: E.Value) -> Result<&2,&2,String,Unit>:
  do Result<&2,&2,String,Unit>:
    +frozen : E.Value = get(request,"frozen")
    +reference : E.Value = get(request,"reference")
    +cpu : List<&2,E.Value> = array(request,"cpu")
    +frames : List<&2,E.Value> = type_rows(E.array(reference),"frame")
    +checkpoints : List<&2,E.Value> = type_rows(cpu,"checkpoint")
    +first : E.Value = E.at(checkpoints,0)
    +final : E.Value = E.at(checkpoints,1)
    +supervised : E.Value = get(request,"supervised")
    +validation : E.Value = get(request,"validation")
    _ : E.Value <- reference_sequence(reference,frozen)
    _ : Unit <- require(U32.is_eq(E.count(checkpoints),2),"off endpoint checkpoints missing or duplicated")
    _ : Unit <- required_fields(first,["frame"])
    _ : Unit <- required_fields(final,["frame"])
    _ : Unit <- require(eq(first,"frame","0") &&
      eq(final,"frame",U32.show((E.count(array(frozen,"frames")) - 1 : U32))),"off endpoint checkpoints missing or duplicated")
    first_time : E.Signed <- natural_field(first,"time_ns")
    _ : Unit <- require(E.int_le(first_time,E.int(get(E.at(frames,0),"end_ns"))),"off endpoint checkpoint timing invalid")
    final_time : E.Signed <- natural_field(final,"time_ns")
    _ : Unit <- require(E.int_le(E.int(get(last(frames),"end_ns")),final_time),"off endpoint checkpoint timing invalid")
    _ : Unit <- required_fields(first,["names"])
    _ : Unit <- required_fields(final,["names"])
    _ : Unit <- require(same(get(first,"names"),E.Array{strings(["initialization","review_opening"])}) &&
      same(get(final,"names"),E.Array{strings(["completion"])}),"off endpoint names mismatch")
    _ : Unit <- require(U32.is_eq(E.count(type_rows(cpu,"complete")),1) && eq(last(cpu),"record_type","complete"),"off completion marker missing")
    reference_count : E.Signed <- natural_field(supervised,"reference_records")
    _ : Unit <- require(E.int_eq(reference_count,integer(E.count(E.array(reference)))),"lost common recorder records")
    committed_count : E.Signed <- natural_field(supervised,"shared_committed_slots")
    _ : Unit <- require(E.int_eq(committed_count,integer(E.count(E.array(reference)))),"lost common recorder records")
    header_count : E.Signed <- natural_field(supervised,"shared_header_records")
    _ : Unit <- require(E.int_eq(header_count,integer(E.count(E.array(reference)))),"lost common recorder records")
    termination : E.Value <- E.required(supervised,"termination")
    cause : E.Value <- E.required(termination,"cause")
    _ : Unit <- require(E.eq(cause,E.Text{"normal_exit"}),"mandatory supervision/accounting incomplete")
    errors : E.Value <- E.required(supervised,"errors")
    _ : Unit <- require(Bool.not(E.truth(errors)) && E.truth(get(request,"resource")) && E.truth(get(request,"allocations")),"mandatory supervision/accounting incomplete")
    ledger : E.Value <- E.required(supervised,"allocation_ledger")
    _ : Unit <- require(Bool.not(E.is_null(ledger)),"mandatory supervision/accounting incomplete")
    _ : Unit <- require(Bool.not(E.truth(get(request,"gpu_nonempty"))),"GPU query evidence unexpectedly enabled in off control")
    _ : Unit <- require(Bool.not(E.is_null(validation)),"separate complete off validation unavailable")
    _ : Unit <- validation_count(validation,integer(E.count(array(frozen,"frames"))),"separate complete off validation unavailable")
    endpoint_validation(checkpoints,validation,["initialization","completion"])
def off_result(+request: E.Value) -> E.Value:
  +config = get(request,"config")
  +manifest = get(request,"manifest")
  +cpu = array(request,"cpu")
  +frames = type_rows(array(request,"reference"),"frame")
  +edits = type_rows(array(request,"reference"),"edit")
  +errors = array(request,"errors")
  +errors = Bool.pick(List<&2,E.Value>,Bool.not(has_types(cpu,["frame","stage","edit","action","static_audit","native_audit","render_work","body_motion"])),errors,
    List.append(&2,E.Value,errors,[E.Text{"disabled detailed field present in off stream"}]))
  +errors = Bool.pick(List<&2,E.Value>,all_types(cpu,strings(["worker_start","checkpoint","complete","window_closed"])),errors,
    List.append(&2,E.Value,errors,[E.Text{"unexpected off stream record"}]))
  +errors = append_error(errors,off_check(request))
  +errors = duration_errors(errors,duration_checks(List.append(&2,E.Value,ordinary_rows(frames),accepted_rows(edits))))
  +complete = U32.is_eq(E.count(errors),0)
  +state = Bool.pick(String,complete,"pass","inconclusive")
  +ordinary = Bool.pick(List<&2,E.Value>,duration_valid(duration_checks(List.append(&2,E.Value,ordinary_rows(frames),accepted_rows(edits)))),durations(frames,"ordinary",False{}),Nil{})
  +accepted = Bool.pick(List<&2,E.Value>,duration_valid(duration_checks(List.append(&2,E.Value,ordinary_rows(frames),accepted_rows(edits)))),durations(edits,"",True{}),Nil{})
  +populations : E.Value = E.Object{[("ordinary",R.distribution(ordinary)),("accepted_edits",R.distribution(accepted))]}
  +result : E.Value = E.Object{[str("schema","megascene-evidence/1"),str("record_type","summary"),field("attempt_id",get(manifest,"attempt_id")),
    str("attempt_kind","calibration_off"),field("synthetic",Bool.pick(E.Value,E.has(manifest,"synthetic"),get(manifest,"synthetic"),E.Boolean{False{}})),
    str("qualification","diagnostic_control_only"),field("termination",get(get(request,"supervised"),"termination")),field("supervision",get(request,"supervised")),
    field("evidence_errors",E.Array{errors}),field("disabled_evidence",E.Object{[("intermediate_checkpoints",measurement("disabled","accepted calibration-off protocol","intermediate_checkpoints","records")),
      ("detailed_inventory_transitions",measurement("disabled","accepted calibration-off protocol","detailed_inventory_transitions","records")),
      ("stage_timing",measurement("disabled","accepted calibration-off protocol","stage_timing","ns")),
      ("gpu_queries",measurement("disabled","accepted calibration-off protocol","gpu_queries","ns")),
      ("ordinary_logging",measurement("disabled","accepted calibration-off protocol","ordinary_logging","records"))]}),
    str("equality_limit","Initial/final and scalar action evidence cannot establish transient state equality."),
    field("endpoint_agreement",gate(state,Bool.pick(String,complete,"initial/final canonical digests and scalar outcomes agree with separate complete off validation","endpoint or common evidence incomplete"),text(config,"schedule"),["validation.json","cpu.jsonl","reference.jsonl"])),
    field("schedule_completion",gate(state,Bool.pick(String,complete,"common frame/action sequence complete","off control invalid"),text(config,"schedule"),["reference.jsonl"])),
    field("state_correctness",gate("inconclusive","actual off control omits intermediate checkpoints",text(config,"schedule"),Nil{})),
    field("rendering_correctness",gate("inconclusive","actual off control omits detailed native audits",text(config,"profile"),Nil{})),
    field("visual_quality",gate("inconclusive","off control cannot qualify visual quality",text(config,"profile"),Nil{})),
    field("calibration",gate("inconclusive","off control cannot qualify performance alone",text(config,"schedule"),Nil{})),
    field("gpu_execution",E.Object{[("capability",measurement("disabled","GPU queries disabled by calibration-off protocol","submitted work","ns")),("required_evidence_complete",E.Boolean{False{}})]}),
    field("measurement_availability",E.Object{[("reference",gate(state,Bool.pick(String,complete,"common preallocated recorder retained","common recorder incomplete"),"frame/edit boundaries",["reference.jsonl"])),
      ("gpu",gate("not_applicable","GPU queries disabled by calibration-off protocol","GPU intervals",Nil{})),
      ("resources",gate(Bool.pick(String,E.truth(get(request,"resource")) && E.truth(get(request,"allocations")) && Bool.not(E.truth(get(request,"resource_errors"))) && Bool.not(E.truth(get(request,"allocation_errors"))),"pass","inconclusive"),
        "mandatory resource/allocation evidence","attempt",["resources.jsonl","allocations.jsonl"]))]}),
    field("qualified_capacity",gate("inconclusive","calibration-off controls cannot enter capacity endpoints",text(config,"schedule"),Nil{})),
    field("interactive_pass",gate("inconclusive","calibration-off controls cannot enter interactive endpoints",text(config,"schedule"),Nil{})),
    field("endpoint_eligible",gate("inconclusive","calibration-off control is diagnostic only",text(config,"schedule"),Nil{})),
    field("populations",populations),field("completed_prefix",E.Object{[("startup",E.Boolean{Bool.not(U32.is_eq(E.count(frames),0))}),
      ("warmup",E.Text{U32.show(population_count(frames,"warmup"))}),("measured",E.Text{U32.show((population_count(frames,"ordinary") + population_count(frames,"edit") + population_count(frames,"motion") : U32))})]}),
    field("raw_evidence",E.Object{[str("reference","reference.jsonl"),str("endpoints","cpu.jsonl"),str("resources","resources.jsonl"),str("allocations","allocations.jsonl")]})]}
  off_performance(performance(config),result,frames,populations)
def mode_scope(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    +series : E.Value = get(request,"series")
    +manifest : E.Value = get(request,"manifest")
    +summary : E.Value = get(request,"summary")
    +mode : String = text(request,"mode")
    _ : Unit <- require(Bool.not(E.truth(get(manifest,"synthetic"))),"mode validation scope mismatch")
    kind : E.Value <- E.required(manifest,"attempt_kind")
    _ : Unit <- require(E.eq(kind,E.Text{"calibration_" ++ mode}),"mode validation scope mismatch")
    kind : E.Value <- E.required(summary,"attempt_kind")
    _ : Unit <- require(E.eq(kind,E.Text{"validation_only"}),"mode validation scope mismatch")
    +effective : E.Value <- E.required(manifest,"effective")
    actual_mode : E.Value <- E.required(effective,"calibration_mode")
    _ : Unit <- require(E.eq(actual_mode,E.Text{mode}),"mode validation scope mismatch")
    actual_scope : E.Value <- scope_checked(effective)
    expected_scope : E.Value <- E.required(series,"scope")
    _ : Unit <- require(same(actual_scope,expected_scope),"mode validation scope mismatch")
    return E.Null{}
def modes_validate(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    _ : E.Value <- mode_scope(request)
    +series : E.Value = get(request,"series")
    expected : E.Signed <- expected_frame_count(get(series,"scope"),eq(series,"protocol","performance-v2"))
    _ : Unit <- validation_count(get(request,"validation"),expected,"incomplete mode validation")
    return E.Null{}
def peer_validation(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    _ : E.Value <- peer_binding(request)
    +config : E.Value = get(request,"config")
    +peer : E.Value = get(get(request,"peer_manifest"),"effective")
    expected : E.Signed <- expected_frame_count(config,True{})
    checked : E.Signed <- natural_field(get(request,"validation"),"checked_frames")
    _ : Unit <- require(E.int_eq(checked,expected),"peer validation replay incomplete")
    attempt : E.Value <- E.required(get(request,"validation"),"attempt_id")
    return E.Object{[("status",E.Text{"pass"}),("mode",get(peer,"calibration_mode")),("source",get(request,"source")),
      ("validation_attempt_id",attempt)]}

def host_type(value: E.Value) -> String:
  match value:
    case E.Null{}: "NoneType"
    case E.Boolean{_}: "bool"
    case E.Number{_}: "int"
    case E.Real{_,_}: "float"
    case E.Text{_}: "str"
    case E.Array{_}: "list"
    case E.Object{_}: "dict"
    case _: "object"
def resume_arrays(+runs: E.Value, +controls: E.Value) -> Result<&2,&2,String,Unit>:
  S.delayed(Result<&2,&2,String,Unit>,E.is_array(runs) && E.is_array(controls),_ => Done{Unit{}},_ =>
    Fail{"type error:" ++ Bool.pick(String,E.is_array(runs),
      "can only concatenate list (not \"" ++ host_type(controls) ++ "\") to list",
      Bool.pick(String,E.is_text(runs),"can only concatenate str (not \"" ++ host_type(controls) ++ "\") to str",
        "unsupported operand type(s) for +: '" ++ host_type(runs) ++ "' and '" ++ host_type(controls) ++ "'"))})

def series_resume(+request: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    +series : E.Value = get(request,"series")
    current_scope : E.Value <- E.required(series,"scope")
    expected_scope : E.Value <- scope_checked(get(request,"config"))
    _ : Unit <- require(same(current_scope,expected_scope),"existing series scope/order mismatch")
    current_order : E.Value <- E.required(series,"order")
    _ : Unit <- require(same(current_order,order()),"existing series scope/order mismatch")
    +runs : E.Value <- E.required(series,"runs")
    +controls : E.Value <- E.required(series,"controls")
    _ : Unit <- resume_arrays(runs,controls)
    _ : Unit <- resumable_runs(List.append(&2,E.Value,E.array(runs),E.array(controls)))
    return E.Null{}
def handle(operation: String, +request: E.Value) -> E.Value:
  match operation:
    case "series_configuration": result(series_configuration(request))
    case "series_resume": result(series_resume(request))
    case "series_roots": result(series_roots(request))
    case "series_runtime": result(series_runtime(request))
    case "series_runtime_prepare": result(series_runtime_prepare(request))
    case "series_runtime_schedule": result(series_runtime_schedule(request))
    case "record_status": result(record_status(request))
    case "series_continuation": result(series_continuation(request))
    case "campaign_continuation": result(campaign_continuation(request))
    case "run_evidence": result(run_evidence(request))
    case "values_header": result(values_header(request))
    case "pair_header": result(pair_header(request))
    case "pair_reference": result(pair_reference(request))
    case "peer_binding": result(peer_binding(request))
    case "mode_scope": result(mode_scope(request))
    case "append_control": E.put(get(request,"report"),"controls",E.Array{List.append(&2,E.Value,array(get(request,"report"),"controls"),[get(request,"value")])})
    case "pair_indices": pair_indices(request)
    case "plan": result(plan(E.text(request)))
    case "matrix": result(plan(E.text(request)))
    case "scope": result(scope_checked(request))
    case "reference_sequence": result(reference_sequence(get(request,"records"),get(request,"frozen")))
    case "off_result": off_result(request)
    case "compare_modes": result(compare_modes(request))
    case "classify_statistic": classify_statistic(text(request,"name"),array(request,"controls"))
    case "values": result(values(request))
    case "assessment_start": result(assessment_start(request))
    case "mode_validation": result(modes_validate(request))
    case "assessment_finish": assessment_finish(request)
    case "validation_run": result(validation_run(request))
    case "control_entry": result(control_entry(request))
    case "report_control": result(report_control(request))
    case "pair_record": result(pair_record(request))
    case "peer_workload": result(peer_workload(request))
    case "pair_kinds": result(pair_kinds(request))
    case "peer_validation": result(peer_validation(request))
    case _: E.Error{"unsupported calibration operation"}
def main() -> IO(Unit): E.main(~handle)
