import Base
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/src/core.bend as Core
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W
import ../../deps/bend-vulkan/examples/indexed_offscreen.bend as E
import ../../deps/bend-vulkan/examples/offscreen_roundtrip.bend as Memory
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D
import ../src/appearance.bend as F
import ../shaders/appearance_uniforms.bend as U
import ../../render.bend as R
import ../../voxel.bend as X
import ../shaders/spirv.bend as S

type Case is Data:
  Case{name: String, direction: U32, anchor: X.Cell, u: F32, v: F32, width: F32, height: F32, material: U32, brush: Maybe<&2,X.MetricSphere>, expected: X.Cell, selected: Bool, production: Bool}
type Frame is Data:
  Frame{uniform: E.BoundBuffer, set: V.DescriptorSet, sampled: V.DescriptorSet, sampler: V.Sampler}
type Target is Data:
  Target{color: E.Attachment, depth: E.Attachment, framebuffer: V.Framebuffer, stage: E.BoundBuffer, shadow: E.Attachment, shadow_framebuffer: V.Framebuffer}
type Programs is Data:
  Programs{abi: V.GraphicsPipeline, adapter: V.GraphicsPipeline, world: V.GraphicsPipeline, culled: V.GraphicsPipeline, sample: V.GraphicsPipeline, depth: V.GraphicsPipeline}
type Fixture is Data:
  Fixture{device: V.Device, command: V.CommandBuffer, fence: V.Fence, frame: Frame, target: Target, vertices: E.BoundBuffer, index: E.BoundBuffer, programs: Programs}

def extent() -> V.Extent2D:
  V.Extent2D{512,2}

def area() -> V.RenderArea:
  V.RenderArea{V.Offset2D{0,0},extent()}

def attachment(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, format: U32, +aspect: U32, usage: U32, size: V.Extent2D) -> V.Action(E.Attachment):
  do V.Action<E.Attachment>:
    +image : V.ImageHandle <- V.Device.create_image(device,V.ImageCreateInfo{format,size,1,1,usage})
    requirements : V.MemoryRequirements <- V.Device.get_image_memory_requirements(device,image)
    +memory : V.DeviceMemory <- Memory.allocate(instance,physical,device,requirements,0)
    V.Device.bind_image_memory(device,image,memory,W.zero())
    view : V.ImageView <- V.Device.create_image_view(device,V.ImageViewCreateInfo{image,1,V.ImageSubresourceRange{aspect,0,1,0,1}})
    return E.Attachment{image,memory,view}

def attributes() -> List<V.VertexInputAttribute>:
  [V.VertexInputAttribute{0,0,106,0},V.VertexInputAttribute{1,0,37,12},V.VertexInputAttribute{2,0,37,16},V.VertexInputAttribute{3,0,106,20},V.VertexInputAttribute{4,0,103,32}]

def pipeline(+device: V.Device, layout: V.PipelineLayout, pass: V.RenderPass, vertex_words: List<U32>, fragment_words: List<U32>, +mesh: Bool, cull: U32, front: U32, depth: Maybe<&2,V.DepthState>) -> V.Action(V.GraphicsPipeline):
  do V.Action<V.GraphicsPipeline>:
    +vertex : V.ShaderModule <- V.Device.create_shader_module(device,vertex_words)
    +fragment : V.ShaderModule <- V.Device.create_shader_module(device,fragment_words)
    result : V.GraphicsPipeline <- V.Device.create_graphics_pipeline(device,V.GraphicsPipelineCreateInfo{layout,pass,vertex,fragment,Bool.pick(List<V.VertexInputBinding>,mesh,[V.VertexInputBinding{0,40,0}],[]),Bool.pick(List<V.VertexInputAttribute>,mesh,attributes(),[]),3,V.RasterState{cull,front},depth,15})
    V.Device.destroy_shader_module(device,vertex)
    V.Device.destroy_shader_module(device,fragment)
    return result

