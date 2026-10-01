import Base
import ./benchmark.bend as Bench
import ./benchmark_number.bend as Num
import ./benchmark_host.bend as Host

type CapacityStep is Data:
	CapacityStep{value: Num.Binary64, rest: List<&2, Num.Binary64>}

type CapacityLines is Data:
	CapacityLines{count: U32, ordered: Bool}

def Capacity.value(step: CapacityStep) -> Num.Binary64:
	CapacityStep{value, rest} = step
	value

def Capacity.rest(step: CapacityStep) -> List<&2, Num.Binary64>:
	CapacityStep{value, rest} = step
	rest

def Capacity.count(lines: CapacityLines) -> U32:
	CapacityLines{count, ordered} = lines
	count

def Capacity.ordered(lines: CapacityLines) -> Bool:
	CapacityLines{count, ordered} = lines
	ordered

def Check.require(ok: Bool, message: String) -> IO(Unit):
	match ok:
		case True{}:
			IO.pure(Unit, Unit{})
		case False{}:
			IO.die(Unit, 1, message)

def Check.text(+actual: String, +expected: String, name: String) -> IO(Unit):
	Check.require(String.eq(actual, expected), name ++ " expected " ++ expected ++ ", got " ++ actual)

def Check.strings(actual: List<String>, expected: List<String>) -> Bool:
	match actual expected:
		case Nil{} Nil{}:
			True{}
		case a <> ar b <> br:
			String.eq(a, b) && Check.strings(ar, br)
		case _ _:
			False{}

def Check.threads(actual: List<&2, U32>, expected: List<&2, U32>) -> Bool:
	match actual expected:
		case Nil{} Nil{}:
			True{}
		case a <> ar b <> br:
			U32.is_eq(a, b) && Check.threads(ar, br)
		case _ _:
			False{}

def Check.options_result(result: Result<&2, &2, String, Bench.Options>, expected: Bench.Options, name: String) -> IO(Unit):
	match result:
		case Fail{message}:
			IO.die(Unit, 1, name ++ " failed: " ++ message)
		case Done{Bench.Options{af, an, at, ar, ab, ao, ah}}:
			Bench.Options{ef, en, et, er, eb, eo, eh} = expected
			Check.require(U32.is_eq(af, ef) && U32.is_eq(an, en) && Check.threads(at, et) &&
				String.eq(ar, er) && String.eq(ab, eb) && String.eq(ao, eo) && U32.is_eq(Bool.to_u32(ah), Bool.to_u32(eh)), name ++ " options differ")

def Check.options(args: List<String>, expected: Bench.Options, name: String) -> IO(Unit):
	Check.options_result(Bench.Options.parse(args, Bench.Options.defaults(12)), expected, name)

def Check.bad_options(result: Result<&2, &2, String, Bench.Options>, name: String) -> IO(Unit):
	match result:
		case Fail{message}:
			IO.pure(Unit, Unit{})
		case Done{value}:
			IO.die(Unit, 1, name ++ " unexpectedly accepted")

def Check.bad_args(args: List<String>, name: String) -> IO(Unit):
	Check.bad_options(Bench.Options.parse(args, Bench.Options.defaults(12)), name)

