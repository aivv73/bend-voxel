import Base
import ./geometry_device.bend as CPU
import ../src/mesh.bend as M
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/src/upload.bend as U
import ../../deps/bend-vulkan/src/core.bend as Core
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W
import ../../voxel.bend as X
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D
import ../../deps/bend-vulkan/examples/indexed_offscreen.bend as E
import ../src/chunks.bend as C
import ../src/exterior.bend as Exterior
import ../src/generation.bend as G
import ../src/renderer.bend as GPU

def built(pair: X.Body & Result<&2,&1,Exterior.Error,C.ChunkSet>) -> V.Action(X.Body & C.ChunkSet):
  (body,result) = pair
  match result:
    case Fail{error}: IO.pure(V.VkResult(X.Body & C.ChunkSet),Fail{(1,Exterior.error_show(error))})
    case Done{set}: V.Action.pure(X.Body & C.ChunkSet,(body,set))

def copied_back(+command: V.CommandBuffer, +destination: V.Buffer, xs: List<&2,G.Copy>) -> V.Action(Unit):
  match xs:
    case Nil{}: V.Action.pure(Unit,Unit{})
    case G.Copy{U.Slice{source,offset,length},buffer} <> rest:
      do V.Action<Unit>:
        V.CommandBuffer.copy_buffer(command,buffer,destination,[V.BufferCopy{W.zero(),offset,length}])
        copied_back(command,destination,rest)

def storage_memory(storage: U.Staging) -> V.DeviceMemory:
  match storage:
    case U.Empty{}: V.DeviceMemory{0}
    case U.Staging{U.Allocation{b,m,c},cursor}: m

def low(word: W.U64) -> U32:
  W.U64{lo,hi} = word
  lo

def allocation_memory(a: U.Allocation) -> V.DeviceMemory:
  U.Allocation{b,m,c} = a
  m

def verify(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, +command: V.CommandBuffer, +fence: V.Fence, storage: U.Staging, +plan: G.Plan) -> V.Action(Unit):
  G.Plan{geometry,+copies,created,+bytes} = plan
  do V.Action<Unit>:
    +back : U.Allocation <- U.allocate(instance,physical,device,bytes,2,2)
    +buffer : V.Buffer = G.allocation_buffer(back)
    +memory : V.DeviceMemory = allocation_memory(back)
    V.CommandBuffer.begin(command)
    G.record(command,plan)
    V.CommandBuffer.pipeline_barrier(command,4096,4096,[V.MemoryBarrier{4096,2048}],[],[])
    copied_back(command,buffer,copies)
    V.CommandBuffer.pipeline_barrier(command,4096,16384,[V.MemoryBarrier{4096,8192}],[],[])
    E.complete(device,command,fence)
    expected : List<U32> <- V.Device.read_memory(device,storage_memory(storage),W.zero(),low(bytes))
    actual : List<U32> <- V.Device.read_memory(device,memory,W.zero(),low(bytes))
    D.require(D.bytes_equal(expected,actual),"Chunk GPU copies differ from staged CPU logical bytes")
    E.reset(device,command,fence)
    U.discard(device,back)

type Context is Data:
  Context{instance: V.Instance, physical: V.PhysicalDevice, device: V.Device, command: V.CommandBuffer, fence: V.Fence}
type State is Type:
  State{body: X.Body, set: C.ChunkSet, storage: U.Staging, geometry: GPU.Geometry}

def counts(state: State, expected: U32, reduced: U32) -> V.Action(State):
  State{body,C.ChunkSet{cs,ps,fs,bs,+q,+sq,rb,rt},storage,geometry} = state
  do V.Action<State>:
    D.require(U32.is_eq(q,expected) && U32.is_eq(sq,reduced),"Chunk/GPU state lost canonical or shadow count metadata")
    return State{body,C.ChunkSet{cs,ps,fs,bs,q,sq,rb,rt},storage,geometry}

