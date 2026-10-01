import Base
import ./benchmark_metrics.bend as M
import ./megascene_scale.bend as S
import ./schedule_json.bend as J
import ./stress_metrics.bend as N
import ./stress_contract.bend as C

type Options is Data:
  Options{warmup: U32, measured: U32, edit_every: U32, mode: String, check_world: Bool}
type Report is Data:
  Report{passed: Bool, errors: List<&2,String>, fields: List<&2,String>}
type Row is Data:
  Row{tag: String, fields: List<&2,String>}
type Record is Data:
  Record{values: List<&2,S.Integer>}
type Signed is Data:
  Signed{negative: Bool, magnitude: S.Integer}
type Log is Data:
  Log{initial: Signed, surface: Signed, frames: List<&2,Record>, stages: List<&2,Record>, vulkan: List<&2,Record>, edits: List<&2,Record>, cuts: List<&2,Record>, rows: List<&2,Row>}
type View is Data:
  View{camera: String, kind: U32, aim: String}
type Body is Data:
  Body{counts: Record, offset: String}
type Csv is Data:
  Csv{field: String, fields: List<&2,String>, rows: List<&2,Row>, mode: U32, started: Bool}
type WorldCounts is Data:
  WorldCounts{inventory: Record, caches: List<&2,Record>, lods: List<&2,Record>}
type WorldData is Data:
  WorldData{inventory: Record, caches: List<&2,Record>, lods: List<&2,Record>, bodies: List<&2,Body>, errors: List<&2,String>}
type Context is Data:
  Context{fields: List<&2,String>, errors: List<&2,String>}
type Lighting is Data:
  Lighting{refreshes: S.Integer, errors: List<&2,String>}

def map(~A: Data, ~B: Data, ~fn: A -> B, xs: List<&2,A>) -> List<&2,B>:
  match xs:
    case Nil{}: Nil{}
    case h <> rest: fn(h) <> map(A,B,fn,rest)

def require(ok: Bool, message: String) -> Result<&2,&2,String,Unit>:
  match ok:
    case True{}: Done{Unit{}}
    case False{}: Fail{message}
def errors(result: Result<&2,&2,String,Unit>) -> List<&2,String>:
  match result:
    case Done{_}: Nil{}
    case Fail{message}: [message]
def diagnostics(checks: List<&2,Result<&2,&2,String,Unit>>) -> List<&2,String>:
  match checks:
    case Nil{}: Nil{}
    case head <> rest: List.append(&2,String,errors(head),diagnostics(rest))
def invalid(message: String) -> Report: Report{False{},[message],Nil{}}
def add_error(report: Report, message: String) -> Report:
  Report{_,xs,fields} = report
  Report{False{},List.append(&2,String,xs,[message]),fields}
def json(report: Report) -> String:
  Report{passed,errors,fields} = report
  M.object(List.append(&2,String,[J.field("pass",J.boolean(passed)),J.field("errors",J.array(map(String,String,J.quote,errors)))],fields))
def count(-A: Data, xs: List<&2,A>) -> U32: U32.from_nat(List.length(&2,A,xs))
def scalar(n: U32) -> S.Integer: S.Integer.from_u32(32n,n)
def value(row: Record, index: Nat) -> S.Integer:
  Record{values} = row
  Maybe.default(&2,S.Integer,List.get(&2,S.Integer,values,index),S.Integer.zero())
def Record.values(row: Record) -> List<&2,S.Integer>:
  Record{values} = row
  values
def sum(xs: List<&2,S.Integer>) -> S.Integer:
  match xs:
    case Nil{}: S.Integer.zero()
    case h <> rest: S.Integer.add(h,sum(rest))
def column(xs: List<&2,Record>, +index: Nat) -> List<&2,S.Integer>:
  match xs:
    case Nil{}: Nil{}
    case row <> rest: value(row,index) <> column(rest,index)
def maximum(xs: List<&2,S.Integer>) -> S.Integer:
  match xs:
    case Nil{}: S.Integer.zero()
    case +h <> rest:
      +tail = maximum(rest)
      Bool.pick(S.Integer,S.Integer.le(h,tail),tail,h)
def eq(a: Record, b: Record, +index: Nat) -> Bool: S.Integer.eq(value(a,index),value(b,index))
def zero(row: Record, index: Nat) -> Bool: S.Integer.eq(value(row,index),S.Integer.zero())
def row.less(a: Record, b: Record) -> Bool: S.Integer.le(value(a,0n),value(b,0n))
def signed.show(value: Signed) -> String:
  Signed{negative,magnitude} = value
  Bool.pick(String,negative,"-","") ++ S.Integer.show(magnitude)
def number.result(parsed: Maybe<&2,S.Integer>) -> Result<&2,&2,String,S.Integer>:
  match parsed:
    case Some{value}: Done{value}
    case None{}: Fail{"Invalid integer field"}
def number(text: String, bounded: Bool) -> Result<&2,&2,String,S.Integer>:
  do Result<&2,&2,String,S.Integer>:
    +n : S.Integer <- number.result(Maybe.bind(&2,String,S.Integer,M.integer.sign(String.trim(N.normalize(text))),S.Integer.read))
    _ : Unit <- require(Bool.not(bounded) || S.Integer.le(n,scalar(4294967295)),"Integer field exceeds U32")
    return n
def signed.negative(text: String, negative: Bool) -> Result<&2,&2,String,Signed>:
  do Result<&2,&2,String,Signed>:
    +n : S.Integer <- number.result(Maybe.bind(&2,String,S.Integer,M.digits(text,False{}),S.Integer.read))
    return Signed{negative && Bool.not(S.Integer.eq(n,S.Integer.zero())),n}
def signed.trimmed(text: String) -> Result<&2,&2,String,Signed>:
  match text:
    case SCon{'-',rest}: signed.negative(rest,True{})
    case SCon{'+',rest}: signed.negative(rest,False{})
    case rest: signed.negative(rest,False{})
