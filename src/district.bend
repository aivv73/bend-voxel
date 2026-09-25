import Base
import ./math.bend as R
import ./spatial.bend as S
import ./material.bend as M

# Deterministic 64 x 64 x 32 meter district, with integer cell coordinates.
# Assemblies never overlap. Only explicit green foundations are anchors.
type Assembly is Data:
  Assembly{tree: S.Tree}
def box(+x: F32, +y: F32, +z: F32, dx: F32, dy: F32, dz: F32, m: U32) -> S.Box:
  S.Box{R.Vec{x,y,z},R.Vec{(x + dx : F32),(y + dy : F32),(z + dz : F32)},m}
def tower(n: Nat, +level: U32, +x: F32, bs: List<&2,S.Box>) -> List<&2,S.Box>:
  match n:
    case 0n: bs
    case 1n+k:
      +y = (U32.to_f32(level) * 40.0 : F32)
      tower(k,(level + 1 : U32),x,
        box(x,y,(0.0 - 250.0 : F32),100.0,4.0,100.0,R.word(U32.is_eq(level,0),M.foundation(),M.concrete())) <>
        box(x,(y + 4.0 : F32),(0.0 - 250.0 : F32),6.0,36.0,6.0,M.frame()) <>
        box((x + 94.0 : F32),(y + 4.0 : F32),(0.0 - 250.0 : F32),6.0,36.0,6.0,M.frame()) <>
        box(x,(y + 4.0 : F32),(0.0 - 156.0 : F32),6.0,36.0,6.0,M.frame()) <>
        box((x + 94.0 : F32),(y + 4.0 : F32),(0.0 - 156.0 : F32),6.0,36.0,6.0,M.frame()) <> bs)
def bridge.posts(n: Nat, +i: U32, bs: List<&2,S.Box>) -> List<&2,S.Box>:
  match n:
    case 0n: bs
    case 1n+k:
      +x = (0.0 - 140.0 + U32.to_f32(i) * 20.0 : F32)
      bridge.posts(k,(i + 1 : U32),box(x,164.0,(0.0 - 210.0 : F32),2.0,12.0,2.0,M.frame()) <>
        box(x,164.0,(0.0 - 192.0 : F32),2.0,12.0,2.0,M.frame()) <> bs)
def towers() -> S.Tree:
  S.build(tower(8n,0,(0.0 - 260.0 : F32),tower(8n,0,160.0,bridge.posts(15n,0,[
    box((0.0 - 158.0 : F32),160.0,(0.0 - 210.0 : F32),316.0,4.0,20.0,M.frame()),
    box((0.0 - 140.0 : F32),176.0,(0.0 - 210.0 : F32),282.0,2.0,2.0,M.frame()),
    box((0.0 - 140.0 : F32),176.0,(0.0 - 192.0 : F32),282.0,2.0,2.0,M.frame()),
    # The only connections to the towers: two severable 20 x 30 x 30 cm fuses.
    box((0.0 - 160.0 : F32),161.0,(0.0 - 201.0 : F32),2.0,3.0,3.0,M.machinery()),
    box(158.0,161.0,(0.0 - 201.0 : F32),2.0,3.0,3.0,M.machinery())
  ]))))
def hall.columns(n: Nat, +i: U32, +y: F32, bs: List<&2,S.Box>) -> List<&2,S.Box>:
  match n:
    case 0n: bs
    case 1n+k:
      +x = (0.0 - 280.0 + U32.to_f32((i % 5 : U32)) * 63.0 : F32)
      +z = (20.0 + U32.to_f32((i / 5 : U32)) * 58.0 : F32)
      hall.columns(k,(i + 1 : U32),y,box(x,y,z,8.0,56.0,8.0,M.frame()) <> bs)
# Windowed 20 cm wall panels fit strictly between the perimeter columns.
# Each bay has a 2 m lower panel and 1.6 m upper panel around an open window.
def hall.walls(n: Nat, +i: U32, +y: F32, bs: List<&2,S.Box>) -> List<&2,S.Box>:
  match n:
    case 0n: bs
    case 1n+k:
      +x = (0.0 - 272.0 + U32.to_f32(i) * 63.0 : F32)
      +z = (28.0 + U32.to_f32(i) * 58.0 : F32)
      hall.walls(k,(i + 1 : U32),y,
        box(x,y,20.0,55.0,20.0,2.0,M.concrete()) <> box(x,(y + 40.0 : F32),20.0,55.0,16.0,2.0,M.concrete()) <>
        box(x,y,258.0,55.0,20.0,2.0,M.concrete()) <> box(x,(y + 40.0 : F32),258.0,55.0,16.0,2.0,M.concrete()) <>
        box((0.0 - 280.0 : F32),y,z,2.0,20.0,50.0,M.concrete()) <> box((0.0 - 280.0 : F32),(y + 40.0 : F32),z,2.0,16.0,50.0,M.concrete()) <>
        box((0.0 - 22.0 : F32),y,z,2.0,20.0,50.0,M.concrete()) <> box((0.0 - 22.0 : F32),(y + 40.0 : F32),z,2.0,16.0,50.0,M.concrete()) <> bs)
