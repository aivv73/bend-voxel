import Base
import ./baseline-dda.bend as D

type Sample is Data:
	Sample{family: U32, origin: F32, delta: F32, low: U32, cell: U32, high: U32}

type Witness is Data:
	Witness{sample: Sample, kind: U32, time: F32, boundary: F32, moving: Bool, positive: Bool, limit: U32, actual: U32}

type Stats is Data:
	Stats{checks: U32, calls: U32, reuses: U32, raw_equal: U32, unsafe: U32, known: U32, rejected: U32,
		positive: U32, negative: U32, nonfinite_origin: U32, nonfinite_delta: U32, nonfinite_time: U32}

type Families is Data:
	Families{small: U32, edge: U32, huge: U32, origin: U32, delta: U32, time: U32, mixed: U32, special: U32}

type ScanResult is Data:
	ScanResult{stats: Stats, families: Families, coverage: U32, time_modes: U32,
		first_unsafe: Maybe<&2,Witness>, first_known: Maybe<&2,Witness>, first_rejected: Maybe<&2,Witness>}

def Bits.float(bits: U32) -> F32:
	match bits:
		case U32{word}: F32{word}

def Bits.magnitude(value: F32) -> U32:
	(F32.bits(value) .&. 2147483647 : U32)

def Bits.nan(value: F32) -> Bool:
	(Bits.magnitude(value) > 2139095040 : U32)

def Bits.infinity(value: F32) -> Bool:
	U32.is_eq(Bits.magnitude(value),2139095040)

def Bits.nonfinite(value: F32) -> Bool:
	(Bits.magnitude(value) >= 2139095040 : U32)

def Bits.subnormal(value: F32) -> Bool:
	+magnitude = Bits.magnitude(value)
	((magnitude > 0) && (magnitude < 8388608) : U32)

def Bits.neighbor.valid(nan: Bool, zero: Bool, up: Bool, positive: Bool, +value: F32, +bits: U32) -> F32:
	match nan zero up positive:
		case True{} _ _ _: value
		case False{} True{} True{} _: Bits.float(1)
		case False{} True{} False{} _: Bits.float(2147483649)
		case False{} False{} True{} True{}:
			Bits.float(Bool.pick(U32,Bits.infinity(value),bits,(bits + 1 : U32)))
		case False{} False{} False{} True{}: Bits.float((bits - 1 : U32))
		case False{} False{} True{} False{}: Bits.float((bits - 1 : U32))
		case False{} False{} False{} False{}:
			Bits.float(Bool.pick(U32,Bits.infinity(value),bits,(bits + 1 : U32)))

def Bits.neighbor(+value: F32, +up: Bool) -> F32:
	+bits = F32.bits(value)
	Bits.neighbor.valid(Bits.nan(value),F32.is_eq(value,0.0),up,(bits < 2147483648 : U32),value,bits)

def Sample.valid(sample: Sample, +kind: U32) -> Bool:
	Sample{family,origin,delta,+low,+cell,+high} = sample
	((low <= cell) && (cell < high) && (high - low <= 16) && (family <= 7) && (kind <= 18) : U32)

def Sample.boundary(sample: Sample) -> F32:
	Sample{family,origin,+delta,low,cell,high} = sample
	+positive = (delta > 0.0 : F32)
	D.Axis.next(F32.is_ne(delta,0.0),positive,origin,delta,Bool.pick(U32,positive,(high - 1 : U32),low))

def First.keep(bad: Bool, witness: Witness, first: Maybe<&2,Witness>) -> Maybe<&2,Witness>:
	match bad first:
		case True{} None{}: Some{witness}
		case _ prior: prior

def Families.add(families: Families, family: U32) -> Families:
	Families{a,b,c,d,e,f,g,h} = families
	match family:
		case 0: Families{(a + 1 : U32),b,c,d,e,f,g,h}
		case 1: Families{a,(b + 1 : U32),c,d,e,f,g,h}
		case 2: Families{a,b,(c + 1 : U32),d,e,f,g,h}
		case 3: Families{a,b,c,(d + 1 : U32),e,f,g,h}
		case 4: Families{a,b,c,d,(e + 1 : U32),f,g,h}
		case 5: Families{a,b,c,d,e,(f + 1 : U32),g,h}
		case 6: Families{a,b,c,d,e,f,(g + 1 : U32),h}
		case _: Families{a,b,c,d,e,f,g,(h + 1 : U32)}

