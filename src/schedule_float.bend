import Base

type Expr is Data:
  Literal{text: String}
  Add{a: Expr, b: Expr}
  Sub{a: Expr, b: Expr}
  Mul{a: Expr, b: Expr}
  Div{a: Expr, b: Expr}
  Pow2{x: Expr}
  Sqrt{x: Expr}
  Hypot{a: Expr, b: Expr}
  Atan2{a: Expr, b: Expr}
  Round32{x: Expr}
  Sin32{x: Expr}
  Cos32{x: Expr}
  Sqrt32{x: Expr}
  Sum3{a: Expr, b: Expr, c: Expr}
  Max{a: Expr, b: Expr}

type Vec is Data:
  Vec{x: Expr, y: Expr, z: Expr}

def encode(expr: Expr) -> String:
  match expr:
    case Literal{text}: text ++ " "
    case Add{a,b}: encode(a) ++ encode(b) ++ "add "
    case Sub{a,b}: encode(a) ++ encode(b) ++ "sub "
    case Mul{a,b}: encode(a) ++ encode(b) ++ "mul "
    case Div{a,b}: encode(a) ++ encode(b) ++ "div "
    case Pow2{x}: encode(x) ++ "pow2 "
    case Sqrt{x}: encode(x) ++ "sqrt "
    case Hypot{a,b}: encode(a) ++ encode(b) ++ "hypot "
    case Atan2{a,b}: encode(a) ++ encode(b) ++ "atan2 "
    case Round32{x}: encode(x) ++ "round32 "
    case Sin32{x}: encode(x) ++ "sin32 "
    case Cos32{x}: encode(x) ++ "cos32 "
    case Sqrt32{x}: encode(x) ++ "sqrt32 "
    case Sum3{a,b,c}: encode(a) ++ encode(b) ++ encode(c) ++ "sum3 "
    case Max{a,b}: encode(a) ++ encode(b) ++ "max "

def host(code: String, format: U32) -> IO(String):
  import "./schedule_float.c"
  import "./schedule_float.js"

def evaluate(expr: Expr) -> IO(String):
  host(encode(expr),0)

def bits(expr: Expr) -> IO(String):
  host(encode(expr),1)

def vector(v: Vec) -> IO(String):
  match v:
    case Vec{x,y,z}:
      do IO<String>:
        a : String <- bits(x)
        b : String <- bits(y)
        c : String <- bits(z)
        return "[" ++ a ++ "," ++ b ++ "," ++ c ++ "]"

def exact.vector(v: Vec) -> IO(String):
  match v:
    case Vec{x,y,z}:
      do IO<String>:
        a : String <- evaluate(x)
        b : String <- evaluate(y)
        c : String <- evaluate(z)
        return "[\"" ++ a ++ "\",\"" ++ b ++ "\",\"" ++ c ++ "\"]"

def delta(eye: Vec, look: Vec) -> Vec:
  match eye:
    case Vec{x,y,z}:
      match look:
        case Vec{a,b,c}: Vec{Sub{a,x},Sub{b,y},Sub{c,z}}

def camera.delta(eye: Vec, d: Vec) -> IO(String):
  match d:
    case Vec{+x,y,+z}:
      do IO<String>:
        position : String <- vector(eye)
        yaw : String <- bits(Atan2{x,z})
        pitch : String <- bits(Atan2{y,Hypot{x,z}})
        return "{\"eye_m\":" ++ position ++ ",\"pitch\":" ++ pitch ++ ",\"yaw\":" ++ yaw ++ "}"

def camera(+eye: Vec, look: Vec) -> IO(String):
  camera.delta(eye,delta(eye,look))

def ray_to.delta(eye: Vec, d: Vec) -> IO(String):
  match d:
    case Vec{+x,+y,+z}:
      +length = {Sqrt{Sum3{Mul{x,x},Mul{y,y},Mul{z,z}}} : Expr}
      do IO<String>:
        origin : String <- vector(eye)
        direction : String <- vector(Vec{Div{x,length},Div{y,length},Div{z,length}})
        return "{\"direction\":" ++ direction ++ ",\"origin_m\":" ++ origin ++ "}"

def ray_to(+eye: Vec, look: Vec) -> IO(String):
  ray_to.delta(eye,delta(eye,look))

def center.direction(+yaw: Expr, +pitch: Expr) -> Vec:
  Vec{Round32{Add{Round32{Mul{Sin32{yaw},Cos32{pitch}}},Literal{"0.0"}}},
      Round32{Add{Sin32{pitch},Literal{"0.0"}}},
      Round32{Add{Round32{Mul{Cos32{yaw},Cos32{pitch}}},Literal{"0.0"}}}}

def center.normalized(d: Vec) -> Vec:
  match d:
    case Vec{+x,+y,+z}:
      +length = {Sqrt32{Round32{Add{Round32{Add{Round32{Mul{x,x}},Round32{Mul{y,y}}}},Round32{Mul{z,z}}}}} : Expr}
      +inverse = {Round32{Div{Literal{"1.0"},length}} : Expr}
      Vec{Round32{Mul{x,inverse}},Round32{Mul{y,inverse}},Round32{Mul{z,inverse}}}

def center(eye: Vec, yaw: Expr, pitch: Expr) -> IO(String):
  do IO<String>:
    origin : String <- vector(eye)
    direction : String <- vector(center.normalized(center.direction(yaw,pitch)))
    return "{\"direction\":" ++ direction ++ ",\"origin_m\":" ++ origin ++ "}"
