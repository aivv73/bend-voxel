import Base
import ./src/exterior.bend as Exterior
import ./src/geometry-laws.bend as GeometryLaws
import ./LAWS.bend as Laws


def Laws.voxel_full_material_word(material):
  {==}
def Laws.voxel_high_material_bits():
  {==}
def Laws.voxel_rgb_direction_bytes():
  {==}
def Laws.voxel_all_direction_codes():
  {==}
def Laws.voxel_empty_face_count():
  {==}
def Laws.voxel_face_count_step(face,faces,n):
  {==}
def Laws.voxel_face_count_limit(face):
  {==}
def Laws.voxel_quad_index_pattern(base):
  {==}
def Laws.voxel_max_fixture_index():
  {==}
def Laws.voxel_quad_outward():
  {==}

def Laws.voxel_second_triangle_outward():
  {==}

def Laws.voxel_all_8cube_indices_bounded():
  {==}

def Laws.exterior_subtract_center_four_disjoint_pieces():
  {==}

def Laws.exterior_subtract_touching_unchanged():
  {==}

def Laws.exterior_subtract_contains_empty():
  {==}

def Laws.exterior_rectangle_preserves_full_material(normal,d,m,r):
  match r:
    case Exterior.Rect2{u0,u1,v0,v1}:
      {==}

def Laws.exterior_rectangle_preserves_direction(normal,d,m,r):
  match r:
    case Exterior.Rect2{u0,u1,v0,v1}:
      {==}

def Laws.exterior_indices_preserve_order(base):
  {==}

def Laws.exterior_coordinate_bound_exact():
  {==}

def Laws.exterior_coordinate_bound_rejects_next():
  {==}

def Laws.exterior_count_limit_accepts_exact():
  {==}

def Laws.exterior_count_limit_rejects_next():
  {==}

def Laws.exterior_count_limit_rejects_wrapping_product():
  {==}

def Laws.exterior_capacity_bytes_keep_high_limb():
  {==}

def Laws.exterior_asymmetric_first_normals():
  {==}

def Laws.exterior_asymmetric_second_normals():
  {==}

def Laws.exterior_overlap_rejected_with_sources():
  {==}
def Laws.exterior_clipping_preserves_every_material(rs,normal,d,m,old):
  match rs:
    case Nil{}: {==}
    case Exterior.Rect2{a,b,c,e} <> rest:
      %Laws.exterior_clipping_preserves_every_material(rest,normal,d,m,old) : {m <> GeometryLaws.materials(Exterior.lift(rest,Exterior.Patch{normal,d,m,old})) == m <> _ : List<U32>}
      {==}


def Laws.appearance_payload_bytes():
  {==}

def Laws.appearance_payload_words():
  {==}

def Laws.appearance_selected_offset():
  {==}

def Laws.appearance_ring_index_count():
  {==}


def Laws.chunk_region_boundary():
  {==}

def Laws.chunk_huge_source_stays_analytic():
  {==}

def Laws.chunk_dirty_neighbor_boundary():
  {==}

def Laws.chunk_low_boundary_clamped():
  {==}

def Laws.chunk_full_source_tuple_required():
  {==}

def Laws.greedy_exact_shared_edge():
  {==}

def Laws.greedy_material_boundary():
  {==}

def Laws.greedy_plane_boundary():
  {==}

def Laws.greedy_gap_rejected():
  {==}

def Laws.greedy_four_tiles_one_rectangle():
  {==}

def Laws.chunk_runs_merge_only_adjacent_local_ranges():
  {==}

def Laws.retirement_keeps_exact_key_and_version():
  {==}

def Laws.retirement_selects_changed_and_removed():
  {==}

def Laws.retirement_equal_version_different_key_is_obsolete():
  {==}

def Laws.retirement_empty_has_no_allocations():
  {==}
