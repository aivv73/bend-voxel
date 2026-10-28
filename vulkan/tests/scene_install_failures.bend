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
import ./generation_recording.bend as Recording

def set(pair: X.Body & C.ChunkSet) -> C.ChunkSet:
  (body,chunks) = pair
  chunks

def expected_failure(code: U32, result: V.VkResult(Scene.Group & C.ChunkSet)) -> V.Action(Unit):
  match result:
    case Done{value}: D.require(False{},"Post-prepare installer failure unexpectedly succeeded")
    case Fail{(actual,message)}: D.require(U32.is_eq(code,actual),"Post-prepare installer changed the primary or cleanup error")

def failures(modes: List<U32>, +context: T.Context, +scene: Scene.Group, +expected: List<&2,U32>, +rows: U32) -> V.Action(Unit):
  match modes:
    case Nil{}: V.Action.pure(Unit,Unit{})
    case +mode <> rest:
      T.Context{+instance,+physical,+device,+command,+fence} = context
      Scene.Group{a,+geometry,r,u} = scene
      do V.Action<Unit>:
        candidate : X.Body & C.ChunkSet <- T.built(C.build(X.Body.filled(3n,2),1))
        armed : U32 & U32 <- V.debug_u64_roundtrip(W.of_u32(mode))
        result : V.VkResult(Scene.Group & C.ChunkSet) <- V.Action.lift(V.VkResult(Scene.Group & C.ChunkSet),Scene.install_chunks(instance,physical,device,command,fence,scene,1,set(candidate)))
        expected_failure(Bool.pick(U32,U32.is_eq(mode,1),4294967295,1610612741),result)
        disarmed : U32 & U32 <- V.debug_u64_roundtrip(W.zero())
        actual : List<&2,U32> <- T.read_geometry(context,geometry)
        live : U32 <- V.debug_live_objects()
        D.require(D.bytes_equal(E.copy_words(actual),E.copy_words(expected)) && U32.is_eq(live,rows),"Handled installer error changed installed device bytes or leaked rows")
        failures(rest,context,scene,expected,rows)

def installed(+context: T.Context, result: Scene.Group & C.ChunkSet) -> V.Action(Unit):
  T.Context{instance,physical,+device,command,fence} = context
  (+scene,set) = result
  Scene.Group{a,geometry,r,u} = scene
  do V.Action<Unit>:
    expected : List<&2,U32> <- T.read_geometry(context,geometry)
    rows : U32 <- V.debug_live_objects()
    failures([1,2,1,2],context,scene,expected,rows)

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
    scene : Scene.Group <- Scene.create(instance,physical,device)
    initial : X.Body & C.ChunkSet <- T.built(C.build(X.Body.solid(3n),0))
    result : Scene.Group & C.ChunkSet <- Scene.install_chunks(instance,physical,device,command,fence,scene,0,set(initial))
    installed(T.Context{instance,physical,device,command,fence},result)

def terminal_installed(+context: T.Context, mode: U32, result: Scene.Group & C.ChunkSet) -> V.Action(Unit):
  T.Context{instance,physical,device,command,fence} = context
  (scene,previous_set) = result
  do V.Action<Unit>:
    armed : U32 & U32 <- V.debug_u64_roundtrip(W.of_u32(mode))
    candidate : X.Body & C.ChunkSet <- T.built(C.build(X.Body.filled(3n,2),1))
    replacement : Scene.Group & C.ChunkSet <- Scene.install_chunks(instance,physical,device,command,fence,scene,1,set(candidate))
    D.require(False{},"Terminal installer failure continued into another operation")

def terminal(mode: U32, pair: T.Context & V.CommandBuffer) -> V.Action(Unit):
  (+context,hold) = pair
  T.Context{+instance,+physical,+device,+command,+fence} = context
  do V.Action<Unit>:
    disarmed : U32 & U32 <- V.debug_u64_roundtrip(W.zero())
    scene : Scene.Group <- Scene.create(instance,physical,device)
    initial : X.Body & C.ChunkSet <- T.built(C.build(X.Body.solid(3n),0))
    result : Scene.Group & C.ChunkSet <- Scene.install_chunks(instance,physical,device,command,fence,scene,0,set(initial))
    terminal_installed(context,mode,result)

def terminal_run(+mode: U32, entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    pair : T.Context & V.CommandBuffer <- Recording.context(entry)
    terminal(mode,pair)

def terminal_result(code: U32, result: V.VkResult(Unit)) -> V.Action(Unit):
  match result:
    case Done{value}: D.require(False{},"Terminal installer unexpectedly succeeded")
    case Fail{(actual,message)}: D.require(U32.is_eq(code,actual),"Terminal installer lost its primary error")

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    reset : V.VkResult(Unit) <- V.Entry.with(Unit,entry => terminal_run(3,entry))
    reset_checked : V.VkResult(Unit) <- terminal_result(4294967295,reset)
    V.or_exit(Unit,reset_checked)
    loss : V.VkResult(Unit) <- V.Entry.with(Unit,entry => terminal_run(4,entry))
    loss_checked : V.VkResult(Unit) <- terminal_result(4294967292,loss)
    V.or_exit(Unit,loss_checked)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- D.require(U32.is_zero(count),"Installer failure scope leaked rows")
    V.or_exit(Unit,checked)
    IO.print("Handled post-prepare begin and mid-copy failures preserved installed bytes and rows across retries")
    IO.print("Post-prepare reset failure and device loss terminated installation with exact scope cleanup")
