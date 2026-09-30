import Base
import ./schedule_float.bend as F
import ./schedule_json.bend as J
import ./megascene_scale.bend as Scale

type Pose is Data:
  Pose{eye: F.Vec, look: F.Vec}

def num(n: U32) -> F.Expr: F.Literal{U32.show(n)}
def select(-T: Data, flag: Bool, yes: T, no: T) -> T:
  match flag:
    case True{}: yes
    case False{}: no
def real(n: String) -> F.Expr: F.Literal{n}
def pose.camera(p: Pose) -> IO(String):
  Pose{eye,look} = p
  F.camera(eye,look)
def string.at(n: Nat, xs: List<&2,String>) -> String:
  match n xs:
    case 0n x <> _: x
    case 1n+p _ <> rest: string.at(p,rest)
    case _ Nil{}: "null"
def phase.name(i: U32) -> String:
  match i:
    case 0: "opening"
    case 1: "wall"
    case 2: "interior"
    case 3: "cavity"
    case 4: "assembly"
    case 5: "far"
    case 6: "opening"
    case 7: "cavity"
    case 8: "sky"
    case _: "opening"
def features(name: String) -> List<&2,String>:
  match name:
    case "opening": [J.quote("building silhouettes"),J.quote("span silhouettes"),J.quote("major shadows")]
    case "wall": [J.quote("exterior plaster wall")]
    case "interior": [J.quote("clear interior doorway"),J.quote("interior wall")]
    case "cavity": [J.quote("cavity depth"),J.quote("open air"),J.quote("cavity bridge")]
    case "assembly": [J.quote("irregular lobes"),J.quote("material distinctions")]
    case "far": [J.quote("whole district extent"),J.quote("major structures"),J.quote("major shadows")]
    case _: [J.quote("open sky")]
def append(xs: List<&2,String>,ys: List<&2,String>) -> List<&2,String>:
  match xs:
    case Nil{}: ys
    case x <> rest: x <> append(rest,ys)
def initial.points(warmup: U32) -> List<&2,String>:
  [J.point("initialization",0),J.point("review_opening",0),J.point("warmup_end",warmup)]
def interpolate(+a: F.Expr,+b: F.Expr,+t: F.Expr) -> F.Expr:
  F.Round32{F.Add{a,F.Mul{F.Sub{b,a},t}}}
def frame.phase.flags(start: Bool,warm: Bool,edit: Bool,moving: Bool) -> String:
  match start warm edit moving:
    case True{} _ _ _: "startup"
    case _ True{} _ _: "warmup"
    case _ _ True{} _: "edit"
    case _ _ _ True{}: "motion"
    case _ _ _ _: "ordinary"
def pose.emit(p: Pose) -> IO(Unit):
  Pose{+eye,+look} = p
  do IO<Unit>:
    es : String <- F.exact.vector(eye)
    ls : String <- F.exact.vector(look)
    IO.print("[" ++ es ++ "," ++ ls ++ "]")
def camera.route(route: String) -> String:
  match route:
    case "picking-v1": "traversal-v1"
    case "picking-v2": "traversal-v2"
    case _: route

def is.picking(id: String) -> Bool:
  match id:
    case "picking-v1": True{}
    case "picking-v2": True{}
    case "proxy-compact-reference-picking-v1": True{}
    case "proxy-mixed-world-picking-v1": True{}
    case _: False{}

def pick.enabled(i: U32) -> Bool:
  match i:
    case 1: True{}
    case 2: True{}
    case 3: True{}
    case 4: True{}
    case 7: True{}
    case 8: True{}
    case _: False{}

def pose.ray.delta(eye: F.Vec,d: F.Vec) -> IO(String):
  F.Vec{+x,y,+z} = d
  F.center(eye,F.Round32{F.Atan2{x,z}},F.Round32{F.Atan2{y,F.Hypot{x,z}}})
def vec(x: String,y: String,z: String) -> F.Vec: F.Vec{real(x),real(y),real(z)}
def origin(+q: U32,+n: U32) -> F.Vec:
  F.Vec{F.Sub{num((320 * (n % q : U32) : U32)),num((160 * q : U32))},real("0"),
    F.Sub{num((320 * (n / q : U32) : U32)),num((160 * q : U32))}}
def meters(v: F.Vec, o: F.Vec) -> F.Vec:
  F.Vec{x,y,z} = v
  F.Vec{ox,oy,oz} = o
  F.Vec{F.Div{F.Add{x,ox},real("10")},F.Div{F.Add{y,oy},real("10")},F.Div{F.Add{z,oz},real("10")}}
