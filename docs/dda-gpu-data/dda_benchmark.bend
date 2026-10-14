import Base
import ../../main.bend as M
import ../../render.bend as R
import ./dda_compare.bend as C
import ../../scripts/benchmark.bend as B
import ../../scripts/benchmark_number.bend as N
import ../../scripts/benchmark_host.bend as H
import ./dda_config.bend as K
import ./candidate-dda.bend as X

type Work is Data:
	Work{renderer: String, scene: C.Scene, samples: List<&2,N.Binary64>}

def Sample.finish(+renderer: String, samples: List<&2,N.Binary64>, +frames: U32, repeat: U32, start: Nat, finish: Nat, result: Window & C.Scene) -> IO(Window & Work):
	(window,scene) = result
	do IO<Window & Work>:
		elapsed : N.Elapsed <- H.Host.result(N.Elapsed,N.Elapsed.read(Nat.show(Nat.sub(finish,start))),"Elapsed time")
		+value : N.Binary64 <- H.Host.result(N.Binary64,N.Number.sample(elapsed,frames),"Frame sample")
		IO.print("renderer=" ++ renderer ++ " repeat=" ++ U32.show(repeat) ++ " frames=" ++ U32.show(frames) ++ " ms/frame=" ++ N.Number.fixed3(value))
		return (window,Work{renderer,scene,value <> samples})

def Sample(+frames: U32, repeat: U32, window: Window, work: Work) -> IO(Window & Work):
	Work{renderer,scene,samples} = work
	do IO<Window & Work>:
		warm : Window & C.Scene <- C.Frames(4n,(window,scene))
		start : Nat <- IO.now()
		result : Window & C.Scene <- C.Frames(U32.to_nat(frames),warm)
		finish : Nat <- IO.now()
		Sample.finish(renderer,samples,frames,repeat,start,finish,result)

def Sample.prepend(work: Work, result: Window & List<&2,Work>) -> Window & List<&2,Work>:
	(window,rest) = result
	(window,work <> rest)

def Sample.rest(result: Window & Work, next: Window -> IO(Window & List<&2,Work>)) -> IO(Window & List<&2,Work>):
	(window,work) = result
	IO.bind(Window & List<&2,Work>,Window & List<&2,Work>,next(window),result => IO.pure(Window & List<&2,Work>,Sample.prepend(work,result)))

def Samples(works: List<&2,Work>, window: Window, +frames: U32, +repeat: U32) -> IO(Window & List<&2,Work>):
	match works:
		case Nil{}: IO.pure(Window & List<&2,Work>,(window,Nil{}))
		case work <> rest:
			IO.bind(Window & Work,Window & List<&2,Work>,Sample(frames,repeat,window,work),result => Sample.rest(result,w => Samples(rest,w,frames,repeat)))

def Repeats.next(result: Window & List<&2,Work>, next: Window -> List<&2,Work> -> IO(Window & List<&2,Work>)) -> IO(Window & List<&2,Work>):
	(window,works) = result
	next(window,List.reverse(&2,Work,works))

def Repeats(fuel: Nat, +repeat: U32, +frames: U32, state: Window & List<&2,Work>) -> IO(Window & List<&2,Work>):
	match fuel:
		case 0n: IO.pure(Window & List<&2,Work>,state)
		case 1n+rest:
			(window,works) = state
			IO.bind(Window & List<&2,Work>,Window & List<&2,Work>,Samples(works,window,frames,repeat),
				result => Repeats.next(result,w => ws => Repeats(rest,(repeat + 1 : U32),frames,(w,ws))))

def Values(values: List<&2,N.Binary64>) -> String:
	match values:
		case Nil{}: ""
		case head <> rest: N.Number.json(head) ++ " " ++ Values(rest)

def Bounds(values: List<&2,N.Binary64>, +low: N.Binary64, +high: N.Binary64) -> String:
	match values:
		case Nil{}: N.Number.json(low) ++ "\t" ++ N.Number.json(high)
		case +head <> rest:
			Bounds(rest,Bool.pick(N.Binary64,B.Rows.le(head,low),head,low),Bool.pick(N.Binary64,B.Rows.le(high,head),head,high))

def Range(values: List<&2,N.Binary64>) -> String:
	match values:
		case Nil{}: "0\t0"
		case +head <> rest: Bounds(rest,head,head)

def Report.rows(works: List<&2,Work>, +label: String, text: String) -> IO(String):
	match works:
		case Nil{}: IO.pure(String,text)
		case Work{renderer,scene,+samples} <> rest:
			do IO<String>:
				median : N.Binary64 <- H.Host.result(N.Binary64,B.Rows.median(samples),"Median")
				Report.rows(rest,label,text ++ label ++ "\t" ++ renderer ++ "\t" ++ N.Number.json(median) ++ "\t" ++ Range(samples) ++ "\t" ++ Values(List.reverse(&2,N.Binary64,samples)) ++ "\n")

