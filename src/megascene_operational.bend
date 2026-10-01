import Base
import ./megascene_scale.bend as Scale

type Request is Data:
  Request{q: U32, owners: U32, cells: U32, surface: U32, vertices: U32,
    frames: U32, budget: U32, width: Scale.Integer, height: Scale.Integer, now: Scale.Integer}

type Value is Data:
  Value{name: String, magnitude: Scale.Integer}

type History is Data:
  History{created: Scale.Integer, removed: Scale.Integer, actions: Scale.Integer}

def require(-A: Data, ok: Bool, message: String, value: A) -> Result<&2,&2,String,A>:
  match ok:
    case True{}: Done{value}
    case False{}: Fail{message}

def natural.result(value: Maybe<&2,Scale.Integer>, message: String) -> Result<&2,&2,String,Scale.Integer>:
  match value:
    case None{}: Fail{message}
    case Some{n}: Done{n}

def natural(text: String, message: String) -> Result<&2,&2,String,Scale.Integer>:
  natural.result(Scale.Integer.read(text),message)

def envelope.message(label: String) -> String:
  "unsupported " ++ label ++ ": exceeds checked U32/native size envelope"

def u32.limit() -> Scale.Integer:
  Scale.Integer.from_u32(32n,4294967295)

def narrow.valid(n: Scale.Integer, message: String, valid: Bool) -> Result<&2,&2,String,U32>:
  match valid:
    case True{}: Done{Scale.Integer.to_u32(n)}
    case False{}: Fail{message}

def narrow(+n: Scale.Integer, message: String) -> Result<&2,&2,String,U32>:
  narrow.valid(n,message,Scale.Integer.le(n,u32.limit()))

def counter(text: String, +label: String) -> Result<&2,&2,String,U32>:
  do Result<&2,&2,String,U32>:
    n : Scale.Integer <- natural(text,envelope.message(label))
    narrow(n,envelope.message(label))

def scalar(+n: U32) -> Scale.Integer:
  Scale.Integer.from_u32(32n,n)

def values(+request: Request) -> List<&2,Value>:
  Request{+q,+owners,+cells,+surface,+vertices,+frames,+budget,+width,+height,_} = request
  o = scalar(owners)
  [ Value{"neighborhoods",scalar((q * q : U32))},
    Value{"initial_owners",scalar(owners)},
    Value{"source_cells",scalar(cells)},
    Value{"source_surface_bound",scalar(surface)},
    Value{"source_vertices",scalar(vertices)},
    Value{"frames_including_startup",scalar(frames)},
    Value{"fragment_budget",scalar(budget)},
    Value{"initial_next_id",Scale.Integer.inc(scalar(owners))},
    Value{"live_body_upper_bound",Scale.Integer.add(scalar(owners),scalar(budget))},
    Value{"initial_native_geometry_bytes_bound",Scale.Integer.mul(
      Scale.Integer.add(Scale.Integer.add(scalar(vertices),Scale.Integer.mul(o,scalar(36))),scalar(50000)),scalar(128))},
    Value{"maximum_edit_vertex_count",Scale.Integer.mul(scalar(cells),scalar(36))},
    Value{"framebuffer_byte_bound",Scale.Integer.mul(Scale.Integer.mul(width,height),scalar(16))},
    Value{"shadow_byte_bound",scalar(16777216)},
    Value{"frame_counter_upper_bound",Scale.Integer.inc(scalar(frames))} ]

def fields(xs: List<&2,Value>) -> Result<&2,&2,String,String>:
  match xs:
    case Nil{}: Done{""}
    case Value{+name,n} <> rest:
      do Result<&2,&2,String,String>:
        value : U32 <- narrow(n,envelope.message(name))
        tail : String <- fields(rest)
        return "\"" ++ name ++ "\":\"" ++ U32.show(value) ++ "\"," ++ tail

def clock.limit() -> Scale.Integer:
  Scale.Integer.add(Scale.Integer.mul(u32.limit(),scalar(4294967295)),
    Scale.Integer.mul(u32.limit(),scalar(2)))

