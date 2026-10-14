import Base

type Counts is Data:
	Counts{samples: U32, estimates: U32, raw_mismatches: U32, estimate_mismatches: U32}

def Bits.float(bits: U32) -> F32:
	match bits:
		case U32{word}: F32{word}

def Estimate.before(+events: F32, +limit: U32) -> U32:
	U32.min(limit,F32.to_u32(F32.floor(F32.clamp(events,0.0,U32.to_f32(limit)))))

def Estimate.after(+events: F32, +limit: U32) -> U32:
	U32.min(limit,F32.to_u32(F32.clamp(events,0.0,U32.to_f32(limit))))

def Limits.edges() -> List<&2,U32>:
	[513,1024,65535,65536,16777215,16777216,16777217,2147483647,2147483648,4294967040,4294967167,4294967168,4294967294,4294967295]

def Limits.range(fuel: Nat, +events: F32, +limit: U32, counts: Counts) -> Counts:
	match fuel:
		case 0n: counts
		case 1n+rest:
			Counts{samples,checks,raw,mismatches} = counts
			bad = Bool.to_u32(U32.is_ne(Estimate.before(events,limit),Estimate.after(events,limit)))
			Limits.range(rest,events,(limit + 1 : U32),Counts{samples,(checks + 1 : U32),raw,(mismatches + bad : U32)})

def Limits.list(limits: List<&2,U32>, +events: F32, counts: Counts) -> Counts:
	match limits:
		case Nil{}: counts
		case Con{+limit,rest}:
			Counts{samples,checks,raw,mismatches} = counts
			bad = Bool.to_u32(U32.is_ne(Estimate.before(events,limit),Estimate.after(events,limit)))
			Limits.list(rest,events,Counts{samples,(checks + 1 : U32),raw,(mismatches + bad : U32)})

def Sample.check(bits: U32, counts: Counts) -> Counts:
	Counts{samples,estimates,raw_mismatches,estimate_mismatches} = counts
	+events = Bits.float(bits)
	bad = Bool.to_u32(U32.is_ne(F32.to_u32(F32.floor(events)),F32.to_u32(events)))
	Limits.list(Limits.edges(),events,Limits.range(513n,events,0,Counts{(samples + 1 : U32),estimates,(raw_mismatches + bad : U32),estimate_mismatches}))

def Sample.signs(+bits: U32, counts: Counts) -> Counts:
	Sample.check((bits .^. 2147483648 : U32),Sample.check(bits,counts))

def Window.scan(fuel: Nat, +bits: U32, counts: Counts) -> Counts:
	match fuel:
		case 0n: counts
		case 1n+rest:
			Window.scan(rest,(bits + 1 : U32),Sample.signs(bits,counts))

def Window.center(+bits: U32, counts: Counts) -> Counts:
	Window.scan(9n,(U32.max(bits,4) - 4 : U32),counts)

def Integers.scan(fuel: Nat, +integer: U32, counts: Counts) -> Counts:
	match fuel:
		case 0n: counts
		case 1n+rest:
			Integers.scan(rest,(integer + 1 : U32),Window.center(F32.bits(U32.to_f32(integer)),counts))

def Powers.scan(fuel: Nat, +bits: U32, counts: Counts) -> Counts:
	match fuel:
		case 0n: counts
		case 1n+rest:
			Powers.scan(rest,(bits + 8388608 : U32),Window.center(bits,counts))

def Mantissas.scan(fuel: Nat, +exponent: U32, +mantissa: U32, counts: Counts) -> Counts:
	match fuel:
		case 0n: Sample.signs((exponent .|. 8388607 : U32),counts)
		case 1n+rest:
			Mantissas.scan(rest,exponent,(mantissa + 524288 : U32),Sample.signs((exponent .|. mantissa : U32),counts))

def Exponents.scan(fuel: Nat, +bits: U32, counts: Counts) -> Counts:
	match fuel:
		case 0n: counts
		case 1n+rest:
			Exponents.scan(rest,(bits + 8388608 : U32),Mantissas.scan(16n,bits,0,counts))

def Edges.scan(limits: List<&2,U32>, counts: Counts) -> Counts:
	match limits:
		case Nil{}: counts
		case Con{limit,rest}:
			Edges.scan(rest,Window.center(F32.bits(U32.to_f32(limit)),counts))

