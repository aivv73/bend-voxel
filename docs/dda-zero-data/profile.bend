import Base
import ./dda_profile.bend as P
import ./dda_estimate_profile.bend as E
import ../dump.bend as D

def Hook.header() -> String:
	"#define _GNU_SOURCE\n#include <stdint.h>\n#include <stdio.h>\n#include <stdatomic.h>\n" ++
	"static _Atomic uint64_t dda_counts[28];\n" ++
	"#define DDA_COUNT(i,n) atomic_fetch_add_explicit(&dda_counts[i], (uint64_t)(n), memory_order_relaxed)\n" ++
	"static const char *dda_names[] = {\"region_lookups\",\"outside_lookups\",\"tree_lookups\",\"tree_branches\",\"tree_leaves\",\"region_crossings\",\"axis_advance_calls\",\"axis_count_calls\",\"axis_count_iterations\",\"axis_count_collapsed_iterations\",\"trace_region_iterations\",\"rays\",\"final_hits\",\"final_misses\",\"image_pixels\",\"image_quads\",\"frame_roots\",\"axis_count_zero_mid_iterations\",\"plane_predicate_evaluations\",\"zero_event_predicate_evaluations\",\"estimate_up_steps\",\"estimate_down_steps\",\"correction_iterations\",\"correction_fuel_exhaustions\",\"predicate_calls\",\"zero_predicate_calls\",\"advanced_calls\",\"zero_advanced_calls\"};\n" ++
	"static void __attribute__((destructor)) dda_report(void) { for (int i=0;i<28;i++) fprintf(stderr, \"%s\\t%llu\\n\", dda_names[i], (unsigned long long)atomic_load(&dda_counts[i])); }\n"

def Hook.kind(+line: String, current: String) -> String:
	Bool.pick(String,P.Hook.spin(line,"19"),"predicate",
	Bool.pick(String,P.Hook.spin(line,"48"),"advanced",
	Bool.pick(String,P.Hook.spin(line,"47"),"estimate",
	Bool.pick(String,P.Hook.spin(line,"26"),"correct",
	Bool.pick(String,P.Hook.spin(line,"27"),"next",
	P.Hook.kind(line,E.Symbols(),current))))))

def Hook.anchor(+kind: String, +line: String) -> U32:
	match kind:
		case "advance": Bool.pick(U32,String.eq(line,"  u32 _moving_0 = r0;"),2,0)
		case "advanced":
			(Bool.pick(U32,String.eq(line,"  u32 _count_0 = r5;"),8192,0) .|.
			Bool.pick(U32,String.eq(line,"    if (spin_27(e, _o_9, U32_BIN(_count_0, !=, 0ull), _positive_2, _origin_2, _delta_2, _v_22) == 0) {"),16384,0) : U32)
		case "next":
			(Bool.pick(U32,String.eq(line,"  u32 _moving_0 = r0;"),32768,0) .|.
			Bool.pick(U32,String.eq(line,"    if (_moving_0 == 0) {"),65536,0) .|.
			Bool.pick(U32,String.contains(line,"/ f32_unbox(_delta_1)"),131072,0) .|.
			Bool.pick(U32,String.eq(line,"      _v_7 = 1900671690ull;"),262144,0) : U32)
		case _: E.Hook.anchor(kind,line)

def Hook.validate(lines: List<&2,String>, kind: String, found: U32) -> U32:
	match lines:
		case Nil{}: found
		case Con{+line,rest}:
			+next = Hook.kind(line,kind)
			Hook.validate(rest,next,(found .|. Hook.anchor(next,line) : U32))

def Hook.entry(header: Bool, kind: String) -> String:
	match header kind:
		case True{} "predicate": "  DDA_COUNT(24,1);\n  DDA_COUNT(25,r5 == 0);\n"
		case True{} "advanced": "  DDA_COUNT(26,1);\n  DDA_COUNT(27,r5 == 0);\n"
		case _ _: ""

def Hook.line(+line: String, +kind: String) -> String:
	+header = String.starts_with(line,"INLINE Term spin_") || String.starts_with(line,"FAR Term spin_")
	E.Hook.line(String.eq(kind,"predicate") && E.Hook.predicate(line),String.eq(kind,"correct") && E.Hook.up(line),
		String.eq(kind,"correct") && E.Hook.down(line),String.eq(kind,"correct") && String.eq(line,"  WL_SPIN"),
		String.eq(kind,"correct") && String.eq(line,"    if (_fuel_0 == 0) {"),String.eq(kind,"estimate") && P.Hook.spin(line,"47"),line,kind) ++ Hook.entry(header,kind)

def Hook.lines(lines: List<&2,String>, kind: String) -> List<&2,String>:
	match lines:
		case Nil{}: Nil{}
		case Con{+line,rest}:
			+next = Hook.kind(line,kind)
			Hook.line(line,next) <> Hook.lines(rest,next)

def Write(valid: Bool, found: U32, source: String, output: String) -> IO(Unit):
	match valid:
		case False{}: IO.die(Unit,1,"Zero-event function bindings or guarded arithmetic sites differ: mask=" ++ U32.show(found) ++ "; inspect emitted C first")
		case True{}:
			do IO<Unit>:
				file : File <- IO.try(File,File.open(output,"w"))
				written : File & Result<&1,&1,U32 & String,Unit> <- File.write(file,Hook.header() ++ String.join(Hook.lines(String.split(source,'\n'),""),""))
				file : File <- D.Dump.written(written)
				File.close(file)

def Run(input: String, output: String) -> IO(Unit):
	do IO<Unit>:
		file : File <- IO.try(File,File.open(input,"r"))
		read : File & Result<&1,&1,U32 & String,String> <- File.read(file,8388608)
		+source : String <- P.Read.result(read)
		+found : U32 <- IO.pure(U32,Hook.validate(String.split(source,'\n'),"",0))
		Write(U32.is_eq(found,524287),found,source,output)

def Args(args: List<String>) -> IO(Unit):
	match args:
		case Con{program,Con{input,Con{output,Nil{}}}}: Run(input,output)
		case _: IO.die(Unit,1,"Usage: dda-zero-profile input.c output.c")

def main() -> IO(Unit):
	IO.bind(List<String>,Unit,IO.args(),Args)