def descriptors(+device: V.Device, frame: Frame) -> V.Action(Unit):
  Frame{E.BoundBuffer{ub,um},+set,+sampled,sampler} = frame
  V.Device.update_descriptor_set(device,set,[V.UniformWrite{0,0,[V.DescriptorBuffer{ub,W.zero(),W.of_u32(2336)}]}])

def buffer_memory(buffer: E.BoundBuffer) -> V.DeviceMemory:
  E.BoundBuffer{b,m} = buffer
  m

def attachment_view(a: E.Attachment) -> V.ImageView:
  E.Attachment{i,m,v} = a
  v

def create(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device) -> V.Action(Fixture):
  do V.Action<Fixture>:
    +uniform : E.BoundBuffer <- E.buffer(instance,physical,device,2336,16)
    +vertices : E.BoundBuffer <- E.buffer(instance,physical,device,240,128)
    +index : E.BoundBuffer <- E.buffer(instance,physical,device,48,64)
    +stage : E.BoundBuffer <- E.buffer(instance,physical,device,4096,2)
    im : V.DeviceMemory = buffer_memory(index)
    V.Device.write_memory(device,im,W.zero(),E.bytes([0,1,2,3,4,5,0,1,2,2,3,0]))
    +schema : V.DescriptorSetLayout <- V.Device.create_descriptor_set_layout(device,V.DescriptorSetLayoutCreateInfo{[V.DescriptorBinding{0,V.UniformDescriptor{},1,17}]})
    +sample_schema : V.DescriptorSetLayout <- V.Device.create_descriptor_set_layout(device,V.DescriptorSetLayoutCreateInfo{[V.DescriptorBinding{0,V.SampledDescriptor{},1,16}]})
    +pool : V.DescriptorPool <- V.Device.create_descriptor_pool(device,V.DescriptorPoolCreateInfo{2,[V.DescriptorPoolSize{V.UniformDescriptor{},1},V.DescriptorPoolSize{V.SampledDescriptor{},1}]})
    +set : V.DescriptorSet <- V.Device.allocate_descriptor_set(device,pool,schema)
    +sampled : V.DescriptorSet <- V.Device.allocate_descriptor_set(device,pool,sample_schema)
    +sampler : V.Sampler <- V.Device.create_sampler(device,V.SamplerCreateInfo{0,0,0,2,2,2,0.0,0.0,4})
    +color : E.Attachment <- attachment(instance,physical,device,37,1,17,extent())
    +depth : E.Attachment <- attachment(instance,physical,device,126,2,32,extent())
    +shadow : E.Attachment <- attachment(instance,physical,device,126,2,36,V.Extent2D{512,512})
    +sv : V.ImageView = attachment_view(shadow)
    V.Device.update_descriptor_set(device,sampled,[V.SampledWrite{0,0,[V.DescriptorImage{sv,sampler,4}]}])
    +frame : Frame = Frame{uniform,set,sampled,sampler}
    descriptors(device,frame)
    +only_frame : V.PipelineLayout <- V.Device.create_pipeline_layout(device,V.PipelineLayoutCreateInfo{[schema],None{}})
    +world_layout : V.PipelineLayout <- V.Device.create_pipeline_layout(device,V.PipelineLayoutCreateInfo{[schema,sample_schema],None{}})
    +depth_layout : V.PipelineLayout <- V.Device.create_pipeline_layout(device,V.PipelineLayoutCreateInfo{[],None{}})
    +pass : V.RenderPass <- V.Device.create_render_pass(device,V.RenderPassCreateInfo{[V.AttachmentInfo{37,1,0}],Some{V.AttachmentInfo{126,1,0}}})
    +shadow_pass : V.RenderPass <- V.Device.create_render_pass(device,V.RenderPassCreateInfo{[],Some{V.AttachmentInfo{126,1,0}}})
    cv : V.ImageView = attachment_view(color)
    dv : V.ImageView = attachment_view(depth)
    framebuffer : V.Framebuffer <- V.Device.create_framebuffer(device,V.FramebufferCreateInfo{pass,[cv,dv],extent()})
    shadow_framebuffer : V.Framebuffer <- V.Device.create_framebuffer(device,V.FramebufferCreateInfo{shadow_pass,[sv],V.Extent2D{512,512}})
    abi : V.GraphicsPipeline <- pipeline(device,only_frame,pass,S.appearance_backdrop_vert_words(),S.appearance_abi_frag_words(),False{},0,0,None{})
    adapter : V.GraphicsPipeline <- pipeline(device,world_layout,pass,S.fixture_metadata_adapter_words(),S.appearance_world_frag_words(),True{},0,0,None{})
    world : V.GraphicsPipeline <- pipeline(device,world_layout,pass,S.appearance_world_vert_words(),S.appearance_world_frag_words(),True{},2,0,Some{V.DepthState{True{},True{},1}})
    culled : V.GraphicsPipeline <- pipeline(device,world_layout,pass,S.appearance_world_vert_words(),S.appearance_world_frag_words(),True{},2,1,Some{V.DepthState{True{},True{},1}})
    sample : V.GraphicsPipeline <- pipeline(device,world_layout,pass,S.appearance_backdrop_vert_words(),S.fixture_sample_fixture_words(),False{},0,0,None{})
    depth_pipeline : V.GraphicsPipeline <- pipeline(device,depth_layout,shadow_pass,S.fixture_depth_fixture_words(),S.fixture_depth_fragment_words(),False{},0,0,Some{V.DepthState{True{},True{},7}})
    programs : Programs = Programs{abi,adapter,world,culled,sample,depth_pipeline}
    target : Target = Target{color,depth,framebuffer,stage,shadow,shadow_framebuffer}
    +commands : V.CommandPool <- V.Device.create_command_pool(device)
    command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,commands)
    fence : V.Fence <- V.Device.create_fence(device,False{})
    return Fixture{device,command,fence,frame,target,vertices,index,programs}

