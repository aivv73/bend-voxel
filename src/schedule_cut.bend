import Base
import ./schedule_route.bend as Route
import ./schedule_float.bend as F
import ./schedule_json.bend as J

def lift(control: String) -> U32:
  match control:
    case "fill": 8
    case _: 0

def center.delta(eye: F.Vec,d: F.Vec) -> IO(String):
  F.Vec{+x,y,+z} = d
  F.center(eye,F.Round32{F.Atan2{x,z}},F.Round32{F.Atan2{y,F.Hypot{x,z}}})

def center(p: Route.Pose) -> IO(String):
  Route.Pose{+eye,look} = p
  center.delta(eye,F.delta(eye,look))

def frames(n: Nat,+index: U32,+opening: String,+view: String,+cuts: U32,+spacing: U32,+moving: Bool) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+rest:
      +edit = (index >= 121 : U32) && (index < (121 + cuts * spacing : U32) : U32) &&
        U32.is_eq(((index - 121) % spacing : U32),0)
      motion = moving && (index >= 152 : U32) && (index <= 163 : U32)
      actions = Route.select(String,edit,J.array([J.number(((index - 121) / spacing : U32))]),"[]")
      camera = Route.select(String,(index <= 120 : U32),opening,view)
      do IO<Unit>:
        IO.print(Route.frame(index,120,Route.frame.phase(index,120,edit,motion),camera,False{},actions,Nil{}))
        frames(rest,(index + 1 : U32),opening,view,cuts,spacing,moving)

def localized.pose(+origin: String,control: String) -> Route.Pose:
  +x = Route.select(String,String.eq(control,"material-detail"),"161","160")
  +offset = Route.vec(origin,"0",origin)
  Route.Pose{Route.meters(Route.vec(x,"44","170"),offset),Route.meters(Route.vec(x,"24","160"),offset)}

def localized.action(+point: F.Vec,+view: Route.Pose) -> IO(Unit):
  Route.Pose{eye,_} = view
  do IO<Unit>:
    target : String <- F.vector(point)
    ray : String <- center(view)
    exact : String <- F.exact.vector(eye)
    IO.print(J.object([J.field("record_type",J.quote("action")),J.field("action",J.number(0)),
      J.field("frame",J.number(121)),J.field("measured_ordinal",J.number(0)),J.field("target_m",target),
      J.field("radius_m",J.quote("0x3e4ccccd")),J.field("required","true"),
      J.field("expected_owner",J.number(1)),J.field("expected_material",J.number(2)),
      J.field("pre_edit_ray",ray),J.field("_eye",exact)]))

def localized(+q: U32,+seed: U32,+origin: String,+control: String,id: String) -> IO(Unit):
  +p = localized.pose(origin,control)
  point = Route.meters(Route.vec("160","24","160"),Route.vec(origin,"0",origin))
  reviews = {[J.review("opening",0,Route.features("opening")),
    J.review("cut",121,[J.quote("localized terrain hole"),J.quote("new exposed cut surfaces"),J.quote("unchanged nearby terrain")]),
    J.review("completion",3720,[J.quote("unchanged cut geometry"),J.quote("new exposed cut surfaces")])] : List<&2,String>}
  points = Route.append(Route.initial.points(120),[J.point("action_0",121),J.point("completion",3720)])
  do IO<Unit>:
    +opening : String <- Route.pose.camera(Route.pose("opening",0,q,seed,"traversal-v2","base"))
    +view : String <- Route.pose.camera(p)
    IO.print(Route.header(id,120,3600,opening,reviews,points,True{},Nil{}))
    localized.action(point,p)
    frames(3721n,0,opening,view,1,1,False{})

def support.eye(+origin: String,+height: U32) -> F.Vec:
  F.Vec{F.Div{F.Add{Route.real("160"),Route.real(origin)},Route.real("10")},
    F.Add{Route.real("18.0"),F.Div{Route.num(height),Route.real("10")}},
    F.Div{F.Add{Route.real("300"),Route.real(origin)},Route.real("10")}}

def support.look(+origin: String,height: U32) -> F.Vec:
  F.Vec{F.Div{F.Add{Route.real("76"),Route.real(origin)},Route.real("10")},
    F.Add{Route.real("5.5"),F.Div{Route.num(height),Route.real("10")}},
    F.Div{F.Add{Route.real("204"),Route.real(origin)},Route.real("10")}}

