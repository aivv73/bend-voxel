import Base

def present(window: Window, image: Image, hud: String) -> IO(Window & Image & List<Event>):
  import "./platform/present.c"
  import "./platform/present.js"
def micros() -> IO(U32):
  import "./platform/micros.c"
  import "./platform/micros.js"
