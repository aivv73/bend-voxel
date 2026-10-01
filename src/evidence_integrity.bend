import Base
import ./evidence_value.bend as E
import ./megascene_scale.bend as S

def get(v: E.Value, key: String) -> E.Value: E.get(v,key)
def text(v: E.Value, key: String) -> String: E.text(get(v,key))
def eq(v: E.Value, key: String, expected: String) -> Bool: E.eq(get(v,key),E.Text{expected})
def require(ok: Bool, reason: String) -> Result<&2,&2,String,Unit>:
  match ok:
    case True{}: Done{Unit{}}
    case False{}: Fail{reason}
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
def number(n: U32) -> E.Signed: E.int(E.Number{U32.show(n)})
def maximum(+a: E.Signed, +b: E.Signed) -> E.Signed: Bool.pick(E.Signed,E.int_le(a,b),b,a)
def zero_default(value: E.Value) -> E.Signed:
  match value:
    case E.Null{}: number(0)
    case _: E.int(value)
def remove(fields: List<&2,E.Field()>, +key: String) -> List<&2,E.Field()>:
  match fields:
    case Nil{}: Nil{}
    case (+k,v) <> rest:
      +tail = remove(rest,key)
      Bool.pick(List<&2,E.Field()>,String.eq(k,key),tail,(k,v) <> tail)
def list_fields_count(fields: List<&2,E.Field()>) -> U32:
  match fields:
    case Nil{}: 0
    case h <> t: (1 + list_fields_count(t) : U32)
@unsafe
def allocation_rows(rows: List<&2,E.Value>, +normal: Bool, +live: E.Signed, +peak: E.Signed, +next_id: E.Signed,
  +owned: E.Value, +heaps: E.Value, +peaks: E.Value, +device: E.Value) -> Result<&2,&2,String,E.Value>:
  match rows:
    case Nil{}:
      do Result<&2,&2,String,E.Value>:
        _ : Unit <- require(Bool.not(normal) || U32.is_eq(list_fields_count(E.fields(owned)),0),"normal teardown left live explicit allocations")
        return E.Object{[("live_bytes",E.int_string(live)),("peak_bytes",E.int_string(peak)),
          ("live_allocations",E.Text{U32.show(list_fields_count(E.fields(owned)))}),
          ("scope",E.Text{"explicit Vulkan allocations; not residency or heap budgets"})]}
    case +r <> rest:
      do Result<&2,&2,String,E.Value>:
        +kind : String = text(r,"record_type")
        allocation_step(eq(r,"record_type","vulkan_error"),r,rest,normal,live,peak,next_id,owned,heaps,peaks,device)

