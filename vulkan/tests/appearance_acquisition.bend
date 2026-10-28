import Base
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W
import ../../render.bend as R
import ../../voxel.bend as X
import ../../main.bend as Controls
import ../../deps/bend-vulkan/examples/window.bend as WSI
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D
import ../../deps/bend-vulkan/examples/indexed_offscreen.bend as E
import ../src/interactive.bend as I
import ../src/scene.bend as Scene
import ../src/appearance.bend as A
import ../src/presentation.bend as P
import ../src/chunks.bend as C
import ../src/flight.bend as F
import ../src/viewport.bend as View
import ../src/renderer.bend as GPU
import ../../deps/bend-vulkan/src/upload.bend as U
import ../../deps/bend-vulkan/src/core.bend as Core
import ./chunk_device.bend as CD
import ../../deps/bend-vulkan/tests/native.bend as N
import ../src/generation.bend as G

type Expected is Data:
  Expected{uniform: List<&2,U32>, revision: U32, bytes: List<&2,U32>}

type Check is Data:
  Acquire{device: V.Device}
  WaitAcquire{device: V.Device}
  Pending{device: V.Device}
  WaitRender{device: V.Device}
  WaitPresent{device: V.Device}
  Uniform{device: V.Device, one: Expected, two: Expected}

def encoded_bytes(result: Maybe<Array<U32>>) -> List<U32>:
  match result:
    case None{}: []
    case Some{words}: E.bytes(List.take(&1,U32,Array.to_list(~U32,words),584n))

def uniform_memory(a: Scene.Assets) -> V.DeviceMemory:
  Scene.Assets{E.BoundBuffer{b,m},s,ss,p,f,sd,sampler,shadow,sp,sf,ps,fl,ml,indices,palette} = a
  m

def shadow_image(a: Scene.Assets) -> V.ImageHandle:
  Scene.Assets{u,s,ss,p,f,sd,sampler,E.Attachment{image,m,v},sp,sf,ps,fl,ml,indices,palette} = a
  image

def frame_acquired(slot: F.Slot, outcome: V.AcquireOutcome) -> V.Action(F.Slot):
  F.Slot{f,a,t,s,q,phase} = slot
  match outcome:
    case V.Acquired{acquisition,index,replace}: V.Action.pure(F.Slot,F.Slot{f,a,t,s,q,F.Acquiring{acquisition,index,replace}})
    case _: IO.pure(V.VkResult(F.Slot),Fail{(1,"Fixture did not acquire an image")})

def chain(target: Maybe<&2,P.SlotTarget>) -> V.Swapchain:
  match target:
    case None{}: V.Swapchain{0}
    case Some{P.SlotTarget{shared,images,depth}}: I.target_swapchain(shared)

def acquire_slot(+device: V.Device, slot: F.Slot) -> V.Action(F.Slot):
  F.Slot{+frame,a,+target,s,q,phase} = slot
  P.Frame{p,c,+acquire,r,present,finished} = frame
  do V.Action<F.Slot>:
    outcome : V.AcquireOutcome <- V.Device.acquire(device,chain(target),acquire,W.of_u32(1000000000))
    frame_acquired(F.Slot{frame,a,target,s,q,phase},outcome)

def edited(result: Maybe<I.World>) -> V.Action(I.World):
  match result:
    case Some{world}: V.Action.pure(I.World,world)
    case None{}: IO.pure(V.VkResult(I.World),Fail{(1,"Fixture unexpectedly closed")})

def waited(+device: V.Device, slot: F.Slot) -> V.Action(F.Slot):
  F.Slot{+frame,a,t,s,q,phase} = slot
  P.Frame{p,c,+acquire,r,present,finished} = frame
  do V.Action<F.Slot>:
    status : U32 <- V.Fence.wait(acquire,W.U64{4294967295,4294967295})
    return F.Slot{frame,a,t,s,q,phase}

def frozen(body: X.Body, camera: R.Camera, controls: Controls.Controls, +revision: U32, original: I.Original, point: I.Pointer, input: A.FrameInput, bytes: List<&2,U32>, pair: C.ChunkSet & F.Fleet) -> I.World & (F.Fleet & Expected):
  (set,fleet) = pair
  (I.World{body,set,camera,controls,revision,original,point,False{}},(fleet,Expected{CD.share(encoded_bytes(A.encode(input))),revision,bytes}))

