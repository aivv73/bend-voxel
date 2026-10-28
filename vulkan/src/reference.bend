import Base
import ../../voxel.bend as X
import ../../render.bend as R
import ../../material.bend as P
import ../../lighting.bend as L
import ./mesh.bend as M
import ./exterior.bend as Exterior
import ./geometry.bend as G

type Sample is Data:
  Sample{depth: F32, material: U32, direction: U32, color: U32}
type Report is Data:
  Report{pixels: U32, excluded: U32, mismatches: U32, invalid_edges: U32, upstream: U32, covered: U32, materials: U32, directions: U32}

def project(fs: List<&2,X.Face>, +basis: R.Basis, +palette: L.Palette) -> List<&2,R.Projected>:
  match fs:
    case Nil{}: Nil{}
    case Con{X.Face{+cell,+d,+material},rest}:
      R.Projected.add(R.Projected.of(X.Face{cell,d,material},basis,palette,material),project(rest,basis,palette))
    case Con{X.Rectangle{+cell,+d,+material,w,h},rest}:
      R.Projected.add(R.Projected.of(X.Rectangle{cell,d,material,w,h},basis,palette,material),project(rest,basis,palette))


def empty() -> Sample:
  Sample{1.0,0,255,0}

def select(valid: Bool, +t: F32, +material: U32, +d: X.Direction, +near: F32, palette: P.Palette, old: Sample) -> Sample:
  Sample{+depth,om,od,oc} = old
  Bool.pick(Sample,valid && ((1.0 - near / t) < depth : F32),Sample{(1.0 - near / t : F32),material,Exterior.direction(d),P.Palette.surface(palette,material,R.Face.light(d))},Sample{depth,om,od,oc})


def intersection(+denom: F32, du: F32, dv: F32, plane: F32, u0: F32, v0: F32, width: F32, height: F32, material: U32, +d: X.Direction, +near: F32, palette: P.Palette, +epsilon: F32, old: Sample) -> Sample:
  +t = (plane / denom : F32)
  +u = (u0 + t * du : F32)
  +v = (v0 + t * dv : F32)
  select(F32.is_ne(denom,0.0) && ((t >= near) && (u >= F32.neg(epsilon)) && (u <= width + epsilon) && (v >= F32.neg(epsilon)) && (v <= height + epsilon) : F32),t,material,d,near,palette,old)

def face_axes(axis: R.Vec3, plane: F32, u: F32, v: F32, width: F32, height: F32, mat: U32, d: X.Direction, near: F32, palette: P.Palette, +epsilon: F32, old: Sample) -> Sample:
  R.Vec3{a,b,c} = axis
  intersection(a,b,c,plane,u,v,width,height,mat,d,near,palette,epsilon,old)

def face_hit(face: R.Projected, ray: R.Vec3, near: F32, palette: P.Palette, +epsilon: F32, old: Sample) -> Sample:
  R.Projected{cell,+d,plane,u,v,color,visibility,mat,bounds,w,h,outline} = face
  face_axes(R.Face.axes(d,ray),plane,u,v,w,h,mat,d,near,palette,epsilon,old)

def hit(fs: List<&2,R.Projected>, +ray: R.Vec3, +near: F32, +palette: P.Palette, +epsilon: F32, old: Sample) -> Sample:
  match fs:
    case Nil{}: old
    case Con{face,rest}: hit(rest,ray,near,palette,epsilon,face_hit(face,ray,near,palette,epsilon,old))

def segment_distance(segment: R.Segment, +x: F32, +y: F32) -> Bool:
  R.Segment{+ax,+ay,ia,bx,by,ib,bounds} = segment
  +dx = (bx - ax : F32)
  +dy = (by - ay : F32)
  +length = (dx * dx + dy * dy : F32)
  +t = F32.clamp((((x - ax) * dx + (y - ay) * dy) / F32.max(length,0.00000001) : F32),0.0,1.0)
  +ex = (x - ax - t * dx : F32)
  +ey = (y - ay - t * dy : F32)
  (ex * ex + ey * ey <= 1.0 : F32)