def Check.cli() -> IO(Unit):
	do IO<Unit>:
		Check.options([], Bench.Options{24, 3, [1, 6, 12], "", "build/bend-voxel-rewrite", "", False{}}, "system defaults")
		Check.options(["--frames", "24", "--frames=32", "--repeats=2", "--cpu-threads", "1", "1", "6", "--output", "first", "--output=final", "--root", "a b", "--binary=x"],
			Bench.Options{32, 2, [1, 1, 6], "a b", "x", "final", False{}}, "replacement and duplicate threads")
		Check.options(["--cpu-threads=1", "6", "--cpu-threads", "12", "1", "--output=--literal"],
			Bench.Options{24, 3, [12, 1], "", "build/bend-voxel-rewrite", "--literal", False{}}, "nargs replacement and literal path")
		Check.options(["--frames=4294967295", "--repeats=4294967295", "--cpu-threads=4294967295"],
			Bench.Options{4294967295, 4294967295, [4294967295], "", "build/bend-voxel-rewrite", "", False{}}, "U32 maximum")
		Check.options(["--frames=00024", "--repeats=02", "--cpu-threads=0001"],
			Bench.Options{24, 2, [1], "", "build/bend-voxel-rewrite", "", False{}}, "leading zeros")
		Check.options(["--help"], Bench.Options{24, 3, [1, 6, 12], "", "build/bend-voxel-rewrite", "", True{}}, "help")
		Check.options_result(Bench.Options.parse([], Bench.Options.defaults(1)), Bench.Options{24, 3, [1], "", "build/bend-voxel-rewrite", "", False{}}, "one core")
		Check.options_result(Bench.Options.parse([], Bench.Options.defaults(2)), Bench.Options{24, 3, [1, 2], "", "build/bend-voxel-rewrite", "", False{}}, "two cores")
		Check.bad_args(["--frames=23"], "short workload")
		Check.bad_args(["--repeats=1"], "one repeat")
		Check.bad_args(["--cpu-threads", "1", "0"], "zero threads")
		Check.bad_args(["--frames=4294967296"], "overflow")
		Check.bad_args(["--frames=-24"], "negative")
		Check.bad_args(["--frames=2_4"], "underscore")
		Check.bad_args(["--frames=٢٤"], "Unicode digits")
		Check.bad_args(["--frames="], "empty integer")
		Check.bad_args(["--output="], "empty path")
		Check.bad_args(["--frames"], "missing frame value")
		Check.bad_args(["--cpu-threads"], "missing thread values")
		Check.bad_args(["--cpu-threads", "--output=x"], "empty nargs")
		Check.bad_args(["--unknown=1"], "unknown option")
		IO.print("benchmark CLI checks passed")

def Check.elapsed(result: Result<&2, &2, String, Num.Elapsed>, high: U32, low: U32, name: String) -> IO(Unit):
	match result:
		case Fail{message}:
			IO.die(Unit, 1, name ++ " failed: " ++ message)
		case Done{Num.Elapsed{actual_high, actual_low}}:
			Check.require(U32.is_eq(high, actual_high) && U32.is_eq(low, actual_low), name ++ " elapsed differs")

def Check.bad_metric(result: Result<&2, &2, String, Num.Elapsed>, name: String) -> IO(Unit):
	match result:
		case Fail{message}:
			IO.pure(Unit, Unit{})
		case Done{value}:
			IO.die(Unit, 1, name ++ " unexpectedly accepted")

def Check.scanner() -> IO(Unit):
	do IO<Unit>:
		Check.elapsed(Bench.Scan.measurement("prefixframes=00024 elapsed_ms=00123.9tail", 24), 0, 123, "embedded substring")
		Check.elapsed(Bench.Scan.measurement("frames=24 elapsed_ms=0", 24), 0, 0, "EOF zero")
		Check.elapsed(Bench.Scan.measurement("frames=999999999999999999999999 incomplete frames=24 elapsed_ms=7", 24), 0, 7, "incomplete huge candidate")
		Check.elapsed(Bench.Scan.measurement("frames=24 elapsed_ms= frames=24 elapsed_ms=8", 24), 0, 8, "incomplete elapsed")
		Check.elapsed(Bench.Scan.measurement("fframes=24 elapsed_ms=281474976710655", 24), 65535, 4294967295, "overlapping prefix and elapsed maximum")
		Check.bad_metric(Bench.Scan.measurement("frames=23 elapsed_ms=1 frames=24 elapsed_ms=2", 24), "first complete wrong frame")
		Check.bad_metric(Bench.Scan.measurement("frames=4294967296 elapsed_ms=1 frames=24 elapsed_ms=2", 24), "first complete frame overflow")
		Check.bad_metric(Bench.Scan.measurement("frames=24 elapsed_ms=281474976710656 frames=24 elapsed_ms=2", 24), "first complete elapsed overflow")
		Check.bad_metric(Bench.Scan.measurement("frames=24  elapsed_ms=1", 24), "two spaces")
		Check.bad_metric(Bench.Scan.measurement("frames=24\telapsed_ms=1", 24), "tab separator")
		Check.bad_metric(Bench.Scan.measurement("frames=24 elapsed_ms=-1", 24), "signed elapsed")
		Check.bad_metric(Bench.Scan.measurement("frames=٢٤ elapsed_ms=1", 24), "Unicode frame digits")
		Check.bad_metric(Bench.Scan.measurement("frames=24 elapsed_ms=", 24), "incomplete EOF")
		IO.print("benchmark metric scanner checks passed")

