import Base
import ../../atelier.bend as A
import ../../voxel.bend as V
import ../../render.bend as R
import ../../lighting.bend as L
import ../../material.bend as M

type FaceData is Data:
  FaceData{anchor: V.Cell, direction: V.Direction, material: U32}

type Receiver is Data:
  Receiver{name: String, pose: U32, face: V.Face, cell: V.Cell, point: R.Vec3, u: F32, v: F32}

def nums(xs: List<U32>) -> String:
  match xs:
    case Nil{}: ""
    case x <> Nil{}: U32.show(x)
    case x <> rest: U32.show(x) ++ "," ++ nums(rest)

def vec(p: R.Vec3) -> String:
  R.Vec3{x,y,z} = p
  "[" ++ nums([F32.bits(x),F32.bits(y),F32.bits(z)]) ++ "]"

def cell(c: V.Cell) -> String:
  V.Cell{x,y,z} = c
  "[" ++ nums([x,y,z]) ++ "]"

def dir(d: V.Direction) -> U32:
  match d:
    case V.NegX{}: 0
    case V.PosX{}: 1
    case V.NegY{}: 2
    case V.PosY{}: 3
    case V.NegZ{}: 4
    case V.PosZ{}: 5

def face_parts(f: V.Face) -> FaceData:
  match f:
    case V.Face{c,d,m}: FaceData{c,d,m}
    case V.Rectangle{c,d,m,w,h}: FaceData{c,d,m}

def face_json(+f: V.Face, +parts: FaceData) -> String:
  FaceData{c,d,m} = parts
  "{\"anchor\":" ++ cell(c) ++ ",\"direction\":" ++ U32.show(dir(d)) ++ ",\"material\":" ++ U32.show(m) ++ ",\"size\":[" ++ nums([V.Face.width(f),V.Face.height(f)]) ++ "]}"

def boxes(bs: List<&2,V.Cuboid>) -> String:
  match bs:
    case Nil{}: ""
    case V.Cuboid{lo,hi,m} <> Nil{}:
      "[" ++ cell(lo) ++ "," ++ cell(hi) ++ "," ++ U32.show(m) ++ "]"
    case V.Cuboid{lo,hi,m} <> rest:
      "[" ++ cell(lo) ++ "," ++ cell(hi) ++ "," ++ U32.show(m) ++ "]," ++ boxes(rest)

def body_json(name: String, b: V.Body) -> V.Body & String:
  match b:
    case V.Cuboids{+bs}: (V.Cuboids{bs},"{\"kind\":\"body\",\"state\":\"" ++ name ++ "\",\"boxes\":[" ++ boxes(bs) ++ "]}")
    case V.Body{s,a}: (V.Body{s,a},"{}")

def shadow(+s: V.Surface, +depth: Nat) -> R.ShadowMap:
  V.Surface{+fs} = s
  +basis = R.Shadow.basis(R.Shadow.extent(fs,1))
  R.ShadowMap{basis,R.Shadow.configured(depth,R.Shadow.tiles(R.Tiles.build(4n,R.Shadow.faces(fs,basis),0,0,512),basis,depth)),L.Ramp.constant(0),L.Ramp.constant(0)}

def basis_json(b: R.Basis) -> String:
  R.Basis{eye,right,up,forward,scale,near} = b
  "{\"eye\":" ++ vec(eye) ++ ",\"right\":" ++ vec(right) ++ ",\"up\":" ++ vec(up) ++ ",\"forward\":" ++ vec(forward) ++ ",\"scale\":" ++ U32.show(F32.bits(scale)) ++ ",\"near\":" ++ U32.show(F32.bits(near)) ++ "}"

def cache_depth(+w: U32, h: U32) -> Nat:
  U32.to_nat(U32.min(8,U32.max(4,(U32.from_nat(U32.log2(U32.max(w,h))) + 1 : U32))))

def cache_axis(depth: Nat, +u: F32, index: U32) -> U32:
  match depth:
    case 0n: index
    case 1n+rest:
      +right = (u >= 0.5 : F32)
      cache_axis(rest,Bool.pick(F32,right,(u * 2.0 - 1.0 : F32),(u * 2.0 : F32)),(index * 2 + Bool.to_u32(right) : U32))

