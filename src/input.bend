import Base
import ./math.bend as R
import ./render.bend as V
import ./world.bend as W

type Control is Data:
  Control{camera: V.Camera, keys: U32, mx: U32, my: U32, looking: Bool, left: Bool, focused: Bool, cut: Bool, reset: Bool, quit: Bool}
def initial() -> Control:
  Control{V.camera(), 0, 320, 180, False{}, False{}, True{}, False{}, False{}, False{}}
def key.bit(+key: U32, code: U32, bit: U32) -> U32:
  R.word(U32.is_eq(key, code), bit, 0)
def key.mask(+key: U32) -> U32:
  (key.bit(key, 119, 1) .|. key.bit(key, 115, 2) .|. key.bit(key, 97, 4) .|. key.bit(key, 100, 8) .|. key.bit(key, 113, 16) .|. key.bit(key, 101, 32) .|. key.bit(key, 114, 64) : U32)
def key(+code: U32, +down: Bool, c: Control) -> Control:
  Control{cam, +keys, mx, my, look, left, +focus, _, _, quit} = c
  +mask = key.mask(code)
  +release = (U32.is_eq(code, 0) || U32.is_eq(code, 27))
  Control{cam, R.word((release || Bool.not(focus)), 0, R.word(down, (keys .|. mask : U32), (keys .&. (4294967295 .^. mask) : U32))), mx, my,
    (look && Bool.not(release)), (left && Bool.not(release)), (focus && Bool.not(release)), False{},
    (focus && down && U32.is_eq(code, 114) && U32.is_eq((keys .&. 64 : U32), 0)), quit}
def motion(+x: U32, +y: U32, c: Control) -> Control:
  Control{cam, keys, mx, my, +look, left, focus, _, _, quit} = c
  V.Camera{eye, yaw, pitch} = cam
  +dx = (U32.to_f32(x) - U32.to_f32(mx) : F32)
  +dy = (U32.to_f32(y) - U32.to_f32(my) : F32)
  Control{V.Camera{eye, (yaw - R.pick(look, (dx * 0.005 : F32), 0.0) : F32), R.clamp((pitch - R.pick(look, (dy * 0.005 : F32), 0.0) : F32), (0.0 - 1.35 : F32), 1.35)}, keys, x, y, look, left, focus, False{}, False{}, quit}
def mouse(+x: U32, +y: U32, +button: U32, +down: Bool, c: Control) -> Control:
  Control{cam, keys, _, _, +look, +left, focus, _, _, quit} = c
  +l = U32.is_eq(button, 0)
  +r = U32.is_eq(button, 1)
  +click = (l && down && Bool.not(left) && Bool.not(look))
  +reset = (click && ((x >= 570) && (y < 25) : U32))
  Control{cam, keys, x, y, ((r && down) || (Bool.not(r) && look)), ((l && down) || (Bool.not(l) && left)), (focus || down), (click && Bool.not(reset)), reset, quit}
def event(e: Event, c: Control) -> Control:
  match e:
    case Key{code, down}:
      key(code, down, c)
    case Move{x, y}:
      motion(x, y, c)
    case Mouse{x, y, button, down}:
      mouse(x, y, button, down, c)
    case Close{}:
      Control{cam, keys, mx, my, look, left, focus, _, _, _} = c
      Control{cam, keys, mx, my, look, left, focus, False{}, False{}, True{}}
def held(+keys: U32, bit: U32) -> F32:
  R.pick(((keys .&. bit) > 0 : U32), 1.0, 0.0)
def step(c: Control, +dt: F32) -> Control:
  Control{cam, +keys, mx, my, look, left, +focus, _, _, quit} = c
  V.Camera{eye, +yaw, pitch} = cam
  R.Vec{x, y, z} = eye
  +dx = (held(keys, 8) - held(keys, 4) : F32)
  +dz = (held(keys, 1) - held(keys, 2) : F32)
  +dy = (held(keys, 32) - held(keys, 16) : F32)
  +speed = (2.0 * dt / R.max(1.0, F32.sqrt((dx * dx + dy * dy + dz * dz : F32))) : F32)
  Control{V.Camera{R.Vec{R.clamp((x + (0.0 - F32.cos(yaw) * dx + F32.sin(yaw) * dz) * speed : F32), (0.0 - 6.0 : F32), 6.0), R.clamp((y + dy * speed : F32), 0.15, 6.0), R.clamp((z + (F32.sin(yaw) * dx + F32.cos(yaw) * dz) * speed : F32), (0.0 - 6.0 : F32), 6.0)}, yaw, pitch}, keys, mx, my, look, left, focus, False{}, False{}, quit}
def aim(+c: Control, bs: List<&2, W.Body>) -> V.Aim:
  Control{cam, _, mx, my, look, _, focus, _, _, _} = c
  V.aim((focus && Bool.not(look)), bs, cam, mx, my)

# Keep held-button latches when resetting so one press remains one action.
def reset.state(c: Control) -> Control:
  Control{_,keys,_,_,_,left,focus,_,_,quit} = c
  Control{V.camera(),keys,320,180,False{},left,focus,False{},False{},quit}
