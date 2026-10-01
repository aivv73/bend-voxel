import Base
import ../src/stress_parser.bend as P
import ../src/benchmark_metrics.bend as M
import ../src/stress_tool.bend as T

type Request is Data:
  Request{options: P.Options, code: U32}

def request(warmup: String, frames: String, every: String, mode: String, world: String, code: String) -> Result<&2,&2,String,Request>:
  do Result<&2,&2,String,Request>:
    warmup : U32 <- M.argument(warmup)
    frames : U32 <- M.argument(frames)
    every : U32 <- M.argument(every)
    world : U32 <- M.argument(world)
    code : U32 <- M.argument(code)
    return Request{P.Options{warmup,frames,every,mode,U32.is_ne(world,0)},code}
def source.result(result: Result<&2,&2,String,String>) -> IO(String):
  match result:
    case Done{text}: IO.pure(String,text)
    case Fail{message}: IO.die(String,2,message)
def source(path: String) -> IO(String):
  match path:
    case "--empty": IO.pure(String,"")
    case _:
      do IO<String>:
        result : Result<&2,&2,String,String> <- T.artifact.read(path)
        source.result(result)
def parsed(value: Result<&2,&2,String,Request>, path: String) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{Request{options,code}}:
      do IO<Unit>:
        raw : String <- source(path)
        report : P.Report <- P.parse(raw,code,options)
        IO.print(P.json(report))
def arguments(args: List<String>) -> IO(Unit):
  match args:
    case _ <> path <> warmup <> frames <> every <> mode <> world <> code <> Nil{}:
      parsed(request(warmup,frames,every,mode,world,code),path)
    case _: IO.die(Unit,2,"stress-parser-test FILE WARMUP FRAMES EVERY MODE WORLD EXIT")
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
