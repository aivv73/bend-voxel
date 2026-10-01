import Base
import ./schedule_route.bend as R
import ./schedule_float.bend as F
import ./schedule_json.bend as J
import ./megascene_scale.bend as Scale

type Visit is Data:
  Visit{neighborhood: U32, prior: U32, kind: U32, variation: U32, local: F.Vec, target: F.Vec, eye: F.Vec}
type Track is Data:
  Track{eyes: List<&2,F.Vec>, targets: List<&2,F.Vec>, cameras: List<&2,String>, actions: List<&2,String>}

def cut.frame(+k: U32,+performance: Bool) -> U32:
  offset = R.select(U32,U32.is_eq((k % 10 : U32),5),732,((k % 10 : U32) * 180 : U32))
  R.select(U32,performance,(121 + (k / 10 : U32) * 1800 + offset : U32),(121 + k * 12 : U32))
def local(+a: U32,+r: U32,+v: U32,+control: String) -> F.Vec:
  match a:
    case 0: F.Vec{R.num((160 + 12 * r : U32)),R.real("24"),R.num((160 + 8 * r : U32))}
    case 1: F.Vec{R.real("18"),R.real("48"),R.num((48 + 12 * r : U32))}
    case 2: F.Vec{R.real("25"),R.real("40"),R.num((180 + 24 * r : U32))}
    case 3: F.Vec{R.num((163 + 12 * r : U32)),R.real("24"),R.num((160 + 8 * r : U32))}
    case 4: F.Vec{R.real("127"),R.real("40"),R.num((180 + 24 * r : U32))}
    case 5: F.Vec{R.real("76"),R.num((74 + v : U32)),R.num((180 + 24 * r : U32))}
    case 6:
      F.Vec{R.select(F.Expr,String.eq(control,"body-rich"),R.num((40 + 3 * r : U32)),R.real("78")),R.real("48"),R.select(F.Expr,String.eq(control,"body-rich"),R.real("134"),R.num((54 + 3 * r : U32)))}
    case 7: F.Vec{R.num((284 + 3 * r : U32)),R.num((58 + (v % 2 : U32) : U32)),R.num((180 + 3 * r : U32))}
    case 8: F.Vec{R.num(R.select(U32,U32.is_eq(r,0),236,R.select(U32,U32.is_eq(r,1),230,226))),R.real("23"),R.real("272")}
    case _: F.Vec{R.num(R.select(U32,U32.is_eq(r,0),276,R.select(U32,U32.is_eq(r,1),282,286))),R.real("23"),R.real("272")}
def shifted(v: F.Vec,+lift: U32) -> F.Vec:
  F.Vec{x,y,z} = v
  F.Vec{x,F.Add{y,R.num(lift)},z}
def rounded(v: F.Vec) -> F.Vec:
  F.Vec{x,y,z} = v
  F.Vec{F.Round32{x},F.Round32{y},F.Round32{z}}
def motion(n: Nat,+offset: F.Expr,+speed: F.Expr) -> IO(F.Expr):
  match n:
    case 0n: IO.pure(F.Expr,offset)
    case 1n+p:
      +dt = {F.Round32{F.Div{R.real("1"),R.real("60")}} : F.Expr}
      do IO<F.Expr>:
        y : String <- F.evaluate(F.Round32{F.Sub{F.Round32{F.Add{offset,F.Round32{F.Mul{speed,dt}}}},F.Round32{F.Mul{F.Round32{F.Mul{F.Round32{R.real("4.905")},dt}},dt}}}})
        velocity : String <- F.evaluate(F.Round32{F.Sub{speed,F.Round32{F.Mul{F.Round32{R.real("9.81")},dt}}}})
        motion(p,R.real(y),R.real(velocity))
def beam.target(v: F.Vec,o: F.Vec,offset: F.Expr) -> F.Vec:
  F.Vec{x,y,z} = v
  F.Vec{ox,oy,oz} = o
  +tenth = {F.Round32{R.real("0.1")} : F.Expr}
  F.Vec{F.Round32{F.Mul{F.Add{x,ox},tenth}},F.Round32{F.Add{F.Round32{F.Mul{F.Add{y,oy},tenth}},offset}},F.Round32{F.Mul{F.Add{z,oz},tenth}}}
