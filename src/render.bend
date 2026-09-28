import Base
import ./math.bend as R
import ./world.bend as W
import ./spatial.bend as S
import ./material.bend as M

type Camera is Data:
  Camera{eye: R.Vec, yaw: F32, pitch: F32, width: U32, height: U32}
type Aim is Data:
  Aim{point: R.Vec, distance: F32, kind: U32}

# Picking retains the winning leaf's identity without changing Aim or tie order.
type Hit is Data:
  Hit{aim: Aim, owner: U32, material: U32}
def hit.aim(h: Hit) -> Aim:
  Hit{a,_,_} = h
  a

def camera.size(width: U32, height: U32) -> Camera:
  Camera{R.Vec{9.0, 11.0, 25.0}, (0.0 - 2.8084 : F32), (0.0 - 0.30 : F32),width,height}
def camera() -> Camera:
  camera.size(640,360)
def cam(+c: Camera) -> R.Cam:
  Camera{eye, +yaw, +pitch, +width, +height} = c
  +sy = F32.sin(yaw)
  +cy = F32.cos(yaw)
  +sp = F32.sin(pitch)
  +cp = F32.cos(pitch)
  R.Cam{eye, R.Vec{(0.0 - cy : F32), 0.0, sy}, R.Vec{(0.0 - sy * sp : F32), cp, (0.0 - cy * sp : F32)}, R.Vec{(sy * cp : F32), sp, (cy * cp : F32)},
    (400.0 * U32.to_f32(height) / 360.0 : F32), (U32.to_f32(width) * 0.5 : F32),
    (U32.to_f32(height) * 0.5 : F32), 0.05, width, height}
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
def hit.choose(on: Bool, p: R.Vec, t: F32, kind: U32, owner: U32, material: U32, old: Hit) -> Hit:
  match on:
    case True{}: Hit{Aim{p,t,kind},owner,material}
    case False{}: old
def hit.leaf(r: Interval, +material: U32, owner: U32, +o: R.Vec, +d: R.Vec, +best: Hit) -> Hit:
  Interval{+near,far} = r
  Hit{Aim{_,limit,_},_,_} = best
  +t = R.pick((near >= 0.0 : F32),near,far)
  hit.choose(((t >= 0.0) && (t < limit) : F32),R.Vec.add(o,R.Vec.scale(d,t)),t,
    R.word(M.is_anchor(material),2,1),owner,material,best)
@unsafe
def hit.tree.go(on: Bool, t: S.Tree, +owner: U32, +offset: F32, +o: R.Vec, +d: R.Vec, best: Hit) -> Hit:
  match on t:
    case False{} _: best
    case True{} S.Empty{}: best
    case True{} S.Leaf{+b}:
      S.Box{_,_,m} = b
      hit.leaf(ray.box(b,o,d,offset),m,owner,o,d,best)
    case True{} S.Branch{_,a,b}:
      hit.tree(b,owner,offset,o,d,hit.tree(a,owner,offset,o,d,best))
@unsafe
def hit.tree(+t: S.Tree, +owner: U32, +offset: F32, +o: R.Vec, +d: R.Vec, +best: Hit) -> Hit:
  hit.tree.go(ray.possible(ray.box(S.bounds(t),o,d,offset),hit.aim(best)),t,owner,offset,o,d,best)
def hit.bodies(bs: List<&2,W.Body>, +o: R.Vec, +d: R.Vec, best: Hit) -> Hit:
  match bs:
    case Nil{}: best
    case W.Body{id,_,offset,_,_,t,_,_} <> rest:
      hit.bodies(rest,o,d,hit.tree(t,id,offset,o,d,best))
def hit.start(bs: List<&2,W.Body>, +o: R.Vec, +d: R.Vec) -> Hit:
  R.Vec{_,y,_} = o
  R.Vec{_,+dy,_} = d
  +t = (0.0 - y / R.pick((F32.abs(dy) > 0.000001 : F32),dy,0.000001) : F32)
  hit.bodies(bs,o,d,Hit{aim.choose(((dy < 0.0) && (t < 256.0) && (t >= 0.0) : F32),
    R.Vec.add(o,R.Vec.scale(d,t)),t,3,Aim{R.Vec{0.0,0.0,0.0},256.0,0}),0,0})
# Existing interactive/public entry points use the same identified traversal.
def ray.tree(t: S.Tree, offset: F32, o: R.Vec, d: R.Vec, best: Aim) -> Aim:
  hit.aim(hit.tree(t,0,offset,o,d,Hit{best,0,0}))
def ray.start(bs: List<&2,W.Body>, o: R.Vec, d: R.Vec) -> Aim:
  hit.aim(hit.start(bs,o,d))
def ray.direction(c: R.Cam, mx: F32, my: F32) -> R.Vec:
  R.Cam{_,right,up,fwd,+focal,+cx,+cy,_,_,_} = c
  R.Vec.unit(R.Vec.add(fwd,R.Vec.add(R.Vec.scale(right,((mx - cx) / focal : F32)),R.Vec.scale(up,((cy - my) / focal : F32)))))
def ray.cam(+c: R.Cam, bs: List<&2,W.Body>, mx: F32, my: F32) -> Aim:
  R.Cam{eye,_,_,_,_,_,_,_,_,_} = c
  ray.start(bs,eye,ray.direction(c,mx,my))
def aim(active: Bool, bs: List<&2,W.Body>, c: Camera, mx: U32, my: U32) -> Aim:
  match active:
    case True{}: ray.cam(cam(c),bs,U32.to_f32(mx),U32.to_f32(my))
    case False{}: Aim{R.Vec{0.0,0.0,0.0},256.0,0}
