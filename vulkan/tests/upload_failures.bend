import Base
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/src/core.bend as Core
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W
import ../../voxel.bend as X
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D
import ../src/mesh.bend as M
import ../src/exterior.bend as Exterior
import ../src/renderer.bend as GPU
import ../../deps/bend-vulkan/examples/indexed_offscreen.bend as E

def mesh_result(result: Result<&2,&1,Exterior.Error,M.Mesh>) -> V.Action(M.Mesh):
  match result:
    case Done{mesh}: V.Action.pure(M.Mesh,mesh)
    case Fail{error}: IO.pure(V.VkResult(M.Mesh),Fail{(1,"Failed to pack upload fixture")})

def mesh() -> V.Action(M.Mesh):
  mesh_result(M.pack([X.Rectangle{X.Cell{1,2,3},X.PosZ{},4294967295,4,7}]))

def share(xs: List<U32>) -> List<&2,U32>:
  match xs:
    case Nil{}: Nil{}
    case x <> rest: x <> share(rest)

def bytes(+device: V.Device, geometry: GPU.Geometry) -> V.Action(List<U32>):
  match geometry:
    case GPU.Empty{}: V.Action.pure(List<U32>,[])
    case GPU.Chunked{chunks,runs}: IO.pure(V.VkResult(List<U32>),Fail{(1,"Legacy upload fixture unexpectedly received chunk geometry")})
    case GPU.Geometry{E.BoundBuffer{vb,vm},E.BoundBuffer{ib,im},count}:
      do V.Action<List<U32>>:
        vertices : List<U32> <- V.Device.read_memory(device,vm,W.zero(),160)
        indices : List<U32> <- V.Device.read_memory(device,im,W.zero(),24)
        return List.append(&1,U32,vertices,indices)

def rejected(result: V.VkResult(GPU.Geometry & M.Mesh)) -> V.Action(Unit):
  match result:
    case Done{value}: D.require(False{},"Controlled upload failure unexpectedly succeeded")
    case Fail{(code,message)}: D.require(U32.is_eq(code,4294967294),"Controlled upload failure lost VkResult bits")

def failures(modes: List<U32>, +instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, +old: GPU.Geometry, +expected: List<&2,U32>, +rows: U32) -> V.Action(Unit):
  match modes:
    case Nil{}: V.Action.pure(Unit,Unit{})
    case mode <> rest:
      do V.Action<Unit>:
        armed : U32 & U32 <- V.debug_u64_roundtrip(W.of_u32(mode))
        candidate : M.Mesh <- mesh()
        result : V.VkResult(GPU.Geometry & M.Mesh) <- V.Action.lift(V.VkResult(GPU.Geometry & M.Mesh),GPU.upload_mesh(instance,physical,device,old,candidate))
        rejected(result)
        after : List<U32> <- bytes(device,old)
        live : U32 <- V.debug_live_objects()
        D.require(D.bytes_equal(after,E.copy_words(expected)) && U32.is_eq(live,rows),"Failed geometry preparation changed installed bytes or leaked resources")
        failures(rest,instance,physical,device,old,expected,rows)

def installed(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, pair: GPU.Geometry & M.Mesh) -> V.Action(Unit):
  (+old,mesh) = pair
  do V.Action<Unit>:
    before : List<U32> <- bytes(device,old)
    rows : U32 <- V.debug_live_objects()
    failures([1,2,3,4,5,6],instance,physical,device,old,share(before),rows)

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- D.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    family : U32 <- D.choose(Core.find_queue_family(families,1),"No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    original : M.Mesh <- mesh()
    pair : GPU.Geometry & M.Mesh <- GPU.upload_mesh(instance,physical,device,GPU.Empty{},original)
    installed(instance,physical,device,pair)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- D.require(U32.is_zero(count),"Upload failure scope leaked")
    V.or_exit(Unit,checked)
    IO.print("Six real-device geometry allocation/upload failures preserved installed bytes and rows")
