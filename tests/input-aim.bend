import Base
import ../src/input.bend as I
import ../src/render.bend as V
import ../src/world.bend as W
import ../src/spatial.bend as S
import ../src/district.bend as D
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
  (F32.abs((y - 36.0 : F32)) < 0.0001 : F32)
def sprinted(c: I.Control) -> Bool:
  I.Control{cam,_,_,_,_,_,_,_,_,_} = c
  V.Camera{p,_,_} = cam
  R.Vec{_,y,_} = p
  (F32.abs((y - 60.0 : F32)) < 0.0001 : F32)
def showcase.camera(c: I.Control) -> Bool:
  I.Control{cam,_,_,_,_,_,_,_,_,_} = c
  V.Camera{p,_,pitch} = cam
  R.Vec{x,y,z} = p
  (((F32.abs((x - 160.0 : F32)) < 0.0001) &&
    (F32.abs((y - 145.0 : F32)) < 0.0001) &&
    (F32.abs((z - 500.0 : F32)) < 0.0001) &&
    (F32.abs((pitch + 0.4 : F32)) < 0.0001)) : F32)
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
    Unit <- check(moved(I.step(I.key(101,True{},I.initial()),0.5)),"movement is twelve meters per second")
    Unit <- check(sprinted(I.step(I.key(16,True{},I.key(101,True{},I.initial())),0.5)),"shift enables fast travel")
    Unit <- check(showcase.camera(I.showcase()),"showcase starts at the overview camera")
    Unit <- check(showcase.camera(I.reset.state(I.showcase(),True{})),"showcase reset restores its camera")
    Unit <- check(hit(V.ray.tree(S.Leaf{D.box((0.0 - 320.0 : F32),0.0,(0.0 - 320.0 : F32),640.0,4.0,640.0,2)},0.0,R.Vec{31.9,4.0,31.9},R.Vec{0.0,(0.0 - 1.0 : F32),0.0},V.Aim{R.Vec{0.0,0.0,0.0},256.0,0}),1,3.6),"large sparse slab far-end picking")
    Unit <- check(hit(V.ray.tree(S.Leaf{D.box((0.0 - 40.0 : F32),20.0,0.0,10.0,10.0,10.0,2)},(0.0 - 1.0 : F32),R.Vec{(0.0 - 3.5 : F32),5.0,0.5},R.Vec{0.0,(0.0 - 1.0 : F32),0.0},V.Aim{R.Vec{0.0,0.0,0.0},256.0,0}),1,3.0),"picking uses moving body local coordinates")
    Unit <- check(hit(V.ray.tree(S.Leaf{D.box(0.0,0.0,0.0,10.0,10.0,10.0,1)},0.0,R.Vec{0.5,5.0,0.5},R.Vec{0.0,(0.0 - 1.0 : F32),0.0},V.Aim{R.Vec{0.0,0.0,0.0},256.0,0}),2,4.0),"spatial picking identifies explicit anchors")
    Unit <- check(hit(V.ray.tree(S.Leaf{D.box(0.0,0.0,0.0,10.0,10.0,10.0,2)},0.0,R.Vec{2.0,5.0,0.5},R.Vec{0.0,(0.0 - 1.0 : F32),0.0},V.Aim{R.Vec{0.0,0.0,0.0},256.0,0}),0,256.0),"parallel ray outside bounds misses")
    IO.print("ALL INPUT AND AIM CHECKS PASSED")