def signed(text: String) -> Result<&2,&2,String,Signed>: signed.trimmed(String.trim(N.normalize(text)))
def numbers(xs: List<&2,String>, +bounded: Bool) -> Result<&2,&2,String,List<&2,S.Integer>>:
  match xs:
    case Nil{}: Done{Nil{}}
    case h <> rest:
      do Result<&2,&2,String,List<&2,S.Integer>>:
        n : S.Integer <- number(h,bounded)
        tail : List<&2,S.Integer> <- numbers(rest,bounded)
        return n <> tail

def csv.row(fields: List<&2,String>) -> Row:
  match fields:
    case tag <> rest: Row{tag,rest}
    case _: Row{"",Nil{}}
def csv.push(field: String, fields: List<&2,String>, rows: List<&2,Row>) -> List<&2,Row>:
  csv.row(List.reverse(&2,String,String.reverse(field) <> fields)) <> rows
def csv.finish(field: String, fields: List<&2,String>, +rows: List<&2,Row>, started: Bool) -> List<&2,Row>:
  List.reverse(&2,Row,Bool.pick(List<&2,Row>,started,csv.push(field,fields,rows),rows))
def csv.end(state: Csv) -> List<&2,Row>:
  Csv{field,fields,rows,_,started} = state
  csv.finish(field,fields,rows,started)
def csv.quote(mode: U32, +field: String, fields: List<&2,String>, rows: List<&2,Row>) -> Csv:
  match mode:
    case 1: Csv{field,fields,rows,2,True{}}
    case 2: Csv{SCon{'"',field},fields,rows,1,True{}}
    case _: Csv{Bool.pick(String,String.is_empty(field),field,SCon{'"',field}),fields,rows,Bool.pick(U32,String.is_empty(field),1,0),True{}}
def csv.separator(mode: U32, c: Char, field: String, fields: List<&2,String>, +rows: List<&2,Row>, started: Bool) -> Csv:
  match mode c:
    case 1 char: Csv{SCon{char,field},fields,rows,1,True{}}
    case _ ',': Csv{"",String.reverse(field) <> fields,rows,0,True{}}
    case _ _: Csv{"",Nil{},Bool.pick(List<&2,Row>,started,csv.push(field,fields,rows),rows),0,False{}}
def csv.step(c: Char, state: Csv) -> Csv:
  match c state:
    case '"' Csv{field,fields,rows,mode,_}: csv.quote(mode,field,fields,rows)
    case ',' Csv{field,fields,rows,mode,started}: csv.separator(mode,',',field,fields,rows,started)
    case '\n' Csv{field,fields,rows,mode,started}: csv.separator(mode,'\n',field,fields,rows,started)
    case '\r' Csv{field,fields,rows,mode,started}: csv.separator(mode,'\r',field,fields,rows,started)
    case char Csv{field,fields,rows,+mode,_}: Csv{SCon{char,field},fields,rows,Bool.pick(U32,U32.is_eq(mode,1),1,0),True{}}
def csv.go(source: String, state: Csv) -> List<&2,Row>:
  match source:
    case SNil{}: csv.end(state)
    case SCon{c,rest}: csv.go(rest,csv.step(c,state))
def csv(source: String) -> List<&2,Row>: csv.go(source,Csv{"",Nil{},Nil{},0,False{}})
def selected(xs: List<&2,Row>, +tag: String) -> List<&2,List<&2,String>>:
  match xs:
    case Nil{}: Nil{}
    case Row{+name,fields} <> rest:
      +tail = selected(rest,tag)
      Bool.pick(List<&2,List<&2,String>>,String.eq(name,tag),fields <> tail,tail)
def latencies(xs: List<&2,Row>) -> List<&2,List<&2,String>>:
  match xs:
    case Nil{}: Nil{}
    case Row{+name,fields} <> rest:
      +tail = latencies(rest)
      Bool.pick(List<&2,List<&2,String>>,String.eq(name,"cut") || String.eq(name,"attempt"),fields <> tail,tail)
def records(xs: List<&2,List<&2,String>>, +width: Nat, +bounded: Bool) -> Result<&2,&2,String,List<&2,Record>>:
  match xs:
    case Nil{}: Done{Nil{}}
    case +fields <> rest:
      do Result<&2,&2,String,List<&2,Record>>:
        _ : Unit <- require(Nat.is_eq(List.length(&2,String,fields),width),"Invalid sample field count")
        values : List<&2,S.Integer> <- numbers(fields,bounded)
        tail : List<&2,Record> <- records(rest,width,bounded)
        return Record{values} <> tail
def special(xs: List<&2,List<&2,String>>, +tag: String) -> Result<&2,&2,String,Signed>:
  match xs:
    case (value <> Nil{}) <> Nil{}: signed(value)
    case _: Fail{"Expected one " ++ tag ++ " row"}
