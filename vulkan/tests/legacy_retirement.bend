import Base
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W
import ../../voxel.bend as X
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D
import ../../deps/bend-vulkan/examples/indexed_offscreen.bend as E
import ../src/exterior.bend as Exterior
import ../src/mesh.bend as M
import ../src/renderer.bend as GPU
import ./generation_recording.bend as G
import ./chunk_device.bend as T
import ../../deps/bend-vulkan/tests/native.bend as N

def mesh_built(pair: X.Body & Result<&2,&1,Exterior.Error,M.Mesh>) -> V.Action(M.Mesh):
  (body,result) = pair
  match result:
    case Done{mesh}: V.Action.pure(M.Mesh,mesh)
    case Fail{error}: IO.pure(V.VkResult(M.Mesh),Fail{(1,"Legacy fixture mesh failed")})

def mesh(body: X.Body) -> V.Action(M.Mesh):
  mesh_built(M.build(body))

def bytes(+device: V.Device, geometry: GPU.Geometry) -> V.Action(List<&2,U32>):
  match geometry:
    case GPU.Geometry{E.BoundBuffer{vb,vm},E.BoundBuffer{ib,im},+count}:
      do V.Action<List<&2,U32>>:
        vertices : List<U32> <- V.Device.read_memory(device,vm,W.zero(),(count / 6 * 160 : U32))
        indices : List<U32> <- V.Device.read_memory(device,im,W.zero(),(count * 4 : U32))
        return T.share(List.append(&1,U32,vertices,indices))
    case _: IO.pure(V.VkResult(List<&2,U32>),Fail{(1,"Legacy fixture requires geometry")})

def unchanged(+device: V.Device, +geometry: GPU.Geometry, expected: List<&2,U32>, rows: U32) -> V.Action(Unit):
  do V.Action<Unit>:
    actual : List<&2,U32> <- bytes(device,geometry)
    live : U32 <- V.debug_live_objects()
    D.require(D.bytes_equal(E.copy_words(actual),E.copy_words(expected)) && U32.is_eq(live,rows),"Legacy retirement rejection changed installed bytes or leaked candidate buffers")
    G.live_pairs(device,GPU.geometry_pairs(geometry))

def retried(+context: T.Context, old: GPU.Geometry, rows: U32, result: GPU.Geometry & M.Mesh) -> V.Action(Unit):
  T.Context{instance,physical,+device,command,fence} = context
  (+geometry,mesh) = result
  do V.Action<Unit>:
    V.Device.collect_retired(device)
    live : U32 <- V.debug_live_objects()
    D.require(U32.is_eq(live,rows),"Legacy successful retry retained old geometry")
    G.live_pairs(device,GPU.geometry_pairs(geometry))
    GPU.release(device,geometry)
    V.Device.collect_retired(device)
    V.Action.lift(Unit,IO.print("Legacy complete upload and empty replacement retirement rejection preserved old bytes and cleaned both candidates before successful retry"))

def held(+context: T.Context, +hold: V.CommandBuffer, +geometry: GPU.Geometry, index: V.Buffer) -> V.Action(Unit):
  T.Context{+instance,+physical,+device,command,+fence} = context
  do V.Action<Unit>:
    +expected : List<&2,U32> <- bytes(device,geometry)
    +rows : U32 <- V.debug_live_objects()
    V.CommandBuffer.begin(hold)
    V.CommandBuffer.bind_index_buffer(hold,index,W.zero(),1)
    candidate : M.Mesh <- mesh(X.Body.filled(3n,2))
    N.expect_error(GPU.Geometry & M.Mesh,1610612740,GPU.upload_mesh(instance,physical,device,geometry,candidate))
    unchanged(device,geometry,expected,rows)
    empty : M.Mesh <- mesh(X.Cuboids{Nil{}})
    N.expect_error(GPU.Geometry & M.Mesh,1610612740,GPU.upload_mesh(instance,physical,device,geometry,empty))
    unchanged(device,geometry,expected,rows)
    E.complete(device,hold,fence)
    E.reset(device,hold,fence)
    retry : M.Mesh <- mesh(X.Body.filled(3n,2))
    result : GPU.Geometry & M.Mesh <- GPU.upload_mesh(instance,physical,device,geometry,retry)
    retried(context,geometry,rows,result)

def installed(context: T.Context, hold: V.CommandBuffer, pair: GPU.Geometry & M.Mesh) -> V.Action(Unit):
  (geometry,mesh) = pair
  match geometry:
    case GPU.Geometry{vs,E.BoundBuffer{+index,im},count}: held(context,hold,geometry,index)
    case _: D.require(False{},"Legacy fixture initial upload was empty")

def created(pair: T.Context & V.CommandBuffer) -> V.Action(Unit):
  (+context,hold) = pair
  T.Context{instance,physical,device,command,fence} = context
  do V.Action<Unit>:
    initial : M.Mesh <- mesh(X.Body.solid(3n))
    result : GPU.Geometry & M.Mesh <- GPU.upload_mesh(instance,physical,device,GPU.Empty{},initial)
    installed(context,hold,result)

def run(entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    pair : T.Context & V.CommandBuffer <- G.context(entry)
    created(pair)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- D.require(U32.is_zero(count),"Legacy retirement scope leaked rows")
    V.or_exit(Unit,checked)
