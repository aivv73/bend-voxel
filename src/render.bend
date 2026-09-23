import Base
import ./math.bend as R
import ./world.bend as W

type Camera is Data:
  Camera{eye: R.Vec, yaw: F32, pitch: F32}
type Aim is Data:
  Aim{point: R.Vec, distance: F32, kind: U32}

def camera() -> Camera:
  Camera{R.Vec{5.0, 3.4, 6.0}, (0.0 - 2.4468544 : F32), (0.0 - 0.23 : F32)}
def cam(+c: Camera) -> R.Cam:
  Camera{eye, +yaw, +pitch} = c
  +sy = F32.sin(yaw)
  +cy = F32.cos(yaw)
  +sp = F32.sin(pitch)
  +cp = F32.cos(pitch)
  R.Cam{eye, R.Vec{(0.0 - cy : F32), 0.0, sy}, R.Vec{(0.0 - sy * sp : F32), cp, (0.0 - cy * sp : F32)}, R.Vec{(sy * cp : F32), sp, (cy * cp : F32)}, 400.0, 320.0, 180.0, 0.05, 640, 360}
def normal(s: U32) -> R.Vec:
  match s:
    case 0:
      R.Vec{(0.0 - 1.0 : F32), 0.0, 0.0}
    case 1:
      R.Vec{1.0, 0.0, 0.0}
    case 2:
      R.Vec{0.0, (0.0 - 1.0 : F32), 0.0}
    case 3:
      R.Vec{0.0, 1.0, 0.0}
    case 4:
      R.Vec{0.0, 0.0, (0.0 - 1.0 : F32)}
    case _:
      R.Vec{0.0, 0.0, 1.0}
def face.center(i: U32, +side: U32, len: U32, rows: U32, offset: F32) -> R.Vec:
  +half = (U32.to_f32((len - 1 : U32)) * 0.05 : F32)
  R.Vec.add(W.xyz(i), R.Vec{R.pick((side < 2 : U32),0.0,half),offset,R.pick((side < 2 : U32),half,(U32.to_f32((rows - 1 : U32)) * 0.05 : F32))})
def aim.choose(on: Bool, p: R.Vec, t: F32, kind: U32, old: Aim) -> Aim:
  match on:
    case True{}:
      Aim{p, t, kind}
    case False{}:
      old
def ray.face(+rows: U32, +len: U32, +i: U32, +side: U32, +offset: F32, +owner: U32, +o: R.Vec, +d: R.Vec, +best: Aim) -> Aim:
  Aim{_, limit, _} = best
  +n = normal(side)
  +p = face.center(i,side,len,rows,offset)
  +den = R.Vec.dot(d, n)
  +t = ((R.Vec.dot(R.Vec.sub(p, o), n) + 0.05) / R.pick((F32.abs(den) > 0.000001 : F32), den, 0.000001) : F32)
  +hit = R.Vec.add(o, R.Vec.scale(d, t))
  W.vec(Aim, R.Vec.sub(hit, p), +x => +y => +z =>
    aim.choose(((F32.abs(den) > 0.000001) && (t >= 0.0) && (t < limit) && (F32.abs(x) <= R.pick((side < 2 : U32),0.05001,(U32.to_f32(len) * 0.05 + 0.00001 : F32))) && (F32.abs(y) <= 0.05001) && (F32.abs(z) <= R.pick((side < 2 : U32),(U32.to_f32(len) * 0.05 + 0.00001 : F32),(U32.to_f32(rows) * 0.05 + 0.00001 : F32))) : F32), hit, t,
      R.word((U32.is_eq(owner, 1) && U32.is_eq((i / 40 % 24 : U32), 0)), 2, 1), best))
def ray.faces(fs: List<&2, W.Face>, +id: U32, +offset: F32, +o: R.Vec, +d: R.Vec, best: Aim) -> Aim:
  match fs:
    case Nil{}:
      best
    case W.Face{lenI, side, len, rows} <> rest:
      ray.faces(rest, id, offset, o, d, ray.face(rows, len, lenI, side, offset, id, o, d, best))
def ray.bodies(bs: List<&2, W.Body>, +o: R.Vec, +d: R.Vec, best: Aim) -> Aim:
  match bs:
    case Nil{}:
      best
    case W.Body{id, offset, _, _, fs} <> rest:
      ray.bodies(rest, o, d, ray.faces(fs, id, offset, o, d, best))
def ray.start(bs: List<&2, W.Body>, +o: R.Vec, +d: R.Vec) -> Aim:
  R.Vec{_, y, _} = o
  R.Vec{_, +dy, _} = d
  +t = (0.0 - y / R.pick((F32.abs(dy) > 0.000001 : F32), dy, 0.000001) : F32)
  ray.bodies(bs, o, d, aim.choose(((dy < 0.0) && (t < 14.0) && (t >= 0.0) : F32), R.Vec.add(o, R.Vec.scale(d, t)), t, 3, Aim{R.Vec{0.0, 0.0, 0.0}, 14.0, 0}))
def ray.cam(c: R.Cam, bs: List<&2, W.Body>, mx: F32, my: F32) -> Aim:
  R.Cam{eye, right, up, fwd, _, _, _, _, _, _} = c
  ray.start(bs, eye, R.Vec.unit(R.Vec.add(fwd, R.Vec.add(R.Vec.scale(right, ((mx - 320.0) / 400.0 : F32)), R.Vec.scale(up, ((180.0 - my) / 400.0 : F32))))))
def aim(active: Bool, bs: List<&2, W.Body>, c: Camera, mx: U32, my: U32) -> Aim:
  match active:
    case True{}:
      ray.cam(cam(c), bs, U32.to_f32(mx), U32.to_f32(my))
    case False{}:
      Aim{R.Vec{0.0, 0.0, 0.0}, 14.0, 0}
