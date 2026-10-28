import Base
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/src/core.bend as Core
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W
import ../../main.bend as Controls
import ../../atelier.bend as AtelierBody
import ../../render.bend as R
import ../../voxel.bend as X
import ../../deps/bend-vulkan/examples/window.bend as WSI
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D
import ./mesh.bend as M
import ./chunks.bend as C
import ./flight.bend as F
import ./generation.bend as G
import ./timing.bend as Timing
import ./exterior.bend as Exterior
import ./renderer.bend as GPU
import ./presentation.bend as P
import ./viewport.bend as View
import ./scene.bend as Scene
import ./appearance.bend as A

type Original is Data:
  Cube{}
  Atelier{}
type Pointer is Data:
  Pointer{x: U32, y: U32}

type World is Type:
  World{body: X.Body, mesh: C.ChunkSet, camera: R.Camera, controls: Controls.Controls, revision: U32, original: Original, pointer: Pointer, changed: Bool}
type Session is Type:
  Session{world: World, target: Maybe<&2,P.Target>, fleet: F.Fleet, width: U32, height: U32, mapped: Bool, recreate: Bool, generations: U32}

def built(pair: X.Body & Result<&2,&1,Exterior.Error,C.ChunkSet>) -> V.Action(X.Body & C.ChunkSet):
  (body,result) = pair
  match result:
    case Fail{error}: IO.pure(V.VkResult(X.Body & C.ChunkSet),Fail{(1,Exterior.error_show(error))})
    case Done{mesh}: V.Action.pure(X.Body & C.ChunkSet,(body,mesh))

def original_body(original: Original) -> X.Body:
  match original:
    case Cube{}: X.Body.solid(3n)
    case Atelier{}: AtelierBody.body()

def original_camera(original: Original) -> R.Camera:
  match original:
    case Cube{}: R.Camera.initial()
    case Atelier{}: R.Camera.atelier()

def initial_world(pair: X.Body & C.ChunkSet) -> World:
  (body,mesh) = pair
  World{body,mesh,R.Camera.initial(),Controls.Controls.initial(),0,Cube{},Pointer{320,240},True{}}

def edited_world(pair: X.Body & C.ChunkSet, camera: R.Camera, controls: Controls.Controls, revision: U32, original: Original, pointer: Pointer) -> World:
  (body,mesh) = pair
  World{body,mesh,camera,controls,U32.inc(revision),original,pointer,True{}}

def initial(result: X.Body & Result<&2,&1,Exterior.Error,C.ChunkSet>) -> V.Action(World):
  do V.Action<World>:
    pair : X.Body & C.ChunkSet <- built(result)
    return initial_world(pair)

def edited(result: X.Body & Result<&2,&1,Exterior.Error,C.ChunkSet>, camera: R.Camera, controls: Controls.Controls, revision: U32, original: Original, pointer: Pointer) -> V.Action(World):
  do V.Action<World>:
    pair : X.Body & C.ChunkSet <- built(result)
    return edited_world(pair,camera,controls,revision,original,pointer)

def required_revision(value: Maybe<&2,U32>) -> V.Action(U32):
  match value:
    case Some{revision}: V.Action.pure(U32,revision)
    case None{}: IO.pure(V.VkResult(U32),Fail{(1610612741,"Body revision sequence exhausted")})

def next_revision(current: U32) -> V.Action(U32):
  required_revision(Core.next_revision(current))

def changed(world: World, sphere: X.MetricSphere) -> V.Action(World):
  World{body,mesh,camera,controls,+revision,+original,pointer,old} = world
  do V.Action<World>:
    next : U32 <- next_revision(revision)
    edited(C.cut(body,mesh,sphere,next),camera,controls,revision,original,pointer)

def picked(world: World, hit: Maybe<&2,X.MetricSphere>) -> V.Action(World):
  match hit:
    case None{}: V.Action.pure(World,world)
    case Some{sphere}: changed(world,sphere)

