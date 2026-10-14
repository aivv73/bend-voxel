import Base
import ../dda.bend as X
import ./benchmark.bend as B

type Cut is Data:
	Intact{}
	Carved{}

type View is Data:
	Opening{}
	Inside{}
	Axis{}
	Opposite{}

type SceneSpec is Data:
	AtelierScene{cut: Cut}
	CubeScene{cut: Cut, view: View}

type Renderer is Data:
	RegionDda{}
	UnitDda{}
	FacesOnly{}
	ExistingShadows{}

type DrawSpec is Data:
	DdaDraw{skip: Bool, schedule: X.Schedule}
	FaceDraw{shadows: Bool, tile: X.ForkDepth, fork: X.ForkDepth}

type MeasuredFrames is Data:
	MeasuredFrames{predecessor: Nat}

type Action is Data:
	Bench{frames: MeasuredFrames}
	Profile{}
	Export{path: String}
	VerifySteps{}
	VerifyFaces{tile: X.ForkDepth}

type RunConfig is Data:
	RunConfig{scene: SceneSpec, draw: DrawSpec, action: Action}

type Options is Data:
	Options{cube: Bool, cut: Cut, view: View, renderer: Renderer, assignment: X.Assignment, fork: X.ForkDepth, tile: X.ForkDepth, action: Action, seen: U32}

type Parser is Data:
	Flags{options: Options}
	Value{tag: U32, options: Options}
	Bad{message: String}

def RunConfig.scene(config: RunConfig) -> SceneSpec:
	RunConfig{scene,draw,action} = config
	scene

def Cut.bool(cut: Cut) -> Bool:
	match cut:
		case Intact{}: False{}
		case Carved{}: True{}

def Cut.name(cut: Cut) -> String:
	match cut:
		case Intact{}: "intact"
		case Carved{}: "carved"

def View.name(view: View) -> String:
	match view:
		case Opening{}: "opening"
		case Inside{}: "inside"
		case Axis{}: "axis"
		case Opposite{}: "opposite"

def View.read(text: String) -> Maybe<&2,View>:
	match text:
		case "opening": Some{Opening{}}
		case "inside": Some{Inside{}}
		case "axis": Some{Axis{}}
		case "opposite": Some{Opposite{}}
		case _: None{}

def Renderer.read(text: String) -> Maybe<&2,Renderer>:
	match text:
		case "dda": Some{RegionDda{}}
		case "dda-step": Some{UnitDda{}}
		case "faces": Some{FacesOnly{}}
		case "existing": Some{ExistingShadows{}}
		case _: None{}

def Assignment.name(assignment: X.Assignment) -> String:
	match assignment:
		case X.Contiguous{}: "contiguous"
		case X.Interleaved{}: "interleaved"

def Assignment.read(text: String) -> Maybe<&2,X.Assignment>:
	match text:
		case "contiguous": Some{X.Contiguous{}}
		case "interleaved": Some{X.Interleaved{}}
		case _: None{}

def Frames.count(frames: MeasuredFrames) -> Nat:
	MeasuredFrames{predecessor} = frames
	1n+predecessor

def Frames.positive(value: U32) -> Result<&2,&2,String,MeasuredFrames>:
	match value:
		case 0: Fail{"Measured frames must be positive"}
		case +n: Done{MeasuredFrames{Nat.sub(U32.to_nat(n),1n)}}

def Frames.read(text: String) -> Result<&2,&2,String,MeasuredFrames>:
	do Result<&2,&2,String,MeasuredFrames>:
		value : U32 <- B.Decimal.read(text)
		Frames.positive(value)

def Read.required(-A: Data, value: Maybe<&2,A>, error: String) -> Result<&2,&2,String,A>:
	match value:
		case Some{x}: Done{x}
		case None{}: Fail{error}

def Depth.read(text: String) -> Result<&2,&2,String,X.ForkDepth>:
	Read.required(X.ForkDepth,X.ForkDepth.read(text),"Depth must be an integer in 0..9")

def SceneSpec.cube(spec: SceneSpec) -> Bool:
	match spec:
		case AtelierScene{cut}: False{}
		case CubeScene{cut,view}: True{}

