import Base
import ./vendor/bend3d.bend as R

# The original 40 x 24 x 20 lattice holds owner IDs (0 air, 1 anchored,
# 2..65 fragments). Bodies translate vertically, preserving local cell IDs.
type Face is Data:
  Face{index: U32, side: U32, length: U32, rows: U32}
type Body is Data:
  Body{id: U32, offset: F32, speed: F32, bottom: F32, faces: List<&2, Face>}
type World is Type:
  World{cells: Array<U32>, bodies: List<&2, Body>, solids: U32, fragments: U32, removed: U32, status: U32}

def xyz(+i: U32) -> R.Vec:
  R.Vec{(U32.to_f32((i % 40 : U32)) * 0.1 - 1.95 : F32),
    (U32.to_f32((i / 40 % 24 : U32)) * 0.1 + 0.05 : F32),
    (U32.to_f32((i / 960 : U32)) * 0.1 - 0.95 : F32)}
def initial.cell(+i: U32) -> U32:
  +x = (i % 40 : U32)
  +y = (i / 40 % 24 : U32)
  +z = (i / 960 : U32)
  R.word(((y >= 20 : U32) || (((x >= 7) && (x < 13) || (x >= 27) && (x < 33) : U32)
    && ((z >= 7) && (z < 13) : U32))), 1, 0)
def initial.fill(n: Nat, +i: U32, a: Array<U32>) -> Array<U32>:
  match n:
    case 0n:
      a
    case 1n+k:
      initial.fill(k, (i + 1 : U32), Array.set(U32, a, i, initial.cell(i)))

def neighbor(+i: U32, side: U32) -> U32:
  match side:
    case 0:
      R.word((i % 40 > 0 : U32), (i - 1 : U32), 32767)
    case 1:
      R.word((i % 40 < 39 : U32), (i + 1 : U32), 32767)
    case 2:
      R.word((i / 40 % 24 > 0 : U32), (i - 40 : U32), 32767)
    case 3:
      R.word((i / 40 % 24 < 23 : U32), (i + 40 : U32), 32767)
    case 4:
      R.word((i / 960 > 0 : U32), (i - 960 : U32), 32767)
    case _:
      R.word((i / 960 < 19 : U32), (i + 960 : U32), 32767)

def face.add(on: Bool, i: U32, s: U32, fs: List<&2, Face>) -> List<&2, Face>:
  match on:
    case True{}:
      Face{i, s, 1, 1} <> fs
    case False{}:
      fs

def pair(-A: Type, -B: Type, -C: Type, p: A & B, k: A -> B -> C) -> C:
  (a, b) = p
  k(a, b)
# Merge exposed rows along z for x-normal faces, otherwise along x.
# Rows never cross y, so protected anchor material remains distinct.
def face.next(+i: U32, side: U32) -> U32:
  neighbor(i, R.word((side < 2 : U32), 5, 1))
def face.prev(+i: U32, side: U32) -> U32:
  neighbor(i, R.word((side < 2 : U32), 4, 0))
def face.exposed(+i: U32, +side: U32, +owner: U32, a: Array<U32>) -> Array<U32> & Bool:
  pair(Array<U32>, U32, Array<U32> & Bool, Array.get(U32,a,i), a => here =>
    pair(Array<U32>, U32, Array<U32> & Bool, Array.get(U32,a,neighbor((i % 19200 : U32),side)), a => there =>
      (a, ((i < 19200 : U32) && U32.is_eq(here,owner) && U32.is_ne(there,owner)))))
def face.run.cont(ok: Bool, a: Array<U32>, len: U32, k: Array<U32> -> U32 -> Array<U32> & U32) -> Array<U32> & U32:
  match ok:
    case False{}: (a,len)
    case True{}: k(a,(len + 1 : U32))
def face.run(n: Nat, +i: U32, +side: U32, +owner: U32, a: Array<U32>, +len: U32) -> Array<U32> & U32:
  match n:
    case 0n: (a,len)
    case 1n+k:
      pair(Array<U32>, Bool, Array<U32> & U32, face.exposed(i,side,owner,a), a => ok =>
        face.run.cont(ok,a,len,a => len => face.run(k,face.next(i,side),side,owner,a,len)))
def row.equal(+i: U32, +side: U32, +owner: U32, len: U32, a: Array<U32>) -> Array<U32> & Bool:
  pair(Array<U32>,Bool,Array<U32> & Bool,face.exposed(face.prev(i,side),side,owner,a),a => prev =>
    pair(Array<U32>,U32,Array<U32> & Bool,face.run(40n,i,side,owner,a,0),a => actual =>
      (a,((i < 19200 : U32) && Bool.not(prev) && U32.is_eq(len,actual)))))
