import Base
import ./evidence_value.bend as E
import ./schedule_json.bend as J

def field_is(+value: E.Value, key: String, expected: String) -> Bool:
  E.eq(E.get(value,key),E.string(expected))
def status(value: E.Value, name: String) -> Bool: field_is(E.get(value,name),"status","pass")
def contains(xs: List<&2,E.Value>, +value: E.Value) -> Bool:
  match xs:
    case Nil{}: False{}
    case h <> t: E.eq(h,value) || contains(t,value)
def has_text(+value: E.Value, key: String, expected: String) -> Bool:
  contains(E.array(E.get(value,key)),E.string(expected))
def one_of(+value: String, choices: List<&2,String>) -> Bool:
  match choices:
    case Nil{}: False{}
    case h <> t: String.eq(value,h) || one_of(value,t)
def matching(keys: List<&2,String>, +a: E.Value, +b: E.Value, +reason: String) -> Result<&2,&2,String,Unit>:
  match keys:
    case Nil{}: Done{Unit{}}
    case +key <> rest:
      do Result<&2,&2,String,Unit>:
        before : E.Value <- E.required(a,key)
        after : E.Value <- E.required(b,key)
        _ : Unit <- E.require(E.eq(before,after),reason ++ key)
        matching(rest,a,b,reason)
def required(keys: List<&2,String>, +value: E.Value) -> Result<&2,&2,String,Unit>:
  match keys:
    case Nil{}: Done{Unit{}}
    case +key <> rest:
      do Result<&2,&2,String,Unit>:
        _ : E.Value <- E.required(value,key)
        required(rest,value)
def numeric_delta(keys: List<&2,String>, +a: E.Value, +b: E.Value) -> Result<&2,&2,String,E.Value>:
  match keys:
    case Nil{}: Done{E.object(Nil{})}
    case +key <> rest:
      do Result<&2,&2,String,E.Value>:
        variant : E.Value <- E.required(b,key)
        after : E.Signed <- E.natural(variant)
        baseline : E.Value <- E.required(a,key)
        before : E.Signed <- E.natural(baseline)
        rest : E.Value <- numeric_delta(rest,a,b)
        return E.object((key,E.int_string(E.int_sub(after,before))) <> E.fields(rest))
def shared(+a: E.Value, +b: E.Value, +key: String) -> E.Value:
  E.object([("baseline",E.get(a,key)),("variant",E.get(b,key))])
def positive(value: E.Value) -> Bool: E.int_gt(E.int(value),E.int_zero())
def negative(value: E.Value) -> Bool: E.int_lt(E.int(value),E.int_zero())
def distinct(+a: E.Value, +b: E.Value) -> Result<&2,&2,String,Unit>:
  do Result<&2,&2,String,Unit>:
    first : E.Value <- E.required(a,"attempt_id")
    second : E.Value <- E.required(b,"attempt_id")
    E.require(Bool.not(E.eq(first,second)),"reused attempt identity")
def binding(+manifest: E.Value) -> Result<&2,&2,String,Unit>:
  do Result<&2,&2,String,Unit>:
    environment : E.Value <- E.required(manifest,"worker_environment")
    _ : E.Value <- E.required(environment,"MEGASCENE_SCHEDULE_SHA256")
    return Unit{}
def status_fields(+value: E.Value, names: List<&2,String>) -> Result<&2,&2,String,Unit>:
  match names:
    case Nil{}: Done{Unit{}}
    case name <> rest:
      do Result<&2,&2,String,Unit>:
        item : E.Value <- E.required(value,name)
        _ : E.Value <- E.required(item,"status")
        status_fields(value,rest)

