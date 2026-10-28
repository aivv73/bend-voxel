import Base
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/src/core.bend as Core
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W
import ../../voxel.bend as X
import ../src/scene.bend as Scene
import ../src/chunks.bend as C
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D
import ../../deps/bend-vulkan/examples/indexed_offscreen.bend as E
import ./chunk_device.bend as T
import ../src/generation.bend as G
import ../src/renderer.bend as GPU

def set(pair: X.Body & C.ChunkSet) -> C.ChunkSet:
  (body,chunks) = pair
  chunks

def initial_body(mixed: Bool) -> X.Body:
  match mixed:
    case False{}: X.Body.solid(3n)
    case True{}: X.Cuboids{[X.Cuboid{X.Cell{0,0,0},X.Cell{2,2,2},1},X.Cuboid{X.Cell{32,0,0},X.Cell{36,2,2},2},X.Cuboid{X.Cell{64,0,0},X.Cell{66,2,2},3}]}

def cut_candidate(pair: X.Body & C.ChunkSet) -> V.Action(C.ChunkSet):
  (body,chunks) = pair
  do V.Action<C.ChunkSet>:
    result : X.Body & C.ChunkSet <- T.built(C.cut(body,chunks,X.MetricSphere{X.PointCm{5.0,5.0,5.0},330.0},1))
    return set(result)

def candidate(mixed: Bool) -> V.Action(C.ChunkSet):
  match mixed:
    case False{}:
      do V.Action<C.ChunkSet>:
        result : X.Body & C.ChunkSet <- T.built(C.build(X.Body.filled(3n,2),1))
        return set(result)
    case True{}:
      do V.Action<C.ChunkSet>:
        original : X.Body & C.ChunkSet <- T.built(C.build(initial_body(True{}),0))
        cut_candidate(original)

def held_resident(mixed: Bool, chunks: List<&2,GPU.Resident>) -> V.Action(GPU.Resident):
  match mixed chunks:
    case True{} first <> second <> rest: V.Action.pure(GPU.Resident,second)
    case False{} first <> rest: V.Action.pure(GPU.Resident,first)
    case _ _: IO.pure(V.VkResult(GPU.Resident),Fail{(1,"Fixture needs installed residents")})

def live_pairs(+device: V.Device, pairs: List<(V.Buffer & V.DeviceMemory)>) -> V.Action(Unit):
  match pairs:
    case Nil{}: V.Action.pure(Unit,Unit{})
    case (buffer,memory) <> rest:
      do V.Action<Unit>:
        requirements : V.MemoryRequirements <- V.Device.get_buffer_memory_requirements(device,buffer)
        live_pairs(device,rest)

def rejected(result: V.VkResult(Scene.Group & C.ChunkSet)) -> V.Action(Unit):
  match result:
    case Done{value}: D.require(False{},"Recording index publication unexpectedly succeeded")
    case Fail{(code,message)}: D.require(U32.is_eq(code,1610612740),"Recording index rejection lost its primary or cleanup error")

def pair_ids(pairs: List<(V.Buffer & V.DeviceMemory)>) -> List<U32>:
  match pairs:
    case Nil{}: Nil{}
    case (V.Buffer{b},V.DeviceMemory{m}) <> rest: b <> m <> pair_ids(rest)

def retained_found(a: Maybe<&2,GPU.Resident>, b: Maybe<&2,GPU.Resident>) -> V.Action(Unit):
  match a b:
    case Some{x} Some{y}: D.require(D.bytes_equal(pair_ids(GPU.resident_pairs(x)),pair_ids(GPU.resident_pairs(y))),"Mixed publication replaced a retained resident")
    case _ _: D.require(False{},"Mixed publication lost its retained resident")

def retained(old: GPU.Geometry, next: GPU.Geometry, mixed: Bool) -> V.Action(Unit):
  match mixed:
    case False{}: V.Action.pure(Unit,Unit{})
    case True{}:
      +key : C.ChunkKey = C.ChunkKey{64,0,0,32}
      retained_found(GPU.find_resident(G.residents(old),key),GPU.find_resident(G.residents(next),key))

def retried(+context: T.Context, old: GPU.Geometry, +mixed: Bool, +rows: U32, result: Scene.Group & C.ChunkSet) -> V.Action(Unit):
  T.Context{instance,physical,+device,command,fence} = context
  (Scene.Group{a,+geometry,+revision,+uploads},C.ChunkSet{cs,ps,fs,bs,q,sq,+rebuilt,+kept}) = result
  do V.Action<Unit>:
    D.require(U32.is_eq(revision,1) && U32.is_eq(uploads,Bool.pick(U32,mixed,16,8)),"Successful retry changed revision or upload counters")
    retained(old,geometry,mixed)
    D.require(Bool.not(mixed) || (U32.is_eq(rebuilt,1) && U32.is_eq(kept,1) && U32.is_eq(U32.from_nat(List.length(&2,GPU.Resident,G.residents(geometry))),2)),"Mixed publication did not change/remove/reuse distinct chunks")
    V.Device.collect_retired(device)
    live : U32 <- V.debug_live_objects()
    D.require(U32.is_eq(live,Bool.pick(U32,mixed,(rows - 8 : U32),rows)),"Successful publication left obsolete allocations live")
    live_pairs(device,GPU.geometry_pairs(geometry))
    actual : List<&2,U32> <- T.read_geometry(context,geometry)
    D.require(Bool.not(List.is_empty(&2,U32,actual)),"Successful retry installed empty geometry")
    V.Action.lift(Unit,IO.print(Bool.pick(String,mixed,"Mixed reused/changed/removed generation retained exact resident handles after atomic rejection and retry","Index-only Recording publication rejection preserved all old bytes/handles/counters/rows and held command submitted before retry")))

