import Base
import ./dda.bend as X
import ./voxel.bend as V
import ./lighting.bend as L
import ./LAWS.bend as Laws
import ./material.bend as M
import ./render.bend as R
import ./scripts/dda_compare.bend as C
import ./scripts/dda_config.bend as K

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

def Laws.dda_fork_depth_bounded(depth):
	match depth:
		case X.F0{}: {==}
		case X.F1{}: {==}
		case X.F2{}: {==}
		case X.F3{}: {==}
		case X.F4{}: {==}
		case X.F5{}: {==}
		case X.F6{}: {==}
		case X.F7{}: {==}
		case X.F8{}: {==}
		case X.F9{}: {==}

def Laws.dda_schedule_dimensions_valid(depth,assignment):
	match depth:
		case X.F0{}: {==}
		case X.F1{}: {==}
		case X.F2{}: {==}
		case X.F3{}: {==}
		case X.F4{}: {==}
		case X.F5{}: {==}
		case X.F6{}: {==}
		case X.F7{}: {==}
		case X.F8{}: {==}
		case X.F9{}: {==}

def Laws.dda_schedule_depth_partition(depth):
	match depth:
		case X.F0{}: {==}
		case X.F1{}: {==}
		case X.F2{}: {==}
		case X.F3{}: {==}
		case X.F4{}: {==}
		case X.F5{}: {==}
		case X.F6{}: {==}
		case X.F7{}: {==}
		case X.F8{}: {==}
		case X.F9{}: {==}

def Laws.dda_schedule_dimensions_do_not_wrap(depth):
	match depth:
		case X.F0{}: {==}
		case X.F1{}: {==}
		case X.F2{}: {==}
		case X.F3{}: {==}
		case X.F4{}: {==}
		case X.F5{}: {==}
		case X.F6{}: {==}
		case X.F7{}: {==}
		case X.F8{}: {==}
		case X.F9{}: {==}

def Laws.dda_native_open_quadrants(a,b,c,d):
	{==}

def Laws.dda_weave_zero_left_inverse(a,b,c,d):
	{==}

def Laws.dda_weave_zero_right_inverse(a,b,c,d):
	{==}

def Laws.dda_weave_opened_recurrence(local,aa,ab,ac,ad,ba,bb,bc,bd,ca,cb,cc,cd,da,db,dc,dd):
	match local:
		case 0n: {==}
		case 1n+rest: {==}

def Laws.dda_contiguous_frame_is_reference(depth,skip,grid,basis,palette,ground):
	{==}

def Laws.dda_hit_image_is_pix(hit):
	match hit:
		case R.Hit{depth,color,id,cell,direction}: {==}

def Laws.dda_original_pixel_is_pix(skip,grid,basis,palette,ground,x,y):
	match basis:
		case R.Basis{eye,right,up,forward,focal,near}:
			Laws.dda_hit_image_is_pix(R.Pixel.shaded(X.Pixel.hit(X.Trace.mode(skip,grid,eye,R.Pixel.ray(R.Basis{eye,right,up,forward,focal,near},x,y),near),palette,R.Hit.background(x,y)),ground,R.Basis{eye,right,up,forward,focal,near},R.Pixel.ray(R.Basis{eye,right,up,forward,focal,near},x,y)))

def Laws.dda_draw_retains_scene(scene):
	match scene:
		case C.Dda{spec,schedule,skip,grid,basis,palette,ground}: {==}
		case C.Faces{spec,tile,fork,tiles,basis,ground}: {==}
		case C.Existing{spec,tile,fork,R.RenderScene{basis,tiles,count,cache}}: {==}

def Laws.dda_step_scan_does_not_invoke_assignment(draw):
	{==}

def Laws.dda_face_scan_does_not_invoke_assignment(draw,tile):
	{==}

def Laws.dda_measured_count_is_positive(predecessor):
	{==}

def Laws.dda_carved_cube_arguments_keep_both_flags(view):
	{==}

def Laws.dda_report_admission_rejects_missing(prefix,expected,valid):
	{==}

def Laws.dda_report_admission_rejects_multiple(prefix,expected,extra,valid):
	{==}

def Proof.transpose_cong(+a: X.Four, +b: X.Four, +c: X.Four, +d: X.Four, +e: X.Four, +f: X.Four, +g: X.Four, +h: X.Four,
	ae: {a == e : X.Four}, bf: {b == f : X.Four}, cg: {c == g : X.Four}, dh: {d == h : X.Four}) ->
	{X.Native.transpose(a,b,c,d) == X.Native.transpose(e,f,g,h) : X.Four}:
	%ae : {X.Native.transpose(a,b,c,d) == X.Native.transpose(_,f,g,h) : X.Four}
	%bf : {X.Native.transpose(a,b,c,d) == X.Native.transpose(a,_,g,h) : X.Four}
	%cg : {X.Native.transpose(a,b,c,d) == X.Native.transpose(a,b,_,h) : X.Four}
	%dh : {X.Native.transpose(a,b,c,d) == X.Native.transpose(a,b,c,_) : X.Four}
	{==}

