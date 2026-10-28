import Base
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/src/core.bend as Core
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W
import ../../voxel.bend as X
import ../../render.bend as R
import ../../atelier.bend as Atelier
import ../src/exterior.bend as Exterior
import ../src/mesh.bend as M
import ../src/renderer.bend as GPU
import ../src/viewport.bend as View
import ../src/acceptance.bend as A
import ../src/reference.bend as Ref
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D
import ../../deps/bend-vulkan/examples/indexed_offscreen.bend as E

type Loaded is Type:
  Loaded{body: X.Body, faces: List<&2,X.Face>, renderer: GPU.Renderer}

def cpu_bytes(s: M.PackedSize, vs: Array<U32>, ix: Array<U32>) -> List<&2,U32>:
  M.PackedSize{q,vc,ic,vw,iw,vb,ib,vsize,isize,vd,id} = s
  A.share(List.append(&1,U32,E.bytes(List.take(&1,U32,Array.to_list(~U32,vs),U32.to_nat(vw))),E.bytes(List.take(&1,U32,Array.to_list(~U32,ix),U32.to_nat(iw)))))

def original_arrays(+fs: List<&2,X.Face>, +s: M.PackedSize, bounds: Maybe<&2,M.Extent>, vertices: Array<U32> & Array<U32>, indices: Array<U32> & Array<U32>) -> M.Mesh & List<&2,U32>:
  (vs,copyvs) = vertices
  (ix,copyix) = indices
  (M.Mesh{fs,s,bounds,vs,ix},cpu_bytes(s,copyvs,copyix))

def original(mesh: M.Mesh) -> M.Mesh & List<&2,U32>:
  M.Mesh{fs,s,bounds,vs,ix} = mesh
  original_arrays(fs,s,bounds,Array.clone(U32,vs),Array.clone(U32,ix))

def installed(body: X.Body, expected: List<&2,U32>, pair: GPU.Renderer & M.Mesh) -> V.Action(Loaded):
  (+renderer,M.Mesh{fs,s,bounds,vs,ix}) = pair
  do V.Action<Loaded>:
    bytes : List<U32> <- GPU.geometry_bytes(renderer)
    D.require(D.bytes_equal(bytes,E.copy_words(expected)),"Actual Vulkan logical geometry bytes differ from original CPU packed arrays")
    return Loaded{body,fs,renderer}

def upload_original(renderer: GPU.Renderer, body: X.Body, pair: M.Mesh & List<&2,U32>) -> V.Action(Loaded):
  (mesh,expected) = pair
  do V.Action<Loaded>:
    result : GPU.Renderer & M.Mesh <- GPU.replace_mesh(renderer,mesh)
    installed(body,expected,result)

def built(renderer: GPU.Renderer, pair: X.Body & Result<&2,&1,Exterior.Error,M.Mesh>, +q: U32, +vb: U32, +ib: U32) -> V.Action(Loaded):
  (body,result) = pair
  match result:
    case Fail{error}: IO.pure(V.VkResult(Loaded),Fail{(1,Exterior.error_show(error))})
    case Done{M.Mesh{fs,+s,bounds,vs,ix}}:
      do V.Action<Loaded>:
        D.require(U32.is_eq(GPU.quads(s),q) && U32.is_eq(GPU.vertex_length(s),vb) && U32.is_eq(GPU.index_length(s),ib),"Pinned logical geometry counts or bytes changed")
        V.Action.lift(Unit,IO.print("Device geometry quads=" ++ U32.show(q) ++ " vertex_bytes=" ++ U32.show(vb) ++ " index_bytes=" ++ U32.show(ib)))
        upload_original(renderer,body,original(M.Mesh{fs,s,bounds,vs,ix}))

def load(renderer: GPU.Renderer, body: X.Body, q: U32, vb: U32, ib: U32) -> V.Action(Loaded):
  built(renderer,M.build(body),q,vb,ib)

def rows(expected: U32) -> V.Action(Unit):
  do V.Action<Unit>:
    actual : U32 <- V.debug_live_objects()
    D.require(U32.is_eq(actual,expected),"Geometry replacement changed resource rows")

