import Base
import ./megascene_scale.bend as S

def within_five_percent(+off: S.Integer, on: S.Integer) -> Bool:
  S.Integer.le(S.Integer.mul(on,S.Integer.from_u32(32n,20)),
    S.Integer.mul(off,S.Integer.from_u32(32n,21)))

def population(count: U32, +duration: S.Integer) -> Bool:
  (count >= 1000 : U32) && S.Integer.le(S.Integer.mul(S.Integer.from_u32(32n,1000000000),S.Integer.ten()),duration)

def edits(count: U32) -> Bool: (count >= 100 : U32)

def bracket(+low: S.Integer, +high: S.Integer) -> Bool:
  S.Integer.le(S.Integer.mul(S.Integer.sub(S.Integer.square(high),S.Integer.square(low)),S.Integer.ten()),S.Integer.square(low))
