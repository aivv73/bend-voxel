import Base
import ./demo.bend as D
import ./world.bend as W
import ./render.bend as V
import ./input.bend as I
import ./vulkan.bend as VK
import ./math.bend as R
import ./color.bend as Color
import ./megascene_edit.bend as E

def close(win: Window) -> IO(Unit):
  do IO<Unit>:
    VK.vulkan.mark(13)
    win : Window <- VK.vulkan.release(win)
    Window.close(win)
    VK.vulkan.mark(14)

def stopped(done: Bool, win: Window, state: D.State,
  k: Window -> D.State -> IO(Unit)) -> IO(Unit):
  match done:
    case True{}:
      do IO<Unit>:
        VK.vulkan.mark(17)
        close(win)
    case False{}: k(win,state)

def captured(enabled: Bool, win: Window) -> IO(Window):
  match enabled:
    case True{}: VK.vulkan.capture(win)
    case False{}: IO.pure(Window,win)

def next(shown: Window & D.State & List<Event>, enabled: Bool, k: Window -> D.State -> IO(Unit)) -> IO(Unit):
  (win,state,events) = shown
  do IO<Unit>:
    win : Window <- captured(enabled,win)
    stopped(D.events.close(events),win,state,k)

def validation(r: Result<&1,&1,U32 & String,String>) -> Bool:
  match r:
    case Done{_}: True{}
    case Fail{_}: False{}

def camera(s: D.State, cam: V.Camera) -> D.State:
  D.State{world,control,pending,last} = s
  I.Control{_,keys,mx,my,looking,left,focused,cut,reset,quit} = control
  D.State{world,I.Control{cam,keys,mx,my,looking,left,focused,cut,reset,quit},pending,last}

def edit(state: D.State, +point: R.Vec, +action: U32) -> IO(D.State):
  D.State{+world,control,pending,last} = state
  do IO<D.State>:
    VK.vulkan.editbegin(action,point)
    VK.vulkan.mark(19)
    E.guard(world,point)
    prepared : W.Edit <- IO.pure(W.Edit,W.carve.prepare(world,point))
    VK.vulkan.mark(20)
    VK.vulkan.mark(21)
    classified : W.EditClassification <- IO.pure(W.EditClassification,W.carve.classify(prepared))
    VK.vulkan.mark(22)
    VK.vulkan.mark(23)
    surfaces : W.EditSurfaces <- IO.pure(W.EditSurfaces,W.carve.surfaces(classified))
    VK.vulkan.mark(24)
    VK.vulkan.mark(25)
    +world : W.World <- IO.pure(W.World,W.carve.finalize(surfaces))
    VK.vulkan.mark(26)
    VK.vulkan.editrecord(world,action,point)
    return D.State{world,control,pending,last}

def action(enabled: Bool, state: D.State, point: R.Vec) -> IO(D.State):
  match enabled:
    case True{}: edit(state,point,0)
    case False{}: IO.pure(D.State,state)

def loop(n: Nat, +point: R.Vec, +index: U32, +width: U32, +height: U32, +enabled: Bool, win: Window, state: D.State) -> IO(Unit):
  match n:
    case 0n:
      do IO<Unit>:
        close(win)
        VK.vulkan.mark(15)
    case 1n+rest:
      do IO<Unit>:
        VK.vulkan.mark(9)
        updated : D.State <- IO.pure(D.State,D.advance(state,(1.0 / 60.0 : F32)))
        VK.vulkan.mark(10)
        updated : D.State <- action(U32.is_eq(index,121),updated,point)
        VK.vulkan.mark(11)
        cam : V.Camera <- VK.vulkan.route(index,width,height)
        updated : D.State = camera(updated,cam)
        VK.vulkan.mark(12)
        shown : Window & D.State & List<Event> <- VK.vulkan.frame(win,updated,V.Aim{R.Vec{0.0,0.0,0.0},0.0,0},"MEGASCENE / LOCALIZED CUT / DEVELOPMENT OBSERVATION")
        next(shown,enabled,w => s => loop(rest,point,(index + 1 : U32),width,height,enabled,w,s))

def start(w: W.World, +point: R.Vec, +width: U32, +height: U32, frames: Nat) -> IO(Unit):
  do IO<Unit>:
    VK.vulkan.mark(7)
    win : Window <- IO.try(Window,Window.open("Megascene / Localized cut / Unqualified development observation",width,height))
    win : Window <- VK.vulkan.colors(win,Color.palette())
    VK.vulkan.mark(8)
    cam : V.Camera <- VK.vulkan.route(0,width,height)
    state : D.State = D.State{w,I.Control{cam,0,0,0,False{},False{},False{},False{},False{},False{}},Nil{},0}
    shown : Window & D.State & List<Event> <- VK.vulkan.frame(win,state,V.Aim{R.Vec{0.0,0.0,0.0},0.0,0},"MEGASCENE / LOCALIZED CUT / DEVELOPMENT OBSERVATION")
    mode : Result<&1,&1,U32 & String,String> <- IO.get_env("MEGASCENE_VALIDATE")
    +enabled : Bool = validation(mode)
    next(shown,enabled,w => s => loop(frames,point,1,width,height,enabled,w,s))
