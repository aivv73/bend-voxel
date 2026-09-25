import Base
import ./math.bend as R
import ./spatial.bend as S
import ./material.bend as M
import ./district.bend as D
import ./showcase_assets.bend as A

# A 6 x 6 works yard. Coordinates are 10 cm voxel cells; each tile spans
# 64 m and has a different silhouette, with Blender-authored props nearby.
def box(+x: F32, +y: F32, +z: F32, dx: F32, dy: F32, dz: F32, material: U32) -> S.Box:
  S.Box{R.Vec{x,y,z},R.Vec{(x + dx : F32),(y + dy : F32),(z + dz : F32)},material}

def ground() -> S.Tree:
  S.build([
    box((0.0 - 300.0 : F32),0.0,(0.0 - 300.0 : F32),600.0,1.0,600.0,M.foundation()),
    box((0.0 - 300.0 : F32),1.0,(0.0 - 300.0 : F32),600.0,2.0,600.0,M.concrete()),
    box((0.0 - 300.0 : F32),3.0,(0.0 - 300.0 : F32),20.0,1.0,600.0,M.foundation()),
    box(280.0,3.0,(0.0 - 300.0 : F32),20.0,1.0,600.0,M.foundation()),
    box((0.0 - 280.0 : F32),3.0,(0.0 - 300.0 : F32),560.0,1.0,20.0,M.foundation()),
    box((0.0 - 280.0 : F32),3.0,280.0,560.0,1.0,20.0,M.foundation())])

def foundry() -> S.Tree:
  S.build([
    box((0.0 - 120.0 : F32),3.0,(0.0 - 120.0 : F32),240.0,1.0,240.0,M.foundation()),
    box((0.0 - 120.0 : F32),4.0,(0.0 - 120.0 : F32),240.0,12.0,240.0,M.concrete()),
    box((0.0 - 110.0 : F32),16.0,(0.0 - 110.0 : F32),10.0,204.0,10.0,M.frame()),
    box(100.0,16.0,(0.0 - 110.0 : F32),10.0,204.0,10.0,M.frame()),
    box((0.0 - 110.0 : F32),16.0,100.0,10.0,204.0,10.0,M.frame()),
    box(100.0,16.0,100.0,10.0,204.0,10.0,M.frame()),
    box((0.0 - 110.0 : F32),220.0,(0.0 - 110.0 : F32),220.0,8.0,10.0,M.machinery()),
    box((0.0 - 110.0 : F32),220.0,100.0,220.0,8.0,10.0,M.machinery()),
    box((0.0 - 110.0 : F32),220.0,(0.0 - 100.0 : F32),10.0,8.0,200.0,M.machinery()),
    box(100.0,220.0,(0.0 - 100.0 : F32),10.0,8.0,200.0,M.machinery()),
    box((0.0 - 40.0 : F32),16.0,(0.0 - 40.0 : F32),80.0,84.0,80.0,M.machinery()),
    box((0.0 - 50.0 : F32),100.0,(0.0 - 50.0 : F32),100.0,10.0,100.0,M.frame()),
    box((0.0 - 15.0 : F32),110.0,(0.0 - 15.0 : F32),30.0,80.0,30.0,M.machinery()),
    box((0.0 - 20.0 : F32),190.0,(0.0 - 20.0 : F32),40.0,10.0,40.0,M.foundation())])

def observatory() -> S.Tree:
  S.build([
    box((0.0 - 100.0 : F32),3.0,(0.0 - 100.0 : F32),200.0,1.0,200.0,M.foundation()),
    box((0.0 - 100.0 : F32),4.0,(0.0 - 100.0 : F32),200.0,21.0,200.0,M.concrete()),
    box((0.0 - 70.0 : F32),25.0,(0.0 - 70.0 : F32),140.0,20.0,140.0,M.concrete()),
    box((0.0 - 45.0 : F32),45.0,(0.0 - 45.0 : F32),90.0,15.0,90.0,M.concrete()),
    box((0.0 - 85.0 : F32),25.0,(0.0 - 85.0 : F32),7.0,225.0,7.0,M.frame()),
    box(78.0,25.0,(0.0 - 85.0 : F32),7.0,225.0,7.0,M.frame()),
    box((0.0 - 85.0 : F32),25.0,78.0,7.0,225.0,7.0,M.frame()),
    box(78.0,25.0,78.0,7.0,225.0,7.0,M.frame()),
    box((0.0 - 85.0 : F32),250.0,(0.0 - 85.0 : F32),170.0,8.0,7.0,M.machinery()),
    box((0.0 - 85.0 : F32),250.0,78.0,170.0,8.0,7.0,M.machinery()),
    box((0.0 - 12.0 : F32),60.0,(0.0 - 12.0 : F32),24.0,240.0,24.0,M.machinery()),
    box((0.0 - 18.0 : F32),300.0,(0.0 - 18.0 : F32),36.0,10.0,36.0,M.foundation())])

def transit.posts(n: Nat, +i: U32, bs: List<&2,S.Box>) -> List<&2,S.Box>:
  match n:
    case 0n: bs
    case 1n+k:
      +x = (0.0 - 220.0 + U32.to_f32(i) * 145.0 : F32)
      transit.posts(k,(i + 1 : U32),
        box(x,16.0,(0.0 - 65.0 : F32),8.0,134.0,8.0,M.frame()) <>
        box(x,16.0,57.0,8.0,134.0,8.0,M.frame()) <> bs)
