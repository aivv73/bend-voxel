import Base

type Integer is Data:
  ScaleZero{}
  ScaleBit{low: Bool, high: Integer}

def Integer.bit(low: Bool, high: Integer) -> Integer:
  match low high:
    case False{} ScaleZero{}: ScaleZero{}
    case False{} ScaleBit{b,t}: ScaleBit{False{},ScaleBit{b,t}}
    case True{} _: ScaleBit{True{},high}

def Integer.zero() -> Integer: ScaleZero{}
def Integer.one() -> Integer: ScaleBit{True{},ScaleZero{}}
def Integer.two() -> Integer: ScaleBit{False{},Integer.one()}
def Integer.four() -> Integer: ScaleBit{False{},Integer.two()}
def Integer.five() -> Integer: ScaleBit{True{},Integer.two()}
def Integer.ten() -> Integer: ScaleBit{False{},Integer.five()}

def Integer.bits(n: Integer) -> Nat:
  match n:
    case ScaleZero{}: 0n
    case ScaleBit{b,t}: 1n+Integer.bits(t)

def Integer.cmp.fin(low: Cmp, high: Cmp) -> Cmp:
  match high:
    case LT{}: LT{}
    case EQ{}: low
    case GT{}: GT{}

def Integer.cmp(a: Integer, b: Integer) -> Cmp:
  match a b:
    case ScaleZero{} ScaleZero{}: EQ{}
    case ScaleZero{} ScaleBit{x,t}: LT{}
    case ScaleBit{x,t} ScaleZero{}: GT{}
    case ScaleBit{x,xt} ScaleBit{y,yt}:
      Integer.cmp.fin(Bool.cmp(x,y),Integer.cmp(xt,yt))

def Integer.eq(a: Integer, b: Integer) -> Bool:
  Cmp.is_eq(Integer.cmp(a,b))

def Integer.le(a: Integer, b: Integer) -> Bool:
  Cmp.is_le(Integer.cmp(a,b))

def Integer.carry.bit(result: Bool & Bool, continuation: Bool -> Integer) -> Integer:
  (digit,next) = result
  Integer.bit(digit,continuation(next))

def Integer.add.carry(a: Integer, b: Integer, carry: Bool) -> Integer:
  match a b:
    case ScaleZero{} ScaleZero{}: Integer.bit(carry,ScaleZero{})
    case ScaleZero{} ScaleBit{bb,bt}:
      Integer.carry.bit(Bool.full_add(False{},bb,carry),
        next => Integer.add.carry(ScaleZero{},bt,next))
    case ScaleBit{ab,at} ScaleZero{}:
      Integer.carry.bit(Bool.full_add(ab,False{},carry),
        next => Integer.add.carry(at,ScaleZero{},next))
    case ScaleBit{ab,at} ScaleBit{bb,bt}:
      Integer.carry.bit(Bool.full_add(ab,bb,carry),
        next => Integer.add.carry(at,bt,next))

def Integer.add(a: Integer, b: Integer) -> Integer:
  Integer.add.carry(a,b,False{})

def Integer.inc(a: Integer) -> Integer:
  Integer.add(a,Integer.one())

def Integer.sub.carry(a: Integer, b: Integer, carry: Bool) -> Integer:
  match a b:
    case ScaleZero{} _: ScaleZero{}
    case ScaleBit{ab,at} ScaleZero{}:
      Integer.carry.bit(Bool.full_add(ab,True{},carry),
        next => Integer.sub.carry(at,ScaleZero{},next))
    case ScaleBit{ab,at} ScaleBit{bb,bt}:
      Integer.carry.bit(Bool.full_add(ab,Bool.not(bb),carry),
        next => Integer.sub.carry(at,bt,next))

def Integer.sub(a: Integer, b: Integer) -> Integer:
  Integer.sub.carry(a,b,True{})

def Integer.distance(+a: Integer, +b: Integer) -> Integer:
  Bool.pick(Integer,Integer.le(a,b),Integer.sub(b,a),Integer.sub(a,b))

