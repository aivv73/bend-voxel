import Base
import ./baseline-dda.bend as B
import ./candidate-dda.bend as X
import ../../voxel.bend as V
import ../../atelier.bend as A
import ./world-property.bend as W

type Counts is Data:
	Counts{nodes: Nat, links: Nat, mismatches: Nat}

def Counts.join(a: Counts, b: Counts) -> Counts:
	Counts{an,al,am} = a
	Counts{bn,bl,bm} = b
	Counts{Nat.add(1n,Nat.add(an,bn)),Nat.add(al,bl),Nat.add(am,bm)}

def Counts.link(value: Counts) -> Counts:
	Counts{nodes,links,mismatches} = value
	Counts{nodes,1n+links,mismatches}

def Less(+table: X.Table, id: Nat) -> Bool:
	match table:
		case X.Directory{cut,left,right}: Nat.is_lt(id,cut)
		case _: False{}

def Find(+table: X.Table, less: Bool, +id: Nat) -> X.Table:
	match table less:
		case X.Directory{cut,left,right} True{}: Find(left,Less(left,id),id)
		case X.Directory{cut,left,right} False{}:
			+next = Nat.sub(id,cut)
			Find(right,Less(right,next),next)
		case page _: page

def Valid.link(+target: Nat, +count: Nat, +page_id: Nat) -> Bool:
	Nat.is_ne(target,0n) && Nat.is_lt(target,count) && (Nat.is_eq(page_id,0n) || Nat.is_lt(target,page_id))

def Walk(+fuel: Nat, inside: Bool, tree: B.Tree, row: X.Row, +table: X.Table, +page: X.Table, +slot: Nat, +page_id: Nat, +count: Nat) -> Counts:
	match fuel inside tree row:
		case 0n _ _ _: Counts{0n,0n,1n}
		case 1n+rest False{} _ _: Counts{0n,0n,1n}
		case 1n+rest True{} B.Solid{material} X.RowSolid{other}:
			Counts{1n,0n,U32.to_nat(Bool.to_u32(U32.is_ne(material,other)))}
		case 1n+rest True{} B.Branch{left,right} X.RowSplit{}:
			+low = X.Slot.child(slot,True{})
			+high = X.Slot.child(slot,False{})
			Counts.join(Walk(rest,True{},left,X.Page.row(low,page),table,page,low,page_id,count),
				Walk(rest,True{},right,X.Page.row(high,page),table,page,high,page_id,count))
		case 1n+rest True{} B.Branch{left,right} X.RowLink{+target}:
			+next = Find(table,Less(table,target),target)
			Counts.link(Walk(rest,Valid.link(target,count,page_id),B.Branch{left,right},X.Page.row(0n,next),table,next,0n,target,count))
		case _ _ _ _: Counts{0n,0n,1n}

def Reference.count(tree: B.Tree) -> Nat:
	match tree:
		case B.Solid{material}: 1n
		case B.Branch{left,right}: Nat.add(1n,Nat.add(Reference.count(left),Reference.count(right)))

def Require(valid: Bool) -> IO(Unit):
	match valid:
		case True{}: IO.pure(Unit,Unit{})
		case False{}: IO.die(Unit,1,"Indexed topology, materials, links, or coverage differ")

def Report(label: String, expected: Nat, page_count: Nat, counts: Counts) -> IO(Unit):
	Counts{+nodes,+links,+mismatches} = counts
	do IO<Unit>:
		IO.print(label ++ " nodes=" ++ Nat.show(nodes) ++ " links=" ++ Nat.show(links) ++ " mismatches=" ++ Nat.show(mismatches))
		Require(Nat.is_eq(nodes,expected) && Nat.is_eq(1n+links,page_count) && Nat.is_eq(mismatches,0n))

def Grids(label: String, old: B.Grid, new: X.Grid) -> IO(Unit):
	B.Grid{side,+tree} = old
	X.Grid{new_side,X.Index{+height,+count,+table}} = new
	do IO<Unit>:
		Require(U32.is_eq(side,new_side))
		Report(label,Reference.count(tree),count,Walk(1n+Nat.mul(2n,height),True{},tree,X.Page.row(0n,Find(table,Less(table,0n),0n)),
			table,Find(table,Less(table,0n),0n),0n,0n,count))

def Verify(label: String, old: V.Body & B.Grid, new: V.Body & X.Grid) -> IO(Unit):
	(body,grid) = old
	(new_body,new_grid) = new
	Grids(label,grid,new_grid)

def Dyadic(fuel: Nat, +depth: Nat) -> IO(Unit):
	match fuel:
		case 0n: IO.pure(Unit,Unit{})
		case 1n+rest:
			do IO<Unit>:
				Verify("dyadic depth " ++ Nat.show(depth),B.Grid.build(W.Dyadic.body(depth)),X.Grid.build(W.Dyadic.body(depth)))
				Dyadic(rest,1n+depth)

def main() -> IO(Unit):
	do IO<Unit>:
		Verify("empty",B.Grid.build(V.Body.empty(3n)),X.Grid.build(V.Body.empty(3n)))
		Verify("uniform",B.Grid.build(V.Body.filled(3n,4294967295)),X.Grid.build(V.Body.filled(3n,4294967295)))
		Verify("dense",B.Grid.build(W.Dense()),X.Grid.build(W.Dense()))
		Verify("overlapping cuboids",B.Grid.build(W.Boxes()),X.Grid.build(W.Boxes()))
		Dyadic(13n,0n)
		Verify("Atelier",B.Grid.build(A.body()),X.Grid.build(A.body()))
