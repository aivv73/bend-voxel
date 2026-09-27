import Base
import ../src/color.bend as Color
import ../src/math.bend as R

def check(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.print("PASS " ++ label)
    case False{}: IO.die(Unit,1,"FAIL " ++ label)

def close(a: F32, b: F32) -> Bool:
  (F32.abs((a - b : F32)) < 0.002 : F32)

def vec.close(a: R.Vec, b: R.Vec) -> Bool:
  R.Vec{ar,ag,ab} = a
  R.Vec{br,bg,bb} = b
  (close(ar,br) && close(ag,bg) && close(ab,bb))

def expected(+word: U32) -> R.Vec:
  R.Vec{Color.channel(word,65536),Color.channel(word,256),Color.channel(word,1)}

def changed(a: R.Vec, b: R.Vec) -> Bool:
  R.Vec{ar,ag,ab} = a
  R.Vec{br,bg,bb} = b
  ((F32.abs((ar - br : F32)) + F32.abs((ag - bg : F32)) +
    F32.abs((ab - bb : F32)) > 0.01) : F32)

# F32 transcendental operations are opaque to the proof normalizer; validate
# the actual compiled palette, including detached and overlay colors, here.
def palette.in_gamut(colors: List<&2,R.Vec>) -> Bool:
  match colors:
    case Nil{}: True{}
    case color <> rest: (Color.in_gamut(color) && palette.in_gamut(rest))

def palette.mapping(colors: List<&2,R.Vec>) -> Bool:
  match colors:
    case foundation <> _ <> concrete <> _ <> frame <> _ <> machinery <> _ <>
         plaster <> _ <> ground <> background <> background_display <>
         pale <> cyan <> accent <> reset <> protected <> preview <> Nil{}:
      (vec.close(foundation,Color.surface(Color.foundation(),False{})) &&
       vec.close(concrete,Color.surface(Color.concrete(),False{})) &&
       vec.close(frame,Color.surface(Color.frame(),False{})) &&
       vec.close(machinery,Color.surface(Color.machinery(),False{})) &&
       vec.close(plaster,Color.surface(Color.plaster(),False{})) &&
       vec.close(ground,Color.display_linear(1978429)) &&
       vec.close(background,Color.display_linear(1187886)) &&
       vec.close(background_display,Color.display(1187886)) &&
       vec.close(pale,Color.display(15198439)) &&
       vec.close(cyan,Color.display(10476509)) &&
       vec.close(accent,Color.display(16768872)) &&
       vec.close(reset,Color.display(4964772)) &&
       vec.close(protected,Color.display(16552594)) &&
       vec.close(preview,Color.quantize(Color.display(16768872))))
    case _: False{}

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(vec.close(Color.encode(Color.surface(Color.foundation(),False{})),expected(4964772)),
      "foundation keeps its authored color")
    Unit <- check(vec.close(Color.encode(Color.surface(Color.concrete(),False{})),expected(13737320)),
      "concrete keeps its authored color")
    Unit <- check(vec.close(Color.encode(Color.surface(Color.frame(),False{})),expected(6721452)),
      "frame keeps its authored color")
    Unit <- check(vec.close(Color.encode(Color.surface(Color.machinery(),False{})),expected(14259535)),
      "machinery keeps its authored color")
    Unit <- check(changed(Color.surface(Color.concrete(),False{}),
      Color.surface(Color.concrete(),True{})),"detachment changes appearance")
    Unit <- check(Color.in_gamut(Color.to_linear(Color.Oklch{0.7,0.5,30.0})),
      "out-of-gamut chroma is reduced")
    Unit <- check(vec.close(Color.encode(Color.display_linear(1978429)),expected(1978429)),
      "ground display color round trips")
    Unit <- check(palette.mapping(Color.palette()),"native palette uses material ID order")
    Unit <- check(palette.in_gamut(Color.palette()),"every palette channel is finite and in gamut")
    IO.print("ALL BEND COLOR CHECKS PASSED")
