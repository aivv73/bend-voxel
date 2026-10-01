import Base
import ./benchmark_tool.bend as B
import ./benchmark_metrics.bend as M
import ./schedule_json.bend as J
import ./stress_parser.bend as P

type Case is Data:
  Case{name: String, mode: String, view: U32}
type Options is Data:
  Options{root: String, output: String, binary: String, warmup: U32, measured: U32, edit_every: U32,
    budget: U32, timeout: U32, width: U32, height: U32, cases: List<&2,Case>}
type Outcome is Data:
  Outcome{code: U32, error: String}
type Present is Data:
  Present{mode: String, valid: Bool}
type Resolution is Data:
  Resolution{width: U32, height: U32}

def cases() -> List<&2,Case>:
  [Case{"atelier","static",0},Case{"atelier-night","night",6},Case{"atelier-camera","camera",1},
    Case{"atelier-aim","aim",2},Case{"atelier-carve","carve",3}]
def case.name(value: Case) -> String:
  Case{name,_,_} = value
  name
def case.find(xs: List<&2,Case>, +name: String) -> Result<&2,&2,String,Case>:
  match xs:
    case Nil{}: Fail{"unknown stress case"}
    case +h <> rest: Bool.pick(Result<&2,&2,String,Case>,String.eq(case.name(h),name),Done{h},case.find(rest,name))
def case.lookup(name: String) -> Result<&2,&2,String,Case>: case.find(cases(),name)
def require(ok: Bool, message: String) -> Result<&2,&2,String,Unit>:
  match ok:
    case True{}: Done{Unit{}}
    case False{}: Fail{message}
def moving(workload: Case) -> Bool:
  Case{_,+mode,_} = workload
  String.eq(mode,"camera") || String.eq(mode,"aim")
def checked(+options: Options) -> Result<&2,&2,String,Options>:
  Options{_,_,_,+warmup,+measured,_,+budget,+timeout,+width,+height,+selected} = options
  do Result<&2,&2,String,Options>:
    _ : Unit <- require(((measured >= 1) && (timeout >= 1) && (timeout <= 4294964) : U32),"frames and timeout must be positive; timeout must be at most 4294964 seconds")
    _ : Unit <- require(((warmup <= 5000) && (measured <= 5000) && (warmup + measured <= 5000) : U32),"at most 5000 total frames per case")
    _ : Unit <- require(((budget >= 1) && (budget <= 65536) : U32),"body budget must be 1..65536")
    _ : Unit <- require(((width >= 640) && (width <= 7680) && (height >= 360) && (height <= 4320) && (width * height <= 8294400) : U32),"resolution must be 640..7680 by 360..4320, at most 8294400 pixels")
    _ : Unit <- require(Bool.not(Nat.is_eq(List.length(&2,Case,selected),0n)),"at least one stress case required")
    _ : Unit <- require(((measured >= 4) : U32) || Bool.not(List.any(&2,Case,moving,selected)),"moving view workloads need at least four measured frames")
    return options

def option.names() -> List<&2,String>:
  ["--cases","--warmup","--frames","--edit-every","--body-budget","--timeout","--resolution","--output","--binary","--help"]
def option.parts(parts: List<&2,String>) -> Result<&2,&2,String,List<&2,String>>:
  match parts:
    case +name <> +rest:
      do Result<&2,&2,String,List<&2,String>>:
        name : String <- B.option.unique(B.option.matches(option.names(),name))
        return name <> Bool.pick(List<&2,String>,Nat.is_eq(List.length(&2,String,rest),0n),Nil{},[String.join(rest,"=")])
    case _: Fail{"invalid stress option"}
def option(s: String) -> Result<&2,&2,String,List<&2,String>>:
  match s:
    case "-h": Done{["--help"]}
    case SCon{'-',SCon{'-',_}}: option.parts(String.split(s,'='))
    case _: Done{[s]}
def normalize(xs: List<&2,String>) -> Result<&2,&2,String,List<&2,String>>:
  match xs:
    case Nil{}: Done{Nil{}}
    case "--" <> rest: Done{"--" <> rest}
    case h <> rest:
      do Result<&2,&2,String,List<&2,String>>:
        head : List<&2,String> <- option(h)
        tail : List<&2,String> <- normalize(rest)
        return List.append(&2,String,head,tail)
