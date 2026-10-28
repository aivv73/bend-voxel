import Base
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/src/core.bend as Core
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D
import ../../deps/bend-vulkan/examples/indexed_offscreen.bend as E
import ../src/timing.bend as Timing

def disabled(view: Maybe<&2,V.QueryPool>) -> V.Action(Unit):
  match view:
    case None{}: V.Action.pure(Unit,Unit{})
    case Some{pool}: D.require(False{},"Failed reset left a per-frame query view enabled")

def enabled(view: Maybe<&2,V.QueryPool>) -> V.Action(Unit):
  match view:
    case Some{pool}: V.Action.pure(Unit,Unit{})
    case None{}: D.require(False{},"Successful query reset disabled the frame")

def ready(xs: List<V.Timestamp>) -> V.Action(Unit):
  match xs:
    case [V.Timestamp{a,True{}},V.Timestamp{b,True{}}]: V.Action.pure(Unit,Unit{})
    case _: D.require(False{},"Previous frame did not produce completed query data")

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
    +queries : V.QueryPool <- V.Device.create_timestamp_pool(device,6)
    V.CommandBuffer.begin(command)
    +view : Maybe<&2,V.QueryPool> <- Timing.reset(command,Some{queries})
    enabled(view)
    Timing.write(command,view,0)
    Timing.write(command,view,1)
    E.complete(device,command,fence)
    values : List<V.Timestamp> <- V.Device.timestamp_results(device,queries,0,2)
    ready(values)
    E.reset(device,command,fence)
    V.CommandBuffer.begin(command)
    +failed : Maybe<&2,V.QueryPool> <- Timing.reset(command,Some{queries})
    disabled(failed)
    started : W.U64 <- V.monotonic_ns()
    Timing.observe(device,failed,started,True{})
    +retry : Maybe<&2,V.QueryPool> <- Timing.reset(command,Some{queries})
    enabled(retry)
    Timing.write(command,retry,0)
    Timing.write(command,retry,1)
    E.complete(device,command,fence)
    values : List<V.Timestamp> <- V.Device.timestamp_results(device,queries,0,2)
    ready(values)
    E.reset(device,command,fence)
    V.Device.destroy_query_pool(device,queries)
    V.Device.destroy_command_pool(device,pool)
    V.Device.destroy_fence(device,fence)
    V.Action.lift(Unit,IO.print("Completed old queries plus reset-ref OOM disabled frame diagnostics and recovered on retry"))

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
