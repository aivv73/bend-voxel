import Base

type Cell is Data:
	Cell{x: U32, y: U32, z: U32}

type Brush is Data:
	Sphere{center: Cell, radius: U32}

type Body is Type:
	Body{side: U32, cells: Array<U32>}

type Snapshot is Data:
	Leaf{material: U32}
	Node{left: Snapshot, right: Snapshot}

type Direction is Data:
	NegX{}
	PosX{}
	NegY{}
	PosY{}
	NegZ{}
	PosZ{}

type Face is Data:
	Face{cell: Cell, direction: Direction, material: U32}

type Surface is Data:
	Surface{faces: List<&2, Face>}

def Cell.erase(material: U32, hit: Bool) -> U32:
	match hit:
		case True{}:
			0
		case False{}:
			material

def Face.exposed(solid: Bool, neighbor: Bool) -> Bool:
	Bool.and(solid, Bool.not(neighbor))

def Body.filled(+depth: Nat, material: U32) -> Body:
	Body{U32.pow(2, depth), Array.new(U32, Nat.mul(3n, depth), material)}

def Body.solid(depth: Nat) -> Body:
	Body.filled(depth, 1)

def Body.empty(depth: Nat) -> Body:
	Body.filled(depth, 0)

def Body.index(side: U32, cell: Cell) -> U32:
	Cell{x, y, z} = cell
	+xside = side
	(x + xside * y + xside * xside * z : U32)

def Cell.at(+side: U32, +index: U32) -> Cell:
	Cell{(index % side : U32), ((index / side) % side : U32), (index / (side * side) : U32)}

def Cell.inside(+side: U32, cell: Cell) -> Bool:
	Cell{x, y, z} = cell
	((x < side) && (y < side) && (z < side) : U32)

def Body.write.valid(inside: Bool, body: Body, cell: Cell, material: U32) -> Body:
	match inside:
		case False{}:
			body
		case True{}:
			Body{+side, cells} = body
			Body{side, Array.set(U32, cells, Body.index(side, cell), material)}

def Body.write(body: Body, +cell: Cell, material: U32) -> Body:
	Body{+side, cells} = body
	Body.write.valid(Cell.inside(side, cell), Body{side, cells}, cell, material)

def Distance.choose(ordered: Bool, a: U32, b: U32) -> U32:
	match ordered:
		case True{}:
			(a - b : U32)
		case False{}:
			(b - a : U32)

def Distance.axis(+a: U32, +b: U32) -> U32:
	Distance.choose((a >= b : U32), a, b)

def Brush.hits(brush: Brush, cell: Cell) -> Bool:
	Sphere{Cell{cx, cy, cz}, +r} = brush
	Cell{x, y, z} = cell
	+dx = Distance.axis(x, cx)
	+dy = Distance.axis(y, cy)
	+dz = Distance.axis(z, cz)
	(((dx <= r) && (dy <= r) && (dz <= r)) && (dx * dx + dy * dy + dz * dz <= r * r) : U32)

def Body.destroy.leaf(hit: Bool, material: U32) -> Array<U32>:
	ALeaf{Cell.erase(material, hit)}

def Body.destroy.tree(cells: Array<U32>, +side: U32, +brush: Brush, +base: U32, +span: U32) -> Array<U32>:
	match cells:
		case ALeaf{material}:
			Body.destroy.leaf(Brush.hits(brush, Cell.at(side, base)), material)
		case ANode{left, right}:
			+half = (span / 2 : U32)
			ANode{Body.destroy.tree(left, side, brush, base, half),
				Body.destroy.tree(right, side, brush, (base + half : U32), half)}

def Body.destroy.valid(valid: Bool, body: Body, brush: Brush) -> Body:
	match valid:
		case False{}:
			body
		case True{}:
			Body{+side, cells} = body
			Body{side, Body.destroy.tree(cells, side, brush, 0, (side * side * side : U32))}

def Body.destroy(body: Body, brush: Brush) -> Body:
	Body{+side, cells} = body
	Sphere{+center, +radius} = brush
	Body.destroy.valid((Cell.inside(side, center) && (radius <= side : U32)), Body{side, cells}, Sphere{center, radius})

def Snapshot.join(a: Array<U32> & Snapshot, b: Array<U32> & Snapshot) -> Array<U32> & Snapshot:
	(left, lcopy) = a
	(right, rcopy) = b
	(ANode{left, right}, Node{lcopy, rcopy})

