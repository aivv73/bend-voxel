import Base
import ./ui_capture.bend as C

def Check.require(ok: Bool, message: String) -> IO(Unit):
	match ok:
		case True{}:
			IO.pure(Unit, Unit{})
		case False{}:
			IO.die(Unit, 1, message)

def Image.equal(a: Image, b: Image) -> Bool:
	match a b:
		case Pix{x} Pix{y}:
			U32.is_eq(x, y)
		case Qua{al, ar, ab, ac} Qua{bl, br, bb, bc}:
			Image.equal(al, bl) && Image.equal(ar, br) && Image.equal(ab, bb) && Image.equal(ac, bc)
		case _ _:
			False{}

def Image.uniform(image: Image, +color: U32) -> Bool:
	match image:
		case Pix{actual}:
			U32.is_eq(actual, color)
		case Qua{tl, tr, bl, br}:
			Image.uniform(tl, color) && Image.uniform(tr, color) && Image.uniform(bl, color) && Image.uniform(br, color)

def Image.at(+depth: Nat, +x: U32, +y: U32, +side: U32, image: Image) -> U32:
	match depth image:
		case _ Pix{color}:
			color
		case 0n _:
			4294967295
		case 1n+rest Qua{tl, tr, bl, br}:
			+half = (side / 2 : U32)
			Image.at(rest, (x % half : U32), (y % half : U32), half,
				Bool.pick(Image, (y < half : U32), Bool.pick(Image, (x < half : U32), tl, tr), Bool.pick(Image, (x < half : U32), bl, br)))

def Check.tile(converted: Array<U32> & Image, expected: Image) -> IO(Unit):
	(pixels, image) = converted
	Check.require(Image.equal(image, expected), "Row-major pixels mapped to the wrong quadrants")

def Check.mapping() -> IO(Unit):
	pixels = {ANode{
		ANode{ANode{ALeaf{1}, ALeaf{2}}, ANode{ALeaf{3}, ALeaf{4}}},
		ANode{ANode{ALeaf{5}, ALeaf{6}}, ANode{ALeaf{7}, ALeaf{8}}}} : Array<U32>}
	pixels = {ANode{pixels, ANode{
		ANode{ANode{ALeaf{9}, ALeaf{10}}, ANode{ALeaf{11}, ALeaf{12}}},
		ANode{ANode{ALeaf{13}, ALeaf{14}}, ANode{ALeaf{15}, ALeaf{16}}}}} : Array<U32>}
	do IO<Unit>:
		Check.tile(C.Capture.tile(2n, 4, 0, 0, 4, pixels),
			Qua{Qua{Pix{1}, Pix{2}, Pix{5}, Pix{6}}, Qua{Pix{3}, Pix{4}, Pix{7}, Pix{8}},
				Qua{Pix{9}, Pix{10}, Pix{13}, Pix{14}}, Qua{Pix{11}, Pix{12}, Pix{15}, Pix{16}}})
		Check.tile(C.Capture.tile(0n, 1, 0, 0, 1, ALeaf{16777215}), Pix{16777215})

def Check.uniform(result: Result<&2, &2, String, Image>) -> IO(Unit):
	match result:
		case Fail{message}:
			IO.die(Unit, 1, message)
		case Done{image}:
			Check.require(Image.uniform(image, 1193046), "Full-frame capture lost RGB precision")

def Check.markers(result: Result<&2, &2, String, Image>) -> IO(Unit):
	match result:
		case Fail{message}:
			IO.die(Unit, 1, message)
		case Done{+image}:
			Check.require(
				U32.is_eq(Image.at(9n, 0, 0, 512, image), 16711680) &&
				U32.is_eq(Image.at(9n, 511, 0, 512, image), 65280) &&
				U32.is_eq(Image.at(9n, 0, 511, 512, image), 255) &&
				U32.is_eq(Image.at(9n, 511, 511, 512, image), 16777215) &&
				U32.is_eq(Image.at(9n, 256, 255, 512, image), 1193046) &&
				U32.is_eq(Image.at(9n, 255, 256, 512, image), 6636321) &&
				U32.is_eq(Image.at(9n, 255, 255, 512, image), 0), "Full-frame capture coordinates differ")

def Check.frame() -> IO(Unit):
	pixels = [0 : U32^18n]
	pixels[0] <- 16711680
	pixels[511] <- 65280
	pixels[261632] <- 255
	pixels[262143] <- 16777215
	pixels[130816] <- 1193046
	pixels[131327] <- 6636321
	do IO<Unit>:
		Check.markers(C.Capture.image(Capture{512, 512, pixels}))
		Check.uniform(C.Capture.image(Capture{512, 512, [1193046 : U32^18n]}))

def Check.rejected(result: Result<&2, &2, String, Image>, expected: String) -> IO(Unit):
	match result:
		case Done{image}:
			IO.die(Unit, 1, "Malformed capture was accepted")
		case Fail{message}:
			Check.require(String.eq(message, expected), "Malformed capture failed at the wrong boundary")

def main() -> IO(Unit):
	do IO<Unit>:
		Check.mapping()
		Check.frame()
		Check.rejected(C.Capture.image(Capture{513, 512, ALeaf{0}}), "UI capture: expected a 512x512 client")
		Check.rejected(C.Capture.image(Capture{512, 511, ALeaf{0}}), "UI capture: expected a 512x512 client")
		Check.rejected(C.Capture.image(Capture{512, 512, [0 : U32^17n]}), "UI capture: expected exactly 262144 RGB pixels")
		Check.rejected(C.Capture.image(Capture{512, 512, [0 : U32^19n]}), "UI capture: expected exactly 262144 RGB pixels")
		IO.print("PASS capture mapping, RGB precision, full-frame coordinates, dimensions, and capacity")
