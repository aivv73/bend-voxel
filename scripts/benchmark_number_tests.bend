import Base
import ./benchmark_number.bend as N

type Input is Data:
	Input{high: U32, low: U32, frames: U32}

def Check.require(ok: Bool, message: String) -> IO(Unit):
	match ok:
		case True{}:
			IO.pure(Unit, Unit{})
		case False{}:
			IO.die(Unit, 1, message)

def Check.words(value: N.Binary64, +name: String, expected_high: U32, expected_low: U32) -> IO(Unit):
	N.Binary64{+high, +low} = value
	Check.require(U32.is_eq(high, expected_high) && U32.is_eq(low, expected_low),
		name ++ " words differ: " ++ U32.show(high) ++ "," ++ U32.show(low))

def Check.format(+value: N.Binary64, +name: String, expected: String) -> IO(Unit):
	+actual = N.Number.fixed3(value)
	Check.require(String.eq(actual, expected), name ++ " fixed3 differs: " ++ actual)

def Check.json(+value: N.Binary64, +name: String, expected: String) -> IO(Unit):
	+actual = N.Number.json(value)
	Check.require(String.eq(actual, expected), name ++ " JSON differs: " ++ actual)

def Check.result(result: Result<&2, &2, String, N.Binary64>, +name: String,
	high: U32, low: U32, fixed: String, json: String) -> IO(Unit):
	match result:
		case Fail{error}:
			IO.die(Unit, 1, name ++ " failed: " ++ error)
		case Done{+value}:
			do IO<Unit>:
				Check.words(value, name, high, low)
				Check.format(value, name, fixed)
				Check.json(value, name, json)

def Check.parsed(result: Result<&2, &2, String, N.Elapsed>, +name: String,
	frames: U32, high: U32, low: U32, fixed: String, json: String) -> IO(Unit):
	match result:
		case Fail{error}:
			IO.die(Unit, 1, name ++ " parse failed: " ++ error)
		case Done{elapsed}:
			Check.result(N.Number.sample(elapsed, frames), name, high, low, fixed, json)

def Check.sample(text: String, frames: U32, +name: String,
	high: U32, low: U32, fixed: String, json: String) -> IO(Unit):
	Check.parsed(N.Elapsed.read(text), name, frames, high, low, fixed, json)

def Check.elapsed(result: Result<&2, &2, String, N.Elapsed>, +name: String, high: U32, low: U32) -> IO(Unit):
	match result:
		case Fail{error}:
			IO.die(Unit, 1, name ++ " parse failed: " ++ error)
		case Done{N.Elapsed{actual_high, actual_low}}:
			Check.require(U32.is_eq(actual_high, high) && U32.is_eq(actual_low, low), name ++ " elapsed words differ")

def Check.bad_elapsed(result: Result<&2, &2, String, N.Elapsed>, +name: String, expected: String) -> IO(Unit):
	match result:
		case Done{value}:
			IO.die(Unit, 1, name ++ " accepted invalid elapsed")
		case Fail{error}:
			Check.require(String.eq(error, expected), name ++ " error differs")

def Check.bad_sample(result: Result<&2, &2, String, N.Binary64>, +name: String, expected: String) -> IO(Unit):
	match result:
		case Done{value}:
			IO.die(Unit, 1, name ++ " accepted invalid sample")
		case Fail{error}:
			Check.require(String.eq(error, expected), name ++ " error differs")

def Check.order(actual: Cmp, expected: Cmp, name: String) -> IO(Unit):
	match actual expected:
		case LT{} LT{}:
			IO.pure(Unit, Unit{})
		case EQ{} EQ{}:
			IO.pure(Unit, Unit{})
		case GT{} GT{}:
			IO.pure(Unit, Unit{})
		case _ _:
			IO.die(Unit, 1, name ++ " numeric order differs")

