import Base
import ./evidence_value.bend as E
import ./megascene_scale.bend as Scale

def cases() -> List<&2,String>:
  ["static","traversal","picking","localized","support","history"]

def schedule(+kind: String) -> String:
  match kind:
    case "traversal": "traversal-v2"
    case "picking": "picking-v2"
    case kind: kind ++ "-v1"

def requirement(+group: String, +kind: String, +preset: String, +threads: String,
    +resolution: String, +profile: String, +route: String, +diagnostic: E.Value,
    +control: E.Value, +count: String) -> E.Value:
  E.object([("group",E.string(group)),("case",E.string(kind)),("preset",E.string(preset)),
    ("threads",E.string(threads)),("resolution",E.string(resolution)),("profile",E.string(profile)),
    ("schedule",E.string(route)),("diagnostic",diagnostic),("control",control),
    ("required_complete_attempts",E.number(count))])

def primary_threads(+kind: String, +preset: String, threads: List<&2,String>) -> List<&2,E.Value>:
  match threads:
    case Nil{}: Nil{}
    case thread <> rest:
      requirement("primary",kind,preset,thread,"1920x1080","full",schedule(kind),E.Null{},E.Null{},
        Bool.pick(String,String.eq(preset,"small") && (String.eq(kind,"static") || String.eq(kind,"history")),"3","1"))
        <> primary_threads(kind,preset,rest)

def primary_cases(kinds: List<&2,String>, +preset: String, +threads: List<&2,String>) -> List<&2,E.Value>:
  match kinds:
    case Nil{}: Nil{}
    case kind <> rest:
      List.append(&2,E.Value,primary_threads(kind,preset,threads),primary_cases(rest,preset,threads))

def resolution_cases(kinds: List<&2,String>) -> List<&2,E.Value>:
  match kinds:
    case Nil{}: Nil{}
    case +kind <> rest:
      requirement("resolution",kind,"small","6","640x360","full",schedule(kind),E.Null{},E.Null{},"1")
        <> resolution_cases(rest)

def proxy_profiles(+diagnostic: String, +kind: String, profiles: List<&2,String>) -> List<&2,E.Value>:
  match profiles:
    case Nil{}: Nil{}
    case profile <> rest:
      requirement("proxy",kind,"small","6","1920x1080",profile,"proxy-" ++ diagnostic ++ "-" ++ kind ++ "-v1",
        E.string(diagnostic),E.Null{},"1") <> proxy_profiles(diagnostic,kind,rest)

def proxy_cases(+diagnostic: String, kinds: List<&2,String>) -> List<&2,E.Value>:
  match kinds:
    case Nil{}: Nil{}
    case kind <> rest:
      List.append(&2,E.Value,proxy_profiles(diagnostic,kind,["full","proxy"]),proxy_cases(diagnostic,rest))

def proxy_diagnostics(diagnostics: List<&2,String>) -> List<&2,E.Value>:
  match diagnostics:
    case Nil{}: Nil{}
    case diagnostic <> rest:
      List.append(&2,E.Value,proxy_cases(diagnostic,["traversal","picking"]),proxy_diagnostics(rest))

def Control() -> Data:
  Sigma<&2,&2,String,_ => E.Field()>

def controls() -> List<&2,Control()>:
  [("static","spread-static-v1",E.string("spread")),
   ("support","fill-support-v1",E.string("fill")),
   ("history","fill-history-v1",E.string("fill")),
   ("history","body-rich-history-v1",E.string("body-rich")),
   ("static","material-detail-static-v1",E.string("material-detail")),
   ("localized","material-detail-localized-v1",E.string("material-detail")),
   ("static","surface-detail-static-v1",E.string("surface-detail")),
   ("history","history-12-v1",E.Null{}),("history","history-48-v1",E.Null{}),
   ("support","support-1-span-v1",E.Null{}),("support","support-2-span-v1",E.Null{})]

def control_rows(rows: List<&2,Control()>) -> List<&2,E.Value>:
  match rows:
    case Nil{}: Nil{}
    case (kind,route,control) <> rest:
      requirement("control",kind,"small","6","1920x1080","full",route,E.Null{},control,"1") <> control_rows(rest)