def band(ss: List<&2,R.Segment>, +x: F32, +y: F32) -> Bool:
  match ss:
    case Nil{}: False{}
    case Con{s,rest}: segment_distance(s,x,y) || band(rest,x,y)

def polygon_edges(points: List<&2,R.Vec3>, +first: R.Vec3, +previous: R.Vec3, +basis: R.Basis, edges: List<&2,R.Segment>) -> List<&2,R.Segment>:
  match points:
    case Nil{}: R.Segment.add(R.Segment.of(previous,first,basis),edges)
    case Con{+p,rest}: polygon_edges(rest,first,p,basis,R.Segment.add(R.Segment.of(previous,p,basis),edges))

def clipped_edges(points: List<&2,R.Vec3>, basis: R.Basis, edges: List<&2,R.Segment>) -> List<&2,R.Segment>:
  match points:
    case Nil{}: edges
    case Con{+p,rest}: polygon_edges(rest,p,p,basis,edges)

def local_edges(+a: R.Vec3, +b: R.Vec3, +c: R.Vec3, +d: R.Vec3, +basis: R.Basis, +near: F32, edges: List<&2,R.Segment>) -> List<&2,R.Segment>:
  clipped_edges(R.Clip.edge(a,b,near,R.Clip.edge(b,c,near,R.Clip.edge(c,d,near,R.Clip.edge(d,a,near,Nil{})))),basis,edges)

def face_edges(coordinates: R.Vec3, +d: X.Direction, +basis: R.Basis, near: F32, +width: F32, +height: F32, edges: List<&2,R.Segment>) -> List<&2,R.Segment>:
  R.Vec3{+p,+u,+v} = coordinates
  local_edges(R.Basis.local(basis,R.Face.point(d,p,u,v)),R.Basis.local(basis,R.Face.point(d,p,(u + width : F32),v)),R.Basis.local(basis,R.Face.point(d,p,(u + width : F32),(v + height : F32))),R.Basis.local(basis,R.Face.point(d,p,u,(v + height : F32))),basis,near,edges)

def edges(fs: List<&2,X.Face>, +basis: R.Basis, +near: F32, ss: List<&2,R.Segment>) -> List<&2,R.Segment>:
  match fs:
    case Nil{}: ss
    case Con{X.Face{cell,+d,m},rest}: edges(rest,basis,near,face_edges(R.Face.coordinates(d,cell),d,basis,near,1.0,1.0,ss))
    case Con{X.Rectangle{cell,+d,m,w,h},rest}: edges(rest,basis,near,face_edges(R.Face.coordinates(d,cell),d,basis,near,U32.to_f32(w),U32.to_f32(h),ss))

def byte_close(+a: U32, +b: U32) -> Bool:
  ((a <= b + 1) && (b <= a + 1) : U32)

def upstream_equal(sample: Sample, hit: R.Hit, +near: F32) -> Bool:
  Sample{depth,mat,dir,color} = sample
  R.Hit{t,c,id,cell,d} = hit
  match cell:
    case None{}: U32.is_eq(mat,0)
    case Some{cell}: U32.is_eq(mat,id) && U32.is_eq(dir,Exterior.direction(d)) && (F32.abs((depth - (1.0 - near / t) : F32)) <= 0.00002 : F32)

