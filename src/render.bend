import Base
import ./vendor/bend3d.bend as R
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
def view(+c: R.Cam, p: R.Vec) -> R.Vec:
  R.Cam{eye, right, up, fwd, _, _, _, _, _, _} = c
  +d = R.Vec.sub(p, eye)
  R.Vec{R.Vec.dot(d, right), R.Vec.dot(d, up), R.Vec.dot(d, fwd)}
def depth(+p: R.Vec) -> F32:
  R.Vec{_, _, z} = p
  z

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
def tangent(s: U32) -> R.Vec:
  match s:
    case 0:
      R.Vec{0.0, 0.0, 0.05}
    case 1:
      R.Vec{0.0, 0.05, 0.0}
    case 2:
      R.Vec{0.05, 0.0, 0.0}
    case 3:
      R.Vec{0.0, 0.0, 0.05}
    case 4:
      R.Vec{0.0, 0.05, 0.0}
    case _:
      R.Vec{0.05, 0.0, 0.0}

# Clip view-space geometry at z >= 0.05, then project directly. Unlike
# Cam.proj this intentionally accepts vertices exactly on the clipping plane.
def projected(p: R.Vec, color: R.Vec) -> R.Vert:
  R.Vec{x, y, +z} = p
  R.Vec{r, g, b} = color
  R.Vert{(320.0 + 400.0 * x / z : F32), (180.0 - 400.0 * y / z : F32), (1.0 / z : F32), r, g, b}
def crossing(+a: R.Vec, +b: R.Vec) -> R.Vec:
  R.Vec.mix(a, b, ((0.05 - depth(a)) / (depth(b) - depth(a)) : F32))
def clip.edge(aon: Bool, bon: Bool, +a: R.Vec, +b: R.Vec, acc: List<R.Vec>) -> List<R.Vec>:
  match aon bon:
    case True{} True{}:
      b <> acc
    case True{} False{}:
      crossing(a, b) <> acc
    case False{} True{}:
      b <> crossing(a, b) <> acc
    case False{} False{}:
      acc
def clip.walk(xs: List<R.Vec>, +prev: R.Vec, acc: List<R.Vec>) -> List<R.Vec>:
  match xs:
    case Nil{}:
      acc
    case +p <> rest:
      clip.walk(rest, p, clip.edge((depth(prev) >= 0.05 : F32), (depth(p) >= 0.05 : F32), prev, p, acc))
def reverse(xs: List<R.Vec>, acc: List<R.Vec>) -> List<R.Vec>:
  match xs:
    case Nil{}:
      acc
    case p <> rest:
      reverse(rest, p <> acc)
def fan.rest(xs: List<R.Vec>, +a: R.Vec, +b: R.Vec, +color: R.Vec, cells: R.Cells) -> R.Cells:
  match xs:
    case Nil{}:
      cells
    case +c <> rest:
      fan.rest(rest, a, c, color, R.Mesh.raster(projected(a, color), projected(b, color), projected(c, color), 0, 1.0, 639.0, 359.0, cells))
def fan(xs: List<R.Vec>, color: R.Vec, cells: R.Cells) -> R.Cells:
  match xs:
    case a <> b <> rest:
      fan.rest(rest, a, b, color, cells)
    case _:
      cells
def triangle(+a: R.Vec, +b: R.Vec, +c: R.Vec, color: R.Vec, cells: R.Cells) -> R.Cells:
  fan(reverse(clip.walk([a, b, c], c, Nil{}), Nil{}), color, cells)
def quad(+a: R.Vec, +b: R.Vec, +c: R.Vec, +d: R.Vec, +color: R.Vec, cells: R.Cells) -> R.Cells:
  triangle(a, c, d, color, triangle(a, b, c, color, cells))
def face.draw(on: Bool, +rows: U32, +len: U32, +p: R.Vec, +side: U32, +cam: R.Cam, +color: R.Vec, cells: R.Cells) -> R.Cells:
  match on:
    case False{}:
      cells
    case True{}:
      +n = normal(side)
      +u = tangent(side)
      +v = R.Vec.cross(n, u)
      +u = R.Vec.scale(u, R.pick(((U32.is_eq(side,0) || U32.is_eq(side,2)) || U32.is_eq(side,5)), U32.to_f32(len), 1.0))
      +v = R.Vec.scale(v, R.pick(((U32.is_eq(side,1) || U32.is_eq(side,3)) || U32.is_eq(side,4)), U32.to_f32(len), 1.0))
      +u = R.Vec.scale(u,R.pick(U32.is_eq(side,3),U32.to_f32(rows),1.0))
      +v = R.Vec.scale(v,R.pick(U32.is_eq(side,2),U32.to_f32(rows),1.0))
      +c = R.Vec.add(p, R.Vec.scale(n, 0.05))
      quad(view(cam, R.Vec.sub(R.Vec.sub(c, u), v)), view(cam, R.Vec.sub(R.Vec.add(c, u), v)),
        view(cam, R.Vec.add(R.Vec.add(c, u), v)), view(cam, R.Vec.add(R.Vec.sub(c, u), v)), color, cells)
