import Base
import ./candidate-dda.bend as X
import ../../voxel.bend as V
import ../../lighting.bend as L
import ./LAWS.bend as Laws
import ../../material.bend as M
import ../../render.bend as R

def Laws.material_foundation_id():
	{==}

def Laws.material_concrete_id():
	{==}

def Laws.material_frame_id():
	{==}

def Laws.material_machinery_id():
	{==}

def Laws.material_read_id(material):
	match material:
		case M.Foundation{}:
			{==}
		case M.Concrete{}:
			{==}
		case M.Frame{}:
			{==}
		case M.Machinery{}:
			{==}
		case M.Plaster{}:
			{==}

def Laws.material_id_nonzero(material):
	match material:
		case M.Foundation{}:
			{==}
		case M.Concrete{}:
			{==}
		case M.Frame{}:
			{==}
		case M.Machinery{}:
			{==}
		case M.Plaster{}:
			{==}

def Laws.material_palette_lookup(palette, material, light):
	match material:
		case M.Foundation{}:
			{==}
		case M.Concrete{}:
			{==}
		case M.Frame{}:
			{==}
		case M.Machinery{}:
			{==}
		case M.Plaster{}:
			{==}

def Laws.erase_idempotent(material, hit):
	match hit:
		case True{}:
			{==}
		case False{}:
			{==}

def Laws.erase_miss_preserves_material(material):
	{==}

def Laws.erase_hit_removes_material(material):
	{==}

def Laws.occupied_neighbor_hides_face(solid):
	match solid:
		case True{}:
			{==}
		case False{}:
			{==}

def Laws.empty_cell_has_no_face(neighbor):
	{==}

def Laws.isolated_solid_has_face():
	{==}


def Laws.daylight_palette_lookup(palette, material, direction):
	match material:
		case M.Foundation{}:
			{==}
		case M.Concrete{}:
			{==}
		case M.Frame{}:
			{==}
		case M.Machinery{}:
			{==}
		case M.Plaster{}:
			{==}

def Laws.unlit_color_preserved(color, visible):
	{==}

def Laws.occluded_sun_sample():
	{==}

def Laws.clear_sun_sample():
	{==}

def Laws.material_plaster_id():
	{==}

def Laws.unit_face_projection_matches_rectangle(cell, direction, material, basis, palette, id):
	match basis:
		case R.Basis{eye, right, up, forward, focal, near}:
			{==}

def Laws.illuminated_unit_face_projection_matches_rectangle(cell, direction, material, basis, palette, id, visibility):
	match basis:
		case R.Basis{eye, right, up, forward, focal, near}:
			{==}

def Laws.pending_existing_preserved(hit):
	{==}

def Laws.pending_accept_preserves_hit(closer, cell, depth, color, visibility, u, v, edge, id, direction, old):
	match closer:
		case False{}: {==}
		case True{}: {==}

def Laws.pending_covered_preserves_hit(covered, u, v, cell, depth, color, visibility, id, direction, outline, old):
	match covered:
		case False{}: {==}
		case True{}:
			match old:
				case R.Existing{R.Hit{previous, old_color, old_id, old_cell, old_direction}}:
					Laws.pending_accept_preserves_hit(R.Hit.closer(old_cell, depth, previous, id, old_id), cell, depth, color, visibility, u, v, outline && ((u < 0.0225) || (v < 0.0225) || (u > 0.9775) || (v > 0.9775) : F32), id, direction, R.Existing{R.Hit{previous, old_color, old_id, old_cell, old_direction}})
				case R.Selected{previous, old_id, old_cell, old_direction, ramp, field, old_u, old_v, edge}:
					Laws.pending_accept_preserves_hit(R.Hit.closer(Some{old_cell}, depth, previous, id, old_id), cell, depth, color, visibility, u, v, outline && ((u < 0.0225) || (v < 0.0225) || (u > 0.9775) || (v > 0.9775) : F32), id, direction, R.Selected{previous, old_id, old_cell, old_direction, ramp, field, old_u, old_v, edge})

