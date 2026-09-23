import Base
import ./vendor/bend3d.bend as R
import ./world.bend as W
import ./render.bend as V
import ./input.bend as I
import ./platform.bend as P
import ./probe.bend as Probe

type Sample is Data:
  Sample{stamp: U32, status: U32, kind: U32, carveUs: U32, connectivityUs: U32, surfaceUs: U32, finalizeUs: U32}
type State is Type:
  State{world: W.World, control: I.Control, pending: List<&2, Sample>, lastCut: U32}
def initial() -> State:
  State{W.initial(), I.initial(), Nil{}, 0}
def state.world(-T: Type, s: State, k: W.World -> I.Control -> List<&2, Sample> -> U32 -> T) -> T:
  State{w, c, p, t} = s
  k(w, c, p, t)
def selected(kind: U32, w: W.World, point: R.Vec) -> W.World:
  match kind:
    case 1:
      W.carve(w, point)
    case _:
      W.World{a, bs, n, count, _, _} = w
      W.World{a, bs, n, count, 0, 2}
def pending.add(status: U32, kind: U32, stamp: U32, p: List<&2,Sample>) -> List<&2,Sample>:
  Sample{stamp,status,kind,0,0,0,0} <> p
def status(s: U32) -> String:
  match s:
    case 1:
      "READY / CUT APPLIED"
    case 2:
      "NO REMOVABLE TARGET"
    case 4:
      "REPLAY TARGET CHECK FAILED"
    case 3:
      "FRAGMENT LIMIT REACHED - RESET TO CONTINUE"
    case _:
      "READY"
def apply.aim(aim: V.Aim, w: W.World, c: I.Control, p: List<&2, Sample>, last: U32, stamp: U32) -> State:
  V.Aim{point, _, +kind} = aim
  W.use.world(State, selected(kind, w, point), a => bs => n => count => r => +status =>
    State{W.World{a, bs, n, count, r, status}, c, pending.add(status, kind, stamp, p), last})
def apply.cut(doit: Bool, w: W.World, +c: I.Control, p: List<&2, Sample>, last: U32, stamp: U32) -> State:
  match doit:
    case False{}:
      State{w, c, p, last}
    case True{}:
      W.World{a, +bs, n, count, r, status} = w
      apply.aim(I.aim(c, bs), W.World{a, bs, n, count, r, status}, c, p, last, stamp)
def apply.reset(reset: Bool, cut: Bool, w: W.World, c: I.Control, p: List<&2, Sample>, last: U32, stamp: U32) -> State:
  match reset:
    case True{}:
      State{W.initial(), I.reset.state(c), Nil{}, 0}
    case False{}:
      apply.cut(cut, w, c, p, last, stamp)
def event.control(+c: I.Control, w: W.World, p: List<&2, Sample>, last: U32, stamp: U32) -> State:
  I.Control{_, _, _, _, _, _, _, cut, reset, _} = c
  apply.reset(reset, cut, w, c, p, last, stamp)
def event(e: Event, s: State, stamp: U32) -> State:
  State{w, c, p, last} = s
  event.control(I.event(e, c), w, p, last, stamp)
def events(es: List<Event>, s: State, +stamp: U32) -> State:
  match es:
    case Nil{}:
      s
    case e <> rest:
      events(rest, event(e, s, stamp), stamp)
def advance(s: State, +dt: F32) -> State:
  State{w, c, p, last} = s
  State{W.step(w, dt), I.step(c, dt), p, last}
def target(kind: U32) -> String:
  match kind:
    case 1:
      "CARVE / 20 CM"
    case 2:
      "PROTECTED ANCHOR"
    case 3:
      "PROTECTED FLOOR"
    case _:
      "NO TARGET"
