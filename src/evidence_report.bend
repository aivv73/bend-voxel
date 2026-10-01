import Base
import ./evidence_value.bend as E
import ./megascene_scale.bend as S
import ./evidence_integrity.bend as I
import ./evidence_thresholds.bend as T

type Prefix is Data:
  Prefix{records: List<&2,E.Value>, errors: List<&2,E.Value>}
def prefix_cons(value: E.Value, prefix: Prefix) -> Prefix:
  match prefix:
    case Prefix{records,errors}: Prefix{value <> records,errors}

def text(+value: E.Value, key: String) -> String: E.text(E.get(value,key))
def items(+value: E.Value, key: String) -> List<&2,E.Value>: E.array(E.get(value,key))
def status(value: E.Value) -> String: text(value,"status")
def map_values(~f: E.Value -> E.Value -> E.Value, +ctx: E.Value, values: List<&2,E.Value>) -> List<&2,E.Value>:
  match values:
    case Nil{}: Nil{}
    case +v <> rest: f(ctx,v) <> map_values(~f,ctx,rest)
def map_strings(~f: E.Value -> String -> E.Value, +ctx: E.Value, values: List<&2,String>) -> List<&2,E.Value>:
  match values:
    case Nil{}: Nil{}
    case +v <> rest: f(ctx,v) <> map_strings(~f,ctx,rest)
def filter_keep(values: List<&2,E.Value>, value: E.Value, keep: Bool) -> List<&2,E.Value>:
  match keep:
    case True{}: value <> values
    case False{}: values
def filter(~f: E.Value -> E.Value -> Bool, +ctx: E.Value, values: List<&2,E.Value>) -> List<&2,E.Value>:
  match values:
    case Nil{}: Nil{}
    case +v <> rest: filter_keep(filter(~f,ctx,rest),v,f(ctx,v))
def any(~f: E.Value -> E.Value -> Bool, +ctx: E.Value, values: List<&2,E.Value>) -> Bool:
  match values:
    case Nil{}: False{}
    case +v <> rest: f(ctx,v) || any(~f,ctx,rest)
def all(~f: E.Value -> E.Value -> Bool, +ctx: E.Value, values: List<&2,E.Value>) -> Bool:
  match values:
    case Nil{}: True{}
    case +v <> rest: f(ctx,v) && all(~f,ctx,rest)
def all_keys(~f: E.Value -> String -> Bool, +ctx: E.Value, values: List<&2,String>) -> Bool:
  match values:
    case Nil{}: True{}
    case +v <> rest: f(ctx,v) && all_keys(~f,ctx,rest)
def any_fields(~f: E.Value -> E.Field() -> Bool, +ctx: E.Value, values: List<&2,E.Field()>) -> Bool:
  match values:
    case Nil{}: False{}
    case +v <> rest: f(ctx,v) || any_fields(~f,ctx,rest)
def strings(values: List<&2,String>) -> E.Value: E.Array{map_strings(~(_ => v => E.string(v)),E.Null{},values)}
def object(value: E.Value) -> Bool:
  match value:
    case E.Object{_}: True{}
    case _: False{}
def boolean(value: E.Value) -> Bool:
  match value:
    case E.Boolean{_}: True{}
    case _: False{}
def yes(value: E.Value) -> Bool: E.bool(value)
def matches(+value: E.Value, +key: String, expected: String) -> Bool: String.eq(text(value,key),expected)
def one_of(+value: String, values: List<&2,String>) -> Bool:
  match values:
    case Nil{}: False{}
    case v <> rest: String.eq(value,v) || one_of(value,rest)
def member(+value: E.Value, values: List<&2,E.Value>) -> Bool:
  match values:
    case Nil{}: False{}
    case v <> rest: E.eq(value,v) || member(value,rest)
@unsafe def unique_step(values: List<&2,E.Value>, +seen: List<&2,E.Value>, +value: E.Value, present: Bool) -> List<&2,E.Value>:
  match present:
    case True{}: unique(values,seen)
    case False{}: value <> unique(values,value <> seen)
@unsafe def unique(values: List<&2,E.Value>, +seen: List<&2,E.Value>) -> List<&2,E.Value>:
  match values:
    case Nil{}: Nil{}
    case +v <> rest: unique_step(rest,seen,v,member(v,seen))
def select(+records: List<&2,E.Value>, kind: String) -> List<&2,E.Value>:
  filter(~(ctx => +r => matches(r,"record_type",E.text(ctx))),E.string(kind),records)
def field_values(records: List<&2,E.Value>, +key: String) -> List<&2,E.Value>:
  map_values(~(ctx => +r => E.get(r,E.text(ctx))),E.string(key),records)
def add_error(errors: List<&2,E.Value>, message: String) -> List<&2,E.Value>:
  List.append(&2,E.Value,errors,[E.string(message)])
def errors_if(errors: List<&2,E.Value>, ok: Bool, message: String) -> List<&2,E.Value>:
  match ok:
    case True{}: errors
    case False{}: add_error(errors,message)
def prefix_errors(errors: List<&2,E.Value>, +prefix: String) -> List<&2,E.Value>:
  map_values(~(ctx => +v => E.string(E.text(ctx) ++ E.text(v))),E.string(prefix),errors)
def contains(+errors: List<&2,E.Value>, +needle: String) -> Bool:
  any(~(ctx => +e => String.contains(E.text(e),E.text(ctx))),E.string(needle),errors)
def omit_gpu(errors: List<&2,E.Value>) -> List<&2,E.Value>:
  filter(~(_ => e => Bool.not(String.starts_with(E.text(e),"GPU: "))),E.Null{},errors)
def num(+value: E.Value, key: String) -> E.Signed: E.int(E.get(value,key))
def n(n: U32) -> E.Signed: E.int_text(U32.show(n))
def word(value: E.Signed) -> U32: S.Integer.to_u32(E.int_abs(value))
def eqi(a: E.Signed, b: E.Signed) -> Bool: Cmp.is_eq(E.int_cmp(a,b))
def lei(a: E.Signed, b: E.Signed) -> Bool: Cmp.is_le(E.int_cmp(a,b))
def gti(a: E.Signed, b: E.Signed) -> Bool: Cmp.is_gt(E.int_cmp(a,b))
def integer(value: E.Value) -> Result<&2,&2,String,Unit>:
  do Result<&2,&2,String,Unit>:
    _ : E.Signed <- E.natural(value)
    return Unit{}
def required_keys(+record: E.Value, keys: List<&2,String>) -> Result<&2,&2,String,Unit>:
  match keys:
    case Nil{}: Done{Unit{}}
    case +key <> rest:
      do Result<&2,&2,String,Unit>:
        _ : Unit <- E.require(E.has(record,key),"'" ++ key ++ "'")
        required_keys(record,rest)
def required_top_keys(+record: E.Value, keys: List<&2,String>) -> Result<&2,&2,String,Unit>:
  match keys:
    case Nil{}: Done{Unit{}}
    case key <> rest:
      do Result<&2,&2,String,Unit>:
        _ : E.Value <- E.required(record,key)
        required_top_keys(record,rest)
def record_types(records: List<&2,E.Value>) -> Result<&2,&2,String,Unit>:
  match records:
    case Nil{}: Done{Unit{}}
    case record <> rest:
      do Result<&2,&2,String,Unit>:
        _ : Unit <- required_top_keys(record,["record_type"])
        record_types(rest)
def value_integer(+record: E.Value, key: String) -> Result<&2,&2,String,Unit>:
  +key = key
  do Result<&2,&2,String,Unit>:
    _ : Unit <- required_keys(record,[key])
    integer(E.get(record,key))
def integer_fields(+record: E.Value, fields: List<&2,String>) -> Result<&2,&2,String,Unit>:
  match fields:
    case Nil{}: Done{Unit{}}
    case field <> rest:
      do Result<&2,&2,String,Unit>:
        _ : Unit <- value_integer(record,field)
        integer_fields(record,rest)
def count(values: List<&2,E.Value>) -> E.Value: E.string(U32.show(E.count(values)))
def extension_overlap(+value: E.Value, field: E.Field()) -> Bool:
  (+key,_) = field
  E.has(value,key) && Bool.not(String.eq(key,"extensions"))
def checked_object(+value: E.Value, +kind: String) -> Result<&2,&2,String,Unit>:
  +extensions = E.get(value,"extensions")
  do Result<&2,&2,String,Unit>:
    _ : Unit <- E.require(object(value) && matches(value,"schema","megascene-evidence/1"),"unsupported " ++ kind ++ " schema")
    E.require((Bool.not(E.has(value,"extensions")) || object(extensions)) &&
      Bool.not(any_fields(~(ctx => field => extension_overlap(ctx,field)),value,E.fields(extensions))),kind ++ " extension overrides a required field")
def gate(state: String, reason: String, scope: String, evidence: List<&2,String>) -> E.Value:
  E.object([("status",E.string(state)),("reason",E.string(reason)),("scope",E.string(scope)),("evidence",strings(evidence))])
def performance(config: E.Value) -> Bool:
  one_of(text(config,"schedule"),["static-perf-v2","history-perf-v2"])
def scope_keys(config: E.Value) -> List<&2,String>:
  List.append(&2,String,["case","preset","seed","threads","resolution","profile","schedule","diagnostic","control","fragment_budget"],
    Bool.pick(List<&2,String>,performance(config),["warmup","frames"],Nil{}))
