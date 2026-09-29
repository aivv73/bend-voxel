import Base
import ./demo.bend as D
import ./world.bend as W
import ./render.bend as V
import ./input.bend as I
import ./vulkan.bend as VK
import ./math.bend as R
import ./color.bend as Color
import ./megascene_localized.bend as L

type Cut is Data:
  Cut{frame: U32, action: U32, point: R.Vec, expected: U32}

def required(ok: Bool, state: D.State) -> IO(D.State):
  match ok:
    case True{}: IO.pure(D.State,state)
    case False{}: IO.die(D.State,2,"required history cut rejected, empty, or mismatched")

def accepted(state: D.State, expected: U32) -> IO(D.State):
  D.State{+world,control,pending,last} = state
  W.World{_,_,_,removed,status,_,_} = world
  required(U32.is_eq(status,1) && U32.is_eq(removed,expected),D.State{world,control,pending,last})

def apply(due: Bool, cuts: List<&2,Cut>, state: D.State) -> IO(List<&2,Cut> & D.State):
  match due cuts:
    case True{} Cut{_,action,point,expected} <> rest:
      do IO<List<&2,Cut> & D.State>:
        state : D.State <- L.edit(state,point,action)
        state : D.State <- accepted(state,expected)
        return (rest,state)
    case _ cuts: IO.pure(List<&2,Cut> & D.State,(cuts,state))

def action(index: U32, cuts: List<&2,Cut>, state: D.State) -> IO(List<&2,Cut> & D.State):
  match cuts:
    case Nil{}: IO.pure(List<&2,Cut> & D.State,(Nil{},state))
    case +cut <> rest:
      Cut{frame,_,_,_} = cut
      apply(U32.is_eq(index,frame),cut <> rest,state)

def show(result: List<&2,Cut> & D.State, index: U32, width: U32, height: U32, enabled: Bool, win: Window,
  k: List<&2,Cut> -> Window -> D.State -> IO(Unit)) -> IO(Unit):
  (cuts,updated) = result
  do IO<Unit>:
    VK.vulkan.mark(11)
    cam : V.Camera <- VK.vulkan.route(index,width,height)
    updated : D.State = L.camera(updated,cam)
    VK.vulkan.mark(12)
    shown : Window & D.State & List<Event> <- VK.vulkan.frame(win,updated,V.Aim{R.Vec{0.0,0.0,0.0},0.0,0},"MEGASCENE / IRREGULAR HISTORY / DEVELOPMENT OBSERVATION")
    L.next(shown,enabled,w => s => k(cuts,w,s))

def loop(n: Nat, cuts: List<&2,Cut>, +index: U32, +width: U32, +height: U32, +enabled: Bool, win: Window, state: D.State) -> IO(Unit):
  match n:
    case 0n:
      do IO<Unit>:
        VK.vulkan.audit(state,V.Aim{R.Vec{0.0,0.0,0.0},0.0,0})
        L.close(win)
        VK.vulkan.mark(15)
    case 1n+rest:
      do IO<Unit>:
        VK.vulkan.mark(9)
        updated : D.State <- IO.pure(D.State,D.advance(state,(1.0 / 60.0 : F32)))
        VK.vulkan.mark(10)
        result : List<&2,Cut> & D.State <- action(index,cuts,updated)
        show(result,index,width,height,enabled,win,c => w => s => loop(rest,c,(index + 1 : U32),width,height,enabled,w,s))

def start(w: W.World, cuts: List<&2,Cut>, +width: U32, +height: U32, frames: Nat) -> IO(Unit):
  do IO<Unit>:
    VK.vulkan.mark(7)
    win : Window <- IO.try(Window,Window.open("Megascene / Irregular history / Unqualified development observation",width,height))
    win : Window <- VK.vulkan.colors(win,Color.palette())
    VK.vulkan.mark(8)
    cam : V.Camera <- VK.vulkan.route(0,width,height)
    state : D.State = D.State{w,I.Control{cam,0,0,0,False{},False{},False{},False{},False{},False{}},Nil{},0}
    shown : Window & D.State & List<Event> <- VK.vulkan.frame(win,state,V.Aim{R.Vec{0.0,0.0,0.0},0.0,0},"MEGASCENE / IRREGULAR HISTORY / DEVELOPMENT OBSERVATION")
    mode : Result<&1,&1,U32 & String,String> <- IO.get_env("MEGASCENE_VALIDATE")
    +enabled : Bool = L.validation(mode)
    L.next(shown,enabled,w => s => loop(frames,cuts,1,width,height,enabled,w,s))