def Report(+output: String, label: String, result: Window & List<&2,Work>) -> IO(Unit):
	(window,works) = result
	do IO<Unit>:
		Window.close(window)
		text : String <- Report.rows(works,label,"configuration\trenderer\tmedian_ms\tmin_ms\tmax_ms\tsamples_ms\n")
		H.Host.mkdir(output)
		H.Host.write(output,text)
		IO.print("Saved " ++ output)

def Work.steps(steps: Bool, spec: K.SceneSpec, schedule: X.Schedule, works: List<&2,Work>) -> List<&2,Work>:
	match steps:
		case False{}: works
		case True{}: Work{"dda-step",C.Scene.build(spec,K.DdaDraw{False{},schedule}),Nil{}} <> works

def Work.reports(works: List<&2,Work>, +frames: K.MeasuredFrames) -> IO(Unit):
	match works:
		case Nil{}: IO.pure(Unit,Unit{})
		case Work{renderer,scene,samples} <> rest:
			do IO<Unit>:
				IO.print(K.Report.line(C.Scene.config(scene,K.Bench{frames})))
				Work.reports(rest,frames)

def Option.value(present: Bool, value: Maybe<&2,String>, fallback: String, flag: String) -> Result<&2,&2,String,String>:
	match present value:
		case True{} None{}: Fail{"Missing value for " ++ flag}
		case False{} None{}: Done{fallback}
		case _ Some{+text}:
			Bool.pick(Result<&2,&2,String,String>,String.starts_with(text,"--"),Fail{"Missing value for " ++ flag},Done{text})

def Option.read(+args: List<&2,String>, +flag: String, fallback: String) -> Result<&2,&2,String,String>:
	Option.value(M.Options.has(args,flag),M.Options.flag(args,flag,False{}),fallback,flag)

def Run(+args: List<&2,String>) -> IO(Unit):
	do IO<Unit>:
		output : String <- H.Host.result(String,Option.read(args,"--output","build/dda-benchmark.tsv"),"Output")
		label : String <- H.Host.result(String,Option.read(args,"--label","runtime"),"Label")
		count_text : String <- H.Host.result(String,Option.read(args,"--frames","12"),"Frames")
		repeat_text : String <- H.Host.result(String,Option.read(args,"--repeats","5"),"Repeats")
		tile_text : String <- H.Host.result(String,Option.read(args,"--tile-depth","6"),"Tile depth")
		fork_text : String <- H.Host.result(String,Option.read(args,"--fork-depth","6"),"Fork depth")
		assignment_text : String <- H.Host.result(String,Option.read(args,"--assignment","contiguous"),"Assignment")
		view_text : String <- H.Host.result(String,Option.read(args,"--view","opening"),"View")
		+count : K.MeasuredFrames <- H.Host.result(K.MeasuredFrames,K.Frames.read(count_text),"Frames")
		+frames : U32 = U32.from_nat(K.Frames.count(count))
		+repeats : U32 <- H.Host.result(U32,B.Decimal.read(repeat_text),"Repeats")
		+tile : X.ForkDepth <- H.Host.result(X.ForkDepth,K.Depth.read(tile_text),"Tile depth")
		+fork : X.ForkDepth <- H.Host.result(X.ForkDepth,K.Depth.read(fork_text),"Fork depth")
		assignment : X.Assignment <- H.Host.result(X.Assignment,K.Read.required(X.Assignment,K.Assignment.read(assignment_text),"Unknown assignment"),"Assignment")
		+schedule : X.Schedule = X.Schedule{fork,assignment}
		+config : K.RunConfig <- H.Host.result(K.RunConfig,K.Config.parse(List.append(&2,String,
			Bool.pick(List<&2,String>,M.Options.has(args,"--cube"),["--cube"],Nil{}),
			List.append(&2,String,Bool.pick(List<&2,String>,M.Options.has(args,"--cut"),["--cut"],Nil{}),["--view",view_text] ))),"Scene")
		+spec : K.SceneSpec = K.RunConfig.scene(config)
		H.Host.require((frames >= 1 : U32) && (repeats >= 5 : U32),"Use at least one frame and five repetitions")
		dda : List<&2,Work> <- IO.pure(List<&2,Work>,[Work{"dda",C.Scene.build(spec,K.DdaDraw{True{},schedule}),Nil{}}])
		faces : List<&2,Work> <- IO.pure(List<&2,Work>,List.append(&2,Work,dda,[Work{"faces",C.Scene.build(spec,K.FaceDraw{False{},tile,fork}),Nil{}}]))
		existing : List<&2,Work> <- IO.pure(List<&2,Work>,List.append(&2,Work,faces,[Work{"existing",C.Scene.build(spec,K.FaceDraw{True{},tile,fork}),Nil{}}]))
		+works : List<&2,Work> <- IO.pure(List<&2,Work>,Work.steps(M.Options.has(args,"--steps"),spec,schedule,existing))
		Work.reports(works,count)
		window : Window <- IO.try(Window,Window.open("Bend DDA comparison",512,512))
		result : Window & List<&2,Work> <- Repeats(U32.to_nat(repeats),1,frames,(window,works))
		Report(output,label,result)

def main() -> IO(Unit):
	IO.bind(List<String>,Unit,IO.args(),args => Run(M.Options.args(args)))
