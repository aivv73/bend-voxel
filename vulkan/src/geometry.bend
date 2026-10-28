import Base
import ./mesh.bend as M
import ./exterior.bend as Exterior
import ../../voxel.bend as X
import ../../render.bend as R
import ../../material.bend as P

def float(word: U32) -> F32:
  U32{bits} = word
  F32{bits}

def same_cell(a: X.Cell, b: X.Cell) -> Bool:
  X.Cell{x,y,z} = a
  X.Cell{u,v,w} = b
  U32.is_eq(x,u) && U32.is_eq(y,v) && U32.is_eq(z,w)

def rectangle_patch(cell: X.Cell, +d: U32, mat: U32, p: Exterior.Patch) -> Bool:
  X.Cell{+x,+y,+z} = cell
  Exterior.Patch{normal,dir,m,Exterior.Rect2{u0,u1,v0,v1}} = p
  +n = Bool.pick(U32,(d < 2 : U32),x,Bool.pick(U32,(d < 4 : U32),y,z))
  +u = Bool.pick(U32,(d < 2 : U32),y,x)
  +v = Bool.pick(U32,(d < 4 : U32),z,y)
  U32.is_eq(normal,n) && U32.is_eq(Exterior.direction(dir),d) && U32.is_eq(mat,m) && (u0 <= u : U32) && (u < u1 : U32) && (v0 <= v : U32) && (v < v1 : U32)

def rectangle_contains(cell: X.Cell, d: U32, mat: U32, face: X.Face) -> Bool:
  rectangle_patch(cell,d,mat,Exterior.patch(face))

def occurrences(fs: List<&2,X.Face>, +cell: X.Cell, +d: U32, +mat: U32) -> U32:
  match fs:
    case Nil{}: 0
    case Con{X.Face{c,dir,m},rest}:
      (Bool.pick(U32,same_cell(cell,c) && U32.is_eq(d,Exterior.direction(dir)) && U32.is_eq(mat,m),1,0) + occurrences(rest,cell,d,mat) : U32)
    case Con{rectangle,rest}: (Bool.to_u32(rectangle_contains(cell,d,mat,rectangle)) + occurrences(rest,cell,d,mat) : U32)

def lookup(tree: X.Snapshot, +index: U32, +span: U32) -> U32:
  match tree:
    case X.Leaf{m}: m
    case X.Node{left,right}:
      +half = (span / 2 : U32)
      (lookup(left,(index % half : U32),half) * Bool.pick(U32,(index < half : U32),1,0) + lookup(right,(index % half : U32),half) * Bool.pick(U32,(index >= half : U32),1,0) : U32)

def read(tree: X.Snapshot, +side: U32, cell: X.Cell) -> U32:
  X.Cell{+x,+y,+z} = cell
  (lookup(tree,(x + side * y + side * side * z : U32),(side * side * side : U32)) * Bool.pick(U32,((x < side) && (y < side) && (z < side) : U32),1,0) : U32)

def neighbor(cell: X.Cell, d: U32) -> X.Cell:
  X.Cell{+x,+y,+z} = cell
  match d:
    case 0: X.Cell{(x - 1 : U32),y,z}
    case 1: X.Cell{(x + 1 : U32),y,z}
    case 2: X.Cell{x,(y - 1 : U32),z}
    case 3: X.Cell{x,(y + 1 : U32),z}
    case 4: X.Cell{x,y,(z - 1 : U32)}
    case _: X.Cell{x,y,(z + 1 : U32)}

def enumerate(fuel: Nat, +index: U32, +side: U32, +tree: X.Snapshot, +fs: List<&2,X.Face>, +total: U32, +ok: Bool) -> U32 & Bool:
  match fuel:
    case 0n: (total,ok)
    case 1n+rest:
      +n = (index / 6 : U32)
      +d = (index % 6 : U32)
      +cell = {X.Cell{(n % side : U32),((n / side) % side : U32),(n / (side * side) : U32)} : X.Cell}
      +material = read(tree,side,cell)
      +exposed = U32.is_ne(material,0) && U32.is_eq(read(tree,side,neighbor(cell,d)),0)
      +expected = Bool.pick(U32,exposed,1,0)
      enumerate(rest,(index + 1 : U32),side,tree,fs,(total + expected : U32),ok && U32.is_eq(occurrences(fs,cell,d,material),expected))

