import Base
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/src/upload.bend as U
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W
import ../../deps/bend-vulkan/examples/indexed_offscreen.bend as E
import ../../voxel.bend as X
import ./mesh.bend as M
import ./chunks.bend as C
import ./residency.bend as Residency
import ./renderer.bend as GPU

type Copy is Data:
  Copy{source: U.Slice, destination: V.Buffer}
type Plan is Data:
  Plan{geometry: GPU.Geometry, copies: List<&2,Copy>, created: List<&2,U.Allocation>, bytes: W.U64}
type StreamReady is Data:
  StreamReady{stream: GPU.Stream, copies: List<&2,Copy>, created: List<&2,U.Allocation>}
type ChunkReady is Data:
  ChunkReady{resident: GPU.Resident, copies: List<&2,Copy>, created: List<&2,U.Allocation>}

def concat(~A: Data, xs: List<&2,A>, ys: List<&2,A>) -> List<&2,A>:
  match xs:
    case Nil{}: ys
    case x <> rest: x <> concat(~A,rest,ys)

def discard(+device: V.Device, xs: List<&2,U.Allocation>) -> V.Action(Unit):
  match xs:
    case Nil{}: V.Action.pure(Unit,Unit{})
    case allocation <> rest:
      do IO<V.VkResult(Unit)>:
        head : V.VkResult(Unit) <- U.discard(device,allocation)
        tail : V.VkResult(Unit) <- discard(device,rest)
        return V.Entry.finish(Unit,head,tail)

def allocation_buffer(a: U.Allocation) -> V.Buffer:
  U.Allocation{b,m,c} = a
  b

def bound(a: U.Allocation) -> E.BoundBuffer:
  U.Allocation{b,m,c} = a
  E.BoundBuffer{b,m}

def staged(+device: V.Device, +allocation: U.Allocation, pair: (U.Staging & Array<U32>) & V.VkResult(U.Slice)) -> IO((U.Staging & Array<U32>) & V.VkResult(U.Allocation & Copy)):
  (owner,result) = pair
  match result:
    case Done{slice}: IO.pure((U.Staging & Array<U32>) & V.VkResult(U.Allocation & Copy),(owner,Done{(allocation,Copy{slice,allocation_buffer(allocation)})}))
    case Fail{error}:
      do IO<(U.Staging & Array<U32>) & V.VkResult(U.Allocation & Copy)>:
        cleanup : V.VkResult(Unit) <- U.discard(device,allocation)
        return (owner,V.Entry.finish(U.Allocation & Copy,Fail{error},cleanup))

def allocated(+device: V.Device, staging: U.Staging, length: W.U64, words: Array<U32>, result: V.VkResult(U.Allocation)) -> IO((U.Staging & Array<U32>) & V.VkResult(U.Allocation & Copy)):
  match result:
    case Fail{error}: IO.pure((U.Staging & Array<U32>) & V.VkResult(U.Allocation & Copy),((staging,words),Fail{error}))
    case Done{+allocation}:
      do IO<(U.Staging & Array<U32>) & V.VkResult(U.Allocation & Copy)>:
        pair : (U.Staging & Array<U32>) & V.VkResult(U.Slice) <- U.stage(device,staging,W.zero(),length,words)
        staged(device,allocation,pair)

def array(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, staging: U.Staging, +length: W.U64, usage: U32, words: Array<U32>) -> IO((U.Staging & Array<U32>) & V.VkResult(U.Allocation & Copy)):
  do IO<(U.Staging & Array<U32>) & V.VkResult(U.Allocation & Copy)>:
    result : V.VkResult(U.Allocation) <- U.allocate(instance,physical,device,length,usage,0)
    allocated(device,staging,length,words,result)

