import Base
import ./candidate-dda.bend as X
import ../../voxel.bend as V
import ../../material.bend as M
import ../../lighting.bend as L
import ../../render.bend as R

law material_foundation_id:
	{M.Material.id(M.Foundation{}) == 1 : U32}

law material_concrete_id:
	{M.Material.id(M.Concrete{}) == 2 : U32}

law material_frame_id:
	{M.Material.id(M.Frame{}) == 3 : U32}

law material_machinery_id:
	{M.Material.id(M.Machinery{}) == 4 : U32}

law material_read_id:
	for +material: M.Material
	{M.Material.read(M.Material.id(material)) == Some{material} : Maybe<&2, M.Material>}

law material_id_nonzero:
	for material: M.Material
	{U32.is_ne(M.Material.id(material), 0) == True{} : Bool}

law material_palette_lookup:
	for +palette: M.Palette
	for +material: M.Material
	for +light: M.Light
	{M.Palette.surface(palette, M.Material.id(material), light) == M.Palette.color(palette, material, light) : U32}

law erase_idempotent:
	for material: U32
	for hit: Bool
	{V.Cell.erase(V.Cell.erase(material, hit), hit) == V.Cell.erase(material, hit) : U32}

law erase_miss_preserves_material:
	for material: U32
	{V.Cell.erase(material, False{}) == material : U32}

law erase_hit_removes_material:
	for material: U32
	{V.Cell.erase(material, True{}) == 0 : U32}

law occupied_neighbor_hides_face:
	for solid: Bool
	{V.Face.exposed(solid, True{}) == False{} : Bool}

law empty_cell_has_no_face:
	for neighbor: Bool
	{V.Face.exposed(False{}, neighbor) == False{} : Bool}

law isolated_solid_has_face:
	{V.Face.exposed(True{}, False{}) == True{} : Bool}


law daylight_palette_lookup:
	for +palette: L.Palette
	for +material: M.Material
	for +direction: V.Direction
	{L.Palette.surface(palette, M.Material.id(material), direction) == L.Palette.color(palette, material, direction) : L.Ramp}

law unlit_color_preserved:
	for +color: U32
	for visible: U32
	{L.Ramp.color(L.Ramp.constant(color), visible) == color : U32}

law occluded_sun_sample:
	{L.Shadow.visible(True{}) == 0 : U32}

law clear_sun_sample:
	{L.Shadow.visible(False{}) == 1 : U32}

law material_plaster_id:
	{M.Material.id(M.Plaster{}) == 5 : U32}

law unit_face_projection_matches_rectangle:
	for +cell: V.Cell
	for +direction: V.Direction
	for +material: U32
	for +basis: R.Basis
	for +palette: L.Palette
	for +id: U32
	{R.Projected.of(V.Face{cell, direction, material}, basis, palette, id) == R.Projected.of(V.Rectangle{cell, direction, material, 1, 1}, basis, palette, id) : Maybe<&2, R.Projected>}

law illuminated_unit_face_projection_matches_rectangle:
	for +cell: V.Cell
	for +direction: V.Direction
	for +material: U32
	for +basis: R.Basis
	for +palette: L.Palette
	for +id: U32
	for +visibility: L.ColorField
	{R.Projected.illuminated(R.Illuminated{V.Face{cell, direction, material}, visibility}, basis, palette, id) == R.Projected.illuminated(R.Illuminated{V.Rectangle{cell, direction, material, 1, 1}, visibility}, basis, palette, id) : Maybe<&2, R.Projected>}

law pending_existing_preserved:
	for +hit: R.Hit
	{R.PendingHit.finish(R.Existing{hit}) == hit : R.Hit}

law pending_accept_preserves_hit:
	for +closer: Bool
	for +cell: V.Cell
	for +depth: F32
	for +color: L.Ramp
	for +visibility: L.ColorField
	for +u: F32
	for +v: F32
	for +edge: Bool
	for +id: U32
	for +direction: V.Direction
	for +old: R.PendingHit
	{R.PendingHit.finish(R.PendingHit.accept(closer, cell, depth, color, visibility, u, v, edge, id, direction, old)) == R.Hit.accept(closer, cell, depth, color, visibility, u, v, edge, id, direction, R.PendingHit.finish(old)) : R.Hit}

