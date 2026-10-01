import Base
import ./schedule_json.bend as J

type Decimal is Data:
  Decimal{word: U32, overflow: Bool}

type Request is Data:
  Request{kind: String, preset: Maybe<&2,String>, side: Maybe<&2,String>, seed: String, threads: String, budget: String,
    allowance: Maybe<&2,String>, campaign: Maybe<&2,String>, archive: Maybe<&2,String>, capture: Bool, validation: Bool, validated: Maybe<&2,String>,
    runtime: Maybe<&2,String>, peer: Maybe<&2,String>, deadline: Maybe<&2,String>, diagnostic: Maybe<&2,String>, resolution: Maybe<&2,String>,
    profile: Maybe<&2,String>, schedule: Maybe<&2,String>, frames: Maybe<&2,String>, warmup: Maybe<&2,String>,
    calibration: Maybe<&2,String>, search: Maybe<&2,String>}

type Common is Data:
  Common{kind: String, preset: String, q: U32, seed: U32, threads: U32, budget: U32}

def require(ok: Bool, message: String) -> Result<&2,&2,String,Unit>:
  match ok:
    case False{}: Fail{message}
    case True{}: Done{Unit{}}

def option(text: String) -> Maybe<&2,String>:
  match text:
    case "0": None{}
    case SCon{Chr{49},tail}: Some{tail}
    case _: Some{"!invalid type"}

def absent(value: Maybe<&2,String>) -> Bool:
  match value:
    case None{}: True{}
    case Some{_}: False{}

def text(value: Maybe<&2,String>, fallback: String) -> String:
  match value:
    case None{}: fallback
    case Some{value}: value

def matches(value: Maybe<&2,String>, expected: String) -> Bool:
  match value:
    case None{}: False{}
    case Some{value}: String.eq(value,expected)

def present(value: Maybe<&2,String>) -> Bool:
  Bool.not(String.eq(text(value,""),""))

def one_of(+value: String, choices: List<&2,String>) -> Bool:
  match choices:
    case Nil{}: False{}
    case choice <> rest: String.eq(value,choice) || one_of(value,rest)

def optional(+value: Maybe<&2,String>, choices: List<&2,String>) -> Bool:
  absent(value) || one_of(text(value,""),choices)

def decimal.step(+acc: U32, overflow: Bool, +digit: U32, valid: Bool,
    continuation: U32 -> Bool -> Result<&2,&2,String,Decimal>) -> Result<&2,&2,String,Decimal>:
  match valid:
    case False{}: Fail{"noncanonical integer"}
    case True{}:
      continuation((acc * 10 + digit : U32),overflow || (acc > 429496729 : U32) ||
        (U32.is_eq(acc,429496729) && (digit > 5 : U32)))

def decimal.tail(digits: String, acc: U32, overflow: Bool) -> Result<&2,&2,String,Decimal>:
  match digits:
    case SNil{}: Done{Decimal{acc,overflow}}
    case SCon{Chr{c},rest}:
      +digit = (c - 48 : U32)
      decimal.step(acc,overflow,digit,(digit < 10 : U32),
        acc => overflow => decimal.tail(rest,acc,overflow))

def decimal(value: String) -> Result<&2,&2,String,Decimal>:
  match value:
    case "0": Done{Decimal{0,False{}}}
    case SCon{Chr{+c},rest}:
      decimal.step(0,False{},(c - 48 : U32),((c >= 49) && (c <= 57) : U32),
        acc => overflow => decimal.tail(rest,acc,overflow))
    case _: Fail{"noncanonical integer"}

def bounded(value: Decimal, limit: U32) -> Bool:
  match value:
    case Decimal{n,overflow}: Bool.not(overflow) && (n <= limit : U32)

def word(value: Decimal) -> U32:
  Decimal{word,_} = value
  word

def exact(+value: Decimal, +expected: U32) -> Bool:
  bounded(value,expected) && U32.is_eq(word(value),expected)

def allowance(value: Maybe<&2,String>) -> Result<&2,&2,String,Unit>:
  match value:
    case None{}: Done{Unit{}}
    case Some{value}:
      do Result<&2,&2,String,Unit>:
        +n : Decimal <- decimal(value)
        require(bounded(n,86400) && (word(n) >= 1 : U32),"additional allowance must be 1..86400 seconds")