def hud(n: U32, count: U32, removed: U32, s: U32, kind: U32, frameUs: U32, cutUs: U32) -> String:
  "BEND VOXEL / FIRST DEMO\n" ++
  "VOXELS " ++ U32.show(n) ++ "  BODIES " ++ U32.show(count) ++ "/64  REMOVED " ++ U32.show(removed) ++ "\n" ++
  "FRAME " ++ U32.show((frameUs / 1000 : U32)) ++ " MS  CUT " ++ U32.show((cutUs / 1000 : U32)) ++ " MS\n" ++
  target(kind) ++ "\n" ++ status(s) ++ "\n" ++
  "WASD MOVE  QE UP/DOWN  RMB LOOK  LMB CUT  R RESET  ESC RELEASE"
def scene.aim(+aim: V.Aim, +camera: V.Camera, s: State, bs: List<&2, W.Body>, n: U32, count: U32, r: U32, status: U32, frameUs: U32, last: U32) -> State & R.Cells & String:
  V.Aim{_, _, +kind} = aim
  (s, V.preview((kind > 0 : U32), aim, camera, V.build(bs, camera, aim)), hud(n, count, r, status, kind, frameUs, last))

def scene(s: State, frameUs: U32) -> State & R.Cells & String:
  State{w, +c, p, +last} = s
  W.World{a, +bs, +n, +count, +r, +status} = w
  I.Control{camera, _, _, _, _, _, _, _, _, _} = c
  scene.aim(I.aim(c, bs), camera, State{W.World{a, bs, n, count, r, status}, c, p, last}, bs, n, count, r, status, frameUs, last)
def frame.unpack(-T: Type, r: Image & R.Cells, k: Image -> R.Cells -> T) -> T:
  (im, cells) = r
  k(im, cells)
def show.pack(r: Window & Image & List<Event>, s: State) -> IO(Window & Image & List<Event> & State):
  (win, im, es) = r
  IO.pure(Window & Image & List<Event> & State, (win, im, es, s))

def show.drawn(r: Image & R.Cells, win: Window, s: State, hud: String) -> IO(Window & Image & List<Event> & State):
  (im, cells) = r
  do IO<Window & Image & List<Event> & State>:
    unused : R.Cells <- IO.pure(R.Cells,R.Cells.drop(4n,cells))
    shown : Window & Image & List<Event> <- P.present(win, im, hud)
    show.pack(shown, s)
def show.ready(r: State & R.Cells & String, win: Window, old: Image) -> IO(Window & Image & List<Event> & State):
  (s, cells, hud) = r
  do IO<Window & Image & List<Event> & State>:
    +seam : U32 <- P.micros()
    drawn : Image & R.Cells <- IO.pure(Image & R.Cells, V.frame(cells, old))
    show.drawn(drawn, win, s, hud)
def pending.last(p: List<&2, Sample>, +end: U32, last: U32) -> U32:
  match p:
    case Nil{}:
      last
    case Sample{t,status,_,_,_,_,_} <> rest:
      pending.last(rest,end,R.word(U32.is_eq(status,1),(end - t : U32),last))