def Proof.false_motive(value: Bool) -> Type:
	match value:
		case False{}: Unit
		case True{}: Empty

def Proof.false_true(evidence: {False{} == True{} : Bool}) -> Empty:
	%evidence : Proof.false_motive(_)
	Unit{}

def Proof.absurd(-A: Type, evidence: Empty) -> A:
	match evidence:

def Proof.all4_apply(-A: Type, +a: Bool, +b: Bool, +c: Bool, +d: Bool, complete: {(a && b && c && d) == True{} : Bool},
	conclude: {a == True{} : Bool} -> {b == True{} : Bool} -> {c == True{} : Bool} -> {d == True{} : Bool} -> A) -> A:
	match a b c d:
		case False{} _ _ _:
			Proof.absurd(A,Proof.false_true(complete))
		case True{} False{} _ _:
			Proof.absurd(A,Proof.false_true(complete))
		case True{} True{} False{} _:
			Proof.absurd(A,Proof.false_true(complete))
		case True{} True{} True{} False{}:
			Proof.absurd(A,Proof.false_true(complete))
		case True{} True{} True{} True{}:
			conclude({==})({==})({==})({==})

def Proof.all4_join(+a: Bool, +b: Bool, +c: Bool, +d: Bool,
	a_true: {a == True{} : Bool}, b_true: {b == True{} : Bool}, c_true: {c == True{} : Bool}, d_true: {d == True{} : Bool}) ->
	{(a && b && c && d) == True{} : Bool}:
	%Equal.sym(Bool,a,True{},a_true) : {(_ && b && c && d) == True{} : Bool}
	%Equal.sym(Bool,b,True{},b_true) : {(_ && c && d) == True{} : Bool}
	%Equal.sym(Bool,c,True{},c_true) : {(_ && d) == True{} : Bool}
	d_true

def Proof.qua_cong(+a: Image, +b: Image, +c: Image, +d: Image, +e: Image, +f: Image, +g: Image, +h: Image,
	ae: {a == e : Image}, bf: {b == f : Image}, cg: {c == g : Image}, dh: {d == h : Image}) ->
	{Qua{a,b,c,d} == Qua{e,f,g,h} : Image}:
	%ae : {Qua{a,b,c,d} == Qua{_,f,g,h} : Image}
	%bf : {Qua{a,b,c,d} == Qua{a,_,g,h} : Image}
	%cg : {Qua{a,b,c,d} == Qua{a,b,_,h} : Image}
	%dh : {Qua{a,b,c,d} == Qua{a,b,c,_} : Image}
	{==}

def Laws.dda_weave_transpose_recurrence(local,a,b,c,d):
	match a b c d:
		case X.Four{aa,ab,ac,ad} X.Four{ba,bb,bc,bd} X.Four{ca,cb,cc,cd} X.Four{da,db,dc,dd}:
			Laws.dda_weave_opened_recurrence(local,aa,ba,ca,da,ab,bb,cb,db,ac,bc,cc,dc,ad,bd,cd,dd)

