import Base
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/src/core.bend as Core
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W
import ../../deps/bend-vulkan/src/upload.bend as Upload
import ../../deps/bend-vulkan/examples/window.bend as WSI
import ../../deps/bend-vulkan/examples/indexed_offscreen.bend as E
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D
import ./presentation.bend as P
import ./renderer.bend as GPU
import ./scene.bend as Scene
import ./chunks.bend as C
import ./generation.bend as G
import ./appearance.bend as A
import ./timing.bend as Timing
import ../../render.bend as R

type Packet is Data:
  Packet{acquisition: V.Acquisition, index: U32, revision: U32, started: W.U64, queries: Maybe<&2,V.QueryPool>, sequence: W.U64}
type Phase is Type:
  Free{}
  Acquiring{acquisition: V.Acquisition, index: U32, replace: Bool}
  Submitted{packet: Packet, replace: Bool}
  Presenting{packet: Packet, replace: Bool, lost: Bool, shown: Bool}
  Discarding{packet: Packet}
type Slot is Type:
  Slot{frame: P.Frame, assets: Scene.Assets, target: Maybe<&2,P.SlotTarget>, staging: Upload.Staging, queries: Maybe<&2,V.QueryPool>, phase: Phase}
type Ordering is Data:
  Ordering{next_submit: W.U64, next_present: W.U64}
type Shared is Data:
  Shared{geometry: GPU.Geometry, installed: U32, uploads: U32, frames: U32, completed: U32, recreate: Bool, ordering: Ordering}
type Fleet is Type:
  Fleet{first: Slot, rest: List<Slot>, shared: Shared}

type Visit is Data:
  Service{device: V.Device, trace: Bool}
  Acquire{device: V.Device}
  Drain{device: V.Device}
  Retarget{context: WSI.Context, target: Maybe<&2,P.Target>}

def slot(+context: WSI.Context, assets: Scene.Assets, trace: Bool) -> V.Action(Slot):
  WSI.Context{w,i,p,s,+device,g,q} = context
  do V.Action<Slot>:
    frame : P.Frame <- P.frame(device)
    queries : Maybe<&2,V.QueryPool> <- Timing.create(device,trace)
    return Slot{frame,assets,None{},Upload.Empty{},queries,Free{}}

def idle_slot(slot: Slot) -> Slot & Bool:
  Slot{f,a,t,s,q,phase} = slot
  match phase:
    case Free{}: (Slot{f,a,t,s,q,Free{}},True{})
    case phase: (Slot{f,a,t,s,q,phase},False{})

def target_drop(device: V.Device, target: Maybe<&2,P.SlotTarget>) -> V.Action(Unit):
  match target:
    case None{}: V.Action.pure(Unit,Unit{})
    case Some{target}: P.slot_destroy(device,target)

def retarget_slot(+context: WSI.Context, slot: Slot, target: Maybe<&2,P.Target>) -> V.Action(Slot):
  WSI.Context{w,i,p,s,+device,g,q} = context
  Slot{f,a,old,storage,queries,phase} = slot
  match target:
    case None{}:
      do V.Action<Slot>:
        target_drop(device,old)
        return Slot{f,a,None{},storage,queries,phase}
    case Some{target}:
      do V.Action<Slot>:
        target_drop(device,old)
        local : P.SlotTarget <- P.slot_target(context,target)
        return Slot{f,a,Some{local},storage,queries,phase}

def presented(+device: V.Device, slot: Slot, shared: Shared, packet: Packet, replace: Bool, lost: Bool, +shown: Bool, status: U32) -> V.Action(Slot & Shared):
  Slot{+frame,a,t,s,q,phase} = slot
  P.Frame{pool,+command,acquire,render,+present,finished} = frame
  Shared{geo,installed,uploads,+frames,+revision,recreate,order} = shared
  Packet{acquisition,index,+packet_revision,started,view,sequence} = packet
  match status:
    case 0:
      do V.Action<Slot & Shared>:
        V.Fence.reset(present)
        V.CommandBuffer.reset(command)
        V.Device.collect_retired(device)
        D.require(Bool.not(lost),"Surface lost after matching presentation completion")
        return (Slot{frame,a,t,s,q,Free{}},Shared{geo,installed,uploads,(frames + Bool.to_u32(shown) : U32),Bool.pick(U32,shown,Core.completed_revision(revision,packet_revision),revision),recreate || replace,order})
    case _:
      V.Action.pure(Slot & Shared,(Slot{frame,a,t,s,q,Presenting{Packet{acquisition,index,packet_revision,started,view,sequence},replace,lost,shown}},shared))

