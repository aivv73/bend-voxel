import Base
import ./schedule_points.bend as P
import ./schedule_file.bend as FileIO

type Words is Data:
  Words{data: List<&2,U32>, rest: List<&2,String>}

type ParsedRow is Data:
  ParsedRow{data: List<&2,U32>, rest: List<&2,String>, seen: List<&2,U32>}

def byte(+n: U32) -> List<&2,U32>:
  [(n .&. 255 : U32),((n >> 8n : U32) .&. 255 : U32),((n >> 16n : U32) .&. 255 : U32),((n >> 24n : U32) .&. 255 : U32)]

def hex.digit(+c: U32) -> Result<&2,&2,String,U32>:
  do Result<&2,&2,String,U32>:
    _ : Unit <- P.require((((c >= 48) && (c <= 57)) || ((c >= 97) && (c <= 102)) : U32))
    return ((c .&. 15 : U32) + 9 * Bool.to_u32((c >= 97 : U32)) : U32)

def hex.go(text: String, n: Nat, acc: U32) -> Result<&2,&2,String,U32>:
  match text n:
    case SNil{} 0n: Done{acc}
    case SCon{Chr{c},rest} 1n+p:
      do Result<&2,&2,String,U32>:
        digit : U32 <- hex.digit(c)
        hex.go(rest,p,((acc << 4n : U32) .|. digit : U32))
    case _ _: Fail{"invalid runtime artifact binary32 word"}

def word(text: String) -> Result<&2,&2,String,U32>:
  match text:
    case SCon{Chr{48},SCon{Chr{120},rest}}: hex.go(rest,8n,0)
    case _: Fail{"invalid runtime artifact binary32 word"}

def words.prepend(value: U32, parsed: Words) -> Words:
  match parsed:
    case Words{values,rest}: Words{List.append(&2,U32,byte(value),values),rest}

def words(n: Nat, xs: List<&2,String>) -> Result<&2,&2,String,Words>:
  match n xs:
    case 0n xs: Done{Words{Nil{},xs}}
    case 1n+p x <> rest:
      do Result<&2,&2,String,Words>:
        value : U32 <- word(x)
        parsed : Words <- words(p,rest)
        return words.prepend(value,parsed)
    case _ Nil{}: Fail{"incomplete runtime artifact row"}

def flag(text: String) -> Result<&2,&2,String,U32>:
  match text:
    case "true": Done{1}
    case "false": Done{0}
    case _: Fail{"invalid runtime artifact picking flag"}

def phase(text: String) -> Result<&2,&2,String,U32>:
  match text:
    case "startup": Done{0}
    case "warmup": Done{1}
    case "ordinary": Done{2}
    case "edit": Done{3}
    case "motion": Done{4}
    case _: Fail{"invalid runtime artifact phase"}

def action(text: String) -> Result<&2,&2,String,U32>:
  match text:
    case "none": Done{4294967295}
    case text: P.number(text)

def frame.fresh(+f: U32, frames: List<&2,U32>) -> Bool:
  match frames:
    case Nil{}: True{}
    case g <> rest: Bool.and(Bool.not(U32.is_eq(f,g)),frame.fresh(f,rest))

def row.prepend(prefix: List<&2,U32>, parsed: Words, seen: List<&2,U32>) -> ParsedRow:
  match parsed:
    case Words{data,rest}: ParsedRow{List.append(&2,U32,prefix,data),rest,seen}

def row(kind: String, xs: List<&2,String>, +seen: List<&2,U32>) -> Result<&2,&2,String,ParsedRow>:
  match kind xs:
    case "camera" xs:
      do Result<&2,&2,String,ParsedRow>:
        parsed : Words <- words(5n,xs)
        return row.prepend(Nil{},parsed,seen)
    case "ray" enabled <> rest:
      do Result<&2,&2,String,ParsedRow>:
        enabled : U32 <- flag(enabled)
        parsed : Words <- words(6n,rest)
        return row.prepend(byte(enabled),parsed,seen)
    case "policy" name <> flags <> rest:
      do Result<&2,&2,String,ParsedRow>:
        phase : U32 <- phase(name)
        +flags : U32 <- P.number(flags)
        _ : Unit <- P.require((flags <= 7 : U32))
        return ParsedRow{List.append(&2,U32,byte(phase),byte(flags)),rest,seen}
    case "supplementary" f <> a <> rest:
      do Result<&2,&2,String,ParsedRow>:
        +f : U32 <- P.number(f)
        a : U32 <- action(a)
        _ : Unit <- P.require((f <= 21720 : U32))
        _ : Unit <- P.require(frame.fresh(f,seen))
        parsed : Words <- words(5n,rest)
        return row.prepend(List.append(&2,U32,byte(f),byte(a)),parsed,f <> seen)
    case _ _: Fail{"incomplete runtime artifact row"}

def record(kind: String, xs: List<&2,String>, seen: List<&2,U32>) -> Result<&2,&2,String,ParsedRow>:
  match xs:
    case "row" <> rest: row(kind,rest,seen)
    case _: Fail{"missing runtime artifact row boundary"}

def rows.step(parsed: ParsedRow, next: List<&2,String> -> List<&2,U32> -> Result<&2,&2,String,List<&2,U32>>) -> Result<&2,&2,String,List<&2,U32>>:
  match parsed:
    case ParsedRow{data,rest,seen}:
      do Result<&2,&2,String,List<&2,U32>>:
        tail : List<&2,U32> <- next(rest,seen)
        return List.append(&2,U32,data,tail)

def rows(n: Nat, +kind: String, xs: List<&2,String>, seen: List<&2,U32>) -> Result<&2,&2,String,List<&2,U32>>:
  match n xs:
    case 0n "complete" <> Nil{}: Done{Nil{}}
    case 0n _: Fail{"incomplete or extra runtime artifact records"}
    case 1n+p xs:
      do Result<&2,&2,String,List<&2,U32>>:
        parsed : ParsedRow <- record(kind,xs,seen)
        rows.step(parsed,rest => seen => rows(p,kind,rest,seen))

def request.parts(xs: List<&2,String>) -> Result<&2,&2,String,List<&2,U32>>:
  match xs:
    case "megascene-binary/1" <> +kind <> count <> rest:
      do Result<&2,&2,String,List<&2,U32>>:
        +n : U32 <- P.number(count)
        _ : Unit <- P.require(((n >= 1) && (n <= 21721) : U32))
        _ : Unit <- P.require(Bool.or(Bool.not(String.eq(kind,"supplementary")),(n <= 128 : U32)))
        rows(U32.to_nat(n),kind,rest,Nil{})
    case _: Fail{"invalid runtime artifact protocol"}

def request(text: String) -> Result<&2,&2,String,List<&2,U32>>:
  request.parts(String.split(text,' '))

def emit(output: String, result: Result<&2,&2,String,List<&2,U32>>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{bytes}: FileIO.write(output,bytes)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case _ <> input <> output <> Nil{}:
      do IO<Unit>:
        text : String <- FileIO.read(input)
        emit(output,request(text))
    case _: IO.die(Unit,2,"usage: schedule-binary INPUT OUTPUT")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
