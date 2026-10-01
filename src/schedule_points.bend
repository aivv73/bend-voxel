import Base

type Point is Data:
  Point{frame: U32, name: String}

def require(ok: Bool) -> Result<&2,&2,String,Unit>:
  match ok:
    case True{}: Done{Unit{}}
    case False{}: Fail{"invalid checkpoint plan"}

def number.read(+text: String, parsed: Maybe<&2,U32>) -> Result<&2,&2,String,U32>:
  match parsed:
    case None{}: Fail{"invalid checkpoint plan integer"}
    case Some{+n}:
      do Result<&2,&2,String,U32>:
        _ : Unit <- require(String.eq(text,U32.show(n)))
        return n

def number(+text: String) -> Result<&2,&2,String,U32>: number.read(text,U32.read(text))

def name.chars(text: String, +length: U32) -> Bool:
  match text:
    case SNil{}: ((length > 0) && (length <= 128) : U32)
    case SCon{Chr{+c},rest}:
      Bool.and((((c >= 65) && (c <= 90)) || ((c >= 97) && (c <= 122)) ||
        ((c >= 48) && (c <= 57)) || U32.is_eq(c,95) : U32),name.chars(rest,(length + 1 : U32)))

def fresh(+name: String, points: List<&2,Point>) -> Bool:
  match points:
    case Nil{}: True{}
    case Point{_,other} <> rest: Bool.and(Bool.not(String.eq(name,other)),fresh(name,rest))

def parse(xs: List<String>, +count: U32, +n: U32, +seen: List<&2,Point>) -> Result<&2,&2,String,List<&2,Point>>:
  match xs:
    case Nil{}:
      do Result<&2,&2,String,List<&2,Point>>:
        _ : Unit <- require((n > 0 : U32))
        return List.reverse(&2,Point,seen)
    case frame <> +name <> rest:
      do Result<&2,&2,String,List<&2,Point>>:
        _ : Unit <- require((n < 4096 : U32))
        +f : U32 <- number(frame)
        _ : Unit <- require((f < count : U32))
        _ : Unit <- require(name.chars(name,0))
        _ : Unit <- require(fresh(name,seen))
        parse(rest,count,(n + 1 : U32),Point{f,name} <> seen)
    case _: Fail{"incomplete checkpoint plan"}

def frame(point: Point) -> U32:
  match point:
    case Point{f,_}: f

def choose(before: Bool, yes: List<&2,Point>, no: List<&2,Point>) -> List<&2,Point>:
  match before:
    case True{}: yes
    case False{}: no

def insert(+point: Point, points: List<&2,Point>) -> List<&2,Point>:
  match points:
    case Nil{}: point <> Nil{}
    case +head <> +rest:
      choose((frame(point) <= frame(head) : U32),point <> head <> rest,head <> insert(point,rest))

def sort(points: List<&2,Point>) -> List<&2,Point>:
  match points:
    case Nil{}: Nil{}
    case p <> rest: insert(p,sort(rest))

def rows(points: List<&2,Point>) -> String:
  match points:
    case Nil{}: ""
    case Point{frame,name} <> rest: U32.show(frame) ++ "\t" ++ name ++ "\n" ++ rows(rest)

def size(points: List<&2,Point>) -> U32:
  match points:
    case Nil{}: 0
    case _ <> rest: (1 + size(rest) : U32)

def serialize(+protocol: String, count: String, args: List<String>) -> Result<&2,&2,String,String>:
  do Result<&2,&2,String,String>:
    _ : Unit <- require(Bool.or(String.eq(protocol,"megascene-checkpoints/1"),String.eq(protocol,"megascene-reviews/1")))
    +count : U32 <- number(count)
    _ : Unit <- require(((count >= 1) && (count <= 21721) : U32))
    +points : List<&2,Point> <- parse(args,count,0,Nil{})
    return protocol ++ "\t" ++ U32.show(count) ++ "\t" ++ U32.show(size(points)) ++ "\n" ++ rows(sort(points))

def emit(result: Result<&2,&2,String,String>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{text}: IO.write(text)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case _ <> protocol <> count <> rest: emit(serialize(protocol,count,rest))
    case _: IO.die(Unit,2,"usage: schedule-points PROTOCOL COUNT [FRAME NAME]...")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