def resolution(parts: List<&2,String>) -> Result<&2,&2,String,Resolution>:
  match parts:
    case +a <> +b <> Nil{}:
      do Result<&2,&2,String,Resolution>:
        _ : Unit <- require(Bool.not(String.is_empty(a)) && Bool.not(String.is_empty(b)) &&
          List.all(&2,Char,Char.is_digit,String.to_list(a)) && List.all(&2,Char,Char.is_digit,String.to_list(b)),"resolution must be WIDTHxHEIGHT")
        a : U32 <- M.argument(a)
        b : U32 <- M.argument(b)
        return Resolution{a,b}
    case _: Fail{"resolution must be WIDTHxHEIGHT"}
def set.number(+name: String, +value: U32, options: Options) -> Options:
  Options{root,out,binary,+warmup,+frames,+edit,+budget,+timeout,width,height,selected} = options
  Options{root,out,binary,Bool.pick(U32,String.eq(name,"--warmup"),value,warmup),
    Bool.pick(U32,String.eq(name,"--frames"),value,frames),Bool.pick(U32,String.eq(name,"--edit-every"),value,edit),
    Bool.pick(U32,String.eq(name,"--body-budget"),value,budget),Bool.pick(U32,String.eq(name,"--timeout"),value,timeout),width,height,selected}
def set.path(+name: String, +value: String, options: Options) -> Options:
  Options{root,+out,+binary,warmup,frames,edit,budget,timeout,width,height,selected} = options
  Options{root,Bool.pick(String,String.eq(name,"--output"),value,out),Bool.pick(String,String.eq(name,"--binary"),value,binary),warmup,frames,edit,budget,timeout,width,height,selected}
def set.resolution(value: Resolution, options: Options) -> Options:
  Resolution{width,height} = value
  Options{root,out,binary,warmup,frames,edit,budget,timeout,_,_,selected} = options
  Options{root,out,binary,warmup,frames,edit,budget,timeout,width,height,selected}
def set.cases(selected: List<&2,Case>, options: Options) -> Options:
  Options{root,out,binary,warmup,frames,edit,budget,timeout,width,height,_} = options
  Options{root,out,binary,warmup,frames,edit,budget,timeout,width,height,selected}
def arguments.cases(xs: List<&2,String>, +acc: List<&2,Case>, next: List<&2,Case> -> List<&2,String> -> Result<&2,&2,String,Options>) -> Result<&2,&2,String,Options>:
  match xs:
    case Nil{}:
      do Result<&2,&2,String,Options>:
        _ : Unit <- require(Bool.not(Nat.is_eq(List.length(&2,Case,acc),0n)),"--cases requires one or more cases")
        next(List.reverse(&2,Case,acc),Nil{})
    case +h <> +rest:
      match h:
        case SCon{'-',_}:
          do Result<&2,&2,String,Options>:
            _ : Unit <- require(Bool.not(Nat.is_eq(List.length(&2,Case,acc),0n)),"--cases requires one or more cases")
            next(List.reverse(&2,Case,acc),h <> rest)
        case _:
          do Result<&2,&2,String,Options>:
            item : Case <- case.lookup(h)
            arguments.cases(rest,item <> acc,next)
def arguments.value(name: String, value: String, options: Options, next: Options -> Result<&2,&2,String,Options>) -> Result<&2,&2,String,Options>:
  match name:
    case "--output": next(set.path("--output",value,options))
    case "--binary": next(set.path("--binary",value,options))
    case +name:
      do Result<&2,&2,String,Options>:
        value : U32 <- M.argument(value)
        next(set.number(name,value,options))
def argument.known(name: String) -> Bool:
  match name:
    case "--warmup": True{}
    case "--frames": True{}
    case "--edit-every": True{}
    case "--body-budget": True{}
    case "--timeout": True{}
    case "--output": True{}
    case "--binary": True{}
    case _: False{}