def axes(d: U32, n: F32, u: F32, v: F32) -> R.Vec3:
  match d:
    case 0: R.Vec3{n,u,v}
    case 1: R.Vec3{n,u,v}
    case 2: R.Vec3{u,n,v}
    case 3: R.Vec3{u,n,v}
    case _: R.Vec3{u,v,n}

def basis_axes(d: U32) -> R.Basis:
  match d:
    case 0: R.Basis{R.Vec3{0.0,0.0,0.0},R.Vec3{0.0,F32.neg(1.0),0.0},R.Vec3{0.0,0.0,1.0},R.Vec3{1.0,0.0,0.0},4096.0,0.1}
    case 1: R.Basis{R.Vec3{0.0,0.0,0.0},R.Vec3{0.0,1.0,0.0},R.Vec3{0.0,0.0,1.0},R.Vec3{F32.neg(1.0),0.0,0.0},4096.0,0.1}
    case 2: R.Basis{R.Vec3{0.0,0.0,0.0},R.Vec3{1.0,0.0,0.0},R.Vec3{0.0,0.0,1.0},R.Vec3{0.0,1.0,0.0},4096.0,0.1}
    case 3: R.Basis{R.Vec3{0.0,0.0,0.0},R.Vec3{F32.neg(1.0),0.0,0.0},R.Vec3{0.0,0.0,1.0},R.Vec3{0.0,F32.neg(1.0),0.0},4096.0,0.1}
    case 4: R.Basis{R.Vec3{0.0,0.0,0.0},R.Vec3{1.0,0.0,0.0},R.Vec3{0.0,F32.neg(1.0),0.0},R.Vec3{0.0,0.0,1.0},4096.0,0.1}
    case _: R.Basis{R.Vec3{0.0,0.0,0.0},R.Vec3{1.0,0.0,0.0},R.Vec3{0.0,1.0,0.0},R.Vec3{0.0,0.0,F32.neg(1.0)},4096.0,0.1}

