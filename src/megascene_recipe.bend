import Base
import ./math.bend as R

type Control is Data:
  Plain{}
  Spread{}
  MaterialDetail{}
  SurfaceDetail{}
  Fill{}
  BodyRich{}
type Box is Data:
  Box{lo: R.Vec, hi: R.Vec, material: U32}
type Owner is Data:
  Owner{role: String, neighborhood: Maybe<&2,U32>, boxes: List<&2,Box>}
type District is Data:
  District{side: U32, seed: U32, control: Control}

def control(s: String) -> Maybe<&2,Control>:
  match s:
    case "base": Some{Plain{}}
    case "spread": Some{Spread{}}
    case "material-detail": Some{MaterialDetail{}}
    case "surface-detail": Some{SurfaceDetail{}}
    case "fill": Some{Fill{}}
    case "body-rich": Some{BodyRich{}}
    case _: None{}
def control.name(c: Control) -> String:
  match c:
    case Plain{}: "base"
    case Spread{}: "spread"
    case MaterialDetail{}: "material-detail"
    case SurfaceDetail{}: "surface-detail"
    case Fill{}: "fill"
    case BodyRich{}: "body-rich"
def district.valid(ok: Bool, q: U32, seed: U32, c: Control) -> Maybe<&2,District>:
  match ok:
    case True{}: Some{District{q,seed,c}}
    case False{}: None{}
def district(+q: U32, +seed: U32, c: Control) -> Maybe<&2,District>:
  district.valid(((q >= 2) && (q <= 5) : U32) && (U32.is_eq(seed,45) || U32.is_eq(seed,46)),q,seed,c)
def spacing(c: Control) -> U32:
  match c:
    case Spread{}: 640
    case _: 320
def envelope(+q: U32, c: Control) -> U32:
  match c:
    case Spread{}: (640 * (q - 1) + 320 : U32)
    case _: (320 * q : U32)
def box(x0: F32, x1: F32, y0: F32, y1: F32, z0: F32, z1: F32, m: U32) -> Box:
  Box{R.Vec{x0,y0,z0},R.Vec{x1,y1,z1},m}
def terrain(+v: F32) -> List<&2,Box>:
  +h = (32.0 + 2.0 * v : F32)
  [box(0.0,320.0,0.0,1.0,0.0,320.0,1),
   box(0.0,320.0,1.0,8.0,0.0,320.0,2),
   box(0.0,224.0,8.0,24.0,0.0,320.0,2),
   box(288.0,320.0,8.0,24.0,0.0,320.0,2),
   box(224.0,288.0,8.0,24.0,0.0,240.0,2),
   box(224.0,288.0,8.0,24.0,304.0,320.0,2),
   box(224.0,288.0,22.0,24.0,271.0,273.0,2),
   box(160.0,208.0,24.0,h,16.0,64.0,2),
   box(160.0,184.0,24.0,h,64.0,96.0,2),
   box(184.0,208.0,24.0,28.0,64.0,96.0,2)]
def building(v: F32) -> List<&2,Box>:
  +h = (80.0 + 2.0 * v : F32)
  +top = (h + 3.0 : F32)
  [box(16.0,24.0,24.0,26.0,16.0,24.0,1),
   box(16.0,24.0,24.0,26.0,128.0,136.0,1),
   box(128.0,136.0,24.0,26.0,16.0,24.0,1),
   box(128.0,136.0,24.0,26.0,128.0,136.0,1),
   box(16.0,136.0,26.0,28.0,16.0,136.0,5),
   box(16.0,20.0,28.0,h,20.0,132.0,5),
   box(16.0,136.0,28.0,h,132.0,136.0,5),
   box(16.0,64.0,28.0,h,16.0,20.0,5),
   box(88.0,136.0,28.0,h,16.0,20.0,5),
   box(64.0,88.0,60.0,h,16.0,20.0,5),
   box(132.0,136.0,28.0,h,20.0,56.0,5),
   box(132.0,136.0,28.0,h,80.0,132.0,5),
   box(132.0,136.0,28.0,44.0,56.0,80.0,5),
   box(132.0,136.0,64.0,h,56.0,80.0,5),
   box(76.0,80.0,28.0,h,48.0,72.0,2),
   box(76.0,80.0,28.0,h,88.0,112.0,2),
   box(76.0,80.0,60.0,h,72.0,88.0,2),
   box(16.0,48.0,h,top,16.0,136.0,3),
   box(72.0,136.0,h,top,16.0,136.0,3),
   box(48.0,72.0,h,top,16.0,96.0,3),
   box(48.0,72.0,h,top,120.0,136.0,3)]
def span(+j: U32, v: F32) -> List<&2,Box>:
  +z = U32.to_f32((176 + 24 * j : U32))
  +b = (72.0 + v : F32)
  [box(22.0,28.0,24.0,26.0,(z + 1.0 : F32),(z + 7.0 : F32),1),
   box(124.0,130.0,24.0,26.0,(z + 1.0 : F32),(z + 7.0 : F32),1),
   box(24.0,26.0,26.0,b,(z + 3.0 : F32),(z + 5.0 : F32),3),
   box(126.0,128.0,26.0,b,(z + 3.0 : F32),(z + 5.0 : F32),3),
   box(16.0,136.0,b,(b + 4.0 : F32),z,(z + 8.0 : F32),2)]
