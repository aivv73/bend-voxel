import Base
import ./world.bend as W
import ./vendor/bend3d.bend as R
import ./platform.bend as P

type Request is Type:
  Request{world: W.World, point: R.Vec, carve: Bool}
type EditResult is Type:
  EditResult{world: W.World, carveUs: U32, connectivityUs: U32, surfaceUs: U32, finalizeUs: U32}
def run(r: Request) -> W.World:
  Request{w,p,on} = r
  match on:
    case False{}: w
    case True{}: W.carve(w,p)
def timed(r: Request) -> IO(EditResult):
  Request{w,p,on} = r
  match on:
    case False{}: IO.pure(EditResult,EditResult{w,0,0,0,0})
    case True{}:
      do IO<EditResult>:
        +start : U32 <- P.micros()
        edit : W.Edit <- IO.pure(W.Edit,W.carve.prepare(w,p))
        +cut : U32 <- P.micros()
        classified : W.EditClassification <- IO.pure(W.EditClassification,W.carve.classify(edit))
        +connected : U32 <- P.micros()
        surfaces : W.EditSurfaces <- IO.pure(W.EditSurfaces,W.carve.surfaces(classified))
        +meshed : U32 <- P.micros()
        next : W.World <- IO.pure(W.World,W.carve.finalize(surfaces))
        end : U32 <- P.micros()
        IO.pure(EditResult,EditResult{next,(cut - start : U32),(connected - cut : U32),(meshed - connected : U32),(end - meshed : U32)})