def loop.cont(quit: Bool, win: Window, s: State, old: Image, stamp: U32, frameUs: U32, remaining: U32, k: Window -> State -> Image -> U32 -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  match quit:
    case True{}:
      Window.close(win)
    case False{}:
      k(win, s, old, stamp, frameUs, remaining)
def loop.next(+c: I.Control, win: Window, s: State, im: Image, now: U32, dt: U32, +remaining: U32, k: Window -> State -> Image -> U32 -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  I.Control{_, _, _, _, _, _, _, _, _, quit} = c
  loop.cont((quit || U32.is_eq(remaining, 1)), win, s, im, now, dt, R.word((remaining > 0 : U32), (remaining - 1 : U32), 0), k)
def loop.after(win: Window, im: Image, es: List<Event>, s: State, +before: U32, +now: U32, +remaining: U32, k: Window -> State -> Image -> U32 -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  State{w, c, pending, last} = s
  state.world(IO(Unit), events(es, State{w, c, Nil{}, pending.last(pending, now, last)}, now), w => +c => p => last =>
    loop.next(c, win, State{w, c, p, last}, im, before, (now - before : U32), remaining, k))
def loop.shown(r: Window & Image & List<Event> & State, +before: U32, +remaining: U32, k: Window -> State -> Image -> U32 -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  (win, im, es, s) = r
  do IO<Unit>:
    +now : U32 <- P.micros()
    loop.after(win, im, es, s, before, now, remaining, k)
@unsafe
def loop(win: Window, s: State, old: Image, +stamp: U32, +frameUs: U32, remaining: U32) -> IO(Unit):
  do IO<Unit>:
    +now : U32 <- P.micros()
    shown : Window & Image & List<Event> & State <- show.ready(scene(advance(s, R.min(0.1, (U32.to_f32((now - stamp : U32)) / 1000000.0 : F32))), frameUs), win, old)
    loop.shown(shown, now, remaining, w => s => im => t => dt => r => loop(w, s, im, t, dt, r))
def env.read(r: Maybe<&2, U32>) -> U32:
  match r:
    case Some{n}:
      n
    case None{}:
      0
def env.number(r: Result<&1, &1, U32 & String, String>) -> U32:
  match r:
    case Done{s}:
      env.read(U32.read(s))
    case Fail{_}:
      0
def replay.camera(s: State, +elapsed: U32) -> State:
  State{w, _, p, last} = s
  +time = U32.to_f32(((elapsed + 15000000) % 20000000 : U32))
  +angle = R.pick((time >= 13000000.0 : F32), ((time - 13000000.0) * 0.0000003 : F32), 0.0)
  +eye = {R.Vec{(6.0 * F32.sin(angle) : F32), 2.8, (6.0 * F32.cos(angle) : F32)} : R.Vec}
  State{w, I.Control{V.Camera{eye, (3.14159265 + angle : F32), (0.0 - 0.22 : F32)}, 0, 260, 220, False{}, False{}, True{}, False{}, False{}, False{}}, p, last}
def bench.logcuts(p: List<&2, Sample>, +end: U32) -> IO(Unit):
  match p:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Sample{+t,+status,kind,_,_,_,_} <> rest:
      do IO<Unit>:
        Unit <- IO.print(Bool.pick(String,U32.is_eq(status,1),"cut,","attempt,") ++ U32.show(t) ++ "," ++ U32.show((end - t : U32)) ++ "," ++ U32.show(status) ++ "," ++ U32.show(kind))
        bench.logcuts(rest, end)
def bench.edits(p: List<&2,Sample>, +elapsed: U32) -> IO(Unit):
  match p:
    case Nil{}: IO.pure(Unit,Unit{})
    case Sample{stamp,status,kind,cut,connectivity,surface,finalize} <> rest:
      do IO<Unit>:
        Unit <- IO.print("edit," ++ U32.show(elapsed) ++ "," ++ U32.show(stamp) ++ "," ++ U32.show(kind) ++ "," ++ U32.show(status) ++ "," ++ U32.show(cut) ++ "," ++ U32.show(connectivity) ++ "," ++ U32.show(surface) ++ "," ++ U32.show(finalize))
        bench.edits(rest,elapsed)
def bench.cut.sum(p: List<&2,Sample>) -> U32:
  match p:
    case Nil{}: 0
    case Sample{_,_,_,cut,_,_,_} <> rest: (cut + bench.cut.sum(rest) : U32)
def bench.connectivity.sum(p: List<&2,Sample>) -> U32:
  match p:
    case Nil{}: 0
    case Sample{_,_,_,_,connectivity,_,_} <> rest: (connectivity + bench.connectivity.sum(rest) : U32)
def bench.surface.sum(p: List<&2,Sample>) -> U32:
  match p:
    case Nil{}: 0
    case Sample{_,_,_,_,_,surface,_} <> rest: (surface + bench.surface.sum(rest) : U32)
def bench.finalize.sum(p: List<&2,Sample>) -> U32:
  match p:
    case Nil{}: 0
    case Sample{_,_,_,_,_,_,finalize} <> rest: (finalize + bench.finalize.sum(rest) : U32)
def bench.log(+elapsed: U32, +frame: U32, n: U32, c: U32, +p: List<&2,Sample>, end: U32, +update: U32, +scene: U32, +render: U32, +dispose: U32, +present: U32) -> IO(Unit):
  +cut = bench.cut.sum(p)
  +connectivity = bench.connectivity.sum(p)
  +surface = bench.surface.sum(p)
  +finalize = bench.finalize.sum(p)
  do IO<Unit>:
    Unit <- IO.print("frame," ++ U32.show(elapsed) ++ "," ++ U32.show(frame) ++ "," ++ U32.show(n) ++ "," ++ U32.show(c))
    Unit <- IO.print("stage," ++ U32.show(elapsed) ++ "," ++ U32.show(cut) ++ "," ++ U32.show(connectivity) ++ "," ++ U32.show(surface) ++ "," ++ U32.show(finalize) ++ "," ++ U32.show((update - cut - connectivity - surface - finalize : U32)) ++ "," ++ U32.show(scene) ++ "," ++ U32.show(render) ++ "," ++ U32.show(dispose) ++ "," ++ U32.show(present) ++ "," ++ U32.show((frame - update - scene - render - dispose - present : U32)))
    Unit <- bench.logcuts(p,end)
    bench.edits(p,elapsed)
def bench.finish(done: Bool, win: Window, s: State, im: Image, epoch: U32, end: U32, elapsed: U32, frame: U32, k: Window -> State -> Image -> U32 -> U32 -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  match done:
    case True{}:
      Window.close(win)
    case False{}:
      k(win, s, im, epoch, end, elapsed, frame)
def events.close(es: List<Event>) -> Bool:
  match es:
    case Nil{}: False{}
    case Close{} <> rest: True{}
    case _ <> rest: events.close(rest)
def bench.after(update: U32, scene: U32, render: U32, dispose: U32, present: U32, quit: Bool, win: Window, im: Image, s: State, +epoch: U32, previousEnd: U32, elapsed: U32, +end: U32, k: Window -> State -> Image -> U32 -> U32 -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  State{w, c, +pending, last} = s
  W.World{a, bs, +n, +count, r, status} = w
  +total = (end - epoch : U32)
  +dt = (end - previousEnd : U32)
  do IO<Unit>:
    Unit <- bench.log(total,dt,n,count,pending,end,update,scene,render,dispose,present)
    bench.finish((quit || (total >= 65000000 : U32)), win, State{W.World{a, bs, n, count, r, status}, c, Nil{}, pending.last(pending, end, last)}, im, epoch, end, elapsed, dt, k)
def bench.presented(r: Window & Image & List<Event>, s: State, +epoch: U32, stamp: U32, elapsed: U32, update: U32, scene: U32, render: U32, dispose: U32, presentStart: U32, k: Window -> State -> Image -> U32 -> U32 -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  (win,im,es) = r
  do IO<Unit>:
    +end : U32 <- P.micros()
    bench.after(update,scene,render,dispose,(end - presentStart : U32),events.close(es),win,im,s,epoch,stamp,elapsed,end,k)
def bench.drawn(r: Image & R.Cells, s: State, hud: String, win: Window, epoch: U32, stamp: U32, elapsed: U32, update: U32, scene: U32, renderStart: U32, k: Window -> State -> Image -> U32 -> U32 -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  (im,cells) = r
  do IO<Unit>:
    +renderEnd : U32 <- P.micros()
    unused : R.Cells <- IO.pure(R.Cells,R.Cells.drop(4n,cells))
    +disposed : U32 <- P.micros()
    shown : Window & Image & List<Event> <- P.present(win,im,hud)
    bench.presented(shown,s,epoch,stamp,elapsed,update,scene,(renderEnd - renderStart : U32),(disposed - renderEnd : U32),disposed,k)
def bench.render(r: State & R.Cells & String, win: Window, old: Image, epoch: U32, stamp: U32, elapsed: U32, update: U32, scene: U32, renderStart: U32, k: Window -> State -> Image -> U32 -> U32 -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  (s,cells,hud) = r
  do IO<Unit>:
    drawn : Image & R.Cells <- IO.pure(Image & R.Cells,V.frame(cells,old))
    bench.drawn(drawn,s,hud,win,epoch,stamp,elapsed,update,scene,renderStart,k)
def replay.point(+i: U32) -> R.Vec:
  +left = (i < 6 : U32)
  +j = ((i - 2) % 4 : U32)
  R.Vec{(R.pick(left, (0.0 - 1.0 : F32), 1.0) + R.pick((j < 2 : U32), (0.0 - 0.15 : F32), 0.15) : F32), 1.05, R.pick(U32.is_eq((j % 2 : U32), 0), (0.0 - 0.15 : F32), 0.15)}
def replay.ready(ok: Bool, w: W.World, i: U32, offset: F32) -> Probe.Request:
  match ok:
    case True{}: Probe.Request{w,R.Vec.add(W.xyz(i),R.Vec{0.0,offset,0.0}),True{}}
    case False{}:
      W.World{a,bs,n,c,_,_} = w
      Probe.Request{W.World{a,bs,n,c,0,4},R.Vec{0.0,0.0,0.0},False{}}
def replay.voxel(w: W.World, +i: U32, moving: Bool) -> Probe.Request:
  W.World{a,+bs,n,c,r,status} = w
  W.pair(Array<U32>,U32,Probe.Request,Array.get(U32,a,i),a => +owner =>
    W.vec(Probe.Request,W.body.find(bs,owner),+offset => +speed => bottom =>
      replay.ready(((owner > 1 : U32) && Bool.pick(Bool,moving,(speed < 0.0 : F32),((F32.abs(speed) < 0.00001) && (F32.abs((offset + bottom : F32)) < 0.00001) : F32))),W.World{a,bs,n,c,r,status},i,offset)))
def replay.request(i: U32, w: W.World) -> Probe.Request:
  match i:
    case 1: Probe.Request{w,R.Vec{(0.0 - 1.0 : F32),1.05,0.3},True{}}
    case 10: replay.voxel(w,10540,True{})
    case 11: replay.voxel(w,800,False{})
    case 12: Probe.Request{selected(2,w,R.Vec{0.0,0.0,0.0}),R.Vec{0.0,0.0,0.0},False{}}
    case 13: Probe.Request{selected(0,w,R.Vec{0.0,0.0,0.0}),R.Vec{0.0,0.0,0.0},False{}}
    case +other: Probe.Request{w,replay.point(other),True{}}
def replay.world(i: U32, w: W.World) -> W.World:
  Probe.run(replay.request(i,w))
def replay.apply(i: U32, s: State, stamp: U32) -> State:
  match i:
    case 0:
      initial()
    case +other:
      State{w, c, p, last} = s
      W.use.world(State, replay.world(other, w), a => bs => n => count => r => +status =>
        State{W.World{a, bs, n, count, r, status}, c, pending.add(status,(other + 100 : U32),stamp,p), last})
def replay.when(on: Bool, i: U32, s: State, stamp: U32) -> State:
  match on:
    case True{}:
      replay.apply(i, s, stamp)
    case False{}:
      s

def replay.time(i: U32) -> U32:
  match i:
    case 0: 0
    case 1: 1000000
    case 2: 3000000
    case 3: 3200000
    case 4: 3400000
    case 5: 3600000
    case 6: 6000000
    case 7: 6200000
    case 8: 6400000
    case 9: 6600000
    case 10: 6800000
    case 11: 9000000
    case 12: 11000000
    case _: 12000000

def replay.scan(n: Nat, +i: U32, +previous: U32, +elapsed: U32, +epoch: U32, s: State) -> State:
  match n:
    case 0n:
      s
    case 1n+k:
      +due = (5000000 + i / 14 * 20000000 + replay.time((i % 14 : U32)) : U32)
      replay.scan(k, (i + 1 : U32), previous, elapsed, epoch, replay.when(((due > previous) && (due <= elapsed) : U32), (i % 14 : U32), s, (epoch + due : U32)))
def replay.measured(r: Probe.EditResult, c: I.Control, p: List<&2,Sample>, last: U32, kind: U32, stamp: U32) -> State:
  Probe.EditResult{w,cut,connectivity,surface,finalize} = r
  W.use.world(State,w,a => bs => n => count => r => +status =>
    State{W.World{a,bs,n,count,r,status},c,Sample{stamp,status,kind,cut,connectivity,surface,finalize} <> p,last})
def replay.apply.timed(i: U32, s: State, stamp: U32) -> IO(State):
  match i:
    case 0: IO.pure(State,initial())
    case +other:
      State{w,c,p,last} = s
      do IO<State>:
        measured : Probe.EditResult <- Probe.timed(replay.request(other,w))
        IO.pure(State,replay.measured(measured,c,p,last,(other + 100 : U32),stamp))
def replay.when.timed(on: Bool, i: U32, s: State, stamp: U32) -> IO(State):
  match on:
    case False{}: IO.pure(State,s)
    case True{}: replay.apply.timed(i,s,stamp)
def replay.scan.timed(n: Nat, +i: U32, +previous: U32, +elapsed: U32, +epoch: U32, s: State) -> IO(State):
  match n:
    case 0n: IO.pure(State,s)
    case 1n+k:
      +due = (5000000 + i / 14 * 20000000 + replay.time((i % 14 : U32)) : U32)
      do IO<State>:
        next : State <- replay.when.timed(((due > previous) && (due <= elapsed) : U32),(i % 14 : U32),s,(epoch + due : U32))
        replay.scan.timed(k,(i + 1 : U32),previous,elapsed,epoch,next)
@unsafe
def bench.loop(win: Window, s: State, old: Image, +epoch: U32, +stamp: U32, +previous: U32, +frameUs: U32) -> IO(Unit):
  do IO<Unit>:
    +now : U32 <- P.micros()
    updated : State <- replay.scan.timed(42n,0,previous,(now - epoch : U32),epoch,advance(s,(U32.to_f32((now - epoch - previous : U32)) / 1000000.0 : F32)))
    camera : State <- IO.pure(State,replay.camera(updated,(now - epoch : U32)))
    +updateEnd : U32 <- P.micros()
    ready : State & R.Cells & String <- IO.pure(State & R.Cells & String,scene(camera,frameUs))
    +sceneEnd : U32 <- P.micros()
    bench.render(ready,win,old,epoch,stamp,(now - epoch : U32),(updateEnd - now : U32),(sceneEnd - updateEnd : U32),sceneEnd,
      w => s => im => e => t => elapsed => dt => bench.loop(w,s,im,e,t,elapsed,dt))
def start(benchmark: Bool, win: Window, +now: U32, limit: U32) -> IO(Unit):
  match benchmark:
    case True{}:
      bench.loop(win, initial(), Pix{0}, now, now, 0, 0)
    case False{}:
      loop(win, initial(), Pix{0}, now, 0, limit)
def main() -> IO(Unit):
  do IO<Unit>:
    benchmark : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_BENCH")
    maxFrames : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_FRAMES")
    win : Window <- IO.try(Window, Window.open("Bend Voxel - WASD move / RMB look / LMB carve / R reset", 640, 360))
    +now : U32 <- P.micros()
    start((env.number(benchmark) > 0 : U32), win, now, env.number(maxFrames))

# Reproducible 20-second cycle. Benchmark times include queueing from
# the scheduled command timestamp to the completed visible frame.