def click(world: World, +view: View.Viewport, +x: U32, +y: U32) -> V.Action(World):
  World{body,mesh,+camera,+controls,revision,+original,pointer,old} = world
  C.ChunkSet{chunks,primitives,+faces,bounds,count,shadow,rebuilt,retained} = mesh
  View.Viewport{+width,+height} = view
  picked(World{body,C.ChunkSet{chunks,primitives,faces,bounds,count,shadow,rebuilt,retained},camera,controls,revision,original,pointer,old},View.target(view,camera,faces,Bool.pick(U32,Controls.Controls.capture(controls),(width / 2 : U32),x),Bool.pick(U32,Controls.Controls.capture(controls),(height / 2 : U32),y)))

def reset(world: World) -> V.Action(World):
  World{body,mesh,camera,controls,+revision,+original,pointer,old} = world
  do V.Action<World>:
    next : U32 <- next_revision(revision)
    edited(C.build(original_body(original),next),camera,controls,revision,original,pointer)

def key(world: World, code: U32, down: Bool) -> World:
  World{body,mesh,camera,controls,+revision,+original,pointer,old} = world
  World{body,mesh,camera,Controls.Controls.key(code,down,controls),revision,original,pointer,old}

def capture(world: World, looking: Bool) -> World:
  World{body,mesh,camera,controls,+revision,+original,pointer,old} = world
  World{body,mesh,camera,Controls.Controls.look(controls,looking),revision,original,pointer,old}

def look_active(active: Bool, world: World, dx: F32, dy: F32) -> World:
  match active world:
    case False{} _: world
    case True{} World{body,mesh,camera,controls,revision,original,pointer,old}:
      World{body,mesh,R.Camera.look(camera,dx,dy),controls,revision,original,pointer,True{}}

def look(world: World, dx: F32, dy: F32) -> World:
  World{body,mesh,camera,+controls,revision,+original,pointer,old} = world
  look_active(Controls.Controls.capture(controls),World{body,mesh,camera,controls,revision,original,pointer,old},dx,dy)

def click_point(world: World, view: View.Viewport, point: U32 & U32) -> V.Action(World):
  (x,y) = point
  click(world,view,x,y)

def mapped_click(world: World, +mapping: View.Mapping, x: U32, y: U32) -> V.Action(World):
  View.Mapping{ww,wh,width,height} = mapping
  click_point(world,View.Viewport{width,height},View.map_point(mapping,x,y))

def pointer(world: World, x: U32, y: U32) -> World:
  World{body,mesh,camera,controls,revision,original,old,changed} = world
  World{body,mesh,camera,controls,revision,original,Pointer{x,y},True{}}

def hover_point(+view: View.Viewport, +camera: R.Camera, faces: List<&2,X.Face>, +captured: Bool, point: U32 & U32) -> Maybe<&2,X.MetricSphere>:
  View.Viewport{+width,+height} = view
  (x,y) = point
  View.target(view,camera,faces,Bool.pick(U32,captured,(width / 2 : U32),x),Bool.pick(U32,captured,(height / 2 : U32),y))

def hover(+view: View.Mapping, camera: R.Camera, controls: Controls.Controls, point: Pointer, faces: List<&2,X.Face>) -> Maybe<&2,X.MetricSphere>:
  View.Mapping{ww,wh,w,h} = view
  Pointer{x,y} = point
  hover_point(View.Viewport{w,h},camera,faces,Controls.Controls.capture(controls),View.map_point(view,x,y))

def space(world: World, +view: View.Mapping) -> V.Action(World):
  match world:
    case World{body,mesh,camera,controls,revision,Cube{},point,dirty}:
      changed(World{body,mesh,camera,controls,revision,Cube{},point,dirty},X.MetricSphere.brush(X.PointCm.cell(X.Cell{6,6,6})))
    case World{body,C.ChunkSet{chunks,primitives,+faces,bounds,count,shadow,rebuilt,retained},+camera,+controls,revision,Atelier{},+point,changed}:
      picked(World{body,C.ChunkSet{chunks,primitives,faces,bounds,count,shadow,rebuilt,retained},camera,controls,revision,Atelier{},point,changed},hover(view,camera,controls,point,faces))

def continued(action: V.Action(World)) -> V.Action(Maybe<World>):
  do V.Action<Maybe<World>>:
    world : World <- action
    return Some{world}

