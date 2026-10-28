import Base
import ./chunks.bend as C
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/src/core.bend as Core
import ../../deps/bend-vulkan/src/upload.bend as Upload
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W
import ../../render.bend as R
import ../../voxel.bend as X
import ../shaders/spirv.bend as S
import ../../deps/bend-vulkan/examples/indexed_offscreen.bend as E
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D
import ../../deps/bend-vulkan/examples/offscreen_roundtrip.bend as Memory
import ./mesh.bend as M

type Stream is Data:
  Stream{vertices: E.BoundBuffer, indices: E.BoundBuffer, count: U32}
type Resident is Data:
  Resident{key: C.ChunkKey, version: U32, color: Stream, shadow: Stream}
type Geometry is Data:
  Empty{}
  Chunked{chunks: List<&2,Resident>, runs: List<&2,C.Run>}
  Geometry{vertices: E.BoundBuffer, indices: E.BoundBuffer, count: U32}
type Renderer is Data:
  Renderer{instance: V.Instance, physical: V.PhysicalDevice, device: V.Device, command: V.CommandBuffer, fence: V.Fence, framebuffer: V.Framebuffer, color: E.Attachment, depth: E.Attachment, stage: E.BoundBuffer, basic: V.GraphicsPipeline, material: V.GraphicsPipeline, direction: V.GraphicsPipeline, geometry: Geometry, uploads: U32}

def area() -> V.RenderArea:
  V.RenderArea{V.Offset2D{0,0},V.Extent2D{512,512}}

def attachment(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, +format: U32, +aspect: U32, usage: U32) -> V.Action(E.Attachment):
  do V.Action<E.Attachment>:
    +image : V.ImageHandle <- V.Device.create_image(device,V.ImageCreateInfo{format,V.Extent2D{512,512},1,1,usage})
    requirements : V.MemoryRequirements <- V.Device.get_image_memory_requirements(device,image)
    +memory : V.DeviceMemory <- Memory.allocate(instance,physical,device,requirements,0)
    V.Device.bind_image_memory(device,image,memory,W.zero())
    view : V.ImageView <- V.Device.create_image_view(device,V.ImageViewCreateInfo{image,1,V.ImageSubresourceRange{aspect,0,1,0,1}})
    return E.Attachment{image,memory,view}

def pipeline_finished(+device: V.Device, fragment: V.ShaderModule, result: V.VkResult(V.GraphicsPipeline)) -> V.Action(V.GraphicsPipeline):
  do V.Action<V.GraphicsPipeline>:
    V.Device.destroy_shader_module(device,fragment)
    IO.pure(V.VkResult(V.GraphicsPipeline),result)

def pipeline(+device: V.Device, layout: V.PipelineLayout, pass: V.RenderPass, vertex: V.ShaderModule, words: List<U32>) -> V.Action(V.GraphicsPipeline):
  do V.Action<V.GraphicsPipeline>:
    +fragment : V.ShaderModule <- V.Device.create_shader_module(device,words)
    result : V.VkResult(V.GraphicsPipeline) <- V.Action.lift(V.VkResult(V.GraphicsPipeline),V.Device.create_graphics_pipeline(device,V.GraphicsPipelineCreateInfo{layout,pass,vertex,fragment,[V.VertexInputBinding{0,40,0}],[V.VertexInputAttribute{0,0,106,0},V.VertexInputAttribute{1,0,37,12},V.VertexInputAttribute{2,0,37,16}],3,V.RasterState{2,0},Some{V.DepthState{True{},True{},1}},15}))
    pipeline_finished(device,fragment,result)

def framebuffer(device: V.Device, pass: V.RenderPass, color: E.Attachment, depth: E.Attachment) -> V.Action(V.Framebuffer):
  E.Attachment{ci,cm,cv} = color
  E.Attachment{di,dm,dv} = depth
  V.Device.create_framebuffer(device,V.FramebufferCreateInfo{pass,[cv,dv],V.Extent2D{512,512}})