def on_axes(+d: X.Direction, axis: R.Vec3, +w: F32, +h: F32) -> Bool:
  R.Vec3{a,+b,+c} = axis
  F32.is_eq(a,Bool.pick(F32,(Exterior.direction(d) % 2 > 0 : U32),1.0,0.0)) && (F32.is_eq(b,0.0) || F32.is_eq(b,w)) && (F32.is_eq(c,0.0) || F32.is_eq(c,h))

def on_delta(+d: X.Direction, delta: R.Vec3, w: F32, h: F32) -> Bool:
  on_axes(d,R.Face.axes(d,delta),w,h)

def on_face(cell: X.Cell, d: X.Direction, point: R.Vec3, w: F32, h: F32) -> Bool:
  X.Cell{x,y,z} = cell
  R.Vec3{px,py,pz} = point
  on_delta(d,R.Vec3{(px - U32.to_f32(x) : F32),(py - U32.to_f32(y) : F32),(pz - U32.to_f32(z) : F32)},w,h)

def sub(a: R.Vec3, b: R.Vec3) -> R.Vec3:
  R.Vec3.add(a,R.Vec3.scale(b,F32.neg(1.0)))

def winding(+a: R.Vec3, +b: R.Vec3, +c: R.Vec3, d: X.Direction, area: F32) -> Bool:
  F32.is_eq(R.Vec3.dot(R.Vec3.cross(sub(b,a),sub(c,a)),R.Face.normal(d)),area)

def quad_ok(+cell: X.Cell, +d: X.Direction, +a: R.Vec3, +b: R.Vec3, +c: R.Vec3, +e: R.Vec3, +w: F32, +h: F32) -> Bool:
  on_face(cell,d,a,w,h) && on_face(cell,d,b,w,h) && on_face(cell,d,c,w,h) && on_face(cell,d,e,w,h) && winding(a,b,c,d,(w * h : F32)) && winding(c,e,a,d,(w * h : F32)) && F32.is_eq(R.Vec3.dot(sub(c,a),sub(c,a)),(w * w + h * h : F32))

def rectangles(fs: List<&2,X.Face>) -> List<&2,X.Face>:
  match fs:
    case Nil{}: Nil{}
    case X.Face{cell,d,m} <> rest: X.Rectangle{cell,d,m,1,1} <> rectangles(rest)
    case r <> rest: r <> rectangles(rest)

def flat_metadata(+cell: X.Cell, +w: U32, +h: U32, ax: U32, ay: U32, az: U32, width: U32, height: U32) -> Bool:
  X.Cell{x,y,z} = cell
  U32.is_eq(ax,F32.bits(U32.to_f32(x))) && U32.is_eq(ay,F32.bits(U32.to_f32(y))) && U32.is_eq(az,F32.bits(U32.to_f32(z))) && U32.is_eq(width,F32.bits(U32.to_f32(w))) && U32.is_eq(height,F32.bits(U32.to_f32(h)))

def packed(fs: List<&2,X.Face>, vs: List<U32>, ix: List<U32>, +i: U32, +palette: P.Palette, +ok: Bool) -> Bool:
  match fs vs ix:
    case Nil{} _ _: ok
    case Con{X.Rectangle{+cell,+d,+mat,+w,+h},rest} ax <> ay <> az <> ac <> am <> aa <> ab <> ad <> aw <> ah <> bx <> by <> bz <> bc <> bm <> ba <> bb <> bd <> bw <> bh <> cx <> cy <> cz <> cc <> cm <> ca <> cb <> cd <> cw <> ch <> ex <> ey <> ez <> ec <> em <> ea <> eb <> ed <> ew <> eh <> tail +ia <> ib <> +ic <> id <> ie <> iff <> it:
      +color = M.rgbd(P.Palette.surface(palette,mat,R.Face.light(d)),Exterior.direction(d))
      +metadata = U32.is_eq(ac,color) && U32.is_eq(bc,color) && U32.is_eq(cc,color) && U32.is_eq(ec,color) && U32.is_eq(am,mat) && U32.is_eq(bm,mat) && U32.is_eq(cm,mat) && U32.is_eq(em,mat)
      +flat = flat_metadata(cell,w,h,aa,ab,ad,aw,ah) && flat_metadata(cell,w,h,ba,bb,bd,bw,bh) && flat_metadata(cell,w,h,ca,cb,cd,cw,ch) && flat_metadata(cell,w,h,ea,eb,ed,ew,eh)
      +indices = U32.is_eq(ia,(i * 4 : U32)) && U32.is_eq(ib,(i * 4 + 1 : U32)) && U32.is_eq(ic,(i * 4 + 2 : U32)) && U32.is_eq(id,ic) && U32.is_eq(ie,(i * 4 + 3 : U32)) && U32.is_eq(iff,ia)
      packed(rest,tail,it,(i + 1 : U32),palette,ok && metadata && flat && indices && quad_ok(cell,d,R.Vec3{float(ax),float(ay),float(az)},R.Vec3{float(bx),float(by),float(bz)},R.Vec3{float(cx),float(cy),float(cz)},R.Vec3{float(ex),float(ey),float(ez)},U32.to_f32(w),U32.to_f32(h)))
    case _ _ _: False{}

