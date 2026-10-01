import Base
import ./megascene_admit.bend as Parse
import ./megascene_admission.bend as Admission
import ./megascene_scale.bend as Scale
import ./schedule_binary.bend as Binary
import ./schedule_file.bend as FileIO

type Mode is Data:
  Static{}
  Traversal{}
  Picking{proxy: Bool}
  Localized{}
  Support{}
  History{}
type Camera is Data:
  Camera{x: U32, y: U32, z: U32, yaw: U32, pitch: U32}
type Cut is Data:
  Cut{frame: U32, action: U32, x: U32, y: U32, z: U32, removed: U32}
type ParsedCuts is Data:
  ParsedCuts{cuts: List<&2,Cut>, rest: List<&2,String>}
type Config is Data:
  Config{mode: Mode, budget: U32, width: U32, height: U32, total: U32, camera: Camera, cuts: List<&2,Cut>}

def require(-A: Data, ok: Bool, value: A) -> Result<&2,&2,String,A>:
  Admission.require(A,ok,"invalid worker-source input",value)

def unsigned(text: String, label: String) -> Result<&2,&2,String,U32>:
  do Result<&2,&2,String,U32>:
    n : Admission.Integer <- Parse.coordinate(text)
    Admission.checked.integer(n,label)

def number.show(n: Admission.Integer) -> Result<&2,&2,String,String>:
  match n:
    case Admission.Integer{negative,magnitude}:
      +digits = Scale.Integer.show(magnitude) ++ ".0"
      Done{Bool.pick(String,negative,"(0.0 - " ++ digits ++ " : F32)",digits)}
    case _: Fail{"invalid worker-source coordinate"}

def number(+n: Admission.Integer) -> Result<&2,&2,String,String>:
  do Result<&2,&2,String,String>:
    _ : F32 <- Admission.exact(n,"inexact worker-source coordinate")
    number.show(n)

def vector(v: Admission.ExactVec) -> Result<&2,&2,String,String>:
  Admission.ExactVec{x,y,z} = v
  do Result<&2,&2,String,String>:
    x : String <- number(x)
    y : String <- number(y)
    z : String <- number(z)
    return "R.Vec{" ++ x ++ "," ++ y ++ "," ++ z ++ "}"

def box(b: Admission.ExactBox) -> Result<&2,&2,String,String>:
  Admission.ExactBox{lo,hi,m} = b
  do Result<&2,&2,String,String>:
    lo : String <- vector(lo)
    hi : String <- vector(hi)
    m : U32 <- Admission.material(m)
    return "S.Box{" ++ lo ++ "," ++ hi ++ "," ++ U32.show(m) ++ "}"

def boxes(bs: List<&2,Admission.ExactBox>) -> Result<&2,&2,String,List<&2,String>>:
  match bs:
    case Nil{}: Done{Nil{}}
    case b <> rest:
      do Result<&2,&2,String,List<&2,String>>:
        b : String <- box(b)
        rest : List<&2,String> <- boxes(rest)
        return b <> rest

def owner.index(+index: U32) -> String:
  "owner" ++ U32.show(index) ++ "()"

def owners(source: List<&2,Admission.ExactOwner>, +index: U32) -> Result<&2,&2,String,String>:
  match source:
    case Nil{}: Done{""}
    case Admission.ExactOwner{bs} <> rest:
      do Result<&2,&2,String,String>:
        bs : List<&2,String> <- boxes(bs)
        next : U32 <- Admission.checked.add(index,1,"worker owner index")
        rest : String <- owners(rest,next)
        return "def " ++ owner.index(index) ++ " -> Showcase.Assembly:\n  Showcase.Assembly{S.build([" ++
          String.join(bs,",\n    ") ++ "])}\n" ++ rest

def calls(source: List<&2,Admission.ExactOwner>, +index: U32) -> String:
  match source:
    case Nil{}: ""
    case _ <> +rest:
      owner.index(index) ++ Bool.pick(String,List.is_empty(&2,Admission.ExactOwner,rest),"",",") ++ calls(rest,(index + 1 : U32))

def imports(+prefix: String) -> String:
  "import ./" ++ prefix ++ "math.bend as R\nimport ./" ++ prefix ++ "spatial.bend as S\nimport ./" ++ prefix ++ "showcase.bend as Showcase\n" ++
    "import ./" ++ prefix ++ "world.bend as W\nimport ./" ++ prefix ++ "megascene.bend as M\n"

def admission(+source: List<&2,Admission.ExactOwner>, budget: U32) -> Result<&2,&2,String,String>:
  do Result<&2,&2,String,String>:
    declarations : String <- owners(source,0)
    return "import Base\n" ++ imports("src/") ++ declarations ++ "def main() -> IO(Unit):\n" ++
      "  M.emit(W.from.bodies(W.assemblies([" ++ calls(source,0) ++ "],1)," ++ U32.show(budget) ++ "))\n"

