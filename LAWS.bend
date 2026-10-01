import Base
import ./voxel.bend as V

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
