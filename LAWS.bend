import Base
import ./voxel.bend as V
import ./material.bend as M
import ./lighting.bend as L
import ./render.bend as R

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
