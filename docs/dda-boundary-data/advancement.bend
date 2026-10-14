import Base
import ./candidate-dda.bend as C
import ../../voxel.bend as V
import ../../render.bend as R
import ./baseline-dda.bend as B
import ../../voxel.bend as BV
import ../../render.bend as BR

type Domain is Data:
	Domain{low: U32, cell: U32, high: U32}

type AxisInput is Data:
	AxisInput{moving: Bool, positive: Bool, origin: F32, delta: F32, cell: U32, time: F32, boundary: F32, low: U32, high: U32}

type RegionInput is Data:
	RegionInput{eye: R.Vec3, ray: R.Vec3, cell: V.Cell, low: V.Cell, high: V.Cell}

type Errors is Data:
	Errors{count: U32, depth: U32, cell: U32, previous: U32, crosses: U32, direction: U32, bounds: U32}

type Stats is Data:
	Stats{samples: U32, reuse: U32, fallback: U32, stopped: U32, coverage: U32, failures: U32, errors: Errors, first: Maybe<&2,String>}

def Float(bits: U32) -> F32:
	U32{word} = bits
	F32{word}

def Require(valid: Bool, message: String) -> IO(Unit):
	match valid:
		case True{}: IO.pure(Unit,Unit{})
		case False{}: IO.die(Unit,1,message)

def Flag(value: Bool, bit: U32) -> U32:
	Bool.pick(U32,value,bit,0)

def Errors.zero() -> Errors:
	Errors{0,0,0,0,0,0,0}

def Errors.add(a: Errors, b: Errors) -> Errors:
	Errors{ac,ad,ax,ap,af,ar,ab} = a
	Errors{bc,bd,bx,bp,bf,br,bb} = b
	Errors{(ac + bc : U32),(ad + bd : U32),(ax + bx : U32),(ap + bp : U32),(af + bf : U32),(ar + br : U32),(ab + bb : U32)}

def Errors.any(errors: Errors) -> Bool:
	Errors{count,depth,cell,previous,crosses,direction,bounds} = errors
	U32.is_ne((count .|. depth .|. cell .|. previous .|. crosses .|. direction .|. bounds : U32),0)

def First.keep(first: Maybe<&2,String>, next: Maybe<&2,String>) -> Maybe<&2,String>:
	match first:
		case Some{text}: Some{text}
		case None{}: next

def Stats.zero() -> Stats:
	Stats{0,0,0,0,0,0,Errors.zero(),None{}}

def Stats.record(reuse: U32, fallback: U32, stopped: U32, coverage: U32, +errors: Errors, first: Maybe<&2,String>, stats: Stats) -> Stats:
	Stats{n,r,f,s,c,b,e,w} = stats
	Stats{(n + 1 : U32),(r + reuse : U32),(f + fallback : U32),(s + stopped : U32),(c .|. coverage : U32),
		(b + Bool.to_u32(Errors.any(errors)) : U32),Errors.add(e,errors),First.keep(w,first)}

def Stats.add(a: Stats, b: Stats) -> Stats:
	Stats{an,ar,af,as,ac,ab,ae,aw} = a
	Stats{bn,br,bf,bs,bc,bb,be,bw} = b
	Stats{(an + bn : U32),(ar + br : U32),(af + bf : U32),(as + bs : U32),(ac .|. bc : U32),(ab + bb : U32),Errors.add(ae,be),First.keep(aw,bw)}

def Axis.limit(positive: Bool, domain: Domain) -> U32:
	Domain{low,+cell,high} = domain
	Bool.pick(U32,positive,(high - cell : U32),(cell - low + 1 : U32))

def Axis.reuse(input: AxisInput) -> Bool:
	AxisInput{moving,positive,origin,delta,+cell,time,boundary,low,+high} = input
	moving && ((low <= cell) && (cell < high) && (high <= 16777216) : U32) && F32.is_eq(time,boundary)