def event(event: Event, world: World, view: View.Mapping) -> V.Action(Maybe<World>):
  match event:
    case Close{}: V.Action.pure(Maybe<World>,None{})
    case Key{27,True{}}: V.Action.pure(Maybe<World>,None{})
    case Key{32,True{}}: continued(space(world,view))
    case Key{114,True{}}: continued(reset(world))
    case Key{82,True{}}: continued(reset(world))
    case Key{code,down}: V.Action.pure(Maybe<World>,Some{key(world,code,down)})
    case Mouse{+x,+y,1,down}: V.Action.pure(Maybe<World>,Some{capture(pointer(world,x,y),down)})
    case Mouse{+x,+y,0,True{}}: continued(mapped_click(pointer(world,x,y),view,x,y))
    case Mouse{+x,+y,button,down}: V.Action.pure(Maybe<World>,Some{pointer(world,x,y)})
    case Move{x,y}: V.Action.pure(Maybe<World>,Some{pointer(world,x,y)})
    case Look{dx,dy}: V.Action.pure(Maybe<World>,Some{look(world,dx,dy)})
    case _: V.Action.pure(Maybe<World>,Some{world})

def events_next(result: Maybe<World>, next: World -> V.Action(Maybe<World>)) -> V.Action(Maybe<World>):
  match result:
    case None{}: V.Action.pure(Maybe<World>,None{})
    case Some{world}: next(world)

def events(xs: List<Event>, world: World, +view: View.Mapping) -> V.Action(Maybe<World>):
  match xs:
    case Nil{}: V.Action.pure(Maybe<World>,Some{world})
    case Con{head,rest}:
      do V.Action<Maybe<World>>:
        result : Maybe<World> <- event(head,world,view)
        events_next(result,next => events(rest,next,view))

def fly(world: World, +elapsed: Nat) -> World:
  World{body,mesh,+camera,+controls,revision,+original,pointer,old} = world
  +next = Controls.Controls.fly(controls,camera,elapsed)
  World{body,mesh,next,controls,revision,original,pointer,old || Bool.not(R.Camera.equal(camera,next))}

def capture_granted(world: World, looking: Bool, actual: Bool) -> World:
  match looking actual:
    case True{} False{}: capture(world,False{})
    case _ _: world

def capture_requested(window: V.NativeWindow, world: World, request: Maybe<&2,Bool>) -> V.Action(World):
  match request:
    case None{}: V.Action.pure(World,world)
    case Some{+looking}:
      do V.Action<World>:
        actual : Bool <- V.NativeWindow.capture(window,looking)
        return capture_granted(world,looking,actual)

def capture_result(window: V.NativeWindow, world: World, result: Controls.Controls & Maybe<&2,Bool>) -> V.Action(World):
  World{body,mesh,camera,old,revision,original,pointer,changed} = world
  (controls,request) = result
  capture_requested(window,World{body,mesh,camera,controls,revision,original,pointer,changed},request)

def capture_apply(window: V.NativeWindow, world: World) -> V.Action(World):
  World{body,mesh,camera,+controls,revision,original,pointer,changed} = world
  capture_result(window,World{body,mesh,camera,controls,revision,original,pointer,changed},Controls.Controls.request(controls))

def device(context: WSI.Context) -> V.Device:
  WSI.Context{window,instance,physical,surface,device,g,p} = context
  device

def window(context: WSI.Context) -> V.NativeWindow:
  WSI.Context{window,instance,physical,surface,device,g,p} = context
  window

def frame_extent(bounds: Maybe<&2,M.Extent>) -> U32:
  match bounds:
    case None{}: 0
    case Some{M.Extent{low,X.Cell{x,y,z}}}: U32.max(x,U32.max(y,z))

def output(+format: U32) -> A.Output:
  Bool.pick(A.Output,U32.is_eq(format,43) || U32.is_eq(format,50),A.Srgb{},A.Unorm{})

def target_swapchain(target: P.Target) -> V.Swapchain:
  P.Target{sc,images,pass,layout,pipeline,w,h,format,programs} = target
  sc

def target_destroy(device: V.Device, target: Maybe<&2,P.Target>) -> V.Action(Unit):
  match target:
    case None{}: V.Action.pure(Unit,Unit{})
    case Some{target}: P.destroy(device,target)

def production_target(device: V.Device, target: P.Target, assets: Scene.Assets, original: Original) -> V.Action(P.Target):
  match original:
    case Cube{}: V.Action.pure(P.Target,target)
    case Atelier{}: P.promote(device,target,assets)