def requirements() -> E.Value:
  E.Array{List.concat(&2,E.Value,[primary_cases(cases(),"small",["1","6","12"]),
    primary_cases(cases(),"large",["6"]),resolution_cases(["static","history"]),
    proxy_diagnostics(["mixed-world","compact-reference"]),control_rows(controls())])}

def all_pass(+outcomes: E.Value, names: List<&2,String>) -> Bool:
  match names:
    case Nil{}: True{}
    case name <> rest:
      String.eq(E.text(E.get(outcomes,name)),"pass") && all_pass(outcomes,rest)

def text_is(value: E.Value, expected: String) -> Bool:
  E.eq(value,E.string(expected))

def field_problem(+row: E.Value, +name: String) -> E.Value:
  Bool.pick(E.Value,E.has(row,name),E.Null{},E.Error{"missing field:" ++ name})

def first_problem(+left: E.Value, right: E.Value) -> E.Value:
  Bool.pick(E.Value,E.is_null(left),right,left)

def outcome_problem(+outcomes: E.Value, names: List<&2,String>) -> E.Value:
  match names:
    case Nil{}: E.Null{}
    case +name <> rest:
      first_problem(field_problem(outcomes,name),Bool.pick(E.Value,text_is(E.get(outcomes,name),"pass"),
        outcome_problem(outcomes,rest),E.Null{}))

def complete_problem(+row: E.Value) -> E.Value:
  +config = E.get(row,"configuration")
  +outcomes = E.get(row,"outcomes")
  +runtime = E.get(row,"runtime_artifacts")
  +raw = E.get(row,"raw_evidence")
  +prefix = E.object([("startup",E.boolean(True{})),("warmup",E.string("120")),("measured",E.string("3600"))])
  +names = {["schedule_completion","state_correctness","rendering_correctness"] : List<&2,String>}
  first_problem(field_problem(row,"configuration"),first_problem(field_problem(row,"outcomes"),
    Bool.pick(E.Value,text_is(E.get(config,"warmup"),"120") && text_is(E.get(config,"frames"),"3600") &&
      Bool.not(E.truth(E.get(config,"validation_only"))),
      first_problem(field_problem(row,"completed_prefix"),Bool.pick(E.Value,E.eq(E.get(row,"completed_prefix"),prefix),
        first_problem(outcome_problem(outcomes,names),Bool.pick(E.Value,all_pass(outcomes,names),
          first_problem(field_problem(row,"validation_status"),Bool.pick(E.Value,text_is(E.get(row,"validation_status"),"pass"),
            first_problem(field_problem(row,"runtime_artifacts"),first_problem(field_problem(runtime,"present_entries"),
              first_problem(field_problem(runtime,"manifest_entries"),Bool.pick(E.Value,
                E.eq(E.get(runtime,"present_entries"),E.get(runtime,"manifest_entries")),
                first_problem(field_problem(row,"raw_evidence"),first_problem(field_problem(raw,"present_entries"),
                  field_problem(raw,"manifest_entries"))),E.Null{})))),E.Null{})),E.Null{})),E.Null{})),E.Null{})))

def complete(+row: E.Value) -> Bool:
  +config = E.get(row,"configuration")
  +runtime = E.get(row,"runtime_artifacts")
  +evidence = E.get(row,"raw_evidence")
  text_is(E.get(config,"warmup"),"120") && text_is(E.get(config,"frames"),"3600") &&
    Bool.not(E.truth(E.get(config,"validation_only"))) &&
    E.eq(E.get(row,"completed_prefix"),E.object([("startup",E.boolean(True{})),
      ("warmup",E.string("120")),("measured",E.string("3600"))])) &&
    all_pass(E.get(row,"outcomes"),["schedule_completion","state_correctness","rendering_correctness"]) &&
    String.eq(E.text(E.get(row,"validation_status")),"pass") &&
    E.has(runtime,"present_entries") && E.has(runtime,"manifest_entries") &&
    E.eq(E.get(runtime,"present_entries"),E.get(runtime,"manifest_entries")) &&
    E.has(evidence,"present_entries") && E.has(evidence,"manifest_entries") &&
    E.eq(E.get(evidence,"present_entries"),E.get(evidence,"manifest_entries"))