def freeze_packed(+context: WSI.Context, fleet: F.Fleet, body: X.Body, +camera: R.Camera, +controls: Controls.Controls, +revision: U32, original: I.Original, +point: I.Pointer, palette: A.Palette, encoding: A.Output, pair: C.ChunkSet & List<&2,U32>) -> V.Action(I.World & (F.Fleet & Expected)):
  (C.ChunkSet{cs,primitives,+faces,+bounds,count,shadow,rebuilt,retained},bytes) = pair
  +input : A.FrameInput = A.FrameInput{R.Camera.basis(camera),640,480,I.frame_extent(bounds),palette,I.hover(View.Mapping{640,480,640,480},camera,controls,point,faces),encoding,A.Shaded{}}
  do V.Action<I.World & (F.Fleet & Expected)>:
    result : C.ChunkSet & F.Fleet <- F.render(context,False{},fleet,C.ChunkSet{cs,primitives,faces,bounds,count,shadow,rebuilt,retained},revision,input,False{})
    return frozen(body,camera,controls,revision,original,point,input,bytes,result)

def freeze(context: WSI.Context, fleet: F.Fleet, world: I.World, palette: A.Palette, encoding: A.Output) -> V.Action(I.World & (F.Fleet & Expected)):
  I.World{body,set,camera,controls,revision,original,point,dirty} = world
  freeze_packed(context,fleet,body,camera,controls,revision,original,point,palette,encoding,CD.snapshot(set))

def rendered(slot: F.Slot, +device: V.Device) -> V.Action(F.Slot):
  F.Slot{+frame,a,t,s,q,phase} = slot
  P.Frame{p,c,acquire,+render,present,finished} = frame
  do V.Action<F.Slot>:
    status : U32 <- V.Fence.wait(render,W.U64{4294967295,4294967295})
    return F.Slot{frame,a,t,s,q,phase}

def shadow(+context: CD.Context, +image: V.ImageHandle) -> V.Action(List<U32>):
  CD.Context{+instance,+physical,+device,+command,+fence} = context
  do V.Action<List<U32>>:
    +back : U.Allocation <- U.allocate(instance,physical,device,W.of_u32(1048576),2,2)
    V.CommandBuffer.begin(command)
    E.transition(command,image,2,4,6,128,4096,32,2048)
    V.CommandBuffer.copy_image_to_buffer(command,image,6,G.allocation_buffer(back),[V.BufferImageCopy{W.zero(),0,0,V.ImageSubresourceLayers{2,0,0,1},V.Offset2D{0,0},V.Extent2D{512,512}}])
    E.transition(command,image,2,6,4,4096,128,2048,32)
    V.CommandBuffer.pipeline_barrier(command,4096,16384,[V.MemoryBarrier{4096,8192}],[],[])
    E.complete(device,command,fence)
    bytes : List<U32> <- V.Device.read_memory(device,CD.allocation_memory(back),W.zero(),1048576)
    E.reset(device,command,fence)
    U.discard(device,back)
    return bytes

def pending(+device: V.Device, slot: F.Slot) -> V.Action(F.Slot):
  F.Slot{f,+a,t,s,q,phase} = slot
  match phase:
    case F.Submitted{packet,replace}:
      do V.Action<F.Slot>:
        N.expect_error(List<U32>,1610612740,V.Device.read_memory(device,uniform_memory(a),W.zero(),2336))
        return F.Slot{f,a,t,s,q,F.Submitted{packet,replace}}
    case _: IO.pure(V.VkResult(F.Slot),Fail{(1,"Both slots must be submitted before either fence is observed")})


def check_packet(+device: V.Device, slot: F.Slot, expected: Expected) -> V.Action(F.Slot):
  F.Slot{f,+a,t,s,q,phase} = slot
  match phase:
    case F.Submitted{F.Packet{acquisition,index,+actual,started,view,sequence},replace}:
      Expected{+input,+revision,bytes} = expected
      do V.Action<F.Slot>:
        D.require(U32.is_eq(actual,revision),"Packet revision changed while submitted")
        uniform : List<U32> <- V.Device.read_memory(device,uniform_memory(a),W.zero(),2336)
        D.require(D.bytes_equal(uniform,E.copy_words(input)),"Independent slot uniform differs from all 2336 acquisition-time bytes")
        return F.Slot{f,a,t,s,q,F.Submitted{F.Packet{acquisition,index,actual,started,view,sequence},replace}}
    case _: IO.pure(V.VkResult(F.Slot),Fail{(1,"Fixture expected two submitted packets before observing fences")})

def presenting_bytes(+device: V.Device, slot: F.Slot, expected: Expected) -> V.Action(F.Slot):
  F.Slot{f,+a,t,s,q,phase} = slot
  match phase:
    case F.Presenting{packet,replace,lost,shown}:
      Expected{input,r,b} = expected
      do V.Action<F.Slot>:
        bytes : List<U32> <- V.Device.read_memory(device,uniform_memory(a),W.zero(),2336)
        D.require(D.bytes_equal(bytes,E.copy_words(input)),"Presenting camera/pointer events overwrote a frozen slot uniform")
        return F.Slot{f,a,t,s,q,F.Presenting{packet,replace,lost,shown}}
    case _: IO.pure(V.VkResult(F.Slot),Fail{(1,"Fixture expected both independent presentation owners")})

