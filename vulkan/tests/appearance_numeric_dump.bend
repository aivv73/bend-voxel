import Base
import ../src/appearance.bend as F
import ../shaders/appearance_uniforms.bend as U
import ../../render.bend as R
import ../../voxel.bend as X
import ../../material.bend as M
import ../../lighting.bend as L

def print_words(+label: String, words: List<U32>, +index: U32) -> IO(Unit):
  match words:
    case Nil{}: IO.pure(Unit,Unit{})
    case Con{word,rest}:
      do IO<Unit>:
        IO.print(label ++ " " ++ U32.show(index) ++ " " ++ U32.show(word))
        print_words(label,rest,(index + 1 : U32))

def print_array(result: Maybe<Array<U32>>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit,1,"frame rejected")
    case Some{words}: print_words("frame",Array.to_list(~U32,words),0)

def print_cell(+label: String, cells: List<&2,X.Cell>) -> IO(Unit):
  match cells:
    case Nil{}: IO.pure(Unit,Unit{})
    case Con{X.Cell{x,y,z},rest}:
      do IO<Unit>:
        IO.print(label ++ " " ++ U32.show(x) ++ " " ++ U32.show(y) ++ " " ++ U32.show(z))
        print_cell(label,rest)

def print_selected(label: String, cells: Maybe<&2,List<&2,X.Cell>>) -> IO(Unit):
  match cells:
    case None{}: IO.print(label ++ " rejected")
    case Some{xs}: print_cell(label,xs)

def print_linear(label: String, color: M.LinearRgb) -> IO(Unit):
  M.LinearRgb{r,g,b} = color
  IO.print(label ++ " " ++ U32.show(F32.bits(r)) ++ " " ++ U32.show(F32.bits(g)) ++ " " ++ U32.show(F32.bits(b)))

def print_palette(palette: F.Palette) -> IO(Unit):
  F.Palette{a,b,c,d,e} = palette
  do IO<Unit>:
    print_linear("palette 1",a)
    print_linear("palette 2",b)
    print_linear("palette 3",c)
    print_linear("palette 4",d)
    print_linear("palette 5",e)

def direction(d: U32) -> X.Direction:
  match d:
    case 0: X.NegX{}
    case 1: X.PosX{}
    case 2: X.NegY{}
    case 3: X.PosY{}
    case 4: X.NegZ{}
    case _: X.PosZ{}

def palette_at(p: F.Palette, id: U32) -> M.LinearRgb:
  F.Palette{a,b,c,d,e} = p
  match id:
    case 1: a
    case 2: b
    case 3: c
    case 4: d
    case _: e

def day_dump(fuel: Nat, +index: U32, +p: F.Palette) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+rest:
      +id = (index / 60 + 1 : U32)
      +d = (index / 10 % 6 : U32)
      +v = (index % 10 : U32)
      do IO<Unit>:
        IO.print("day " ++ U32.show(id) ++ " " ++ U32.show(d) ++ " " ++ U32.show(v) ++ " " ++ U32.show(L.Day.color(palette_at(p,id),L.Sky.amount(direction(d)),L.Sun.cosine(direction(d)),v)))
        day_dump(rest,(index + 1 : U32),p)

def hit_result(label: String, hit: R.Hit) -> IO(Unit):
  match hit:
    case R.Hit{depth,color,id,Some{X.Cell{x,y,z}},d}:
      IO.print(label ++ " " ++ U32.show(x) ++ " " ++ U32.show(y) ++ " " ++ U32.show(z) ++ " " ++ U32.show(id))
    case _: IO.die(Unit,1,"literal identity missed")