def square(+q: U32) -> Result<&2,&2,String,U32>:
  do Result<&2,&2,String,U32>:
    _ : Unit <- require(((q >= 2) && (q <= 5) : U32),
      "square neighborhood scale unsupported: supported q=2..5; no physical capacity claim")
    return q

def preset(q: U32) -> String:
  match q:
    case 2: "small"
    case 4: "large"
    case q: "scale-" ++ U32.show(q)

def preset.side(value: String) -> Result<&2,&2,String,U32>:
  match value:
    case "small": Done{2}
    case "large": Done{4}
    case _: Fail{"unsupported square neighborhood scale"}

def side(value: Maybe<&2,String>, requested: Maybe<&2,String>) -> Result<&2,&2,String,U32>:
  match value:
    case None{}: preset.side(text(requested,"small"))
    case Some{value}:
      do Result<&2,&2,String,U32>:
        +n : Decimal <- decimal(value)
        _ : Unit <- require(U32.is_eq((word(n) % 32 : U32),0),"district side must be 32*q metres")
        _ : Unit <- require(bounded(n,160),
          "square neighborhood scale unsupported: supported q=2..5; no physical capacity claim")
        square((word(n) / 32 : U32))

def admission.option(value: Maybe<&2,String>, name: String) -> Result<&2,&2,String,Unit>:
  require(absent(value),"--" ++ name ++ " requires --case static or a later capability; request rejected")

def admission(request: Request) -> Result<&2,&2,String,Unit>:
  match request:
    case Request{kind,_,_,_,_,_,_,_,_,capture,validation,validated,runtime,peer,deadline,
      diagnostic,resolution,profile,schedule,frames,warmup,calibration,search}:
      match kind:
        case "admission":
          do Result<&2,&2,String,Unit>:
            _ : Unit <- require(Bool.not(validation) && absent(validated) && absent(runtime) && absent(peer),"validation options require --case static")
            _ : Unit <- require(Bool.not(capture) && absent(deadline),"capture/deadline require --case static")
            _ : Unit <- admission.option(diagnostic,"diagnostic")
            _ : Unit <- admission.option(resolution,"resolution")
            _ : Unit <- admission.option(profile,"profile")
            _ : Unit <- admission.option(schedule,"schedule")
            _ : Unit <- admission.option(frames,"frames")
            _ : Unit <- admission.option(warmup,"warmup")
            return Unit{}
        case _: Done{Unit{}}

def request.check(request: Request) -> Result<&2,&2,String,Unit>:
  Request{kind,_,_,_,_,_,+additional,campaign,archive,_,_,_,_,_,_,_,_,_,_,_,_,_,_} = request
  do Result<&2,&2,String,Unit>:
    _ : Unit <- require(one_of(kind,["admission","static","traversal","picking","localized","support","history"]),"unsupported Megascene case")
    _ : Unit <- require(absent(additional) || present(campaign) || present(archive),"additional allowance requires a campaign archive")
    allowance(additional)

def common(+request: Request) -> Result<&2,&2,String,Common>:
  Request{+kind,+requested,side_value,seed_value,thread_value,budget_value,_,_,+archive,
    _,_,_,_,_,_,_,_,_,_,_,_,+calibration,+search} = request
  do Result<&2,&2,String,Common>:
    _ : Unit <- request.check(request)
    _ : Unit <- admission(request)
    _ : Unit <- require(Bool.not(String.eq(kind,"admission") && Bool.not(absent(archive))),"--archive requires --case static or a later capability; request rejected")
    _ : Unit <- require(Bool.not(String.eq(kind,"admission") && Bool.not(absent(calibration))),"--calibration requires --case static or a later capability; request rejected")
    _ : Unit <- require(Bool.not(String.eq(kind,"admission") && Bool.not(absent(search))),"--search requires --case static or a later capability; request rejected")
    +seed : Decimal <- decimal(seed_value)
    +threads : Decimal <- decimal(thread_value)
    +budget : Decimal <- decimal(budget_value)
    _ : Unit <- require(exact(seed,45) || exact(seed,46),"supported seeds are 45 and 46")
    _ : Unit <- require(exact(threads,1) || exact(threads,6) || exact(threads,12),"supported thread counts are 1, 6 and 12")
    _ : Unit <- require(bounded(budget,4294967295),"fragment budget exceeds U32")
    +q : U32 <- side(side_value,requested)
    _ : Unit <- require(optional(requested,[preset(q)]),"contradictory preset and side")
    return Common{kind,preset(q),q,word(seed),word(threads),word(budget)}