def advance_presentation(shared: Shared, replace: Bool) -> Shared:
  Shared{g,r,u,n,p,recreate,Ordering{next_submit,next_present}} = shared
  Shared{g,r,u,n,p,recreate || replace,Ordering{next_submit,W.add(next_present,W.of_u32(1))}}

def present_outcome(slot: Slot, shared: Shared, packet: Packet, +replace: Bool, outcome: V.PresentOutcome) -> Slot & Shared:
  Slot{f,a,t,s,q,phase} = slot
  match outcome:
    case V.Presented{}: (Slot{f,a,t,s,q,Presenting{packet,replace,False{},True{}}},advance_presentation(shared,replace))
    case V.PresentSuboptimal{}: (Slot{f,a,t,s,q,Presenting{packet,True{},False{},True{}}},advance_presentation(shared,True{}))
    case V.PresentOutOfDate{}: (Slot{f,a,t,s,q,Presenting{packet,True{},False{},False{}}},advance_presentation(shared,True{}))
    case V.PresentSurfaceLost{}: (Slot{f,a,t,s,q,Presenting{packet,True{},True{},False{}}},advance_presentation(shared,True{}))

def discard_completed(+device: V.Device, slot: Slot, shared: Shared, packet: Packet, status: U32) -> V.Action(Slot & Shared):
  Slot{+frame,a,t,s,q,phase} = slot
  P.Frame{pool,+command,acquire,+render,present,finished} = frame
  Packet{acquisition,index,revision,started,queries,sequence} = packet
  match status:
    case 0:
      do V.Action<Slot & Shared>:
        V.CommandBuffer.reset(command)
        V.Fence.reset(render)
        V.Device.release_acquired(device,acquisition)
        V.Device.collect_retired(device)
        return (Slot{frame,a,t,s,q,Free{}},advance_presentation(shared,True{}))
    case _: V.Action.pure(Slot & Shared,(Slot{frame,a,t,s,q,Discarding{packet}},shared))

def discard_rendered(+device: V.Device, +trace: Bool, slot: Slot, shared: Shared, packet: Packet) -> V.Action(Slot & Shared):
  Slot{+frame,a,t,s,q,phase} = slot
  P.Frame{pool,+command,acquire,+render,present,finished} = frame
  Packet{acquisition,index,revision,+started,+queries,sequence} = packet
  do V.Action<Slot & Shared>:
    Timing.observe(device,queries,started,trace)
    V.CommandBuffer.reset(command)
    V.Fence.reset(render)
    V.CommandBuffer.begin(command)
    V.CommandBuffer.end(command)
    V.Device.submit_synced(device,command,render,[V.SemaphoreWait{finished,8192}],[])
    return (Slot{frame,a,t,s,q,Discarding{packet}},shared)

def render_completed(+device: V.Device, +trace: Bool, slot: Slot, shared: Shared, packet: Packet, +replace: Bool, obsolete: Bool) -> V.Action(Slot & Shared):
  Slot{+frame,a,t,s,q,phase} = slot
  P.Frame{pool,command,acquire,render,+present,+finished} = frame
  Packet{+acquisition,index,revision,+started,+view,sequence} = packet
  match obsolete:
    case True{}: discard_rendered(device,trace,Slot{frame,a,t,s,q,Free{}},shared,packet)
    case False{}:
      do V.Action<Slot & Shared>:
        Timing.observe(device,view,started,trace)
        before : W.U64 <- V.monotonic_ns()
        outcome : V.PresentOutcome <- V.Device.present(device,acquisition,finished,present)
        after : W.U64 <- V.monotonic_ns()
        Timing.cpu(trace,"present_call",before,after)
        return present_outcome(Slot{frame,a,t,s,q,Free{}},shared,packet,replace,outcome)

def recreating(shared: Shared) -> Bool:
  Shared{g,r,u,n,p,recreate,order} = shared
  recreate

def rendered_ready(+device: V.Device, +trace: Bool, slot: Slot, +shared: Shared, packet: Packet, +replace: Bool, status: U32, allowed: Bool) -> V.Action(Slot & Shared):
  Slot{+frame,a,t,s,+q,phase} = slot
  P.Frame{pool,command,acquire,render,+present,+finished} = frame
  Packet{+acquisition,index,revision,+started,+view,+sequence} = packet
  match status allowed:
    case 0 True{}: render_completed(device,trace,Slot{frame,a,t,s,q,Free{}},shared,packet,replace,recreating(shared))
    case _ _: V.Action.pure(Slot & Shared,(Slot{frame,a,t,s,q,Submitted{Packet{acquisition,index,revision,started,view,sequence},replace}},shared))

