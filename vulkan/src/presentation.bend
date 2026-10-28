import Base
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/src/core.bend as Core
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W
import ../shaders/spirv.bend as S
import ../../deps/bend-vulkan/examples/window.bend as WSI
import ../../deps/bend-vulkan/examples/indexed_offscreen.bend as E
import ../../deps/bend-vulkan/examples/offscreen_roundtrip.bend as Memory
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D
import ./renderer.bend as GPU
import ./scene.bend as Scene
import ../../render.bend as R

type SwapImage is Data:
  SwapImage{image: V.ImageHandle, view: V.ImageView}
type ImageTarget is Data:
  ImageTarget{image: V.ImageHandle, view: V.ImageView, framebuffer: V.Framebuffer}
type Target is Data:
  Target{swapchain: V.Swapchain, images: List<&2,SwapImage>, pass: V.RenderPass, layout: V.PipelineLayout, pipeline: V.GraphicsPipeline, width: U32, height: U32, format: U32, production: Maybe<&2,Scene.Programs>}
type SlotTarget is Data:
  SlotTarget{shared: Target, images: List<&2,ImageTarget>, depth: E.Attachment}
type Choice is Data:
  Choice{count: U32, format: U32, space: U32, width: U32, height: U32, transform: U32, alpha: U32}
type Frame is Data:
  Frame{pool: V.CommandPool, command: V.CommandBuffer, acquire: V.Fence, render: V.Fence, present: V.Fence, finished: V.Semaphore}

def choice_extent(format: U32 & U32, extent: U32 & U32, count: U32, transform: U32, +alpha: U32) -> Choice:
  (f,s) = format
  (w,h) = extent
  Choice{count,f,s,w,h,transform,(alpha .&. (0 - alpha : U32) : U32)}

def choice(caps: V.SurfaceCapabilities, format: U32 & U32, width: U32, height: U32) -> Choice:
  V.SurfaceCapabilities{+minimum,+maximum,cw,ch,lw,lh,hw,hh,transforms,transform,alpha,usage} = caps
  choice_extent(format,Core.surface_extent(cw,ch,lw,lh,hw,hh,width,height),Core.present_image_count(minimum,maximum),transform,alpha)

type Owned is Data:
  OwnSwapchain{swapchain: V.Swapchain}
  OwnImage{image: V.ImageHandle}
  OwnMemory{memory: V.DeviceMemory}
  OwnView{view: V.ImageView}
  OwnPass{pass: V.RenderPass}
  OwnLayout{layout: V.PipelineLayout}
  OwnShader{shader: V.ShaderModule}
  OwnPipeline{pipeline: V.GraphicsPipeline}
  OwnFramebuffer{framebuffer: V.Framebuffer}

def release_owned(+device: V.Device, resource: Owned) -> V.Action(Unit):
  match resource:
    case OwnSwapchain{swapchain}: V.Device.destroy_swapchain(device,swapchain)
    case OwnImage{image}: V.Device.destroy_image(device,image)
    case OwnMemory{memory}: V.Device.free_memory(device,memory)
    case OwnView{view}: V.Device.destroy_image_view(device,view)
    case OwnPass{pass}: V.Device.destroy_render_pass(device,pass)
    case OwnLayout{layout}: V.Device.destroy_pipeline_layout(device,layout)
    case OwnShader{shader}: V.Device.destroy_shader_module(device,shader)
    case OwnPipeline{pipeline}: V.Device.destroy_graphics_pipeline(device,pipeline)
    case OwnFramebuffer{framebuffer}: V.Device.destroy_framebuffer(device,framebuffer)

def rollback(+device: V.Device, owned: List<&2,Owned>) -> V.Action(Unit):
  match owned:
    case Nil{}: V.Action.pure(Unit,Unit{})
    case Con{resource,rest}:
      do V.Action<Unit>:
        release_owned(device,resource)
        rollback(device,rest)

def guard_result(-A: Type, -B: Type, device: V.Device, owned: List<&2,Owned>, result: V.VkResult(A), next: A -> V.Action(B)) -> V.Action(B):
  match result:
    case Done{value}: next(value)
    case Fail{error}:
      do V.Action<B>:
        rollback(device,owned)
        IO.pure(V.VkResult(B),Fail{error})

def guard(-A: Type, -B: Type, +device: V.Device, owned: List<&2,Owned>, action: V.Action(A), next: A -> V.Action(B)) -> V.Action(B):
  IO.bind(V.VkResult(A),V.VkResult(B),action,result => guard_result(A,B,device,owned,result,next))