def irregular(v: U32) -> List<&2,Box>:
  +r = U32.to_f32((v % 2 : U32))
  [box(280.0,288.0,24.0,26.0,176.0,184.0,1),
   box(280.0,288.0,26.0,42.0,176.0,184.0,4),
   box(272.0,288.0,42.0,50.0,168.0,184.0,4),
   box(280.0,296.0,50.0,(58.0 + r : F32),176.0,192.0,3),
   box(288.0,(302.0 + r : F32),34.0,50.0,184.0,199.0,4)]

def translate(b: Box, +ox: F32, +oz: F32, +dy: F32) -> Box:
  Box{R.Vec{x,y,z},R.Vec{u,v,w},m} = b
  Box{R.Vec{(x + ox : F32),(y + dy : F32),(z + oz : F32)},
      R.Vec{(u + ox : F32),(v + dy : F32),(w + oz : F32)},m}
def translate.list(bs: List<&2,Box>, +ox: F32, +oz: F32, +dy: F32) -> List<&2,Box>:
  match bs:
    case Nil{}: Nil{}
    case b <> rest: translate(b,ox,oz,dy) <> translate.list(rest,ox,oz,dy)
def rise(c: Control) -> F32:
  match c:
    case Fill{}: 8.0
    case _: 0.0
def bands(n: Nat, +x: U32, +x1: U32, +b: Box) -> List<&2,Box>:
  match n:
    case 0n: Nil{}
    case 1n+k:
      Box{R.Vec{_,y,z},R.Vec{_,v,w},_} = b
      +hi = R.word(((x + 4) < x1 : U32),(x + 4 : U32),x1)
      box(U32.to_f32(x),U32.to_f32(hi),y,v,z,w,R.word(U32.is_eq(((x / 4) % 2 : U32),0),2,5)) <>
        bands(k,(x + 4 : U32),x1,b)
def pits.z(n: Nat, +x: F32, +w: F32, cursor: F32) -> List<&2,Box>:
  match n:
    case 0n: [box(x,(x + 2.0 : F32),22.0,24.0,cursor,240.0,2)]
    case 1n+k:
      +z = (16.0 + 6.0 * w : F32)
      box(x,(x + 2.0 : F32),22.0,24.0,cursor,z,2) <>
        pits.z(k,x,(w + 1.0 : F32),(z + 2.0 : F32))
def pits.gap(on: Bool, lo: F32, +hi: F32, tail: List<&2,Box>) -> List<&2,Box>:
  match on:
    case True{}: box(lo,hi,22.0,24.0,0.0,240.0,2) <> tail
    case False{}: tail
def pits.x(n: Nat, +u: F32, +cursor: F32) -> List<&2,Box>:
  match n:
    case 0n: [box(cursor,288.0,22.0,24.0,0.0,240.0,2)]
    case 1n+k:
      +x = (224.0 + 6.0 * u : F32)
      pits.gap((cursor < x : F32),cursor,x,
        List.append(&2,Box,pits.z(8n,x,0.0,0.0),pits.x(k,(u + 1.0 : F32),(x + 2.0 : F32))))
def pits(on: Bool, b: Box, tail: List<&2,Box>) -> List<&2,Box>:
  match on:
    case True{}:
      box(224.0,288.0,8.0,22.0,0.0,240.0,2) <>
        List.append(&2,Box,pits.x(8n,0.0,224.0),tail)
    case False{}: b <> tail
def detail.box(c: Control, b: Box, tail: List<&2,Box>) -> List<&2,Box>:
  match c b:
    case Fill{} +b:
      Box{R.Vec{_,+y,_},_,_} = b
      translate(b,0.0,0.0,R.pick((y >= 8.0 : F32),8.0,0.0)) <> tail
    case MaterialDetail{} Box{R.Vec{+x,y,z},R.Vec{+u,v,w},2}:
      +lo = F32.to_u32(x)
      +hi = F32.to_u32(u)
      List.append(&2,Box,bands(U32.to_nat(((hi - lo + 3) / 4 : U32)),lo,hi,
        Box{R.Vec{x,y,z},R.Vec{u,v,w},2}),tail)
    case SurfaceDetail{} +b:
      Box{R.Vec{x,y,z},R.Vec{u,v,w},_} = b
      pits(F32.is_eq(x,224.0) && F32.is_eq(u,288.0) && F32.is_eq(y,8.0) &&
        F32.is_eq(v,24.0) && F32.is_eq(z,0.0) && F32.is_eq(w,240.0),b,tail)
    case _ b: b <> tail
def detail(bs: List<&2,Box>, +c: Control) -> List<&2,Box>:
  match bs:
    case Nil{}: Nil{}
    case +b <> rest:
      detail.box(c,b,detail(rest,c))
def fill.layer(c: Control) -> List<&2,Box>:
  match c:
    case Fill{}: [box(0.0,320.0,8.0,16.0,0.0,320.0,2)]
    case _: Nil{}