def Laws.dda_weave_left_inverse_open(local,remaining,a,b,c,d,complete):
	match local a b c d:
		case 0n _ _ _ _:
			{==}
		case 1n+rest Pix{+color} +b +c +d:
			Proof.absurd({X.Native.unweave(1n+rest,X.Native.weave(1n+rest,X.Four{Pix{color},b,c,d})) == X.Four{Pix{color},b,c,d} : X.Four},Proof.false_true(complete))
		case 1n+rest +a Pix{+color} +c +d:
			Proof.all4_apply({X.Native.unweave(1n+rest,X.Native.weave(1n+rest,X.Four{a,Pix{color},c,d})) == X.Four{a,Pix{color},c,d} : X.Four},
				X.Native.full(Nat.add(1n+rest,remaining),a),X.Native.full(Nat.add(1n+rest,remaining),Pix{color}),X.Native.full(Nat.add(1n+rest,remaining),c),X.Native.full(Nat.add(1n+rest,remaining),d),complete,
				a_full => b_full => c_full => d_full => Proof.absurd({X.Native.unweave(1n+rest,X.Native.weave(1n+rest,X.Four{a,Pix{color},c,d})) == X.Four{a,Pix{color},c,d} : X.Four},Proof.false_true(b_full)))
		case 1n+rest +a +b Pix{+color} +d:
			Proof.all4_apply({X.Native.unweave(1n+rest,X.Native.weave(1n+rest,X.Four{a,b,Pix{color},d})) == X.Four{a,b,Pix{color},d} : X.Four},
				X.Native.full(Nat.add(1n+rest,remaining),a),X.Native.full(Nat.add(1n+rest,remaining),b),X.Native.full(Nat.add(1n+rest,remaining),Pix{color}),X.Native.full(Nat.add(1n+rest,remaining),d),complete,
				a_full => b_full => c_full => d_full => Proof.absurd({X.Native.unweave(1n+rest,X.Native.weave(1n+rest,X.Four{a,b,Pix{color},d})) == X.Four{a,b,Pix{color},d} : X.Four},Proof.false_true(c_full)))
		case 1n+rest +a +b +c Pix{+color}:
			Proof.all4_apply({X.Native.unweave(1n+rest,X.Native.weave(1n+rest,X.Four{a,b,c,Pix{color}})) == X.Four{a,b,c,Pix{color}} : X.Four},
				X.Native.full(Nat.add(1n+rest,remaining),a),X.Native.full(Nat.add(1n+rest,remaining),b),X.Native.full(Nat.add(1n+rest,remaining),c),X.Native.full(Nat.add(1n+rest,remaining),Pix{color}),complete,
				a_full => b_full => c_full => d_full => Proof.absurd({X.Native.unweave(1n+rest,X.Native.weave(1n+rest,X.Four{a,b,c,Pix{color}})) == X.Four{a,b,c,Pix{color}} : X.Four},Proof.false_true(d_full)))
		case 1n+rest Qua{+aa,+ab,+ac,+ad} Qua{+ba,+bb,+bc,+bd} Qua{+ca,+cb,+cc,+cd} Qua{+da,+db,+dc,+dd}:
			+depth = Nat.add(rest,remaining)
			-Goal = {X.Native.unweave(1n+rest,X.Native.weave(1n+rest,X.Four{Qua{aa,ab,ac,ad},Qua{ba,bb,bc,bd},Qua{ca,cb,cc,cd},Qua{da,db,dc,dd}})) == X.Four{Qua{aa,ab,ac,ad},Qua{ba,bb,bc,bd},Qua{ca,cb,cc,cd},Qua{da,db,dc,dd}} : X.Four}
			Proof.all4_apply(Goal,
				X.Native.full(1n+depth,Qua{aa,ab,ac,ad}),X.Native.full(1n+depth,Qua{ba,bb,bc,bd}),X.Native.full(1n+depth,Qua{ca,cb,cc,cd}),X.Native.full(1n+depth,Qua{da,db,dc,dd}),complete,
				a_full => b_full => c_full => d_full =>
				Proof.all4_apply(Goal,
					X.Native.full(depth,aa),X.Native.full(depth,ab),X.Native.full(depth,ac),X.Native.full(depth,ad),a_full,
					aa_full => ab_full => ac_full => ad_full =>
					Proof.all4_apply(Goal,
						X.Native.full(depth,ba),X.Native.full(depth,bb),X.Native.full(depth,bc),X.Native.full(depth,bd),b_full,
						ba_full => bb_full => bc_full => bd_full =>
						Proof.all4_apply(Goal,
							X.Native.full(depth,ca),X.Native.full(depth,cb),X.Native.full(depth,cc),X.Native.full(depth,cd),c_full,
							ca_full => cb_full => cc_full => cd_full =>
							Proof.all4_apply(Goal,
								X.Native.full(depth,da),X.Native.full(depth,db),X.Native.full(depth,dc),X.Native.full(depth,dd),d_full,
								da_full => db_full => dc_full => dd_full =>
								Equal.trans(X.Four,
									X.Native.unweave(1n+rest,X.Native.weave.opened(rest,X.Four{aa,ab,ac,ad},X.Four{ba,bb,bc,bd},X.Four{ca,cb,cc,cd},X.Four{da,db,dc,dd})),
									X.Native.transpose(X.Native.unweave(rest,X.Native.weave(rest,X.Four{aa,ba,ca,da})),X.Native.unweave(rest,X.Native.weave(rest,X.Four{ab,bb,cb,db})),X.Native.unweave(rest,X.Native.weave(rest,X.Four{ac,bc,cc,dc})),X.Native.unweave(rest,X.Native.weave(rest,X.Four{ad,bd,cd,dd}))),
									X.Four{Qua{aa,ab,ac,ad},Qua{ba,bb,bc,bd},Qua{ca,cb,cc,cd},Qua{da,db,dc,dd}},
									Equal.cong(Image,X.Four,image => X.Native.unweave(1n+rest,image),X.Native.weave.opened(rest,X.Four{aa,ab,ac,ad},X.Four{ba,bb,bc,bd},X.Four{ca,cb,cc,cd},X.Four{da,db,dc,dd}),Qua{X.Native.weave(rest,X.Four{aa,ba,ca,da}),X.Native.weave(rest,X.Four{ab,bb,cb,db}),X.Native.weave(rest,X.Four{ac,bc,cc,dc}),X.Native.weave(rest,X.Four{ad,bd,cd,dd})},Laws.dda_weave_opened_recurrence(rest,aa,ab,ac,ad,ba,bb,bc,bd,ca,cb,cc,cd,da,db,dc,dd)),
									Proof.transpose_cong(X.Native.unweave(rest,X.Native.weave(rest,X.Four{aa,ba,ca,da})),X.Native.unweave(rest,X.Native.weave(rest,X.Four{ab,bb,cb,db})),X.Native.unweave(rest,X.Native.weave(rest,X.Four{ac,bc,cc,dc})),X.Native.unweave(rest,X.Native.weave(rest,X.Four{ad,bd,cd,dd})),X.Four{aa,ba,ca,da},X.Four{ab,bb,cb,db},X.Four{ac,bc,cc,dc},X.Four{ad,bd,cd,dd},
										Laws.dda_weave_left_inverse_open(rest,remaining,aa,ba,ca,da,Proof.all4_join(X.Native.full(depth,aa),X.Native.full(depth,ba),X.Native.full(depth,ca),X.Native.full(depth,da),aa_full,ba_full,ca_full,da_full)),
										Laws.dda_weave_left_inverse_open(rest,remaining,ab,bb,cb,db,Proof.all4_join(X.Native.full(depth,ab),X.Native.full(depth,bb),X.Native.full(depth,cb),X.Native.full(depth,db),ab_full,bb_full,cb_full,db_full)),
										Laws.dda_weave_left_inverse_open(rest,remaining,ac,bc,cc,dc,Proof.all4_join(X.Native.full(depth,ac),X.Native.full(depth,bc),X.Native.full(depth,cc),X.Native.full(depth,dc),ac_full,bc_full,cc_full,dc_full)),
										Laws.dda_weave_left_inverse_open(rest,remaining,ad,bd,cd,dd,Proof.all4_join(X.Native.full(depth,ad),X.Native.full(depth,bd),X.Native.full(depth,cd),X.Native.full(depth,dd),ad_full,bd_full,cd_full,dd_full)))))))))


