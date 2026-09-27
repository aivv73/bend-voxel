import Base
import ./math.bend as R

# Fixed world-space cuts shared by the Vulkan stress suite and face profiler.
def point(+ordinal: U32) -> R.Vec:
  match ordinal:
    case 0: R.Vec{(0.0 - 7.5 : F32),4.2,1.5}
    case 1: R.Vec{0.5,7.5,(0.0 - 1.5 : F32)}
    case 2: R.Vec{12.5,4.0,(0.0 - 2.5 : F32)}
    case 3: R.Vec{(0.0 - 8.8 : F32),4.2,1.5}
    case 4: R.Vec{(0.0 - 2.0 : F32),6.8,(0.0 - 1.5 : F32)}
    case _: R.Vec{13.2,3.5,(0.0 - 2.5 : F32)}
