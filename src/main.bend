import Base
import ./demo.bend as D
import ./world.bend as W
import ./render.bend as V
import ./input.bend as I
import ./platform.bend as P
import ./vulkan.bend as VK
import ./math.bend as R
import ./probe.bend as Probe
import ./spatial.bend as S
import ./resolution.bend as Resolution
import ./atelier_workload.bend as AtelierWorkload
import ./color.bend as Color

def aim.kind(a: V.Aim) -> U32:
  V.Aim{_, _, kind} = a
  kind

def ready(s: D.State, frameUs: U32) -> D.State & V.Aim & String:
  D.State{w, +c, pending, +last} = s
  W.World{+bs, +solids, +count, +removed, +status, next, +budget} = w
  +aim = I.aim(c, bs)
  (D.State{W.World{bs, solids, count, removed, status, next, budget}, c, pending, last},
    aim, D.hud(solids, count, budget, removed, status, aim.kind(aim), frameUs, last))

def show(r: D.State & V.Aim & String, win: Window) -> IO(Window & D.State & List<Event>):
  (state, aim, hud) = r
  VK.vulkan.frame(win, state, aim, hud)

def close(win: Window) -> IO(Unit):
  do IO<Unit>:
    win : Window <- VK.vulkan.release(win)
    Window.close(win)

def quit(c: I.Control) -> Bool:
  I.Control{_, _, _, _, _, _, _, _, _, value} = c
  value

