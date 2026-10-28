import Base
import ../../atelier.bend as A
import ../../voxel.bend as V
import ../../render.bend as R

def report(shadow: R.ShadowMap) -> IO(Unit):
  R.ShadowMap{basis,depths,ground,grid} = shadow
  IO.print("base_width=" ++ U32.show(R.Shadow.width()) ++ " effective_atelier_width=" ++ U32.show(R.Shadow.resolution(depths)))

def run(pair: V.Body & V.Surface) -> IO(Unit):
  (body,surface) = pair
  report(R.ShadowMap.build(surface))

def main() -> IO(Unit):
  run(V.Surface.build(A.body()))
