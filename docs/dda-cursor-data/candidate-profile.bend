import Base
import ./dda_profile.bend as P
import ../dump.bend as D

def Hook.header() -> String:
	"#define _GNU_SOURCE\n#include <stdint.h>\n#include <stdio.h>\n#include <stdatomic.h>\n" ++
	"static _Atomic uint64_t cursor_counts[21];\n" ++
	"#define CURSOR_COUNT(i,n) atomic_fetch_add_explicit(&cursor_counts[i], (uint64_t)(n), memory_order_relaxed)\n" ++
	"static const char *cursor_names[] = {\"suffix_lookups\",\"suffix_branches\",\"suffix_leaves\",\"seed_calls\",\"seed_branches\",\"seed_early_leaves\",\"cache_queries\",\"cache_hits\",\"cache_refreshes\",\"cache_outside\",\"region_crossings\",\"rays\",\"final_hits\",\"final_misses\",\"image_pixels\",\"image_quads\",\"frame_roots\",\"axis_advances\",\"plane_predicates\",\"zero_predicates\",\"trace_iterations\"};\n" ++
	"static void __attribute__((destructor)) cursor_report(void) { for (int i=0;i<21;i++) fprintf(stderr, \"%s\\t%llu\\n\", cursor_names[i], (unsigned long long)atomic_load(&cursor_counts[i])); }\n"

def Hook.kind(+line: String, current: String) -> String:
	Bool.pick(String,P.Hook.spin(line,"47"),"suffix",
	Bool.pick(String,P.Hook.spin(line,"67"),"seed",
	Bool.pick(String,P.Hook.spin(line,"110"),"query",
	Bool.pick(String,P.Hook.spin(line,"107"),"crossing",
	Bool.pick(String,P.Hook.spin(line,"189"),"ray",
	Bool.pick(String,P.Hook.spin(line,"69"),"advance",
	Bool.pick(String,P.Hook.spin(line,"19"),"predicate",
	Bool.pick(String,P.Hook.spin(line,"149"),"trace",
	Bool.pick(String,String.starts_with(line,"  WL_CASE(FID____DDA_FRAME_FORK)"),"frame",
	Bool.pick(String,String.starts_with(line,"INLINE Term spin_") || String.starts_with(line,"FAR Term spin_") || String.starts_with(line,"  WL_CASE("),"",current))))))))))

def Hook.anchor(kind: String, +line: String) -> U32:
	match kind:
		case "suffix": Bool.pick(U32,String.eq(line,"  u32 _low_3 = r9;"),1,0)
		case "seed": Bool.pick(U32,String.eq(line,"  u32 _low_8 = r12;"),2,0)
		case "query": Bool.pick(U32,String.eq(line,"  Term _anchor_0 = r7;"),4,0)
		case "crossing": Bool.pick(U32,String.eq(line,"  u32 _region_6 = r15;"),8,0)
		case "ray": Bool.pick(U32,String.eq(line,"  u32 _near_1 = r9;"),16,0)
		case "advance": Bool.pick(U32,String.eq(line,"  u32 _moving_1 = r0;"),32,0)
		case "predicate": (Bool.pick(U32,String.eq(line,"  u32 _count_1 = r5;"),64,0) .|. Bool.pick(U32,String.starts_with(line,"    _v_2 = ((U32_BIN(_count_1, ==, 0)) |"),128,0) : U32)
		case "trace": Bool.pick(U32,String.eq(line,"  Term _cursor_16 = r33;"),256,0)
		case "frame": Bool.pick(U32,String.eq(line,"    u32 _size_0 = r73;"),512,0)
		case _: 0

def Hook.validate(lines: List<&2,String>, kind: String, found: U32) -> U32:
	match lines:
		case Nil{}: found
		case Con{+line,rest}:
			+next = Hook.kind(line,kind)
			Hook.validate(rest,next,(found .|. Hook.anchor(next,line) : U32))