def SceneSpec.cut(spec: SceneSpec) -> Cut:
	match spec:
		case AtelierScene{cut}: cut
		case CubeScene{cut,view}: cut

def SceneSpec.view(spec: SceneSpec) -> View:
	match spec:
		case AtelierScene{cut}: Opening{}
		case CubeScene{cut,view}: view

def SceneSpec.label(spec: SceneSpec) -> String:
	match spec:
		case AtelierScene{Intact{}}: "opening"
		case AtelierScene{Carved{}}: "cut"
		case CubeScene{Intact{},Opening{}}: "cube"
		case CubeScene{Carved{},Opening{}}: "carved"
		case CubeScene{cut,view}: "cube-" ++ Cut.name(cut) ++ "-" ++ View.name(view)

def SceneSpec.read(text: String) -> Maybe<&2,SceneSpec>:
	match text:
		case "opening": Some{AtelierScene{Intact{}}}
		case "cut": Some{AtelierScene{Carved{}}}
		case "cube": Some{CubeScene{Intact{},Opening{}}}
		case "carved": Some{CubeScene{Carved{},Opening{}}}
		case "inside": Some{CubeScene{Intact{},Inside{}}}
		case "axis": Some{CubeScene{Intact{},Axis{}}}
		case "opposite": Some{CubeScene{Intact{},Opposite{}}}
		case _: None{}

def SceneSpec.all() -> List<&2,SceneSpec>:
	[AtelierScene{Intact{}},AtelierScene{Carved{}},CubeScene{Intact{},Opening{}},CubeScene{Carved{},Opening{}},CubeScene{Intact{},Inside{}},CubeScene{Intact{},Axis{}},CubeScene{Intact{},Opposite{}}]

def DrawSpec.renderer(draw: DrawSpec) -> String:
	match draw:
		case DdaDraw{True{},schedule}: "dda"
		case DdaDraw{False{},schedule}: "dda-step"
		case FaceDraw{False{},tile,fork}: "faces"
		case FaceDraw{True{},tile,fork}: "existing"

def DrawSpec.fork(draw: DrawSpec) -> X.ForkDepth:
	match draw:
		case DdaDraw{skip,X.Schedule{fork,assignment}}: fork
		case FaceDraw{shadows,tile,fork}: fork

def DrawSpec.assignment(draw: DrawSpec) -> String:
	match draw:
		case DdaDraw{skip,X.Schedule{fork,assignment}}: Assignment.name(assignment)
		case FaceDraw{shadows,tile,fork}: "not_applicable"

def Action.name(action: Action) -> String:
	match action:
		case Bench{frames}: "bench"
		case Profile{}: "profile"
		case Export{path}: "export"
		case VerifySteps{}: "verify_steps"
		case VerifyFaces{tile}: "verify_faces"

def Action.invoked(action: Action) -> Bool:
	match action:
		case VerifySteps{}: False{}
		case VerifyFaces{tile}: False{}
		case _: True{}

def Action.warm(action: Action) -> Nat:
	match action:
		case Bench{frames}: 4n
		case Profile{}: 4n
		case _: 0n

def Action.measured(action: Action) -> Nat:
	match action:
		case Bench{frames}: Frames.count(frames)
		case Profile{}: 1n
		case _: 0n

def Action.assignment(invoked: Bool, draw: DrawSpec) -> String:
	match invoked:
		case True{}: DrawSpec.assignment(draw)
		case False{}: "not_invoked"

def DrawSpec.tile(draw: DrawSpec) -> String:
	match draw:
		case DdaDraw{skip,schedule}: "not_applicable"
		case FaceDraw{shadows,tile,fork}: Nat.show(X.ForkDepth.nat(tile))

def Action.tile(draw: DrawSpec, action: Action) -> String:
	match action:
		case VerifyFaces{tile}: Nat.show(X.ForkDepth.nat(tile))
		case _: DrawSpec.tile(draw)

def Report.work(invoked: Bool, +draw: DrawSpec) -> String:
	match invoked draw:
		case False{} _: "logical_jobs=0 pixels_per_job=0"
		case True{} DdaDraw{skip,+schedule}:
			+f = X.ForkDepth.nat(DrawSpec.fork(draw))
			"logical_jobs=" ++ U32.show((1 << Nat.add(f,f) : U32)) ++ " pixels_per_job=" ++ U32.show((1 << Nat.add(Nat.sub(9n,f),Nat.sub(9n,f)) : U32))
		case True{} FaceDraw{shadows,tile,fork}: "logical_jobs=not_applicable pixels_per_job=not_applicable"

