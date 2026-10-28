import Base
import ../src/chunks.bend as C
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/src/core.bend as Core
import ../shaders/spirv.bend as S
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W
import ../../atelier.bend as Atelier
import ../../render.bend as R
import ../../voxel.bend as X
import ../../dump.bend as Dump
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D
import ../src/renderer.bend as GPU
import ../src/mesh.bend as M
import ../src/scene.bend as Scene
import ../src/appearance.bend as A
import ../src/production.bend as P
import ../src/viewport.bend as View
import ./geometry_dump.bend as Source
import ../src/exterior.bend as Exterior

type Context is Data:
  Context{instance: V.Instance, physical: V.PhysicalDevice, device: V.Device, commands: P.Commands}

def persistent(bytes: List<U32>) -> List<&2,U32>:
  match bytes:
    case Nil{}: Nil{}
    case b <> rest: b <> persistent(rest)

def save(path: String, bytes: List<U32>) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File,File.open(path,"w"))
    result : File & Result<&1,&1,U32 & String,Unit> <- File.write_bytes(file,persistent(bytes))
    file : File <- Dump.Dump.written(result)
    File.close(file)

def text(path: String, value: String) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File,File.open(path,"w"))
    result : File & Result<&1,&1,U32 & String,Unit> <- File.write(file,value)
    file : File <- Dump.Dump.written(result)
    File.close(file)

def save_readback(+name: String, full: Bool, read: P.Readback) -> IO(Unit):
  match full read:
    case False{} P.Readback{color,depth,shadow,uniform}: save(name ++ ".rgba",color)
    case True{} P.Readback{color,depth,shadow,uniform}:
      do IO<Unit>:
        save(name ++ ".rgba",color)
        save(name ++ ".depth",depth)
        save(name ++ ".shadow",shadow)
        save(name ++ ".uniform",uniform)

def built(pair: X.Body & Result<&2,&1,Exterior.Error,C.ChunkSet>) -> V.Action(X.Body & C.ChunkSet):
  (body,result) = pair
  match result:
    case Fail{e}: IO.pure(V.VkResult(X.Body & C.ChunkSet),Fail{(1,"Production fixture mesh rejected")})
    case Done{mesh}: V.Action.pure(X.Body & C.ChunkSet,(body,mesh))

def extent(bounds: Maybe<&2,M.Extent>) -> U32:
  match bounds:
    case None{}: 0
    case Some{M.Extent{low,X.Cell{x,y,z}}}: U32.max(x,U32.max(y,z))

def image(+context: Context, +target: P.Target, +scene: Scene.Group, +input: A.FrameInput, +name: String, +preview: Bool, full: Bool) -> V.Action(Unit):
  Context{instance,physical,+device,commands} = context
  do V.Action<Unit>:
    result : P.Readback <- P.render(device,commands,target,scene,input,preview)
    V.Action.lift(Unit,save_readback("build/milestone-6-production/" ++ name,full,result))

def mode(m: U32) -> A.Mode:
  match m:
    case 2: A.Material{}
    case 3: A.Direction{}
    case 4: A.CellX{}
    case 5: A.CellY{}
    case 6: A.CellZ{}
    case _: A.Selected{}

def modes(fuel: Nat, +m: U32, +context: Context, +target: P.Target, +scene: Scene.Group, input: A.FrameInput, +name: String) -> V.Action(Unit):
  match fuel:
    case 0n: V.Action.pure(Unit,Unit{})
    case 1n+rest:
      A.FrameInput{+basis,+w,+h,+extent,+palette,+brush,+output,old} = input
      do V.Action<Unit>:
        image(context,target,scene,A.FrameInput{basis,w,h,extent,palette,brush,output,mode(m)},name ++ "-mode" ++ U32.show(m),False{},U32.is_eq(m,2))
        modes(rest,U32.inc(m),context,target,scene,A.FrameInput{basis,w,h,extent,palette,brush,output,A.Shaded{}},name)