def loop.cont(done: Bool, win: Window, state: D.State, now: U32, +limit: U32,
  k: Window -> D.State -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  match done:
    case True{}: close(win)
    case False{}: k(win, state, now, R.word((limit > 0 : U32), (limit - 1 : U32), 0))

def loop.next(win: Window, state: D.State, now: U32, +limit: U32,
  k: Window -> D.State -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  D.State{w, +c, pending, last} = state
  loop.cont((quit(c) || U32.is_eq(limit, 1)), win, D.State{w, c, pending, last}, now, limit, k)

def loop.clear(state: D.State, now: U32) -> D.State:
  D.State{w, c, pending, last} = state
  D.State{w, c, Nil{}, D.pending.last(pending, now, last)}

def loop.events(win: Window, state: D.State, events: List<Event>, +now: U32, limit: U32,
  k: Window -> D.State -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  loop.next(win, D.events(events, loop.clear(state, now), now), now, limit, k)

def loop.shown(r: Window & D.State & List<Event>, now: U32, limit: U32,
  k: Window -> D.State -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  (win, state, events) = r
  loop.events(win, state, events, now, limit, k)

@unsafe
def loop(win: Window, state: D.State, +stamp: U32, limit: U32) -> IO(Unit):
  do IO<Unit>:
    +now : U32 <- P.micros()
    shown : Window & D.State & List<Event> <- show(ready(D.advance(state,
      R.min(0.1, (U32.to_f32((now - stamp : U32)) / 1000000.0 : F32))), (now - stamp : U32)), win)
    loop.shown(shown, now, limit, w => s => t => n => loop(w, s, t, n))

def number(r: Result<&1, &1, U32 & String, String>) -> U32:
  match r:
    case Fail{_}: 0
    case Done{text}: D.env.read(U32.read(text))

# Benchmark cuts use world-space coordinates and fixed frame scheduling.
def stress.request(+w: W.World, ordinal: U32) -> Probe.Request:
  Probe.Request{w,AtelierWorkload.point(ordinal),True{}}
def stress.edit(on: Bool, +state: D.State, ordinal: U32) -> IO(D.State):
  match on:
    case False{}: IO.pure(D.State,state)
    case True{}:
      D.State{w,c,p,last} = state
      do IO<D.State>:
        stamp : U32 <- P.micros()
        result : Probe.EditResult <- Probe.timed(stress.request(w,ordinal))
        IO.pure(D.State,D.sample.measured(result,c,p,last,200,stamp))
def stress.edit.due(+index: U32, +warmup: U32, every: U32) -> Bool:
  match every:
    case 0: False{}
    case +period:
      ((index >= warmup : U32) && U32.is_eq(((index - warmup) % period : U32),0) &&
        ((index - warmup) / period < 6 : U32))
def stress.camera(+index: U32, s: D.State) -> D.State:
  D.State{w,c,p,last} = s
  I.Control{V.Camera{_,_,_,+viewportW,+viewportH},_,_,_,_,_,_,_,_,_} = c
  +angle = (U32.to_f32((index % 720 : U32)) * 0.008726646 : F32)
  +eye = {R.Vec{(24.0 * F32.sin(angle) : F32),11.0,(24.0 * F32.cos(angle) : F32)} : R.Vec}
  D.State{w,I.Control{V.Camera{eye,(3.14159265 + angle : F32),(0.0 - 0.28 : F32),viewportW,viewportH},
    0,(viewportW / 2 : U32),(viewportH / 2 : U32),False{},False{},False{},False{},False{},False{}},p,last}
def stress.aim(+index: U32, s: D.State) -> D.State:
  D.State{w,c,p,last} = s
  I.Control{V.Camera{_,_,_,+viewportW,+viewportH},_,_,_,_,_,_,_,_,_} = c
  +mx = ((80 + index * 5 % 480) * viewportW / 640 : U32)
  D.State{w,I.Control{V.camera.size(viewportW,viewportH),
    0,mx,(viewportH / 2 : U32),False{},False{},True{},False{},False{},False{}},p,last}
def stress.night(s: D.State) -> D.State:
  D.State{w,c,p,last} = s
  I.Control{cam,_,mx,my,look,left,focus,cut,reset,quit} = c
  D.State{w,I.Control{cam,256,mx,my,look,left,False{},cut,reset,quit},p,last}
def stress.fixed(s: D.State) -> D.State:
  D.State{w,c,p,last} = s
  I.Control{cam,keys,mx,my,look,left,_,cut,reset,quit} = c
  D.State{w,I.Control{cam,keys,mx,my,look,left,False{},cut,reset,quit},p,last}
def stress.view(mode: U32, index: U32, s: D.State) -> D.State:
  match mode:
    case 1: stress.camera(index,s)
    case 2: stress.aim(index,s)
    case 6: stress.night(s)
    case _: stress.fixed(s)
type Stress is Data:
  Stress{epoch: U32, index: U32, total: U32, warmup: U32, every: U32, mode: U32}
def stress.done(done: Bool, win: Window, state: D.State, config: Stress, end: U32, frameUs: U32,
  k: Window -> D.State -> Stress -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  match done:
    case True{}: close(win)
    case False{}: k(win, state, config, end, frameUs)
def stress.world(w: W.World, c: I.Control, +pending: List<&2,D.Sample>, last: U32,
  events: List<Event>, win: Window, +epoch: U32, +previousEnd: U32,
  now: U32, +updateEnd: U32, +sceneEnd: U32, +end: U32,
  +index: U32, +total: U32, warmup: U32, every: U32, mode: U32,
  k: Window -> D.State -> Stress -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  W.World{bs, +solids, +bodies, removed, status, next, budget} = w
  do IO<Unit>:
    Unit <- D.sample.log((end - epoch : U32), (end - previousEnd : U32), solids, bodies,
      pending, end, (updateEnd - now : U32), (sceneEnd - updateEnd : U32), (end - sceneEnd : U32))
    stress.done(((index + 1 >= total : U32) || D.events.close(events)), win,
      D.State{W.World{bs, solids, bodies, removed, status, next, budget}, c, Nil{}, D.pending.last(pending, end, last)},
      Stress{epoch, (index + 1 : U32), total, warmup, every, mode}, end,
      (end - previousEnd : U32), k)
def stress.config(w: W.World, c: I.Control, pending: List<&2,D.Sample>, last: U32,
  events: List<Event>, win: Window, config: Stress, previousEnd: U32,
  now: U32, updateEnd: U32, sceneEnd: U32, end: U32,
  k: Window -> D.State -> Stress -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  Stress{epoch, index, total, warmup, every, mode} = config
  stress.world(w, c, pending, last, events, win, epoch, previousEnd,
    now, updateEnd, sceneEnd, end, index, total, warmup, every, mode, k)
def stress.after(win: Window, state: D.State, events: List<Event>, config: Stress,
  previousEnd: U32, now: U32, updateEnd: U32, sceneEnd: U32, end: U32,
  k: Window -> D.State -> Stress -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  D.State{w, c, pending, last} = state
  stress.config(w, c, pending, last, events, win, config, previousEnd,
    now, updateEnd, sceneEnd, end, k)
def stress.shown(r: Window & D.State & List<Event>, config: Stress, previousEnd: U32,
  now: U32, updateEnd: U32, sceneEnd: U32, end: U32,
  k: Window -> D.State -> Stress -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  (win, state, events) = r
  stress.after(win, state, events, config, previousEnd, now, updateEnd, sceneEnd, end, k)
@unsafe
def stress.loop(win: Window, state: D.State, config: Stress, +previousEnd: U32, frameUs: U32) -> IO(Unit):
  Stress{epoch, +index, total, +warmup, +every, +mode} = config
  do IO<Unit>:
    +now : U32 <- P.micros()
    updated : D.State <- stress.edit(stress.edit.due(index,warmup,every),
      D.advance(state,(1.0 / 60.0 : F32)), ((index - warmup) / R.word(U32.is_eq(every,0),1,every) : U32))
    viewed : D.State <- IO.pure(D.State, stress.view(mode, index, updated))
    +updateEnd : U32 <- P.micros()
    sceneState : D.State & V.Aim & String <- IO.pure(D.State & V.Aim & String, ready(viewed, frameUs))
    +sceneEnd : U32 <- P.micros()
    shown : Window & D.State & List<Event> <- show(sceneState, win)
    +end : U32 <- P.micros()
    stress.shown(shown, Stress{epoch, index, total, warmup, every, mode}, previousEnd,
      now, updateEnd, sceneEnd, end, w => s => c => t => dt => stress.loop(w, s, c, t, dt))
def stress.inventory(w: W.World) -> IO(Unit):
  W.World{+bs,n,_,_,_,_,budget} = w
  IO.print("world," ++ U32.show(n) ++ "," ++ U32.show(W.bodies.count(bs)) ++ "," ++
    U32.show(W.bodies.regions(bs)) ++ "," ++ U32.show(budget))
def stress.start(win: Window, +warmup: U32, measured: U32, every: U32, mode: U32, budget: U32,
  width: U32, height: U32) -> IO(Unit):
  do IO<Unit>:
    +start : U32 <- P.micros()
    +world : W.World <- IO.pure(W.World, W.showcase(budget))
    +epoch : U32 <- P.micros()
    Unit <- IO.print("init," ++ U32.show((epoch - start : U32)))
    Unit <- stress.inventory(world)
    stress.loop(win, D.State{world, I.initial.size(width,height), Nil{}, 0},
      Stress{epoch, 0, (warmup + measured : U32), warmup, every, mode}, epoch, 0)
def start.stress(on: Bool, win: Window, now: U32, frames: U32,
  warmup: U32, measured: U32, every: U32, mode: U32, budget: U32,
  width: U32, height: U32) -> IO(Unit):
  match on:
    case True{}: stress.start(win, warmup, measured, every, mode, budget, width, height)
    case False{}: loop(win,D.State{W.showcase(budget),I.initial.size(width,height),Nil{},0},now,frames)

def configuration.budget.go(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,"VOXEL_BODY_BUDGET must be at most 65536")
def configuration.budget(budget: U32) -> IO(Unit):
  configuration.budget.go((budget <= 65536 : U32))
def configuration.resolution.parsed(r: Maybe<&2,Resolution.Size>) -> IO(Resolution.Size):
  match r:
    case Some{size}: IO.pure(Resolution.Size,size)
    case None{}: IO.die(Resolution.Size,1,"VOXEL_RESOLUTION must be WIDTHxHEIGHT (640..7680 by 360..4320, at most 8294400 pixels)")
def configuration.resolution(r: Result<&1,&1,U32 & String,String>) -> IO(Resolution.Size):
  match r:
    case Fail{_}: IO.pure(Resolution.Size,Resolution.default())
    case Done{text}: configuration.resolution.parsed(Resolution.parse(text))
def main() -> IO(Unit):
  do IO<Unit>:
    budgetEnv : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_BODY_BUDGET")
    +budget : U32 <- IO.pure(U32,number(budgetEnv))
    Unit <- configuration.budget(budget)
    frames : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_FRAMES")
    stressFlag : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_STRESS")
    stressWarmup : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_STRESS_WARMUP")
    stressMeasured : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_STRESS_MEASURED")
    stressEdit : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_STRESS_EDIT_EVERY")
    stressView : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_STRESS_VIEW")
    +stressOn : U32 <- IO.pure(U32, number(stressFlag))
    resolutionEnv : Result<&1,&1,U32 & String,String> <- IO.get_env("VOXEL_RESOLUTION")
    +size : Resolution.Size <- configuration.resolution(resolutionEnv)
    +width : U32 <- IO.pure(U32,Resolution.width(size))
    +height : U32 <- IO.pure(U32,Resolution.height(size))
    win : Window <- IO.try(Window, Window.open("Bend Voxel Vulkan - WASD / RMB look / LMB carve / R reset", width, height))
    win : Window <- VK.vulkan.colors(win, Color.palette())
    +now : U32 <- P.micros()
    start.stress((stressOn > 0 : U32), win, now, number(frames),
      number(stressWarmup), number(stressMeasured), number(stressEdit), number(stressView),
      R.word(U32.is_eq(budget,0),2048,budget),width,height)