def controls_load(+payload: E.Value) -> Result<&2,&2,String,E.Value>:
  +manifest = E.get(payload,"manifest")
  +summary = E.get(payload,"summary")
  +validation = E.get(payload,"validation")
  +inventory = E.get(payload,"inventory")
  do Result<&2,&2,String,E.Value>:
    _ : Unit <- required(["attempt_id","effective"],manifest)
    _ : Unit <- required(["attempt_kind","synthetic","attempt_id","state_correctness","schedule_completion","rendering_correctness"],summary)
    _ : Unit <- required(["status","synthetic","identity"],validation)
    _ : Unit <- status_fields(summary,["state_correctness","schedule_completion","rendering_correctness"])
    _ : Unit <- E.require(field_is(summary,"attempt_kind","development_observation") &&
      Bool.not(E.truth(E.get(summary,"synthetic"))) && E.eq(E.get(summary,"attempt_id"),E.get(manifest,"attempt_id")) &&
      status(summary,"state_correctness") && status(summary,"schedule_completion") && status(summary,"rendering_correctness"),
      "complete nonsynthetic timed Vulkan attempt required")
    _ : Unit <- E.require(field_is(validation,"status","pass") && Bool.not(E.truth(E.get(validation,"synthetic"))),
      "complete nonsynthetic validation required")
    _ : Unit <- E.require(E.eq(E.get(validation,"identity"),E.get(payload,"expected_identity")),"validation/runtime identity mismatch")
    _ : Unit <- required(["validation"],inventory)
    _ : Unit <- E.require(field_is(inventory,"validation","validation.json"),"inventory validation link missing")
    return E.Boolean{True{}}

def control_case(control: String, +case_name: String) -> Result<&2,&2,String,Unit>:
  match control:
    case "material-detail": E.require(one_of(case_name,["static","localized"]),"unsupported material control case")
    case "fill": E.require(one_of(case_name,["support","history"]),"unsupported fill control case")
    case "body-rich": E.require(String.eq(case_name,"history"),"unsupported body-rich control case")
    case _: E.require(String.eq(case_name,"static"),"unsupported control case")
def control_invariants(control: String, +a: E.Value, +b: E.Value, +delta: E.Value, +case_name: String) -> Result<&2,&2,String,Unit>:
  match control:
    case "spread": E.require(field_is(delta,"cells","46080") && field_is(delta,"protected_cells","1920") &&
      E.eq(E.get(E.get(b,"generation_envelope_cells"),"lo"),E.Array{[E.string("-480"),E.string("0"),E.string("-480")]}) &&
      positive(E.get(delta,"cuboids")) && positive(E.get(delta,"surface_rectangles")),"spread work mismatch")
    case "material-detail": E.require(field_is(delta,"cells","0") && field_is(delta,"protected_cells","0") &&
      E.eq(E.get(a,"generation_envelope_cells"),E.get(b,"generation_envelope_cells")) &&
      E.eq(E.get(a,"occupied_bounds_cells"),E.get(b,"occupied_bounds_cells")) &&
      Bool.not(E.eq(E.get(a,"cells_by_material"),E.get(b,"cells_by_material"))) &&
      Bool.not(E.eq(E.get(a,"exposed_area_by_material_cell_faces"),E.get(b,"exposed_area_by_material_cell_faces"))) &&
      positive(E.get(delta,"cuboids")) && positive(E.get(delta,"surface_rectangles")),"material control invariants mismatch")
    case "surface-detail": E.require(field_is(delta,"cells","-2048") && field_is(delta,"protected_cells","0") &&
      E.eq(E.get(a,"generation_envelope_cells"),E.get(b,"generation_envelope_cells")) &&
      E.eq(E.get(a,"occupied_bounds_cells"),E.get(b,"occupied_bounds_cells")) &&
      positive(E.get(delta,"exposed_area_cell_faces")) && positive(E.get(delta,"cuboids")) &&
      positive(E.get(delta,"surface_rectangles")),"surface control invariants mismatch")
    case "fill": E.require(one_of(case_name,["support","history"]) && field_is(delta,"cells","3276800") &&
      field_is(delta,"protected_cells","0") && E.eq(E.get(a,"generation_envelope_cells"),E.get(b,"generation_envelope_cells")) &&
      E.eq(E.get(E.get(a,"occupied_bounds_cells"),"lo"),E.get(E.get(b,"occupied_bounds_cells"),"lo")) &&
      Bool.not(E.eq(E.at(E.array(E.get(E.get(a,"occupied_bounds_cells"),"hi")),1),E.at(E.array(E.get(E.get(b,"occupied_bounds_cells"),"hi")),1))) &&
      Bool.not(E.eq(E.get(E.get(a,"cells_by_material"),"2"),E.get(E.get(b,"cells_by_material"),"2"))),"fill control invariants mismatch")
    case _: E.require(String.eq(case_name,"history") && field_is(delta,"cells","-76032") && field_is(delta,"protected_cells","0") &&
      E.eq(E.get(a,"generation_envelope_cells"),E.get(b,"generation_envelope_cells")) &&
      E.eq(E.get(a,"occupied_bounds_cells"),E.get(b,"occupied_bounds_cells")) &&
      negative(E.get(delta,"exposed_area_cell_faces")) && negative(E.get(delta,"surface_rectangles")),"body-rich control invariants mismatch")

