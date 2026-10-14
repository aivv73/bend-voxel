import Base
import ../dda.bend as X
import ./dda_config.bend as K
import ./benchmark_host.bend as H
import ./benchmark_number.bend as N
import ./benchmark.bend as B

type Execution is Data:
	Cpu{threads: U32}
	GpuRequested{threads: U32}

type PairSpec is Data:
	PairSpec{scene: K.SceneSpec, accepted: X.Schedule, candidate: X.Schedule, frames: K.MeasuredFrames, execution: Execution}

type Samples is Data:
	Samples{accepted: List<&2,N.Binary64>, candidate: List<&2,N.Binary64>, pairs: String}

def Samples.pairs(samples: Samples) -> String:
	Samples{accepted,candidate,pairs} = samples
	pairs

def Report.header() -> String:
	"role\texecution_request\thost_threads_request\tscene_label\teffective_options\tmedian_ms\tmin_ms\tmax_ms\tall_pairs_ms\n"

def Args.linear(args: List<&2,String>) -> List<String>:
	match args:
		case Nil{}: Nil{}
		case head <> rest: head <> Args.linear(rest)

def Execution.read(text: String, threads: U32) -> Result<&2,&2,String,Execution>:
	match text:
		case "off": Done{Cpu{threads}}
		case "on": Done{GpuRequested{threads}}
		case _: Fail{"GPU request must be off or on"}

def Execution.argv(execution: Execution) -> List<&2,String>:
	match execution:
		case Cpu{threads}: ["--gpu","off","--threads",U32.show(threads),"--"]
		case GpuRequested{threads}: ["--gpu","on","--threads",U32.show(threads),"--"]

def Execution.name(execution: Execution) -> String:
	match execution:
		case Cpu{threads}: "cpu"
		case GpuRequested{threads}: "gpu_requested"

def Execution.threads(execution: Execution) -> U32:
	match execution:
		case Cpu{threads}: threads
		case GpuRequested{threads}: threads

def Endpoint.argv(execution: Execution, config: K.RunConfig) -> List<&2,String>:
	List.append(&2,String,Execution.argv(execution),K.Config.argv(config))

def Endpoint.captured(result: Result<&1,&1,U32 & String,U32 & (String & String)>, +raw: String) -> IO(String):
	match result:
		case Fail{(code,+message)}:
			do IO<String>:
				H.Host.write(raw ++ ".failure.txt",message)
				IO.die(String,1,"Renderer process failed to start or complete. " ++ message)
		case Done{(+status,(+stdout,stderr))}:
			do IO<String>:
				H.Host.write(raw,stdout)
				H.Host.write(raw ++ ".stderr.txt",stderr)
				H.Host.write(raw ++ ".exit.txt",U32.show(status) ++ "\n")
				H.Host.require(U32.is_zero(status),"Renderer exited with status " ++ U32.show(status))
				return stdout

def Endpoint.sample(+program: String, +execution: Execution, +config: K.RunConfig, +frames: K.MeasuredFrames, +raw: String) -> IO(N.Binary64):
	do IO<N.Binary64>:
		H.Host.write(raw ++ ".argv.txt",program ++ "\n" ++ String.join(Endpoint.argv(execution,config),"\n") ++ "\n")
		+stdout : String <- IO.bind(Result<&1,&1,U32 & String,U32 & (String & String)>,String,
			Process.run(program,Args.linear(Endpoint.argv(execution,config)),"",4294967295,4294967295),result => Endpoint.captured(result,raw))
		Unit <- H.Host.result(Unit,K.Report.check(config,stdout),"Effective options")
		Unit <- H.Host.result(Unit,K.Runtime.check(Execution.threads(execution),stdout),"Effective host thread count")
		elapsed : N.Elapsed <- H.Host.result(N.Elapsed,B.Scan.measurement(stdout,U32.from_nat(K.Frames.count(frames))),"Completed measurement")
		H.Host.result(N.Binary64,N.Number.sample(elapsed,U32.from_nat(K.Frames.count(frames))),"Complete-window frame sample")

def Pair.config(scene: K.SceneSpec, schedule: X.Schedule, frames: K.MeasuredFrames) -> K.RunConfig:
	K.RunConfig{scene,K.DdaDraw{True{},schedule},K.Bench{frames}}

def Pair.sample(reverse: Bool, +accepted_program: String, +candidate_program: String, +pair: PairSpec, +raw: String) -> IO(N.Binary64 & N.Binary64):
	match reverse:
		case False{}:
			PairSpec{+scene,accepted,candidate,+frames,+execution} = pair
			do IO<N.Binary64 & N.Binary64>:
				a : N.Binary64 <- Endpoint.sample(accepted_program,execution,Pair.config(scene,accepted,frames),frames,raw ++ ".accepted.stdout.txt")
				b : N.Binary64 <- Endpoint.sample(candidate_program,execution,Pair.config(scene,candidate,frames),frames,raw ++ ".candidate.stdout.txt")
				return (a,b)
		case True{}:
			PairSpec{+scene,accepted,candidate,+frames,+execution} = pair
			do IO<N.Binary64 & N.Binary64>:
				b : N.Binary64 <- Endpoint.sample(candidate_program,execution,Pair.config(scene,candidate,frames),frames,raw ++ ".candidate.stdout.txt")
				a : N.Binary64 <- Endpoint.sample(accepted_program,execution,Pair.config(scene,accepted,frames),frames,raw ++ ".accepted.stdout.txt")
				return (a,b)