def Axis.counts(moving: Bool, reuse: Bool, +positive: Bool, +origin: F32, +delta: F32, +cell: U32, +time: F32, +limit: U32) -> U32 & U32:
	match moving:
		case False{}: (0,0)
		case True{}:
			(C.Axis.advance.count(reuse,positive,origin,delta,cell,time,limit),B.Axis.count(positive,origin,delta,cell,time,limit))

def Axis.coverage(input: AxisInput, +reuse: Bool, actual_count: U32, result: C.Advance) -> U32:
	AxisInput{+moving,+positive,+origin,+delta,+cell,+time,+boundary,+low,+high} = input
	C.Advance{next,previous,crosses} = result
	+valid = ((low <= cell) && (cell < high) : U32)
	+delta_bits = (F32.bits(delta) .&. 2147483647 : U32)
	+origin_bits = (F32.bits(origin) .&. 2147483647 : U32)
	+limit = Axis.limit(positive,Domain{low,cell,high})
	(Flag(reuse && positive,1) .|. Flag(reuse && Bool.not(positive),2)
		.|. Flag(moving && (high > 16777216 : U32),4) .|. Flag(moving && Bool.not(valid),8)
		.|. Flag(reuse && F32.is_eq(time,1.0e30),16) .|. Flag(Bool.not(moving) && F32.is_eq(time,boundary),32)
		.|. Flag(reuse && Bool.not(positive) && U32.is_zero(low) && U32.is_eq(next,4294967295) && U32.is_zero(previous) && crosses,64)
		.|. Flag(reuse && U32.is_eq(delta_bits,2139095040),128) .|. Flag(reuse && U32.is_eq(origin_bits,2139095040),256)
		.|. Flag(moving && Bool.not(F32.is_eq(boundary,boundary)),512)
		.|. Flag(reuse && (delta_bits > 0 : U32) && (delta_bits < 8388608 : U32),1024)
		.|. Flag(moving && Bool.not(F32.is_eq(time,boundary)),2048)
		.|. Flag(Bool.not(moving) && U32.is_eq(F32.bits(delta),2147483648),4096)
		.|. Flag(moving && valid && (high > 16777216 : U32) && F32.is_eq(time,boundary) && U32.is_ne(actual_count,limit),8192)
		.|. Flag(reuse && U32.is_eq(F32.bits(time),2147483648),16384) : U32)

def Axis.witness(failed: Bool, input: AxisInput, count: U32, actual_count: U32, candidate: C.Advance, baseline: B.Advance) -> Maybe<&2,String>:
	match failed:
		case False{}: None{}
		case True{}:
			AxisInput{moving,positive,origin,delta,cell,time,boundary,low,high} = input
			C.Advance{cc,cp,cf} = candidate
			B.Advance{bc,bp,bf} = baseline
			Some{"axis moving=" ++ U32.show(Bool.to_u32(moving)) ++ " positive=" ++ U32.show(Bool.to_u32(positive))
				++ " origin_bits=" ++ U32.show(F32.bits(origin)) ++ " delta_bits=" ++ U32.show(F32.bits(delta))
				++ " cell=" ++ U32.show(cell) ++ " time_bits=" ++ U32.show(F32.bits(time)) ++ " boundary_bits=" ++ U32.show(F32.bits(boundary))
				++ " low=" ++ U32.show(low) ++ " high=" ++ U32.show(high) ++ " selected_count=" ++ U32.show(count) ++ " actual_count=" ++ U32.show(actual_count)
				++ " candidate=" ++ U32.show(cc) ++ "," ++ U32.show(cp) ++ "," ++ U32.show(Bool.to_u32(cf))
				++ " baseline=" ++ U32.show(bc) ++ "," ++ U32.show(bp) ++ "," ++ U32.show(Bool.to_u32(bf))}