def body_saved(+name: String, +revision: U32, pair: X.Body & String) -> V.Action(X.Body & C.ChunkSet):
  (body,json) = pair
  do V.Action<X.Body & C.ChunkSet>:
    V.Action.lift(Unit,text("build/milestone-6-production/" ++ name ++ ".body.json",json))
    built(C.build(body,revision))

def attachment_output(+format: U32) -> A.Output:
  Bool.pick(A.Output,U32.is_eq(format,43) || U32.is_eq(format,50),A.Srgb{},A.Unorm{})

def selected_id(input: A.FrameInput) -> A.FrameInput:
  A.FrameInput{b,w,h,e,p,s,o,m} = input
  A.FrameInput{b,w,h,e,p,s,o,A.Selected{}}

def trace_mode(m: U32) -> A.Mode:
  match m:
    case 0: A.Shaded{}
    case 1: A.Basic{}
    case _: mode(m)

def trace_frames(fuel: Nat, +m: U32, +context: Context, +target: P.Target, +scene: Scene.Group, input: A.FrameInput, +prefix: String) -> V.Action(Unit):
  match fuel:
    case 0n: V.Action.pure(Unit,Unit{})
    case 1n+rest:
      A.FrameInput{+b,+w,+h,+e,+p,+s,+o,old} = input
      do V.Action<Unit>:
        image(context,target,scene,A.FrameInput{b,w,h,e,p,s,o,trace_mode(m)},prefix ++ U32.show(m),False{},False{})
        trace_frames(rest,U32.inc(m),context,target,scene,A.FrameInput{b,w,h,e,p,s,o,A.Shaded{}},prefix)

def trace_target(p: P.Target, metadata: V.GraphicsPipeline) -> P.Target:
  P.Target{color,depth,pass,fb,stage,Scene.Programs{world,background,rings},w,h,f} = p
  P.Target{color,depth,pass,fb,stage,Scene.Programs{metadata,background,rings},w,h,f}

def trace_layout(a: Scene.Assets) -> V.PipelineLayout:
  Scene.Assets{u,s,ss,p,f,sd,sampler,shadow,sp,sf,ps,fl,ml,ix,palette} = a
  ml

def trace(+name: String, +context: Context, +target: P.Target, +scene: Scene.Group, input: A.FrameInput) -> V.Action(Unit):
  Context{instance,physical,+device,commands} = context
  P.Target{c,d,+pass,fb,stage,programs,w,h,f} = target
  do V.Action<Unit>:
    +metadata : V.GraphicsPipeline <- Scene.pipeline(device,trace_layout(Scene.assets(scene)),pass,S.appearance_world_vert_words(),S.fixture_world_metadata_words(),1,Some{V.DepthState{True{},True{},1}})
    trace_frames(8n,0,context,trace_target(target,metadata),scene,input,name ++ "-metadata-")
    V.Device.destroy_graphics_pipeline(device,metadata)

def installed_scene(+context: Context, +target: P.Target, +name: String, +camera: R.Camera, +brush: Maybe<&2,X.MetricSphere>, body: X.Body, installed: Scene.Group & C.ChunkSet) -> V.Action(Scene.Group & X.Body):
  P.Target{color,depth,pass,fb,stage,programs,+w,+h,+format} = target
  (+scene,C.ChunkSet{cs,primitives,faces,+bounds,q,sq,rebuilt,retained}) = installed
  +input : A.FrameInput = A.FrameInput{R.Camera.basis(camera),w,h,extent(bounds),Scene.palette(Scene.assets(scene)),None{},attachment_output(format),A.Shaded{}}
  +selected : A.FrameInput = A.FrameInput{R.Camera.basis(camera),w,h,extent(bounds),Scene.palette(Scene.assets(scene)),brush,attachment_output(format),A.Shaded{}}
  do V.Action<Scene.Group & X.Body>:
    image(context,target,scene,input,name,False{},True{})
    image(context,target,scene,input,name ++ "-repeat",False{},True{})
    modes(6n,2,context,target,scene,input,name)
    image(context,target,scene,selected,name ++ "-selected",False{},True{})
    image(context,target,scene,selected_id(selected),name ++ "-selected-id",False{},False{})
    image(context,target,scene,selected,name ++ "-rings",True{},True{})
    trace(name,context,target,scene,input)
    return (scene,body)

