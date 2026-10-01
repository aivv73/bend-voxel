import Base
import ./schedule_float.bend as F

type Camera is Data:
  Camera{eye: List<&2,U32>, yaw: U32, pitch: U32}
type Frame is Data:
  Frame{id: String, camera: Camera, ray: Bool, origin: List<&2,U32>, direction: List<&2,U32>, pick: Maybe<&2,U32>, actions: List<&2,String>}
type Action is Data:
  Action{frame: String, id: String, required: Bool, target: List<&2,U32>, hit: Maybe<&2,F.Expr>}
type Review is Data:
  Review{name: String, frame: String, features: List<&2,String>}
type Supplementary is Data:
  Supplementary{frame: String, camera: Camera, action: Maybe<&2,String>, original: String, features: List<&2,String>}
type Frozen is Data:
  Frozen{warmup: U32, expected: U32, frames: List<&2,Frame>, reviews: List<&2,Review>, details: List<&2,Supplementary>, actions: List<&2,Action>}
type Header is Data:
  Header{warmup: U32, expected: U32}
type Report is Data:
  Report{frames: U32, actions: U32, maximum: U32}

type UnicodeState is Data:
  UnicodeState{remaining: U32, value: U32, minimum: U32}
type UnicodeStep is Data:
  UnicodeStep{state: UnicodeState, output: Maybe<&2,U32>}

def require(ok: Bool, message: String) -> Result<&2,&2,String,Unit>:
  match ok:
    case True{}: Done{Unit{}}
    case False{}: Fail{message}

def checked(ok: Bool, message: String) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit,Unit{})
    case False{}: IO.die(Unit,2,message)

def digit.show(+n: U32) -> String:
  SCon{Chr{(n + Bool.pick(U32,(n < 10 : U32),48,87) : U32)},SNil{}}

def digit(+c: U32) -> Maybe<&2,U32>:
  Bool.pick(Maybe<&2,U32>,((c >= 48) && (c <= 57) : U32),Some{(c - 48 : U32)},
    Bool.pick(Maybe<&2,U32>,((c >= 97) && (c <= 102) : U32),Some{(c - 87 : U32)},
      Bool.pick(Maybe<&2,U32>,((c >= 65) && (c <= 70) : U32),Some{(c - 55 : U32)},None{})))

def text.hex(text: String) -> Maybe<&2,String>:
  match text:
    case SNil{}: Some{SNil{}}
    case SCon{Chr{a},SCon{Chr{b},rest}}:
      do Maybe<&2,String>:
        a : U32 <- digit(a)
        b : U32 <- digit(b)
        rest : String <- text.hex(rest)
        return SCon{Chr{(a * 16 + b : U32)},rest}
    case _: None{}

def scalar.hex(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{+c},rest}:
      digit.show(((c >> 4n : U32) .&. 15 : U32)) ++ digit.show((c .&. 15 : U32)) ++ scalar.hex(rest)

def scalar(text: String) -> String:
  "s" ++ scalar.hex(text)

def text(token: String) -> Maybe<&2,String>:
  match token:
    case SCon{Chr{115},rest}: text.hex(rest)
    case SCon{Chr{105},rest}: Some{rest}
    case SCon{Chr{102},rest}: text.hex(rest)
    case _: None{}

def number.step(valid: Bool, next: Unit -> Maybe<&2,U32>) -> Maybe<&2,U32>:
  match valid:
    case False{}: None{}
    case True{}: next(Unit{})

def number.digits(s: String, +acc: U32) -> Maybe<&2,U32>:
  match s:
    case SNil{}: Some{acc}
    case SCon{Chr{+c},rest}:
      number.step((((c >= 48) && (c <= 57)) && (acc <= ((4294967295 - (c - 48 : U32) : U32) / 10 : U32)) : U32),_ => number.digits(rest,(acc * 10 + c - 48 : U32)))

def number.parsed(parsed: Maybe<&2,U32>, message: String, empty: Bool) -> Result<&2,&2,String,U32>:
  match parsed:
    case None{}: Fail{message}
    case Some{n}:
      do Result<&2,&2,String,U32>:
        _ : Unit <- require(Bool.not(empty),message)
        return n

def number.text(parsed: Maybe<&2,String>, message: String) -> Result<&2,&2,String,U32>:
  match parsed:
    case None{}: Fail{message}
    case Some{+s}: number.parsed(number.digits(String.trim(s),0),message,String.is_empty(String.trim(s)))