def real(+word: U32) -> String:
  "real.bits(" ++ U32.show(word) ++ ")"

def real.vector(x: U32, y: U32, z: U32) -> String:
  "R.Vec{" ++ real(x) ++ "," ++ real(y) ++ "," ++ real(z) ++ "}"

def camera(c: Camera, width: U32, height: U32) -> String:
  Camera{x,y,z,yaw,pitch} = c
  "V.Camera{" ++ real.vector(x,y,z) ++ "," ++ real(yaw) ++ "," ++ real(pitch) ++ "," ++
    U32.show(width) ++ "," ++ U32.show(height) ++ "}"

def module(mode: Mode) -> String:
  match mode:
    case Static{}: "megascene_static"
    case Traversal{}: "megascene_traversal"
    case Picking{_}: "megascene_picking_replay"
    case Localized{}: "megascene_localized"
    case Support{}: "megascene_support"
    case History{}: "megascene_history"

def entry(mode: Mode) -> String:
  match mode:
    case Picking{True{}}: "Static.start.proxy"
    case _: "Static.start"

def cut(c: Cut, history: Bool) -> String:
  Cut{frame,action,x,y,z,removed} = c
  "Static.Cut{" ++ U32.show(frame) ++ "," ++ U32.show(action) ++ "," ++ real.vector(x,y,z) ++
    Bool.pick(String,history,"," ++ U32.show(removed),"") ++ "}"

def cuts(xs: List<&2,Cut>, +history: Bool) -> List<&2,String>:
  match xs:
    case Nil{}: Nil{}
    case c <> rest: cut(c,history) <> cuts(rest,history)

def start.args.shape(mode: Mode, c: Camera, width: U32, height: U32, cs: List<&2,Cut>, +size: String) -> Result<&2,&2,String,String>:
  match mode cs:
    case Static{} Nil{}: Done{camera(c,width,height) ++ "," ++ size}
    case Traversal{} Nil{}: Done{size}
    case Picking{_} Nil{}: Done{size}
    case Localized{} Cut{_,_,x,y,z,_} <> _ : Done{real.vector(x,y,z) ++ "," ++ size}
    case Support{} cs: Done{"[" ++ String.join(cuts(cs,False{}),",") ++ "]," ++ size}
    case History{} cs: Done{"[" ++ String.join(cuts(cs,True{}),",") ++ "]," ++ size}
    case _ _: Fail{"worker-source action shape mismatch"}

def start.args(mode: Mode, c: Camera, +width: U32, +height: U32, cs: List<&2,Cut>) -> Result<&2,&2,String,String>:
  start.args.shape(mode,c,width,height,cs,U32.show(width) ++ "," ++ U32.show(height))

def replay(+source: List<&2,Admission.ExactOwner>, config: Config) -> Result<&2,&2,String,String>:
  Config{+mode,budget,width,height,total,camera,cs} = config
  do Result<&2,&2,String,String>:
    declarations : String <- owners(source,0)
    args : String <- start.args(mode,camera,width,height,cs)
    return "import Base\nimport ./" ++ module(mode) ++ ".bend as Static\n" ++
      "import ./vulkan.bend as VK\nimport ./render.bend as V\n" ++ imports("") ++ declarations ++
      "def real.bits(bits: U32) -> F32:\n  U32{word} = bits\n  F32{word}\n\n" ++
      "def main() -> IO(Unit):\n  do IO<Unit>:\n    VK.vulkan.mark(0)\n    VK.vulkan.mark(1)\n" ++
      "    sources : List<&2,Showcase.Assembly> <- IO.pure(List<&2,Showcase.Assembly>,[" ++ calls(source,0) ++ "])\n" ++
      "    VK.vulkan.mark(2)\n    VK.vulkan.mark(3)\n" ++
      "    +world : W.World <- IO.pure(W.World,W.from.bodies(W.assemblies(sources,1)," ++ U32.show(budget) ++ "))\n" ++
      "    VK.vulkan.mark(4)\n    VK.vulkan.mark(5)\n    M.emit(world)\n    VK.vulkan.mark(6)\n    " ++
      entry(mode) ++ "(world," ++ args ++ "," ++ U32.show(total) ++ "n)\n"

def word(+text: String) -> Result<&2,&2,String,U32>:
  do Result<&2,&2,String,U32>:
    +n : U32 <- Binary.word(text)
    require(U32,U32.is_ne((n .&. 2139095040 : U32),2139095040),n)

def parse.mode(text: String, proxy: Bool) -> Result<&2,&2,String,Mode>:
  match text:
    case "static": Done{Static{}}
    case "traversal": Done{Traversal{}}
    case "picking": Done{Picking{proxy}}
    case "localized": Done{Localized{}}
    case "support": Done{Support{}}
    case "history": Done{History{}}
    case _: Fail{"unsupported worker-source case"}