def position(+c: Case, u: F32, v: F32) -> R.Vec3:
  Case{name,+d,X.Cell{x,y,z},cu,cv,w,h,id,brush,e,s,p} = c
  +base : R.Vec3 = R.Vec3{U32.to_f32(x),U32.to_f32(y),U32.to_f32(z)}
  R.Vec3.add(base,axes(d,U32.to_f32((d % 2 : U32)),u,v))

def basis_with(+c: Case, axes: R.Basis) -> R.Basis:
  Case{name,d,anchor,u,v,w,h,id,brush,e,s,p} = c
  R.Basis{old,+right,+up,+forward,focal,near} = axes
  +ray = R.Vec3.add(forward,R.Vec3.scale(R.Vec3.add(right,up),0.03125))
  eye = R.Vec3.add(position(c,u,v),R.Vec3.scale(ray,F32.neg(5.0)))
  R.Basis{eye,right,up,forward,focal,near}

def basis(+c: Case) -> R.Basis:
  Case{name,+d,anchor,u,v,w,h,id,brush,e,s,p} = c
  basis_with(c,basis_axes(d))

def vertex(+c: Case, point: R.Vec3) -> List<U32>:
  Case{name,d,X.Cell{x,y,z},u,v,w,h,id,brush,e,s,p} = c
  R.Vec3{px,py,pz} = point
  [F32.bits(px),F32.bits(py),F32.bits(pz),(3351057 + d * 16777216 : U32),id,F32.bits(U32.to_f32(x)),F32.bits(U32.to_f32(y)),F32.bits(U32.to_f32(z)),F32.bits(w),F32.bits(h)]

def vertices(+c: Case) -> List<U32>:
  Case{name,+d,anchor,u,v,+w,+h,id,brush,e,s,p} = c
  +reverse = U32.is_eq(d,0) || U32.is_eq(d,3) || U32.is_eq(d,4)
  a b cc dd = vertex(c,position(c,0.0,0.0)) vertex(c,position(c,Bool.pick(F32,reverse,0.0,w),Bool.pick(F32,reverse,h,0.0))) vertex(c,position(c,w,h)) vertex(c,position(c,Bool.pick(F32,reverse,w,0.0),Bool.pick(F32,reverse,0.0,h)))
  List.concat(&1,U32,[a,b,cc,dd,vertex(c,position(c,0.0,0.0)),vertex(c,position(c,0.0,0.0))])

def mode(value: U32) -> F.Mode:
  match value:
    case 0: F.Shaded{}
    case 1: F.Basic{}
    case 2: F.Material{}
    case 3: F.Direction{}
    case 4: F.CellX{}
    case 5: F.CellY{}
    case 6: F.CellZ{}
    case _: F.Selected{}

def encoded(+c: Case, palette: F.Palette, m: U32) -> Maybe<Array<U32>>:
  Case{name,d,anchor,u,v,w,h,id,brush,e,s,p} = c
  F.encode(F.FrameInput{basis(c),512,2,1048576,palette,brush,F.Unorm{},mode(m)})

def range(fuel: Nat, +index: U32) -> List<U32>:
  match fuel:
    case 0n: []
    case 1n+rest: (1056964608 + index : U32) <> range(rest,(index + 1 : U32))

def sentinel() -> Maybe<Array<U32>>:
  U.pack(U.FrameWords{range(16n,0),range(16n,16),range(4n,32),range(4n,36),range(4n,40),range(4n,44),range(4n,48),range(4n,52),range(4n,56),range(20n,60),range(4n,80),range(500n,84)})

def print_words(+label: String, words: List<U32>, +index: U32) -> IO(Unit):
  match words:
    case Nil{}: IO.pure(Unit,Unit{})
    case Con{word,rest}:
      do IO<Unit>:
        IO.print(label ++ " " ++ U32.show(index) ++ " " ++ U32.show(word))
        print_words(label,rest,(index + 1 : U32))

def words(bytes: List<U32>) -> List<U32>:
  match bytes:
    case Con{a,Con{b,Con{c,Con{d,rest}}}}:
      (a + b * 256 + c * 65536 + d * 16777216 : U32) <> words(rest)
    case _: []