def lift(v: F.Vec, +control: String) -> F.Vec:
  F.Vec{x,y,z} = v
  match control:
    case "fill": F.Vec{x,F.Add{y,real("0.8")},z}
    case _: F.Vec{x,y,z}
def phase.neighborhood(+i: U32,+q: U32) -> U32:
  select(U32,U32.is_eq(i,6) || U32.is_eq(i,7),(q * q - 1 : U32),0)
def route.points(n: Nat,+i: U32) -> List<&2,String>:
  match n:
    case 0n: [J.point("completion",3720)]
    case 1n+p:
      id = "review_route_" ++ select(String,(i < 10 : U32),"0" ++ U32.show(i),U32.show(i))
      J.point(id,(181 + 300 * i : U32)) <> route.points(p,(i + 1 : U32))
def interpolate.vec(a: F.Vec,b: F.Vec,+t: F.Expr) -> F.Vec:
  F.Vec{ax,ay,az} = a
  F.Vec{bx,by,bz} = b
  F.Vec{interpolate(ax,bx,t),interpolate(ay,by,t),interpolate(az,bz,t)}
def frame.phase(+index: U32,+warmup: U32,edit: Bool,moving: Bool) -> String:
  frame.phase.flags(U32.is_eq(index,0),(index <= warmup : U32),edit,moving)
def frame(+index: U32,+warmup: U32,phase: String,camera: String,picking: Bool,actions: String,extra: List<&2,String>) -> String:
  ordinal = select(String,(index > warmup : U32),J.number((index - warmup - 1 : U32)),"null")
  J.object(append([J.field("record_type",J.quote("frame")),J.field("frame",J.number(index)),J.field("phase",J.quote(phase)),J.field("measured_ordinal",ordinal),J.field("camera",camera),J.field("picking",J.boolean(picking)),J.field("actions",actions)],extra))
def header(+id: String,warmup: U32,measured: U32,opening: String,reviews: List<&2,String>,points: List<&2,String>,edit: Bool,extra: List<&2,String>) -> String:
  editing = select(String,edit,"edit","edit_disabled")
  J.object(append([J.field("schema",J.quote("megascene-evidence/1")),J.field("record_type",J.quote("schedule")),J.field("fixed_step",J.quote("0x3c888889")),J.field("schedule_id",J.quote(id)),J.field("warmup_frames",J.number(warmup)),J.field("measured_frames",J.number(measured)),J.field("opening",opening),J.field("review_views",J.array(reviews)),J.field("required_checkpoints",J.array(points)),J.field("checkpoint_implementation",J.quote("megascene-checkpoint/1")),J.field("update_order",J.array([J.quote("physics"),J.quote(editing),J.quote(select(String,is.picking(id),"view_picking","view_picking_disabled")),J.quote("render")]))],extra))
def pose.ray(p: Pose) -> IO(String):
  Pose{+eye,look} = p
  pose.ray.delta(eye,F.delta(eye,look))
def local(+name: String, +v: U32, route: String, control: String) -> Pose:
  match name:
    case "opening": Pose{vec("150","120","310"),vec("76","48","76")}
    case "wall": Pose{vec("8","48","60"),vec("16","48","60")}
    case "interior":
      match control:
        case "body-rich": Pose{vec("40","48","80"),vec("40","48","132")}
        case _: Pose{vec("116","44","80"),vec("20","44","80")}
    case "cavity":
      match route:
        case "traversal-v1": Pose{vec("256","44","244"),vec("256","8","256")}
        case _: Pose{vec("256","70","210"),vec("256","12","272")}
    case "assembly": Pose{vec("284","90","160"),F.Vec{real("284"),num((58 + (v % 2 : U32) : U32)),real("180")}}
    case _: Pose{vec("160","120","160"),vec("160","220","260")}
def vec.at(n: Nat, xs: List<&2,F.Vec>) -> F.Vec:
  match n xs:
    case 0n x <> _: x
    case 1n+p _ <> rest: vec.at(p,rest)
    case _ Nil{}: vec("0","0","0")
def pose.local(p: Pose,+o: F.Vec,+control: String) -> Pose:
  Pose{eye,look} = p
  Pose{lift(meters(eye,o),control),lift(meters(look,o),control)}