def Check.configs(configs: List<&2, Bench.Config>) -> String:
	match configs:
		case Nil{}:
			""
		case Bench.Config{gpu, threads, tile, fork} <> rest:
			gpu ++ "/" ++ U32.show(threads) ++ "/" ++ U32.show(tile) ++ "/" ++ U32.show(fork) ++ ";" ++ Check.configs(rest)

def Check.samples(values: List<&2, Num.Binary64>) -> String:
	match values:
		case Nil{}:
			""
		case value <> rest:
			Num.Number.json(value) ++ ";" ++ Check.samples(rest)

def Check.rows(rows: List<&2, Bench.Row>) -> String:
	match rows:
		case Nil{}:
			""
		case Bench.Row{config, reversed} <> rest:
			Check.configs([config]) ++ "[" ++ Check.samples(List.reverse(&2, Num.Binary64, reversed)) ++ "]" ++ Check.rows(rest)

def Check.median(result: Result<&2, &2, String, Num.Binary64>, high: U32, low: U32, name: String) -> IO(Unit):
	match result:
		case Fail{message}:
			IO.die(Unit, 1, name ++ " failed: " ++ message)
		case Done{Num.Binary64{ah, al}}:
			Check.require(U32.is_eq(ah, high) && U32.is_eq(al, low), name ++ " median differs")

def Check.bad_median(result: Result<&2, &2, String, Num.Binary64>) -> IO(Unit):
	match result:
		case Fail{message}:
			IO.pure(Unit, Unit{})
		case Done{value}:
			IO.die(Unit, 1, "Empty median unexpectedly accepted")

def Check.history() -> IO(Unit):
	+cpu = {Bench.Config{"off", 1, 6, 6} : Bench.Config}
	+gpu = {Bench.Config{"on", 1, 4, 0} : Bench.Config}
	+initial = Bench.Rows.from_configs([cpu, cpu, gpu], Nil{})
	+rows = Bench.Rows.add(Bench.Rows.add(Bench.Rows.add(initial, cpu, Num.Binary64{1072693248, 0}), gpu, Num.Binary64{1074266112, 0}), cpu, Num.Binary64{1074790400, 0})
	do IO<Unit>:
		Check.text(Check.configs(Bench.Config.list([1, 1, 6])), "off/1/6/0;off/1/6/6;off/1/6/6;off/6/6/6;on/1/4/0;on/1/4/4;on/1/5/5;on/1/6/6;", "duplicate physical launches")
		Check.text(Check.configs(Bench.Config.order(True{}, Bench.Config.list([1, 6]))), "on/1/6/6;on/1/5/5;on/1/4/4;on/1/4/0;off/6/6/6;off/1/6/6;off/1/6/0;", "whole-list reverse")
		Check.require(Check.strings(Bench.Config.args(Bench.Config{"off", 6, 5, 4}, 32), ["--gpu", "off", "--threads", "6", "--tile-depth", "5", "--fork-depth", "4", "--bench", "32"]), "Renderer arguments differ")
		Check.text(Check.rows(rows), "off/1/6/6;[1.0;4.0;]on/1/4/0;[3.0;]", "first-occurrence rows and chronological history")
		Check.median(Bench.Rows.median([Num.Binary64{1075052544, 0}, Num.Binary64{1072693248, 0}, Num.Binary64{1074266112, 0}]), 1074266112, 0, "odd median")
		Check.median(Bench.Rows.median([Num.Binary64{1075052544, 0}, Num.Binary64{1072693248, 0}, Num.Binary64{1074790400, 0}, Num.Binary64{1073741824, 0}]), 1074266112, 0, "even median")
		Check.bad_median(Bench.Rows.median([]))
		Check.text(Bench.Progress.line(2, cpu, Num.Binary64{1072693248, 0}), "repeat=2 gpu=off threads=1 tile=6 fork=6 ms/frame=1.000", "progress precision")
		IO.print("benchmark row history checks passed")