def Axis.compare(input: AxisInput, pair_sample: U32 & U32, +candidate: C.Advance, +baseline: B.Advance, stats: Stats) -> Stats:
	AxisInput{+moving,+positive,+origin,+delta,+cell,+time,+boundary,+low,+high} = input
	(+count,+actual_count) = pair_sample
	C.Advance{cc,cp,cf} = candidate
	B.Advance{bc,bp,bf} = baseline
	+input = {AxisInput{moving,positive,origin,delta,cell,time,boundary,low,high} : AxisInput}
	+reuse = Axis.reuse(input)
	+errors = {Errors{Bool.to_u32(U32.is_ne(count,actual_count)),0,Bool.to_u32(U32.is_ne(cc,bc)),Bool.to_u32(U32.is_ne(cp,bp)),Bool.to_u32(U32.is_ne(Bool.to_u32(cf),Bool.to_u32(bf))),0,0} : Errors}
	Stats.record(Bool.to_u32(reuse),Bool.to_u32(moving && Bool.not(reuse)),Bool.to_u32(Bool.not(moving)),Axis.coverage(input,reuse,actual_count,candidate),
		errors,Axis.witness(Errors.any(errors),input,count,actual_count,candidate,baseline),stats)

def Axis.check(input: AxisInput, stats: Stats) -> Stats:
	AxisInput{+moving,+positive,+origin,+delta,+cell,+time,+boundary,+low,+high} = input
	+input = {AxisInput{moving,positive,origin,delta,cell,time,boundary,low,high} : AxisInput}
	Axis.compare(input,Axis.counts(moving,Axis.reuse(input),positive,origin,delta,cell,time,Axis.limit(positive,Domain{low,cell,high})),
		C.Axis.advance(moving,positive,origin,delta,cell,time,boundary,low,high),B.Axis.advance(moving,positive,origin,delta,cell,time,low,high),stats)

def Axis.bounded(bounded: Bool, input: AxisInput, stats: Stats) -> Stats:
	match bounded:
		case True{}: Axis.check(input,stats)
		case False{}: Stats.record(0,0,0,0,Errors{0,0,0,0,0,0,1},Some{"axis modular limit exceeds eight"},stats)

def Axis.times(times: List<&2,F32>, +moving: Bool, +positive: Bool, +origin: F32, +delta: F32, +boundary: F32, +domain: Domain, stats: Stats) -> Stats:
	match times:
		case Nil{}: stats
		case time <> rest:
			Domain{low,cell,high} = domain
			+bounded = Bool.not(moving) || (Axis.limit(positive,domain) <= 8 : U32)
			Axis.times(rest,moving,positive,origin,delta,boundary,domain,
				Axis.bounded(bounded,AxisInput{moving,positive,origin,delta,cell,time,boundary,low,high},stats))

def Times(+boundary: F32) -> List<&2,F32>:
	+bits = F32.bits(boundary)
	[boundary,Float((bits - 1 : U32)),Float((bits + 1 : U32)),0.0,Float(2147483648),1.0e30,Float(2143289345)]

def Axis.origins(origins: List<&2,F32>, +delta: F32, +domain: Domain, stats: Stats) -> Stats:
	match origins:
		case Nil{}: stats
		case +origin <> rest:
			Domain{low,cell,high} = domain
			+moving = F32.is_ne(delta,0.0)
			+positive = (delta > 0.0 : F32)
			+boundary = B.Axis.next(moving,positive,origin,delta,Bool.pick(U32,positive,(high - 1 : U32),low))
			Axis.origins(rest,delta,domain,Axis.times(Times(boundary),moving,positive,origin,delta,boundary,domain,stats))

def Origins(edges: Bool, domain: Domain) -> List<&2,F32>:
	match edges domain:
		case True{} Domain{low,+cell,high}: [0.0,U32.to_f32(cell),(U32.to_f32(cell) + 0.5 : F32)]
		case False{} Domain{+low,+cell,high}: [(U32.to_f32(low) - 1.0 : F32),U32.to_f32(low),U32.to_f32(cell),(U32.to_f32(cell) + 0.5 : F32),
			(U32.to_f32(high) + 1.0 : F32),Float(2147483648),Float(2139095040),Float(4286578688),Float(2143289345)]

