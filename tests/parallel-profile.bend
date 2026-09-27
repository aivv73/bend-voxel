import Base
import ../src/world.bend as W
import ../src/platform.bend as P
import ../src/face_profile.bend as Profile

# Time production initialization and the six real edits. Profile.run verifies
# each local surface against the independent counted full rebuild after timing.
def main() -> IO(Unit):
  do IO<Unit>:
    +start : U32 <- P.micros()
    world : W.World <- IO.pure(W.World,W.showcase(2048))
    +end : U32 <- P.micros()
    Unit <- IO.print("init," ++ U32.show((end - start : U32)))
    Profile.run(6n,0,world)