def Report.line(config: RunConfig) -> String:
	RunConfig{+scene,+draw,+action} = config
	"dda_options_v1 scene=" ++ Bool.pick(String,SceneSpec.cube(scene),"cube","atelier") ++
		" view=" ++ View.name(SceneSpec.view(scene)) ++ " cut=" ++ Cut.name(SceneSpec.cut(scene)) ++
		" renderer=" ++ DrawSpec.renderer(draw) ++ " assignment=" ++ Action.assignment(Action.invoked(action),draw) ++
		" depth=" ++ Nat.show(X.ForkDepth.nat(DrawSpec.fork(draw))) ++ " tile=" ++ Action.tile(draw,action) ++
		" warm=" ++ Nat.show(Action.warm(action)) ++ " measured=" ++ Nat.show(Action.measured(action)) ++
		" width=512 height=512 " ++ Report.work(Action.invoked(action),draw) ++
		" action=" ++ Action.name(action) ++ " frame_invoked=" ++ Bool.pick(String,Action.invoked(action),"true","false")

def Report.scan(lines: List<&2,String>, +prefix: String, +expected: String, count: Nat, valid: Bool) -> Result<&2,&2,String,Unit>:
	match lines:
		case Nil{}:
			Bool.pick(Result<&2,&2,String,Unit>,Nat.is_eq(count,1n) && valid,Done{Unit{}},Fail{"Expected exactly one matching effective-option report"})
		case +line <> rest:
			+report = String.starts_with(line,prefix)
			Report.scan(rest,prefix,expected,Nat.add(count,Bool.pick(Nat,report,1n,0n)),valid && (Bool.not(report) || String.eq(line,expected)))

def Report.check(config: RunConfig, stdout: String) -> Result<&2,&2,String,Unit>:
	Report.scan(String.split(stdout,'\n'),"dda_options_v1",Report.line(config),0n,True{})

def Runtime.line(threads: U32) -> String:
	"dda_runtime_v1 cpu_threads=" ++ U32.show(threads)

def Runtime.check(threads: U32, stdout: String) -> Result<&2,&2,String,Unit>:
	Report.scan(String.split(stdout,'\n'),"dda_runtime_v1",Runtime.line(threads),0n,True{})

def Cut.argv(cut: Cut) -> List<&2,String>:
	match cut:
		case Intact{}: Nil{}
		case Carved{}: ["--cut"]

def SceneSpec.argv(spec: SceneSpec) -> List<&2,String>:
	match spec:
		case AtelierScene{cut}: Cut.argv(cut)
		case CubeScene{cut,view}: List.append(&2,String,["--cube","--view",View.name(view)],Cut.argv(cut))

def DrawSpec.argv(+draw: DrawSpec) -> List<&2,String>:
	match draw:
		case DdaDraw{skip,X.Schedule{fork,assignment}}:
			["--renderer",DrawSpec.renderer(draw),"--assignment",Assignment.name(assignment),"--fork-depth",Nat.show(X.ForkDepth.nat(fork))]
		case FaceDraw{shadows,tile,fork}:
			["--renderer",DrawSpec.renderer(draw),"--tile-depth",Nat.show(X.ForkDepth.nat(tile)),"--fork-depth",Nat.show(X.ForkDepth.nat(fork))]

def Action.argv(action: Action) -> List<&2,String>:
	match action:
		case Bench{frames}: ["--bench",Nat.show(Frames.count(frames))]
		case Profile{}: ["--profile"]
		case Export{path}: ["--dump",path]
		case VerifySteps{}: ["--verify-steps"]
		case VerifyFaces{tile}: ["--verify"]

def Config.draw_argv(+draw: DrawSpec, action: Action) -> List<&2,String>:
	match draw action:
		case DdaDraw{skip,schedule} VerifyFaces{tile}:
			List.append(&2,String,DrawSpec.argv(draw),["--tile-depth",Nat.show(X.ForkDepth.nat(tile))])
		case _ _: DrawSpec.argv(draw)

