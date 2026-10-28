import Base
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D
import ../src/interactive.bend as I
import ../src/chunks.bend as C
import ../src/viewport.bend as View
import ../../voxel.bend as X

def cells_count(cells: Array<U32>) -> U32:
  match cells:
    case ALeaf{value}: Bool.to_u32(U32.is_ne(value,0))
    case ANode{left,right}:
      a b = cells_count(left) cells_count(right)
      (a + b : U32)

def body_count(body: X.Body) -> U32:
  match body:
    case X.Body{side,cells}: cells_count(cells)
    case X.Cuboids{boxes}: 4294967295

def occupied(result: Maybe<I.World>) -> U32:
  match result:
    case None{}: 4294967295
    case Some{I.World{body,mesh,camera,controls,revision,original,pointer,changed}}: body_count(body)

def queued(events: List<Event>) -> V.Action(Maybe<I.World>):
  do V.Action<Maybe<I.World>>:
    world : I.World <- I.initial(C.build(X.Body.solid(3n),0))
    I.events(events,world,View.Mapping{640,480,640,480})

def reset_click() -> V.Action(Maybe<I.World>):
  do V.Action<Maybe<I.World>>:
    world : I.World <- I.initial(C.build(X.Body.cut(X.Body.solid(3n),X.MetricSphere.demo()),0))
    I.events([Key{114,True{}},Mouse{320,240,0,True{}}],world,View.Mapping{640,480,640,480})

def cavity_hit(result: Maybe<I.World>) -> Maybe<&2,X.MetricSphere>:
  match result:
    case None{}: None{}
    case Some{I.World{body,C.ChunkSet{chunks,primitives,faces,bounds,count,shadow,rebuilt,retained},camera,controls,revision,original,pointer,changed}}:
      View.target(View.Viewport{640,480},camera,faces,320,240)

def cavity_point(hit: Maybe<&2,X.MetricSphere>) -> Bool:
  match hit:
    case None{}: False{}
    case Some{X.MetricSphere{X.PointCm{x,y,z},r}}:
      (F32.abs((x - 52.916145 : F32)) < 0.001 : F32) && (F32.abs((y - 53.285084 : F32)) < 0.001 : F32) && (F32.abs((z - 50.0 : F32)) < 0.001 : F32)

def pointer_is(result: Maybe<I.World>, +x: U32, +y: U32) -> Bool:
  match result:
    case None{}: False{}
    case Some{I.World{body,mesh,camera,controls,r,o,I.Pointer{px,py},dirty}}:
      U32.is_eq(x,px) && U32.is_eq(y,py)

def checks() -> V.Action(Unit):
  do V.Action<Unit>:
    first : Maybe<I.World> <- queued([Mouse{320,240,0,True{}}])
    +one : U32 = occupied(first)
    second : Maybe<I.World> <- queued([Mouse{320,240,0,True{}},Mouse{320,240,0,True{}}])
    +two : U32 = occupied(second)
    restored : Maybe<I.World> <- queued([Mouse{320,240,0,True{}},Mouse{320,240,0,True{}},Key{114,True{}},Mouse{320,240,0,True{}}])
    +reset : U32 = occupied(restored)
    prepared : Maybe<I.World> <- reset_click()
    +reset_prepared : U32 = occupied(prepared)
    cavity : Maybe<I.World> <- queued([Key{32,True{}}])
    pointer_click : Maybe<I.World> <- queued([Mouse{300,220,0,True{}}])
    D.require(pointer_is(pointer_click,300,220),"Click without Move must update the uncaptured pointer used by preview and Space")
    released : Maybe<I.World> <- queued([Move{10,10},Mouse{320,240,1,True{}},Look{2.0,1.0},Mouse{320,240,1,False{}}])
    D.require(pointer_is(released,320,240),"Capture release must restore the actual event pointer after center-based hover")
    V.Action.lift(Unit,IO.print("one queued click voxels=" ++ U32.show(one)))
    V.Action.lift(Unit,IO.print("two queued clicks before upload voxels=" ++ U32.show(two)))
    V.Action.lift(Unit,IO.print("reset then queued click before upload voxels=" ++ U32.show(reset)))
    V.Action.lift(Unit,IO.print("reset prepared cut then click before upload voxels=" ++ U32.show(reset_prepared)))
    D.require(U32.is_eq(one,505),"One queued center click must leave 505 occupied voxels")
    D.require(U32.is_eq(two,484),"Two queued center clicks must leave 484 occupied voxels before upload")
    D.require(U32.is_eq(reset,505),"Reset then queued center click must leave 505 occupied voxels before upload")
    D.require(U32.is_eq(reset_prepared,505),"Reset of a prepared cut then center click must leave 505 occupied voxels before upload")
    D.require(cavity_point(cavity_hit(cavity)),"Demo edit picking must hit 52.916145,53.285084,50 cm within 0.001 cm before upload")
    V.Action.lift(Unit,IO.print("Queued edit/reset picking before upload passed"))

def main() -> IO(Unit):
  do IO<Unit>:
    result : V.VkResult(Unit) <- checks()
    V.or_exit(Unit,result)