def Snapshot.of(cells: Array<U32>) -> Array<U32> & Snapshot:
	match cells:
		case ALeaf{+material}:
			(ALeaf{material}, Leaf{material})
		case ANode{left, right}:
			Snapshot.join(Snapshot.of(left), Snapshot.of(right))

def Snapshot.get(cells: Snapshot, +index: U32, +span: U32, leftward: Bool) -> U32:
	match cells:
		case Leaf{material}:
			material
		case Node{left, right}:
			match leftward:
				case True{}:
					Snapshot.get(left, index, (span / 2 : U32), (index < span / 4 : U32))
				case False{}:
					+j = (index - span / 2 : U32)
					Snapshot.get(right, j, (span / 2 : U32), (j < span / 4 : U32))

def Snapshot.read.valid(inside: Bool, cells: Snapshot, +side: U32, cell: Cell) -> U32:
	match inside:
		case False{}:
			0
		case True{}:
			+i = Body.index(side, cell)
			+n = (side * side * side : U32)
			Snapshot.get(cells, i, n, (i < n / 2 : U32))

def Snapshot.read(cells: Snapshot, +side: U32, +cell: Cell) -> U32:
	Snapshot.read.valid(Cell.inside(side, cell), cells, side, cell)

def Face.add(exposed: Bool, face: Face, faces: List<&2, Face>) -> List<&2, Face>:
	match exposed:
		case True{}:
			face <> faces
		case False{}:
			faces

def Surface.cell(material: U32, +snapshot: Snapshot, +side: U32, +cell: Cell, faces: List<&2, Face>) -> List<&2, Face>:
	match material:
		case 0:
			faces
		case +m:
			Cell{+x, +y, +z} = cell
			faces = Face.add(Face.exposed(True{}, U32.is_ne(Snapshot.read(snapshot, side, Cell{(x - 1 : U32), y, z}), 0)), Face{cell, NegX{}, m}, faces)
			faces = Face.add(Face.exposed(True{}, U32.is_ne(Snapshot.read(snapshot, side, Cell{(x + 1 : U32), y, z}), 0)), Face{cell, PosX{}, m}, faces)
			faces = Face.add(Face.exposed(True{}, U32.is_ne(Snapshot.read(snapshot, side, Cell{x, (y - 1 : U32), z}), 0)), Face{cell, NegY{}, m}, faces)
			faces = Face.add(Face.exposed(True{}, U32.is_ne(Snapshot.read(snapshot, side, Cell{x, (y + 1 : U32), z}), 0)), Face{cell, PosY{}, m}, faces)
			faces = Face.add(Face.exposed(True{}, U32.is_ne(Snapshot.read(snapshot, side, Cell{x, y, (z - 1 : U32)}), 0)), Face{cell, NegZ{}, m}, faces)
			Face.add(Face.exposed(True{}, U32.is_ne(Snapshot.read(snapshot, side, Cell{x, y, (z + 1 : U32)}), 0)), Face{cell, PosZ{}, m}, faces)

def Surface.scan(fuel: Nat, +snapshot: Snapshot, +side: U32, +index: U32, faces: List<&2, Face>) -> List<&2, Face>:
	match fuel:
		case 0n:
			faces
		case 1n+rest:
			+cell = Cell.at(side, index)
			Surface.scan(rest, snapshot, side, (index + 1 : U32),
				Surface.cell(Snapshot.read(snapshot, side, cell), snapshot, side, cell, faces))

def Surface.finish(+side: U32, result: Array<U32> & Snapshot) -> Body & Surface:
	(cells, snapshot) = result
	(Body{side, cells}, Surface{Surface.scan(U32.to_nat((side * side * side : U32)), snapshot, side, 0, Nil{})})

def Surface.build(body: Body) -> Body & Surface:
	Body{+side, cells} = body
	Surface.finish(side, Snapshot.of(cells))

def Direction.show(direction: Direction) -> String:
	match direction:
		case NegX{}:
			"-x"
		case PosX{}:
			"+x"
		case NegY{}:
			"-y"
		case PosY{}:
			"+y"
		case NegZ{}:
			"-z"
		case PosZ{}:
			"+z"

def Cell.show(cell: Cell) -> String:
	Cell{x, y, z} = cell
	U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z)

def Surface.count.faces(faces: List<&2, Face>, n: U32) -> U32:
	match faces:
		case Nil{}:
			n
		case Con{face, rest}:
			Surface.count.faces(rest, (n + 1 : U32))

def Surface.count(surface: Surface) -> U32:
	Surface{faces} = surface
	Surface.count.faces(faces, 0)
