import Base
import ./image_data.bend as Data
import ./image_fixture.bend as Fixture

type Options is Data:
	Options{root: String, checker: String, test: String}

def Test.result(-A: Data, result: Result<&2, &2, String, A>) -> IO(A):
	match result:
		case Done{value}:
			IO.pure(A, value)
		case Fail{message}:
			IO.die(A, 1, message)

def Test.read(path: String) -> IO(Data.Raster):
	IO.bind(Result<&2, &2, String, Data.Raster>, Data.Raster, Data.Image.read(path), result => Test.result(Data.Raster, result))

def Test.hash(image: Data.Raster, expected: String) -> IO(Unit):
	do IO<Unit>:
		hash : String <- Test.result(String, Data.Image.hash(image))
		Fixture.Fixture.require(String.eq(hash, expected), "Real renderer fixture has an unexpected RGB hash")

def Test.mutate(image: Data.Raster) -> Data.Raster:
	Data.Raster{pixels} = image
	Data.Raster{List.set(&2, U32, pixels, 1n, (17 * 65536 + 24 * 256 + 32 : U32))}

def Test.pixel(pixel: Maybe<&2, U32>, expected: U32) -> IO(Unit):
	match pixel:
		case Some{actual}:
			Fixture.Fixture.require(U32.is_eq(actual, expected), "Mutation changed a sampled pixel")
		case None{}:
			IO.die(Unit, 1, "Missing fixture pixel")

def Test.fixture_samples(+full: Data.Raster, cut: Data.Raster) -> IO(Unit):
	do IO<Unit>:
		Test.pixel(Data.Image.pixel(full, 0, 0), (16 * 65536 + 24 * 256 + 32 : U32))
		Test.pixel(Data.Image.pixel(full, 256, 256), (229 * 65536 + 188 * 256 + 122 : U32))
		Test.pixel(Data.Image.pixel(full, 256, 300), (160 * 65536 + 114 * 256 + 72 : U32))
		changed : U32 <- Test.result(U32, Data.Image.changed(full, cut))
		Fixture.Fixture.require(U32.is_eq(changed, 18520), "Common mutation did not preserve the 18520-pixel delta")

def Test.renderer(+repo: String, path: String, cut: Bool) -> IO(Unit):
	args = Bool.pick(List<String>, cut, ["--cut"], Nil{})
	IO.bind(String, Unit, Fixture.Fixture.process(repo ++ "/build/bend-voxel-rewrite",
		List.append(&1, String, ["--gpu", "off", "--threads", "1", "--tile-depth", "4", "--fork-depth", "0", "--dump", path], args)), output => IO.pure(Unit, Unit{}))

def Test.executables(names: List<&2, String>, +repo: String, +scratch: String) -> IO(Unit):
	match names:
		case Nil{}:
			IO.pure(Unit, Unit{})
		case name <> rest:
			do IO<Unit>:
				Fixture.Fixture.copy(repo ++ "/build/image-fixture", scratch ++ "/build/image-fixture-" ++ name)
				Test.executables(rest, repo, scratch)

def Test.setup(+repo: String, +scratch: String) -> IO(Unit):
	do IO<Unit>:
		String <- Fixture.Fixture.process("mkdir", ["-p", scratch ++ "/build/image-check"])
		Test.renderer(repo, scratch ++ "/build/full.ppm", False{})
		Test.renderer(repo, scratch ++ "/build/cut.ppm", True{})
		+full : Data.Raster <- Test.read(scratch ++ "/build/full.ppm")
		+cut : Data.Raster <- Test.read(scratch ++ "/build/cut.ppm")
		Test.hash(full, "a259f628eaeb04b707de9e5dc960eca4d80007fba2530beb96786cbca7b14a9b")
		Test.hash(cut, "4071d9e26a5a50cf429d4f65c6392fa679d784c2b7671933d4a9f4209e11b49d")
		Test.pixel(Data.Image.pixel(full, 1, 0), (16 * 65536 + 24 * 256 + 32 : U32))
		Test.pixel(Data.Image.pixel(cut, 1, 0), (16 * 65536 + 24 * 256 + 32 : U32))
		+wrong_full : Data.Raster = Test.mutate(full)
		+wrong_cut : Data.Raster = Test.mutate(cut)
		Test.fixture_samples(wrong_full, wrong_cut)
		Fixture.Fixture.image(scratch ++ "/build/full-wrong.ppm", wrong_full)
		Fixture.Fixture.image(scratch ++ "/build/cut-wrong.ppm", wrong_cut)
		Test.executables(["correct", "wrong-both", "wrong-full", "wrong-cut", "no-write"], repo, scratch)

