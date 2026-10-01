import Base
import ./megascene_scale.bend as Scale

def Field() -> Data: Sigma<&2,&2,String,_ => Value>

type Value is Data:
  Null{}
  Boolean{value: Bool}
  Number{text: String}
  Real{text: String, decimal: String}
  Text{value: String}
  Array{values: List<&2,Value>}
  Object{fields: List<&2,Field()>}
  Ratio{numerator: String, denominator: String}
  Error{message: String}
  Divide{left: Value, right: Value}

type Signed is Data:
  Sign{negative: Bool, magnitude: Scale.Integer}
type Rational is Data:
  Rational{numerator: Signed, denominator: Scale.Integer}

def require(ok: Bool, message: String) -> Result<&2,&2,String,Unit>:
  match ok:
    case True{}: Done{Unit{}}
    case False{}: Fail{message}
def string(value: String) -> Value: Text{value}
def number(value: String) -> Value: Number{value}
def boolean(value: Bool) -> Value: Boolean{value}
def object(value: List<&2,Field()>) -> Value: Object{value}
def fields(value: Value) -> List<&2,Field()>:
  match value:
    case Object{xs}: xs
    case _: Nil{}
def array(value: Value) -> List<&2,Value>:
  match value:
    case Array{xs}: xs
    case _: Nil{}
def text(value: Value) -> String:
  match value:
    case Text{s}: s
    case Number{s}: s
    case Real{s,_}: s
    case _: ""
def decimal_text(value: Value) -> String:
  match value:
    case Real{_,s}: s
    case value: text(value)
def bool(value: Value) -> Bool:
  match value:
    case Boolean{b}: b
    case _: False{}
def is_null(value: Value) -> Bool:
  match value:
    case Null{}: True{}
    case _: False{}
def is_text(value: Value) -> Bool:
  match value:
    case Text{_}: True{}
    case _: False{}
def is_bool(value: Value) -> Bool:
  match value:
    case Boolean{_}: True{}
    case _: False{}
def is_array(value: Value) -> Bool:
  match value:
    case Array{_}: True{}
    case _: False{}
def is_object(value: Value) -> Bool:
  match value:
    case Object{_}: True{}
    case _: False{}
def get.fields(xs: List<&2,Field()>, +key: String) -> Value:
  match xs:
    case Nil{}: Null{}
    case (name,value) <> rest:
      Bool.pick(Value,String.eq(name,key),value,get.fields(rest,key))