def arguments.parse(fuel: Nat, xs: List<&2,String>, +options: Options) -> Result<&2,&2,String,Options>:
  match fuel xs:
    case _ Nil{}: checked(options)
    case 0n _: Fail{"invalid stress arguments"}
    case 1n+p "--cases" <> rest: arguments.cases(rest,Nil{},selected => rest => arguments.parse(p,rest,set.cases(selected,options)))
    case 1n+p "--resolution" <> value <> rest:
      do Result<&2,&2,String,Options>:
        value : Resolution <- resolution(String.split(value,'x'))
        arguments.parse(p,rest,set.resolution(value,options))
    case 1n+p +name <> value <> rest:
      do Result<&2,&2,String,Options>:
        _ : Unit <- require(argument.known(name),"unknown stress option or missing value")
        arguments.value(name,value,options,options => arguments.parse(p,rest,options))
    case _ _: Fail{"unknown stress option or missing value"}

def artifact.closed(value: File & Result<&1,&1,U32 & String,String>) -> IO(Result<&2,&2,String,String>):
  match value:
    case (file,Done{text}):
      do IO<Result<&2,&2,String,String>>:
        _ : Unit <- File.close(file)
        return Done{B.newlines(text)}
    case (file,Fail{(_,message)}):
      do IO<Result<&2,&2,String,String>>:
        _ : Unit <- File.close(file)
        return Fail{message}
def artifact.sized(valid: Bool, file: File, size: U32) -> IO(Result<&2,&2,String,String>):
  match valid:
    case True{}:
      do IO<Result<&2,&2,String,String>>:
        value : File & Result<&1,&1,U32 & String,String> <- File.read(file,size)
        artifact.closed(value)
    case False{}:
      do IO<Result<&2,&2,String,String>>:
        _ : Unit <- File.close(file)
        return Fail{"stress artifact exceeds 16 MiB"}
def artifact.size(value: File & Result<&1,&1,U32 & String,U32>) -> IO(Result<&2,&2,String,String>):
  match value:
    case (file,Done{+size}): artifact.sized((size <= 16777216 : U32),file,size)
    case (file,Fail{(_,message)}):
      do IO<Result<&2,&2,String,String>>:
        _ : Unit <- File.close(file)
        return Fail{message}
def artifact.opened(value: Result<&1,&1,U32 & String,File>) -> IO(Result<&2,&2,String,String>):
  match value:
    case Fail{(_,message)}: IO.pure(Result<&2,&2,String,String>,Fail{message})
    case Done{file}:
      do IO<Result<&2,&2,String,String>>:
        value : File & Result<&1,&1,U32 & String,U32> <- File.size(file)
        artifact.size(value)
def artifact.read(path: String) -> IO(Result<&2,&2,String,String>):
  do IO<Result<&2,&2,String,String>>:
    value : Result<&1,&1,U32 & String,File> <- File.open(path,"r")
    artifact.opened(value)

def present.lines(xs: List<&2,String>, +mode: String, +valid: Bool) -> Present:
  match xs:
    case Nil{}: Present{mode,valid && Bool.not(String.is_empty(mode))}
    case +line <> rest:
      +candidate = Bool.pick(String,String.eq(line,"stress_present_mode,immediate"),"immediate",Bool.pick(String,String.eq(line,"stress_present_mode,mailbox"),"mailbox",""))
      present.lines(rest,Bool.pick(String,String.is_empty(mode),candidate,mode),valid && (String.is_empty(candidate) || String.is_empty(mode) || String.eq(candidate,mode)))
def presentation(error: String) -> Present: present.lines(String.lines(error),"",True{})
def deadline.notice(line: String) -> Bool:
  +s : String = line
  String.starts_with(s,"timeout: sending signal TERM to command ") || String.starts_with(s,"timeout: sending signal KILL to command ")
def outcome.observed(deadline: Bool, code: U32, error: String) -> Outcome:
  match deadline:
    case True{}: Outcome{124,""}
    case False{}: Outcome{code,error}
def outcome.raw(code: U32, error: String) -> Outcome:
  +message : String = error
  outcome.observed(List.any(&2,String,deadline.notice,String.lines(B.newlines(message))),code,message)