def support.target(+origin: String,height: U32,+action: U32) -> F.Vec:
  x = Route.select(String,U32.is_eq((action % 2 : U32),0),"25","127")
  Route.meters(F.Vec{Route.real(x),Route.num((40 + height : U32)),
    Route.num((180 + 24 * (action / 2 : U32) : U32))},Route.vec(origin,"0",origin))

def support.visibility(+origin: String,+seed: U32,height: U32,action: U32) -> F.Vec:
  Route.meters(F.Vec{Route.real("76"),Route.num((76 + seed - 45 + height : U32)),
    Route.num((180 + 24 * (action / 2 : U32) : U32))},Route.vec(origin,"0",origin))

def support.detail.camera(point: F.Vec,height: U32) -> IO(String):
  F.Vec{+x,+y,+z} = point
  look = {F.Vec{F.Round32{x},F.Round32{y},F.Round32{z}} : F.Vec}
  eye = {F.Vec{F.Round32{x},F.Add{Route.real("4.0"),F.Div{Route.num(height),Route.real("10")}},
    F.Add{F.Round32{z},Route.real("1.2")}} : F.Vec}
  F.camera(eye,look)

def support.details(n: Nat,+action: U32,+origin: String,+height: U32) -> IO(List<&2,String>):
  match n:
    case 0n: IO.pure(List<&2,String>,Nil{})
    case 1n+rest:
      do IO<List<&2,String>>:
        view : String <- support.detail.camera(support.target(origin,height,action),height)
        remaining : List<&2,String> <- support.details(rest,(action + 1 : U32),origin,height)
        detail : String = J.object([J.field("name",J.quote("detail_" ++ U32.show(action))),
          J.field("frame",J.number((121 + 6 * action : U32))),J.field("action",J.number(action)),
          J.field("camera",view),J.field("features",J.array([J.quote("support cut and exposed surfaces"),J.quote("anchored stump")])),
          J.field("supplementary_to",J.quote("cut_" ++ U32.show(action)))])
        return detail <> remaining

def support.points(n: Nat,+action: U32) -> List<&2,String>:
  match n:
    case 0n: Nil{}
    case 1n+rest: J.point("action_" ++ U32.show(action),(121 + 6 * action : U32)) <> support.points(rest,(action + 1 : U32))

def support.motion.points(n: Nat,+frame: U32) -> List<&2,String>:
  match n:
    case 0n: [J.point("completion",3720)]
    case 1n+rest: J.point("motion_" ++ U32.show((frame - 121 : U32)),frame) <> support.motion.points(rest,(frame + 1 : U32))

def support.cut.reviews(n: Nat,+action: U32) -> List<&2,String>:
  match n:
    case 0n: Nil{}
    case 1n+rest:
      feature = Route.select(String,U32.is_eq((action % 2 : U32),0),"supported span","released span")
      J.review("cut_" ++ U32.show(action),(121 + 6 * action : U32),
        [J.quote("support cut and exposed surfaces"),J.quote("anchored stump"),J.quote(feature)]) <>
        support.cut.reviews(rest,(action + 1 : U32))

def support.uncut.reviews(n: Nat,+action: U32) -> List<&2,String>:
  match n:
    case 0n: Nil{}
    case 1n+rest:
      J.review("uncut_visit_" ++ U32.show(action),(121 + 6 * action : U32),
        [J.quote("no support cut at this overview visit"),J.quote("later span remains supported")]) <>
        support.uncut.reviews(rest,(action + 1 : U32))

def support.beam.features(n: Nat,+span: U32) -> List<&2,String>:
  match n:
    case 0n: [J.quote("moving body shadows")]
    case 1n+rest: J.quote("beam_" ++ U32.show(span) ++ "_top_center") <> support.beam.features(rest,(span + 1 : U32))

def support.reviews(+spans: U32,+cuts: U32) -> List<&2,String>:
  +plural = Route.select(String,U32.is_eq(spans,1),"","s")
  +motion = {J.quote(Route.select(String,U32.is_eq(spans,3),"three distinct released spans",
    U32.show(spans) ++ " distinct released span" ++ plural)) <> support.beam.features(U32.to_nat(spans),0) : List<&2,String>}
  completion = Route.select(List<&2,String>,U32.is_eq(spans,3),[J.quote("settled spans"),J.quote("protected anchored stumps")],
    [J.quote(U32.show(spans) ++ " settled released span" ++ plural),J.quote("unsevered later spans"),J.quote("protected anchored stumps")])
  Route.append(J.review("opening",0,Route.features("opening")) <> support.cut.reviews(U32.to_nat(cuts),0),
    Route.append(support.uncut.reviews(U32.to_nat((6 - cuts : U32)),cuts),
      [J.review("motion_31",152,motion),J.review("motion_42",163,motion),J.review("completion",3720,completion)]))

