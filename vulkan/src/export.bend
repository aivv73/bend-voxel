import Base
import ../../dump.bend as D

def pixels(bytes: List<U32>) -> List<&2,String>:
  match bytes:
    case Nil{}: Nil{}
    case r <> g <> b <> a <> rest:
      (U32.show(r) ++ " " ++ U32.show(g) ++ " " ++ U32.show(b)) <> pixels(rest)
    case _: Nil{}

def ppm(path: String, bytes: List<U32>) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File,File.open(path,"w"))
    result : File & Result<&1,&1,U32 & String,Unit> <- File.write(file,"P3\n512 512\n255\n" ++ String.join(pixels(bytes),"\n") ++ "\n")
    file : File <- D.Dump.written(result)
    File.close(file)
