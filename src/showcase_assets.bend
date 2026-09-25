import Base
import ./math.bend as R
import ./spatial.bend as S
import ./material.bend as M

# Generated from assets/showcase_assets.blend.
# Edit the Blender boxes, then run make export-showcase-assets.
def beacon() -> S.Tree:
  S.build([S.Box{R.Vec{(0.0 - 8.0 : F32),0.0,(0.0 - 8.0 : F32)},R.Vec{8.0,2.0,8.0},M.foundation()},
    S.Box{R.Vec{(0.0 - 8.0 : F32),24.0,(0.0 - 8.0 : F32)},R.Vec{8.0,30.0,8.0},M.machinery()},
    S.Box{R.Vec{(0.0 - 7.0 : F32),2.0,(0.0 - 7.0 : F32)},R.Vec{(0.0 - 5.0 : F32),24.0,(0.0 - 5.0 : F32)},M.frame()},
    S.Box{R.Vec{(0.0 - 7.0 : F32),2.0,5.0},R.Vec{(0.0 - 5.0 : F32),24.0,7.0},M.frame()},
    S.Box{R.Vec{(0.0 - 6.0 : F32),30.0,(0.0 - 6.0 : F32)},R.Vec{6.0,32.0,6.0},M.foundation()},
    S.Box{R.Vec{5.0,2.0,(0.0 - 7.0 : F32)},R.Vec{7.0,24.0,(0.0 - 5.0 : F32)},M.frame()},
    S.Box{R.Vec{5.0,2.0,5.0},R.Vec{7.0,24.0,7.0},M.frame()}])

def cargo_pod() -> S.Tree:
  S.build([S.Box{R.Vec{(0.0 - 12.0 : F32),0.0,(0.0 - 9.0 : F32)},R.Vec{12.0,2.0,9.0},M.foundation()},
    S.Box{R.Vec{(0.0 - 12.0 : F32),2.0,(0.0 - 9.0 : F32)},R.Vec{(0.0 - 10.0 : F32),16.0,(0.0 - 7.0 : F32)},M.frame()},
    S.Box{R.Vec{(0.0 - 12.0 : F32),2.0,7.0},R.Vec{(0.0 - 10.0 : F32),16.0,9.0},M.frame()},
    S.Box{R.Vec{(0.0 - 12.0 : F32),16.0,(0.0 - 9.0 : F32)},R.Vec{12.0,18.0,9.0},M.concrete()},
    S.Box{R.Vec{(0.0 - 10.0 : F32),2.0,(0.0 - 7.0 : F32)},R.Vec{10.0,16.0,7.0},M.machinery()},
    S.Box{R.Vec{10.0,2.0,(0.0 - 9.0 : F32)},R.Vec{12.0,16.0,(0.0 - 7.0 : F32)},M.frame()},
    S.Box{R.Vec{10.0,2.0,7.0},R.Vec{12.0,16.0,9.0},M.frame()}])

def gateway() -> S.Tree:
  S.build([S.Box{R.Vec{(0.0 - 35.0 : F32),0.0,(0.0 - 7.0 : F32)},R.Vec{(0.0 - 25.0 : F32),3.0,7.0},M.foundation()},
    S.Box{R.Vec{(0.0 - 35.0 : F32),52.0,(0.0 - 7.0 : F32)},R.Vec{35.0,58.0,7.0},M.machinery()},
    S.Box{R.Vec{(0.0 - 33.0 : F32),3.0,(0.0 - 5.0 : F32)},R.Vec{(0.0 - 27.0 : F32),20.0,5.0},M.concrete()},
    S.Box{R.Vec{(0.0 - 33.0 : F32),20.0,(0.0 - 5.0 : F32)},R.Vec{(0.0 - 27.0 : F32),52.0,5.0},M.frame()},
    S.Box{R.Vec{(0.0 - 30.0 : F32),58.0,(0.0 - 5.0 : F32)},R.Vec{30.0,60.0,5.0},M.foundation()},
    S.Box{R.Vec{25.0,0.0,(0.0 - 7.0 : F32)},R.Vec{35.0,3.0,7.0},M.foundation()},
    S.Box{R.Vec{27.0,3.0,(0.0 - 5.0 : F32)},R.Vec{33.0,20.0,5.0},M.concrete()},
    S.Box{R.Vec{27.0,20.0,(0.0 - 5.0 : F32)},R.Vec{33.0,52.0,5.0},M.frame()}])