def indices_ready(+device: V.Device, faces: List<&2,X.Face>, +size: M.PackedSize, bounds: Maybe<&2,M.Extent>, vertices: Array<U32>, +vertex: U.Allocation, copy: Copy, pair: (U.Staging & Array<U32>) & V.VkResult(U.Allocation & Copy)) -> IO((M.Mesh & U.Staging) & V.VkResult(StreamReady)):
  ((staging,indices),result) = pair
  match result:
    case Done{(+index,icopy)}: IO.pure((M.Mesh & U.Staging) & V.VkResult(StreamReady),((M.Mesh{faces,size,bounds,vertices,indices},staging),Done{StreamReady{GPU.Stream{bound(vertex),bound(index),GPU.index_count(size)},[copy,icopy],[vertex,index]}}))
    case Fail{error}:
      do IO<(M.Mesh & U.Staging) & V.VkResult(StreamReady)>:
        cleanup : V.VkResult(Unit) <- U.discard(device,vertex)
        return ((M.Mesh{faces,size,bounds,vertices,indices},staging),V.Entry.finish(StreamReady,Fail{error},cleanup))

def vertices_ready(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, faces: List<&2,X.Face>, +size: M.PackedSize, bounds: Maybe<&2,M.Extent>, indices: Array<U32>, pair: (U.Staging & Array<U32>) & V.VkResult(U.Allocation & Copy)) -> IO((M.Mesh & U.Staging) & V.VkResult(StreamReady)):
  ((staging,vertices),result) = pair
  match result:
    case Fail{error}: IO.pure((M.Mesh & U.Staging) & V.VkResult(StreamReady),((M.Mesh{faces,size,bounds,vertices,indices},staging),Fail{error}))
    case Done{(+allocation,copy)}:
      do IO<(M.Mesh & U.Staging) & V.VkResult(StreamReady)>:
        pair : (U.Staging & Array<U32>) & V.VkResult(U.Allocation & Copy) <- array(instance,physical,device,staging,M.word_bytes(GPU.index_count(size)),67,indices)
        indices_ready(device,faces,size,bounds,vertices,allocation,copy,pair)

def stream(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, staging: U.Staging, mesh: M.Mesh) -> IO((M.Mesh & U.Staging) & V.VkResult(StreamReady)):
  M.Mesh{faces,+size,bounds,vertices,indices} = mesh
  do IO<(M.Mesh & U.Staging) & V.VkResult(StreamReady)>:
    pair : (U.Staging & Array<U32>) & V.VkResult(U.Allocation & Copy) <- array(instance,physical,device,staging,W.of_u32(GPU.vertex_length(size)),131,vertices)
    vertices_ready(instance,physical,device,faces,size,bounds,indices,pair)

def shadow_ready(+device: V.Device, +key: C.ChunkKey, +version: U32, domains: List<&2,C.Domain>, color: M.Mesh, ready: StreamReady, pair: (M.Mesh & U.Staging) & V.VkResult(StreamReady)) -> IO((C.Chunk & U.Staging) & V.VkResult(ChunkReady)):
  StreamReady{color_stream,cc,+created} = ready
  ((shadow,staging),result) = pair
  match result:
    case Done{StreamReady{shadow_stream,sc,owned}}: IO.pure((C.Chunk & U.Staging) & V.VkResult(ChunkReady),((C.Chunk{key,version,domains,color,shadow},staging),Done{ChunkReady{GPU.Resident{key,version,color_stream,shadow_stream},concat(~Copy,cc,sc),concat(~U.Allocation,created,owned)}}))
    case Fail{error}:
      do IO<(C.Chunk & U.Staging) & V.VkResult(ChunkReady)>:
        cleanup : V.VkResult(Unit) <- discard(device,created)
        return ((C.Chunk{key,version,domains,color,shadow},staging),V.Entry.finish(ChunkReady,Fail{error},cleanup))

def color_ready(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, key: C.ChunkKey, version: U32, domains: List<&2,C.Domain>, shadow: M.Mesh, pair: (M.Mesh & U.Staging) & V.VkResult(StreamReady)) -> IO((C.Chunk & U.Staging) & V.VkResult(ChunkReady)):
  ((color,staging),result) = pair
  match result:
    case Fail{error}: IO.pure((C.Chunk & U.Staging) & V.VkResult(ChunkReady),((C.Chunk{key,version,domains,color,shadow},staging),Fail{error}))
    case Done{ready}:
      do IO<(C.Chunk & U.Staging) & V.VkResult(ChunkReady)>:
        pair : (M.Mesh & U.Staging) & V.VkResult(StreamReady) <- stream(instance,physical,device,staging,shadow)
        shadow_ready(device,key,version,domains,color,ready,pair)