def cache_leaf(+map: R.ShadowMap, +f: V.Face, u: F32, v: F32, +parts: FaceData) -> L.ColorField:
  FaceData{c,+d,m} = parts
  +w = U32.to_f32(V.Face.width(f))
  +h = U32.to_f32(V.Face.height(f))
  +depth = cache_depth(V.Face.width(f),V.Face.height(f))
  +n = U32.pow(2,depth)
  R.Lighting.face_field(0n,map,c,d,w,h,U32.to_f32(n),cache_axis(depth,u,0),cache_axis(depth,v,0),1)

def cache_point(+f: V.Face, u: F32, v: F32, +parts: FaceData, coords: R.Vec3) -> R.Vec3:
  FaceData{c,+d,m} = parts
  R.Vec3{plane,cu,cv} = coords
  +depth = cache_depth(V.Face.width(f),V.Face.height(f))
  +n = U32.to_f32(U32.pow(2,depth))
  R.Face.point(d,plane,(cu + (U32.to_f32(cache_axis(depth,u,0)) + 0.5) * U32.to_f32(V.Face.width(f)) / n : F32),
    (cv + (U32.to_f32(cache_axis(depth,v,0)) + 0.5) * U32.to_f32(V.Face.height(f)) / n : F32))

def local_normal(b: R.Basis, +n: R.Vec3) -> R.Vec3:
  R.Basis{eye,right,up,forward,scale,near} = b
  R.Vec3{R.Vec3.dot(n,right),R.Vec3.dot(n,up),R.Vec3.dot(n,forward)}

def stored_inside(inside: Bool, map: R.ShadowDepth, x: F32, y: F32) -> String:
  match inside:
    case False{}: "null"
    case True{}: U32.show(F32.bits(R.Shadow.at(map,F32.to_u32(x),F32.to_u32(y))))

def stored(map: R.ShadowDepth, +x: F32, +y: F32, +n: F32) -> String:
  stored_inside(((x >= 0.0) && (y >= 0.0) && (x < n) && (y < n) : F32),map,x,y)

def tap(+map: R.ShadowDepth, +x: F32, +y: F32, +u: F32, +v: F32, +z: F32, +sx: F32, +sy: F32) -> String:
  +receiver = (z + sx * (x + 0.5 - u) + sy * (y + 0.5 - v) - 0.005 : F32)
  "[" ++ nums([F32.bits(x),F32.bits(y)]) ++ "," ++ stored(map,x,y,U32.to_f32(R.Shadow.resolution(map))) ++ "," ++ nums([F32.bits(receiver),R.Shadow.receiver_sample(map,x,y,u,v,z,sx,sy)]) ++ "]"

def taps(+map: R.ShadowDepth, +x: F32, +y: F32, +u: F32, +v: F32, +z: F32, +sx: F32, +sy: F32) -> String:
  "[" ++ tap(map,(x - 1.0 : F32),(y - 1.0 : F32),u,v,z,sx,sy) ++ "," ++ tap(map,x,(y - 1.0 : F32),u,v,z,sx,sy) ++ "," ++ tap(map,(x + 1.0 : F32),(y - 1.0 : F32),u,v,z,sx,sy) ++ "," ++
  tap(map,(x - 1.0 : F32),y,u,v,z,sx,sy) ++ "," ++ tap(map,x,y,u,v,z,sx,sy) ++ "," ++ tap(map,(x + 1.0 : F32),y,u,v,z,sx,sy) ++ "," ++
  tap(map,(x - 1.0 : F32),(y + 1.0 : F32),u,v,z,sx,sy) ++ "," ++ tap(map,x,(y + 1.0 : F32),u,v,z,sx,sy) ++ "," ++ tap(map,(x + 1.0 : F32),(y + 1.0 : F32),u,v,z,sx,sy) ++ "]"