def presentation_ready(shared: Shared, packet: Packet) -> Bool:
  Shared{g,r,u,n,p,recreate,Ordering{next_submit,next_present}} = shared
  Packet{a,i,revision,s,q,sequence} = packet
  Core.sequence_ready(next_present,sequence)

def rendered(device: V.Device, trace: Bool, slot: Slot, +shared: Shared, +packet: Packet, replace: Bool, status: U32) -> V.Action(Slot & Shared):
  rendered_ready(device,trace,slot,shared,packet,replace,status,presentation_ready(shared,packet))

def service_slot(+device: V.Device, +trace: Bool, slot: Slot, shared: Shared) -> V.Action(Slot & Shared):
  Slot{+frame,a,t,s,q,phase} = slot
  P.Frame{pool,command,acquire,+render,+present,finished} = frame
  match phase:
    case Submitted{packet,replace}:
      do V.Action<Slot & Shared>:
        status : U32 <- V.Fence.status(render)
        rendered(device,trace,Slot{frame,a,t,s,q,Free{}},shared,packet,replace,status)
    case Discarding{packet}:
      do V.Action<Slot & Shared>:
        status : U32 <- V.Fence.status(render)
        discard_completed(device,Slot{frame,a,t,s,q,Free{}},shared,packet,status)
    case Presenting{packet,replace,lost,shown}:
      do V.Action<Slot & Shared>:
        status : U32 <- V.Fence.status(present)
        presented(device,Slot{frame,a,t,s,q,Free{}},shared,packet,replace,lost,shown,status)
    case phase: V.Action.pure(Slot & Shared,(Slot{frame,a,t,s,q,phase},shared))

def acquired(slot: Slot, shared: Shared, outcome: V.AcquireOutcome) -> Slot & Shared:
  Slot{f,a,t,s,q,phase} = slot
  Shared{geo,r,u,n,p,replace,order} = shared
  match outcome:
    case V.Acquired{acquisition,index,suboptimal}: (Slot{f,a,t,s,q,Acquiring{acquisition,index,suboptimal}},shared)
    case V.AcquireOutOfDate{}: (Slot{f,a,t,s,q,Free{}},Shared{geo,r,u,n,p,True{},order})
    case V.AcquireSurfaceLost{}: (Slot{f,a,t,s,q,Free{}},Shared{geo,r,u,n,p,True{},order})
    case _: (Slot{f,a,t,s,q,Free{}},shared)

def swapchain(target: P.SlotTarget) -> V.Swapchain:
  P.SlotTarget{P.Target{sc,shared,pass,layout,pipeline,w,h,format,programs},images,depth} = target
  sc

def acquire_slot_ready(device: V.Device, slot: Slot, shared: Shared) -> V.Action(Slot & Shared):
  Slot{+frame,a,t,s,q,phase} = slot
  P.Frame{pool,command,+acquire,render,present,finished} = frame
  match t phase:
    case Some{+target} Free{}:
      do V.Action<Slot & Shared>:
        outcome : V.AcquireOutcome <- V.Device.acquire(device,swapchain(target),acquire,W.zero())
        return acquired(Slot{frame,a,Some{target},s,q,Free{}},shared,outcome)
    case t phase: V.Action.pure(Slot & Shared,(Slot{frame,a,t,s,q,phase},shared))

def acquire_if(device: V.Device, slot: Slot, shared: Shared, obsolete: Bool) -> V.Action(Slot & Shared):
  match obsolete:
    case True{}: V.Action.pure(Slot & Shared,(slot,shared))
    case False{}: acquire_slot_ready(device,slot,shared)

def acquire_slot(device: V.Device, slot: Slot, +shared: Shared) -> V.Action(Slot & Shared):
  acquire_if(device,slot,shared,recreating(shared))