def Test.checker(+checker: String, +scratch: String, mode: String) -> IO(U32 & (String & String)):
	IO.try(U32 & (String & String), Process.run(checker, ["--gpu", "off", "--", "--cpu-only", "--root", scratch, "--binary", "build/image-fixture-" ++ mode], "", 16777216, 180000))

def Test.output_lines(lines: List<&2, String>, +paths: List<&2, String>) -> List<&2, String>:
	match lines:
		case Nil{}:
			List.reverse(&2, String, paths)
		case +line <> rest:
			Test.output_lines(rest, Bool.pick(List<&2, String>, String.starts_with(line, "fixture output="), String.drop(line, 15n) <> paths, paths))

def Test.success_text(+status: U32, +stdout: String, stderr: String) -> IO(List<&2, String>):
	+paths = Test.output_lines(String.lines(stdout), Nil{})
	do IO<List<&2, String>>:
		Fixture.Fixture.require(U32.is_eq(status, 0), "Correct fixture matrix failed " ++ stderr)
		Fixture.Fixture.require(String.contains(stdout, "Image checks passed. Destruction changed 18520 pixels."), "Correct fixture matrix did not finish")
		Fixture.Fixture.require(Nat.is_eq(List.length(&2, String, paths), 8n), "Expected eight successful CPU fixture exports")
		return paths

def Test.success(result: U32 & (String & String)) -> IO(List<&2, String>):
	match result:
		case Tuple{status, Tuple{stdout, stderr}}:
			Test.success_text(status, stdout, stderr)

def Test.failure_text(+label: String, expected: String, +status: U32, stdout: String, +stderr: String) -> IO(List<&2, String>):
	do IO<List<&2, String>>:
		Fixture.Fixture.require(U32.is_eq(status, 1), label ++ " must exit 1, observed " ++ U32.show(status))
		Fixture.Fixture.require(String.contains(stderr, expected), label ++ " failed for the wrong reason " ++ stderr)
		IO.print(label ++ " rejected with the expected diagnostic.")
		return Test.output_lines(String.lines(stdout), Nil{})

def Test.failure(label: String, expected: String, result: U32 & (String & String)) -> IO(List<&2, String>):
	match result:
		case Tuple{status, Tuple{stdout, stderr}}:
			Test.failure_text(label, expected, status, stdout, stderr)

def Test.correct(+checker: String, +scratch: String) -> IO(List<&2, String>):
	IO.bind(U32 & (String & String), List<&2, String>, Test.checker(checker, scratch, "correct"), Test.success)

def Test.golden_case(+checker: String, +scratch: String, +mode: String, scene: String) -> IO(Unit):
	do IO<Unit>:
		result : U32 & (String & String) <- Test.checker(checker, scratch, mode)
		List<&2, String> <- Test.failure(mode, "Golden RGB SHA-256 mismatch for " ++ scene, result)
		return Unit{}

def Test.golden(+checker: String, +scratch: String) -> IO(Unit):
	do IO<Unit>:
		Test.golden_case(checker, scratch, "wrong-both", "full")
		Test.golden_case(checker, scratch, "wrong-full", "full")
		Test.golden_case(checker, scratch, "wrong-cut", "cut")

def Test.disjoint(paths: List<&2, String>, +others: List<&2, String>) -> IO(Unit):
	match paths:
		case Nil{}:
			IO.pure(Unit, Unit{})
		case +path <> +rest:
			do IO<Unit>:
				Fixture.Fixture.require(Bool.not(List.contains(~String, ~String.eq, rest, path)), "Repeated output path within one checker invocation")
				Fixture.Fixture.require(Bool.not(List.contains(~String, ~String.eq, others, path)), "Output path reused across checker invocations")
				Test.disjoint(rest, others)

def Test.exports(paths: List<&2, String>, +scratch: String) -> IO(Unit):
	match paths:
		case Nil{}:
			IO.pure(Unit, Unit{})
		case +path <> rest:
			+scene = Bool.pick(String, String.contains(path, "/cut-"), "cut", "full")
			do IO<Unit>:
				+image : Data.Raster <- Test.read(scratch ++ "/build/" ++ scene ++ ".ppm")
				compared : Result<&2, &2, String, Unit> <- Data.Image.compare(path, image)
				Test.result(Unit, compared)
				Test.exports(rest, scratch)