def Delta.bits(edges: Bool) -> List<&2,U32>:
	match edges:
		case True{}: [1065353216,1,2139095040,0]
		case False{}: [0,1,8388607,8388608,F32.bits(1.0e-30),1056964608,1065353216,1073741824,2139095039,2139095040,2143289345]

def Axis.deltas(bits: List<&2,U32>, +edges: Bool, +domain: Domain, stats: Stats) -> Stats:
	match bits:
		case Nil{}: stats
		case +bits <> rest:
			Axis.deltas(rest,edges,domain,Axis.origins(Origins(edges,domain),Float((bits .|. 2147483648 : U32)),domain,
				Axis.origins(Origins(edges,domain),Float(bits),domain,stats)))

def Axis.domains(domains: List<&2,Domain>, +edges: Bool, stats: Stats) -> Stats:
	match domains:
		case Nil{}: stats
		case +domain <> rest:
			Axis.domains(rest,edges,Axis.deltas(Delta.bits(edges),edges,domain,stats))

def Domains.cells(cells: List<&2,Nat>, +low: U32, +high: U32, tail: List<&2,Domain>) -> List<&2,Domain>:
	match cells:
		case Nil{}: tail
		case cell <> rest:
			Domain{low,(low + U32.from_nat(cell) : U32),high} <> Domains.cells(rest,low,high,tail)

def Domains.widths(widths: List<&2,Nat>, +high: U32, tail: List<&2,Domain>) -> List<&2,Domain>:
	match widths:
		case Nil{}: tail
		case +width <> rest:
			+size = U32.from_nat(1n+width)
			Domains.cells(List.range(1n+width),(high - size : U32),high,Domains.widths(rest,high,tail))

def Domains.small(highs: List<&2,Nat>) -> List<&2,Domain>:
	match highs:
		case Nil{}: Nil{}
		case +high <> rest:
			Domains.widths(List.range(1n+high),U32.from_nat(1n+high),Domains.small(rest))

def Domains.edges(highs: List<&2,U32>) -> List<&2,Domain>:
	match highs:
		case Nil{}: Nil{}
		case high <> rest:
			Domains.widths(List.range(8n),high,Domains.edges(rest))

def Domains.malformed() -> List<&2,Domain>:
	[Domain{0,0,0},Domain{1,0,1},Domain{4,4,4},Domain{4,3,3},Domain{4294967295,4294967295,0},Domain{4294967295,0,2},Domain{4294967293,4294967295,1}]

def Vec.baseline(vec: R.Vec3) -> BR.Vec3:
	R.Vec3{x,y,z} = vec
	BR.Vec3{x,y,z}

def Cell.baseline(cell: V.Cell) -> BV.Cell:
	V.Cell{x,y,z} = cell
	BV.Cell{x,y,z}

def Cell.errors(candidate: V.Cell, baseline: BV.Cell) -> U32:
	V.Cell{x,y,z} = candidate
	BV.Cell{bx,by,bz} = baseline
	(Bool.to_u32(U32.is_ne(x,bx)) + Bool.to_u32(U32.is_ne(y,by)) + Bool.to_u32(U32.is_ne(z,bz)) : U32)

def Direction.candidate(direction: V.Direction) -> U32:
	match direction:
		case V.NegX{}: 0
		case V.PosX{}: 1
		case V.NegY{}: 2
		case V.PosY{}: 3
		case V.NegZ{}: 4
		case V.PosZ{}: 5

def Direction.baseline(direction: BV.Direction) -> U32:
	match direction:
		case BV.NegX{}: 0
		case BV.PosX{}: 1
		case BV.NegY{}: 2
		case BV.PosY{}: 3
		case BV.NegZ{}: 4
		case BV.PosZ{}: 5

def Cell.show(cell: V.Cell) -> String:
	V.Cell{x,y,z} = cell
	U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z)