def eye.values(a: U32,+r: U32,+v: U32,+x: F.Expr,+y: F.Expr,+z: F.Expr,+ox: F.Expr,+oz: F.Expr,+control: String,+lift: F.Expr) -> F.Vec:
  match a:
    case 0: F.Vec{x,F.Add{y,R.real("2")},F.Add{z,R.real("1")}}
    case 3: F.Vec{x,F.Add{y,R.real("2")},F.Add{z,R.real("1")}}
    case 1: F.Vec{F.Div{F.Add{R.real("8"),ox},R.real("10")},F.Add{R.real("4.8"),lift},z}
    case 2: F.Vec{x,F.Add{R.real("4"),lift},F.Div{F.Add{R.num((192 + 24 * r : U32)),oz},R.real("10")}}
    case 4: F.Vec{x,F.Add{R.real("4"),lift},F.Div{F.Add{R.num((192 + 24 * r : U32)),oz},R.real("10")}}
    case 5: F.Vec{x,F.Add{y,R.real("2")},F.Add{z,R.real("1.2")}}
    case 6: F.Vec{F.Div{F.Add{R.select(F.Expr,String.eq(control,"body-rich"),R.num((40 + 3 * r : U32)),R.real("100")),ox},R.real("10")},F.Add{R.real("4.8"),lift},R.select(F.Expr,String.eq(control,"body-rich"),F.Div{F.Add{R.real("120"),oz},R.real("10")},z)}
    case 7: F.Vec{x,F.Add{F.Div{R.num((90 + (v % 2 : U32) : U32)),R.real("10")},lift},F.Sub{z,R.real("2")}}
    case _: F.Vec{x,F.Add{R.real("4.4"),lift},F.Div{F.Add{R.real("256"),oz},R.real("10")}}
def overview(performance: Bool) -> U32: R.select(U32,performance,21661,1681)
def mapping.record(mapping: Scale.Integer & U32,+group: U32) -> String:
  (neighborhood,prior) = mapping
  J.object([J.field("group",J.number(group)),J.field("neighborhood",J.quote(Scale.Integer.show(neighborhood))),J.field("prior_visits",J.number(prior))])
def groups(n: Nat,+i: U32) -> List<&2,String>:
  match n:
    case 0n: Nil{}
    case 1n+p: J.field("group_" ++ U32.show(i),J.array([J.number((i * 1800 : U32)),J.number(((i + 1) * 1800 - 1 : U32))])) <> groups(p,(i + 1 : U32))
def count(id: String) -> U32:
  match id:
    case "history-12-v1": 12
    case "history-48-v1": 48
    case _: 120
def eye(+a: U32,+r: U32,+v: U32,point: F.Vec,o: F.Vec,+control: String) -> F.Vec:
  F.Vec{+x,+y,+z} = point
  F.Vec{+ox,oy,+oz} = o
  eye.values(a,r,v,x,y,z,ox,oz,control,R.select(F.Expr,String.eq(control,"fill"),R.real("0.8"),R.real("0")))
def visit.emit(v: Visit,+k: U32,+performance: Bool) -> IO(F.Vec & F.Vec & String & String):
  Visit{n,r,a,variation,local,+target,+eye} = v
  +frame = cut.frame(k,performance)
  do IO<F.Vec & F.Vec & String & String>:
    +cam : String <- F.camera(eye,target)
    ray : String <- F.ray_to(eye,target)
    point : String <- F.vector(target)
    exact_eye : String <- F.exact.vector(eye)
    action : String = J.object([J.field("action",J.number(k)),J.field("frame",J.number(frame)),J.field("measured_ordinal",J.number((frame - 121 : U32))),J.field("target_m",point),J.field("radius_m",J.quote("0x3e4ccccd")),J.field("required","true"),J.field("pre_edit_ray",ray),J.field("_eye",exact_eye)])
    return (eye,target,cam,action)
def points(n: Nat,+k: U32,+count: U32,+performance: Bool) -> List<&2,String>:
  match n:
    case 0n: Nil{}
    case 1n+p: J.point("action_" ++ U32.show(k),cut.frame(k,performance)) <> points(p,(k + 1 : U32),count,performance)
