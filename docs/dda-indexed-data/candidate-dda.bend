import Base
import ../../voxel.bend as V
import ../../render.bend as R
import ../../lighting.bend as L
import ../../material.bend as M

type Tree is Data:
	Solid{material: U32}
	Branch{left: Tree, right: Tree}

type Grid is Data:
	Grid{side: U32, cells: Index}

type Row is Data:
	RowSolid{material: U32}
	RowSplit{}
	RowLink{page: Nat}
	RowPad{}

type Table is Data:
	Directory{cut: Nat, left: Table, right: Table}
	Page{
		r00: Row, r01: Row, r02: Row, r03: Row,
		r04: Row, r05: Row, r06: Row, r07: Row,
		r08: Row, r09: Row, r10: Row, r11: Row,
		r12: Row, r13: Row, r14: Row, r15: Row,
		r16: Row, r17: Row, r18: Row, r19: Row,
		r20: Row, r21: Row, r22: Row, r23: Row,
		r24: Row, r25: Row, r26: Row, r27: Row,
		r28: Row, r29: Row, r30: Row
	}

type Index is Data:
	Index{height: Nat, page_count: Nat, table: Table}

type Space is Data:
	Space{axis: Split, leftward: Bool, cell: V.Cell, span: V.Cell, low: V.Cell}

type PageResult is Data:
	Finished{region: Region}
	Resume{page: Nat, space: Space}
	Invalid{}

type Region is Data:
	Region{material: U32, low: V.Cell, high: V.Cell}

type Advance is Data:
	Advance{cell: U32, previous: U32, crosses: Bool}

type Split is Data:
	SplitX{}
	SplitY{}
	SplitZ{}

type Sides is Data:
	Sides{nx: U32, px: U32, ny: U32, py: U32, nz: U32, pz: U32}

type Palette is Data:
	Palette{foundation: Sides, concrete: Sides, frame: Sides, machinery: Sides, plaster: Sides}

def Sides.cached(sides: L.Sides) -> Sides:
	L.Sides{nx,px,ny,py,nz,pz} = sides
	Sides{L.Ramp.color(nx,9),L.Ramp.color(px,9),L.Ramp.color(ny,9),L.Ramp.color(py,9),L.Ramp.color(nz,9),L.Ramp.color(pz,9)}

def Sides.color(sides: Sides, direction: V.Direction) -> U32:
	Sides{nx,px,ny,py,nz,pz} = sides
	match direction:
		case V.NegX{}: nx
		case V.PosX{}: px
		case V.NegY{}: ny
		case V.PosY{}: py
		case V.NegZ{}: nz
		case V.PosZ{}: pz

def Palette.build() -> Palette:
	Palette{Sides.cached(L.Sides.build(M.Foundation{})),Sides.cached(L.Sides.build(M.Concrete{})),Sides.cached(L.Sides.build(M.Frame{})),
		Sides.cached(L.Sides.build(M.Machinery{})),Sides.cached(L.Sides.build(M.Plaster{}))}

def Palette.color(material: U32, palette: Palette, direction: V.Direction) -> U32:
	match material:
		case 1:
			Palette{foundation,concrete,frame,machinery,plaster} = palette
			Sides.color(foundation,direction)
		case 2:
			Palette{foundation,concrete,frame,machinery,plaster} = palette
			Sides.color(concrete,direction)
		case 3:
			Palette{foundation,concrete,frame,machinery,plaster} = palette
			Sides.color(frame,direction)
		case 4:
			Palette{foundation,concrete,frame,machinery,plaster} = palette
			Sides.color(machinery,direction)
		case 5:
			Palette{foundation,concrete,frame,machinery,plaster} = palette
			Sides.color(plaster,direction)
		case _: 16711935

type Slab is Data:
	Slab{enter: F32, leave: F32}

type Crossing is Data:
	Crossing{depth: F32, cell: V.Cell, previous: V.Cell, direction: V.Direction}

type SurfaceHit is Data:
	SurfaceHit{depth: F32, cell: V.Cell, direction: V.Direction, material: U32}

def Tree.join(left: Tree, right: Tree) -> Tree:
	match left right:
		case Solid{+a} Solid{+b}:
			Bool.pick(Tree, U32.is_eq(a,b), Solid{a}, Branch{Solid{a},Solid{b}})
		case a b: Branch{a,b}

def Tree.left(tree: Tree) -> Tree:
	match tree:
		case Solid{material}: Solid{material}
		case Branch{left,right}: left

def Tree.right(tree: Tree) -> Tree:
	match tree:
		case Solid{material}: Solid{material}
		case Branch{left,right}: right

def Region.overlaps(a: V.Cuboid, b: V.Cuboid) -> Bool:
	V.Cuboid{V.Cell{x,y,z},V.Cell{hx,hy,hz},m} = a
	V.Cuboid{V.Cell{bx,by,bz},V.Cell{bhx,bhy,bhz},bm} = b
	((x < bhx) && (hx > bx) && (y < bhy) && (hy > by) && (z < bhz) && (hz > bz) : U32)

def Region.covers(a: V.Cuboid, b: V.Cuboid) -> Bool:
	V.Cuboid{V.Cell{x,y,z},V.Cell{hx,hy,hz},m} = a
	V.Cuboid{V.Cell{bx,by,bz},V.Cell{bhx,bhy,bhz},bm} = b
	((x <= bx) && (hx >= bhx) && (y <= by) && (hy >= bhy) && (z <= bz) && (hz >= bhz) : U32)

