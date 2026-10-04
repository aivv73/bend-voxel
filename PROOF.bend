import ./LAWS.bend as Laws
import ./material.bend as M

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