def get(value: Value, key: String) -> Value: get.fields(fields(value),key)
def has.fields(xs: List<&2,Field()>, +key: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case (name,value) <> rest: String.eq(name,key) || has.fields(rest,key)
def has(value: Value, key: String) -> Bool: has.fields(fields(value),key)
def required(+value: Value, +key: String) -> Result<&2,&2,String,Value>:
  do Result<&2,&2,String,Value>:
    _ : Unit <- require(has(value,key),"missing field:" ++ key)
    return get(value,key)
def exception_text(+message: String) -> String:
  Bool.pick(String,String.starts_with(message,"missing field:"),"'" ++ String.drop(message,14n) ++ "'",message)
def put.fields(xs: List<&2,Field()>, +key: String, +value: Value) -> List<&2,Field()>:
  match xs:
    case Nil{}: [(key,value)]
    case (+name,old) <> +rest:
      Bool.pick(List<&2,Field()>,String.eq(name,key),(key,value) <> rest,
        (name,old) <> put.fields(rest,key,value))
def put(value: Value, key: String, replacement: Value) -> Value:
  Object{put.fields(fields(value),key,replacement)}
def merge.fields(xs: List<&2,Field()>, value: Value) -> Value:
  match xs:
    case Nil{}: value
    case (key,replacement) <> rest: merge.fields(rest,put(value,key,replacement))
def merge(left: Value, right: Value) -> Value: merge.fields(fields(right),left)
def count(xs: List<&2,Value>) -> U32: U32.from_nat(List.length(&2,Value,xs))
def at(xs: List<&2,Value>, n: U32) -> Value:
  Maybe.default(&2,Value,List.get(&2,Value,xs,U32.to_nat(n)),Null{})

def int_sign(negative: Bool, magnitude: Scale.Integer) -> Signed:
  match magnitude:
    case Scale.ScaleZero{}: Sign{False{},Scale.ScaleZero{}}
    case Scale.ScaleBit{b,t}: Sign{negative,Scale.ScaleBit{b,t}}
def int_read(sign: Bool, result: Maybe<&2,Scale.Integer>) -> Signed:
  match result:
    case None{}: Sign{False{},Scale.ScaleZero{}}
    case Some{value}: int_sign(sign,value)
def int_text(value: String) -> Signed:
  match value:
    case SCon{'-',rest}: int_read(True{},Scale.Integer.read(rest))
    case SCon{'+',rest}: int_read(False{},Scale.Integer.read(rest))
    case value: int_read(False{},Scale.Integer.read(value))
def int(value: Value) -> Signed: int_text(text(value))
def int_zero() -> Signed: Sign{False{},Scale.ScaleZero{}}
def int_u32(value: U32) -> Signed: Sign{False{},Scale.Integer.from_u32(32n,value)}
def int_show(value: Signed) -> String:
  Sign{negative,magnitude} = value
  Bool.pick(String,negative,"-","") ++ Scale.Integer.show(magnitude)
def int_value(value: Signed) -> Value: Number{int_show(value)}
def int_string(value: Signed) -> Value: Text{int_show(value)}
def int_negative(value: Signed) -> Bool:
  Sign{negative,_} = value
  negative
def int_abs(value: Signed) -> Scale.Integer:
  Sign{_,magnitude} = value
  magnitude
def int_neg(value: Signed) -> Signed:
  Sign{negative,magnitude} = value
  int_sign(Bool.not(negative),magnitude)
def int_add.choose(negative: Bool, +a: Scale.Integer, +b: Scale.Integer, cmp: Cmp) -> Signed:
  match cmp:
    case LT{}: int_sign(Bool.not(negative),Scale.Integer.sub(b,a))
    case _: int_sign(negative,Scale.Integer.sub(a,b))
def int_add.sign(same: Bool, negative: Bool, +av: Scale.Integer, +bv: Scale.Integer) -> Signed:
  match same:
    case True{}: int_sign(negative,Scale.Integer.add(av,bv))
    case False{}: int_add.choose(negative,av,bv,Scale.Integer.cmp(av,bv))
def int_add(a: Signed, b: Signed) -> Signed:
  match a b:
    case Sign{+an,+av} Sign{+bn,+bv}:
      int_add.sign(Cmp.is_eq(Bool.cmp(an,bn)),an,av,bv)
def int_sub(a: Signed, b: Signed) -> Signed: int_add(a,int_neg(b))
def int_mul(a: Signed, b: Signed) -> Signed:
  Sign{an,av} = a
  Sign{bn,bv} = b
  int_sign(Bool.xor(an,bn),Scale.Integer.mul(av,bv))
def int_cmp.sign(negative: Bool, cmp: Cmp) -> Cmp:
  match negative cmp:
    case False{} _: cmp
    case True{} LT{}: GT{}
    case True{} GT{}: LT{}
    case True{} EQ{}: EQ{}
def int_cmp(a: Signed, b: Signed) -> Cmp:
  match a b:
    case Sign{False{},av} Sign{True{},bv}: GT{}
    case Sign{True{},av} Sign{False{},bv}: LT{}
    case Sign{sign,av} Sign{_,bv}: int_cmp.sign(sign,Scale.Integer.cmp(av,bv))
def int_eq(a: Signed, b: Signed) -> Bool: Cmp.is_eq(int_cmp(a,b))
def int_le(a: Signed, b: Signed) -> Bool: Cmp.is_le(int_cmp(a,b))
def int_lt(a: Signed, b: Signed) -> Bool: Cmp.is_lt(int_cmp(a,b))
def int_ge(a: Signed, b: Signed) -> Bool: Cmp.is_ge(int_cmp(a,b))
def int_gt(a: Signed, b: Signed) -> Bool: Cmp.is_gt(int_cmp(a,b))
def canonical_digits(xs: String) -> Bool:
  match xs:
    case SNil{}: True{}
    case SCon{Chr{+c},rest}: (((c >= 48) && (c <= 57) : U32)) && canonical_digits(rest)
def canonical_natural(xs: String) -> Bool:
  match xs:
    case "0": True{}
    case SCon{Chr{+c},rest}: (((c >= 49) && (c <= 57) : U32)) && canonical_digits(rest)
    case _: False{}
def canonical_integer(xs: String) -> Bool:
  match xs:
    case SCon{'-',+rest}: Bool.not(String.eq(rest,"0")) && canonical_natural(rest)
    case xs: canonical_natural(xs)
def integer(value: Value) -> Result<&2,&2,String,Signed>:
  match value:
    case Text{+s}:
      do Result<&2,&2,String,Signed>:
        _ : Unit <- require(canonical_integer(s),"noncanonical integer")
        return int_text(s)
    case _: Fail{"noncanonical integer"}
def natural(value: Value) -> Result<&2,&2,String,Signed>:
  match value:
    case Text{+s}:
      do Result<&2,&2,String,Signed>:
        _ : Unit <- require(canonical_natural(s),"noncanonical integer")
        return int_text(s)
    case _: Fail{"noncanonical integer"}

def ratio(numerator: Signed, denominator: Scale.Integer) -> Value:
  Ratio{int_show(numerator),Scale.Integer.show(denominator)}
def rational_integer(value: Signed) -> Rational: Rational{value,Scale.Integer.one()}
def rational_add(a: Rational, b: Rational) -> Rational:
  Rational{an,+ad} = a
  Rational{bn,+bd} = b
  Rational{int_add(int_mul(an,Sign{False{},bd}),int_mul(bn,Sign{False{},ad})),Scale.Integer.mul(ad,bd)}
def rational_neg(a: Rational) -> Rational:
  Rational{n,d} = a
  Rational{int_neg(n),d}
def rational_sub(a: Rational, b: Rational) -> Rational: rational_add(a,rational_neg(b))
def rational_mul(a: Rational, b: Rational) -> Rational:
  Rational{an,ad} = a
  Rational{bn,bd} = b
  Rational{int_mul(an,bn),Scale.Integer.mul(ad,bd)}
def rational_div(a: Rational, b: Rational) -> Rational:
  Rational{an,ad} = a
  Rational{Sign{negative,magnitude},bd} = b
  Rational{int_mul(an,Sign{negative,bd}),Scale.Integer.mul(ad,magnitude)}
def rational_cmp(a: Rational, b: Rational) -> Cmp:
  Rational{an,ad} = a
  Rational{bn,bd} = b
  int_cmp(int_mul(an,Sign{False{},bd}),int_mul(bn,Sign{False{},ad}))
def rational_le(a: Rational, b: Rational) -> Bool: Cmp.is_le(rational_cmp(a,b))
def rational_lt(a: Rational, b: Rational) -> Bool: Cmp.is_lt(rational_cmp(a,b))
def rational_eq(a: Rational, b: Rational) -> Bool: Cmp.is_eq(rational_cmp(a,b))
def rational_value(value: Rational) -> Value:
  Rational{n,d} = value
  ratio(n,d)

def hex_digit(+c: U32) -> U32:
  Bool.pick(U32,((c >= 48) && (c <= 57) : U32),(c - 48 : U32),(c - 87 : U32))
def hex_read(s: String, acc: Scale.Integer) -> Scale.Integer:
  match s:
    case SNil{}: acc
    case SCon{'.',rest}: hex_read(rest,acc)
    case SCon{Chr{c},rest}:
      hex_read(rest,Scale.Integer.add(Scale.Integer.mul(acc,Scale.Integer.from_u32(5n,16)),
        Scale.Integer.from_u32(4n,hex_digit(c))))
def power_two(n: Nat) -> Scale.Integer:
  match n:
    case 0n: Scale.Integer.one()
    case 1n+p: Scale.Integer.double(power_two(p))
def rational_hex.parts(negative: Bool, parts: List<&2,String>) -> Rational:
  match parts:
    case +mantissa <> exponent <> Nil{}:
      +fraction = Maybe.default(&2,String,List.get(&2,String,String.split(mantissa,'.'),1n),"")
      +shift = int_sub(int_text(exponent),int_u32((U32.from_nat(String.length(fraction)) * 4 : U32)))
      +digits = hex_read(String.drop(mantissa,2n),Scale.ScaleZero{})
      Rational{int_sign(negative,Scale.Integer.mul(digits,
        Bool.pick(Scale.Integer,int_negative(shift),Scale.Integer.one(),power_two(U32.to_nat(Scale.Integer.to_u32(int_abs(shift))))))),
        Bool.pick(Scale.Integer,int_negative(shift),power_two(U32.to_nat(Scale.Integer.to_u32(int_abs(shift)))),Scale.Integer.one())}
    case _: rational_integer(int_zero())
def rational_hex(s: String) -> Rational:
  match s:
    case SCon{'-',rest}: rational_hex.parts(True{},String.split(rest,'p'))
    case s: rational_hex.parts(False{},String.split(s,'p'))
def rational(value: Value) -> Rational:
  match value:
    case Real{s,_}: rational_hex(s)
    case Ratio{n,d}: Rational{int_text(n),int_abs(int_text(d))}
    case Boolean{b}: rational_integer(int_u32(Bool.to_u32(b)))
    case value: rational_integer(int(value))
def finite(value: Value) -> Bool:
  match value:
    case Real{+s,_}: Bool.not(String.eq(s,"nan") || String.eq(s,"inf") || String.eq(s,"-inf"))
    case Number{_}: True{}
    case _: False{}
def truth(value: Value) -> Bool:
  match value:
    case Divide{a,b}: truth(a)
    case Null{}: False{}
    case Boolean{b}: b
    case Text{s}: Bool.not(String.is_empty(s))
    case Number{s}: Bool.not(int_eq(int_text(s),int_zero()))
    case Real{+s,_}: Bool.not(String.eq(s,"0x0.0p+0") || String.eq(s,"-0x0.0p+0"))
    case Array{xs}: Bool.not(List.is_empty(&2,Value,xs))
    case Object{xs}: Bool.not(List.is_empty(&2,Field(),xs))
    case Ratio{n,_}: Bool.not(int_eq(int_text(n),int_zero()))
    case Error{_}: True{}
def numeric(value: Value) -> Bool:
  match value:
    case Boolean{_}: True{}
    case Number{_}: True{}
    case Real{_ ,_}: True{}
    case Ratio{_ ,_}: True{}
    case _: False{}
def numeric_finite(value: Value) -> Bool:
  match value:
    case Real{+s,_}: Bool.not(String.eq(s,"nan") || String.eq(s,"inf") || String.eq(s,"-inf"))
    case value: numeric(value)

type EqualityTask is Data:
  Compare{a: Value, b: Value}
  CompareArrays{a: List<&2,Value>, b: List<&2,Value>}
  CompareFields{a: List<&2,Field()>, b: Value}

@unsafe def eq_tasks(tasks: List<&2,EqualityTask>) -> Bool:
  match tasks:
    case Nil{}: True{}
    case Compare{Null{},Null{}} <> rest: eq_tasks(rest)
    case Compare{Text{a},Text{b}} <> rest: String.eq(a,b) && eq_tasks(rest)
    case Compare{Array{a},Array{b}} <> rest: eq_tasks(CompareArrays{a,b} <> rest)
    case Compare{Object{a},+b} <> rest:
      is_object(b) && Nat.is_eq(List.length(&2,Field(),a),List.length(&2,Field(),fields(b))) &&
        eq_tasks(CompareFields{a,b} <> rest)
    case Compare{+a,+b} <> rest:
      numeric_finite(a) && numeric_finite(b) && rational_eq(rational(a),rational(b)) && eq_tasks(rest)
    case CompareArrays{Nil{},Nil{}} <> rest: eq_tasks(rest)
    case CompareArrays{a <> ax,b <> bx} <> rest: eq_tasks(Compare{a,b} <> CompareArrays{ax,bx} <> rest)
    case CompareArrays{_,_} <> rest: False{}
    case CompareFields{Nil{},b} <> rest: eq_tasks(rest)
    case CompareFields{(+key,a) <> ax,+b} <> rest:
      has(b,key) && eq_tasks(Compare{a,get(b,key)} <> CompareFields{ax,b} <> rest)
def eq(a: Value, b: Value) -> Bool: eq_tasks([Compare{a,b}])

def hex_char(+c: U32) -> Char:
  Chr{(c + Bool.pick(U32,(c < 10 : U32),48,87) : U32)}
def hex_valid(+c: U32) -> Bool:
  (((c >= 48) && (c <= 57)) || ((c >= 97) && (c <= 102)) : U32)
def text_encode(s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{Chr{+c},rest}:
      SCon{hex_char(((c >> 20n : U32) .&. 15 : U32)),
        SCon{hex_char(((c >> 16n : U32) .&. 15 : U32)),
          SCon{hex_char(((c >> 12n : U32) .&. 15 : U32)),
            SCon{hex_char(((c >> 8n : U32) .&. 15 : U32)),
              SCon{hex_char(((c >> 4n : U32) .&. 15 : U32)),
                SCon{hex_char((c .&. 15 : U32)),text_encode(rest)}}}}}}
def text_decode(s: String) -> Result<&2,&2,String,String>:
  match s:
    case SNil{}: Done{""}
    case SCon{Chr{+a},SCon{Chr{+b},SCon{Chr{+c},SCon{Chr{+d},SCon{Chr{+e},SCon{Chr{+f},rest}}}}}}:
      do Result<&2,&2,String,String>:
        _ : Unit <- require(hex_valid(a) && hex_valid(b) && hex_valid(c) && hex_valid(d) && hex_valid(e) && hex_valid(f),"malformed evidence text")
        +code : U32 = (hex_digit(a) * 1048576 + hex_digit(b) * 65536 + hex_digit(c) * 4096 +
          hex_digit(d) * 256 + hex_digit(e) * 16 + hex_digit(f) : U32)
        _ : Unit <- require((code <= 1114111 : U32),"malformed evidence text")
        rest : String <- text_decode(rest)
        return SCon{Chr{code},rest}
    case _: Fail{"malformed evidence text"}

type EncodingTask is Data:
  Encode{value: Value}
  EncodeValues{values: List<&2,Value>}
  EncodeFields{fields: List<&2,Field()>}
  EncodedText{text: String}

@unsafe def encode_tasks(tasks: List<&2,EncodingTask>) -> String:
  match tasks:
    case Nil{}: ""
    case EncodedText{s} <> rest: s ++ "\n" ++ encode_tasks(rest)
    case Encode{Null{}} <> rest: "n\n" ++ encode_tasks(rest)
    case Encode{Boolean{b}} <> rest: "b" ++ U32.show(Bool.to_u32(b)) ++ "\n" ++ encode_tasks(rest)
    case Encode{Number{s}} <> rest: "i" ++ s ++ "\n" ++ encode_tasks(rest)
    case Encode{Real{s,d}} <> rest: "f" ++ s ++ "/" ++ d ++ "\n" ++ encode_tasks(rest)
    case Encode{Text{s}} <> rest: "s" ++ text_encode(s) ++ "\n" ++ encode_tasks(rest)
    case Encode{Error{s}} <> rest: "e" ++ text_encode(s) ++ "\n" ++ encode_tasks(rest)
    case Encode{Divide{a,b}} <> rest:
      encode_tasks(Encode{a} <> Encode{b} <> EncodedText{"d"} <> rest)
    case Encode{Ratio{n,d}} <> rest: "r" ++ n ++ "/" ++ d ++ "\n" ++ encode_tasks(rest)
    case Encode{Array{+xs}} <> rest:
      encode_tasks(EncodeValues{xs} <> EncodedText{"a" ++ U32.show(count(xs))} <> rest)
    case Encode{Object{+xs}} <> rest:
      encode_tasks(EncodeFields{xs} <> EncodedText{"o" ++ Nat.show(List.length(&2,Field(),xs))} <> rest)
    case EncodeValues{Nil{}} <> rest: encode_tasks(rest)
    case EncodeValues{h <> t} <> rest: encode_tasks(Encode{h} <> EncodeValues{t} <> rest)
    case EncodeFields{Nil{}} <> rest: encode_tasks(rest)
    case EncodeFields{(key,value) <> t} <> rest:
      encode_tasks(Encode{Text{key}} <> Encode{value} <> EncodeFields{t} <> rest)
def encode(value: Value) -> String: encode_tasks([Encode{value}])

def pop_values(n: Nat, stack: List<&2,Value>, acc: List<&2,Value>) -> Result<&2,&2,String,List<&2,Value>>:
  match n stack:
    case 0n _: Done{Array{acc} <> stack}
    case 1n+p h <> rest: pop_values(p,rest,h <> acc)
    case _ _: Fail{"evidence array stack underflow"}
def pop_fields(n: Nat, stack: List<&2,Value>, acc: List<&2,Field()>) -> Result<&2,&2,String,List<&2,Value>>:
  match n stack:
    case 0n _: Done{Object{acc} <> stack}
    case 1n+p value <> Text{key} <> rest: pop_fields(p,rest,(key,value) <> acc)
    case _ _: Fail{"evidence object stack underflow"}
def decode_size.number(parsed: Maybe<&2,U32>) -> Result<&2,&2,String,Nat>:
  match parsed:
    case None{}: Fail{"malformed evidence container length"}
    case Some{n}: Done{U32.to_nat(n)}
def decode_size(+s: String) -> Result<&2,&2,String,Nat>:
  do Result<&2,&2,String,Nat>:
    _ : Unit <- require(canonical_natural(s),"malformed evidence container length")
    decode_size.number(U32.read(s))
def decode_real(parts: List<&2,String>, stack: List<&2,Value>) -> Result<&2,&2,String,List<&2,Value>>:
  match parts:
    case hex <> decimal <> Nil{}: Done{Real{hex,decimal} <> stack}
    case _: Fail{"malformed evidence real"}
def decode_token(token: String, stack: List<&2,Value>) -> Result<&2,&2,String,List<&2,Value>>:
  match token:
    case "n": Done{Null{} <> stack}
    case "b0": Done{Boolean{False{}} <> stack}
    case "b1": Done{Boolean{True{}} <> stack}
    case SCon{'i',+s}:
      do Result<&2,&2,String,List<&2,Value>>:
        _ : Unit <- require(canonical_integer(s),"malformed evidence integer")
        return Number{s} <> stack
    case SCon{'f',s}: decode_real(String.split(s,'/'),stack)
    case SCon{'s',s}:
      do Result<&2,&2,String,List<&2,Value>>:
        value : String <- text_decode(s)
        return Text{value} <> stack
    case SCon{'e',s}:
      do Result<&2,&2,String,List<&2,Value>>:
        value : String <- text_decode(s)
        return Error{value} <> stack
    case SCon{'a',s}:
      do Result<&2,&2,String,List<&2,Value>>:
        n : Nat <- decode_size(s)
        pop_values(n,stack,Nil{})
    case SCon{'o',s}:
      do Result<&2,&2,String,List<&2,Value>>:
        n : Nat <- decode_size(s)
        pop_fields(n,stack,Nil{})
    case _: Fail{"malformed evidence token"}
def decode_tokens(tokens: List<&2,String>, stack: List<&2,Value>) -> Result<&2,&2,String,Value>:
  match tokens:
    case Nil{}:
      match stack:
        case value <> Nil{}: Done{value}
        case _: Fail{"malformed evidence root"}
    case token <> rest:
      do Result<&2,&2,String,Value>:
        stack : List<&2,Value> <- decode_token(token,stack)
        decode_tokens(rest,stack)
def decode(text: String) -> Result<&2,&2,String,Value>:
  decode_tokens(String.lines(String.trim_end(text)),Nil{})

def read_result(result: Result<&1,&1,U32 & String,String>) -> IO(String):
  match result:
    case Fail{(_,message)}: IO.die(String,2,message)
    case Done{value}: IO.pure(String,value)
def opened(result: Result<&1,&1,U32 & String,File>) -> IO(File):
  match result:
    case Fail{(_,message)}: IO.die(File,2,message)
    case Done{file}: IO.pure(File,file)
def read_expected(valid: Bool, content: String) -> IO(String):
  match valid:
    case True{}: IO.pure(String,content)
    case False{}: IO.die(String,2,"incomplete evidence input file")
def read_content(expected: U32, value: File & Result<&1,&1,U32 & String,String>) -> IO(String):
  (file,result) = value
  do IO<String>:
    File.close(file)
    +content : String <- read_result(result)
    read_expected(Nat.is_eq(String.length(content),U32.to_nat(expected)),content)
def read_size(value: File & Result<&1,&1,U32 & String,U32>) -> IO(String):
  match value:
    case (file,Done{+size}):
      do IO<String>:
        value : File & Result<&1,&1,U32 & String,String> <- File.read(file,size)
        read_content(size,value)
    case (file,Fail{(_,message)}):
      do IO<String>:
        File.close(file)
        IO.die(String,2,message)
def read(path: String) -> IO(String):
  do IO<String>:
    opened_file : Result<&1,&1,U32 & String,File> <- File.open(path,"r")
    file : File <- opened(opened_file)
    size : File & Result<&1,&1,U32 & String,U32> <- File.size(file)
    read_size(size)
def execute(~handler: String -> @+payload:Value -> Value, result: Result<&2,&2,String,Value>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{+request}: IO.write(encode(handler(text(get(request,"operation")),get(request,"payload"))))
def arguments(~handler: String -> @+payload:Value -> Value, args: List<String>) -> IO(Unit):
  match args:
    case _ <> path <> Nil{}:
      do IO<Unit>:
        value : String <- read(path)
        execute(~handler,decode(value))
    case _: IO.die(Unit,2,"evidence worker requires one request path")
def main(~handler: String -> @+payload:Value -> Value) -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(~handler,args)
