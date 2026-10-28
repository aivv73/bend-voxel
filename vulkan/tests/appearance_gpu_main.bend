import Base
import ./appearance_gpu.bend as G
import ./appearance_cases.bend as C
import ../src/appearance.bend as F

def main() -> IO(Unit):
  G.main_with(C.rows(),F.palette())