def mapping(target: Maybe<&2,P.Target>, +ww: U32, +wh: U32) -> View.Mapping:
  match target:
    case None{}: View.Mapping{ww,wh,ww,wh}
    case Some{P.Target{sc,images,pass,layout,pipeline,w,h,format,programs}}: View.Mapping{ww,wh,w,h}

def input(world: World, view: View.Mapping, palette: A.Palette, encoding: A.Output) -> World & A.FrameInput:
  World{body,C.ChunkSet{chunks,primitives,+faces,+bounds,count,shadow,rebuilt,retained},+camera,+controls,revision,original,+point,changed} = world
  View.Mapping{+ww,+wh,+w,+h} = view
  (World{body,C.ChunkSet{chunks,primitives,faces,bounds,count,shadow,rebuilt,retained},camera,controls,revision,original,point,changed},A.FrameInput{R.Camera.basis(camera),w,h,frame_extent(bounds),palette,hover(view,camera,controls,point,faces),encoding,A.Shaded{}})

def format(target: Maybe<&2,P.Target>) -> U32:
  match target:
    case None{}: 37
    case Some{P.Target{sc,images,pass,layout,pipeline,w,h,f,programs}}: f

def shared(fleet: F.Fleet) -> F.Fleet & F.Shared:
  F.Fleet{first,rest,+state} = fleet
  (F.Fleet{first,rest,state},state)

def palette(fleet: F.Fleet) -> F.Fleet & A.Palette:
  F.Fleet{F.Slot{f,+a,t,s,q,phase},rest,state} = fleet
  (F.Fleet{F.Slot{f,a,t,s,q,phase},rest,state},Scene.palette(a))

def assets(fleet: F.Fleet) -> F.Fleet & Scene.Assets:
  F.Fleet{F.Slot{f,+a,t,s,q,phase},rest,state} = fleet
  (F.Fleet{F.Slot{f,a,t,s,q,phase},rest,state},a)

def changed_target(fleet: F.Fleet) -> F.Fleet & Bool:
  F.Fleet{first,rest,+state} = fleet
  F.Shared{g,r,u,f,p,replace,order} = state
  (F.Fleet{first,rest,state},replace)

def clear_recreate(fleet: F.Fleet) -> F.Fleet:
  F.Fleet{first,rest,F.Shared{g,r,u,f,p,replace,order}} = fleet
  F.Fleet{first,rest,F.Shared{g,r,u,f,p,False{},order}}

def original(world: World) -> World & Original:
  World{body,mesh,camera,controls,revision,+which,point,changed} = world
  (World{body,mesh,camera,controls,revision,which,point,changed},which)

def recreated(+context: WSI.Context, world: World, old: Maybe<&2,P.Target>, fleet: F.Fleet, +w: U32, +h: U32, mapped: Bool, generations: U32, which: Original, a: Scene.Assets) -> V.Action(Session):
  +dev = device(context)
  do V.Action<Session>:
    fleet : F.Fleet <- F.retarget(context,None{},fleet)
    target_destroy(dev,old)
    raw : P.Target <- P.build(context,w,h)
    +target : P.Target <- production_target(dev,raw,a,which)
    fleet : F.Fleet <- F.retarget(context,Some{target},fleet)
    return Session{world,Some{target},clear_recreate(fleet),w,h,mapped,False{},U32.inc(generations)}

def recreate_assets(context: WSI.Context, world: World, target: Maybe<&2,P.Target>, w: U32, h: U32, mapped: Bool, generations: U32, which: Original, pair: F.Fleet & Scene.Assets) -> V.Action(Session):
  (fleet,a) = pair
  recreated(context,world,target,fleet,w,h,mapped,generations,which,a)

def recreate_original(context: WSI.Context, target: Maybe<&2,P.Target>, fleet: F.Fleet, w: U32, h: U32, mapped: Bool, generations: U32, pair: World & Original) -> V.Action(Session):
  (world,which) = pair
  recreate_assets(context,world,target,w,h,mapped,generations,which,assets(fleet))

