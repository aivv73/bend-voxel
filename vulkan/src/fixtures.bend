import Base
import ../../voxel.bend as X
import ../../render.bend as R

def camera(view: U32) -> R.Camera:
  match view:
    case 0: R.Camera{R.Vec3{20.0,4.0,4.0},3.14159265,0.0}
    case 1: R.Camera{R.Vec3{F32.neg(12.0),4.0,4.0},0.0,0.0}
    case 2: R.Camera{R.Vec3{4.0,20.0,4.0},F32.neg(1.57079633),0.0}
    case 3: R.Camera{R.Vec3{4.0,F32.neg(12.0),4.0},1.57079633,0.0}
    case 4: R.Camera{R.Vec3{4.0,4.0,20.0},0.0,F32.neg(1.57079633)}
    case _: R.Camera{R.Vec3{4.0,4.0,F32.neg(12.0)},0.0,1.57079633}

def materials() -> X.Body:
  body = X.Body.empty(3n)
  body = X.Body.write(body,X.Cell{0,3,3},1)
  body = X.Body.write(body,X.Cell{1,3,3},2)
  body = X.Body.write(body,X.Cell{2,3,3},3)
  body = X.Body.write(body,X.Cell{3,3,3},4)
  body = X.Body.write(body,X.Cell{4,3,3},5)
  body = X.Body.write(body,X.Cell{5,3,3},2147483648)
  body = X.Body.write(body,X.Cell{6,3,3},2309737967)
  X.Body.write(body,X.Cell{7,3,3},4294967295)

def expected(+index: U32, carved: Bool) -> U32:
  +x = (index % 8 : U32)
  +y = (index / 8 % 8 : U32)
  +z = (index / 64 : U32)
  +dx = (U32.to_f32(x) * 10.0 + 5.0 - 65.0 : F32)
  +dy = (U32.to_f32(y) * 10.0 + 5.0 - 65.0 : F32)
  +dz = (U32.to_f32(z) * 10.0 + 5.0 - 65.0 : F32)
  Bool.pick(U32,carved && (dx * dx + dy * dy + dz * dz <= 400.0 : F32),0,1)

def join(left: Array<U32> & Bool, right: Array<U32> & Bool) -> Array<U32> & Bool:
  (a,ok) = left
  (b,valid) = right
  (ANode{a,b},ok && valid)

def cells_ok(cells: Array<U32>, +index: U32, +span: U32, +carved: Bool) -> Array<U32> & Bool:
  match cells:
    case ALeaf{+mat}: (ALeaf{mat},U32.is_eq(mat,expected(index,carved)))
    case ANode{left,right}:
      a = cells_ok(left,index,(span / 2 : U32),carved)
      b = cells_ok(right,(index + span / 2 : U32),(span / 2 : U32),carved)
      join(a,b)

def body_ok(pair: Array<U32> & Bool) -> X.Body & Bool:
  (cells,ok) = pair
  (X.Body{8,cells},ok)

def cube(body: X.Body, carved: Bool) -> X.Body & Bool:
  match body:
    case X.Body{side,cells}: body_ok(cells_ok(cells,0,512,carved))
    case X.Cuboids{boxes}: (X.Cuboids{boxes},False{})
