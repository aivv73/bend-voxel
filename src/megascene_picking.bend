import Base
import ./world.bend as W
import ./render.bend as V
import ./math.bend as R

type Ray is Data:
  Ray{enabled: Bool, origin: R.Vec, direction: R.Vec}

def guard(bodies: List<&2,W.Body>, ray: Ray) -> IO(Unit):
  import "./picking/guard.c"
  import "./picking/guard.js"

def run(active: Bool, bodies: List<&2,W.Body>, origin: R.Vec, direction: R.Vec) -> V.Hit:
  match active:
    case True{}: V.hit.start(bodies,origin,direction)
    case False{}: V.Hit{V.Aim{R.Vec{0.0,0.0,0.0},0.0,0},0,0}

def pick(+bodies: List<&2,W.Body>, +ray: Ray) -> IO(V.Hit):
  Ray{active,origin,direction} = ray
  do IO<V.Hit>:
    Unit <- guard(bodies,ray)
    return run(active,bodies,origin,direction)

# Use the existing camera projection for the actual center ray. The recorder
# compares these bits to the independently admitted frozen input in both runs.
def center(ray: Ray, +camera: V.Camera) -> Ray:
  Ray{active,_,_} = ray
  V.Camera{eye,_,_,+width,+height} = camera
  Ray{active,eye,V.ray.direction(V.cam(camera),(U32.to_f32(width) * 0.5 : F32),(U32.to_f32(height) * 0.5 : F32))}