def Laws.pending_intersection_preserves_hit(nonparallel, denom, plane, u_eye, v_eye, du, dv, near, cell, color, visibility, id, direction, width, height, outline, old):
	match nonparallel:
		case False{}: {==}
		case True{}:
			+t = (plane / denom : F32)
			+u = ((u_eye + t * du) / width : F32)
			+v = ((v_eye + t * dv) / height : F32)
			Laws.pending_covered_preserves_hit((F32.is_eq((t - t : F32), 0.0) && ((t >= near) && (u >= 0.0) && (u <= 1.0) && (v >= 0.0) && (v <= 1.0) : F32)), u, v, R.Face.sample_cell(direction, cell, (u * width : F32), (v * height : F32), width, height), t, color, visibility, id, direction, outline, old)

def Laws.pending_axes_preserves_hit(face, axis, near, old):
	R.Projected{cell, direction, plane, u_eye, v_eye, color, visibility, id, bounds, width, height, outline} = face
	R.Vec3{denom, du, dv} = axis
	Laws.pending_intersection_preserves_hit(F32.is_ne(denom, 0.0), denom, plane, u_eye, v_eye, du, dv, near, cell, color, visibility, id, direction, width, height, outline, old)

def Laws.pending_face_preserves_hit(face, ray, near, old):
	R.Projected{cell, direction, plane, u_eye, v_eye, color, visibility, id, bounds, width, height, outline} = face
	Laws.pending_axes_preserves_hit(R.Projected{cell, direction, plane, u_eye, v_eye, color, visibility, id, bounds, width, height, outline}, R.Face.axes(direction, ray), near, old)

def Laws.pending_scan_preserves_hit(faces, ray, near, old):
	match faces:
		case Nil{}: {==}
		case Con{face, rest}:
			Equal.trans(R.Hit,
				R.PendingHit.finish(R.PendingHit.scan(rest, ray, near, R.PendingHit.face(face, ray, near, old))),
				R.Pixel.eager(rest, ray, near, R.PendingHit.finish(R.PendingHit.face(face, ray, near, old))),
				R.Pixel.eager(rest, ray, near, R.Hit.face(face, ray, near, R.PendingHit.finish(old))),
				Laws.pending_scan_preserves_hit(rest, ray, near, R.PendingHit.face(face, ray, near, old)),
				Equal.cong(R.Hit, R.Hit, hit => R.Pixel.eager(rest, ray, near, hit),
					R.PendingHit.finish(R.PendingHit.face(face, ray, near, old)),
					R.Hit.face(face, ray, near, R.PendingHit.finish(old)),
					Laws.pending_face_preserves_hit(face, ray, near, old)))

def Laws.final_lighting_preserves_hit(faces, ray, near, hit):
	Laws.pending_scan_preserves_hit(faces, ray, near, R.Existing{hit})

def Laws.dda_uniform_material(material,axis,leftward,cell,span):
	{==}

def Laws.dda_cached_daylight_preserved(sides,direction):
	match sides direction:
		case L.Sides{nx,px,ny,py,nz,pz} V.NegX{}: {==}
		case L.Sides{nx,px,ny,py,nz,pz} V.PosX{}: {==}
		case L.Sides{nx,px,ny,py,nz,pz} V.NegY{}: {==}
		case L.Sides{nx,px,ny,py,nz,pz} V.PosY{}: {==}
		case L.Sides{nx,px,ny,py,nz,pz} V.NegZ{}: {==}
		case L.Sides{nx,px,ny,py,nz,pz} V.PosZ{}: {==}

def Laws.dda_outside_is_empty(cells,side,cell):
	{==}

def Laws.dda_disjoint_paint_preserves_grid(fuel,covers,box,region,axis,tree):
	match fuel:
		case 0n: {==}
		case 1n+rest: {==}

def Laws.dda_face_flip_involution(direction):
	match direction:
		case V.NegX{}: {==}
		case V.PosX{}: {==}
		case V.NegY{}: {==}
		case V.PosY{}: {==}
		case V.NegZ{}: {==}
		case V.PosZ{}: {==}

def Laws.dda_stationary_axis_never_crosses(positive,origin,delta,cell):
	{==}

def Laws.dda_uncrossed_coordinate_preserved(positive,cell):
	match positive:
		case True{}: {==}
		case False{}: {==}

def Laws.dda_traversal_is_bounded(inside,material,previous,grid,eye,ray,crossing):
	{==}