def publish(+context: Context, body: X.Body, old: GPU.Geometry, pair: (C.ChunkSet & U.Staging) & V.VkResult(G.Plan), unchanged: Bool) -> V.Action(State):
  Context{+instance,+physical,+device,+command,+fence} = context
  (owner,result) = pair
  (set,storage) = owner
  match result:
    case Fail{error}: IO.pure(V.VkResult(State),Fail{error})
    case Done{+plan}:
      G.Plan{+geometry,+copies,+created,+bytes} = plan
      +kept : U.Staging = storage
      do V.Action<State>:
        D.require(Bool.not(unchanged) || (W.is_zero(bytes) && List.is_empty(&2,G.Copy,copies) && List.is_empty(&2,U.Allocation,created)),"Unchanged generation allocated or uploaded geometry")
        Bool.pick(V.Action(Unit),W.is_zero(bytes),V.Action.pure(Unit,Unit{}),verify(instance,physical,device,command,fence,kept,plan))
        G.commit(device,old,geometry)
        return State{body,set,kept,geometry}

def upload(+context: Context, state: State, unchanged: Bool) -> V.Action(State):
  Context{+instance,+physical,+device,command,fence} = context
  State{body,set,storage,+old} = state
  do V.Action<State>:
    V.Device.collect_retired(device)
    pair : (C.ChunkSet & U.Staging) & V.VkResult(G.Plan) <- V.Action.lift((C.ChunkSet & U.Staging) & V.VkResult(G.Plan),G.prepare(instance,physical,device,old,storage,set))
    publish(context,body,old,pair,unchanged)

def changed(+context: Context, geometry: GPU.Geometry, storage: U.Staging, pair: X.Body & C.ChunkSet) -> V.Action(State):
  (body,set) = pair
  upload(context,State{body,set,storage,geometry},False{})

def empty_after(+context: Context, state: State) -> V.Action(State):
  State{body,set,storage,geometry} = state
  do V.Action<State>:
    cut : X.Body & C.ChunkSet <- built(C.cut(body,set,X.MetricSphere{X.PointCm{35.0,35.0,35.0},1000.0},1))
    changed(context,geometry,storage,cut)

def reset(+context: Context, state: State) -> V.Action(State):
  State{body,set,storage,geometry} = state
  do V.Action<State>:
    original : X.Body & C.ChunkSet <- built(C.build(X.Body.solid(3n),2))
    changed(context,geometry,storage,original)

def dispose(context: Context, state: State) -> V.Action(Unit):
  Context{instance,physical,+device,command,fence} = context
  State{body,set,storage,geometry} = state
  do V.Action<Unit>:
    GPU.release(device,geometry)
    U.release(device,storage)

def share(xs: List<U32>) -> List<&2,U32>:
  match xs:
    case Nil{}: Nil{}
    case x <> rest: x <> share(rest)

def snapshot_chunk_pair(key: C.ChunkKey, version: U32, domains: List<&2,C.Domain>, color: M.Mesh & List<&2,U32>, shadow: M.Mesh & List<&2,U32>) -> C.Chunk & List<&2,U32>:
  (c,cb) = color
  (s,sb) = shadow
  (C.Chunk{key,version,domains,c,s},G.concat(~U32,cb,sb))

def snapshot_chunk(chunk: C.Chunk) -> C.Chunk & List<&2,U32>:
  C.Chunk{key,version,domains,color,shadow} = chunk
  snapshot_chunk_pair(key,version,domains,CPU.original(color),CPU.original(shadow))

def snapshot_cons(head: C.Chunk & List<&2,U32>, tail: List<C.Chunk> & List<&2,U32>) -> List<C.Chunk> & List<&2,U32>:
  (chunk,bytes) = head
  (chunks,rest) = tail
  (chunk <> chunks,G.concat(~U32,bytes,rest))

def snapshot_chunks(xs: List<C.Chunk>) -> List<C.Chunk> & List<&2,U32>:
  match xs:
    case Nil{}: (Nil{},Nil{})
    case chunk <> rest: snapshot_cons(snapshot_chunk(chunk),snapshot_chunks(rest))

def snapshot_done(primitives: List<&2,C.Primitive>, faces: List<&2,X.Face>, bounds: Maybe<&2,M.Extent>, q: U32, sq: U32, rb: U32, rt: U32, pair: List<C.Chunk> & List<&2,U32>) -> C.ChunkSet & List<&2,U32>:
  (chunks,bytes) = pair
  (C.ChunkSet{chunks,primitives,faces,bounds,q,sq,rb,rt},bytes)

def snapshot(set: C.ChunkSet) -> C.ChunkSet & List<&2,U32>:
  C.ChunkSet{chunks,primitives,faces,bounds,q,sq,rb,rt} = set
  snapshot_done(primitives,faces,bounds,q,sq,rb,rt,snapshot_chunks(chunks))