def number(token: String, message: String) -> Result<&2,&2,String,U32>:
  number.text(text(token),message)

def parsed.number(result: Result<&2,&2,String,U32>) -> IO(U32):
  match result:
    case Fail{message}: IO.die(U32,2,message)
    case Done{n}: IO.pure(U32,n)

def binary32.digit(d: Maybe<&2,U32>, next: U32 -> Result<&2,&2,String,U32>) -> Result<&2,&2,String,U32>:
  match d:
    case None{}: Fail{"malformed frozen binary32"}
    case Some{d}: next(d)

def binary32.hex(s: String, count: Nat, +acc: U32) -> Result<&2,&2,String,U32>:
  match s count:
    case SNil{} 0n:
      do Result<&2,&2,String,U32>:
        _ : Unit <- require(U32.is_ne((acc .&. 2139095040 : U32),2139095040),"nonfinite frozen binary32")
        return acc
    case SCon{Chr{c},rest} 1n+p:
      binary32.digit(digit(c),d => binary32.hex(rest,p,(acc * 16 + d : U32)))
    case _ _: Fail{"malformed frozen binary32"}

def binary32.text(parsed: Maybe<&2,String>) -> Result<&2,&2,String,U32>:
  match parsed:
    case Some{SCon{Chr{48},SCon{Chr{120},rest}}}: binary32.hex(rest,8n,0)
    case _: Fail{"malformed frozen binary32"}

def binary32(token: String) -> Result<&2,&2,String,U32>:
  binary32.text(text(token))

def magnitude(n: U32) -> U32: (n .&. 2147483647 : U32)