def Flag(condition: Bool, value: U32) -> U32:
	Bool.pick(U32,condition,value,0)

def Coverage(+witness: Witness, +eligible: Bool, +unsafe: Bool) -> U32:
	Witness{Sample{family,+origin,+delta,low,cell,+high},+kind,+time,+boundary,+moving,+positive,limit,actual} = witness
	+a = (Flag(eligible && positive,1) .|. Flag(eligible && Bool.not(positive),2) .|.
		Flag(Bool.not(moving) && U32.is_eq(F32.bits(delta),0),4) .|.
		Flag(Bool.not(moving) && U32.is_eq(F32.bits(delta),2147483648),8) : U32)
	+b = (Flag(Bits.nan(origin),16) .|. Flag(Bits.nan(delta),32) .|. Flag(Bits.nan(time),64) .|.
		Flag(Bits.infinity(origin),128) .|. Flag(Bits.infinity(delta),256) .|. Flag(Bits.infinity(time),512) : U32)
	+c = (Flag(Bits.subnormal(origin),1024) .|. Flag(Bits.subnormal(delta),2048) .|.
		Flag(Bits.subnormal(time),4096) .|. Flag(eligible && U32.is_eq(high,16777216),8192) .|.
		Flag((high > 16777216 : U32),16384) .|. Flag((high >= 2147483648 : U32),32768) .|.
		Flag(U32.is_eq(high,4294967295),65536) : U32)
	+d = (Flag(eligible && U32.is_eq(F32.bits(time),2139095040),131072) .|.
		Flag(eligible && U32.is_eq(F32.bits(time),4286578688),262144) .|.
		Flag(eligible && F32.is_eq(time,0.0),524288) .|.
		Flag(eligible && F32.is_eq(time,1.0e30),1048576) .|.
		Flag(eligible && Bits.nonfinite(origin),2097152) .|.
		Flag(eligible && Bits.nonfinite(delta),4194304) .|.
		Flag(eligible && U32.is_eq(kind,2),8388608) : U32)
	+e = (Flag(moving && Bool.not(F32.is_eq(time,boundary)),16777216) .|. Flag(unsafe,33554432) .|.
		Flag(unsafe && U32.is_eq(high,16777218),67108864) .|.
		Flag(moving && (kind >= 1 : U32) && (kind <= 4 : U32) && Bool.not(F32.is_eq(time,boundary)),134217728) .|.
		Flag(moving && Bits.nan(delta) && Bool.not(F32.is_eq(time,boundary)),268435456) : U32)
	(a .|. b .|. c .|. d .|. e : U32)

def Record(result: ScanResult, +witness: Witness) -> ScanResult:
	ScanResult{Stats{checks,calls,reuses,raw,unsafe_count,known_count,rejected,pos,neg,nfo,nfd,nft},families,coverage,modes,first_unsafe,first_known,first_rejected} = result
	Witness{Sample{+family,+origin,+delta,low,cell,+high},+kind,+time,+boundary,+moving,+positive,+limit,+actual} = witness
	+equal = moving && F32.is_eq(time,boundary)
	+eligible = equal && (high <= 16777216 : U32)
	+disagrees = equal && U32.is_ne(actual,limit)
	+unsafe = disagrees && (high > 16777216 : U32)
	+known = eligible && U32.is_ne(actual,limit)
	ScanResult{Stats{(checks + 1 : U32),(calls + Bool.to_u32(moving) : U32),(reuses + Bool.to_u32(eligible) : U32),
		(raw + Bool.to_u32(equal) : U32),(unsafe_count + Bool.to_u32(unsafe) : U32),(known_count + Bool.to_u32(known) : U32),rejected,
		(pos + Bool.to_u32(eligible && positive) : U32),(neg + Bool.to_u32(eligible && Bool.not(positive)) : U32),
		(nfo + Bool.to_u32(eligible && Bits.nonfinite(origin)) : U32),
		(nfd + Bool.to_u32(eligible && Bits.nonfinite(delta)) : U32),
		(nft + Bool.to_u32(eligible && Bits.nonfinite(time)) : U32)},Families.add(families,family),
		(coverage .|. Coverage(witness,eligible,unsafe) : U32),(modes .|. U32.shln(1,U32.to_nat(kind)) : U32),
		First.keep(unsafe,witness,first_unsafe),First.keep(known,witness,first_known),first_rejected}

