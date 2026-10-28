import Base
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/examples/window.bend as WSI
import ../src/presentation.bend as P
import ../src/renderer.bend as GPU
import ../../deps/bend-vulkan/examples/indexed_offscreen.bend as E
import ../../render.bend as R
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W
import ../../deps/bend-vulkan/tests/native.bend as T
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D

def borrowed_images(xs: List<V.ImageHandle>, +device: V.Device, memory: V.DeviceMemory) -> V.Action(Unit):
  match xs:
    case Nil{}: IO.pure(V.VkResult(Unit),Fail{(1,"Swapchain has no borrowed images")})
    case Con{+image,rest}:
      do V.Action<Unit>:
        T.expect_error(Unit,1610612740,V.Device.destroy_image(device,image))
        T.expect_error(V.MemoryRequirements,1610612740,V.Device.get_image_memory_requirements(device,image))
        T.expect_error(Unit,1610612740,V.Device.bind_image_memory(device,image,memory,W.zero()))
        T.expect_error(Unit,1610612738,V.Device.destroy_image(V.Device{4294967295},image))

def boundaries(context: WSI.Context, frame: P.Frame, target: P.SlotTarget) -> V.Action(Unit):
  WSI.Context{window,instance,physical,surface,+device,g,p} = context
  P.Frame{pool,command,acquire,render,present,finished} = frame
  P.SlotTarget{P.Target{+swapchain,shared,pass,layout,pipeline,width,height,format,production},images,E.Attachment{di,memory,dv}} = target
  do V.Action<Unit>:
    borrowed : List<V.ImageHandle> <- V.Device.swapchain_images(device,swapchain)
    borrowed_images(borrowed,device,memory)
    T.expect_error(Unit,1610612740,V.NativeWindow.close(window))
    T.expect_error(Unit,1610612740,V.Instance.destroy_surface(instance,surface))
    T.expect_error(Unit,1610612740,V.Device.destroy_swapchain(device,swapchain))

def acquired(+context: WSI.Context, +frame: P.Frame, +target: P.SlotTarget, outcome: V.AcquireOutcome) -> V.Action(Unit):
  WSI.Context{window,instance,physical,surface,+device,g,p} = context
  P.Frame{pool,+command,+acquire,+render,+present,+finished} = frame
  P.SlotTarget{+shared,images,depth} = target
  P.Target{+swapchain,borrowed,pass,layout,pipeline,width,height,format,production} = shared
  match outcome:
    case V.Acquired{+acquisition,+index,suboptimal}:
      do V.Action<Unit>:
        T.expect_error(Unit,1610612740,V.Fence.reset(acquire))
        T.expect_error(Unit,1610612740,V.Device.destroy_fence(device,acquire))
        T.expect_error(V.AcquireOutcome,1610612740,V.Device.acquire(device,swapchain,acquire,W.zero()))
        done : U32 <- V.Fence.wait(acquire,W.U64{4294967295,4294967295})
        V.Fence.reset(acquire)
        P.record(device,frame,target,acquisition,index,R.Camera.initial(),GPU.Empty{})
        rendered : U32 <- V.Fence.wait(render,W.U64{4294967295,4294967295})
        result : V.PresentOutcome <- V.Device.present(device,acquisition,finished,present)
        T.expect_error(Unit,1610612740,V.Device.destroy_semaphore(device,finished))
        T.expect_error(Unit,1610612740,V.Fence.reset(present))
        status : U32 <- V.Fence.status(render)
        T.expect_error(Unit,1610612740,V.Device.destroy_semaphore(device,finished))
        shown : U32 <- V.Fence.wait(present,W.U64{4294967295,4294967295})
        T.expect_error(Unit,1610612738,V.Device.release_acquired(device,acquisition))
        T.expect_error(V.PresentOutcome,1610612738,V.Device.present(device,acquisition,finished,present))
        V.CommandBuffer.reset(command)
        P.slot_destroy(device,target)
        P.destroy(device,shared)
        V.Device.destroy_command_pool(device,pool)
    case _: IO.pure(V.VkResult(Unit),Fail{(1610612739,"Acquire smoke failed")})

def get_device(context: WSI.Context) -> V.Device:
  WSI.Context{window,instance,physical,surface,device,g,p} = context
  device

def get_swapchain(target: P.SlotTarget) -> V.Swapchain:
  P.SlotTarget{P.Target{swapchain,borrowed,pass,layout,pipeline,width,height,format,production},images,depth} = target
  swapchain

def get_acquire(frame: P.Frame) -> V.Fence:
  P.Frame{pool,command,acquire,render,present,finished} = frame
  acquire

def abandoned(outcome: V.AcquireOutcome, +device: V.Device, +swapchain: V.Swapchain, +fence: V.Fence) -> V.Action(Unit):
  match outcome:
    case V.Acquired{acquisition,index,suboptimal}:
      do V.Action<Unit>:
        ready : U32 <- V.Fence.wait(fence,W.U64{4294967295,4294967295})
        V.Device.release_acquired(device,acquisition)
        V.Fence.reset(fence)
    case _: IO.pure(V.VkResult(Unit),Fail{(1,"Abandoned acquisition did not acquire")})

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +context : WSI.Context <- WSI.open(entry,"Bend WSI smoke",False{})
    +frame : P.Frame <- P.frame(get_device(context))
    shared : P.Target <- P.build(context,640,480)
    +target : P.SlotTarget <- P.slot_target(context,shared)
    boundaries(context,frame,target)
    abandoned_outcome : V.AcquireOutcome <- V.Device.acquire(get_device(context),get_swapchain(target),get_acquire(frame),W.of_u32(1000000000))
    abandoned(abandoned_outcome,get_device(context),get_swapchain(target),get_acquire(frame))
    outcome : V.AcquireOutcome <- V.Device.acquire(get_device(context),get_swapchain(target),get_acquire(frame),W.of_u32(1000000000))
    acquired(context,frame,target,outcome)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- D.require(U32.is_zero(count),"Presentation smoke leaked rows")
    V.or_exit(Unit,checked)
    IO.print("Native presentation borrowing, abandoned acquisition and fence ownership passed")
