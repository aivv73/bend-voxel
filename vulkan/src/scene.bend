import Base
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W
import ../shaders/spirv.bend as S
import ../shaders/appearance_uniforms.bend as U
import ../../deps/bend-vulkan/examples/indexed_offscreen.bend as E
import ../../deps/bend-vulkan/examples/offscreen_roundtrip.bend as Memory
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D
import ./renderer.bend as GPU
import ./chunks.bend as C
import ./generation.bend as G
import ../../deps/bend-vulkan/src/upload.bend as Upload
import ./mesh.bend as M
import ./appearance.bend as A
import ./timing.bend as Timing

type Assets is Data:
  Assets{uniform: E.BoundBuffer, schema: V.DescriptorSetLayout, sampled_schema: V.DescriptorSetLayout, pool: V.DescriptorPool, frame: V.DescriptorSet, sampled: V.DescriptorSet, sampler: V.Sampler, shadow: E.Attachment, shadow_pass: V.RenderPass, shadow_framebuffer: V.Framebuffer, shadow_pipeline: V.GraphicsPipeline, frame_layout: V.PipelineLayout, main_layout: V.PipelineLayout, indices: E.BoundBuffer, palette: A.Palette}
type Group is Data:
  Group{assets: Assets, geometry: GPU.Geometry, installed: U32, uploads: U32}
type Programs is Data:
  Programs{world: V.GraphicsPipeline, background: V.GraphicsPipeline, rings: V.GraphicsPipeline}

def attachment(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, format: U32, +aspect: U32, usage: U32, size: V.Extent2D) -> V.Action(E.Attachment):
  do V.Action<E.Attachment>:
    +image : V.ImageHandle <- V.Device.create_image(device,V.ImageCreateInfo{format,size,1,1,usage})
    requirements : V.MemoryRequirements <- V.Device.get_image_memory_requirements(device,image)
    +memory : V.DeviceMemory <- Memory.allocate(instance,physical,device,requirements,0)
    V.Device.bind_image_memory(device,image,memory,W.zero())
    view : V.ImageView <- V.Device.create_image_view(device,V.ImageViewCreateInfo{image,1,V.ImageSubresourceRange{aspect,0,1,0,1}})
    return E.Attachment{image,memory,view}

def attachment_view(a: E.Attachment) -> V.ImageView:
  E.Attachment{i,m,v} = a
  v

def buffer_handle(b: E.BoundBuffer) -> V.Buffer:
  E.BoundBuffer{buffer,memory} = b
  buffer

def buffer_memory(b: E.BoundBuffer) -> V.DeviceMemory:
  E.BoundBuffer{buffer,memory} = b
  memory

def attributes() -> List<V.VertexInputAttribute>:
  [V.VertexInputAttribute{0,0,106,0},V.VertexInputAttribute{1,0,37,12},V.VertexInputAttribute{2,0,37,16},V.VertexInputAttribute{3,0,106,20},V.VertexInputAttribute{4,0,103,32}]

def pipeline_finished(+device: V.Device, vertex: V.ShaderModule, fragment: V.ShaderModule, result: V.VkResult(V.GraphicsPipeline)) -> V.Action(V.GraphicsPipeline):
  do V.Action<V.GraphicsPipeline>:
    V.Device.destroy_shader_module(device,fragment)
    V.Device.destroy_shader_module(device,vertex)
    IO.pure(V.VkResult(V.GraphicsPipeline),result)

def fragment_ready(+device: V.Device, +vertex: V.ShaderModule, result: V.VkResult(V.ShaderModule), layout: V.PipelineLayout, pass: V.RenderPass, +kind: U32, depth: Maybe<&2,V.DepthState>) -> V.Action(V.GraphicsPipeline):
  match result:
    case Fail{error}:
      do V.Action<V.GraphicsPipeline>:
        V.Device.destroy_shader_module(device,vertex)
        IO.pure(V.VkResult(V.GraphicsPipeline),Fail{error})
    case Done{+fragment}:
      do V.Action<V.GraphicsPipeline>:
        pipeline : V.VkResult(V.GraphicsPipeline) <- V.Action.lift(V.VkResult(V.GraphicsPipeline),V.Device.create_graphics_pipeline(device,V.GraphicsPipelineCreateInfo{layout,pass,vertex,fragment,Bool.pick(List<V.VertexInputBinding>,U32.is_zero(kind),[],[V.VertexInputBinding{0,40,0}]),Bool.pick(List<V.VertexInputAttribute>,U32.is_eq(kind,1),attributes(),Bool.pick(List<V.VertexInputAttribute>,U32.is_eq(kind,2),[V.VertexInputAttribute{0,0,106,0}],[])),3,V.RasterState{Bool.pick(U32,U32.is_zero(kind),0,2),0},depth,15}))
        pipeline_finished(device,vertex,fragment,pipeline)