def Reject(sample: Sample, kind: U32, time: F32, result: ScanResult) -> ScanResult:
	ScanResult{Stats{checks,calls,reuses,raw,unsafe_count,known_count,rejected,pos,neg,nfo,nfd,nft},families,coverage,modes,first_unsafe,first_known,first_rejected} = result
	ScanResult{Stats{(checks + 1 : U32),calls,reuses,raw,unsafe_count,known_count,(rejected + 1 : U32),pos,neg,nfo,nfd,nft},
		families,coverage,modes,first_unsafe,first_known,
		First.keep(True{},Witness{sample,kind,time,0.0,False{},False{},0,0},first_rejected)}

def Count(moving: Bool, positive: Bool, origin: F32, delta: F32, cell: U32, time: F32, limit: U32) -> U32:
	match moving:
		case False{}: 0
		case True{}: D.Axis.count(positive,origin,delta,cell,time,limit)

def Check.valid(valid: Bool, +sample: Sample, +kind: U32, +time: F32, result: ScanResult) -> ScanResult:
	match valid:
		case False{}: Reject(sample,kind,time,result)
		case True{}:
			Sample{family,origin,+delta,low,+cell,high} = sample
			+moving = F32.is_ne(delta,0.0)
			+positive = (delta > 0.0 : F32)
			+limit = Bool.pick(U32,positive,(high - cell : U32),(cell - low + 1 : U32))
			+actual = Count(moving,positive,origin,delta,cell,time,limit)
			Record(result,Witness{sample,kind,time,Sample.boundary(sample),moving,positive,limit,actual})

def Check(+sample: Sample, +kind: U32, time: F32, result: ScanResult) -> ScanResult:
	Check.valid(Sample.valid(sample,kind),sample,kind,time,result)

def Times.choose(kind: U32, +boundary: F32, other: F32, third: F32) -> F32:
	match kind:
		case 0: boundary
		case 1: F32.min(boundary,other)
		case 2: F32.min(boundary,F32.min(boundary,boundary))
		case 3: F32.min(boundary,F32.min(other,third))
		case 4: F32.min(other,F32.min(boundary,third))
		case 5: Bits.neighbor(boundary,False{})
		case 6: Bits.neighbor(boundary,True{})
		case 7: Bits.float(0)
		case 8: Bits.float(2147483648)
		case 9: Bits.float(2139095040)
		case 10: Bits.float(4286578688)
		case 11: Bits.float(2143289344)
		case 12: Bits.float(2139095041)
		case 13: 1.0e30
		case _: F32.min(boundary,1.0e30)

def Times.value(+sample: Sample, kind: U32) -> F32:
	Sample{family,+origin,+delta,low,cell,+high} = sample
	+positive = (delta > 0.0 : F32)
	+moving = F32.is_ne(delta,0.0)
	+boundary_cell = Bool.pick(U32,positive,(high - 1 : U32),low)
	+boundary = Sample.boundary(sample)
	+other = D.Axis.next(moving,positive,(origin + 1.0 : F32),delta,boundary_cell)
	+third = D.Axis.next(moving,positive,(origin - 1.0 : F32),delta,boundary_cell)
	Times.choose(kind,boundary,other,third)

def Times.scan(fuel: Nat, +kind: U32, +sample: Sample, result: ScanResult) -> ScanResult:
	match fuel:
		case 0n: result
		case 1n+rest:
			Times.scan(rest,(kind + 1 : U32),sample,Check(sample,kind,Times.value(sample,kind),result))