def direct_json(+map: R.ShadowMap, +p: R.Vec3, +d: V.Direction, +local: R.Vec3, +normal: R.Vec3) -> String:
  R.ShadowMap{basis,+depths,ground,grid} = map
  R.Basis{eye,right,up,forward,+scale,near} = basis
  R.Vec3{px,py,+z} = local
  R.Vec3{nx,ny,+nz} = normal
  +width = U32.to_f32(R.Shadow.resolution(depths))
  +u = (width * 0.5 + px * scale * width / 512.0 : F32)
  +v = (width * 0.5 - py * scale * width / 512.0 : F32)
  +texel = (512.0 / (scale * width) : F32)
  +sx = (0.0 - nx / nz * texel : F32)
  +sy = (ny / nz * texel : F32)
  "{\"local\":" ++ vec(local) ++ ",\"local_normal\":" ++ vec(normal) ++ ",\"uv_slope\":[" ++ nums([F32.bits(u),F32.bits(v),F32.bits(sx),F32.bits(sy)]) ++ "],\"visible\":" ++ U32.show(R.Shadow.visibility(map,p,d)) ++ ",\"taps\":" ++ taps(depths,F32.floor(u),F32.floor(v),u,v,z,sx,sy) ++ "}"

def colors(m: U32, +d: V.Direction, +cached: U32, +direct: U32) -> String:
  +ramp = L.Palette.surface(L.Palette.build(),m,d)
  "[" ++ nums([L.Ramp.color(ramp,cached),L.Ramp.color(ramp,direct)]) ++ "]"

def emit_receiver(+state: String, +map: R.ShadowMap, r: Receiver, +parts: FaceData) -> IO(Unit):
  R.ShadowMap{+basis,depths,ground,grid} = map
  Receiver{name,pose,+f,own,+p,+u,+v} = r
  FaceData{+c,+d,+m} = parts
  +sunny = (L.Sun.cosine(d) > 0.0 : F32)
  +cached = Bool.pick(U32,sunny,L.ColorField.sample(cache_leaf(map,f,u,v,parts),u,v),9)
  +cp = cache_point(f,u,v,parts,R.Face.coordinates(d,c))
  IO.print("{\"kind\":\"receiver\",\"state\":\"" ++ state ++ "\",\"name\":\"" ++ name ++ "\",\"pose\":" ++ U32.show(pose) ++ ",\"resolution\":" ++ U32.show(R.Shadow.resolution(depths)) ++ ",\"face\":" ++ face_json(f,parts) ++ ",\"cell\":" ++ cell(own) ++ ",\"point\":" ++ vec(p) ++ ",\"normal\":" ++ vec(R.Face.normal(d)) ++ ",\"face_uv\":[" ++ nums([F32.bits(u),F32.bits(v)]) ++ "],\"cache_point\":" ++ vec(cp) ++ ",\"cache_resolution\":" ++ U32.show(U32.pow(2,cache_depth(V.Face.width(f),V.Face.height(f)))) ++ ",\"cached\":" ++ U32.show(cached) ++ ",\"direct\":" ++ direct_json(map,p,d,R.Basis.local(basis,p),local_normal(basis,R.Face.normal(d))) ++ ",\"cache_direct\":" ++ direct_json(map,cp,d,R.Basis.local(basis,cp),local_normal(basis,R.Face.normal(d))) ++ ",\"rgb_packed\":" ++ colors(m,d,cached,R.Shadow.visibility(map,p,d)) ++ "}")

def emit(+state: String, +map: R.ShadowMap, +r: Receiver) -> IO(Unit):
  Receiver{name,pose,+f,c,p,u,v} = r
  emit_receiver(state,map,r,face_parts(f))

def nth(fs: List<&2,V.Face>, n: U32) -> V.Face:
  match fs n:
    case Nil{} _: V.Face{V.Cell{0,0,0},V.PosZ{},0}
    case f <> rest 0: f
    case f <> rest +n: nth(rest,(n - 1 : U32))

def camera(pose: U32) -> R.Camera:
  match pose:
    case 0: R.Camera.atelier()
    case 1: R.Camera.look(R.Camera.atelier(),80.0,0.0)
    case 2: R.Camera.look(R.Camera.atelier(),(0.0 - 80.0 : F32),25.0)
    case _: R.Camera{R.Vec3{310.0,(0.0 - 50.0 : F32),180.0},1.90401163,(0.0 - 0.50 : F32)}

def pixel(i: U32) -> U32:
  match i:
    case 0: 128
    case 1: 192
    case 2: 226
    case 3: 256
    case 4: 320
    case _: 384