def Check.report_result(result: Result<&2, &2, String, String>, expected: String) -> IO(Unit):
	match result:
		case Fail{message}:
			IO.die(Unit, 1, "Report failed: " ++ message)
		case Done{actual}:
			Check.text(actual, expected, "report schema, indentation, and full sample precision")

def Check.report() -> IO(Unit):
	do IO<Unit>:
		Check.text(Bench.JSON.quote("a\"\\\n\t" ++ SCon{Chr{1}, SNil{}}), "\"a\\\"\\\\\\n\\t\\u0001\"", "JSON escaping")
		Check.report_result(Bench.Report.json(Bench.Options{24, 2, [1], "", "x", "out", False{}}, Bench.Identity{"2026-10-01T12:34:56.123456+00:00", "binary", "main", "voxel", "render", "dump"},
			[Bench.Row{Bench.Config{"off", 1, 6, 0}, [Num.Binary64{1074790400, 0}, Num.Binary64{1073741824, 0}]}]),
			"{\n  \"generated_at\": \"2026-10-01T12:34:56.123456+00:00\",\n  \"binary_sha256\": \"binary\",\n  \"source_sha256\": {\n    \"main.bend\": \"main\",\n    \"voxel.bend\": \"voxel\",\n    \"render.bend\": \"render\",\n    \"dump.bend\": \"dump\"\n  },\n  \"frames\": 24,\n  \"warmup_frames\": 8,\n  \"repeats\": 2,\n  \"workload\": \"native Window.frame with cached scene and scripted destruction/reset\",\n  \"results\": [\n    {\n      \"gpu\": \"off\",\n      \"threads\": 1,\n      \"tile_depth\": 6,\n      \"fork_depth\": 0,\n      \"samples_ms_per_frame\": [\n        2.0,\n        4.0\n      ],\n      \"median_ms_per_frame\": 3.0\n    }\n  ]\n}\n")
		Check.text(Host.Path.parent("relative/sub/report.json"), "relative/sub", "relative parent")
		Check.text(Host.Path.parent("/report.json"), "/", "root parent")
		Check.text(Bench.Run.output("/repo", "caller/report.json"), "caller/report.json", "caller-relative output")
		Check.text(Bench.Run.output("/repo", ""), "/repo/build/benchmark.json", "default output")
		Check.require(Host.Host.date_matches("2026-10-01T12:34:56.123456+00:00", "####-##-##T##:##:##.######+00:00"), "UTC microseconds rejected")
		Check.require(Bool.not(Host.Host.date_matches("2026-10-01T12:34:56.%6N+00:00", "####-##-##T##:##:##.######+00:00")), "Unexpanded date format accepted")
		IO.print("benchmark report and path checks passed")

def Capacity.pattern(fuel: Nat, +index: U32, reversed: List<&2, Num.Binary64>) -> IO(List<&2, Num.Binary64>):
	match fuel:
		case 0n:
			IO.pure(List<&2, Num.Binary64>, List.reverse(&2, Num.Binary64, reversed))
		case 1n+rest:
			do IO<List<&2, Num.Binary64>>:
				value : Num.Binary64 <- Host.Host.result(Num.Binary64, Num.Number.sample(Num.Elapsed{0, (index * 73 % 256 : U32)}, 32), "Capacity fixture sample")
				Capacity.pattern(rest, (index + 1 : U32), value <> reversed)

def Capacity.first(pattern: List<&2, Num.Binary64>) -> CapacityStep:
	match pattern:
		case Nil{}:
			CapacityStep{Num.Binary64{0, 0}, Nil{}}
		case head <> rest:
			CapacityStep{head, rest}

def Capacity.next(cursor: List<&2, Num.Binary64>, pattern: List<&2, Num.Binary64>) -> CapacityStep:
	match cursor:
		case Nil{}:
			Capacity.first(pattern)
		case head <> rest:
			CapacityStep{head, rest}