def Geometry.ray(+family: U32, ray: U32, +low: U32, +cell: U32, +high: U32) -> Sample:
	match ray:
		case 0: Sample{family,0.0,1.0,low,cell,high}
		case 1: Sample{family,0.0,F32.neg(1.0),low,cell,high}
		case 2: Sample{family,(U32.to_f32(cell) + 0.5 : F32),1.0,low,cell,high}
		case 3: Sample{family,(U32.to_f32(cell) + 0.5 : F32),F32.neg(1.0),low,cell,high}
		case 4: Sample{family,U32.to_f32(high),Bits.float(1),low,cell,high}
		case 5: Sample{family,U32.to_f32(low),Bits.float(2147483649),low,cell,high}
		case 6: Sample{family,U32.to_f32(cell),Bits.float(2139095040),low,cell,high}
		case 7: Sample{family,U32.to_f32(cell),Bits.float(4286578688),low,cell,high}
		case 8: Sample{family,0.0,Bits.float(0),low,cell,high}
		case _: Sample{family,0.0,Bits.float(2147483648),low,cell,high}

def Geometry.rays(fuel: Nat, +ray: U32, +family: U32, +low: U32, +cell: U32, +high: U32, result: ScanResult) -> ScanResult:
	match fuel:
		case 0n: result
		case 1n+rest:
			Geometry.rays(rest,(ray + 1 : U32),family,low,cell,high,
				Times.scan(15n,0,Geometry.ray(family,ray,low,cell,high),result))

def Geometry.cells(fuel: Nat, +family: U32, +low: U32, +cell: U32, +high: U32, result: ScanResult) -> ScanResult:
	match fuel:
		case 0n: result
		case 1n+rest:
			Geometry.cells(rest,family,low,(cell + 1 : U32),high,Geometry.rays(10n,0,family,low,cell,high,result))

def Small.widths(fuel: Nat, +low: U32, +width: U32, result: ScanResult) -> ScanResult:
	match fuel:
		case 0n: result
		case 1n+rest:
			Small.widths(rest,low,(width + 1 : U32),Geometry.cells(U32.to_nat(width),0,low,low,(low + width : U32),result))

def Small.scan(fuel: Nat, +low: U32, result: ScanResult) -> ScanResult:
	match fuel:
		case 0n: result
		case 1n+rest: Small.scan(rest,(low + 1 : U32),Small.widths(16n,low,1,result))

def Edges.widths(fuel: Nat, +family: U32, +high: U32, +width: U32, result: ScanResult) -> ScanResult:
	match fuel:
		case 0n: result
		case 1n+rest:
			+low = (high - width : U32)
			Edges.widths(rest,family,high,(width + 1 : U32),Geometry.cells(U32.to_nat(width),family,low,low,high,result))

def Edges.scan(fuel: Nat, +high: U32, result: ScanResult) -> ScanResult:
	match fuel:
		case 0n: result
		case 1n+rest: Edges.scan(rest,(high + 1 : U32),Edges.widths(16n,1,high,1,result))

def Huge.scan(highs: List<&2,U32>, result: ScanResult) -> ScanResult:
	match highs:
		case Nil{}: result
		case Con{+high,rest}: Huge.scan(rest,Edges.widths(16n,2,high,1,result))

def Float.geometry(+family: U32, index: U32, origin: F32, delta: F32) -> Sample:
	match index:
		case 0: Sample{family,origin,delta,0,0,16}
		case 1: Sample{family,origin,delta,0,15,16}
		case 2: Sample{family,origin,delta,16777200,16777200,16777216}
		case _: Sample{family,origin,delta,16777200,16777215,16777216}

def Float.time(+sample: Sample, +value: F32, result: ScanResult) -> ScanResult:
	+boundary = Sample.boundary(sample)
	a = Check(sample,15,value,result)
	b = Check(sample,16,F32.min(boundary,value),a)
	c = Check(sample,17,F32.min(value,boundary),b)
	Check(sample,18,F32.min(boundary,F32.min(value,Times.value(sample,1))),c)

def Float.cell(index: U32) -> U32:
	match index:
		case 0: 0
		case 1: 15
		case 2: 16777200
		case _: 16777215

