import Base
import ./demo.bend as D
import ./render.bend as V
import ./math.bend as R

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