def draw_mode(+command: V.CommandBuffer, assets: Scene.Assets, programs: Maybe<&2,Scene.Programs>, framebuffer: V.Framebuffer, pipeline: V.GraphicsPipeline, +w: U32, +h: U32, +geometry: GPU.Geometry, revision: U32, uploads: U32, basis: R.Basis, cube: Bool, queries: Maybe<&2,V.QueryPool>) -> V.Action(Unit):
  match programs cube:
    case Some{programs} False{}: Scene.record(command,Scene.Group{assets,geometry,revision,uploads},programs,framebuffer,w,h,True{},queries)
    case _ True{}:
      do V.Action<Unit>:
        GPU.publish(command,geometry)
        V.CommandBuffer.begin_render_pass(command,framebuffer,V.RenderArea{V.Offset2D{0,0},V.Extent2D{w,h}},[V.ColorClear{V.ClearColor{0.025,0.035,0.055,1.0}},V.DepthClear{1.0}])
        V.CommandBuffer.bind_graphics_pipeline(command,pipeline)
        Scene.viewport(command,w,h)
        V.CommandBuffer.push_constants(command,GPU.matrix_extent(basis,w,h))
        GPU.draw(command,geometry)
        V.CommandBuffer.end_render_pass(command)
    case _ _: D.require(False{},"Slot has no production programs")

def draw(+device: V.Device, +command: V.CommandBuffer, assets: Scene.Assets, target: P.SlotTarget, image: P.ImageTarget, queries: Maybe<&2,V.QueryPool>, +geometry: GPU.Geometry, revision: U32, uploads: U32, input: A.FrameInput, cube: Bool) -> V.Action(Unit):
  P.SlotTarget{P.Target{sc,shared,pass,layout,pipeline,+w,+h,format,programs},images,E.Attachment{+depth,dm,dv}} = target
  P.ImageTarget{+color,view,+framebuffer} = image
  A.FrameInput{basis,iw,ih,extent,palette,brush,output,mode} = input
  do V.Action<Unit>:
    E.transition(command,color,1,0,2,1024,1024,0,256)
    E.transition(command,depth,2,0,3,768,768,0,1536)
    draw_mode(command,assets,programs,framebuffer,pipeline,w,h,geometry,revision,uploads,basis,cube,queries)
    E.transition(command,color,1,2,1000001002,1024,8192,256,0)

def record(+device: V.Device, +frame: P.Frame, +assets: Scene.Assets, +target: P.SlotTarget, +queries: Maybe<&2,V.QueryPool>, +plan: G.Plan, acquisition: V.Acquisition, index: U32, +revision: U32, +uploads: U32, input: A.FrameInput, cube: Bool) -> V.Action(Maybe<&2,V.QueryPool>):
  P.Frame{pool,+command,acquire,+render,present,+finished} = frame
  P.SlotTarget{P.Target{sc,shared,pass,layout,pipeline,+w,+h,format,programs},+images,E.Attachment{+depth,dm,dv}} = target
  G.Plan{+geometry,copies,created,bytes} = plan
  do V.Action<Maybe<&2,V.QueryPool>>:
    image : P.ImageTarget <- P.at(images,index)
    V.CommandBuffer.begin(command)
    V.CommandBuffer.use_acquisition(command,acquisition)
    +active : Maybe<&2,V.QueryPool> <- Timing.reset(command,queries)
    Timing.write(command,active,0)
    G.record(command,plan)
    Timing.write(command,active,1)
    draw(device,command,assets,target,image,active,geometry,revision,uploads,input,cube)
    V.CommandBuffer.end(command)
    V.Fence.reset(render)
    V.Device.submit_synced(device,command,render,[],[finished])
    return active

def publish_generation(changed: Bool, device: V.Device, old: GPU.Geometry, next: GPU.Geometry) -> V.Action(Unit):
  match changed:
    case False{}: V.Action.pure(Unit,Unit{})
    case True{}: G.commit(device,old,next)

def submitted(+device: V.Device, slot: Slot, shared: Shared, +plan: G.Plan, packet: Packet, replace: Bool, set: C.ChunkSet, result: V.VkResult(Maybe<&2,V.QueryPool>)) -> V.Action((C.ChunkSet & Slot) & Shared):
  Slot{+frame,a,t,+storage,q,phase} = slot
  P.Frame{pool,command,acquire,render,present,finished} = frame
  Shared{+old,previous,+uploads,frames,presented,recreate,Ordering{next_submit,next_present}} = shared
  G.Plan{+geometry,+copies,created,bytes} = plan
  Packet{acquisition,index,+revision,started,view,sequence} = packet
  match result:
    case Fail{(+code,+message)}:
      do V.Action<(C.ChunkSet & Slot) & Shared>:
        Scene.failed_install(device,command,plan,storage,Fail{(code,message)})
        IO.pure(V.VkResult((C.ChunkSet & Slot) & Shared),Fail{(code,message)})
    case Done{active}:
      do V.Action<(C.ChunkSet & Slot) & Shared>:
        publish_generation(U32.is_ne(previous,revision),device,old,geometry)
        return ((set,Slot{frame,a,t,storage,q,Submitted{Packet{acquisition,index,revision,started,active,sequence},replace}}),Shared{geometry,revision,(uploads + U32.from_nat(List.length(&2,G.Copy,copies)) : U32),frames,presented,recreate,Ordering{W.add(next_submit,W.of_u32(1)),next_present}})