def Float.roles(+bits: U32, +geometry: U32, result: ScanResult) -> ScanResult:
	+value = Bits.float(bits)
	+base = Float.geometry(3,geometry,value,1.0)
	+cell = Float.cell(geometry)
	a = Times.scan(15n,0,base,result)
	b = Times.scan(15n,0,Float.geometry(3,geometry,value,F32.neg(1.0)),a)
	c = Times.scan(15n,0,Float.geometry(4,geometry,0.0,value),b)
	d = Times.scan(15n,0,Float.geometry(4,geometry,U32.to_f32(cell),value),c)
	e = Float.time(Float.geometry(5,geometry,0.0,1.0),value,d)
	f = Float.time(Float.geometry(5,geometry,0.0,F32.neg(1.0)),value,e)
	g = Times.scan(15n,0,Float.geometry(6,geometry,value,value),f)
	Times.scan(15n,0,Float.geometry(6,geometry,value,Bits.float((bits .^. 2147483648 : U32))),g)

def Float.geometries(fuel: Nat, +geometry: U32, +bits: U32, result: ScanResult) -> ScanResult:
	match fuel:
		case 0n: result
		case 1n+rest: Float.geometries(rest,(geometry + 1 : U32),bits,Float.roles(bits,geometry,result))

def Float.signs(+bits: U32, result: ScanResult) -> ScanResult:
	a = Float.geometries(4n,0,bits,result)
	Float.geometries(4n,0,(bits .^. 2147483648 : U32),a)

def Float.mantissas(mantissas: List<&2,U32>, +exponent: U32, result: ScanResult) -> ScanResult:
	match mantissas:
		case Nil{}: result
		case Con{mantissa,rest}: Float.mantissas(rest,exponent,Float.signs((exponent .|. mantissa : U32),result))

def Float.exponents(fuel: Nat, +exponent: U32, result: ScanResult) -> ScanResult:
	match fuel:
		case 0n: result
		case 1n+rest:
			Float.exponents(rest,(exponent + 8388608 : U32),Float.mantissas([0,1,4194304,8388606,8388607],exponent,result))

def Scan() -> ScanResult:
	zero = {ScanResult{Stats{0,0,0,0,0,0,0,0,0,0,0,0},Families{0,0,0,0,0,0,0,0},0,0,None{},None{},None{}} : ScanResult}
	+counterexample = {Sample{7,0.0,1.0,16777217,16777217,16777218} : Sample}
	a = Check(counterexample,0,Sample.boundary(counterexample),zero)
	b = Times.scan(15n,0,Sample{7,F32.neg(1.0e30),1.0,0,0,1},a)
	c = Times.scan(15n,0,Sample{7,1.0e30,F32.neg(1.0),0,0,1},b)
	d = Small.scan(17n,0,c)
	e = Edges.scan(33n,16777200,d)
	f = Huge.scan([2147483632,2147483647,2147483648,2147483649,2147483664,4294967040,4294967167,4294967168,4294967279,4294967294,4294967295],e)
	Float.exponents(256n,0,f)

def Scan.mode(dispatch: Bool) -> ScanResult:
	match dispatch:
		case False{}: Scan()
		case True{}: Scan!()

def Stats.show(stats: Stats) -> String:
	Stats{checks,calls,reuses,raw,unsafe,known,rejected,pos,neg,nfo,nfd,nft} = stats
	"checks=" ++ U32.show(checks) ++ " count_calls=" ++ U32.show(calls) ++ " reuses=" ++ U32.show(reuses) ++
	" raw_boundary_equal=" ++ U32.show(raw) ++ " unsafe_boundary_count_disagreements=" ++ U32.show(unsafe) ++
	" known_limit_mismatches=" ++ U32.show(known) ++ " rejected_generation=" ++ U32.show(rejected) ++
	" positive_reuses=" ++ U32.show(pos) ++ " negative_reuses=" ++ U32.show(neg) ++
	" nonfinite_origin_reuses=" ++ U32.show(nfo) ++ " nonfinite_delta_reuses=" ++ U32.show(nfd) ++
	" nonfinite_time_reuses=" ++ U32.show(nft)

def Families.show(families: Families) -> String:
	Families{a,b,c,d,e,f,g,h} = families
	"small=" ++ U32.show(a) ++ " coordinate_edges=" ++ U32.show(b) ++ " huge=" ++ U32.show(c) ++
	" origin_exponents=" ++ U32.show(d) ++ " delta_exponents=" ++ U32.show(e) ++ " time_exponents=" ++ U32.show(f) ++
	" mixed_exponents=" ++ U32.show(g) ++ " special=" ++ U32.show(h)

