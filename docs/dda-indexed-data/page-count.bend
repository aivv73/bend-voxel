import Base
import ./baseline-dda.bend as X
import ../../atelier.bend as A
import ../../voxel.bend as V

def Next(width: Nat, rest_depth: Nat) -> Nat:
	match rest_depth:
		case 0n: Nat.sub(width,1n)
		case 1n+rest: rest

def Extra(rest_depth: Nat) -> Nat:
	match rest_depth:
		case 0n: 1n
		case 1n+rest: 0n

def Links(tree: X.Tree, +width: Nat, +rest_depth: Nat) -> Nat:
	match tree:
		case X.Solid{material}: 0n
		case X.Branch{left,right}:
			Nat.add(Extra(rest_depth),Nat.add(Links(left,width,Next(width,rest_depth)),Links(right,width,Next(width,rest_depth))))

def Report(+tree: X.Tree, +width: Nat) -> IO(Unit):
	IO.print("split_levels=" ++ Nat.show(width) ++ " pages=" ++ Nat.show(Nat.add(1n,Links(tree,width,width))))

def Grid.count(result: X.Grid) -> IO(Unit):
	X.Grid{side,+cells} = result
	do IO<Unit>:
		Report(cells,2n)
		Report(cells,3n)
		Report(cells,4n)

def Body.count(result: V.Body & X.Grid) -> IO(Unit):
	(body,grid) = result
	Grid.count(grid)

def main() -> IO(Unit):
	Body.count(X.Grid.build(A.body()))
