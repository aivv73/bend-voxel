import Base
import ./baseline-dda.bend as B
import ./candidate-dda.bend as X
import ../../voxel.bend as V
import ../../atelier.bend as A

type Counts is Data:
	Counts{queries: U32, mismatches: U32}

def Cell.equal(a: V.Cell, b: V.Cell) -> Bool:
	V.Cell{x,y,z} = a
	V.Cell{rx,ry,rz} = b
	U32.is_eq(x,rx) && U32.is_eq(y,ry) && U32.is_eq(z,rz)

def Region.equal(a: B.Region, b: X.Region) -> Bool:
	B.Region{m,low,high} = a
	X.Region{rm,rl,rh} = b
	U32.is_eq(m,rm) && Cell.equal(low,rl) && Cell.equal(high,rh)

def Point(+reference: B.Grid, +candidate: X.Grid, +cell: V.Cell) -> U32:
	Bool.to_u32(Bool.not(U32.is_eq(B.Grid.read(reference,cell),X.Grid.read(candidate,cell)) &&
		Region.equal(B.Grid.region(reference,cell),X.Grid.region(candidate,cell))))

def Corner(+index: U32, box: V.Cuboid) -> V.Cell:
	V.Cuboid{V.Cell{+x,+y,+z},V.Cell{hx,hy,hz},material} = box
	V.Cell{Bool.pick(U32,U32.is_zero(U32.and(index,1)),x,(hx - 1 : U32)),
		Bool.pick(U32,U32.is_zero(U32.and(index,2)),y,(hy - 1 : U32)),
		Bool.pick(U32,U32.is_zero(U32.and(index,4)),z,(hz - 1 : U32))}

def Probe(index: U32, +box: V.Cuboid) -> V.Cell:
	match index:
		case 8:
			V.Cuboid{V.Cell{+x,+y,+z},V.Cell{hx,hy,hz},material} = box
			V.Cell{(x + (hx - x) / 2 : U32),(y + (hy - y) / 2 : U32),(z + (hz - z) / 2 : U32)}
		case 9:
			V.Cuboid{V.Cell{+x,+y,+z},V.Cell{hx,hy,hz},material} = box
			V.Cell{x,(y + (hy - y) / 2 : U32),(z + (hz - z) / 2 : U32)}
		case 10:
			V.Cuboid{V.Cell{+x,+y,+z},V.Cell{hx,hy,hz},material} = box
			V.Cell{(hx - 1 : U32),(y + (hy - y) / 2 : U32),(z + (hz - z) / 2 : U32)}
		case 11:
			V.Cuboid{V.Cell{+x,+y,+z},V.Cell{hx,hy,hz},material} = box
			V.Cell{(x + (hx - x) / 2 : U32),y,(z + (hz - z) / 2 : U32)}
		case 12:
			V.Cuboid{V.Cell{+x,+y,+z},V.Cell{hx,hy,hz},material} = box
			V.Cell{(x + (hx - x) / 2 : U32),(hy - 1 : U32),(z + (hz - z) / 2 : U32)}
		case 13:
			V.Cuboid{V.Cell{+x,+y,+z},V.Cell{hx,hy,hz},material} = box
			V.Cell{(x + (hx - x) / 2 : U32),(y + (hy - y) / 2 : U32),z}
		case 14:
			V.Cuboid{V.Cell{+x,+y,+z},V.Cell{hx,hy,hz},material} = box
			V.Cell{(x + (hx - x) / 2 : U32),(y + (hy - y) / 2 : U32),(hz - 1 : U32)}
		case other: Corner(other,box)

def Corners(fuel: Nat, +reference: B.Grid, +candidate: X.Grid, +box: V.Cuboid, +index: U32, mismatches: U32) -> U32:
	match fuel:
		case 0n: mismatches
		case 1n+rest: Corners(rest,reference,candidate,box,(index + 1 : U32),(mismatches + Point(reference,candidate,Probe(index,box)) : U32))

def Join(a: Counts, b: Counts) -> Counts:
	Counts{aq,am} = a
	Counts{bq,bm} = b
	Counts{(aq + bq : U32),(am + bm : U32)}

def Leaves(tree: B.Tree, +reference: B.Grid, +candidate: X.Grid, +box: V.Cuboid, +axis: U32) -> Counts:
	match tree:
		case B.Solid{material}: Counts{15,Corners(15n,reference,candidate,box,0,0)}
		case B.Branch{left,right}:
			Join(Leaves(left,reference,candidate,V.Cuboid.half(box,axis,True{}),((axis + 1) % 3 : U32)),
				Leaves(right,reference,candidate,V.Cuboid.half(box,axis,False{}),((axis + 1) % 3 : U32)))

def Scan(fuel: Nat, +reference: B.Grid, +candidate: X.Grid, +side: U32, +index: U32, mismatches: U32) -> Counts:
	match fuel:
		case 0n: Counts{index,mismatches}
		case 1n+rest: Scan(rest,reference,candidate,side,(index + 1 : U32),(mismatches + Point(reference,candidate,V.Cell.at(side,index)) : U32))