def prepared(+context: Context, +target: P.Target, +name: String, +camera: R.Camera, +revision: U32, brush: Maybe<&2,X.MetricSphere>, scene: Scene.Group, pair: X.Body & C.ChunkSet) -> V.Action(Scene.Group & X.Body):
  Context{+instance,+physical,+device,P.Commands{command,fence}} = context
  P.Target{color,depth,pass,fb,stage,programs,+w,+h,+format} = target
  (body,mesh) = pair
  do V.Action<Scene.Group & X.Body>:
    installed : Scene.Group & C.ChunkSet <- Scene.install_chunks(instance,physical,device,command,fence,scene,revision,mesh)
    installed_scene(context,target,name,camera,brush,body,installed)

def install_scene(+context: Context, target: P.Target, +name: String, camera: R.Camera, +revision: U32, brush: Maybe<&2,X.MetricSphere>, scene: Scene.Group, body: X.Body) -> V.Action(Scene.Group & X.Body):
  do V.Action<Scene.Group & X.Body>:
    pair : X.Body & C.ChunkSet <- body_saved(name,revision,Source.body(body))
    prepared(context,target,name,camera,revision,brush,scene,pair)

def hover_brush() -> X.MetricSphere:
  X.MetricSphere.brush(X.PointCm{1985.5450439453125,2100.0,453.81011962890625})

def finish(+device: V.Device, target: P.Target, pair: Scene.Group & X.Body) -> V.Action(Unit):
  (scene,body) = pair
  P.destroy_target(device,target)

def stroke(+context: Context, old: P.Target, +scene: Scene.Group) -> V.Action(Unit):
  Context{+instance,+physical,+device,commands} = context
  do V.Action<Unit>:
    P.destroy_target(device,old)
    +target : P.Target <- P.create_target(instance,physical,device,Scene.assets(scene),512,512,37)
    image(context,target,scene,A.FrameInput{R.Basis{R.Vec3{4.125,4.25,524294.0},R.Vec3{1.0,0.0,0.0},R.Vec3{0.0,1.0,0.0},R.Vec3{0.0,0.0,F32.neg(1.0)},1048576.0,0.1},512,512,1,Scene.palette(Scene.assets(scene)),Some{X.MetricSphere.brush(X.PointCm{40.0,40.0,60.0})},A.Unorm{},A.Shaded{}},"stroke-inclusive",True{},True{})
    image(context,target,scene,A.FrameInput{R.Basis{R.Vec3{4.1250152587890625,4.25,524294.0},R.Vec3{1.0,0.0,0.0},R.Vec3{0.0,1.0,0.0},R.Vec3{0.0,0.0,F32.neg(1.0)},1048576.0,0.1},512,512,1,Scene.palette(Scene.assets(scene)),Some{X.MetricSphere.brush(X.PointCm{40.0,40.0,60.0})},A.Unorm{},A.Shaded{}},"stroke-outside",True{},True{})
    P.destroy_target(device,target)

def strokes(context: Context, target: P.Target, pair: Scene.Group & X.Body) -> V.Action(Unit):
  (scene,body) = pair
  stroke(context,target,scene)

def degenerate(+context: Context, old: P.Target, pair: Scene.Group & X.Body) -> V.Action(Unit):
  Context{+instance,+physical,+device,commands} = context
  (+scene,body) = pair
  do V.Action<Unit>:
    P.destroy_target(device,old)
    +target : P.Target <- P.create_target(instance,physical,device,Scene.assets(scene),384,192,37)
    next : Scene.Group & X.Body <- install_scene(context,target,"degenerate",R.Camera{R.Vec3{6.3842944,0.09819364,6.0},1.6689711,0.0},9,Some{X.MetricSphere.brush(X.PointCm{40.0,40.0,60.0})},scene,body)
    strokes(context,target,next)