def Laws.dda_region_material_preserved(tree,axis,leftward,cell,span,low):
	match tree axis leftward cell span low:
		case X.Solid{material} _ _ _ V.Cell{sx,sy,sz} V.Cell{lx,ly,lz}: {==}
		case X.Branch{left,right} X.SplitX{} True{} V.Cell{x,y,z} V.Cell{sx,sy,sz} low:
			Laws.dda_region_material_preserved(left,X.SplitY{},(y < sy / 2 : U32),V.Cell{x,y,z},V.Cell{(sx / 2 : U32),sy,sz},low)
		case X.Branch{left,right} X.SplitX{} False{} V.Cell{x,y,z} V.Cell{sx,sy,sz} V.Cell{lx,ly,lz}:
			Laws.dda_region_material_preserved(right,X.SplitY{},(y < sy / 2 : U32),V.Cell{(x - sx / 2 : U32),y,z},V.Cell{(sx / 2 : U32),sy,sz},V.Cell{(lx + sx / 2 : U32),ly,lz})
		case X.Branch{left,right} X.SplitY{} True{} V.Cell{x,y,z} V.Cell{sx,sy,sz} low:
			Laws.dda_region_material_preserved(left,X.SplitZ{},(z < sz / 2 : U32),V.Cell{x,y,z},V.Cell{sx,(sy / 2 : U32),sz},low)
		case X.Branch{left,right} X.SplitY{} False{} V.Cell{x,y,z} V.Cell{sx,sy,sz} V.Cell{lx,ly,lz}:
			Laws.dda_region_material_preserved(right,X.SplitZ{},(z < sz / 2 : U32),V.Cell{x,(y - sy / 2 : U32),z},V.Cell{sx,(sy / 2 : U32),sz},V.Cell{lx,(ly + sy / 2 : U32),lz})
		case X.Branch{left,right} X.SplitZ{} True{} V.Cell{x,y,z} V.Cell{sx,sy,sz} low:
			Laws.dda_region_material_preserved(left,X.SplitX{},(x < sx / 2 : U32),V.Cell{x,y,z},V.Cell{sx,sy,(sz / 2 : U32)},low)
		case X.Branch{left,right} X.SplitZ{} False{} V.Cell{x,y,z} V.Cell{sx,sy,sz} V.Cell{lx,ly,lz}:
			Laws.dda_region_material_preserved(right,X.SplitX{},(x < sx / 2 : U32),V.Cell{x,y,(z - sz / 2 : U32)},V.Cell{sx,sy,(sz / 2 : U32)},V.Cell{lx,ly,(lz + sz / 2 : U32)})

def Laws.dda_region_outside_is_empty(cells,side,cell):
	{==}

def Laws.dda_stationary_region_axis_preserved(positive,origin,delta,cell,time,boundary_time,low,high):
	{==}

def Laws.dda_boundary_reuse_returns_limit(positive,origin,delta,cell,time,limit):
	{==}

def Laws.dda_boundary_fallback_uses_actual_count(positive,origin,delta,cell,time,limit):
	{==}

def Laws.dda_boundary_reuse_preserves_reconstruction_given_count_equality(positive,origin,delta,cell,time,limit,count_equality):
	%count_equality : {X.Axis.advanced(positive,origin,delta,cell,time,_) == X.Axis.advanced(positive,origin,delta,cell,time,X.Axis.count(positive,origin,delta,cell,time,limit)) : X.Advance}
	{==}

def Laws.dda_boundary_rejected_domain_uses_actual_count(positive,origin,delta,cell,time,boundary_time,low,high,rejected):
	Equal.cong(Bool,X.Advance,reuse => X.Axis.advanced(positive,origin,delta,cell,time,X.Axis.advance.count(reuse && F32.is_eq(time,boundary_time),positive,origin,delta,cell,time,Bool.pick(U32,positive,(high - cell : U32),(cell - low + 1 : U32)))),
		((low <= cell) && (cell < high) && (high <= 16777216) : U32),False{},rejected)

def Laws.dda_region_traversal_is_bounded(inside,previous,grid,eye,ray,crossing,region):
	{==}

def Laws.dda_zero_plane_events_are_accepted(positive,origin,delta,cell,time):
	{==}

def Laws.dda_count_down_stops_at_accepted_plane(fuel,at_limit,positive,origin,delta,cell,time,count,limit):
	{==}

