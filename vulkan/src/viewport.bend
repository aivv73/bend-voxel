import Base
import ../../deps/bend-vulkan/src/core.bend as Core
import ../../render.bend as R
import ../../voxel.bend as X
import ../../lighting.bend as Material

type Viewport is Data:
  Viewport{width: U32, height: U32}
type Mapping is Data:
  Mapping{window_width: U32, window_height: U32, width: U32, height: U32}

def map_point(mapping: Mapping, x: U32, y: U32) -> U32 & U32:
  Mapping{ww,wh,width,height} = mapping
  ((x * width / U32.max(ww,1) : U32),(y * height / U32.max(wh,1) : U32))

def ray_offset(basis: R.Basis, height: U32, offset: F32 & F32) -> R.Vec3:
  R.Basis{eye,right,up,forward,+focal,near} = basis
  (x,y) = offset
  +pixels = (focal * U32.to_f32(height) / 512.0 : F32)
  R.Vec3.add(forward,R.Vec3.add(R.Vec3.scale(right,(x / pixels : F32)),R.Vec3.scale(up,(y / pixels : F32))))

def ray(view: Viewport, basis: R.Basis, x: U32, y: U32) -> R.Vec3:
  Viewport{width,+height} = view
  ray_offset(basis,height,Core.viewport_pixel(width,height,x,y))

def face_coordinates(+cell: X.Cell, direction: X.Direction, coordinates: R.Vec3, axis: R.Vec3, width: F32, height: F32) -> R.Projected:
  R.Vec3{plane,u,v} = coordinates
  R.Vec3{ep,eu,ev} = axis
  R.Projected{cell,direction,(plane - ep : F32),(eu - u : F32),(ev - v : F32),Material.Flat{0},Material.Color{9},1,R.Bounds{0,0,0,0},width,height,False{}}

def face(+face: X.Face, eye: R.Vec3) -> R.Projected:
  match face:
    case X.Face{+cell,+direction,material}:
      face_coordinates(cell,direction,R.Face.coordinates(direction,cell),R.Face.axes(direction,eye),1.0,1.0)
    case X.Rectangle{+cell,+direction,material,width,height}:
      face_coordinates(cell,direction,R.Face.coordinates(direction,cell),R.Face.axes(direction,eye),U32.to_f32(width),U32.to_f32(height))

def front(direction: X.Direction, ray: R.Vec3) -> Bool:
  match direction ray:
    case X.NegX{} R.Vec3{x,y,z}: (x > 0.0 : F32)
    case X.PosX{} R.Vec3{x,y,z}: (x < 0.0 : F32)
    case X.NegY{} R.Vec3{x,y,z}: (y > 0.0 : F32)
    case X.PosY{} R.Vec3{x,y,z}: (y < 0.0 : F32)
    case X.NegZ{} R.Vec3{x,y,z}: (z > 0.0 : F32)
    case X.PosZ{} R.Vec3{x,y,z}: (z < 0.0 : F32)

def facing(face: X.Face, ray: R.Vec3) -> Bool:
  match face:
    case X.Face{cell,direction,material}: front(direction,ray)
    case X.Rectangle{cell,direction,material,width,height}: front(direction,ray)

def visible(visible: Bool, head: X.Face, eye: R.Vec3, rest: List<&2,R.Projected>) -> List<&2,R.Projected>:
  match visible:
    case False{}: rest
    case True{}: face(head,eye) <> rest

def faces(xs: List<&2,X.Face>, +eye: R.Vec3, +ray: R.Vec3) -> List<&2,R.Projected>:
  match xs:
    case Nil{}: Nil{}
    case Con{+head,rest}: visible(facing(head,ray),head,eye,faces(rest,eye,ray))

def target_valid(valid: Bool, +view: Viewport, +basis: R.Basis, surface: List<&2,X.Face>, +x: U32, +y: U32) -> Maybe<&2,X.MetricSphere>:
  match valid:
    case False{}: None{}
    case True{}:
      R.Basis{eye,right,up,forward,focal,near} = basis
      +direction = ray(view,basis,x,y)
      R.Hit.target(R.Pixel.hit(faces(surface,eye,direction),direction,near,R.Hit.background(x,y)),basis,direction)

def target(+view: Viewport, +camera: R.Camera, surface: List<&2,X.Face>, +x: U32, +y: U32) -> Maybe<&2,X.MetricSphere>:
  Viewport{width,height} = view
  target_valid((x < width : U32) && (y < height : U32),view,R.Camera.basis(camera),surface,x,y)
