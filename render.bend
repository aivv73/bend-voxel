import Base
import ./voxel.bend as V

type Projected is Data:
	Projected{cell: V.Cell, direction: V.Direction, px: F32, py: F32, depth: F32, color: U32, id: U32, minx: U32, miny: U32, maxx: U32, maxy: U32}

type Tiles is Data:
	Tile{x: U32, y: U32, size: U32, faces: List<&2, Projected>}
	Split{tl: Tiles, tr: Tiles, bl: Tiles, br: Tiles}

type RenderScene is Data:
	RenderScene{tiles: Tiles, face_count: U32}

type Hit is Data:
	Hit{depth: F32, color: U32, id: U32, cell: Maybe<&2, V.Cell>}

def Projected.of(direction: V.Direction, cell: V.Cell, material: U32) -> Maybe<&2, Projected>:
	match direction:
		case V.PosX{}:
			V.Cell{+x, +y, +z} = cell
			+px = (256 + 20 * (x + 1) - 20 * y : U32)
			+py = (280 + 10 * (x + 1 + y) - 20 * z : U32)
			Some{Projected{V.Cell{x, y, z}, V.PosX{}, U32.to_f32(px), U32.to_f32(py), U32.to_f32((1600 * (x + 1 + y + z) : U32)), (9330748 + z * 197378 : U32), (6 * (x + 8 * y + 64 * z) + 1 : U32), (px - 20 : U32), (py - 20 : U32), px, (py + 10 : U32)}}
		case V.PosY{}:
			V.Cell{+x, +y, +z} = cell
			+px = (256 + 20 * x - 20 * (y + 1) : U32)
			+py = (280 + 10 * (x + y + 1) - 20 * z : U32)
			Some{Projected{V.Cell{x, y, z}, V.PosY{}, U32.to_f32(px), U32.to_f32(py), U32.to_f32((1600 * (x + y + 1 + z) : U32)), (11500614 + z * 197378 : U32), (6 * (x + 8 * y + 64 * z) + 3 : U32), px, (py - 20 : U32), (px + 20 : U32), (py + 10 : U32)}}
		case V.PosZ{}:
			V.Cell{+x, +y, +z} = cell
			+px = (256 + 20 * x - 20 * y : U32)
			+py = (280 + 10 * (x + y) - 20 * (z + 1) : U32)
			Some{Projected{V.Cell{x, y, z}, V.PosZ{}, U32.to_f32(px), U32.to_f32(py), U32.to_f32((1600 * (x + y + z + 1) : U32)), (14134899 + z * 131585 : U32), (6 * (x + 8 * y + 64 * z) + 5 : U32), (px - 20 : U32), py, (px + 20 : U32), (py + 20 : U32)}}
		case _:
			None{}

def Projected.add(value: Maybe<&2, Projected>, rest: List<&2, Projected>) -> List<&2, Projected>:
	match value:
		case None{}:
			rest
		case Some{face}:
			face <> rest

def Projected.list(faces: List<&2, V.Face>) -> List<&2, Projected>:
	match faces:
		case Nil{}:
			Nil{}
		case Con{V.Face{cell, direction, material}, rest}:
			Projected.add(Projected.of(direction, cell, material), Projected.list(rest))

def Projected.overlaps(face: Projected, +x: U32, +y: U32, +size: U32) -> Bool:
	Projected{cell, direction, px, py, depth, color, id, minx, miny, maxx, maxy} = face
	((minx < x + size) && (miny < y + size) && (maxx > x) && (maxy > y) : U32)

def Projected.filter(faces: List<&2, Projected>, +x: U32, +y: U32, +size: U32, found: List<&2, Projected>) -> List<&2, Projected>:
	match faces:
		case Nil{}:
			found
		case Con{+face, rest}:
			Projected.filter(rest, x, y, size, Projected.add(Bool.pick(Maybe<&2, Projected>, Projected.overlaps(face, x, y, size), Some{face}, None{}), found))

def Tiles.build(+depth: Nat, +faces: List<&2, Projected>, +x: U32, +y: U32, +size: U32) -> Tiles:
	match depth:
		case 0n:
			Tile{x, y, size, faces}
		case 1n+rest:
			+h = (size / 2 : U32)
			Split{Tiles.build(rest, Projected.filter(faces, x, y, h, Nil{}), x, y, h),
				Tiles.build(rest, Projected.filter(faces, (x + h : U32), y, h, Nil{}), (x + h : U32), y, h),
				Tiles.build(rest, Projected.filter(faces, x, (y + h : U32), h, Nil{}), x, (y + h : U32), h),
				Tiles.build(rest, Projected.filter(faces, (x + h : U32), (y + h : U32), h, Nil{}), (x + h : U32), (y + h : U32), h)}

def RenderScene.build(surface: V.Surface, tile_depth: Nat) -> RenderScene:
	V.Surface{+faces} = surface
	RenderScene{Tiles.build(tile_depth, Projected.list(faces), 0, 0, 512), V.Surface.count.faces(faces, 0)}

def Hit.uv(direction: V.Direction, +dx: F32, +dy: F32) -> F32 & F32:
	match direction:
		case V.PosX{}:
			((0.0 - 40.0 * dx : F32), (0.0 - 40.0 * dy - 20.0 * dx : F32))
		case V.PosY{}:
			((40.0 * dx : F32), (20.0 * dx - 40.0 * dy : F32))
		case _:
			((20.0 * dx + 40.0 * dy : F32), (40.0 * dy - 20.0 * dx : F32))

def Hit.accept(closer: Bool, cell: V.Cell, depth: F32, color: U32, id: U32, old: Hit) -> Hit:
	match closer:
		case True{}:
			Hit{depth, color, id, Some{cell}}
		case False{}:
			old

