import Base
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../voxel.bend as X
import ../../render.bend as R
import ../../dump.bend as OldExport
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D
import ../../deps/bend-vulkan/examples/indexed_offscreen.bend as E
import ./mesh.bend as M
import ./exterior.bend as Exterior
import ./geometry.bend as G
import ./renderer.bend as GPU
import ./reference.bend as Ref
import ./export.bend as Export
import ./fixtures.bend as F

type State is Type:
  State{body: X.Body, faces: List<&2,X.Face>, renderer: GPU.Renderer}

def share(words: List<U32>) -> List<&2,U32>:
  match words:
    case Nil{}: Nil{}
    case Con{word,rest}: word <> share(rest)

def report(+report: Ref.Report) -> V.Action(Ref.Report):
  Ref.Report{pixels,edges,errors,invalid,upstream,covered,mats,dirs} = report
  do V.Action<Ref.Report>:
    V.Action.lift(Unit,IO.print("Pixels " ++ U32.show(pixels) ++ ", excluded " ++ U32.show(edges) ++ ", mismatches " ++ U32.show(errors) ++ ", invalid edges " ++ U32.show(invalid) ++ ", upstream " ++ U32.show(upstream) ++ ", covered " ++ U32.show(covered) ++ ", materials " ++ U32.show(mats) ++ ", directions " ++ U32.show(dirs)))
    D.require(U32.is_eq(pixels,262144) && U32.is_eq(errors,0) && U32.is_eq(invalid,0) && U32.is_eq(upstream,0),"Voxel reference mismatch")
    return report

def export(path: Maybe<&2,String>, bytes: List<U32>) -> V.Action(Unit):
  match path:
    case None{}: V.Action.pure(Unit,Unit{})
    case Some{p}: V.Action.lift(Unit,Export.ppm(p,bytes))

def retain(+colors: List<&2,U32>, depths: List<U32>, faces: List<&2,X.Face>, basis: R.Basis, mode: U32, path: Maybe<&2,String>) -> V.Action(Ref.Report & List<&2,U32>):
  do V.Action<Ref.Report & List<&2,U32>>:
    export(path,E.copy_words(colors))
    result : Ref.Report <- report(Ref.compare((E.copy_words(colors),depths),faces,basis,mode))
    return (result,colors)

def read_frame(pair: List<U32> & List<U32>, faces: List<&2,X.Face>, basis: R.Basis, mode: U32, path: Maybe<&2,String>) -> V.Action(Ref.Report & List<&2,U32>):
  (colors,depths) = pair
  retain(share(colors),depths,faces,basis,mode,path)

def frame(renderer: GPU.Renderer, faces: List<&2,X.Face>, +camera: R.Camera, +mode: U32, path: Maybe<&2,String>) -> V.Action(Ref.Report & List<&2,U32>):
  do V.Action<Ref.Report & List<&2,U32>>:
    result : List<U32> & List<U32> <- GPU.frame(renderer,camera,mode)
    read_frame(result,faces,R.Camera.basis(camera),mode,path)

def uploaded(body: X.Body, faces: List<&2,X.Face>, pair: GPU.Renderer & M.Mesh) -> V.Action(State):
  (+renderer,mesh) = pair
  GPU.Renderer{instance,physical,device,command,fence,fb,color,depth,stage,basic,mat,dir,geometry,uploads} = renderer
  do V.Action<State>:
    V.Device.collect_retired(device)
    return State{body,faces,renderer}

def checked(renderer: GPU.Renderer, pair: X.Body & (M.Mesh & Bool)) -> V.Action(State):
  (body,(M.Mesh{+faces,+size,bounds,vs,ix},valid)) = pair
  +count = GPU.quads(size)
  do V.Action<State>:
    D.require(valid && (count <= 3072 : U32),"Independent complete voxel geometry check failed")
    V.Action.lift(Unit,IO.print("Complete packed geometry verified, faces " ++ U32.show(count)))
    installed : GPU.Renderer & M.Mesh <- GPU.replace_mesh(renderer,M.Mesh{faces,size,bounds,vs,ix})
    uploaded(body,faces,installed)

def built(renderer: GPU.Renderer, pair: X.Body & Result<&2,&1,Exterior.Error,M.Mesh>) -> V.Action(State):
  (body,result) = pair
  match result:
    case Fail{error}: IO.pure(V.VkResult(State),Fail{(1,Exterior.error_show(error))})
    case Done{mesh}: checked(renderer,G.checked(body,mesh))

def load(renderer: GPU.Renderer, body: X.Body) -> V.Action(State):
  built(renderer,M.build(body))