def Vec.bits(vec: R.Vec3) -> String:
	R.Vec3{x,y,z} = vec
	U32.show(F32.bits(x)) ++ "," ++ U32.show(F32.bits(y)) ++ "," ++ U32.show(F32.bits(z))

def Region.witness(failed: Bool, input: RegionInput, candidate: C.Crossing, baseline: B.Crossing) -> Maybe<&2,String>:
	match failed:
		case False{}: None{}
		case True{}:
			RegionInput{eye,ray,cell,low,high} = input
			C.Crossing{ct,cc,cp,cd} = candidate
			B.Crossing{bt,BV.Cell{bx,by,bz},BV.Cell{px,py,pz},bd} = baseline
			Some{"region eye_bits=" ++ Vec.bits(eye) ++ " ray_bits=" ++ Vec.bits(ray) ++ " cell=" ++ Cell.show(cell) ++ " low=" ++ Cell.show(low) ++ " high=" ++ Cell.show(high)
				++ " candidate=" ++ U32.show(F32.bits(ct)) ++ ";" ++ Cell.show(cc) ++ ";" ++ Cell.show(cp) ++ ";" ++ U32.show(Direction.candidate(cd))
				++ " baseline=" ++ U32.show(F32.bits(bt)) ++ ";" ++ U32.show(bx) ++ "," ++ U32.show(by) ++ "," ++ U32.show(bz)
				++ ";" ++ U32.show(px) ++ "," ++ U32.show(py) ++ "," ++ U32.show(pz) ++ ";" ++ U32.show(Direction.baseline(bd))}

def Region.axis(+origin: F32, +delta: F32, cell: U32, +time: F32, +low: U32, +high: U32) -> U32:
	+moving = F32.is_ne(delta,0.0)
	+positive = (delta > 0.0 : F32)
	+boundary = B.Axis.next(moving,positive,origin,delta,Bool.pick(U32,positive,(high - 1 : U32),low))
	(Flag(moving,1) .|. Flag(Axis.reuse(AxisInput{moving,positive,origin,delta,cell,time,boundary,low,high}),2)
		.|. Flag(moving && F32.is_eq(time,boundary),4) : U32)

def Region.compare(input: RegionInput, +candidate: C.Crossing, +baseline: B.Crossing, stats: Stats) -> Stats:
	RegionInput{R.Vec3{+ox,+oy,+oz},R.Vec3{+dx,+dy,+dz},V.Cell{+x,+y,+z},V.Cell{+lx,+ly,+lz},V.Cell{+hx,+hy,+hz}} = input
	C.Crossing{+time,cc,cp,+cd} = candidate
	B.Crossing{bt,bc,bp,bd} = baseline
	+input = {RegionInput{R.Vec3{ox,oy,oz},R.Vec3{dx,dy,dz},V.Cell{x,y,z},V.Cell{lx,ly,lz},V.Cell{hx,hy,hz}} : RegionInput}
	+ax = Region.axis(ox,dx,x,time,lx,hx)
	+ay = Region.axis(oy,dy,y,time,ly,hy)
	+az = Region.axis(oz,dz,z,time,lz,hz)
	+rx = U32.is_ne((ax .&. 2 : U32),0)
	+ry = U32.is_ne((ay .&. 2 : U32),0)
	+rz = U32.is_ne((az .&. 2 : U32),0)
	+mx = U32.is_ne((ax .&. 1 : U32),0)
	+my = U32.is_ne((ay .&. 1 : U32),0)
	+mz = U32.is_ne((az .&. 1 : U32),0)
	+tx = U32.is_ne((ax .&. 4 : U32),0)
	+ty = U32.is_ne((ay .&. 4 : U32),0)
	+tz = U32.is_ne((az .&. 4 : U32),0)
	+errors = {Errors{0,Bool.to_u32(U32.is_ne(F32.bits(time),F32.bits(bt))),Cell.errors(cc,bc),Cell.errors(cp,bp),0,Bool.to_u32(U32.is_ne(Direction.candidate(cd),Direction.baseline(bd))),0} : Errors}
	+ties = (Bool.to_u32(tx) + Bool.to_u32(ty) + Bool.to_u32(tz) : U32)
	+coverage = (Flag(U32.is_eq(ties,2),1) .|. Flag(U32.is_eq(ties,3),2)
		.|. Flag(tx && ty && Bool.not(tz),4) .|. Flag(tx && tz && Bool.not(ty),8) .|. Flag(ty && tz && Bool.not(tx),16)
		.|. Flag(F32.is_eq(time,1.0e30) && (mx || my || mz) && Bool.not(mx && my && mz),32)
		.|. Flag(U32.is_eq(F32.bits(time),2147483648),64) .|. U32.shln(256,U32.to_nat(Direction.candidate(cd))) : U32)
	Stats.record((Bool.to_u32(rx) + Bool.to_u32(ry) + Bool.to_u32(rz) : U32),
		(Bool.to_u32(mx && Bool.not(rx)) + Bool.to_u32(my && Bool.not(ry)) + Bool.to_u32(mz && Bool.not(rz)) : U32),
		(Bool.to_u32(Bool.not(mx)) + Bool.to_u32(Bool.not(my)) + Bool.to_u32(Bool.not(mz)) : U32),coverage,
		errors,Region.witness(Errors.any(errors),input,candidate,baseline),stats)