def hit_row(+state: String, +map: R.ShadowMap, +fs: List<&2,V.Face>, +b: R.Basis, +ray: R.Vec3, +pose: U32, x: U32, y: U32, hit: R.PendingHit) -> IO(Unit):
  R.Basis{eye,right,up,forward,focal,near} = b
  match hit:
    case R.Existing{old}: IO.pure(Unit,Unit{})
    case R.Selected{+t,+id,c,d,ramp,field,+u,+v,edge}:
      emit(state,map,Receiver{"pixel_" ++ U32.show(x) ++ "_" ++ U32.show(y),pose,nth(fs,id),c,R.Vec3.add(eye,R.Vec3.scale(ray,t)),u,v})

def pose_pixels(fuel: Nat, +state: String, +map: R.ShadowMap, +fs: List<&2,V.Face>, +projected: List<&2,R.Projected>, +b: R.Basis, +pose: U32, +i: U32) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+rest:
      +x = pixel((i % 6 : U32))
      +y = Bool.pick(U32,U32.is_eq((i / 6 : U32),2),224,pixel((i / 6 : U32)))
      +ray = R.Pixel.ray(b,x,y)
      do IO<Unit>:
        hit_row(state,map,fs,b,ray,pose,x,y,R.PendingHit.scan(projected,ray,0.1,R.Existing{R.Hit.background(x,y)}))
        pose_pixels(rest,state,map,fs,projected,b,pose,(i + 1 : U32))

def poses(fuel: Nat, +state: String, +map: R.ShadowMap, +fs: List<&2,V.Face>, +i: U32) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+rest:
      +b = R.Camera.basis(camera(i))
      do IO<Unit>:
        IO.print("{\"kind\":\"pose\",\"index\":" ++ U32.show(i) ++ ",\"basis\":" ++ basis_json(b) ++ "}")
        pose_pixels(36n,state,map,fs,R.Projected.list(fs,b,L.Palette.build(),0),b,i,0)
        poses(rest,state,map,fs,(i + 1 : U32))

def face_sample(state: String, map: R.ShadowMap, +f: V.Face, index: U32, +u: F32, +v: F32, +parts: FaceData, coords: R.Vec3) -> IO(Unit):
  FaceData{+c,+d,m} = parts
  R.Vec3{plane,cu,cv} = coords
  +w = U32.to_f32(V.Face.width(f))
  +h = U32.to_f32(V.Face.height(f))
  emit(state,map,Receiver{"face_" ++ V.Cell.show(c) ++ "_" ++ U32.show(dir(d)) ++ "_" ++ U32.show(index),99,f,R.Face.sample_cell(d,c,(u * w : F32),(v * h : F32),w,h),R.Face.point(d,plane,(cu + u * w : F32),(cv + v * h : F32)),u,v})

def face_samples(+state: String, +map: R.ShadowMap, +f: V.Face, +parts: FaceData) -> IO(Unit):
  FaceData{c,d,m} = parts
  +coords = R.Face.coordinates(d,c)
  do IO<Unit>:
    face_sample(state,map,f,0,0.125,0.125,parts,coords)
    face_sample(state,map,f,1,0.5,0.5,parts,coords)
    face_sample(state,map,f,2,0.875,0.875,parts,coords)

def sample_if(selected: Bool, state: String, map: R.ShadowMap, +f: V.Face) -> IO(Unit):
  match selected:
    case False{}: IO.pure(Unit,Unit{})
    case True{}: face_samples(state,map,f,face_parts(f))

def sampled_faces(fs: List<&2,V.Face>, +state: String, +map: R.ShadowMap, +i: U32) -> IO(Unit):
  match fs:
    case Nil{}: IO.pure(Unit,Unit{})
    case +f <> rest:
      do IO<Unit>:
        sample_if(((i < 48 : U32) || U32.is_eq((i % 127 : U32),0)),state,map,f)
        sampled_faces(rest,state,map,(i + 1 : U32))

def sunny(parts: FaceData) -> Bool:
  FaceData{c,d,m} = parts
  (L.Sun.cosine(d) > 0.0 : F32)

def small_face(fs: List<&2,V.Face>) -> V.Face:
  match fs:
    case Nil{}: V.Face{V.Cell{0,0,0},V.NegX{},0}
    case +f <> rest:
      Bool.pick(V.Face,(((V.Face.width(f) <= 4) && (V.Face.height(f) <= 4) : U32) && sunny(face_parts(f))),f,small_face(rest))