def matching_keys(+config: E.Value, +needed: E.Value, keys: List<&2,String>) -> Bool:
  match keys:
    case Nil{}: True{}
    case +key <> rest:
      E.eq(E.get(config,key),E.get(needed,key)) && matching_keys(config,needed,rest)

def matches(+row: E.Value, +needed: E.Value) -> Bool:
  +config = E.get(row,"configuration")
  text_is(E.get(config,"seed"),"45") &&
    matching_keys(config,needed,["case","preset","threads","resolution","profile","schedule","diagnostic","control"]) &&
    Bool.not(String.eq(E.text(E.get(row,"attempt_kind")),"calibration_off"))

def select(~C: Data, ~predicate: C -> E.Value -> Bool, +context: C, rows: List<&2,E.Value>) -> List<&2,E.Value>:
  match rows:
    case Nil{}: Nil{}
    case +row <> rest:
      List.filter.put(E.Value,row,select(~C,~predicate,context,rest),predicate(context,row))

def ids(rows: List<&2,E.Value>) -> E.Value:
  match rows:
    case Nil{}: E.Array{Nil{}}
    case row <> rest:
      E.Array{E.get(row,"attempt_id") <> E.array(ids(rest))}

def matching_problem(rows: List<&2,E.Value>, +needed: E.Value) -> E.Value:
  match rows:
    case Nil{}: E.Null{}
    case +row <> rest:
      +config = E.get(row,"configuration")
      first_problem(field_problem(row,"configuration"),first_problem(Bool.pick(E.Value,
        text_is(E.get(config,"seed"),"45") && matching_keys(config,needed,
          ["case","preset","threads","resolution","profile","schedule","diagnostic","control"]),
        field_problem(row,"attempt_kind"),E.Null{}),matching_problem(rest,needed)))

def completed_problem(rows: List<&2,E.Value>) -> E.Value:
  match rows:
    case Nil{}: E.Null{}
    case +row <> rest: first_problem(complete_problem(row),completed_problem(rest))

def fields_problem(+row: E.Value, names: List<&2,String>) -> E.Value:
  match names:
    case Nil{}: E.Null{}
    case name <> rest: first_problem(field_problem(row,name),fields_problem(row,rest))

def coverage_output_problem(rows: List<&2,E.Value>, +completed: Bool) -> E.Value:
  match rows:
    case Nil{}: E.Null{}
    case +row <> rest:
      first_problem(field_problem(row,"attempt_id"),first_problem(Bool.pick(E.Value,completed,
        first_problem(field_problem(row,"repeat_identity_sha256"),fields_problem(E.get(row,"outcomes"),
          ["visual_quality","numeric_validity"])),E.Null{}),coverage_output_problem(rest,completed)))

def groups(rows: List<&2,E.Value>, +result: E.Value) -> E.Value:
  match rows:
    case Nil{}: result
    case +row <> rest:
      +key = E.text(E.get(row,"repeat_identity_sha256"))
      +previous = E.array(E.get(result,key))
      groups(rest,E.put(result,key,E.Array{List.append(&2,E.Value,previous,[E.get(row,"attempt_id")])}))

def largest_group(rows: List<&2,E.Field()>) -> U32:
  match rows:
    case Nil{}: 0
    case (_,value) <> rest: U32.max(E.count(E.array(value)),largest_group(rest))

def coverage_row(+needed: E.Value, +attempts: List<&2,E.Value>) -> E.Value:
  +matching = select(~E.Value,~(needed => row => matches(row,needed)),needed,attempts)
  +completed = select(~Unit,~(u => row => complete(row)),Unit{},matching)
  +repeats = groups(completed,E.object(Nil{}))
  +count = E.int(E.get(needed,"required_complete_attempts"))
  +covered = E.int_le(count,E.int(E.number(U32.show(largest_group(E.fields(repeats))))))
  +problem = first_problem(matching_problem(attempts,needed),first_problem(completed_problem(matching),
    first_problem(coverage_output_problem(completed,True{}),coverage_output_problem(matching,False{}))))
  Bool.pick(E.Value,E.is_null(problem),E.merge(needed,E.object([("candidate_attempts",ids(matching)),("complete_runtime_attempts",ids(completed)),
    ("visual_quality_pass_attempts",ids(select(~String,~(+name => row =>
      String.eq(E.text(E.get(E.get(row,"outcomes"),name)),"pass")),"visual_quality",completed))),
    ("numeric_validity_pass_attempts",ids(select(~String,~(+name => row =>
      String.eq(E.text(E.get(E.get(row,"outcomes"),name)),"pass")),"numeric_validity",completed))),
    ("repeat_groups",repeats),("runtime_coverage",E.string(Bool.pick(String,covered,"observed","missing"))),
    ("acceptance",E.string("unassessed"))])),problem)

