# Vector and camera primitives adapted from Bend3D. See vendor/NOTICE.md.
import Base

type Vec is Data:
  Vec{x: F32, y: F32, z: F32}

def pick(c: Bool, a: F32, b: F32) -> F32:
  match c:
    case True{}: a
    case False{}: b

def word(c: Bool, a: U32, b: U32) -> U32:
  match c:
    case True{}: a
    case False{}: b

def min(+a: F32, +b: F32) -> F32:
  pick((a < b : F32), a, b)

def max(+a: F32, +b: F32) -> F32:
  pick((a < b : F32), b, a)

def clamp(+x: F32, +lo: F32, +hi: F32) -> F32:
  min(hi, max(lo, x))

def Vec.add(+a: Vec, +b: Vec) -> Vec:
  Vec{ax, ay, az} = a
  Vec{bx, by, bz} = b
  Vec{(ax + bx : F32), (ay + by : F32), (az + bz : F32)}

def Vec.sub(+a: Vec, +b: Vec) -> Vec:
  Vec{ax, ay, az} = a
  Vec{bx, by, bz} = b
  Vec{(ax - bx : F32), (ay - by : F32), (az - bz : F32)}

def Vec.scale(+a: Vec, +k: F32) -> Vec:
  Vec{x, y, z} = a
  Vec{(x * k : F32), (y * k : F32), (z * k : F32)}

def Vec.dot(+a: Vec, +b: Vec) -> F32:
  Vec{ax, ay, az} = a
  Vec{bx, by, bz} = b
  (ax * bx + ay * by + az * bz : F32)

def Vec.len(+v: Vec) -> F32:
  F32.sqrt(Vec.dot(v, v))

def Vec.unit(+v: Vec) -> Vec:
  Vec.scale(v, (1.0 / max(0.00001, Vec.len(v)) : F32))

type Cam is Data:
  Cam{eye: Vec, right: Vec, up: Vec, fwd: Vec, focal: F32, cx: F32, cy: F32, near: F32, w: U32, h: U32}
