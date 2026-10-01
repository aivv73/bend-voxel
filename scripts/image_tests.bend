import Base
import ./image_data.bend as Data

def Test.require(ok: Bool, message: String) -> IO(Unit):
	match ok:
		case True{}:
			IO.pure(Unit, Unit{})
		case False{}:
			IO.die(Unit, 1, message)

def Test.result(-A: Data, result: Result<&2, &2, String, A>) -> IO(A):
	match result:
		case Done{value}:
			IO.pure(A, value)
		case Fail{message}:
			IO.die(A, 1, message)

def Test.failed(-A: Data, result: Result<&2, &2, String, A>, label: String) -> IO(Unit):
	match result:
		case Fail{message}:
			IO.pure(Unit, Unit{})
		case Done{value}:
			IO.die(Unit, 1, "Accepted invalid " ++ label)

def Test.error(-A: Data, result: Result<&2, &2, String, A>, expected: String) -> IO(Unit):
	match result:
		case Fail{message}:
			Test.require(String.eq(message, expected), "Invalid input failed for the wrong reason")
		case Done{value}:
			IO.die(Unit, 1, "Accepted invalid input")

def Test.bytes(text: String) -> List<&2, U32>:
	match text:
		case SNil{}:
			Nil{}
		case SCon{head, rest}:
			Char.to_u32(head) <> Test.bytes(rest)

def Test.scanned(scanned: Data.Scan & U32) -> Data.Scan:
	(state, count) = scanned
	state

def Test.feed(parts: List<&2, String>, state: Data.Scan) -> Data.Scan:
	match parts:
		case Nil{}:
			state
		case part <> rest:
			Test.feed(rest, Test.scanned(Data.Parse.feed(Test.bytes(part), state, 0)))

def Test.fragmented(state: Data.Scan) -> IO(Unit):
	match state:
		case Data.Channels{True{}, 3, 2, 258, 0, Data.Save{Nil{}}}:
			IO.pure(Unit, Unit{})
		case _:
			IO.die(Unit, 1, "Fragmented header or channel token was parsed incorrectly")

def Test.final_pixel(state: Data.Scan) -> IO(Unit):
	match state:
		case Data.Channels{False{}, 0, 0, 0, 1, Data.Save{66051 <> Nil{}}}:
			IO.pure(Unit, Unit{})
		case _:
			IO.die(Unit, 1, "RGB packing or token delimiter was parsed incorrectly")

def Test.progress(result: Result<&2, &2, String, U32>, expected: U32) -> IO(Unit):
	match result:
		case Done{offset}:
			Test.require(U32.is_eq(offset, expected), "Short-read progress offset differs")
		case Fail{message}:
			IO.die(Unit, 1, message)

def Test.boundaries() -> IO(Unit):
	+partial = Test.feed(["P", "3 ", "5", "12\t51", "2\n2", "55\r", "00", "1 2", " 03"], Data.Parse.start(Data.Save{Nil{}}))
	do IO<Unit>:
		Test.fragmented(partial)
		Test.final_pixel(Data.Parse.byte(32, partial))
		Test.progress(Data.Read.progress(8, 0, 1), 1)
		Test.progress(Data.Read.progress(8, 1, 2), 3)
		Test.progress(Data.Read.progress(8, 3, 1), 4)
		Test.progress(Data.Read.progress(8, 4, 4), 8)
		Test.progress(Data.Read.progress(8, 8, 0), 8)
		Test.failed(U32, Data.Read.progress(8, 7, 0), "premature EOF")
		Test.failed(U32, Data.Read.progress(8, 0, 9), "overlong read")
		Test.failed(U32, Data.Read.progress(8, 4294967295, 1), "wrapped offset")
		Test.error(Data.Parsed, Data.Read.eof_result(Done{[32]}, Data.Parse.start(Data.Save{Nil{}})), "Image file has an unread suffix or changed size")
		IO.print("Fragmented parser and short-read progress checks passed.")