def pixel_basis(d: U32) -> R.Basis:
  match d:
    case 0: R.Basis{R.Vec3{0.0,0.0,0.0},R.Vec3{0.0,F32.neg(1.0),0.0},R.Vec3{0.0,0.0,1.0},R.Vec3{1.0,0.0,0.0},1.0,0.1}
    case 1: R.Basis{R.Vec3{0.0,0.0,0.0},R.Vec3{0.0,1.0,0.0},R.Vec3{0.0,0.0,1.0},R.Vec3{F32.neg(1.0),0.0,0.0},1.0,0.1}
    case 2: R.Basis{R.Vec3{0.0,0.0,0.0},R.Vec3{1.0,0.0,0.0},R.Vec3{0.0,0.0,1.0},R.Vec3{0.0,1.0,0.0},1.0,0.1}
    case 3: R.Basis{R.Vec3{0.0,0.0,0.0},R.Vec3{F32.neg(1.0),0.0,0.0},R.Vec3{0.0,0.0,1.0},R.Vec3{0.0,F32.neg(1.0),0.0},1.0,0.1}
    case 4: R.Basis{R.Vec3{0.0,0.0,0.0},R.Vec3{1.0,0.0,0.0},R.Vec3{0.0,F32.neg(1.0),0.0},R.Vec3{0.0,0.0,1.0},1.0,0.1}
    case _: R.Basis{R.Vec3{0.0,0.0,0.0},R.Vec3{1.0,0.0,0.0},R.Vec3{0.0,1.0,0.0},R.Vec3{0.0,0.0,F32.neg(1.0)},1.0,0.1}

def pixel_hit(+d: U32, +u: U32, +v: U32, ray: R.Vec3) -> IO(Unit):
  R.Vec3{+denom,+du,+dv} = ray
  hit_result("pixel_identity " ++ U32.show(d) ++ " " ++ U32.show(u) ++ " " ++ U32.show(v),
    R.Hit.intersection(True{},denom,(5.0 * denom : F32),(U32.to_f32(u) - 5.0 * du : F32),(U32.to_f32(v) - 5.0 * dv : F32),
      du,dv,0.1,X.Cell{7,11,13},L.Flat{0},L.Color{9},2147483906,direction(d),2.0,3.0,False{},R.Hit.background(0,0)))

def identity(fuel: Nat, +index: U32) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+rest:
      +d = (index / 12 : U32)
      +u = (index / 4 % 3 : U32)
      +v = (index % 4 : U32)
      +sign = Bool.pick(F32,U32.is_eq((d % 2 : U32),0),1.0,F32.neg(1.0))
      do IO<Unit>:
        hit_result("identity " ++ U32.show(d) ++ " " ++ U32.show(u) ++ " " ++ U32.show(v),
          R.Hit.intersection(True{},sign,(5.0 * sign : F32),U32.to_f32(u),U32.to_f32(v),0.0,0.0,0.1,X.Cell{7,11,13},L.Flat{0},L.Color{9},2147483906,direction(d),2.0,3.0,False{},R.Hit.background(0,0)))
        pixel_hit(d,u,v,R.Face.axes(direction(d),R.Pixel.ray(pixel_basis(d),256,256)))
        identity(rest,(index + 1 : U32))

def segment(label: String, result: Maybe<&2,R.Segment>) -> IO(Unit):
  match result:
    case None{}: IO.print(label ++ " rejected")
    case Some{R.Segment{x,y,a,u,v,b,bounds}}:
      print_words(label,[F32.bits(x),F32.bits(y),F32.bits(a),F32.bits(u),F32.bits(v),F32.bits(b)],0)

def transfer(fuel: Nat, values: List<F32>, +i: U32) -> IO(Unit):
  match fuel values:
    case 0n _: IO.pure(Unit,Unit{})
    case 1n+rest Nil{}: IO.pure(Unit,Unit{})
    case 1n+rest Con{value,tail}:
      do IO<Unit>:
        IO.print("transfer " ++ U32.show(i) ++ " " ++ U32.show(F32.bits(M.Srgb.channel(value))))
        transfer(rest,tail,(i + 1 : U32))

def show_bool(label: String, b: Bool) -> IO(Unit):
  IO.print(label ++ " " ++ Bool.pick(String,b,"1","0"))

def rejected(result: Maybe<Array<U32>>) -> Bool:
  match result:
    case None{}: True{}
    case Some{words}: False{}