def calibration_reason(state: String) -> String:
  match state:
    case "pass": "applicable calibration passed"
    case "not_executed": "calibration not executed"
    case "insufficient": "calibration populations insufficient"
    case "noisy": "calibration controls too noisy"
    case "failed": "calibration overhead failed"
    case _: "calibration does not cover this configuration"
def calibration_value(value: E.Value, +config: E.Value) -> Result<&2,&2,String,E.Value>:
  match value:
    case E.Null{}:
      Done{E.put(E.put(E.put(gate("inconclusive","calibration not executed","performance calibration",Nil{}),
        "calibration_status",E.string("not_executed")),"reference",E.Null{}),"configuration_scope",E.Null{})}
    case +value:
      +state = status(value)
      +scope = E.get(value,"scope")
      +reference = E.get(value,"reference")
      +keys = scope_keys(config)
      +applicable = all_keys(~(+ctx => +key => E.eq(E.get(E.at(E.array(ctx),0),key),E.get(E.at(E.array(ctx),1),key))),E.Array{[scope,config]},keys)
      do Result<&2,&2,String,E.Value>:
        _ : Unit <- checked_object(value,"calibration")
        _ : Unit <- E.require(one_of(state,["pass","not_executed","insufficient","noisy","failed","inapplicable"]),"invalid calibration status")
        _ : Unit <- E.require(object(scope) && all_keys(~(+ctx => +key => E.has(ctx,key)),scope,keys),"calibration scope incomplete")
        _ : Unit <- E.require(E.is_null(reference) || (Bool.not(String.is_empty(E.text(reference))) && E.is_text(reference)),"invalid calibration reference")
        _ : Unit <- E.require(Bool.not(String.eq(state,"pass")) || (E.truth(reference) && applicable),"passing calibration lacks matching scope/reference")
        reason : String = Bool.pick(String,Bool.not(applicable),"calibration scope does not match this configuration",
          calibration_reason(state))
        result : E.Value = gate(Bool.pick(String,String.eq(state,"pass") && applicable,"pass",
          Bool.pick(String,String.eq(state,"failed") && applicable,"fail",
          Bool.pick(String,String.eq(state,"inapplicable") || Bool.not(applicable),"not_applicable","inconclusive"))),reason,"performance calibration",
          Bool.pick(List<&2,String>,E.truth(reference),[E.text(reference)],Nil{}))
        return E.put(E.put(E.put(result,"calibration_status",E.string(state)),"reference",reference),"configuration_scope",scope)
def calibration(value: E.Value, config: E.Value, kind: String) -> Result<&2,&2,String,E.Value>:
  match kind:
    case "calibration_off":
      Done{E.put(E.put(E.put(gate("inconclusive","calibration-off control cannot qualify a benchmark endpoint","performance calibration",Nil{}),
        "calibration_status",E.string("inapplicable")),"reference",E.Null{}),"configuration_scope",E.Null{})}
    case _: calibration_value(value,config)
def sum(values: List<&2,E.Value>) -> E.Signed:
  match values:
    case Nil{}: E.int_text("0")
    case value <> rest: E.int_add(E.int(value),sum(rest))
def signed_values(values: List<&2,E.Value>) -> List<&2,E.Signed>:
  match values:
    case Nil{}: Nil{}
    case v <> rest: E.int(v) <> signed_values(rest)
def signed_samples(values: List<&2,E.Signed>) -> List<&2,E.Value>:
  match values:
    case Nil{}: Nil{}
    case v <> rest: E.string(E.int_show(v)) <> signed_samples(rest)
def signed_sum(values: List<&2,E.Signed>) -> E.Signed:
  match values:
    case Nil{}: E.int_zero()
    case v <> rest: E.int_add(v,signed_sum(rest))
def signed_at(values: List<&2,E.Signed>, index: U32) -> E.Signed:
  Maybe.default(&2,E.Signed,List.get(&2,E.Signed,values,U32.to_nat(index)),E.int_zero())
def percentile(+sorted: List<&2,E.Signed>, +len: U32, rank: U32) -> E.Value:
  E.number(E.int_show(signed_at(sorted,(((len * rank + 99 : U32) / 100 : U32) - 1 : U32))))
def distribution_result(+sorted: List<&2,E.Signed>, +total: String, +base: E.Value, +len: U32) -> E.Value:
  match len:
    case 0: E.put(E.put(E.put(E.put(E.put(base,"mean",E.Null{}),"p50",E.Null{}),"p95",E.Null{}),"p99",E.Null{}),"max",E.Null{})
    case +len:
      E.put(E.put(E.put(E.put(E.put(base,"mean",E.Ratio{total,U32.show(len)}),"p50",percentile(sorted,len,50)),"p95",percentile(sorted,len,95)),"p99",percentile(sorted,len,99)),
        "max",E.number(E.int_show(signed_at(sorted,(len - 1 : U32)))))
def distribution(+values: List<&2,E.Value>) -> E.Value:
  +len = E.count(values)
  +parsed = signed_values(values)
  +sorted = List.sort(E.Signed,E.int_le,parsed)
  +total = E.int_show(signed_sum(parsed))
  +samples = signed_samples(parsed)
  +base = E.object([("count",E.string(U32.show(len))),("unit",E.string("ns")),("samples_ns",E.Array{samples}),
    ("observation_interval_ns",E.string(total))])
  distribution_result(sorted,total,base,len)
def duration_values(records: List<&2,E.Value>) -> List<&2,E.Value>: field_values(records,"duration_ns")
def frame_check(+frame: E.Value, +previous: E.Value, +index: U32, +config: E.Value, +frozen: List<&2,E.Value>) -> Result<&2,&2,String,Unit>:
  +warmup = num(config,"warmup")
  +bound = E.int_add(warmup,num(config,"frames"))
  +expected = Bool.pick(String,performance(config) && Bool.not(List.is_empty(&2,E.Value,frozen)),text(E.at(frozen,0),"phase"),
    Bool.pick(String,U32.is_eq(index,0),"startup",Bool.pick(String,lei(n(index),warmup),"warmup","")))
  do Result<&2,&2,String,Unit>:
    _ : Unit <- E.require(lei(n(index),bound),"extra CPU frames")
    _ : Unit <- value_integer(frame,"frame")
    _ : Unit <- E.require(eqi(num(frame,"frame"),n(index)),"CPU frame gap or duplicate")
    _ : Unit <- required_keys(frame,["population"])
    _ : Unit <- E.require(String.is_empty(expected) || matches(frame,"population",expected),"CPU frame population mismatch")
    _ : Unit <- E.require(one_of(text(frame,"population"),["startup","warmup","ordinary","edit","motion"]),"unknown CPU population")
    _ : Unit <- integer_fields(frame,["begin_ns","end_ns","duration_ns"])
    _ : Unit <- required_keys(frame,["unit","status"])
    _ : Unit <- E.require(lei(num(frame,"begin_ns"),num(frame,"end_ns")) &&
      eqi(num(frame,"duration_ns"),E.int_sub(num(frame,"end_ns"),num(frame,"begin_ns"))) &&
      matches(frame,"unit","ns") && matches(frame,"status","measured"),"invalid CPU interval")
    E.require(U32.is_eq(index,0) || eqi(num(frame,"begin_ns"),num(previous,"end_ns")),"CPU frame boundary gap")
@unsafe def frame_checked(result: Result<&2,&2,String,Unit>, frame: E.Value, rest: List<&2,E.Value>, index: U32, config: E.Value, frozen: List<&2,E.Value>) -> Prefix:
  match result:
    case Fail{message}: Prefix{Nil{},[E.string(message)]}
    case Done{_}:
      +frame = frame
      prefix_cons(frame,frames_checked(rest,(index + 1 : U32),frame,config,List.drop(&2,E.Value,frozen,1n)))
@unsafe def frames_checked(records: List<&2,E.Value>, +index: U32, +previous: E.Value, +config: E.Value, +frozen: List<&2,E.Value>) -> Prefix:
  match records:
    case Nil{}: Prefix{Nil{},Nil{}}
    case +frame <> rest:
      frame_checked(frame_check(frame,previous,index,config,frozen),frame,rest,index,config,frozen)
def edit_check(+edit: E.Value, +seen: List<&2,E.Value>, +frames: List<&2,E.Value>, +config: E.Value) -> Result<&2,&2,String,Unit>:
  +index = word(num(edit,"frame"))
  +frame = E.at(frames,index)
  do Result<&2,&2,String,Unit>:
    _ : Unit <- required_keys(edit,["action"])
    _ : Unit <- E.require(Bool.not(member(E.get(edit,"action"),seen)),"duplicate edit response")
    _ : Unit <- required_keys(edit,["accepted"])
    _ : Unit <- E.require(boolean(E.get(edit,"accepted")),"invalid edit association")
    _ : Unit <- value_integer(edit,"frame")
    _ : Unit <- E.require(lei(num(edit,"frame"),E.int_add(num(config,"warmup"),num(config,"frames"))),"invalid edit association")
    _ : Unit <- integer_fields(edit,["duration_ns","end_ns","begin_ns"])
    _ : Unit <- E.require(eqi(num(edit,"duration_ns"),E.int_sub(num(edit,"end_ns"),num(edit,"begin_ns"))),"invalid edit interval")
    _ : Unit <- E.require((index < E.count(frames) : U32),"list index out of range")
    E.require(matches(frame,"population","edit") && lei(num(frame,"begin_ns"),num(edit,"begin_ns")) &&
      lei(num(edit,"begin_ns"),num(edit,"end_ns")) && E.eq(E.get(edit,"end_ns"),E.get(frame,"end_ns")),"edit response boundary mismatch")