def Region.run(input: RegionInput, stats: Stats) -> Stats:
	RegionInput{+eye,+ray,+cell,+low,+high} = input
	Region.compare(RegionInput{eye,ray,cell,low,high},C.Crossing.region(eye,ray,cell,C.Region{0,low,high}),
		B.Crossing.region(Vec.baseline(eye),Vec.baseline(ray),Cell.baseline(cell),B.Region{0,Cell.baseline(low),Cell.baseline(high)}),stats)

def Region.limits(input: RegionInput) -> Bool:
	RegionInput{eye,R.Vec3{+dx,+dy,+dz},V.Cell{x,y,z},V.Cell{lx,ly,lz},V.Cell{hx,hy,hz}} = input
	(F32.is_eq(dx,0.0) || (Axis.limit((dx > 0.0 : F32),Domain{lx,x,hx}) <= 8 : U32))
		&& (F32.is_eq(dy,0.0) || (Axis.limit((dy > 0.0 : F32),Domain{ly,y,hy}) <= 8 : U32))
		&& (F32.is_eq(dz,0.0) || (Axis.limit((dz > 0.0 : F32),Domain{lz,z,hz}) <= 8 : U32))

def Region.bounded(bounded: Bool, input: RegionInput, stats: Stats) -> Stats:
	match bounded:
		case True{}: Region.run(input,stats)
		case False{}: Stats.record(0,0,0,0,Errors{0,0,0,0,0,0,1},Some{"region modular limit exceeds eight"},stats)

def Region.check(+input: RegionInput, stats: Stats) -> Stats:
	Region.bounded(Region.limits(input),input,stats)

def Tie.axis(active: Bool, +positive: Bool, +magnitude: F32, +width: U32, +index: U32) -> U32 & (F32 & F32):
	+cell = Bool.pick(U32,positive,index,(width - 1 - index : U32))
	+delta = Bool.pick(F32,positive,magnitude,F32.neg(magnitude))
	(cell,((U32.to_f32(cell) + 0.5 : F32),Bool.pick(F32,active,delta,Bool.pick(F32,positive,0.0,Float(2147483648)))))

def Tie.input.axes(ax: U32 & (F32 & F32), ay: U32 & (F32 & F32), az: U32 & (F32 & F32), +width: U32) -> RegionInput:
	(x,(ox,dx)) = ax
	(y,(oy,dy)) = ay
	(z,(oz,dz)) = az
	RegionInput{R.Vec3{ox,oy,oz},R.Vec3{dx,dy,dz},V.Cell{x,y,z},V.Cell{0,0,0},V.Cell{width,width,width}}