def copies_next(head: List<&2,G.Copy>, pair: List<&2,G.Copy> & W.U64) -> List<&2,G.Copy> & W.U64:
  (tail,bytes) = pair
  (G.concat(~G.Copy,head,tail),bytes)

def resident_copies(xs: List<&2,GPU.Resident>, +offset: W.U64) -> List<&2,G.Copy> & W.U64:
  match xs:
    case Nil{}: (Nil{},offset)
    case GPU.Resident{k,v,GPU.Stream{E.BoundBuffer{cv,cm},E.BoundBuffer{ci,cim},+count},GPU.Stream{E.BoundBuffer{sv,sm},E.BoundBuffer{si,sim},+sc}} <> rest:
      +vbytes = W.of_u32((count / 6 * 160 : U32))
      +ibytes = W.of_u32((count * 4 : U32))
      +svbytes = W.of_u32((sc / 6 * 160 : U32))
      +sibytes = W.of_u32((sc * 4 : U32))
      copies_next([G.Copy{U.Slice{V.Buffer{0},offset,vbytes},cv},G.Copy{U.Slice{V.Buffer{0},W.add(offset,vbytes),ibytes},ci},G.Copy{U.Slice{V.Buffer{0},W.add(offset,W.add(vbytes,ibytes)),svbytes},sv},G.Copy{U.Slice{V.Buffer{0},W.add(offset,W.add(W.add(vbytes,ibytes),svbytes)),sibytes},si}],resident_copies(rest,W.add(offset,W.add(W.add(vbytes,ibytes),W.add(svbytes,sibytes)))))

def read_plan(+context: Context, pair: List<&2,G.Copy> & W.U64) -> V.Action(List<&2,U32>):
  Context{+instance,+physical,+device,+command,+fence} = context
  (copies,+bytes) = pair
  do V.Action<List<&2,U32>>:
    +back : U.Allocation <- U.allocate(instance,physical,device,bytes,2,2)
    +buffer : V.Buffer = G.allocation_buffer(back)
    +memory : V.DeviceMemory = allocation_memory(back)
    V.CommandBuffer.begin(command)
    V.CommandBuffer.pipeline_barrier(command,4096,4096,[V.MemoryBarrier{4096,2048}],[],[])
    copied_back(command,buffer,copies)
    V.CommandBuffer.pipeline_barrier(command,4096,16384,[V.MemoryBarrier{4096,8192}],[],[])
    E.complete(device,command,fence)
    actual : List<U32> <- V.Device.read_memory(device,memory,W.zero(),low(bytes))
    E.reset(device,command,fence)
    U.discard(device,back)
    return share(actual)

def read_geometry(context: Context, geometry: GPU.Geometry) -> V.Action(List<&2,U32>):
  read_plan(context,resident_copies(G.residents(geometry),W.zero()))

def failed_arrays(+context: Context, body: X.Body, geometry: GPU.Geometry, storage: U.Staging, expected: List<&2,U32>, pair: C.ChunkSet & List<&2,U32>) -> V.Action(State):
  (set,actual) = pair
  do V.Action<State>:
    D.require(D.bytes_equal(E.copy_words(expected),E.copy_words(actual)),"Failed chunk upload changed or lost returned CPU arrays")
    return State{body,set,storage,geometry}

def rejected(result: V.VkResult(G.Plan)) -> V.Action(Unit):
  match result:
    case Done{value}: D.require(False{},"Injected chunk preparation failure unexpectedly committed")
    case Fail{(code,message)}: D.require(U32.is_eq(code,4294967294),"Chunk preparation lost the injected error or cleanup error")

def failed(context: Context, body: X.Body, geometry: GPU.Geometry, expected: List<&2,U32>, pair: (C.ChunkSet & U.Staging) & V.VkResult(G.Plan)) -> V.Action(State):
  ((set,storage),result) = pair
  do V.Action<State>:
    rejected(result)
    failed_arrays(context,body,geometry,storage,expected,snapshot(set))