def after_rejection(+context: T.Context, +scene: Scene.Group, +hold: V.CommandBuffer, +mixed: Bool, +expected: List<&2,U32>, +rows: U32, result: V.VkResult(Scene.Group & C.ChunkSet)) -> V.Action(Unit):
  T.Context{+instance,+physical,+device,+command,+fence} = context
  Scene.Group{a,+geometry,+revision,+uploads} = scene
  do V.Action<Unit>:
    rejected(result)
    live_pairs(device,GPU.geometry_pairs(geometry))
    actual : List<&2,U32> <- T.read_geometry(context,geometry)
    after : U32 <- V.debug_live_objects()
    D.require(D.bytes_equal(E.copy_words(expected),E.copy_words(actual)) && U32.is_eq(after,rows),"Rejected publication changed installed bytes or retained candidate/staging rows")
    D.require(U32.is_eq(revision,0) && U32.is_eq(uploads,Bool.pick(U32,mixed,12,4)),"Rejected publication changed installed counters")
    E.complete(device,hold,fence)
    E.reset(device,hold,fence)
    next : C.ChunkSet <- candidate(mixed)
    replacement : Scene.Group & C.ChunkSet <- Scene.install_chunks(instance,physical,device,command,fence,scene,1,next)
    retried(context,geometry,mixed,rows,replacement)

def recording(+context: T.Context, +scene: Scene.Group, +hold: V.CommandBuffer, +mixed: Bool, resident: GPU.Resident) -> V.Action(Unit):
  T.Context{+instance,+physical,+device,+command,+fence} = context
  Scene.Group{a,+geometry,r,u} = scene
  GPU.Resident{k,v,GPU.Stream{vertices,E.BoundBuffer{index,im},count},shadow} = resident
  do V.Action<Unit>:
    expected : List<&2,U32> <- T.read_geometry(context,geometry)
    V.CommandBuffer.begin(hold)
    V.CommandBuffer.bind_index_buffer(hold,index,W.zero(),1)
    next : C.ChunkSet <- candidate(mixed)
    before : U32 <- V.debug_live_objects()
    result : V.VkResult(Scene.Group & C.ChunkSet) <- V.Action.lift(V.VkResult(Scene.Group & C.ChunkSet),Scene.install_chunks(instance,physical,device,command,fence,scene,1,next))
    after_rejection(context,scene,hold,mixed,expected,before,result)

def installed(+context: T.Context, hold: V.CommandBuffer, +mixed: Bool, result: Scene.Group & C.ChunkSet) -> V.Action(Unit):
  (+scene,set) = result
  Scene.Group{a,geometry,r,u} = scene
  do V.Action<Unit>:
    resident : GPU.Resident <- held_resident(mixed,G.residents(geometry))
    recording(context,scene,hold,mixed,resident)

def context(entry: V.Entry) -> V.Action(T.Context & V.CommandBuffer):
  do V.Action<T.Context & V.CommandBuffer>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- D.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    family : U32 <- D.choose(Core.find_queue_family(families,1),"No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    hold : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    fence : V.Fence <- V.Device.create_fence(device,False{})
    return (T.Context{instance,physical,device,command,fence},hold)

def scene_run(+mixed: Bool, pair: T.Context & V.CommandBuffer) -> V.Action(Unit):
  (+context,hold) = pair
  T.Context{+instance,+physical,+device,+command,+fence} = context
  do V.Action<Unit>:
    scene : Scene.Group <- Scene.create(instance,physical,device)
    initial : X.Body & C.ChunkSet <- T.built(C.build(initial_body(mixed),0))
    result : Scene.Group & C.ChunkSet <- Scene.install_chunks(instance,physical,device,command,fence,scene,0,set(initial))
    installed(context,hold,mixed,result)

def run(+mixed: Bool, entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    pair : T.Context & V.CommandBuffer <- context(entry)
    scene_run(mixed,pair)

def main() -> IO(Unit):
  do IO<Unit>:
    first : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(False{},entry))
    V.or_exit(Unit,first)
    mixed : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(True{},entry))
    V.or_exit(Unit,mixed)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- D.require(U32.is_zero(count),"Recording publication scope leaked rows")
    V.or_exit(Unit,checked)