def action_match(+action: E.Value, edits: List<&2,E.Value>) -> Bool:
  match edits:
    case Nil{}: False{}
    case +edit <> rest:
      Bool.pick(Bool,E.eq(E.get(edit,"action"),E.get(action,"action")),E.eq(E.get(edit,"accepted"),E.get(action,"accepted")),action_match(action,rest))
def action_keys(actions: List<&2,E.Value>) -> Result<&2,&2,String,Unit>:
  match actions:
    case Nil{}: Done{Unit{}}
    case action <> rest:
      do Result<&2,&2,String,Unit>:
        _ : Unit <- required_keys(action,["accepted"])
        action_keys(rest)
def action_check(+actions: List<&2,E.Value>, +edits: List<&2,E.Value>, +seen: List<&2,E.Value>) -> Result<&2,&2,String,Unit>:
  +identities = field_values(actions,"action")
  +distinct = unique(identities,Nil{})
  do Result<&2,&2,String,Unit>:
    _ : Unit <- E.require(U32.is_eq(E.count(actions),E.count(edits)),"action/edit count mismatch")
    _ : Unit <- E.require(U32.is_eq(E.count(distinct),E.count(actions)),"duplicate action evidence")
    _ : Unit <- E.require(U32.is_eq(E.count(distinct),E.count(seen)) && all(~(ctx => +v => member(v,E.array(ctx))),E.Array{seen},distinct),"action/edit identity mismatch")
    _ : Unit <- action_keys(actions)
    _ : Unit <- E.require(all(~(_ => r => boolean(E.get(r,"accepted"))),E.Null{},actions),"action acceptance missing")
    E.require(all(~(ctx => +r => action_match(r,E.array(ctx))),E.Array{edits},actions),"action/edit acceptance mismatch")
def action_checked(result: Result<&2,&2,String,Unit>) -> Prefix:
  match result:
    case Fail{message}: Prefix{Nil{},[E.string(message)]}
    case Done{_}: Prefix{Nil{},Nil{}}
@unsafe def edit_checked(result: Result<&2,&2,String,Unit>, +edit: E.Value, rest: List<&2,E.Value>, all: List<&2,E.Value>, actions: List<&2,E.Value>, seen: List<&2,E.Value>, frames: List<&2,E.Value>, config: E.Value) -> Prefix:
  match result:
    case Fail{message}: Prefix{Nil{},[E.string(message)]}
    case Done{_}:
      prefix_cons(edit,edits_checked(rest,all,actions,E.get(edit,"action") <> seen,frames,config))
@unsafe def edits_checked(records: List<&2,E.Value>, +all: List<&2,E.Value>, +actions: List<&2,E.Value>, +seen: List<&2,E.Value>, +frames: List<&2,E.Value>, +config: E.Value) -> Prefix:
  match records:
    case Nil{}:
      action_checked(action_check(actions,all,seen))
    case +edit <> rest:
      edit_checked(edit_check(edit,seen,frames,config),edit,rest,all,actions,seen,frames,config)

def population(+frames: List<&2,E.Value>, +name: String) -> List<&2,E.Value>:
  filter(~(ctx => +r => matches(r,"population",E.text(ctx))),E.string(name),frames)
def populations(+frames: List<&2,E.Value>, names: List<&2,String>) -> List<&2,E.Field()>:
  match names:
    case Nil{}: Nil{}
    case +name <> rest: (name,distribution(duration_values(population(frames,name)))) <> populations(frames,rest)
def frame_catalog(frames: List<&2,E.Value>) -> Map<&2,String>:
  match frames:
    case Nil{}: Map.new(&2,String)
    case +frame <> rest: Map.set(&2,String,frame_catalog(rest),text(frame,"frame"),text(frame,"population"))
def catalog_has(catalog: Map<&2,String>, key: String) -> Bool:
  Pair.snd(Map<&2,String>,Bool,Map.has(&2,String,catalog,key))
def catalog_get(catalog: Map<&2,String>, key: String) -> String:
  Pair.snd(Map<&2,String>,String,Map.get(String,"teardown",catalog,key))
def append_sample(+group: E.Value, +key: String, value: E.Value) -> E.Value:
  E.put(group,key,E.Array{value <> items(group,key)})
@unsafe def stage_record(keep: Bool, +record: E.Value, rest: List<&2,E.Value>, +catalog: Map<&2,String>, +perf: Bool, +groups: E.Value, +frame: String, +stage: String) -> Result<&2,&2,String,E.Value>:
  match keep:
    case False{}: stage_values(rest,catalog,perf,groups)
    case True{}:
      do Result<&2,&2,String,E.Value>:
        _ : E.Value <- E.required(record,"stage")
        +duration : E.Value <- E.required(record,"duration_ns")
        _ : E.Signed <- E.natural(duration)
        +name : String = Bool.pick(String,E.is_text(E.get(record,"frame")),catalog_get(catalog,frame),"teardown")
        +samples : E.Value = append_sample(E.get(groups,stage),name,duration)
        updated : E.Value = Bool.pick(E.Value,String.eq(name,"motion") && Bool.not(perf),append_sample(samples,"ordinary",duration),samples)
        stage_values(rest,catalog,perf,E.put(groups,stage,updated))
@unsafe def stage_values(records: List<&2,E.Value>, +catalog: Map<&2,String>, +perf: Bool, groups: E.Value) -> Result<&2,&2,String,E.Value>:
  match records:
    case Nil{}: Done{groups}
    case +record <> rest:
      +frame = text(record,"frame")
      +stage = text(record,"stage")
      stage_record(matches(record,"record_type","stage") && ((E.is_text(E.get(record,"frame")) && catalog_has(catalog,frame)) || String.eq(stage,"teardown")),record,rest,catalog,perf,groups,frame,stage)
def distributions(fields: List<&2,E.Field()>) -> List<&2,E.Field()>:
  match fields:
    case Nil{}: Nil{}
    case (key,value) <> rest: (key,distribution(List.reverse(&2,E.Value,E.array(value)))) <> distributions(rest)
def stage_distributions(fields: List<&2,E.Field()>) -> List<&2,E.Field()>:
  match fields:
    case Nil{}: Nil{}
    case (key,value) <> rest: (key,E.object(distributions(E.fields(value)))) <> stage_distributions(rest)
def history_selected(+frames: List<&2,E.Value>, +range: E.Value, +warmup: E.Signed) -> List<&2,E.Value>:
  filter(~(+ctx => +r => (
    +range = E.get(ctx,"range")
    +index = E.int_sub(E.int_sub(num(r,"frame"),num(ctx,"warmup")),n(1))
    lei(E.int(E.at(E.array(range),0)),index) && lei(index,E.int(E.at(E.array(range),1)))
  )),E.object([("range",range),("warmup",E.string(E.int_show(warmup)))]),frames)
def history_groups(+frames: List<&2,E.Value>, names: List<&2,String>) -> List<&2,E.Field()>:
  match names:
    case Nil{}: Nil{}
    case +name <> rest:
      selected = Bool.pick(List<&2,E.Value>,String.eq(name,"combined"),frames,population(frames,name))
      (name,distribution(duration_values(selected))) <> history_groups(frames,rest)
def history_populations(fields: List<&2,E.Field()>, +frames: List<&2,E.Value>, +config: E.Value) -> List<&2,E.Field()>:
  match fields:
    case Nil{}: Nil{}
    case (key,value) <> rest:
      selected = history_selected(frames,value,num(config,"warmup"))
      (key,E.object(history_groups(selected,Bool.pick(List<&2,String>,performance(config),
        ["combined","ordinary","edit","motion"],["combined","ordinary","edit"])))) <> history_populations(rest,frames,config)
def measured_duration(+frames: List<&2,E.Value>) -> E.Signed:
  match frames:
    case Nil{}: n(0)
    case +first <> +rest:
      +frames = {first <> rest : List<&2,E.Value>}
      E.int_sub(num(E.at(frames,(E.count(frames) - 1 : U32)),"end_ns"),num(first,"begin_ns"))
def cold_startup(+frames: List<&2,E.Value>, +summary: E.Value) -> E.Value:
  +launch = E.get(E.get(summary,"supervision"),"launch_ns")
  +end = E.get(E.at(frames,0),"end_ns")
  +available = E.truth(E.Array{frames}) && E.truth(launch) && lei(E.int(launch),E.int(end))
  E.object([("status",E.string(Bool.pick(String,available,"measured","incomplete"))),
    ("reason",E.string(Bool.pick(String,available,"process launch to first usable frame-effect return","startup boundary unavailable"))),
    ("scope",E.string("startup")),("unit",E.string("ns")),
    ("value",Bool.pick(E.Value,available,E.string(E.int_show(E.int_sub(E.int(end),E.int(launch)))),E.Null{}))])
def frame_identity(frames: List<&2,E.Value>) -> E.Value:
  E.Array{map_values(~(_ => +r => E.Array{[E.get(r,"frame"),E.get(r,"begin_ns"),E.get(r,"end_ns")]}),E.Null{},frames)}
def count_error(+supervision: E.Value, +key: String, +records: List<&2,E.Value>, errors: List<&2,E.Value>) -> List<&2,E.Value>:
  errors_if(errors,Bool.not(E.has(supervision,key)) || eqi(num(supervision,key),n(E.count(records))),key ++ " count mismatch")