def views(+target: Target, xs: List<V.ImageHandle>, +device: V.Device, +owned: List<&2,Owned>, +acc: List<&2,SwapImage>) -> V.Action(Target):
  Target{swapchain,old,pass,layout,pipeline,width,height,format,production} = target
  match xs:
    case Nil{}: V.Action.pure(Target,Target{swapchain,acc,pass,layout,pipeline,width,height,format,production})
    case Con{+image,rest}:
      guard(V.ImageView,Target,device,owned,V.Device.create_image_view(device,V.ImageViewCreateInfo{image,1,V.ImageSubresourceRange{1,0,1,0,1}}),+view =>
        views(target,rest,device,OwnView{view} <> owned,SwapImage{image,view} <> acc))

def images_ready(+device: V.Device, +target: Target, +owned: List<&2,Owned>, xs: List<V.ImageHandle>) -> V.Action(Target):
  views(target,List.reverse(&1,V.ImageHandle,xs),device,owned,Nil{})

def target_pipeline(+device: V.Device, +swapchain: V.Swapchain, +pass: V.RenderPass, +layout: V.PipelineLayout, +width: U32, +height: U32, +format: U32, +owned: List<&2,Owned>) -> V.Action(Target):
  guard(V.ShaderModule,Target,device,owned,V.Device.create_shader_module(device,S.voxel_vertex_words()),+vertex =>
    guard(V.GraphicsPipeline,Target,device,OwnShader{vertex} <> owned,GPU.pipeline(device,layout,pass,vertex,S.voxel_fragment_words()),+pipeline =>
      guard(Unit,Target,device,OwnPipeline{pipeline} <> OwnShader{vertex} <> owned,V.Device.destroy_shader_module(device,vertex),unit =>
        guard(List<V.ImageHandle>,Target,device,OwnPipeline{pipeline} <> owned,V.Device.swapchain_images(device,swapchain),xs =>
          images_ready(device,Target{swapchain,Nil{},pass,layout,pipeline,width,height,format,None{}},OwnPipeline{pipeline} <> owned,xs)))))

def target_layout(+device: V.Device, +swapchain: V.Swapchain, +pass: V.RenderPass, +width: U32, +height: U32, +format: U32, +owned: List<&2,Owned>) -> V.Action(Target):
  guard(V.PipelineLayout,Target,device,owned,V.Device.create_pipeline_layout(device,V.PipelineLayoutCreateInfo{[],Some{V.PushConstantRange{1,64}}}),+layout =>
    target_pipeline(device,swapchain,pass,layout,width,height,format,OwnLayout{layout} <> owned))

def target_pass(+device: V.Device, +swapchain: V.Swapchain, +format: U32, +width: U32, +height: U32, +owned: List<&2,Owned>) -> V.Action(Target):
  guard(V.RenderPass,Target,device,owned,V.Device.create_render_pass(device,V.RenderPassCreateInfo{[V.AttachmentInfo{format,1,0}],Some{V.AttachmentInfo{126,1,0}}}),+pass =>
    target_layout(device,swapchain,pass,width,height,format,OwnPass{pass} <> owned))

def build_chosen(+context: WSI.Context, choice: Choice) -> V.Action(Target):
  WSI.Context{window,instance,physical,+surface,+device,g,p} = context
  Choice{count,+format,space,+width,+height,transform,alpha} = choice
  guard(V.Swapchain,Target,device,Nil{},V.Device.create_swapchain(device,V.SwapchainCreateInfo{surface,count,format,space,V.Extent2D{width,height},16,transform,alpha,2}),+swapchain =>
    target_pass(device,swapchain,format,width,height,[OwnSwapchain{swapchain}]))

def choose_format(format: Maybe<(U32 & U32)>) -> V.Action(U32 & U32):
  match format:
    case None{}: IO.pure(V.VkResult(U32 & U32),Fail{(1610612739,"No supported surface format")})
    case Some{pair}: V.Action.pure(U32 & U32,pair)

def build(+context: WSI.Context, +width: U32, +height: U32) -> V.Action(Target):
  WSI.Context{window,+instance,+physical,+surface,device,g,p} = context
  do V.Action<Target>:
    caps : V.SurfaceCapabilities <- V.Instance.surface_capabilities(instance,physical,surface)
    formats : List<(U32 & U32)> <- V.Instance.surface_formats(instance,physical,surface)
    format : U32 & U32 <- choose_format(Core.surface_format(formats))
    build_chosen(context,choice(caps,format,width,height))

