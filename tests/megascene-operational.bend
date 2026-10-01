import Base
import ../src/megascene_operational.bend as O
import ./schedule-test-io.bend as T

def rejected(value: Result<&2,&2,String,String>, +label: String) -> IO(Unit):
  match value:
    case Fail{message}: T.check(String.eq(message,O.envelope.message(label)),"wrong counter rejection for " ++ label)
    case Done{_}: IO.die(Unit,1,"accepted overflowing " ++ label)

def message(value: Result<&2,&2,String,String>, expected: String) -> IO(Unit):
  match value:
    case Fail{actual}: T.check(String.eq(actual,expected),"wrong admission rejection")
    case Done{_}: IO.die(Unit,1,"accepted unsupported admission")

def accepted(value: Result<&2,&2,String,String>) -> IO(Unit):
  match value:
    case Fail{error}: IO.die(Unit,1,error)
    case Done{_}: IO.pure(Unit,Unit{})

def literal(value: Result<&2,&2,String,String>) -> IO(Unit):
  match value:
    case Fail{error}: IO.die(Unit,1,error)
    case Done{actual}: T.check(String.eq(actual,
      "{\"neighborhoods\":\"25\",\"initial_owners\":\"1\",\"source_cells\":\"1\",\"source_surface_bound\":\"1\",\"source_vertices\":\"1\",\"frames_including_startup\":\"1\",\"fragment_budget\":\"1\",\"initial_next_id\":\"2\",\"live_body_upper_bound\":\"2\",\"initial_native_geometry_bytes_bound\":\"6404736\",\"maximum_edit_vertex_count\":\"36\",\"framebuffer_byte_bound\":\"3686400\",\"shadow_byte_bound\":\"16777216\",\"frame_counter_upper_bound\":\"2\",\"signed_cell_extent\":\"800\",\"maximum_split_sum\":\"1600\",\"monotonic_admission_ns\":\"1000\",\"monotonic_deadline_upper_ns\":\"300000001000\",\"scope\":\"q=2..5 source/frame representation; actual edits and native allocation have evolving guards; not a physical capacity ceiling\"}"),
      "operational admission differs from the literal reference")

def text(value: Result<&2,&2,String,String>, expected: String) -> IO(Unit):
  match value:
    case Fail{error}: IO.die(Unit,1,error)
    case Done{actual}: T.check(String.eq(actual,expected),"derived bounds differ from literal reference")

def main() -> IO(Unit):
  do IO<Unit>:
    literal(O.request("5","1","1","1","1","1","1","640","360","1000"))
    accepted(O.request("2","1","119304647","4294967295","33504395","4294967294","1","1920","1080","1000"))
    rejected(O.request("2","1","119304648","1","1","1","1","640","360","1000"),"maximum_edit_vertex_count")
    rejected(O.request("2","1","1","1","33504396","1","1","640","360","1000"),"initial_native_geometry_bytes_bound")
    rejected(O.request("2","4294967295","1","1","1","1","1","640","360","1000"),"initial_next_id")
    rejected(O.request("2","1","1","1","1","1","4294967295","640","360","1000"),"live_body_upper_bound")
    rejected(O.request("2","1","1","1","1","4294967295","1","640","360","1000"),"frame_counter_upper_bound")
    rejected(O.request("2","1","1","1","1","1","1","4294967295","4294967295","1000"),"framebuffer_byte_bound")
    rejected(O.request("2","1","4294967296","1","1","1","1","640","360","1000"),"source_cells")
    rejected(O.request("2","1","18446744073709551616","1","1","1","1","640","360","1000"),"source_cells")
    rejected(O.request("2","1","-1","1","1","1","1","640","360","1000"),"source_cells")
    accepted(O.request("2","0","0","0","0","1","0","640","360","18446743772709551615"))
    message(O.request("2","0","0","0","0","1","0","640","360","18446743772709551616"),"unsupported monotonic clock arithmetic")
    message(O.request("2","0","0","0","0","1","0","640","360","18446744073709551616"),"unsupported monotonic clock arithmetic")
    message(O.request("2","0","0","0","0","1","0","641","360","1000"),"unsupported native framebuffer resolution")
    message(O.request("6","0","0","0","0","1","0","640","360","1000"),"square neighborhood scale unsupported: supported q=2..5; no physical capacity claim")
    text(O.native("0","0"),"6400768")
    text(O.native("1","33504389"),"4294967168")
    message(O.native("1","33504390"),"static native arena capacity: unsigned integer exceeds supported range")
    message(O.native("1","4294967295"),"static render vertices: unsigned integer exceeds supported range")
    text(O.history("2","100","2",["2","10","2","20"]),
      "{\"accepted_actions\":\"2\",\"planned_removed_cells\":\"30\",\"planned_final_cells\":\"70\",\"planned_lifetime_next_id\":\"7\",\"planned_final_live_bodies\":\"4\",\"scope\":\"independent sparse preflight; each actual edit is re-guarded before unsafe code\"}")
    message(O.history("2","100","1",["2","10","2","20"]),"history fragment budget preflight")
    message(O.history("1","100","1",["4294967295","10"]),"history lifetime next ID: unsigned integer exceeds supported range")
    message(O.history("0","100","1",["0","10"]),"history live bodies: unsigned integer exceeds supported range")
    message(O.history("1","10","1",["1","11"]),"history removed cells exceed source population")
    IO.print("operational admission: literal bounds, U32 overflow, U64 clock endpoints and evolving counters passed")
