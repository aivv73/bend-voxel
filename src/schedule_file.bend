import Base

def die(file: File) -> IO(String):
  do IO<String>:
    _ : Unit <- File.close(file)
    IO.die(String,2,"invalid runtime artifact input")

def eof.result(acc: List<&2,String>, value: File & Result<&1,&1,U32 & String,String>) -> IO(String):
  match value:
    case (file,Done{SNil{}}):
      do IO<String>:
        _ : Unit <- File.close(file)
        return String.join(List.reverse(&2,String,acc),"")
    case (file,_): die(file)

def eof(file: File, acc: List<&2,String>) -> IO(String):
  do IO<String>:
    value : File & Result<&1,&1,U32 & String,String> <- File.read(file,1)
    eof.result(acc,value)

def block(value: File & Result<&1,&1,U32 & String,String>, next: File -> String -> IO(String)) -> IO(String):
  match value:
    case (file,Done{SNil{}}): die(file)
    case (file,Done{text}): next(file,text)
    case (file,Fail{_}): die(file)

def step(file: File, count: U32, next: File -> String -> IO(String)) -> IO(String):
  do IO<String>:
    value : File & Result<&1,&1,U32 & String,String> <- File.read(file,count)
    block(value,next)

def ready(done: Bool, file: File, acc: List<&2,String>, next: File -> IO(String)) -> IO(String):
  match done:
    case True{}: eof(file,acc)
    case False{}: next(file)

def exhausted(done: Bool, file: File, acc: List<&2,String>) -> IO(String):
  match done:
    case True{}: eof(file,acc)
    case False{}: die(file)

def loop(fuel: Nat, +remaining: U32, file: File, +acc: List<&2,String>) -> IO(String):
  match fuel:
    case 0n: exhausted(U32.is_eq(remaining,0),file,acc)
    case 1n+p:
      ready(U32.is_eq(remaining,0),file,acc,file =>
        step(file,U32.min(remaining,65536),file => +text =>
          loop(p,(remaining - U32.from_nat(String.length(text)) : U32),file,text <> acc)))

def size.checked(valid: Bool, file: File, +n: U32) -> IO(String):
  match valid:
    case True{}: loop(U32.to_nat(n),n,file,Nil{})
    case False{}: die(file)

def size.result(value: File & Result<&1,&1,U32 & String,U32>) -> IO(String):
  match value:
    case (file,Done{+n}): size.checked(((n > 0) && (n <= 2097152) : U32),file,n)
    case (file,Fail{_}): die(file)

def read.opened(value: Result<&1,&1,U32 & String,File>) -> IO(String):
  match value:
    case Fail{_}: IO.die(String,2,"runtime artifact input unavailable")
    case Done{file}:
      do IO<String>:
        value : File & Result<&1,&1,U32 & String,U32> <- File.size(file)
        size.result(value)

def read(path: String) -> IO(String):
  do IO<String>:
    value : Result<&1,&1,U32 & String,File> <- File.open(path,"r")
    read.opened(value)

def write.result(value: File & Result<&1,&1,U32 & String,Unit>) -> IO(Unit):
  match value:
    case (file,Done{_}): File.close(file)
    case (file,Fail{_}):
      do IO<Unit>:
        _ : Unit <- File.close(file)
        IO.die(Unit,2,"runtime artifact write failed")

def write.opened(data: List<&2,U32>, value: Result<&1,&1,U32 & String,File>) -> IO(Unit):
  match value:
    case Fail{_}: IO.die(Unit,2,"runtime artifact output unavailable")
    case Done{file}:
      do IO<Unit>:
        value : File & Result<&1,&1,U32 & String,Unit> <- File.write_bytes(file,data)
        write.result(value)

def write(path: String, data: List<&2,U32>) -> IO(Unit):
  do IO<Unit>:
    value : Result<&1,&1,U32 & String,File> <- File.open(path,"w")
    write.opened(data,value)
