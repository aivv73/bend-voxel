import Base
import ./math.bend as R

# Material colors are authored in OKLCH and sent to Vulkan as linear RGB.
type Oklch is Data:
  Oklch{lightness: F32, chroma: F32, hue: F32}

def cube(+x: F32) -> F32:
  (x * x * x : F32)

# Bjorn Ottosson's D65 Oklab to linear sRGB transform.
def raw(color: Oklch) -> R.Vec:
  Oklch{+lightness,+chroma,+hue} = color
  +radians = (hue * 0.017453292519943295 : F32)
  +a = (chroma * F32.cos(radians) : F32)
  +b = (chroma * F32.sin(radians) : F32)
  +l = cube((lightness + 0.3963377774 * a + 0.2158037573 * b : F32))
  +m = cube((lightness - 0.1055613458 * a - 0.0638541728 * b : F32))
  +s = cube((lightness - 0.0894841775 * a - 1.2914855480 * b : F32))
  R.Vec{(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s : F32),
    (0.0 - 1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s : F32),
    (0.0 - 0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s : F32)}

def in_gamut(color: R.Vec) -> Bool:
  R.Vec{+r,+g,+b} = color
  ((r >= 0.0 && r <= 1.0 && g >= 0.0 && g <= 1.0 && b >= 0.0 && b <= 1.0) : F32)

def fit(steps: Nat, +lightness: F32, +hue: F32, +lo: F32, +hi: F32) -> F32:
  match steps:
    case 0n: lo
    case 1n+rest:
      +mid = ((lo + hi) * 0.5 : F32)
      +inside = in_gamut(raw(Oklch{lightness,mid,hue}))
      fit(rest,lightness,hue,R.pick(inside,mid,lo),R.pick(inside,hi,mid))

def clamp(color: R.Vec) -> R.Vec:
  R.Vec{r,g,b} = color
  R.Vec{R.clamp(r,0.0,1.0),R.clamp(g,0.0,1.0),R.clamp(b,0.0,1.0)}

def to_linear.choose(inside: Bool, first: R.Vec, +lightness: F32,
                     +chroma: F32, +hue: F32) -> R.Vec:
  match inside:
    case True{}: first
    case False{}:
      +best = fit(24n,lightness,hue,0.0,chroma)
      clamp(raw(Oklch{lightness,best,hue}))

def to_linear(color: Oklch) -> R.Vec:
  Oklch{+lightness,+chroma,+hue} = color
  +bounded = R.clamp(lightness,0.0,1.0)
  +first = raw(Oklch{bounded,chroma,hue})
  to_linear.choose(in_gamut(first),first,bounded,chroma,hue)

def foundation() -> Oklch: Oklch{0.736340,0.114340,173.8965}
def concrete() -> Oklch: Oklch{0.733411,0.093103,66.0436}
def frame() -> Oklch: Oklch{0.630974,0.062930,239.8232}
def machinery() -> Oklch: Oklch{0.723628,0.119039,64.7019}
def plaster() -> Oklch: Oklch{0.860000,0.018000,85.0000}

def surface(color: Oklch, detached: Bool) -> R.Vec:
  Oklch{+lightness,+chroma,+hue} = color
  match detached:
    case False{}: to_linear(Oklch{lightness,chroma,hue})
    case True{}:
      to_linear(Oklch{R.min(0.92,(lightness + 0.07 : F32)),
        (chroma * 0.72 : F32),hue})

def decode_channel(+value: F32) -> F32:
  R.pick((value <= 0.04045 : F32),(value / 12.92 : F32),
    F32.pow(((value + 0.055) / 1.055 : F32),2.4))

def encode_channel(+value: F32) -> F32:
  +bounded = R.clamp(value,0.0,1.0)
  R.pick((bounded <= 0.0031308 : F32),(12.92 * bounded : F32),
    (1.055 * F32.pow(bounded,(1.0 / 2.4 : F32)) - 0.055 : F32))

def encode(color: R.Vec) -> R.Vec:
  R.Vec{r,g,b} = color
  R.Vec{encode_channel(r),encode_channel(g),encode_channel(b)}

def channel(word: U32, divisor: U32) -> F32:
  (U32.to_f32(((word / divisor) % 256 : U32)) / 255.0 : F32)

def display(+word: U32) -> R.Vec:
  R.Vec{channel(word,65536),channel(word,256),channel(word,1)}

def decode(color: R.Vec) -> R.Vec:
  R.Vec{r,g,b} = color
  R.Vec{decode_channel(r),decode_channel(g),decode_channel(b)}

def display_linear(word: U32) -> R.Vec:
  decode(display(word))

def quantize_channel(value: F32) -> F32:
  (F32.floor((value * 255.0 : F32)) / 255.0 : F32)

def quantize(color: R.Vec) -> R.Vec:
  R.Vec{r,g,b} = color
  R.Vec{quantize_channel(r),quantize_channel(g),quantize_channel(b)}

# The bridge expects IDs 1..5 in anchored/detached pairs, then linear ground
# and background, followed by background, pale HUD, cyan HUD, gold accent,
# reset, protected aim, and quantized brush preview display colors.
def palette() -> List<&2,R.Vec>:
  [surface(foundation(),False{}),surface(foundation(),True{}),
   surface(concrete(),False{}),surface(concrete(),True{}),
   surface(frame(),False{}),surface(frame(),True{}),
   surface(machinery(),False{}),surface(machinery(),True{}),
   surface(plaster(),False{}),surface(plaster(),True{}),
   display_linear(1978429),display_linear(1187886),
   display(1187886),display(15198439),display(10476509),
   display(16768872),display(4964772),display(16552594),
   quantize(display(16768872))]
