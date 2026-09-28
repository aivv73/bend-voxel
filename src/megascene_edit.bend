import Base
import ./world.bend as W
import ./math.bend as R

# This bounded runtime guard precedes unsafe carving, component classification,
# ID allocation and surface construction. It is not a formal proof.
def guard(world: W.World, point: R.Vec) -> IO(Unit):
  import "./edit/guard.c"
  import "./edit/guard.js"
