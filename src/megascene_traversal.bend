import Base
import ./demo.bend as D
import ./world.bend as W
import ./render.bend as V
import ./input.bend as I
import ./vulkan.bend as VK
import ./math.bend as R
import ./color.bend as Color

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

def loop(n: Nat, +index: U32, +width: U32, +height: U32, +enabled: Bool, win: Window, state: D.State) -> IO(Unit):
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
        VK.vulkan.mark(11)
        cam : V.Camera <- VK.vulkan.route(index,width,height)
        updated : D.State = camera(updated,cam)
        VK.vulkan.mark(12)
        shown : Window & D.State & List<Event> <- VK.vulkan.frame(win,updated,V.Aim{R.Vec{0.0,0.0,0.0},0.0,0},"MEGASCENE / TRAVERSAL / DEVELOPMENT OBSERVATION")
        next(shown,enabled,w => s => loop(rest,(index + 1 : U32),width,height,enabled,w,s))

def start(w: W.World, +width: U32, +height: U32, frames: Nat) -> IO(Unit):
  do IO<Unit>:
    VK.vulkan.mark(7)
    win : Window <- IO.try(Window,Window.open("Megascene / Traversal / Unqualified development observation",width,height))
    win : Window <- VK.vulkan.colors(win,Color.palette())
    VK.vulkan.mark(8)
    cam : V.Camera <- VK.vulkan.route(0,width,height)
    state : D.State = D.State{w,I.Control{cam,0,0,0,False{},False{},False{},False{},False{},False{}},Nil{},0}
    shown : Window & D.State & List<Event> <- VK.vulkan.frame(win,state,V.Aim{R.Vec{0.0,0.0,0.0},0.0,0},"MEGASCENE / TRAVERSAL / DEVELOPMENT OBSERVATION")
    mode : Result<&1,&1,U32 & String,String> <- IO.get_env("MEGASCENE_VALIDATE")
    +enabled : Bool = validation(mode)
    next(shown,enabled,w => s => loop(frames,1,width,height,enabled,w,s))
