import Base
import ./megascene_admission.bend as Admission
import ./megascene_scale.bend as Scale

type ParsedBoxes is Data:
  ParsedBoxes{boxes: List<&2,Admission.ExactBox>, rest: List<&2,String>}

def invalid(-A: Data) -> Result<&2,&2,String,A>:
  Fail{"invalid admission input"}

def tokens.go(s: String, current: String, acc: List<&2,String>) -> Result<&2,&2,String,List<&2,String>>:
  match s current:
    case SNil{} SNil{}: invalid(List<&2,String>)
    case SNil{} SCon{h,t}: Done{List.reverse(&2,String,String.reverse(SCon{h,t}) <> acc)}
    case SCon{Chr{32},rest} SNil{}: invalid(List<&2,String>)
    case SCon{Chr{32},rest} SCon{h,t}: tokens.go(rest,SNil{},String.reverse(SCon{h,t}) <> acc)
    case SCon{h,rest} current: tokens.go(rest,SCon{h,current},acc)

def magnitude.digit(acc: Scale.Integer, +c: U32, ok: Bool,
    next: Scale.Integer -> Result<&2,&2,String,Scale.Integer>) -> Result<&2,&2,String,Scale.Integer>:
  match ok:
    case False{}: invalid(Scale.Integer)
    case True{}: next(Scale.Integer.add(Scale.Integer.mul(acc,Scale.Integer.ten()),
      Scale.Integer.from_u32(4n,(c - 48 : U32))))

def magnitude.go(text: String, acc: Scale.Integer) -> Result<&2,&2,String,Scale.Integer>:
  match text:
    case SNil{}: Done{acc}
    case SCon{Chr{+c},rest}: magnitude.digit(acc,c,((c >= 48) && (c <= 57) : U32),
      acc => magnitude.go(rest,acc))

def magnitude.valid(text: String, ok: Bool) -> Result<&2,&2,String,Scale.Integer>:
  match ok:
    case False{}: invalid(Scale.Integer)
    case True{}: magnitude.go(text,Scale.Integer.zero())

def magnitude(+text: String) -> Result<&2,&2,String,Scale.Integer>:
  match text:
    case "0": Done{Scale.Integer.zero()}
    case SCon{Chr{+c},_}:
      magnitude.valid(text,((c >= 49) && (c <= 57) : U32))
    case _: invalid(Scale.Integer)

def integer(text: String) -> Result<&2,&2,String,Admission.Integer>:
  match text:
    case SCon{Chr{45},rest}:
      do Result<&2,&2,String,Admission.Integer>:
        +n : Scale.Integer <- magnitude(rest)
        _ : Unit <- Admission.require(Unit,Bool.not(Scale.Integer.eq(n,Scale.Integer.zero())),
          "invalid admission input",Unit{})
        return Admission.Integer{True{},n}
    case text:
      do Result<&2,&2,String,Admission.Integer>:
        n : Scale.Integer <- magnitude(text)
        return Admission.Integer{False{},n}

def count(text: String) -> Result<&2,&2,String,U32>:
  do Result<&2,&2,String,U32>:
    n : Admission.Integer <- integer(text)
    Admission.checked.integer(n,"admission input count")

def extent(numerator: String, +denominator: String) -> Result<&2,&2,String,Admission.Extent>:
  match numerator:
    case "invalid": Admission.require(Admission.Extent,String.eq(denominator,"1"),
      "invalid admission input",Admission.InvalidExtent{})
    case "inf": Admission.require(Admission.Extent,String.eq(denominator,"1"),
      "invalid admission input",Admission.Infinite{False{}})
    case "-inf": Admission.require(Admission.Extent,String.eq(denominator,"1"),
      "invalid admission input",Admission.Infinite{True{}})
    case numerator:
      do Result<&2,&2,String,Admission.Extent>:
        n : Admission.Integer <- integer(numerator)
        +d : Scale.Integer <- magnitude(denominator)
        _ : Unit <- Admission.require(Unit,Bool.not(Scale.Integer.eq(d,Scale.Integer.zero())),
          "invalid admission input",Unit{})
        return Admission.Finite{n,d}

def material(text: String) -> Result<&2,&2,String,Maybe<&2,Admission.Integer>>:
  match text:
    case "invalid": Done{None{}}
    case text:
      do Result<&2,&2,String,Maybe<&2,Admission.Integer>>:
        n : Admission.Integer <- integer(text)
        return Some{n}