def expect_rejected(result: V.VkResult(GPU.Geometry & M.Mesh), expected: String) -> V.Action(Unit):
  match result:
    case Done{value}: D.require(False{},"Oversized logical upload unexpectedly succeeded")
    case Fail{(code,message)}: D.require(U32.is_eq(code,1) && String.eq(message,expected),"Wrong logical upload size diagnostic")

def rejected(renderer: GPU.Renderer, vb: W.U64, ib: W.U64, expected: String) -> V.Action(Unit):
  GPU.Renderer{+instance,+physical,+device,command,fence,fb,color,depth,stage,basic,mat,dir,old,uploads} = renderer
  do IO<V.VkResult(Unit)>:
    result : V.VkResult(GPU.Geometry & M.Mesh) <- GPU.upload_mesh(instance,physical,device,old,M.Mesh{Nil{},M.PackedSize{0,0,0,0,0,vb,ib,1,1,0n,0n},None{},[0 : U32^0n],[0 : U32^0n]})
    expect_rejected(result,expected)

def rejection_checks(+renderer: GPU.Renderer, +expected_rows: U32, +expected_bytes: List<&2,U32>) -> V.Action(Unit):
  do V.Action<Unit>:
    rejected(renderer,W.U64{0,1},W.zero(),"Mesh logical vertex bytes exceed the 16 MiB single-write upload limit")
    rejected(renderer,W.zero(),W.U64{0,1},"Mesh logical index bytes exceed the 16 MiB single-write upload limit")
    rejected(renderer,W.of_u32(16777217),W.zero(),"Mesh logical vertex bytes exceed the 16 MiB single-write upload limit")
    rejected(renderer,W.zero(),W.of_u32(16777217),"Mesh logical index bytes exceed the 16 MiB single-write upload limit")
    rows(expected_rows)
    bytes : List<U32> <- GPU.geometry_bytes(renderer)
    D.require(D.bytes_equal(bytes,E.copy_words(expected_bytes)),"Rejected upload released or changed installed geometry")
    GPU.upload_sizes(M.PackedSize{0,0,0,0,0,W.of_u32(16777216),W.of_u32(16777216),1,1,0n,0n})

def camera_frames(+renderer: GPU.Renderer) -> V.Action(Unit):
  do V.Action<Unit>:
    before : List<U32> <- GPU.geometry_bytes(renderer)
    +expected : List<&2,U32> = A.share(before)
    first : List<U32> & List<U32> <- GPU.frame(renderer,R.Camera.atelier(),0)
    moved : List<U32> & List<U32> <- GPU.frame(renderer,R.Camera.look(R.Camera.atelier(),12.0,F32.neg(8.0)),0)
    after : List<U32> <- GPU.geometry_bytes(renderer)
    D.require(D.bytes_equal(after,E.copy_words(expected)),"Camera frame changed actual uploaded geometry")

def rectangle_materials() -> X.Body:
  X.Cuboids{[
    X.Cuboid{X.Cell{0,2,1},X.Cell{1,6,7},1},
    X.Cuboid{X.Cell{1,2,1},X.Cell{2,6,7},2},
    X.Cuboid{X.Cell{2,2,1},X.Cell{3,6,7},3},
    X.Cuboid{X.Cell{3,2,1},X.Cell{4,6,7},4},
    X.Cuboid{X.Cell{4,2,1},X.Cell{5,6,7},5},
    X.Cuboid{X.Cell{5,2,1},X.Cell{6,6,7},2147483648},
    X.Cuboid{X.Cell{6,2,1},X.Cell{7,6,7},2309737967},
    X.Cuboid{X.Cell{7,2,1},X.Cell{8,6,7},4294967295}]}

def rectangle_state(state: A.State) -> V.Action(Unit):
  A.State{body,+fs,+renderer} = state
  do V.Action<Unit>:
    A.diagnostic_state(A.State{body,fs,renderer})
    back : Ref.Report & List<&2,U32> <- A.frame(renderer,Nil{},R.Camera{R.Vec3{4.0,4.0,4.0},0.0,0.0},0,None{})
    V.Action.lift(Unit,IO.print("Rendered asymmetric rectangles passed all six directions, full U32 materials and inside back-face culling"))

