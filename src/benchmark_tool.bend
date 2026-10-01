import Base
import ./benchmark_metrics.bend as M
import ./schedule_json.bend as J
import ./schedule_file.bend as Files
import ./megascene_scale.bend as S

type Options is Data:
  Options{root: String, mode: String, output: String, timeout: U32, runs: U32, threads: List<&2,U32>, binaries: List<&2,String>}
type Run is Data:
  Run{code: U32, out: String, error: String}

def shared(xs: List<String>) -> List<&2,String>:
  match xs:
    case Nil{}: Nil{}
    case x <> rest: x <> shared(rest)
def linear(xs: List<&2,String>) -> List<String>:
  match xs:
    case Nil{}: Nil{}
    case x <> rest: x <> linear(rest)
def write.opened(text: String, value: Result<&1,&1,U32 & String,File>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit,1,"benchmark output unavailable")
    case Done{file}:
      do IO<Unit>:
        value : File & Result<&1,&1,U32 & String,Unit> <- File.write(file,text)
        Files.write.result(value)
def write(path: String, text: String) -> IO(Unit):
  do IO<Unit>:
    file : Result<&1,&1,U32 & String,File> <- File.open(path,"w")
    write.opened(text,file)
def newlines(s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{'\r',SCon{'\n',rest}}: "\n" ++ newlines(rest)
    case SCon{'\r',rest}: "\n" ++ newlines(rest)
    case SCon{c,rest}: SCon{c,newlines(rest)}
def executed(value: Result<&1,&1,U32 & String,U32 & (String & String)>) -> IO(Run):
  match value:
    case Fail{(_,message)}: IO.die(Run,1,message)
    case Done{(code,(out,error))}: IO.pure(Run,Run{code,out,error})
def run.text(run: Run) -> Run:
  Run{code,out,error} = run
  Run{code,newlines(out),newlines(error)}
def command(args: List<&2,String>, maximum: U32, timeout: U32) -> IO(Run):
  do IO<Run>:
    value : Result<&1,&1,U32 & String,U32 & (String & String)> <- Process.run("env",linear(args),"",maximum,timeout)
    executed(value)
def successful(value: Run) -> IO(String):
  match value:
    case Run{0,out,_}: IO.pure(String,out)
    case Run{_,_,error}: IO.die(String,1,error)
def system(args: List<&2,String>) -> IO(String):
  do IO<String>:
    run : Run <- command(args,1048576,10000)
    successful(run)
def cwd(root: String, args: List<&2,String>) -> List<&2,String>: ("--chdir=" ++ root) <> args
def path.components(xs: List<&2,String>) -> List<&2,String>:
  match xs:
    case Nil{}: Nil{}
    case "" <> rest: path.components(rest)
    case "." <> rest: path.components(rest)
    case h <> rest: h <> path.components(rest)
def path.clean(+s: String) -> String:
  +tail = String.join(path.components(String.split(s,'/')),"/")
  Bool.pick(String,String.starts_with(s,"/"),"/" ++ tail,Bool.pick(String,String.is_empty(tail),".",tail))
def path.parts(root: String, name: String, absolute: Bool) -> String:
  match absolute:
    case True{}: path.clean(name)
    case False{}: path.clean(root ++ "/" ++ name)
def path(+root: String, +name: String) -> String: path.parts(root,name,String.starts_with(name,"/"))
def trim(s: String) -> String: String.trim(s)
def mkdir(name: String) -> IO(Unit):
  do IO<Unit>:
    _ : String <- system(["mkdir","-p","--",name])
    return Unit{}
def hash(name: String) -> IO(String):
  do IO<String>:
    result : String <- system(["sha256sum","-z","--",name])
    return String.take(result,64n)
def positive(value: U32) -> Result<&2,&2,String,U32>:
  match value:
    case 0: Fail{"positive argument required"}
    case _: Done{value}
def option.unique(xs: List<&2,String>) -> Result<&2,&2,String,String>:
  match xs:
    case h <> Nil{}: Done{h}
    case _: Fail{"unknown or ambiguous benchmark option"}
def option.matches(keys: List<&2,String>, +name: String) -> List<&2,String>:
  match keys:
    case Nil{}: Nil{}
    case +key <> rest:
      +tail = option.matches(rest,name)
      Bool.pick(List<&2,String>,String.starts_with(key,name),key <> tail,tail)
def option.parts(parts: List<&2,String>, +mode: String) -> Result<&2,&2,String,List<&2,String>>:
  match parts:
    case +name <> +rest:
      do Result<&2,&2,String,List<&2,String>>:
        keys : List<&2,String> = Bool.pick(List<&2,String>,String.eq(mode,"faces"),["--output","--timeout","--help"],["--output","--timeout","--runs","--threads","--help"])
        name : String <- option.unique(option.matches(keys,name))
        return name <> Bool.pick(List<&2,String>,Nat.is_eq(List.length(&2,String,rest),0n),Nil{},[String.join(rest,"=")])
    case _: Fail{"invalid benchmark option"}
def option(+s: String, mode: String) -> Result<&2,&2,String,List<&2,String>>:
  match s:
    case "-h": Done{["--help"]}
    case SCon{'-',SCon{'-',_}}: option.parts(String.split(s,'='),mode)
    case _: Done{[s]}
def options(xs: List<&2,String>, +mode: String) -> Result<&2,&2,String,List<&2,String>>:
  match xs:
    case Nil{}: Done{Nil{}}
    case "--" <> rest: Done{"--" <> rest}
    case h <> rest:
      do Result<&2,&2,String,List<&2,String>>:
        h : List<&2,String> <- option(h,mode)
        tail : List<&2,String> <- options(rest,mode)
        return List.append(&2,String,h,tail)
def require(ok: Bool) -> Result<&2,&2,String,Unit>:
  match ok:
    case True{}: Done{Unit{}}
    case False{}: Fail{"invalid benchmark arguments"}
def arguments.finish(+options: Options) -> Result<&2,&2,String,Options>:
  Options{_,+mode,_,+timeout,+runs,threads,binaries} = options
  do Result<&2,&2,String,Options>:
    _ : Unit <- require(((timeout >= 1) && (timeout <= 4294967) && (runs >= 2) : U32))
    _ : Unit <- require(Bool.pick(Bool,String.eq(mode,"faces"),Nat.is_eq(List.length(&2,String,binaries),0n),Nat.is_eq(List.length(&2,String,binaries),2n)))
    _ : Unit <- require(Bool.not(Nat.is_eq(List.length(&2,U32,threads),0n)))
    return options
def arguments.threads.end(+values: List<&2,U32>, rest: List<&2,String>, next: List<&2,U32> -> List<&2,String> -> Result<&2,&2,String,Options>) -> Result<&2,&2,String,Options>:
  do Result<&2,&2,String,Options>:
    _ : Unit <- require(Bool.not(Nat.is_eq(List.length(&2,U32,values),0n)))
    next(values,rest)
def arguments.threads(xs: List<&2,String>, +acc: List<&2,U32>, next: List<&2,U32> -> List<&2,String> -> Result<&2,&2,String,Options>) -> Result<&2,&2,String,Options>:
  match xs:
    case Nil{}: arguments.threads.end(List.reverse(&2,U32,acc),Nil{},next)
    case "--output" <> rest: arguments.threads.end(List.reverse(&2,U32,acc),"--output" <> rest,next)
    case "--timeout" <> rest: arguments.threads.end(List.reverse(&2,U32,acc),"--timeout" <> rest,next)
    case "--runs" <> rest: arguments.threads.end(List.reverse(&2,U32,acc),"--runs" <> rest,next)
    case "--threads" <> rest: arguments.threads.end(List.reverse(&2,U32,acc),"--threads" <> rest,next)
    case "--" <> rest: arguments.threads.end(List.reverse(&2,U32,acc),"--" <> rest,next)
    case +h <> rest:
      do Result<&2,&2,String,Options>:
        h : U32 <- M.argument(h)
        h : U32 <- positive(h)
        arguments.threads(rest,h <> acc,next)
def arguments.parse.fields(fuel: Nat, xs: List<&2,String>, +root: String, +mode: String, +out: String, +timeout: U32, +runs: U32, +threads: List<&2,U32>, +binaries: List<&2,String>) -> Result<&2,&2,String,Options>:
  match fuel xs:
    case _ Nil{}: arguments.finish(Options{root,mode,out,timeout,runs,threads,binaries})
    case 0n _: Fail{"invalid benchmark arguments"}
    case 1n+p "--" <> rest: arguments.finish(Options{root,mode,out,timeout,runs,threads,List.append(&2,String,binaries,rest)})
    case 1n+p "--output" <> name <> rest: arguments.parse.fields(p,rest,root,mode,name,timeout,runs,threads,binaries)
    case 1n+p "--timeout" <> value <> rest:
      do Result<&2,&2,String,Options>:
        value : U32 <- M.argument(value)
        arguments.parse.fields(p,rest,root,mode,out,value,runs,threads,binaries)
    case 1n+p "--runs" <> value <> rest:
      do Result<&2,&2,String,Options>:
        _ : Unit <- require(String.eq(mode,"parallel"))
        value : U32 <- M.argument(value)
        arguments.parse.fields(p,rest,root,mode,out,timeout,value,threads,binaries)
    case 1n+p "--threads" <> rest:
      do Result<&2,&2,String,Options>:
        _ : Unit <- require(String.eq(mode,"parallel"))
        arguments.threads(rest,Nil{},values => rest => arguments.parse.fields(p,rest,root,mode,out,timeout,runs,values,binaries))
    case 1n+p +name <> rest:
      do Result<&2,&2,String,Options>:
        _ : Unit <- require(String.eq(mode,"parallel") && Bool.not(String.starts_with(name,"-")))
        arguments.parse.fields(p,rest,root,mode,out,timeout,runs,threads,List.append(&2,String,binaries,[name]))
def arguments.parse(+xs: List<&2,String>, options: Options) -> Result<&2,&2,String,Options>:
  Options{root,mode,out,timeout,runs,threads,binaries} = options
  arguments.parse.fields(1n+List.length(&2,String,xs),xs,root,mode,out,timeout,runs,threads,binaries)

def fields.hashes(+root: String, names: List<&2,String>) -> IO(List<&2,String>):
  match names:
    case Nil{}: IO.pure(List<&2,String>,Nil{})
    case "" <> rest: fields.hashes(root,rest)
    case +name <> rest:
      do IO<List<&2,String>>:
        digest : String <- hash(path(root,name))
        tail : List<&2,String> <- fields.hashes(root,rest)
        return J.field(name,J.quote(digest)) <> tail
def source.hashes(+root: String, folder: String) -> IO(List<&2,String>):
  do IO<List<&2,String>>:
    names : String <- system(cwd(root,["find",folder,"-xtype","f","-not","-path","*/__pycache__/*","-not","-path","*/__pycache__","-print0"]))
    fields.hashes(root,List.sort(String,String.is_le,String.split(names,Chr{0})))
def metadata(+root: String, version: String) -> IO(String):
  do IO<String>:
    date : String <- system(["date","+%Y-%m-%dT%H:%M:%S%z"])
    revision : String <- system(cwd(root,["git","rev-parse","HEAD"]))
    dirty : String <- system(cwd(root,["git","status","--porcelain"]))
    src : List<&2,String> <- source.hashes(root,"src")
    scripts : List<&2,String> <- source.hashes(root,"scripts")
    return M.object([J.field("date",J.quote(trim(date))),J.field("bend",J.quote(version)),J.field("git_revision",J.quote(trim(revision))),
      J.field("working_tree_dirty",J.boolean(Bool.not(String.is_empty(dirty)))),J.field("source_sha256",M.object(List.append(&2,String,src,scripts))),
      J.field("timing_scope",J.quote("Headless CPU Bend edit stages use the production local face builder and construct cached Bend vertices. The counted full-face diagnostic runs after each timed edit; audit_ms is separate and should not be added to surface_ms.")),
      J.field("count_scope",J.quote("tree_nodes counts visited tree nodes including pruned nodes; cuboid_candidates counts reached leaves; face_checks counts face.covered calls; face_clips counts face.subtract calls. output_faces counts the full diagnostic rebuild and reference_faces counts the local production rebuild. Their surface coverage, sides, and materials are checked for equivalence; rectangle counts may differ."))])

def scope() -> String: "Initialization and sums over six production Atelier edits; full-face correctness audits run outside timed stages."
def profile.header(xs: List<&2,String>, rest: String, next: String -> String -> IO(M.Sample)) -> IO(M.Sample):
  match xs:
    case "init" <> init <> Nil{}: next(rest,init)
    case _: IO.die(M.Sample,1,"Invalid initialization row")
def profile.input(xs: List<&2,String>, next: String -> String -> IO(M.Sample)) -> IO(M.Sample):
  match xs:
    case first <> rest: profile.header(String.split(first,','),String.join(rest,"\n"),next)
    case _: IO.die(M.Sample,1,"Invalid initialization row")
def profile.parse(rest: String, init: String) -> IO(M.Sample):
  do IO<M.Sample>:
    cuts : List<&2,M.Cut> <- M.parse(rest)
    M.sample(cuts,init)
def profile.saved(run: Run, +output: String) -> IO(M.Sample):
  Run{code,+out,+error} = run
  do IO<M.Sample>:
    write(output ++ ".csv",out)
    write(output ++ ".stderr",error)
    out : String <- successful(Run{code,out,error})
    profile.input(String.lines(out),profile.parse)
def profile(+root: String, binary: String, threads: U32, +output: String, timeout: U32) -> IO(M.Sample):
  do IO<M.Sample>:
    run : Run <- command(cwd(root,[binary,"--threads",U32.show(threads),"--gpu","off"]),1048576,(1000 * timeout : U32))
    profile.saved(run.text(run),output)

def indent(n: Nat) -> String: String.repeat("  ",n)
def layout(s: String, +depth: Nat, quoted: Bool, escaped: Bool, +pretty: Bool) -> String:
  match s quoted escaped:
    case SNil{} _ _: ""
    case SCon{c,rest} True{} True{}: SCon{c,SNil{}} ++ layout(rest,depth,True{},False{},pretty)
    case SCon{'"',rest} +q _: "\"" ++ layout(rest,depth,Bool.not(q),False{},pretty)
    case SCon{'\\',rest} True{} _: "\\" ++ layout(rest,depth,True{},True{},pretty)
    case SCon{c,rest} True{} _: SCon{c,SNil{}} ++ layout(rest,depth,True{},False{},pretty)
    case SCon{'{',SCon{'}',rest}} _ _: "{}" ++ layout(rest,depth,False{},False{},pretty)
    case SCon{'[',SCon{']',rest}} _ _: "[]" ++ layout(rest,depth,False{},False{},pretty)
    case SCon{'{',rest} _ _: "{" ++ Bool.pick(String,pretty,"\n" ++ indent(1n+depth),"") ++ layout(rest,1n+depth,False{},False{},pretty)
    case SCon{'[',rest} _ _: "[" ++ Bool.pick(String,pretty,"\n" ++ indent(1n+depth),"") ++ layout(rest,1n+depth,False{},False{},pretty)
    case SCon{'}',rest} _ _: Bool.pick(String,pretty,"\n" ++ indent(Nat.sub(depth,1n)),"") ++ "}" ++ layout(rest,Nat.sub(depth,1n),False{},False{},pretty)
    case SCon{']',rest} _ _: Bool.pick(String,pretty,"\n" ++ indent(Nat.sub(depth,1n)),"") ++ "]" ++ layout(rest,Nat.sub(depth,1n),False{},False{},pretty)
    case SCon{',',rest} _ _: "," ++ Bool.pick(String,pretty,"\n" ++ indent(depth)," ") ++ layout(rest,depth,False{},False{},pretty)
    case SCon{':',rest} _ _: ": " ++ layout(rest,depth,False{},False{},pretty)
    case SCon{c,rest} _ _: SCon{c,SNil{}} ++ layout(rest,depth,False{},False{},pretty)
def report(s: String) -> String: layout(s,0n,False{},False{},True{}) ++ "\n"
def message(s: String) -> String: layout(s,0n,False{},False{},False{})
def signature.words(xs: List<&2,U32>) -> String:
  match xs:
    case Nil{}: ""
    case x <> rest: U32.show(x) ++ "," ++ signature.words(rest)
def signature(cuts: List<&2,M.Cut>) -> String:
  match cuts:
    case Nil{}: ""
    case M.Cut{+counts} <> rest:
      signature.words(List.append(&2,U32,List.take(&2,U32,counts,3n),List.drop(&2,U32,counts,8n))) ++ ";" ++ signature(rest)
def signature.cuts(value: M.Sample) -> String:
  M.Sample{cuts,_} = value
  signature(cuts)
def signature.require(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,"Baseline/candidate correctness counters differ")
def signature.check(reference: Maybe<&2,String>, actual: String) -> IO(String):
  match reference:
    case None{}: IO.pure(String,actual)
    case Some{+expected}:
      do IO<String>:
        _ : Unit <- signature.require(String.eq(expected,actual))
        return expected
def stage.samples(xs: List<&2,M.Sample>, +i: Nat) -> List<&2,String>:
  match xs:
    case Nil{}: Nil{}
    case M.Sample{_,ms} <> rest: M.text(ms,i) <> stage.samples(rest,i)
def stage.medians(n: Nat, +i: Nat, +xs: List<&2,M.Sample>) -> IO(List<&2,String>):
  match n:
    case 0n: IO.pure(List<&2,String>,Nil{})
    case 1n+p:
      do IO<List<&2,String>>:
        value : String <- M.median(stage.samples(xs,i))
        tail : List<&2,String> <- stage.medians(p,1n+i,xs)
        return value <> tail
def samples.json(xs: List<&2,M.Sample>) -> IO(List<&2,String>):
  match xs:
    case Nil{}: IO.pure(List<&2,String>,Nil{})
    case h <> rest:
      do IO<List<&2,String>>:
        h : String <- M.sample.json(h)
        rest : List<&2,String> <- samples.json(rest)
        return h <> rest
def medians.json(xs: List<&2,M.Sample>) -> IO(String):
  do IO<String>:
    values : List<&2,String> <- stage.medians(6n,0n,xs)
    fields : List<&2,String> <- M.float.fields(M.stages(),values)
    return M.object(fields)
def pair.ordered(first: U32, a: M.Sample, b: M.Sample) -> M.Sample & M.Sample:
  match first:
    case 0: (a,b)
    case _: (b,a)
def prefix(+output: String, thread: U32, name: String, iteration: String) -> String:
  output ++ "/t" ++ U32.show(thread) ++ "-" ++ name ++ "-" ++ iteration
def pair(options: Options, +thread: U32, +index: U32, +reference: String) -> IO(M.Sample & M.Sample):
  Options{+root,_,+output,+timeout,_,_,+binaries} = options
  +first = (index % 2 : U32)
  +second = (1 - first : U32)
  do IO<M.Sample & M.Sample>:
    +a : M.Sample <- profile(root,M.text(binaries,U32.to_nat(first)),thread,prefix(output,thread,Bool.pick(String,U32.is_eq(first,0),"baseline","candidate"),U32.show(index)),timeout)
    _ : String <- signature.check(Some{reference},signature.cuts(a))
    +b : M.Sample <- profile(root,M.text(binaries,U32.to_nat(second)),thread,prefix(output,thread,Bool.pick(String,U32.is_eq(second,0),"baseline","candidate"),U32.show(index)),timeout)
    _ : String <- signature.check(Some{reference},signature.cuts(b))
    return pair.ordered(first,a,b)
def measured.next(value: M.Sample & M.Sample, a: List<&2,M.Sample>, b: List<&2,M.Sample>, next: List<&2,M.Sample> -> List<&2,M.Sample> -> IO(List<&2,M.Sample> & List<&2,M.Sample>)) -> IO(List<&2,M.Sample> & List<&2,M.Sample>):
  (x,y) = value
  next(x <> a,y <> b)
def measured(n: Nat, +index: U32, +options: Options, +thread: U32, +reference: String, a: List<&2,M.Sample>, b: List<&2,M.Sample>) -> IO(List<&2,M.Sample> & List<&2,M.Sample>):
  match n:
    case 0n: IO.pure(List<&2,M.Sample> & List<&2,M.Sample>,(List.reverse(&2,M.Sample,a),List.reverse(&2,M.Sample,b)))
    case 1n+p:
      do IO<List<&2,M.Sample> & List<&2,M.Sample>>:
        values : M.Sample & M.Sample <- pair(options,thread,index,reference)
        measured.next(values,a,b,a => b => measured(p,(index + 1 : U32),options,thread,reference,a,b))
def group.json(values: List<&2,M.Sample> & List<&2,M.Sample>) -> IO(String & String):
  (+a,+b) = values
  do IO<String & String>:
    am : String <- medians.json(a)
    bm : String <- medians.json(b)
    aj : List<&2,String> <- samples.json(a)
    bj : List<&2,String> <- samples.json(b)
    +medians : String = M.object([J.field("baseline",am),J.field("candidate",bm)])
    return (M.object([J.field("samples",M.object([J.field("baseline",J.array(aj)),J.field("candidate",J.array(bj))])),J.field("median_ms",medians)]),medians)

def exhibit.counts(cuts: List<&2,M.Cut>, +index: U32, +field: Nat) -> S.Integer:
  match cuts:
    case Nil{}: S.Integer.zero()
    case M.Cut{+counts} <> rest:
      S.Integer.add(S.Integer.from_u32(32n,Bool.pick(U32,U32.is_eq((M.get(counts,0n) % 3 : U32),index),M.get(counts,field),0)),exhibit.counts(rest,index,field))
def exhibit.times(cuts: List<&2,M.Cut>, +index: U32) -> List<&2,String>:
  match cuts:
    case Nil{}: Nil{}
    case M.Cut{+counts} <> rest:
      +tail = exhibit.times(rest,index)
      Bool.pick(List<&2,String>,U32.is_eq((M.get(counts,0n) % 3 : U32),index),M.milliseconds(M.get(counts,5n)) <> tail,tail)
def exhibits(n: Nat, +index: U32, +cuts: List<&2,M.Cut>) -> IO(List<&2,String>):
  match n:
    case 0n: IO.pure(List<&2,String>,Nil{})
    case 1n+p:
      do IO<List<&2,String>>:
        value : String <- M.sum(exhibit.times(cuts,index))
        value : String <- M.decimal(value)
        tail : List<&2,String> <- exhibits(p,(index + 1 : U32),cuts)
        return J.field(M.exhibit(index),M.object([J.field("surface_ms_total",value),J.field("face_checks_total",S.Integer.show(exhibit.counts(cuts,index,12n))),J.field("face_clips_total",S.Integer.show(exhibit.counts(cuts,index,13n)))])) <> tail
def console(cuts: List<&2,M.Cut>) -> IO(Unit):
  match cuts:
    case Nil{}: IO.pure(Unit,Unit{})
    case M.Cut{+c} <> rest:
      do IO<Unit>:
        IO.print(M.exhibit(M.get(c,0n)) ++ " cut " ++ U32.show((M.get(c,0n) / 3 + 1 : U32)) ++ ": surface " ++ U32.show((M.get(c,5n) / 1000 : U32)) ++ "." ++ M.pad3((M.get(c,5n) % 1000 : U32)) ++ " ms, " ++
          U32.show(M.get(c,8n)) ++ " cuboids, " ++ U32.show(M.get(c,12n)) ++ " face checks, " ++ U32.show(M.get(c,13n)) ++ " clips, " ++ U32.show(M.get(c,15n)) ++ " local faces (" ++ U32.show(M.get(c,14n)) ++ " full rebuild)")
        console(rest)
def faces.saved(+root: String, +out: String, version: String, run: Run) -> IO(Unit):
  Run{code,+csv,+error} = run
  do IO<Unit>:
    write(path(out,"raw.csv"),"tag," ++ String.join(M.names(),",") ++ "\n" ++ csv)
    write(path(out,"stderr.log"),error)
    csv : String <- successful(Run{code,csv,error})
    +cuts : List<&2,M.Cut> <- M.parse(csv)
    metadata : String <- metadata(root,version)
    groups : List<&2,String> <- exhibits(3n,0,cuts)
    write(path(out,"report.json"),report(M.object([J.field("metadata",metadata),J.field("cuts",J.array(M.cuts.json(cuts))),J.field("exhibits",M.object(groups)),J.field("pass","true")])))
    console(cuts)
    IO.print("Report: " ++ path(out,"report.json"))
def faces.ready(options: Options, version: String) -> IO(Unit):
  Options{+root,_,output,+timeout,_,_,_} = options
  +out = path(root,output)
  +binary = root ++ "/build/atelier-face-profile"
  do IO<Unit>:
    mkdir(out)
    mkdir(root ++ "/build")
    _ : String <- system(["rm","-f","--",binary])
    compiled : Run <- command("-u" <> "CUDA_HOME" <> cwd(root,["bend","src/face_profile.bend","-o",binary]),1048576,(1000 * timeout : U32))
    _ : String <- successful(compiled)
    run : Run <- command("-u" <> "CUDA_HOME" <> cwd(root,[binary]),1048576,(1000 * timeout : U32))
    faces.saved(root,out,version,run.text(run))
def faces.version(options: Options, version: String) -> IO(Unit):
  match version:
    case "bend 2.0.34": faces.ready(options,"bend 2.0.34")
    case _: IO.die(Unit,2,"this benchmark requires Bend 2.0.34")
def faces(options: Options) -> IO(Unit):
  do IO<Unit>:
    version : String <- system(["bend","version"])
    faces.version(options,trim(version))

def parallel.document(binaries: String, runs: U32, threads: List<&2,String>) -> String:
  M.object([J.field("binaries",binaries),J.field("runs",U32.show(runs)),J.field("scope",J.quote(scope())),J.field("threads",M.object(threads))])
def replace.field(+prefix: String, +value: String, fields: List<&2,String>) -> List<&2,String>:
  match fields:
    case Nil{}: [value]
    case +h <> +rest: Bool.pick(List<&2,String>,String.starts_with(h,prefix),value <> rest,h <> replace.field(prefix,value,rest))
def group.saved(value: String & String, options: Options, +thread: U32, binaries: String, fields: List<&2,String>) -> IO(List<&2,String>):
  (group,medians) = value
  Options{_,_,output,_,runs,_,_} = options
  +fields = replace.field(J.quote(U32.show(thread)) ++ ":",J.field(U32.show(thread),group),fields)
  do IO<List<&2,String>>:
    IO.print(message(M.object([J.field("threads",U32.show(thread)),J.field("median_ms",medians)])))
    write(output ++ "/report.json",report(parallel.document(binaries,runs,fields)))
    return fields
def parallel.threads(todo: List<&2,U32>, +options: Options, reference: Maybe<&2,String>, +bins: String, fields: List<&2,String>) -> IO(Unit):
  match todo:
    case Nil{}: IO.pure(Unit,Unit{})
    case +thread <> rest:
      Options{+root,_,+output,+timeout,+runs,_,+binaries} = options
      do IO<Unit>:
        base : M.Sample <- profile(root,M.text(binaries,0n),thread,prefix(output,thread,"baseline","warmup"),timeout)
        +reference : String <- signature.check(reference,signature.cuts(base))
        candidate : M.Sample <- profile(root,M.text(binaries,1n),thread,prefix(output,thread,"candidate","warmup"),timeout)
        _ : String <- signature.check(Some{reference},signature.cuts(candidate))
        values : List<&2,M.Sample> & List<&2,M.Sample> <- measured(U32.to_nat(runs),0,options,thread,reference,Nil{},Nil{})
        group : String & String <- group.json(values)
        fields : List<&2,String> <- group.saved(group,options,thread,bins,fields)
        parallel.threads(rest,options,Some{reference},bins,fields)
def parallel.resolved(options: Options, baseline: String, candidate: String) -> IO(Unit):
  Options{root,_,output,timeout,runs,+threads,_} = options
  do IO<Unit>:
    +baseline : String <- system(["realpath","-m","--",baseline])
    +candidate : String <- system(["realpath","-m","--",candidate])
    +output : String <- system(["realpath","-m","--",output])
    +baseline : String = trim(baseline)
    +candidate : String = trim(candidate)
    +output : String = trim(output)
    mkdir(output)
    a : String <- hash(baseline)
    b : String <- hash(candidate)
    info : String = M.object([J.field("baseline",M.object([J.field("path",J.quote(baseline)),J.field("sha256",J.quote(a))])),J.field("candidate",M.object([J.field("path",J.quote(candidate)),J.field("sha256",J.quote(b))]))])
    parallel.threads(threads,Options{root,"parallel",output,timeout,runs,threads,[baseline,candidate]},None{},info,Nil{})
def parallel.paths(options: Options, paths: List<&2,String>) -> IO(Unit):
  match paths:
    case baseline <> candidate <> Nil{}: parallel.resolved(options,baseline,candidate)
    case _: IO.die(Unit,2,"expected baseline and candidate")
def parallel(+options: Options) -> IO(Unit):
  Options{_,_,_,_,_,_,paths} = options
  parallel.paths(options,paths)
def execute.mode(mode: String, options: Options) -> IO(Unit):
  match mode:
    case "faces": faces(options)
    case "parallel": parallel(options)
    case _: IO.die(Unit,2,"expected faces or parallel")
def execute(+options: Options) -> IO(Unit):
  Options{_,mode,_,_,_,_,_} = options
  execute.mode(mode,options)
def help(mode: String) -> IO(Unit):
  IO.print(Bool.pick(String,String.eq(mode,"faces"),"usage: benchmark_faces.sh [--output OUTPUT] [--timeout TIMEOUT]\nProfile face-builder work for the six fixed Light Atelier cuts.","usage: benchmark_parallel.sh BASELINE CANDIDATE [--runs RUNS] [--threads N ...] [--timeout TIMEOUT] [--output OUTPUT]\nCompare two builds of tests/parallel-profile.bend in alternating order."))
def parsed(value: Result<&2,&2,String,Options>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{options}: execute(options)
def normalized.help(requested: Bool, xs: List<&2,String>, +root: String, +mode: String) -> IO(Unit):
  match requested:
    case True{}: help(mode)
    case False{}: parsed(arguments.parse(xs,Options{root,mode,Bool.pick(String,String.eq(mode,"faces"),"build/faces","build/parallel"),180,4,[1,6,12],Nil{}}))
def normalized(result: Result<&2,&2,String,List<&2,String>>, root: String, +mode: String) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{+xs}: normalized.help(List.any(&2,String,s => String.eq(s,"--help"),xs),xs,root,mode)
def arguments(args: List<String>) -> IO(Unit):
  match args:
    case _ <> +root <> +mode <> rest: normalized(options(shared(rest),mode),root,mode)
    case _: IO.die(Unit,2,"benchmark-tool ROOT faces|parallel [OPTIONS]")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
