import Base
import ./voxel.bend as V
import ./render.bend as R
import ./lighting.bend as L
import ./material.bend as M

type Tree is Data:
	Solid{material: U32}
	Branch{left: Tree, right: Tree}

type Grid is Data:
	Grid{side: U32, cells: Tree}

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

def Grid.dense(+side: U32, snapshot: Array<U32> & V.Snapshot) -> V.Body & Grid:
	(cells,copy) = snapshot
	(V.Body{side,cells},Grid{side,Tree.dense(Nat.mul(3n,U32.log2(side)),copy,side,V.Cuboid{V.Cell{0,0,0},V.Cell{side,side,side},0},0)})

def Grid.build(body: V.Body) -> V.Body & Grid:
	match body:
		case V.Body{+side,cells}:
			Grid.dense(side,V.Snapshot.of(cells))
		case V.Cuboids{+boxes}:
			+depth = Nat.add(1n,U32.log2((Grid.extent(boxes,1) - 1 : U32)))
			+side = U32.pow(2,depth)
			(V.Cuboids{boxes},Grid{side,Grid.paint(List.reverse(&2,V.Cuboid,boxes),depth,side,Solid{0})})

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

def Grid.read.valid(inside: Bool, cells: Tree, +side: U32, cell: V.Cell) -> U32:
	match inside:
		case False{}: 0
		case True{}:
			V.Cell{+x,y,z} = cell
			Tree.read(cells,SplitX{},(x < side / 2 : U32),cell,V.Cell{side,side,side})

def Grid.read(grid: Grid, +cell: V.Cell) -> U32:
	Grid{+side,cells} = grid
	Grid.read.valid(V.Cell.inside(side,cell),cells,side,cell)

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

def Grid.region.valid(inside: Bool, cells: Tree, +side: U32, cell: V.Cell) -> Region:
	match inside:
		case False{}: Region{0,V.Cell{0,0,0},V.Cell{0,0,0}}
		case True{}:
			V.Cell{+x,y,z} = cell
			Tree.region(cells,SplitX{},(x < side / 2 : U32),cell,V.Cell{side,side,side},V.Cell{0,0,0})

def Grid.region(grid: Grid, +cell: V.Cell) -> Region:
	Grid{+side,cells} = grid
	Grid.region.valid(V.Cell.inside(side,cell),cells,side,cell)

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

type ForkDepth is Data:
	F0{}
	F1{}
	F2{}
	F3{}
	F4{}
	F5{}
	F6{}
	F7{}
	F8{}
	F9{}

type Assignment is Data:
	Contiguous{}
	Interleaved{}

type Schedule is Data:
	Schedule{fork: ForkDepth, assignment: Assignment}

type Dimensions is Data:
	Dimensions{q: U32, s: U32, leaf_depth: Nat}

type Point is Data:
	Point{x: U32, y: U32}

type Owner is Data:
	Owner{qx: U32, qy: U32}

type Local is Data:
	Local{ix: U32, iy: U32}

type Address is Data:
	Address{owner: Owner, local: Local}

type Four is Data:
	Four{tl: Image, tr: Image, bl: Image, br: Image}

def ForkDepth.nat(depth: ForkDepth) -> Nat:
	match depth:
		case F0{}: 0n
		case F1{}: 1n
		case F2{}: 2n
		case F3{}: 3n
		case F4{}: 4n
		case F5{}: 5n
		case F6{}: 6n
		case F7{}: 7n
		case F8{}: 8n
		case F9{}: 9n

def ForkDepth.read(text: String) -> Maybe<&2,ForkDepth>:
	match text:
		case "0": Some{F0{}}
		case "1": Some{F1{}}
		case "2": Some{F2{}}
		case "3": Some{F3{}}
		case "4": Some{F4{}}
		case "5": Some{F5{}}
		case "6": Some{F6{}}
		case "7": Some{F7{}}
		case "8": Some{F8{}}
		case "9": Some{F9{}}
		case _: None{}

def Schedule.dimensions(schedule: Schedule) -> Dimensions:
	Schedule{fork,assignment} = schedule
	+f = ForkDepth.nat(fork)
	+l = Nat.sub(9n,f)
	Dimensions{(1 << f : U32),(1 << l : U32),l}

def Dimensions.valid(dimensions: Dimensions) -> Bool:
	Dimensions{+q,+s,leaf_depth} = dimensions
	(q > 0 : U32) && (s > 0 : U32) && U32.is_eq((q * s : U32),512)

def Schedule.valid(schedule: Schedule) -> Bool:
	Dimensions.valid(Schedule.dimensions(schedule))

def Point.bounded(point: Point) -> Bool:
	Point{x,y} = point
	(x < 512 : U32) && (y < 512 : U32)

