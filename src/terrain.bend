import Base
import ./vendor/bend3d.bend as R
import ./render.bend as V

# A 32^3 domain with 20 cm cells. Uniform regions are single leaves.
# Child bits are x + 2*y + 4*z; material 0 is empty space.
type Tree is Data:
  Leaf{material: U32}
  Branch{a: Tree, b: Tree, c: Tree, d: Tree, e: Tree, f: Tree, g: Tree, h: Tree}
type Face is Data:
  Face{x: U32, y: U32, z: U32, side: U32, material: U32}

def height(+x: U32, +z: U32) -> U32:
  +xf = U32.to_f32(x)
  +zf = U32.to_f32(z)
  F32.to_u32((10.0 + 4.0 * F32.sin((xf * 0.19 : F32)) + 3.0 * F32.cos((zf * 0.23 : F32)) + 2.0 * F32.sin(((xf + zf) * 0.31 : F32)) : F32))
def material(+x: U32, +y: U32, +z: U32) -> U32:
  +h = height(x,z)
  R.word((y >= h : U32),0,R.word(U32.is_eq((y + 1 : U32),h),R.word((h > 15 : U32),3,1),2))
def uniform(t: Tree, +m: U32) -> Bool:
  match t:
    case Leaf{k}: U32.is_eq(k,m)
    case Branch{_,_,_,_,_,_,_,_}: False{}
def merge.choose(same: Bool, m: U32, a: Tree, b: Tree, c: Tree, d: Tree, e: Tree, f: Tree, g: Tree, h: Tree) -> Tree:
  match same:
    case True{}: Leaf{m}
    case False{}: Branch{a,b,c,d,e,f,g,h}
def merge(+a: Tree, +b: Tree, +c: Tree, +d: Tree, +e: Tree, +f: Tree, +g: Tree, +h: Tree) -> Tree:
  match a:
    case Leaf{+m}:
      merge.choose((uniform(b,m) && uniform(c,m) && uniform(d,m) && uniform(e,m) && uniform(f,m) && uniform(g,m) && uniform(h,m)),m,Leaf{m},b,c,d,e,f,g,h)
    case Branch{aa,ab,ac,ad,ae,af,ag,ah}: Branch{Branch{aa,ab,ac,ad,ae,af,ag,ah},b,c,d,e,f,g,h}
def build(n: Nat, +x: U32, +y: U32, +z: U32, +size: U32) -> Tree:
  match n:
    case 0n: Leaf{material(x,y,z)}
    case 1n+ +k:
      +s = (size / 2 : U32)
      merge(
        build(k,x,y,z,s),
        build(k,(x + s : U32),y,z,s),
        build(k,x,(y + s : U32),z,s),
        build(k,(x + s : U32),(y + s : U32),z,s),
        build(k,x,y,(z + s : U32),s),
        build(k,(x + s : U32),y,(z + s : U32),s),
        build(k,x,(y + s : U32),(z + s : U32),s),
        build(k,(x + s : U32),(y + s : U32),(z + s : U32),s))
def initial() -> Tree:
  build(5n,0,0,0,32)
def get.child(child: U32, a: Tree, b: Tree, c: Tree, d: Tree, e: Tree, f: Tree, g: Tree, h: Tree) -> Tree:
  match child:
    case 0: a
    case 1: b
    case 2: c
    case 3: d
    case 4: e
    case 5: f
    case 6: g
    case _: h
@unsafe
def get(t: Tree, +x: U32, +y: U32, +z: U32, +size: U32) -> U32:
  match t:
    case Leaf{m}: m
    case Branch{a,b,c,d,e,f,g,h}:
      +s = (size / 2 : U32)
      +child = (R.word((x >= s : U32),1,0) + R.word((y >= s : U32),2,0) + R.word((z >= s : U32),4,0) : U32)
      +xx = (x % s : U32)
      +yy = (y % s : U32)
      +zz = (z % s : U32)
      get(get.child(child,a,b,c,d,e,f,g,h),xx,yy,zz,s)
def sample.inside(inside: Bool, t: Tree, x: U32, y: U32, z: U32) -> U32:
  match inside:
    case True{}: get(t,x,y,z,32)
    case False{}: 0
def sample(t: Tree, +x: U32, +y: U32, +z: U32) -> U32:
  sample.inside(((x < 32) && (y < 32) && (z < 32) : U32),t,x,y,z)
def nodes(t: Tree) -> U32:
  match t:
    case Leaf{_}: 1
    case Branch{a,b,c,d,e,f,g,h}: (1 + nodes(a) + nodes(b) + nodes(c) + nodes(d) + nodes(e) + nodes(f) + nodes(g) + nodes(h) : U32)
def solids(t: Tree, +size: U32) -> U32:
  match t:
    case Leaf{m}: R.word((m > 0 : U32),(size * size * size : U32),0)
    case Branch{a,b,c,d,e,f,g,h}:
      +s = (size / 2 : U32)
      (solids(a,s) + solids(b,s) + solids(c,s) + solids(d,s) + solids(e,s) + solids(f,s) + solids(g,s) + solids(h,s) : U32)
