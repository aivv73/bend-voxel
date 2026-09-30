import Base
import ./schedule_float.bend as F
import ./schedule_route.bend as Route
import ./schedule_history.bend as History
import ./schedule_cut.bend as Cut
import ./schedule_policy.bend as Policy
import ./schedule_proxy.bend as Proxy

def history(q: Maybe<&2,U32>,seed: Maybe<&2,U32>,control: String,+id: String) -> IO(Unit):
  match q seed:
    case Some{q} Some{seed}: History.history(q,seed,control,id,History.count(id),String.eq(id,"history-perf-v2"))
    case _ _: IO.die(Unit,2,"invalid history arguments")
def localized(q: Maybe<&2,U32>,seed: Maybe<&2,U32>,origin: String,control: String,id: String) -> IO(Unit):
  match q seed:
    case Some{q} Some{seed}: Cut.localized(q,seed,origin,control,id)
    case _ _: IO.die(Unit,2,"invalid localized arguments")
def support(q: Maybe<&2,U32>,seed: Maybe<&2,U32>,origin: String,control: String,+id: String) -> IO(Unit):
  match q seed:
    case Some{q} Some{seed}: Cut.support(q,seed,origin,control,id,Cut.spans(id))
    case _ _: IO.die(Unit,2,"invalid support arguments")
def proxy(q: Maybe<&2,U32>,seed: Maybe<&2,U32>,diagnostic: String,scene: String,height: Maybe<&2,U32>,lo: F.Vec,hi: F.Vec) -> IO(Unit):
  match q seed height:
    case Some{q} Some{seed} Some{height}: Proxy.proxy(q,seed,diagnostic,scene,height,lo,hi)
    case _ _ _: IO.die(Unit,2,"invalid proxy arguments")
def arguments(xs: List<String>) -> IO(Unit):
  match xs:
    case _ <> "policy" <> warmup <> measured <> performance <> cuts <> moving <> reviews <> points <> overview <> Nil{}: Policy.policy(warmup,measured,performance,cuts,moving,reviews,points,overview)
    case _ <> "protocol" <> id <> Nil{}: IO.print(Policy.protocol(String.eq(id,"history-perf-v2")))
    case _ <> "proxy" <> q <> seed <> diagnostic <> scene <> height <> x <> y <> z <> a <> b <> c <> Nil{}: proxy(U32.read(q),U32.read(seed),diagnostic,scene,U32.read(height),Route.vec(x,y,z),Route.vec(a,b,c))
    case _ <> "proxy-shadow" <> x <> y <> z <> a <> b <> c <> Nil{}:
      do IO<Unit>:
        cam : String <- Proxy.shadow(Route.vec(x,y,z),Route.vec(a,b,c))
        IO.print(cam)
    case _ <> "history-face" <> x <> y <> z <> a <> b <> c <> Nil{}:
      do IO<Unit>:
        cam : String <- Proxy.history.face(Route.vec(x,y,z),Route.vec(a,b,c))
        IO.print(cam)
    case _ <> "history" <> q <> seed <> control <> id <> Nil{}: history(U32.read(q),U32.read(seed),control,id)
    case _ <> "localized" <> q <> seed <> origin <> control <> id <> Nil{}: localized(U32.read(q),U32.read(seed),origin,control,id)
    case _ <> "support" <> q <> seed <> origin <> control <> id <> Nil{}: support(U32.read(q),U32.read(seed),origin,control,id)
    case _: Route.arguments(xs)
def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<String> <- IO.args()
    arguments(xs)