def Capacity.values(fuel: Nat, +pattern: List<&2, Num.Binary64>, cursor: List<&2, Num.Binary64>, reversed: List<&2, Num.Binary64>) -> List<&2, Num.Binary64>:
	match fuel:
		case 0n:
			reversed
		case 1n+rest:
			+step = Capacity.next(cursor, pattern)
			Capacity.values(rest, pattern, Capacity.rest(step), Capacity.value(step) <> reversed)

def Capacity.fill(fuel: Nat, +value: Num.Binary64, values: List<&2, Num.Binary64>) -> List<&2, Num.Binary64>:
	match fuel:
		case 0n:
			values
		case 1n+rest:
			Capacity.fill(rest, value, value <> values)

def Capacity.sample_order(index: U32, line: String) -> Bool:
	match index:
		case 0:
			String.eq(line, "        0.0,")
		case 1:
			String.eq(line, "        2.28125,")
		case 2:
			String.eq(line, "        4.5625,")
		case 3:
			String.eq(line, "        6.84375,")
		case 254:
			String.eq(line, "        3.4375,")
		case 255:
			String.eq(line, "        5.71875,")
		case 256:
			String.eq(line, "        0.0,")
		case 32768:
			String.eq(line, "        0.0,")
		case 65535:
			String.eq(line, "        5.71875")
		case _:
			True{}

def Capacity.line(sample: Bool, line: String, +count: U32, ordered: Bool) -> CapacityLines:
	match sample:
		case False{}:
			CapacityLines{count, ordered}
		case True{}:
			CapacityLines{(count + 1 : U32), ordered && Capacity.sample_order(count, line)}

def Capacity.lines(text: String, reversed: String, +count: U32, ordered: Bool) -> CapacityLines:
	match text:
		case SNil{}:
			CapacityLines{count, ordered && String.is_empty(reversed)}
		case SCon{'\n', rest}:
			+line = String.reverse(reversed)
			+lines = Capacity.line(String.starts_with(line, "        "), line, count, ordered)
			Capacity.lines(rest, "", Capacity.count(lines), Capacity.ordered(lines))
		case SCon{char, rest}:
			Capacity.lines(rest, SCon{char, reversed}, count, ordered)

def Capacity.report(result: Result<&2, &2, String, String>) -> IO(Unit):
	match result:
		case Fail{message}:
			IO.die(Unit, 1, "Large report failed: " ++ message)
		case Done{+json}:
			+lines = Capacity.lines(json, "", 0, True{})
			Check.require(U32.is_eq(Capacity.count(lines), 65536) && Capacity.ordered(lines) &&
				String.starts_with(json, "{\n  \"generated_at\": \"2026-10-01T12:34:56.123456+00:00\",\n") &&
				String.ends_with(json, "        5.71875\n      ],\n      \"median_ms_per_frame\": 3.984375\n    }\n  ]\n}\n"),
				"65536-sample report count, acquisition order, precision, or final newline differs")

def Capacity.threads(fuel: Nat, +thread: U32, reversed: List<&2, U32>) -> List<&2, U32>:
	match fuel:
		case 0n:
			reversed
		case 1n+rest:
			Capacity.threads(rest, thread, thread <> reversed)

def Capacity.configs(configs: List<&2, Bench.Config>, +index: U32, count: U32, valid: Bool) -> Bool:
	match configs:
		case Nil{}:
			valid && U32.is_eq(count, 65541)
		case config <> rest:
			Capacity.configs(rest, (index + 1 : U32), (count + 1 : U32), valid &&
				Bench.Config.equal(config, Bool.pick(Bench.Config, U32.is_eq(index, 0), Bench.Config{"off", 1, 6, 0},
					Bool.pick(Bench.Config, (index <= 65536 : U32), Bench.Config{"off", 6, 6, 6},
						Bool.pick(Bench.Config, U32.is_eq(index, 65537), Bench.Config{"on", 1, 4, 0},
							Bool.pick(Bench.Config, U32.is_eq(index, 65538), Bench.Config{"on", 1, 4, 4},
								Bool.pick(Bench.Config, U32.is_eq(index, 65539), Bench.Config{"on", 1, 5, 5}, Bench.Config{"on", 1, 6, 6})))))))