def row.count(n: Nat, +i: U32, +side: U32, +owner: U32, +len: U32, a: Array<U32>, rows: U32) -> Array<U32> & U32:
  match n:
    case 0n: (a,rows)
    case 1n+k:
      pair(Array<U32>,Bool,Array<U32> & U32,row.equal(i,side,owner,len,a),a => ok =>
        face.run.cont(ok,a,rows,a => rows => row.count(k,neighbor(i,5),side,owner,len,a,rows)))
def row.start(skip: Bool, +i: U32, +side: U32, owner: U32, +len: U32, a: Array<U32>, fs: List<&2,Face>) -> Array<U32> & List<&2,Face>:
  match skip:
    case True{}: (a,fs)
    case False{}:
      pair(Array<U32>,U32,Array<U32> & List<&2,Face>,row.count(20n,i,side,owner,len,a,0),a => rows => (a,Face{i,side,len,rows} <> fs))
def face.rectangle(horizontal: Bool, +i: U32, +side: U32, +owner: U32, +len: U32, a: Array<U32>, fs: List<&2,Face>) -> Array<U32> & List<&2,Face>:
  match horizontal:
    case False{}: (a,Face{i,side,len,1} <> fs)
    case True{}:
      pair(Array<U32>,Bool,Array<U32> & List<&2,Face>,row.equal(neighbor(i,4),side,owner,len,a),a => prev => row.start(prev,i,side,owner,len,a,fs))
def face.start(on: Bool, +i: U32, +side: U32, +owner: U32, a: Array<U32>, fs: List<&2,Face>) -> Array<U32> & List<&2,Face>:
  match on:
    case False{}: (a,fs)
    case True{}:
      pair(Array<U32>, U32, Array<U32> & List<&2,Face>, face.run(40n,i,side,owner,a,0), a => len => face.rectangle((U32.is_eq(side,2) || U32.is_eq(side,3)),i,side,owner,len,a,fs))
def face.visible(here: Bool, +i: U32, +side: U32, +owner: U32, a: Array<U32>, fs: List<&2,Face>) -> Array<U32> & List<&2,Face>:
  match here:
    case False{}: (a,fs)
    case True{}:
      pair(Array<U32>,Bool,Array<U32> & List<&2,Face>,face.exposed(face.prev(i,side),side,owner,a),a => prev =>
        face.start(Bool.not(prev),i,side,owner,a,fs))
def faces.sides(n: Nat, +side: U32, +i: U32, +owner: U32, a: Array<U32>, fs: List<&2, Face>) -> Array<U32> & List<&2, Face>:
  match n:
    case 0n: (a, fs)
    case 1n+k:
      pair(Array<U32>, Bool, Array<U32> & List<&2,Face>, face.exposed(i,side,owner,a), a => here =>
        pair(Array<U32>,List<&2,Face>,Array<U32> & List<&2,Face>,face.visible(here,i,side,owner,a,fs),a => fs =>
          faces.sides(k,(side + 1 : U32),i,owner,a,fs)))

type Flood is Type:
  Flood{source: Array<U32>, seen: Array<U32>, todo: List<U32>, members: List<&2, U32>, anchored: Bool, bottom: F32}
def faces.cells(ids: List<&2, U32>, +owner: U32, a: Array<U32>, fs: List<&2, Face>) -> Array<U32> & List<&2, Face>:
  match ids:
    case Nil{}:
      (a, fs)
    case i <> rest:
      pair(Array<U32>, List<&2, Face>, Array<U32> & List<&2, Face>, faces.sides(6n, 0, i, owner, a, fs), a => fs =>
        faces.cells(rest, owner, a, fs)
      )

# Flood marks cells at enqueue time; at most 19,200 are visited.
def flood.offer.go(ok: Bool, +i: U32, f: Flood) -> Flood:
  match ok:
    case False{}:
      f
    case True{}:
      Flood{a, seen, todo, members, anchor, bottom} = f
      Flood{a, Array.set(U32, seen, i, 1), i <> todo, members, anchor, bottom}
def flood.offer(+i: U32, +owner: U32, f: Flood) -> Flood:
  Flood{a, seen, todo, members, anchor, bottom} = f
  pair(Array<U32>, U32, Flood, Array.get(U32, a, i), a => o =>
    pair(Array<U32>, U32, Flood, Array.get(U32, seen, i), seen => v =>
      flood.offer.go((U32.is_eq(o, owner) && U32.is_eq(v, 0)), i, Flood{a, seen, todo, members, anchor, bottom})
    )
  )
