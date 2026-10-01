import Base
import ./frozen_admission.bend as A

def emit.result(result: A.Report) -> IO(Unit):
  match result:
    case A.Report{frames,actions,maximum}:
      IO.print("{\"frozen_frames\":\"" ++ U32.show(frames) ++ "\",\"frozen_actions\":\"" ++ U32.show(actions) ++
        "\",\"maximum_word\":" ++ U32.show(maximum) ++ "}")
def emit(parsed: Result<&2,&2,String,A.Frozen>) -> IO(Unit):
  match parsed:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{frozen}:
      do IO<Unit>:
        report : A.Report <- A.admit(frozen)
        emit.result(report)
def read.end(+text: String, value: File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  match value:
    case (file,Done{SNil{}}):
      do IO<Unit>:
        File.close(file)
        emit(A.parse(text))
    case (file,_):
      do IO<Unit>:
        File.close(file)
        IO.die(Unit,2,"invalid frozen admission input file")
def read.content(n: U32, value: File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  match value:
    case (file,Done{+text}):
      do IO<Unit>:
        A.checked(Nat.is_eq(String.length(text),U32.to_nat(n)),"invalid frozen admission input file")
        tail : File & Result<&1,&1,U32 & String,String> <- File.read(file,1)
        read.end(text,tail)
    case (file,_):
      do IO<Unit>:
        File.close(file)
        IO.die(Unit,2,"invalid frozen admission input file")
def read.size(value: File & Result<&1,&1,U32 & String,U32>) -> IO(Unit):
  match value:
    case (file,Done{+n}):
      do IO<Unit>:
        A.checked((n > 0 : U32),"invalid frozen admission input file")
        text : File & Result<&1,&1,U32 & String,String> <- File.read(file,n)
        read.content(n,text)
    case (file,_):
      do IO<Unit>:
        File.close(file)
        IO.die(Unit,2,"invalid frozen admission input file")
def opened(value: Result<&1,&1,U32 & String,File>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit,2,"invalid frozen admission input file")
    case Done{file}:
      do IO<Unit>:
        size : File & Result<&1,&1,U32 & String,U32> <- File.size(file)
        read.size(size)
def arguments(args: List<String>) -> IO(Unit):
  match args:
    case _ <> path <> Nil{}:
      do IO<Unit>:
        file : Result<&1,&1,U32 & String,File> <- File.open(path,"r")
        opened(file)
    case _: IO.die(Unit,2,"usage: megascene-frozen-admit INPUT")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
