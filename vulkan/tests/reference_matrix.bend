import Base
import ../src/appearance.bend as F
import ../../material.bend as M
import ../../render.bend as R
import ../../lighting.bend as L

def nums(xs: List<U32>) -> String:
  match xs:
    case Nil{}: ""
    case x <> Nil{}: U32.show(x)
    case x <> rest: U32.show(x) ++ "," ++ nums(rest)

def palette_value(id: U32, value: Maybe<&2,M.LinearRgb>) -> IO(Unit):
  match value:
    case None{}: IO.die(Unit,1,"Pinned palette failed")
    case Some{M.LinearRgb{r,g,b}}:
      IO.print("{\"kind\":\"palette\",\"material\":" ++ U32.show(id) ++ ",\"linear_bits\":[" ++ nums([F32.bits(r),F32.bits(g),F32.bits(b)]) ++ "]}")

def control_map(resolution: U32) -> R.ShadowMap:
  R.ShadowMap{R.Basis{R.Vec3{0.0,0.0,0.0},R.Vec3{1.0,0.0,0.0},R.Vec3{0.0,1.0,0.0},R.Vec3{0.0,0.0,1.0},64.0,0.1},R.Resolution{resolution,R.Depth{12.48}},L.Ramp.constant(0),L.Ramp.constant(0)}

def literal_controls() -> IO(Unit):
  +point = {R.Vec3{0.125,0.25,12.0} : R.Vec3}
  +normal = {R.Vec3{(0.0 - 0.6 : F32),0.0,0.8} : R.Vec3}
  IO.print("{\"kind\":\"literal_control\",\"point_bits\":[" ++ nums([F32.bits(0.125),F32.bits(0.25),F32.bits(12.0)]) ++ "],\"normal_bits\":[" ++ nums([F32.bits((0.0 - 0.6 : F32)),F32.bits(0.0),F32.bits(0.8)]) ++ "],\"world_depth_bits\":" ++ U32.show(F32.bits(12.48)) ++ ",\"counts\":[" ++ nums([R.Shadow.visibility.local(control_map(8),point,normal),R.Shadow.visibility.local(control_map(8),point,R.Vec3{(0.0 - 0.6 : F32),0.0,(0.8 / 32.0 : F32)}),R.Shadow.visibility.local(control_map(4),point,normal)]) ++ "]}")

def main() -> IO(Unit):
  do IO<Unit>:
    literal_controls()
    IO.print("{\"kind\":\"production_matrix\",\"extent\":440,\"matrix_bits\":[" ++ nums(F.sun_matrix(440)) ++ "],\"span_bits\":" ++ U32.show(F32.bits(F.sun_span(440))) ++ ",\"inverse_depth_bits\":" ++ U32.show(F32.bits(F.sun_inverse_depth(440))) ++ ",\"world_bias_bits\":" ++ U32.show(F32.bits(0.005)) ++ "}")
    palette_value(1,M.Oklch.linear(M.Material.oklch(M.Foundation{})))
    palette_value(2,M.Oklch.linear(M.Material.oklch(M.Concrete{})))
    palette_value(3,M.Oklch.linear(M.Material.oklch(M.Frame{})))
    palette_value(4,M.Oklch.linear(M.Material.oklch(M.Machinery{})))
    palette_value(5,M.Oklch.linear(M.Material.oklch(M.Plaster{})))