def coverage_rows(requirements: List<&2,E.Value>, +attempts: List<&2,E.Value>) -> List<&2,E.Value>:
  match requirements:
    case Nil{}: Nil{}
    case needed <> rest: coverage_row(needed,attempts) <> coverage_rows(rest,attempts)

def map(~C: Data, ~function: C -> E.Value -> E.Value, +context: C, rows: List<&2,E.Value>) -> List<&2,E.Value>:
  match rows:
    case Nil{}: Nil{}
    case +row <> rest: function(context,row) <> map(~C,~function,context,rest)

def contains(rows: List<&2,E.Value>, +value: E.Value) -> Bool:
  match rows:
    case Nil{}: False{}
    case row <> rest: E.eq(row,value) || contains(rest,value)

def greatest_group(fields: List<&2,E.Field()>, +best: E.Value) -> E.Value:
  match fields:
    case Nil{}: best
    case (_,+value) <> rest:
      greatest_group(rest,Bool.pick(E.Value,(E.count(E.array(value)) > E.count(E.array(best)) : U32),value,best))

def last_result(result: Maybe<&2,E.Value>) -> E.Value:
  match result:
    case None{}: E.Null{}
    case Some{value}: value

def source_for(+payload: E.Value) -> E.Value:
  +row = E.get(payload,"row")
  +rows = E.array(E.get(payload,"rows"))
  +by_id = E.get(payload,"by_id")
  +groups = E.get(row,"repeat_groups")
  +peer = E.at(select(~E.Value,~(+row => +item =>
    String.eq(E.text(E.get(item,"group")),"primary") && E.eq(E.get(item,"case"),E.get(row,"case")) &&
    String.eq(E.text(E.get(item,"preset")),"small") && text_is(E.get(item,"threads"),"6") &&
    E.truth(E.get(item,"complete_runtime_attempts"))),row,rows),0)
  +candidates = map(~E.Value,~(by_id => id => E.get(by_id,E.text(id))),by_id,E.array(E.get(peer,"complete_runtime_attempts")))
  +preferred = select(~E.Value,~(ids => item => contains(E.array(ids),E.get(item,"attempt_id"))),
    E.get(payload,"preferred_ids"),candidates)
  +cross_thread = String.eq(E.text(E.get(row,"group")),"primary") && String.eq(E.text(E.get(row,"preset")),"small") &&
    (text_is(E.get(row,"threads"),"1") || text_is(E.get(row,"threads"),"12"))
  Bool.pick(E.Value,E.truth(groups),E.get(by_id,E.text(E.at(E.array(greatest_group(E.fields(groups),E.Null{})),0))),
    Bool.pick(E.Value,cross_thread && Bool.not(E.is_null(peer)),last_result(List.last(&2,E.Value,
      Bool.pick(List<&2,E.Value>,List.is_empty(&2,E.Value,preferred),candidates,preferred))),E.Null{}))

def source_problem(+payload: E.Value) -> E.Value:
  +row = E.get(payload,"row")
  +groups = E.get(row,"repeat_groups")
  +chosen = E.at(E.array(greatest_group(E.fields(groups),E.Null{})),0)
  first_problem(field_problem(row,"repeat_groups"),Bool.pick(E.Value,E.truth(groups),
    field_problem(E.get(payload,"by_id"),E.text(chosen)),first_problem(field_problem(row,"group"),
      Bool.pick(E.Value,text_is(E.get(row,"group"),"primary"),first_problem(field_problem(row,"preset"),
        Bool.pick(E.Value,text_is(E.get(row,"preset"),"small"),field_problem(row,"threads"),E.Null{})),E.Null{}))))

