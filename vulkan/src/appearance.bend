import Base
import ../../voxel.bend as X
import ../../render.bend as R
import ../../material.bend as M
import ../shaders/appearance_uniforms.bend as U

type Output is Data:
  Unorm{}
  Srgb{}
type Mode is Data:
  Shaded{}
  Basic{}
  Material{}
  Direction{}
  CellX{}
  CellY{}
  CellZ{}
  Selected{}
type Palette is Data:
  Palette{foundation: M.LinearRgb, concrete: M.LinearRgb, frame: M.LinearRgb, machinery: M.LinearRgb, plaster: M.LinearRgb}
type FrameInput is Data:
  FrameInput{basis: R.Basis, width: U32, height: U32, extent: U32, palette: Palette, brush: Maybe<&2,X.MetricSphere>, output: Output, mode: Mode}

def coordinate_limit() -> U32:
  1048576

def palette_join(a: Maybe<&2,M.LinearRgb>, b: Maybe<&2,M.LinearRgb>, c: Maybe<&2,M.LinearRgb>, d: Maybe<&2,M.LinearRgb>, e: Maybe<&2,M.LinearRgb>) -> Maybe<&2,Palette>:
  match a b c d e:
    case Some{av} Some{bv} Some{cv} Some{dv} Some{ev}: Some{Palette{av,bv,cv,dv,ev}}
    case _ _ _ _ _: None{}

def palette() -> Maybe<&2,Palette>:
  a b = M.Oklch.linear(M.Material.oklch(M.Foundation{})) M.Oklch.linear(M.Material.oklch(M.Concrete{}))
  c d = M.Oklch.linear(M.Material.oklch(M.Frame{})) M.Oklch.linear(M.Material.oklch(M.Machinery{}))
  palette_join(a,b,c,d,M.Oklch.linear(M.Material.oklch(M.Plaster{})))

def rgb_words(color: M.LinearRgb) -> List<U32>:
  M.LinearRgb{r,g,b} = color
  [F32.bits(r),F32.bits(g),F32.bits(b),0]

def palette_words(palette: Palette) -> List<U32>:
  Palette{a,b,c,d,e} = palette
  List.concat(&1,U32,[rgb_words(a),rgb_words(b),rgb_words(c),rgb_words(d),rgb_words(e)])

def vector_words(point: R.Vec3, w: F32) -> List<U32>:
  R.Vec3{x,y,z} = point
  [F32.bits(x),F32.bits(y),F32.bits(z),F32.bits(w)]

def camera_matrix(basis: R.Basis, width: U32, height: U32) -> List<U32>:
  R.Basis{+eye,R.Vec3{+rx,+ry,+rz},R.Vec3{+ux,+uy,+uz},R.Vec3{+fx,+fy,+fz},focal,near} = basis
  +scale = (focal / 256.0 : F32)
  +horizontal = (scale * U32.to_f32(height) / U32.to_f32(width) : F32)
  +tx = F32.neg(R.Vec3.dot(eye,R.Vec3{rx,ry,rz}))
  +ty = F32.neg(R.Vec3.dot(eye,R.Vec3{ux,uy,uz}))
  +tz = F32.neg(R.Vec3.dot(eye,R.Vec3{fx,fy,fz}))
  [F32.bits((horizontal * rx : F32)),F32.bits(F32.neg((scale * ux : F32))),F32.bits(fx),F32.bits(fx),
   F32.bits((horizontal * ry : F32)),F32.bits(F32.neg((scale * uy : F32))),F32.bits(fy),F32.bits(fy),
   F32.bits((horizontal * rz : F32)),F32.bits(F32.neg((scale * uz : F32))),F32.bits(fz),F32.bits(fz),
   F32.bits((horizontal * tx : F32)),F32.bits(F32.neg((scale * ty : F32))),F32.bits((tz - near : F32)),F32.bits(tz)]

def sun_span(extent: U32) -> F32:
  (U32.to_f32(U32.max(extent,1)) * 2.0 + 2.0 : F32)

def sun_inverse_depth(extent: U32) -> F32:
  (1.0 / (4.0 * sun_span(extent) - 0.1) : F32)

