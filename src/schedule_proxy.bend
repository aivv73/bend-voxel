import Base
import ./schedule_route.bend as Route
import ./schedule_float.bend as F
import ./schedule_json.bend as J

type Hold is Data:
  Hold{label: String, camera: String, ray: String, target: String}

def center(lo: F.Vec,hi: F.Vec) -> F.Vec:
  F.Vec{x,y,z} = lo
  F.Vec{a,b,c} = hi
  F.Vec{F.Div{F.Add{x,a},Route.real("20")},F.Div{F.Add{y,b},Route.real("20")},F.Div{F.Add{z,c},Route.real("20")}}
def radius(lo: F.Vec,hi: F.Vec) -> F.Expr:
  F.Vec{x,y,z} = lo
  F.Vec{a,b,c} = hi
  F.Sqrt{F.Sum3{F.Pow2{F.Div{F.Sub{a,x},Route.real("20")}},F.Pow2{F.Div{F.Sub{b,y},Route.real("20")}},F.Pow2{F.Div{F.Sub{c,z},Route.real("20")}}}}
def parameter(i: U32) -> U32:
  match i:
    case 0: 105
    case 1: 75
    case 2: 90
    case 3: 105
    case 4: 90
    case 8: 105
    case _: 75
def label(diagnostic: String,i: U32) -> String:
  match diagnostic:
    case "mixed-world": Route.string.at(U32.to_nat(i),["far_entry","near_exit","far_reentry"])
    case _: "hold_" ++ U32.show(i)
def at(+center: F.Vec,+radius: F.Expr,height: U32,p: U32) -> Route.Pose:
  F.Vec{x,y,z} = center
  distance = {F.Add{radius,F.Div{F.Mul{F.Mul{Route.real("800"),F.Div{Route.num(height),Route.real("360")}},radius},Route.num(p)}} : F.Expr}
  Route.Pose{F.Vec{x,y,F.Add{z,distance}},center}
def pose(diagnostic: String,i: U32,+center: F.Vec,radius: F.Expr,height: U32) -> Route.Pose:
  match diagnostic:
    case "mixed-world":
      F.Vec{x,y,z} = center
      distance = Route.select(F.Expr,U32.is_eq(i,1),Route.real("100"),Route.real("1000"))
      Route.Pose{F.Vec{x,y,F.Add{z,distance}},center}
    case _: at(center,radius,height,parameter(i))
def ray.pose(target: Bool,p: Route.Pose) -> Route.Pose:
  match target:
    case True{}:
      Route.Pose{eye,_} = p
      Route.Pose{eye,Route.vec("6","4.2","7.1")}
    case False{}: p
def hold(+diagnostic: String,+i: U32,center: F.Vec,radius: F.Expr,height: U32) -> IO(Hold):
  +p = pose(diagnostic,i,center,radius,height)
  +hit = String.eq(diagnostic,"compact-reference") && U32.is_eq(i,6)
  do IO<Hold>:
    cam : String <- Route.pose.camera(p)
    ray : String <- Route.pose.ray(ray.pose(hit,p))
    return Hold{label(diagnostic,i),cam,ray,Route.select(String,hit,"right_lobe","declared_miss")}
def hold.prepend(h: Hold,hs: List<&2,Hold>) -> List<&2,Hold>: h <> hs
def holds(n: Nat,+i: U32,+diagnostic: String,+center: F.Vec,+radius: F.Expr,+height: U32) -> IO(List<&2,Hold>):
  match n:
    case 0n: IO.pure(List<&2,Hold>,Nil{})
    case 1n+p:
      do IO<List<&2,Hold>>:
        h : Hold <- hold(diagnostic,i,center,radius,height)
        hs : List<&2,Hold> <- holds(p,(i + 1 : U32),diagnostic,center,radius,height)
        return hold.prepend(h,hs)
def hold.at(n: Nat,hs: List<&2,Hold>) -> Hold:
  match n hs:
    case 0n h <> _: h
    case 1n+p _ <> rest: hold.at(p,rest)
    case _ Nil{}: Hold{"","","",""}
def labels(hs: List<&2,Hold>) -> List<&2,String>:
  match hs:
    case Nil{}: Nil{}
    case Hold{name,_,_,_} <> rest: J.quote(name) <> labels(rest)
def reviews(hs: List<&2,Hold>,+i: U32,+length: U32) -> List<&2,String>:
  match hs:
    case Nil{}: [J.review("completion",3720,[J.quote("unchanged geometry"),J.quote("major shadows")])]
    case Hold{+name,_,_,_} <> rest:
      J.object([J.field("name",J.quote("review_" ++ name)),J.field("frame",J.number((121 + i * length + length / 2 : U32))),J.field("pose",J.quote(name)),J.field("features",J.array([J.quote("group silhouette"),J.quote("major shadows")]))]) <> reviews(rest,(i + 1 : U32),length)
def points(hs: List<&2,Hold>,+i: U32,+length: U32) -> List<&2,String>:
  match hs:
    case Nil{}: [J.point("completion",3720)]
    case Hold{name,_,_,_} <> rest:
      J.point("review_" ++ name,(121 + i * length + length / 2 : U32)) <> points(rest,(i + 1 : U32),length)
