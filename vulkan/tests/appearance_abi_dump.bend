import Base
import ../shaders/appearance_uniforms.bend as U
import ../src/appearance.bend as F
import ../../voxel.bend as X

def range(fuel: Nat, +index: U32) -> List<U32>:
  match fuel:
    case 0n: Nil{}
    case 1n+rest: (1056964608 + index : U32) <> range(rest,(index + 1 : U32))

def values() -> U.FrameWords:
  U.FrameWords{range(16n,0),range(16n,16),range(4n,32),range(4n,36),range(4n,40),range(4n,44),range(4n,48),range(4n,52),range(4n,56),range(20n,60),range(4n,80),range(500n,84)}

def show(fuel: Nat, words: List<U32>, +index: U32) -> IO(Unit):
  match fuel words:
    case 0n _: IO.pure(Unit,Unit{})
    case 1n+rest Nil{}: IO.die(Unit,1,"short sentinel array")
    case 1n+rest Con{word,tail}:
      do IO<Unit>:
        IO.print("abi " ++ U32.show(index) ++ " " ++ U32.show(word))
        show(rest,tail,(index + 1 : U32))

def packed(result: Maybe<Array<U32>>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit,1,"sentinel pack rejected")
    case Some{words}: show(1024n,Array.to_list(~U32,words),0)

def invalid(result: Maybe<Array<U32>>, label: String) -> IO(Unit):
  match result:
    case None{}: IO.print(label ++ " rejected")
    case Some{words}: IO.die(Unit,1,"bad field length accepted")

def cells(fuel: Nat) -> List<&2,X.Cell>:
  match fuel:
    case 0n: Nil{}
    case 1n+rest: X.Cell{0,0,0} <> cells(rest)

def selection_rejected(result: Maybe<List<U32>>) -> IO(Unit):
  match result:
    case None{}: IO.print("overflow_cells rejected")
    case Some{words}: IO.die(Unit,1,"selected cell overflow accepted")

def main() -> IO(Unit):
  do IO<Unit>:
    packed(U.pack(values()))
    selection_rejected(F.cell_words(125n,cells(126n)))
    invalid(U.pack_fields([U.Field{0,2,[1]}],[0 : U32^10n]),"short_field")
    invalid(U.pack_fields([U.Field{0,2,[1,2,3]}],[0 : U32^10n]),"long_field")