def expected(sample: Sample, +mode: U32, +r: U32, +g: U32, +b: U32, +a: U32, +depth: F32) -> Bool:
  Sample{+z,+mat,+dir,+color} = sample
  +red = Bool.pick(U32,U32.is_eq(mode,0),(color >> 16n : U32),Bool.pick(U32,U32.is_eq(mode,1),(mat .&. 255 : U32),dir))
  +green = Bool.pick(U32,U32.is_eq(mode,0),(color >> 8n .&. 255 : U32),Bool.pick(U32,U32.is_eq(mode,1),(mat >> 8n .&. 255 : U32),0))
  +blue = Bool.pick(U32,U32.is_eq(mode,0),(color .&. 255 : U32),Bool.pick(U32,U32.is_eq(mode,1),(mat >> 16n .&. 255 : U32),0))
  +alpha = Bool.pick(U32,U32.is_eq(mode,1),(mat >> 24n : U32),255)
  +background = U32.is_eq(mat,0)
  +rgb = Bool.pick(Bool,U32.is_eq(mode,0),byte_close(r,red) && byte_close(g,green) && byte_close(b,blue),U32.is_eq(r,red) && U32.is_eq(g,green) && U32.is_eq(b,blue))
  Bool.pick(Bool,background,U32.is_eq(r,0) && U32.is_eq(g,0) && U32.is_eq(b,0) && U32.is_eq(a,255) && F32.is_eq(depth,1.0),rgb && U32.is_eq(a,alpha) && (F32.abs((depth - z : F32)) <= 0.00002 : F32))


def background(sample: Sample) -> Bool:
  Sample{z,mat,d,c} = sample
  U32.is_eq(mat,0)

def edge_candidate(fs: List<&2,R.Projected>, +ray: R.Vec3, +near: F32, +palette: P.Palette, +mode: U32, +r: U32, +g: U32, +b: U32, +a: U32, +depth: F32) -> Bool:
  match fs:
    case Nil{}: False{}
    case Con{face,rest}:
      expected(face_hit(face,ray,near,palette,0.0001,empty()),mode,r,g,b,a,depth) || edge_candidate(rest,ray,near,palette,mode,r,g,b,a,depth)

def edge_valid(+fs: List<&2,R.Projected>, +ray: R.Vec3, +near: F32, +palette: P.Palette, +mode: U32, +r: U32, +g: U32, +b: U32, +a: U32, +depth: F32, center: Sample) -> Bool:
  Sample{z,mat,d,c} = center
  +miss = U32.is_eq(r,0) && U32.is_eq(g,0) && U32.is_eq(b,0) && U32.is_eq(a,255) && F32.is_eq(depth,1.0)
  Bool.pick(Bool,miss,background(hit(fs,ray,near,palette,F32.neg(0.0001),empty())),((depth <= z + 0.00002 : F32) || U32.is_eq(mat,0)) && edge_candidate(fs,ray,near,palette,mode,r,g,b,a,depth))

def material_bit(mat: U32) -> U32:
  match mat:
    case 1: 1
    case 2: 2
    case 3: 4
    case 4: 8
    case 5: 16
    case 2147483648: 32
    case 2309737967: 64
    case 4294967295: 128
    case _: 0

def direction_bit(mat: U32, dir: U32) -> U32:
  match mat:
    case 0: 0
    case _: U32.pow(2,U32.to_nat(dir))

def add_report(report: Report, excluded: Bool, good: Bool, valid_edge: Bool, old_ok: Bool, covered: Bool, sample: Sample) -> Report:
  Report{pixels,edges,errors,invalid,upstream,cover,mats,dirs} = report
  Sample{z,+mat,dir,c} = sample
  Report{(pixels + 1 : U32),(edges + Bool.pick(U32,excluded,1,0) : U32),(errors + Bool.pick(U32,good,0,1) : U32),(invalid + Bool.pick(U32,valid_edge,0,1) : U32),(upstream + Bool.pick(U32,old_ok,0,1) : U32),(cover + Bool.pick(U32,covered,1,0) : U32),(mats .|. material_bit(mat) : U32),(dirs .|. direction_bit(mat,dir) : U32)}