def controls(+payload: E.Value) -> Result<&2,&2,String,E.Value>:
  +left = E.array(E.get(payload,"baseline"))
  +right = E.array(E.get(payload,"variant"))
  +bm = E.at(left,0)
  +bv = E.at(left,1)
  +base = E.at(left,2)
  +vm = E.at(right,0)
  +vv = E.at(right,1)
  +variant = E.at(right,2)
  +a = E.get(bm,"effective")
  +b = E.get(vm,"effective")
  +control = E.text(E.get(b,"control"))
  +case_name = E.text(E.get(b,"case"))
  +effects = E.get(variant,"control_comparison")
  do Result<&2,&2,String,E.Value>:
    _ : Unit <- required(["effective"],bm)
    _ : Unit <- required(["effective"],vm)
    _ : Unit <- required(["control"],b)
    _ : Unit <- E.require(E.is_null(E.get(a,"control")) && one_of(control,["spread","material-detail","surface-detail","fill","body-rich"]),
      "expected baseline and terrain control")
    _ : Unit <- matching(["case","preset","seed","threads","resolution","profile","fragment_budget","warmup","frames"],a,b,"baseline/control mismatch: ")
    _ : Unit <- required(["schedule"],a)
    _ : Unit <- required(["schedule"],b)
    _ : Unit <- E.require(field_is(a,"schedule",E.text(E.get(a,"case")) ++ "-v1") && field_is(b,"schedule",control ++ "-" ++ case_name ++ "-v1"),
      "unexpected frozen schedule identities")
    _ : Unit <- distinct(bm,vm)
    _ : Unit <- distinct(bv,vv)
    _ : Unit <- E.require(field_is(a,"preset","small") && field_is(a,"seed","45") && field_is(a,"threads","6") &&
      field_is(a,"resolution","1920x1080") && field_is(a,"profile","full"),"unsupported control comparison")
    _ : Unit <- control_case(control,case_name)
    _ : Unit <- required(["generation_envelope_cells","occupied_bounds_cells","cells_by_material","exposed_area_by_material_cell_faces","bodies","density"],base)
    _ : Unit <- required(["generation_envelope_cells","occupied_bounds_cells","cells_by_material","exposed_area_by_material_cell_faces","bodies","density","control_comparison"],variant)
    _ : Unit <- required(["control","control_source","baseline_source"],effects)
    _ : Unit <- required(["cells"],E.get(effects,"control_source"))
    _ : Unit <- required(["cells"],E.get(effects,"baseline_source"))
    _ : Unit <- required(["cells"],variant)
    _ : Unit <- required(["cells"],base)
    _ : Unit <- E.require(field_is(effects,"control",control) && E.eq(E.get(E.get(effects,"control_source"),"cells"),E.get(variant,"cells")) &&
      E.eq(E.get(E.get(effects,"baseline_source"),"cells"),E.get(base,"cells")),"source/achieved inventory mismatch")
    +delta : E.Value <- numeric_delta(["cells","protected_cells","cuboids","surface_rectangles","exposed_area_cell_faces","vertices"],base,variant)
    _ : Unit <- required(["initial_owners"],E.get(base,"bodies"))
    _ : Unit <- required(["initial_owners"],E.get(variant,"bodies"))
    _ : Unit <- E.require(field_is(E.get(base,"bodies"),"initial_owners","21") &&
      field_is(E.get(variant,"bodies"),"initial_owners",Bool.pick(String,String.eq(control,"body-rich"),"25","21")),"control owner count mismatch")
    _ : Unit <- control_invariants(control,base,variant,delta,case_name)
    _ : Unit <- binding(bm)
    _ : Unit <- binding(vm)
    return E.object([("schema",E.string("megascene-evidence/1")),("record_type",E.string("terrain_control_comparison")),
      ("status",E.string("pass")),("scope",E.string("validated achieved work comparison; unqualified development observations")),
      ("control",E.get(b,"control")),("case",E.get(b,"case")),
      ("baseline",E.object([("attempt_id",E.get(bm,"attempt_id")),("validation_id",E.get(bv,"attempt_id")),
        ("schedule_sha256",E.get(E.get(bm,"worker_environment"),"MEGASCENE_SCHEDULE_SHA256"))])),
      ("variant",E.object([("attempt_id",E.get(vm,"attempt_id")),("validation_id",E.get(vv,"attempt_id")),
        ("schedule_sha256",E.get(E.get(vm,"worker_environment"),"MEGASCENE_SCHEDULE_SHA256"))])),
      ("delta",delta),("owners",shared(base,variant,"bodies")),("density",shared(base,variant,"density")),
      ("materials",shared(base,variant,"cells_by_material")),
      ("exposed_area_by_material_cell_faces",shared(base,variant,"exposed_area_by_material_cell_faces")),
      ("bounds",shared(base,variant,"occupied_bounds_cells")),("source_effects",effects)])

