import Base
import ../demo.bend as D
import ../snapshot.bend as S
import ../world.bend as W
import ../render.bend as V
import ../input.bend as I
import ../vendor/bend3d.bend as R

# PROTOTYPE: export the same fixed-clock world used by snapshot.bend.
# This text is an interchange fixture, not a production save format.
def face.lines(fs: List<&2, W.Face>) -> IO(Unit):
  match fs:
    case Nil{}: IO.pure(Unit, Unit{})
    case W.Face{i, side, length, rows} <> rest:
      do IO<Unit>:
        Unit <- IO.print("face," ++ U32.show(i) ++ "," ++ U32.show(side) ++ "," ++ U32.show(length) ++ "," ++ U32.show(rows))
        face.lines(rest)

def body.lines(bs: List<&2, W.Body>) -> IO(Unit):
  match bs:
    case Nil{}: IO.pure(Unit, Unit{})
    case W.Body{id, offset, _, _, faces} <> rest:
      do IO<Unit>:
        Unit <- IO.print("body," ++ U32.show(id) ++ "," ++ F32.show(offset))
        Unit <- face.lines(faces)
        Unit <- IO.print("endbody")
        body.lines(rest)

def scene.world(w: W.World, c: I.Control, tick: U32) -> IO(Unit):
  W.World{_, bs, solids, count, removed, status} = w
  I.Control{camera, _, _, _, _, _, _, _, _, _} = c
  V.Camera{R.Vec{x, y, z}, yaw, pitch} = camera
  do IO<Unit>:
    Unit <- IO.print("scene,1,640,360," ++ U32.show(tick))
    Unit <- IO.print("camera," ++ F32.show(x) ++ "," ++ F32.show(y) ++ "," ++ F32.show(z) ++ "," ++ F32.show(yaw) ++ "," ++ F32.show(pitch))
    Unit <- IO.print("state," ++ U32.show(solids) ++ "," ++ U32.show(count) ++ "," ++ U32.show(removed) ++ "," ++ U32.show(status))
    Unit <- body.lines(bs)
    IO.print("end")

def scene.state(s: D.State, tick: U32) -> IO(Unit):
  D.state.world(IO(Unit), s, w => c => _ => _ => scene.world(w, c, tick))

def number(m: Maybe<&2, U32>) -> U32:
  match m:
    case None{}: 0
    case Some{v}: U32.min(v, 1199)
def start(r: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match r:
    case Fail{_}: scene.state(D.replay.camera(D.initial(), 5000000), 0)
    case Done{text}:
      +tick = number(U32.read(text))
      scene.state(S.walk(U32.to_nat(tick), 1, D.replay.camera(D.initial(), 5000000)), tick)
def main() -> IO(Unit):
  do IO<Unit>:
    value : Result<&1, &1, U32 & String, String> <- IO.get_env("VOXEL_SNAPSHOT_TICK")
    start(value)