def map_width(map: R.ShadowMap) -> String:
  R.ShadowMap{basis,depths,ground,grid} = map
  U32.show(R.Shadow.resolution(depths))

def full_cache_control(+state: String, +map: R.ShadowMap, +f: V.Face, +parts: FaceData) -> IO(Unit):
  FaceData{c,+d,m} = parts
  +field = R.Lighting.face_sunny(True{},map,c,d,U32.to_f32(V.Face.width(f)),U32.to_f32(V.Face.height(f)))
  IO.print("{\"kind\":\"full_cache_control\",\"state\":\"" ++ state ++ "\",\"face\":" ++ face_json(f,parts) ++ ",\"resolution\":" ++ map_width(map) ++ ",\"full\":[" ++ nums([L.ColorField.sample(field,0.125,0.125),L.ColorField.sample(field,0.5,0.5),L.ColorField.sample(field,0.875,0.875)]) ++ "],\"leaf\":[" ++ nums([L.ColorField.sample(cache_leaf(map,f,0.125,0.125,parts),0.125,0.125),L.ColorField.sample(cache_leaf(map,f,0.5,0.5,parts),0.5,0.5),L.ColorField.sample(cache_leaf(map,f,0.875,0.875,parts),0.875,0.875)]) ++ "]}")

def full_cache(+fs: List<&2,V.Face>, state: String, map: R.ShadowMap) -> IO(Unit):
  +f = small_face(fs)
  full_cache_control(state,map,f,face_parts(f))

def lighting_run(+state: String, +s: V.Surface, +map: R.ShadowMap) -> IO(Unit):
  V.Surface{+fs} = s
  R.ShadowMap{basis,depths,ground,grid} = map
  do IO<Unit>:
    IO.print("{\"kind\":\"shadow\",\"state\":\"" ++ state ++ "\",\"resolution\":" ++ map_width(map) ++ ",\"basis\":" ++ basis_json(basis) ++ "}")
    full_cache(fs,state,map)
    full_cache_control(state,map,nth(fs,11),face_parts(nth(fs,11)))
    sampled_faces(fs,state,map,0)
    poses(4n,state,map,fs,0)

def lighting(+state: String, +s: V.Surface) -> IO(Unit):
  do IO<Unit>:
    lighting_run(state,s,shadow(s,7n))
    lighting_run(state,s,R.ShadowMap.build(s))

def emit_body(pair: V.Body & String) -> IO(V.Body):
  (b,json) = pair
  do IO<V.Body>:
    IO.print(json)
    return b

def carved(+sphere: V.MetricSphere, pair: V.Body & V.Surface) -> IO(Unit):
  (b,+s) = pair
  do IO<Unit>:
    original : V.Body <- emit_body(body_json("carved",b))
    repeated : V.Body <- emit_body(body_json("repeat",V.Body.cut(original,sphere)))
    reset : V.Body <- emit_body(body_json("reset",A.body()))
    lighting("carved",s)

def targeted(+s: V.Surface, b: V.Body, target: Maybe<&2,V.MetricSphere>) -> IO(Unit):
  match target:
    case None{}: IO.die(Unit,1,"Original Atelier ray226,224 missed")
    case Some{+sphere}:
      V.MetricSphere{V.PointCm{x,y,z},radius} = sphere
      do IO<Unit>:
        IO.print("{\"kind\":\"carve\",\"center_cm\":[" ++ nums([F32.bits(x),F32.bits(y),F32.bits(z)]) ++ "],\"radius_cm\":" ++ U32.show(F32.bits(radius)) ++ "}")
        intact : V.Body <- emit_body(body_json("intact",b))
        lighting("intact",s)
        carved(sphere,V.Surface.build(V.Body.cut(intact,sphere)))

def start(pair: V.Body & V.Surface) -> IO(Unit):
  (b,+s) = pair
  V.Surface{fs} = s
  +basis = R.Camera.basis(R.Camera.atelier())
  +ray = R.Pixel.ray(basis,226,224)
  targeted(s,b,R.Hit.target(R.Pixel.hit(R.Projected.list(fs,basis,L.Palette.build(),0),ray,0.1,R.Hit.background(226,224)),basis,ray))

def main() -> IO(Unit):
  start(V.Surface.build(A.body()))
