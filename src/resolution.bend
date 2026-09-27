import Base

type Size is Data:
  Size{width: U32, height: U32}

def default() -> Size:
  Size{640,360}

def width(s: Size) -> U32:
  Size{w,_} = s
  w
def height(s: Size) -> U32:
  Size{_,h} = s
  h

# Keep the HUD legible and bound the color/depth buffers to 4K pixels.
def valid(+width: U32, +height: U32) -> Bool:
  ((width >= 640) && (height >= 360) && (width <= 7680) &&
    (height <= 4320) && (width * height <= 8294400 : U32) : U32)

def digits(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{head,tail}: (Char.is_digit(head) && digits(tail))

def part.digits(ok: Bool, s: String) -> Maybe<&2,U32>:
  match ok:
    case True{}: U32.read(s)
    case False{}: None{}

def part(s: String) -> Maybe<&2,U32>:
  match s:
    case SNil{}: None{}
    case +s: part.digits(digits(s),s)

def pair.valid(ok: Bool, width: U32, height: U32) -> Maybe<&2,Size>:
  match ok:
    case True{}: Some{Size{width,height}}
    case False{}: None{}

def pair(width: Maybe<&2,U32>, height: Maybe<&2,U32>) -> Maybe<&2,Size>:
  match width height:
    case Some{+w} Some{+h}: pair.valid(valid(w,h),w,h)
    case _ _: None{}

def parts(xs: List<&2,String>) -> Maybe<&2,Size>:
  match xs:
    case width <> height <> Nil{}: pair(part(width),part(height))
    case _: None{}

def parse(s: String) -> Maybe<&2,Size>:
  parts(String.split(s,Char.from_u32(120)))
