import Base
import ./world.bend as W
import ./spatial.bend as S
import ./probe.bend as Probe
import ./platform.bend as P
import ./face_audit.bend as Audit
import ./atelier_workload.bend as AtelierWorkload

# Headless diagnostic: time the ordinary edit, then replay the face builder
# with counters. Audit time is separate from the ordinary surface stage.
def next.id(w: W.World) -> U32:
  W.World{_,_,_,_,_,next,_,_} = w
  next
def printed(same: Bool, ordinal: U32, body: U32, removed: U32,
  cut: U32, connectivity: U32, surface: U32, finalize: U32, auditUs: U32,
  cuboids: U32, candidates: U32, nodes: U32, boxCandidates: U32,
  checks: U32, clips: U32, output: U32, reference: U32) -> IO(U32):
  match same:
    case False{}: IO.die(U32,1,"Profiled and production faces cover different surfaces")
    case True{}:
      do IO<U32>:
        Unit <- IO.print("face_build," ++ U32.show(ordinal) ++ "," ++ U32.show(body) ++ "," ++
          U32.show(removed) ++ "," ++ U32.show(cut) ++ "," ++ U32.show(connectivity) ++ "," ++
          U32.show(surface) ++ "," ++ U32.show(finalize) ++ "," ++ U32.show(auditUs) ++ "," ++
          U32.show(cuboids) ++ "," ++ U32.show(candidates) ++ "," ++ U32.show(nodes) ++ "," ++
          U32.show(boxCandidates) ++ "," ++ U32.show(checks) ++ "," ++ U32.show(clips) ++ "," ++
          U32.show(output) ++ "," ++ U32.show(reference))
        IO.pure(U32,1)
def audit.result(r: Audit.FaceProfile, +original: List<&2,S.Face>, ordinal: U32, body: U32,
  removed: U32, cut: U32, connectivity: U32, surface: U32, finalize: U32, auditUs: U32) -> IO(U32):
  Audit.FaceProfile{generated,cuboids,candidates,nodes,boxCandidates,checks,clips,+output} = r
  +reference = Audit.face.count(original)
  printed(Audit.equivalent(generated,original),
    ordinal,body,removed,cut,connectivity,surface,finalize,auditUs,
    cuboids,candidates,nodes,boxCandidates,checks,clips,output,reference)
def audit.one(t: S.Tree, fs: List<&2,S.Face>, ordinal: U32, body: U32,
  removed: U32, cut: U32, connectivity: U32, surface: U32, finalize: U32) -> IO(U32):
  do IO<U32>:
    +start : U32 <- P.micros()
    profile : Audit.FaceProfile <- IO.pure(Audit.FaceProfile,Audit.faces(t))
    +end : U32 <- P.micros()
    audit.result(profile,fs,ordinal,body,removed,cut,connectivity,surface,finalize,(end - start : U32))
def audit.selected(selected: Bool, t: S.Tree, fs: List<&2,S.Face>, ordinal: U32, body: U32,
  removed: U32, cut: U32, connectivity: U32, surface: U32, finalize: U32) -> IO(U32):
  match selected:
    case False{}: IO.pure(U32,0)
    case True{}: audit.one(t,fs,ordinal,body,removed,cut,connectivity,surface,finalize)
def audit.bodies(bs: List<&2,W.Body>, +firstId: U32, +ordinal: U32,
  +removed: U32, +cut: U32, +connectivity: U32, +surface: U32, +finalize: U32) -> IO(U32):
  match bs:
    case Nil{}: IO.pure(U32,0)
    case W.Body{+id,_,_,_,_,t,fs,_} <> rest:
      do IO<U32>:
        +current : U32 <- audit.selected((id >= firstId : U32),t,fs,ordinal,id,
          removed,cut,connectivity,surface,finalize)
        +later : U32 <- audit.bodies(rest,firstId,ordinal,removed,cut,connectivity,surface,finalize)
        IO.pure(U32,(current + later : U32))
def checked.count(count: U32, w: W.World) -> IO(W.World):
  match count:
    case 0: IO.die(W.World,1,"Accepted edit rebuilt no body")
    case _: IO.pure(W.World,w)
def step.world(w: W.World, ordinal: U32, firstId: U32,
  cut: U32, connectivity: U32, surface: U32, finalize: U32) -> IO(W.World):
  W.World{+bs,n,fragments,+removed,status,next,budget,districts} = w
  match status:
    case 1:
      do IO<W.World>:
        +count : U32 <- audit.bodies(bs,firstId,ordinal,removed,cut,connectivity,surface,finalize)
        checked.count(count,W.World{bs,n,fragments,removed,status,next,budget,districts})
    case _: IO.die(W.World,1,"Atelier face-profile cut was rejected")
def step.result(r: Probe.EditResult, ordinal: U32, firstId: U32) -> IO(W.World):
  Probe.EditResult{w,cut,connectivity,surface,finalize} = r
  step.world(w,ordinal,firstId,cut,connectivity,surface,finalize)
def step(+w: W.World, +ordinal: U32) -> IO(W.World):
  +firstId = next.id(w)
  do IO<W.World>:
    r : Probe.EditResult <- Probe.timed(Probe.Request{w,AtelierWorkload.point(ordinal),True{}})
    step.result(r,ordinal,firstId)
@unsafe
def run(n: Nat, +ordinal: U32, w: W.World) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+k:
      do IO<Unit>:
        next : W.World <- step(w,ordinal)
        run(k,(ordinal + 1 : U32),next)
def main() -> IO(Unit):
  run(6n,0,W.showcase(2048))