def Tree.paint(+fuel: Nat, overlaps: Bool, covers: Bool, +box: V.Cuboid, +region: V.Cuboid, +axis: U32, +tree: Tree) -> Tree:
	match fuel overlaps covers:
		case _ False{} _: tree
		case _ True{} True{}:
			V.Cuboid{low,high,material} = box
			Solid{material}
		case 0n _ _: tree
		case 1n+rest True{} False{}:
			+low = V.Cuboid.half(region,axis,True{})
			+high = V.Cuboid.half(region,axis,False{})
			Tree.join(Tree.paint(rest,Region.overlaps(box,low),Region.covers(box,low),box,low,((axis + 1) % 3 : U32),Tree.left(tree)),
				Tree.paint(rest,Region.overlaps(box,high),Region.covers(box,high),box,high,((axis + 1) % 3 : U32),Tree.right(tree)))

def Grid.extent(boxes: List<&2,V.Cuboid>, side: U32) -> U32:
	match boxes:
		case Nil{}: side
		case V.Cuboid{low,V.Cell{x,y,z},material} <> rest:
			Grid.extent(rest,U32.max(side,U32.max(x,U32.max(y,z))))

def Grid.paint(boxes: List<&2,V.Cuboid>, +depth: Nat, +side: U32, tree: Tree) -> Tree:
	match boxes:
		case Nil{}: tree
		case +box <> rest:
			+region = {V.Cuboid{V.Cell{0,0,0},V.Cell{side,side,side},0} : V.Cuboid}
			Grid.paint(rest,depth,side,Tree.paint(Nat.mul(3n,depth),Region.overlaps(box,region),Region.covers(box,region),box,region,0,tree))

def Tree.dense(+fuel: Nat, +snapshot: V.Snapshot, +side: U32, +region: V.Cuboid, +axis: U32) -> Tree:
	match fuel:
		case 0n:
			V.Cuboid{cell,high,m} = region
			Solid{V.Snapshot.read(snapshot,side,cell)}
		case 1n+rest:
			Tree.join(Tree.dense(rest,snapshot,side,V.Cuboid.half(region,axis,True{}),((axis + 1) % 3 : U32)),
				Tree.dense(rest,snapshot,side,V.Cuboid.half(region,axis,False{}),((axis + 1) % 3 : U32)))

def Tree.height(tree: Tree) -> Nat:
	match tree:
		case Solid{material}: 0n
		case Branch{left,right}: 1n+Nat.max(Tree.height(left),Tree.height(right))

def Pack.page_depth() -> Nat:
	4n

def Pack.depth() -> Nat:
	Nat.min(4n,Nat.max(1n,Pack.page_depth()))

def Pack.pads(depth: Nat) -> List<&2,Row>:
	match depth:
		case 0n: [RowPad{}]
		case 1n+rest:
			+children = Pack.pads(rest)
			RowPad{} <> List.append(&2,Row,children,children)

def Pack.terminal(depth: Nat, row: Row) -> List<&2,Row>:
	match depth:
		case 0n: [row]
		case 1n+rest:
			+children = Pack.pads(rest)
			row <> List.append(&2,Row,children,children)

def Table.pad() -> Table:
	Page{RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{},RowPad{}}

def Pack.page(rows: List<&2,Row>) -> Table:
	match rows:
		case r00 <> r01 <> r03 <> r07 <> r15 <> r16 <> r08 <> r17 <> r18 <> r04 <> r09 <> r19 <> r20 <> r10 <> r21 <> r22 <> r02 <> r05 <> r11 <> r23 <> r24 <> r12 <> r25 <> r26 <> r06 <> r13 <> r27 <> r28 <> r14 <> r29 <> r30 <> Nil{}:
			Page{r00,r01,r02,r03,r04,r05,r06,r07,r08,r09,r10,r11,r12,r13,r14,r15,r16,r17,r18,r19,r20,r21,r22,r23,r24,r25,r26,r27,r28,r29,r30}
		case _: Table.pad()

def Pack.bind(packed: List<&2,Row> & (Nat & List<&2,Table>), next: List<&2,Row> -> Nat -> List<&2,Table> -> List<&2,Row> & (Nat & List<&2,Table>)) -> List<&2,Row> & (Nat & List<&2,Table>):
	(rows,(id,pages)) = packed
	next(rows,id,pages)

def Pack.node(tree: Tree, +depth: Nat, +slots: Nat, next: Nat, pages: List<&2,Table>) -> List<&2,Row> & (Nat & List<&2,Table>):
	match tree depth slots:
		case Solid{material} _ _:
			(Pack.terminal(slots,RowSolid{material}),(next,pages))
		case Branch{left,right} 1n+rest 1n+room:
			Pack.bind(Pack.node(left,rest,room,next,pages),a => next => pages =>
				Pack.bind(Pack.node(right,rest,room,next,pages),b => next => pages =>
					(RowSplit{} <> List.append(&2,Row,a,b),(next,pages))))
		case Branch{left,right} _ _:
			+rest = Nat.sub(Pack.depth(),1n)
			Pack.bind(Pack.node(left,rest,3n,next,pages),a => next => pages =>
				Pack.bind(Pack.node(right,rest,3n,next,pages),b => +next => pages =>
					page = Pack.page(RowSplit{} <> List.append(&2,Row,a,b))
					(Pack.terminal(slots,RowLink{next}),(1n+next,page <> pages))))

def Pack.directory.bind(packed: List<&2,Table> & Table, next: List<&2,Table> -> Table -> List<&2,Table> & Table) -> List<&2,Table> & Table:
	(pages,table) = packed
	next(pages,table)