law pending_covered_preserves_hit:
	for +covered: Bool
	for +u: F32
	for +v: F32
	for +cell: V.Cell
	for +depth: F32
	for +color: L.Ramp
	for +visibility: L.ColorField
	for +id: U32
	for +direction: V.Direction
	for +outline: Bool
	for +old: R.PendingHit
	{R.PendingHit.finish(R.PendingHit.covered(covered, u, v, cell, depth, color, visibility, id, direction, outline, old)) == R.Hit.covered(covered, u, v, cell, depth, color, visibility, id, direction, outline, R.PendingHit.finish(old)) : R.Hit}

law pending_intersection_preserves_hit:
	for +nonparallel: Bool
	for +denom: F32
	for +plane: F32
	for +u_eye: F32
	for +v_eye: F32
	for +du: F32
	for +dv: F32
	for +near: F32
	for +cell: V.Cell
	for +color: L.Ramp
	for +visibility: L.ColorField
	for +id: U32
	for +direction: V.Direction
	for +width: F32
	for +height: F32
	for +outline: Bool
	for +old: R.PendingHit
	{R.PendingHit.finish(R.PendingHit.intersection(nonparallel, denom, plane, u_eye, v_eye, du, dv, near, cell, color, visibility, id, direction, width, height, outline, old)) == R.Hit.intersection(nonparallel, denom, plane, u_eye, v_eye, du, dv, near, cell, color, visibility, id, direction, width, height, outline, R.PendingHit.finish(old)) : R.Hit}

law pending_axes_preserves_hit:
	for +face: R.Projected
	for +axis: R.Vec3
	for +near: F32
	for +old: R.PendingHit
	{R.PendingHit.finish(R.PendingHit.axes(face, axis, near, old)) == R.Hit.axes(face, axis, near, R.PendingHit.finish(old)) : R.Hit}

law pending_face_preserves_hit:
	for +face: R.Projected
	for +ray: R.Vec3
	for +near: F32
	for +old: R.PendingHit
	{R.PendingHit.finish(R.PendingHit.face(face, ray, near, old)) == R.Hit.face(face, ray, near, R.PendingHit.finish(old)) : R.Hit}

law pending_scan_preserves_hit:
	for +faces: List<&2, R.Projected>
	for +ray: R.Vec3
	for +near: F32
	for +old: R.PendingHit
	{R.PendingHit.finish(R.PendingHit.scan(faces, ray, near, old)) == R.Pixel.eager(faces, ray, near, R.PendingHit.finish(old)) : R.Hit}

law final_lighting_preserves_hit:
	for +faces: List<&2, R.Projected>
	for +ray: R.Vec3
	for +near: F32
	for +hit: R.Hit
	{R.Pixel.hit(faces, ray, near, hit) == R.Pixel.eager(faces, ray, near, hit) : R.Hit}

law dda_uniform_material:
	for +material: U32
	for axis: X.Split
	for leftward: Bool
	for cell: V.Cell
	for span: V.Cell
	{X.Tree.read(X.Solid{material},axis,leftward,cell,span) == material : U32}

law dda_cached_daylight_preserved:
	for +sides: L.Sides
	for +direction: V.Direction
	{X.Sides.color(X.Sides.cached(sides),direction) == L.Ramp.color(L.Sides.surface(sides,direction),9) : U32}

law dda_outside_is_empty:
	for cells: X.Index
	for side: U32
	for cell: V.Cell
	{X.Grid.read.valid(False{},cells,side,cell) == 0 : U32}

law dda_disjoint_paint_preserves_grid:
	for fuel: Nat
	for covers: Bool
	for box: V.Cuboid
	for region: V.Cuboid
	for axis: U32
	for +tree: X.Tree
	{X.Tree.paint(fuel,False{},covers,box,region,axis,tree) == tree : X.Tree}

law dda_face_flip_involution:
	for +direction: V.Direction
	{X.Direction.flip(X.Direction.flip(direction)) == direction : V.Direction}

law dda_stationary_axis_never_crosses:
	for positive: Bool
	for origin: F32
	for delta: F32
	for cell: U32
	{X.Axis.next(False{},positive,origin,delta,cell) == 1.0e30 : F32}

law dda_uncrossed_coordinate_preserved:
	for positive: Bool
	for +cell: U32
	{X.Axis.step(False{},positive,cell) == cell : U32}

