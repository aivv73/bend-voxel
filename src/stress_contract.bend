import Base

def scheduled.interval(+frame: U32, +warmup: U32, +every: U32) -> U32:
  Bool.to_u32((frame >= warmup : U32) && U32.is_eq(((frame - warmup : U32) % every : U32),0) && (((frame - warmup : U32) / every : U32) < 6 : U32))
def scheduled(frame: U32, warmup: U32, every: U32) -> U32:
  match every:
    case 0: 0
    case _: scheduled.interval(frame,warmup,every)
def expected_edits(measured: U32, every: U32) -> U32:
  match every:
    case 0: 0
    case _: U32.min(6,((measured - 1 : U32) / every + 1 : U32))
def rank(+n: Nat, +percent: Nat) -> Nat:
  Nat.sub(Nat.div(99n+Nat.mul(n,percent),100n),1n)