def extremum(values: List<&2,E.Value>, +maximum: Bool, +best: E.Value) -> E.Value:
  match values:
    case Nil{}: best
    case +v <> rest:
      extremum(rest,maximum,Bool.pick(E.Value,Bool.pick(Bool,maximum,gti(E.int(v),E.int(best)),gti(E.int(best),E.int(v))),v,best))
def resource_samples(samples: List<&2,E.Value>, +supervision: E.Value, +field: String, +key: String, maximum: Bool, errors: List<&2,E.Value>) -> List<&2,E.Value>:
  match samples:
    case Nil{}: errors
    case +v <> rest:
      observed = E.string(E.int_show(E.int(extremum(rest,maximum,v))))
      errors_if(errors,E.eq(E.get(E.get(supervision,key),field),observed),"resource " ++ field ++ " observed extremum mismatch")
def resource_extremum(+resources: List<&2,E.Value>, +supervision: E.Value, +field: String, +key: String, maximum: Bool, errors: List<&2,E.Value>) -> List<&2,E.Value>:
  samples = field_values(filter(~(ctx => +r => E.has(r,E.text(ctx)) && Bool.not(matches(r,"phase","preflight"))),E.string(field),resources),field)
  resource_samples(samples,supervision,field,key,maximum,errors)
def heaps_maxima(heaps: List<&2,E.Value>, +maximum: E.Value) -> E.Value:
  match heaps:
    case Nil{}: maximum
    case +heap <> rest:
      +key = text(heap,"heap")
      +usage = E.get(heap,"usage_bytes")
      +old = Bool.pick(E.Value,E.has(maximum,key),E.get(maximum,key),E.string("0"))
      value = Bool.pick(E.Value,gti(E.int(usage),E.int(old)),E.string(E.int_show(E.int(usage))),old)
      heaps_maxima(rest,E.put(maximum,key,value))
def heap_resources(resources: List<&2,E.Value>, maximum: E.Value) -> E.Value:
  match resources:
    case Nil{}: maximum
    case row <> rest: heap_resources(rest,heaps_maxima(items(row,"heaps"),maximum))
def checkpoint_check(+validation: E.Value, +comparison: E.Value, +cpu: List<&2,E.Value>, +schedule: E.Value, +config: E.Value) -> Result<&2,&2,String,Unit>:
  +expected = unique(field_values(items(comparison,"checkpoints"),"frame"),Nil{})
  +actual = field_values(filter(~(_ => +r => one_of(text(r,"record_type"),["checkpoint","static_audit"])),E.Null{},cpu),"frame")
  do Result<&2,&2,String,Unit>:
    _ : Unit <- value_integer(validation,"checked_frames")
    _ : Unit <- E.require(eqi(num(validation,"checked_frames"),E.int_add(E.int_add(n(1),num(config,"warmup")),num(config,"frames"))),"independent validation replay incomplete")
    _ : Unit <- E.require(object(comparison) && String.eq(status(comparison),"pass"),"timed checkpoint comparison unavailable")
    _ : Unit <- value_integer(comparison,"checked_frames")
    _ : Unit <- E.require(eqi(num(comparison,"checked_frames"),n(E.count(expected))),"timed checkpoint count inconsistent")
    _ : Unit <- E.require(Bool.not(object(schedule)) || E.eq(E.get(schedule,"schedule_id"),E.get(config,"schedule")),"frozen schedule identity mismatch")
    +planned : List<&2,E.Value> = unique(field_values(items(schedule,"required_checkpoints"),"frame"),Nil{})
    _ : Unit <- E.require(Bool.not(object(schedule)) || (U32.is_eq(E.count(planned),E.count(expected)) && all(~(ctx => +v => member(v,E.array(ctx))),E.Array{planned},expected)),"required checkpoint schedule mismatch")
    E.require(U32.is_eq(E.count(actual),E.count(expected)) && all(~(ctx => +v => member(v,E.array(ctx))),E.Array{expected},actual) &&
      U32.is_eq(E.count(unique(actual,Nil{})),E.count(expected)),"timed checkpoint evidence missing or duplicated")
def timed_validation_gate(state: String, +config: E.Value, result: E.Value) -> E.Value:
  match state:
    case "pass": E.get(result,"state_correctness")
    case +state: gate(Bool.pick(String,String.is_empty(state),"inconclusive",state),"timed checkpoint comparison did not pass",text(config,"schedule"),["comparison.json"])
def validation_state(state: String, +result: E.Value, +config: E.Value) -> E.Value:
  match state:
    case "pass":
      timed_validation_gate(status(E.get(result,"state_correctness")),config,result)
    case +state:
      gate(Bool.pick(String,String.is_empty(state),"inconclusive","fail"),
        Bool.pick(String,String.is_empty(state),"complete independent validation unavailable","independent validation failed"),text(config,"schedule"),["validation.json"])
def validation_gate(+result: E.Value, +validation: E.Value, +config: E.Value, failed_check: Bool) -> E.Value:
  validation_state(Bool.pick(String,failed_check,"",status(validation)),result,config)
def review_state(state: String, +result: E.Value, +config: E.Value) -> E.Value:
  match state:
    case "incorrect_rendering":
      E.put(E.put(result,"rendering_correctness",gate("fail","named feature geometry incorrect",text(config,"profile"),["review.json"])),
        "visual_quality",gate("inconclusive","rendering incorrect; readability cannot qualify",text(config,"profile"),["review.json"]))
    case "insufficient_readability": E.put(result,"visual_quality",gate("fail","named feature readability insufficient",text(config,"profile"),["review.json"]))
    case "pass":
      Bool.pick(E.Value,String.eq(status(E.get(result,"visual_quality")),"fail"),result,
        E.put(result,"visual_quality",gate("pass","named feature assessment passed",text(config,"profile"),["review.json"])))
    case _: result
def review_result(result: E.Value, review: E.Value, config: E.Value) -> E.Value:
  review_state(status(review),result,config)

def check_errors(result: Result<&2,&2,String,Unit>, errors: List<&2,E.Value>) -> List<&2,E.Value>:
  match result:
    case Fail{message}: add_error(errors,message)
    case Done{_}: errors
def ledger_errors(result: Result<&2,&2,String,E.Value>, +supervision: E.Value, errors: List<&2,E.Value>) -> List<&2,E.Value>:
  match result:
    case Fail{message}: add_error(errors,"allocation ledger: " ++ message)
    case Done{ledger}: errors_if(errors,E.eq(ledger,E.get(supervision,"allocation_ledger")),"allocation ledger: allocation ledger summary mismatch")
def allocation_errors(+records: List<&2,E.Value>, +supervision: E.Value, normal: Bool, +errors: List<&2,E.Value>) -> List<&2,E.Value>:
  S.delayed(List<&2,E.Value>,E.truth(E.Array{records}),
    _ => ledger_errors(I.allocation_audit(E.Array{records},normal),supervision,errors),_ => errors)
def reserve(cause: String) -> Bool:
  one_of(cause,["process_rss_reserve","available_ram_reserve","device_free_reserve","heap_budget_reserve"])
def non_gpu_error(value: E.Value) -> Bool:
  +error = E.text(value)
  Bool.not(String.eq(error,"required GPU evidence incomplete") || String.starts_with(error,"GPU: "))
def expected_case_actions(kind: String) -> U32:
  match kind:
    case "localized": 1
    case "support": 6
    case "history": 120
    case _: 0
def expected_actions(kind: String, schedule: String) -> U32:
  match schedule:
    case "history-12-v1": 12
    case "history-48-v1": 48
    case "support-1-span-v1": 2
    case "support-2-span-v1": 4
    case _: expected_case_actions(kind)
def schedule_gate(+flags: E.Value, +config: E.Value) -> E.Value:
  +rejected = matches(flags,"cause","required_edit_rejection") || (yes(E.get(flags,"full_frames")) && Bool.not(yes(E.get(flags,"action_ok"))))
  +passed = yes(E.get(flags,"schedule_pass"))
  gate(Bool.pick(String,rejected,"fail",Bool.pick(String,passed,"pass","inconclusive")),
    Bool.pick(String,rejected,"required action rejected, missing or extra",
      Bool.pick(String,passed,"complete declared schedule and required evidence","incomplete schedule or inconsistent required evidence")),
    text(config,"schedule"),["cpu.jsonl","reference.jsonl"])
