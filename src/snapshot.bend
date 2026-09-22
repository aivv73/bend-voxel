import Base
import ./table-demo.bend as D
import ./render.bend as V
import ./world.bend as W
import ./vendor/bend3d.bend as R

def walk(n: Nat, +tick: U32, s: D.State) -> D.State:
  match n:
    case 0n: s
    case 1n+k:
      +elapsed = (5000000 + tick * 1000000 / 60 : U32)
      +previous = (5000000 + (tick - 1) * 1000000 / 60 : U32)
      walk(k,(tick + 1 : U32),D.replay.camera(D.replay.scan(14n,0,previous,elapsed,0,D.advance(s,0.016666667)),elapsed))
def tree(img: Image) -> IO(Unit):
  match img:
    case Pix{c}: IO.print(U32.show(c))
    case Qua{tl,tr,bl,br}:
      do IO<Unit>:
        Unit <- IO.print("Q")
        Unit <- tree(tl)
        Unit <- tree(tr)
        Unit <- tree(bl)
        tree(br)
def drawn(r: Image & R.Cells) -> IO(Unit):
  (im,cells) = r
  do IO<Unit>:
    unused : R.Cells <- IO.pure(R.Cells,R.Cells.drop(4n,cells))
    Unit <- IO.print("TREE")
    tree(im)
def bodies(bs: List<&2,W.Body>) -> IO(Unit):
  match bs:
    case Nil{}: IO.pure(Unit,Unit{})
    case W.Body{id,offset,speed,bottom,_} <> rest:
      do IO<Unit>:
        Unit <- IO.print("body," ++ U32.show(id) ++ "," ++ F32.show(offset) ++ "," ++ F32.show(speed) ++ "," ++ F32.show(bottom))
        bodies(rest)
def ready.world(w: W.World, cells: R.Cells, hud: String, tick: U32) -> IO(Unit):
  W.World{_,bs,n,count,removed,status} = w
  do IO<Unit>:
    Unit <- IO.print("snapshot,1,640,360,2048," ++ U32.show(tick))
    Unit <- IO.print("state," ++ U32.show(n) ++ "," ++ U32.show(count) ++ "," ++ U32.show(removed) ++ "," ++ U32.show(status))
    Unit <- bodies(bs)
    Unit <- IO.print("HUD")
    Unit <- IO.print(hud)
    frame : Image & R.Cells <- IO.pure(Image & R.Cells,V.frame(cells,Pix{0}))
    drawn(frame)
def ready(r: D.State & R.Cells & String, tick: U32) -> IO(Unit):
  (s,cells,hud) = r
  D.state.world(IO(Unit),s,w => _ => _ => _ => ready.world(w,cells,hud,tick))
def number(m: Maybe<&2,U32>) -> U32:
  match m:
    case None{}: 0
    case Some{v}: U32.min(v,1199)
def start(r: Result<&1,&1,U32 & String,String>) -> IO(Unit):
  match r:
    case Fail{_}: ready(D.scene(D.replay.camera(D.initial(),5000000),0),0)
    case Done{text}:
      +tick = number(U32.read(text))
      ready(D.scene(walk(U32.to_nat(tick),1,D.replay.camera(D.initial(),5000000)),0),tick)
def main() -> IO(Unit):
  do IO<Unit>:
    value : Result<&1,&1,U32 & String,String> <- IO.get_env("VOXEL_SNAPSHOT_TICK")
    start(value)
