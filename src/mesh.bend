import Base
import ./math.bend as R
import ./spatial.bend as S

# Local-space positions are generated once for each body's cached faces.
# The native backend assigns palette colors and uploads these vertices.
type Vertex is Data:
  Vertex{position: R.Vec, side: U32, material: U32}

def vertex(p: R.Vec, side: U32, material: U32) -> Vertex:
  Vertex{p,side,material}

def quad(+a: R.Vec, +b: R.Vec, +c: R.Vec, +d: R.Vec,
         +side: U32, +material: U32, tail: List<&2,Vertex>) -> List<&2,Vertex>:
  vertex(a,side,material) <> vertex(b,side,material) <>
  vertex(c,side,material) <> vertex(a,side,material) <>
  vertex(c,side,material) <> vertex(d,side,material) <> tail

def quad.winding(odd: Bool, +p0: R.Vec, +p1: R.Vec, +p2: R.Vec, +p3: R.Vec,
                 +side: U32, +material: U32, tail: List<&2,Vertex>) -> List<&2,Vertex>:
  match odd:
    case False{}: quad(p3,p2,p1,p0,side,material,tail)
    case True{}: quad(p0,p1,p2,p3,side,material,tail)

def face.vertices(f: S.Face, tail: List<&2,Vertex>) -> List<&2,Vertex>:
  S.Face{+lo,+hi,+side,+material} = f
  +u = ((side / 2 + 1) % 3 : U32)
  +v = ((side / 2 + 2) % 3 : U32)
  +p0 = R.Vec.scale(lo,0.1)
  +p1 = R.Vec.scale(S.put(lo,u,S.axis(hi,u)),0.1)
  +p2 = R.Vec.scale(S.put(S.put(lo,u,S.axis(hi,u)),v,S.axis(hi,v)),0.1)
  +p3 = R.Vec.scale(S.put(lo,v,S.axis(hi,v)),0.1)
  quad.winding(U32.is_eq((side % 2 : U32),1),p0,p1,p2,p3,side,material,tail)

def vertices(fs: List<&2,S.Face>) -> List<&2,Vertex>:
  match fs:
    case Nil{}: Nil{}
    case f <> rest: face.vertices(f,vertices(rest))
