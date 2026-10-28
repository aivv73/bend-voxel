import Base
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/examples/window.bend as WSI
import ../src/presentation.bend as P
import ../../deps/bend-vulkan/examples/buffer_roundtrip.bend as D
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W
import ../../deps/bend-vulkan/tests/native.bend as T
import ./presentation.bend as Smoke

def failed_build(+entry: V.Entry) -> V.Action(Unit):
  do V.Action<Unit>:
    +context : WSI.Context <- WSI.open(entry,"Bend target rollback",False{})
    before : U32 <- V.debug_live_objects()
    armed : U32 & U32 <- V.debug_u64_roundtrip(W.of_u32(3735928559))
    T.expect_error(P.Target,4294967294,P.build(context,640,480))
    after : U32 <- V.debug_live_objects()
    D.require(U32.is_eq(before,after),"Partial target build leaked resources")
    V.Action.lift(Unit,IO.print("Bend target pipeline failure rolled back every partial resource"))

def main() -> IO(Unit):
  do IO<Unit>:
    failure : V.VkResult(Unit) <- V.Entry.with(Unit,entry => failed_build(entry))
    V.or_exit(Unit,failure)
    result : V.VkResult(Unit) <- V.Entry.with(Unit,entry => Smoke.run(entry))
    V.or_exit(Unit,result)
    live : V.VkResult(U32) <- V.debug_live_objects()
    count : U32 <- V.or_exit(U32,live)
    checked : V.VkResult(Unit) <- D.require(U32.is_zero(count),"Presentation probes leaked rows")
    V.or_exit(Unit,checked)
    IO.print("Native presentation borrowing and controlled cleanup passed")