def Capacity.rows(fuel: Nat, +index: U32, rows: List<&2, Bench.Row>) -> List<&2, Bench.Row>:
	match fuel:
		case 0n:
			rows
		case 1n+rest:
			Capacity.rows(rest, (index + 1 : U32), Bench.Row{Bench.Config{"off", index, 6, 6}, [Num.Binary64{1072693248, 0}]} <> rows)

def Capacity.row_count(rows: List<&2, Bench.Row>, count: U32) -> U32:
	match rows:
		case Nil{}:
			count
		case row <> rest:
			Capacity.row_count(rest, (count + 1 : U32))

def Capacity.last_row(last: Maybe<&2, Bench.Row>, config: Bench.Config, samples: String, +name: String) -> IO(Unit):
	match last:
		case None{}:
			IO.die(Unit, 1, name ++ " missing final row")
		case Some{Bench.Row{actual, reversed}}:
			do IO<Unit>:
				Check.require(Bench.Config.equal(actual, config), name ++ " final configuration differs")
				Check.text(Check.samples(List.reverse(&2, Num.Binary64, reversed)), samples, name ++ " final samples")

def Check.capacity() -> IO(Unit):
	+threads = Capacity.threads(65536n, 6, Nil{})
	+rows = Capacity.rows(65536n, 1, Nil{})
	do IO<Unit>:
		+pattern : List<&2, Num.Binary64> <- Capacity.pattern(256n, 0, Nil{})
		+even : List<&2, Num.Binary64> = Capacity.values(65536n, pattern, pattern, Nil{})
		odd : List<&2, Num.Binary64> = Capacity.values(65535n, pattern, pattern, Nil{})
		Check.median(Bench.Rows.median(even), 1074782208, 0, "65536 varied samples even median")
		Check.median(Bench.Rows.median(odd), 1074774016, 0, "65535 varied samples odd median")
		Check.median(Bench.Rows.sorted_median(Capacity.fill(32768n, Num.Binary64{1072693248, 0}, Capacity.fill(32768n, Num.Binary64{1073741824, 0}, Nil{}))), 1073217536, 0, "65536 pre-sorted samples")
		Capacity.report(Bench.Report.json(Bench.Options{32, 65536, [1], "", "x", "out", False{}}, Bench.Identity{"2026-10-01T12:34:56.123456+00:00", "binary", "main", "voxel", "render", "dump"}, [Bench.Row{Bench.Config{"off", 1, 6, 0}, even}]))
		Check.require(Bench.Options.valid(threads) && Capacity.configs(Bench.Config.list(threads), 0, 0, True{}), "65536 duplicate CPU entries failed validation, count, or order")
		Check.require(Bool.not(Bench.Options.valid(Capacity.threads(65536n, 6, [0]))), "Invalid trailing CPU thread accepted")
		Check.require(U32.is_eq(Capacity.row_count(Bench.Rows.from_configs(Bench.Config.list(threads), Nil{}), 0), 6), "65536 duplicate CPU entries did not aggregate into six unique rows")
		Check.require(Bench.Rows.contains(rows, Bench.Config{"off", 1, 6, 6}) && Bool.not(Bench.Rows.contains(rows, Bench.Config{"off", 65537, 6, 6})), "65536-row lookup differs")
		+ensured : List<&2, Bench.Row> = Bench.Rows.ensure(rows, Bench.Config{"off", 65537, 6, 6})
		Check.require(U32.is_eq(Capacity.row_count(ensured, 0), 65537), "65536-row append count differs")
		Capacity.last_row(List.last(&2, Bench.Row, ensured), Bench.Config{"off", 65537, 6, 6}, "", "65536-row append")
		Capacity.last_row(List.last(&2, Bench.Row, Bench.Rows.add(rows, Bench.Config{"off", 1, 6, 6}, Num.Binary64{1073741824, 0})), Bench.Config{"off", 1, 6, 6}, "1.0;2.0;", "65536-row update")
		IO.print("benchmark 65536-sample, CPU-entry, and row capacity checks passed")

def main() -> IO(Unit):
	do IO<Unit>:
		Check.cli()
		Check.scanner()
		Check.history()
		Check.report()
		Check.capacity()
		IO.print("Benchmark unit checks passed")