law dda_traversal_is_bounded:
	for inside: Bool
	for material: U32
	for previous: U32
	for grid: X.Grid
	for eye: R.Vec3
	for ray: R.Vec3
	for crossing: X.Crossing
	{X.Trace.walk(0n,inside,material,previous,grid,eye,ray,crossing) == None{} : Maybe<&2,X.SurfaceHit>}

law dda_region_material_preserved:
	for +tree: X.Tree
	for +axis: X.Split
	for +leftward: Bool
	for +cell: V.Cell
	for +span: V.Cell
	for low: V.Cell
	{X.Region.material(X.Tree.region(tree,axis,leftward,cell,span,low)) == X.Tree.read(tree,axis,leftward,cell,span) : U32}

law dda_region_outside_is_empty:
	for cells: X.Index
	for side: U32
	for cell: V.Cell
	{X.Region.material(X.Grid.region.valid(False{},cells,side,cell)) == 0 : U32}

law dda_stationary_region_axis_preserved:
	for positive: Bool
	for origin: F32
	for delta: F32
	for +cell: U32
	for time: F32
	for boundary_time: F32
	for low: U32
	for high: U32
	{X.Axis.advance(False{},positive,origin,delta,cell,time,boundary_time,low,high) == X.Advance{cell,cell,False{}} : X.Advance}

law dda_boundary_reuse_returns_limit:
	for positive: Bool
	for origin: F32
	for delta: F32
	for cell: U32
	for time: F32
	for +limit: U32
	{X.Axis.advance.count(True{},positive,origin,delta,cell,time,limit) == limit : U32}

law dda_boundary_fallback_uses_actual_count:
	for +positive: Bool
	for +origin: F32
	for +delta: F32
	for +cell: U32
	for +time: F32
	for +limit: U32
	{X.Axis.advance.count(False{},positive,origin,delta,cell,time,limit) == X.Axis.count(positive,origin,delta,cell,time,limit) : U32}

law dda_boundary_reuse_preserves_reconstruction_given_count_equality:
	for +positive: Bool
	for +origin: F32
	for +delta: F32
	for +cell: U32
	for +time: F32
	for +limit: U32
	for count_equality: {X.Axis.count(positive,origin,delta,cell,time,limit) == limit : U32}
	{X.Axis.advanced(positive,origin,delta,cell,time,X.Axis.advance.count(True{},positive,origin,delta,cell,time,limit)) == X.Axis.advanced(positive,origin,delta,cell,time,X.Axis.count(positive,origin,delta,cell,time,limit)) : X.Advance}

law dda_boundary_rejected_domain_uses_actual_count:
	for +positive: Bool
	for +origin: F32
	for +delta: F32
	for +cell: U32
	for +time: F32
	for +boundary_time: F32
	for +low: U32
	for +high: U32
	for rejected: {((low <= cell) && (cell < high) && (high <= 16777216) : U32) == False{} : Bool}
	{X.Axis.advance(True{},positive,origin,delta,cell,time,boundary_time,low,high) == X.Axis.advanced(positive,origin,delta,cell,time,X.Axis.count(positive,origin,delta,cell,time,Bool.pick(U32,positive,(high - cell : U32),(cell - low + 1 : U32)))) : X.Advance}

law dda_region_traversal_is_bounded:
	for inside: Bool
	for previous: U32
	for grid: X.Grid
	for eye: R.Vec3
	for ray: R.Vec3
	for crossing: X.Crossing
	for region: X.Region
	{X.Trace.regions(0n,inside,previous,grid,eye,ray,crossing,region) == None{} : Maybe<&2,X.SurfaceHit>}

law dda_zero_plane_events_are_accepted:
	for positive: Bool
	for origin: F32
	for delta: F32
	for cell: U32
	for time: F32
	{X.Axis.before(positive,origin,delta,cell,time,0) == True{} : Bool}

law dda_count_down_stops_at_accepted_plane:
	for fuel: Nat
	for at_limit: Bool
	for positive: Bool
	for origin: F32
	for delta: F32
	for cell: U32
	for time: F32
	for +count: U32
	for limit: U32
	{X.Axis.correct(1n+fuel,False{},True{},at_limit,positive,origin,delta,cell,time,count,limit) == count : U32}

law dda_count_up_rejects_first_late_plane:
	for fuel: Nat
	for at_limit: Bool
	for positive: Bool
	for origin: F32
	for delta: F32
	for cell: U32
	for time: F32
	for +count: U32
	for limit: U32
	{X.Axis.correct(1n+fuel,True{},False{},at_limit,positive,origin,delta,cell,time,count,limit) == (count - 1 : U32) : U32}