def new_chunk(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, staging: U.Staging, chunk: C.Chunk) -> IO((C.Chunk & U.Staging) & V.VkResult(ChunkReady)):
  C.Chunk{key,version,domains,color,shadow} = chunk
  do IO<(C.Chunk & U.Staging) & V.VkResult(ChunkReady)>:
    pair : (M.Mesh & U.Staging) & V.VkResult(StreamReady) <- stream(instance,physical,device,staging,color)
    color_ready(instance,physical,device,key,version,domains,shadow,pair)

def reuse(same: Bool, instance: V.Instance, physical: V.PhysicalDevice, device: V.Device, staging: U.Staging, chunk: C.Chunk, resident: GPU.Resident) -> IO((C.Chunk & U.Staging) & V.VkResult(ChunkReady)):
  match same:
    case True{}: IO.pure((C.Chunk & U.Staging) & V.VkResult(ChunkReady),((chunk,staging),Done{ChunkReady{resident,Nil{},Nil{}}}))
    case False{}: new_chunk(instance,physical,device,staging,chunk)

def found(instance: V.Instance, physical: V.PhysicalDevice, device: V.Device, staging: U.Staging, chunk: C.Chunk, resident: Maybe<&2,GPU.Resident>) -> IO((C.Chunk & U.Staging) & V.VkResult(ChunkReady)):
  C.Chunk{+key,+version,domains,color,shadow} = chunk
  match resident:
    case None{}: new_chunk(instance,physical,device,staging,C.Chunk{key,version,domains,color,shadow})
    case Some{GPU.Resident{k,+v,c,s}}: reuse(U32.is_eq(version,v),instance,physical,device,staging,C.Chunk{key,version,domains,color,shadow},GPU.Resident{k,v,c,s})

def upload_chunk(instance: V.Instance, physical: V.PhysicalDevice, device: V.Device, old: List<&2,GPU.Resident>, staging: U.Staging, chunk: C.Chunk) -> IO((C.Chunk & U.Staging) & V.VkResult(ChunkReady)):
  C.Chunk{+key,version,domains,color,shadow} = chunk
  found(instance,physical,device,staging,C.Chunk{key,version,domains,color,shadow},GPU.find_resident(old,key))

def chunk_rest(head: C.Chunk, pair: (List<C.Chunk> & U.Staging) & V.VkResult(Plan)) -> (List<C.Chunk> & U.Staging) & V.VkResult(Plan):
  ((rest,staging),result) = pair
  ((head <> rest,staging),result)

def uploaded_chunk(+device: V.Device, rest: List<C.Chunk>, residents: List<&2,GPU.Resident>, copies: List<&2,Copy>, created: List<&2,U.Allocation>, pair: (C.Chunk & U.Staging) & V.VkResult(ChunkReady), next: List<C.Chunk> -> U.Staging -> List<&2,GPU.Resident> -> List<&2,Copy> -> List<&2,U.Allocation> -> IO((List<C.Chunk> & U.Staging) & V.VkResult(Plan))) -> IO((List<C.Chunk> & U.Staging) & V.VkResult(Plan)):
  ((chunk,staging),result) = pair
  match result:
    case Fail{error}:
      do IO<(List<C.Chunk> & U.Staging) & V.VkResult(Plan)>:
        cleanup : V.VkResult(Unit) <- discard(device,created)
        return ((chunk <> rest,staging),V.Entry.finish(Plan,Fail{error},cleanup))
    case Done{ChunkReady{resident,cc,owned}}:
      do IO<(List<C.Chunk> & U.Staging) & V.VkResult(Plan)>:
        result : (List<C.Chunk> & U.Staging) & V.VkResult(Plan) <- next(rest,staging,resident <> residents,concat(~Copy,copies,cc),concat(~U.Allocation,created,owned))
        return chunk_rest(chunk,result)