def gather_errors(+payload: E.Value, +frames: List<&2,E.Value>, errors: List<&2,E.Value>) -> List<&2,E.Value>:
  +cpu = items(payload,"cpu")
  +reference = items(payload,"reference")
  +resources = items(payload,"resources")
  +allocations = items(payload,"allocations")
  +summary = E.get(payload,"summary")
  +supervision = E.get(summary,"supervision")
  +cause = text(E.get(summary,"termination"),"cause")
  +gpu = E.get(summary,"gpu_execution")
  +gpu_errors = Bool.pick(List<&2,E.Value>,E.truth(E.get(gpu,"errors")),items(gpu,"errors"),items(payload,"gpu_errors"))
  +source = Bool.pick(E.Value,E.has(summary,"source_evidence_errors"),E.get(summary,"source_evidence_errors"),
    Bool.pick(E.Value,E.has(summary,"evidence_errors"),E.get(summary,"evidence_errors"),E.Array{Nil{}}))
  +heap_maxima = heap_resources(resources,E.object(Nil{}))
  errors = errors_if(errors,Bool.not(E.truth(E.Array{reference})) ||
    E.eq(frame_identity(select(reference,"frame")),frame_identity(frames)),"CPU/reference frame mismatch")
  errors = errors_if(errors,Bool.not(E.truth(E.Array{reference})) ||
    U32.is_eq(E.count(select(reference,"action")),E.count(select(cpu,"action"))),"CPU/reference action mismatch")
  errors = errors_if(errors,E.truth(E.Array{reference}),"reference evidence unavailable")
  errors = errors_if(errors,Bool.not(E.truth(supervision)) || E.eq(E.get(E.get(supervision,"termination"),"cause"),E.get(E.get(summary,"termination"),"cause")),"summary/supervisor termination mismatch")
  errors = count_error(supervision,"resource_samples",resources,errors)
  errors = count_error(supervision,"allocation_records",allocations,errors)
  errors = count_error(supervision,"reference_records",reference,errors)
  errors = resource_extremum(resources,supervision,"rss_bytes","observed_maxima",True{},errors)
  errors = resource_extremum(resources,supervision,"available_ram_bytes","observed_minima",False{},errors)
  errors = resource_extremum(resources,supervision,"device_free_bytes","observed_minima",False{},errors)
  errors = errors_if(errors,Bool.not(E.truth(heap_maxima)) || E.eq(E.get(supervision,"heap_observed_maxima"),heap_maxima),"resource heap observed maxima mismatch")
  errors = allocation_errors(allocations,supervision,String.eq(cause,"normal_exit"),errors)
  errors = List.append(&2,E.Value,errors,prefix_errors(items(supervision,"errors"),"supervision: "))
  errors = errors_if(errors,E.truth(E.Array{resources}),"resource evidence unavailable")
  errors = errors_if(errors,E.truth(E.Array{allocations}),"allocation evidence unavailable")
  errors = List.append(&2,E.Value,errors,prefix_errors(gpu_errors,"GPU: "))
  errors = errors_if(errors,Bool.not(E.truth(E.Array{frames})) || yes(E.get(gpu,"required_evidence_complete")),"required GPU evidence incomplete")
  errors = unique(List.append(&2,E.Value,omit_gpu(E.array(source)),errors),Nil{})
  errors = errors_if(errors,Bool.not(String.eq(cause,"allocation_error")) || E.truth(E.Array{select(allocations,"allocation_failed")}),"allocation termination lacks explicit failed operation")
  errors_if(errors,Bool.not(reserve(cause)) || E.truth(E.get(E.get(summary,"termination"),"reason")),"reserve stop lacks supervisor source/time/value reason")
def schedule_flags(+payload: E.Value, +frames: List<&2,E.Value>, +accepted: List<&2,E.Value>, +integrity: Bool, +errors: List<&2,E.Value>) -> E.Value:
  +summary = E.get(payload,"summary")
  +config = E.get(E.get(payload,"manifest"),"effective")
  +cpu = items(payload,"cpu")
  +completions = select(cpu,"complete")
  +full = eqi(n(E.count(frames)),E.int_add(E.int_add(n(1),num(config,"warmup")),num(config,"frames")))
  +action_ok = U32.is_eq(E.count(accepted),expected_actions(text(config,"case"),text(config,"schedule"))) &&
    U32.is_eq(E.count(select(cpu,"action")),expected_actions(text(config,"case"),text(config,"schedule")))
  +completion = U32.is_eq(E.count(completions),1) && E.truth(E.Array{cpu}) &&
    E.eq(E.at(cpu,(E.count(cpu) - 1 : U32)),E.at(completions,0)) &&
    E.eq(E.get(E.at(completions,0),"frame"),E.string(E.int_show(E.int_add(E.int_add(n(1),num(config,"warmup")),num(config,"frames")))))
  +prior = E.get(summary,"schedule_completion")
  +cause = Bool.pick(String,E.has(E.get(summary,"termination"),"cause"),text(E.get(summary,"termination"),"cause"),"unknown")
  +passed = full && action_ok && String.eq(cause,"normal_exit") && completion &&
    (String.eq(status(prior),"pass") || String.starts_with(text(prior,"reason"),"required GPU evidence incomplete")) && integrity &&
    Bool.not(E.truth(E.get(payload,"cpu_errors"))) && Bool.not(any(~(_ => e => non_gpu_error(e)),E.Null{},errors))
  E.object([("full_frames",E.boolean(full)),("action_ok",E.boolean(action_ok)),("schedule_pass",E.boolean(passed)),("cause",E.string(cause))])
def top_integer_fields(+record: E.Value, keys: List<&2,String>) -> Result<&2,&2,String,Unit>:
  match keys:
    case Nil{}: Done{Unit{}}
    case key <> rest:
      do Result<&2,&2,String,Unit>:
        value : E.Value <- E.required(record,key)
        _ : E.Signed <- E.natural(value)
        top_integer_fields(record,rest)
def natural_values(values: List<&2,E.Value>) -> Result<&2,&2,String,Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case value <> rest:
      do Result<&2,&2,String,Unit>:
        _ : E.Signed <- E.natural(value)
        natural_values(rest)
def history_inputs(fields: List<&2,E.Field()>) -> Result<&2,&2,String,Unit>:
  match fields:
    case Nil{}: Done{Unit{}}
    case (_,pair) <> rest:
      +values = E.array(pair)
      +len = E.count(values)
      do Result<&2,&2,String,Unit>:
        _ : Unit <- natural_values(List.take(&2,E.Value,values,3n))
        _ : Unit <- E.require(U32.is_eq(len,2),Bool.pick(String,(len < 2 : U32),
          "not enough values to unpack (expected 2, got " ++ U32.show(len) ++ ")","too many values to unpack (expected 2)"))
        history_inputs(rest)
def scalar_resource_inputs(resources: List<&2,E.Value>, +field: String) -> Result<&2,&2,String,Unit>:
  match resources:
    case Nil{}: Done{Unit{}}
    case +record <> rest:
      do Result<&2,&2,String,Unit>:
        _ : Unit <- S.delayed(Result<&2,&2,String,Unit>,E.has(record,field) && Bool.not(matches(record,"phase","preflight")),
          _ => top_integer_fields(record,[field]),_ => Done{Unit{}})
        scalar_resource_inputs(rest,field)
def heap_inputs(heaps: List<&2,E.Value>) -> Result<&2,&2,String,Unit>:
  match heaps:
    case Nil{}: Done{Unit{}}
    case +heap <> rest:
      do Result<&2,&2,String,Unit>:
        _ : E.Value <- E.required(heap,"heap")
        _ : Unit <- top_integer_fields(heap,["usage_bytes"])
        heap_inputs(rest)
def resource_inputs(resources: List<&2,E.Value>) -> Result<&2,&2,String,Unit>:
  match resources:
    case Nil{}: Done{Unit{}}
    case +row <> rest:
      do Result<&2,&2,String,Unit>:
        _ : Unit <- heap_inputs(items(row,"heaps"))
        resource_inputs(rest)
def count_inputs(+supervision: E.Value, keys: List<&2,String>) -> Result<&2,&2,String,Unit>:
  match keys:
    case Nil{}: Done{Unit{}}
    case +key <> rest:
      do Result<&2,&2,String,Unit>:
        _ : Unit <- S.delayed(Result<&2,&2,String,Unit>,E.has(supervision,key),
          _ => top_integer_fields(supervision,[key]),_ => Done{Unit{}})
        count_inputs(supervision,rest)
def analysis_inputs(+payload: E.Value, +frames: List<&2,E.Value>) -> Result<&2,&2,String,Unit>:
  +summary = E.get(payload,"summary")
  +supervision = E.get(summary,"supervision")
  +config = E.get(E.get(payload,"manifest"),"effective")
  +schedule = E.get(payload,"schedule")
  +resources = items(payload,"resources")
  do Result<&2,&2,String,Unit>:
    _ : Unit <- S.delayed(Result<&2,&2,String,Unit>,matches(config,"case","history") && object(schedule),
      _ => history_inputs(E.fields(E.get(schedule,"history_populations"))),_ => Done{Unit{}})
    _ : Unit <- S.delayed(Result<&2,&2,String,Unit>,Bool.not(List.is_empty(&2,E.Value,frames)) && E.truth(E.get(supervision,"launch_ns")),
      _ => top_integer_fields(supervision,["launch_ns"]),_ => Done{Unit{}})
    _ : Unit <- count_inputs(supervision,["resource_samples","allocation_records","reference_records"])
    _ : Unit <- scalar_resource_inputs(resources,"rss_bytes")
    _ : Unit <- scalar_resource_inputs(resources,"available_ram_bytes")
    _ : Unit <- scalar_resource_inputs(resources,"device_free_bytes")
    resource_inputs(resources)
