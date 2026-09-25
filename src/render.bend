import Base
import ./math.bend as R
import ./world.bend as W
import ./spatial.bend as S
import ./material.bend as M

type Camera is Data:
  Camera{eye: R.Vec, yaw: F32, pitch: F32}
type Aim is Data:
  Aim{point: R.Vec, distance: F32, kind: U32}

def camera() -> Camera:
  Camera{R.Vec{44.0, 30.0, 48.0}, (0.0 - 2.40 : F32), (0.0 - 0.34 : F32)}
def camera.showcase() -> Camera:
  Camera{R.Vec{160.0, 145.0, 500.0}, 3.1415927, (0.0 - 0.40 : F32)}
def cam(+c: Camera) -> R.Cam:
  Camera{eye, +yaw, +pitch} = c
  +sy = F32.sin(yaw)
  +cy = F32.cos(yaw)
  +sp = F32.sin(pitch)
  +cp = F32.cos(pitch)
  R.Cam{eye, R.Vec{(0.0 - cy : F32), 0.0, sy}, R.Vec{(0.0 - sy * sp : F32), cp, (0.0 - cy * sp : F32)}, R.Vec{(sy * cp : F32), sp, (cy * cp : F32)}, 400.0, 320.0, 180.0, 0.05, 640, 360}
# Ray-box traversal uses the same sparse tree as edits and connectivity.
# Distances are meters; leaf bounds are converted from integer cell space.
type Interval is Data:
  Interval{near: F32, far: F32}
def interval(a: Interval, b: Interval) -> Interval:
  Interval{an,af} = a
  Interval{bn,bf} = b
  Interval{R.max(an,bn),R.min(af,bf)}
def slab.parallel(inside: Bool) -> Interval:
  match inside:
    case True{}: Interval{(0.0 - 1000000.0 : F32),1000000.0}
    case False{}: Interval{1000000.0,(0.0 - 1000000.0 : F32)}
def slab.go(parallel: Bool, +o: F32, +d: F32, +l: F32, +h: F32) -> Interval:
  match parallel:
    case True{}: slab.parallel(((o >= l) && (o < h) : F32))
    case False{}:
      +a = ((l - o) / d : F32)
      +b = ((h - o) / d : F32)
      Interval{R.min(a,b),R.max(a,b)}
def slab(o: F32, +d: F32, l: F32, h: F32) -> Interval:
  slab.go((F32.abs(d) < 0.0000001 : F32),o,d,l,h)
def ray.box(b: S.Box, o: R.Vec, d: R.Vec, +offset: F32) -> Interval:
  S.Box{R.Vec{lx,ly,lz},R.Vec{hx,hy,hz},_} = b
  R.Vec{x,y,z} = o
  R.Vec{u,v,w} = d
  interval(slab(x,u,(lx * 0.1 : F32),(hx * 0.1 : F32)),
    interval(slab(y,v,(ly * 0.1 + offset : F32),(hy * 0.1 + offset : F32)),
      slab(z,w,(lz * 0.1 : F32),(hz * 0.1 : F32))))
def ray.possible(r: Interval, best: Aim) -> Bool:
  Interval{+near,+far} = r
  Aim{_,limit,_} = best
  (((far >= R.max(0.0,near)) && (near < limit)) : F32)
def aim.choose(on: Bool, p: R.Vec, t: F32, kind: U32, old: Aim) -> Aim:
  match on:
    case True{}: Aim{p,t,kind}
    case False{}: old
def ray.leaf(r: Interval, material: U32, +o: R.Vec, +d: R.Vec, +best: Aim) -> Aim:
  Interval{+near,far} = r
  Aim{_,limit,_} = best
  +t = R.pick((near >= 0.0 : F32),near,far)
  aim.choose(((t >= 0.0) && (t < limit) : F32),R.Vec.add(o,R.Vec.scale(d,t)),t,
    R.word(M.is_anchor(material),2,1),best)
@unsafe
def ray.tree.go(on: Bool, t: S.Tree, +offset: F32, +o: R.Vec, +d: R.Vec, best: Aim) -> Aim:
  match on t:
    case False{} _: best
    case True{} S.Empty{}: best
    case True{} S.Leaf{+b}:
      S.Box{_,_,m} = b
      ray.leaf(ray.box(b,o,d,offset),m,o,d,best)
    case True{} S.Branch{_,a,b}:
      ray.tree(b,offset,o,d,ray.tree(a,offset,o,d,best))
@unsafe
def ray.tree(+t: S.Tree, +offset: F32, +o: R.Vec, +d: R.Vec, +best: Aim) -> Aim:
  ray.tree.go(ray.possible(ray.box(S.bounds(t),o,d,offset),best),t,offset,o,d,best)
def ray.bodies(bs: List<&2,W.Body>, +o: R.Vec, +d: R.Vec, best: Aim) -> Aim:
  match bs:
    case Nil{}: best
    case W.Body{_,_,offset,_,_,t,_} <> rest:
      ray.bodies(rest,o,d,ray.tree(t,offset,o,d,best))
def ray.start(bs: List<&2,W.Body>, +o: R.Vec, +d: R.Vec) -> Aim:
  R.Vec{_,y,_} = o
  R.Vec{_,+dy,_} = d
  +t = (0.0 - y / R.pick((F32.abs(dy) > 0.000001 : F32),dy,0.000001) : F32)
  ray.bodies(bs,o,d,aim.choose(((dy < 0.0) && (t < 256.0) && (t >= 0.0) : F32),
    R.Vec.add(o,R.Vec.scale(d,t)),t,3,Aim{R.Vec{0.0,0.0,0.0},256.0,0}))
def ray.cam(c: R.Cam, bs: List<&2,W.Body>, mx: F32, my: F32) -> Aim:
  R.Cam{eye,right,up,fwd,_,_,_,_,_,_} = c
  ray.start(bs,eye,R.Vec.unit(R.Vec.add(fwd,R.Vec.add(R.Vec.scale(right,((mx - 320.0) / 400.0 : F32)),R.Vec.scale(up,((180.0 - my) / 400.0 : F32))))))
def aim(active: Bool, bs: List<&2,W.Body>, c: Camera, mx: U32, my: U32) -> Aim:
  match active:
    case True{}: ray.cam(cam(c),bs,U32.to_f32(mx),U32.to_f32(my))
    case False{}: Aim{R.Vec{0.0,0.0,0.0},256.0,0}