@unsafe
def allocation_step(error: Bool, +r: E.Value, rows: List<&2,E.Value>, +normal: Bool, +live: E.Signed, +peak: E.Signed,
  +next_id: E.Signed, +owned: E.Value, +heaps: E.Value, +peaks: E.Value, +device: E.Value) -> Result<&2,&2,String,E.Value>:
  match error:
    case True{}:
      do Result<&2,&2,String,E.Value>:
        _ : Unit <- require(Bool.not(E.int_eq(E.int(get(r,"vk_result")),number(0))) && E.truth(get(r,"operation")),"invalid Vulkan failure")
        allocation_rows(rows,normal,live,peak,next_id,owned,heaps,peaks,device)
    case False{}:
      do Result<&2,&2,String,E.Value>:
        +kind : String = text(r,"record_type")
        _ : Unit <- require(String.eq(kind,"allocate") || String.eq(kind,"free") || String.eq(kind,"allocation_failed"),"unexpected ledger event")
        +ident : E.Signed <- E.natural(get(r,"allocation_id"))
        +size : E.Signed <- E.natural(get(r,"size_bytes"))
        +heap_id : E.Signed <- E.natural(get(r,"heap"))
        +heap : String = E.int_show(heap_id)
        _ : E.Signed <- E.natural(get(r,"memory_type"))
        _ : Unit <- require(Bool.not(E.int_le(size,number(0))),"zero allocation size")
        _ : Unit <- require(E.has(r,"device"),"missing field:device")
        +actual_device : E.Value = Bool.pick(E.Value,E.eq(device,E.Null{}),get(r,"device"),device)
        _ : Unit <- require(E.eq(get(r,"device"),actual_device),"allocation device changed")
        _ : Unit <- require(String.eq(kind,"free") || E.int_eq(ident,next_id),"allocation identity gap/duplicate")
        +following : E.Signed = Bool.pick(E.Signed,String.eq(kind,"free"),next_id,E.int_add(next_id,number(1)))
        +key : String = E.int_show(ident)
        +entry : E.Value = E.Array{[E.int_string(size),get(r,"heap"),get(r,"memory_type")]}
        _ : Unit <- require(Bool.not(String.eq(kind,"allocate")) || eq(r,"vk_result","0"),"successful allocation has error status")
        _ : Unit <- require(Bool.not(String.eq(kind,"free")) || E.eq(get(owned,key),entry),"free identity/size/type mismatch")
        _ : Unit <- require(Bool.not(String.eq(kind,"free")) || eq(r,"vk_result","0"),"invalid free result")
        _ : Unit <- require(Bool.not(String.eq(kind,"allocation_failed")) || Bool.not(E.int_eq(E.int(get(r,"vk_result")),number(0))),"failed allocation has successful result")
        +new_owned : E.Value = Bool.pick(E.Value,String.eq(kind,"allocate"),E.put(owned,key,entry),
          Bool.pick(E.Value,String.eq(kind,"free"),E.Object{remove(E.fields(owned),key)},owned))
        +delta : E.Signed = Bool.pick(E.Signed,String.eq(kind,"allocate"),size,Bool.pick(E.Signed,String.eq(kind,"free"),E.int_sub(number(0),size),number(0)))
        +new_live : E.Signed = E.int_add(live,delta)
        +heap_live : E.Signed = E.int_add(zero_default(get(heaps,heap)),delta)
        +new_heaps : E.Value = Bool.pick(E.Value,String.eq(kind,"allocation_failed"),heaps,E.put(heaps,heap,E.int_string(heap_live)))
        +new_peak : E.Signed = maximum(peak,new_live)
        +heap_peak : E.Signed = maximum(zero_default(get(peaks,heap)),heap_live)
        _ : Unit <- require(E.eq(get(r,"live_bytes"),E.int_string(new_live)) && E.eq(get(r,"peak_bytes"),E.int_string(new_peak)) &&
          E.eq(get(r,"heap_live_bytes"),E.int_string(heap_live)) && E.eq(get(r,"heap_peak_bytes"),E.int_string(heap_peak)),"ledger totals mismatch")
        allocation_rows(rows,normal,new_live,new_peak,following,new_owned,new_heaps,E.put(peaks,heap,E.int_string(heap_peak)),actual_device)

def allocation_initial(records: List<&2,E.Value>, normal: Bool) -> Result<&2,&2,String,E.Value>:
  match records:
    case Nil{}: Fail{"missing ledger initialization"}
    case +r <> rest:
      do Result<&2,&2,String,E.Value>:
        _ : Unit <- require(eq(r,"record_type","ledger_start"),"missing ledger initialization")
        _ : Unit <- require(eq(r,"live_bytes","0") && eq(r,"peak_bytes","0"),"nonzero initial ledger")
        allocation_rows(rest,normal,number(0),number(0),number(1),E.Object{Nil{}},E.Object{Nil{}},E.Object{Nil{}},E.Null{})

def allocation_audit(records: E.Value, normal: Bool) -> Result<&2,&2,String,E.Value>:
  allocation_initial(E.array(records),normal)