def Tie.input(+pattern: U32, +signs: U32, +magnitude: F32, +width: U32, +index: U32) -> RegionInput:
	Tie.input.axes(Tie.axis(U32.is_ne((pattern .&. 1 : U32),0),U32.is_ne((signs .&. 1 : U32),0),magnitude,width,index),
		Tie.axis(U32.is_ne((pattern .&. 2 : U32),0),U32.is_ne((signs .&. 2 : U32),0),magnitude,width,index),
		Tie.axis(U32.is_ne((pattern .&. 4 : U32),0),U32.is_ne((signs .&. 4 : U32),0),magnitude,width,index),width)

def Ties.patterns(patterns: List<&2,U32>, +signs: U32, +magnitude: F32, +width: U32, +index: U32, stats: Stats) -> Stats:
	match patterns:
		case Nil{}: stats
		case pattern <> rest: Ties.patterns(rest,signs,magnitude,width,index,Region.check(Tie.input(pattern,signs,magnitude,width,index),stats))

def Ties.signs(signs: List<&2,Nat>, +magnitude: F32, +width: U32, +index: U32, stats: Stats) -> Stats:
	match signs:
		case Nil{}: stats
		case signs <> rest: Ties.signs(rest,magnitude,width,index,Ties.patterns([3,5,6,7],U32.from_nat(signs),magnitude,width,index,stats))

def Ties.magnitudes(magnitudes: List<&2,F32>, +width: U32, +index: U32, stats: Stats) -> Stats:
	match magnitudes:
		case Nil{}: stats
		case magnitude <> rest: Ties.magnitudes(rest,width,index,Ties.signs(List.range(8n),magnitude,width,index,stats))

def Ties.cells(cells: List<&2,Nat>, +width: U32, stats: Stats) -> Stats:
	match cells:
		case Nil{}: stats
		case cell <> rest: Ties.cells(rest,width,Ties.magnitudes([1.0,Float(1),Float(2139095039),Float(2139095040),1.0e-30],width,U32.from_nat(cell),stats))

def Ties.widths(widths: List<&2,Nat>, stats: Stats) -> Stats:
	match widths:
		case Nil{}: stats
		case +width <> rest: Ties.widths(rest,Ties.cells(List.range(1n+width),U32.from_nat(1n+width),stats))

def Regions.extra() -> List<&2,RegionInput>:
	+zero = {V.Cell{0,0,0} : V.Cell}
	+one = {V.Cell{1,1,1} : V.Cell}
	+eye = {R.Vec3{0.0,0.0,0.0} : R.Vec3}
	[RegionInput{eye,R.Vec3{1.0e-30,0.0,0.0},zero,zero,one},
		RegionInput{eye,R.Vec3{1.0e-30,1.0e-30,0.0},zero,zero,one},
		RegionInput{eye,R.Vec3{1.0e-30,1.0e-30,1.0e-30},zero,zero,one},
		RegionInput{eye,R.Vec3{0.0,0.0,1.0},zero,zero,one},
		RegionInput{eye,R.Vec3{0.0,Float(2147483648),0.0},zero,zero,one},
		RegionInput{eye,R.Vec3{F32.neg(1.0),F32.neg(1.0),F32.neg(1.0)},zero,zero,one},
		RegionInput{R.Vec3{Float(2147483648),0.0,0.0},R.Vec3{F32.neg(1.0),0.0,0.0},zero,zero,one},
		RegionInput{eye,R.Vec3{1.0,2.0,3.0},zero,zero,V.Cell{1,2,3}},
		RegionInput{R.Vec3{1.0,2.0,3.0},R.Vec3{F32.neg(1.0),F32.neg(2.0),F32.neg(3.0)},V.Cell{0,1,2},zero,V.Cell{1,2,3}},
		RegionInput{R.Vec3{Float(2139095040),0.0,0.0},R.Vec3{1.0,2.0,0.0},zero,zero,one},
		RegionInput{R.Vec3{Float(2143289345),0.0,0.0},R.Vec3{1.0,1.0,0.0},zero,zero,one},
		RegionInput{eye,R.Vec3{Float(2143289345),1.0,1.0},zero,zero,one},
		RegionInput{eye,R.Vec3{Float(2139095040),Float(2139095040),0.0},zero,zero,one},
		RegionInput{eye,R.Vec3{1.0,1.0,1.0},V.Cell{16777217,16777217,16777217},V.Cell{16777217,16777217,16777217},V.Cell{16777218,16777218,16777218}},
		RegionInput{eye,R.Vec3{1.0,1.0,1.0},V.Cell{2147483647,2147483647,2147483647},V.Cell{2147483647,2147483647,2147483647},V.Cell{2147483649,2147483649,2147483649}},
		RegionInput{eye,R.Vec3{1.0,1.0,1.0},V.Cell{4294967294,4294967294,4294967294},V.Cell{4294967294,4294967294,4294967294},V.Cell{4294967295,4294967295,4294967295}},
		RegionInput{eye,R.Vec3{F32.neg(1.0),F32.neg(1.0),F32.neg(1.0)},V.Cell{4294967295,4294967295,4294967295},V.Cell{4294967295,4294967295,4294967295},zero}]