def vec(-C: Type, v: R.Vec, k: F32 -> F32 -> F32 -> C) -> C:
  R.Vec{x, y, z} = v
  k(x, y, z)
@unsafe
def flood.run(f: Flood, +owner: U32) -> Flood:
  match f:
    case Flood{a, seen, Nil{}, members, anchor, bottom}:
      Flood{a, seen, Nil{}, members, anchor, bottom}
    case Flood{a, seen, i <> todo, members, anchor, bottom}:
      +i = i
      vec(Flood, xyz(i), unused0 => y => unused2 =>
        f = {Flood{a, seen, todo, i <> members, (anchor || (U32.is_eq(owner, 1) && U32.is_eq((i / 40 % 24 : U32), 0))), R.min(bottom, (y - 0.05 : F32))} : Flood}
        f = flood.offer(neighbor(i, 0), owner, f)
        f = flood.offer(neighbor(i, 1), owner, f)
        f = flood.offer(neighbor(i, 2), owner, f)
        f = flood.offer(neighbor(i, 3), owner, f)
        f = flood.offer(neighbor(i, 4), owner, f)
        flood.run(flood.offer(neighbor(i, 5), owner, f), owner)
      )

def assign(ids: List<&2, U32>, +owner: U32, a: Array<U32>) -> Array<U32>:
  match ids:
    case Nil{}:
      a
    case i <> rest:
      assign(rest, owner, Array.set(U32, a, i, owner))

def vec.choose(on: Bool, a: R.Vec, b: R.Vec) -> R.Vec:
  match on:
    case True{}:
      a
    case False{}:
      b

def body.find(bs: List<&2, Body>, +id: U32) -> R.Vec:
  match bs:
    case Nil{}:
      R.Vec{0.0, 0.0, 0.0}
    case Body{i, offset, speed, bottom, _} <> rest:
      vec.choose(U32.is_eq(i, id), R.Vec{offset, speed, bottom}, body.find(rest, id))

type Rebuild is Type:
  Rebuild{source: Array<U32>, seen: Array<U32>, output: Array<U32>, bodies: List<&2, Body>, next: U32}
def use.flood(-C: Type, f: Flood, k: Array<U32> -> Array<U32> -> List<U32> -> List<&2, U32> -> Bool -> F32 -> C) -> C:
  Flood{a, b, c, d, e, f} = f
  k(a, b, c, d, e, f)
def rebuild.one(doit: Bool, +i: U32, +owner: U32, +old: List<&2, Body>, r: Rebuild) -> Rebuild:
  match doit:
    case False{}:
      r
    case True{}:
      Rebuild{a, seen, out, bs, next} = r
      +next = next
      use.flood(Rebuild, flood.run(Flood{a, Array.set(U32, seen, i, 1), [i], Nil{}, False{}, 100.0}, owner), a => seen => unused2 => members => +anchored => bottom =>
        +members = members
        +newid = R.word(anchored, 1, next)
        pair(Array<U32>, List<&2, Face>, Rebuild, faces.cells(members, owner, a, Nil{}), a => fs =>
          vec(Rebuild, body.find(old, owner), offset => speed => unused2 =>
            Rebuild{a, seen, assign(members, newid, out), Body{newid, offset, speed, bottom, fs} <> bs, (next + R.word(anchored, 0, 1) : U32)}
          )
        )
      )
def rebuild.scan(n: Nat, +i: U32, +old: List<&2, Body>, r: Rebuild) -> Rebuild:
  match n:
    case 0n:
      r
    case 1n+k:
      Rebuild{a, seen, out, bs, next} = r
      pair(Array<U32>, U32, Rebuild, Array.get(U32, a, i), a => +owner =>
        pair(Array<U32>, U32, Rebuild, Array.get(U32, seen, i), seen => marked =>
          rebuild.scan(k, (i + 1 : U32), old, rebuild.one(((owner > 0 : U32) && U32.is_eq(marked, 0)), i, owner, old, Rebuild{a, seen, out, bs, next}))
        )
      )
def use.rebuild(-C: Type, r: Rebuild, k: Array<U32> -> Array<U32> -> Array<U32> -> List<&2, Body> -> U32 -> C) -> C:
  Rebuild{a, b, c, d, e} = r
  k(a, b, c, d, e)