def Config.argv(config: RunConfig) -> List<&2,String>:
	RunConfig{scene,draw,+action} = config
	List.append(&2,String,Config.draw_argv(draw,action),List.append(&2,String,SceneSpec.argv(scene),Action.argv(action)))

def Parser.result(result: Result<&2,&2,String,Options>) -> Parser:
	match result:
		case Done{options}: Flags{options}
		case Fail{message}: Bad{message}

def Options.assign(tag: U32, +text: String, +options: Options) -> Result<&2,&2,String,Options>:
	match tag options:
		case 1 Options{cube,cut,view,renderer,assignment,fork,tile,action,seen}:
			do Result<&2,&2,String,Options>:
				x : Renderer <- Read.required(Renderer,Renderer.read(text),"Unknown renderer")
				return Options{cube,cut,view,x,assignment,fork,tile,action,seen}
		case 2 Options{cube,cut,view,renderer,assignment,fork,tile,action,seen}:
			do Result<&2,&2,String,Options>:
				x : X.Assignment <- Read.required(X.Assignment,Assignment.read(text),"Unknown assignment")
				return Options{cube,cut,view,renderer,x,fork,tile,action,seen}
		case 3 Options{cube,cut,view,renderer,assignment,fork,tile,action,seen}:
			do Result<&2,&2,String,Options>:
				x : X.ForkDepth <- Depth.read(text)
				return Options{cube,cut,view,renderer,assignment,x,tile,action,seen}
		case 4 Options{cube,cut,view,renderer,assignment,fork,tile,action,seen}:
			do Result<&2,&2,String,Options>:
				x : X.ForkDepth <- Depth.read(text)
				return Options{cube,cut,view,renderer,assignment,fork,x,action,seen}
		case 5 Options{cube,cut,view,renderer,assignment,fork,tile,action,seen}:
			do Result<&2,&2,String,Options>:
				x : View <- Read.required(View,View.read(text),"Unknown view")
				return Options{cube,cut,x,renderer,assignment,fork,tile,action,seen}
		case 6 Options{cube,cut,view,renderer,assignment,fork,tile,action,seen}:
			do Result<&2,&2,String,Options>:
				x : MeasuredFrames <- Frames.read(text)
				return Options{cube,cut,view,renderer,assignment,fork,tile,Bench{x},seen}
		case 7 Options{cube,cut,view,renderer,assignment,fork,tile,action,seen}:
			Bool.pick(Result<&2,&2,String,Options>,String.is_empty(text),Fail{"Export path must be nonempty"},Done{Options{cube,cut,view,renderer,assignment,fork,tile,Export{text},seen}})
		case _ _: Fail{"Unknown valued option"}

def Flag.tag(text: String) -> U32:
	match text:
		case "--renderer": 1
		case "--assignment": 2
		case "--fork-depth": 3
		case "--tile-depth": 4
		case "--view": 5
		case "--bench": 6
		case "--dump": 7
		case "--cube": 8
		case "--cut": 9
		case "--profile": 10
		case "--verify": 11
		case "--verify-steps": 12
		case _: 0

def Parser.flag(tag: U32, value: Maybe<&2,String>, options: Options) -> Parser:
	match tag value options:
		case 0 _ _: Bad{"Unknown option"}
		case 8 None{} Options{cube,cut,view,renderer,assignment,fork,tile,action,seen}: Flags{Options{True{},cut,view,renderer,assignment,fork,tile,action,seen}}
		case 9 None{} Options{cube,cut,view,renderer,assignment,fork,tile,action,seen}: Flags{Options{cube,Carved{},view,renderer,assignment,fork,tile,action,seen}}
		case 10 None{} Options{cube,cut,view,renderer,assignment,fork,tile,action,seen}: Flags{Options{cube,cut,view,renderer,assignment,fork,tile,Profile{},seen}}
		case 11 None{} Options{cube,cut,view,renderer,assignment,fork,+tile,action,seen}: Flags{Options{cube,cut,view,renderer,assignment,fork,tile,VerifyFaces{tile},seen}}
		case 12 None{} Options{cube,cut,view,renderer,assignment,fork,tile,action,seen}: Flags{Options{cube,cut,view,renderer,assignment,fork,tile,VerifySteps{},seen}}
		case +n None{} _: Value{n,options}
		case +n Some{text} _:
			Parser.result(Options.assign(n,text,options))