def upload_checked(pair: Array<U32> & V.VkResult(Unit)) -> V.Action(Unit):
  (array,result) = pair
  IO.pure(V.VkResult(Unit),result)

def upload_array(+device: V.Device, memory: V.DeviceMemory, array: Array<U32>) -> V.Action(Unit):
  do V.Action<Unit>:
    pair : Array<U32> & V.VkResult(Unit) <- V.Action.lift(Array<U32> & V.VkResult(Unit),V.Device.write_memory_words(device,memory,W.zero(),W.zero(),W.of_u32(2336),array))
    upload_checked(pair)

def upload(+f: Fixture, array: Maybe<Array<U32>>) -> V.Action(Unit):
  Fixture{device,command,fence,Frame{E.BoundBuffer{ub,memory},set,sampled,sampler},target,vertices,index,programs} = f
  match array:
    case None{}: D.require(False{},"Frame encoding rejected literal fixture")
    case Some{a}: upload_array(device,memory,a)

def choose_program(p: Programs, kind: U32) -> V.GraphicsPipeline:
  Programs{abi,adapter,world,culled,sample,depth} = p
  match kind:
    case 0: abi
    case 1: adapter
    case 2: world
    case 3: sample
    case _: culled

def bind_vertices(command: V.CommandBuffer, kind: U32, vertices: V.Buffer) -> V.Action(Unit):
  match kind:
    case 1: V.CommandBuffer.bind_vertex_buffer(command,0,vertices,W.zero())
    case 2: V.CommandBuffer.bind_vertex_buffer(command,0,vertices,W.zero())
    case 4: V.CommandBuffer.bind_vertex_buffer(command,0,vertices,W.zero())
    case _: V.Action.pure(Unit,Unit{})

def render(+f: Fixture, +initialized: Bool, +kind: U32) -> V.Action(List<U32>):
  Fixture{+device,+command,+fence,Frame{uniform,+set,+sampled,sampler},Target{E.Attachment{+color,cm,cv},E.Attachment{+depth,dm,dv},framebuffer,E.BoundBuffer{+stage,+sm},E.Attachment{+shadow,shm,shv},shadow_framebuffer},E.BoundBuffer{vertices,vm},E.BoundBuffer{+index,im},+programs} = f
  Programs{a,b,c,d,e,depth_pipeline} = programs
  do V.Action<List<U32>>:
    V.CommandBuffer.begin(command)
    V.CommandBuffer.pipeline_barrier(command,16384,140,[V.MemoryBarrier{16384,14}],[],[])
    E.transition(command,shadow,2,Bool.pick(U32,initialized,4,0),3,Bool.pick(U32,initialized,896,1),768,Bool.pick(U32,initialized,1568,0),1536)
    V.CommandBuffer.begin_render_pass(command,shadow_framebuffer,V.RenderArea{V.Offset2D{0,0},V.Extent2D{512,512}},[V.DepthClear{1.0}])
    V.CommandBuffer.bind_graphics_pipeline(command,depth_pipeline)
    V.CommandBuffer.set_viewport(command,V.Viewport{0.0,0.0,512.0,512.0,0.0,1.0})
    V.CommandBuffer.set_scissor(command,V.RenderArea{V.Offset2D{0,0},V.Extent2D{512,512}})
    V.CommandBuffer.bind_index_buffer(command,index,W.zero(),1)
    V.CommandBuffer.draw_indexed(command,V.IndexedDraw{6,1,0,V.BaseVertex{0},0})
    V.CommandBuffer.end_render_pass(command)
    E.transition(command,shadow,2,3,4,768,128,1024,32)
    E.transition(command,color,1,Bool.pick(U32,initialized,6,0),2,Bool.pick(U32,initialized,4096,1),1024,Bool.pick(U32,initialized,2048,0),256)
    E.transition(command,depth,2,Bool.pick(U32,initialized,3,0),3,Bool.pick(U32,initialized,768,1),768,Bool.pick(U32,initialized,1536,0),1536)
    V.CommandBuffer.begin_render_pass(command,framebuffer,area(),[V.ColorClear{V.ClearColor{0.0,0.0,0.0,0.0}},V.DepthClear{1.0}])
    V.CommandBuffer.bind_graphics_pipeline(command,choose_program(programs,kind))
    V.CommandBuffer.bind_descriptor_sets(command,0,Bool.pick(List<V.DescriptorSet>,U32.is_eq(kind,0),[set],[set,sampled]))
    V.CommandBuffer.set_viewport(command,V.Viewport{0.0,0.0,512.0,2.0,0.0,1.0})
    V.CommandBuffer.set_scissor(command,area())
    bind_vertices(command,kind,vertices)
    V.CommandBuffer.bind_index_buffer(command,index,W.zero(),1)
    V.CommandBuffer.draw_indexed(command,V.IndexedDraw{6,1,Bool.pick(U32,U32.is_eq(kind,2) || U32.is_eq(kind,4),6,0),V.BaseVertex{0},0})
    V.CommandBuffer.end_render_pass(command)
    E.transition(command,color,1,2,6,1024,4096,256,2048)
    V.CommandBuffer.copy_image_to_buffer(command,color,6,stage,[V.BufferImageCopy{W.zero(),0,0,V.ImageSubresourceLayers{1,0,0,1},V.Offset2D{0,0},extent()}])
    V.CommandBuffer.pipeline_barrier(command,4096,16384,[V.MemoryBarrier{4096,8192}],[],[])
    E.complete(device,command,fence)
    bytes : List<U32> <- V.Device.read_memory(device,sm,W.zero(),4096)
    E.reset(device,command,fence)
    return bytes

