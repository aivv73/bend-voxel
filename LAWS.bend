import Base
import ./voxel.bend as V
import ./material.bend as M
import ./lighting.bend as L

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