def reviews(n: Nat,+k: U32,+count: U32,+performance: Bool,+control: String) -> List<&2,String>:
  match n:
    case 0n: Nil{}
    case 1n+p:
      +cut = (k < count : U32)
      id = R.select(String,cut,"cut_","uncut_visit_") ++ U32.show(k)
      features = R.select(List<&2,String>,cut,R.select(List<&2,String>,String.eq(control,"body-rich") && U32.is_eq((k % 10 : U32),6),[J.quote("remaining back wall"),J.quote("new exposed back-wall surfaces")],[J.quote("removed material"),J.quote("new exposed surfaces")]),[J.quote("no new cut at this camera visit"),J.quote("remaining material at later target")])
      J.review(id,cut.frame(k,performance),features) <> reviews(p,(k + 1 : U32),count,performance,control)
def cut.index(n: Nat,+k: U32,+i: U32,+count: U32,+performance: Bool) -> U32:
  match n:
    case 0n: count
    case 1n+p: R.select(U32,U32.is_eq(i,cut.frame(k,performance)),k,cut.index(p,(k + 1 : U32),i,count,performance))
def phase.index(n: Nat,+k: U32,+i: U32,+performance: Bool) -> U32:
  match n:
    case 0n: 0
    case 1n+p: (Bool.to_u32((i >= cut.frame(k,performance) : U32)) + phase.index(p,(k + 1 : U32),i,performance) : U32)
def named(+count: U32,+performance: Bool) -> List<&2,String>:
  append12 = {[J.point("after_cut_12",cut.frame(11,performance))] : List<&2,String>}
  append48 = R.select(List<&2,String>,(count >= 48 : U32),[J.point("after_cut_48",cut.frame(47,performance))],Nil{})
  append120 = R.select(List<&2,String>,U32.is_eq(count,120),[J.point("after_cut_120",cut.frame(119,performance))],Nil{})
  R.append(append12,R.append(append48,append120))
def mapping(n: Nat,+i: U32,+q: U32,+seed: U32) -> List<&2,String>:
  match n:
    case 0n: Nil{}
    case 1n+p: mapping.record(Scale.history_visit(i,Scale.Integer.from_u32(32n,(q * q : U32)),seed),i) <> mapping(p,(i + 1 : U32),q,seed)
def populations(+count: U32,performance: Bool) -> String:
  match performance:
    case True{}: J.object(R.append(groups(12n,0),[J.field("overview",J.array([J.number((cut.frame(119,True{}) - 120 : U32)),J.number((overview(True{}) - 121 : U32))])),J.field("settled_suffix",J.array([J.number((overview(True{}) - 120 : U32)),J.number(21599)]))]))
    case False{}:
      fields = R.append([J.field("cuts_1_12",J.array([J.number(0),J.number(143)]))],R.append(R.select(List<&2,String>,(count >= 48 : U32),[J.field("cuts_13_48",J.array([J.number(144),J.number(575)]))],Nil{}),R.append(R.select(List<&2,String>,U32.is_eq(count,120),[J.field("cuts_49_120",J.array([J.number(576),J.number(1439)]))],[J.field("post_prefix",J.array([J.number((count * 12 : U32)),J.number(1439)]))]),[J.field("overview",J.array([J.number(1440),J.number(1559)])),J.field("tail",J.array([J.number(1560),J.number(3599)]))])))
      J.object(fields)
def visits.prepend(first: F.Vec & F.Vec & String & String,rest: Track) -> Track:
  (eye,target,cam,action) = first
  Track{eyes,targets,cams,actions} = rest
  Track{rounded(eye) <> eyes,target <> targets,cam <> cams,action <> actions}
def visit.target(+n: U32,+prior: U32,+a: U32,+v: U32,+local: F.Vec,+o: F.Vec,+control: String,moving: Bool) -> IO(Visit):
  match moving:
    case True{}:
      do IO<Visit>:
        offset : F.Expr <- motion(12n,R.real("0"),R.real("0"))
        +target : F.Vec = beam.target(local,o,offset)
        return Visit{n,prior,a,v,local,target,eye(a,prior,v,target,o,control)}
    case False{}:
      +target = rounded(R.meters(local,o))
      IO.pure(Visit,Visit{n,prior,a,v,local,target,eye(a,prior,v,target,o,control)})