def compare_pixel(+fs: List<&2,R.Projected>, +ss: List<&2,R.Segment>, +basis: R.Basis, +palette: P.Palette, +mode: U32, +x: U32, +y: U32, +r: U32, +g: U32, +b: U32, +a: U32, +depth: F32, report: Report) -> Report:
  R.Basis{eye,right,up,forward,focal,+near} = basis
  +ray = R.Pixel.ray(basis,x,y)
  +sample = hit(fs,ray,near,palette,0.0,empty())
  +excluded = band(ss,(U32.to_f32(x) + 0.5 : F32),(U32.to_f32(y) + 0.5 : F32))
  +good = expected(sample,mode,r,g,b,a,depth)
  +valid = edge_valid(fs,ray,near,palette,mode,r,g,b,a,depth,sample)
  +old = upstream_equal(sample,R.Pixel.hit(fs,ray,near,R.Hit.background(x,y)),near)
  add_report(report,excluded,excluded || good,Bool.not(excluded) || valid,excluded || old,Bool.not(background(sample)),sample)

def face_rows(fs: List<&2,R.Projected>, +y: U32) -> List<&2,R.Projected>:
  match fs:
    case Nil{}: Nil{}
    case Con{+face,rest}:
      R.Projected{cell,d,p,u,v,c,vis,id,R.Bounds{lx,ly,hx,hy},w,h,o} = face
      R.Projected.add(Bool.pick(Maybe<&2,R.Projected>,((ly <= y) && (hy > y) : U32),Some{face},None{}),face_rows(rest,y))

def segment_rows(ss: List<&2,R.Segment>, +y: U32) -> List<&2,R.Segment>:
  match ss:
    case Nil{}: Nil{}
    case Con{+seg,rest}:
      R.Segment{ax,ay,ia,bx,by,ib,R.Bounds{lx,ly,hx,hy}} = seg
      R.Segment.add(Bool.pick(Maybe<&2,R.Segment>,((ly <= y) && (hy > y) : U32),Some{seg},None{}),segment_rows(rest,y))

def row_faces(refresh: Bool, fs: List<&2,R.Projected>, old: List<&2,R.Projected>, y: U32) -> List<&2,R.Projected>:
  match refresh:
    case True{}: face_rows(fs,y)
    case False{}: old

def row_segments(refresh: Bool, ss: List<&2,R.Segment>, old: List<&2,R.Segment>, y: U32) -> List<&2,R.Segment>:
  match refresh:
    case True{}: segment_rows(ss,y)
    case False{}: old

def pixels(colors: List<U32>, depths: List<U32>, +index: U32, +allfs: List<&2,R.Projected>, +allss: List<&2,R.Segment>, +fs: List<&2,R.Projected>, +ss: List<&2,R.Segment>, +basis: R.Basis, +palette: P.Palette, +mode: U32, report: Report) -> Report:
  match colors depths:
    case Nil{} Nil{}: report
    case r <> g <> b <> a <> rest z0 <> z1 <> z2 <> z3 <> zs:
      +depth = G.float((z0 .|. (z1 << 8n) .|. (z2 << 16n) .|. (z3 << 24n) : U32))
      +x = (index % 512 : U32)
      +y = (index / 512 : U32)
      +row_start = U32.is_eq(x,0)
      +rowfs = row_faces(row_start,allfs,fs,y)
      +rowss = row_segments(row_start,allss,ss,y)
      pixels(rest,zs,(index + 1 : U32),allfs,allss,rowfs,rowss,basis,palette,mode,compare_pixel(R.Projected.filter(rowfs,x,y,1,Nil{}),R.Segment.filter(rowss,x,y,1,Nil{}),basis,palette,mode,x,y,r,g,b,a,depth,report))
    case _ _: Report{0,0,1,1,1,0,0,0}

def compare(pair: List<U32> & List<U32>, +faces: List<&2,X.Face>, +basis: R.Basis, mode: U32) -> Report:
  (colors,depths) = pair
  +fs = project(faces,basis,L.Palette.build())
  +ss = edges(faces,basis,0.1,Nil{})
  pixels(colors,depths,0,fs,ss,Nil{},Nil{},basis,P.Palette.build(),mode,Report{0,0,0,0,0,0,0,0})