law dda_count_up_stops_at_accepted_limit:
	for fuel: Nat
	for positive: Bool
	for origin: F32
	for delta: F32
	for cell: U32
	for time: F32
	for +limit: U32
	{X.Axis.correct(1n+fuel,True{},True{},True{},positive,origin,delta,cell,time,limit,limit) == limit : U32}

law indexed_page_row_order:
	for +r00: X.Row
	for +r01: X.Row
	for +r02: X.Row
	for +r03: X.Row
	for +r04: X.Row
	for +r05: X.Row
	for +r06: X.Row
	for +r07: X.Row
	for +r08: X.Row
	for +r09: X.Row
	for +r10: X.Row
	for +r11: X.Row
	for +r12: X.Row
	for +r13: X.Row
	for +r14: X.Row
	for +r15: X.Row
	for +r16: X.Row
	for +r17: X.Row
	for +r18: X.Row
	for +r19: X.Row
	for +r20: X.Row
	for +r21: X.Row
	for +r22: X.Row
	for +r23: X.Row
	for +r24: X.Row
	for +r25: X.Row
	for +r26: X.Row
	for +r27: X.Row
	for +r28: X.Row
	for +r29: X.Row
	for +r30: X.Row
	for +slot: Nat
	{X.Page.row(slot,X.Pack.page([r00,r01,r03,r07,r15,r16,r08,r17,r18,r04,r09,r19,r20,r10,r21,r22,r02,r05,r11,r23,r24,r12,r25,r26,r06,r13,r27,r28,r14,r29,r30])) == Maybe.default(&2,X.Row,List.get(&2,X.Row,[r00,r01,r02,r03,r04,r05,r06,r07,r08,r09,r10,r11,r12,r13,r14,r15,r16,r17,r18,r19,r20,r21,r22,r23,r24,r25,r26,r27,r28,r29,r30],slot),X.RowPad{}) : X.Row}

law indexed_terminal_has_31_slots:
	for row: X.Row
	{List.length(&2,X.Row,X.Pack.terminal(4n,row)) == 31n : Nat}

law indexed_padding_is_canonical:
	for +depth: Nat
	{X.Pack.terminal(depth,X.RowPad{}) == X.Pack.pads(depth) : List<&2,X.Row>}

law indexed_solid_packing_preserves_counter_and_pages:
	for +material: U32
	for +depth: Nat
	for +slots: Nat
	for +next: Nat
	for +pages: List<&2,X.Table>
	{X.Pack.node(X.Solid{material},depth,slots,next,pages) == (X.Pack.terminal(slots,X.RowSolid{material}),(next,pages)) : List<&2,X.Row> & (Nat & List<&2,X.Table>)}

law indexed_child_slot_is_valid:
	for +slot: Nat
	for +leftward: Bool
	for valid: {Nat.is_lt(slot,15n) == True{} : Bool}
	{Nat.is_lt(X.Slot.child(slot,leftward),31n) == True{} : Bool}

law indexed_directory_single_page:
	for +fuel: Nat
	for +page: X.Table
	for +rest: List<&2,X.Table>
	{X.Pack.directory(fuel,1n,page <> rest) == (rest,page) : List<&2,X.Table> & X.Table}

law indexed_directory_two_pages:
	for +fuel: Nat
	for +left: X.Table
	for +right: X.Table
	for +rest: List<&2,X.Table>
	{X.Pack.directory(1n+fuel,2n,left <> right <> rest) == (rest,X.Directory{1n,left,right}) : List<&2,X.Table> & X.Table}

law indexed_directory_route:
	for +cut: Nat
	for +left: X.Table
	for +right: X.Table
	for +less: Bool
	for +id: Nat
	for +space: X.Space
	{X.Table.seek(X.Directory{cut,left,right},less,id,space) == Bool.pick(X.PageResult,less,X.Table.seek(left,X.Table.less(left,id),id,space),X.Table.seek(right,X.Table.less(right,Nat.sub(id,cut)),Nat.sub(id,cut),space)) : X.PageResult}

law indexed_solid_finishes_without_padding:
	for fuel: Nat
	for +material: U32
	for page: X.Table
	for slot: Nat
	for +space: X.Space
	{X.Page.walk(1n+fuel,X.RowSolid{material},page,slot,space) == X.Finished{X.Space.region(material,space)} : X.PageResult}