def sun_matrix_basis(+extent: U32, basis: R.Basis) -> List<U32>:
  R.Basis{+eye,R.Vec3{+rx,+ry,+rz},R.Vec3{+ux,+uy,+uz},R.Vec3{+fx,+fy,+fz},focal,near} = basis
  +scale = (2.0 / sun_span(extent) : F32)
  +depth = sun_inverse_depth(extent)
  +tx = F32.neg(R.Vec3.dot(eye,R.Vec3{rx,ry,rz}))
  +ty = F32.neg(R.Vec3.dot(eye,R.Vec3{ux,uy,uz}))
  +tz = F32.neg(R.Vec3.dot(eye,R.Vec3{fx,fy,fz}))
  [F32.bits((scale * rx : F32)),F32.bits(F32.neg((scale * ux : F32))),F32.bits((depth * fx : F32)),0,
   F32.bits((scale * ry : F32)),F32.bits(F32.neg((scale * uy : F32))),F32.bits((depth * fy : F32)),0,
   F32.bits((scale * rz : F32)),F32.bits(F32.neg((scale * uz : F32))),F32.bits((depth * fz : F32)),0,
   F32.bits((scale * tx : F32)),F32.bits(F32.neg((scale * ty : F32))),F32.bits(((tz - near) * depth : F32)),F32.bits(1.0)]

def sun_matrix(+extent: U32) -> List<U32>:
  sun_matrix_basis(extent,R.Shadow.basis(U32.max(extent,1)))

def bound(+value: F32) -> Bool:
  M.Number.finite(value) && (value >= 0.0 : F32) && (value <= 10485760.0 : F32)

def brush_valid(brush: Maybe<&2,X.MetricSphere>) -> Bool:
  match brush:
    case None{}: True{}
    case Some{+sphere}:
      X.MetricSphere{X.PointCm{x,y,z},radius} = sphere
      X.MetricSphere.valid(sphere) && F32.is_eq(radius,20.0) && bound(x) && bound(y) && bound(z)

def low(value: F32) -> U32:
  (U32.max(F32.to_u32(F32.floor((value / 10.0 : F32))),2) - 2 : U32)

def high(value: F32) -> U32:
  U32.min((F32.to_u32(F32.floor((value / 10.0 : F32))) + 2 : U32),(coordinate_limit() - 1 : U32))

def candidate(selected: Bool, cell: X.Cell, rest: List<&2,X.Cell>) -> List<&2,X.Cell>:
  match selected:
    case True{}: cell <> rest
    case False{}: rest

def enumerate(fuel: Nat, +i: U32, +sphere: X.MetricSphere, +lo: X.Cell, +hi: X.Cell) -> List<&2,X.Cell>:
  match fuel:
    case 0n: Nil{}
    case 1n+rest:
      X.Cell{lx,ly,lz} = lo
      X.Cell{hx,hy,hz} = hi
      +x = (lx + i / 25 : U32)
      +y = (ly + (i / 5) % 5 : U32)
      +z = (lz + i % 5 : U32)
      +cell = {X.Cell{x,y,z} : X.Cell}
      candidate((x <= hx : U32) && (y <= hy : U32) && (z <= hz : U32) && X.MetricSphere.contains(sphere,cell),cell,
        enumerate(rest,(i + 1 : U32),sphere,lo,hi))

def selected_valid(valid: Bool, brush: Maybe<&2,X.MetricSphere>) -> Maybe<&2,List<&2,X.Cell>>:
  match valid brush:
    case False{} _: None{}
    case True{} None{}: Some{Nil{}}
    case True{} Some{+sphere}:
      X.MetricSphere{X.PointCm{+x,+y,+z},radius} = sphere
      Some{enumerate(125n,0,sphere,X.Cell{low(x),low(y),low(z)},X.Cell{high(x),high(y),high(z)})}

def selected_cells(+brush: Maybe<&2,X.MetricSphere>) -> Maybe<&2,List<&2,X.Cell>>:
  selected_valid(brush_valid(brush),brush)

def cell_words(fuel: Nat, cells: List<&2,X.Cell>) -> Maybe<List<U32>>:
  match fuel cells:
    case 0n Nil{}: Some{Nil{}}
    case 0n Con{c,rest}: None{}
    case 1n+rest Nil{}:
      do Maybe<&1,List<U32>>:
        tail : List<U32> <- cell_words(rest,Nil{})
        return (0 <> 0 <> 0 <> 0 <> tail)
    case 1n+rest Con{X.Cell{x,y,z},xs}:
      do Maybe<&1,List<U32>>:
        tail : List<U32> <- cell_words(rest,xs)
        return (x <> y <> z <> 0 <> tail)

def mode(mode: Mode) -> U32:
  match mode:
    case Shaded{}: 0
    case Basic{}: 1
    case Material{}: 2
    case Direction{}: 3
    case CellX{}: 4
    case CellY{}: 5
    case CellZ{}: 6
    case Selected{}: 7

def output(output: Output) -> U32:
  match output:
    case Unorm{}: 0
    case Srgb{}: 1

def brush_words(brush: Maybe<&2,X.MetricSphere>) -> List<U32>:
  match brush:
    case None{}: [0,0,0,0]
    case Some{X.MetricSphere{X.PointCm{x,y,z},r}}: [F32.bits(x),F32.bits(y),F32.bits(z),F32.bits(r)]