def Point.x(point: Point) -> U32:
	Point{x,y} = point
	x

def Point.y(point: Point) -> U32:
	Point{x,y} = point
	y

def Address.within(dimensions: Dimensions, address: Address) -> Bool:
	Dimensions{+q,+s,leaf_depth} = dimensions
	Address{Owner{qx,qy},Local{ix,iy}} = address
	(qx < q : U32) && (qy < q : U32) && (ix < s : U32) && (iy < s : U32)

def Address.bounded(schedule: Schedule, address: Address) -> Bool:
	Address.within(Schedule.dimensions(schedule),address)

def Assign.contiguous(owner: U32, local: U32, side: U32) -> U32:
	(owner * side + local : U32)

def Assign.interleaved(owner: U32, local: U32, jobs: U32) -> U32:
	(local * jobs + owner : U32)

def Assign.locate(assignment: Assignment, dimensions: Dimensions, address: Address) -> Point:
	match assignment:
		case Contiguous{}:
			Dimensions{q,+s,leaf_depth} = dimensions
			Address{Owner{qx,qy},Local{ix,iy}} = address
			Point{Assign.contiguous(qx,ix,s),Assign.contiguous(qy,iy,s)}
		case Interleaved{}:
			Dimensions{+q,s,leaf_depth} = dimensions
			Address{Owner{qx,qy},Local{ix,iy}} = address
			Point{Assign.interleaved(qx,ix,q),Assign.interleaved(qy,iy,q)}

def Assign.pixel(+schedule: Schedule, address: Address) -> Point:
	Schedule{fork,assignment} = schedule
	Assign.locate(assignment,Schedule.dimensions(schedule),address)

def Assign.owner(assignment: Assignment, dimensions: Dimensions, point: Point) -> Address:
	match assignment:
		case Contiguous{}:
			Dimensions{q,+s,leaf_depth} = dimensions
			Point{+x,+y} = point
			Address{Owner{(x / s : U32),(y / s : U32)},Local{(x % s : U32),(y % s : U32)}}
		case Interleaved{}:
			Dimensions{+q,s,leaf_depth} = dimensions
			Point{+x,+y} = point
			Address{Owner{(x % q : U32),(y % q : U32)},Local{(x / q : U32),(y / q : U32)}}

def Assign.inverse(+schedule: Schedule, point: Point) -> Address:
	Schedule{fork,assignment} = schedule
	Assign.owner(assignment,Schedule.dimensions(schedule),point)

def Native.open(image: Image) -> Four:
	match image:
		case Pix{+color}: Four{Pix{color},Pix{color},Pix{color},Pix{color}}
		case Qua{a,b,c,d}: Four{a,b,c,d}

def Native.weave.opened(+local: Nat, a: Four, b: Four, c: Four, d: Four) -> Image:
	match local a b c d:
		case 0n Four{aa,ab,ac,ad} Four{ba,bb,bc,bd} Four{ca,cb,cc,cd} Four{da,db,dc,dd}:
			Qua{Qua{aa,ba,ca,da},Qua{ab,bb,cb,db},Qua{ac,bc,cc,dc},Qua{ad,bd,cd,dd}}
		case 1n+rest Four{aa,ab,ac,ad} Four{ba,bb,bc,bd} Four{ca,cb,cc,cd} Four{da,db,dc,dd}:
			Qua{Native.weave.opened(rest,Native.open(aa),Native.open(ba),Native.open(ca),Native.open(da)),
				Native.weave.opened(rest,Native.open(ab),Native.open(bb),Native.open(cb),Native.open(db)),
				Native.weave.opened(rest,Native.open(ac),Native.open(bc),Native.open(cc),Native.open(dc)),
				Native.weave.opened(rest,Native.open(ad),Native.open(bd),Native.open(cd),Native.open(dd))}

def Native.weave(local: Nat, images: Four) -> Image:
	match local:
		case 0n:
			Four{a,b,c,d} = images
			Qua{a,b,c,d}
		case 1n+rest:
			Four{a,b,c,d} = images
			Native.weave.opened(rest,Native.open(a),Native.open(b),Native.open(c),Native.open(d))

def Native.transpose(a: Four, b: Four, c: Four, d: Four) -> Four:
	Four{aa,ab,ac,ad} = a
	Four{ba,bb,bc,bd} = b
	Four{ca,cb,cc,cd} = c
	Four{da,db,dc,dd} = d
	Four{Qua{aa,ba,ca,da},Qua{ab,bb,cb,db},Qua{ac,bc,cc,dc},Qua{ad,bd,cd,dd}}