def completions(rows: List<&2,E.Value>) -> List<&2,E.Value>:
  match rows:
    case Nil{}: Nil{}
    case +row <> rest:
      +tail = completions(rest)
      Bool.pick(List<&2,E.Value>,field_is(row,"record_type","checkpoint") && field_is(row,"frame","3720"),
        row <> tail,tail)
def schedule_load(+payload: E.Value) -> Result<&2,&2,String,E.Value>:
  +manifest = E.get(payload,"manifest")
  +summary = E.get(payload,"summary")
  +validation = E.get(payload,"validation")
  +frozen = E.get(payload,"frozen")
  +complete = completions(E.array(E.get(payload,"records")))
  do Result<&2,&2,String,E.Value>:
    _ : Unit <- required(["attempt_kind","synthetic","attempt_id","effective"],manifest)
    _ : Unit <- required(["synthetic","attempt_id","schedule_completion","state_correctness","rendering_correctness","accepted_edits"],summary)
    _ : Unit <- required(["status","synthetic","attempt_id","checked_frames"],validation)
    _ : Unit <- status_fields(summary,["schedule_completion","state_correctness","rendering_correctness"])
    _ : Unit <- E.require(field_is(manifest,"attempt_kind","development_observation") && Bool.not(E.truth(E.get(manifest,"synthetic"))) &&
      E.eq(E.get(summary,"attempt_id"),E.get(manifest,"attempt_id")) && Bool.not(E.truth(E.get(summary,"synthetic"))) &&
      status(summary,"schedule_completion") && status(summary,"state_correctness") && status(summary,"rendering_correctness"),
      "complete nonsynthetic timed Vulkan attempt required")
    _ : Unit <- E.require(field_is(validation,"status","pass") && Bool.not(E.truth(E.get(validation,"synthetic"))) &&
      Bool.not(E.eq(E.get(validation,"attempt_id"),E.get(manifest,"attempt_id"))) && field_is(validation,"checked_frames","3721"),
      "distinct complete validation required")
    _ : Unit <- required(["schedule_id","actions"],frozen)
    _ : Unit <- required(["schedule"],E.get(manifest,"effective"))
    _ : Unit <- required(["count"],E.get(summary,"accepted_edits"))
    _ : Unit <- E.require(E.eq(E.get(frozen,"schedule_id"),E.get(E.get(manifest,"effective"),"schedule")) &&
      field_is(E.get(summary,"accepted_edits"),"count",U32.show(E.count(E.array(E.get(frozen,"actions"))))),"schedule/action evidence mismatch")
    _ : Unit <- E.require(U32.is_eq(E.count(complete),1) && has_text(E.at(complete,0),"names","completion"),"missing final canonical checkpoint")
    return E.at(complete,0)