def common.fields(value: Common) -> List<&2,String>:
  Common{kind,name,+q,seed,threads,budget} = value
  [J.field("case",J.quote(kind)),J.field("preset",J.quote(name)),J.field("side_m",J.number((32 * q : U32))),
    J.field("neighborhoods_per_side",J.number(q)),J.field("seed",J.number(seed)),
    J.field("threads",J.number(threads)),J.field("fragment_budget",J.number(budget))]

def control(diagnostic: Maybe<&2,String>) -> Maybe<&2,String>:
  match diagnostic:
    case None{}: None{}
    case Some{+value}: Bool.pick(Maybe<&2,String>,one_of(value,["spread","material-detail","surface-detail","fill","body-rich"]),Some{value},None{})

def control.case(kind: String, value: String) -> Bool:
  match kind value:
    case "static" "spread": True{}
    case "static" "material-detail": True{}
    case "localized" "material-detail": True{}
    case "static" "surface-detail": True{}
    case "support" "fill": True{}
    case "history" "fill": True{}
    case "history" "body-rich": True{}
    case _ _: False{}

def calibration(+r: Request) -> Result<&2,&2,String,Unit>:
  Request{kind,_,_,_,_,_,_,_,_,capture,_,_,_,peer,_,diagnostic,resolution,profile,_,_,_,+mode,search} = r
  do Result<&2,&2,String,Unit>:
    _ : Unit <- require(absent(search),"--search is not implemented")
    _ : Unit <- require(optional(mode,["on","off"]),"--calibration must be on or off")
    _ : Unit <- require(absent(mode) || (one_of(kind,["static","history"]) && absent(diagnostic) &&
      optional(profile,["full"]) && optional(resolution,["1920x1080"]) && Bool.not(capture)),
      "calibration requires primary static/history full geometry at 1920x1080")
    require(Bool.not(absent(mode)) || absent(peer),"peer validation requires a calibration mode")

def replay.geometry(+r: Request, c: Common, +ctrl: Maybe<&2,String>, +diag: Maybe<&2,String>) -> Result<&2,&2,String,Unit>:
  Request{+kind,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,+resolution,+profile,_,_,_,_,_} = r
  Common{_,+name,_,seed,threads,_} = c
  do Result<&2,&2,String,Unit>:
    _ : Unit <- require(absent(ctrl) || control.case(kind,text(ctrl,"")),"unsupported control/case combination")
    _ : Unit <- require(absent(ctrl) || (String.eq(name,"small") && U32.is_eq(seed,45) && U32.is_eq(threads,6) && optional(resolution,["1920x1080"])),
      "terrain controls require small/seed-45/1080p/6 threads")
    _ : Unit <- require(absent(diag) || (optional(diag,["mixed-world","compact-reference"]) && one_of(kind,["traversal","picking"])),
      "proxy diagnostics require traversal or picking")
    _ : Unit <- require(absent(diag) || (matches(profile,"full") || matches(profile,"proxy")),"proxy diagnostic requires explicit full or proxy profile")
    _ : Unit <- require(absent(diag) || (String.eq(name,"small") && optional(resolution,["1920x1080"])),"proxy diagnostic requires small/1080p")
    require(Bool.not(absent(diag)) || optional(profile,["full"]),"primary replays require --profile full")

def performance(+value: Maybe<&2,String>) -> Bool:
  matches(value,"static-perf-v2") || matches(value,"history-perf-v2")

def variant(value: String) -> Bool:
  one_of(value,["history-12-v1","history-48-v1","support-1-span-v1","support-2-span-v1"])

def schedule.default(+kind: String, name: String, +requested: Maybe<&2,String>, +ctrl: Maybe<&2,String>, +diag: Maybe<&2,String>) -> String:
  match kind:
    case "traversal": Bool.pick(String,absent(diag),Bool.pick(String,present(requested),text(requested,""),"traversal-v2"),"proxy-" ++ text(diag,"") ++ "-traversal-v1")
    case "picking": Bool.pick(String,absent(diag),Bool.pick(String,present(requested),text(requested,""),"picking-v2"),"proxy-" ++ text(diag,"") ++ "-picking-v1")
    case "localized": Bool.pick(String,absent(ctrl),
      Bool.pick(String,variant(text(requested,"")),text(requested,""),"localized-v1"),text(ctrl,"") ++ "-localized-v1")
    case "support": Bool.pick(String,absent(ctrl),
      Bool.pick(String,variant(text(requested,"")),text(requested,""),"support-v1"),text(ctrl,"") ++ "-support-v1")
    case "history": Bool.pick(String,absent(ctrl),Bool.pick(String,variant(text(requested,"")),text(requested,""),
      Bool.pick(String,one_of(name,["small","large"]),"history-v1","history-v2")),text(ctrl,"") ++ "-history-v1")
    case _: Bool.pick(String,absent(ctrl),"static-v1",text(ctrl,"") ++ "-static-v1")