def Check.samples() -> IO(Unit):
	do IO<Unit>:
		Check.sample("0", 1, "zero", 0, 0, "0.000", "0.0")
		Check.sample("000001", 1, "leading zeros", 1072693248, 0, "1.000", "1.0")
		Check.sample("1", 2, "half", 1071644672, 0, "0.500", "0.5")
		Check.sample("1", 3, "third", 1070945621, 1431655765, "0.333",
			"0.333333333333333314829616256247390992939472198486328125")
		Check.sample("2", 3, "two thirds", 1071994197, 1431655765, "0.667",
			"0.66666666666666662965923251249478198587894439697265625")
		Check.sample("1", 2000, "stored value above decimal half", 1061184077, 3539053052, "0.001",
			"0.0005000000000000000104083408558608425664715468883514404296875")
		Check.sample("50", 32, "even three-place tie", 1073283072, 0, "1.562", "1.5625")
		Check.sample("51", 32, "three-place round up", 1073315840, 0, "1.594", "1.59375")
		Check.sample("1", 4294967295, "minimum positive ratio", 1039138816, 1048576, "0.000",
			"0.0000000002328306437080797375305252217003726400434970855712890625")
		Check.sample("4294967296", 3, "elapsed low carry", 1104500053, 1431655765, "1431655765.333",
			"1431655765.3333332538604736328125")
		Check.sample("281474976710655", 1, "largest elapsed", 1123024895, 4294967264,
			"281474976710655.000", "281474976710655.0")
		Check.sample("281474976710655", 4294967295, "largest numerator and denominator", 1089470464, 1048560,
			"65536.000", "65536.00001525855623185634613037109375")
		Check.sample("65535", 65536, "just below one", 1072693216, 0, "1.000", "0.9999847412109375")
		Check.sample("2147483648", 4294967295, "remainder high bit", 1071644672, 1048576,
			"0.500", "0.500000000116415321826934814453125")
		Check.sample("281474976710654", 24, "large fractional value", 1118131541, 1431655723,
			"11728124029610.584", "11728124029610.583984375")

def Check.presentation() -> IO(Unit):
	do IO<Unit>:
		Check.format(N.Binary64{1068498943, 4294967295}, "below even half", "0.062")
		Check.format(N.Binary64{1068498944, 0}, "exact even half", "0.062")
		Check.format(N.Binary64{1068498944, 1}, "above even half", "0.063")
		Check.format(N.Binary64{1070071807, 4294967295}, "below odd half", "0.187")
		Check.format(N.Binary64{1070071808, 0}, "exact odd half", "0.188")
		Check.format(N.Binary64{1070071808, 1}, "above odd half", "0.188")
		Check.format(N.Binary64{1073283071, 4294967295}, "below large even half", "1.562")
		Check.format(N.Binary64{1073283072, 0}, "exact large even half", "1.562")
		Check.format(N.Binary64{1073283072, 1}, "above large even half", "1.563")
		Check.format(N.Binary64{1061184077, 3539053051}, "below nondyadic half", "0.000")
		Check.format(N.Binary64{1061184077, 3539053052}, "above nondyadic half", "0.001")
		Check.format(N.Binary64{1072693247, 4294967295}, "format decimal carry", "1.000")
		Check.json(N.Binary64{1072693248, 1}, "retained low bit",
			"1.0000000000000002220446049250313080847263336181640625")

def Check.midpoints() -> IO(Unit):
	do IO<Unit>:
		Check.words(N.Number.midpoint(N.Binary64{0, 0}, N.Binary64{0, 0}), "zero mean", 0, 0)
		Check.words(N.Number.midpoint(N.Binary64{0, 0}, N.Binary64{1072693248, 0}), "zero and one", 1071644672, 0)
		Check.words(N.Number.midpoint(N.Binary64{1072693248, 0}, N.Binary64{0, 0}), "one and zero", 1071644672, 0)
		Check.words(N.Number.midpoint(N.Binary64{1072693248, 0}, N.Binary64{1073741824, 0}), "one and two", 1073217536, 0)
		Check.words(N.Number.midpoint(N.Binary64{1073741824, 0}, N.Binary64{1072693248, 0}), "two and one", 1073217536, 0)
		Check.words(N.Number.midpoint(N.Binary64{1070945621, 1431655765}, N.Binary64{1071994197, 1431655765}),
			"two rounded thirds", 1071644672, 0)
		Check.words(N.Number.midpoint(N.Binary64{1072693248, 0}, N.Binary64{1072693248, 1}), "mean tie down", 1072693248, 0)
		Check.words(N.Number.midpoint(N.Binary64{1072693248, 1}, N.Binary64{1072693248, 2}), "mean tie up", 1072693248, 2)
		Check.words(N.Number.midpoint(N.Binary64{1073741823, 4294967295}, N.Binary64{1073741824, 0}),
			"mean mantissa carry", 1073741824, 0)
		Check.words(N.Number.midpoint(N.Binary64{1123024895, 4294967264}, N.Binary64{1039138816, 1048576}),
			"wide exponent gap", 1121976319, 4294967264)
		Check.words(N.Number.midpoint(N.Binary64{1123024895, 4294967264}, N.Binary64{1123024895, 4294967264}),
			"largest mean", 1123024895, 4294967264)
		Check.order(N.Number.compare(N.Binary64{0, 0}, N.Binary64{1039138816, 1048576}), LT{}, "zero order")
		Check.order(N.Number.compare(N.Binary64{1072693248, 1}, N.Binary64{1072693248, 0}), GT{}, "low-word order")
		Check.order(N.Number.compare(N.Binary64{1072693248, 1}, N.Binary64{1072693248, 1}), EQ{}, "equal order")