def Require(valid: Bool) -> IO(Unit):
	match valid:
		case True{}: IO.pure(Unit,Unit{})
		case False{}: IO.die(Unit,1,"Indexed storage differs from the frozen tree")

def Report(label: String, counts: Counts) -> IO(Unit):
	Counts{queries,+mismatches} = counts
	do IO<Unit>:
		IO.print(label ++ " queries=" ++ U32.show(queries) ++ " material_or_bounds_mismatches=" ++ U32.show(mismatches))
		Require(U32.is_zero(mismatches))

def All(all: Bool, label: String, old: B.Grid, new: X.Grid, +side: U32) -> IO(Unit):
	match all:
		case False{}: IO.pure(Unit,Unit{})
		case True{}: Report(label ++ " all cells",Scan(U32.to_nat((side * side * side : U32)),old,new,side,0,0))

def Leaf.count(tree: B.Tree) -> U32:
	match tree:
		case B.Solid{material}: 1
		case B.Branch{left,right}: (Leaf.count(left) + Leaf.count(right) : U32)

def Verify.count(+label: String, expected: U32, counts: Counts) -> IO(Unit):
	Counts{+queries,mismatches} = counts
	do IO<Unit>:
		Require(U32.is_eq(queries,expected))
		Report(label,Counts{queries,mismatches})

def Verify.grids(+label: String, all: Bool, +old: B.Grid, +new: X.Grid) -> IO(Unit):
	B.Grid{+side,+tree} = old
	X.Grid{new_side,cells} = new
	do IO<Unit>:
		Require(U32.is_eq(side,new_side))
		Verify.count(label,(15 * Leaf.count(tree) : U32),Leaves(tree,old,new,V.Cuboid{V.Cell{0,0,0},V.Cell{side,side,side},0},0))
		Report(label ++ " outside",Counts{7,(Point(old,new,V.Cell{side,0,0}) + Point(old,new,V.Cell{0,side,0}) +
			Point(old,new,V.Cell{0,0,side}) + Point(old,new,V.Cell{4294967295,0,0}) + Point(old,new,V.Cell{0,4294967295,0}) +
			Point(old,new,V.Cell{0,0,4294967295}) + Point(old,new,V.Cell{4294967295,4294967295,4294967295}) : U32)})
		All(all,label,old,new,side)

def Verify(label: String, all: Bool, reference: V.Body & B.Grid, candidate: V.Body & X.Grid) -> IO(Unit):
	(body,old) = reference
	(new_body,new) = candidate
	Verify.grids(label,all,old,new)

def Pattern(fuel: Nat, +side: U32, cells: Array<U32>, +index: U32) -> V.Body:
	match fuel:
		case 0n: V.Body{side,cells}
		case 1n+rest: Pattern(rest,side,Array.set(U32,cells,index,Bool.pick(U32,U32.is_zero(index),0,U32.xor((index * 2654435761 : U32),2147483648))),(index + 1 : U32))

def Dense() -> V.Body:
	Pattern(512n,8,Array.new(U32,9n,0),0)

def Boxes() -> V.Body:
	V.Cuboids{[V.Cuboid{V.Cell{1,2,0},V.Cell{4,5,7},0},V.Cuboid{V.Cell{2,1,3},V.Cell{7,6,8},4294967295},
		V.Cuboid{V.Cell{0,0,0},V.Cell{8,8,8},2147483648}]}

def Dyadic.box(fuel: Nat, box: V.Cuboid, +axis: U32) -> V.Cuboid:
	match fuel:
		case 0n: box
		case 1n+rest: Dyadic.box(rest,V.Cuboid.half(box,axis,True{}),((axis + 1) % 3 : U32))

def Dyadic.body(depth: Nat) -> V.Body:
	V.Cuboids{[Dyadic.box(depth,V.Cuboid{V.Cell{0,0,0},V.Cell{16,16,16},4294967295},0),
		V.Cuboid{V.Cell{0,0,0},V.Cell{16,16,16},2147483648}]}

def Dyadic.verify(fuel: Nat, +depth: Nat) -> IO(Unit):
	match fuel:
		case 0n: IO.pure(Unit,Unit{})
		case 1n+rest:
			do IO<Unit>:
				Verify("dyadic terminal depth " ++ Nat.show(depth),True{},B.Grid.build(Dyadic.body(depth)),X.Grid.build(Dyadic.body(depth)))
				Dyadic.verify(rest,Nat.add(1n,depth))

def main() -> IO(Unit):
	do IO<Unit>:
		Verify("empty",True{},B.Grid.build(V.Body.empty(3n)),X.Grid.build(V.Body.empty(3n)))
		Verify("uniform full-width material",True{},B.Grid.build(V.Body.filled(3n,4294967295)),X.Grid.build(V.Body.filled(3n,4294967295)))
		Verify("dense arbitrary U32 materials",True{},B.Grid.build(Dense()),X.Grid.build(Dense()))
		Verify("overlapping cuboids",True{},B.Grid.build(Boxes()),X.Grid.build(Boxes()))
		Dyadic.verify(13n,0n)
		Verify("Atelier",False{},B.Grid.build(A.body()),X.Grid.build(A.body()))