def clock.deadline(+now: Scale.Integer, +frames: U32) -> Result<&2,&2,String,Scale.Integer>:
  +deadline = Scale.Integer.add(now,Scale.Integer.mul(scalar(300),scalar(1000000000)))
  last = Scale.Integer.add(deadline,Scale.Integer.mul(scalar(frames),scalar(1000000000)))
  require(Scale.Integer,Scale.Integer.le(last,clock.limit()),"unsupported monotonic clock arithmetic",deadline)

def report(+request: Request) -> Result<&2,&2,String,String>:
  Request{+q,_,_,_,_,+frames,_,+width,+height,+now} = request
  +extent = (160 * q : U32)
  do Result<&2,&2,String,String>:
    fields : String <- fields(values(request))
    _ : Unit <- require(Unit,((extent <= 800) && (2 * extent <= 8388608) : U32),
      "unsupported spatial split/coordinate envelope",Unit{})
    _ : Unit <- require(Unit,(Scale.Integer.eq(width,scalar(640)) && Scale.Integer.eq(height,scalar(360))) ||
      (Scale.Integer.eq(width,scalar(1920)) && Scale.Integer.eq(height,scalar(1080))),
      "unsupported native framebuffer resolution",Unit{})
    deadline : Scale.Integer <- clock.deadline(now,frames)
    return "{" ++ fields ++ "\"signed_cell_extent\":\"" ++ U32.show(extent) ++
      "\",\"maximum_split_sum\":\"" ++ U32.show((2 * extent : U32)) ++
      "\",\"monotonic_admission_ns\":\"" ++ Scale.Integer.show(now) ++
      "\",\"monotonic_deadline_upper_ns\":\"" ++ Scale.Integer.show(deadline) ++
      "\",\"scope\":\"q=2..5 source/frame representation; actual edits and native allocation have evolving guards; not a physical capacity ceiling\"}"

def request(q: String, owners: String, cells: String, surface: String, vertices: String,
    frames: String, budget: String, width: String, height: String, now: String) -> Result<&2,&2,String,String>:
  do Result<&2,&2,String,String>:
    scale : Scale.Integer <- natural(q,"square neighborhood scale unsupported: supported q=2..5; no physical capacity claim")
    +q : U32 <- narrow(scale,"square neighborhood scale unsupported: supported q=2..5; no physical capacity claim")
    _ : Unit <- require(Unit,((q >= 2) && (q <= 5) : U32),
      "square neighborhood scale unsupported: supported q=2..5; no physical capacity claim",Unit{})
    owners : U32 <- counter(owners,"initial_owners")
    cells : U32 <- counter(cells,"source_cells")
    surface : U32 <- counter(surface,"source_surface_bound")
    vertices : U32 <- counter(vertices,"source_vertices")
    frames : U32 <- counter(frames,"frames_including_startup")
    budget : U32 <- counter(budget,"fragment_budget")
    width : Scale.Integer <- natural(width,envelope.message("framebuffer_byte_bound"))
    height : Scale.Integer <- natural(height,envelope.message("framebuffer_byte_bound"))
    now : Scale.Integer <- natural(now,"unsupported monotonic clock arithmetic")
    report(Request{q,owners,cells,surface,vertices,frames,budget,width,height,now})

def native(owners: String, vertices: String) -> Result<&2,&2,String,String>:
  do Result<&2,&2,String,String>:
    owners : Scale.Integer <- natural(owners,"static render vertices: unsigned integer exceeds supported range")
    vertices : Scale.Integer <- natural(vertices,"static render vertices: unsigned integer exceeds supported range")
    +count : U32 <- narrow(Scale.Integer.add(Scale.Integer.add(vertices,
      Scale.Integer.mul(owners,scalar(36))),scalar(50006)),
      "static render vertices: unsigned integer exceeds supported range")
    bytes : U32 <- narrow(Scale.Integer.mul(scalar(count),scalar(128)),
      "static native arena capacity: unsigned integer exceeds supported range")
    return U32.show(bytes)