def transit() -> S.Tree:
  S.build(transit.posts(4n,0,[
    box((0.0 - 250.0 : F32),3.0,(0.0 - 75.0 : F32),500.0,1.0,150.0,M.foundation()),
    box((0.0 - 250.0 : F32),4.0,(0.0 - 75.0 : F32),500.0,12.0,150.0,M.concrete()),
    box((0.0 - 240.0 : F32),150.0,(0.0 - 65.0 : F32),480.0,6.0,8.0,M.machinery()),
    box((0.0 - 240.0 : F32),150.0,57.0,480.0,6.0,8.0,M.machinery()),
    box((0.0 - 220.0 : F32),16.0,(0.0 - 10.0 : F32),440.0,6.0,20.0,M.machinery()),
    box((0.0 - 220.0 : F32),16.0,(0.0 - 75.0 : F32),440.0,10.0,5.0,M.frame()),
    box((0.0 - 220.0 : F32),16.0,70.0,440.0,10.0,5.0,M.frame())]))

def stackyard() -> S.Tree:
  S.build([
    box((0.0 - 160.0 : F32),3.0,(0.0 - 120.0 : F32),320.0,1.0,240.0,M.foundation()),
    box((0.0 - 160.0 : F32),4.0,(0.0 - 120.0 : F32),320.0,6.0,240.0,M.concrete()),
    box((0.0 - 130.0 : F32),10.0,(0.0 - 90.0 : F32),60.0,60.0,60.0,M.concrete()),
    box((0.0 - 130.0 : F32),70.0,(0.0 - 90.0 : F32),60.0,10.0,60.0,M.frame()),
    box((0.0 - 120.0 : F32),80.0,(0.0 - 80.0 : F32),40.0,60.0,40.0,M.machinery()),
    box((0.0 - 30.0 : F32),10.0,(0.0 - 90.0 : F32),60.0,120.0,60.0,M.machinery()),
    box((0.0 - 35.0 : F32),130.0,(0.0 - 95.0 : F32),70.0,10.0,70.0,M.frame()),
    box(70.0,10.0,(0.0 - 90.0 : F32),60.0,90.0,60.0,M.concrete()),
    box(70.0,100.0,(0.0 - 90.0 : F32),60.0,10.0,60.0,M.frame()),
    box(80.0,110.0,(0.0 - 80.0 : F32),40.0,100.0,40.0,M.machinery())])

def core(+kind: U32) -> S.Tree:
  match kind:
    case 0: foundry()
    case 1: observatory()
    case 2: transit()
    case _: stackyard()

def prop.tree.kind(+kind: U32) -> S.Tree:
  match kind:
    case 0: A.beacon()
    case _: A.cargo_pod()
def prop.tree(+i: U32) -> S.Tree:
  prop.tree.kind((i % 3 : U32))
def props(n: Nat, +i: U32, tail: List<&2,D.Assembly>) -> List<&2,D.Assembly>:
  match n:
    case 0n: tail
    case 1n+k:
      +x = (135.0 + U32.to_f32((i % 5 : U32)) * 26.0 : F32)
      +z = (135.0 + U32.to_f32((i / 5 : U32)) * 26.0 : F32)
      D.Assembly{D.translate(prop.tree(i),R.Vec{x,3.0,z})} <>
        props(k,(i + 1 : U32),tail)
def tile(+i: U32) -> List<&2,D.Assembly>:
  D.Assembly{ground()} <>
    D.Assembly{core(((i + (i / 6 : U32)) % 4 : U32))} <>
    D.Assembly{D.translate(A.gateway(),R.Vec{0.0,3.0,(0.0 - 220.0 : F32)})} <>
    props(25n,0,Nil{})
def landmark() -> S.Tree:
  S.build([
    box((0.0 - 20.0 : F32),0.0,(0.0 - 20.0 : F32),40.0,3.0,40.0,M.foundation()),
    box((0.0 - 15.0 : F32),3.0,(0.0 - 15.0 : F32),30.0,27.0,30.0,M.concrete()),
    box((0.0 - 8.0 : F32),30.0,(0.0 - 8.0 : F32),16.0,370.0,16.0,M.frame()),
    box((0.0 - 18.0 : F32),400.0,(0.0 - 18.0 : F32),36.0,20.0,36.0,M.machinery()),
    box((0.0 - 8.0 : F32),420.0,(0.0 - 8.0 : F32),16.0,40.0,16.0,M.foundation())])
def tiles(n: Nat, +i: U32) -> List<&2,D.Assembly>:
  match n:
    case 0n: Nil{}
    case 1n+k:
      +x = (U32.to_f32((i % 6 : U32)) * 640.0 : F32)
      +z = (U32.to_f32((i / 6 : U32)) * 640.0 : F32)
      D.place(tile(i),R.Vec{x,0.0,z},tiles(k,(i + 1 : U32)))
def generate() -> List<&2,D.Assembly>:
  D.Assembly{D.translate(landmark(),R.Vec{1600.0,0.0,1600.0})} <> tiles(36n,0)