def support.variant(+spans: U32,+cuts: U32) -> List<&2,String>:
  variant = J.object([J.field("baseline_schedule_id",J.quote("support-v1")),J.field("required_actions",J.number(cuts)),
    J.field("omitted_actions",J.object([J.field("first",J.number(cuts)),J.field("last",J.number(5)),J.field("count",J.number((6 - cuts : U32)))])),
    J.field("omitted_action_disposition",J.quote("not_required_for_variant")),
    J.field("overview",J.quote("support_v1_all_3600_measured_frames")),J.field("baseline_completion_equivalence","false")])
  Route.select(List<&2,String>,(spans < 3 : U32),[J.field("variant",variant)],Nil{})

def signed.cell(+q: U32,+local: U32) -> String:
  +magnitude = (160 * q : U32)
  Route.select(String,(magnitude > local : U32),"-" ++ U32.show((magnitude - local : U32)),U32.show((local - magnitude : U32)))

def support.beams(n: Nat,+span: U32,+q: U32,+height: U32,+seed: U32) -> List<&2,String>:
  match n:
    case 0n: Nil{}
    case 1n+rest:
      J.object([J.field("span",J.number(span)),J.field("source_owner",J.number((span + 3 : U32))),
        J.field("local_top_center_cells",J.array([J.quote(signed.cell(q,76)),J.number((76 + seed - 45 + height : U32)),
          J.quote(signed.cell(q,(180 + 24 * span : U32)))]))]) <> support.beams(rest,(span + 1 : U32),q,height,seed)

def support.actions(n: Nat,+action: U32,+origin: String,+height: U32,+seed: U32,+eye: F.Vec) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+rest:
      +visible = support.visibility(origin,seed,height,action)
      do IO<Unit>:
        target : String <- F.vector(support.target(origin,height,action))
        visibility : String <- F.vector(visible)
        ray : String <- F.ray_to(eye,visible)
        exact : String <- F.exact.vector(eye)
        IO.print(J.object([J.field("record_type",J.quote("action")),J.field("action",J.number(action)),
          J.field("frame",J.number((121 + 6 * action : U32))),J.field("measured_ordinal",J.number((6 * action : U32))),
          J.field("span",J.number((action / 2 : U32))),J.field("target_m",target),J.field("radius_m",J.quote("0x3e4ccccd")),
          J.field("required","true"),J.field("expected_material",J.number(3)),J.field("source_owner",J.number((3 + (action / 2 : U32) : U32))),
          J.field("visibility_point_m",visibility),J.field("pre_edit_ray",ray),J.field("_eye",exact)]))
        support.actions(rest,(action + 1 : U32),origin,height,seed,eye)

def support(+q: U32,+seed: U32,+origin: String,+control: String,id: String,+spans: U32) -> IO(Unit):
  +height = lift(control)
  +cuts = (2 * spans : U32)
  +eye = support.eye(origin,height)
  points = Route.append(Route.initial.points(120),Route.append(support.points(U32.to_nat(cuts),0),support.motion.points(12n,152)))
  window = J.object([J.field("first",J.number(152)),J.field("last",J.number(163)),
    J.field("measured_first",J.number(31)),J.field("measured_last",J.number(42)),J.field("distinct_spans",J.number(spans))])
  do IO<Unit>:
    +opening : String <- Route.pose.camera(Route.pose("opening",0,q,seed,"traversal-v2",control))
    +view : String <- F.camera(eye,support.look(origin,height))
    exact : String <- F.exact.vector(eye)
    details : List<&2,String> <- support.details(U32.to_nat(cuts),0,origin,height)
    beams : List<&2,String> = support.beams(U32.to_nat(spans),0,q,height,seed)
    extra : List<&2,String> = Route.append([J.field("beam_features",J.array(beams)),J.field("released_bottom_cells",J.number((42 + height : U32))),
      J.field("moving_window",window),J.field("supplementary_views",J.array(details)),J.field("_eye",exact)],support.variant(spans,cuts))
    IO.print(Route.header(id,120,3600,opening,support.reviews(spans,cuts),points,True{},extra))
    support.actions(U32.to_nat(cuts),0,origin,height,seed,eye)
    frames(3721n,0,opening,view,cuts,6,True{})
def spans(id: String) -> U32:
  match id:
    case "support-1-span-v1": 1
    case "support-2-span-v1": 2
    case _: 3