def create(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device) -> V.Action(Renderer):
  do V.Action<Renderer>:
    +color : E.Attachment <- attachment(instance,physical,device,37,1,17)
    +depth : E.Attachment <- attachment(instance,physical,device,126,2,33)
    stage : E.BoundBuffer <- E.buffer(instance,physical,device,2097152,2)
    +vertex : V.ShaderModule <- V.Device.create_shader_module(device,S.voxel_vertex_words())
    +layout : V.PipelineLayout <- V.Device.create_pipeline_layout(device,V.PipelineLayoutCreateInfo{[],Some{V.PushConstantRange{1,64}}})
    +pass : V.RenderPass <- V.Device.create_render_pass(device,V.RenderPassCreateInfo{[V.AttachmentInfo{37,1,0}],Some{V.AttachmentInfo{126,1,0}}})
    basic : V.GraphicsPipeline <- pipeline(device,layout,pass,vertex,S.voxel_fragment_words())
    material : V.GraphicsPipeline <- pipeline(device,layout,pass,vertex,S.voxel_material_words())
    direction : V.GraphicsPipeline <- pipeline(device,layout,pass,vertex,S.voxel_direction_words())
    V.Device.destroy_shader_module(device,vertex)
    fb : V.Framebuffer <- framebuffer(device,pass,color,depth)
    +pool : V.CommandPool <- V.Device.create_command_pool(device)
    command : V.CommandBuffer <- V.Device.allocate_command_buffer(device,pool)
    fence : V.Fence <- V.Device.create_fence(device,False{})
    return Renderer{instance,physical,device,command,fence,fb,color,depth,stage,basic,material,direction,Empty{},0}

def prepare(renderer: Renderer) -> V.Action(Unit):
  Renderer{instance,physical,+device,+command,+fence,fb,E.Attachment{color,cm,cv},E.Attachment{depth,dm,dv},stage,basic,mat,dir,geometry,uploads} = renderer
  do V.Action<Unit>:
    V.CommandBuffer.begin(command)
    E.transition(command,color,1,0,6,1,4096,0,2048)
    E.transition(command,depth,2,0,6,1,4096,0,2048)
    E.complete(device,command,fence)
    E.reset(device,command,fence)

def bound_pair(buffer: E.BoundBuffer) -> V.Buffer & V.DeviceMemory:
  E.BoundBuffer{b,m} = buffer
  (b,m)

def append_pairs(xs: List<(V.Buffer & V.DeviceMemory)>, ys: List<(V.Buffer & V.DeviceMemory)>) -> List<(V.Buffer & V.DeviceMemory)>:
  match xs:
    case Nil{}: ys
    case x <> rest: x <> append_pairs(rest,ys)

def stream_pairs(stream: Stream) -> List<(V.Buffer & V.DeviceMemory)>:
  Stream{vs,ix,count} = stream
  [bound_pair(vs),bound_pair(ix)]

def resident_pairs(resident: Resident) -> List<(V.Buffer & V.DeviceMemory)>:
  Resident{key,version,color,shadow} = resident
  append_pairs(stream_pairs(color),stream_pairs(shadow))

def chunk_pairs(chunks: List<&2,Resident>) -> List<(V.Buffer & V.DeviceMemory)>:
  match chunks:
    case Nil{}: Nil{}
    case resident <> rest: append_pairs(resident_pairs(resident),chunk_pairs(rest))

def geometry_pairs(geometry: Geometry) -> List<(V.Buffer & V.DeviceMemory)>:
  match geometry:
    case Empty{}: Nil{}
    case Chunked{chunks,runs}: chunk_pairs(chunks)
    case Geometry{vs,ix,count}: [bound_pair(vs),bound_pair(ix)]

def release_buffer(device: V.Device, buffer: E.BoundBuffer) -> V.Action(Unit):
  V.Device.retire_buffers(device,[bound_pair(buffer)])

def release(device: V.Device, geometry: Geometry) -> V.Action(Unit):
  V.Device.retire_buffers(device,geometry_pairs(geometry))

def discard_buffers(+device: V.Device, xs: List<(V.Buffer & V.DeviceMemory)>) -> V.Action(Unit):
  match xs:
    case Nil{}: V.Action.pure(Unit,Unit{})
    case (buffer,memory) <> rest:
      do IO<V.VkResult(Unit)>:
        head : V.VkResult(Unit) <- Upload.discard(device,Upload.Allocation{buffer,memory,W.zero()})
        tail : V.VkResult(Unit) <- discard_buffers(device,rest)
        return V.Entry.finish(Unit,head,tail)