def offsets() -> List<&2,U32>: [0,180,360,540,720,732,1080,1260,1440,1620]
def actions_offsets(values: List<&2,U32>, +group: U32, +ordinal: U32) -> List<&2,E.Value>:
  match values:
    case Nil{}: Nil{}
    case x <> rest: E.Object{[("frame",E.Text{U32.show((121 + 1800 * group + x : U32))}),
      ("action",E.Text{U32.show(ordinal)})]} <> actions_offsets(rest,group,(ordinal + 1 : U32))
def expected_actions(groups: Nat, +index: U32) -> List<&2,E.Value>:
  match groups:
    case 0n: Nil{}
    case 1n+p: List.append(&2,E.Value,actions_offsets(offsets(),index,(index * 10 : U32)),expected_actions(p,(index + 1 : U32)))
def actions_match(actual: List<&2,E.Value>, planned: List<&2,E.Value>) -> Bool:
  match actual planned:
    case Nil{} Nil{}: True{}
    case +a <> rest +b <> tail: E.int_eq(E.int(get(a,"frame")),E.int(get(b,"frame"))) && E.eq(get(a,"action"),get(b,"action")) && actions_match(rest,tail)
    case _ _: False{}
def frame_keys(rows: List<&2,E.Value>) -> List<&2,String>:
  match rows:
    case Nil{}: Nil{}
    case r <> rest: E.int_show(E.int(get(r,"frame"))) <> frame_keys(rest)
def has_frame(rows: List<&2,String>, +index: String) -> Bool:
  match rows:
    case Nil{}: False{}
    case k <> rest: String.eq(k,index) || has_frame(rest,index)
def action_map(rows: List<&2,E.Value>, map: E.Value) -> E.Value:
  match rows:
    case Nil{}: map
    case +r <> rest: action_map(rest,E.put(map,E.int_show(E.int(get(r,"frame"))),get(r,"action")))
def frame_validation(frames: List<&2,E.Value>, +actions: E.Value, +checkpoints: List<&2,String>, +reviews: List<&2,String>, +history: Bool, +index: U32) -> Result<&2,&2,String,Unit>:
  match frames:
    case Nil{}: Done{Unit{}}
    case +f <> rest:
      do Result<&2,&2,String,Unit>:
        _ : Unit <- required_fields(f,["frame","phase","measured_ordinal","actions","policy_flags"])
        +phase : String = text(f,"phase")
        +index_text : String = U32.show(index)
        +action : E.Value = get(actions,index_text)
        _ : Unit <- require(eq(f,"frame",U32.show(index)) && (String.eq(phase,"startup") || String.eq(phase,"warmup") || String.eq(phase,"ordinary") ||
          String.eq(phase,"edit") || String.eq(phase,"motion")) && E.eq(get(f,"measured_ordinal"),Bool.pick(E.Value,(index > 120 : U32),E.Text{U32.show((index - 121 : U32))},E.Null{})),"performance frame metadata mismatch")
        +expected : String = Bool.pick(String,U32.is_eq(index,0),"startup",Bool.pick(String,(index <= 120 : U32),"warmup",Bool.pick(String,E.truth(action),"edit","")))
        _ : Unit <- require(Bool.pick(Bool,String.eq(expected,""),String.eq(phase,"ordinary") || (history && String.eq(phase,"motion")),String.eq(phase,expected)),"performance frame population mismatch")
        _ : Unit <- require(E.eq(get(f,"actions"),E.Array{Bool.pick(List<&2,E.Value>,E.truth(action),[action],Nil{})}),"performance frame actions mismatch")
        +flags : U32 = (Bool.to_u32(has_frame(reviews,index_text)) + 2 * Bool.to_u32(has_frame(checkpoints,index_text)) + 4 * Bool.to_u32(history && U32.is_eq(index,21661)) : U32)
        +observed_flags : E.Signed <- natural_field(f,"policy_flags")
        _ : Unit <- require(E.int_eq(observed_flags,number(flags)),"performance frame flags mismatch")
        frame_validation(rest,actions,checkpoints,reviews,history,(index + 1 : U32))
