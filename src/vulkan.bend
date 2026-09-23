import Base
import ./demo.bend as D
import ./render.bend as V

# Linux native Vulkan backend. The state remains Bend-owned; the effect reads
# its current cached faces and returns it unchanged with window events.
def vulkan.frame(window: Window, state: D.State, aim: V.Aim, hud: String) -> IO(Window & D.State & List<Event>):
  import "./vulkan/bridge.c"
  import "./vulkan/bridge.js"

def vulkan.release(window: Window) -> IO(Window):
  import "./vulkan/bridge.c"
  import "./vulkan/bridge.js"