def coordinate(text: String) -> Result<&2,&2,String,Admission.Integer>:
  match text:
    case "invalid": Done{Admission.InvalidInteger{}}
    case text: integer(text)

def boxes.prepend(box: Admission.ExactBox,
    result: Result<&2,&2,String,ParsedBoxes>) ->
  Result<&2,&2,String,ParsedBoxes>:
  match result:
    case Fail{message}: Fail{message}
    case Done{ParsedBoxes{tail,rest}}: Done{ParsedBoxes{box <> tail,rest}}

def count.limited(n: U32, ok: Bool) -> Result<&2,&2,String,Nat>:
  match ok:
    case False{}: invalid(Nat)
    case True{}: Done{U32.to_nat(n)}

def count.nat(text: String, available: List<&2,String>) -> Result<&2,&2,String,Nat>:
  do Result<&2,&2,String,Nat>:
    +n : U32 <- count(text)
    maximum : U32 <- Admission.checked.count(String,available,0,"admission input count")
    count.limited(n,(n <= maximum : U32))

def boxes.record(xs: List<&2,String>, next: Admission.ExactBox -> List<&2,String> ->
    Result<&2,&2,String,ParsedBoxes>) -> Result<&2,&2,String,ParsedBoxes>:
  match xs:
    case m <> x <> y <> z <> u <> v <> w <> rest:
      do Result<&2,&2,String,ParsedBoxes>:
        m : Maybe<&2,Admission.Integer> <- material(m)
        x : Admission.Integer <- coordinate(x)
        y : Admission.Integer <- coordinate(y)
        z : Admission.Integer <- coordinate(z)
        u : Admission.Integer <- coordinate(u)
        v : Admission.Integer <- coordinate(v)
        w : Admission.Integer <- coordinate(w)
        next(Admission.ExactBox{Admission.ExactVec{x,y,z},Admission.ExactVec{u,v,w},m},rest)
    case _: invalid(ParsedBoxes)

def boxes(n: Nat, xs: List<&2,String>) -> Result<&2,&2,String,ParsedBoxes>:
  match n:
    case 0n: Done{ParsedBoxes{Nil{},xs}}
    case 1n+p: boxes.record(xs,box => rest => boxes.prepend(box,boxes(p,rest)))

def owners.boxes(result: ParsedBoxes,
    continuation: List<&2,String> -> Result<&2,&2,String,List<&2,Admission.ExactOwner>>) ->
  Result<&2,&2,String,List<&2,Admission.ExactOwner>>:
  ParsedBoxes{source,rest} = result
  do Result<&2,&2,String,List<&2,Admission.ExactOwner>>:
    tail : List<&2,Admission.ExactOwner> <- continuation(rest)
    return Admission.ExactOwner{source} <> tail

def owners.complete(xs: List<&2,String>) -> Result<&2,&2,String,List<&2,Admission.ExactOwner>>:
  match xs:
    case "complete" <> Nil{}: Done{Nil{}}
    case _: invalid(List<&2,Admission.ExactOwner>)

def owners.record(xs: List<&2,String>, next: ParsedBoxes ->
    Result<&2,&2,String,List<&2,Admission.ExactOwner>>) -> Result<&2,&2,String,List<&2,Admission.ExactOwner>>:
  match xs:
    case count <> +rest:
      do Result<&2,&2,String,List<&2,Admission.ExactOwner>>:
        n : Nat <- count.nat(count,rest)
        result : ParsedBoxes <- boxes(n,rest)
        next(result)
    case _: invalid(List<&2,Admission.ExactOwner>)

def owners(n: Nat, xs: List<&2,String>) -> Result<&2,&2,String,List<&2,Admission.ExactOwner>>:
  match n:
    case 0n: owners.complete(xs)
    case 1n+p: owners.record(xs,result => owners.boxes(result,rest => owners(p,rest)))

def request.tokens(xs: List<&2,String>) -> Result<&2,&2,String,Admission.Bounds>:
  match xs:
      case "megascene-admission/1" <> numerator <> denominator <> budget <> n <> +rest:
        do Result<&2,&2,String,Admission.Bounds>:
          extent : Admission.Extent <- extent(numerator,denominator)
          budget : Admission.Integer <- integer(budget)
          n : Nat <- count.nat(n,rest)
          source : List<&2,Admission.ExactOwner> <- owners(n,rest)
          Admission.admit(source,extent,budget)
      case _: invalid(Admission.Bounds)