def Integer.double(a: Integer) -> Integer:
  Integer.bit(False{},a)

def Integer.half(a: Integer) -> Integer:
  match a:
    case ScaleZero{}: ScaleZero{}
    case ScaleBit{b,t}: t

def Integer.mul(a: Integer, +b: Integer) -> Integer:
  match a:
    case ScaleZero{}: ScaleZero{}
    case ScaleBit{False{},t}: Integer.double(Integer.mul(t,b))
    case ScaleBit{True{},t}: Integer.add(b,Integer.double(Integer.mul(t,b)))

def Integer.square(+a: Integer) -> Integer:
  Integer.mul(a,a)

def Integer.divmod.bit(low: Bool, +denominator: Integer,
                       qr: Integer & Integer) -> Integer & Integer:
  (q,r) = qr
  +next = Integer.bit(low,r)
  +enough = Integer.le(denominator,next)
  (Integer.bit(enough,q),
   Bool.pick(Integer,enough,Integer.sub(next,denominator),next))

def Integer.divmod(a: Integer, +b: Integer) -> Integer & Integer:
  match a:
    case ScaleZero{}: (ScaleZero{},ScaleZero{})
    case ScaleBit{low,t}: Integer.divmod.bit(low,b,Integer.divmod(t,b))

def Integer.mod(a: Integer, b: Integer) -> Integer:
  Pair.snd(Integer,Integer,Integer.divmod(a,b))

def Integer.to_u32(a: Integer) -> U32:
  match a:
    case ScaleZero{}: 0
    case ScaleBit{b,t}: (Bool.to_u32(b) + 2 * Integer.to_u32(t) : U32)

def Integer.from_u32(fuel: Nat, +a: U32) -> Integer:
  match fuel:
    case 0n: ScaleZero{}
    case 1n+p:
      Integer.bit(U32.is_ne((a .&. 1 : U32),0),Integer.from_u32(p,(a >> 1n : U32)))

def Integer.read.digit(acc: Integer, digit: U32, valid: Bool,
                       continuation: Integer -> Maybe<&2,Integer>) -> Maybe<&2,Integer>:
  match valid:
    case False{}: None{}
    case True{}:
      continuation(Integer.add(Integer.mul(acc,Integer.ten()),Integer.from_u32(4n,digit)))

def Integer.read.go(s: String, acc: Integer) -> Maybe<&2,Integer>:
  match s:
    case SNil{}: Some{acc}
    case SCon{Chr{c},t}:
      +digit = (c - 48 : U32)
      Integer.read.digit(acc,digit,U32.is_lt(digit,10),
        value => Integer.read.go(t,value))

def Integer.read(s: String) -> Maybe<&2,Integer>:
  match s:
    case SNil{}: None{}
    case SCon{h,t}: Integer.read.go(SCon{h,t},ScaleZero{})

def Integer.show.step(qr: Integer & Integer, acc: String,
                       continuation: Integer -> String -> String) -> String:
  (q,r) = qr
  digit = {Chr{(48 + Integer.to_u32(r) : U32)} : Char}
  continuation(q,SCon{digit,acc})

def Integer.show.go(fuel: Nat, value: Integer, acc: String) -> String:
  match fuel value:
    case _ ScaleZero{}: acc
    case 0n _: acc
    case 1n+p ScaleBit{b,t}:
      Integer.show.step(Integer.divmod(ScaleBit{b,t},Integer.ten()),acc,
        q => digits => Integer.show.go(p,q,digits))

def Integer.show(+a: Integer) -> String:
  match a:
    case ScaleZero{}: "0"
    case ScaleBit{b,t}: Integer.show.go(1n+Integer.bits(t),ScaleBit{b,t},SNil{})

def delayed(-A: Type, condition: Bool, yes: Unit -> A, no: Unit -> A) -> A:
  match condition:
    case True{}: yes(Unit{})
    case False{}: no(Unit{})