def read_word(word: Maybe<U32>) -> U32:
  match word:
    case None{}: 0
    case Some{w}: w
def sample_word(bytes: List<U32>) -> U32:
  read_word(List.get(&1,U32,words(bytes),256n))

def print_pixel(name: String, kind: U32, mode: U32, bytes: List<U32>) -> IO(Unit):
  IO.print("pixel " ++ name ++ " " ++ U32.show(kind) ++ " " ++ U32.show(mode) ++ " " ++ U32.show(sample_word(bytes)))

def brush_contains(brush: Maybe<&2,X.MetricSphere>, cell: X.Cell) -> Bool:
  match brush:
    case None{}: False{}
    case Some{sphere}: X.MetricSphere.contains(sphere,cell)

def preview(brush: Maybe<&2,X.MetricSphere>, cell: X.Cell) -> U32:
  match brush:
    case None{}: 16711935
    case Some{sphere}: R.Preview.tint(Some{cell},sphere,16711935)

def host_case(+c: Case) -> IO(Unit):
  Case{+name,d,anchor,u,v,w,h,id,+brush,+expected,selected,p} = c
  X.Cell{x,y,z} = expected
  +inside = brush_contains(brush,expected)
  +tint = preview(brush,expected)
  IO.print("host " ++ name ++ " " ++ U32.show(x) ++ " " ++ U32.show(y) ++ " " ++ U32.show(z) ++ " " ++ Bool.pick(String,inside,"1","0") ++ " " ++ U32.show(tint))

def modes(fuel: Nat, +m: U32, +c: Case, +palette: F.Palette, +f: Fixture) -> V.Action(Unit):
  match fuel:
    case 0n: V.Action.pure(Unit,Unit{})
    case 1n+rest:
      Case{+name,d,anchor,u,v,w,h,+id,brush,e,+selected,+production} = c
      Fixture{+device,command,fence,+frame,target,E.BoundBuffer{vb,vm},index,programs} = f
      +kind = Bool.pick(U32,production,2,1)
      do V.Action<Unit>:
        upload(f,encoded(c,palette,m))
        descriptors(device,frame)
        bytes : List<U32> <- render(f,True{},kind)
        V.Action.lift(Unit,print_pixel(name,kind,m,bytes))
        modes(rest,(m + 1 : U32),c,palette,f)