def pipeline(+device: V.Device, layout: V.PipelineLayout, pass: V.RenderPass, vertex_words: List<U32>, fragment_words: List<U32>, kind: U32, depth: Maybe<&2,V.DepthState>) -> V.Action(V.GraphicsPipeline):
  do V.Action<V.GraphicsPipeline>:
    +vertex : V.ShaderModule <- V.Device.create_shader_module(device,vertex_words)
    fragment : V.VkResult(V.ShaderModule) <- V.Action.lift(V.VkResult(V.ShaderModule),V.Device.create_shader_module(device,fragment_words))
    fragment_ready(device,vertex,fragment,layout,pass,kind,depth)

def required_palette(palette: Maybe<&2,A.Palette>) -> V.Action(A.Palette):
  match palette:
    case None{}: IO.pure(V.VkResult(A.Palette),Fail{(1,"Invalid pinned linear palette")})
    case Some{p}: V.Action.pure(A.Palette,p)

def palette(a: Assets) -> A.Palette:
  Assets{u,s,ss,p,f,sd,sampler,sh,sp,sf,ps,fl,ml,ix,palette} = a
  palette

def create(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device) -> V.Action(Group):
  do V.Action<Group>:
    palette : A.Palette <- required_palette(A.palette())
    +uniform : E.BoundBuffer <- E.buffer(instance,physical,device,U.byte_size(),16)
    +schema : V.DescriptorSetLayout <- V.Device.create_descriptor_set_layout(device,V.DescriptorSetLayoutCreateInfo{[V.DescriptorBinding{0,V.UniformDescriptor{},1,17}]})
    +sampled_schema : V.DescriptorSetLayout <- V.Device.create_descriptor_set_layout(device,V.DescriptorSetLayoutCreateInfo{[V.DescriptorBinding{0,V.SampledDescriptor{},1,16}]})
    +pool : V.DescriptorPool <- V.Device.create_descriptor_pool(device,V.DescriptorPoolCreateInfo{2,[V.DescriptorPoolSize{V.UniformDescriptor{},1},V.DescriptorPoolSize{V.SampledDescriptor{},1}]})
    +frame : V.DescriptorSet <- V.Device.allocate_descriptor_set(device,pool,schema)
    +sampled : V.DescriptorSet <- V.Device.allocate_descriptor_set(device,pool,sampled_schema)
    +sampler : V.Sampler <- V.Device.create_sampler(device,V.SamplerCreateInfo{0,0,0,2,2,2,0.0,0.0,4})
    +shadow : E.Attachment <- attachment(instance,physical,device,126,2,37,V.Extent2D{512,512})
    +sv : V.ImageView = attachment_view(shadow)
    ub : V.Buffer = buffer_handle(uniform)
    V.Device.update_descriptor_set(device,frame,[V.UniformWrite{0,0,[V.DescriptorBuffer{ub,W.zero(),W.of_u32(U.byte_size())}]}])
    V.Device.update_descriptor_set(device,sampled,[V.SampledWrite{0,0,[V.DescriptorImage{sv,sampler,4}]}])
    +frame_layout : V.PipelineLayout <- V.Device.create_pipeline_layout(device,V.PipelineLayoutCreateInfo{[schema],None{}})
    +main_layout : V.PipelineLayout <- V.Device.create_pipeline_layout(device,V.PipelineLayoutCreateInfo{[schema,sampled_schema],None{}})
    +shadow_pass : V.RenderPass <- V.Device.create_render_pass(device,V.RenderPassCreateInfo{[],Some{V.AttachmentInfo{126,1,0}}})
    shadow_framebuffer : V.Framebuffer <- V.Device.create_framebuffer(device,V.FramebufferCreateInfo{shadow_pass,[sv],V.Extent2D{512,512}})
    shadow_pipeline : V.GraphicsPipeline <- pipeline(device,frame_layout,shadow_pass,S.appearance_shadow_vert_words(),S.appearance_shadow_frag_words(),2,Some{V.DepthState{True{},True{},1}})
    +indices : E.BoundBuffer <- E.buffer(instance,physical,device,2304,64)
    im : V.DeviceMemory = buffer_memory(indices)
    V.Device.write_memory(device,im,W.zero(),E.bytes(A.static_indices()))
    return Group{Assets{uniform,schema,sampled_schema,pool,frame,sampled,sampler,shadow,shadow_pass,shadow_framebuffer,shadow_pipeline,frame_layout,main_layout,indices,palette},GPU.Empty{},4294967295,0}

