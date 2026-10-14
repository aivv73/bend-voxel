import Base
import ./baseline-dda.bend as X
import ../../atelier.bend as A
import ../../voxel.bend as V

type Counts is Data:
	Counts{nodes: Nat, leaves: Nat, depth: Nat}

def Count.join(a: Counts, b: Counts) -> Counts:
	Counts{an,al,ad} = a
	Counts{bn,bl,bd} = b
	Counts{Nat.add(1n,Nat.add(an,bn)),Nat.add(al,bl),Nat.add(1n,Nat.max(ad,bd))}

def Count(tree: X.Tree) -> Counts:
	match tree:
		case X.Solid{material}: Counts{1n,1n,0n}
		case X.Branch{left,right}: Count.join(Count(left),Count(right))

def Report(side: U32, counts: Counts) -> IO(Unit):
	Counts{nodes,leaves,depth} = counts
	IO.print("side=" ++ U32.show(side) ++ " nodes=" ++ Nat.show(nodes) ++ " leaves=" ++ Nat.show(leaves) ++ " max_depth=" ++ Nat.show(depth))

def Grid.count(result: X.Grid) -> IO(Unit):
	X.Grid{side,cells} = result
	Report(side,Count(cells))

def Body.count(result: V.Body & X.Grid) -> IO(Unit):
	(body,grid) = result
	Grid.count(grid)

def main() -> IO(Unit):
	Body.count(X.Grid.build(A.body()))