def history.actions(xs: List<String>, created: Scale.Integer, removed: Scale.Integer,
    actions: Scale.Integer) -> Result<&2,&2,String,History>:
  match xs:
    case Nil{}: Done{History{created,removed,actions}}
    case c <> r <> rest:
      do Result<&2,&2,String,History>:
        c : Scale.Integer <- natural(c,"invalid history preflight input")
        r : Scale.Integer <- natural(r,"invalid history preflight input")
        history.actions(rest,Scale.Integer.add(created,c),Scale.Integer.add(removed,r),Scale.Integer.inc(actions))
    case _: Fail{"invalid history preflight input"}

def history.report(+owners: Scale.Integer, +cells: Scale.Integer, budget: Scale.Integer,
    totals: History) -> Result<&2,&2,String,String>:
  History{created,+removed,+actions} = totals
  +bodies = Scale.Integer.add(owners,created)
  do Result<&2,&2,String,String>:
    next_id : U32 <- narrow(Scale.Integer.inc(bodies),"history lifetime next ID: unsigned integer exceeds supported range")
    _ : Unit <- require(Unit,Scale.Integer.le(actions,bodies),
      "history live bodies: unsigned integer exceeds supported range",Unit{})
    +live : U32 <- narrow(Scale.Integer.sub(bodies,actions),"history live bodies: unsigned integer exceeds supported range")
    _ : Unit <- require(Unit,Scale.Integer.le(scalar(live),Scale.Integer.add(owners,budget)),
      "history fragment budget preflight",Unit{})
    _ : Unit <- require(Unit,Scale.Integer.le(removed,cells),"history removed cells exceed source population",Unit{})
    return "{\"accepted_actions\":\"" ++ Scale.Integer.show(actions) ++
      "\",\"planned_removed_cells\":\"" ++ Scale.Integer.show(removed) ++
      "\",\"planned_final_cells\":\"" ++ Scale.Integer.show(Scale.Integer.sub(cells,removed)) ++
      "\",\"planned_lifetime_next_id\":\"" ++ U32.show(next_id) ++
      "\",\"planned_final_live_bodies\":\"" ++ U32.show(live) ++
      "\",\"scope\":\"independent sparse preflight; each actual edit is re-guarded before unsafe code\"}"

def history(owners: String, cells: String, budget: String, actions: List<String>) -> Result<&2,&2,String,String>:
  do Result<&2,&2,String,String>:
    owners : Scale.Integer <- natural(owners,"invalid history preflight input")
    cells : Scale.Integer <- natural(cells,"invalid history preflight input")
    budget : Scale.Integer <- natural(budget,"invalid history preflight input")
    totals : History <- history.actions(actions,Scale.Integer.zero(),Scale.Integer.zero(),Scale.Integer.zero())
    history.report(owners,cells,budget,totals)

def emit(result: Result<&2,&2,String,String>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{text}: IO.print(text)

def args.operational(q: String, xs: List<String>) -> IO(Unit):
  match xs:
    case owners <> cells <> surface <> vertices <> frames <> budget <> width <> height <> now <> Nil{}:
      emit(request(q,owners,cells,surface,vertices,frames,budget,width,height,now))
    case _: IO.die(Unit,2,"usage: megascene-operational Q OWNERS CELLS SURFACE VERTICES FRAMES BUDGET WIDTH HEIGHT MONOTONIC_NS")

def args.history(selected: Bool, q: String, xs: List<String>) -> IO(Unit):
  match selected:
    case False{}: args.operational(q,xs)
    case True{}:
      match xs:
        case owners <> cells <> budget <> actions: emit(history(owners,cells,budget,actions))
        case _: IO.die(Unit,2,"usage: megascene-operational history OWNERS CELLS BUDGET ACTION_PAIRS")

def args.native(selected: Bool, +q: String, xs: List<String>) -> IO(Unit):
  match selected:
    case False{}: args.history(String.eq(q,"history"),q,xs)
    case True{}:
      match xs:
        case owners <> vertices <> Nil{}: emit(native(owners,vertices))
        case _: IO.die(Unit,2,"usage: megascene-operational native OWNERS VERTICES")

def args(xs: List<String>) -> IO(Unit):
  match xs:
    case _ <> +q <> rest: args.native(String.eq(q,"native"),q,rest)
    case _: IO.die(Unit,2,"missing operational admission arguments")

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<String> <- IO.args()
    args(xs)