def Witness.show(witness: Witness) -> String:
	Witness{Sample{family,+origin,+delta,low,cell,high},kind,+time,+boundary,moving,positive,limit,actual} = witness
	"family=" ++ U32.show(family) ++ " time_kind=" ++ U32.show(kind) ++
	" low=" ++ U32.show(low) ++ " cell=" ++ U32.show(cell) ++ " high=" ++ U32.show(high) ++
	" origin=" ++ F32.show(origin) ++ " origin_bits=" ++ U32.show(F32.bits(origin)) ++
	" delta=" ++ F32.show(delta) ++ " delta_bits=" ++ U32.show(F32.bits(delta)) ++
	" time=" ++ F32.show(time) ++ " time_bits=" ++ U32.show(F32.bits(time)) ++
	" boundary=" ++ F32.show(boundary) ++ " boundary_bits=" ++ U32.show(F32.bits(boundary)) ++
	" moving=" ++ Bool.show(moving) ++ " positive=" ++ Bool.show(positive) ++
	" limit=" ++ U32.show(limit) ++ " actual_count=" ++ U32.show(actual)

def First.show(first: Maybe<&2,Witness>) -> String:
	match first:
		case None{}: "none"
		case Some{witness}: Witness.show(witness)

def Families.valid(families: Families) -> Bool:
	Families{a,b,c,d,e,f,g,h} = families
	U32.is_eq(a,346800) && U32.is_eq(b,673200) && U32.is_eq(c,224400) && U32.is_eq(d,307200) &&
	U32.is_eq(e,307200) && U32.is_eq(f,81920) && U32.is_eq(g,307200) && U32.is_eq(h,31)

def ScanResult.valid(result: ScanResult) -> Bool:
	ScanResult{Stats{checks,calls,reuses,raw,unsafe,known,rejected,pos,neg,nfo,nfd,nft},families,coverage,modes,first_unsafe,first_known,first_rejected} = result
	U32.is_eq(checks,2247951) && U32.is_zero(known) && U32.is_zero(rejected) && (unsafe > 0 : U32) &&
	Families.valid(families) && U32.is_eq(coverage,536870911) && U32.is_eq(modes,524287)

def Finish(valid: Bool) -> IO(Unit):
	match valid:
		case False{}: IO.die(Unit,1,"FAIL guarded mismatch, malformed generation, or missing declared coverage")
		case True{}: IO.print("PASS finite declared samples; no universal proof or performance verdict")

def Print.result(+result: ScanResult) -> IO(Unit):
	ScanResult{stats,families,coverage,modes,first_unsafe,first_known,first_rejected} = result
	do IO<Unit>:
		IO.print(Stats.show(stats))
		IO.print(Families.show(families))
		IO.print("coverage_mask=" ++ U32.show(coverage) ++ " required=536870911 time_modes=" ++ U32.show(modes) ++ " required=524287")
		IO.print("first_unsafe " ++ First.show(first_unsafe))
		IO.print("first_guarded " ++ First.show(first_known))
		IO.print("first_rejected " ++ First.show(first_rejected))
		Finish(ScanResult.valid(result))

def Run(+dispatch: Bool) -> IO(Unit):
	do IO<Unit>:
		IO.print("Boundary-count property imports ../baseline/dda.bend and calls actual Axis.next and Axis.count")
		IO.print("Eligibility moving && low<=cell<high<=16777216 && F32.is_eq(time,boundary); no finite arithmetic guard")
		IO.print("Every Axis.count call has valid bounds and limit 1..16; both modes use the same sequential Scan")
		IO.print("dispatch=" ++ Bool.pick(String,dispatch,"Scan! requested","Scan CPU"))
		Print.result(Scan.mode(dispatch))

def Args(args: List<String>) -> Bool:
	match args:
		case Nil{}: False{}
		case Con{head,rest}: String.eq(head,"--dispatch") || Args(rest)

def main() -> IO(Unit):
	IO.bind(List<String>,Unit,IO.args(),args => Run(Args(args)))