def request(text: String) -> Result<&2,&2,String,Admission.Bounds>:
  do Result<&2,&2,String,Admission.Bounds>:
    xs : List<&2,String> <- tokens.go(text,SNil{},Nil{})
    request.tokens(xs)

def surface.tail(xs: List<&2,U32>) -> String:
  match xs:
    case Nil{}: "]"
    case n <> rest: ",\"" ++ U32.show(n) ++ "\"" ++ surface.tail(rest)

def surface(xs: List<&2,U32>) -> String:
  match xs:
    case Nil{}: "[]"
    case n <> rest: "[\"" ++ U32.show(n) ++ "\"" ++ surface.tail(rest)

def report(bounds: Admission.Bounds) -> String:
  Admission.Bounds{cells,bounds,vertices,bytes} = bounds
  "{\"cells\":\"" ++ U32.show(cells) ++ "\",\"surface_rectangle_bounds\":" ++ surface(bounds) ++
    ",\"vertex_bound\":\"" ++ U32.show(vertices) ++ "\",\"geometry_byte_bound\":\"" ++ U32.show(bytes) ++ "\"}"

def read.fail(file: File) -> IO(String):
  do IO<String>:
    File.close(file)
    IO.die(String,2,"invalid admission input file")

def chunks(xs: List<&2,String>) -> String:
  match xs:
    case Nil{}: ""
    case h <> rest: h ++ chunks(rest)

def read.eof.result(acc: List<&2,String>, value: File & Result<&1,&1,U32 & String,String>) -> IO(String):
  match value:
    case (file,Done{SNil{}}):
      do IO<String>:
        File.close(file)
        return chunks(List.reverse(&2,String,acc))
    case (file,_): read.fail(file)

def read.eof(file: File, acc: List<&2,String>) -> IO(String):
  do IO<String>:
    result : File & Result<&1,&1,U32 & String,String> <- File.read(file,1)
    read.eof.result(acc,result)

def read.block(value: File & Result<&1,&1,U32 & String,String>, next: File -> String -> IO(String)) -> IO(String):
  match value:
    case (file,Done{SNil{}}): read.fail(file)
    case (file,Done{s}): next(file,s)
    case (file,Fail{_}): read.fail(file)

def read.ready(done: Bool, file: File, acc: List<&2,String>, next: File -> IO(String)) -> IO(String):
  match done:
    case True{}: read.eof(file,acc)
    case False{}: next(file)

def read.exhausted(done: Bool, file: File, acc: List<&2,String>) -> IO(String):
  match done:
    case True{}: read.eof(file,acc)
    case False{}: read.fail(file)

def read.step(file: File, maximum: U32, next: File -> String -> IO(String)) -> IO(String):
  do IO<String>:
    result : File & Result<&1,&1,U32 & String,String> <- File.read(file,maximum)
    read.block(result,next)

def read.loop(fuel: Nat, +remaining: U32, file: File, +acc: List<&2,String>) -> IO(String):
  match fuel:
    case 0n: read.exhausted(U32.is_eq(remaining,0),file,acc)
    case 1n+p:
      read.ready(U32.is_eq(remaining,0),file,acc,file =>
        read.step(file,U32.min(remaining,65536),file => +s =>
          read.loop(p,(remaining - U32.from_nat(String.length(s)) : U32),file,s <> acc)))

def read.size(value: File & Result<&1,&1,U32 & String,U32>) -> IO(String):
  match value:
    case (file,Done{+n}): read.loop(U32.to_nat(n),n,file,Nil{})
    case (file,_): read.fail(file)

def read(file: File) -> IO(String):
  do IO<String>:
    result : File & Result<&1,&1,U32 & String,U32> <- File.size(file)
    read.size(result)

def emit(result: Result<&2,&2,String,Admission.Bounds>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{bounds}: IO.print(report(bounds))

def execute.opened(opened: Result<&1,&1,U32 & String,File>) -> IO(Unit):
  match opened:
      case Fail{_}: IO.die(Unit,2,"invalid admission input file")
      case Done{file}:
        do IO<Unit>:
          text : String <- read(file)
          emit(request(text))

def execute(path: String) -> IO(Unit):
  do IO<Unit>:
    opened : Result<&1,&1,U32 & String,File> <- File.open(path,"r")
    execute.opened(opened)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case _ <> path <> Nil{}: execute(path)
    case _: IO.die(Unit,2,"usage: megascene-admit INPUT")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