def crop.valid(ok: Bool, b: Box, tail: List<&2,Box>) -> List<&2,Box>:
  match ok:
    case True{}: b <> tail
    case False{}: tail
def crop(bs: List<&2,Box>, +left: Bool) -> List<&2,Box>:
  match bs:
    case Nil{}: Nil{}
    case Box{R.Vec{+x,y,z},R.Vec{+u,v,w},m} <> rest:
      +lo = R.pick(left,x,R.max(x,80.0))
      +hi = R.pick(left,R.min(u,72.0),u)
      crop.valid((lo < hi : F32),Box{R.Vec{lo,y,z},R.Vec{hi,v,w},m},crop(rest,left))
def building.owners(c: Control, +n: U32, +bs: List<&2,Box>, +ox: F32, +oz: F32) -> List<&2,Owner>:
  match c:
    case BodyRich{}:
      [Owner{"building_left",Some{n},translate.list(crop(bs,True{}),ox,oz,0.0)},
       Owner{"building_right",Some{n},translate.list(crop(bs,False{}),ox,oz,0.0)}]
    case +c: [Owner{"building",Some{n},translate.list(bs,ox,oz,rise(c))}]
type Patch is Data:
  Patch{terrain: List<&2,Box>, structures: List<&2,Owner>}
def neighborhood(+n: U32, +q: U32, +seed: U32, +c: Control) -> Patch:
  +ix = (n % q : U32)
  +iz = (n / q : U32)
  +half = U32.to_f32((envelope(q,c) / 2 : U32))
  +step = spacing(c)
  +ox = (U32.to_f32((step * ix : U32)) - half : F32)
  +oz = (U32.to_f32((step * iz : U32)) - half : F32)
  +v = ((3 * ix + 5 * iz + seed - 45) % 4 : U32)
  +fv = U32.to_f32(v)
  Patch{translate.list(List.append(&2,Box,detail(terrain(fv),c),fill.layer(c)),ox,oz,0.0),
    List.append(&2,Owner,building.owners(c,n,building(fv),ox,oz),
      [Owner{"span0",Some{n},translate.list(span(0,fv),ox,oz,rise(c))},
       Owner{"span1",Some{n},translate.list(span(1,fv),ox,oz,rise(c))},
       Owner{"span2",Some{n},translate.list(span(2,fv),ox,oz,rise(c))},
       Owner{"irregular",Some{n},translate.list(irregular(v),ox,oz,rise(c))}])}
def patches.join(a: Patch, b: Patch) -> Patch:
  Patch{at,as} = a
  Patch{bt,bs} = b
  Patch{List.append(&2,Box,at,bt),List.append(&2,Owner,as,bs)}
def patches(n: Nat, +index: U32, +q: U32, +seed: U32, +c: Control) -> Patch:
  match n:
    case 0n: Patch{Nil{},Nil{}}
    case 1n+k:
      patches.join(neighborhood(index,q,seed,c),patches(k,(index + 1 : U32),q,seed,c))
def connector(+x0: F32, +x1: F32, +z0: F32, +z1: F32) -> List<&2,Box>:
  [box(x0,x1,0.0,1.0,z0,z1,1),box(x0,x1,1.0,24.0,z0,z1,2)]
def connectors.x(n: Nat, +index: U32, +q: U32, +half: F32) -> List<&2,Box>:
  match n:
    case 0n: Nil{}
    case 1n+k:
      +x = (U32.to_f32((640 * (index % (q - 1)) + 320 : U32)) - half : F32)
      +z = (U32.to_f32((640 * (index / (q - 1)) + 158 : U32)) - half : F32)
      List.append(&2,Box,connector(x,(x + 320.0 : F32),z,(z + 2.0 : F32)),
        connectors.x(k,(index + 1 : U32),q,half))
def connectors.z(n: Nat, +index: U32, +half: F32) -> List<&2,Box>:
  match n:
    case 0n: Nil{}
    case 1n+k:
      +x = (158.0 - half : F32)
      +z = (U32.to_f32((640 * index + 320 : U32)) - half : F32)
      List.append(&2,Box,connector(x,(x + 2.0 : F32),z,(z + 320.0 : F32)),
        connectors.z(k,(index + 1 : U32),half))
def connectors(c: Control, +q: U32) -> List<&2,Box>:
  match c:
    case Spread{}:
      +half = U32.to_f32((envelope(q,Spread{}) / 2 : U32))
      List.append(&2,Box,connectors.x(U32.to_nat((q * (q - 1) : U32)),0,q,half),
        connectors.z(U32.to_nat((q - 1 : U32)),0,half))
    case _: Nil{}
def owners.patch(p: Patch, q: U32, c: Control) -> List<&2,Owner>:
  Patch{ts,bs} = p
  Owner{"terrain",None{},List.append(&2,Box,ts,connectors(c,q))} <> bs
def owners(d: District) -> List<&2,Owner>:
  District{+q,seed,+c} = d
  owners.patch(patches(U32.to_nat((q * q : U32)),0,q,seed,c),q,c)