def drained_if(context: WSI.Context, world: World, target: Maybe<&2,P.Target>, fleet: F.Fleet, w: U32, h: U32, mapped: Bool, generations: U32, ready: Bool) -> V.Action(Session):
  match ready:
    case True{}: recreate_original(context,target,fleet,w,h,mapped,generations,original(world))
    case False{}: V.Action.pure(Session,Session{world,target,fleet,w,h,mapped,True{},generations})

def drained(context: WSI.Context, world: World, target: Maybe<&2,P.Target>, +w: U32, +h: U32, +mapped: Bool, generations: U32, pair: F.Fleet & Bool) -> V.Action(Session):
  (fleet,ready) = pair
  drained_if(context,world,target,fleet,w,h,mapped,generations,ready && Core.drawable(mapped,w,h))

def rendering_finished(body: X.Body, camera: R.Camera, controls: Controls.Controls, revision: U32, original: Original, point: Pointer, target: Maybe<&2,P.Target>, w: U32, h: U32, mapped: Bool, generations: U32, pair: C.ChunkSet & F.Fleet) -> Session:
  (set,fleet) = pair
  Session{World{body,set,camera,controls,revision,original,point,False{}},target,fleet,w,h,mapped,False{},generations}

def is_atelier(which: Original) -> Bool:
  match which:
    case Cube{}: False{}
    case Atelier{}: True{}

def rendering_input(+context: WSI.Context, trace: Bool, +target: Maybe<&2,P.Target>, fleet: F.Fleet, w: U32, h: U32, mapped: Bool, generations: U32, pair: World & A.FrameInput) -> V.Action(Session):
  (World{body,set,camera,controls,+revision,+which,point,dirty},input) = pair
  do V.Action<Session>:
    result : C.ChunkSet & F.Fleet <- F.render(context,trace,fleet,set,revision,input,Bool.not(is_atelier(which)))
    return rendering_finished(body,camera,controls,revision,which,point,target,w,h,mapped,generations,result)

def render_palette(context: WSI.Context, trace: Bool, world: World, +target: Maybe<&2,P.Target>, +w: U32, +h: U32, mapped: Bool, generations: U32, pair: F.Fleet & A.Palette) -> V.Action(Session):
  (fleet,palette) = pair
  rendering_input(context,trace,target,fleet,w,h,mapped,generations,input(world,mapping(target,w,h),palette,output(format(target))))

def advanced_if(+context: WSI.Context, trace: Bool, world: World, target: Maybe<&2,P.Target>, +w: U32, +h: U32, +mapped: Bool, replace: Bool, generations: U32, fleet: F.Fleet, condition: Bool) -> V.Action(Session):
  match condition:
    case True{}:
      do V.Action<Session>:
        fleet : F.Fleet <- F.drain(device(context),fleet)
        drained(context,world,target,w,h,mapped,generations,F.idle(fleet))
    case False{}:
      do V.Action<Session>:
        fleet : F.Fleet <- F.acquire(device(context),fleet)
        render_palette(context,trace,world,target,w,h,mapped,generations,palette(fleet))

def advanced(context: WSI.Context, trace: Bool, world: World, target: Maybe<&2,P.Target>, +w: U32, +h: U32, +mapped: Bool, +replace: Bool, generations: U32, pair: F.Fleet & Bool) -> V.Action(Session):
  (fleet,requested) = pair
  advanced_if(context,trace,world,target,w,h,mapped,replace,generations,fleet,replace || requested || Bool.not(Core.drawable(mapped,w,h)))

def advance(+context: WSI.Context, +trace: Bool, app: Session) -> V.Action(Session):
  Session{world,target,fleet,+w,+h,+mapped,+replace,generations} = app
  do V.Action<Session>:
    fleet : F.Fleet <- F.service(device(context),trace,F.recovery(replace || Bool.not(Core.drawable(mapped,w,h)),fleet))
    advanced(context,trace,world,target,w,h,mapped,replace,generations,changed_target(fleet))

