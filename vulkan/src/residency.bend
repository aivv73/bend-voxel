import Base
import ./chunks.bend as C

type Version is Data:
  Version{key: C.ChunkKey, number: U32}

def equal(a: Version, b: Version) -> Bool:
  Version{ak,av} = a
  Version{bk,bv} = b
  C.key_equal(ak,bk) && U32.is_eq(av,bv)

def contains(xs: List<&2,Version>, +version: Version) -> Bool:
  match xs:
    case Nil{}: False{}
    case first <> rest: equal(first,version) || contains(rest,version)

def obsolete(~A: Data, ~version: A -> Version, old: List<&2,A>, +keep: List<&2,Version>) -> List<&2,A>:
  match old:
    case Nil{}: Nil{}
    case +first <> rest:
      +tail : List<&2,A> = obsolete(~A,~version,rest,keep)
      Bool.pick(List<&2,A>,contains(keep,version(first)),tail,first <> tail)