def feature_names(features: List<&2,E.Value>) -> List<&2,E.Value>:
  match features:
    case Nil{}: Nil{}
    case feature <> rest: E.get(feature,"name") <> feature_names(rest)

def features_problem(features: List<&2,E.Value>) -> E.Value:
  match features:
    case Nil{}: E.Null{}
    case feature <> rest: first_problem(field_problem(feature,"name"),features_problem(rest))

def views_problem(views: List<&2,E.Value>) -> E.Value:
  match views:
    case Nil{}: E.Null{}
    case +view <> rest:
      first_problem(field_problem(view,"name"),first_problem(field_problem(view,"frame"),
        first_problem(field_problem(view,"capture"),first_problem(field_problem(E.get(view,"capture"),"sha256"),
          first_problem(field_problem(view,"features"),first_problem(features_problem(E.array(E.get(view,"features"))),
            views_problem(rest)))))))

def view_signatures(views: List<&2,E.Value>) -> List<&2,E.Value>:
  match views:
    case Nil{}: Nil{}
    case +view <> rest:
      E.Array{[E.get(view,"name"),E.get(view,"frame"),E.get(E.get(view,"capture"),"sha256"),
        E.Array{feature_names(E.array(E.get(view,"features")))}]} <> view_signatures(rest)

def scope_values(+config: E.Value, keys: List<&2,String>) -> List<&2,E.Value>:
  match keys:
    case Nil{}: Nil{}
    case key <> rest: E.get(config,key) <> scope_values(config,rest)

def review_signature(+attempt: E.Value, +review: E.Value) -> E.Value:
  +views = E.get(review,"views")
  Bool.pick(E.Value,E.truth(views),E.Array{[
    E.Array{scope_values(E.get(attempt,"configuration"),["case","preset","seed","resolution","profile","schedule","diagnostic","control"])},
    E.get(review,"schedule_sha256"),E.Array{view_signatures(E.array(views))}]},E.Null{})

def review_signature_problem(+attempt: E.Value, +review: E.Value) -> E.Value:
  first_problem(field_problem(attempt,"configuration"),Bool.pick(E.Value,E.truth(E.get(review,"views")),
    first_problem(views_problem(E.array(E.get(review,"views"))),field_problem(review,"schedule_sha256")),E.Null{}))

def reuse_problem(rows: List<&2,E.Value>) -> E.Value:
  match rows:
    case Nil{}: E.Null{}
    case +row <> rest:
      +attempt = E.get(row,"attempt")
      first_problem(complete_problem(attempt),first_problem(Bool.pick(E.Value,complete(attempt),
        review_signature_problem(attempt,E.get(row,"review")),E.Null{}),reuse_problem(rest)))

def reuse_sources(rows: List<&2,E.Value>, +result: List<&2,E.Value>) -> List<&2,E.Value>:
  match rows:
    case Nil{}: result
    case +row <> rest:
      +attempt = E.get(row,"attempt")
      +review = E.get(row,"review")
      +signature = review_signature(attempt,review)
      +existing = select(~E.Value,~(signature => item => E.eq(E.get(item,"signature"),signature)),signature,result)
      +keep = complete(attempt) && Bool.not(E.is_null(signature)) &&
        String.eq(E.text(E.get(review,"status")),"pass") && E.truth(E.get(row,"assessments_present")) &&
        List.is_empty(&2,E.Value,existing)
      reuse_sources(rest,Bool.pick(List<&2,E.Value>,keep,List.append(&2,E.Value,result,
        [E.object([("attempt",attempt),("signature",signature)])]),result))