def log(world: World, +w: U32, +h: U32, mapped: Bool, captured: Bool, generations: U32, state: F.Shared) -> V.Action(World):
  World{body,C.ChunkSet{chunks,primitives,faces,bounds,+count,+shadow,+rebuilt,+retained},+camera,controls,+revision,which,point,dirty} = world
  R.Camera{R.Vec3{x,y,z},yaw,pitch} = camera
  F.Shared{g,installed,uploads,frames,presented,replace,order} = state
  do V.Action<World>:
    rows : U32 <- V.debug_live_objects()
    V.Action.lift(Unit,IO.print("STATE rows=" ++ U32.show(rows) ++ " frame=" ++ U32.show(frames) ++ " generation=" ++ U32.show(generations) ++ " revision=" ++ U32.show(revision) ++ " installed=" ++ U32.show(installed) ++ " uploads=" ++ U32.show(uploads) ++ " quads=" ++ U32.show(count) ++ " chunks=" ++ U32.show(U32.from_nat(List.length(&2,GPU.Resident,G.residents(g)))) ++ " shadow_quads=" ++ U32.show(shadow) ++ " rebuilt=" ++ U32.show(rebuilt) ++ " retained=" ++ U32.show(retained) ++ " width=" ++ U32.show(w) ++ " height=" ++ U32.show(h) ++ " mapped=" ++ U32.show(Bool.to_u32(mapped)) ++ " captured=" ++ U32.show(Bool.to_u32(captured)) ++ " completed_revision=" ++ U32.show(presented) ++ " camera=" ++ U32.show(F32.bits(x)) ++ "," ++ U32.show(F32.bits(y)) ++ "," ++ U32.show(F32.bits(z)) ++ "," ++ U32.show(F32.bits(yaw)) ++ "," ++ U32.show(F32.bits(pitch))))
    return World{body,C.ChunkSet{chunks,primitives,faces,bounds,count,shadow,rebuilt,retained},camera,controls,revision,which,point,dirty}

def diagnostics(enabled: Bool, world: World, w: U32, h: U32, mapped: Bool, captured: Bool, generations: U32, state: F.Shared) -> V.Action(World):
  match enabled:
    case False{}: V.Action.pure(World,world)
    case True{}: log(world,w,h,mapped,captured,generations,state)

def logged(target: Maybe<&2,P.Target>, w: U32, h: U32, mapped: Bool, replace: Bool, generations: U32, pair: World & F.Fleet) -> Session:
  (world,fleet) = pair
  Session{world,target,fleet,w,h,mapped,replace,generations}

def close_ready(+context: WSI.Context, target: Maybe<&2,P.Target>, pair: F.Fleet & Bool, next: F.Fleet -> V.Action(Unit)) -> V.Action(Unit):
  (fleet,ready) = pair
  match ready:
    case True{}:
      do V.Action<Unit>:
        fleet : F.Fleet <- F.retarget(context,None{},fleet)
        target_destroy(device(context),target)
    case False{}: next(fleet)

def close(fuel: Nat, +context: WSI.Context, fleet: F.Fleet, +target: Maybe<&2,P.Target>) -> V.Action(Unit):
  match fuel:
    case 0n: D.require(False{},"Frame slots did not drain during close")
    case 1n+rest:
      do V.Action<Unit>:
        fleet : F.Fleet <- F.service(device(context),False{},F.recovery(True{},fleet))
        fleet : F.Fleet <- F.drain(device(context),fleet)
        state : V.WindowSnapshot <- V.NativeWindow.poll(window(context),1)
        close_ready(context,target,F.idle(fleet),next => close(rest,context,next,target))

def trace_shared(trace: Bool, world: World, target: Maybe<&2,P.Target>, +w: U32, +h: U32, +mapped: Bool, captured: Bool, replace: Bool, +generations: U32, pair: F.Fleet & F.Shared) -> V.Action(Maybe<Session>):
  (fleet,state) = pair
  do V.Action<Maybe<Session>>:
    world : World <- diagnostics(trace,world,w,h,mapped,captured,generations,state)
    return Some{Session{world,target,fleet,w,h,mapped,replace,generations}}

def trace_session(trace: Bool, app: Session, captured: Bool) -> V.Action(Maybe<Session>):
  Session{world,target,fleet,w,h,mapped,replace,generations} = app
  trace_shared(trace,world,target,w,h,mapped,captured,replace,generations,shared(fleet))