def Test.old_names() -> List<&2, String>:
	["off-4-0", "off-4-4", "off-5-5", "off-6-6", "on-4-0", "on-4-4", "on-5-5", "on-6-6"]

def Test.seed_old(names: List<&2, String>, +scratch: String, +scene: String) -> IO(List<&2, String>):
	match names:
		case Nil{}:
			IO.pure(List<&2, String>, Nil{})
		case name <> rest:
			+path = scratch ++ "/build/image-check/" ++ scene ++ "-" ++ name ++ ".ppm"
			do IO<List<&2, String>>:
				Fixture.Fixture.copy(scratch ++ "/build/" ++ scene ++ ".ppm", path)
				paths : List<&2, String> <- Test.seed_old(rest, scratch, scene)
				return path <> paths

def Test.missing_result(result: Result<&2, &2, String, Data.Raster>) -> IO(Unit):
	match result:
		case Fail{message}:
			Fixture.Fixture.require(String.starts_with(message, "Image open failed:"), "No-write export failed for the wrong reason")
		case Done{image}:
			IO.die(Unit, 1, "No-write renderer left a readable candidate")

def Test.absent(paths: List<&2, String>) -> IO(Unit):
	match paths:
		case path <> Nil{}:
			do IO<Unit>:
				result : Result<&2, &2, String, Data.Raster> <- Data.Image.read(path)
				Test.missing_result(result)
		case _:
			IO.die(Unit, 1, "No-write checker must attempt exactly one export")

def Test.missing(+checker: String, +scratch: String, previous: List<&2, String>) -> IO(Unit):
	do IO<Unit>:
		old_full : List<&2, String> <- Test.seed_old(Test.old_names(), scratch, "full")
		old_cut : List<&2, String> <- Test.seed_old(Test.old_names(), scratch, "cut")
		+old : List<&2, String> = List.append(&2, String, old_full, old_cut)
		result : U32 & (String & String) <- Test.checker(checker, scratch, "no-write")
		missing : List<&2, String> <- Test.failure("zero-exit renderer without output", "Image open failed:", result)
		Test.absent(missing)
		Test.exports(old, scratch)
		Test.exports(previous, scratch)

def Test.run_case(+checker: String, +scratch: String, test: String, +first: List<&2, String>) -> IO(Unit):
	match test:
		case "golden":
			Test.golden(checker, scratch)
		case "missing":
			Test.missing(checker, scratch, first)
		case "all":
			do IO<Unit>:
				+second : List<&2, String> <- Test.correct(checker, scratch)
				Test.disjoint(first, second)
				Test.exports(first, scratch)
				Test.exports(second, scratch)
				IO.print("Two correct fixture matrices used disjoint readable output paths.")
				Test.golden(checker, scratch)
				Test.missing(checker, scratch, List.append(&2, String, first, second))
		case _:
			IO.die(Unit, 1, "Expected --case all, golden, or missing")

def Test.run(options: Options) -> IO(Unit):
	Options{+root, +checker, test} = options
	do IO<Unit>:
		created : String <- Fixture.Fixture.process("mktemp", ["-d", root ++ "/build/image-regression path.XXXXXX"])
		+scratch : String <- Fixture.Fixture.line(created)
		Test.setup(root, scratch)
		+first : List<&2, String> <- Test.correct(checker, scratch)
		Test.run_case(checker, scratch, test, first)
		IO.print("Image checker process regressions passed.")

def Options.parse(args: List<String>, options: Options) -> IO(Unit):
	match args options:
		case Nil{} _:
			Test.run(options)
		case "--root" <> root <> rest Options{_, checker, test}:
			Options.parse(rest, Options{root, checker, test})
		case "--checker" <> checker <> rest Options{root, _, test}:
			Options.parse(rest, Options{root, checker, test})
		case "--case" <> test <> rest Options{root, checker, _}:
			Options.parse(rest, Options{root, checker, test})
		case _ _:
			IO.die(Unit, 1, "Usage: image-regressions [--root repository] [--checker checker] [--case all|golden|missing]")

def Test.start(args: List<String>) -> IO(Unit):
	match args:
		case +program <> rest:
			+root = Fixture.Fixture.parent(Fixture.Fixture.parent(program))
			Options.parse(rest, Options{root, root ++ "/build/image-checker", "all"})
		case Nil{}:
			IO.die(Unit, 1, "Missing regression executable path")

def main() -> IO(Unit):
	IO.bind(List<String>, Unit, IO.args(), Test.start)
