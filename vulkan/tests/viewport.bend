import Base
import ../src/viewport.bend as View
import ../src/mesh.bend as M
import ../src/exterior.bend as Exterior
import ../../voxel.bend as X
import ../../render.bend as R
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D
import ../../deps/bend-vulkan/Vulkan.bend as V

def equal(a: R.Vec3, b: R.Vec3) -> Bool:
  R.Vec3{ax,ay,az} = a
  R.Vec3{bx,by,bz} = b
  F32.is_eq(ax,bx) && F32.is_eq(ay,by) && F32.is_eq(az,bz)

def point(hit: Maybe<&2,X.MetricSphere>, expected_x: F32, expected_y: F32, expected_z: F32) -> Bool:
  match hit:
    case None{}: False{}
    case Some{X.MetricSphere{X.PointCm{x,y,z},radius}}:
      (F32.abs((x - expected_x : F32)) < 0.001 : F32) && (F32.abs((y - expected_y : F32)) < 0.001 : F32) && (F32.abs((z - expected_z : F32)) < 0.001 : F32)

def checks(result: X.Body & M.Mesh) -> V.Action(Unit):
  (body,M.Mesh{+faces,size,bounds,vs,ix}) = result
  +camera : R.Camera = R.Camera{R.Vec3{18.0,18.0,15.0},F32.neg(1.70619449),F32.neg(0.5070985)}
  +front : R.Camera = R.Camera{R.Vec3{4.0,F32.neg(10.0),4.0},1.57079632679,0.0}
  do V.Action<Unit>:
    D.require(equal(View.ray(View.Viewport{512,512},R.Camera.basis(R.Camera.initial()),399,224),R.Pixel.ray(R.Camera.basis(R.Camera.initial()),399,224)),"Square viewport changed upstream pixel-center rays")
    D.require(Maybe.is_some(&2,X.MetricSphere,View.target(View.Viewport{800,450},camera,faces,700,225)),"Landscape visible face outside the old 512 projection was lost")
    D.require(point(View.target(View.Viewport{800,450},front,faces,520,225),72.643386,0.0,39.86455),"Landscape off-center hit must match the y=0 plane within 0.001 cm")
    D.require(point(View.target(View.Viewport{450,700},front,faces,125,300),22.672108,0.0,48.620407),"Portrait off-center hit must match the y=0 plane within 0.001 cm")
    D.require(Maybe.is_none(&2,X.MetricSphere,View.target(View.Viewport{512,512},R.Camera{R.Vec3{4.0,4.0,4.0},0.0,0.0},faces,256,256)),"Picking accepted a culled back face from inside the solid cube")
    D.require(Maybe.is_none(&2,X.MetricSphere,View.target(View.Viewport{800,450},camera,faces,800,225)),"Picking accepted an out-of-extent pixel")
    V.Action.lift(Unit,IO.print("Viewport square rays, wide-field picking and extent rejection passed"))

def built(pair: X.Body & Result<&2,&1,Exterior.Error,M.Mesh>) -> V.Action(Unit):
  (body,result) = pair
  match result:
    case Fail{error}: IO.pure(V.VkResult(Unit),Fail{(1,Exterior.error_show(error))})
    case Done{mesh}: checks((body,mesh))

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- built(M.build(X.Body.solid(3n)))
    V.or_exit(Unit,result)