def asset_uniform(a: Scene.Assets) -> E.BoundBuffer:
  Scene.Assets{uniform,s,ss,p,f,sd,sampler,shadow,sp,sf,ps,fl,ml,indices,palette} = a
  uniform

def submission_sequence(shared: Shared) -> W.U64:
  Shared{g,r,u,f,p,replace,Ordering{next_submit,next_present}} = shared
  next_submit

def required_sequence(value: Maybe<&2,W.U64>) -> V.Action(W.U64):
  match value:
    case None{}: IO.pure(V.VkResult(W.U64),Fail{(1610612741,"Submission sequence exhausted")})
    case Some{next}: V.Action.pure(W.U64,next)

def upload_count(shared: Shared) -> U32:
  Shared{g,r,u,f,p,replace,order} = shared
  u

def record_input(+device: V.Device, +trace: Bool, frame: P.Frame, +a: Scene.Assets, target: P.SlotTarget, queries: Maybe<&2,V.QueryPool>, plan: G.Plan, acquisition: V.Acquisition, index: U32, revision: U32, uploads: U32, input: A.FrameInput, cube: Bool, started: W.U64, words: Array<U32>) -> V.Action(Maybe<&2,V.QueryPool>):
  do V.Action<Maybe<&2,V.QueryPool>>:
    words : Array<U32> <- GPU.upload(device,asset_uniform(a),2336,words)
    +before : W.U64 <- V.monotonic_ns()
    Timing.cpu(trace,"upload_prepare",started,before)
    +view : Maybe<&2,V.QueryPool> <- record(device,frame,a,target,queries,plan,acquisition,index,revision,uploads,input,cube)
    after : W.U64 <- V.monotonic_ns()
    Timing.cpu(trace,"record_and_submit",before,after)
    return view

def encoded(+device: V.Device, +trace: Bool, slot: Slot, +shared: Shared, +plan: G.Plan, +acquisition: V.Acquisition, +index: U32, +replace: Bool, +revision: U32, +input: A.FrameInput, cube: Bool, set: C.ChunkSet, +started: W.U64, words: Maybe<Array<U32>>) -> V.Action((C.ChunkSet & Slot) & Shared):
  Slot{+frame,+a,+t,+storage,+q,phase} = slot
  P.Frame{pool,command,acquire,render,present,finished} = frame
  match t words:
    case Some{+target} Some{words}:
      do V.Action<(C.ChunkSet & Slot) & Shared>:
        +before : W.U64 <- V.monotonic_ns()
        result : V.VkResult(Maybe<&2,V.QueryPool>) <- V.Action.lift(V.VkResult(Maybe<&2,V.QueryPool>),record_input(device,trace,frame,a,target,q,plan,acquisition,index,revision,upload_count(shared),input,cube,started,words))
        submitted(device,Slot{frame,a,Some{target},storage,q,Free{}},shared,plan,Packet{acquisition,index,revision,before,None{},submission_sequence(shared)},replace,set,result)
    case _ _:
      do V.Action<(C.ChunkSet & Slot) & Shared>:
        Scene.failed_install(device,command,plan,storage,Fail{(1,"Invalid frozen frame input or target")})
        IO.pure(V.VkResult((C.ChunkSet & Slot) & Shared),Fail{(1,"Invalid frozen frame input or target")})