def overview(rows: List<&2,E.Value>) -> Bool:
  match rows:
    case Nil{}: False{}
    case +r <> rest: (eq(r,"name","history_overview") && E.int_eq(E.int(get(r,"frame")),number(21661))) || overview(rest)
def performance_validate(+frozen: E.Value) -> Result<&2,&2,String,Unit>:
  do Result<&2,&2,String,Unit>:
    +history : Bool = eq(frozen,"schedule_id","history-perf-v2")
    +frames : List<&2,E.Value> = E.array(get(frozen,"frames"))
    +actions : List<&2,E.Value> = E.array(get(frozen,"actions"))
    +p : E.Value = get(frozen,"performance_protocol")
    _ : Unit <- require((history || eq(frozen,"schedule_id","static-perf-v2")) && eq(frozen,"warmup_frames","120") &&
      eq(frozen,"measured_frames","21600") && U32.is_eq(E.count(frames),21721),"performance frozen duration mismatch")
    _ : Unit <- required_fields(frozen,["performance_protocol","actions","required_checkpoints","review_views"])
    _ : Unit <- required_fields(p,["version","query_pairs","ordinary_duration_min_ns","ordinary_count_min"])
    _ : Unit <- require(eq(p,"version","megascene-performance/2") && eq(p,"query_pairs","21721") &&
      eq(p,"ordinary_duration_min_ns","10000000000") && eq(p,"ordinary_count_min","1000"),"performance metadata mismatch")
    _ : Unit <- require(actions_match(actions,Bool.pick(List<&2,E.Value>,history,expected_actions(12n,0),Nil{})),"performance action density mismatch")
    _ : Unit <- required_fields(p,["overview_frame","history_action_offsets","history_group_frames","history_final_suffix_frames","history_actions_per_measured_frame"])
    _ : Unit <- require(E.eq(get(p,"overview_frame"),Bool.pick(E.Value,history,E.Text{"21661"},E.Null{})) &&
      E.eq(get(p,"history_action_offsets"),Bool.pick(E.Value,history,E.Array{[E.Text{"0"},E.Text{"180"},E.Text{"360"},E.Text{"540"},E.Text{"720"},E.Text{"732"},E.Text{"1080"},E.Text{"1260"},E.Text{"1440"},E.Text{"1620"}]},E.Null{})) &&
      E.eq(get(p,"history_group_frames"),Bool.pick(E.Value,history,E.Text{"1800"},E.Null{})) &&
      E.eq(get(p,"history_final_suffix_frames"),Bool.pick(E.Value,history,E.Text{"179"},E.Null{})) &&
      E.eq(get(p,"history_actions_per_measured_frame"),Bool.pick(E.Value,history,E.Object{[("numerator",E.Text{"1"}),("denominator",E.Text{"180"})]},E.Null{})),"performance history regime mismatch")
    _ : Unit <- frame_validation(frames,action_map(actions,E.Object{Nil{}}),frame_keys(E.array(get(frozen,"required_checkpoints"))),frame_keys(E.array(get(frozen,"review_views"))),history,0)
    _ : Unit <- require(Bool.not(history) || overview(E.array(get(frozen,"required_checkpoints"))),"performance overview checkpoint missing")
    return Unit{}

def value_result(r: Result<&2,&2,String,E.Value>) -> E.Value:
  match r:
    case Done{v}: v
    case Fail{message}: E.Error{message}
def unit_result(r: Result<&2,&2,String,Unit>) -> E.Value:
  match r:
    case Done{_}: E.Null{}
    case Fail{message}: E.Error{message}
def handle(operation: String, +request: E.Value) -> E.Value:
  match operation:
    case "allocation_audit": value_result(allocation_audit(get(request,"records"),E.bool(get(request,"normal"))))
    case "performance_validate": unit_result(performance_validate(request))
    case _: E.Error{"unsupported integrity operation"}
def main() -> IO(Unit): E.main(~handle)