def destroy_images(xs: List<&2,SwapImage>, +device: V.Device) -> V.Action(Unit):
  match xs:
    case Nil{}: V.Action.pure(Unit,Unit{})
    case Con{SwapImage{image,view},rest}:
      do V.Action<Unit>:
        V.Device.destroy_image_view(device,view)
        destroy_images(rest,device)

def destroy_production(device: V.Device, p: Maybe<&2,Scene.Programs>) -> V.Action(Unit):
  match p:
    case None{}: V.Action.pure(Unit,Unit{})
    case Some{programs}: Scene.destroy_programs(device,programs)

def destroy(+device: V.Device, target: Target) -> V.Action(Unit):
  Target{swapchain,images,pass,layout,pipeline,width,height,format,production} = target
  do V.Action<Unit>:
    destroy_images(images,device)
    destroy_production(device,production)
    V.Device.destroy_graphics_pipeline(device,pipeline)
    V.Device.destroy_pipeline_layout(device,layout)
    V.Device.destroy_render_pass(device,pass)
    V.Device.destroy_swapchain(device,swapchain)

def frame(+device: V.Device) -> V.Action(Frame):
  do V.Action<Frame>:
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    acquire : V.Fence <- V.Device.create_fence(device,False{})
    render : V.Fence <- V.Device.create_fence(device,False{})
    present : V.Fence <- V.Device.create_fence(device,False{})
    finished : V.Semaphore <- V.Device.create_semaphore(device)
    return Frame{pool,command,acquire,render,present,finished}

def at(images: List<&2,ImageTarget>, index: U32) -> V.Action(ImageTarget):
  match images index:
    case Nil{} _: IO.pure(V.VkResult(ImageTarget),Fail{(1610612738,"Acquired image index out of range")})
    case Con{image,rest} 0: V.Action.pure(ImageTarget,image)
    case Con{image,rest} n: at(rest,(n - 1 : U32))

def record_image(+device: V.Device, frame: Frame, target: SlotTarget, acquisition: V.Acquisition, image: ImageTarget, camera: R.Camera, +geometry: GPU.Geometry) -> V.Action(Unit):
  Frame{pool,+command,acquire,+render,present,+finished} = frame
  SlotTarget{Target{swapchain,shared,pass,layout,pipeline,+width,+height,+format,+production},images,E.Attachment{+depth,memory,dv}} = target
  ImageTarget{+color,view,framebuffer} = image
  do V.Action<Unit>:
    V.CommandBuffer.begin(command)
    V.CommandBuffer.use_acquisition(command,acquisition)
    GPU.publish(command,geometry)
    E.transition(command,color,1,0,2,1024,1024,0,256)
    E.transition(command,depth,2,0,3,768,768,0,1536)
    V.CommandBuffer.begin_render_pass(command,framebuffer,V.RenderArea{V.Offset2D{0,0},V.Extent2D{width,height}},[V.ColorClear{V.ClearColor{0.025,0.035,0.055,1.0}},V.DepthClear{1.0}])
    V.CommandBuffer.bind_graphics_pipeline(command,pipeline)
    V.CommandBuffer.set_viewport(command,V.Viewport{0.0,0.0,U32.to_f32(width),U32.to_f32(height),0.0,1.0})
    V.CommandBuffer.set_scissor(command,V.RenderArea{V.Offset2D{0,0},V.Extent2D{width,height}})
    V.CommandBuffer.push_constants(command,GPU.matrix_extent(R.Camera.basis(camera),width,height))
    GPU.draw(command,geometry)
    V.CommandBuffer.end_render_pass(command)
    E.transition(command,color,1,2,1000001002,1024,8192,256,0)
    V.CommandBuffer.end(command)
    V.Fence.reset(render)
    V.Device.submit_synced(device,command,render,[],[finished])

def record(+device: V.Device, +frame: Frame, +target: SlotTarget, acquisition: V.Acquisition, index: U32, camera: R.Camera, geometry: GPU.Geometry) -> V.Action(Unit):
  SlotTarget{shared,images,depth} = target
  do V.Action<Unit>:
    image : ImageTarget <- at(images,index)
    record_image(device,frame,target,acquisition,image,camera,geometry)