def check_counts(+count: U32, left: U32 & Bool, right: U32 & Bool) -> Bool:
  (a,ok) = left
  (b,valid) = right
  ok && valid && U32.is_eq(count,(a + b : U32))

def coverage(+side: U32, +tree: X.Snapshot, +fs: List<&2,X.Face>, count: U32) -> Bool:
  +half = (side * side * side * 3 : U32)
  a b = enumerate(U32.to_nat(half),0,side,tree,fs,0,True{}) enumerate(U32.to_nat(half),half,side,tree,fs,0,True{})
  check_counts(count,a,b)

def units(fs: List<&2,X.Face>) -> U32:
  match fs:
    case Nil{}: 0
    case X.Face{c,d,m} <> rest: (1 + units(rest) : U32)
    case X.Rectangle{c,d,m,w,h} <> rest: (w * h + units(rest) : U32)

def check_arrays(+fs: List<&2,X.Face>, +size: M.PackedSize, bounds: Maybe<&2,M.Extent>, vs: Array<U32> & Array<U32>, ix: Array<U32> & Array<U32>, tree: X.Snapshot, +side: U32) -> M.Mesh & Bool:
  (vertices,vcopy) = vs
  (indices,icopy) = ix
  coverage_ok = coverage(side,tree,fs,units(fs))
  geometry = packed(rectangles(fs),Array.to_list(~U32,vcopy),Array.to_list(~U32,icopy),0,P.Palette.build(),True{})
  (M.Mesh{fs,size,bounds,vertices,indices},coverage_ok && geometry)

def check_mesh(mesh: M.Mesh, tree: X.Snapshot, side: U32) -> M.Mesh & Bool:
  M.Mesh{fs,size,bounds,vs,ix} = mesh
  check_arrays(fs,size,bounds,Array.clone(U32,vs),Array.clone(U32,ix),tree,side)

def checked_dense(+side: U32, pair: Array<U32> & X.Snapshot, mesh: M.Mesh) -> X.Body & (M.Mesh & Bool):
  (cells,tree) = pair
  (X.Body{side,cells},check_mesh(mesh,tree,side))

def box_read(boxes: List<&2,X.Cuboid>, +cell: X.Cell) -> U32:
  match boxes:
    case Nil{}: 0
    case X.Cuboid{X.Cell{x,y,z},X.Cell{hx,hy,hz},+m} <> rest:
      X.Cell{+cx,+cy,+cz} = cell
      Bool.pick(U32,(x <= cx : U32) && (cx < hx : U32) && (y <= cy : U32) && (cy < hy : U32) && (z <= cz : U32) && (cz < hz : U32) && U32.is_ne(m,0),m,box_read(rest,cell))

def counts_join(left: U32 & Bool, right: U32 & Bool) -> U32 & Bool:
  (a,ok) = left
  (b,valid) = right
  ((a + b : U32),ok && valid)

def box_directions(fuel: Nat, +d: U32, +cell: X.Cell, +m: U32, +boxes: List<&2,X.Cuboid>, +fs: List<&2,X.Face>) -> U32 & Bool:
  match fuel:
    case 0n: (0,True{})
    case 1n+k:
      +expected = Bool.to_u32(U32.is_eq(box_read(boxes,neighbor(cell,d)),0))
      counts_join((expected,U32.is_eq(occurrences(fs,cell,d,m),expected)),box_directions(k,(d + 1 : U32),cell,m,boxes,fs))

def box_x(fuel: Nat, +x: U32, +y: U32, +z: U32, +m: U32, +boxes: List<&2,X.Cuboid>, +fs: List<&2,X.Face>) -> U32 & Bool:
  match fuel:
    case 0n: (0,True{})
    case 1n+k: counts_join(box_directions(6n,0,X.Cell{x,y,z},m,boxes,fs),box_x(k,(x + 1 : U32),y,z,m,boxes,fs))