def hall.floors(n: Nat, +level: U32, bs: List<&2,S.Box>) -> List<&2,S.Box>:
  match n:
    case 0n: bs
    case 1n+k:
      +y = (U32.to_f32(level) * 60.0 : F32)
      hall.floors(k,(level + 1 : U32),hall.columns(25n,0,(y + 4.0 : F32),hall.walls(4n,0,(y + 4.0 : F32),
        box((0.0 - 280.0 : F32),y,20.0,260.0,4.0,240.0,R.word(U32.is_eq(level,0),M.foundation(),M.concrete())) <> bs)))
def hall() -> S.Tree:
  S.build(hall.floors(3n,0,[box((0.0 - 280.0 : F32),180.0,20.0,260.0,4.0,240.0,M.concrete())]))
def rack.bars(n: Nat, +i: U32, +x: F32, +y: F32, +z: F32, bs: List<&2,S.Box>) -> List<&2,S.Box>:
  match n:
    case 0n: bs
    case 1n+k:
      rack.bars(k,(i + 1 : U32),x,y,z,box((x + 2.0 + U32.to_f32(i) * 3.0 : F32),y,(z + 2.0 : F32),1.0,1.0,16.0,M.machinery()) <> bs)
def rack.shelves(n: Nat, +i: U32, +x: F32, +z: F32, bs: List<&2,S.Box>) -> List<&2,S.Box>:
  match n:
    case 0n: bs
    case 1n+k:
      +y = (4.0 + U32.to_f32(i) * 8.0 : F32)
      rack.shelves(k,(i + 1 : U32),x,z,rack.bars(9n,0,x,y,z,
        box((x + 2.0 : F32),y,z,26.0,1.0,2.0,M.frame()) <>
        box((x + 2.0 : F32),y,(z + 18.0 : F32),26.0,1.0,2.0,M.frame()) <> bs))
def rack(+i: U32) -> S.Tree:
  +x = (40.0 + U32.to_f32((i % 6 : U32)) * 40.0 : F32)
  +z = (20.0 + U32.to_f32((i / 6 : U32)) * 30.0 : F32)
  S.build(rack.shelves(10n,0,x,z,[box(x,0.0,z,30.0,2.0,20.0,M.foundation()),
    box(x,2.0,z,2.0,82.0,2.0,M.frame()),box((x + 28.0 : F32),2.0,z,2.0,82.0,2.0,M.frame()),
    box(x,2.0,(z + 18.0 : F32),2.0,82.0,2.0,M.frame()),box((x + 28.0 : F32),2.0,(z + 18.0 : F32),2.0,82.0,2.0,M.frame())]))
def pallet(+i: U32) -> S.Tree:
  +x = (40.0 + U32.to_f32((i % 16 : U32)) * 15.0 : F32)
  +z = (170.0 + U32.to_f32((i / 16 : U32)) * 15.0 : F32)
  S.build([box(x,0.0,z,8.0,2.0,8.0,M.foundation()),box((x + 3.0 : F32),2.0,(z + 3.0 : F32),2.0,16.0,2.0,M.machinery()),
    box(x,18.0,z,8.0,12.0,8.0,M.machinery())])
def racks(n: Nat, +i: U32, bs: List<&2,Assembly>) -> List<&2,Assembly>:
  match n:
    case 0n: bs
    case 1n+k: racks(k,(i + 1 : U32),Assembly{rack(i)} <> bs)
def pallets(n: Nat, +i: U32, bs: List<&2,Assembly>) -> List<&2,Assembly>:
  match n:
    case 0n: bs
    case 1n+k: pallets(k,(i + 1 : U32),Assembly{pallet(i)} <> bs)
def district() -> List<&2,Assembly>:
  Assembly{towers()} <> Assembly{hall()} <> racks(24n,0,pallets(128n,0,Nil{}))
def translate.box(b: S.Box, +delta: R.Vec) -> S.Box:
  S.Box{l,h,m} = b
  S.Box{R.Vec.add(l,delta),R.Vec.add(h,delta),m}
def translate(t: S.Tree, +delta: R.Vec) -> S.Tree:
  match t:
    case S.Empty{}: S.Empty{}
    case S.Leaf{b}: S.Leaf{translate.box(b,delta)}
    case S.Branch{b,a,c}: S.Branch{translate.box(b,delta),translate(a,delta),translate(c,delta)}
def place(bs: List<&2,Assembly>, +delta: R.Vec, tail: List<&2,Assembly>) -> List<&2,Assembly>:
  match bs:
    case Nil{}: tail
    case Assembly{t} <> rest: Assembly{translate(t,delta)} <> place(rest,delta,tail)
def grid(n: Nat, +i: U32, +columns: U32, +template: List<&2,Assembly>) -> List<&2,Assembly>:
  match n:
    case 0n: Nil{}
    case 1n+k:
      place(template,R.Vec{(U32.to_f32((i % columns : U32)) * 640.0 : F32),0.0,
        (U32.to_f32((i / columns : U32)) * 640.0 : F32)},grid(k,(i + 1 : U32),columns,template))
def generate(+n: U32) -> List<&2,Assembly>:
  grid(U32.to_nat(n),0,F32.to_u32(F32.ceil(F32.sqrt(U32.to_f32(n)))),district())
