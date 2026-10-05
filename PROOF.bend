import Base
import ./voxel.bend as V
import ./lighting.bend as L
import ./LAWS.bend as Laws
import ./material.bend as M
import ./render.bend as R

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