def box_y(fuel: Nat, +y: U32, +z: U32, +x: U32, +width: Nat, +m: U32, +boxes: List<&2,X.Cuboid>, +fs: List<&2,X.Face>) -> U32 & Bool:
  match fuel:
    case 0n: (0,True{})
    case 1n+k: counts_join(box_x(width,x,y,z,m,boxes,fs),box_y(k,(y + 1 : U32),z,x,width,m,boxes,fs))

def box_z(fuel: Nat, +z: U32, +x: U32, +y: U32, +width: Nat, +height: Nat, +m: U32, +boxes: List<&2,X.Cuboid>, +fs: List<&2,X.Face>) -> U32 & Bool:
  match fuel:
    case 0n: (0,True{})
    case 1n+k: counts_join(box_y(height,y,z,x,width,m,boxes,fs),box_z(k,(z + 1 : U32),x,y,width,height,m,boxes,fs))

def box_coverage(xs: List<&2,X.Cuboid>, +boxes: List<&2,X.Cuboid>, +fs: List<&2,X.Face>) -> U32 & Bool:
  match xs:
    case Nil{}: (0,True{})
    case X.Cuboid{lo,hi,0} <> rest: box_coverage(rest,boxes,fs)
    case X.Cuboid{X.Cell{+x,+y,+z},X.Cell{hx,hy,hz},m} <> rest:
      a b = box_z(U32.to_nat((hz - z : U32)),z,x,y,U32.to_nat((hx - x : U32)),U32.to_nat((hy - y : U32)),m,boxes,fs) box_coverage(rest,boxes,fs)
      counts_join(a,b)

def box_checked(+boxes: List<&2,X.Cuboid>, +fs: List<&2,X.Face>, s: M.PackedSize, bounds: Maybe<&2,M.Extent>, vertices: Array<U32> & Array<U32>, indices: Array<U32> & Array<U32>) -> X.Body & (M.Mesh & Bool):
  (vs,vcopy) = vertices
  (ix,icopy) = indices
  geometry = packed(rectangles(fs),Array.to_list(~U32,vcopy),Array.to_list(~U32,icopy),0,P.Palette.build(),True{})
  coverage_ok = check_counts(units(fs),box_coverage(boxes,boxes,fs),(0,True{}))
  (X.Cuboids{boxes},(M.Mesh{fs,s,bounds,vs,ix},geometry && coverage_ok))

def checked(body: X.Body, mesh: M.Mesh) -> X.Body & (M.Mesh & Bool):
  match body mesh:
    case X.Body{side,cells} _: checked_dense(side,X.Snapshot.of(cells),mesh)
    case X.Cuboids{+boxes} M.Mesh{+fs,s,bounds,vs,ix}: box_checked(boxes,fs,s,bounds,Array.clone(U32,vs),Array.clone(U32,ix))

def integer_sub(a: X.Cell, b: X.Cell) -> X.Cell:
  X.Cell{x,y,z} = a
  X.Cell{u,v,w} = b
  X.Cell{(x - u : U32),(y - v : U32),(z - w : U32)}

def integer_cross(a: X.Cell, b: X.Cell) -> X.Cell:
  X.Cell{+x,+y,+z} = a
  X.Cell{+u,+v,+w} = b
  X.Cell{(y * w - z * v : U32),(z * u - x * w : U32),(x * v - y * u : U32)}

def quad_normal(+d: U32) -> X.Cell:
  integer_cross(integer_sub(M.corner(d,1,1,1),M.corner(d,0,1,1)),integer_sub(M.corner(d,2,1,1),M.corner(d,0,1,1)))

def quad_second_normal(+d: U32) -> X.Cell:
  integer_cross(integer_sub(M.corner(d,3,1,1),M.corner(d,2,1,1)),integer_sub(M.corner(d,0,1,1),M.corner(d,2,1,1)))

def indices_bounded(indices: List<U32>, +limit: U32) -> Bool:
  match indices:
    case Nil{}: True{}
    case index <> rest: (index < limit : U32) && indices_bounded(rest,limit)

def fixture_index_bounds(fuel: Nat, +face: U32) -> Bool:
  match fuel:
    case 0n: True{}
    case 1n+rest:
      indices_bounded(Array.to_list(~U32,M.index_quad((face * 4 : U32),0,[0 : U32^3n])),((face + 1) * 4 : U32)) && fixture_index_bounds(rest,(face + 1 : U32))