def flag(text: String) -> Result<&2,&2,String,Bool>:
  match text:
    case "true": Done{True{}}
    case "false": Done{False{}}
    case _: Fail{"invalid worker-source proxy flag"}

def parse.cuts.prepend(c: Cut, result: ParsedCuts) -> ParsedCuts:
  ParsedCuts{cs,rest} = result
  ParsedCuts{c <> cs,rest}

def parse.cuts(n: Nat, xs: List<&2,String>) -> Result<&2,&2,String,ParsedCuts>:
  match n xs:
    case 0n xs: Done{ParsedCuts{Nil{},xs}}
    case 1n+p f <> a <> x <> y <> z <> removed <> rest:
      do Result<&2,&2,String,ParsedCuts>:
        f : U32 <- unsigned(f,"worker action frame")
        a : U32 <- unsigned(a,"worker action ID")
        x : U32 <- word(x)
        y : U32 <- word(y)
        z : U32 <- word(z)
        removed : U32 <- unsigned(removed,"worker removed cells")
        result : ParsedCuts <- parse.cuts(p,rest)
        return parse.cuts.prepend(Cut{f,a,x,y,z,removed},result)
    case _ _: Fail{"incomplete worker-source actions"}

def parse.owners(xs: List<&2,String>) -> Result<&2,&2,String,List<&2,Admission.ExactOwner>>:
  match xs:
    case n <> +rest:
      do Result<&2,&2,String,List<&2,Admission.ExactOwner>>:
        n : Nat <- Parse.count.nat(n,rest)
        Parse.owners(n,rest)
    case _: Fail{"incomplete worker-source owners"}

def parse.replay.cuts(mode: Mode, budget: U32, width: U32, height: U32, total: U32, camera: Camera, parsed: ParsedCuts) -> Result<&2,&2,String,String>:
  ParsedCuts{cs,rest} = parsed
  do Result<&2,&2,String,String>:
    source : List<&2,Admission.ExactOwner> <- parse.owners(rest)
    replay(source,Config{mode,budget,width,height,total,camera,cs})

def parse.replay(xs: List<&2,String>) -> Result<&2,&2,String,String>:
  match xs:
    case name <> proxy <> budget <> width <> height <> warmup <> frames <> x <> y <> z <> yaw <> pitch <> n <> +rest:
      do Result<&2,&2,String,String>:
        proxy : Bool <- flag(proxy)
        mode : Mode <- parse.mode(name,proxy)
        budget : U32 <- unsigned(budget,"fragment budget")
        +width : U32 <- unsigned(width,"worker width")
        +height : U32 <- unsigned(height,"worker height")
        _ : Unit <- require(Unit,Bool.or(U32.is_eq(width,640) && U32.is_eq(height,360),
          U32.is_eq(width,1920) && U32.is_eq(height,1080)),Unit{})
        +warmup : U32 <- unsigned(warmup,"worker warmup frames")
        +frames : U32 <- unsigned(frames,"worker measured frames")
        _ : Unit <- require(Unit,((warmup <= 120) && (frames >= 1) && (frames <= 21600) : U32),Unit{})
        total : U32 <- Admission.checked.add(warmup,frames,"worker total frames")
        x : U32 <- word(x)
        y : U32 <- word(y)
        z : U32 <- word(z)
        yaw : U32 <- word(yaw)
        pitch : U32 <- word(pitch)
        +n : U32 <- unsigned(n,"worker action count")
        _ : Unit <- require(Unit,(n <= 128 : U32),Unit{})
        parsed : ParsedCuts <- parse.cuts(U32.to_nat(n),rest)
        parse.replay.cuts(mode,budget,width,height,total,Camera{x,y,z,yaw,pitch},parsed)
    case _: Fail{"incomplete worker-source configuration"}

def request.parts(xs: List<&2,String>) -> Result<&2,&2,String,String>:
  match xs:
    case "megascene-worker/1" <> "admission" <> budget <> rest:
      do Result<&2,&2,String,String>:
        budget : U32 <- unsigned(budget,"fragment budget")
        source : List<&2,Admission.ExactOwner> <- parse.owners(rest)
        admission(source,budget)
    case "megascene-worker/1" <> "replay" <> rest: parse.replay(rest)
    case _: Fail{"invalid worker-source protocol"}

def request(text: String) -> Result<&2,&2,String,String>:
  do Result<&2,&2,String,String>:
    tokens : List<&2,String> <- Parse.tokens.go(text,SNil{},Nil{})
    request.parts(tokens)

def emit(result: Result<&2,&2,String,String>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{source}: IO.write(source)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case _ <> path <> Nil{}:
      do IO<Unit>:
        text : String <- FileIO.read(path)
        emit(request(text))
    case _: IO.die(Unit,2,"usage: megascene-worker-source INPUT")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(args)