def prepared(+device: V.Device, +trace: Bool, slot: Slot, shared: Shared, acquisition: V.Acquisition, index: U32, replace: Bool, revision: U32, +input: A.FrameInput, cube: Bool, started: W.U64, pair: (C.ChunkSet & Upload.Staging) & V.VkResult(G.Plan)) -> V.Action((C.ChunkSet & Slot) & Shared):
  Slot{f,a,t,old,q,phase} = slot
  ((set,storage),result) = pair
  match result:
    case Fail{error}:
      do IO<V.VkResult((C.ChunkSet & Slot) & Shared)>:
        cleanup : V.VkResult(Unit) <- Upload.release(device,storage)
        return V.Entry.finish((C.ChunkSet & Slot) & Shared,Fail{error},cleanup)
    case Done{+plan}:
      +staging : Upload.Staging = storage
      encoded(device,trace,Slot{f,a,t,staging,q,Free{}},shared,plan,acquisition,index,replace,revision,input,cube,set,started,A.encode(input))

def prepare_generation(unchanged: Bool, instance: V.Instance, physical: V.PhysicalDevice, device: V.Device, geometry: GPU.Geometry, storage: Upload.Staging, set: C.ChunkSet) -> IO((C.ChunkSet & Upload.Staging) & V.VkResult(G.Plan)):
  match unchanged:
    case True{}: IO.pure((C.ChunkSet & Upload.Staging) & V.VkResult(G.Plan),((set,Upload.reset(storage)),Done{G.Plan{geometry,Nil{},Nil{},W.zero()}}))
    case False{}: G.prepare(instance,physical,device,geometry,storage,set)

def ready(+context: WSI.Context, +trace: Bool, slot: Slot, +shared: Shared, set: C.ChunkSet, acquisition: V.Acquisition, index: U32, replace: Bool, +revision: U32, input: A.FrameInput, cube: Bool, status: U32) -> V.Action((C.ChunkSet & Slot) & Shared):
  WSI.Context{w,+instance,+physical,s,+device,g,p} = context
  Slot{+frame,a,t,storage,q,phase} = slot
  P.Frame{pool,+command,+acquire,render,present,finished} = frame
  Shared{+geometry,installed,uploads,frames,presented,recreate,order} = shared
  match status:
    case 0:
      do V.Action<(C.ChunkSet & Slot) & Shared>:
        available : W.U64 <- required_sequence(Core.sequence_next(submission_sequence(shared)))
        V.Fence.reset(acquire)
        V.Device.collect_retired(device)
        +started : W.U64 <- V.monotonic_ns()
        pair : (C.ChunkSet & Upload.Staging) & V.VkResult(G.Plan) <- V.Action.lift((C.ChunkSet & Upload.Staging) & V.VkResult(G.Plan),prepare_generation(U32.is_eq(installed,revision),instance,physical,device,geometry,storage,set))
        prepared(device,trace,Slot{frame,a,t,Upload.Empty{},q,Free{}},shared,acquisition,index,replace,revision,input,cube,started,pair)
    case _: V.Action.pure((C.ChunkSet & Slot) & Shared,((set,Slot{frame,a,t,storage,q,Acquiring{acquisition,index,replace}}),shared))

def render_slot(+context: WSI.Context, trace: Bool, slot: Slot, shared: Shared, set: C.ChunkSet, revision: U32, input: A.FrameInput, cube: Bool) -> V.Action((C.ChunkSet & Slot) & Shared):
  Slot{+frame,a,t,s,q,phase} = slot
  P.Frame{pool,command,+acquire,render,present,finished} = frame
  match phase:
    case Acquiring{acquisition,index,replace}:
      do V.Action<(C.ChunkSet & Slot) & Shared>:
        status : U32 <- V.Fence.status(acquire)
        ready(context,trace,Slot{frame,a,t,s,q,Free{}},shared,set,acquisition,index,replace,revision,input,cube,status)
    case phase: V.Action.pure((C.ChunkSet & Slot) & Shared,((set,Slot{frame,a,t,s,q,phase}),shared))

def drain_ready(+device: V.Device, slot: Slot, acquisition: V.Acquisition, index: U32, replace: Bool, status: U32) -> V.Action(Slot):
  Slot{+frame,a,t,s,q,phase} = slot
  P.Frame{pool,command,+acquire,render,present,finished} = frame
  match status:
    case 0:
      do V.Action<Slot>:
        V.Device.release_acquired(device,acquisition)
        V.Fence.reset(acquire)
        return Slot{frame,a,t,s,q,Free{}}
    case _: V.Action.pure(Slot,Slot{frame,a,t,s,q,Acquiring{acquisition,index,replace}})

