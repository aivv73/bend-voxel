import Base

def micros() -> IO(U32):
  import "./platform/micros.c"
  import "./platform/micros.js"