def face.center(i: U32, +side: U32, len: U32, rows: U32, offset: F32) -> R.Vec:
  +half = (U32.to_f32((len - 1 : U32)) * 0.05 : F32)
  R.Vec.add(W.xyz(i), R.Vec{R.pick((side < 2 : U32),0.0,half),offset,R.pick((side < 2 : U32),half,(U32.to_f32((rows - 1 : U32)) * 0.05 : F32))})
def face.single(+i: U32, +side: U32, +len: U32, +rows: U32, +id: U32, +offset: F32, +cam: R.Cam, selected: Bool, cells: R.Cells) -> R.Cells:
  +p = face.center(i,side,len,rows,offset)
  +anchor = (U32.is_eq(id,1) && U32.is_eq((i / 40 % 24 : U32),0))
  +rgb = R.word(selected,16768872,R.word(anchor,4964772,R.word((id > 1 : U32),11375835,13736040)))
  +shade = R.pick(U32.is_eq(side,3),1.0,R.pick((side < 2 : U32),0.78,0.62))
  face.draw((R.Vec.dot(normal(side),R.Vec.sub(R.Cam.eye(cam),p)) > 0.05 : F32),rows,len,p,side,cam,R.Vec.scale(R.Vec.rgb(rgb),shade),cells)
def face.detail(n: Nat, +i: U32, +side: U32, +id: U32, +offset: F32, +cam: R.Cam, +point: R.Vec, cells: R.Cells) -> R.Cells:
  match n:
    case 0n: cells
    case 1n+k:
      face.detail(k,W.face.next(i,side),side,id,offset,cam,point,face.single(i,side,1,1,id,offset,cam,W.inside(i,offset,point),cells))
def face.segment(len: U32, i: U32, side: U32, id: U32, offset: F32, cam: R.Cam, cells: R.Cells) -> R.Cells:
  match len:
    case 0: cells
    case other: face.single(i,side,other,1,id,offset,cam,False{},cells)
def face.partition(+t: F32, +i: U32, +side: U32, +len: U32, +id: U32, +offset: F32, +cam: R.Cam, +point: R.Vec, cells: R.Cells) -> R.Cells:
  +begin = F32.to_u32(F32.floor(R.clamp((t * 10.0 - 2.01 : F32),0.0,U32.to_f32(len))))
  +end = F32.to_u32(F32.ceil(R.clamp((t * 10.0 + 2.01 : F32),0.0,U32.to_f32(len))))
  +stride = R.word((side < 2 : U32),960,1)
  face.segment((len - end : U32),(i + end * stride : U32),side,id,offset,cam,
    face.detail(U32.to_nat((end - begin : U32)),(i + begin * stride : U32),side,id,offset,cam,point,
      face.segment(begin,i,side,id,offset,cam,cells)))
def face.detail.row(near: Bool, +i: U32, +side: U32, len: U32, id: U32, offset: F32, cam: R.Cam, +point: R.Vec, cells: R.Cells) -> R.Cells:
  match near:
    case True{}:
      W.vec(R.Cells,R.Vec.sub(point,W.xyz(i)),x => y => z =>
        face.partition(R.pick((side < 2 : U32),z,x),i,side,len,id,offset,cam,point,cells))
    case False{}: face.single(i,side,len,1,id,offset,cam,False{},cells)
def face.detail.rows(n: Nat, +i: U32, +side: U32, +len: U32, +id: U32, +offset: F32, +cam: R.Cam, +point: R.Vec, cells: R.Cells) -> R.Cells:
  match n:
    case 0n: cells
    case 1n+k:
      +near = W.vec(Bool,R.Vec.sub(point,face.center(i,side,len,1,offset)),x => y => z =>
        (Bool.not((U32.is_eq(side,2) || U32.is_eq(side,3))) || ((F32.abs(y) <= 0.201) && (F32.abs(z) <= 0.201) : F32)))
      face.detail.rows(k,W.neighbor(i,5),side,len,id,offset,cam,point,face.detail.row(near,i,side,len,id,offset,cam,point,cells))
def face.choose(detail: Bool, +i: U32, +side: U32, len: U32, rows: U32, id: U32, offset: F32, cam: R.Cam, point: R.Vec, cells: R.Cells) -> R.Cells:
  match detail:
    case True{}: face.detail.rows(U32.to_nat(rows),i,side,len,id,offset,cam,point,cells)
    case False{}: face.single(i,side,len,rows,id,offset,cam,False{},cells)