def Test.write_result(written: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
	(file, result) = written
	do IO<Unit>:
		File.close(file)
		IO.pass(Unit, result)

def Test.write(path: String, text: String) -> IO(Unit):
	do IO<Unit>:
		file : File <- IO.try(File, File.open(path, "w"))
		IO.bind(File & Result<&1, &1, U32 & String, Unit>, Unit, File.write(file, text), Test.write_result)

def Test.written(written: File & Result<&1, &1, U32 & String, Unit>) -> IO(File):
	match written:
		case (file, Done{value}):
			IO.pure(File, file)
		case (file, Fail{(code, message)}):
			do IO<File>:
				File.close(file)
				IO.die(File, 1, message)

def Test.rows(fuel: Nat, file: File, +row: String) -> IO(File):
	match fuel:
		case 0n:
			IO.pure(File, file)
		case 1n+rest:
			IO.bind(File & Result<&1, &1, U32 & String, Unit>, File, File.write(file, row),
				written => IO.bind(File, File, Test.written(written), next => Test.rows(rest, next, row)))

def Test.fixture(path: String, first: String, last: String) -> IO(Unit):
	+row = String.repeat("1 2 3 ", 512n)
	do IO<Unit>:
		file : File <- IO.try(File, File.open(path, "w"))
		header : File <- IO.bind(File & Result<&1, &1, U32 & String, Unit>, File, File.write(file, "P3\t512\r512\n255\n"), Test.written)
		first : File <- IO.bind(File & Result<&1, &1, U32 & String, Unit>, File, File.write(header, first), Test.written)
		middle : File <- Test.rows(510n, first, row)
		IO.bind(File & Result<&1, &1, U32 & String, Unit>, Unit, File.write(middle, last), Test.write_result)

type Malformed is Data:
	Malformed{name: String, text: String, error: String}

def Test.malformed_cases() -> List<&2, Malformed>:
	+header = {"Expected literal P3 512 512 255 header tokens" : String}
	+range = {"Channel is out of range or image has extra channels" : String}
	+digit = {"Expected an unsigned ASCII channel in 0..255" : String}
	+count = {"Expected exactly 786432 RGB channels" : String}
	[Malformed{"magic", "P6 512 512 255\n", header},
	 Malformed{"width", "P3 511 512 255\n", header},
	 Malformed{"header-zero", "P3 0512 512 255\n", header},
	 Malformed{"merged-header", "P3512 512 255\n", header},
	 Malformed{"comment", "P3 # pixels\n512 512 255\n", header},
	 Malformed{"range", "P3 512 512 255\n256 0 0", range},
	 Malformed{"overflow", "P3 512 512 255\n4294967296 0 0", range},
	 Malformed{"negative", "P3 512 512 255\n-1 0 0", digit},
	 Malformed{"positive-sign", "P3 512 512 255\n+1 0 0", digit},
	 Malformed{"underscore", "P3 512 512 255\n1_0 0 0", digit},
	 Malformed{"unicode", "P3 512 512 255\n１ 0 0", digit},
	 Malformed{"nondigit", "P3 512 512 255\n1x 0 0", digit},
	 Malformed{"missing", "P3 512 512 255\n", count},
	 Malformed{"truncated", "P3 512 512 255\n1 2", count}]

def Test.malformed(cases: List<&2, Malformed>, +directory: String) -> IO(Unit):
	match cases:
		case Nil{}:
			IO.pure(Unit, Unit{})
		case Malformed{name, text, +expected} <> rest:
			+path = directory ++ "/" ++ name ++ ".ppm"
			do IO<Unit>:
				Test.write(path, text)
				result : Result<&2, &2, String, Data.Raster> <- Data.Image.read(path)
				Test.error(Data.Raster, result, expected)
				fragmented : Result<&2, &2, String, Data.Parsed> <- Data.Read.file(path, 1, Data.Save{Nil{}})
				Test.error(Data.Parsed, fragmented, expected)
				Test.malformed(rest, directory)

def Test.pixel(value: Maybe<&2, U32>, expected: U32) -> IO(Unit):
	match value:
		case Some{actual}:
			Test.require(U32.is_eq(actual, expected), "Packed fixture pixel differs")
		case None{}:
			IO.die(Unit, 1, "Missing fixture pixel")

def Test.bounds(value: Maybe<&2, U32>) -> IO(Unit):
	match value:
		case None{}:
			IO.pure(Unit, Unit{})
		case Some{actual}:
			IO.die(Unit, 1, "Out-of-bounds pixel aliased a valid pixel")

def Test.append(path: String, text: String) -> IO(Unit):
	do IO<Unit>:
		file : File <- IO.try(File, File.open(path, "a"))
		IO.bind(File & Result<&1, &1, U32 & String, Unit>, Unit, File.write(file, text), Test.write_result)

def Test.compare_chunks(path: String, image: Data.Raster) -> IO(Result<&2, &2, String, Data.Parsed>):
	Data.Raster{pixels} = image
	Data.Read.file(path, 257, Data.Compare{pixels, True{}})

def Test.images(+directory: String) -> IO(Unit):
	+uniform = directory ++ "/uniform.ppm"
	+changed = directory ++ "/changed.ppm"
	+extra_path = directory ++ "/extra.ppm"
	+last = String.repeat("1 2 3 ", 511n) ++ "1 2 3"
	do IO<Unit>:
		Test.fixture(uniform, "001\t02\r3\n" ++ String.repeat("1 2 3 ", 511n), last)
		Test.fixture(changed, "4 5 6 1 2 9 " ++ String.repeat("1 2 3 ", 510n), last)
		parsed : Result<&2, &2, String, Data.Raster> <- Data.Image.read(uniform)
		+image : Data.Raster <- Test.result(Data.Raster, parsed)
		Test.pixel(Data.Image.pixel(image, 0, 0), 66051)
		Test.pixel(Data.Image.pixel(image, 511, 511), 66051)
		Test.bounds(Data.Image.pixel(image, 512, 0))
		Test.bounds(Data.Image.pixel(image, 0, 512))
		Test.bounds(Data.Image.pixel(image, 4294967295, 4294967295))
		matched : Result<&2, &2, String, Unit> <- Data.Image.compare(uniform, image)
		Test.result(Unit, matched)
		mismatch : Result<&2, &2, String, Unit> <- Data.Image.compare(changed, image)
		Test.failed(Unit, mismatch, "changed exact comparison")
		other : Result<&2, &2, String, Data.Raster> <- Data.Image.read(changed)
		other : Data.Raster <- Test.result(Data.Raster, other)
		count : U32 <- Test.result(U32, Data.Image.changed(image, other))
		Test.require(U32.is_eq(count, 2), "Expected two changed pixels, including one with three changed channels")
		fragmented : Result<&2, &2, String, Data.Parsed> <- Test.compare_chunks(uniform, image)
		checked : Data.Parsed <- Test.result(Data.Parsed, fragmented)
		Test.fixture(extra_path, String.repeat("1 2 3 ", 512n), last)
		Test.append(extra_path, " 4")
		extra : Result<&2, &2, String, Data.Raster> <- Data.Image.read(extra_path)
		Test.failed(Data.Raster, extra, "extra channel suffix")
		IO.print("Complete-file, exact pixel, bounds, delta, and EOF checks passed.")

def Test.process(result: U32 & (String & String)) -> IO(Unit):
	(status, output) = result
	Test.require(U32.is_eq(status, 0), "Fixture directory setup failed")

def Test.all(+directory: String) -> IO(Unit):
	do IO<Unit>:
		IO.bind(U32 & (String & String), Unit, IO.try(U32 & (String & String), Process.run("mkdir", ["-p", directory], "", 1048576, 30000)), Test.process)
		Test.boundaries()
		Test.malformed(Test.malformed_cases(), directory)
		Test.images(directory)
		IO.print("Image parser runtime checks passed.")

def Inspect.loaded(+image: Data.Raster) -> IO(Unit):
	do IO<Unit>:
		hash : String <- Test.result(String, Data.Image.hash(image))
		IO.print("RGB sha256=" ++ hash)
		IO.print("Image input valid.")

def Inspect.input(path: String, chunk: U32) -> IO(Unit):
	do IO<Unit>:
		parsed : Result<&2, &2, String, Data.Parsed> <- Data.Read.file(path, chunk, Data.Save{Nil{}})
		image : Data.Raster <- Test.result(Data.Raster, Data.Image.retained(parsed))
		Inspect.loaded(image)

def Inspect.compare(+path: String, other: String) -> IO(Unit):
	do IO<Unit>:
		parsed : Result<&2, &2, String, Data.Raster> <- Data.Image.read(path)
		+image : Data.Raster <- Test.result(Data.Raster, parsed)
		compared : Result<&2, &2, String, Unit> <- Data.Image.compare(other, image)
		Test.result(Unit, compared)
		IO.print("Exact RGB image equal.")
		Inspect.loaded(image)

def Test.mode(output: Bool, input: Bool, path: String) -> IO(Unit):
	match output input:
		case True{} False{}:
			Test.all(path)
		case False{} True{}:
			Inspect.input(path, 8192)
		case _ _:
			IO.die(Unit, 1, "Usage: image-tests [--output directory | --input ppm [--compare ppm | --chunk bytes]]")

def Inspect.chunk(value: Maybe<&2, U32>, path: String) -> IO(Unit):
	match value:
		case Some{chunk}:
			Inspect.input(path, chunk)
		case None{}:
			IO.die(Unit, 1, "Invalid read chunk")

def Inspect.option(input: Bool, compare: Bool, chunk: Bool, path: String, value: String) -> IO(Unit):
	match input compare chunk:
		case True{} True{} False{}:
			Inspect.compare(path, value)
		case True{} False{} True{}:
			Inspect.chunk(U32.read(value), path)
		case _ _ _:
			IO.die(Unit, 1, "Usage: image-tests --input ppm [--compare ppm | --chunk bytes]")

def Test.args(args: List<String>) -> IO(Unit):
	match args:
		case Nil{}:
			Test.all("build/image-fixtures")
		case Con{+flag, Con{path, Nil{}}}:
			Test.mode(String.eq(flag, "--output"), String.eq(flag, "--input"), path)
		case Con{flag, Con{path, Con{+option, Con{value, Nil{}}}}}:
			Inspect.option(String.eq(flag, "--input"), String.eq(option, "--compare"), String.eq(option, "--chunk"), path, value)
		case _:
			IO.die(Unit, 1, "Usage: image-tests [--output directory | --input ppm [--compare ppm | --chunk bytes]]")

def Test.start(args: List<String>) -> IO(Unit):
	match args:
		case program <> rest:
			Test.args(rest)
		case Nil{}:
			Test.args(Nil{})

def main() -> IO(Unit):
	IO.bind(List<String>, Unit, IO.args(), Test.start)