def Hook.entry(kind: String) -> String:
	match kind:
		case "suffix": "  CURSOR_COUNT(0,1);\n"
		case "seed": "  CURSOR_COUNT(3,1);\n"
		case "query": "  CURSOR_COUNT(6,1);\n  CURSOR_COUNT(7,r0 != 0 && r1 != 0);\n  CURSOR_COUNT(8,r0 != 0 && r1 == 0);\n  CURSOR_COUNT(9,r0 == 0);\n"
		case "crossing": "  CURSOR_COUNT(10,1);\n"
		case "ray": "  CURSOR_COUNT(11,1);\n"
		case "advance": "  CURSOR_COUNT(17,1);\n"
		case _: ""

def Hook.loop(kind: String) -> String:
	match kind:
		case "suffix": "    CURSOR_COUNT(1,term_aux(_tree_1) != CID____DDA_SOLID);\n    CURSOR_COUNT(2,term_aux(_tree_1) == CID____DDA_SOLID);\n"
		case "seed": "    CURSOR_COUNT(4,_fuel_0 != 0 && term_aux(_tree_1) != CID____DDA_SOLID);\n    CURSOR_COUNT(5,_fuel_0 != 0 && term_aux(_tree_1) == CID____DDA_SOLID);\n"
		case "trace": "    CURSOR_COUNT(20,1);\n"
		case "frame": "    CURSOR_COUNT(16,_size_0 == 512);\n"
		case _: ""

def Hook.line(header: Bool, loop: Bool, returns: Bool, predicate: Bool, +line: String, +kind: String) -> String:
	match header loop returns predicate:
		case True{} _ _ _: line ++ "\n" ++ Hook.entry(kind)
		case False{} True{} _ _: line ++ "\n" ++ Hook.loop(kind)
		case False{} False{} True{} _:
			Bool.pick(String,String.eq(kind,"ray"),"  CURSOR_COUNT(12,o[0] != 0);\n  CURSOR_COUNT(13,o[0] == 0);\n","") ++ line ++ "\n"
		case False{} False{} False{} True{}: "    CURSOR_COUNT(18,1);\n    CURSOR_COUNT(19,_count_1 == 0);\n" ++ line ++ "\n"
		case _ _ _ _:
			Bool.pick(String,String.contains(line,"term_pak(CID_PIX,"),"    CURSOR_COUNT(14,1);\n","") ++
			Bool.pick(String,String.contains(line,"term_ctr(CID_QUA,"),"    CURSOR_COUNT(15,1);\n","") ++ line ++ "\n"

def Hook.lines(lines: List<&2,String>, kind: String) -> List<&2,String>:
	match lines:
		case Nil{}: Nil{}
		case Con{+line,rest}:
			+next = Hook.kind(line,kind)
			Hook.line(String.starts_with(line,"INLINE Term spin_") || String.starts_with(line,"FAR Term spin_"),
				String.eq(line,"  WL_SPIN") || String.eq(line,"    WL_SPIN"),String.eq(line,"  return 1;"),
				String.eq(next,"predicate") && String.starts_with(line,"    _v_2 = ((U32_BIN(_count_1, ==, 0)) |"),line,next) <> Hook.lines(rest,next)

def Write(valid: Bool, source: String, output: String) -> IO(Unit):
	match valid:
		case False{}: IO.die(Unit,1,"Cursor function bindings differ; inspect emitted C before instrumenting")
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
		Write(U32.is_eq(Hook.validate(String.split(source,'\n'),"",0),1023),source,output)

def Args(args: List<String>) -> IO(Unit):
	match args:
		case Con{program,Con{input,Con{output,Nil{}}}}: Run(input,output)
		case _: IO.die(Unit,1,"Usage: dda-cursor-profile input.c output.c")

def main() -> IO(Unit):
	IO.bind(List<String>,Unit,IO.args(),Args)