def maximum(xs: List<&2,U32>, acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case n <> rest: maximum(rest,U32.max(acc,magnitude(n)))

def hex.word(fuel: Nat, +n: U32) -> String:
  match fuel:
    case 0n: ""
    case 1n+p: hex.word(p,(n >> 4n : U32)) ++ digit.show((n .&. 15 : U32))

def exact(+word: U32) -> F.Expr:
  +exp = ((word >> 23n : U32) .&. 255 : U32)
  mantissa = ((word .&. 8388607 : U32) + Bool.pick(U32,U32.is_eq(exp,0),0,8388608) : U32)
  sign = Bool.pick(String,U32.is_eq((word .&. 2147483648 : U32),0),"","-")
  power = Bool.pick(String,(exp >= 150 : U32),U32.show((exp - 150 : U32)),"-" ++ U32.show(Bool.pick(U32,U32.is_eq(exp,0),149,(150 - exp : U32))))
  F.Literal{sign ++ "0x" ++ hex.word(6n,mantissa) ++ "p" ++ power}

def decimal.finite(parsed: Maybe<&2,F32>, literal: String) -> Result<&2,&2,String,F.Expr>:
  match parsed:
    case None{}: Fail{"required edit target outside strict reach"}
    case Some{x}:
      do Result<&2,&2,String,F.Expr>:
        _ : Unit <- require(U32.is_ne((F32.bits(x) .&. 2139095040 : U32),2139095040),"required edit target outside strict reach")
        return F.Literal{literal}

def decimal.digit(+c: U32) -> Bool:
  ((c >= 48) && (c <= 57) : U32)
def decimal.cleaned(parsed: Maybe<&2,String>) -> Result<&2,&2,String,F.Expr>:
  match parsed:
    case None{}: Fail{"required edit target outside strict reach"}
    case Some{+s}: decimal.finite(F32.read(s),s)
def decimal.underscore(valid: Bool, next: Unit -> Maybe<&2,String>) -> Maybe<&2,String>:
  match valid:
    case False{}: None{}
    case True{}: next(Unit{})
def decimal.clean(s: String, previous: Bool) -> Maybe<&2,String>:
  match s:
    case SNil{}: Some{SNil{}}
    case SCon{Chr{95},SCon{Chr{+c},rest}}:
      decimal.underscore(Bool.and(previous,decimal.digit(c)),_ =>
        do Maybe<&2,String>:
          tail : String <- decimal.clean(rest,True{})
          return SCon{Chr{c},tail})
    case SCon{Chr{95},SNil{}}: None{}
    case SCon{Chr{+c},rest}:
      do Maybe<&2,String>:
        tail : String <- decimal.clean(rest,decimal.digit(c))
        return SCon{Chr{c},tail}

def unicode.decimal(blocks: List<&2,U32>, +c: U32) -> U32:
  match blocks:
    case Nil{}: c
    case +zero <> rest:
      Bool.pick(U32,((c >= zero) && (c <= (zero + 9 : U32)) : U32),(48 + c - zero : U32),unicode.decimal(rest,c))

# Decimal digit blocks and float whitespace follow Python's Unicode 16.0.0 database.
def unicode.space(+c: U32) -> Bool:
  ((c >= 8192) && (c <= 8202) : U32) || U32.is_eq(c,133) || U32.is_eq(c,160) || U32.is_eq(c,5760) || U32.is_eq(c,8232) || U32.is_eq(c,8233) || U32.is_eq(c,8239) || U32.is_eq(c,8287) || U32.is_eq(c,12288)
def unicode.non_ascii(+c: U32) -> U32:
  Bool.pick(U32,unicode.space(c),32,unicode.decimal([48,1632,1776,1984,2406,2534,2662,2790,2918,3046,3174,3302,3430,3558,3664,3792,3872,4160,4240,6112,6160,6470,6608,6784,6800,6992,7088,7232,7248,42528,43216,43264,43472,43504,43600,44016,65296,66720,68912,68928,69734,69872,69942,70096,70384,70736,70864,71248,71360,71376,71386,71472,71904,72016,72688,72784,73040,73120,73552,90416,92768,92864,93008,93552,118000,120782,120792,120802,120812,120822,123200,123632,124144,124401,125264,130032],c))
def unicode.ascii(ascii: Bool, c: U32) -> U32:
  match ascii:
    case True{}: c
    case False{}: unicode.non_ascii(c)
def unicode.codepoint(+c: U32) -> U32:
  unicode.ascii((c < 128 : U32),c)
def unicode.scalar(+c: U32, minimum: U32) -> Bool:
  ((c >= minimum) && (c <= 1114111) && ((c < 55296) || (c > 57343)) : U32)
def unicode.leading(+c: U32) -> Maybe<&2,UnicodeStep>:
  Bool.pick(Maybe<&2,UnicodeStep>,(c < 128 : U32),Some{UnicodeStep{UnicodeState{0,0,0},Some{c}}},
    Bool.pick(Maybe<&2,UnicodeStep>,((c >= 194) && (c <= 223) : U32),Some{UnicodeStep{UnicodeState{1,(c .&. 31 : U32),128},None{}}},
      Bool.pick(Maybe<&2,UnicodeStep>,((c >= 224) && (c <= 239) : U32),Some{UnicodeStep{UnicodeState{2,(c .&. 15 : U32),2048},None{}}},
        Bool.pick(Maybe<&2,UnicodeStep>,((c >= 240) && (c <= 244) : U32),Some{UnicodeStep{UnicodeState{3,(c .&. 7 : U32),65536},None{}}},None{}))))
def unicode.complete(valid: Bool, c: U32) -> Maybe<&2,UnicodeStep>:
  match valid:
    case False{}: None{}
    case True{}: Some{UnicodeStep{UnicodeState{0,0,0},Some{c}}}
def unicode.remaining(done: Bool, count: U32, +value: U32, minimum: U32) -> Maybe<&2,UnicodeStep>:
  match done:
    case False{}: Some{UnicodeStep{UnicodeState{(count - 1 : U32),value,minimum},None{}}}
    case True{}: unicode.complete(unicode.scalar(value,minimum),value)
def unicode.trailing(valid: Bool, +count: U32, value: U32, minimum: U32, c: U32) -> Maybe<&2,UnicodeStep>:
  match valid:
    case False{}: None{}
    case True{}: unicode.remaining(U32.is_eq(count,1),count,(value * 64 + (c .&. 63 : U32) : U32),minimum)
def unicode.step.choose(start: Bool, count: U32, value: U32, minimum: U32, +c: U32) -> Maybe<&2,UnicodeStep>:
  match start:
    case True{}: unicode.leading(c)
    case False{}: unicode.trailing(((c >= 128) && (c <= 191) : U32),count,value,minimum,c)
def unicode.step(state: UnicodeState, c: U32) -> Maybe<&2,UnicodeStep>:
  match state:
    case UnicodeState{+count,value,minimum}: unicode.step.choose(U32.is_eq(count,0),count,value,minimum,c)
def unicode.advance(step: UnicodeStep, acc: String, next: UnicodeState -> String -> Maybe<&2,String>) -> Maybe<&2,String>:
  match step:
    case UnicodeStep{state,None{}}: next(state,acc)
    case UnicodeStep{state,Some{c}}: next(state,SCon{Chr{unicode.codepoint(c)},acc})
def unicode.end(state: UnicodeState, acc: String) -> Maybe<&2,String>:
  match state:
    case UnicodeState{count,_,_}: Bool.pick(Maybe<&2,String>,U32.is_eq(count,0),Some{String.reverse(acc)},None{})
def unicode.loop(s: String, state: UnicodeState, acc: String) -> Maybe<&2,String>:
  match s:
    case SNil{}: unicode.end(state,acc)
    case SCon{Chr{c},rest}:
      do Maybe<&2,String>:
        step : UnicodeStep <- unicode.step(state,c)
        unicode.advance(step,acc,state => acc => unicode.loop(rest,state,acc))
def unicode.normalize(s: String) -> Maybe<&2,String>:
  unicode.loop(s,UnicodeState{0,0,0},SNil{})

def decimal.normalized(parsed: Maybe<&2,String>) -> Result<&2,&2,String,F.Expr>:
  match parsed:
    case None{}: Fail{"required edit target outside strict reach"}
    case Some{s}: decimal.cleaned(decimal.clean(String.trim(s),False{}))

def decimal.text(parsed: Maybe<&2,String>) -> Result<&2,&2,String,F.Expr>:
  match parsed:
    case Some{s}: decimal.normalized(unicode.normalize(s))
    case None{}: Fail{"required edit target outside strict reach"}

def decimal(token: String) -> Result<&2,&2,String,F.Expr>:
  match token:
    case "b0": Done{F.Literal{"0.0"}}
    case "b1": Done{F.Literal{"1.0"}}
    case token: decimal.text(text(token))

def nonpositive(+text: String) -> Bool:
  Bool.or(String.starts_with(text,"-"),String.eq(text,"0x0p+0"))

def list(token: String) -> Result<&2,&2,String,List<&2,String>>:
  match token:
    case "l": Done{Nil{}}
    case SCon{Chr{108},rest}: Done{String.split(rest,',')}
    case _: Fail{"malformed frozen list"}

def records(~A: Data, ~parse: String -> Result<&2,&2,String,A>, lines: List<&2,String>) -> Result<&2,&2,String,List<&2,A>>:
  match lines:
    case Nil{}: Done{Nil{}}
    case line <> rest:
      do Result<&2,&2,String,List<&2,A>>:
        x : A <- parse(line)
        rest : List<&2,A> <- records(~A,~parse,rest)
        return x <> rest

def vector(token: String) -> Result<&2,&2,String,List<&2,U32>>:
  do Result<&2,&2,String,List<&2,U32>>:
    xs : List<&2,String> <- list(token)
    records(~U32,~binary32,xs)

def vector.three(xs: List<&2,U32>) -> Bool:
  Nat.is_eq(List.length(&2,U32,xs),3n)

def camera(eye: String, yaw: String, pitch: String) -> Result<&2,&2,String,Camera>:
  do Result<&2,&2,String,Camera>:
    +eye : List<&2,U32> <- vector(eye)
    _ : Unit <- require(vector.three(eye),"malformed frozen camera")
    yaw : U32 <- binary32(yaw)
    pitch : U32 <- binary32(pitch)
    return Camera{eye,yaw,pitch}

def truth(token: String) -> Bool:
  match token:
    case "n": False{}
    case "b0": False{}
    case "i0": False{}
    case "s": False{}
    case "l": False{}
    case "f302e30": False{}
    case "f2d302e30": False{}
    case "x": False{}
    case _: True{}

def pick.checked(ignored: Bool, token: String) -> Result<&2,&2,String,Maybe<&2,U32>>:
  match ignored:
    case True{}: Done{None{}}
    case False{}:
      do Result<&2,&2,String,Maybe<&2,U32>>:
        n : U32 <- binary32(token)
        return Some{n}
def pick(+kind: String, token: String) -> Result<&2,&2,String,Maybe<&2,U32>>:
  pick.checked((String.eq(kind,"n") || String.eq(kind,"s30")),token)

def optional.hit(kind: String, token: String) -> Result<&2,&2,String,Maybe<&2,F.Expr>>:
  match kind:
    case "n": Done{None{}}
    case "b":
      do Result<&2,&2,String,Maybe<&2,F.Expr>>:
        n : U32 <- binary32(token)
        return Some{exact(n)}
    case "d":
      do Result<&2,&2,String,Maybe<&2,F.Expr>>:
        x : F.Expr <- decimal(token)
        return Some{x}
    case _: Fail{"malformed frozen edit hit"}

def camera.maximum(c: Camera) -> U32:
  match c:
    case Camera{eye,_,_}: maximum(eye,0)

# These are the last binary32 words below the binary64 pi + 1e-6 and pi/2 + 1e-6 limits.
def camera.valid(c: Camera) -> Bool:
  match c:
    case Camera{_,yaw,pitch}:
      ((magnitude(yaw) <= 1078530014) && (magnitude(pitch) <= 1070141411) : U32)

def within(xs: List<&2,U32>, limit: U32) -> Bool:
  (maximum(xs,0) <= limit : U32)

def reach(+n: U32) -> Bool:
  ((magnitude(n) < 1132462080) && (U32.is_eq((n .&. 2147483648 : U32),0) || U32.is_eq(magnitude(n),0)) : U32)

def frame.pick(pick: Maybe<&2,U32>) -> Bool:
  match pick:
    case None{}: True{}
    case Some{n}: reach(n)

def ray.delta(direction: List<&2,U32>) -> F.Expr:
  match direction:
    case x <> y <> z <> Nil{}:
      +a = {exact(x) : F.Expr}
      +b = {exact(y) : F.Expr}
      +c = {exact(z) : F.Expr}
      F.Sub{F.Sum3{F.Mul{a,a},F.Mul{b,b},F.Mul{c,c}},F.Literal{"1.0"}}
    case _: F.Literal{"2.0"}

def ray.valid(direction: List<&2,U32>) -> IO(Bool):
  +delta = {ray.delta(direction) : F.Expr}
  do IO<Bool>:
    residual : String <- F.evaluate(F.Sub{F.Max{delta,F.Sub{F.Literal{"0.0"},delta}},F.Literal{"2e-6"}})
    return nonpositive(residual)

def hit.valid(hit: Maybe<&2,F.Expr>) -> IO(Bool):
  match hit:
    case None{}: IO.pure(Bool,True{})
    case Some{+x}:
      do IO<Bool>:
        negative : String <- F.evaluate(F.Sub{F.Literal{"0.0"},x})
        +upper : String <- F.evaluate(F.Sub{x,F.Literal{"256.0"}})
        return Bool.and(nonpositive(negative),Bool.and(nonpositive(upper),Bool.not(String.eq(upper,"0x0p+0"))))

def frame.tokens(tokens: List<&2,String>) -> Result<&2,&2,String,Frame>:
  match tokens:
    case "F" <> id <> eye <> yaw <> pitch <> +ray <> origin <> direction <> kind <> distance <> actions <> Nil{}:
      do Result<&2,&2,String,Frame>:
        cam : Camera <- camera(eye,yaw,pitch)
        +origin : List<&2,U32> <- vector(origin)
        +direction : List<&2,U32> <- vector(direction)
        _ : Unit <- require((String.eq(ray,"b0") || String.eq(ray,"b1")),"malformed frozen ray")
        _ : Unit <- require((String.eq(ray,"b0") || vector.three(origin)),"malformed frozen ray origin")
        _ : Unit <- require((String.eq(ray,"b0") || vector.three(direction)),"frozen ray direction invalid")
        pick : Maybe<&2,U32> <- pick(kind,distance)
        actions : List<&2,String> <- list(actions)
        return Frame{id,cam,String.eq(ray,"b1"),origin,direction,pick,actions}
    case _: Fail{"malformed frozen frame"}

def frame(line: String) -> Result<&2,&2,String,Frame>:
  frame.tokens(String.split(line,' '))

def review.tokens(tokens: List<&2,String>) -> Result<&2,&2,String,Review>:
  match tokens:
    case "R" <> name <> frame <> features <> Nil{}:
      do Result<&2,&2,String,Review>:
        features : List<&2,String> <- list(features)
        return Review{name,frame,features}
    case _: Fail{"malformed frozen review"}

def review(line: String) -> Result<&2,&2,String,Review>:
  review.tokens(String.split(line,' '))

def supplementary.tokens(tokens: List<&2,String>) -> Result<&2,&2,String,Supplementary>:
  match tokens:
    case "S" <> frame <> eye <> yaw <> pitch <> +action <> original <> features <> Nil{}:
      do Result<&2,&2,String,Supplementary>:
        camera : Camera <- camera(eye,yaw,pitch)
        features : List<&2,String> <- list(features)
        return Supplementary{frame,camera,Bool.pick(Maybe<&2,String>,String.eq(action,"n"),None{},Some{action}),original,features}
    case _: Fail{"malformed frozen supplementary view"}

def supplementary(line: String) -> Result<&2,&2,String,Supplementary>:
  supplementary.tokens(String.split(line,' '))

def action.tokens(tokens: List<&2,String>) -> Result<&2,&2,String,Action>:
  match tokens:
    case "A" <> frame <> id <> required <> target <> kind <> hit <> Nil{}:
      do Result<&2,&2,String,Action>:
        +target : List<&2,U32> <- vector(target)
        _ : Unit <- require(vector.three(target),"malformed frozen edit target")
        hit : Maybe<&2,F.Expr> <- optional.hit(kind,hit)
        return Action{frame,id,truth(required),target,hit}
    case _: Fail{"malformed frozen action"}

def action(line: String) -> Result<&2,&2,String,Action>:
  action.tokens(String.split(line,' '))

def header.tokens(tokens: List<&2,String>) -> Result<&2,&2,String,Header>:
  match tokens:
    case "v1" <> warmup <> measured <> Nil{}:
      do Result<&2,&2,String,Header>:
        +w : U32 <- number(warmup,"unsupported frozen frame count")
        +m : U32 <- number(measured,"unsupported frozen frame count")
        _ : Unit <- require((w <= 4294967293 : U32),"unsupported frozen frame count")
        _ : Unit <- require((m <= (4294967293 - w : U32) : U32),"unsupported frozen frame count")
        return Header{w,(1 + w + m : U32)}
    case _: Fail{"malformed frozen admission header"}

def header(line: String) -> Result<&2,&2,String,Header>:
  header.tokens(String.split(line,' '))

def section.lines(+s: String) -> List<&2,String>:
  Bool.pick(List<&2,String>,String.is_empty(s),Nil{},String.split(s,'|'))

def assemble(h: Header, fs: List<&2,Frame>, rs: List<&2,Review>, ds: List<&2,Supplementary>, acts: List<&2,Action>) -> Frozen:
  match h:
    case Header{w,n}: Frozen{w,n,fs,rs,ds,acts}

def parse.lines(lines: List<&2,String>) -> Result<&2,&2,String,Frozen>:
  match lines:
    case h <> fs <> rs <> ds <> acts <> Nil{}:
      do Result<&2,&2,String,Frozen>:
        p : Header <- header(h)
        fs : List<&2,Frame> <- records(~Frame,~frame,section.lines(fs))
        rs : List<&2,Review> <- records(~Review,~review,section.lines(rs))
        ds : List<&2,Supplementary> <- records(~Supplementary,~supplementary,section.lines(ds))
        acts : List<&2,Action> <- records(~Action,~action,section.lines(acts))
        return assemble(p,fs,rs,ds,acts)
    case _: Fail{"malformed frozen admission request"}

def parse(input: String) -> Result<&2,&2,String,Frozen>:
  parse.lines(String.split(input,'\n'))

def member(+id: String, xs: List<&2,String>) -> Bool:
  match xs:
    case Nil{}: False{}
    case x <> rest: Bool.or(String.eq(id,x),member(id,rest))

def subset(xs: List<&2,String>, +ys: List<&2,String>) -> Bool:
  match xs:
    case Nil{}: True{}
    case x <> rest: Bool.and(member(x,ys),subset(rest,ys))

def frame.actions.choose(zero: Bool, acts: List<&2,String>, next: Unit -> List<&2,String>) -> List<&2,String>:
  match zero:
    case True{}: acts
    case False{}: next(Unit{})

def frame.actions(xs: List<&2,Frame>, +n: U32) -> List<&2,String>:
  match xs:
    case Nil{}: Nil{}
    case Frame{_,_,_,_,_,_,acts} <> rest:
      frame.actions.choose(U32.is_eq(n,0),acts,_ => frame.actions(rest,(n - 1 : U32)))

def action.bound(action: Maybe<&2,String>, xs: List<&2,String>) -> Bool:
  match action:
    case None{}: True{}
    case Some{id}: member(id,xs)

def bound.choose(same: Bool, +frame: String, +features: List<&2,String>, other: String, allowed: List<&2,String>, next: Unit -> Bool) -> Bool:
  match same:
    case True{}: Bool.and(String.eq(frame,other),subset(features,allowed))
    case False{}: next(Unit{})

def bound(+original: String, +frame: String, +features: List<&2,String>, xs: List<&2,Review>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Review{name,other,allowed} <> rest:
      bound.choose(String.eq(original,name),frame,features,other,allowed,_ => bound(original,frame,features,rest))

def frames.check(xs: List<&2,Frame>, +index: U32, acc: U32) -> IO(U32):
  match xs:
    case Nil{}: IO.pure(U32,acc)
    case Frame{id,+cam,has_ray,origin,direction,pick,_} <> rest:
      do IO<U32>:
        checked(String.eq(id,scalar(U32.show(index))),"frozen frame order mismatch")
        checked(camera.valid(cam),"frozen camera angle outside supported range")
        checked((camera.maximum(cam) <= 1157627904 : U32),"frozen camera outside supported numeric envelope")
        checked(within(origin,1157627904),"frozen ray origin outside supported numeric envelope")
        ray : Bool <- Bool.pick(IO(Bool),Bool.not(has_ray),IO.pure(Bool,True{}),ray.valid(direction))
        checked(ray,"frozen ray direction invalid")
        checked(frame.pick(pick),"required picking result outside strict reach")
        frames.check(rest,(index + 1 : U32),U32.max(acc,camera.maximum(cam)))

def details.check(xs: List<&2,Supplementary>, +n: U32, +fs: List<&2,Frame>, +rs: List<&2,Review>, +seen: List<&2,String>, acc: U32) -> IO(U32):
  match xs:
    case Nil{}: IO.pure(U32,acc)
    case Supplementary{+frame,+cam,action,original,features} <> rest:
      do IO<U32>:
        +f : U32 <- parsed.number(number(frame,"invalid supplementary frame"))
        checked(Bool.and((f < n : U32),Bool.not(member(scalar(U32.show(f)),seen))),"invalid supplementary frame")
        checked(Bool.and(camera.valid(cam),(camera.maximum(cam) <= 1157627904 : U32)),"supplementary camera outside supported envelope")
        checked(action.bound(action,frame.actions(fs,f)),"supplementary action missing from its frame")
        checked(bound(original,frame,features,rs),"supplementary view does not bind an original feature")
        details.check(rest,n,fs,rs,scalar(U32.show(f)) <> seen,U32.max(acc,camera.maximum(cam)))

def actions.check(xs: List<&2,Action>, +w: U32, +n: U32, +fs: List<&2,Frame>, +seen: List<&2,String>, count: U32) -> IO(U32):
  match xs:
    case Nil{}: IO.pure(U32,count)
    case Action{frame,+id,required,target,hit} <> rest:
      do IO<U32>:
        checked(required,"frozen action silently optional")
        +f : U32 <- parsed.number(number(frame,"frozen action missing from its frame"))
        checked(((f > w) && (f < n) && member(id,frame.actions(fs,f)) : U32),"frozen action missing from its frame")
        +key : String = scalar(U32.show(f)) ++ ":" ++ id
        checked(Bool.not(member(key,seen)),"duplicate frozen action")
        checked(within(target,1149239296),"frozen edit target outside supported numeric envelope")
        valid : Bool <- hit.valid(hit)
        checked(valid,"required edit target outside strict reach")
        actions.check(rest,w,n,fs,key <> seen,(count + 1 : U32))

def admit(frozen: Frozen) -> IO(Report):
  match frozen:
    case Frozen{w,+n,+fs,rs,ds,acts}:
      do IO<Report>:
        checked(Nat.is_eq(List.length(&2,Frame,fs),U32.to_nat(n)),"unsupported frozen frame count")
        maximum : U32 <- frames.check(fs,0,0)
        maximum : U32 <- details.check(ds,n,fs,rs,Nil{},maximum)
        count : U32 <- actions.check(acts,w,n,fs,Nil{},0)
        return Report{n,count,maximum}