def canonical_field_le(a: E.Field(), b: E.Field()) -> Bool:
  (key_a,_) = a
  (key_b,_) = b
  String.is_le(key_a,key_b)
@unsafe def canonical(value: E.Value) -> String:
  match value:
    case E.Null{}: "null"
    case E.Boolean{b}: J.boolean(b)
    case E.Number{s}: s
    case E.Real{_,s}: s
    case E.Text{s}: J.quote(s)
    case E.Array{xs}: "[" ++ canonical_values(xs)
    case E.Object{xs}: "{" ++ canonical_fields(List.sort(E.Field(),canonical_field_le,xs))
    case _: "null"
def canonical_values(xs: List<&2,E.Value>) -> String:
  match xs:
    case Nil{}: "]"
    case h <> Nil{}: canonical(h) ++ "]"
    case h <> rest: canonical(h) ++ "," ++ canonical_values(rest)
def canonical_fields(xs: List<&2,E.Field()>) -> String:
  match xs:
    case Nil{}: "}"
    case (key,value) <> Nil{}: J.quote(key) ++ ":" ++ canonical(value) ++ "}"
    case (key,value) <> rest: J.quote(key) ++ ":" ++ canonical(value) ++ "," ++ canonical_fields(rest)
def geometry_body(+body: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    _ : Unit <- required(["anchored","occupancy","surface","offset_m"],body)
    return E.object([("anchored",E.get(body,"anchored")),("occupancy",E.get(body,"occupancy")),
      ("surface",E.get(body,"surface")),("offset_m",E.get(body,"offset_m"))])
def geometry_bodies(bodies: List<&2,E.Value>) -> Result<&2,&2,String,List<&2,E.Value>>:
  match bodies:
    case Nil{}: Done{Nil{}}
    case body <> rest:
      do Result<&2,&2,String,List<&2,E.Value>>:
        body : E.Value <- geometry_body(body)
        rest : List<&2,E.Value> <- geometry_bodies(rest)
        return body <> rest
def geometry_le(a: E.Value, b: E.Value) -> Bool: String.is_le(canonical(a),canonical(b))
def geometry(+payload: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    _ : Unit <- required(["bodies"],payload)
    _ : Unit <- E.require(E.is_array(E.get(payload,"bodies")),"missing comparison field: bodies")
    bodies : List<&2,E.Value> <- geometry_bodies(E.array(E.get(payload,"bodies")))
    return E.Array{List.sort(E.Value,geometry_le,bodies)}
def removed_cells(cells: List<&2,E.Value>, +owner: E.Value) -> List<&2,E.Value>:
  match cells:
    case Nil{}: Nil{}
    case cell <> rest: E.Array{owner <> E.array(cell)} <> removed_cells(rest,owner)
def removed_actions(actions: List<&2,E.Value>) -> List<&2,E.Value>:
  match actions:
    case Nil{}: Nil{}
    case +action <> rest:
      List.append(&2,E.Value,removed_cells(E.array(E.get(action,"reference_removed_cells")),E.get(E.get(action,"pre_edit_hit"),"owner")),removed_actions(rest))
def tuple_cmp.choose(cmp: Cmp, continuation: Unit -> Cmp) -> Cmp:
  match cmp:
    case EQ{}: continuation(Unit{})
    case cmp: cmp
def tuple_cmp(a: List<&2,E.Value>, b: List<&2,E.Value>) -> Cmp:
  match a b:
    case Nil{} Nil{}: EQ{}
    case Nil{} _: LT{}
    case _ Nil{}: GT{}
    case x <> xt y <> yt:
      tuple_cmp.choose(String.order(E.text(x),E.text(y)),u => tuple_cmp(xt,yt))
def tuple_le(a: E.Value, b: E.Value) -> Bool: Cmp.is_le(tuple_cmp(E.array(a),E.array(b)))
def unique_sorted(xs: List<&2,E.Value>, previous: Maybe<&2,E.Value>) -> List<&2,E.Value>:
  match xs previous:
    case Nil{} _: Nil{}
    case +h <> rest None{}: h <> unique_sorted(rest,Some{h})
    case +h <> rest Some{previous}:
      +tail = unique_sorted(rest,Some{h})
      Bool.pick(List<&2,E.Value>,E.eq(h,previous),tail,h <> tail)
def removed(payload: E.Value) -> E.Value:
  E.Array{unique_sorted(List.sort(E.Value,tuple_le,removed_actions(E.array(E.get(payload,"actions")))),None{})}
def removed_owner(empty: Bool, action: E.Value) -> Result<&2,&2,String,Unit>:
  match empty:
    case True{}: Done{Unit{}}
    case False{}:
      do Result<&2,&2,String,Unit>:
        hit : E.Value <- E.required(action,"pre_edit_hit")
        _ : E.Value <- E.required(hit,"owner")
        return Unit{}
def removed_valid(actions: List<&2,E.Value>) -> Result<&2,&2,String,Unit>:
  match actions:
    case Nil{}: Done{Unit{}}
    case +action <> rest:
      do Result<&2,&2,String,Unit>:
        +cells : E.Value <- E.required(action,"reference_removed_cells")
        _ : Unit <- E.require(E.is_array(cells),"missing removed-cell evidence")
        _ : Unit <- removed_owner(List.is_empty(&2,E.Value,E.array(cells)),action)
        removed_valid(rest)
def removed_checked(+payload: E.Value) -> Result<&2,&2,String,E.Value>:
  do Result<&2,&2,String,E.Value>:
    _ : Unit <- required(["actions"],payload)
    _ : Unit <- E.require(E.is_array(E.get(payload,"actions")),"missing comparison field: actions")
    _ : Unit <- removed_valid(E.array(E.get(payload,"actions")))
    return removed(payload)
def without.fields(xs: List<&2,E.Field()>, +name: String) -> List<&2,E.Field()>:
  match xs:
    case Nil{}: Nil{}
    case (+key,value) <> rest:
      +tail = without.fields(rest,name)
      Bool.pick(List<&2,E.Field()>,String.eq(key,name),tail,(key,value) <> tail)
def without(value: E.Value, name: String) -> E.Value: E.Object{without.fields(E.fields(value),name)}
def cameras(a: List<&2,E.Value>, b: List<&2,E.Value>) -> Result<&2,&2,String,Unit>:
  match a b:
    case Nil{} _: Done{Unit{}}
    case _ Nil{}: Done{Unit{}}
    case x <> xt y <> yt:
      do Result<&2,&2,String,Unit>:
        first : E.Value <- E.required(x,"camera")
        second : E.Value <- E.required(y,"camera")
        _ : Unit <- E.require(E.eq(first,second),"variant actions or camera differ from frozen baseline prefix")
        cameras(xt,yt)
def schedule_protocol(+a: E.Value, +b: E.Value) -> Bool:
  E.eq(E.get(a,"case"),E.get(b,"case")) && one_of(E.text(E.get(a,"case")),["history","support"]) &&
    field_is(a,"schedule",E.text(E.get(a,"case")) ++ "-v1") &&
    one_of(E.text(E.get(b,"schedule")),Bool.pick(List<&2,String>,field_is(a,"case","history"),
      ["history-12-v1","history-48-v1"],["support-1-span-v1","support-2-span-v1"]))

def schedules(+payload: E.Value) -> Result<&2,&2,String,E.Value>:
  +left = E.array(E.get(payload,"baseline"))
  +right = E.array(E.get(payload,"variant"))
  +bm = E.at(left,0)
  +bs = E.at(left,1)
  +bv = E.at(left,2)
  +bi = E.at(left,3)
  +bf = E.at(left,4)
  +bc = E.get(E.at(left,5),"payload")
  +vm = E.at(right,0)
  +vs = E.at(right,1)
  +vv = E.at(right,2)
  +vi = E.at(right,3)
  +vf = E.at(right,4)
  +vc = E.get(E.at(right,5),"payload")
  +a = E.get(bm,"effective")
  +b = E.get(vm,"effective")
  +base_actions = E.array(E.get(bf,"actions"))
  +variant_actions = E.array(E.get(vf,"actions"))
  +meta = E.get(vf,"variant")
  do Result<&2,&2,String,E.Value>:
    _ : Unit <- required(["effective"],bm)
    _ : Unit <- required(["effective"],vm)
    _ : Unit <- required(["case","schedule"],a)
    _ : Unit <- required(["case","schedule"],b)
    _ : Unit <- E.require(schedule_protocol(a,b),"expected baseline and shortened schedule")
    _ : Unit <- matching(["preset","seed","threads","resolution","profile","fragment_budget","warmup","frames","side_m"],a,b,"baseline/variant mismatch: ")
    _ : Unit <- E.require(field_is(a,"preset","small") && field_is(a,"seed","45") && field_is(a,"threads","6") && field_is(a,"resolution","1920x1080") &&
      field_is(a,"profile","full") && E.is_null(E.get(a,"control")) && E.is_null(E.get(b,"control")),"unsupported schedule comparison configuration")
    _ : Unit <- distinct(bm,vm)
    _ : Unit <- distinct(bv,vv)
    _ : Unit <- required(["actual_work"],bv)
    _ : Unit <- required(["actual_work"],vv)
    _ : Unit <- E.require(E.eq(without(vi,"requested_controls"),without(bi,"requested_controls")) && E.eq(E.get(bv,"actual_work"),E.get(vv,"actual_work")),
      "initial achieved world/work differs")
    _ : Unit <- required(["actions","frames","variant"],vf)
    _ : Unit <- required(["actions","frames"],bf)
    _ : Unit <- E.require(E.eq(E.Array{variant_actions},E.Array{List.take(&2,E.Value,base_actions,U32.to_nat(E.count(variant_actions)))}),
      "variant actions or camera differ from frozen baseline prefix")
    _ : Unit <- cameras(E.array(E.get(vf,"frames")),E.array(E.get(bf,"frames")))
    _ : Unit <- E.require(
      U32.is_eq(E.count(E.array(E.get(vf,"frames"))),3721) && U32.is_eq(E.count(E.array(E.get(bf,"frames"))),3721),
      "variant actions or camera differ from frozen baseline prefix")
    _ : Unit <- required(["baseline_schedule_id","required_actions","omitted_actions","omitted_action_disposition","baseline_completion_equivalence"],meta)
    _ : Unit <- required(["count"],E.get(meta,"omitted_actions"))
    _ : Unit <- status_fields(vs,["baseline_schedule_completion"])
    _ : Unit <- E.require(E.eq(E.get(meta,"baseline_schedule_id"),E.get(a,"schedule")) &&
      field_is(meta,"required_actions",U32.show(E.count(variant_actions))) &&
      field_is(E.get(meta,"omitted_actions"),"count",U32.show((E.count(base_actions) - E.count(variant_actions) : U32))) &&
      field_is(meta,"omitted_action_disposition","not_required_for_variant") && E.is_bool(E.get(meta,"baseline_completion_equivalence")) &&
      Bool.not(E.bool(E.get(meta,"baseline_completion_equivalence"))) &&
      field_is(E.get(vs,"baseline_schedule_completion"),"status","not_applicable"),"shortened schedule mislabeled as baseline completion")
    +base_geometry : E.Value <- geometry(bc)
    +variant_geometry : E.Value <- geometry(vc)
    +base_removed : E.Value <- removed_checked(bf)
    +variant_removed : E.Value <- removed_checked(vf)
    +same_geometry : Bool = E.eq(base_geometry,variant_geometry)
    +same_removed : Bool = E.eq(base_removed,variant_removed)
    _ : Unit <- required(["cells","next_id","bodies"],bc)
    _ : Unit <- required(["cells","next_id","bodies"],vc)
    _ : Unit <- required(["accepted_edits","populations"],vs)
    _ : Unit <- required(["edited_work"],vv)
    return E.object([("schema",E.string("megascene-evidence/1")),("record_type",E.string("schedule_variant_comparison")),("status",E.string("pass")),
      ("case",E.get(a,"case")),
      ("baseline",E.object([("attempt_id",E.get(bm,"attempt_id")),("validation_id",E.get(bv,"attempt_id")),("schedule_id",E.get(a,"schedule")),
        ("actions",E.string(U32.show(E.count(base_actions)))),("final_geometry_sha256",E.get(payload,"base_geometry_sha256")),
        ("removed_cell_set_sha256",E.get(payload,"base_removed_sha256")),("final_cells",E.get(bc,"cells")),("final_next_id",E.get(bc,"next_id")),
        ("final_bodies",E.string(U32.show(E.count(E.array(E.get(bc,"bodies"))))))])),
      ("variant",E.object([("attempt_id",E.get(vm,"attempt_id")),("validation_id",E.get(vv,"attempt_id")),("schedule_id",E.get(b,"schedule")),
        ("actions",E.string(U32.show(E.count(variant_actions)))),("final_geometry_sha256",E.get(payload,"variant_geometry_sha256")),
        ("removed_cell_set_sha256",E.get(payload,"variant_removed_sha256")),("final_cells",E.get(vc,"cells")),("final_next_id",E.get(vc,"next_id")),
        ("final_bodies",E.string(U32.show(E.count(E.array(E.get(vc,"bodies")))))),("moving_window",E.get(vv,"moving_window")),
        ("edit_population",E.get(vs,"accepted_edits")),("frame_populations",E.get(vs,"populations")),
        ("history_populations",E.get(vs,"history_populations")),("edited_work_checkpoints",E.string(U32.show(E.count(E.array(E.get(vv,"edited_work"))))))])),
      ("same_final_geometry",E.boolean(same_geometry)),("same_removed_cell_set",E.boolean(same_removed)),
      ("identical_final_geometry_witness",E.boolean(same_geometry && same_removed)),
      ("retention_specific_attribution",E.string(Bool.pick(String,same_geometry && same_removed,
        "candidate witness only; attribution requires a separate controlled analysis","unavailable"))),
      ("scope",E.string("separately validated/timed action and camera comparison; no benchmark qualification")),
      ("_witnesses",E.object([("base_geometry",base_geometry),("variant_geometry",variant_geometry),
        ("base_removed",base_removed),("variant_removed",variant_removed)]))])

def result(value: Result<&2,&2,String,E.Value>) -> E.Value:
  match value:
    case Done{value}: value
    case Fail{message}: E.Error{message}
def handle(operation: String, +payload: E.Value) -> E.Value:
  match operation:
    case "controls_load": result(controls_load(payload))
    case "controls": result(controls(payload))
    case "schedule_load": result(schedule_load(payload))
    case "schedules": result(schedules(payload))
    case "geometry": result(geometry(payload))
    case "removed": result(removed_checked(payload))
    case _: E.Error{"unknown comparison operation"}
def main() -> IO(Unit): E.main(~handle)