def upload_rejected(device: V.Device, candidates: List<(V.Buffer & V.DeviceMemory)>, error: U32 & String) -> V.Action(Geometry & M.Mesh):
  do IO<V.VkResult(Geometry & M.Mesh)>:
    cleanup : V.VkResult(Unit) <- discard_buffers(device,candidates)
    return V.Entry.finish(Geometry & M.Mesh,Fail{error},cleanup)

def upload_published(device: V.Device, candidate: Geometry, mesh: M.Mesh, result: V.VkResult(Unit)) -> V.Action(Geometry & M.Mesh):
  match result:
    case Fail{error}: upload_rejected(device,geometry_pairs(candidate),error)
    case Done{unit}: V.Action.pure(Geometry & M.Mesh,(candidate,mesh))

def upload_checked(pair: Array<U32> & V.VkResult(Unit)) -> V.Action(Array<U32>):
  (words,result) = pair
  do V.Action<Array<U32>>:
    IO.pure(V.VkResult(Unit),result)
    return words

def upload(+device: V.Device, buffer: E.BoundBuffer, length: U32, words: Array<U32>) -> V.Action(Array<U32>):
  E.BoundBuffer{b,m} = buffer
  do V.Action<Array<U32>>:
    pair : Array<U32> & V.VkResult(Unit) <- V.Action.lift(Array<U32> & V.VkResult(Unit),V.Device.write_memory_words(device,m,W.zero(),W.zero(),W.of_u32(length),words))
    upload_checked(pair)

def upload_sizes(size: M.PackedSize) -> V.Action(Unit):
  M.PackedSize{q,vc,ic,vw,iw,+vb,+ib,vs,iscap,vd,id} = size
  do V.Action<Unit>:
    D.require(Bool.not(Core.size_less(W.of_u32(16777216),vb)),"Mesh logical vertex bytes exceed the 16 MiB single-write upload limit")
    D.require(Bool.not(Core.size_less(W.of_u32(16777216),ib)),"Mesh logical index bytes exceed the 16 MiB single-write upload limit")

def quads(s: M.PackedSize) -> U32:
  M.PackedSize{q,vc,ic,vw,iw,vb,ib,vsize,isize,vd,id} = s
  q

def index_count(s: M.PackedSize) -> U32:
  M.PackedSize{q,vc,ic,vw,iw,vb,ib,vsize,isize,vd,id} = s
  ic

def vertex_length(s: M.PackedSize) -> U32:
  M.PackedSize{q,vc,ic,vw,iw,W.U64{vb,hi},ib,vsize,isize,vd,id} = s
  vb

def index_length(s: M.PackedSize) -> U32:
  M.PackedSize{q,vc,ic,vw,iw,vb,W.U64{ib,hi},vsize,isize,vd,id} = s
  ib

def bound_buffer(allocation: Upload.Allocation) -> E.BoundBuffer:
  Upload.Allocation{buffer,memory,capacity} = allocation
  E.BoundBuffer{buffer,memory}

def uploaded_indices(+device: V.Device, old: Geometry, +vbuffer: E.BoundBuffer, +ibuffer: E.BoundBuffer, +ic: U32, fs: List<&2, X.Face>, s: M.PackedSize, bounds: Maybe<&2,M.Extent>, vertices: Array<U32>, pair: Array<U32> & V.VkResult(Unit)) -> V.Action(Geometry & M.Mesh):
  (indices,result) = pair
  match result:
    case Fail{error}: upload_rejected(device,[bound_pair(vbuffer),bound_pair(ibuffer)],error)
    case Done{unit}:
      do V.Action<Geometry & M.Mesh>:
        retired : V.VkResult(Unit) <- V.Action.lift(V.VkResult(Unit),release(device,old))
        upload_published(device,Geometry{vbuffer,ibuffer,ic},M.Mesh{fs,s,bounds,vertices,indices},retired)

def uploaded_vertices(+device: V.Device, old: Geometry, +vbuffer: E.BoundBuffer, +ibuffer: E.BoundBuffer, +s: M.PackedSize, bounds: Maybe<&2,M.Extent>, fs: List<&2,X.Face>, indices: Array<U32>, pair: Array<U32> & V.VkResult(Unit)) -> V.Action(Geometry & M.Mesh):
  E.BoundBuffer{ib,+im} = ibuffer
  (vertices,result) = pair
  match result:
    case Fail{error}: upload_rejected(device,[bound_pair(vbuffer),bound_pair(ibuffer)],error)
    case Done{unit}:
      do V.Action<Geometry & M.Mesh>:
        pair : Array<U32> & V.VkResult(Unit) <- V.Action.lift(Array<U32> & V.VkResult(Unit),V.Device.write_memory_words(device,im,W.zero(),W.zero(),W.of_u32(index_length(s)),indices))
        uploaded_indices(device,old,vbuffer,ibuffer,index_count(s),fs,s,bounds,vertices,pair)

