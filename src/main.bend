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

def aim.kind(a: V.Aim) -> U32:
  V.Aim{_, _, kind} = a
  kind

def ready(s: D.State, frameUs: U32) -> D.State & V.Aim & String:
  D.State{w, +c, pending, +last} = s
  W.World{+bs, +solids, +count, +removed, +status, next, +budget, districts} = w
  +aim = I.aim(c, bs)
  (D.State{W.World{bs, solids, count, removed, status, next, budget, districts}, c, pending, last},
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

# All replay coordinates are real world meters and independent of frame rate.
def stress.point(+ordinal: U32, mode: U32, +districts: U32) -> R.Vec:
  match mode:
    case 4:
      R.Vec{R.pick(U32.is_eq(ordinal,0),(0.0 - 15.9 : F32),15.9),16.25,(0.0 - 19.95 : F32)}
    case 5:
      +width = F32.to_u32(F32.ceil(F32.sqrt(U32.to_f32(districts))))
      +dx = (U32.to_f32((ordinal / 128 % width : U32)) * 64.0 : F32)
      +dz = (U32.to_f32((ordinal / 128 / width : U32)) * 64.0 : F32)
      R.Vec{(dx + 4.4 + U32.to_f32((ordinal % 16 : U32)) * 1.5 : F32),1.0,
        (dz + 17.4 + U32.to_f32((ordinal / 16 % 8 : U32)) * 1.5 : F32)}
    case _:
      R.Vec{(0.0 - 27.6 + U32.to_f32((ordinal % 5 : U32)) * 6.3 : F32),
        (6.35 + U32.to_f32((ordinal / 25 : U32)) * 6.0 : F32),
        (2.4 + U32.to_f32((ordinal / 5 % 5 : U32)) * 5.8 : F32)}
def stress.request(+w: W.World, ordinal: U32, mode: U32) -> Probe.Request:
  W.World{_,_,_,_,_,_,_,districts} = w
  Probe.Request{w,stress.point(ordinal,mode,districts),True{}}
@unsafe
def stress.edit.batch(n: Nat, state: D.State, +ordinal: U32, +mode: U32) -> IO(D.State):
  match n:
    case 0n: IO.pure(D.State,state)
    case 1n+k:
      D.State{w,c,p,last} = state
      do IO<D.State>:
        stamp : U32 <- P.micros()
        result : Probe.EditResult <- Probe.timed(stress.request(w,ordinal,mode))
        updated : D.State <- IO.pure(D.State,D.sample.measured(result,c,p,last,200,stamp))
        stress.edit.batch(k,updated,(ordinal + 1 : U32),mode)
def stress.batch.size(s: D.State, mode: U32) -> U32:
  D.State{W.World{_,_,_,_,_,_,_,districts},_,_,_} = s
  R.word(U32.is_eq(mode,5),(districts * 8 : U32),1)
def stress.edit(on: Bool, +state: D.State, ordinal: U32, +mode: U32) -> IO(D.State):
  match on:
    case False{}: IO.pure(D.State,state)
    case True{}:
      +batch = stress.batch.size(state,mode)
      stress.edit.batch(U32.to_nat(batch),state,(ordinal * batch : U32),mode)
def stress.edit.due(+index: U32, +warmup: U32, every: U32, +mode: U32) -> Bool:
  match every:
    case 0: False{}
    case +period:
      ((index >= warmup : U32) && U32.is_eq(((index - warmup) % period : U32),0) &&
        ((index - warmup) / period < R.word(U32.is_eq(mode,4),2,R.word(U32.is_eq(mode,5),16,75)) : U32))
def stress.camera(+index: U32, s: D.State) -> D.State:
  D.State{+w,_,p,last} = s
  W.World{_,_,_,_,_,_,_,districts} = w
  +width = F32.ceil(F32.sqrt(U32.to_f32(districts)))
  +center = ((width - 1.0) * 32.0 : F32)
  +radius = (width * 52.0 : F32)
  +angle = (U32.to_f32((index % 720 : U32)) * 0.008726646 : F32)
  +eye = {R.Vec{(center + radius * F32.sin(angle) : F32),(28.0 + (width - 1.0) * 12.0 : F32),(center + radius * F32.cos(angle) : F32)} : R.Vec}
  D.State{w,I.Control{V.Camera{eye,(3.14159265 + angle : F32),(0.0 - 0.30 : F32)},
    0,320,180,False{},False{},False{},False{},False{},False{}},p,last}
def stress.aim(+index: U32, s: D.State) -> D.State:
  D.State{w,_,p,last} = s
  +mx = (100 + index * 5 % 440 : U32)
  D.State{w,I.Control{V.Camera{R.Vec{16.0,5.0,26.0},3.14159265,(0.0 - 0.15 : F32)},
    0,mx,180,False{},False{},True{},False{},False{},False{}},p,last}
def stress.bridge(s: D.State) -> D.State:
  D.State{w,_,p,last} = s
  D.State{w,I.Control{V.Camera{R.Vec{0.0,20.0,(0.0 - 4.0 : F32)},3.14159265,(0.0 - 0.25 : F32)},
    0,320,180,False{},False{},False{},False{},False{},False{}},p,last}
def stress.follow.box(b: S.Box, offset: F32) -> R.Vec:
  S.Box{l,h,_} = b
  R.Vec.add(R.Vec.scale(R.Vec.add(l,h),0.05),R.Vec{0.0,offset,0.0})
def stress.follow.body(bs: List<&2,W.Body>) -> R.Vec:
  match bs:
    case Nil{}: R.Vec{4.4,2.0,17.4}
    case W.Body{_,_,o,_,False{},t,_} <> _: stress.follow.box(S.bounds(t),o)
    case _ <> rest: stress.follow.body(rest)
def stress.follow(s: D.State) -> D.State:
  D.State{+w,_,p,last} = s
  W.World{bs,_,_,_,_,_,_,_} = w
  +eye = R.Vec.add(stress.follow.body(bs),R.Vec{0.0,3.0,5.0})
  D.State{w,I.Control{V.Camera{eye,3.14159265,(0.0 - 0.5404195 : F32)},
    0,320,180,False{},False{},True{},False{},False{},False{}},p,last}
def stress.view(mode: U32, index: U32, s: D.State) -> D.State:
  match mode:
    case 1: stress.camera(index,s)
    case 2: stress.aim(index,s)
    case 4: stress.bridge(s)
    case 5: stress.follow(s)
    case _: stress.camera(90,s)
type Stress is Data:
  Stress{epoch: U32, index: U32, total: U32, scene: U32, warmup: U32, every: U32, mode: U32}
def stress.done(done: Bool, win: Window, state: D.State, config: Stress, end: U32, frameUs: U32,
  k: Window -> D.State -> Stress -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  match done:
    case True{}: close(win)
    case False{}: k(win, state, config, end, frameUs)
def stress.world(w: W.World, c: I.Control, +pending: List<&2,D.Sample>, last: U32,
  events: List<Event>, win: Window, +epoch: U32, +previousEnd: U32,
  now: U32, +updateEnd: U32, +sceneEnd: U32, +end: U32,
  +index: U32, +total: U32, scene: U32, warmup: U32, every: U32, mode: U32,
  k: Window -> D.State -> Stress -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  W.World{bs, +solids, +bodies, removed, status, next, budget, districts} = w
  do IO<Unit>:
    Unit <- D.sample.log((end - epoch : U32), (end - previousEnd : U32), solids, bodies,
      pending, end, (updateEnd - now : U32), (sceneEnd - updateEnd : U32), (end - sceneEnd : U32))
    stress.done(((index + 1 >= total : U32) || D.events.close(events)), win,
      D.State{W.World{bs, solids, bodies, removed, status, next, budget, districts}, c, Nil{}, D.pending.last(pending, end, last)},
      Stress{epoch, (index + 1 : U32), total, scene, warmup, every, mode}, end,
      (end - previousEnd : U32), k)
def stress.config(w: W.World, c: I.Control, pending: List<&2,D.Sample>, last: U32,
  events: List<Event>, win: Window, config: Stress, previousEnd: U32,
  now: U32, updateEnd: U32, sceneEnd: U32, end: U32,
  k: Window -> D.State -> Stress -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  Stress{epoch, index, total, scene, warmup, every, mode} = config
  stress.world(w, c, pending, last, events, win, epoch, previousEnd,
    now, updateEnd, sceneEnd, end, index, total, scene, warmup, every, mode, k)
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
  Stress{epoch, +index, total, +scene, +warmup, +every, +mode} = config
  do IO<Unit>:
    +now : U32 <- P.micros()
    updated : D.State <- stress.edit(stress.edit.due(index,warmup,every,mode),
      D.advance(state,(1.0 / 60.0 : F32)), ((index - warmup) / R.word(U32.is_eq(every,0),1,every) : U32), mode)
    viewed : D.State <- IO.pure(D.State, stress.view(mode, index, updated))
    +updateEnd : U32 <- P.micros()
    sceneState : D.State & V.Aim & String <- IO.pure(D.State & V.Aim & String, ready(viewed, frameUs))
    +sceneEnd : U32 <- P.micros()
    shown : Window & D.State & List<Event> <- show(sceneState, win)
    +end : U32 <- P.micros()
    stress.shown(shown, Stress{epoch, index, total, scene, warmup, every, mode}, previousEnd,
      now, updateEnd, sceneEnd, end, w => s => c => t => dt => stress.loop(w, s, c, t, dt))
def stress.inventory(w: W.World) -> IO(Unit):
  W.World{+bs,n,_,_,_,_,budget,districts} = w
  IO.print("world," ++ U32.show(n) ++ "," ++ U32.show(W.bodies.count(bs)) ++ "," ++
    U32.show(W.bodies.regions(bs)) ++ "," ++ U32.show(districts) ++ "," ++ U32.show(budget))
def stress.start(win: Window, +scene: U32, +warmup: U32, measured: U32, every: U32, mode: U32, budget: U32) -> IO(Unit):
  do IO<Unit>:
    +start : U32 <- P.micros()
    +world : W.World <- IO.pure(W.World, W.configured(R.word(U32.is_eq(scene,2),4,R.word(U32.is_eq(scene,3),16,1)),budget))
    +epoch : U32 <- P.micros()
    Unit <- IO.print("init," ++ U32.show(scene) ++ "," ++ U32.show((epoch - start : U32)))
    Unit <- stress.inventory(world)
    stress.loop(win, D.State{world, I.initial(), Nil{}, 0},
      Stress{epoch, 0, (warmup + measured : U32), scene, warmup, every, mode}, epoch, 0)

def start.stress(on: Bool, win: Window, now: U32, frames: U32,
  scene: U32, warmup: U32, measured: U32, every: U32, mode: U32, districts: U32, budget: U32) -> IO(Unit):
  match on:
    case True{}: stress.start(win, scene, warmup, measured, every, mode, budget)
    case False{}: loop(win,D.State{W.configured(districts,budget),I.initial(),Nil{},0},now,frames)

def configuration.budget.go(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,1,"VOXEL_BODY_BUDGET must be at most 65536")
def configuration.budget(budget: U32) -> IO(Unit):
  configuration.budget.go((budget <= 65536 : U32))
def configuration.valid.go(ok: Bool, budget: U32) -> IO(Unit):
  match ok:
    case True{}: configuration.budget(budget)
    case False{}: IO.die(Unit,1,"VOXEL_DISTRICTS must be 1, 4, or 16")
def configuration.valid(+districts: U32, budget: U32) -> IO(Unit):
  configuration.valid.go((U32.is_eq(districts,0) || U32.is_eq(districts,1) || U32.is_eq(districts,4) || U32.is_eq(districts,16)),budget)
def main() -> IO(Unit):
  do IO<Unit>:
    districtEnv : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_DISTRICTS")
    budgetEnv : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_BODY_BUDGET")
    +districts : U32 <- IO.pure(U32,number(districtEnv))
    +budget : U32 <- IO.pure(U32,number(budgetEnv))
    Unit <- configuration.valid(districts,budget)
    frames : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_FRAMES")
    stressScene : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_STRESS_SCENE")
    stressWarmup : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_STRESS_WARMUP")
    stressMeasured : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_STRESS_MEASURED")
    stressEdit : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_STRESS_EDIT_EVERY")
    stressView : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_STRESS_VIEW")
    +stressId : U32 <- IO.pure(U32, number(stressScene))
    win : Window <- IO.try(Window, Window.open("Bend Voxel Vulkan - WASD / RMB look / LMB carve / R reset", 640, 360))
    +now : U32 <- P.micros()
    start.stress((stressId > 0 : U32), win, now, number(frames),
      stressId, number(stressWarmup), number(stressMeasured), number(stressEdit), number(stressView),
      R.word(U32.is_eq(districts,0),1,districts),R.word(U32.is_eq(budget,0),2048,budget))