def Check.guards() -> IO(Unit):
	+syntax = {"elapsed_ms must be nonempty unsigned ASCII decimal" : String}
	+range = {"elapsed_ms exceeds 281474976710655" : String}
	do IO<Unit>:
		Check.elapsed(N.Elapsed.read("000000000000000000000"), "all zero digits", 0, 0)
		Check.elapsed(N.Elapsed.read("4294967296"), "elapsed word carry", 1, 0)
		Check.elapsed(N.Elapsed.read("000281474976710655"), "elapsed upper bound", 65535, 4294967295)
		Check.bad_elapsed(N.Elapsed.read(""), "empty", syntax)
		Check.bad_elapsed(N.Elapsed.read("-1"), "negative", syntax)
		Check.bad_elapsed(N.Elapsed.read("+1"), "positive sign", syntax)
		Check.bad_elapsed(N.Elapsed.read(" 1"), "leading space", syntax)
		Check.bad_elapsed(N.Elapsed.read("1 "), "trailing space", syntax)
		Check.bad_elapsed(N.Elapsed.read("1.0"), "decimal point", syntax)
		Check.bad_elapsed(N.Elapsed.read("1x"), "suffix", syntax)
		Check.bad_elapsed(N.Elapsed.read("١"), "Unicode digit", syntax)
		Check.bad_elapsed(N.Elapsed.read("281474976710656"), "elapsed above bound", range)
		Check.bad_elapsed(N.Elapsed.read("999999999999999999999999"), "long overflow", range)
		Check.bad_sample(N.Number.sample(N.Elapsed{0, 1}, 0), "zero denominator", "frame denominator must be positive")
		Check.bad_sample(N.Number.sample(N.Elapsed{65536, 0}, 1), "forged elapsed above bound", range)

def Check.run() -> IO(Unit):
	do IO<Unit>:
		Check.samples()
		Check.presentation()
		Check.midpoints()
		Check.guards()
		IO.print("Benchmark number tests passed: literal ratios, mean ties, decimal half neighbors, exact JSON and input guards")

def Dump.value(+value: N.Binary64) -> String:
	N.Binary64{high, low} = value
	"{\"high\":" ++ U32.show(high) ++ ",\"low\":" ++ U32.show(low) ++
		",\"fixed3\":\"" ++ N.Number.fixed3(value) ++ "\",\"value\":" ++ N.Number.json(value) ++ "}"

def Input.json(input: Input) -> String:
	Input{high, low, frames} = input
	"{\"elapsed_high\":" ++ U32.show(high) ++ ",\"elapsed_low\":" ++ U32.show(low) ++ ",\"frames\":" ++ U32.show(frames) ++ "}"

def Input.sample(input: Input) -> Result<&2, &2, String, N.Binary64>:
	Input{high, low, frames} = input
	N.Number.sample(N.Elapsed{high, low}, frames)

def Dump.pair(left: Result<&2, &2, String, N.Binary64>, right: Result<&2, &2, String, N.Binary64>,
	left_input: Input, right_input: Input) -> IO(Unit):
	match left right:
		case Fail{error} _:
			IO.die(Unit, 1, error)
		case Done{value} Fail{error}:
			IO.die(Unit, 1, error)
		case Done{+left_value} Done{+right_value}:
			IO.print("{\"left_input\":" ++ Input.json(left_input) ++ ",\"right_input\":" ++ Input.json(right_input) ++
				",\"left\":" ++ Dump.value(left_value) ++ ",\"right\":" ++ Dump.value(right_value) ++
				",\"mean\":" ++ Dump.value(N.Number.midpoint(left_value, right_value)) ++ "}")

def Dump.next(seed: U32) -> U32:
	(seed * 1664525 + 1013904223 : U32)

def Dump.loop(count: Nat, +seed: U32) -> IO(Unit):
	match count:
		case 0n:
			IO.pure(Unit, Unit{})
		case 1n+rest:
			+a = Dump.next(seed)
			+b = Dump.next(a)
			+c = Dump.next(b)
			+d = Dump.next(c)
			+e = Dump.next(d)
			+left = {Input{(seed .&. 65535 : U32), a, U32.max(b, 1)} : Input}
			+right = {Input{(c .&. 65535 : U32), d, U32.max(e, 1)} : Input}
			do IO<Unit>:
				Dump.pair(Input.sample(left), Input.sample(right), left, right)
				Dump.loop(rest, Dump.next(e))

def Check.args(args: List<&1, String>) -> IO(Unit):
	match args:
		case Con{program, Con{"--dump", Nil{}}}:
			Dump.loop(128n, 2718281828)
		case Con{program, Nil{}}:
			Check.run()
		case _:
			IO.die(Unit, 1, "usage: benchmark_number_tests [--dump]")

def main() -> IO(Unit):
	do IO<Unit>:
		args : List<&1, String> <- IO.args
		Check.args(args)