def faces(fs: List<&2,W.Face>, +id: U32, +offset: F32, +cam: R.Cam, +aim: Aim, cells: R.Cells) -> R.Cells:
  match fs:
    case Nil{}: cells
    case W.Face{+i,+side,+len,+rows} <> rest:
      Aim{+point,_,kind} = aim
      +d = R.Vec.sub(point,face.center(i,side,len,rows,offset))
      +near = W.vec(Bool,d,+x => +y => +z => (((F32.abs(y) <= 0.201) && (F32.abs(x) <= R.pick((side < 2 : U32),0.201,(0.201 + U32.to_f32(len) * 0.05 : F32))) && (F32.abs(z) <= R.pick((side < 2 : U32),(0.201 + U32.to_f32(len) * 0.05 : F32),(0.201 + U32.to_f32(rows) * 0.05 : F32)))) : F32))
      faces(rest,id,offset,cam,aim,face.choose((U32.is_eq(kind,1) && near && Bool.not((U32.is_eq(id,1) && U32.is_eq((i / 40 % 24 : U32),0)))),i,side,len,rows,id,offset,cam,point,cells))
def bodies(bs: List<&2, W.Body>, +cam: R.Cam, +aim: Aim, cells: R.Cells) -> R.Cells:
  match bs:
    case Nil{}:
      cells
    case W.Body{id, offset, _, _, fs} <> rest:
      bodies(rest, cam, aim, faces(fs, id, offset, cam, aim, cells))
def floor(+cam: R.Cam, cells: R.Cells) -> R.Cells:
  quad(view(cam, R.Vec{(0.0 - 6.0 : F32), 0.0, (0.0 - 6.0 : F32)}),
    view(cam, R.Vec{(0.0 - 6.0 : F32), 0.0, 6.0}), view(cam, R.Vec{6.0, 0.0, 6.0}),
    view(cam, R.Vec{6.0, 0.0, (0.0 - 6.0 : F32)}), R.Vec{0.12, 0.19, 0.24}, cells)
def build(bs: List<&2, W.Body>, +c: Camera, aim: Aim) -> R.Cells:
  bodies(bs, cam(c), aim, floor(cam(c), R.CNil{}))
def sky(+x: U32, +y: U32, +size: U32) -> U32:
  1187886
def flat(+s: U32, +x: U32, +y: U32, +size: U32) -> Bool:
  True{}
def column(per: Bool, +x: U32, +s: U32) -> U32:
  s
def pixel(+x: U32, +y: U32, +s: U32) -> U32:
  s
def width() -> U32:
  640
def height() -> U32:
  360
def frame(cells: R.Cells, old: Image) -> Image & R.Cells:
  R.Frame.show(~U32, ~sky, ~flat, ~column, ~pixel, ~width, ~height, cells, old)

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

def screen.line(on: Bool, a: R.Vec, b: R.Vec, col: U32, cells: R.Cells) -> R.Cells:
  match on:
    case False{}:
      cells
    case True{}:
      R.Vec{ax, ay, +az} = a
      R.Vec{bx, by, +bz} = b
      R.Text.seg((320.0 + 400.0 * ax / az : F32), (180.0 - 400.0 * ay / az : F32),
        (320.0 + 400.0 * bx / bz : F32), (180.0 - 400.0 * by / bz : F32), 0.45, 0.45, col, 639.0, 359.0, cells)
def ring.point(axis: U32, +a: F32, +p: R.Vec) -> R.Vec:
  match axis:
    case 0:
      R.Vec.add(p, R.Vec{0.0, (0.2 * F32.cos(a) : F32), (0.2 * F32.sin(a) : F32)})
    case 1:
      R.Vec.add(p, R.Vec{(0.2 * F32.cos(a) : F32), 0.0, (0.2 * F32.sin(a) : F32)})
    case _:
      R.Vec.add(p, R.Vec{(0.2 * F32.cos(a) : F32), (0.2 * F32.sin(a) : F32), 0.0})
def ring(n: Nat, +i: U32, +axis: U32, +p: R.Vec, +cam: R.Cam, +col: U32, cells: R.Cells) -> R.Cells:
  match n:
    case 0n:
      cells
    case 1n+k:
      +a = view(cam, ring.point(axis, (U32.to_f32(i) * 0.5235988 : F32), p))
      +b = view(cam, ring.point(axis, (U32.to_f32((i + 1 : U32)) * 0.5235988 : F32), p))
      ring(k, (i + 1 : U32), axis, p, cam, col, screen.line(((depth(a) >= 0.05) && (depth(b) >= 0.05) : F32), a, b, col, cells))
def preview(on: Bool, aim: Aim, +c: Camera, cells: R.Cells) -> R.Cells:
  match on:
    case False{}:
      cells
    case True{}:
      Aim{+p, _, +kind} = aim
      +col = R.word(U32.is_eq(kind, 1), 16768872, 16552594)
      ring(12n, 0, 0, p, cam(c), col, ring(12n, 0, 1, p, cam(c), col, ring(12n, 0, 2, p, cam(c), col, cells)))
