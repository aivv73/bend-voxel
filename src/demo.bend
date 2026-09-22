import Base
import ./terrain.bend as T
import ./vendor/bend3d.bend as R
import ./render.bend as V
import ./input.bend as I
import ./platform.bend as P

type State is Data:
  State{terrain: T.Tree, faces: List<&2,T.Face>, control: I.Control, nodes: U32, solids: U32}
def control.camera(c: I.Control) -> I.Control:
  I.Control{_,keys,mx,my,look,left,focus,cut,reset,quit} = c
  I.Control{V.Camera{R.Vec{5.0,4.8,6.0},(0.0 - 2.4468544 : F32),(0.0 - 0.40 : F32)},keys,mx,my,look,left,focus,cut,reset,quit}
def initial() -> State:
  +tree = T.initial()
  State{tree,T.surface(tree),control.camera(I.initial()),T.nodes(tree),T.solids(tree,32)}
def reset(on: Bool, c: I.Control) -> I.Control:
  match on:
    case True{}: control.camera(I.reset.state(c))
    case False{}: c
def event.control(+c: I.Control, t: T.Tree, fs: List<&2,T.Face>, n: U32, v: U32) -> State:
  I.Control{_,_,_,_,_,_,_,_,r,_} = c
  State{t,fs,reset(r,c),n,v}
def event(e: Event, s: State) -> State:
  State{t,fs,c,n,v} = s
  event.control(I.event(e,c),t,fs,n,v)
def events(es: List<Event>, s: State) -> State:
  match es:
    case Nil{}: s
    case e <> rest: events(rest,event(e,s))
def advance(s: State, dt: F32) -> State:
  State{t,fs,c,n,v} = s
  State{t,fs,I.step(c,dt),n,v}
def hud(n: U32, v: U32, frame: U32) -> String:
  "BEND VOXEL / SVO TERRAIN\n" ++
  "32 x 32 x 32  /  20 CM VOXELS  /  " ++ U32.show(v) ++ " SOLID\n" ++
  "SVO NODES " ++ U32.show(n) ++ "  FRAME " ++ U32.show((frame / 1000 : U32)) ++ " MS\n" ++
  "EXPLORE / GRASS, EARTH AND STONE\n" ++
  "WASD MOVE  QE UP/DOWN  HOLD RMB TO LOOK\n" ++
  "R RESET CAMERA  ESC RELEASE  CLICK TO RESUME"
def scene(s: State, frame: U32) -> State & R.Cells & String:
  State{t,+fs,+c,+n,+v} = s
  I.Control{camera,_,_,_,_,_,_,_,_,_} = c
  (State{t,fs,c,n,v},T.draw(fs,V.cam(camera),R.CNil{}),hud(n,v,frame))
def show.pack(r: Window & Image & List<Event>, s: State) -> IO(Window & Image & List<Event> & State):
  (win,im,es) = r
  IO.pure(Window & Image & List<Event> & State,(win,im,es,s))
def show.drawn(r: Image & R.Cells, win: Window, s: State, hud: String) -> IO(Window & Image & List<Event> & State):
  (im,cells) = r
  do IO<Window & Image & List<Event> & State>:
    unused : R.Cells <- IO.pure(R.Cells,R.Cells.drop(4n,cells))
    shown : Window & Image & List<Event> <- P.present(win,im,hud)
    show.pack(shown,s)
def show.ready(r: State & R.Cells & String, win: Window, old: Image) -> IO(Window & Image & List<Event> & State):
  (s,cells,hud) = r
  do IO<Window & Image & List<Event> & State>:
    drawn : Image & R.Cells <- IO.pure(Image & R.Cells,V.frame(cells,old))
    show.drawn(drawn,win,s,hud)
def loop.cont(done: Bool, win: Window, s: State, im: Image, stamp: U32, frame: U32, remaining: U32, k: Window -> State -> Image -> U32 -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  match done:
    case True{}: Window.close(win)
    case False{}: k(win,s,im,stamp,frame,remaining)
def loop.next(s: State, win: Window, im: Image, stamp: U32, frame: U32, +remaining: U32, k: Window -> State -> Image -> U32 -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  State{t,fs,+c,n,v} = s
  I.Control{_,_,_,_,_,_,_,_,_,quit} = c
  loop.cont((quit || U32.is_eq(remaining,1)),win,State{t,fs,c,n,v},im,stamp,frame,R.word((remaining > 0 : U32),(remaining - 1 : U32),0),k)
def loop.shown(r: Window & Image & List<Event> & State, +before: U32, remaining: U32, k: Window -> State -> Image -> U32 -> U32 -> U32 -> IO(Unit)) -> IO(Unit):
  (win,im,es,s) = r
  do IO<Unit>:
    +now : U32 <- P.micros()
    loop.next(events(es,s),win,im,before,(now - before : U32),remaining,k)
@unsafe
def loop(win: Window, s: State, old: Image, +stamp: U32, frame: U32, remaining: U32) -> IO(Unit):
  do IO<Unit>:
    +now : U32 <- P.micros()
    shown : Window & Image & List<Event> & State <- show.ready(scene(advance(s,R.min(0.1,(U32.to_f32((now - stamp : U32)) / 1000000.0 : F32))),frame),win,old)
    loop.shown(shown,now,remaining,w => s => im => t => dt => r => loop(w,s,im,t,dt,r))
def env.read(r: Maybe<&2,U32>) -> U32:
  match r:
    case Some{n}: n
    case None{}: 0
def env.number(r: Result<&1,&1,U32 & String,String>) -> U32:
  match r:
    case Done{s}: env.read(U32.read(s))
    case Fail{_}: 0
def main() -> IO(Unit):
  do IO<Unit>:
    limit : Result<&1,&1,U32 & String,String> <- IO.get_env("VOXEL_FRAMES")
    s : State <- IO.pure(State,initial())
    win : Window <- IO.try(Window,Window.open("Bend Voxel - SVO Terrain / WASD move / RMB look / R reset",640,360))
    +now : U32 <- P.micros()
    loop(win,s,Pix{0},now,0,env.number(limit))