def empty_state(state: Loaded, +expected_rows: U32) -> V.Action(Unit):
  Loaded{body,fs,+renderer} = state
  do V.Action<Unit>:
    rows((expected_rows - 4 : U32))
    bytes : List<U32> <- GPU.geometry_bytes(renderer)
    D.require(D.bytes_equal(bytes,Nil{}) && U32.is_eq(GPU.upload_count(renderer),8),"Empty mesh allocated buffers or uploaded data")
    fixture : A.State <- A.load(renderer,rectangle_materials())
    rows(expected_rows)
    rectangle_state(fixture)

def reset_state(state: Loaded, +baseline: List<&2,U32>, +expected_rows: U32) -> V.Action(Unit):
  Loaded{body,fs,+renderer} = state
  do V.Action<Unit>:
    rows(expected_rows)
    bytes : List<U32> <- GPU.geometry_bytes(renderer)
    D.require(D.bytes_equal(bytes,E.copy_words(baseline)) && U32.is_eq(GPU.upload_count(renderer),8),"Reset device bytes or upload count differs")
    empty : Loaded <- load(renderer,X.Cuboids{Nil{}},0,0,0)
    empty_state(empty,expected_rows)

def repeat_state(state: Loaded, +baseline: List<&2,U32>, carved: List<&2,U32>, +expected_rows: U32) -> V.Action(Unit):
  Loaded{body,fs,+renderer} = state
  do V.Action<Unit>:
    rows(expected_rows)
    bytes : List<U32> <- GPU.geometry_bytes(renderer)
    D.require(D.bytes_equal(bytes,E.copy_words(carved)) && U32.is_eq(GPU.upload_count(renderer),6),"Repeat device bytes or upload count differs")
    reset : Loaded <- load(renderer,Atelier.body(),10304,1648640,247296)
    reset_state(reset,baseline,expected_rows)

def carved_state(state: Loaded, +sphere: X.MetricSphere, +baseline: List<&2,U32>, +expected_rows: U32) -> V.Action(Unit):
  Loaded{body,fs,+renderer} = state
  do V.Action<Unit>:
    rows(expected_rows)
    old : List<U32> <- GPU.geometry_bytes(renderer)
    +carved : List<&2,U32> = A.share(old)
    D.require(Bool.not(D.bytes_equal(E.copy_words(carved),E.copy_words(baseline))) && U32.is_eq(GPU.upload_count(renderer),4),"Carve did not replace device geometry")
    camera_frames(renderer)
    D.require(U32.is_eq(GPU.upload_count(renderer),4),"Camera-only carved frames uploaded geometry")
    repeated : Loaded <- load(renderer,X.Body.cut(body,sphere),10359,1657440,248616)
    repeat_state(repeated,baseline,carved,expected_rows)

def cut_state(body: X.Body, renderer: GPU.Renderer, sphere: Maybe<&2,X.MetricSphere>, baseline: List<&2,U32>, expected_rows: U32) -> V.Action(Unit):
  match sphere:
    case None{}: D.require(False{},"Atelier viewport ray 226,224 missed")
    case Some{+sphere}:
      do V.Action<Unit>:
        carved : Loaded <- load(renderer,X.Body.cut(body,sphere),10359,1657440,248616)
        carved_state(carved,sphere,baseline,expected_rows)

def intact_state(state: Loaded) -> V.Action(Unit):
  Loaded{body,+fs,+renderer} = state
  do V.Action<Unit>:
    +expected_rows : U32 <- V.debug_live_objects()
    bytes : List<U32> <- GPU.geometry_bytes(renderer)
    +baseline : List<&2,U32> = A.share(bytes)
    D.require(U32.is_eq(GPU.upload_count(renderer),2),"Intact mesh did not perform exactly two uploads")
    rejection_checks(renderer,expected_rows,baseline)
    camera_frames(renderer)
    D.require(U32.is_eq(GPU.upload_count(renderer),2),"Camera-only intact frames uploaded geometry")
    cut_state(body,renderer,View.target(View.Viewport{512,512},R.Camera.atelier(),fs,226,224),baseline,expected_rows)

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
    intact : Loaded <- load(renderer,Atelier.body(),10304,1648640,247296)
    intact_state(intact)
    V.Action.lift(Unit,IO.print("Actual Vulkan Atelier logical-array bytes, state equality, resource rows and rendered rectangles passed"))

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    rows : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,rows)
    checked : V.VkResult(Unit) <- D.require(U32.is_eq(count,0),"Geometry device scope leaked")
    V.or_exit(Unit,checked)