law indexed_link_preserves_space:
	for fuel: Nat
	for +target: Nat
	for page: X.Table
	for slot: Nat
	for +space: X.Space
	{X.Page.walk(1n+fuel,X.RowLink{target},page,slot,space) == X.Resume{target,space} : X.PageResult}

law indexed_link_decreases_fuel:
	for +fuel: Nat
	for +target: Nat
	for +space: X.Space
	for +table: X.Table
	{X.Index.region(1n+fuel,X.Resume{target,space},table) == X.Index.region(fuel,X.Table.seek(table,X.Table.less(table,target),target,space),table) : X.Region}

law indexed_split_preserves_full_region:
	for +left: X.Tree
	for +right: X.Tree
	for +axis: X.Split
	for +leftward: Bool
	for +cell: V.Cell
	for +span: V.Cell
	for +low: V.Cell
	{X.Tree.region(X.Branch{left,right},axis,leftward,cell,span,low) == X.Tree.space(Bool.pick(X.Tree,leftward,left,right),X.Space.step(X.Space{axis,leftward,cell,span,low})) : X.Region}

law indexed_uniform_inside_and_outside_full_region:
	for +inside: Bool
	for +material: U32
	for +side: U32
	for +cell: V.Cell
	{X.Grid.region.valid(inside,X.Index{0n,1n,X.Pack.page(X.Pack.terminal(4n,X.RowSolid{material}))},side,cell) == X.Tree.region.valid(inside,X.Solid{material},side,cell) : X.Region}

law indexed_uniform_grid_full_region:
	for +material: U32
	for +side: U32
	for +cell: V.Cell
	{X.Grid.region(X.Grid.pack(side,X.Solid{material}),cell) == X.Tree.region.valid(V.Cell.inside(side,cell),X.Solid{material},side,cell) : X.Region}

law indexed_single_split_page_full_region:
	for +a: U32
	for +b: U32
	for +axis: X.Split
	for +leftward: Bool
	for +cell: V.Cell
	for +span: V.Cell
	for +low: V.Cell
	{X.Page.walk(5n,X.RowSplit{},X.Pack.page(X.RowSplit{} <> List.append(&2,X.Row,X.Pack.terminal(3n,X.RowSolid{a}),X.Pack.terminal(3n,X.RowSolid{b}))),0n,X.Space{axis,leftward,cell,span,low}) == X.Finished{X.Tree.region(X.Branch{X.Solid{a},X.Solid{b}},axis,leftward,cell,span,low)} : X.PageResult}

law indexed_single_split_inside_and_outside_full_region:
	for +inside: Bool
	for +a: U32
	for +b: U32
	for +side: U32
	for +cell: V.Cell
	{X.Grid.region.valid(inside,X.Index{1n,1n,X.Pack.page(X.RowSplit{} <> List.append(&2,X.Row,X.Pack.terminal(3n,X.RowSolid{a}),X.Pack.terminal(3n,X.RowSolid{b})))},side,cell) == X.Tree.region.valid(inside,X.Branch{X.Solid{a},X.Solid{b}},side,cell) : X.Region}

law indexed_single_split_grid_full_region:
	for +a: U32
	for +b: U32
	for +side: U32
	for +cell: V.Cell
	{X.Grid.region(X.Grid.pack(side,X.Branch{X.Solid{a},X.Solid{b}}),cell) == X.Tree.region.valid(V.Cell.inside(side,cell),X.Branch{X.Solid{a},X.Solid{b}},side,cell) : X.Region}

law indexed_outside_full_sentinel:
	for cells: X.Index
	for side: U32
	for cell: V.Cell
	{X.Grid.region.valid(False{},cells,side,cell) == X.Region{0,V.Cell{0,0,0},V.Cell{0,0,0}} : X.Region}

law indexed_height_bounds_left:
	for +left: X.Tree
	for +right: X.Tree
	{Nat.is_ge(X.Tree.height(X.Branch{left,right}),1n+X.Tree.height(left)) == True{} : Bool}

law indexed_height_bounds_right:
	for +left: X.Tree
	for +right: X.Tree
	{Nat.is_ge(X.Tree.height(X.Branch{left,right}),1n+X.Tree.height(right)) == True{} : Bool}