def Laws.dda_count_up_rejects_first_late_plane(fuel,at_limit,positive,origin,delta,cell,time,count,limit):
	{==}

def Laws.dda_count_up_stops_at_accepted_limit(fuel,positive,origin,delta,cell,time,limit):
	{==}

def Laws.indexed_page_row_order(r00,r01,r02,r03,r04,r05,r06,r07,r08,r09,r10,r11,r12,r13,r14,r15,r16,r17,r18,r19,r20,r21,r22,r23,r24,r25,r26,r27,r28,r29,r30,slot):
	match slot:
		case 0n: {==}
		case 1n: {==}
		case 2n: {==}
		case 3n: {==}
		case 4n: {==}
		case 5n: {==}
		case 6n: {==}
		case 7n: {==}
		case 8n: {==}
		case 9n: {==}
		case 10n: {==}
		case 11n: {==}
		case 12n: {==}
		case 13n: {==}
		case 14n: {==}
		case 15n: {==}
		case 16n: {==}
		case 17n: {==}
		case 18n: {==}
		case 19n: {==}
		case 20n: {==}
		case 21n: {==}
		case 22n: {==}
		case 23n: {==}
		case 24n: {==}
		case 25n: {==}
		case 26n: {==}
		case 27n: {==}
		case 28n: {==}
		case 29n: {==}
		case 30n: {==}
		case 31n+rest: {==}

def Laws.indexed_terminal_has_31_slots(row):
	{==}

def Laws.indexed_padding_is_canonical(depth):
	match depth:
		case 0n: {==}
		case 1n+rest: {==}

def Laws.indexed_solid_packing_preserves_counter_and_pages(material,depth,slots,next,pages):
	{==}

def True_only(value: Bool) -> Type:
	match value:
		case False{}: Empty
		case True{}: Unit

def False_is_not_true(e: {False{} == True{} : Bool}) -> Empty:
	%Equal.sym(Bool,False{},True{},e) : True_only(_)
	Unit{}

def Laws.indexed_child_slot_is_valid(slot,leftward,valid):
	match slot leftward:
		case 0n True{}: {==}
		case 0n False{}: {==}
		case 1n True{}: {==}
		case 1n False{}: {==}
		case 2n True{}: {==}
		case 2n False{}: {==}
		case 3n True{}: {==}
		case 3n False{}: {==}
		case 4n True{}: {==}
		case 4n False{}: {==}
		case 5n True{}: {==}
		case 5n False{}: {==}
		case 6n True{}: {==}
		case 6n False{}: {==}
		case 7n True{}: {==}
		case 7n False{}: {==}
		case 8n True{}: {==}
		case 8n False{}: {==}
		case 9n True{}: {==}
		case 9n False{}: {==}
		case 10n True{}: {==}
		case 10n False{}: {==}
		case 11n True{}: {==}
		case 11n False{}: {==}
		case 12n True{}: {==}
		case 12n False{}: {==}
		case 13n True{}: {==}
		case 13n False{}: {==}
		case 14n True{}: {==}
		case 14n False{}: {==}
		case 15n _:
			Empty.absurd({Nat.is_lt(X.Slot.child(slot,leftward),31n) == True{} : Bool},False_is_not_true(valid))
		case 16n+rest _:
			Empty.absurd({Nat.is_lt(X.Slot.child(slot,leftward),31n) == True{} : Bool},False_is_not_true(valid))

def Laws.indexed_directory_single_page(fuel,page,rest):
	match fuel:
		case 0n: {==}
		case 1n+more: {==}

def Laws.indexed_directory_two_pages(fuel,left,right,rest):
	match fuel:
		case 0n: {==}
		case 1n+more: {==}

def Laws.indexed_directory_route(cut,left,right,less,id,space):
	match less:
		case False{}: {==}
		case True{}: {==}

def Laws.indexed_solid_finishes_without_padding(fuel,material,page,slot,space):
	{==}

def Laws.indexed_link_preserves_space(fuel,target,page,slot,space):
	{==}

def Laws.indexed_link_decreases_fuel(fuel,target,space,table):
	{==}

