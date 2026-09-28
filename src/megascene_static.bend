import Base
import ./demo.bend as D
import ./world.bend as W
import ./render.bend as V
import ./input.bend as I
import ./vulkan.bend as VK
import ./math.bend as R
import ./color.bend as Color

# Fixed, finite replay; input events never enter the world or camera. The only
# accepted external event is Close, recorded as an incomplete invocation.
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

def next(shown: Window & D.State & List<Event>, k: Window -> D.State -> IO(Unit)) -> IO(Unit):
  (win,state,events) = shown
  stopped(D.events.close(events),win,state,k)

def loop(n: Nat, win: Window, state: D.State) -> IO(Unit):
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
        aim : V.Aim <- IO.pure(V.Aim,V.Aim{R.Vec{0.0,0.0,0.0},0.0,0})
        VK.vulkan.mark(12)
        shown : Window & D.State & List<Event> <- VK.vulkan.frame(win,updated,aim,"MEGASCENE / STATIC / DEVELOPMENT OBSERVATION")
        next(shown,w => s => loop(rest,w,s))

def after(review: Bool, n: Nat, win: Window, state: D.State) -> IO(Unit):
  match review:
    case False{}: loop(n,win,state)
    case True{}:
      do IO<Unit>:
        IO.sleep(250)
        win : Window <- VK.vulkan.capture(win)
        close(win)
        VK.vulkan.mark(15)

def review(r: Result<&1,&1,U32 & String,String>) -> Bool:
  match r:
    case Done{_}: True{}
    case Fail{_}: False{}

def start(w: W.World, +camera: V.Camera, width: U32, height: U32, frames: Nat) -> IO(Unit):
  do IO<Unit>:
    VK.vulkan.mark(7)
    win : Window <- IO.try(Window,Window.open("Megascene / Static / Unqualified development observation",width,height))
    win : Window <- VK.vulkan.colors(win,Color.palette())
    VK.vulkan.mark(8)
    state : D.State = D.State{w,I.Control{camera,0,0,0,False{},False{},False{},False{},False{},False{}},Nil{},0}
    shown : Window & D.State & List<Event> <- VK.vulkan.frame(win,state,V.Aim{R.Vec{0.0,0.0,0.0},0.0,0},"MEGASCENE / STATIC / DEVELOPMENT OBSERVATION")
    mode : Result<&1,&1,U32 & String,String> <- IO.get_env("MEGASCENE_CAPTURE")
    next(shown,w => s => after(review(mode),frames,w,s))