def assets(group: Group) -> Assets:
  Group{assets,geometry,installed,uploads} = group
  assets

def programs_finished(+device: V.Device, +world: V.GraphicsPipeline, +background: V.GraphicsPipeline, result: V.VkResult(V.GraphicsPipeline)) -> V.Action(Programs):
  match result:
    case Done{rings}: V.Action.pure(Programs,Programs{world,background,rings})
    case Fail{error}:
      do V.Action<Programs>:
        V.Device.destroy_graphics_pipeline(device,background)
        V.Device.destroy_graphics_pipeline(device,world)
        IO.pure(V.VkResult(Programs),Fail{error})

def programs_background(+device: V.Device, +world: V.GraphicsPipeline, pass: V.RenderPass, frame_layout: V.PipelineLayout, result: V.VkResult(V.GraphicsPipeline)) -> V.Action(Programs):
  match result:
    case Fail{error}:
      do V.Action<Programs>:
        V.Device.destroy_graphics_pipeline(device,world)
        IO.pure(V.VkResult(Programs),Fail{error})
    case Done{+background}:
      do V.Action<Programs>:
        result : V.VkResult(V.GraphicsPipeline) <- V.Action.lift(V.VkResult(V.GraphicsPipeline),pipeline(device,frame_layout,pass,S.appearance_ring_vert_words(),S.appearance_ring_frag_words(),0,Some{V.DepthState{True{},False{},3}}))
        programs_finished(device,world,background,result)

def programs(+device: V.Device, a: Assets, +pass: V.RenderPass) -> V.Action(Programs):
  Assets{u,s,ss,p,f,sd,sampler,sh,sp,sf,ps,+fl,+ml,ix,palette} = a
  do V.Action<Programs>:
    +world : V.GraphicsPipeline <- pipeline(device,ml,pass,S.appearance_world_vert_words(),S.appearance_world_frag_words(),1,Some{V.DepthState{True{},True{},1}})
    result : V.VkResult(V.GraphicsPipeline) <- V.Action.lift(V.VkResult(V.GraphicsPipeline),pipeline(device,ml,pass,S.appearance_backdrop_vert_words(),S.appearance_backdrop_frag_words(),0,None{}))
    programs_background(device,world,pass,fl,result)

def destroy_programs(+device: V.Device, p: Programs) -> V.Action(Unit):
  Programs{world,background,rings} = p
  do V.Action<Unit>:
    V.Device.destroy_graphics_pipeline(device,rings)
    V.Device.destroy_graphics_pipeline(device,background)
    V.Device.destroy_graphics_pipeline(device,world)

def failed_install(+device: V.Device, command: V.CommandBuffer, plan: G.Plan, staging: Upload.Staging, primary: V.VkResult(Unit)) -> V.Action(Unit):
  do IO<V.VkResult(Unit)>:
    reset : V.VkResult(Unit) <- V.CommandBuffer.reset(command)
    retired : V.VkResult(Unit) <- G.retire_plan(device,plan)
    released : V.VkResult(Unit) <- Upload.release(device,staging)
    return V.Entry.finish(Unit,primary,V.Entry.finish(Unit,reset,V.Entry.finish(Unit,retired,released)))

def install_rejected(device: V.Device, plan: G.Plan, error: U32 & String) -> V.Action(Group & C.ChunkSet):
  do IO<V.VkResult(Group & C.ChunkSet)>:
    cleanup : V.VkResult(Unit) <- G.abort(device,plan)
    return V.Entry.finish(Group & C.ChunkSet,Fail{error},cleanup)

def install_selected(device: V.Device, a: Assets, revision: U32, uploads: U32, set: C.ChunkSet, plan: G.Plan, retired: V.VkResult(Unit)) -> V.Action(Group & C.ChunkSet):
  G.Plan{geometry,copies,created,bytes} = plan
  match retired:
    case Fail{error}: install_rejected(device,plan,error)
    case Done{unit}: V.Action.pure(Group & C.ChunkSet,(Group{a,geometry,revision,(uploads + U32.from_nat(List.length(&2,G.Copy,copies)) : U32)},set))

def install_committed(+device: V.Device, a: Assets, old: GPU.Geometry, revision: U32, uploads: U32, set: C.ChunkSet, plan: G.Plan, released: V.VkResult(Unit)) -> V.Action(Group & C.ChunkSet):
  G.Plan{+geometry,+copies,created,bytes} = plan
  match released:
    case Fail{error}: install_rejected(device,plan,error)
    case Done{unit}:
      do V.Action<Group & C.ChunkSet>:
        retired : V.VkResult(Unit) <- V.Action.lift(V.VkResult(Unit),G.commit(device,old,geometry))
        install_selected(device,a,revision,uploads,set,plan,retired)