def Laws.indexed_split_preserves_full_region(left,right,axis,leftward,cell,span,low):
	match axis leftward cell span low:
		case X.SplitX{} True{} V.Cell{x,y,z} V.Cell{sx,sy,sz} V.Cell{lx,ly,lz}:
			{==}
		case X.SplitX{} False{} V.Cell{x,y,z} V.Cell{sx,sy,sz} V.Cell{lx,ly,lz}:
			{==}
		case X.SplitY{} True{} V.Cell{x,y,z} V.Cell{sx,sy,sz} V.Cell{lx,ly,lz}:
			{==}
		case X.SplitY{} False{} V.Cell{x,y,z} V.Cell{sx,sy,sz} V.Cell{lx,ly,lz}:
			{==}
		case X.SplitZ{} True{} V.Cell{x,y,z} V.Cell{sx,sy,sz} V.Cell{lx,ly,lz}:
			{==}
		case X.SplitZ{} False{} V.Cell{x,y,z} V.Cell{sx,sy,sz} V.Cell{lx,ly,lz}:
			{==}

def Laws.indexed_uniform_inside_and_outside_full_region(inside,material,side,cell):
	match inside cell:
		case False{} _: {==}
		case True{} V.Cell{x,y,z}: {==}

def Laws.indexed_uniform_grid_full_region(material,side,cell):
	Laws.indexed_uniform_inside_and_outside_full_region(V.Cell.inside(side,cell),material,side,cell)

def Laws.indexed_single_split_page_full_region(a,b,axis,leftward,cell,span,low):
	match axis leftward cell span low:
		case X.SplitX{} True{} V.Cell{x,y,z} V.Cell{sx,sy,sz} V.Cell{lx,ly,lz}:
			{==}
		case X.SplitX{} False{} V.Cell{x,y,z} V.Cell{sx,sy,sz} V.Cell{lx,ly,lz}:
			{==}
		case X.SplitY{} True{} V.Cell{x,y,z} V.Cell{sx,sy,sz} V.Cell{lx,ly,lz}:
			{==}
		case X.SplitY{} False{} V.Cell{x,y,z} V.Cell{sx,sy,sz} V.Cell{lx,ly,lz}:
			{==}
		case X.SplitZ{} True{} V.Cell{x,y,z} V.Cell{sx,sy,sz} V.Cell{lx,ly,lz}:
			{==}
		case X.SplitZ{} False{} V.Cell{x,y,z} V.Cell{sx,sy,sz} V.Cell{lx,ly,lz}:
			{==}

def Laws.indexed_single_split_inside_and_outside_full_region(inside,a,b,side,cell):
	match inside cell:
		case False{} _: {==}
		case True{} V.Cell{x,y,z}:
			Equal.cong(X.PageResult,X.Region,result => X.Index.region(2n,result,X.Pack.page(X.RowSplit{} <> List.append(&2,X.Row,X.Pack.terminal(3n,X.RowSolid{a}),X.Pack.terminal(3n,X.RowSolid{b})))),
				X.Page.walk(5n,X.RowSplit{},X.Pack.page(X.RowSplit{} <> List.append(&2,X.Row,X.Pack.terminal(3n,X.RowSolid{a}),X.Pack.terminal(3n,X.RowSolid{b}))),0n,X.Space{X.SplitX{},(x < side / 2 : U32),cell,V.Cell{side,side,side},V.Cell{0,0,0}}),
				X.Finished{X.Tree.region(X.Branch{X.Solid{a},X.Solid{b}},X.SplitX{},(x < side / 2 : U32),cell,V.Cell{side,side,side},V.Cell{0,0,0})},
				Laws.indexed_single_split_page_full_region(a,b,X.SplitX{},(x < side / 2 : U32),cell,V.Cell{side,side,side},V.Cell{0,0,0}))

def Laws.indexed_single_split_grid_full_region(a,b,side,cell):
	Laws.indexed_single_split_inside_and_outside_full_region(V.Cell.inside(side,cell),a,b,side,cell)

def Laws.indexed_outside_full_sentinel(cells,side,cell):
	{==}

def Laws.indexed_height_bounds_left(left,right):
	Nat.max_ge_l(X.Tree.height(left),X.Tree.height(right))

def Laws.indexed_height_bounds_right(left,right):
	Nat.max_ge_r(X.Tree.height(left),X.Tree.height(right))