def schedule(+r: Request, c: Common, ctrl: Maybe<&2,String>, diag: Maybe<&2,String>) -> Result<&2,&2,String,String>:
  Request{+kind,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,resolution,_,+requested,_,_,_,_} = r
  Common{_,+name,_,seed,threads,_} = c
  +id = Bool.pick(String,performance(requested),text(requested,""),schedule.default(kind,name,requested,ctrl,diag))
  +check_variant = one_of(kind,["localized","support","history"]) && variant(id)
  do Result<&2,&2,String,String>:
    _ : Unit <- require(Bool.not(check_variant) || ((String.eq(kind,"history") && one_of(id,["history-12-v1","history-48-v1"])) ||
      (String.eq(kind,"support") && one_of(id,["support-1-span-v1","support-2-span-v1"]))),"variant schedule/case mismatch")
    _ : Unit <- require(Bool.not(check_variant) || (String.eq(name,"small") && U32.is_eq(seed,45) && U32.is_eq(threads,6) && optional(resolution,["1920x1080"])),
      "history/span controls require small/seed-45/1080p/6 threads")
    _ : Unit <- require(optional(requested,[id]),"unsupported frozen schedule")
    return id

def json.option(value: Maybe<&2,String>) -> String:
  match value:
    case None{}: "null"
    case Some{value}: J.quote(value)

def late(+r: Request, +c: Common, +ctrl: Maybe<&2,String>, +diag: Maybe<&2,String>, +warmup: U32, +frames: U32,
    +id: String) -> Result<&2,&2,String,Unit>:
  Request{+kind,_,_,_,_,_,_,_,_,capture,validation,validated,runtime,_,_,_,resolution,profile,requested,_,_,_,_} = r
  Common{_,name,_,seed,threads,budget} = c
  do Result<&2,&2,String,Unit>:
    _ : Unit <- require(Bool.not(present(validated) && present(runtime)),"choose --validated or --runtime-from")
    _ : Unit <- require(Bool.not(validation && (present(validated) || capture)),"validation-only cannot reuse validation or request capture")
    _ : Unit <- require(Bool.not(performance(requested)) || (String.eq(id,kind ++ "-perf-v2") && one_of(kind,["static","history"])),
      "performance schedule/case mismatch")
    _ : Unit <- require(Bool.not(performance(requested)) || (String.eq(name,"small") && U32.is_eq(seed,45) && U32.is_eq(threads,6) &&
      optional(profile,["full"]) && optional(resolution,["1920x1080"]) && U32.is_eq(warmup,120) && U32.is_eq(frames,21600) &&
      U32.is_eq(budget,2048) && absent(ctrl) && absent(diag)),
      "performance v2 requires small/seed45/6/full/1080p/120/21600/budget2048")
    require(Bool.not(performance(requested) && capture),"performance captures use separate validation evidence")

def late.message(result: Result<&2,&2,String,Unit>) -> String:
  match result:
    case Fail{message}: J.quote(message)
    case Done{_}: "null"