def Pair.row(+round: U32, reverse: Bool, sample: N.Binary64 & N.Binary64, samples: Samples) -> Samples:
	(+a,+b) = sample
	Samples{old,new,pairs} = samples
	Samples{a <> old,b <> new,pairs ++ U32.show(round) ++ "\t" ++ Bool.pick(String,reverse,"BA","AB") ++ "\t" ++ N.Number.json(a) ++ "\t" ++ N.Number.json(b) ++ "\n"}

def Pair.repeats(fuel: Nat, +round: U32, +reverse: Bool, +accepted: String, +candidate: String, +pair: PairSpec, +raw: String, samples: Samples) -> IO(Samples):
	match fuel:
		case 0n: IO.pure(Samples,samples)
		case 1n+rest:
			do IO<Samples>:
				sample : N.Binary64 & N.Binary64 <- Pair.sample(reverse,accepted,candidate,pair,raw ++ ".pair" ++ U32.show(round))
				+next : Samples = Pair.row(round,reverse,sample,samples)
				H.Host.write(raw ++ ".pairs.tsv",Samples.pairs(next))
				Pair.repeats(rest,(round + 1 : U32),Bool.not(reverse),accepted,candidate,pair,raw,next)

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

def Report.row(role: String, +config: K.RunConfig, +execution: Execution, +values: List<&2,N.Binary64>) -> IO(String):
	do IO<String>:
		median : N.Binary64 <- H.Host.result(N.Binary64,B.Rows.median(values),"Median")
		return role ++ "\t" ++ Execution.name(execution) ++ "\t" ++ U32.show(Execution.threads(execution)) ++ "\t" ++ K.SceneSpec.label(K.RunConfig.scene(config)) ++ "\t" ++
			K.Report.line(config) ++ "\t" ++ N.Number.json(median) ++ "\t" ++ Range(values) ++ "\t" ++ Values(List.reverse(&2,N.Binary64,values)) ++ "\n"

def Report.samples(accepted_program: String, candidate_program: String, pair: PairSpec, +output: String, samples: Samples) -> IO(String):
	PairSpec{+scene,accepted,candidate,+frames,+execution} = pair
	Samples{a,b,pairs} = samples
	do IO<String>:
		+old : String <- Report.row("accepted",Pair.config(scene,accepted,frames),execution,a)
		+new : String <- Report.row("candidate",Pair.config(scene,candidate,frames),execution,b)
		H.Host.write(output ++ ".pairs.tsv",pairs)
		H.Host.write(output ++ ".programs.txt",accepted_program ++ "\n" ++ candidate_program ++ "\n")
		H.Host.write(output,Report.header() ++ old ++ new)
		return old ++ new

def Pair.run(+accepted: String, +candidate: String, +pair: PairSpec, +output: String) -> IO(String):
	do IO<String>:
		H.Host.mkdir(output)
		samples : Samples <- Pair.repeats(5n,1,False{},accepted,candidate,pair,output,Samples{Nil{},Nil{},"pair\torder\taccepted_ms\tcandidate_ms\n"})
		Report.samples(accepted,candidate,pair,output,samples)

def Sweep.depths() -> List<&2,X.ForkDepth>:
	[X.F4{},X.F5{},X.F6{},X.F7{},X.F8{},X.F9{}]

def Sweep.schedules(depths: List<&2,X.ForkDepth>) -> List<&2,X.Schedule>:
	match depths:
		case Nil{}: Nil{}
		case +depth <> rest: X.Schedule{depth,X.Contiguous{}} <> X.Schedule{depth,X.Interleaved{}} <> Sweep.schedules(rest)

def Sweep.configs(schedules: List<&2,X.Schedule>, +scene: K.SceneSpec, +frames: K.MeasuredFrames, +execution: Execution) -> List<&2,PairSpec>:
	match schedules:
		case Nil{}: Nil{}
		case schedule <> rest: PairSpec{scene,X.Schedule{X.F6{},X.Contiguous{}},schedule,frames,execution} <> Sweep.configs(rest,scene,frames,execution)

def Sweep.scenes(scenes: List<&2,K.SceneSpec>, +frames: K.MeasuredFrames, +execution: Execution) -> List<&2,PairSpec>:
	match scenes:
		case Nil{}: Nil{}
		case scene <> rest:
			List.append(&2,PairSpec,Sweep.configs(Sweep.schedules(Sweep.depths()),scene,frames,execution),Sweep.scenes(rest,frames,execution))