def chosen.flags(warm: Bool,visit: Bool,transition: Bool,+i: U32,+performance: Bool,+eyes: List<&2,F.Vec>,+targets: List<&2,F.Vec>,+cams: List<&2,String>,far: R.Pose,opening: String) -> IO(String):
  match warm visit transition:
    case True{} _ _: IO.pure(String,opening)
    case _ True{} _:
      index = R.select(U32,performance,(phase.index(120n,0,i,performance) - 1 : U32),U32.min(((i - 121) / 12 : U32),119))
      IO.pure(String,R.string.at(U32.to_nat(index),cams))
    case _ _ True{}:
      +t = {F.Div{R.num((i - cut.frame(119,performance) - R.select(U32,performance,0,11) : U32)),R.real("120")} : F.Expr}
      R.pose.camera(R.interpolate.pose(R.Pose{R.vec.at(119n,eyes),R.vec.at(119n,targets)},far,t))
    case _ _ _: R.pose.camera(far)
def metadata(+q: U32,+seed: U32,+count: U32,+performance: Bool,+id: String,control: String) -> List<&2,String>:
  faces = R.select(List<&2,String>,U32.is_eq(q,2) && U32.is_eq(count,120),[J.number(88),J.number(89),J.number(98),J.number(99),J.number(108),J.number(109),J.number(118),J.number(119)],Nil{})
  base = {[J.field("history_populations",populations(count,performance)),J.field("_history_faces",J.array(faces)),J.field("_diagnostic_interior",J.boolean(String.eq(control,"body-rich")))] : List<&2,String>}
  mapping_fields = R.select(List<&2,String>,String.eq(id,"history-v2"),[J.field("history_neighborhood_mapping",J.object([J.field("version",J.quote("coprime-prior-visits-v1")),J.field("stride",J.quote(Scale.Integer.show(Scale.history_stride(Scale.Integer.from_u32(32n,(q * q : U32)))))),J.field("group_visits",J.array(mapping(12n,0,q,seed)))]))],Nil{})
  variant = R.select(List<&2,String>,(count < 120 : U32),[J.field("variant",J.object([J.field("baseline_schedule_id",J.quote("history-v1")),J.field("required_actions",J.number(count)),J.field("omitted_actions",J.object([J.field("first",J.number(count)),J.field("last",J.number(119)),J.field("count",J.number((120 - count : U32)))])),J.field("omitted_action_disposition",J.quote("not_required_for_variant")),J.field("camera_track",J.quote("full_history_v1_all_3600_measured_frames")),J.field("baseline_completion_equivalence","false")]))],Nil{})
  R.append(base,R.append(mapping_fields,variant))
def header(+q: U32,+seed: U32,+control: String,+id: String,+count: U32,+performance: Bool,opening: String) -> List<&2,String>:
  +end = R.select(U32,performance,21720,3720)
  more_reviews = {[J.review("history_overview",overview(performance),R.select(List<&2,String>,U32.is_eq(count,120),[J.quote("cumulative destruction"),J.quote("remaining anchored material")],[J.quote("destruction after " ++ U32.show(count) ++ " cuts"),J.quote("remaining uncut later targets")])),J.review("completion",end,R.select(List<&2,String>,U32.is_eq(count,120),[J.quote("retained geometry"),J.quote("settled fragments")],[J.quote("retained geometry after " ++ U32.show(count) ++ " cuts"),J.quote("settled fragments"),J.quote("remaining uncut later targets")]))] : List<&2,String>}
  R.header(id,120,R.select(U32,performance,21600,3600),opening,R.append(J.review("opening",0,[J.quote("district and structures")]) <> reviews(120n,0,count,performance,control),more_reviews),R.append(R.initial.points(120),R.append(points(U32.to_nat(count),0,count,performance),R.append(named(count,performance),[J.point("history_overview",overview(performance)),J.point("completion",end)]))),True{},metadata(q,seed,count,performance,id,control))