def prepare_analyzed(+payload: E.Value, +frames: List<&2,E.Value>, +valid_edits: List<&2,E.Value>, +integrity: Bool, +errors: List<&2,E.Value>, stages: E.Value) -> Result<&2,&2,String,E.Value>:
  +manifest = E.get(payload,"manifest")
  +summary = E.get(payload,"summary")
  +config = E.get(manifest,"effective")
  +perf = performance(config)
  +warmup = word(num(config,"warmup"))
  +measured = List.drop(&2,E.Value,frames,U32.to_nat((warmup + 1 : U32)))
  +ordinary = duration_values(filter(~(ctx => +r => matches(r,"population","ordinary") || (Bool.not(E.bool(ctx)) && matches(r,"population","motion"))),E.boolean(perf),measured))
  +accepted = duration_values(filter(~(_ => r => yes(E.get(r,"accepted"))),E.Null{},valid_edits))
  +groups = E.object(populations(frames,["startup","warmup","edit","motion"]))
  +groups = E.put(E.put(groups,"ordinary",distribution(ordinary)),"combined",distribution(duration_values(measured)))
  +errors = gather_errors(payload,frames,errors)
  +flags = schedule_flags(payload,frames,accepted,integrity,errors)
  +cause = text(flags,"cause")
  +source = Bool.pick(E.Value,E.has(summary,"source_evidence_errors"),E.get(summary,"source_evidence_errors"),
    Bool.pick(E.Value,E.has(summary,"evidence_errors"),E.get(summary,"evidence_errors"),E.Array{Nil{}}))
  +result = E.put(E.put(summary,"synthetic",E.boolean(E.truth(E.get(manifest,"synthetic")) || E.truth(E.get(summary,"synthetic")))),"attempt_kind",E.get(manifest,"attempt_kind"))
  +result = E.put(E.put(E.put(result,"populations",groups),"accepted_edits",distribution(accepted)),"stage_populations",
    E.object(stage_distributions(E.fields(stages))))
  +result = Bool.pick(E.Value,matches(config,"case","history") && object(E.get(payload,"schedule")),
    E.put(result,"history_populations",E.object(history_populations(E.fields(E.get(E.get(payload,"schedule"),"history_populations")),measured,config))),result)
  +result = E.put(E.put(E.put(result,"measured_interval_ns",E.string(E.int_show(measured_duration(measured)))),"completed_prefix",E.object([
    ("startup",E.boolean(E.truth(E.Array{frames}))),
    ("warmup",E.string(U32.show(U32.min(U32.sub(E.count(frames),U32.min(E.count(frames),1)),warmup)))),
    ("measured",E.string(U32.show(U32.sub(E.count(frames),U32.min(E.count(frames),(warmup + 1 : U32))))))])),"cold_startup",cold_startup(frames,summary))
  +result = E.put(E.put(result,"source_evidence_errors",source),"termination_evidence",gate(
    Bool.pick(String,String.eq(cause,"unknown") || contains(errors,"termination"),"inconclusive","pass"),
    Bool.pick(String,String.eq(cause,"unknown"),"termination cause unavailable","supervisor cause and supporting raw evidence"),
    "attempt termination",["supervision.json","resources.jsonl","allocations.jsonl"]))
  +result = E.put(result,"schedule_completion",schedule_gate(flags,config))
  +validation = E.get(payload,"validation")
  +check_errors = S.delayed(List<&2,E.Value>,String.eq(status(validation),"pass"),
    _ => check_errors(checkpoint_check(validation,E.get(payload,"comparison"),items(payload,"cpu"),E.get(payload,"schedule"),config),Nil{}),_ => Nil{})
  +errors = List.append(&2,E.Value,errors,check_errors)
  +result = E.put(result,"state_correctness",validation_gate(result,validation,config,E.truth(E.Array{check_errors})))
  +result = review_result(result,E.get(payload,"review"),config)
  +result = Bool.pick(E.Value,String.eq(status(E.get(result,"numeric_validity")),"pass") && Bool.not(String.eq(status(E.get(manifest,"numeric_admission")),"pass")),
    E.put(result,"numeric_validity",gate("inconclusive","numeric admission evidence does not pass",text(config,"schedule"),["manifest.json"])),result)
  do Result<&2,&2,String,E.Value>:
    _ : Unit <- analysis_inputs(payload,frames)
    cal : E.Value <- calibration(E.get(payload,"calibration"),config,text(result,"attempt_kind"))
    result : E.Value = E.put(E.put(result,"calibration",cal),"evidence_errors",E.Array{errors})
    context : E.Value = E.object([("config",config),("ordinary_count",E.number(U32.show(E.count(ordinary)))),
      ("ordinary_duration",E.string(E.int_show(sum(ordinary)))),("accepted_count",E.number(U32.show(E.count(accepted)))),
      ("cpu_integrity",E.boolean(integrity)),("cpu_frames",E.boolean(E.truth(E.Array{frames}))),
      ("cpu_errors",E.get(payload,"cpu_errors")),("resources",E.boolean(E.truth(E.get(payload,"resources")))),
      ("allocations",E.boolean(E.truth(E.get(payload,"allocations")))),("reference",E.boolean(E.truth(E.get(payload,"reference")))),
      ("failed_allocations",E.boolean(E.truth(E.Array{select(items(payload,"allocations"),"allocation_failed")}))),
      ("gpu_errors",Bool.pick(E.Value,E.truth(E.get(E.get(summary,"gpu_execution"),"errors")),E.get(E.get(summary,"gpu_execution"),"errors"),E.get(payload,"gpu_errors"))),
      ("cause",E.string(cause))])
    return E.object([("result",result),("context",context)])
def prepare_analysis(+payload: E.Value, +frames: List<&2,E.Value>, +valid_edits: List<&2,E.Value>, +integrity: Bool, +errors: List<&2,E.Value>) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    stages : E.Value <- stage_values(items(payload,"cpu"),frame_catalog(frames),
      performance(E.get(E.get(payload,"manifest"),"effective")),E.object(Nil{}))
    prepare_analyzed(payload,frames,valid_edits,integrity,errors,stages)
def prepare_edits(+payload: E.Value, +frames: List<&2,E.Value>, +errors: List<&2,E.Value>, initial: U32, edits: Prefix) -> Result<&2,&2,String,E.Value>:
  match edits:
    case Prefix{valid,edit_errors}:
      +errors = List.append(&2,E.Value,errors,edit_errors)
      prepare_analysis(payload,frames,valid,U32.is_eq(E.count(errors),initial),errors)
def prepare_frames(+payload: E.Value, +errors: List<&2,E.Value>, initial: U32, frames: Prefix) -> Result<&2,&2,String,E.Value>:
  match frames:
    case Prefix{+valid,frame_errors}:
      +edits = select(items(payload,"cpu"),"edit")
      prepare_edits(payload,valid,List.append(&2,E.Value,errors,frame_errors),initial,
        edits_checked(edits,edits,select(items(payload,"cpu"),"action"),Nil{},valid,E.get(E.get(payload,"manifest"),"effective")))
def prepare(+payload: E.Value) -> Result<&2,&2,String,E.Value>:
  +manifest = E.get(payload,"manifest")
  +summary = E.get(payload,"summary")
  +config = E.get(manifest,"effective")
  +errors = List.append(&2,E.Value,List.append(&2,E.Value,List.append(&2,E.Value,items(payload,"cpu_errors"),items(payload,"resource_errors")),items(payload,"allocation_errors")),items(payload,"reference_errors"))
  +initial = E.count(errors)
  +schedule = E.get(payload,"schedule")
  do Result<&2,&2,String,E.Value>:
    _ : Unit <- checked_object(manifest,"manifest")
    _ : Unit <- checked_object(summary,"summary")
    _ : Unit <- required_top_keys(manifest,["record_type","attempt_id","effective","attempt_kind"])
    _ : Unit <- required_top_keys(summary,["record_type","attempt_id"])
    _ : Unit <- E.require(matches(manifest,"record_type","manifest") && matches(summary,"record_type","summary") && E.eq(E.get(manifest,"attempt_id"),E.get(summary,"attempt_id")),"manifest/summary identity mismatch")
    _ : Unit <- E.require(object(config),"missing effective configuration")
    _ : Unit <- required_top_keys(config,["case","profile","schedule","warmup","frames"])
    _ : Unit <- integer_fields(config,["warmup","frames"])
    _ : Unit <- record_types(items(payload,"cpu"))
    _ : Unit <- record_types(items(payload,"reference"))
    errors : List<&2,E.Value> = S.delayed(List<&2,E.Value>,performance(config),_ =>
      check_errors(I.performance_validate(schedule),errors),_ => errors)
    prepare_frames(payload,errors,initial,frames_checked(select(items(payload,"cpu"),"frame"),0,E.Null{},config,items(schedule,"frames")))

def statistic_failures(+stats: E.Value, limits: List<&2,E.Field()>, +prefix: String) -> List<&2,E.Value>:
  match limits:
    case Nil{}: Nil{}
    case (+key,limit) <> rest:
      +remaining = statistic_failures(stats,rest,prefix)
      Bool.pick(List<&2,E.Value>,Bool.not(E.rational_le(E.rational(E.get(stats,key)),E.rational(limit))),
        E.string(prefix ++ key) <> remaining,remaining)
def value_strings(values: List<&2,E.Value>) -> List<&2,String>:
  match values:
    case Nil{}: Nil{}
    case v <> rest: E.text(v) <> value_strings(rest)
def join(values: List<&2,E.Value>) -> String: String.join(value_strings(values),", ")
def lowercase(value: String) -> String:
  match value:
    case SNil{}: SNil{}
    case SCon{Chr{+c},rest}:
      SCon{Chr{Bool.pick(U32,((c >= 65) && (c <= 90) : U32),(c + 32 : U32),c)},lowercase(rest)}