def process_events(+trace: Bool, +context: WSI.Context, next: Maybe<World>, target: Maybe<&2,P.Target>, fleet: F.Fleet, +w: U32, +h: U32, +mapped: Bool, captured: Bool, replace: Bool, +generations: U32, elapsed: Nat) -> V.Action(Maybe<Session>):
  match next:
    case None{}:
      do V.Action<Maybe<Session>>:
        close(100000n,context,fleet,target)
        return None{}
    case Some{world}:
      do V.Action<Maybe<Session>>:
        moved : World <- capture_apply(window(context),fly(world,elapsed))
        app : Session <- advance(context,trace,Session{moved,target,fleet,w,h,mapped,replace,generations})
        trace_session(trace,app,captured)

def snapshot(+trace: Bool, app: Session, +context: WSI.Context, state: V.WindowSnapshot, elapsed: Nat) -> V.Action(Maybe<Session>):
  Session{world,+target,fleet,+ow,+oh,om,replace,generations} = app
  V.WindowSnapshot{+w,+h,+mapped,focused,captured,native_events} = state
  do V.Action<Maybe<Session>>:
    before : W.U64 <- V.monotonic_ns()
    next : Maybe<World> <- events(native_events,world,mapping(target,w,h))
    after : W.U64 <- V.monotonic_ns()
    Timing.cpu(trace,"edit_mesh_events",before,after)
    process_events(trace,context,next,target,fleet,w,h,mapped,captured,replace || U32.is_ne(ow,w) || U32.is_ne(oh,h),generations,elapsed)

def elapsed(previous: Maybe<&2,Nat>, now: Nat) -> Nat:
  match previous:
    case None{}: 0n
    case Some{before}: Nat.min(Nat.sub(now,before),100n)

def turn(+trace: Bool, +context: WSI.Context, previous: Maybe<&2,Nat>, app: Session, next: Maybe<Session> -> Nat -> V.Action(Unit)) -> V.Action(Unit):
  Session{world,target,fleet,+w,+h,+mapped,replace,generations} = app
  do V.Action<Unit>:
    state : V.WindowSnapshot <- V.NativeWindow.poll(window(context),Bool.pick(U32,Core.drawable(mapped,w,h),1,50))
    +now : Nat <- V.Action.lift(Nat,IO.now())
    result : Maybe<Session> <- snapshot(trace,Session{world,target,fleet,w,h,mapped,replace,generations},context,state,elapsed(previous,now))
    next(result,now)

def loop(fuel: Nat, next: Maybe<Session>, +trace: Bool, +context: WSI.Context, previous: Maybe<&2,Nat>) -> V.Action(Unit):
  match fuel next:
    case 0n _: V.Action.pure(Unit,Unit{})
    case _ None{}: V.Action.pure(Unit,Unit{})
    case 1n+rest Some{app}: turn(trace,context,previous,app,result => now => loop(rest,result,trace,context,Some{now}))

def initial_selected(pair: X.Body & C.ChunkSet, +which: Original) -> World:
  (body,set) = pair
  World{body,set,original_camera(which),Controls.Controls.initial(),0,which,Pointer{320,240},True{}}

def initial_scene(+which: Original) -> V.Action(World):
  do V.Action<World>:
    pair : X.Body & C.ChunkSet <- built(C.build(original_body(which),0))
    return initial_selected(pair,which)

def scene_create(context: WSI.Context) -> V.Action(Scene.Group):
  WSI.Context{w,i,p,s,d,g,q} = context
  Scene.create(i,p,d)

def announce(context: WSI.Context, enabled: Bool) -> V.Action(Unit):
  WSI.Context{w,i,p,s,d,g,q} = context
  match enabled:
    case False{}: V.Action.pure(Unit,Unit{})
    case True{}: V.Action.lift(Unit,IO.print("Queues " ++ U32.show(g) ++ " " ++ U32.show(q)))

def run(+entry: V.Entry, split: Bool, +trace: Bool, original: Original, slots: U32) -> V.Action(Unit):
  do V.Action<Unit>:
    +context : WSI.Context <- WSI.open(entry,"Bend Vulkan | WASD Q/E | RMB look | click carve | Space cut | R reset | Esc",split)
    announce(context,trace)
    +scene : Scene.Group <- scene_create(context)
    fleet : F.Fleet <- F.create(context,Scene.assets(scene),slots,trace)
    world : World <- initial_scene(original)
    loop(4294967295n,Some{Session{world,None{},fleet,640,480,False{},True{},0}},trace,context,None{})