def ring_views(+context: Context, old: P.Target, pair: Scene.Group & X.Body) -> V.Action(Unit):
  Context{+instance,+physical,+device,commands} = context
  (+scene,body) = pair
  do V.Action<Unit>:
    P.destroy_target(device,old)
    +target : P.Target <- P.create_target(instance,physical,device,Scene.assets(scene),384,192,37)
    next : Scene.Group & X.Body <- install_scene(context,target,"near",R.Camera{R.Vec3{4.0,F32.neg(0.05),6.0},1.57079632679,0.0},8,Some{X.MetricSphere.brush(X.PointCm{40.0,0.0,60.0})},scene,X.Cuboids{[]})
    degenerate(context,target,next)

def reciprocal(+context: Context, +target: P.Target, +scene: Scene.Group) -> V.Action(Unit):
  +input : A.FrameInput = A.FrameInput{R.Basis{R.Vec3{4.0,F32.neg(0.15),6.0},R.Vec3{1.0,0.0,0.0},R.Vec3{0.0,0.0,1.0},R.Vec3{0.0,1.0,0.0},4.0,0.1},384,512,8,Scene.palette(Scene.assets(scene)),Some{X.MetricSphere.brush(X.PointCm{44.0,10.0,60.0})},A.Unorm{},A.Shaded{}}
  do V.Action<Unit>:
    image(context,target,scene,input,"reciprocal",False{},True{})
    image(context,target,scene,input,"reciprocal-selected",False{},True{})
    image(context,target,scene,input,"reciprocal-rings",True{},True{})

def cube_ready(+context: Context, +target: P.Target, pair: Scene.Group & X.Body) -> V.Action(Unit):
  (+scene,body) = pair
  do V.Action<Unit>:
    reciprocal(context,target,scene)
    ring_views(context,target,(scene,body))

def ring_cube(+context: Context, old: P.Target, pair: Scene.Group & X.Body) -> V.Action(Unit):
  Context{+instance,+physical,+device,commands} = context
  (+scene,body) = pair
  do V.Action<Unit>:
    P.destroy_target(device,old)
    +target : P.Target <- P.create_target(instance,physical,device,Scene.assets(scene),384,512,37)
    next : Scene.Group & X.Body <- install_scene(context,target,"foreground",R.Camera{R.Vec3{4.0,F32.neg(8.0),6.0},1.57079632679,0.0},7,Some{X.MetricSphere.brush(X.PointCm{40.0,10.0,60.0})},scene,X.Body.solid(3n))
    cube_ready(context,target,next)

def palette_body() -> X.Body:
  body = X.Body.empty(3n)
  body = X.Body.write(body,X.Cell{1,3,3},1)
  body = X.Body.write(body,X.Cell{2,3,3},2)
  body = X.Body.write(body,X.Cell{3,3,3},3)
  body = X.Body.write(body,X.Cell{4,3,3},4)
  body = X.Body.write(body,X.Cell{5,3,3},5)
  X.Body.write(body,X.Cell{6,3,3},2147483906)

def palette_scene(+context: Context, old: P.Target, pair: Scene.Group & X.Body) -> V.Action(Unit):
  Context{+instance,+physical,+device,commands} = context
  (+scene,body) = pair
  do V.Action<Unit>:
    P.destroy_target(device,old)
    +target : P.Target <- P.create_target(instance,physical,device,Scene.assets(scene),512,256,37)
    next : Scene.Group & X.Body <- install_scene(context,target,"palette",R.Camera{R.Vec3{4.0,F32.neg(8.0),7.0},1.57079632679,F32.neg(0.25)},10,Some{X.MetricSphere.brush(X.PointCm{65.0,30.0,35.0})},scene,palette_body())
    ring_cube(context,target,next)

