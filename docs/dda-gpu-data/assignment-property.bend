import Base
import ./candidate-dda.bend as X

type Counts is Data:
	Counts{addresses: U32, out_of_bounds: U32, inverse_address: U32, inverse_screen: U32, duplicates: U32}

def Point.equal(a: X.Point, b: X.Point) -> Bool:
	X.Point{x,y} = a
	X.Point{rx,ry} = b
	U32.is_eq(x,rx) && U32.is_eq(y,ry)

def Address.equal(a: X.Address, b: X.Address) -> Bool:
	X.Address{X.Owner{qx,qy},X.Local{ix,iy}} = a
	X.Address{X.Owner{rx,ry},X.Local{lx,ly}} = b
	U32.is_eq(qx,rx) && U32.is_eq(qy,ry) && U32.is_eq(ix,lx) && U32.is_eq(iy,ly)

def Address.at(+index: U32, dimensions: X.Dimensions) -> X.Address:
	X.Dimensions{+q,+s,leaf_depth} = dimensions
	+area = (s * s : U32)
	+job = (index / area : U32)
	+local = (index % area : U32)
	X.Address{X.Owner{(job % q : U32),(job / q : U32)},X.Local{(local % s : U32),(local / s : U32)}}

def Mark.saved(index: U32, +counts: Counts, result: Array<U32> & U32) -> Array<U32> & Counts:
	Counts{addresses,out_of_bounds,inverse_address,inverse_screen,duplicates} = counts
	(marks,+old) = result
	(Array.set(U32,marks,index,(old + 1 : U32)),
		Counts{addresses,out_of_bounds,inverse_address,inverse_screen,
			(duplicates + Bool.to_u32((old > 0 : U32)) : U32)})

def Mark(valid: Bool, point: X.Point, marks: Array<U32>, counts: Counts) -> Array<U32> & Counts:
	match valid:
		case False{}: (marks,counts)
		case True{}:
			X.Point{x,y} = point
			+index = (y * 512 + x : U32)
			Mark.saved(index,counts,Array.get(U32,marks,index))

def State.bind(result: Array<U32> & Counts, next: Array<U32> -> Counts -> Array<U32> & Counts) -> Array<U32> & Counts:
	(marks,counts) = result
	next(marks,counts)

def Visit(fuel: Nat, counts: Counts, +schedule: X.Schedule, +dimensions: X.Dimensions, +index: U32,
	marks: Array<U32>) -> Array<U32> & Counts:
	match fuel counts:
		case 0n totals: (marks,totals)
		case 1n+rest Counts{+addresses,+out_of_bounds,+inverse_address,+inverse_screen,+duplicates}:
			+address = Address.at(index,dimensions)
			+point = X.Assign.pixel(schedule,address)
			+screen = {X.Point{(index % 512 : U32),(index / 512 : U32)} : X.Point}
			+owner = X.Assign.inverse(schedule,screen)
			+valid = X.Point.bounded(point)
			+next = {Counts{(addresses + 1 : U32),
				(out_of_bounds + Bool.to_u32(Bool.not(valid && X.Address.bounded(schedule,address) && X.Address.bounded(schedule,owner))) : U32),
				(inverse_address + Bool.to_u32(Bool.not(Address.equal(X.Assign.inverse(schedule,point),address))) : U32),
				(inverse_screen + Bool.to_u32(Bool.not(Point.equal(X.Assign.pixel(schedule,owner),screen))) : U32),duplicates} : Counts}
			State.bind(Mark(valid,point,marks,next),next_marks => next_counts =>
				Visit(rest,next_counts,schedule,dimensions,(index + 1 : U32),next_marks))

def Array.bind(result: Array<U32> & U32, next: Array<U32> -> U32 -> Array<U32> & U32) -> Array<U32> & U32:
	(marks,value) = result
	next(marks,value)

def Coverage(fuel: Nat, +index: U32, marks: Array<U32>, failures: U32) -> Array<U32> & U32:
	match fuel:
		case 0n: (marks,failures)
		case 1n+rest:
			Array.bind(Array.get(U32,marks,index),next_marks => value =>
				Coverage(rest,(index + 1 : U32),next_marks,
					(failures + Bool.to_u32(U32.is_ne(value,1)) : U32)))

def Require(valid: Bool, message: String) -> IO(Unit):
	match valid:
		case True{}: IO.pure(Unit,Unit{})
		case False{}: IO.die(Unit,1,message)

def Report.coverage(+label: String, +counts: Counts, result: Array<U32> & U32) -> IO(Unit):
	Counts{+addresses,+out_of_bounds,+inverse_address,+inverse_screen,+duplicates} = counts
	(marks,+coverage_failures) = result
	do IO<Unit>:
		IO.print(label ++ " addresses=" ++ U32.show(addresses) ++ " out_of_bounds=" ++ U32.show(out_of_bounds) ++
			" inverse_address=" ++ U32.show(inverse_address) ++ " inverse_screen=" ++ U32.show(inverse_screen) ++
			" duplicates=" ++ U32.show(duplicates) ++ " coverage_failures=" ++ U32.show(coverage_failures))
		Require(U32.is_eq(addresses,262144) && U32.is_zero(out_of_bounds) && U32.is_zero(inverse_address) &&
			U32.is_zero(inverse_screen) && U32.is_zero(duplicates) && U32.is_zero(coverage_failures),"Assignment property failed")

def Report(+label: String, result: Array<U32> & Counts) -> IO(Unit):
	(marks,+counts) = result
	Report.coverage(label,counts,Coverage(262144n,0,marks,0))

def Check(+schedule: X.Schedule, label: String) -> IO(Unit):
	do IO<Unit>:
		Require(X.Schedule.valid(schedule),"Invalid derived dimensions")
		Report(label,Visit(262144n,Counts{0,0,0,0,0},schedule,X.Schedule.dimensions(schedule),0,Array.new(U32,18n,0)))

def Depths(depths: List<&2,X.ForkDepth>) -> IO(Unit):
	match depths:
		case Nil{}: IO.pure(Unit,Unit{})
		case Con{+depth,rest}:
			do IO<Unit>:
				Check(X.Schedule{depth,X.Contiguous{}},"contiguous f=" ++ Nat.show(X.ForkDepth.nat(depth)))
				Check(X.Schedule{depth,X.Interleaved{}},"interleaved f=" ++ Nat.show(X.ForkDepth.nat(depth)))
				Depths(rest)

def main() -> IO(Unit):
	Depths([X.F0{},X.F1{},X.F2{},X.F3{},X.F4{},X.F5{},X.F6{},X.F7{},X.F8{},X.F9{}])