def Pack.directory(+fuel: Nat, +count: Nat, pages: List<&2,Table>) -> List<&2,Table> & Table:
	match fuel count pages:
		case _ 0n _: (Nil{},Table.pad())
		case _ 1n page <> rest: (rest,page)
		case _ 1n Nil{}: (Nil{},Table.pad())
		case 0n 2n+more _: (pages,Table.pad())
		case 1n+rest 2n+more _:
			+half = Nat.div(count,2n)
			Pack.directory.bind(Pack.directory(rest,half,pages),pages => left =>
				Pack.directory.bind(Pack.directory(rest,Nat.sub(count,half),pages),pages => right =>
					(pages,Directory{half,left,right})))

def Grid.pack.table(side: U32, height: Nat, count: Nat, packed: List<&2,Table> & Table) -> Grid:
	(unused,table) = packed
	Grid{side,Index{height,count,table}}

def Grid.pack.rows(side: U32, height: Nat, packed: List<&2,Row> & (Nat & List<&2,Table>)) -> Grid:
	(rows,(+count,pages)) = packed
	root = Pack.page(rows)
	Grid.pack.table(side,height,count,Pack.directory(count,count,root <> List.reverse(&2,Table,pages)))

def Grid.pack(+side: U32, +tree: Tree) -> Grid:
	+height = Tree.height(tree)
	Grid.pack.rows(side,height,Pack.node(tree,Pack.depth(),4n,1n,Nil{}))

def Grid.dense(+side: U32, snapshot: Array<U32> & V.Snapshot) -> V.Body & Grid:
	(cells,copy) = snapshot
	(V.Body{side,cells},Grid.pack(side,Tree.dense(Nat.mul(3n,U32.log2(side)),copy,side,V.Cuboid{V.Cell{0,0,0},V.Cell{side,side,side},0},0)))

def Grid.build(body: V.Body) -> V.Body & Grid:
	match body:
		case V.Body{+side,cells}:
			Grid.dense(side,V.Snapshot.of(cells))
		case V.Cuboids{+boxes}:
			+depth = Nat.add(1n,U32.log2((Grid.extent(boxes,1) - 1 : U32)))
			+side = U32.pow(2,depth)
			(V.Cuboids{boxes},Grid.pack(side,Grid.paint(List.reverse(&2,V.Cuboid,boxes),depth,side,Solid{0})))

def Tree.read(tree: Tree, axis: Split, leftward: Bool, cell: V.Cell, span: V.Cell) -> U32:
	match tree axis leftward cell span:
		case Solid{material} _ _ _ _: material
		case Branch{left,right} SplitX{} True{} V.Cell{x,+y,z} V.Cell{sx,+sy,sz}:
			Tree.read(left,SplitY{},(y < sy / 2 : U32),V.Cell{x,y,z},V.Cell{(sx / 2 : U32),sy,sz})
		case Branch{left,right} SplitX{} False{} V.Cell{x,+y,z} V.Cell{+sx,+sy,sz}:
			Tree.read(right,SplitY{},(y < sy / 2 : U32),V.Cell{(x - sx / 2 : U32),y,z},V.Cell{(sx / 2 : U32),sy,sz})
		case Branch{left,right} SplitY{} True{} V.Cell{x,y,+z} V.Cell{sx,sy,+sz}:
			Tree.read(left,SplitZ{},(z < sz / 2 : U32),V.Cell{x,y,z},V.Cell{sx,(sy / 2 : U32),sz})
		case Branch{left,right} SplitY{} False{} V.Cell{x,y,+z} V.Cell{sx,+sy,+sz}:
			Tree.read(right,SplitZ{},(z < sz / 2 : U32),V.Cell{x,(y - sy / 2 : U32),z},V.Cell{sx,(sy / 2 : U32),sz})
		case Branch{left,right} SplitZ{} True{} V.Cell{+x,y,z} V.Cell{+sx,sy,sz}:
			Tree.read(left,SplitX{},(x < sx / 2 : U32),V.Cell{x,y,z},V.Cell{sx,sy,(sz / 2 : U32)})
		case Branch{left,right} SplitZ{} False{} V.Cell{+x,y,z} V.Cell{+sx,sy,+sz}:
			Tree.read(right,SplitX{},(x < sx / 2 : U32),V.Cell{x,y,(z - sz / 2 : U32)},V.Cell{sx,sy,(sz / 2 : U32)})

def Region.material(region: Region) -> U32:
	Region{material,low,high} = region
	material