def Special.scan(bits: List<&2,U32>, counts: Counts) -> Counts:
	match bits:
		case Nil{}: counts
		case Con{word,rest}:
			Special.scan(rest,Window.center(word,counts))

def Binade.check(bits: U32, counts: Counts) -> Counts:
	Counts{samples,estimates,raw_mismatches,estimate_mismatches} = counts
	+events = Bits.float(bits)
	bad = Bool.to_u32(U32.is_ne(F32.to_u32(F32.floor(events)),F32.to_u32(events)))
	Limits.list([0,1,255,256,257,511,512],events,Counts{(samples + 1 : U32),estimates,(raw_mismatches + bad : U32),estimate_mismatches})

def Binade.scan(fuel: Nat, +bits: U32, counts: Counts) -> Counts:
	match fuel:
		case 0n: counts
		case 1n+rest:
			Binade.scan(rest,(bits + 1 : U32),Binade.check((bits .^. 2147483648 : U32),Binade.check(bits,counts)))

def Counts.show(counts: Counts) -> String:
	Counts{+samples,estimates,raw_mismatches,estimate_mismatches} = counts
	"samples=" ++ U32.show(samples) ++ " raw_checks=" ++ U32.show(samples) ++
	" estimate_checks=" ++ U32.show(estimates) ++ " raw_mismatches=" ++ U32.show(raw_mismatches) ++
	" estimate_mismatches=" ++ U32.show(estimate_mismatches)

def Counts.valid(expected_samples: U32, expected_estimates: U32, counts: Counts) -> Bool:
	Counts{samples,estimates,raw_mismatches,estimate_mismatches} = counts
	U32.is_eq(samples,expected_samples) && U32.is_eq(estimates,expected_estimates) &&
	U32.is_zero(raw_mismatches) && U32.is_zero(estimate_mismatches)

def Finish(valid: Bool) -> IO(Unit):
	match valid:
		case False{}: IO.die(Unit,1,"FAIL: conversion mismatch or incomplete sweep")
		case True{}: IO.print("PASS: zero mismatches in the declared finite sweep; this is not a universal proof")

def main() -> IO(Unit):
	do IO<Unit>:
		IO.print("Conversion property: to_u32(floor(events)) equals to_u32(events)")
		IO.print("Estimate property: both expressions retain F32.clamp(events,0,F32(limit)) and U32.min(limit,...)")
		IO.print("Every boundary/exponent sample checks all 513 limits 0..512 and the 14 Limits.edges values")
		IO.print("Integer centers 0..512 and power centers 2^0..2^32 use 9 consecutive F32 bit patterns at center +/-4; zero uses bits 0..8")
		IO.print("Every bit pattern also checks its sign-bit mirror; windows may extend outside [0,512]")
		IO.print("All 256 exponent fields check mantissas k*2^19 for k=0..15 and 2^23-1")
		IO.print("Extra windows cover F32(limit) for all edge limits and the subnormal/normal boundary, infinity, quiet-NaN boundary, and largest NaN payload")
		IO.print("Counts include repeated patterns across families; this does not exhaust all F32 bit patterns or all U32 limits")
		a : Counts = Integers.scan(513n,0,Counts{0,0,0,0})
		b : Counts = Powers.scan(33n,1065353216,a)
		c : Counts = Exponents.scan(256n,0,b)
		d : Counts = Edges.scan(Limits.edges(),c)
		+result : Counts = Special.scan([8388608,2139095040,2143289344,2147483643],d)
		IO.print("boundary/exponent " ++ Counts.show(result))
		IO.print("Exhaustive binade: every F32 bit pattern from 0x43800000 through 0x44000000 inclusive, values [256,512], and its sign mirror")
		IO.print("Each exhaustive binade sample checks limits [0,1,255,256,257,511,512]; other limits are covered by the boundary/exponent sweep")
		+binade : Counts = Binade.scan(8388609n,1132462080,Counts{0,0,0,0})
		IO.print("exhaustive binade " ++ Counts.show(binade))
		Finish(Counts.valid(18856,9937112,result) && Counts.valid(16777218,117440526,binade))