def cube(renderer: GPU.Renderer, pair: X.Body & Bool) -> V.Action(State):
  (body,valid) = pair
  do V.Action<State>:
    D.require(valid,"Independent metric-sphere occupancy mismatch")
    load(renderer,body)

def edit(state: State) -> V.Action(State):
  State{body,faces,renderer} = state
  cube(renderer,F.cube(X.Body.cut(body,X.MetricSphere.demo()),True{}))

def reset(state: State) -> V.Action(State):
  State{body,faces,renderer} = state
  cube(renderer,F.cube(X.Body.solid(3n),False{}))

def same_frame(pair: Ref.Report & List<&2,U32>, expected: List<&2,U32>) -> V.Action(Unit):
  (report,actual) = pair
  D.require(D.bytes_equal(E.copy_words(actual),E.copy_words(expected)),"Repeat or reset changed exact frame bytes")

def image(pair: Ref.Report & List<&2,U32>) -> List<&2,U32>:
  (report,colors) = pair
  colors

def materials(pair: Ref.Report & List<&2,U32>) -> U32:
  (Ref.Report{p,e,m,i,u,c,mats,dirs},colors) = pair
  mats

def directions(pair: Ref.Report & List<&2,U32>) -> U32:
  (Ref.Report{p,e,m,i,u,c,mats,dirs},colors) = pair
  dirs

def legacy_image(scene: R.RenderScene, path: String) -> IO(Unit):
  R.RenderScene{basis,tiles,count,cache} = scene
  OldExport.Dump.ppm(path,R.Tiles.image(0n,R.LightingCache.ground(cache),basis,None{},tiles))

def legacy(+faces: List<&2,X.Face>, path: String) -> V.Action(Unit):
  V.Action.lift(Unit,legacy_image(R.RenderScene.build(X.Surface{faces},R.Camera.initial(),5n),path))

def live(+expected: U32) -> V.Action(Unit):
  do V.Action<Unit>:
    +actual : U32 <- V.debug_live_objects()
    D.require(U32.is_eq(actual,expected),"Voxel replacements changed live resources, expected " ++ U32.show(expected) ++ ", actual " ++ U32.show(actual))

def camera_frames(renderer: GPU.Renderer, +faces: List<&2,X.Face>) -> V.Action(Unit):
  +gpu = renderer
  do V.Action<Unit>:
    old : List<U32> <- GPU.geometry_bytes(gpu)
    +bytes : List<&2,U32> = share(old)
    +uploads : U32 = GPU.upload_count(gpu)
    moved : Ref.Report & List<&2,U32> <- frame(gpu,faces,R.Camera.look(R.Camera.initial(),35.0,F32.neg(20.0)),0,None{})
    back : Ref.Report & List<&2,U32> <- frame(gpu,faces,R.Camera.initial(),0,None{})
    now : List<U32> <- GPU.geometry_bytes(gpu)
    D.require(D.bytes_equal(E.copy_words(bytes),now) && U32.is_eq(uploads,GPU.upload_count(gpu)),"Camera frames uploaded or changed mesh bytes")

def diagnostic_views(fuel: Nat, +view: U32, +renderer: GPU.Renderer, +faces: List<&2,X.Face>, +mats: U32, +dirs: U32) -> V.Action(Unit):
  match fuel:
    case 0n:
      D.require(U32.is_eq(mats,255) && U32.is_eq(dirs,63),"GPU diagnostics did not cover every material and direction")
    case 1n+rest:
      do V.Action<Unit>:
        material_frame : Ref.Report & List<&2,U32> <- frame(renderer,faces,F.camera(view),1,None{})
        direction_frame : Ref.Report & List<&2,U32> <- frame(renderer,faces,F.camera(view),2,None{})
        diagnostic_views(rest,(view + 1 : U32),renderer,faces,(mats .|. materials(material_frame) : U32),(dirs .|. directions(direction_frame) : U32))

def diagnostic_state(state: State) -> V.Action(Unit):
  State{body,+faces,+renderer} = state
  do V.Action<Unit>:
    camera_frames(renderer,faces)
    diagnostic_views(6n,0,renderer,faces,0,0)
    V.Action.lift(Unit,IO.print("GPU full U32 materials including high bits and all six directions verified"))

def old_export(path: Maybe<&2,String>, faces: List<&2,X.Face>) -> V.Action(Unit):
  match path:
    case None{}: V.Action.pure(Unit,Unit{})
    case Some{p}: legacy(faces,p)

