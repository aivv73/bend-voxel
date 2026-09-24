import Base
import ./math.bend as R
import ./world.bend as W
import ./render.bend as V
import ./input.bend as I
import ./platform.bend as P
import ./probe.bend as Probe

type Sample is Data:
  Sample{stamp: U32, status: U32, kind: U32, carveUs: U32, connectivityUs: U32, surfaceUs: U32, finalizeUs: U32}
type State is Data:
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
      W.status(w,2)
def pending.add(status: U32, kind: U32, stamp: U32, p: List<&2,Sample>) -> List<&2,Sample>:
  Sample{stamp,status,kind,0,0,0,0} <> p
def status(s: U32) -> String:
  match s:
    case 1:
      "READY / CUT APPLIED"
    case 2:
      "NO REMOVABLE TARGET"
    case 3:
      "BODY BUDGET REACHED - CUT REJECTED"
    case _:
      "READY"
def apply.aim(aim: V.Aim, w: W.World, c: I.Control, p: List<&2, Sample>, last: U32, stamp: U32) -> State:
  V.Aim{point, _, +kind} = aim
  W.use.world(State, selected(kind, w, point), bs => n => count => r => +status => next => budget => districts =>
    State{W.World{bs, n, count, r, status, next, budget, districts}, c, pending.add(status, kind, stamp, p), last})
def apply.cut(doit: Bool, w: W.World, +c: I.Control, p: List<&2, Sample>, last: U32, stamp: U32) -> State:
  match doit:
    case False{}:
      State{w, c, p, last}
    case True{}:
      W.World{+bs, n, count, r, status, next, budget, districts} = w
      apply.aim(I.aim(c, bs), W.World{bs, n, count, r, status, next, budget, districts}, c, p, last, stamp)
def apply.reset(reset: Bool, cut: Bool, w: W.World, c: I.Control, p: List<&2, Sample>, last: U32, stamp: U32) -> State:
  match reset:
    case True{}:
      State{W.reset(w), I.reset.state(c), Nil{}, 0}
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
def hud(n: U32, count: U32, budget: U32, removed: U32, s: U32, kind: U32, frameUs: U32, cutUs: U32) -> String:
  "BEND VOXEL / DEMOLITION DISTRICT\n" ++
  "VOXELS " ++ U32.show(n) ++ "  BODIES " ++ U32.show(count) ++ "/" ++ U32.show(budget) ++ "  REMOVED " ++ U32.show(removed) ++ "\n" ++
  "FRAME " ++ U32.show((frameUs / 1000 : U32)) ++ " MS  CUT " ++ U32.show((cutUs / 1000 : U32)) ++ " MS\n" ++
  target(kind) ++ "\n" ++ status(s) ++ "\n" ++
  "WASD MOVE  QE UP/DOWN  RMB LOOK  LMB CUT  R RESET  ESC RELEASE"
def pending.last(p: List<&2, Sample>, +end: U32, last: U32) -> U32:
  match p:
    case Nil{}:
      last
    case Sample{t,status,_,_,_,_,_} <> rest:
      pending.last(rest,end,R.word(U32.is_eq(status,1),(end - t : U32),last))
def env.read(r: Maybe<&2, U32>) -> U32:
  match r:
    case Some{n}:
      n
    case None{}:
      0
def sample.logcuts(p: List<&2, Sample>, +end: U32) -> IO(Unit):
  match p:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Sample{+t,+status,kind,_,_,_,_} <> rest:
      do IO<Unit>:
        Unit <- IO.print(Bool.pick(String,U32.is_eq(status,1),"cut,","attempt,") ++ U32.show(t) ++ "," ++ U32.show((end - t : U32)) ++ "," ++ U32.show(status) ++ "," ++ U32.show(kind))
        sample.logcuts(rest, end)
def sample.edits(p: List<&2,Sample>, +elapsed: U32) -> IO(Unit):
  match p:
    case Nil{}: IO.pure(Unit,Unit{})
    case Sample{stamp,status,kind,cut,connectivity,surface,finalize} <> rest:
      do IO<Unit>:
        Unit <- IO.print("edit," ++ U32.show(elapsed) ++ "," ++ U32.show(stamp) ++ "," ++ U32.show(kind) ++ "," ++ U32.show(status) ++ "," ++ U32.show(cut) ++ "," ++ U32.show(connectivity) ++ "," ++ U32.show(surface) ++ "," ++ U32.show(finalize))
        sample.edits(rest,elapsed)
def sample.cut.sum(p: List<&2,Sample>) -> U32:
  match p:
    case Nil{}: 0
    case Sample{_,_,_,cut,_,_,_} <> rest: (cut + sample.cut.sum(rest) : U32)
def sample.connectivity.sum(p: List<&2,Sample>) -> U32:
  match p:
    case Nil{}: 0
    case Sample{_,_,_,_,connectivity,_,_} <> rest: (connectivity + sample.connectivity.sum(rest) : U32)
def sample.surface.sum(p: List<&2,Sample>) -> U32:
  match p:
    case Nil{}: 0
    case Sample{_,_,_,_,_,surface,_} <> rest: (surface + sample.surface.sum(rest) : U32)
def sample.finalize.sum(p: List<&2,Sample>) -> U32:
  match p:
    case Nil{}: 0
    case Sample{_,_,_,_,_,_,finalize} <> rest: (finalize + sample.finalize.sum(rest) : U32)
def sample.log(+elapsed: U32, +frame: U32, n: U32, c: U32, +p: List<&2,Sample>, end: U32, +update: U32, +scene: U32, +render: U32) -> IO(Unit):
  +cut = sample.cut.sum(p)
  +connectivity = sample.connectivity.sum(p)
  +surface = sample.surface.sum(p)
  +finalize = sample.finalize.sum(p)
  do IO<Unit>:
    Unit <- IO.print("frame," ++ U32.show(elapsed) ++ "," ++ U32.show(frame) ++ "," ++ U32.show(n) ++ "," ++ U32.show(c))
    Unit <- IO.print("stage," ++ U32.show(elapsed) ++ "," ++ U32.show(cut) ++ "," ++ U32.show(connectivity) ++ "," ++ U32.show(surface) ++ "," ++ U32.show(finalize) ++ "," ++ U32.show((update - cut - connectivity - surface - finalize : U32)) ++ "," ++ U32.show(scene) ++ "," ++ U32.show(render) ++ "," ++ U32.show((frame - update - scene - render : U32)))
    Unit <- sample.logcuts(p,end)
    sample.edits(p,elapsed)
def events.close(es: List<Event>) -> Bool:
  match es:
    case Nil{}: False{}
    case Close{} <> rest: True{}
    case _ <> rest: events.close(rest)
def sample.measured(r: Probe.EditResult, c: I.Control, p: List<&2,Sample>, last: U32, kind: U32, stamp: U32) -> State:
  Probe.EditResult{w,cut,connectivity,surface,finalize} = r
  W.use.world(State,w,bs => n => count => r => +status => next => budget => districts =>
    State{W.World{bs,n,count,r,status,next,budget,districts},c,Sample{stamp,status,kind,cut,connectivity,surface,finalize} <> p,last})