def tags.contains(xs: List<&2,String>, +tag: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case h <> rest: String.eq(h,tag) || tags.contains(rest,tag)
def known(row: Row) -> Bool:
  Row{tag,_} = row
  tags.contains(["init","surface","frame","stage","vulkan_stage","edit","cut","attempt","view","world","mesh_cache","lod_cache","bodies","lighting"],tag)
def log(+rows: List<&2,Row>) -> Result<&2,&2,String,Log>:
  do Result<&2,&2,String,Log>:
    _ : Unit <- require(List.all(&2,Row,known,rows),"Unexpected stress row")
    initial : Signed <- special(selected(rows,"init"),"init")
    surface : Signed <- special(selected(rows,"surface"),"surface")
    frames : List<&2,Record> <- records(selected(rows,"frame"),4n,True{})
    stages : List<&2,Record> <- records(selected(rows,"stage"),9n,True{})
    vulkan : List<&2,Record> <- records(selected(rows,"vulkan_stage"),10n,True{})
    edits : List<&2,Record> <- records(selected(rows,"edit"),8n,True{})
    cuts : List<&2,Record> <- records(latencies(rows),4n,True{})
    return Log{initial,surface,frames,stages,vulkan,edits,cuts,rows}

def edit.signature(row: Record) -> String:
  +row = row
  String.join([S.Integer.show(value(row,1n)),S.Integer.show(value(row,3n)),S.Integer.show(value(row,2n))],",")
def cut.signature(row: Record) -> String:
  +row = row
  String.join([S.Integer.show(value(row,0n)),S.Integer.show(value(row,2n)),S.Integer.show(value(row,3n))],",")
def signatures(~fn: Record -> String, xs: List<&2,Record>) -> String:
  String.join(List.sort(String,String.is_le,map(Record,String,fn,xs)),";")
def edits.at(xs: List<&2,Record>, +end: S.Integer) -> List<&2,Record>:
  match xs:
    case Nil{}: Nil{}
    case +row <> rest:
      +tail = edits.at(rest,end)
      Bool.pick(List<&2,Record>,S.Integer.eq(value(row,0n),end),row <> tail,tail)
def frames.contains(xs: List<&2,Record>, +end: S.Integer) -> Bool:
  match xs:
    case Nil{}: False{}
    case row <> rest: S.Integer.eq(value(row,0n),end) || frames.contains(rest,end)
def edits.owned(xs: List<&2,Record>, +frames: List<&2,Record>) -> Bool:
  match xs:
    case Nil{}: True{}
    case row <> rest: frames.contains(frames,value(row,0n)) && edits.owned(rest,frames)
def edit.sums(+own: List<&2,Record>, +stage: Record) -> Bool:
  S.Integer.eq(sum(column(own,4n)),value(stage,1n)) && S.Integer.eq(sum(column(own,5n)),value(stage,2n)) &&
    S.Integer.eq(sum(column(own,6n)),value(stage,3n)) && S.Integer.eq(sum(column(own,7n)),value(stage,4n))
def intervals(frames: List<&2,Record>, stages: List<&2,Record>, vulkan: List<&2,Record>, +edits: List<&2,Record>, +previous: S.Integer, +index: U32) -> Result<&2,&2,String,Unit>:
  match frames stages vulkan:
    case Nil{} Nil{} Nil{}: Done{Unit{}}
    case +frame <> rest +stage <> stages +vk <> vulkan:
      +end = value(frame,0n)
      do Result<&2,&2,String,Unit>:
        _ : Unit <- require(S.Integer.eq(end,S.Integer.add(previous,value(frame,1n))) && (U32.is_eq(index,0) || Bool.not(S.Integer.eq(end,previous))),"End-to-end interval mismatch")
        _ : Unit <- require(eq(frame,stage,0n),"Frame/stage timestamps do not match")
        _ : Unit <- require(S.Integer.eq(sum(List.drop(&2,S.Integer,Record.values(stage),1n)),value(frame,1n)),"Stage sum mismatch")
        _ : Unit <- require(S.Integer.eq(value(vk,0n),scalar(index)),"Vulkan detail rows do not match frame indices")
        _ : Unit <- require(S.Integer.le(sum(List.drop(&2,S.Integer,Record.values(vk),1n)),value(stage,7n)),"Vulkan detail exceeds frame effect")
        own : List<&2,Record> = edits.at(edits,end)
        _ : Unit <- require(edit.sums(own,stage),"Edit/stage mismatch")
        intervals(rest,stages,vulkan,edits,end,(index + 1 : U32))
    case _ _ _: Fail{"Expected complete frame samples"}
def core(+log: Log, options: Options) -> Result<&2,&2,String,Unit>:
  Log{_,_,+frames,+stages,+vulkan,+edits,+cuts,_} = log
  Options{warmup,measured,_,_,_} = options
  +expected = (warmup + measured : U32)
  do Result<&2,&2,String,Unit>:
    _ : Unit <- require(U32.is_eq(count(Record,frames),expected) && U32.is_eq(count(Record,stages),expected) && U32.is_eq(count(Record,vulkan),expected),"Expected " ++ U32.show(expected) ++ " complete frames")
    _ : Unit <- intervals(frames,List.sort(Record,row.less,stages),List.sort(Record,row.less,vulkan),edits,S.Integer.zero(),0)
    _ : Unit <- require(edits.owned(edits,frames),"Orphan edit")
    _ : Unit <- require(String.eq(signatures(edit.signature,edits),signatures(cut.signature,cuts)),"Edit/latency samples do not match")
    require(List.all(&2,Record,row => S.Integer.eq(value(row,2n),scalar(1)),cuts),"Non-accepted cut row")
def view_only(+mode: String) -> Bool:
  tags.contains(["static","night","camera","aim"],mode)
def late(log: Log, options: Options) -> Result<&2,&2,String,Unit>:
  Log{_,_,frames,_,_,+edits,cuts,_} = log
  Options{warmup,measured,every,_,_} = options
  +expected = C.expected_edits(measured,every)
  do Result<&2,&2,String,Unit>:
    _ : Unit <- require(U32.is_eq(count(Record,edits),expected) && U32.is_eq(count(Record,cuts),expected),"Expected " ++ U32.show(expected) ++ " edits and latency samples")
    _ : Unit <- require(List.all(&2,Record,row => S.Integer.eq(value(row,3n),scalar(1)),edits),"A stress edit was not accepted")
    require(Bool.not(S.Integer.eq(sum(column(List.drop(&2,Record,frames,U32.to_nat(warmup)),1n)),S.Integer.zero())),"No measured frame time")

def float.result(parsed: Maybe<&2,String>) -> Result<&2,&2,String,String>:
  match parsed:
    case Some{value}: Done{value}
    case None{}: Fail{"Invalid finite floating field"}
def floats.join(head: Result<&2,&2,String,String>, tail: Result<&2,&2,String,List<&2,String>>) -> Result<&2,&2,String,List<&2,String>>:
  do Result<&2,&2,String,List<&2,String>>:
    h : String <- head
    t : List<&2,String> <- tail
    return h <> t
def floats(xs: List<&2,String>) -> IO(Result<&2,&2,String,List<&2,String>>):
  match xs:
    case Nil{}: IO.pure(Result<&2,&2,String,List<&2,String>>,Done{Nil{}})
    case h <> rest:
      do IO<Result<&2,&2,String,List<&2,String>>>:
        h : Maybe<&2,String> <- N.literal(h)
        tail : Result<&2,&2,String,List<&2,String>> <- floats(rest)
        return floats.join(float.result(h),tail)
def view.fields(+xs: List<&2,String>, index: U32) -> Result<&2,&2,String,U32>:
  do Result<&2,&2,String,U32>:
    _ : Unit <- require(U32.is_eq(count(String,xs),10),"Invalid view field count")
    frame : S.Integer <- number(M.text(xs,0n),False{})
    +kind : S.Integer <- number(M.text(xs,6n),False{})
    _ : Unit <- require(S.Integer.eq(frame,scalar(index)) && S.Integer.le(kind,scalar(3)),"Invalid view frame index or kind")
    return S.Integer.to_u32(kind)
def view.decoded(values: Result<&2,&2,String,List<&2,String>>, kind: U32, tail: Result<&2,&2,String,List<&2,View>>) -> Result<&2,&2,String,List<&2,View>>:
  do Result<&2,&2,String,List<&2,View>>:
    +values : List<&2,String> <- values
    tail : List<&2,View> <- tail
    return View{String.join(map(String,String,N.identity,List.take(&2,String,values,5n)),"/"),kind,String.join(map(String,String,N.identity,List.drop(&2,String,values,5n)),"/")} <> tail
def views.valid(fields: Result<&2,&2,String,U32>, +xs: List<&2,String>, next: Unit -> IO(Result<&2,&2,String,List<&2,View>>)) -> IO(Result<&2,&2,String,List<&2,View>>):
  match fields:
    case Fail{message}: IO.pure(Result<&2,&2,String,List<&2,View>>,Fail{message})
    case Done{kind}:
      do IO<Result<&2,&2,String,List<&2,View>>>:
        values : Result<&2,&2,String,List<&2,String>> <- floats(List.append(&2,String,List.take(&2,String,List.drop(&2,String,xs,1n),5n),List.drop(&2,String,xs,7n)))
        tail : Result<&2,&2,String,List<&2,View>> <- next(Unit{})
        return view.decoded(values,kind,tail)
def views(xs: List<&2,List<&2,String>>, +index: U32) -> IO(Result<&2,&2,String,List<&2,View>>):
  match xs:
    case Nil{}: IO.pure(Result<&2,&2,String,List<&2,View>>,Done{Nil{}})
    case +fields <> rest: views.valid(view.fields(fields,index),fields,_ => views(rest,(index + 1 : U32)))
def distinct.sorted(xs: List<&2,String>, +previous: String, +started: Bool) -> U32:
  match xs:
    case Nil{}: 0
    case +h <> rest:
      (Bool.to_u32(Bool.not(started) || Bool.not(String.eq(h,previous))) + distinct.sorted(rest,h,True{}) : U32)
def distinct(xs: List<&2,String>) -> U32: distinct.sorted(List.sort(String,String.is_le,xs),"",False{})
def View.camera(v: View) -> String:
  View{camera,_,_} = v
  camera
def View.aim(v: View) -> String:
  View{_,_,aim} = v
  aim
def View.target(v: View) -> Bool:
  View{_,kind,_} = v
  U32.is_ne(kind,0)
def View.preview(v: View) -> Bool:
  View{_,kind,_} = v
  U32.is_eq(kind,1)
def view.workload(mode: String, +cameras: U32, +aims: U32, +target: U32, +preview: U32, required: U32, measured: U32) -> Result<&2,&2,String,Unit>:
  match mode:
    case "camera": require((cameras >= required : U32) && U32.is_eq(target,0),"Camera workload did not move with aim disabled")
    case "aim": require(U32.is_eq(cameras,1) && (aims >= required : U32) && (preview >= (measured / 4 : U32) : U32),"Aim workload did not sweep removable targets with a fixed camera")
    case "carve": require(U32.is_eq(cameras,1) && U32.is_eq(target,0),"Fixed view moved or enabled aim")
    case "night": require(U32.is_eq(cameras,1) && U32.is_eq(target,0),"Fixed view moved or enabled aim")
    case _: Fail{"Unknown view mode"}
def view.summary(result: Result<&2,&2,String,List<&2,View>>, options: Options) -> Result<&2,&2,String,String>:
  Options{+warmup,+measured,_,+mode,_} = options
  do Result<&2,&2,String,String>:
    +xs : List<&2,View> <- result
    _ : Unit <- require(U32.is_eq(count(View,xs),(warmup + measured : U32)),"Expected complete view rows")
    +xs : List<&2,View> = List.drop(&2,View,xs,U32.to_nat(warmup))
    +cameras : U32 = distinct(map(View,String,View.camera,xs))
    +targets : List<&2,View> = List.filter(View,View.target,xs)
    +aims : U32 = distinct(map(View,String,View.aim,targets))
    +target : U32 = count(View,targets)
    +preview : U32 = count(View,List.filter(View,View.preview,xs))
    +required : U32 = U32.min(12,U32.max(2,(measured / 4 : U32)))
    _ : Unit <- view.workload(mode,cameras,aims,target,preview,required,measured)
    return M.object([J.field("camera_positions",U32.show(cameras)),J.field("aim_positions",U32.show(aims)),J.field("target_frames",U32.show(target)),J.field("preview_frames",U32.show(preview))])
def view.check.mode(mode: String, +xs: List<&2,List<&2,String>>, +options: Options) -> IO(Result<&2,&2,String,String>):
  match mode:
    case "static": IO.pure(Result<&2,&2,String,String>,Bool.pick(Result<&2,&2,String,String>,U32.is_eq(count(List<&2,String>,xs),0),Done{"{}"},Fail{"Unexpected view rows for a static case"}))
    case _:
      do IO<Result<&2,&2,String,String>>:
        values : Result<&2,&2,String,List<&2,View>> <- views(xs,0)
        return view.summary(values,options)
def view.check(rows: List<&2,Row>, +options: Options) -> IO(Result<&2,&2,String,String>):
  Options{_,_,_,mode,_} = options
  view.check.mode(mode,selected(rows,"view"),options)

def body.decoded(counts: Result<&2,&2,String,List<&2,S.Integer>>, offset: Maybe<&2,String>) -> Result<&2,&2,String,Body>:
  do Result<&2,&2,String,Body>:
    counts : List<&2,S.Integer> <- counts
    +offset : String <- float.result(offset)
    _ : Unit <- require(String.starts_with(offset,"-") || String.eq(offset,"0x0p+0"),"Invalid body translation")
    return Body{Record{counts},offset}
def bodies.join(head: Result<&2,&2,String,Body>, tail: Result<&2,&2,String,List<&2,Body>>) -> Result<&2,&2,String,List<&2,Body>>:
  do Result<&2,&2,String,List<&2,Body>>:
    h : Body <- head
    t : List<&2,Body> <- tail
    return h <> t
def bodies.row(+fields: List<&2,String>, next: Unit -> IO(Result<&2,&2,String,List<&2,Body>>), valid: Bool) -> IO(Result<&2,&2,String,List<&2,Body>>):
  match valid:
    case False{}: IO.pure(Result<&2,&2,String,List<&2,Body>>,Fail{"Invalid body row width"})
    case True{}:
      do IO<Result<&2,&2,String,List<&2,Body>>>:
        offset : Maybe<&2,String> <- N.literal(M.text(fields,4n))
        tail : Result<&2,&2,String,List<&2,Body>> <- next(Unit{})
        return bodies.join(body.decoded(numbers(List.take(&2,String,fields,4n),False{}),offset),tail)
def bodies(xs: List<&2,List<&2,String>>) -> IO(Result<&2,&2,String,List<&2,Body>>):
  match xs:
    case Nil{}: IO.pure(Result<&2,&2,String,List<&2,Body>>,Done{Nil{}})
    case +fields <> rest: bodies.row(fields,_ => bodies(rest),U32.is_eq(count(String,fields),5))
def Body.counts(body: Body) -> Record:
  Body{counts,_} = body
  counts
def Body.offset(body: Body) -> String:
  Body{_,offset} = body
  offset
def world.inventory(rows: List<&2,Record>) -> Result<&2,&2,String,Record>:
  match rows:
    case +row <> Nil{}:
      do Result<&2,&2,String,Record>:
        _ : Unit <- require(S.Integer.eq(value(row,0n),scalar(803970)) && S.Integer.eq(value(row,1n),scalar(6)) && S.Integer.eq(value(row,2n),scalar(2034)),"World inventory does not match Light Atelier")
        return row
    case _: Fail{"Expected one world inventory"}
def world.frames(frames: List<&2,Record>, caches: List<&2,Record>, lods: List<&2,Record>, bodies: List<&2,Body>, +index: U32) -> Result<&2,&2,String,Unit>:
  match frames caches lods bodies:
    case Nil{} Nil{} Nil{} Nil{}: Done{Unit{}}
    case +frame <> rest +cache <> caches +lod <> lods Body{+body,_} <> bodies:
      do Result<&2,&2,String,Unit>:
        _ : Unit <- require(S.Integer.eq(value(cache,0n),scalar(index)) && S.Integer.eq(value(lod,0n),scalar(index)) && S.Integer.eq(value(body,0n),scalar(index)),"Invalid mesh cache/LOD/body index")
        _ : Unit <- require(S.Integer.eq(S.Integer.add(value(body,1n),value(frame,3n)),value(cache,2n)) && S.Integer.le(value(body,2n),value(frame,3n)) && S.Integer.le(value(body,3n),value(frame,3n)),"Body ownership, anchor or motion counts disagree")
        world.frames(rest,caches,lods,bodies,(index + 1 : U32))
    case _ _ _ _: Fail{"Missing mesh cache, LOD cache or body samples"}
def world.geometry(caches: List<&2,Record>, lods: List<&2,Record>, bodies: List<&2,Body>, +options: Options, +index: U32) -> List<&2,String>:
  match caches lods bodies:
    case +cache <> caches +lod <> lods Body{+body,_} <> bodies:
      Options{warmup,_,every,_,_} = options
      +batch = C.scheduled(index,warmup,every)
      +label = " at frame " ++ U32.show(index)
      List.append(&2,String,diagnostics([
        require(U32.is_eq(index,0) || U32.is_ne(batch,0) || zero(cache,1n),"Unedited geometry rebuilt" ++ label),
        require(U32.is_eq(index,0) || S.Integer.le(value(cache,1n),scalar((batch * 2 : U32))),"An edit rebuilt unrelated body geometry" ++ label),
        require(U32.is_eq(index,0) || U32.is_ne(batch,0) || zero(lod,3n),"Unedited proxy rebuilt" ++ label),
        require(S.Integer.le(value(cache,3n),value(cache,2n)),"Visible body count exceeds live bodies" ++ label),
        require(S.Integer.le(value(lod,1n),value(lod,4n)) && S.Integer.le(value(lod,2n),value(cache,3n)) && S.Integer.le(value(lod,2n),value(body,1n)) &&
          S.Integer.eq(value(lod,4n),S.Integer.add(S.Integer.sub(value(cache,3n),value(lod,2n)),value(lod,1n))) && S.Integer.le(value(lod,5n),value(cache,4n)),"LOD draw, body or vertex counts disagree" ++ label)]),
        world.geometry(caches,lods,bodies,options,(index + 1 : U32)))
    case _ _ _: Nil{}
def world.schedule(frames: List<&2,Record>, +edits: List<&2,Record>, +options: Options, +index: U32) -> Bool:
  match frames:
    case Nil{}: True{}
    case frame <> rest:
      Options{warmup,_,every,_,_} = options
      U32.is_eq(count(Record,edits.at(edits,value(frame,0n))),C.scheduled(index,warmup,every)) &&
        world.schedule(rest,edits,options,(index + 1 : U32))
def world.bounds(frames: List<&2,Record>, +budget: S.Integer, previous: S.Integer) -> List<&2,String>:
  match frames:
    case Nil{}: Nil{}
    case +frame <> rest:
      List.append(&2,String,errors(require(S.Integer.le(value(frame,2n),previous) && S.Integer.le(value(frame,3n),budget),"World gained cells or exceeded the body budget")),
        world.bounds(rest,budget,value(frame,2n)))
def world.final(+frames: List<&2,Record>, options: Options) -> List<&2,String>:
  Options{_,measured,every,+mode,_} = options
  +last = Maybe.default(&2,Record,List.get(&2,Record,List.reverse(&2,Record,frames),0n),Record{Nil{}})
  diagnostics([
    require(U32.is_eq(C.expected_edits(measured,every),0) || Cmp.is_lt(S.Integer.cmp(value(last,2n),scalar(803970))),"Accepted edits did not remove real cells"),
    require(Bool.not(view_only(mode)) || (S.Integer.eq(value(last,2n),scalar(803970)) && zero(last,3n)),"View-only workload mutated the world")])
def world.policy(+frames: List<&2,Record>, caches: List<&2,Record>, lods: List<&2,Record>, bodies: List<&2,Body>, edits: List<&2,Record>, inventory: Record, +options: Options) -> List<&2,String>:
  +inventory = inventory
  List.append(&2,String,world.geometry(caches,lods,bodies,options,0),
    List.append(&2,String,errors(require(world.schedule(frames,edits,options,0),"Edit batches do not match their scheduled frames")),
      List.append(&2,String,world.bounds(frames,value(inventory,3n),value(inventory,0n)),world.final(frames,options))))
def world.counts(+rows: List<&2,Row>) -> Result<&2,&2,String,WorldCounts>:
  do Result<&2,&2,String,WorldCounts>:
    inventory : List<&2,Record> <- records(selected(rows,"world"),4n,False{})
    inventory : Record <- world.inventory(inventory)
    caches : List<&2,Record> <- records(selected(rows,"mesh_cache"),6n,False{})
    lods : List<&2,Record> <- records(selected(rows,"lod_cache"),6n,False{})
    return WorldCounts{inventory,caches,lods}
def world.valid.counts(counts: WorldCounts, +bodies: List<&2,Body>, +frames: List<&2,Record>, edits: List<&2,Record>, +options: Options) -> Result<&2,&2,String,WorldData>:
  WorldCounts{+inventory,+caches,+lods} = counts
  do Result<&2,&2,String,WorldData>:
    _ : Unit <- world.frames(frames,caches,lods,bodies,0)
    return WorldData{inventory,caches,lods,bodies,world.policy(frames,caches,lods,bodies,edits,inventory,options)}
def world.valid(counts: Result<&2,&2,String,WorldCounts>, bodies: Result<&2,&2,String,List<&2,Body>>, frames: List<&2,Record>, edits: List<&2,Record>, options: Options) -> Result<&2,&2,String,WorldData>:
  do Result<&2,&2,String,WorldData>:
    counts : WorldCounts <- counts
    bodies : List<&2,Body> <- bodies
    world.valid.counts(counts,bodies,frames,edits,options)
def field.maximum(name: String, rows: List<&2,Record>, index: Nat) -> String:
  J.field(name,S.Integer.show(maximum(column(rows,index))))
def field.total(name: String, rows: List<&2,Record>, index: Nat) -> String:
  J.field(name,S.Integer.show(sum(column(rows,index))))
def field.mean(name: String, +rows: List<&2,Record>, index: Nat) -> IO(String):
  do IO<String>:
    mean : String <- N.ratio(sum(column(rows,index)),scalar(count(Record,rows)))
    return J.field(name,mean)
def world.summary(result: Result<&2,&2,String,WorldData>, +warmup: U32) -> IO(Context):
  match result:
    case Fail{message}: IO.pure(Context,Context{Nil{},[message]})
    case Done{WorldData{+inventory,caches,lods,+bodies,errors}}:
      +measured_cache = List.drop(&2,Record,caches,U32.to_nat(warmup))
      +measured_lod = List.drop(&2,Record,lods,U32.to_nat(warmup))
      +body_counts = map(Body,Record,Body.counts,bodies)
      do IO<Context>:
        offset : String <- N.minimum(map(Body,String,Body.offset,bodies))
        upload : List<&2,String> <- N.scaled(column(measured_cache,5n),"1048576")
        upload : String <- N.stats(upload,"mib")
        proxied : String <- field.mean("lod_proxied_bodies_mean",measured_lod,2n)
        draws : String <- field.mean("draw_calls_mean",measured_lod,4n)
        visible : String <- field.mean("visible_bodies_mean",measured_cache,3n)
        return Context{[J.field("initial_solid_cells",S.Integer.show(value(inventory,0n))),J.field("initial_assemblies",S.Integer.show(value(inventory,1n))),
          J.field("initial_regions",S.Integer.show(value(inventory,2n))),J.field("body_budget",S.Integer.show(value(inventory,3n))),
          field.maximum("max_moving_bodies",body_counts,2n),field.maximum("max_translated_bodies",body_counts,3n),J.field("minimum_body_offset_m",offset),
          field.total("meshes_rebuilt",measured_cache,1n),J.field("upload_mib",upload),field.maximum("visible_bodies_max",measured_cache,3n),
          field.maximum("lod_proxy_draws_max",measured_lod,1n),field.maximum("lod_proxied_bodies_max",measured_lod,2n),proxied,
          field.total("lod_proxy_rebuilds",measured_lod,3n),field.maximum("draw_calls_max",measured_lod,4n),draws,visible,field.maximum("proxy_vertices_max",measured_lod,5n)],errors}
def world.enabled(check: Bool, +log: Log, +options: Options) -> IO(Context):
  match check:
    case False{}: IO.pure(Context,Context{Nil{},Nil{}})
    case True{}:
      Log{_,_,frames,_,_,edits,_,+rows} = log
      Options{warmup,_,_,_,_} = options
      do IO<Context>:
        bs : Result<&2,&2,String,List<&2,Body>> <- bodies(selected(rows,"bodies"))
        world.summary(world.valid(world.counts(rows),bs,frames,edits,options),warmup)
def world(+log: Log, +options: Options) -> IO(Context):
  Options{_,_,_,_,check} = options
  world.enabled(check,log,options)
def lighting.row(+fields: List<&2,String>, +index: U32, mode: String) -> Result<&2,&2,String,Record>:
  do Result<&2,&2,String,Record>:
    _ : Unit <- require(U32.is_eq(count(String,fields),3),"Invalid lighting field count at row " ++ U32.show(index))
    values : List<&2,S.Integer> <- numbers(fields,False{})
    +row : Record = Record{values}
    _ : Unit <- require(S.Integer.eq(value(row,0n),scalar(index)) && S.Integer.eq(value(row,1n),scalar(Bool.to_u32(String.eq(mode,"night")))) && S.Integer.le(value(row,2n),scalar(1)),"Invalid lighting frame, night mode or shadow refresh at row " ++ U32.show(index))
    return row
def lighting.policy(+row: Record, options: Options, +index: U32) -> List<&2,String>:
  Options{warmup,_,every,mode,_} = options
  diagnostics([
    require((U32.is_ne(index,0) && U32.is_eq(C.scheduled(index,warmup,every),0)) || S.Integer.eq(value(row,2n),scalar(1)),"Shadow map did not refresh for frame " ++ U32.show(index)),
    require(Bool.not(view_only(mode)) || U32.is_eq(index,0) || zero(row,2n),"View-only frame " ++ U32.show(index) ++ " refreshed the shadow map")])
def lighting.accumulate(result: Result<&2,&2,String,Record>, tail: Lighting, options: Options, index: U32) -> Lighting:
  match result:
    case Fail{message}:
      Lighting{refreshes,errors} = tail
      Lighting{refreshes,message <> errors}
    case Done{+row}:
      Lighting{refreshes,errors} = tail
      Lighting{S.Integer.add(value(row,2n),refreshes),List.append(&2,String,lighting.policy(row,options,index),errors)}
def lighting.frames(rows: List<&2,List<&2,String>>, +options: Options, +index: U32) -> Lighting:
  match rows:
    case Nil{}: Lighting{S.Integer.zero(),Nil{}}
    case fields <> rest:
      Options{_,_,_,mode,_} = options
      lighting.accumulate(lighting.row(fields,index,mode),lighting.frames(rest,options,(index + 1 : U32)),options,index)
def lighting.summary(value: Lighting, expected: U32, mode: String) -> Context:
  Lighting{refreshes,errors} = value
  Context{[J.field("night_frames",U32.show(Bool.pick(U32,String.eq(mode,"night"),expected,0))),J.field("shadow_refreshes",S.Integer.show(refreshes))],errors}
def lighting.complete(valid: Bool, rows: List<&2,List<&2,String>>, +options: Options) -> Context:
  match valid:
    case False{}: Context{Nil{},["Expected complete lighting rows"]}
    case True{}:
      Options{warmup,measured,_,mode,_} = options
      lighting.summary(lighting.frames(rows,options,0),(warmup + measured : U32),mode)
def lighting.enabled(check: Bool, +rows: List<&2,Row>, +options: Options) -> Context:
  match check:
    case False{}: Context{Nil{},Nil{}}
    case True{}:
      Options{warmup,measured,_,_,_} = options
      +lights = selected(rows,"lighting")
      lighting.complete(U32.is_eq(count(List<&2,String>,lights),(warmup + measured : U32)),lights,options)
def lighting(+rows: List<&2,Row>, +options: Options) -> Context:
  Options{_,_,_,_,check} = options
  lighting.enabled(check,rows,options)

def stage.names() -> List<&2,String>: ["carving","connectivity","surface_generation","edit_finalization","update_other","scene_preparation","vulkan_frame_effect","overhead"]
def vulkan_stages() -> List<&2,String>: ["bridge_preparation","geometry_generation","fence_wait","vertex_upload","image_acquire","command_recording","submit_and_present","renderer_other","events_and_x11_sync"]
def stage.stats(names: List<&2,String>, +rows: List<&2,Record>, +index: Nat) -> IO(List<&2,String>):
  match names:
    case Nil{}: IO.pure(List<&2,String>,Nil{})
    case name <> rest:
      do IO<List<&2,String>>:
        values : List<&2,String> <- N.scaled(column(rows,index),"1000")
        value : String <- N.stats(values,"ms")
        tail : List<&2,String> <- stage.stats(rest,rows,1n+index)
        return J.field(name,value) <> tail
def signed.ms(value: Signed) -> IO(String):
  Signed{negative,magnitude} = value
  do IO<String>:
    value : String <- N.ratio(magnitude,scalar(1000))
    return Bool.pick(String,negative,"-","") ++ value
def measured(log: Log, options: Options, view: String, +world_fields: List<&2,String>, lighting_fields: List<&2,String>, +errors: List<&2,String>) -> IO(Report):
  Log{initial,surface,+frames,stages,vulkan,+edits,cuts,_} = log
  Options{+warmup,_,_,_,_} = options
  +measured_frames = List.drop(&2,Record,frames,U32.to_nat(warmup))
  +measured_stages = List.drop(&2,Record,stages,U32.to_nat(warmup))
  +measured_vulkan = List.drop(&2,Record,vulkan,U32.to_nat(warmup))
  +total = sum(column(measured_frames,1n))
  +first = Maybe.default(&2,Record,List.get(&2,Record,frames,0n),Record{Nil{}})
  +last = Maybe.default(&2,Record,List.get(&2,Record,List.reverse(&2,Record,frames),0n),Record{Nil{}})
  do IO<Report>:
    initialization : String <- signed.ms(initial)
    seconds : String <- N.ratio(total,scalar(1000000))
    throughput : String <- N.ratio(S.Integer.mul(scalar(count(Record,measured_frames)),scalar(1000000)),total)
    fraction : String <- N.ratio(sum(column(measured_vulkan,5n)),total)
    values : List<&2,String> <- N.scaled(column(measured_frames,1n),"1000")
    frame : String <- N.stats(values,"ms")
    stages : List<&2,String> <- stage.stats(stage.names(),measured_stages,1n)
    vulkan : List<&2,String> <- stage.stats(vulkan_stages(),measured_vulkan,1n)
    values : List<&2,String> <- N.scaled(column(cuts,1n),"1000")
    latency : String <- N.stats(values,"ms")
    fields : List<&2,String> = [J.field("initialization_ms",initialization),J.field("surface_rectangles",signed.show(surface)),
      J.field("solid_cells_start",S.Integer.show(Bool.pick(S.Integer,U32.is_ne(count(String,world_fields),0),scalar(803970),value(first,2n)))),
      J.field("solid_cells_end",S.Integer.show(value(last,2n))),field.maximum("max_bodies",frames,3n),J.field("measured_frames",U32.show(count(Record,measured_frames))),
      J.field("measured_seconds",seconds),J.field("throughput_fps",throughput),J.field("frame",frame),J.field("stages",M.object(stages)),
      J.field("vulkan_stages",M.object(vulkan)),J.field("acquire_wait_fraction",fraction),J.field("view",view),J.field("edits",U32.show(count(Record,edits))),J.field("edit_latency",latency)]
    return Report{U32.is_eq(count(String,errors),0),errors,List.append(&2,String,List.append(&2,String,world_fields,lighting_fields),fields)}
def measured.context.fields(+log: Log, +options: Options, view: String, world: Context, lighting: Context) -> IO(Report):
  Context{world_fields,world_errors} = world
  Context{lighting_fields,lighting_errors} = lighting
  measured(log,options,view,world_fields,lighting_fields,List.append(&2,String,errors(late(log,options)),List.append(&2,String,world_errors,lighting_errors)))
def measured.context(+log: Log, +options: Options, view: String) -> IO(Report):
  Log{_,_,_,_,_,_,_,rows} = log
  do IO<Report>:
    context : Context <- world(log,options)
    measured.context.fields(log,options,view,context,lighting(rows,options))
def process.errors(code: U32) -> List<&2,String>:
  match code:
    case 0: Nil{}
    case _: ["Process exited " ++ U32.show(code)]
def parse.admitted(errors: List<&2,String>, log: Log, options: Options, view: String) -> IO(Report):
  match errors:
    case Nil{}: measured.context(log,options,view)
    case _: IO.pure(Report,Report{False{},errors,Nil{}})
def parse.view(result: Result<&2,&2,String,String>, log: Log, options: Options, core_errors: List<&2,String>, exit_code: U32) -> IO(Report):
  match result:
    case Fail{message}: IO.pure(Report,Report{False{},message <> List.append(&2,String,core_errors,process.errors(exit_code)),Nil{}})
    case Done{view}: parse.admitted(List.append(&2,String,core_errors,process.errors(exit_code)),log,options,view)
def parse.core(result: Result<&2,&2,String,Unit>, +log: Log, +options: Options, exit_code: U32) -> IO(Report):
  Log{_,_,_,_,_,_,_,rows} = log
  do IO<Report>:
    view : Result<&2,&2,String,String> <- view.check(rows,options)
    parse.view(view,log,options,errors(result),exit_code)
def parse.log(result: Result<&2,&2,String,Log>, +options: Options, exit_code: U32) -> IO(Report):
  match result:
    case Fail{message}: IO.pure(Report,Report{False{},message <> process.errors(exit_code),Nil{}})
    case Done{+log}: parse.core(core(log,options),log,options,exit_code)
def options.valid(options: Options) -> Result<&2,&2,String,Unit>:
  Options{+warmup,+measured,_,_,_} = options
  require(((warmup <= 5000) && (measured >= 1) && (measured <= 5000) && (warmup + measured <= 5000) : U32),"Invalid stress frame counts")
def parse.options(result: Result<&2,&2,String,Unit>, source: String, options: Options, exit_code: U32) -> IO(Report):
  match result:
    case Fail{message}: IO.pure(Report,Report{False{},message <> process.errors(exit_code),Nil{}})
    case Done{_}: parse.log(log(csv(source)),options,exit_code)
def parse(source: String, +exit_code: U32, +options: Options) -> IO(Report):
  parse.options(options.valid(options),source,options,exit_code)