def promoted(+device: V.Device, +target: Target, result: V.VkResult(Scene.Programs)) -> V.Action(Target):
  Target{sc,images,pass,layout,pipeline,w,h,format,old} = target
  match result:
    case Fail{error}:
      do V.Action<Target>:
        destroy(device,target)
        IO.pure(V.VkResult(Target),Fail{error})
    case Done{programs}:
      V.Action.pure(Target,Target{sc,images,pass,layout,pipeline,w,h,format,Some{programs}})

def promote(+device: V.Device, +target: Target, assets: Scene.Assets) -> V.Action(Target):
  Target{sc,images,pass,layout,pipeline,w,h,format,old} = target
  do V.Action<Target>:
    result : V.VkResult(Scene.Programs) <- V.Action.lift(V.VkResult(Scene.Programs),Scene.programs(device,assets,pass))
    promoted(device,target,result)

def slot_images(+target: Target, +depth: E.Attachment, xs: List<&2,SwapImage>, +device: V.Device, +owned: List<&2,Owned>, +acc: List<&2,ImageTarget>) -> V.Action(SlotTarget):
  Target{sc,borrowed,+pass,layout,pipeline,+w,+h,format,programs} = target
  E.Attachment{image,memory,+view} = depth
  match xs:
    case Nil{}: V.Action.pure(SlotTarget,SlotTarget{target,acc,depth})
    case SwapImage{+color,+color_view} <> rest:
      guard(V.Framebuffer,SlotTarget,device,owned,V.Device.create_framebuffer(device,V.FramebufferCreateInfo{pass,[color_view,view],V.Extent2D{w,h}}),+framebuffer =>
        slot_images(target,depth,rest,device,OwnFramebuffer{framebuffer} <> owned,ImageTarget{color,color_view,framebuffer} <> acc))

def slot_depth(+device: V.Device, +target: Target, +image: V.ImageHandle, +memory: V.DeviceMemory) -> V.Action(SlotTarget):
  Target{sc,+images,pass,layout,pipeline,w,h,format,programs} = target
  +owned : List<&2,Owned> = [OwnImage{image},OwnMemory{memory}]
  guard(V.ImageView,SlotTarget,device,owned,V.Device.create_image_view(device,V.ImageViewCreateInfo{image,1,V.ImageSubresourceRange{2,0,1,0,1}}),+view =>
    slot_images(target,E.Attachment{image,memory,view},List.reverse(&2,SwapImage,images),device,OwnView{view} <> owned,Nil{}))

def slot_memory(+context: WSI.Context, +target: Target, +image: V.ImageHandle, requirements: V.MemoryRequirements) -> V.Action(SlotTarget):
  WSI.Context{window,instance,physical,surface,+device,g,p} = context
  guard(V.DeviceMemory,SlotTarget,device,[OwnImage{image}],Memory.allocate(instance,physical,device,requirements,0),+memory =>
    guard(Unit,SlotTarget,device,[OwnImage{image},OwnMemory{memory}],V.Device.bind_image_memory(device,image,memory,W.zero()),unit =>
      slot_depth(device,target,image,memory)))

def slot_target(+context: WSI.Context, +target: Target) -> V.Action(SlotTarget):
  WSI.Context{window,instance,physical,surface,+device,g,p} = context
  Target{sc,images,pass,layout,pipeline,+w,+h,format,programs} = target
  guard(V.ImageHandle,SlotTarget,device,Nil{},V.Device.create_image(device,V.ImageCreateInfo{126,V.Extent2D{w,h},1,1,32}),+image =>
    guard(V.MemoryRequirements,SlotTarget,device,[OwnImage{image}],V.Device.get_image_memory_requirements(device,image),requirements =>
      slot_memory(context,target,image,requirements)))

def slot_destroy_images(xs: List<&2,ImageTarget>, +device: V.Device) -> V.Action(Unit):
  match xs:
    case Nil{}: V.Action.pure(Unit,Unit{})
    case ImageTarget{image,view,framebuffer} <> rest:
      do V.Action<Unit>:
        V.Device.destroy_framebuffer(device,framebuffer)
        slot_destroy_images(rest,device)

def slot_destroy(+device: V.Device, target: SlotTarget) -> V.Action(Unit):
  SlotTarget{shared,images,E.Attachment{depth,memory,view}} = target
  do V.Action<Unit>:
    slot_destroy_images(images,device)
    V.Device.destroy_image_view(device,view)
    V.Device.destroy_image(device,depth)
    V.Device.free_memory(device,memory)
