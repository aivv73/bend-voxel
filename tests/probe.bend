import Base
import ../src/probe.bend as P
import ../src/world.bend as W
import ../src/math.bend as R
import ./world.bend as T

def verify(r: P.EditResult, n: U32, c: U32, status: U32, label: String) -> IO(Unit):
  P.EditResult{w,_,_,_,_} = r
  do IO<Unit>:
    w : W.World <- T.inspect(w,n,c,status,label)
    IO.pure(Unit,Unit{})
def skipped(r: P.EditResult) -> IO(Unit):
  P.EditResult{w,cut,connectivity,surface,finalize} = r
  do IO<Unit>:
    Unit <- T.check((U32.is_eq(cut,0) && U32.is_eq(connectivity,0) && U32.is_eq(surface,0) && U32.is_eq(finalize,0)),"skipped edit records zero stages")
    w : W.World <- T.inspect(w,11,1,1,"skipped edit preserves world")
    IO.pure(Unit,Unit{})
def main() -> IO(Unit):
  do IO<Unit>:
    r : P.EditResult <- P.timed(P.Request{T.bar(2,0.0,0.0),R.Vec{0.55,10.05,0.05},True{}})
    Unit <- verify(r,6,2,1,"timed sparse split")
    r : P.EditResult <- P.timed(P.Request{T.bar(1,0.0,0.0),R.Vec{0.55,10.05,0.05},True{}})
    Unit <- verify(r,11,1,3,"timed budget rollback")
    r : P.EditResult <- P.timed(P.Request{T.bar(2,0.0,0.0),R.Vec{20.0,20.0,20.0},True{}})
    Unit <- verify(r,11,1,2,"timed no-op transaction")
    r : P.EditResult <- P.timed(P.Request{T.bar(2,0.0,0.0),R.Vec{20.0,20.0,20.0},False{}})
    Unit <- skipped(r)
    IO.print("ALL PROBE CHECKS PASSED")