def drain_slot(device: V.Device, slot: Slot) -> V.Action(Slot):
  Slot{+frame,a,t,s,q,phase} = slot
  P.Frame{pool,command,+acquire,render,present,finished} = frame
  match phase:
    case Acquiring{acquisition,index,replace}:
      do V.Action<Slot>:
        status : U32 <- V.Fence.status(acquire)
        drain_ready(device,Slot{frame,a,t,s,q,Free{}},acquisition,index,replace,status)
    case phase: V.Action.pure(Slot,Slot{frame,a,t,s,q,phase})


def idle_cons(pair: Slot & Bool, tail: List<Slot> & Bool) -> List<Slot> & Bool:
  (slot,a) = pair
  (rest,b) = tail
  (slot <> rest,a && b)

def idle_slots(xs: List<Slot>) -> List<Slot> & Bool:
  match xs:
    case Nil{}: (Nil{},True{})
    case slot <> rest: idle_cons(idle_slot(slot),idle_slots(rest))

def drain_visit(device: V.Device, slot: Slot, shared: Shared) -> V.Action(Slot & Shared):
  do V.Action<Slot & Shared>:
    slot : Slot <- drain_slot(device,slot)
    return (slot,shared)

def retarget_visit(context: WSI.Context, target: Maybe<&2,P.Target>, slot: Slot, shared: Shared) -> V.Action(Slot & Shared):
  do V.Action<Slot & Shared>:
    slot : Slot <- retarget_slot(context,slot,target)
    return (slot,shared)

def visit_action(operation: Visit, slot: Slot, shared: Shared) -> V.Action(Slot & Shared):
  match operation:
    case Service{device,trace}: service_slot(device,trace,slot,shared)
    case Acquire{device}: acquire_slot(device,slot,shared)
    case Drain{device}: drain_visit(device,slot,shared)
    case Retarget{context,target}: retarget_visit(context,target,slot,shared)

def visit_cons(slot: Slot, pair: List<Slot> & Shared) -> List<Slot> & Shared:
  (rest,shared) = pair
  (slot <> rest,shared)

def visit_head(pair: Slot & Shared, next: Shared -> V.Action(List<Slot> & Shared)) -> V.Action(List<Slot> & Shared):
  (slot,shared) = pair
  do V.Action<List<Slot> & Shared>:
    tail : List<Slot> & Shared <- next(shared)
    return visit_cons(slot,tail)

def visit(fuel: Nat, slots: List<Slot>, shared: Shared, +operation: Visit) -> V.Action(List<Slot> & Shared):
  match fuel slots:
    case 0n Nil{}: V.Action.pure(List<Slot> & Shared,(Nil{},shared))
    case 0n _: IO.pure(V.VkResult(List<Slot> & Shared),Fail{(1,"Frame slot configuration exceeds two owners")})
    case 1n+rest Nil{}: V.Action.pure(List<Slot> & Shared,(Nil{},shared))
    case 1n+rest slot <> tail:
      do V.Action<List<Slot> & Shared>:
        pair : Slot & Shared <- visit_action(operation,slot,shared)
        visit_head(pair,state => visit(rest,tail,state,operation))

def render_cons(slot: Slot, pair: C.ChunkSet & (List<Slot> & Shared)) -> C.ChunkSet & (List<Slot> & Shared):
  (set,(rest,shared)) = pair
  (set,(slot <> rest,shared))

def render_head(pair: (C.ChunkSet & Slot) & Shared, next: C.ChunkSet -> Shared -> V.Action(C.ChunkSet & (List<Slot> & Shared))) -> V.Action(C.ChunkSet & (List<Slot> & Shared)):
  ((set,slot),shared) = pair
  do V.Action<C.ChunkSet & (List<Slot> & Shared)>:
    tail : C.ChunkSet & (List<Slot> & Shared) <- next(set,shared)
    return render_cons(slot,tail)

def render_slots(fuel: Nat, slots: List<Slot>, shared: Shared, set: C.ChunkSet, +context: WSI.Context, +trace: Bool, +revision: U32, +input: A.FrameInput, +cube: Bool) -> V.Action(C.ChunkSet & (List<Slot> & Shared)):
  match fuel slots:
    case 0n Nil{}: V.Action.pure(C.ChunkSet & (List<Slot> & Shared),(set,(Nil{},shared)))
    case 0n _: IO.pure(V.VkResult(C.ChunkSet & (List<Slot> & Shared)),Fail{(1,"Frame slot configuration exceeds two owners")})
    case 1n+rest Nil{}: V.Action.pure(C.ChunkSet & (List<Slot> & Shared),(set,(Nil{},shared)))
    case 1n+rest slot <> tail:
      do V.Action<C.ChunkSet & (List<Slot> & Shared)>:
        pair : (C.ChunkSet & Slot) & Shared <- render_slot(context,trace,slot,shared,set,revision,input,cube)
        render_head(pair,next => state => render_slots(rest,tail,state,next,context,trace,revision,input,cube))