def sqrt.go(fuel: Nat, +target: Integer, +low: Integer, +high: Integer) -> Integer:
  match fuel:
    case 0n: low
    case 1n+ +p:
      +middle = Integer.half(Integer.add(low,high))
      delayed(Integer,Integer.eq(middle,low),u => low,u =>
        delayed(Integer,Integer.le(Integer.square(middle),target),
          u => sqrt.go(p,target,middle,high),u => sqrt.go(p,target,low,middle)))

def closest(+target: Integer, +lower: Integer, +upper: Integer, +twice: Bool) -> Integer:
  lower_area = Bool.pick(Integer,twice,Integer.double(Integer.square(lower)),Integer.square(lower))
  upper_area = Bool.pick(Integer,twice,Integer.double(Integer.square(upper)),Integer.square(upper))
  Bool.pick(Integer,Integer.le(Integer.distance(lower_area,target),Integer.distance(upper_area,target)),
    lower,upper)

def next_growth(+q: Integer) -> Integer:
  +target = Integer.double(Integer.square(q))
  +root = sqrt.go(2n+Integer.bits(q),target,q,Integer.double(q))
  closest(target,root,Integer.inc(root),False{})

def clamp(+a: Integer, +low: Integer, +high: Integer) -> Integer:
  Bool.pick(Integer,Integer.le(a,low),low,Bool.pick(Integer,Integer.le(high,a),high,a))

def midpoint_refinement(+low: Integer, +high: Integer) -> Maybe<&2,Integer>:
  delayed(Maybe<&2,Integer>,Integer.eq(Integer.inc(low),high),u => None{},u => (
    +target = Integer.add(Integer.square(low),Integer.square(high))
    +root = sqrt.go(2n+Integer.bits(high),Integer.half(target),low,high)
    +first = Integer.inc(low)
    +last = Integer.sub(high,Integer.one())
    Some{closest(target,clamp(root,first,last),clamp(Integer.inc(root),first,last),True{})}
  ))

def gcd(fuel: Nat, a: Integer, +b: Integer) -> Integer:
  match fuel b:
    case _ ScaleZero{}: a
    case 0n _: b
    case 1n+p ScaleBit{digit,tail}:
      gcd(p,ScaleBit{digit,tail},Integer.mod(a,ScaleBit{digit,tail}))

type StrideSearch is Data:
  Found{stride: Integer}
  Pending{next: Integer}

def history_stride.search(fuel: Nat, +count: Integer, state: StrideSearch) -> StrideSearch:
  match fuel state:
    case _ Found{stride}: Found{stride}
    case 0n Pending{+candidate}:
      co = gcd(2n+Nat.double(Integer.bits(count)),count,candidate)
      Bool.pick(StrideSearch,Integer.eq(co,Integer.one()),Found{candidate},Pending{Integer.inc(candidate)})
    case 1n+ +p Pending{candidate}:
      history_stride.search(p,count,history_stride.search(p,count,Pending{candidate}))

def history_stride.result(state: StrideSearch) -> Integer:
  match state:
    case Found{stride}: stride
    case Pending{next}: next

def history_stride(+count: Integer) -> Integer:
  history_stride.result(history_stride.search(Integer.bits(count),count,Pending{Integer.five()}))

def history_visit.prior(fuel: Nat, +count: Integer, +stride: Integer, +offset: Integer,
                        +neighborhood: Integer, +index: U32) -> U32:
  match fuel:
    case 0n: 0
    case 1n+p:
      visit = Integer.mod(Integer.add(Integer.mul(stride,Integer.from_u32(4n,index)),offset),count)
      (Bool.to_u32(Integer.eq(visit,neighborhood)) +
        history_visit.prior(p,count,stride,offset,neighborhood,(index + 1 : U32)) : U32)

def history_visit(+group: U32, +count: Integer, seed: U32) -> Integer & U32:
  +stride = history_stride(count)
  +offset = Integer.from_u32(1n,(seed - 45 : U32))
  +neighborhood = Integer.mod(Integer.add(Integer.mul(stride,Integer.from_u32(4n,group)),offset),count)
  prior = history_visit.prior(U32.to_nat(group),count,stride,offset,neighborhood,0)
  (neighborhood,prior)