def run(+p: F.Palette) -> IO(Unit):
  +basis = R.Camera.basis(R.Camera.atelier())
  +brush = {Some{X.MetricSphere.demo()} : Maybe<&2,X.MetricSphere>}
  +wire = {R.Segment{0.0,0.0,0.5,10.0,0.0,0.25,R.Bounds{0,0,10,1}} : R.Segment}
  do IO<Unit>:
    print_array(F.encode(F.FrameInput{basis,640,360,440,p,brush,F.Unorm{},F.Shaded{}}))
    print_palette(p)
    day_dump(300n,0,p)
    IO.print("unknown unselected " ++ U32.show(R.Preview.tint(Some{X.Cell{0,0,0}},X.MetricSphere.demo(),L.Ramp.color(L.Palette.surface(L.Palette.build(),2147483906,X.PosZ{}),9))))
    IO.print("unknown selected " ++ U32.show(R.Preview.tint(Some{X.Cell{6,6,6}},X.MetricSphere.demo(),L.Ramp.color(L.Palette.surface(L.Palette.build(),2147483906,X.PosZ{}),9))))
    print_selected("selected demo",F.selected_cells(brush))
    print_selected("selected edge",F.selected_cells(Some{X.MetricSphere.brush(X.PointCm{25.0,5.0,5.0})}))
    print_selected("selected equal",F.selected_cells(Some{X.MetricSphere.brush(X.PointCm{45.0,65.0,65.0})}))
    print_selected("selected below",F.selected_cells(Some{X.MetricSphere.brush(X.PointCm{44.999996185302734375,65.0,65.0})}))
    print_selected("selected above",F.selected_cells(Some{X.MetricSphere.brush(X.PointCm{45.000003814697265625,65.0,65.0})}))
    print_selected("selected limit",F.selected_cells(Some{X.MetricSphere.brush(X.PointCm{10485760.0,10485760.0,10485760.0})}))
    print_selected("selected invalid_radius",F.selected_cells(Some{X.MetricSphere{X.PointCm{65.0,65.0,65.0},19.0}}))
    print_selected("selected invalid_coordinate",F.selected_cells(Some{X.MetricSphere.brush(X.PointCm{10485761.0,65.0,65.0})}))
    show_bool("reject_zero_width",rejected(F.encode(F.FrameInput{basis,0,360,440,p,brush,F.Unorm{},F.Shaded{}})))
    show_bool("reject_extent",rejected(F.encode(F.FrameInput{basis,640,360,1048577,p,brush,F.Unorm{},F.Shaded{}})))
    identity(72n,0)
    hit_result("normalized 41",R.Hit.intersection(True{},1.0,5.0,1.0,0.0,0.0,0.0,0.1,X.Cell{7,11,13},L.Flat{0},L.Color{9},2147483906,X.PosZ{},41.0,3.0,False{},R.Hit.background(0,0)))
    transfer(7n,[F32.neg(0.1),0.0,0.0031308,0.18,0.5,1.0,1.1],0)
    print_words("sun 1",F.sun_matrix(1),0)
    print_words("sun 14",F.sun_matrix(14),0)
    print_words("sun 440",F.sun_matrix(440),0)
    print_words("sun 1048576",F.sun_matrix(1048576),0)
    print_words("indices",F.static_indices(),0)
    segment("segment crossing",R.Segment.of(R.Vec3{0.0,0.0,0.05},R.Vec3{1.0,0.0,1.0},basis))
    segment("segment reversed",R.Segment.of(R.Vec3{1.0,0.0,1.0},R.Vec3{0.0,0.0,0.05},basis))
    segment("segment hidden",R.Segment.of(R.Vec3{0.0,0.0,0.01},R.Vec3{1.0,0.0,0.05},basis))
    show_bool("wire inside",R.Wire.segment(wire,5.0,0.75,0.1,10.0,Some{X.Cell{0,0,0}}))
    show_bool("wire outside",R.Wire.segment(wire,5.0,0.750000059604644775390625,0.1,10.0,Some{X.Cell{0,0,0}}))
    show_bool("wire reciprocal_front",R.Wire.segment(wire,5.0,0.0,0.1,2.8,Some{X.Cell{0,0,0}}))
    show_bool("wire reciprocal_back",R.Wire.segment(wire,5.0,0.0,0.1,2.6,Some{X.Cell{0,0,0}}))
    show_bool("wire background",R.Wire.segment(wire,5.0,0.0,0.1,0.0,None{}))

def ready(palette: Maybe<&2,F.Palette>) -> IO(Unit):
  match palette:
    case None{}: IO.die(Unit,1,"pinned palette failed")
    case Some{p}: run(p)

def main() -> IO(Unit):
  ready(F.palette())
