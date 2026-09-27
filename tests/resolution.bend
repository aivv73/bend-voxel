import Base
import ../src/resolution.bend as R

def check(ok: Bool, label: String) -> IO(Unit):
  match ok:
    case True{}: IO.print("PASS " ++ label)
    case False{}: IO.die(Unit,1,"FAIL " ++ label)

def accepts.result(r: Maybe<&2,R.Size>, width: U32, height: U32) -> Bool:
  match r:
    case Some{R.Size{w,h}}: (U32.is_eq(w,width) && U32.is_eq(h,height))
    case None{}: False{}
def accepts(s: String, width: U32, height: U32) -> Bool:
  accepts.result(R.parse(s),width,height)
def rejects.result(r: Maybe<&2,R.Size>) -> Bool:
  match r:
    case Some{_}: False{}
    case None{}: True{}
def rejects(s: String) -> Bool:
  rejects.result(R.parse(s))

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- check(accepts("640x360",640,360),"default resolution parses")
    Unit <- check(accepts("1920x1080",1920,1080),"HD resolution parses")
    Unit <- check(accepts("3440x1440",3440,1440),"ultrawide resolution parses")
    Unit <- check(accepts("7680x1080",7680,1080),"wide 4K-pixel limit parses")
    Unit <- check(rejects("1920X1080"),"separator is lowercase x")
    Unit <- check(rejects("1920x"),"height is required")
    Unit <- check(rejects("1920x1080x1"),"extra dimensions are rejected")
    Unit <- check(rejects("1920x10p0"),"non-digits are rejected")
    Unit <- check(rejects("639x360"),"minimum width is enforced")
    Unit <- check(rejects("3840x2161"),"pixel limit is enforced")
    IO.print("ALL RESOLUTION CHECKS PASSED")