def route.reviews(n: Nat,+i: U32,+q: U32) -> List<&2,String>:
  match n:
    case 0n: [J.object([J.field("name",J.quote("completion")),J.field("frame",J.number(3720)),J.field("pose",J.quote("opening")),J.field("features",J.array([J.quote("unchanged return geometry"),J.quote("major shadows")]))])]
    case 1n+p:
      +name = phase.name(i)
      +id = "review_route_" ++ select(String,(i < 10 : U32),"0" ++ U32.show(i),U32.show(i))
      more = select(List<&2,String>,(i >= 6 : U32),[J.quote("unchanged return geometry")],Nil{})
      neighborhood = select(String,U32.is_eq(i,5),"null",J.number(phase.neighborhood(i,q)))
      J.object([J.field("name",J.quote(id)),J.field("frame",J.number((181 + 300 * i : U32))),J.field("pose",J.quote(name)),J.field("neighborhood",neighborhood),J.field("features",J.array(append(features(name),more)))]) <> route.reviews(p,(i + 1 : U32),q)
def interpolate.pose(p: Pose,s: Pose,+t: F.Expr) -> Pose:
  Pose{eye,look} = p
  Pose{seye,slook} = s
  Pose{interpolate.vec(eye,seye,t),interpolate.vec(look,slook,t)}
def static.frames(n: Nat,+i: U32,+warmup: U32,+opening: String) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+p:
      do IO<Unit>:
        IO.print(frame(i,warmup,frame.phase(i,warmup,False{},False{}),opening,False{},"[]",Nil{}))
        static.frames(p,(i + 1 : U32),warmup,opening)
def pick.target(+phase: U32,q: U32) -> String:
  owner = select(String,U32.is_eq(phase,4),"6",select(String,U32.is_eq(phase,3) || U32.is_eq(phase,7),"1",select(String,U32.is_eq(phase,8),"0","2")))
  material = select(String,U32.is_eq(phase,4),"3",select(String,U32.is_eq(phase,3) || U32.is_eq(phase,7),"2",select(String,U32.is_eq(phase,8),"0","5")))
  J.object([J.field("name",J.quote(phase.name(phase))),J.field("neighborhood",J.number(phase.neighborhood(phase,q))),J.field("owner",J.quote(owner)),J.field("material",J.quote(material)),J.field("outcome",J.quote(select(String,U32.is_eq(phase,8),"miss","hit")))])
def pose(+name: String,+n: U32,+q: U32,+seed: U32,+route: String,+control: String) -> Pose:
  match name:
    case "far":
      +side = num((32 * q : U32))
      Pose{lift(F.Vec{real("0"),F.Mul{real("0.75"),side},F.Mul{real("1.25"),side}},control),lift(vec("0","2.4","0"),control)}
    case _:
      +o = origin(q,n)
      v = ((3 * (n % q : U32) + 5 * (n / q : U32) + seed - 45) % 4 : U32)
      pose.local(local(name,v,route,control),o,control)
def static.eye(+eye: F.Vec,+warmup: U32,+measured: U32,id: String) -> IO(Unit):
  F.Vec{x,y,z} = eye
  look = {F.Vec{F.Add{x,real("-74")},F.Add{y,real("-72")},F.Add{z,real("-234")}} : F.Vec}
  do IO<Unit>:
    +opening : String <- F.camera(eye,look)
    IO.print(header(id,warmup,measured,opening,[J.review("opening",0,features("opening"))],append(initial.points(warmup),[J.point("completion",(warmup + measured : U32))]),False{},Nil{}))
    static.frames(U32.to_nat((1 + warmup + measured : U32)),0,warmup,opening)
def route.record(active: Bool,+picking: Bool,+i: U32,q: U32,+phase: U32,+offset: U32,p: Pose,+cam: String) -> IO(String):
  match active:
    case True{}:
      do IO<String>:
        ray : String <- pose.ray(p)
        return frame(i,120,"ordinary",cam,True{},"[]",[J.field("route_phase",J.quote(phase.name(phase))),J.field("phase_offset",J.number(offset)),J.field("ray",ray),J.field("target",pick.target(phase,q))])
    case False{}:
      extra = select(List<&2,String>,picking,[J.field("ray","null"),J.field("target","null")],Nil{})
      fields = append([J.field("route_phase",select(String,(i > 120 : U32),J.quote(phase.name(phase)),"null")),J.field("phase_offset",select(String,(i > 120 : U32),J.number(offset),"null"))],extra)
      IO.pure(String,frame(i,120,frame.phase(i,120,False{},False{}),cam,False{},"[]",fields))
