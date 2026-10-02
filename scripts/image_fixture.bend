import Base
import ./image_data.bend as Data
import ../dump.bend as Dump

type Mode is Data:
	Correct{}
	WrongBoth{}
	WrongFull{}
	WrongCut{}
	NoWrite{}

type Export is Data:
	Export{cut: Bool, path: String}

def Fixture.require(ok: Bool, message: String) -> IO(Unit):
	match ok:
		case True{}:
			IO.pure(Unit, Unit{})
		case False{}:
			IO.die(Unit, 1, message)

def Fixture.parent_reverse(path: String) -> String:
	match path:
		case SNil{}:
			"."
		case SCon{'/', SNil{}}:
			"/"
		case SCon{'/', rest}:
			String.reverse(rest)
		case SCon{_, rest}:
			Fixture.parent_reverse(rest)

def Fixture.parent(path: String) -> String:
	Fixture.parent_reverse(String.reverse(path))

def Fixture.line_reverse(text: String) -> IO(String):
	match text:
		case SCon{'\n', rest}:
			do IO<String>:
				+path : String = String.reverse(rest)
				Fixture.require(Bool.not(String.is_empty(path)) && Bool.not(String.contains(path, "\n")), "Expected one nonempty output path")
				return path
		case _:
			IO.die(String, 1, "Expected a newline-terminated output path")

def Fixture.line(text: String) -> IO(String):
	Fixture.line_reverse(String.reverse(text))

def Fixture.process_done(+program: String, result: U32 & (String & String)) -> IO(String):
	(+status, output) = result
	(stdout, stderr) = output
	do IO<String>:
		Fixture.require(U32.is_eq(status, 0), program ++ " failed with exit " ++ U32.show(status) ++ " " ++ stderr)
		return stdout

def Fixture.process(+program: String, args: List<String>) -> IO(String):
	IO.bind(U32 & (String & String), String, IO.try(U32 & (String & String), Process.run(program, args, "", 16777216, 180000)), result => Fixture.process_done(program, result))

def Fixture.copy(source: String, target: String) -> IO(Unit):
	IO.bind(String, Unit, Fixture.process("cp", ["--", source, target]), output => IO.pure(Unit, Unit{}))

def Fixture.written(written: File & Result<&1, &1, U32 & String, Unit>) -> IO(File):
	match written:
		case (file, Done{value}):
			IO.pure(File, file)
		case (file, Fail{(code, message)}):
			do IO<File>:
				File.close(file)
				IO.die(File, 1, message)

def Fixture.row(fuel: Nat, pixels: List<&2, U32>, text: String) -> List<&2, U32> & String:
	match fuel pixels:
		case 0n _:
			(pixels, text ++ "\n")
		case 1n+rest pixel <> tail:
			Fixture.row(rest, tail, text ++ Dump.Dump.rgb(pixel))
		case _ Nil{}:
			(Nil{}, text)

def Fixture.rows_step(row: List<&2, U32> & String, file: File) -> IO(List<&2, U32> & File):
	(tail, text) = row
	do IO<List<&2, U32> & File>:
		next : File <- IO.bind(File & Result<&1, &1, U32 & String, Unit>, File, File.write(file, text), Fixture.written)
		return (tail, next)

def Fixture.rows(fuel: Nat, state: List<&2, U32> & File) -> IO(Unit):
	match fuel state:
		case 0n Tuple{_, file}:
			File.close(file)
		case 1n+rest Tuple{pixels, file}:
			IO.bind(List<&2, U32> & File, Unit, Fixture.rows_step(Fixture.row(512n, pixels, ""), file), row => Fixture.rows(rest, row))

def Fixture.image(path: String, image: Data.Raster) -> IO(Unit):
	Data.Raster{pixels} = image
	do IO<Unit>:
		file : File <- IO.try(File, File.open(path, "w"))
		header : File <- IO.bind(File & Result<&1, &1, U32 & String, Unit>, File, File.write(file, "P3\n512 512\n255\n"), Fixture.written)
		Fixture.rows(512n, (pixels, header))

def Mode.pick(both: Bool, full: Bool, cut: Bool, no_write: Bool) -> Mode:
	match both full cut no_write:
		case True{} _ _ _:
			WrongBoth{}
		case _ True{} _ _:
			WrongFull{}
		case _ _ True{} _:
			WrongCut{}
		case _ _ _ True{}:
			NoWrite{}
		case _ _ _ _:
			Correct{}

def Mode.read(+program: String) -> Mode:
	Mode.pick(String.ends_with(program, "-wrong-both"), String.ends_with(program, "-wrong-full"), String.ends_with(program, "-wrong-cut"), String.ends_with(program, "-no-write"))

def Mode.wrong(mode: Mode, cut: Bool) -> Bool:
	match mode:
		case WrongBoth{}:
			True{}
		case WrongFull{}:
			Bool.not(cut)
		case WrongCut{}:
			cut
		case _:
			False{}

def Fixture.args(args: List<String>, cut: Bool, path: String) -> Export:
	match args:
		case Nil{}:
			Export{cut, path}
		case "--dump" <> value <> rest:
			Fixture.args(rest, cut, value)
		case "--cut" <> rest:
			Fixture.args(rest, True{}, path)
		case _ <> rest:
			Fixture.args(rest, cut, path)

def Fixture.write(mode: Mode, directory: String, +cut: Bool, path: String) -> IO(Unit):
	match mode:
		case NoWrite{}:
			IO.pure(Unit, Unit{})
		case writer:
			name = Bool.pick(String, cut, "cut", "full")
			suffix = Bool.pick(String, Mode.wrong(writer, cut), "-wrong", "")
			Fixture.copy(directory ++ "/" ++ name ++ suffix ++ ".ppm", path)

def Fixture.export(mode: Mode, directory: String, export: Export) -> IO(Unit):
	Export{cut, +path} = export
	do IO<Unit>:
		Fixture.require(Bool.not(String.is_empty(path)), "Fixture requires --dump")
		IO.print("fixture output=" ++ path)
		Fixture.write(mode, directory, cut, path)

def Fixture.start(args: List<String>) -> IO(Unit):
	match args:
		case +program <> rest:
			Fixture.export(Mode.read(program), Fixture.parent(program), Fixture.args(rest, False{}, ""))
		case Nil{}:
			IO.die(Unit, 1, "Missing fixture executable path")

def main() -> IO(Unit):
	IO.bind(List<String>, Unit, IO.args(), Fixture.start)
