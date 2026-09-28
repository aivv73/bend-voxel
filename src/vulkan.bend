import Base
import ./demo.bend as D
import ./world.bend as W
import ./render.bend as V
import ./math.bend as R
import ./megascene_picking.bend as P

# Linux native Vulkan backend. Bend computes the static palette at startup.
def vulkan.colors(window: Window, colors: List<&2,R.Vec>) -> IO(Window):
  import "./vulkan/bridge.c"
  import "./vulkan/bridge.js"

# The effect reads cached faces and Bend-built vertices, then returns window events.
def vulkan.frame(window: Window, state: D.State, aim: V.Aim, hud: String) -> IO(Window & D.State & List<Event>):
  import "./vulkan/bridge.c"
  import "./vulkan/bridge.js"

def vulkan.release(window: Window) -> IO(Window):
  import "./vulkan/bridge.c"
  import "./vulkan/bridge.js"

# Separate opt-in static-runner evidence and outside-timing opening capture.
def vulkan.mark(code: U32) -> IO(Unit):
  import "./vulkan/record.c"
  import "./vulkan/bridge.js"
def vulkan.capture(window: Window) -> IO(Window):
  import "./vulkan/bridge.c"
  import "./vulkan/bridge.js"

# The runner freezes every binary32 camera before either replay. The native
# effect reads those bits by frame index; no libm interpolation runs in a worker.
def vulkan.route(index: U32, width: U32, height: U32) -> IO(V.Camera):
  import "./vulkan/record.c"
  import "./vulkan/bridge.js"

# Frozen picking input and actual identified result, including disabled samples.
def vulkan.pickray(index: U32) -> IO(P.Ray):
  import "./vulkan/record.c"
  import "./vulkan/bridge.js"
def vulkan.pickrecord(ray: P.Ray, hit: V.Hit) -> IO(Unit):
  import "./vulkan/record.c"
  import "./vulkan/bridge.js"

# Action acceptance and frame-return response evidence. The action remains in
# canonical history even when it is rejected or removes no cells.
def vulkan.editbegin(action: U32, point: R.Vec) -> IO(Unit):
  import "./vulkan/record.c"
  import "./vulkan/bridge.js"
def vulkan.editrecord(world: W.World, action: U32, point: R.Vec) -> IO(Unit):
  import "./vulkan/record.c"
  import "./vulkan/bridge.js"
