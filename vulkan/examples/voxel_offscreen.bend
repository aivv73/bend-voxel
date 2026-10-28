import Base
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/src/core.bend as Core
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D
import ../src/renderer.bend as GPU
import ../src/acceptance.bend as Acceptance

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- D.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    family : U32 <- D.choose(Core.find_queue_family(families,1),"No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    +renderer : GPU.Renderer <- GPU.create(instance,physical,device)
    GPU.prepare(renderer)
    Acceptance.run(renderer)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- D.require(U32.is_eq(count,0),"Voxel consumer scope leaked")
    V.or_exit(Unit,checked)
