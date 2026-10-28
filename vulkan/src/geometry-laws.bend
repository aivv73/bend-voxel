import Base
import ./mesh.bend as M
import ./exterior.bend as E
import ../../voxel.bend as X

def material(face: X.Face) -> U32:
  match face:
    case X.Face{c,d,m}: m
    case X.Rectangle{c,d,m,w,h}: m

def face_direction(face: X.Face) -> X.Direction:
  match face:
    case X.Face{c,d,m}: d
    case X.Rectangle{c,d,m,w,h}: d

def sub(a: X.Cell, b: X.Cell) -> X.Cell:
  X.Cell{x,y,z} = a
  X.Cell{u,v,w} = b
  X.Cell{(x - u : U32),(y - v : U32),(z - w : U32)}

def cross(a: X.Cell, b: X.Cell) -> X.Cell:
  X.Cell{+x,+y,+z} = a
  X.Cell{+u,+v,+w} = b
  X.Cell{(y * w - z * v : U32),(z * u - x * w : U32),(x * v - y * u : U32)}

def first(+d: U32) -> X.Cell:
  cross(sub(M.corner(d,1,2,3),M.corner(d,0,2,3)),sub(M.corner(d,2,2,3),M.corner(d,0,2,3)))

def second(+d: U32) -> X.Cell:
  cross(sub(M.corner(d,3,2,3),M.corner(d,2,2,3)),sub(M.corner(d,0,2,3),M.corner(d,2,2,3)))

def materials(fs: List<&2,X.Face>) -> List<U32>:
  match fs:
    case Nil{}: Nil{}
    case face <> rest: material(face) <> materials(rest)

def repeated(rs: List<&2,E.Rect2>, +m: U32) -> List<U32>:
  match rs:
    case Nil{}: Nil{}
    case r <> rest: m <> repeated(rest,m)

def bounded_count_step(faces: List<&2,X.Face>, +n: U32) -> Result<&2,&2,E.Error,U32>:
  do Result<&2,&2,E.Error,U32>:
    ok : Unit <- Bool.pick(Result<&2,&2,E.Error,Unit>,(n < E.quad_limit() : U32),Done{Unit{}},Fail{E.GeometryTooLarge{}})
    E.count(faces,(n + 1 : U32))