def Parser.claim(duplicate: Bool, tag: U32, value: Maybe<&2,String>, options: Options) -> Parser:
	match duplicate:
		case True{}: Bad{"Duplicate option or conflicting actions"}
		case False{}: Parser.flag(tag,value,options)

def Parser.option(+tag: U32, value: Maybe<&2,String>, options: Options) -> Parser:
	Options{cube,cut,view,renderer,assignment,fork,tile,action,+seen} = options
	+bit = (1 << U32.to_nat(Bool.pick(U32,(tag >= 10 : U32) || U32.is_eq(tag,7),6,tag)) : U32)
	Parser.claim(U32.is_ne((seen .&. bit : U32),0),tag,value,Options{cube,cut,view,renderer,assignment,fork,tile,action,(seen .|. bit : U32)})

def Parser.token(token: String & Maybe<&2,String>, options: Options) -> Parser:
	(flag,value) = token
	Parser.option(Flag.tag(flag),value,options)

def Config.draw(renderer: Renderer, assignment: X.Assignment, fork: X.ForkDepth, tile: X.ForkDepth) -> DrawSpec:
	match renderer:
		case RegionDda{}: DdaDraw{True{},X.Schedule{fork,assignment}}
		case UnitDda{}: DdaDraw{False{},X.Schedule{fork,assignment}}
		case FacesOnly{}: FaceDraw{False{},tile,fork}
		case ExistingShadows{}: FaceDraw{True{},tile,fork}

def Action.with_tile(action: Action, tile: X.ForkDepth) -> Action:
	match action:
		case VerifyFaces{old}: VerifyFaces{tile}
		case _: action

def Config.finish(+options: Options) -> Result<&2,&2,String,RunConfig>:
	match options:
		case Options{False{},cut,Opening{},renderer,assignment,fork,tile,action,seen}:
			Bool.pick(Result<&2,&2,String,RunConfig>,
				U32.is_ne((seen .&. 4 : U32),0) && (String.eq(DrawSpec.renderer(Config.draw(renderer,assignment,fork,tile)),"faces") || String.eq(DrawSpec.renderer(Config.draw(renderer,assignment,fork,tile)),"existing")),
				Fail{"DDA assignment is unsupported for face renderers"},Done{RunConfig{AtelierScene{cut},Config.draw(renderer,assignment,fork,tile),Action.with_tile(action,tile)}})
		case Options{True{},cut,view,renderer,assignment,fork,tile,action,seen}:
			Bool.pick(Result<&2,&2,String,RunConfig>,
				U32.is_ne((seen .&. 4 : U32),0) && (String.eq(DrawSpec.renderer(Config.draw(renderer,assignment,fork,tile)),"faces") || String.eq(DrawSpec.renderer(Config.draw(renderer,assignment,fork,tile)),"existing")),
				Fail{"DDA assignment is unsupported for face renderers"},Done{RunConfig{CubeScene{cut,view},Config.draw(renderer,assignment,fork,tile),Action.with_tile(action,tile)}})
		case _: Fail{"Non-opening views require --cube"}

def Parser.finish(parser: Parser) -> Result<&2,&2,String,RunConfig>:
	match parser:
		case Flags{options}: Config.finish(options)
		case Value{tag,options}: Fail{"Missing option value"}
		case Bad{message}: Fail{message}

def Parser.go(args: List<&2,String>, parser: Parser) -> Result<&2,&2,String,RunConfig>:
	match args parser:
		case Nil{} _: Parser.finish(parser)
		case arg <> rest Flags{options}: Parser.go(rest,Parser.token(B.Option.split(arg,""),options))
		case arg <> rest Value{tag,options}: Parser.go(rest,Parser.result(Options.assign(tag,arg,options)))
		case _ Bad{message}: Fail{message}

def Config.parse(args: List<&2,String>) -> Result<&2,&2,String,RunConfig>:
	Parser.go(args,Flags{Options{False{},Intact{},Opening{},RegionDda{},X.Contiguous{},X.F6{},X.F6{},Bench{MeasuredFrames{23n}},0}})