def Native.unweave(+local: Nat, image: Image) -> Four:
	match local image:
		case 0n _: Native.open(image)
		case 1n+rest Pix{+color}:
			Native.transpose(Native.unweave(rest,Pix{color}),Native.unweave(rest,Pix{color}),Native.unweave(rest,Pix{color}),Native.unweave(rest,Pix{color}))
		case 1n+rest Qua{a,b,c,d}:
			Native.transpose(Native.unweave(rest,a),Native.unweave(rest,b),Native.unweave(rest,c),Native.unweave(rest,d))

def Native.full(+depth: Nat, image: Image) -> Bool:
	match depth image:
		case 0n Pix{color}: True{}
		case 1n+rest Qua{a,b,c,d}:
			Native.full(rest,a) && Native.full(rest,b) && Native.full(rest,c) && Native.full(rest,d)
		case _ _: False{}

def Native.is_pixel(image: Image) -> Bool:
	match image:
		case Pix{color}: True{}
		case Qua{a,b,c,d}: False{}

def Native.at(+depth: Nat, image: Image, +point: Point) -> Image:
	match depth image:
		case _ Pix{color}: Pix{color}
		case 0n Qua{a,b,c,d}: Qua{a,b,c,d}
		case 1n+rest Qua{a,b,c,d}:
			Point{x,y} = point
			+mask = (1 << rest : U32)
			Native.at(rest,Bool.pick(Image,U32.is_zero((y .&. mask : U32)),
				Bool.pick(Image,U32.is_zero((x .&. mask : U32)),a,b),
				Bool.pick(Image,U32.is_zero((x .&. mask : U32)),c,d)),point)

def Frame.local(+depth: Nat, +skip: Bool, +grid: Grid, +basis: R.Basis, +palette: Palette, +ground: R.GroundLighting,
	+q: U32, +qx: U32, +qy: U32, +ix: U32, +iy: U32, +side: U32) -> Image:
	match depth:
		case 0n:
			Frame.seq(0n,skip,grid,basis,palette,ground,Assign.interleaved(qx,ix,q),Assign.interleaved(qy,iy,q),1)
		case 1n+rest:
			+h = (side / 2 : U32)
			Qua{Frame.local(rest,skip,grid,basis,palette,ground,q,qx,qy,ix,iy,h),
				Frame.local(rest,skip,grid,basis,palette,ground,q,qx,qy,(ix + h : U32),iy,h),
				Frame.local(rest,skip,grid,basis,palette,ground,q,qx,qy,ix,(iy + h : U32),h),
				Frame.local(rest,skip,grid,basis,palette,ground,q,qx,qy,(ix + h : U32),(iy + h : U32),h)}

def Frame.owners(+remaining: Nat, +local: Nat, +skip: Bool, +grid: Grid, +basis: R.Basis, +palette: Palette, +ground: R.GroundLighting,
	+q: U32, +s: U32, +qx: U32, +qy: U32, +owner_side: U32) -> Image:
	match remaining:
		case 0n: Frame.local(local,skip,grid,basis,palette,ground,q,qx,qy,0,0,s)
		case 1n+rest:
			+h = (owner_side / 2 : U32)
			a b c d = Frame.owners(rest,local,skip,grid,basis,palette,ground,q,s,qx,qy,h) Frame.owners(rest,local,skip,grid,basis,palette,ground,q,s,(qx + h : U32),qy,h) Frame.owners(rest,local,skip,grid,basis,palette,ground,q,s,qx,(qy + h : U32),h) Frame.owners(rest,local,skip,grid,basis,palette,ground,q,s,(qx + h : U32),(qy + h : U32),h)
			Native.weave(local,Four{a,b,c,d})

def Frame.interleaved(dimensions: Dimensions, fork: ForkDepth, skip: Bool, grid: Grid, basis: R.Basis, palette: Palette, ground: R.GroundLighting) -> Image:
	Dimensions{+q,s,local} = dimensions
	Frame.owners(ForkDepth.nat(fork),local,skip,grid,basis,palette,ground,q,s,0,0,q)

def Frame.selected(schedule: Schedule, skip: Bool, grid: Grid, basis: R.Basis, palette: Palette, ground: R.GroundLighting) -> Image:
	Schedule{+fork,assignment} = schedule
	match assignment:
		case Contiguous{}: Frame.fork(ForkDepth.nat(fork),skip,grid,basis,palette,ground,0,0,512)
		case Interleaved{}:
			Frame.interleaved(Schedule.dimensions(Schedule{fork,Interleaved{}}),fork,skip,grid,basis,palette,ground)

def Frame.image(+grid: Grid, +basis: R.Basis, +palette: Palette, +ground: R.GroundLighting, schedule: Schedule) -> Grid & Image:
	(grid,Frame.selected!(schedule,True{},grid,basis,palette,ground))