def route.frame.when(warm: Bool,+i: U32,+q: U32,+seed: U32,+route: String,opening: String) -> IO(String):
  match warm:
    case True{}: route.record(False{},is.picking(route),i,q,0,0,pose("opening",0,q,seed,camera.route(route),"base"),opening)
    case False{}:
      +phase = ((i - 121) / 300 : U32)
      +offset = ((i - 121) % 300 : U32)
      +p = pose(phase.name(phase),phase.neighborhood(phase,q),q,seed,camera.route(route),"base")
      +next = U32.min((phase + 1 : U32),11)
      +s = pose(phase.name(next),phase.neighborhood(next,q),q,seed,camera.route(route),"base")
      +t = {F.Div{num((offset - 119 : U32)),real("180")} : F.Expr}
      +chosen = select(Pose,(offset < 120 : U32),p,select(Pose,U32.is_eq(offset,299),s,
        interpolate.pose(p,s,t)))
      do IO<String>:
        cam : String <- pose.camera(chosen)
        route.record(is.picking(route) && pick.enabled(phase) && (offset < 120 : U32),is.picking(route),i,q,phase,offset,chosen,cam)
def static(+origin: String,+warmup: U32,+measured: U32,id: String) -> IO(Unit):
  static.eye(meters(vec("150","120","310"),vec(origin,"0",origin)),warmup,measured,id)
def arguments.pose(name: String,n: Maybe<&2,U32>,q: Maybe<&2,U32>,seed: Maybe<&2,U32>,route: String,control: String) -> IO(Unit):
  match n q seed:
    case Some{n} Some{q} Some{seed}: pose.emit(pose(name,n,q,seed,route,control))
    case _ _ _: IO.die(Unit,2,"invalid pose arguments")
def route.frame(+i: U32,+q: U32,+seed: U32,+route: String,opening: String) -> IO(String):
  route.frame.when((i <= 120 : U32),i,q,seed,route,opening)
def arguments.static(origin: String,warmup: Maybe<&2,U32>,measured: Maybe<&2,U32>,id: String) -> IO(Unit):
  match warmup measured:
    case Some{warmup} Some{measured}: static(origin,warmup,measured,id)
    case _ _: IO.die(Unit,2,"invalid static arguments")
def route.frames(n: Nat,+i: U32,+q: U32,+seed: U32,+route: String,+opening: String) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+p:
      do IO<Unit>:
        row : String <- route.frame(i,q,seed,route,opening)
        IO.print(row)
        route.frames(p,(i + 1 : U32),q,seed,route,opening)
def traversal(+q: U32,+seed: U32,+route: String) -> IO(Unit):
  do IO<Unit>:
    +opening : String <- pose.camera(pose("opening",0,q,seed,camera.route(route),"base"))
    IO.print(header(route,120,3600,opening,J.review("opening",0,features("opening")) <> route.reviews(12n,0,q),append(initial.points(120),route.points(12n,0)),False{},select(List<&2,String>,is.picking(route),[J.field("camera_route_id",J.quote(camera.route(route)))],Nil{})))
    route.frames(3721n,0,q,seed,route,opening)
def arguments.traversal(q: Maybe<&2,U32>,seed: Maybe<&2,U32>,route: String) -> IO(Unit):
  match q seed:
    case Some{q} Some{seed}: traversal(q,seed,route)
    case _ _: IO.die(Unit,2,"invalid traversal arguments")
def arguments(xs: List<String>) -> IO(Unit):
  match xs:
    case _ <> "traversal" <> q <> seed <> route <> Nil{}:
      arguments.traversal(U32.read(q),U32.read(seed),route)
    case _ <> "static" <> origin <> warmup <> measured <> id <> Nil{}:
      arguments.static(origin,U32.read(warmup),U32.read(measured),id)
    case _ <> "pose" <> name <> n <> q <> seed <> route <> control <> Nil{}:
      arguments.pose(name,U32.read(n),U32.read(q),U32.read(seed),route,control)
    case _ <> "camera" <> x <> y <> z <> a <> b <> c <> Nil{}:
      do IO<Unit>:
        result : String <- F.camera(vec(x,y,z),vec(a,b,c))
        IO.print(result)
    case _ <> "center" <> x <> y <> z <> yaw <> pitch <> Nil{}:
      do IO<Unit>:
        result : String <- F.center(vec(x,y,z),real(yaw),real(pitch))
        IO.print(result)
    case _ <> "ray" <> x <> y <> z <> a <> b <> c <> Nil{}:
      do IO<Unit>:
        result : String <- F.ray_to(vec(x,y,z),vec(a,b,c))
        IO.print(result)
    case _: IO.die(Unit,2,"unsupported schedule command")
