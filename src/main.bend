import Base
import ./demo.bend as D
import ./world.bend as W
import ./render.bend as V
import ./input.bend as I
import ./platform.bend as P
import ./vulkan.bend as VK
import ./math.bend as R
import ./probe.bend as Probe

def aim.kind(a: V.Aim) -> U32:
  V.Aim{_, _, kind} = a
  kind

def ready(s: D.State, frameUs: U32) -> D.State & V.Aim & String:
  D.State{w, +c, pending, +last} = s
  W.World{a, +bs, +solids, +count, +removed, +status} = w
  +aim = I.aim(c, bs)
  (D.State{W.World{a, bs, solids, count, removed, status}, c, pending, last},
    aim, D.hud(solids, count, removed, status, aim.kind(aim), frameUs, last))

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

def stress.point(+ordinal: U32, +scene: U32) -> R.Vec:
  +x = (U32.to_f32((4 + ordinal % 6 * 6 : U32)) * 0.1 - 1.95 : F32)
  +z = (U32.to_f32((8 + ordinal / 6 % 2 * 8 : U32)) * 0.1 - 0.95 : F32)
  R.Vec{x, R.pick(U32.is_eq(scene, 1), 2.15, 1.25), z}
def stress.edit(on: Bool, state: D.State, index: U32, every: U32, scene: U32, stamp: U32) -> IO(D.State):
  match on:
    case False{}: IO.pure(D.State, state)
    case True{}:
      D.State{w, c, p, last} = state
      do IO<D.State>:
        result : Probe.EditResult <- Probe.timed(Probe.Request{w, stress.point((index / every : U32), scene), True{}})
        IO.pure(D.State, D.sample.measured(result, c, p, last, 200, stamp))
def stress.edit.due(+index: U32, warmup: U32, every: U32) -> Bool:
  match every:
    case 0: False{}
    case +period: ((index >= warmup : U32) && U32.is_eq((index % period : U32), 0))
type Stress is Data:
  Stress{epoch: U32, index: U32, total: U32, scene: U32, warmup: U32, every: U32}
def stress.done(done: Bool, win: Window, state: D.State, config: Stress, end: U32, frameUs: U32,
  k: Window -> D.State -> Stress -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  match done:
    case True{}: close(win)
    case False{}: k(win, state, config, end, frameUs)
def stress.world(w: W.World, c: I.Control, +pending: List<&2,D.Sample>, last: U32,
  events: List<Event>, win: Window, +epoch: U32, +previousEnd: U32,
  now: U32, +updateEnd: U32, +sceneEnd: U32, +end: U32,
  +index: U32, +total: U32, scene: U32, warmup: U32, every: U32,
  k: Window -> D.State -> Stress -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  W.World{a, bs, +solids, +bodies, removed, status} = w
  do IO<Unit>:
    Unit <- D.sample.log((end - epoch : U32), (end - previousEnd : U32), solids, bodies,
      pending, end, (updateEnd - now : U32), (sceneEnd - updateEnd : U32), (end - sceneEnd : U32))
    stress.done(((index + 1 >= total : U32) || D.events.close(events)), win,
      D.State{W.World{a, bs, solids, bodies, removed, status}, c, Nil{}, D.pending.last(pending, end, last)},
      Stress{epoch, (index + 1 : U32), total, scene, warmup, every}, end,
      (end - previousEnd : U32), k)
def stress.config(w: W.World, c: I.Control, pending: List<&2,D.Sample>, last: U32,
  events: List<Event>, win: Window, config: Stress, previousEnd: U32,
  now: U32, updateEnd: U32, sceneEnd: U32, end: U32,
  k: Window -> D.State -> Stress -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  Stress{epoch, index, total, scene, warmup, every} = config
  stress.world(w, c, pending, last, events, win, epoch, previousEnd,
    now, updateEnd, sceneEnd, end, index, total, scene, warmup, every, k)
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
  Stress{epoch, +index, total, +scene, +warmup, +every} = config
  do IO<Unit>:
    +now : U32 <- P.micros()
    updated : D.State <- stress.edit(stress.edit.due(index, warmup, every),
      D.advance(state, R.min(0.1, (U32.to_f32((now - previousEnd : U32)) / 1000000.0 : F32))), index, every, scene, now)
    +updateEnd : U32 <- P.micros()
    sceneState : D.State & V.Aim & String <- IO.pure(D.State & V.Aim & String, ready(updated, frameUs))
    +sceneEnd : U32 <- P.micros()
    shown : Window & D.State & List<Event> <- show(sceneState, win)
    +end : U32 <- P.micros()
    stress.shown(shown, Stress{epoch, index, total, scene, warmup, every}, previousEnd,
      now, updateEnd, sceneEnd, end, w => s => c => t => dt => stress.loop(w, s, c, t, dt))
def stress.start(win: Window, +scene: U32, +warmup: U32, measured: U32, every: U32) -> IO(Unit):
  do IO<Unit>:
    +start : U32 <- P.micros()
    world : W.World <- IO.pure(W.World, W.stress(scene))
    +epoch : U32 <- P.micros()
    Unit <- IO.print("init," ++ U32.show(scene) ++ "," ++ U32.show((epoch - start : U32)))
    stress.loop(win, D.State{world, I.initial(), Nil{}, 0},
      Stress{epoch, 0, (warmup + measured : U32), scene, warmup, every}, epoch, 0)

def start.stress(on: Bool, win: Window, now: U32, frames: U32,
  scene: U32, warmup: U32, measured: U32, every: U32) -> IO(Unit):
  match on:
    case True{}: stress.start(win, scene, warmup, measured, every)
    case False{}: loop(win, D.initial(), now, frames)

def main() -> IO(Unit):
  do IO<Unit>:
    frames : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_FRAMES")
    stressScene : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_STRESS_SCENE")
    stressWarmup : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_STRESS_WARMUP")
    stressMeasured : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_STRESS_MEASURED")
    stressEdit : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_STRESS_EDIT_EVERY")
    +stressId : U32 <- IO.pure(U32, number(stressScene))
    win : Window <- IO.try(Window, Window.open("Bend Voxel Vulkan - WASD / RMB look / LMB carve / R reset", 640, 360))
    +now : U32 <- P.micros()
    start.stress((stressId > 0 : U32), win, now, number(frames),
      stressId, number(stressWarmup), number(stressMeasured), number(stressEdit))