def Tree.region(tree: Tree, axis: Split, leftward: Bool, cell: V.Cell, span: V.Cell, low: V.Cell) -> Region:
	match tree axis leftward cell span low:
		case Solid{material} _ _ _ V.Cell{sx,sy,sz} V.Cell{+lx,+ly,+lz}:
			Region{material,V.Cell{lx,ly,lz},V.Cell{(lx + sx : U32),(ly + sy : U32),(lz + sz : U32)}}
		case Branch{left,right} SplitX{} True{} V.Cell{x,+y,z} V.Cell{sx,+sy,sz} low:
			Tree.region(left,SplitY{},(y < sy / 2 : U32),V.Cell{x,y,z},V.Cell{(sx / 2 : U32),sy,sz},low)
		case Branch{left,right} SplitX{} False{} V.Cell{x,+y,z} V.Cell{+sx,+sy,sz} V.Cell{lx,ly,lz}:
			Tree.region(right,SplitY{},(y < sy / 2 : U32),V.Cell{(x - sx / 2 : U32),y,z},V.Cell{(sx / 2 : U32),sy,sz},V.Cell{(lx + sx / 2 : U32),ly,lz})
		case Branch{left,right} SplitY{} True{} V.Cell{x,y,+z} V.Cell{sx,sy,+sz} low:
			Tree.region(left,SplitZ{},(z < sz / 2 : U32),V.Cell{x,y,z},V.Cell{sx,(sy / 2 : U32),sz},low)
		case Branch{left,right} SplitY{} False{} V.Cell{x,y,+z} V.Cell{sx,+sy,+sz} V.Cell{lx,ly,lz}:
			Tree.region(right,SplitZ{},(z < sz / 2 : U32),V.Cell{x,(y - sy / 2 : U32),z},V.Cell{sx,(sy / 2 : U32),sz},V.Cell{lx,(ly + sy / 2 : U32),lz})
		case Branch{left,right} SplitZ{} True{} V.Cell{+x,y,z} V.Cell{+sx,sy,sz} low:
			Tree.region(left,SplitX{},(x < sx / 2 : U32),V.Cell{x,y,z},V.Cell{sx,sy,(sz / 2 : U32)},low)
		case Branch{left,right} SplitZ{} False{} V.Cell{+x,y,z} V.Cell{+sx,sy,+sz} V.Cell{lx,ly,lz}:
			Tree.region(right,SplitX{},(x < sx / 2 : U32),V.Cell{x,y,(z - sz / 2 : U32)},V.Cell{sx,sy,(sz / 2 : U32)},V.Cell{lx,ly,(lz + sz / 2 : U32)})

def Tree.region.valid(inside: Bool, tree: Tree, +side: U32, +cell: V.Cell) -> Region:
	match inside:
		case False{}: Region{0,V.Cell{0,0,0},V.Cell{0,0,0}}
		case True{}:
			V.Cell{+x,y,z} = cell
			Tree.region(tree,SplitX{},(x < side / 2 : U32),cell,V.Cell{side,side,side},V.Cell{0,0,0})

def Slot.child(slot: Nat, leftward: Bool) -> Nat:
	match leftward:
		case True{}: 1n+Nat.double(slot)
		case False{}: 2n+Nat.double(slot)

def Space.leftward(+space: Space) -> Bool:
	Space{axis,leftward,cell,span,low} = space
	leftward

def Space.region(material: U32, space: Space) -> Region:
	Space{axis,leftward,cell,V.Cell{sx,sy,sz},V.Cell{+lx,+ly,+lz}} = space
	Region{material,V.Cell{lx,ly,lz},V.Cell{(lx + sx : U32),(ly + sy : U32),(lz + sz : U32)}}

def Space.step(space: Space) -> Space:
	match space:
		case Space{SplitX{},True{},V.Cell{x,+y,z},V.Cell{sx,+sy,sz},low}:
			Space{SplitY{},(y < sy / 2 : U32),V.Cell{x,y,z},V.Cell{(sx / 2 : U32),sy,sz},low}
		case Space{SplitX{},False{},V.Cell{x,+y,z},V.Cell{+sx,+sy,sz},V.Cell{lx,ly,lz}}:
			Space{SplitY{},(y < sy / 2 : U32),V.Cell{(x - sx / 2 : U32),y,z},V.Cell{(sx / 2 : U32),sy,sz},V.Cell{(lx + sx / 2 : U32),ly,lz}}
		case Space{SplitY{},True{},V.Cell{x,y,+z},V.Cell{sx,sy,+sz},low}:
			Space{SplitZ{},(z < sz / 2 : U32),V.Cell{x,y,z},V.Cell{sx,(sy / 2 : U32),sz},low}
		case Space{SplitY{},False{},V.Cell{x,y,+z},V.Cell{sx,+sy,+sz},V.Cell{lx,ly,lz}}:
			Space{SplitZ{},(z < sz / 2 : U32),V.Cell{x,(y - sy / 2 : U32),z},V.Cell{sx,(sy / 2 : U32),sz},V.Cell{lx,(ly + sy / 2 : U32),lz}}
		case Space{SplitZ{},True{},V.Cell{+x,y,z},V.Cell{+sx,sy,sz},low}:
			Space{SplitX{},(x < sx / 2 : U32),V.Cell{x,y,z},V.Cell{sx,sy,(sz / 2 : U32)},low}
		case Space{SplitZ{},False{},V.Cell{+x,y,z},V.Cell{+sx,sy,+sz},V.Cell{lx,ly,lz}}:
			Space{SplitX{},(x < sx / 2 : U32),V.Cell{x,y,(z - sz / 2 : U32)},V.Cell{sx,sy,(sz / 2 : U32)},V.Cell{lx,ly,(lz + sz / 2 : U32)}}

def Tree.space(tree: Tree, space: Space) -> Region:
	Space{axis,leftward,cell,span,low} = space
	Tree.region(tree,axis,leftward,cell,span,low)