def output_formats(+context: Context, old: P.Target, pair: Scene.Group & X.Body) -> V.Action(Unit):
  Context{+instance,+physical,+device,commands} = context
  (+scene,body) = pair
  do V.Action<Unit>:
    P.destroy_target(device,old)
    +target : P.Target <- P.create_target(instance,physical,device,Scene.assets(scene),512,512,43)
    next : Scene.Group & X.Body <- install_scene(context,target,"srgb",R.Camera.atelier(),2,Some{hover_brush()},scene,body)
    palette_scene(context,target,next)

def portrait(+context: Context, old: P.Target, pair: Scene.Group & X.Body) -> V.Action(Unit):
  Context{+instance,+physical,+device,commands} = context
  (+scene,body) = pair
  do V.Action<Unit>:
    P.destroy_target(device,old)
    +tall : P.Target <- P.create_target(instance,physical,device,Scene.assets(scene),450,900,37)
    next : Scene.Group & X.Body <- install_scene(context,tall,"portrait",R.Camera{R.Vec3{110.0,F32.neg(35.0),65.0},1.1,F32.neg(0.2)},2,Some{X.MetricSphere.brush(X.PointCm{1500.0,200.0,500.0})},scene,body)
    output_formats(context,tall,next)

def resizes(+context: Context, old: P.Target, pair: Scene.Group & X.Body) -> V.Action(Unit):
  Context{+instance,+physical,+device,commands} = context
  (+scene,body) = pair
  do V.Action<Unit>:
    P.destroy_target(device,old)
    +wide : P.Target <- P.create_target(instance,physical,device,Scene.assets(scene),800,450,37)
    next : Scene.Group & X.Body <- install_scene(context,wide,"landscape",R.Camera.atelier(),2,Some{hover_brush()},scene,body)
    portrait(context,wide,next)

def restored(+context: Context, +target: P.Target, pair: Scene.Group & X.Body) -> V.Action(Unit):
  (scene,body) = pair
  do V.Action<Unit>:
    next : Scene.Group & X.Body <- install_scene(context,target,"reset",R.Camera.atelier(),2,Some{hover_brush()},scene,Atelier.body())
    resizes(context,target,next)

def carved(+context: Context, +target: P.Target, pair: Scene.Group & X.Body) -> V.Action(Unit):
  (scene,body) = pair
  do V.Action<Unit>:
    next : Scene.Group & X.Body <- install_scene(context,target,"carved",R.Camera.atelier(),1,Some{hover_brush()},scene,X.Body.cut(body,hover_brush()))
    restored(context,target,next)

def scenes(+context: Context, scene: Scene.Group, +target: P.Target) -> V.Action(Unit):
  do V.Action<Unit>:
    first : Scene.Group & X.Body <- install_scene(context,target,"intact",R.Camera.atelier(),0,Some{hover_brush()},scene,Atelier.body())
    carved(context,target,first)

def run(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +instance : V.Instance <- V.Entry.create_instance(entry,V.InstanceCreateInfo.default())
    devices : List<V.PhysicalDevice> <- V.Instance.enumerate_physical_devices(instance)
    +physical : V.PhysicalDevice <- D.first(devices)
    families : List<(U32 & U32)> <- V.Instance.get_physical_device_queue_family_properties(instance,physical)
    family : U32 <- D.choose(Core.find_queue_family(families,1),"No graphics queue")
    +device : V.Device <- V.Instance.create_device(instance,physical,V.DeviceCreateInfo{family,[]})
    +scene : Scene.Group <- Scene.create(instance,physical,device)
    commands : P.Commands <- P.commands(device)
    +target : P.Target <- P.create_target(instance,physical,device,Scene.assets(scene),512,512,37)
    scenes(Context{instance,physical,device,commands},scene,target)

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    +count : U32 <- V.or_exit(U32,live)
    IO.print("Production shared recorder live=" ++ U32.show(count))
    checked : V.VkResult(Unit) <- D.require(U32.is_zero(count),"Production scene leaked rows")
    V.or_exit(Unit,checked)