def observe(state: State, path: Maybe<&2,String>, legacy_path: Maybe<&2,String>) -> V.Action(State & List<&2,U32>):
  State{body,+faces,+renderer} = state
  do V.Action<State & List<&2,U32>>:
    result : Ref.Report & List<&2,U32> <- frame(renderer,faces,R.Camera.initial(),0,path)
    old_export(legacy_path,faces)
    return (State{body,faces,renderer},image(result))

def cycle(state: State, +expected: U32) -> V.Action(State):
  do V.Action<State>:
    reset_state : State <- reset(state)
    live(expected)
    carved : State <- edit(reset_state)
    live(expected)
    return carved

def cycles(fuel: Nat, state: State, +expected: U32) -> V.Action(State):
  match fuel:
    case 0n: V.Action.pure(State,state)
    case 1n+rest:
      do V.Action<State>:
        next : State <- cycle(state,expected)
        cycles(rest,next,expected)

def final_empty(state: State, +expected: U32) -> V.Action(Unit):
  State{body,faces,+renderer} = state
  do V.Action<Unit>:
    live((expected - 4 : U32))
    empty : Ref.Report & List<&2,U32> <- frame(renderer,Nil{},R.Camera.initial(),0,Some{"build/voxel-empty.ppm"})
    diagnostic : State <- load(renderer,F.materials())
    live(expected)
    diagnostic_state(diagnostic)

def cavity(state: State, +expected: U32) -> V.Action(Unit):
  State{body,+faces,+renderer} = state
  do V.Action<Unit>:
    live(expected)
    result : Ref.Report & List<&2,U32> <- frame(renderer,faces,R.Camera.initial(),0,None{})
    empty : State <- load(renderer,X.Body.empty(3n))
    final_empty(empty,expected)

def reset_checked(pair: State & List<&2,U32>, +baseline: List<&2,U32>, +expected: U32) -> V.Action(Unit):
  (State{body,faces,+renderer},actual) = pair
  do V.Action<Unit>:
    D.require(D.bytes_equal(E.copy_words(actual),E.copy_words(baseline)),"Reset failed to restore exact original image")
    live(expected)
    hole : State <- load(renderer,X.Body.write(X.Body.solid(3n),X.Cell{3,3,3},0))
    cavity(hole,expected)

def repeated_checked(pair: State & List<&2,U32>, +baseline: List<&2,U32>, carved: List<&2,U32>, +expected: U32) -> V.Action(Unit):
  (state,actual) = pair
  do V.Action<Unit>:
    D.require(D.bytes_equal(E.copy_words(actual),E.copy_words(carved)),"Repeated carve changed exact frame")
    after_cycles : State <- cycles(8n,state,expected)
    reset_state : State <- reset(after_cycles)
    restored : State & List<&2,U32> <- observe(reset_state,Some{"build/voxel-reset.ppm"},None{})
    reset_checked(restored,baseline,expected)

def carved_checked(pair: State & List<&2,U32>, +baseline: List<&2,U32>, +expected: U32) -> V.Action(Unit):
  (State{body,+faces,+renderer},+carved) = pair
  do V.Action<Unit>:
    D.require(Bool.not(D.bytes_equal(E.copy_words(carved),E.copy_words(baseline))),"Carving did not change the frame")
    live(expected)
    camera_frames(renderer,faces)
    repeated : State <- edit(State{body,faces,renderer})
    live(expected)
    result : State & List<&2,U32> <- observe(repeated,None{},None{})
    repeated_checked(result,baseline,carved,expected)

def intact_checked(pair: State & List<&2,U32>) -> V.Action(Unit):
  (State{body,+faces,+renderer},baseline) = pair
  do V.Action<Unit>:
    expected : U32 <- V.debug_live_objects()
    D.require(U32.is_eq(U32.from_nat(List.length(&2,X.Face,faces)),384),"Intact cube must have 384 exposed quads")
    camera_frames(renderer,faces)
    carved : State <- edit(State{body,faces,renderer})
    image : State & List<&2,U32> <- observe(carved,Some{"build/voxel-carved.ppm"},Some{"build/voxel-upstream-carved.ppm"})
    carved_checked(image,baseline,expected)

def run(renderer: GPU.Renderer) -> V.Action(Unit):
  do V.Action<Unit>:
    state : State <- cube(renderer,F.cube(X.Body.solid(3n),False{}))
    initial : State & List<&2,U32> <- observe(state,Some{"build/voxel-intact.ppm"},Some{"build/voxel-upstream-intact.ppm"})
    intact_checked(initial)
    V.Action.lift(Unit,IO.print("Voxel complete geometry, RGBA8+D32 references, camera reuse, carve/repeat/reset, empty mesh and bounded replacements passed"))