def reuse_targets(rows: List<&2,E.Value>, +sources: List<&2,E.Value>) -> List<&2,E.Value>:
  match rows:
    case Nil{}: Nil{}
    case +row <> rest:
      +attempt = E.get(row,"attempt")
      +review = E.get(row,"review")
      +signature = review_signature(attempt,review)
      +source = E.get(E.at(select(~E.Value,~(signature => item => E.eq(E.get(item,"signature"),signature)),signature,sources),0),"attempt")
      +keep = complete(attempt) && Bool.not(E.is_null(signature) || E.is_null(source)) &&
        String.eq(E.text(E.get(review,"status")),"awaiting_named_feature_review") &&
        Bool.not(E.eq(E.get(source,"attempt_id"),E.get(attempt,"attempt_id")))
      List.filter.put(E.Value,E.object([("source_attempt",E.get(source,"attempt_id")),
        ("source_archive",E.get(source,"archive")),("target_attempt",E.get(attempt,"attempt_id")),
        ("target_archive",E.get(attempt,"archive")),("capture_count",E.number(U32.show(E.count(E.array(E.at(E.array(signature),2))))))]),
        reuse_targets(rest,sources),keep)

def nonnegative(+value: E.Signed) -> E.Signed:
  Bool.pick(E.Signed,E.int_negative(value),E.int_zero(),value)

def minimum(+left: E.Signed, +right: E.Signed) -> E.Signed:
  Bool.pick(E.Signed,E.int_le(left,right),left,right)

def clock_elapsed(+campaign: E.Value, +payload: E.Value) -> E.Signed:
  E.int_sub(Bool.pick(E.Signed,E.eq(E.get(payload,"boot_id"),E.get(campaign,"boot_id")),
    E.int(E.get(payload,"monotonic_ns")),E.int(E.get(payload,"utc_ns"))),
    Bool.pick(E.Signed,E.eq(E.get(payload,"boot_id"),E.get(campaign,"boot_id")),
      E.int(E.get(campaign,"lease_ns")),E.int(E.get(campaign,"lease_utc_ns"))))

def runner_remaining(+payload: E.Value) -> E.Value:
  +campaign = E.get(payload,"campaign")
  elapsed = Bool.pick(E.Signed,(String.eq(E.text(E.get(campaign,"state")),"active") || E.truth(E.get(payload,"lease_always"))),
    nonnegative(clock_elapsed(campaign,payload)),E.int_zero())
  E.int_value(nonnegative(E.int_sub(E.int(E.get(campaign,"allowance_ns")),
    E.int_add(E.int(E.get(campaign,"elapsed_ns")),elapsed))))

def runner_remaining_problem(+payload: E.Value) -> E.Value:
  +campaign = E.get(payload,"campaign")
  first_problem(field_problem(campaign,"state"),first_problem(Bool.pick(E.Value,
    (text_is(E.get(campaign,"state"),"active") || E.truth(E.get(payload,"lease_always"))),first_problem(field_problem(campaign,"boot_id"),
      Bool.pick(E.Value,E.eq(E.get(payload,"boot_id"),E.get(campaign,"boot_id")),
        field_problem(campaign,"lease_ns"),field_problem(campaign,"lease_utc_ns"))),E.Null{}),
    fields_problem(campaign,["elapsed_ns","allowance_ns"])))

def remaining(+ledger: E.Value, +supervised: E.Value) -> E.Value:
  +gross = nonnegative(E.int_sub(E.int_sub(E.int(E.get(ledger,"allowance_ns")),
    E.int(E.get(ledger,"prior_gross_charge_ns"))),E.int(E.get(ledger,"new_work_charge_ns"))))
  E.merge(ledger,Bool.pick(E.Value,E.is_null(supervised),E.object([("remaining_ns",E.int_string(gross))]),
    E.object([("runner_campaign_remaining_ns",E.int_string(E.int(supervised))),
      ("remaining_ns",E.int_string(minimum(gross,E.int(supervised))))])))

def allowance_gate(+payload: E.Value) -> E.Value:
  +ledger = E.get(payload,"ledger")
  +supervised = E.get(payload,"supervised")
  +available = Bool.pick(E.Signed,E.is_null(supervised),E.int(E.get(ledger,"remaining_ns")),
    minimum(E.int(E.get(ledger,"remaining_ns")),E.int(supervised)))
  +seconds = E.int(E.get(payload,"timeout"))
  +nanoseconds = E.int_mul(seconds,E.int_text("1000000000"))
  Bool.pick(E.Value,E.int_le(available,E.int_zero()),E.Error{"consolidated acceptance allowance exhausted"},
    Bool.pick(E.Value,E.int_le(nanoseconds,available),E.int_value(seconds),
      E.ratio(available,Scale.Integer.from_u32(32n,1000000000))))

