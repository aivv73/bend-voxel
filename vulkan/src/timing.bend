import Base
import ../../deps/bend-vulkan/Vulkan.bend as V
import ../../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W

def unavailable(scope: String) -> V.Action(Unit):
  V.Action.lift(Unit,IO.print("TIMING unavailable=" ++ scope))

def checked(scope: String, result: V.VkResult(Unit)) -> V.Action(Unit):
  match result:
    case Done{unit}: V.Action.pure(Unit,Unit{})
    case Fail{error}: unavailable(scope)

def created(result: V.VkResult(V.QueryPool)) -> V.Action(Maybe<&2,V.QueryPool>):
  match result:
    case Done{pool}: V.Action.pure(Maybe<&2,V.QueryPool>,Some{pool})
    case Fail{error}:
      do V.Action<Maybe<&2,V.QueryPool>>:
        unavailable("gpu_query_pool_creation")
        return None{}

def properties(result: V.VkResult(V.TimestampProperties)) -> V.Action(Unit):
  match result:
    case Done{V.TimestampProperties{+bits,+period}}:
      V.Action.lift(Unit,IO.print("TIMING timestamp_valid_bits=" ++ U32.show(bits) ++ " timestamp_period_ns_f32_bits=" ++ U32.show(F32.bits(period)) ++ " timestamp_scope=top_to_bottom_inclusive timestamp_supported=" ++ U32.show(Bool.to_u32(U32.is_ne(bits,0) && (period > 0.0 : F32)))))
    case Fail{error}: unavailable("timestamp_properties")

def create(+device: V.Device, enabled: Bool) -> V.Action(Maybe<&2,V.QueryPool>):
  match enabled:
    case False{}: V.Action.pure(Maybe<&2,V.QueryPool>,None{})
    case True{}:
      do V.Action<Maybe<&2,V.QueryPool>>:
        info : V.VkResult(V.TimestampProperties) <- V.Action.lift(V.VkResult(V.TimestampProperties),V.Device.timestamp_properties(device))
        properties(info)
        result : V.VkResult(V.QueryPool) <- V.Action.lift(V.VkResult(V.QueryPool),V.Device.create_timestamp_pool(device,6))
        created(result)

def reset_result(+pool: V.QueryPool, result: V.VkResult(Unit)) -> V.Action(Maybe<&2,V.QueryPool>):
  match result:
    case Done{unit}: V.Action.pure(Maybe<&2,V.QueryPool>,Some{pool})
    case Fail{error}:
      do V.Action<Maybe<&2,V.QueryPool>>:
        unavailable("gpu_query_reset")
        return None{}

def reset(command: V.CommandBuffer, pool: Maybe<&2,V.QueryPool>) -> V.Action(Maybe<&2,V.QueryPool>):
  match pool:
    case None{}: V.Action.pure(Maybe<&2,V.QueryPool>,None{})
    case Some{+pool}:
      do V.Action<Maybe<&2,V.QueryPool>>:
        result : V.VkResult(Unit) <- V.Action.lift(V.VkResult(Unit),V.CommandBuffer.reset_timestamp_queries(command,pool,0,6))
        reset_result(pool,result)

def write(command: V.CommandBuffer, pool: Maybe<&2,V.QueryPool>, +index: U32) -> V.Action(Unit):
  match pool:
    case None{}: V.Action.pure(Unit,Unit{})
    case Some{pool}:
      do V.Action<Unit>:
        result : V.VkResult(Unit) <- V.Action.lift(V.VkResult(Unit),V.CommandBuffer.write_timestamp(command,pool,index,Bool.pick(U32,U32.is_zero((index .&. 1 : U32)),1,8192)))
        checked("gpu_timestamp_write",result)

def duration(scope: String, result: V.VkResult(F32)) -> V.Action(Unit):
  match result:
    case Done{value}: V.Action.lift(Unit,IO.print("TIMING gpu_scope=" ++ scope ++ " ns_f32_bits=" ++ U32.show(F32.bits(value))))
    case Fail{error}: unavailable(scope ++ "_wrap_or_properties")

def missing(scopes: List<String>) -> V.Action(Unit):
  match scopes:
    case Nil{}: V.Action.pure(Unit,Unit{})
    case scope <> rest:
      do V.Action<Unit>:
        unavailable(scope ++ "_query_availability")
        missing(rest)

def pair(+device: V.Device, +bound: W.U64, xs: List<V.Timestamp>, scopes: List<String>) -> V.Action(Unit):
  match xs scopes:
    case V.Timestamp{start,True{}} <> V.Timestamp{end,True{}} <> rest scope <> tail:
      do V.Action<Unit>:
        result : V.VkResult(F32) <- V.Action.lift(V.VkResult(F32),V.Device.timestamp_duration(device,start,end,bound))
        duration(scope,result)
        pair(device,bound,rest,tail)
    case Nil{} Nil{}: V.Action.pure(Unit,Unit{})
    case _ remaining: missing(remaining)

def results(device: V.Device, bound: W.U64, result: V.VkResult(List<V.Timestamp>)) -> V.Action(Unit):
  match result:
    case Done{xs}: pair(device,bound,xs,["upload","shadow","main"])
    case Fail{error}: unavailable("gpu_query_results")

def observe(+device: V.Device, pool: Maybe<&2,V.QueryPool>, +started: W.U64, enabled: Bool) -> V.Action(Unit):
  match pool enabled:
    case Some{pool} True{}:
      do V.Action<Unit>:
        now : W.U64 <- V.monotonic_ns()
        result : V.VkResult(List<V.Timestamp>) <- V.Action.lift(V.VkResult(List<V.Timestamp>),V.Device.timestamp_results(device,pool,0,6))
        results(device,W.add(now,W.neg(started)),result)
    case None{} True{}: unavailable("gpu_frame_queries_disabled")
    case _ _: V.Action.pure(Unit,Unit{})

def cpu_value(scope: String, delta: W.U64) -> V.Action(Unit):
  W.U64{lo,hi} = delta
  V.Action.lift(Unit,IO.print("TIMING cpu_scope=" ++ scope ++ " ns_lo=" ++ U32.show(lo) ++ " ns_hi=" ++ U32.show(hi)))

def cpu(enabled: Bool, scope: String, started: W.U64, ended: W.U64) -> V.Action(Unit):
  match enabled:
    case False{}: V.Action.pure(Unit,Unit{})
    case True{}: cpu_value(scope,W.add(ended,W.neg(started)))