def culled(production: Bool, name: String, +f: Fixture) -> V.Action(Unit):
  match production:
    case False{}: V.Action.pure(Unit,Unit{})
    case True{}:
      do V.Action<Unit>:
        bytes : List<U32> <- render(f,True{},4)
        V.Action.lift(Unit,print_pixel(name,4,7,bytes))

def print_cells(+name: String, cells: List<&2,X.Cell>) -> IO(Unit):
  match cells:
    case Nil{}: IO.pure(Unit,Unit{})
    case Con{X.Cell{x,y,z},rest}:
      do IO<Unit>:
        IO.print("selected " ++ name ++ " " ++ U32.show(x) ++ " " ++ U32.show(y) ++ " " ++ U32.show(z))
        print_cells(name,rest)

def print_selection(name: String, cells: Maybe<&2,List<&2,X.Cell>>) -> IO(Unit):
  match cells:
    case None{}: IO.die(Unit,1,"Frozen selected cells rejected")
    case Some{xs}: print_cells(name,xs)

def case_run(+c: Case, +palette: F.Palette, +f: Fixture) -> V.Action(Unit):
  Case{+name,d,anchor,u,v,w,h,+id,brush,e,+selected,+production} = c
  Fixture{+device,command,fence,frame,target,E.BoundBuffer{vb,vm},index,programs} = f
  +first = Bool.pick(U32,U32.is_eq(id,2147483906) || selected,0,1)
  do V.Action<Unit>:
    V.Action.lift(Unit,host_case(c))
    V.Action.lift(Unit,print_selection(name,F.selected_cells(brush)))
    V.Device.write_memory(device,vm,W.zero(),E.bytes(vertices(c)))
    modes(U32.to_nat((8 - first : U32)),first,c,palette,f)
    culled(production,name,f)

def cases(rows: List<&2,Case>, +palette: F.Palette, +f: Fixture) -> V.Action(Unit):
  match rows:
    case Nil{}: V.Action.pure(Unit,Unit{})
    case Con{c,rest}:
      do V.Action<Unit>:
        case_run(c,palette,f)
        cases(rest,palette,f)

def host_sentinel(packed: Maybe<Array<U32>>) -> V.Action(Unit):
  match packed:
    case None{}: D.require(False{},"Sentinel pack rejected")
    case Some{array}: V.Action.lift(Unit,print_words("abi_host",Array.to_list(~U32,array),0))

def abi(+f: Fixture) -> V.Action(Unit):
  do V.Action<Unit>:
    host_sentinel(sentinel())
    upload(f,sentinel())
    bytes : List<U32> <- render(f,False{},0)
    V.Action.lift(Unit,print_words("abi_gpu",words(bytes),0))

def sample(+f: Fixture, id: U32) -> V.Action(Unit):
  do V.Action<Unit>:
    bytes : List<U32> <- render(f,True{},3)
    V.Action.lift(Unit,IO.print("sample " ++ U32.show(id) ++ " " ++ U32.show(sample_word(bytes))))

def run(+entry: V.Entry, rows: List<&2,Case>, palette: F.Palette) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- D.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    family : U32 <- D.choose(Core.find_queue_family(families,1),"No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    +fixture : Fixture <- create(instance,physical,device)
    abi(fixture)
    sample(fixture,0)
    cases(rows,palette,fixture)
    sample(fixture,1)

def main_with(rows: List<&2,Case>, palette: Maybe<&2,F.Palette>) -> IO(Unit):
  match palette:
    case None{}: IO.die(Unit,1,"Frozen palette rejected")
    case Some{p}:
      do IO<Unit>:
        result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry,rows,p))
        V.or_exit(Unit,result)
        live : V.VkResult(U32) <- V.debug_live_objects()
        +count : U32 <- V.or_exit(U32,live)
        IO.print("live " ++ U32.show(count))
        checked : V.VkResult(Unit) <- D.require(U32.is_zero(count),"Shader GPU fixture leaked rows")
        V.or_exit(Unit,checked)