def gate_requirements(+result: E.Value, names: List<&2,String>, +failure: Bool) -> List<&2,E.Value>:
  match names:
    case Nil{}: Nil{}
    case +name <> rest:
      +state = status(E.get(result,name))
      +keep = Bool.pick(Bool,failure,String.eq(state,"fail"),Bool.not(String.eq(state,"pass")))
      +remaining = gate_requirements(result,rest,failure)
      Bool.pick(List<&2,E.Value>,keep,E.string(name) <> remaining,remaining)
def gate_reason(+failures: List<&2,E.Value>, +missing: List<&2,E.Value>, successful: String) -> String:
  Bool.pick(String,E.truth(E.Array{failures}),"failed: " ++ join(failures),
    Bool.pick(String,E.truth(E.Array{missing}),"unqualified: " ++ join(missing),successful))
def finalize(+prepared: E.Value) -> E.Value:
  +result = E.get(prepared,"result")
  +context = E.get(prepared,"context")
  +config = E.get(context,"config")
  +perf = performance(config)
  +ordinary_count = word(num(context,"ordinary_count"))
  +accepted_count = word(num(context,"accepted_count"))
  +action_required = one_of(text(config,"case"),["localized","support","history"])
  +ordinary_duration = Bool.pick(E.Signed,perf,num(context,"ordinary_duration"),num(result,"measured_interval_ns"))
  +enough = T.population(ordinary_count,E.int_abs(ordinary_duration)) && Bool.not(E.int_negative(ordinary_duration))
  +edit_enough = T.edits(accepted_count)
  +population_reason = Bool.pick(String,enough,
    Bool.pick(String,perf,"1000 ordinary frames and 10 ordinary seconds","1000 ordinary frames and 10 measured seconds"),
    Bool.pick(String,perf,"requires 1000 ordinary frames and 10 ordinary seconds in this attempt","requires 1000 ordinary frames and 10 measured seconds in this attempt"))
  +result = E.put(result,"population_qualification",gate(Bool.pick(String,enough,"pass","inconclusive"),population_reason,"ordinary frames",["cpu.jsonl"]))
  +result = E.put(result,"edit_response",Bool.pick(E.Value,action_required,
    gate(Bool.pick(String,edit_enough,"pass","inconclusive"),Bool.pick(String,edit_enough,"at least 100 accepted edits","fewer than 100 accepted edits in this attempt"),"accepted edits",["cpu.jsonl"]),
    gate("not_applicable","no edits in declared schedule","accepted edits",Nil{})))
  +startup = E.get(result,"cold_startup")
  +failed = Bool.pick(List<&2,E.Value>,String.eq(status(startup),"measured") && gti(num(startup,"value"),E.int_text("30000000000")),[E.string("startup")],Nil{})
  +ordinary = E.get(E.get(result,"populations"),"ordinary")
  +failed = List.append(&2,E.Value,failed,Bool.pick(List<&2,E.Value>,(ordinary_count > 0 : U32),
    statistic_failures(ordinary,[("mean",E.number("16700000")),("p95",E.number("16700000")),("p99",E.number("33300000")),("max",E.number("100000000"))],"ordinary_"),Nil{}))
  +failed = List.append(&2,E.Value,failed,Bool.pick(List<&2,E.Value>,action_required && (accepted_count > 0 : U32),
    statistic_failures(E.get(result,"accepted_edits"),[("p95",E.number("100000000")),("max",E.number("250000000"))],"edit_"),Nil{}))
  +ready = enough && String.eq(status(startup),"measured") && (Bool.not(action_required) || edit_enough)
  +responsiveness = Bool.pick(String,E.truth(E.Array{failed}),"fail",Bool.pick(String,ready,"pass","inconclusive"))
  +result = E.put(result,"responsiveness",E.put(gate(responsiveness,
    Bool.pick(String,E.truth(E.Array{failed}),join(failed),Bool.pick(String,ready,"all applicable latency gates pass","latency population or startup evidence insufficient")),
    "declared interactive gates",["cpu.jsonl"]),"failed_gates",E.Array{failed}))
  +errors = items(result,"evidence_errors")
  +resource_ok = Bool.not(contains(errors,"resource") || contains(errors,"allocation") || contains(errors,"supervision")) && yes(E.get(context,"resources")) && yes(E.get(context,"allocations"))
  +cpu_available = yes(E.get(context,"cpu_frames")) && yes(E.get(context,"cpu_integrity")) && Bool.not(E.truth(E.get(context,"cpu_errors")))
  +gpu_ok = yes(E.get(E.get(result,"gpu_execution"),"required_evidence_complete"))
  +result = E.put(result,"measurement_availability",E.object([
    ("cpu",gate(Bool.pick(String,cpu_available,"pass","inconclusive"),Bool.pick(String,cpu_available,"completed CPU intervals","CPU intervals incomplete"),"frame intervals",["cpu.jsonl"])),
    ("gpu",gate(Bool.pick(String,gpu_ok,"pass","inconclusive"),Bool.pick(String,gpu_ok,"GPU capability and interval evidence","GPU intervals incomplete"),"submitted work",["gpu.jsonl"])),
    ("resources",gate(Bool.pick(String,resource_ok,"pass","inconclusive"),Bool.pick(String,resource_ok,"supervised resource/allocation evidence","resource or allocation evidence incomplete"),"attempt",["resources.jsonl","allocations.jsonl"]))]))
  +requirements = {["state_correctness","rendering_correctness","visual_quality","numeric_validity","schedule_completion"] : List<&2,String>}
  +failures = gate_requirements(result,requirements,True{})
  +missing = gate_requirements(result,requirements,False{})
  +result = E.put(result,"workload_completion",gate(Bool.pick(String,E.truth(E.Array{failures}),"fail",Bool.pick(String,E.truth(E.Array{missing}),"inconclusive","pass")),
    gate_reason(failures,missing,"required state, fidelity, numeric and schedule evidence"),"complete declared workload",["validation.json","comparison.json","review.json","cpu.jsonl"]))
  +missing = Bool.pick(List<&2,E.Value>,resource_ok,missing,List.append(&2,E.Value,missing,[E.string("resource_evidence")]))
  +integrity_error = any(~(ctx => +e => non_gpu_error(e) && Bool.not(member(e,E.array(ctx)))),E.get(context,"gpu_errors"),errors)
  +missing = Bool.pick(List<&2,E.Value>,integrity_error,List.append(&2,E.Value,missing,[E.string("evidence_integrity")]),missing)
  +reference_error = Bool.not(yes(E.get(context,"reference"))) || any(~(_ => e => String.contains(lowercase(E.text(e)),"reference")),E.Null{},errors)
  +missing = Bool.pick(List<&2,E.Value>,reference_error,List.append(&2,E.Value,missing,[E.string("reference_evidence")]),missing)
  +nonqualifying = one_of(text(result,"attempt_kind"),["calibration_off","validation_only","validation_replay","opening_capture","admission","reproduction"])
  +missing = Bool.pick(List<&2,E.Value>,nonqualifying,List.append(&2,E.Value,missing,[E.string("nonqualifying_attempt_kind")]),missing)
  +cause = text(context,"cause")
  +failed_cause = reserve(cause) || one_of(cause,["required_edit_rejection","allocation_error","device_loss"])
  +failures = Bool.pick(List<&2,E.Value>,failed_cause,List.append(&2,E.Value,failures,[E.string(cause)]),failures)
  +capacity = Bool.pick(String,E.truth(E.Array{failures}),"fail",Bool.pick(String,E.truth(E.Array{missing}),"inconclusive","pass"))
  +result = E.put(result,"qualified_capacity",gate(capacity,gate_reason(failures,missing,"correct complete workload within policy"),"complete declared workload",["summary.json","validation.json","supervision.json"]))
  +interactive = Bool.pick(String,String.eq(capacity,"fail") || String.eq(responsiveness,"fail"),"fail",
    Bool.pick(String,String.eq(capacity,"pass") && String.eq(responsiveness,"pass") && String.eq(status(E.get(result,"calibration")),"pass") && gpu_ok,"pass","inconclusive"))
  +result = E.put(result,"interactive_pass",gate(interactive,
    Bool.pick(String,String.eq(interactive,"pass"),"qualified single-attempt interactive observation",
      Bool.pick(String,String.eq(interactive,"fail"),"latency or required correctness/fidelity failed","capacity, populations or calibration not qualified")),"single attempt",["summary.json"]))
  +result = E.put(result,"confirmed_endpoint",gate("inconclusive","one attempt cannot confirm a search endpoint","series repetition",["campaign.json","series.json"]))
  +synthetic = yes(E.get(result,"synthetic"))
  +result = E.put(result,"endpoint_eligible",gate(Bool.pick(String,synthetic,"inconclusive",Bool.pick(String,String.eq(interactive,"pass"),"pass","inconclusive")),
    Bool.pick(String,synthetic,"synthetic fixture is excluded from measured searches",Bool.pick(String,String.eq(interactive,"pass"),"qualified attempt requires separate repetitions","attempt is not a qualified interactive observation")),"search input",Nil{}))
  +allocation_failure = String.eq(cause,"allocation_error") && yes(E.get(context,"failed_allocations"))
  +result = E.put(result,"observed_capacity_failure",gate(Bool.pick(String,allocation_failure,"inconclusive","not_applicable"),
    Bool.pick(String,allocation_failure,"explicit allocation failure is one observation; diagnostic retry required","no confirmed allocation failure endpoint"),
    "single attempt",Bool.pick(List<&2,String>,yes(E.get(context,"failed_allocations")),["allocations.jsonl"],Nil{})))
  +result = E.put(result,"implementation_acceptance",gate("inconclusive","one attempt, including a truthfully reported failure, cannot complete the required acceptance matrix","issue #47 acceptance matrix",["campaign.json"]))
  +result = E.put(result,"raw_evidence",E.object([("cpu",E.string("cpu.jsonl")),("gpu",E.string("gpu.jsonl")),("resources",E.string("resources.jsonl")),
    ("allocations",E.string("allocations.jsonl")),("reference",E.string("reference.jsonl")),("checkpoints",E.string("cpu.jsonl")),("actions",E.string("cpu.jsonl"))]))
  E.put(result,"qualification",E.string(Bool.pick(String,synthetic,"synthetic_report","classified_attempt")))
