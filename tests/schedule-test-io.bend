import Base
import ../src/schedule_file.bend as Files

def check(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,message)

def process.result(value: Result<&1,&1,U32 & String,U32 & (String & String)>, expected: U32, text: String, error: String, label: String) -> IO(Unit):
  match value:
    case Fail{(_,message)}: IO.die(Unit,1,label ++ ": " ++ message)
    case Done{(code,(out,err))}:
      check((U32.is_eq(code,expected) && String.eq(out,text) && String.contains(err,error)),label)

def process(program: String, args: List<String>, expected: U32, text: String, error: String, label: String) -> IO(Unit):
  do IO<Unit>:
    value : Result<&1,&1,U32 & String,U32 & (String & String)> <- Process.run(program,args,"",262144,10000)
    process.result(value,expected,text,error,label)

def bytes.same(xs: List<&2,U32>, ys: List<&2,U32>) -> Bool:
  match xs ys:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: (U32.is_eq(x,y) && bytes.same(xs,ys))
    case _ _: False{}

def bytes.read.result(value: File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(List<&2,U32>):
  match value:
    case (file,Done{bytes}):
      do IO<List<&2,U32>>:
        _ : Unit <- File.close(file)
        return bytes
    case (file,Fail{(_,message)}):
      do IO<List<&2,U32>>:
        _ : Unit <- File.close(file)
        IO.die(List<&2,U32>,1,message)

def bytes.read.opened(value: Result<&1,&1,U32 & String,File>) -> IO(List<&2,U32>):
  match value:
    case Fail{(_,message)}: IO.die(List<&2,U32>,1,message)
    case Done{file}:
      do IO<List<&2,U32>>:
        value : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,2097153)
        bytes.read.result(value)

def bytes.read(path: String) -> IO(List<&2,U32>):
  do IO<List<&2,U32>>:
    value : Result<&1,&1,U32 & String,File> <- File.open(path,"r")
    bytes.read.opened(value)

def bytes.check(path: String, expected: List<&2,U32>, label: String) -> IO(Unit):
  do IO<Unit>:
    actual : List<&2,U32> <- bytes.read(path)
    check(bytes.same(actual,expected),label)

def text.bytes(text: String) -> List<&2,U32>:
  match text:
    case SNil{}: Nil{}
    case SCon{Chr{c},rest}: c <> text.bytes(rest)

def text.write(path: String, text: String) -> IO(Unit): Files.write(path,text.bytes(text))

def linear(xs: List<&2,String>) -> List<String>:
  match xs:
    case Nil{}: Nil{}
    case x <> rest: x <> linear(rest)
