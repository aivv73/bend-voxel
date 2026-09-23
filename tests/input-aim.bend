import Base
import ../src/input.bend as I
import ../src/render.bend as V
import ../src/world.bend as W
import ../src/math.bend as R

def check(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.print("PASS " ++ label)
    case False{}: IO.die(Unit,1,"FAIL " ++ label)
def cut(c: I.Control) -> Bool:
  I.Control{_,_,_,_,_,_,_,cut,_,_} = c
  cut
def keys(c: I.Control) -> U32:
  I.Control{_,keys,_,_,_,_,_,_,_,_} = c
  keys
def focused(c: I.Control) -> Bool:
  I.Control{_,_,_,_,_,_,focus,_,_,_} = c
  focus
def reset(c: I.Control) -> Bool:
  I.Control{_,_,_,_,_,_,_,_,reset,_} = c
  reset
def hit(a: V.Aim, kind0: U32, t0: F32) -> Bool:
  V.Aim{_,t,kind} = a
  (U32.is_eq(kind,kind0) && (F32.abs((t - t0 : F32)) < 0.0001 : F32))
def moved(c: I.Control) -> Bool:
  I.Control{cam,_,_,_,_,_,_,_,_,_} = c
  V.Camera{p,_,_} = cam
  R.Vec{_,y,_} = p
  (F32.abs((y - 4.4 : F32)) < 0.0001 : F32)
def main() -> IO(Unit):
  +held = I.mouse(320,180,0,True{},I.initial())
  +released = I.key(27,True{},I.key(119,True{},I.initial()))
  do IO<Unit>:
    Unit <- check(cut(held),"left press cuts once")
    Unit <- check(Bool.not(cut(I.mouse(320,180,0,True{},held))),"held left does not repeat")
    Unit <- check(cut(I.mouse(320,180,0,True{},I.mouse(320,180,0,False{},held))),"release rearms left")
    Unit <- check(Bool.not(cut(I.mouse(320,180,0,True{},I.mouse(320,180,1,True{},I.initial())))),"right look suppresses cuts")
    Unit <- check((U32.is_eq(keys(released),0) && Bool.not(focused(released))),"escape clears held state")
    Unit <- check(U32.is_eq(keys(I.key(119,True{},released)),0),"unfocused movement ignored")
    Unit <- check(focused(I.mouse(320,180,0,True{},released)),"click restores focus")
    Unit <- check(U32.is_eq(keys(I.key(0,False{},I.key(119,True{},I.initial()))),0),"focus loss clears movement")
    Unit <- check(reset(I.mouse(600,15,0,True{},I.initial())),"reset button")
    Unit <- check(moved(I.step(I.key(101,True{},I.initial()),0.5)),"movement is two meters per second")
    Unit <- check(hit(V.ray.face(1,40,800,3,0.0,1,R.Vec{1.8,4.0,(0.0 - 0.95 : F32)},R.Vec{0.0,(0.0 - 1.0 : F32),0.0},V.Aim{R.Vec{0.0,0.0,0.0},14.0,0}),1,1.9),"merged face far-end picking")
    IO.print("ALL INPUT AND AIM CHECKS PASSED")