def failure_modes(modes: List<U32>, +context: Context, state: State, +expected: List<&2,U32>, +old_bytes: List<&2,U32>, +rows: U32) -> V.Action(State):
  match modes:
    case Nil{}: V.Action.pure(State,state)
    case mode <> rest:
      Context{+instance,+physical,+device,command,fence} = context
      State{body,set,storage,+geometry} = state
      do V.Action<State>:
        armed : U32 & U32 <- V.debug_u64_roundtrip(W.of_u32(mode))
        pair : (C.ChunkSet & U.Staging) & V.VkResult(G.Plan) <- V.Action.lift((C.ChunkSet & U.Staging) & V.VkResult(G.Plan),G.prepare(instance,physical,device,geometry,storage,set))
        state : State <- failed(context,body,geometry,expected,pair)
        disarmed : U32 & U32 <- V.debug_u64_roundtrip(W.zero())
        bytes : List<&2,U32> <- read_geometry(context,geometry)
        live : U32 <- V.debug_live_objects()
        D.require(D.bytes_equal(E.copy_words(bytes),E.copy_words(old_bytes)) && U32.is_eq(live,rows),"Failed chunk preparation changed installed device bytes or native rows")
        failure_modes(rest,context,state,expected,old_bytes,rows)

def candidate_saved(+context: Context, body: X.Body, storage: U.Staging, +geometry: GPU.Geometry, pair: C.ChunkSet & List<&2,U32>) -> V.Action(State):
  Context{instance,physical,+device,command,fence} = context
  (set,expected) = pair
  do V.Action<State>:
    bytes : List<&2,U32> <- read_geometry(context,geometry)
    rows : U32 <- V.debug_live_objects()
    failure_modes([1,2,3,4,5,6,7,8,9,10,11,12],context,State{body,set,storage,geometry},expected,bytes,rows)

def candidate_body(context: Context, storage: U.Staging, geometry: GPU.Geometry, pair: X.Body & C.ChunkSet) -> V.Action(State):
  (body,set) = pair
  candidate_saved(context,body,storage,geometry,snapshot(set))

def failures(+context: Context, state: State) -> V.Action(State):
  State{body,set,storage,geometry} = state
  do V.Action<State>:
    candidate : X.Body & C.ChunkSet <- built(C.build(X.Body.filled(3n,2),3))
    candidate_body(context,storage,geometry,candidate)

def uploaded(+context: Context, pair: X.Body & C.ChunkSet) -> V.Action(Unit):
  Context{instance,physical,+device,command,fence} = context
  (body,set) = pair
  do V.Action<Unit>:
    +baseline : U32 <- V.debug_live_objects()
    a : State <- upload(context,State{body,set,U.Empty{},GPU.Empty{}},False{})
    a : State <- counts(a,384,6)
    +full : U32 <- V.debug_live_objects()
    b : State <- upload(context,a,True{})
    after_noop : U32 <- V.debug_live_objects()
    D.require(U32.is_eq(full,after_noop),"Camera/no-op installation changed native resource rows")
    b : State <- failures(context,b)
    c : State <- empty_after(context,b)
    c : State <- counts(c,0,0)
    V.Device.collect_retired(device)
    empty_rows : U32 <- V.debug_live_objects()
    D.require(U32.is_eq(empty_rows,(baseline + 2 : U32)),"Empty-after-edit retained geometry buffers or lost reusable staging")
    d : State <- reset(context,c)
    d : State <- counts(d,384,6)
    restored : U32 <- V.debug_live_objects()
    D.require(U32.is_eq(full,restored),"Reset changed native resource rows")
    e : State <- upload(context,d,True{})
    dispose(context,e)
    after : U32 <- V.debug_live_objects()
    D.require(U32.is_eq(baseline,after),"Chunk generation teardown leaked rows")

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- D.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    family : U32 <- D.choose(Core.find_queue_family(families,1),"No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    +command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    +fence : V.Fence <- V.Device.create_fence(device,False{})
    state : X.Body & C.ChunkSet <- built(C.build(X.Body.solid(3n),0))
    uploaded(Context{instance,physical,device,command,fence},state)
    V.Device.destroy_command_pool(device,pool)
    V.Device.destroy_fence(device,fence)
    V.Device.destroy(device)
    V.Instance.destroy(instance)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- D.require(U32.is_zero(count),"Chunk scope leaked native rows")
    V.or_exit(Unit,checked)
    IO.print("Immutable chunk generation CPU/staging/device bytes, no-op reuse, empty-after-edit, reset and cleanup passed")