def neighbor(t: Tree, +x: U32, +y: U32, +z: U32, side: U32) -> U32:
  match side:
    case 0: sample(t,(x - 1 : U32),y,z)
    case 1: sample(t,(x + 1 : U32),y,z)
    case 2: sample(t,x,(y - 1 : U32),z)
    case 3: sample(t,x,(y + 1 : U32),z)
    case 4: sample(t,x,y,(z - 1 : U32))
    case _: sample(t,x,y,(z + 1 : U32))
def face.add(on: Bool, f: Face, fs: List<&2,Face>) -> List<&2,Face>:
  match on:
    case True{}: f <> fs
    case False{}: fs
def sides(n: Nat, +side: U32, +root: Tree, +x: U32, +y: U32, +z: U32, +m: U32, fs: List<&2,Face>) -> List<&2,Face>:
  match n:
    case 0n: fs
    case 1n+k:
      sides(k,(side + 1 : U32),root,x,y,z,m,face.add(U32.is_eq(neighbor(root,x,y,z,side),0),Face{x,y,z,side,m},fs))
# Traverse occupied leaves, subdividing only for the surface cache. The
# authoritative world stays compressed; no dense array is allocated.
def leaf.faces(n: Nat, +i: U32, +root: Tree, +x: U32, +y: U32, +z: U32, +size: U32, +m: U32, fs: List<&2,Face>) -> List<&2,Face>:
  match n:
    case 0n: fs
    case 1n+k:
      leaf.faces(k,(i + 1 : U32),root,x,y,z,size,m,sides(6n,0,root,(x + i % size : U32),(y + i / size % size : U32),(z + i / (size * size) : U32),m,fs))
def faces(t: Tree, +root: Tree, +x: U32, +y: U32, +z: U32, +size: U32, fs: List<&2,Face>) -> List<&2,Face>:
  match t:
    case Leaf{m}:
      match m:
        case 0: fs
        case +other: leaf.faces(U32.to_nat((size * size * size : U32)),0,root,x,y,z,size,other,fs)
    case Branch{a,b,c,d,e,f,g,h}:
      +s = (size / 2 : U32)
      fs = faces(a,root,x,y,z,s,fs)
      fs = faces(b,root,(x + s : U32),y,z,s,fs)
      fs = faces(c,root,x,(y + s : U32),z,s,fs)
      fs = faces(d,root,(x + s : U32),(y + s : U32),z,s,fs)
      fs = faces(e,root,x,y,(z + s : U32),s,fs)
      fs = faces(f,root,(x + s : U32),y,(z + s : U32),s,fs)
      fs = faces(g,root,x,(y + s : U32),(z + s : U32),s,fs)
      faces(h,root,(x + s : U32),(y + s : U32),(z + s : U32),s,fs)
def surface(+t: Tree) -> List<&2,Face>:
  faces(t,t,0,0,0,32,Nil{})
def color.shaded(m: U32, +shade: F32) -> R.Vec:
  match m:
    case 1: R.Vec.scale(R.Vec{0.30,0.61,0.24},shade)
    case 2: R.Vec.scale(R.Vec{0.43,0.30,0.19},shade)
    case _: R.Vec.scale(R.Vec{0.62,0.66,0.65},shade)
def color(m: U32, +side: U32) -> R.Vec:
  +shade = R.pick(U32.is_eq(side,3),1.0,R.pick((side < 2 : U32),0.72,0.85))
  color.shaded(m,shade)
def camera.eye(cam: R.Cam) -> R.Vec:
  R.Cam{eye,_,_,_,_,_,_,_,_,_} = cam
  eye
def draw.visible(on: Bool, p: R.Vec, n: R.Vec, +u: R.Vec, +v: R.Vec, +cam: R.Cam, color: R.Vec, cells: R.Cells) -> R.Cells:
  match on:
    case False{}: cells
    case True{}:
      +c = R.Vec.add(p,R.Vec.scale(n,0.1))
      V.quad(V.view(cam,R.Vec.sub(R.Vec.sub(c,u),v)),V.view(cam,R.Vec.sub(R.Vec.add(c,u),v)),V.view(cam,R.Vec.add(R.Vec.add(c,u),v)),V.view(cam,R.Vec.add(R.Vec.sub(c,u),v)),color,cells)
def draw.face(f: Face, +cam: R.Cam, cells: R.Cells) -> R.Cells:
  Face{x,y,z,+side,m} = f
  +p = {R.Vec{(U32.to_f32(x) * 0.2 - 3.1 : F32),(U32.to_f32(y) * 0.2 + 0.1 : F32),(U32.to_f32(z) * 0.2 - 3.1 : F32)} : R.Vec}
  +n = V.normal(side)
  +u = R.Vec.scale(V.tangent(side),2.0)
  +v = R.Vec.cross(n,u)
  draw.visible((R.Vec.dot(n,R.Vec.sub(camera.eye(cam),p)) > 0.1 : F32),p,n,u,v,cam,color(m,side),cells)
def draw(fs: List<&2,Face>, +cam: R.Cam, cells: R.Cells) -> R.Cells:
  match fs:
    case Nil{}: cells
    case f <> rest: draw(rest,cam,draw.face(f,cam,cells))