def replay(+r: Request, +c: Common) -> Result<&2,&2,String,String>:
  Request{+kind,_,_,_,_,_,_,_,_,+capture,validation,_,_,peer,+deadline_value,+diagnostic,+resolution,+profile,+requested,
    frames_value,warmup_value,mode,_} = r
  Common{_,_,+q,_,_,_} = c
  +ctrl = control(diagnostic)
  +diag = Bool.pick(Maybe<&2,String>,absent(ctrl),diagnostic,None{})
  +perf = performance(requested)
  do Result<&2,&2,String,String>:
    _ : Unit <- calibration(r)
    _ : Unit <- replay.geometry(r,c,ctrl,diag)
    +id : String <- schedule(r,c,ctrl,diag)
    _ : Unit <- require(optional(resolution,["640x360","1920x1080"]),"supported replay resolutions are 640x360 and 1920x1080")
    +warmup : Decimal <- decimal(text(warmup_value,"120"))
    +frames : Decimal <- decimal(text(frames_value,Bool.pick(String,perf,"21600","3600")))
    +deadline : Decimal <- decimal(text(deadline_value,"300"))
    _ : Unit <- require(bounded(warmup,120) && bounded(frames,Bool.pick(U32,perf,21600,3600)) && (word(frames) >= 1 : U32),"unsupported replay frame count")
    +complete : Bool = exact(warmup,120) && exact(frames,3600)
    _ : Unit <- require(Bool.not(one_of(kind,["traversal","picking","localized","support","history"]) && Bool.not(perf)) || complete,
      "primary replay requires the complete 120/3600 schedule")
    _ : Unit <- require(Bool.not(one_of(kind,["traversal","picking","localized","support","history"]) && Bool.not(perf) && capture),
      "replay captures come from the separate validation replay")
    _ : Unit <- require(absent(ctrl) || complete,"terrain controls require the complete 120/3600 schedule")
    _ : Unit <- require(absent(mode) || Bool.not((perf || complete) && Bool.not(validation)) || Bool.not(absent(peer)),
      "complete calibration controls require prior opposite-mode validation")
    _ : Unit <- require(bounded(deadline,300) && (word(deadline) >= 1 : U32),"development deadline must be 1..300 seconds")
    +extra : List<&2,String> = Bool.pick(List<&2,String>,perf && String.eq(kind,"history"),
      [J.field("validation_deadline_s",J.number(Bool.pick(U32,absent(deadline_value),480,word(deadline))))],Nil{})
    +fields : List<&2,String> = [J.field("diagnostic",json.option(diag)),J.field("control",json.option(ctrl)),
      J.field("calibration_mode",json.option(mode)),J.field("envelope_side_m",J.number(Bool.pick(U32,matches(ctrl,"spread"),(64 * (q - 1 : U32) + 32 : U32),(32 * q : U32)))),
      J.field("profile",J.quote(text(profile,"full"))),J.field("resolution",J.quote(text(resolution,"1920x1080"))),
      J.field("warmup",J.number(word(warmup))),J.field("frames",J.number(word(frames))),J.field("schedule",J.quote(id)),
      J.field("deadline_s",J.number(word(deadline))),J.field("schedule_kind",J.quote(Bool.pick(String,perf,"performance_v2",
        Bool.pick(String,variant(id),"declared_control",Bool.pick(String,complete,"accepted","declared_development_prefix")))))]
    return J.object([J.field("configuration",J.object(List.append(&2,String,fields,extra))),
      J.field("late_error",late.message(late(r,c,ctrl,diag,word(warmup),word(frames),id)))])

def emit(result: Result<&2,&2,String,String>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{value}: IO.print(value)

def execute(operation: String, +r: Request) -> Result<&2,&2,String,String>:
  match operation:
    case "request":
      do Result<&2,&2,String,String>:
        _ : Unit <- request.check(r)
        return "null"
    case "common":
      do Result<&2,&2,String,String>:
        c : Common <- common(r)
        return J.object(common.fields(c))
    case "replay":
      do Result<&2,&2,String,String>:
        c : Common <- common(r)
        replay(r,c)
    case _: Fail{"unsupported configuration operation"}

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case _ <> op <> kind <> name <> side_value <> seed <> threads <> budget <> additional <> campaign <> archive <> capture <>
      validation <> validated <> runtime <> peer <> deadline <> diagnostic <> resolution <> profile <> schedule_value <> frames <> warmup <> calibration_value <> search <> Nil{}:
      emit(execute(op,Request{kind,option(name),option(side_value),seed,threads,budget,option(additional),option(campaign),
        option(archive),String.eq(capture,"true"),String.eq(validation,"true"),option(validated),option(runtime),
        option(peer),option(deadline),option(diagnostic),option(resolution),option(profile),option(schedule_value),option(frames),
        option(warmup),option(calibration_value),option(search)}))
    case _: IO.die(Unit,2,"usage: megascene-configuration request|common|replay CASE PRESET SIDE SEED THREADS BUDGET ALLOWANCE CAMPAIGN ARCHIVE CAPTURE VALIDATION VALIDATED RUNTIME PEER DEADLINE DIAGNOSTIC RESOLUTION PROFILE SCHEDULE FRAMES WARMUP CALIBRATION SEARCH")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