def install_recorded(+device: V.Device, command: V.CommandBuffer, a: Assets, old: GPU.Geometry, +revision: U32, +uploads: U32, set: C.ChunkSet, +staging: Upload.Staging, +plan: G.Plan, result: V.VkResult(Unit)) -> V.Action(Group & C.ChunkSet):
  match result:
    case Fail{(+code,+message)}:
      do V.Action<Group & C.ChunkSet>:
        failed_install(device,command,plan,staging,Fail{(code,message)})
        IO.pure(V.VkResult(Group & C.ChunkSet),Fail{(code,message)})
    case Done{unit}:
      do V.Action<Group & C.ChunkSet>:
        released : V.VkResult(Unit) <- V.Action.lift(V.VkResult(Unit),Upload.release(device,staging))
        install_committed(device,a,old,revision,uploads,set,plan,released)

def record_install(+device: V.Device, +command: V.CommandBuffer, +fence: V.Fence, plan: G.Plan) -> V.Action(Unit):
  do V.Action<Unit>:
    V.CommandBuffer.begin(command)
    G.record(command,plan)
    E.complete(device,command,fence)
    E.reset(device,command,fence)

def chunk_installed(+device: V.Device, +command: V.CommandBuffer, fence: V.Fence, a: Assets, old: GPU.Geometry, revision: U32, uploads: U32, pair: (C.ChunkSet & Upload.Staging) & V.VkResult(G.Plan)) -> V.Action(Group & C.ChunkSet):
  (owner,result) = pair
  (set,storage) = owner
  match result:
    case Fail{error}:
      do IO<V.VkResult(Group & C.ChunkSet)>:
        cleanup : V.VkResult(Unit) <- Upload.release(device,storage)
        return V.Entry.finish(Group & C.ChunkSet,Fail{error},cleanup)
    case Done{+plan}:
      +staging : Upload.Staging = storage
      do V.Action<Group & C.ChunkSet>:
        result : V.VkResult(Unit) <- V.Action.lift(V.VkResult(Unit),record_install(device,command,fence,plan))
        install_recorded(device,command,a,old,revision,uploads,set,staging,plan,result)

def install_chunks(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, +command: V.CommandBuffer, +fence: V.Fence, group: Group, +revision: U32, set: C.ChunkSet) -> V.Action(Group & C.ChunkSet):
  Group{a,+geometry,previous,uploads} = group
  do V.Action<Group & C.ChunkSet>:
    V.CommandBuffer.reset(command)
    V.Fence.reset(fence)
    V.Device.collect_retired(device)
    pair : (C.ChunkSet & Upload.Staging) & V.VkResult(G.Plan) <- V.Action.lift((C.ChunkSet & Upload.Staging) & V.VkResult(G.Plan),G.prepare(instance,physical,device,geometry,Upload.Empty{},set))
    chunk_installed(device,command,fence,a,geometry,revision,uploads,pair)

def upload(+device: V.Device, a: Assets, words: Maybe<Array<U32>>) -> V.Action(Unit):
  Assets{uniform,s,ss,p,f,sd,sampler,sh,sp,sf,ps,fl,ml,ix,palette} = a
  match words:
    case None{}: D.require(False{},"Invalid production frame input")
    case Some{words}:
      do V.Action<Unit>:
        array : Array<U32> <- GPU.upload(device,uniform,U.byte_size(),words)
        return Unit{}

def viewport(+command: V.CommandBuffer, +width: U32, +height: U32) -> V.Action(Unit):
  do V.Action<Unit>:
    V.CommandBuffer.set_viewport(command,V.Viewport{0.0,0.0,U32.to_f32(width),U32.to_f32(height),0.0,1.0})
    V.CommandBuffer.set_scissor(command,V.RenderArea{V.Offset2D{0,0},V.Extent2D{width,height}})

def record_rings(enabled: Bool, +command: V.CommandBuffer, rings: V.GraphicsPipeline, frame: V.DescriptorSet, indices: V.Buffer) -> V.Action(Unit):
  match enabled:
    case False{}: V.Action.pure(Unit,Unit{})
    case True{}:
      do V.Action<Unit>:
        V.CommandBuffer.bind_graphics_pipeline(command,rings)
        V.CommandBuffer.bind_descriptor_sets(command,0,[frame])
        V.CommandBuffer.bind_index_buffer(command,indices,W.zero(),1)
        V.CommandBuffer.draw_indexed(command,V.IndexedDraw{576,1,0,V.BaseVertex{0},0})