def Hit.color(edge: Bool, color: U32) -> U32:
	match edge:
		case True{}:
			5258540
		case False{}:
			color

def Hit.covered(covered: Bool, +u: F32, +v: F32, cell: V.Cell, +depth: F32, color: U32, +id: U32, old: Hit) -> Hit:
	match covered:
		case False{}:
			old
		case True{}:
			Hit{+previous, old_color, +old_id, old_cell} = old
			+d = (depth + u + v : F32)
			Hit.accept(((d > previous : F32) || ((F32.is_eq(d, previous)) && (id < old_id : U32))), cell, d,
				Hit.color(((u < 36.0) || (v < 36.0) || (u > 1564.0) || (v > 1564.0) : F32), color), id, Hit{previous, old_color, old_id, old_cell})

def Hit.local(uv: F32 & F32, cell: V.Cell, depth: F32, color: U32, id: U32, old: Hit) -> Hit:
	(+u, +v) = uv
	Hit.covered(((u >= 0.0) && (u < 1600.0) && (v >= 0.0) && (v < 1600.0) : F32), u, v, cell, depth, color, id, old)

def Hit.face(face: Projected, +x: U32, +y: U32, old: Hit) -> Hit:
	Projected{cell, direction, px, py, depth, color, id, minx, miny, maxx, maxy} = face
	Hit.local(Hit.uv(direction, (U32.to_f32((2 * x + 1 : U32)) - 2.0 * px : F32),
		(U32.to_f32((2 * y + 1 : U32)) - 2.0 * py : F32)), cell, depth, color, id, old)

def Background.color(floor: Bool, +x: U32, +y: U32) -> U32:
	match floor:
		case False{}:
			(1054752 + (y / 32) * 65793 : U32)
		case True{}:
			Hit.color((((x + 2 * y) % 80 < 2) || ((x + 1024 - 2 * y) % 80 < 2) : U32), 1779504)

def Hit.background(+x: U32, +y: U32) -> Hit:
	Hit{0.0, Background.color((y > 360 : U32), x, y), 4294967295, None{}}

def Pixel.hit(faces: List<&2, Projected>, +x: U32, +y: U32, hit: Hit) -> Hit:
	match faces:
		case Nil{}:
			hit
		case Con{face, rest}:
			Pixel.hit(rest, x, y, Hit.face(face, x, y, hit))

def Pixel.image(hit: Hit) -> Image:
	Hit{depth, color, id, cell} = hit
	Pix{color}

def Tile.image(+depth: Nat, +faces: List<&2, Projected>, +x: U32, +y: U32, +size: U32) -> Image:
	match depth:
		case 0n:
			Pixel.image(Pixel.hit(faces, x, y, Hit.background(x, y)))
		case 1n+rest:
			+h = (size / 2 : U32)
			Qua{Tile.image(rest, faces, x, y, h), Tile.image(rest, faces, (x + h : U32), y, h),
				Tile.image(rest, faces, x, (y + h : U32), h), Tile.image(rest, faces, (x + h : U32), (y + h : U32), h)}

def Tiles.image.seq(tiles: Tiles) -> Image:
	match tiles:
		case Tile{+x, +y, +size, faces}:
			Tile.image(U32.log2(size), faces, x, y, size)
		case Split{tl, tr, bl, br}:
			Qua{Tiles.image.seq(tl), Tiles.image.seq(tr), Tiles.image.seq(bl), Tiles.image.seq(br)}

def Tiles.image(+fork_depth: Nat, tiles: Tiles) -> Image:
	match fork_depth:
		case 0n:
			Tiles.image.seq(tiles)
		case 1n+rest:
			match tiles:
				case Tile{+x, +y, +size, faces}:
					Tile.image(U32.log2(size), faces, x, y, size)
				case Split{tl, tr, bl, br}:
					a b c d = Tiles.image(rest, tl) Tiles.image(rest, tr) Tiles.image(rest, bl) Tiles.image(rest, br)
					Qua{a, b, c, d}

def RenderScene.image(+scene: RenderScene, fork_depth: Nat) -> Image & RenderScene:
	RenderScene{tiles, face_count} = scene
	(Tiles.image!(fork_depth, tiles), scene)

def Hit.cell(hit: Hit) -> Maybe<&2, V.Cell>:
	Hit{depth, color, id, cell} = hit
	cell

def Tiles.pick(tiles: Tiles, +x: U32, +y: U32, +size: U32, right: Bool, bottom: Bool) -> Maybe<&2, V.Cell>:
	match tiles:
		case Tile{tx, ty, tile_size, faces}:
			Hit.cell(Pixel.hit(faces, x, y, Hit.background(x, y)))
		case Split{tl, tr, bl, br}:
			match right bottom:
				case False{} False{}:
					Tiles.pick(tl, x, y, (size / 2 : U32), (x % (size / 2) >= size / 4 : U32), (y % (size / 2) >= size / 4 : U32))
				case True{} False{}:
					Tiles.pick(tr, x, y, (size / 2 : U32), (x % (size / 2) >= size / 4 : U32), (y % (size / 2) >= size / 4 : U32))
				case False{} True{}:
					Tiles.pick(bl, x, y, (size / 2 : U32), (x % (size / 2) >= size / 4 : U32), (y % (size / 2) >= size / 4 : U32))
				case True{} True{}:
					Tiles.pick(br, x, y, (size / 2 : U32), (x % (size / 2) >= size / 4 : U32), (y % (size / 2) >= size / 4 : U32))

def RenderScene.pick(scene: RenderScene, +x: U32, +y: U32) -> Maybe<&2, V.Cell>:
	RenderScene{tiles, face_count} = scene
	Tiles.pick(tiles, x, y, 512, (x >= 256 : U32), (y >= 256 : U32))