def charge(+payload: E.Value) -> E.Value:
  +ledger = E.get(payload,"ledger")
  +entry = E.get(payload,"entry")
  updated = E.merge(ledger,E.object([("new_work",E.Array{List.append(&2,E.Value,E.array(E.get(ledger,"new_work")),[entry])}),
    ("new_work_charge_ns",E.int_string(E.int_add(E.int(E.get(ledger,"new_work_charge_ns")),E.int(E.get(entry,"elapsed_ns")))))]))
  remaining(updated,E.get(payload,"supervised"))

def sum_elapsed(rows: List<&2,E.Value>, acc: E.Signed) -> E.Signed:
  match rows:
    case Nil{}: acc
    case row <> rest: sum_elapsed(rest,E.int_add(acc,E.int(E.get(row,"elapsed_ns"))))

def text_order(a: E.Value, b: E.Value) -> Bool:
  String.is_le(E.text(a),E.text(b))

def unique(rows: List<&2,E.Value>, +result: List<&2,E.Value>) -> List<&2,E.Value>:
  match rows:
    case Nil{}: result
    case +row <> rest:
      unique(rest,Bool.pick(List<&2,E.Value>,contains(result,row),result,List.append(&2,E.Value,result,[row])))

def reconcile(+payload: E.Value) -> E.Value:
  +ledger = E.get(payload,"ledger")
  +campaigns = E.array(E.get(payload,"campaigns"))
  +previous = unique(map(~Unit,~(u => row => E.get(row,"campaign")),Unit{},E.array(E.get(ledger,"prior_campaigns"))),Nil{})
  +found = unique(map(~Unit,~(u => row => E.get(row,"campaign")),Unit{},campaigns),Nil{})
  +missing = List.sort(~E.Value,~text_order,select(~E.Value,~(found => row => Bool.not(contains(E.array(found),row))),E.Array{found},previous))
  +added = List.sort(~E.Value,~text_order,select(~E.Value,~(previous => row => Bool.not(contains(E.array(previous),row))),E.Array{previous},found))
  updated = E.merge(ledger,E.object([("prior_campaigns",E.Array{campaigns}),
    ("prior_gross_charge_ns",E.int_string(sum_elapsed(campaigns,E.int_zero()))),
    ("charging_policy",E.string("Conservative gross charge of every retained earlier Megascene campaign root, including development and failed attempts; new work charged once through new_work"))]))
  E.object([("missing",E.Array{missing}),("newly_charged",E.Array{added}),
    ("ledger",remaining(updated,E.get(payload,"supervised")))])

def overhead_rows(rows: List<&2,E.Value>, +payload: E.Value, +ledger: E.Value, +credited: E.Value,
    +changes: List<&2,E.Value>) -> E.Value:
  match rows:
    case Nil{}:
      updated = E.merge(ledger,E.object([("runner_overhead_credited_ns",credited),
        ("new_work",E.Array{List.append(&2,E.Value,E.array(E.get(ledger,"new_work")),changes)}),
        ("new_work_charge_ns",E.int_string(E.int_add(E.int(E.get(ledger,"new_work_charge_ns")),sum_elapsed(changes,E.int_zero()))))]))
      E.object([("charged",E.Array{changes}),("ledger",remaining(updated,E.get(payload,"supervised")))])
    case +row <> rest:
      +campaign = E.get(row,"campaign")
      +path = E.get(row,"path")
      +active = String.eq(E.text(E.get(campaign,"state")),"active")
      +current = E.eq(path,E.get(E.get(ledger,"runner_campaign"),"path"))
      +bridge = Bool.pick(E.Signed,Bool.not(current) && active && Bool.not(E.is_null(E.get(row,"next_start_ns"))),
        nonnegative(E.int_sub(E.int(E.get(row,"next_start_ns")),E.int(E.get(campaign,"lease_utc_ns")))),E.int_zero())
      +gross = Bool.pick(E.Signed,current && active,minimum(E.int(E.get(campaign,"allowance_ns")),
        E.int_add(E.int(E.get(campaign,"elapsed_ns")),nonnegative(clock_elapsed(campaign,payload)))),
        E.int_add(E.int(E.get(campaign,"elapsed_ns")),bridge))
      +wrapped = sum_elapsed(select(~E.Value,~(+row => +run => E.eq(E.get(run,"runner_campaign"),E.get(row,"path")) ||
        contains(E.array(E.get(run,"command")),E.get(row,"root"))),row,E.array(E.get(ledger,"new_work"))),E.int_zero())
      +overhead = nonnegative(E.int_sub(gross,wrapped))
      +previous = E.int(E.get(credited,E.text(path)))
      +increased = E.int_gt(overhead,previous)
      overhead_rows(rest,payload,ledger,Bool.pick(E.Value,increased,E.put(credited,E.text(path),E.int_string(overhead)),credited),
        Bool.pick(List<&2,E.Value>,increased,List.append(&2,E.Value,changes,[E.object([
          ("name",E.string("supervisor-gross-overhead")),("campaign",path),
          ("elapsed_ns",E.int_string(E.int_sub(overhead,previous))),("gross_ns",E.int_string(gross)),
          ("wrapped_ns",E.int_string(wrapped)),("bridge_to_next_runner_ns",E.int_string(bridge)),
          ("status",E.string("charged"))])]),changes))