def record(+command: V.CommandBuffer, group: Group, programs: Programs, framebuffer: V.Framebuffer, +width: U32, +height: U32, show_rings: Bool, +queries: Maybe<&2,V.QueryPool>) -> V.Action(Unit):
  Group{Assets{uniform,s,ss,p,+frame,+sampled,sampler,E.Attachment{+shadow,sm,sv},sp,sf,shadow_pipeline,fl,ml,E.BoundBuffer{+indices,im},palette},+geometry,revision,uploads} = group
  Programs{world,background,rings} = programs
  do V.Action<Unit>:
    Timing.write(command,queries,2)
    GPU.publish(command,geometry)
    V.CommandBuffer.pipeline_barrier(command,16384,140,[V.MemoryBarrier{16384,14}],[],[])
    V.CommandBuffer.pipeline_barrier(command,4992,768,[V.MemoryBarrier{3616,1536}],[],[])
    E.transition(command,shadow,2,0,3,4992,768,0,1536)
    V.CommandBuffer.begin_render_pass(command,sf,V.RenderArea{V.Offset2D{0,0},V.Extent2D{512,512}},[V.DepthClear{1.0}])
    V.CommandBuffer.bind_graphics_pipeline(command,shadow_pipeline)
    V.CommandBuffer.bind_descriptor_sets(command,0,[frame])
    viewport(command,512,512)
    GPU.draw_shadow(command,geometry)
    V.CommandBuffer.end_render_pass(command)
    E.transition(command,shadow,2,3,4,768,128,1024,32)
    Timing.write(command,queries,3)
    Timing.write(command,queries,4)
    V.CommandBuffer.begin_render_pass(command,framebuffer,V.RenderArea{V.Offset2D{0,0},V.Extent2D{width,height}},[V.ColorClear{V.ClearColor{0.0,0.0,0.0,1.0}},V.DepthClear{1.0}])
    viewport(command,width,height)
    V.CommandBuffer.bind_graphics_pipeline(command,background)
    V.CommandBuffer.bind_descriptor_sets(command,0,[frame,sampled])
    V.CommandBuffer.bind_index_buffer(command,indices,W.zero(),1)
    V.CommandBuffer.draw_indexed(command,V.IndexedDraw{6,1,0,V.BaseVertex{0},0})
    V.CommandBuffer.bind_graphics_pipeline(command,world)
    V.CommandBuffer.bind_descriptor_sets(command,0,[frame,sampled])
    GPU.draw(command,geometry)
    record_rings(show_rings,command,rings,frame,indices)
    V.CommandBuffer.end_render_pass(command)
    Timing.write(command,queries,5)


def slot_assets(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, shared: Assets) -> V.Action(Assets):
  Assets{u,+schema,+sampled_schema,p,f,sd,+sampler,sh,+shadow_pass,sf,+shadow_pipeline,+frame_layout,+main_layout,+indices,+palette} = shared
  do V.Action<Assets>:
    +uniform : E.BoundBuffer <- E.buffer(instance,physical,device,U.byte_size(),16)
    +pool : V.DescriptorPool <- V.Device.create_descriptor_pool(device,V.DescriptorPoolCreateInfo{2,[V.DescriptorPoolSize{V.UniformDescriptor{},1},V.DescriptorPoolSize{V.SampledDescriptor{},1}]})
    +frame : V.DescriptorSet <- V.Device.allocate_descriptor_set(device,pool,schema)
    +sampled : V.DescriptorSet <- V.Device.allocate_descriptor_set(device,pool,sampled_schema)
    +shadow : E.Attachment <- attachment(instance,physical,device,126,2,37,V.Extent2D{512,512})
    +sv : V.ImageView = attachment_view(shadow)
    ub : V.Buffer = buffer_handle(uniform)
    V.Device.update_descriptor_set(device,frame,[V.UniformWrite{0,0,[V.DescriptorBuffer{ub,W.zero(),W.of_u32(U.byte_size())}]}])
    V.Device.update_descriptor_set(device,sampled,[V.SampledWrite{0,0,[V.DescriptorImage{sv,sampler,4}]}])
    framebuffer : V.Framebuffer <- V.Device.create_framebuffer(device,V.FramebufferCreateInfo{shadow_pass,[sv],V.Extent2D{512,512}})
    return Assets{uniform,schema,sampled_schema,pool,frame,sampled,sampler,shadow,shadow_pass,framebuffer,shadow_pipeline,frame_layout,main_layout,indices,palette}
