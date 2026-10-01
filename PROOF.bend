import ./LAWS.bend as Laws

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