def Regions.scan(inputs: List<&2,RegionInput>, stats: Stats) -> Stats:
	match inputs:
		case Nil{}: stats
		case input <> rest: Regions.scan(rest,Region.check(input,stats))

def Stats.report(+name: String, expected: U32, +required: U32, stats: Stats) -> IO(Unit):
	Stats{+n,r,f,s,+c,+bad,Errors{count,depth,cell,previous,crosses,direction,bounds},first} = stats
	do IO<Unit>:
		IO.print("family=" ++ name ++ " samples=" ++ U32.show(n) ++ " reuse=" ++ U32.show(r) ++ " fallback=" ++ U32.show(f) ++ " stopped=" ++ U32.show(s)
			++ " coverage_mask=" ++ U32.show(c) ++ " mismatch_samples=" ++ U32.show(bad) ++ " count_mismatches=" ++ U32.show(count)
			++ " depth_bit_mismatches=" ++ U32.show(depth) ++ " cell_field_mismatches=" ++ U32.show(cell) ++ " previous_field_mismatches=" ++ U32.show(previous)
			++ " crossing_flag_mismatches=" ++ U32.show(crosses) ++ " direction_mismatches=" ++ U32.show(direction) ++ " unbounded_samples=" ++ U32.show(bounds))
		IO.print("first_mismatch=" ++ Maybe.default(&2,String,first,"none"))
		Require(U32.is_eq(n,expected),name ++ " missing planned samples")
		Require(U32.is_eq((c .&. required : U32),required),name ++ " missing required branch coverage")
		Require(U32.is_zero(bad),name ++ " candidate differs from frozen baseline")

def main() -> IO(Unit):
	do IO<Unit>:
		+small : Stats <- IO.pure(Stats,Axis.domains(Domains.small(List.range(8n)),False{},Stats.zero()))
		Stats.report("small",166320,24563,small)
		+edges : Stats <- IO.pure(Stats,Axis.domains(Domains.edges([16777212,16777213,16777214,16777215,16777216,16777217,16777218,16777219,16777220,
			2147483647,2147483648,2147483649,4294967294,4294967295]),True{},Stats.zero()))
		Stats.report("precision",84672,12295,edges)
		+malformed : Stats <- IO.pure(Stats,Axis.domains(Domains.malformed(),False{},Stats.zero()))
		Stats.report("malformed",9702,4616,malformed)
		+regions : Stats <- IO.pure(Stats,Regions.scan(Regions.extra(),Ties.widths(List.range(8n),Stats.zero())))
		Stats.report("regions",5777,16255,regions)
		Stats.report("axis_total",260694,32767,Stats.add(small,Stats.add(edges,malformed)))
		IO.print("exact_boundary_properties_passed")