def outcome(value: Result<&1,&1,U32 & String,U32 & (String & String)>) -> Outcome:
  match value:
    case Done{(code,(out,error))}: outcome.raw(code,error)
    case Fail{(_,message)}: Outcome{125,message}
def edit.interval(mode: String, interval: U32) -> U32: Bool.pick(U32,String.eq(mode,"carve"),interval,0)
def dimensions(width: U32, height: U32) -> String: U32.show(width) ++ "x" ++ U32.show(height)
def run.control() -> String:
  "duration=$1; csv=$2; error=$3; child=$4; shift 4; locale_present=${LC_ALL+x}; locale_value=${LC_ALL-}; " ++
  "LC_ALL=C timeout --verbose --kill-after=1 \"$duration\" sh -c \"$child\" stress-child \"$locale_present\" \"$locale_value\" \"$csv\" \"$error\" \"$@\""
def run.child() -> String:
  "locale_present=$1; locale_value=$2; csv=$3; error=$4; shift 4; " ++
  "if [ \"$locale_present\" = x ]; then LC_ALL=$locale_value; export LC_ALL; else unset LC_ALL; fi; " ++
  "exec \"$@\" > \"$csv\" 2> \"$error\""
def run(+options: Options, workload: Case, +csv: String, +error: String) -> IO(Outcome):
  Options{root,_,binary,warmup,measured,edit,budget,+timeout,width,height,_} = options
  Case{_,mode,view} = workload
  do IO<Outcome>:
    B.write(csv,"")
    B.write(error,"")
    value : Result<&1,&1,U32 & String,U32 & (String & String)> <- Process.run("sh",B.linear([
      "-c",run.control(),"stress-run",U32.show(timeout),csv,error,run.child(),"env","--chdir=" ++ root,
      "VOXEL_RESOLUTION=" ++ dimensions(width,height),"VOXEL_STRESS=1","VOXEL_BODY_BUDGET=" ++ U32.show(budget),
      "VOXEL_STRESS_PRESENT=unpaced","VOXEL_STRESS_VIEW=" ++ U32.show(view),"VOXEL_STRESS_WARMUP=" ++ U32.show(warmup),
      "VOXEL_STRESS_MEASURED=" ++ U32.show(measured),"VOXEL_STRESS_EDIT_EVERY=" ++ U32.show(edit.interval(mode,edit)),
      binary,"--gpu","off"]),"",1048576,((timeout + 3) * 1000 : U32))
    return outcome(value)

def report.append(report: P.Report, fields: List<&2,String>) -> P.Report:
  P.Report{passed,errors,old} = report
  P.Report{passed,errors,List.append(&2,String,old,fields)}
def parsed.csv(source: Result<&2,&2,String,String>, code: U32, options: P.Options) -> IO(P.Report):
  match source:
    case Done{text}: P.parse(text,code,options)
    case Fail{message}: IO.pure(P.Report,P.Report{False{},[message],Nil{}})
def parsed.present(value: Present, +report: P.Report) -> P.Report:
  Present{+mode,valid} = value
  report.append(Bool.pick(P.Report,valid,report,P.add_error(report,"Unpaced present mode was not confirmed")),[J.field("present_mode",Bool.pick(String,String.is_empty(mode),"null",J.quote(mode)))])
def parsed.stderr(source: Result<&2,&2,String,String>, report: P.Report) -> P.Report:
  match source:
    case Done{error}: parsed.present(presentation(error),report)
    case Fail{message}: report.append(P.add_error(report,message),[J.field("present_mode","null")])
def parsed.outcome(value: Outcome, +report: P.Report) -> P.Report:
  Outcome{_,+message} = value
  Bool.pick(P.Report,String.is_empty(message),report,P.add_error(report,message))
def outcome.code(value: Outcome) -> U32:
  Outcome{code,_} = value
  code
def select.field(xs: List<&2,String>, +key: String) -> String:
  match xs:
    case Nil{}: J.field(key,"null")
    case +field <> rest: Bool.pick(String,String.starts_with(field,J.quote(key) ++ ":"),field,select.field(rest,key))