def Sweep.id(pair: PairSpec) -> String:
	PairSpec{scene,accepted,X.Schedule{fork,assignment},frames,execution} = pair
	K.SceneSpec.label(scene) ++ "-" ++ K.Assignment.name(assignment) ++ "-f" ++ Nat.show(X.ForkDepth.nat(fork))

def Sweep.run(pairs: List<&2,PairSpec>, +accepted: String, +candidate: String, +output: String, rows: String) -> IO(Unit):
	match pairs:
		case Nil{}:
			do IO<Unit>:
				H.Host.write(output,Report.header() ++ rows)
				IO.print("Saved " ++ output)
		case +pair <> rest:
			do IO<Unit>:
				IO.print("Pair batch " ++ Sweep.id(pair))
				text : String <- Pair.run(accepted,candidate,pair,output ++ "." ++ Sweep.id(pair) ++ ".tsv")
				+next : String = rows ++ text
				H.Host.write(output,Report.header() ++ next)
				Sweep.run(rest,accepted,candidate,output,next)

def Scenes.read(text: String) -> Result<&2,&2,String,List<&2,K.SceneSpec>>:
	match text:
		case "all": Done{K.SceneSpec.all()}
		case _:
			do Result<&2,&2,String,List<&2,K.SceneSpec>>:
				scene : K.SceneSpec <- K.Read.required(K.SceneSpec,K.SceneSpec.read(text),"Scene must be opening, cut, cube, carved, inside, axis, opposite, or all")
				return [scene]

def Run.sweep(accepted: String, candidate: String, +threads: String, gpu: String, count: String, output: String, scene: String) -> IO(Unit):
	do IO<Unit>:
		+n : U32 <- H.Host.result(U32,B.Decimal.read(threads),"Host threads")
		H.Host.require((n > 0 : U32),"Host threads must be positive")
		execution : Execution <- H.Host.result(Execution,Execution.read(gpu,n),"Execution request")
		frames : K.MeasuredFrames <- H.Host.result(K.MeasuredFrames,K.Frames.read(count),"Measured frames")
		scenes : List<&2,K.SceneSpec> <- H.Host.result(List<&2,K.SceneSpec>,Scenes.read(scene),"Scenes")
		Sweep.run(Sweep.scenes(scenes,frames,execution),accepted,candidate,output,"")

def Run.pair(accepted: String, candidate: String, threads: String, gpu: String, count: String, +output: String, scene: String, aa: String, af: String, ba: String, bf: String) -> IO(Unit):
	do IO<Unit>:
		+n : U32 <- H.Host.result(U32,B.Decimal.read(threads),"Host threads")
		H.Host.require((n > 0 : U32),"Host threads must be positive")
		execution : Execution <- H.Host.result(Execution,Execution.read(gpu,n),"Execution request")
		frames : K.MeasuredFrames <- H.Host.result(K.MeasuredFrames,K.Frames.read(count),"Measured frames")
		spec : K.SceneSpec <- H.Host.result(K.SceneSpec,K.Read.required(K.SceneSpec,K.SceneSpec.read(scene),"Unknown scene"),"Scene")
		a_assignment : X.Assignment <- H.Host.result(X.Assignment,K.Read.required(X.Assignment,K.Assignment.read(aa),"Unknown assignment"),"Accepted assignment")
		a_depth : X.ForkDepth <- H.Host.result(X.ForkDepth,K.Depth.read(af),"Accepted depth")
		b_assignment : X.Assignment <- H.Host.result(X.Assignment,K.Read.required(X.Assignment,K.Assignment.read(ba),"Unknown assignment"),"Candidate assignment")
		b_depth : X.ForkDepth <- H.Host.result(X.ForkDepth,K.Depth.read(bf),"Candidate depth")
		rows : String <- Pair.run(accepted,candidate,PairSpec{spec,X.Schedule{a_depth,a_assignment},X.Schedule{b_depth,b_assignment},frames,execution},output)
		IO.print("Saved " ++ output)

def Args(args: List<String>) -> IO(Unit):
	match args:
		case program <> "sweep" <> accepted <> candidate <> threads <> gpu <> frames <> output <> scene <> Nil{}:
			Run.sweep(accepted,candidate,threads,gpu,frames,output,scene)
		case program <> "pair" <> accepted <> candidate <> threads <> gpu <> frames <> output <> scene <> aa <> af <> ba <> bf <> Nil{}:
			Run.pair(accepted,candidate,threads,gpu,frames,output,scene,aa,af,ba,bf)
		case _: IO.die(Unit,1,"Usage\n  dda-sweep sweep accepted candidate threads off|on frames output.tsv scene|all\n  dda-sweep pair accepted candidate threads off|on frames output.tsv scene accepted-assignment accepted-depth candidate-assignment candidate-depth")

def main() -> IO(Unit):
	IO.bind(List<String>,Unit,IO.args(),Args)