def index_buffer_ready(+device: V.Device, old: Geometry, +vbuffer: E.BoundBuffer, mesh: M.Mesh, result: V.VkResult(Upload.Allocation)) -> V.Action(Geometry & M.Mesh):
  E.BoundBuffer{vb,+vm} = vbuffer
  match mesh result:
    case _ Fail{error}: upload_rejected(device,[bound_pair(vbuffer)],error)
    case M.Mesh{fs,+s,bounds,vs,ix} Done{allocation}:
      do V.Action<Geometry & M.Mesh>:
        pair : Array<U32> & V.VkResult(Unit) <- V.Action.lift(Array<U32> & V.VkResult(Unit),V.Device.write_memory_words(device,vm,W.zero(),W.zero(),W.of_u32(vertex_length(s)),vs))
        uploaded_vertices(device,old,vbuffer,bound_buffer(allocation),s,bounds,fs,ix,pair)

def upload_nonempty(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, old: Geometry, mesh: M.Mesh, empty: Bool) -> V.Action(Geometry & M.Mesh):
  match mesh empty:
    case M.Mesh{fs,s,bounds,vs,ix} True{}:
      do V.Action<Geometry & M.Mesh>:
        release(device,old)
        return (Empty{},M.Mesh{fs,s,bounds,vs,ix})
    case M.Mesh{fs,+s,bounds,vs,ix} False{}:
      do V.Action<Geometry & M.Mesh>:
        vbuffer : Upload.Allocation <- Upload.allocate(instance,physical,device,W.of_u32(vertex_length(s)),128,2)
        result : V.VkResult(Upload.Allocation) <- V.Action.lift(V.VkResult(Upload.Allocation),Upload.allocate(instance,physical,device,W.of_u32(index_length(s)),64,2))
        index_buffer_ready(device,old,bound_buffer(vbuffer),M.Mesh{fs,s,bounds,vs,ix},result)

def upload_mesh(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, old: Geometry, mesh: M.Mesh) -> V.Action(Geometry & M.Mesh):
  M.Mesh{fs,+s,bounds,vs,ix} = mesh
  do V.Action<Geometry & M.Mesh>:
    V.Device.collect_retired(device)
    upload_sizes(s)
    upload_nonempty(instance,physical,device,old,M.Mesh{fs,s,bounds,vs,ix},U32.is_zero(quads(s)))

def mesh_replaced(renderer: Renderer, result: Geometry & M.Mesh) -> Renderer & M.Mesh:
  Renderer{instance,physical,device,command,fence,fb,color,depth,stage,basic,mat,dir,old,uploads} = renderer
  (geometry,M.Mesh{fs,+s,bounds,vs,ix}) = result
  M.PackedSize{count,vc,ic,vw,iw,vb,ib,vsize,isize,vd,id} = s
  (Renderer{instance,physical,device,command,fence,fb,color,depth,stage,basic,mat,dir,geometry,(uploads + Bool.pick(U32,U32.is_zero(count),0,2) : U32)},M.Mesh{fs,s,bounds,vs,ix})

def replace_mesh(+renderer: Renderer, mesh: M.Mesh) -> V.Action(Renderer & M.Mesh):
  Renderer{+instance,+physical,+device,command,fence,fb,color,depth,stage,basic,mat,dir,old,uploads} = renderer
  do V.Action<Renderer & M.Mesh>:
    result : Geometry & M.Mesh <- upload_mesh(instance,physical,device,old,mesh)
    return mesh_replaced(renderer,result)