def upload_chunks(fuel: Nat, xs: List<C.Chunk>, +instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, +old: List<&2,GPU.Resident>, staging: U.Staging, residents: List<&2,GPU.Resident>, copies: List<&2,Copy>, created: List<&2,U.Allocation>, +runs: List<&2,C.Run>, +bytes: W.U64) -> IO((List<C.Chunk> & U.Staging) & V.VkResult(Plan)):
  match fuel xs:
    case _ Nil{}: IO.pure((List<C.Chunk> & U.Staging) & V.VkResult(Plan),((Nil{},staging),Done{Plan{GPU.Chunked{List.reverse(&2,GPU.Resident,residents),runs},copies,created,bytes}}))
    case 0n _:
      do IO<(List<C.Chunk> & U.Staging) & V.VkResult(Plan)>:
        cleanup : V.VkResult(Unit) <- discard(device,created)
        return ((xs,staging),V.Entry.finish(Plan,Fail{(1,"Chunk upload traversal exhausted")},cleanup))
    case 1n+remaining chunk <> rest:
      do IO<(List<C.Chunk> & U.Staging) & V.VkResult(Plan)>:
        pair : (C.Chunk & U.Staging) & V.VkResult(ChunkReady) <- upload_chunk(instance,physical,device,old,staging,chunk)
        uploaded_chunk(device,rest,residents,copies,created,pair,tail => storage => rs => cs => owned => upload_chunks(remaining,tail,instance,physical,device,old,storage,rs,cs,owned,runs,bytes))

def current(found: Maybe<&2,GPU.Resident>, version: U32) -> Bool:
  match found:
    case None{}: False{}
    case Some{GPU.Resident{k,v,c,s}}: U32.is_eq(v,version)

def mesh_bytes(size: M.PackedSize) -> W.U64:
  M.PackedSize{q,vc,ic,vw,iw,vb,ib,vsize,isize,vd,id} = size
  W.add(vb,ib)

def required_head(+old: List<&2,GPU.Resident>, head: C.Chunk, pair: List<C.Chunk> & W.U64) -> List<C.Chunk> & W.U64:
  C.Chunk{+key,+version,domains,M.Mesh{fs,+s,b,vs,ix},M.Mesh{sf,+ss,sb,sv,si}} = head
  (rest,bytes) = pair
  (C.Chunk{key,version,domains,M.Mesh{fs,s,b,vs,ix},M.Mesh{sf,ss,sb,sv,si}} <> rest,W.add(bytes,Bool.pick(W.U64,current(GPU.find_resident(old,key),version),W.zero(),W.add(mesh_bytes(s),mesh_bytes(ss)))))

def required(xs: List<C.Chunk>, +old: List<&2,GPU.Resident>) -> List<C.Chunk> & W.U64:
  match xs:
    case Nil{}: (Nil{},W.zero())
    case head <> rest: required_head(old,head,required(rest,old))

def installed(primitives: List<&2,C.Primitive>, faces: List<&2,X.Face>, bounds: Maybe<&2,M.Extent>, quads: U32, shadow: U32, rebuilt: U32, retained: U32, pair: (List<C.Chunk> & U.Staging) & V.VkResult(Plan)) -> (C.ChunkSet & U.Staging) & V.VkResult(Plan):
  ((chunks,staging),result) = pair
  ((C.ChunkSet{chunks,primitives,faces,bounds,quads,shadow,rebuilt,retained},staging),result)

def reserved(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, old: List<&2,GPU.Resident>, chunks: List<C.Chunk>, +primitives: List<&2,C.Primitive>, faces: List<&2,X.Face>, bounds: Maybe<&2,M.Extent>, +quads: U32, shadow: U32, rebuilt: U32, retained: U32, bytes: W.U64, pair: U.Staging & V.VkResult(Unit)) -> IO((C.ChunkSet & U.Staging) & V.VkResult(Plan)):
  (staging,result) = pair
  match result:
    case Fail{error}: IO.pure((C.ChunkSet & U.Staging) & V.VkResult(Plan),((C.ChunkSet{chunks,primitives,faces,bounds,quads,shadow,rebuilt,retained},staging),Fail{error}))
    case Done{unit}:
      do IO<(C.ChunkSet & U.Staging) & V.VkResult(Plan)>:
        pair : (List<C.Chunk> & U.Staging) & V.VkResult(Plan) <- upload_chunks(U32.to_nat(quads),chunks,instance,physical,device,old,staging,Nil{},Nil{},Nil{},C.runs(primitives),bytes)
        return installed(primitives,faces,bounds,quads,shadow,rebuilt,retained,pair)