def moved_state(before: R.Camera, world: I.World) -> V.Action(I.World):
  I.World{body,set,+camera,controls,revision,which,I.Pointer{+x,+y},+dirty} = world
  do V.Action<I.World>:
    D.require(Bool.not(R.Camera.equal(before,camera)) && U32.is_eq(x,321) && U32.is_eq(y,227) && dirty,"Presenting event must preserve a new dirty camera and pointer")
    return I.World{body,set,camera,controls,revision,which,I.Pointer{x,y},dirty}

def mutate_presenting(world: I.World) -> V.Action(I.World):
  I.World{body,set,+camera,controls,revision,which,point,dirty} = world
  moved_state(camera,I.pointer(I.fly(I.World{body,set,camera,controls,revision,which,point,dirty},16n),321,227))

def free_result(pair: F.Fleet & Bool, next: F.Fleet -> V.Action(F.Fleet)) -> V.Action(F.Fleet):
  (fleet,ready) = pair
  match ready:
    case True{}: V.Action.pure(F.Fleet,fleet)
    case False{}: next(fleet)

def wait_free(fuel: Nat, +context: WSI.Context, fleet: F.Fleet) -> V.Action(F.Fleet):
  match fuel:
    case 0n: IO.pure(V.VkResult(F.Fleet),Fail{(1,"Independent presentation owners did not complete")})
    case 1n+rest:
      do V.Action<F.Fleet>:
        fleet : F.Fleet <- F.service(I.device(context),False{},fleet)
        state : V.WindowSnapshot <- V.NativeWindow.poll(I.window(context),1)
        free_result(F.idle(fleet),next => wait_free(rest,context,next))

def later_frozen(+context: WSI.Context, target: P.Target, prior_uploads: U32, pair: I.World & (F.Fleet & Expected)) -> V.Action(Unit):
  (world,(F.Fleet{first,second,+state},expected)) = pair
  F.Shared{g,r,u,n,p,replace,order} = state
  do V.Action<Unit>:
    D.require(U32.is_eq(prior_uploads,u),"Later camera/pointer acquisition uploaded unchanged chunk geometry")
    first : F.Slot <- pending(I.device(context),first)
    first : F.Slot <- rendered(first,I.device(context))
    first : F.Slot <- check_packet(I.device(context),first,expected)
    I.close(100000n,context,F.Fleet{first,second,state},Some{target})

def later_assets(+context: WSI.Context, +target: P.Target, world: I.World, first: F.Slot, second: List<F.Slot>, +state: F.Shared, palette: A.Palette) -> V.Action(Unit):
  F.Shared{g,r,+u,n,p,replace,order} = state
  do V.Action<Unit>:
    first : F.Slot <- acquire_slot(I.device(context),first)
    first : F.Slot <- waited(I.device(context),first)
    result : I.World & (F.Fleet & Expected) <- freeze(context,F.Fleet{first,second,state},world,palette,I.output(I.format(Some{target})))
    later_frozen(context,target,u,result)

def later_acquire(context: WSI.Context, target: P.Target, world: I.World, fleet: F.Fleet) -> V.Action(Unit):
  F.Fleet{F.Slot{f,+a,t,s,q,phase},second,state} = fleet
  later_assets(context,target,world,F.Slot{f,a,t,s,q,phase},second,state,Scene.palette(a))


def presenting_events(+context: WSI.Context, target: P.Target, world: I.World, fleet: F.Fleet, expected: Expected) -> V.Action(Unit):
  F.Fleet{first,second,shared} = fleet
  do V.Action<Unit>:
    moved : I.World <- mutate_presenting(world)
    first : F.Slot <- presenting_bytes(I.device(context),first,expected)
    fleet : F.Fleet <- wait_free(100000n,context,F.Fleet{first,second,shared})
    later_acquire(context,target,moved,fleet)

def presenting_ready(+context: WSI.Context, target: P.Target, world: I.World, expected: Expected, fleet: F.Fleet) -> V.Action(Unit):
  F.Fleet{first,second,state} = fleet
  do V.Action<Unit>:
    first : F.Slot <- pending(I.device(context),first)
    first : F.Slot <- rendered(first,I.device(context))
    fleet : F.Fleet <- F.service(I.device(context),False{},F.Fleet{first,second,state})
    presenting_events(context,target,world,fleet,expected)

def presenting_frozen(context: WSI.Context, target: P.Target, pair: I.World & (F.Fleet & Expected)) -> V.Action(Unit):
  (world,(fleet,expected)) = pair
  presenting_ready(context,target,world,expected,fleet)

