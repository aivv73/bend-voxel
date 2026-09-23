import Base
import ./demo.bend as D
import ./world.bend as W
import ./render.bend as V
import ./input.bend as I
import ./platform.bend as P
import ./vulkan.bend as VK
import ./vendor/bend3d.bend as R

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

def bench.done(done: Bool, win: Window, state: D.State, epoch: U32, end: U32,
  elapsed: U32, frameUs: U32,
  k: Window -> D.State -> U32 -> U32 -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  match done:
    case True{}: close(win)
    case False{}: k(win, state, epoch, end, elapsed, frameUs)

def bench.world(w: W.World, c: I.Control, +pending: List<&2,D.Sample>, last: U32,
  events: List<Event>, win: Window, +epoch: U32, previousEnd: U32,
  +now: U32, +updateEnd: U32, +sceneEnd: U32, +end: U32,
  k: Window -> D.State -> U32 -> U32 -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  W.World{a, bs, +solids, +count, removed, status} = w
  +total = (end - epoch : U32)
  +duration = (end - previousEnd : U32)
  do IO<Unit>:
    Unit <- D.bench.log(total, duration, solids, count, pending, end,
      (updateEnd - now : U32), (sceneEnd - updateEnd : U32), (end - sceneEnd : U32), 0, 0)
    bench.done((D.events.close(events) || (total >= 65000000 : U32)), win,
      D.State{W.World{a, bs, solids, count, removed, status}, c, Nil{}, D.pending.last(pending, end, last)},
      epoch, end, (now - epoch : U32), duration, k)

def bench.after(win: Window, state: D.State, events: List<Event>, epoch: U32,
  previousEnd: U32, now: U32, updateEnd: U32, sceneEnd: U32, end: U32,
  k: Window -> D.State -> U32 -> U32 -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  D.State{w, c, +pending, last} = state
  bench.world(w, c, pending, last, events, win, epoch, previousEnd, now, updateEnd, sceneEnd, end, k)

def bench.shown(r: Window & D.State & List<Event>, epoch: U32,
  previousEnd: U32, now: U32, updateEnd: U32, sceneEnd: U32, end: U32,
  k: Window -> D.State -> U32 -> U32 -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  (win, state, events) = r
  bench.after(win, state, events, epoch, previousEnd, now, updateEnd, sceneEnd, end, k)

@unsafe
def bench.loop(win: Window, state: D.State, +epoch: U32, +previousEnd: U32, +previousElapsed: U32, frameUs: U32) -> IO(Unit):
  do IO<Unit>:
    +now : U32 <- P.micros()
    updated : D.State <- D.replay.scan.timed(42n, 0, previousElapsed, (now - epoch : U32), epoch,
      D.advance(state, (U32.to_f32((now - epoch - previousElapsed : U32)) / 1000000.0 : F32)))
    camera : D.State <- IO.pure(D.State, D.replay.camera(updated, (now - epoch : U32)))
    +updateEnd : U32 <- P.micros()
    scene : D.State & V.Aim & String <- IO.pure(D.State & V.Aim & String, ready(camera, frameUs))
    +sceneEnd : U32 <- P.micros()
    shown : Window & D.State & List<Event> <- show(scene, win)
    +end : U32 <- P.micros()
    bench.shown(shown, epoch, previousEnd, now, updateEnd, sceneEnd, end,
      w => s => e => t => elapsed => dt => bench.loop(w, s, e, t, elapsed, dt))

def number(r: Result<&1, &1, U32 & String, String>) -> U32:
  match r:
    case Fail{_}: 0
    case Done{text}: D.env.read(U32.read(text))

def start(benchmark: Bool, win: Window, +now: U32, limit: U32) -> IO(Unit):
  match benchmark:
    case True{}: bench.loop(win, D.initial(), now, now, 0, 0)
    case False{}: loop(win, D.initial(), now, limit)

def main() -> IO(Unit):
  do IO<Unit>:
    benchmark : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_BENCH")
    frames : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_FRAMES")
    win : Window <- IO.try(Window, Window.open("Bend Voxel Vulkan - WASD / RMB look / LMB carve / R reset", 640, 360))
    +now : U32 <- P.micros()
    start((number(benchmark) > 0 : U32), win, now, number(frames))