def visit.mapping(mapping: Scale.Integer & U32,+k: U32,+q: U32,+seed: U32,+control: String) -> IO(Visit):
  (neighborhood,+prior) = mapping
  +n = Scale.Integer.to_u32(neighborhood)
  +a = (k % 10 : U32)
  +v = ((3 * (n % q : U32) + 5 * (n / q : U32) + seed - 45) % 4 : U32)
  +lift = R.select(U32,String.eq(control,"fill"),8,0)
  +l = shifted(local(a,prior,v,control),lift)
  visit.target(n,prior,a,v,l,R.origin(q,n),control,U32.is_eq(a,5))
def chosen(+i: U32,+performance: Bool,+eyes: List<&2,F.Vec>,+targets: List<&2,F.Vec>,+cams: List<&2,String>,+far: R.Pose,opening: String) -> IO(String):
  chosen.flags((i <= 120 : U32),(i <= (cut.frame(119,performance) + R.select(U32,performance,0,11) : U32) : U32),(i <= (overview(performance) - R.select(U32,performance,0,1) : U32) : U32),i,performance,eyes,targets,cams,far,opening)
def visit(+k: U32,+q: U32,+seed: U32,control: String) -> IO(Visit):
  visit.mapping(Scale.history_visit((k / 10 : U32),Scale.Integer.from_u32(32n,(q * q : U32)),seed),k,q,seed,control)
def frames(n: Nat,+i: U32,+count: U32,+performance: Bool,+eyes: List<&2,F.Vec>,+targets: List<&2,F.Vec>,+cams: List<&2,String>,+far: R.Pose,+opening: String) -> IO(List<&2,String>):
  match n:
    case 0n: IO.pure(List<&2,String>,Nil{})
    case 1n+p:
      +action = cut.index(U32.to_nat(count),0,i,count,performance)
      edits = R.select(String,(action < count : U32),J.array([J.number(action)]),"[]")
      do IO<List<&2,String>>:
        cam : String <- chosen(i,performance,eyes,targets,cams,far,opening)
        rest : List<&2,String> <- frames(p,(i + 1 : U32),count,performance,eyes,targets,cams,far,opening)
        return R.frame(i,120,R.frame.phase(i,120,(action < count : U32),False{}),cam,False{},edits,Nil{}) <> rest
def visits(n: Nat,+k: U32,+q: U32,+seed: U32,+control: String,+count: U32,+performance: Bool) -> IO(Track):
  match n:
    case 0n: IO.pure(Track,Track{Nil{},Nil{},Nil{},Nil{}})
    case 1n+p:
      do IO<Track>:
        v : Visit <- visit(k,q,seed,control)
        first : F.Vec & F.Vec & String & String <- visit.emit(v,k,performance)
        rest : Track <- visits(p,(k + 1 : U32),q,seed,control,count,performance)
        return visits.prepend(first,rest)
def history.track(track: Track,+q: U32,+seed: U32,+control: String,+id: String,+count: U32,+performance: Bool,+opening: String) -> IO(Unit):
  Track{eyes,targets,cams,+actions} = track
  fields = R.append(header(q,seed,control,id,count,performance,opening),R.select(List<&2,String>,(count < 120 : U32),[J.field("_reference_actions",J.array(List.drop(&2,String,actions,U32.to_nat(count))))],Nil{}))
  do IO<Unit>:
    rows : List<&2,String> <- frames(U32.to_nat(R.select(U32,performance,21721,3721)),0,count,performance,eyes,targets,cams,R.pose("far",0,q,seed,"traversal-v2",control),opening)
    IO.print(R.document(fields,rows,List.take(&2,String,actions,U32.to_nat(count))))
def history(+q: U32,+seed: U32,+control: String,+id: String,+count: U32,+performance: Bool) -> IO(Unit):
  do IO<Unit>:
    +opening : String <- R.pose.camera(R.pose("opening",0,q,seed,"traversal-v2",control))
    track : Track <- visits(120n,0,q,seed,control,count,performance)
    history.track(track,q,seed,control,id,count,performance,opening)