def Page.row(slot: Nat, +page: Table) -> Row:
	match slot:
		case 0n:
			match page:
				case Page{row,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 1n:
			match page:
				case Page{_,row,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 2n:
			match page:
				case Page{_,_,row,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 3n:
			match page:
				case Page{_,_,_,row,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 4n:
			match page:
				case Page{_,_,_,_,row,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 5n:
			match page:
				case Page{_,_,_,_,_,row,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 6n:
			match page:
				case Page{_,_,_,_,_,_,row,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 7n:
			match page:
				case Page{_,_,_,_,_,_,_,row,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 8n:
			match page:
				case Page{_,_,_,_,_,_,_,_,row,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 9n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,row,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 10n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,row,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 11n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,row,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 12n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,_,row,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 13n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,_,_,row,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 14n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,_,_,_,row,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 15n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,row,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 16n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,row,_,_,_,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 17n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,row,_,_,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 18n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,row,_,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 19n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,row,_,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 20n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,row,_,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 21n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,row,_,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 22n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,row,_,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 23n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,row,_,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 24n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,row,_,_,_,_,_,_}: row
				case _: RowPad{}
		case 25n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,row,_,_,_,_,_}: row
				case _: RowPad{}
		case 26n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,row,_,_,_,_}: row
				case _: RowPad{}
		case 27n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,row,_,_,_}: row
				case _: RowPad{}
		case 28n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,row,_,_}: row
				case _: RowPad{}
		case 29n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,row,_}: row
				case _: RowPad{}
		case 30n:
			match page:
				case Page{_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,row}: row
				case _: RowPad{}
		case _: RowPad{}

def Page.walk(fuel: Nat, row: Row, +page: Table, +slot: Nat, +space: Space) -> PageResult:
	match fuel row:
		case 0n _: Invalid{}
		case 1n+rest RowSolid{material}: Finished{Space.region(material,space)}
		case 1n+rest RowLink{target}: Resume{target,space}
		case 1n+rest RowSplit{}:
			+next = Slot.child(slot,Space.leftward(space))
			Page.walk(rest,Page.row(next,page),page,next,Space.step(space))
		case 1n+rest RowPad{}: Invalid{}

def Table.less(+table: Table, id: Nat) -> Bool:
	match table:
		case Directory{cut,_,_}: Nat.is_lt(id,cut)
		case _: False{}

def Table.seek(+table: Table, less: Bool, +id: Nat, +space: Space) -> PageResult:
	match table less:
		case Directory{cut,+left,right} True{}:
			Table.seek(left,Table.less(left,id),id,space)
		case Directory{+cut,left,+right} False{}:
			+next = Nat.sub(id,cut)
			Table.seek(right,Table.less(right,next),next,space)
		case page _: Page.walk(1n+Pack.depth(),Page.row(0n,page),page,0n,space)

def Index.region(fuel: Nat, result: PageResult, +table: Table) -> Region:
	match fuel result:
		case 0n _: Region{0,V.Cell{0,0,0},V.Cell{0,0,0}}
		case 1n+rest Finished{region}: region
		case 1n+rest Resume{+next,state}:
			Index.region(rest,Table.seek(table,Table.less(table,next),next,state),table)
		case 1n+rest Invalid{}: Region{0,V.Cell{0,0,0},V.Cell{0,0,0}}

def Grid.region.valid(inside: Bool, +cells: Index, +side: U32, +cell: V.Cell) -> Region:
	match inside:
		case False{}: Region{0,V.Cell{0,0,0},V.Cell{0,0,0}}
		case True{}:
			Index{height,count,+table} = cells
			V.Cell{+x,y,z} = cell
			Index.region(1n+height,Table.seek(table,Table.less(table,0n),0n,Space{SplitX{},(x < side / 2 : U32),cell,V.Cell{side,side,side},V.Cell{0,0,0}}),table)

def Grid.region(+grid: Grid, +cell: V.Cell) -> Region:
	Grid{+side,cells} = grid
	Grid.region.valid(V.Cell.inside(side,cell),cells,side,cell)

def Grid.read.valid(inside: Bool, +cells: Index, +side: U32, +cell: V.Cell) -> U32:
	Region.material(Grid.region.valid(inside,cells,side,cell))

def Grid.read(+grid: Grid, +cell: V.Cell) -> U32:
	Grid{+side,cells} = grid
	Grid.read.valid(V.Cell.inside(side,cell),cells,side,cell)

def Slab.axis(moving: Bool, +origin: F32, +delta: F32, +side: F32) -> Slab:
	match moving:
		case False{}:
			Bool.pick(Slab,((origin >= 0.0) && (origin <= side) : F32),Slab{(0.0 - 1.0e30 : F32),1.0e30},Slab{1.0e30,(0.0 - 1.0e30 : F32)})
		case True{}:
			+a = ((0.0 - origin) / delta : F32)
			+b = ((side - origin) / delta : F32)
			Slab{F32.min(a,b),F32.max(a,b)}

def Direction.entry(axis: U32, positive: Bool) -> V.Direction:
	match axis positive:
		case 0 True{}: V.NegX{}
		case 0 False{}: V.PosX{}
		case 1 True{}: V.NegY{}
		case 1 False{}: V.PosY{}
		case _ True{}: V.NegZ{}
		case _ False{}: V.PosZ{}

def Direction.flip(direction: V.Direction) -> V.Direction:
	match direction:
		case V.NegX{}: V.PosX{}
		case V.PosX{}: V.NegX{}
		case V.NegY{}: V.PosY{}
		case V.PosY{}: V.NegY{}
		case V.NegZ{}: V.PosZ{}
		case V.PosZ{}: V.NegZ{}

def Axis.cell(positive: Bool, +point: F32, side: U32) -> U32:
	+index = Bool.pick(F32,positive,F32.floor(point),(F32.ceil(point) - 1.0 : F32))
	F32.to_u32(F32.clamp(index,0.0,U32.to_f32((side - 1 : U32))))

def Axis.next(moving: Bool, positive: Bool, origin: F32, delta: F32, cell: U32) -> F32:
	match moving:
		case False{}: 1.0e30
		case True{}:
			((U32.to_f32(cell) + U32.to_f32(Bool.to_u32(positive)) - origin) / delta : F32)

def Axis.step(crosses: Bool, positive: Bool, cell: U32) -> U32:
	match crosses positive:
		case False{} _: cell
		case True{} True{}: (cell + 1 : U32)
		case True{} False{}: (cell - 1 : U32)

def Crossing.next(eye: R.Vec3, ray: R.Vec3, +cell: V.Cell) -> Crossing:
	R.Vec3{ox,oy,oz} = eye
	R.Vec3{+dx,+dy,+dz} = ray
	V.Cell{+x,+y,+z} = cell
	+tx = Axis.next(F32.is_ne(dx,0.0),(dx > 0.0 : F32),ox,dx,x)
	+ty = Axis.next(F32.is_ne(dy,0.0),(dy > 0.0 : F32),oy,dy,y)
	+tz = Axis.next(F32.is_ne(dz,0.0),(dz > 0.0 : F32),oz,dz,z)
	+t = F32.min(tx,F32.min(ty,tz))
	+axis = Bool.pick(U32,F32.is_eq(t,tx),0,Bool.pick(U32,F32.is_eq(t,ty),1,2))
	+delta = Bool.pick(F32,U32.is_eq(axis,0),dx,Bool.pick(F32,U32.is_eq(axis,1),dy,dz))
	Crossing{t,V.Cell{Axis.step(F32.is_eq(t,tx),(dx > 0.0 : F32),x),Axis.step(F32.is_eq(t,ty),(dy > 0.0 : F32),y),Axis.step(F32.is_eq(t,tz),(dz > 0.0 : F32),z)},cell,Direction.entry(axis,(delta > 0.0 : F32))}

def Crossing.cell(crossing: Crossing) -> V.Cell:
	Crossing{depth,cell,previous,direction} = crossing
	cell

# The divided plane time remains authoritative; the rounded point is an estimate.
def Axis.before(positive: Bool, origin: F32, delta: F32, +cell: U32, time: F32, +count: U32) -> Bool:
	+plane = Bool.pick(U32,positive,(cell + count : U32),(cell + 1 - count : U32))
	U32.is_zero(count) || ((U32.to_f32(plane) - origin) / delta <= time : F32)

def Axis.correct(fuel: Nat, +up: Bool, before: Bool, at_limit: Bool, +positive: Bool, +origin: F32, +delta: F32, +cell: U32, +time: F32, +count: U32, +limit: U32) -> U32:
	match fuel up before at_limit:
		case 0n _ _ _: count
		case 1n+rest False{} True{} _: count
		case 1n+rest False{} False{} _:
			+next = (count - 1 : U32)
			Axis.correct(rest,False{},Axis.before(positive,origin,delta,cell,time,next),U32.is_eq(next,limit),positive,origin,delta,cell,time,next,limit)
		case 1n+rest True{} False{} _: (count - 1 : U32)
		case 1n+rest True{} True{} True{}: count
		case 1n+rest True{} True{} False{}:
			+next = (count + 1 : U32)
			Axis.correct(rest,True{},Axis.before(positive,origin,delta,cell,time,next),U32.is_eq(next,limit),positive,origin,delta,cell,time,next,limit)

def Axis.count(+positive: Bool, +origin: F32, +delta: F32, +cell: U32, +time: F32, +limit: U32) -> U32:
	+point = (origin + time * delta : F32)
	+events = Bool.pick(F32,positive,(point - U32.to_f32(cell) : F32),(U32.to_f32(cell) + 1.0 - point : F32))
	+estimate = U32.min(limit,F32.to_u32(F32.clamp(events,0.0,U32.to_f32(limit))))
	+before = Axis.before(positive,origin,delta,cell,time,estimate)
	Axis.correct(Nat.add(1n,U32.to_nat(limit)),before,before,U32.is_eq(estimate,limit),positive,origin,delta,cell,time,estimate,limit)

def Axis.advanced(+positive: Bool, origin: F32, delta: F32, +cell: U32, +time: F32, +count: U32) -> Advance:
	+next = Bool.pick(U32,positive,(cell + count : U32),(cell - count : U32))
	+previous = Bool.pick(U32,positive,(next - 1 : U32),(next + 1 : U32))
	+crosses = U32.is_ne(count,0) && F32.is_eq(Axis.next(True{},positive,origin,delta,previous),time)
	Advance{next,Bool.pick(U32,crosses,previous,next),crosses}

def Axis.advance.count(reuse: Bool, +positive: Bool, +origin: F32, +delta: F32, +cell: U32, +time: F32, +limit: U32) -> U32:
	match reuse:
		case True{}: limit
		case False{}: Axis.count(positive,origin,delta,cell,time,limit)

def Axis.advance(moving: Bool, +positive: Bool, +origin: F32, +delta: F32, +cell: U32, +time: F32, boundary_time: F32, +low: U32, +high: U32) -> Advance:
	match moving:
		case False{}: Advance{cell,cell,False{}}
		case True{}:
			+limit = Bool.pick(U32,positive,(high - cell : U32),(cell - low + 1 : U32))
			reuse = ((low <= cell) && (cell < high) && (high <= 16777216) : U32) && F32.is_eq(time,boundary_time)
			Axis.advanced(positive,origin,delta,cell,time,Axis.advance.count(reuse,positive,origin,delta,cell,time,limit))

def Crossing.advanced(time: F32, ray: R.Vec3, x: Advance, y: Advance, z: Advance) -> Crossing:
	R.Vec3{dx,dy,dz} = ray
	Advance{x,px,+cx} = x
	Advance{y,py,+cy} = y
	Advance{z,pz,cz} = z
	+axis = Bool.pick(U32,cx,0,Bool.pick(U32,cy,1,2))
	+delta = Bool.pick(F32,cx,dx,Bool.pick(F32,cy,dy,dz))
	Crossing{time,V.Cell{x,y,z},V.Cell{px,py,pz},Direction.entry(axis,(delta > 0.0 : F32))}

def Crossing.region(eye: R.Vec3, +ray: R.Vec3, cell: V.Cell, region: Region) -> Crossing:
	R.Vec3{+ox,+oy,+oz} = eye
	R.Vec3{+dx,+dy,+dz} = ray
	V.Cell{+x,+y,+z} = cell
	Region{material,V.Cell{+lx,+ly,+lz},V.Cell{+hx,+hy,+hz}} = region
	+px = (dx > 0.0 : F32)
	+py = (dy > 0.0 : F32)
	+pz = (dz > 0.0 : F32)
	+tx = Axis.next(F32.is_ne(dx,0.0),px,ox,dx,Bool.pick(U32,px,(hx - 1 : U32),lx))
	+ty = Axis.next(F32.is_ne(dy,0.0),py,oy,dy,Bool.pick(U32,py,(hy - 1 : U32),ly))
	+tz = Axis.next(F32.is_ne(dz,0.0),pz,oz,dz,Bool.pick(U32,pz,(hz - 1 : U32),lz))
	+time = F32.min(tx,F32.min(ty,tz))
	Crossing.advanced(time,ray,Axis.advance(F32.is_ne(dx,0.0),px,ox,dx,x,time,tx,lx,hx),
		Axis.advance(F32.is_ne(dy,0.0),py,oy,dy,y,time,ty,ly,hy),Axis.advance(F32.is_ne(dz,0.0),pz,oz,dz,z,time,tz,lz,hz))

# A ray crosses at most 3 * side grid planes.
# Equal crossing times advance every tied axis, with X/Y/Z face priority.
def Trace.walk(fuel: Nat, inside: Bool, material: U32, previous: U32, +grid: Grid, +eye: R.Vec3, +ray: R.Vec3, crossing: Crossing) -> Maybe<&2,SurfaceHit>:
	match fuel inside material previous:
		case 0n _ _ _: None{}
		case 1n+rest False{} 0 0: None{}
		case 1n+rest True{} 0 0:
			Grid{+side,cells} = grid
			Crossing{depth,+cell,old,direction} = crossing
			+next = Crossing.next(eye,ray,cell)
			+next_cell = Crossing.cell(next)
			Trace.walk(rest,V.Cell.inside(side,next_cell),Grid.read(grid,next_cell),0,grid,eye,ray,next)
		case 1n+rest True{} m 0:
			Crossing{depth,cell,old,direction} = crossing
			Some{SurfaceHit{depth,cell,direction,m}}
		case 1n+rest _ 0 p:
			Crossing{depth,cell,old,direction} = crossing
			Some{SurfaceHit{depth,old,Direction.flip(direction),p}}
		case 1n+rest False{} _ _: None{}
		case 1n+rest True{} +m p:
			Grid{+side,cells} = grid
			Crossing{depth,+cell,old,direction} = crossing
			+next = Crossing.next(eye,ray,cell)
			+next_cell = Crossing.cell(next)
			Trace.walk(rest,V.Cell.inside(side,next_cell),Grid.read(grid,next_cell),m,grid,eye,ray,next)

def Axis.cells(point: R.Vec3, ray: R.Vec3, +side: U32) -> V.Cell:
	R.Vec3{x,y,z} = point
	R.Vec3{dx,dy,dz} = ray
	V.Cell{Axis.cell((dx >= 0.0 : F32),x,side),Axis.cell((dy >= 0.0 : F32),y,side),Axis.cell((dz >= 0.0 : F32),z,side)}

def Trace.regions(fuel: Nat, inside: Bool, previous: U32, +grid: Grid, +eye: R.Vec3, +ray: R.Vec3, crossing: Crossing, +region: Region) -> Maybe<&2,SurfaceHit>:
	match fuel inside previous grid crossing region:
		case 0n _ _ _ _ _: None{}
		case 1n+rest False{} 0 _ _ _: None{}
		case 1n+rest True{} 0 Grid{side,cells} Crossing{depth,cell,old,direction} Region{0,low,high}:
			+next = Crossing.region(eye,ray,cell,region)
			+next_cell = Crossing.cell(next)
			Trace.regions(rest,V.Cell.inside(side,next_cell),0,grid,eye,ray,next,Grid.region(grid,next_cell))
		case 1n+rest True{} 0 _ Crossing{depth,cell,old,direction} Region{m,low,high}:
			Some{SurfaceHit{depth,cell,direction,m}}
		case 1n+rest _ p _ Crossing{depth,cell,old,direction} Region{0,low,high}:
			Some{SurfaceHit{depth,old,Direction.flip(direction),p}}
		case 1n+rest False{} _ _ _ _: None{}
		case 1n+rest True{} p Grid{side,cells} Crossing{depth,cell,old,direction} Region{m,low,high}:
			+next = Crossing.region(eye,ray,cell,region)
			+next_cell = Crossing.cell(next)
			Trace.regions(rest,V.Cell.inside(side,next_cell),m,grid,eye,ray,next,Grid.region(grid,next_cell))

def Trace.enter(skip: Bool, +grid: Grid, +eye: R.Vec3, +ray: R.Vec3, +cell: V.Cell, +time: F32, +inside: Bool, +direction: V.Direction) -> Maybe<&2,SurfaceHit>:
	match skip:
		case False{}:
			Grid{side,cells} = grid
			+material = Grid.read(grid,cell)
			Trace.walk(U32.to_nat((3 * side + 1 : U32)),True{},material,Bool.pick(U32,inside,material,0),grid,eye,ray,Crossing{time,cell,cell,direction})
		case True{}:
			Grid{side,cells} = grid
			+region = Grid.region(grid,cell)
			Trace.regions(U32.to_nat((3 * side + 1 : U32)),True{},Bool.pick(U32,inside,Region.material(region),0),grid,eye,ray,Crossing{time,cell,cell,direction},region)

def Trace.start(intersects: Bool, skip: Bool, +grid: Grid, +eye: R.Vec3, +ray: R.Vec3, +near: F32, +enter: F32, direction: V.Direction) -> Maybe<&2,SurfaceHit>:
	match intersects:
		case False{}: None{}
		case True{}:
			Grid{+side,cells} = grid
			+t = F32.max(near,enter)
			+cell = Axis.cells(R.Vec3.add(eye,R.Vec3.scale(ray,t)),ray,side)
			Trace.enter(skip,grid,eye,ray,cell,t,(enter < near : F32),direction)

def Trace.slabs(skip: Bool, grid: Grid, eye: R.Vec3, +ray: R.Vec3, +near: F32, x: Slab, y: Slab, z: Slab) -> Maybe<&2,SurfaceHit>:
	R.Vec3{+dx,+dy,+dz} = ray
	Slab{+tx,+lx} = x
	Slab{+ty,+ly} = y
	Slab{+tz,+lz} = z
	+enter = F32.max(tx,F32.max(ty,tz))
	+leave = F32.min(lx,F32.min(ly,lz))
	+axis = Bool.pick(U32,F32.is_eq(enter,tx),0,Bool.pick(U32,F32.is_eq(enter,ty),1,2))
	+delta = Bool.pick(F32,U32.is_eq(axis,0),dx,Bool.pick(F32,U32.is_eq(axis,1),dy,dz))
	Trace.start(((F32.max(near,enter) < leave) && (enter < 1.0e30) : F32),skip,grid,eye,ray,near,enter,Direction.entry(axis,(delta > 0.0 : F32)))

def Trace.mode(skip: Bool, +grid: Grid, +eye: R.Vec3, +ray: R.Vec3, near: F32) -> Maybe<&2,SurfaceHit>:
	Grid{side,cells} = grid
	R.Vec3{ox,oy,oz} = eye
	R.Vec3{+dx,+dy,+dz} = ray
	+extent = U32.to_f32(side)
	Trace.slabs(skip,grid,eye,ray,near,Slab.axis(F32.is_ne(dx,0.0),ox,dx,extent),Slab.axis(F32.is_ne(dy,0.0),oy,dy,extent),Slab.axis(F32.is_ne(dz,0.0),oz,dz,extent))

def Trace.ray(grid: Grid, eye: R.Vec3, ray: R.Vec3, near: F32) -> Maybe<&2,SurfaceHit>:
	Trace.mode(True{},grid,eye,ray,near)

def Pixel.hit(hit: Maybe<&2,SurfaceHit>, palette: Palette, background: R.Hit) -> R.Hit:
	match hit:
		case None{}: background
		case Some{SurfaceHit{depth,cell,+direction,material}}:
			R.Hit{depth,Palette.color(material,palette,direction),0,Some{cell},direction}

def Ground() -> R.GroundLighting:
	R.GroundLighting{L.Color{9},L.Ramp.build(M.LinearRgb{0.10,0.12,0.15},V.PosZ{}),L.Ramp.build(M.LinearRgb{0.055,0.065,0.08},V.PosZ{})}

def Frame.seq(+depth: Nat, +skip: Bool, +grid: Grid, +basis: R.Basis, +palette: Palette, +ground: R.GroundLighting, +x: U32, +y: U32, +size: U32) -> Image:
	match depth:
		case 0n:
			R.Basis{eye,right,up,forward,focal,near} = basis
			+ray = R.Pixel.ray(basis,x,y)
			R.Pixel.present(ground,basis,ray,None{},x,y,Pixel.hit(Trace.mode(skip,grid,eye,ray,near),palette,R.Hit.background(x,y)))
		case 1n+rest:
			+h = (size / 2 : U32)
			Qua{Frame.seq(rest,skip,grid,basis,palette,ground,x,y,h),Frame.seq(rest,skip,grid,basis,palette,ground,(x + h : U32),y,h),
				Frame.seq(rest,skip,grid,basis,palette,ground,x,(y + h : U32),h),Frame.seq(rest,skip,grid,basis,palette,ground,(x + h : U32),(y + h : U32),h)}

def Frame.fork(+depth: Nat, +skip: Bool, +grid: Grid, +basis: R.Basis, +palette: Palette, +ground: R.GroundLighting, +x: U32, +y: U32, +size: U32) -> Image:
	match depth:
		case 0n: Frame.seq(U32.log2(size),skip,grid,basis,palette,ground,x,y,size)
		case 1n+rest:
			+h = (size / 2 : U32)
			a b c d = Frame.fork(rest,skip,grid,basis,palette,ground,x,y,h) Frame.fork(rest,skip,grid,basis,palette,ground,(x + h : U32),y,h) Frame.fork(rest,skip,grid,basis,palette,ground,x,(y + h : U32),h) Frame.fork(rest,skip,grid,basis,palette,ground,(x + h : U32),(y + h : U32),h)
			Qua{a,b,c,d}

def Frame.image(+grid: Grid, +basis: R.Basis, +palette: Palette, +ground: R.GroundLighting, fork: Nat) -> Grid & Image:
	(grid,Frame.fork!(fork,True{},grid,basis,palette,ground,0,0,512))