def matrix_extent(basis: R.Basis, width: U32, height: U32) -> List<U32>:
  R.Basis{+eye,R.Vec3{+rx,+ry,+rz},R.Vec3{+ux,+uy,+uz},R.Vec3{+fx,+fy,+fz},focal,near} = basis
  +scale = (focal / 256.0 : F32)
  +horizontal = (scale * U32.to_f32(height) / U32.to_f32(width) : F32)
  +tx = F32.neg(R.Vec3.dot(eye,R.Vec3{rx,ry,rz}))
  +ty = F32.neg(R.Vec3.dot(eye,R.Vec3{ux,uy,uz}))
  +tz = F32.neg(R.Vec3.dot(eye,R.Vec3{fx,fy,fz}))
  [F32.bits((horizontal * rx : F32)),F32.bits(F32.neg((scale * ux : F32))),F32.bits(fx),F32.bits(fx),
   F32.bits((horizontal * ry : F32)),F32.bits(F32.neg((scale * uy : F32))),F32.bits(fy),F32.bits(fy),
   F32.bits((horizontal * rz : F32)),F32.bits(F32.neg((scale * uz : F32))),F32.bits(fz),F32.bits(fz),
   F32.bits((horizontal * tx : F32)),F32.bits(F32.neg((scale * ty : F32))),F32.bits((tz - near : F32)),F32.bits(tz)]

def matrix(basis: R.Basis) -> List<U32>:
  matrix_extent(basis,512,512)

def find_resident(xs: List<&2,Resident>, +key: C.ChunkKey) -> Maybe<&2,Resident>:
  match xs:
    case Nil{}: None{}
    case +head <> rest:
      Resident{own,v,c,s} = head
      Bool.pick(Maybe<&2,Resident>,C.key_equal(own,key),Some{head},find_resident(rest,key))

def draw_stream(+command: V.CommandBuffer, stream: Stream, first: U32, count: U32) -> V.Action(Unit):
  Stream{E.BoundBuffer{vb,vm},E.BoundBuffer{ib,im},total} = stream
  do V.Action<Unit>:
    V.CommandBuffer.bind_vertex_buffer(command,0,vb,W.zero())
    V.CommandBuffer.bind_index_buffer(command,ib,W.zero(),1)
    V.CommandBuffer.draw_indexed(command,V.IndexedDraw{count,1,first,V.BaseVertex{0},0})

def draw_run(command: V.CommandBuffer, run: C.Run, resident: Maybe<&2,Resident>) -> V.Action(Unit):
  C.Run{key,first,count} = run
  match resident:
    case None{}: D.require(False{},"Canonical draw run has no chunk generation")
    case Some{Resident{k,v,color,shadow}}: draw_stream(command,color,(first * 6 : U32),(count * 6 : U32))

def draw_runs(+command: V.CommandBuffer, +chunks: List<&2,Resident>, runs: List<&2,C.Run>) -> V.Action(Unit):
  match runs:
    case Nil{}: V.Action.pure(Unit,Unit{})
    case +run <> rest:
      C.Run{key,first,count} = run
      do V.Action<Unit>:
        draw_run(command,run,find_resident(chunks,key))
        draw_runs(command,chunks,rest)

def shadow_chunks(+command: V.CommandBuffer, xs: List<&2,Resident>) -> V.Action(Unit):
  match xs:
    case Nil{}: V.Action.pure(Unit,Unit{})
    case Resident{k,v,c,+shadow} <> rest:
      Stream{vs,ix,count} = shadow
      do V.Action<Unit>:
        draw_stream(command,shadow,0,count)
        shadow_chunks(command,rest)

def draw(+command: V.CommandBuffer, geometry: Geometry) -> V.Action(Unit):
  match geometry:
    case Empty{}: V.Action.pure(Unit,Unit{})
    case Chunked{chunks,runs}: draw_runs(command,chunks,runs)
    case Geometry{E.BoundBuffer{vb,vm},E.BoundBuffer{ib,im},count}:
      do V.Action<Unit>:
        V.CommandBuffer.bind_vertex_buffer(command,0,vb,W.zero())
        V.CommandBuffer.bind_index_buffer(command,ib,W.zero(),1)
        V.CommandBuffer.draw_indexed(command,V.IndexedDraw{count,1,0,V.BaseVertex{0},0})

def draw_shadow(command: V.CommandBuffer, geometry: Geometry) -> V.Action(Unit):
  match geometry:
    case Chunked{chunks,runs}: shadow_chunks(command,chunks)
    case _: draw(command,geometry)