def rebuild(a: Array<U32>, old: List<&2, Body>, count: U32, removed: U32) -> World:
  use.rebuild(World, rebuild.scan(19200n, 0, old, Rebuild{a, Array.new(U32, 15n, 0), Array.new(U32, 15n, 0), Nil{}, 2}), unused0 => unused1 => out => bs => next =>
    World{out, bs, count, (next - 2 : U32), removed, 1}
  )
def initial() -> World:
  rebuild(initial.fill(19200n, 0, Array.new(U32, 15n, 0)), Nil{}, 4640, 0)

def inside(+index: U32, +offset: F32, +p: R.Vec) -> Bool:
  +v = R.Vec.sub(R.Vec.add(xyz(index), R.Vec{0.0, offset, 0.0}), p)
  (R.Vec.dot(v, v) <= 0.0400001 : F32)
def remove.apply(hit: Bool, a: Array<U32>, i: U32) -> Array<U32>:
  match hit:
    case False{}: a
    case True{}: Array.set(U32,a,i,0)
def remove.scan(n: Nat, +i: U32, a: Array<U32>, +bs: List<&2, Body>, +p: R.Vec, +removed: U32) -> Array<U32> & U32:
  match n:
    case 0n:
      (a, removed)
    case 1n+k:
      pair(Array<U32>, U32, Array<U32> & U32, Array.get(U32, a, i), a => +owner =>
        vec(Array<U32> & U32, body.find(bs, owner), offset => unused1 => unused2 =>
          +hit = ((owner > 0 : U32) && Bool.not((U32.is_eq(owner, 1) && U32.is_eq((i / 40 % 24 : U32), 0))) && inside(i, offset, p))
          remove.scan(k, (i + 1 : U32), remove.apply(hit,a,i), bs, p, (removed + R.word(hit, 1, 0) : U32))
        )
      )
def carve.commit(ok: Bool, old: World, fresh: World) -> World:
  match ok:
    case True{}:
      fresh
    case False{}:
      World{a, bs, n, c, _, _} = old
      World{a, bs, n, c, 0, 3}
def use.world(-C: Type, w: World, k: Array<U32> -> List<&2, Body> -> U32 -> U32 -> U32 -> U32 -> C) -> C:
  World{a, b, c, d, e, f} = w
  k(a, b, c, d, e, f)
def carve.changed(changed: Bool, a: Array<U32>, old: World, +removed: U32) -> World:
  match changed:
    case False{}:
      World{a0, bs, n, c, _, _} = old
      World{a0, bs, n, c, 0, 2}
    case True{}:
      World{a0, +bs, +n, c, r, s} = old
      use.world(World, rebuild(a, bs, (n - removed : U32), removed), a => bs2 => n2 => +c2 => r2 => s2 =>
        carve.commit((c2 <= 64 : U32), World{a0, bs, n, c, r, s}, World{a, bs2, n2, c2, r2, s2})
      )
# The transaction boundary is shared by interactive edits and timed probes.
# prepare owns the candidate; finish either commits it or returns the old world.
type Edit is Type:
  Edit{candidate: Array<U32>, old: World, removed: U32}
def carve.prepare(w: World, p: R.Vec) -> Edit:
  World{a, +bs, n, c, r, s} = w
  pair(Array<U32>, Array<U32>, Edit, Array.clone(U32, a), a0 => a =>
    pair(Array<U32>, U32, Edit, remove.scan(19200n, 0, a, bs, p, 0), a => removed =>
      Edit{a, World{a0, bs, n, c, r, s}, removed}))
def carve.finish(edit: Edit) -> World:
  Edit{a,old,+removed} = edit
  carve.changed((removed > 0 : U32),a,old,removed)
def carve(w: World, p: R.Vec) -> World:
  carve.finish(carve.prepare(w,p))

def body.step(+dt: F32, b: Body) -> Body:
  Body{+id, +offset, +speed, +bottom, fs} = b
  +v = (speed - 9.81 * dt : F32)
  +y = (offset + speed * dt - 4.905 * dt * dt : F32)
  +active = (id > 1 : U32)
  Body{id, R.pick(active, R.max((0.0 - bottom : F32), y), 0.0), R.pick((active && (y > (0.0 - bottom : F32) : F32)), v, 0.0), bottom, fs}
def bodies.step(bs: List<&2, Body>, +dt: F32) -> List<&2, Body>:
  match bs:
    case Nil{}:
      Nil{}
    case b <> rest:
      body.step(dt, b) <> bodies.step(rest, dt)
def step(w: World, dt: F32) -> World:
  World{a, bs, n, c, r, s} = w
  World{a, bodies.step(bs, dt), n, c, r, s}

# Continuations destructure effect-free results at function boundaries, as
# required by Bend 2's pattern checker.