def select.fields(keys: List<&2,String>, +fields: List<&2,String>) -> List<&2,String>:
  match keys:
    case Nil{}: Nil{}
    case +key <> rest:
      select.field(fields,key) <> select.fields(rest,fields)
def quote.errors(xs: List<&2,String>) -> List<&2,String>:
  match xs:
    case Nil{}: Nil{}
    case h <> rest: J.quote(h) <> quote.errors(rest)
def console(report: P.Report) -> IO(Unit):
  P.Report{passed,+errors,fields} = report
  +fields : List<&2,String> = J.field("pass",J.boolean(passed)) <> J.field("errors",J.array(quote.errors(errors))) <> fields
  IO.print(String.trim(B.report(M.object(select.fields(["name","pass","solid_cells_start","surface_rectangles","max_bodies","max_moving_bodies","present_mode","throughput_fps","visible_bodies_mean","draw_calls_mean","lod_proxied_bodies_mean","lod_proxy_rebuilds","acquire_wait_fraction","errors"],fields)))))
def case.run(+options: Options, +workload: Case) -> IO(P.Report):
  Options{_,+output,_,warmup,measured,edit,_,_,width,height,_} = options
  Case{+name,+mode,_} = workload
  +interval = edit.interval(mode,edit)
  +csv = output ++ "/" ++ name ++ ".csv"
  +error = output ++ "/" ++ name ++ ".stderr"
  do IO<P.Report>:
    IO.print("Stress " ++ name ++ ": " ++ mode ++ " workload, " ++ dimensions(width,height))
    +value : Outcome <- run(options,workload,csv,error)
    source : Result<&2,&2,String,String> <- artifact.read(csv)
    report : P.Report <- parsed.csv(source,outcome.code(value),P.Options{warmup,measured,interval,mode,True{}})
    source : Result<&2,&2,String,String> <- artifact.read(error)
    +report : P.Report = report.append(parsed.outcome(value,parsed.stderr(source,report)),[J.field("name",J.quote(name)),J.field("view_mode",J.quote(mode)),J.field("edit_every_frames",U32.show(interval))])
    console(report)
    return report

def metadata(+options: Options) -> IO(String):
  Options{+root,_,+binary,warmup,measured,edit,budget,_,width,height,_} = options
  do IO<String>:
    version : String <- B.system(["bend","version"])
    date : String <- B.system(["date","+%Y-%m-%dT%H:%M:%S%z"])
    revision : String <- B.system(B.cwd(root,["git","rev-parse","HEAD"]))
    dirty : String <- B.system(B.cwd(root,["git","status","--porcelain"]))
    src : List<&2,String> <- B.source.hashes(root,"src")
    scripts : List<&2,String> <- B.source.hashes(root,"scripts")
    digest : String <- B.hash(binary)
    return M.object([J.field("date",J.quote(B.trim(date))),J.field("bend",J.quote(B.trim(version))),J.field("git_revision",J.quote(B.trim(revision))),
      J.field("working_tree_dirty",J.boolean(Bool.not(String.is_empty(dirty)))),J.field("binary",J.quote(binary)),J.field("binary_sha256",J.quote(digest)),
      J.field("source_scope",J.quote("source_sha256 describes the current checkout, which may differ from an explicitly selected prebuilt binary; both binaries use the current native library and shaders")),
      J.field("resolution",J.array([U32.show(width),U32.show(height)])),J.field("warmup_frames",U32.show(warmup)),J.field("measured_frames",U32.show(measured)),
      J.field("edit_every_frames",U32.show(edit)),J.field("body_budget",U32.show(budget)),J.field("source_sha256",M.object(List.append(&2,String,src,scripts))),
      J.field("timing_scope",J.quote("Frame throughput includes Bend simulation, edits and body triangle construction, scene preparation, native proxy and overlay geometry, upload, Vulkan submission/presentation, and X11 synchronization. Fence and acquisition waits include GPU/presentation backpressure; these CPU wall-clock intervals are not GPU timestamps.")),
      J.field("scene_scope",J.quote("The six-body Light Atelier has 803,970 occupied 10 cm cells, three editable Blender sculptures, sun shadows, and a plaster courtyard. Physics advances exactly 1/60 second per frame."))])