def publish(+command: V.CommandBuffer, geometry: Geometry) -> V.Action(Unit):
  match geometry:
    case Empty{}: V.Action.pure(Unit,Unit{})
    case Chunked{chunks,runs}: V.CommandBuffer.pipeline_barrier(command,20480,4,[V.MemoryBarrier{20480,6}],[],[])
    case Geometry{E.BoundBuffer{vb,vm},E.BoundBuffer{ib,im},count}:
      V.CommandBuffer.pipeline_barrier(command,16384,4,[],[V.BufferMemoryBarrier{vb,W.zero(),Core.whole_size(),16384,4},V.BufferMemoryBarrier{ib,W.zero(),Core.whole_size(),16384,2}],[])

def frame(renderer: Renderer, camera: R.Camera, +mode: U32) -> V.Action(List<U32> & List<U32>):
  Renderer{instance,physical,+device,+command,+fence,fb,E.Attachment{+color,cm,cv},E.Attachment{+depth,dm,dv},E.BoundBuffer{+stage,+memory},basic,mat,dir,+geometry,uploads} = renderer
  do V.Action<List<U32> & List<U32>>:
    V.Device.collect_retired(device)
    V.CommandBuffer.begin(command)
    publish(command,geometry)
    E.transition(command,color,1,6,2,4096,1024,2048,256)
    E.transition(command,depth,2,6,3,4096,768,2048,1536)
    V.CommandBuffer.begin_render_pass(command,fb,area(),[V.ColorClear{V.ClearColor{0.0,0.0,0.0,1.0}},V.DepthClear{1.0}])
    V.CommandBuffer.bind_graphics_pipeline(command,Bool.pick(V.GraphicsPipeline,U32.is_eq(mode,0),basic,Bool.pick(V.GraphicsPipeline,U32.is_eq(mode,1),mat,dir)))
    V.CommandBuffer.set_viewport(command,V.Viewport{0.0,0.0,512.0,512.0,0.0,1.0})
    V.CommandBuffer.set_scissor(command,area())
    V.CommandBuffer.push_constants(command,matrix(R.Camera.basis(camera)))
    draw(command,geometry)
    V.CommandBuffer.end_render_pass(command)
    E.transition(command,color,1,2,6,1024,4096,256,2048)
    E.transition(command,depth,2,3,6,768,4096,1024,2048)
    V.CommandBuffer.copy_image_to_buffer(command,color,6,stage,[V.BufferImageCopy{W.zero(),0,0,V.ImageSubresourceLayers{1,0,0,1},V.Offset2D{0,0},V.Extent2D{512,512}}])
    V.CommandBuffer.copy_image_to_buffer(command,depth,6,stage,[V.BufferImageCopy{W.of_u32(1048576),0,0,V.ImageSubresourceLayers{2,0,0,1},V.Offset2D{0,0},V.Extent2D{512,512}}])
    V.CommandBuffer.pipeline_barrier(command,4096,16384,[V.MemoryBarrier{4096,8192}],[],[])
    E.complete(device,command,fence)
    colors : List<U32> <- V.Device.read_memory(device,memory,W.zero(),1048576)
    depths : List<U32> <- V.Device.read_memory(device,memory,W.of_u32(1048576),1048576)
    E.reset(device,command,fence)
    return (colors,depths)

def upload_count(renderer: Renderer) -> U32:
  Renderer{instance,physical,device,command,fence,fb,color,depth,stage,basic,mat,dir,geometry,uploads} = renderer
  uploads

def geometry_bytes_read(+device: V.Device, geometry: Geometry) -> V.Action(List<U32>):
  match geometry:
    case Empty{}: V.Action.pure(List<U32>,Nil{})
    case Chunked{chunks,runs}: IO.pure(V.VkResult(List<U32>),Fail{(1,"Chunked device bytes require a transfer readback")})
    case Geometry{E.BoundBuffer{vb,vm},E.BoundBuffer{ib,im},+count}:
      do V.Action<List<U32>>:
        vs : List<U32> <- V.Device.read_memory(device,vm,W.zero(),(count / 6 * 160 : U32))
        ix : List<U32> <- V.Device.read_memory(device,im,W.zero(),(count * 4 : U32))
        return List.append(&1,U32,vs,ix)

def geometry_bytes(+renderer: Renderer) -> V.Action(List<U32>):
  Renderer{instance,physical,+device,command,fence,fb,color,depth,stage,basic,mat,dir,geometry,uploads} = renderer
  do V.Action<List<U32>>:
    V.Device.collect_retired(device)
    geometry_bytes_read(device,geometry)