def presenting_acquired(+context: WSI.Context, +target: P.Target, fleet: F.Fleet, +palette: A.Palette, world: I.World) -> V.Action(Unit):
  F.Fleet{first,second,state} = fleet
  do V.Action<Unit>:
    first : F.Slot <- acquire_slot(I.device(context),first)
    first : F.Slot <- waited(I.device(context),first)
    result : I.World & (F.Fleet & Expected) <- freeze(context,F.Fleet{first,second,state},I.fly(I.key(world,119,True{}),16n),palette,I.output(I.format(Some{target})))
    presenting_frozen(context,target,result)

def run_presenting(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +context : WSI.Context <- WSI.open(entry,"Bend presenting input consistency",False{})
    +scene : Scene.Group <- I.scene_create(context)
    fleet : F.Fleet <- F.create(context,Scene.assets(scene),1,True{})
    raw : P.Target <- P.build(context,640,480)
    +target : P.Target <- P.promote(I.device(context),raw,Scene.assets(scene))
    fleet : F.Fleet <- F.retarget(context,Some{target},fleet)
    world : I.World <- I.initial_scene(I.Atelier{})
    presenting_acquired(context,target,fleet,Scene.palette(Scene.assets(scene)),world)

def clean() -> IO(Unit):
  do IO<Unit>:
    live : V.VkResult(U32) <- V.debug_live_objects()
    rows : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- D.require(U32.is_zero(rows),"Acquisition slots leaked resources")
    V.or_exit(Unit,checked)


def sequence(packet: F.Packet) -> W.U64:
  F.Packet{a,i,r,s,q,sequence} = packet
  sequence

def uniform_sequence(device: V.Device, one: Expected, two: Expected, slot: F.Slot, sequence: W.U64) -> V.Action(F.Slot):
  match sequence:
    case W.U64{0,0}: check_packet(device,slot,one)
    case W.U64{1,0}: check_packet(device,slot,two)
    case _: IO.pure(V.VkResult(F.Slot),Fail{(1,"Two-slot packets have wrong revisions")})

def uniform_slot(+device: V.Device, +one: Expected, +two: Expected, slot: F.Slot) -> V.Action(F.Slot):
  F.Slot{f,a,t,s,q,phase} = slot
  match phase:
    case F.Submitted{+packet,replace}:
      uniform_sequence(device,one,two,F.Slot{f,a,t,s,q,F.Submitted{packet,replace}},sequence(packet))
    case _: IO.pure(V.VkResult(F.Slot),Fail{(1,"Missing submitted packet")})

def wait_presented(+device: V.Device, slot: F.Slot) -> V.Action(F.Slot):
  F.Slot{+frame,a,t,s,q,phase} = slot
  P.Frame{pool,command,acquire,render,+present,finished} = frame
  do V.Action<F.Slot>:
    status : U32 <- V.Fence.wait(present,W.U64{4294967295,4294967295})
    return F.Slot{frame,a,t,s,q,phase}

def check_action(operation: Check, slot: F.Slot) -> V.Action(F.Slot):
  match operation:
    case Acquire{device}: acquire_slot(device,slot)
    case WaitAcquire{device}: waited(device,slot)
    case Pending{device}: pending(device,slot)
    case WaitRender{device}: rendered(slot,device)
    case WaitPresent{device}: wait_presented(device,slot)
    case Uniform{device,one,two}: uniform_slot(device,one,two,slot)

def check_cons(slot: F.Slot, rest: List<F.Slot>) -> List<F.Slot>:
  slot <> rest

def check_tail_head(slot: F.Slot, next: V.Action(List<F.Slot>)) -> V.Action(List<F.Slot>):
  do V.Action<List<F.Slot>>:
    rest : List<F.Slot> <- next
    return check_cons(slot,rest)

def check_tail(fuel: Nat, slots: List<F.Slot>, +operation: Check) -> V.Action(List<F.Slot>):
  match fuel slots:
    case 0n Nil{}: V.Action.pure(List<F.Slot>,Nil{})
    case 0n _: IO.pure(V.VkResult(List<F.Slot>),Fail{(1,"Too many fixture slots")})
    case 1n+rest Nil{}: V.Action.pure(List<F.Slot>,Nil{})
    case 1n+rest slot <> tail:
      do V.Action<List<F.Slot>>:
        slot : F.Slot <- check_action(operation,slot)
        check_tail_head(slot,check_tail(rest,tail,operation))

def check_fleet_tail(first: F.Slot, shared: F.Shared, rest: List<F.Slot>) -> F.Fleet:
  F.Fleet{first,rest,shared}

def walk(+operation: Check, fleet: F.Fleet) -> V.Action(F.Fleet):
  F.Fleet{first,rest,shared} = fleet
  do V.Action<F.Fleet>:
    first : F.Slot <- check_action(operation,first)
    rest : List<F.Slot> <- check_tail(1n,rest,operation)
    return check_fleet_tail(first,shared,rest)

def shadow_handles(fleet: F.Fleet) -> V.Action(F.Fleet & (V.ImageHandle & V.ImageHandle)):
  F.Fleet{F.Slot{f1,+a1,t1,s1,q1,p1},rest,shared} = fleet
  match rest:
    case [F.Slot{f2,+a2,t2,s2,q2,p2}]: V.Action.pure(F.Fleet & (V.ImageHandle & V.ImageHandle),(F.Fleet{F.Slot{f1,a1,t1,s1,q1,p1},[F.Slot{f2,a2,t2,s2,q2,p2}],shared},(shadow_image(a1),shadow_image(a2))))
    case _: IO.pure(V.VkResult(F.Fleet & (V.ImageHandle & V.ImageHandle)),Fail{(1,"Exactly two independent shadow slots are required")})

def shadow_read(+read: CD.Context, pair: F.Fleet & (V.ImageHandle & V.ImageHandle)) -> V.Action(F.Fleet):
  (fleet,(first,second)) = pair
  do V.Action<F.Fleet>:
    a : List<U32> <- shadow(read,first)
    b : List<U32> <- shadow(read,second)
    D.require(Bool.not(D.bytes_equal(a,b)),"Independent shadow attachments must contain distinct real D32 bytes for cut and reset packets")
    return fleet

def geometry_read(read: CD.Context, one: Expected, two: Expected, pair: F.Fleet & F.Shared) -> V.Action(F.Fleet):
  Expected{+u1,r1,b1} = one
  Expected{+u2,r2,b2} = two
  (fleet,F.Shared{geometry,r,u,n,p,replace,order}) = pair
  do V.Action<F.Fleet>:
    D.require(U32.is_eq(r1,1) && U32.is_eq(r2,2),"Queued edit and submitted reset must advance exact revisions")
    D.require(Bool.not(D.bytes_equal(E.copy_words(u1),E.copy_words(u2))),"Independent camera/brush bytes did not change")
    bytes : List<&2,U32> <- CD.read_geometry(read,geometry)
    D.require(D.bytes_equal(E.copy_words(bytes),E.copy_words(b2)),"Actual installed chunk color/shadow bytes differ from latest CPU geometry")
    return fleet

def readbacks(+context: WSI.Context, target: P.Target, +read: CD.Context, one: Expected, two: Expected, fleet: F.Fleet) -> V.Action(Unit):
  do V.Action<Unit>:
    images : F.Fleet & (V.ImageHandle & V.ImageHandle) <- shadow_handles(fleet)
    fleet : F.Fleet <- shadow_read(read,images)
    fleet : F.Fleet <- geometry_read(read,one,two,I.shared(fleet))
    I.close(100000n,context,fleet,Some{target})
    V.Action.lift(Unit,IO.print("Two acquisition-time packets matched device geometry plus all 2336 frame bytes; distinct camera and shadow readbacks passed"))

def reversed(fleet: F.Fleet) -> V.Action(F.Fleet):
  F.Fleet{first,rest,state} = fleet
  match rest:
    case [second]: V.Action.pure(F.Fleet,F.Fleet{second,[first],state})
    case _: IO.pure(V.VkResult(F.Fleet),Fail{(1,"Reverse completion needs two slots")})

def newest_completion(fleet: F.Fleet) -> V.Action(F.Fleet):
  F.Fleet{first,rest,+state} = fleet
  F.Shared{g,r,u,frames,completed,replace,order} = state
  do V.Action<F.Fleet>:
    D.require(U32.is_eq(completed,2) && U32.is_eq(frames,2),"Revision two completion was overwritten by later observation of revision one")
    V.Action.lift(Unit,IO.print("Actual completion observation order 2 then 1 retained completed_revision=2"))
    return F.Fleet{first,rest,state}

def ordered_dispatch(fleet: F.Fleet) -> V.Action(F.Fleet):
  F.Fleet{F.Slot{f,a,t,s,q,phase},rest,+state} = fleet
  match phase rest:
    case F.Submitted{+newer,new_replace} Con{F.Slot{old_frame,oa,ot,os,oq,F.Presenting{+older,old_replace,ol,shown}},Nil{}}:
      F.Shared{g,r,u,n,p,replace,F.Ordering{next_submit,+next_present}} = state
      do V.Action<F.Fleet>:
        D.require(Core.sequence_ready(sequence(newer),W.of_u32(1)) && Core.sequence_ready(sequence(older),W.zero()) && Core.sequence_ready(next_present,W.of_u32(1)),"Newer ready slot must wait until older sequence is dispatched")
        return F.Fleet{F.Slot{f,a,t,s,q,F.Submitted{newer,new_replace}},[F.Slot{old_frame,oa,ot,os,oq,F.Presenting{older,old_replace,ol,shown}}],state}
    case _ _: IO.pure(V.VkResult(F.Fleet),Fail{(1,"Fixed slot order reversed present dispatch")})

def dispatched_head(first: F.Slot, rest: List<F.Slot>, state: F.Shared) -> V.Action(F.Fleet):
  F.Slot{f,a,t,s,q,phase} = first
  match phase:
    case F.Presenting{packet,suboptimal,lost,shown}:
      F.Shared{g,r,u,n,p,replace,F.Ordering{next_submit,+next_present}} = state
      do V.Action<F.Fleet>:
        D.require(Core.sequence_ready(next_present,W.of_u32(2)),"Present dispatch did not consume exactly sequences zero then one")
        return F.Fleet{F.Slot{f,a,t,s,q,F.Presenting{packet,suboptimal,lost,shown}},rest,state}
    case _: IO.pure(V.VkResult(F.Fleet),Fail{(1,"Next ordered ready packet was not presented")})

def dispatch_pair(rest: List<F.Slot>, pair: F.Slot & F.Shared) -> V.Action(F.Fleet):
  (first,state) = pair
  dispatched_head(first,rest,state)

def dispatch_newer(device: V.Device, fleet: F.Fleet) -> V.Action(F.Fleet):
  F.Fleet{first,rest,state} = fleet
  do V.Action<F.Fleet>:
    pair : F.Slot & F.Shared <- F.service_slot(device,False{},first,state)
    dispatch_pair(rest,pair)

def ordered_presenting(+context: WSI.Context, fleet: F.Fleet) -> V.Action(F.Fleet):
  do V.Action<F.Fleet>:
    fleet : F.Fleet <- reversed(fleet)
    fleet : F.Fleet <- F.service(I.device(context),False{},fleet)
    fleet : F.Fleet <- ordered_dispatch(fleet)
    fleet : F.Fleet <- dispatch_newer(I.device(context),fleet)
    V.Action.lift(Unit,IO.print("Newer submitted slot waited for older present dispatch sequences zero then one"))
    return fleet

def reverse_completed(+context: WSI.Context, fleet: F.Fleet) -> V.Action(F.Fleet):
  do V.Action<F.Fleet>:
    fleet : F.Fleet <- ordered_presenting(context,fleet)
    fleet : F.Fleet <- walk(WaitPresent{I.device(context)},fleet)
    fleet : F.Fleet <- F.service(I.device(context),False{},fleet)
    newest_completion(fleet)

def checks(+context: WSI.Context, target: P.Target, +one: Expected, +two: Expected, fleet: F.Fleet) -> V.Action(Unit):
  WSI.Context{window,+instance,+physical,surface,+device,g,p} = context
  do V.Action<Unit>:
    fleet : F.Fleet <- walk(Pending{device},fleet)
    fleet : F.Fleet <- walk(WaitRender{device},fleet)
    fleet : F.Fleet <- walk(Uniform{device,one,two},fleet)
    fleet : F.Fleet <- reverse_completed(context,fleet)
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    fence : V.Fence <- V.Device.create_fence(device,False{})
    readbacks(context,target,CD.Context{instance,physical,device,command,fence},one,two,fleet)

def second_frozen(context: WSI.Context, target: P.Target, expected: Expected, pair: I.World & (F.Fleet & Expected)) -> V.Action(Unit):
  (world,(fleet,second)) = pair
  checks(context,target,expected,second,fleet)

def reset_world(+context: WSI.Context, +target: P.Target, fleet: F.Fleet, expected: Expected, palette: A.Palette, world: I.World) -> V.Action(Unit):
  do V.Action<Unit>:
    world : I.World <- I.reset(I.pointer(I.fly(I.key(world,119,True{}),16n),290,208))
    result : I.World & (F.Fleet & Expected) <- freeze(context,fleet,world,palette,I.output(I.format(Some{target})))
    second_frozen(context,target,expected,result)

def first_frozen(context: WSI.Context, target: P.Target, rest: List<F.Slot>, palette: A.Palette, pair: I.World & (F.Fleet & Expected)) -> V.Action(Unit):
  (world,(F.Fleet{first,none,state},expected)) = pair
  reset_world(context,target,F.Fleet{first,rest,state},expected,palette,world)

def first_only(+context: WSI.Context, +target: P.Target, +palette: A.Palette, world: I.World, fleet: F.Fleet) -> V.Action(Unit):
  F.Fleet{first,rest,shared} = fleet
  do V.Action<Unit>:
    result : I.World & (F.Fleet & Expected) <- freeze(context,F.Fleet{first,Nil{},shared},world,palette,I.output(I.format(Some{target})))
    first_frozen(context,target,rest,palette,result)

def after_events(+context: WSI.Context, target: P.Target, palette: A.Palette, fleet: F.Fleet, result: Maybe<I.World>) -> V.Action(Unit):
  do V.Action<Unit>:
    world : I.World <- edited(result)
    fleet : F.Fleet <- walk(WaitAcquire{I.device(context)},fleet)
    first_only(context,target,palette,world,fleet)

def acquired(+context: WSI.Context, target: P.Target, palette: A.Palette, fleet: F.Fleet, world: I.World) -> V.Action(Unit):
  do V.Action<Unit>:
    fleet : F.Fleet <- walk(Acquire{I.device(context)},fleet)
    events : Maybe<I.World> <- I.events([Move{405,408},Mouse{405,408,0,True{}},Move{291,209}],world,View.Mapping{640,480,640,480})
    after_events(context,target,palette,fleet,events)

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +context : WSI.Context <- WSI.open(entry,"Bend acquisition consistency",False{})
    +scene : Scene.Group <- I.scene_create(context)
    fleet : F.Fleet <- F.create(context,Scene.assets(scene),2,True{})
    raw : P.Target <- P.build(context,640,480)
    +target : P.Target <- P.promote(I.device(context),raw,Scene.assets(scene))
    fleet : F.Fleet <- F.retarget(context,Some{target},fleet)
    world : I.World <- I.initial_scene(I.Atelier{})
    acquired(context,target,Scene.palette(Scene.assets(scene)),fleet,world)

def camera_uploads(fleet: F.Fleet) -> V.Action(F.Fleet):
  F.Fleet{first,rest,+state} = fleet
  F.Shared{g,r,+u,n,p,replace,order} = state
  do V.Action<F.Fleet>:
    D.require(U32.is_zero(r) && U32.is_eq(u,4),"Second camera packet must reuse the same four installed chunk buffers")
    return F.Fleet{first,rest,state}

def wait_discarding(slot: F.Slot, device: V.Device) -> V.Action(F.Slot):
  F.Slot{f,a,t,s,q,phase} = slot
  match phase:
    case F.Discarding{packet}: rendered(F.Slot{f,a,t,s,q,F.Discarding{packet}},device)
    case phase: V.Action.pure(F.Slot,F.Slot{f,a,t,s,q,phase})

def discarded_count(shared: F.Shared, stage: U32) -> V.Action(Unit):
  F.Shared{g,r,u,frames,completed,replace,F.Ordering{next_submit,next_present}} = shared
  D.require(Core.sequence_ready(next_present,W.of_u32(stage)) && U32.is_zero(frames) && U32.is_eq(completed,4294967295),"Ordered acquisition release advanced the wrong sequence or counted an unpresented frame")

def discard_stage(fleet: F.Fleet, stage: U32) -> V.Action(F.Fleet):
  F.Fleet{F.Slot{f1,a1,t1,s1,q1,p1},rest,+shared} = fleet
  match p1 rest stage:
    case F.Discarding{first} Con{F.Slot{f2,a2,t2,s2,q2,F.Submitted{second,suboptimal}},Nil{}} 0:
      do V.Action<F.Fleet>:
        discarded_count(shared,0)
        return F.Fleet{F.Slot{f1,a1,t1,s1,q1,F.Discarding{first}},[F.Slot{f2,a2,t2,s2,q2,F.Submitted{second,suboptimal}}],shared}
    case F.Free{} Con{F.Slot{f2,a2,t2,s2,q2,F.Discarding{second}},Nil{}} 1:
      do V.Action<F.Fleet>:
        discarded_count(shared,1)
        return F.Fleet{F.Slot{f1,a1,t1,s1,q1,F.Free{}},[F.Slot{f2,a2,t2,s2,q2,F.Discarding{second}}],shared}
    case F.Free{} Con{F.Slot{f2,a2,t2,s2,q2,F.Free{}},Nil{}} 2:
      do V.Action<F.Fleet>:
        discarded_count(shared,2)
        return F.Fleet{F.Slot{f1,a1,t1,s1,q1,F.Free{}},[F.Slot{f2,a2,t2,s2,q2,F.Free{}}],shared}
    case _ _ _: IO.pure(V.VkResult(F.Fleet),Fail{(1,"Obsolete two-slot packets issued a present or lost their ordered release")})


def wait_discards(+device: V.Device, fleet: F.Fleet) -> V.Action(F.Fleet):
  F.Fleet{first,rest,shared} = fleet
  match rest:
    case [second]:
      do V.Action<F.Fleet>:
        first : F.Slot <- wait_discarding(first,device)
        second : F.Slot <- wait_discarding(second,device)
        return F.Fleet{first,[second],shared}
    case _: IO.pure(V.VkResult(F.Fleet),Fail{(1,"Recovery needs two slots")})

def recovery_checks(+context: WSI.Context, target: P.Target, fleet: F.Fleet) -> V.Action(Unit):
  do V.Action<Unit>:
    fleet : F.Fleet <- F.service(I.device(context),False{},F.recovery(True{},fleet))
    fleet : F.Fleet <- discard_stage(fleet,0)
    fleet : F.Fleet <- wait_discards(I.device(context),fleet)
    fleet : F.Fleet <- F.service(I.device(context),False{},fleet)
    fleet : F.Fleet <- discard_stage(fleet,1)
    fleet : F.Fleet <- wait_discards(I.device(context),fleet)
    fleet : F.Fleet <- F.service(I.device(context),False{},fleet)
    fleet : F.Fleet <- discard_stage(fleet,2)
    I.close(100000n,context,fleet,Some{target})
    V.Action.lift(Unit,IO.print("Two obsolete submitted packets drained exact semaphore waits and acquisition leases without presenting or counting either frame"))

def camera_finish(+context: WSI.Context, target: P.Target, fleet: F.Fleet, recover: Bool) -> V.Action(Unit):
  match recover:
    case True{}: recovery_checks(context,target,fleet)
    case False{}:
      do V.Action<Unit>:
        fleet : F.Fleet <- ordered_presenting(context,fleet)
        I.close(100000n,context,fleet,Some{target})
        V.Action.lift(Unit,IO.print("Same body revision camera packets obeyed actual submission order with two pending uniforms"))

def camera_checks(+recover: Bool, +context: WSI.Context, target: P.Target, +one: Expected, +two: Expected, fleet: F.Fleet) -> V.Action(Unit):
  do V.Action<Unit>:
    fleet : F.Fleet <- camera_uploads(fleet)
    fleet : F.Fleet <- walk(Pending{I.device(context)},fleet)
    fleet : F.Fleet <- walk(WaitRender{I.device(context)},fleet)
    fleet : F.Fleet <- walk(Uniform{I.device(context),one,two},fleet)
    camera_finish(context,target,fleet,recover)

def camera_second(recover: Bool, context: WSI.Context, target: P.Target, first: Expected, pair: I.World & (F.Fleet & Expected)) -> V.Action(Unit):
  Expected{+u1,+r1,+b1} = first
  (world,(fleet,second)) = pair
  Expected{+u2,+r2,+b2} = second
  do V.Action<Unit>:
    D.require(U32.is_zero(r1) && U32.is_zero(r2) && Bool.not(D.bytes_equal(E.copy_words(u1),E.copy_words(u2))),"Camera-only pair must retain revision zero and distinct input bytes")
    camera_checks(recover,context,target,Expected{u1,r1,b1},Expected{u2,r2,b2},fleet)

def camera_first(recover: Bool, +context: WSI.Context, +target: P.Target, rest: List<F.Slot>, palette: A.Palette, pair: I.World & (F.Fleet & Expected)) -> V.Action(Unit):
  (world,(F.Fleet{first,none,state},expected)) = pair
  do V.Action<Unit>:
    result : I.World & (F.Fleet & Expected) <- freeze(context,F.Fleet{first,rest,state},I.fly(I.key(world,119,True{}),16n),palette,I.output(I.format(Some{target})))
    camera_second(recover,context,target,expected,result)

def camera_acquired(recover: Bool, +context: WSI.Context, +target: P.Target, +palette: A.Palette, world: I.World, fleet: F.Fleet) -> V.Action(Unit):
  F.Fleet{first,rest,state} = fleet
  do V.Action<Unit>:
    result : I.World & (F.Fleet & Expected) <- freeze(context,F.Fleet{first,Nil{},state},world,palette,I.output(I.format(Some{target})))
    camera_first(recover,context,target,rest,palette,result)

def run_camera(recover: Bool, +entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +context : WSI.Context <- WSI.open(entry,"Bend camera submission order",False{})
    +scene : Scene.Group <- I.scene_create(context)
    fleet : F.Fleet <- F.create(context,Scene.assets(scene),2,True{})
    raw : P.Target <- P.build(context,640,480)
    +target : P.Target <- P.promote(I.device(context),raw,Scene.assets(scene))
    fleet : F.Fleet <- F.retarget(context,Some{target},fleet)
    world : I.World <- I.initial_scene(I.Cube{})
    fleet : F.Fleet <- walk(Acquire{I.device(context)},fleet)
    fleet : F.Fleet <- walk(WaitAcquire{I.device(context)},fleet)
    camera_acquired(recover,context,target,Scene.palette(Scene.assets(scene)),world,fleet)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    clean()
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run_presenting(entry))
    V.or_exit(Unit,result)
    clean()
    IO.print("Presenting camera/pointer state survived completion and populated a later acquisition without mesh upload")
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run_camera(False{},entry))
    V.or_exit(Unit,result)
    clean()
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run_camera(True{},entry))
    V.or_exit(Unit,result)
    clean()