def frame.hold(h: Hold,+i: U32,+length: U32,diagnostic: String,scene: String,opening: String,+warm: Bool,index: U32) -> String:
  Hold{label,cam,ray,target} = h
  +active = String.eq(scene,"picking") && Bool.not(warm) &&
    (Bool.not(String.eq(diagnostic,"mixed-world")) || Bool.not(U32.is_eq(index,1)))
  Route.frame(i,120,Route.frame.phase(i,120,False{},False{}),Route.select(String,warm,opening,cam),active,"[]",
    [J.field("route_phase",Route.select(String,warm,"null",J.quote(label))),
     J.field("phase_offset",Route.select(String,warm,"null",J.number(((i - 121) % length : U32)))),
     J.field("ray",Route.select(String,active,ray,"null")),
     J.field("target",Route.select(String,active,J.quote(target),"null"))])
def frame(+i: U32,+length: U32,last: U32,+diagnostic: String,+scene: String,opening: String,hs: List<&2,Hold>) -> String:
  +warm = (i <= 120 : U32)
  +index = Route.select(U32,warm,0,U32.min(((i - 121) / length : U32),last))
  frame.hold(hold.at(U32.to_nat(index),hs),i,length,diagnostic,scene,opening,warm,index)
def frames(n: Nat,+i: U32,+length: U32,+last: U32,+diagnostic: String,+scene: String,+opening: String,+hs: List<&2,Hold>) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+p:
      do IO<Unit>:
        IO.print(frame(i,length,last,diagnostic,scene,opening,hs))
        frames(p,(i + 1 : U32),length,last,diagnostic,scene,opening,hs)
def opening.hold(h: Hold) -> String:
  Hold{_,cam,_,_} = h
  cam
def opening(diagnostic: String,q: U32,seed: U32,hs: List<&2,Hold>) -> IO(String):
  match diagnostic:
    case "mixed-world": Route.pose.camera(Route.pose("opening",0,q,seed,"traversal-v2","base"))
    case _: IO.pure(String,opening.hold(hold.at(0n,hs)))
def proxy(q: U32,seed: U32,+diagnostic: String,+scene: String,height: U32,+lo: F.Vec,+hi: F.Vec) -> IO(Unit):
  +length = Route.select(U32,String.eq(diagnostic,"mixed-world"),1200,120)
  +count = Route.select(U32,String.eq(diagnostic,"mixed-world"),3,9)
  do IO<Unit>:
    +hs : List<&2,Hold> <- holds(U32.to_nat(count),0,diagnostic,center(lo,hi),radius(lo,hi),height)
    +view : String <- opening(diagnostic,q,seed,hs)
    IO.print(Route.header("proxy-" ++ diagnostic ++ "-" ++ scene ++ "-v1",120,3600,view,
      J.review("opening",0,[J.quote("full source geometry"),J.quote("major shadows")]) <> reviews(hs,0,length),
      Route.append(Route.initial.points(120),points(hs,0,length)),False{},
      [J.field("diagnostic",J.quote(diagnostic)),J.field("hold_length",J.number(length)),J.field("hold_labels",J.array(labels(hs)))]))
    frames(3721n,0,length,(count - 1 : U32),diagnostic,scene,view,hs)
def shadow.bounds(lo: F.Vec,hi: F.Vec) -> IO(String):
  F.Vec{+x,_,+z} = lo
  F.Vec{+a,+b,+c} = hi
  +side = {F.Add{F.Max{F.Max{F.Max{F.Sub{a,x},F.Sub{c,z}},F.Mul{Route.real("2"),b}},Route.real("4")},Route.real("6")} : F.Expr}
  +lx = {F.Div{F.Add{x,a},Route.real("2")} : F.Expr}
  +lz = {F.Div{F.Add{z,c},Route.real("2")} : F.Expr}
  look = {F.Vec{lx,Route.real("0"),lz} : F.Vec}
  F.camera(F.Vec{F.Add{lx,F.Mul{Route.real("0.45"),side}},F.Mul{Route.real("0.85"),side},F.Add{lz,F.Mul{Route.real("0.75"),side}}},look)
def meters(v: F.Vec) -> F.Vec:
  F.Vec{x,y,z} = v
  F.Vec{F.Div{x,Route.real("10")},F.Div{y,Route.real("10")},F.Div{z,Route.real("10")}}
def shadow(lo: F.Vec,hi: F.Vec) -> IO(String): shadow.bounds(meters(lo),meters(hi))
def history.face(+point: F.Vec,normal: F.Vec) -> IO(String):
  F.Vec{x,y,z} = point
  F.Vec{nx,ny,nz} = normal
  F.camera(F.Vec{F.Add{F.Add{x,F.Mul{nx,Route.real("3")}},Route.real("0")},F.Add{F.Add{y,F.Mul{ny,Route.real("3")}},Route.real("3")},F.Add{F.Add{z,F.Mul{nz,Route.real("3")}},Route.real("4")}},point)
