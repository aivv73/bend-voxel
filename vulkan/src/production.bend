import Base
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W
import ../../deps/bend-vulkan/examples/indexed_offscreen.bend as E
import ./renderer.bend as GPU
import ./scene.bend as Scene
import ./appearance.bend as A

type Target is Data:
  Target{color: E.Attachment, depth: E.Attachment, pass: V.RenderPass, framebuffer: V.Framebuffer, stage: E.BoundBuffer, programs: Scene.Programs, width: U32, height: U32, format: U32}
type Commands is Data:
  Commands{command: V.CommandBuffer, fence: V.Fence}
type Readback is Type:
  Readback{color: List<U32>, depth: List<U32>, shadow: List<U32>, uniform: List<U32>}

def create_target(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, a: Scene.Assets, +width: U32, +height: U32, +format: U32) -> V.Action(Target):
  do V.Action<Target>:
    +color : E.Attachment <- Scene.attachment(instance,physical,device,format,1,17,V.Extent2D{width,height})
    +depth : E.Attachment <- Scene.attachment(instance,physical,device,126,2,33,V.Extent2D{width,height})
    stage : E.BoundBuffer <- E.buffer(instance,physical,device,(width * height * 8 + 1048576 : U32),2)
    +pass : V.RenderPass <- V.Device.create_render_pass(device,V.RenderPassCreateInfo{[V.AttachmentInfo{format,1,0}],Some{V.AttachmentInfo{126,1,0}}})
    cv : V.ImageView = Scene.attachment_view(color)
    dv : V.ImageView = Scene.attachment_view(depth)
    framebuffer : V.Framebuffer <- V.Device.create_framebuffer(device,V.FramebufferCreateInfo{pass,[cv,dv],V.Extent2D{width,height}})
    programs : Scene.Programs <- Scene.programs(device,a,pass)
    return Target{color,depth,pass,framebuffer,stage,programs,width,height,format}

def commands(+device: V.Device) -> V.Action(Commands):
  do V.Action<Commands>:
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    fence : V.Fence <- V.Device.create_fence(device,False{})
    return Commands{command,fence}

def copy(+command: V.CommandBuffer, image: V.ImageHandle, aspect: U32, buffer: V.Buffer, offset: U32, width: U32, height: U32) -> V.Action(Unit):
  V.CommandBuffer.copy_image_to_buffer(command,image,6,buffer,[V.BufferImageCopy{W.of_u32(offset),0,0,V.ImageSubresourceLayers{aspect,0,0,1},V.Offset2D{0,0},V.Extent2D{width,height}}])

def render(+device: V.Device, commands: Commands, target: Target, +group: Scene.Group, input: A.FrameInput, preview: Bool) -> V.Action(Readback):
  Commands{+command,+fence} = commands
  Target{E.Attachment{+color,cm,cv},E.Attachment{+depth,dm,dv},pass,framebuffer,E.BoundBuffer{+stage,+sm},programs,+width,+height,format} = target
  Scene.Group{+assets,geometry,revision,uploads} = group
  Scene.Assets{E.BoundBuffer{ub,+um},s,ss,p,f,sd,sampler,E.Attachment{+shadow,shm,sv},sp,sf,ps,fl,ml,ix,palette} = assets
  +bytes = (width * height * 4 : U32)
  do V.Action<Readback>:
    Scene.upload(device,assets,A.encode(input))
    V.CommandBuffer.begin(command)
    V.CommandBuffer.pipeline_barrier(command,4864,1792,[V.MemoryBarrier{3584,1792}],[],[])
    E.transition(command,color,1,0,2,4096,1024,0,256)
    E.transition(command,depth,2,0,3,4864,768,0,1536)
    Scene.record(command,group,programs,framebuffer,width,height,preview,None{})
    E.transition(command,color,1,2,6,1024,4096,256,2048)
    E.transition(command,depth,2,3,6,768,4096,1024,2048)
    E.transition(command,shadow,2,4,6,128,4096,32,2048)
    copy(command,color,1,stage,0,width,height)
    copy(command,depth,2,stage,bytes,width,height)
    copy(command,shadow,2,stage,(bytes * 2 : U32),512,512)
    E.transition(command,shadow,2,6,4,4096,128,2048,32)
    V.CommandBuffer.pipeline_barrier(command,4096,16384,[V.MemoryBarrier{4096,8192}],[],[])
    E.complete(device,command,fence)
    colors : List<U32> <- V.Device.read_memory(device,sm,W.zero(),bytes)
    depths : List<U32> <- V.Device.read_memory(device,sm,W.of_u32(bytes),bytes)
    shadows : List<U32> <- V.Device.read_memory(device,sm,W.of_u32((bytes * 2 : U32)),1048576)
    uniforms : List<U32> <- V.Device.read_memory(device,um,W.zero(),2336)
    E.reset(device,command,fence)
    return Readback{colors,depths,shadows,uniforms}

def destroy_attachment(+device: V.Device, a: E.Attachment) -> V.Action(Unit):
  E.Attachment{image,memory,view} = a
  do V.Action<Unit>:
    V.Device.destroy_image_view(device,view)
    V.Device.destroy_image(device,image)
    V.Device.free_memory(device,memory)

def destroy_target(+device: V.Device, t: Target) -> V.Action(Unit):
  Target{color,depth,pass,framebuffer,stage,programs,w,h,format} = t
  do V.Action<Unit>:
    V.Device.destroy_framebuffer(device,framebuffer)
    Scene.destroy_programs(device,programs)
    V.Device.destroy_render_pass(device,pass)
    destroy_attachment(device,color)
    destroy_attachment(device,depth)
    GPU.release_buffer(device,stage)
    V.Device.collect_retired(device)