def Laws.dda_weave_right_inverse_open(local,remaining,image,complete):
	match local image:
		case 0n Pix{color}:
			Proof.absurd({X.Native.weave(0n,X.Native.unweave(0n,Pix{color})) == Pix{color} : Image},Proof.false_true(complete))
		case 0n Qua{a,b,c,d}:
			{==}
		case 1n+rest Pix{color}:
			Proof.absurd({X.Native.weave(1n+rest,X.Native.unweave(1n+rest,Pix{color})) == Pix{color} : Image},Proof.false_true(complete))
		case 1n+rest Qua{+a,+b,+c,+d}:
			+tail = remaining
			Proof.all4_apply({X.Native.weave(1n+rest,X.Native.unweave(1n+rest,Qua{a,b,c,d})) == Qua{a,b,c,d} : Image},
				X.Native.full(Nat.add(rest,1n+tail),a),X.Native.full(Nat.add(rest,1n+tail),b),X.Native.full(Nat.add(rest,1n+tail),c),X.Native.full(Nat.add(rest,1n+tail),d),complete,
				a_full => b_full => c_full => d_full => Equal.trans(Image,
					X.Native.weave(1n+rest,X.Native.unweave(1n+rest,Qua{a,b,c,d})),
					Qua{X.Native.weave(rest,X.Native.unweave(rest,a)),X.Native.weave(rest,X.Native.unweave(rest,b)),X.Native.weave(rest,X.Native.unweave(rest,c)),X.Native.weave(rest,X.Native.unweave(rest,d))},
					Qua{a,b,c,d},
					Laws.dda_weave_transpose_recurrence(rest,X.Native.unweave(rest,a),X.Native.unweave(rest,b),X.Native.unweave(rest,c),X.Native.unweave(rest,d)),
					Proof.qua_cong(X.Native.weave(rest,X.Native.unweave(rest,a)),X.Native.weave(rest,X.Native.unweave(rest,b)),X.Native.weave(rest,X.Native.unweave(rest,c)),X.Native.weave(rest,X.Native.unweave(rest,d)),a,b,c,d,
						Laws.dda_weave_right_inverse_open(rest,tail,a,a_full),Laws.dda_weave_right_inverse_open(rest,tail,b,b_full),Laws.dda_weave_right_inverse_open(rest,tail,c,c_full),Laws.dda_weave_right_inverse_open(rest,tail,d,d_full))))