def overhead(+payload: E.Value) -> E.Value:
  +ledger = E.get(payload,"ledger")
  +credited = E.get(ledger,"runner_overhead_credited_ns")
  overhead_rows(E.array(E.get(payload,"campaigns")),payload,ledger,
    Bool.pick(E.Value,E.is_null(credited),E.object(Nil{}),credited),Nil{})

def primary_pending(rows: List<&2,E.Value>) -> List<&2,E.Value>:
  match rows:
    case Nil{}: Nil{}
    case +row <> rest:
      +primary = text_is(E.get(row,"group"),"primary") || text_is(E.get(row,"group"),"resolution")
      +problem = first_problem(field_problem(row,"group"),Bool.pick(E.Value,primary,
        field_problem(row,"runtime_coverage"),E.Null{}))
      List.filter.put(E.Value,Bool.pick(E.Value,E.is_null(problem),row,problem),primary_pending(rest),
        Bool.not(E.is_null(problem)) || (primary && text_is(E.get(row,"runtime_coverage"),"missing")))

def handle(operation: String, +payload: E.Value) -> E.Value:
  match operation:
    case "requirements": requirements()
    case "complete":
      +problem = complete_problem(payload)
      Bool.pick(E.Value,E.is_null(problem),E.boolean(complete(payload)),problem)
    case "coverage": E.Array{coverage_rows(E.array(requirements()),E.array(payload))}
    case "source_for":
      +problem = source_problem(payload)
      Bool.pick(E.Value,E.is_null(problem),source_for(payload),problem)
    case "review_signature":
      +problem = review_signature_problem(E.get(payload,"attempt"),E.get(payload,"review"))
      Bool.pick(E.Value,E.is_null(problem),review_signature(E.get(payload,"attempt"),E.get(payload,"review")),problem)
    case "review_reuse":
      +problem = reuse_problem(E.array(payload))
      Bool.pick(E.Value,E.is_null(problem),E.Array{reuse_targets(E.array(payload),reuse_sources(E.array(payload),Nil{}))},problem)
    case "runner_remaining":
      +problem = runner_remaining_problem(payload)
      Bool.pick(E.Value,E.is_null(problem),runner_remaining(payload),problem)
    case "remaining": remaining(E.get(payload,"ledger"),E.get(payload,"supervised"))
    case "allowance_gate":
      +problem = field_problem(E.get(payload,"ledger"),"remaining_ns")
      Bool.pick(E.Value,E.is_null(problem),allowance_gate(payload),problem)
    case "charge": charge(payload)
    case "reconcile": reconcile(payload)
    case "overhead": overhead(payload)
    case "primary_pending": E.Array{primary_pending(E.array(payload))}
    case _: E.Error{"unknown acceptance evidence operation"}

def main() -> IO(Unit):
  E.main(~handle)