def create(+context: WSI.Context, +assets: Scene.Assets, count: U32, +trace: Bool) -> V.Action(Fleet):
  WSI.Context{w,instance,physical,s,+device,g,q} = context
  match count:
    case 1:
      do V.Action<Fleet>:
        first : Slot <- slot(context,assets,trace)
        return Fleet{first,Nil{},Shared{GPU.Empty{},4294967295,0,0,4294967295,False{},Ordering{W.zero(),W.zero()}}}
    case _:
      do V.Action<Fleet>:
        first : Slot <- slot(context,assets,trace)
        extra : Scene.Assets <- Scene.slot_assets(instance,physical,device,assets)
        second : Slot <- slot(context,extra,trace)
        return Fleet{first,[second],Shared{GPU.Empty{},4294967295,0,0,4294967295,False{},Ordering{W.zero(),W.zero()}}}

def idle_done(shared: Shared, head: Slot & Bool, tail: List<Slot> & Bool) -> Fleet & Bool:
  (first,a) = head
  (rest,b) = tail
  (Fleet{first,rest,shared},a && b)

def idle(fleet: Fleet) -> Fleet & Bool:
  Fleet{first,rest,shared} = fleet
  idle_done(shared,idle_slot(first),idle_slots(rest))

def fleet_tail(first: Slot, pair: List<Slot> & Shared) -> Fleet:
  (rest,shared) = pair
  Fleet{first,rest,shared}

def fleet_head(pair: Slot & Shared, next: Shared -> V.Action(List<Slot> & Shared)) -> V.Action(Fleet):
  (first,shared) = pair
  do V.Action<Fleet>:
    tail : List<Slot> & Shared <- next(shared)
    return fleet_tail(first,tail)

def visit_fleet(fleet: Fleet, +operation: Visit) -> V.Action(Fleet):
  Fleet{first,rest,shared} = fleet
  do V.Action<Fleet>:
    pair : Slot & Shared <- visit_action(operation,first,shared)
    fleet_head(pair,state => visit(1n,rest,state,operation))

def service(+device: V.Device, +trace: Bool, fleet: Fleet) -> V.Action(Fleet):
  visit_fleet(fleet,Service{device,trace})

def acquire(+device: V.Device, fleet: Fleet) -> V.Action(Fleet):
  visit_fleet(fleet,Acquire{device})

def drain(+device: V.Device, fleet: Fleet) -> V.Action(Fleet):
  visit_fleet(fleet,Drain{device})

def retarget(+context: WSI.Context, +target: Maybe<&2,P.Target>, fleet: Fleet) -> V.Action(Fleet):
  visit_fleet(fleet,Retarget{context,target})

def render_fleet_tail(first: Slot, pair: C.ChunkSet & (List<Slot> & Shared)) -> C.ChunkSet & Fleet:
  (set,(rest,shared)) = pair
  (set,Fleet{first,rest,shared})

def render_fleet_head(pair: (C.ChunkSet & Slot) & Shared, next: C.ChunkSet -> Shared -> V.Action(C.ChunkSet & (List<Slot> & Shared))) -> V.Action(C.ChunkSet & Fleet):
  ((set,first),shared) = pair
  do V.Action<C.ChunkSet & Fleet>:
    tail : C.ChunkSet & (List<Slot> & Shared) <- next(set,shared)
    return render_fleet_tail(first,tail)

def render(+context: WSI.Context, +trace: Bool, fleet: Fleet, set: C.ChunkSet, +revision: U32, +input: A.FrameInput, +cube: Bool) -> V.Action(C.ChunkSet & Fleet):
  Fleet{first,rest,shared} = fleet
  do V.Action<C.ChunkSet & Fleet>:
    pair : (C.ChunkSet & Slot) & Shared <- render_slot(context,trace,first,shared,set,revision,input,cube)
    render_fleet_head(pair,next => state => render_slots(1n,rest,state,next,context,trace,revision,input,cube))

def recovery(requested: Bool, fleet: Fleet) -> Fleet:
  Fleet{first,rest,Shared{g,r,u,n,p,recreate,order}} = fleet
  Fleet{first,rest,Shared{g,r,u,n,p,recreate || requested,order}}