def reports.json(xs: List<&2,P.Report>) -> List<&2,String>:
  match xs:
    case Nil{}: Nil{}
    case h <> rest: P.json(h) <> reports.json(rest)
def document(metadata: String, reports: List<&2,P.Report>, passed: Bool) -> String:
  M.object([J.field("metadata",metadata),J.field("cases",J.array(reports.json(reports))),J.field("pass",J.boolean(passed))])
def exit(passed: Bool) -> IO(Unit):
  match passed:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,"")
def finished(passed: Bool, output: String) -> IO(Unit):
  do IO<Unit>:
    IO.print("Report: " ++ output ++ "/report.json")
    exit(passed)
def options.output(options: Options) -> String:
  Options{_,output,_,_,_,_,_,_,_,_,_} = options
  output
def report.passed(report: P.Report) -> Bool:
  P.Report{passed,_,_} = report
  passed
def execute.cases(todo: List<&2,Case>, +options: Options, +info: String, +acc: List<&2,P.Report>, +passed: Bool) -> IO(Unit):
  match todo:
    case Nil{}:
      Options{_,output,_,_,_,_,_,_,_,_,_} = options
      finished(passed,output)
    case c <> rest:
      do IO<Unit>:
        +value : P.Report <- case.run(options,c)
        +acc : List<&2,P.Report> = value <> acc
        +passed : Bool = passed && report.passed(value)
        B.write(options.output(options) ++ "/report.json",B.report(document(info,List.reverse(&2,P.Report,acc),passed)))
        execute.cases(rest,options,info,acc,passed)
def resolved.exists(value: B.Run, +options: Options, output: String, selected: List<&2,Case>) -> IO(Unit):
  match value:
    case B.Run{0,_,_}:
      do IO<Unit>:
        B.mkdir(output)
        info : String <- metadata(options)
        execute.cases(selected,options,info,Nil{},True{})
    case _: IO.die(Unit,2,"binary is missing; run make build first")
def resolved(+options: Options) -> IO(Unit):
  Options{_,+output,+binary,_,_,_,_,_,_,_,+selected} = options
  do IO<Unit>:
    present : B.Run <- B.command(["test","-f",binary],1024,10000)
    resolved.exists(present,options,output,selected)
def execute(options: Options) -> IO(Unit):
  Options{+root,output,binary,warmup,measured,edit,budget,timeout,width,height,selected} = options
  resolved(Options{root,B.path(root,output),B.path(root,binary),warmup,measured,edit,budget,timeout,width,height,selected})
def help() -> IO(Unit):
  IO.print("usage: benchmark_stress.sh [--cases CASE ...] [--warmup WARMUP] [--frames FRAMES]\n       [--edit-every EDIT_EVERY] [--body-budget BODY_BUDGET] [--timeout TIMEOUT]\n       [--resolution WIDTHxHEIGHT] [--output OUTPUT] [--binary BINARY]\nMeasure the Light Atelier stress workloads.\nDefaults: all five cases, 30 warmup frames, 180 measured frames, 30 edit interval,\n          body budget 2048, timeout 180 seconds, resolution 640x360, output build/stress.")
def parsed(value: Result<&2,&2,String,Options>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{options}: execute(options)
def normalized.help(requested: Bool, +xs: List<&2,String>, root: String) -> IO(Unit):
  match requested:
    case True{}: help()
    case False{}: parsed(arguments.parse(1n+List.length(&2,String,xs),xs,Options{root,"build/stress","build/voxel-demo",30,180,30,2048,180,640,360,cases()}))
def normalized(value: Result<&2,&2,String,List<&2,String>>, root: String) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{+xs}: normalized.help(List.any(&2,String,s => String.eq(s,"--help"),xs),xs,root)
def arguments(xs: List<String>) -> IO(Unit):
  match xs:
    case _ <> root <> rest: normalized(normalize(B.shared(rest)),root)
    case _: IO.die(Unit,2,"stress-tool ROOT [OPTIONS]")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