def sized(+instance: V.Instance, +physical: V.PhysicalDevice, +device: V.Device, old: List<&2,GPU.Resident>, staging: U.Staging, primitives: List<&2,C.Primitive>, faces: List<&2,X.Face>, bounds: Maybe<&2,M.Extent>, quads: U32, shadow: U32, rebuilt: U32, retained: U32, pair: List<C.Chunk> & W.U64) -> IO((C.ChunkSet & U.Staging) & V.VkResult(Plan)):
  (chunks,+bytes) = pair
  do IO<(C.ChunkSet & U.Staging) & V.VkResult(Plan)>:
    pair : U.Staging & V.VkResult(Unit) <- U.reserve(instance,physical,device,U.reset(staging),bytes)
    reserved(instance,physical,device,old,chunks,primitives,faces,bounds,quads,shadow,rebuilt,retained,bytes,pair)

def residents(geometry: GPU.Geometry) -> List<&2,GPU.Resident>:
  match geometry:
    case GPU.Chunked{chunks,runs}: chunks
    case _: Nil{}

def prepare(instance: V.Instance, physical: V.PhysicalDevice, device: V.Device, +old: GPU.Geometry, staging: U.Staging, set: C.ChunkSet) -> IO((C.ChunkSet & U.Staging) & V.VkResult(Plan)):
  C.ChunkSet{chunks,primitives,faces,bounds,quads,shadow,rebuilt,retained} = set
  sized(instance,physical,device,residents(old),staging,primitives,faces,bounds,quads,shadow,rebuilt,retained,required(chunks,residents(old)))

def record_copies(+command: V.CommandBuffer, copies: List<&2,Copy>) -> V.Action(Unit):
  match copies:
    case Nil{}: V.Action.pure(Unit,Unit{})
    case Copy{U.Slice{source,offset,length},destination} <> rest:
      do V.Action<Unit>:
        V.CommandBuffer.copy_buffer(command,source,destination,[V.BufferCopy{offset,W.zero(),length}])
        record_copies(command,rest)

def record(+command: V.CommandBuffer, plan: Plan) -> V.Action(Unit):
  Plan{geometry,copies,created,bytes} = plan
  do V.Action<Unit>:
    V.CommandBuffer.pipeline_barrier(command,16384,4096,[V.MemoryBarrier{16384,2048}],[],[])
    record_copies(command,copies)


def resident_version(resident: GPU.Resident) -> Residency.Version:
  GPU.Resident{key,version,color,shadow} = resident
  Residency.Version{key,version}

def resident_versions(xs: List<&2,GPU.Resident>) -> List<&2,Residency.Version>:
  match xs:
    case Nil{}: Nil{}
    case first <> rest: resident_version(first) <> resident_versions(rest)

def retirement_pairs(old: GPU.Geometry, next: GPU.Geometry) -> List<(V.Buffer & V.DeviceMemory)>:
  match old:
    case GPU.Chunked{chunks,runs}: GPU.chunk_pairs(Residency.obsolete(~GPU.Resident,~(resident => resident_version(resident)),chunks,resident_versions(residents(next))))
    case _: GPU.geometry_pairs(old)

def commit(device: V.Device, old: GPU.Geometry, next: GPU.Geometry) -> V.Action(Unit):
  V.Device.retire_buffers(device,retirement_pairs(old,next))

def abort(device: V.Device, plan: Plan) -> V.Action(Unit):
  Plan{geometry,copies,created,bytes} = plan
  discard(device,created)

def allocation_pairs(xs: List<&2,U.Allocation>) -> List<(V.Buffer & V.DeviceMemory)>:
  match xs:
    case Nil{}: Nil{}
    case U.Allocation{buffer,memory,capacity} <> rest: (buffer,memory) <> allocation_pairs(rest)

def retire_plan(+device: V.Device, plan: Plan) -> V.Action(Unit):
  Plan{geometry,copies,created,bytes} = plan
  do IO<V.VkResult(Unit)>:
    retired : V.VkResult(Unit) <- V.Device.retire_buffers(device,allocation_pairs(created))
    collected : V.VkResult(Unit) <- V.Device.collect_retired(device)
    return V.Entry.finish(Unit,retired,collected)