def brush_enabled(brush: Maybe<&2,X.MetricSphere>) -> U32:
  match brush:
    case None{}: 0
    case Some{s}: 1

def finite_vec(v: R.Vec3) -> Bool:
  R.Vec3{x,y,z} = v
  M.Number.finite(x) && M.Number.finite(y) && M.Number.finite(z)

def eye_valid(+eye: R.Vec3) -> Bool:
  R.Vec3{x,y,z} = eye
  finite_vec(eye) && (F32.abs(x) <= 1048576.0 : F32) && (F32.abs(y) <= 1048576.0 : F32) && (F32.abs(z) <= 1048576.0 : F32)

def unit_pair(+a: R.Vec3, +b: R.Vec3, +c: R.Vec3) -> Bool:
  (F32.abs((R.Vec3.dot(a,a) - 1.0 : F32)) < 0.00002 : F32) &&
  (F32.abs(R.Vec3.dot(a,b)) < 0.00002 : F32) && (F32.abs(R.Vec3.dot(a,c)) < 0.00002 : F32)

def valid(frame: FrameInput) -> Bool:
  FrameInput{R.Basis{eye,+right,+up,+forward,+focal,+near},+w,+h,extent,Palette{a,b,c,d,e},brush,o,m} = frame
  (w > 0 : U32) && (h > 0 : U32) && (w <= 1048576 : U32) && (h <= 1048576 : U32) && (extent <= coordinate_limit() : U32) &&
  eye_valid(eye) && finite_vec(right) && finite_vec(up) && finite_vec(forward) &&
  unit_pair(right,up,forward) && unit_pair(up,right,forward) && unit_pair(forward,right,up) &&
  M.Number.finite(focal) && M.Number.finite(near) && (focal > 0.0 : F32) && (near > 0.0 : F32) && (near <= 1048576.0 : F32) && (focal <= 1048576.0 : F32) &&
  M.LinearRgb.gamut(a) && M.LinearRgb.gamut(b) && M.LinearRgb.gamut(c) && M.LinearRgb.gamut(d) && M.LinearRgb.gamut(e) && brush_valid(brush)

def encode_cell_words(frame: FrameInput, +cells: List<&2,X.Cell>, words: List<U32>) -> Maybe<Array<U32>>:
  FrameInput{+basis,+w,+h,+extent,palette,+brush,o,m} = frame
  R.Basis{eye,right,up,forward,focal,near} = basis
  camera light = camera_matrix(basis,w,h) sun_matrix(extent)
  U.pack(U.FrameWords{camera,light,vector_words(eye,near),vector_words(right,0.0),vector_words(up,0.0),
    vector_words(forward,(focal * U32.to_f32(h) / 512.0 : F32)),
    [F32.bits(U32.to_f32(w)),F32.bits(U32.to_f32(h)),F32.bits((1.0 / U32.to_f32(w) : F32)),F32.bits((1.0 / U32.to_f32(h) : F32))],
    brush_words(brush),[brush_enabled(brush),output(o),mode(m),U32.from_nat(List.length(&2,X.Cell,cells))],palette_words(palette),
    [F32.bits(512.0),F32.bits(sun_span(extent)),F32.bits(sun_inverse_depth(extent)),F32.bits(0.005)],words})

def encode_cells(+frame: FrameInput, +cells: List<&2,X.Cell>) -> Maybe<Array<U32>>:
  do Maybe<&1,Array<U32>>:
    words : List<U32> <- cell_words(125n,cells)
    encode_cell_words(frame,cells,words)

def encode_selected(frame: FrameInput, selected: Maybe<&2,List<&2,X.Cell>>) -> Maybe<Array<U32>>:
  match selected:
    case None{}: None{}
    case Some{cells}: encode_cells(frame,cells)

def frame_brush(frame: FrameInput) -> Maybe<&2,X.MetricSphere>:
  FrameInput{basis,w,h,e,p,brush,o,m} = frame
  brush

def encode_valid(valid: Bool, +frame: FrameInput) -> Maybe<Array<U32>>:
  match valid:
    case False{}: None{}
    case True{}:
      encode_selected(frame,selected_cells(frame_brush(frame)))

def encode(+frame: FrameInput) -> Maybe<Array<U32>>:
  encode_valid(valid(frame),frame)

def ring_indices(fuel: Nat, +index: U32) -> List<U32>:
  match fuel:
    case 0n: Nil{}
    case 1n+rest: index <> ring_indices(rest,(index + 1 : U32))

def ring_index_count() -> U32:
  576

def static_indices() -> List<U32>:
  ring_indices(576n,0)