def result_value(result: Result<&2,&2,String,E.Value>) -> E.Value:
  match result:
    case Fail{message}: E.Error{message}
    case Done{value}: value
def optional_integers(+record: E.Value, fields: List<&2,String>) -> Result<&2,&2,String,Unit>:
  match fields:
    case Nil{}: Done{Unit{}}
    case +field <> rest:
      do Result<&2,&2,String,Unit>:
        _ : Unit <- S.delayed(Result<&2,&2,String,Unit>,E.has(record,field),_ => value_integer(record,field),_ => Done{Unit{}})
        optional_integers(record,rest)
def stream_heaps(heaps: List<&2,E.Value>) -> Result<&2,&2,String,Unit>:
  match heaps:
    case Nil{}: Done{Unit{}}
    case heap <> rest:
      do Result<&2,&2,String,Unit>:
        _ : Unit <- integer_fields(heap,["heap","usage_bytes","budget_bytes"])
        stream_heaps(rest)
def cpu_stream_interval(+record: E.Value, +now: E.Signed) -> Result<&2,&2,String,Unit>:
  do Result<&2,&2,String,Unit>:
    _ : Unit <- integer_fields(record,["begin_ns","end_ns","duration_ns"])
    _ : Unit <- required_keys(record,["status","unit"])
    E.require(lei(num(record,"begin_ns"),num(record,"end_ns")) && lei(num(record,"end_ns"),now) &&
      eqi(num(record,"duration_ns"),E.int_sub(num(record,"end_ns"),num(record,"begin_ns"))) &&
      matches(record,"status","measured") && matches(record,"unit","ns"),"invalid CPU interval")
def resource_stream_interval(+record: E.Value, +now: E.Signed) -> Result<&2,&2,String,Unit>:
  do Result<&2,&2,String,Unit>:
    _ : Unit <- integer_fields(record,["sample_begin_ns","sample_end_ns"])
    _ : Unit <- required_keys(record,["unit"])
    _ : Unit <- E.require(lei(num(record,"sample_begin_ns"),num(record,"sample_end_ns")) &&
      lei(num(record,"sample_end_ns"),now) && matches(record,"unit","bytes"),"invalid resource sample boundary/unit")
    _ : Unit <- optional_integers(record,["rss_bytes","available_ram_bytes","device_free_bytes"])
    stream_heaps(items(record,"heaps"))
def stream_check(+record: E.Value, +manifest: E.Value, +name: String, +index: U32, +last_time: E.Value) -> Result<&2,&2,String,Unit>:
  do Result<&2,&2,String,Unit>:
    _ : Unit <- checked_object(record,name)
    _ : Unit <- required_keys(manifest,["attempt_id","series_id","campaign_id"])
    _ : Unit <- E.require(all_keys(~(+ctx => +key => E.eq(E.get(E.at(E.array(ctx),0),key),E.get(E.at(E.array(ctx),1),key))),
      E.Array{[record,manifest]},["attempt_id","series_id","campaign_id"]),name ++ " identity mismatch")
    _ : Unit <- value_integer(record,"sequence")
    _ : Unit <- E.require(eqi(num(record,"sequence"),n(index)),name ++ " sequence gap or duplicate")
    _ : Unit <- required_keys(record,["clock_id"])
    _ : Unit <- E.require(matches(record,"clock_id","linux.CLOCK_MONOTONIC"),name ++ " clock mismatch")
    _ : Unit <- value_integer(record,"time_ns")
    _ : Unit <- E.require(E.is_null(last_time) || lei(E.int(last_time),num(record,"time_ns")),name ++ " time regressed")
    _ : Unit <- S.delayed(Result<&2,&2,String,Unit>,String.eq(name,"cpu.jsonl"),_ =>
      required_keys(record,["record_type"]),_ => Done{Unit{}})
    _ : Unit <- S.delayed(Result<&2,&2,String,Unit>,String.eq(name,"cpu.jsonl") && one_of(text(record,"record_type"),["frame","stage","edit"]),
      _ => cpu_stream_interval(record,num(record,"time_ns")),_ => Done{Unit{}})
    S.delayed(Result<&2,&2,String,Unit>,String.eq(name,"resources.jsonl") && matches(record,"status","measured"),
      _ => resource_stream_interval(record,num(record,"time_ns")),_ => Done{Unit{}})
@unsafe def stream_checked(check: Result<&2,&2,String,Unit>, +record: E.Value, rest: List<&2,E.Value>, manifest: E.Value, name: String, index: U32, parse_error: E.Value) -> Prefix:
  match check:
    case Fail{message}: Prefix{Nil{},[E.string(message)]}
    case Done{_}: prefix_cons(record,stream_records(rest,manifest,name,(index + 1 : U32),E.get(record,"time_ns"),parse_error))
@unsafe def stream_records(records: List<&2,E.Value>, +manifest: E.Value, +name: String, +index: U32, +last_time: E.Value, +parse_error: E.Value) -> Prefix:
  match records:
    case Nil{}: Prefix{Nil{},Bool.pick(List<&2,E.Value>,E.is_null(parse_error),Nil{},[parse_error])}
    case +record <> rest:
      stream_checked(stream_check(record,manifest,name,index,last_time),record,rest,manifest,name,index,parse_error)
def stream_result(prefix: Prefix) -> E.Value:
  match prefix:
    case Prefix{records,errors}: E.object([("records",E.Array{records}),("errors",E.Array{errors})])
def checked_value(+value: E.Value, kind: String) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    _ : Unit <- checked_object(value,kind)
    return value
def calibration_binding_pass(+calibration: E.Value, +artifacts: E.Value, pass: Bool) -> Result<&2,&2,String,E.Value>:
  match pass:
    case False{}: Done{E.boolean(False{})}
    case True{}:
      do Result<&2,&2,String,E.Value>:
        _ : Unit <- E.require(E.eq(E.get(E.get(calibration,"binding"),"artifacts"),artifacts),
          "performance calibration runtime/schedule binding mismatch")
        return E.boolean(True{})
def calibration_binding(+payload: E.Value) -> Result<&2,&2,String,E.Value>:
  +calibration = E.get(payload,"calibration")
  do Result<&2,&2,String,E.Value>:
    state : E.Value <- E.required(calibration,"status")
    calibration_binding_pass(calibration,E.get(payload,"artifacts"),E.eq(state,E.string("pass")))
def calibration_assessment_scope(+assessment: E.Value, +calibration: E.Value, matches: Bool) -> Result<&2,&2,String,E.Value>:
  match matches:
    case False{}: Fail{"performance calibration assessment mismatch"}
    case True{}:
      do Result<&2,&2,String,E.Value>:
        binding : E.Value <- E.required(calibration,"binding")
        _ : Unit <- E.require(E.eq(E.get(assessment,"binding"),binding),"performance calibration assessment mismatch")
        return E.Null{}
def calibration_assessment_status(+assessment: E.Value, +calibration: E.Value, matches: Bool) -> Result<&2,&2,String,E.Value>:
  match matches:
    case False{}: Fail{"performance calibration assessment mismatch"}
    case True{}:
      do Result<&2,&2,String,E.Value>:
        actual : E.Value <- E.required(assessment,"scope")
        expected : E.Value <- E.required(calibration,"scope")
        calibration_assessment_scope(assessment,calibration,E.eq(actual,expected))
def calibration_assessment(+payload: E.Value) -> Result<&2,&2,String,E.Value>:
  +assessment = E.get(payload,"assessment")
  +calibration = E.get(payload,"calibration")
  do Result<&2,&2,String,E.Value>:
    actual : E.Value <- E.required(assessment,"status")
    expected : E.Value <- E.required(calibration,"status")
    calibration_assessment_status(assessment,calibration,E.eq(actual,expected))
def handle(operation: String, +payload: E.Value) -> E.Value:
  match operation:
    case "distribution": distribution(E.array(payload))
    case "calibration_result": result_value(calibration(E.get(payload,"value"),E.get(payload,"config"),text(payload,"attempt_kind")))
    case "prepare": result_value(prepare(payload))
    case "finalize": finalize(payload)
    case "checked_object": result_value(checked_value(E.get(payload,"value"),text(payload,"kind")))
    case "calibration_binding": result_value(calibration_binding(payload))
    case "calibration_assessment": result_value(calibration_assessment(payload))
    case "stream": stream_result(stream_records(items(payload,"records"),E.get(payload,"manifest"),text(payload,"name"),0,E.Null{},E.get(payload,"parse_error")))
    case _: E.Error{"unsupported report evidence operation"}
def main() -> IO(Unit): E.main(~handle)
