import Base
import ../src/probe.bend as P
import ../src/world.bend as W
import ../src/vendor/bend3d.bend as R
import ./world.bend as T

def verify(r: P.EditResult, n: U32, c: U32, status: U32, label: String) -> IO(Unit):
  P.EditResult{w,_,_} = r
  do IO<Unit>:
    w : W.World <- T.inspect(w,n,c,status,label)
    IO.pure(Unit,Unit{})
def skipped(r: P.EditResult) -> IO(Unit):
  P.EditResult{w,cut,rebuild} = r
  do IO<Unit>:
    Unit <- T.check((U32.is_eq(cut,0) && U32.is_eq(rebuild,0)),"skipped edit records zero stages")
    w : W.World <- T.inspect(w,4640,0,1,"skipped edit preserves world")
    IO.pure(Unit,Unit{})
def main() -> IO(Unit):
  do IO<Unit>:
    r : P.EditResult <- P.timed(P.Request{W.initial(),R.Vec{(0.0 - 1.0 : F32),1.05,0.3},True{}})
    Unit <- verify(r,4622,0,1,"timed partial cut")
    r : P.EditResult <- P.timed(P.Request{T.fixture.cap(),W.xyz(19125),True{}})
    Unit <- verify(r,74,64,3,"timed cap rollback")
    r : P.EditResult <- P.timed(P.Request{W.initial(),R.Vec{20.0,20.0,20.0},True{}})
    Unit <- verify(r,4640,0,2,"timed no-op transaction")
    r : P.EditResult <- P.timed(P.Request{W.initial(),R.Vec{20.0,20.0,20.0},False{}})
    Unit <- skipped(r)
    IO.print("ALL PROBE CHECKS PASSED")
