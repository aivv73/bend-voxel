import Base
import ./src/residency.bend as Residency
import ./src/chunks.bend as Chunks
import ./src/greedy.bend as Greedy
import ./src/appearance.bend as Appearance
import ./shaders/appearance_uniforms.bend as Uniform
import ./src/geometry-laws.bend as GeometryLaws
import ../deps/bend-vulkan/deps/bend-collections/src/math/u64.bend as W
import ./src/mesh.bend as Mesh
import ./src/geometry.bend as Geometry
import ./src/exterior.bend as Exterior
import ../voxel.bend as Voxel


law voxel_full_material_word:
  for material: U32
  {Mesh.material_word(Mesh.quad(Voxel.Cell{0,0,0},0,0,material,1,1,0,[0 : U32^6n])) == material : U32}

law voxel_high_material_bits:
  {Mesh.material_word(Mesh.quad(Voxel.Cell{0,0,0},5,0,4294967295,1,1,0,[0 : U32^6n])) == 4294967295 : U32}

law voxel_rgb_direction_bytes:
  {Mesh.rgbd(1193046,5) == 89535506 : U32}

law voxel_all_direction_codes:
  {[Exterior.direction(Voxel.NegX{}),Exterior.direction(Voxel.PosX{}),Exterior.direction(Voxel.NegY{}),Exterior.direction(Voxel.PosY{}),Exterior.direction(Voxel.NegZ{}),Exterior.direction(Voxel.PosZ{})] == [0,1,2,3,4,5] : List<U32>}

law voxel_empty_face_count:
  {Exterior.count(Nil{},0) == Done{0} : Result<&2,&2,Exterior.Error,U32>}

law voxel_face_count_step:
  for face: Voxel.Face
  for faces: List<&2,Voxel.Face>
  for n: U32
  {Exterior.count(face <> faces,n) == GeometryLaws.bounded_count_step(faces,n) : Result<&2,&2,Exterior.Error,U32>}

law voxel_face_count_limit:
  for face: Voxel.Face
  {Exterior.count([face],26843545) == Fail{Exterior.GeometryTooLarge{}} : Result<&2,&2,Exterior.Error,U32>}

law voxel_quad_index_pattern:
  for base: U32
  {Array.to_list(~U32,Mesh.index_quad(base,0,[0 : U32^3n])) == [base,U32.add(base,1),U32.add(base,2),U32.add(base,2),U32.add(base,3),base,0,0] : List<U32>}

law voxel_max_fixture_index:
  {Array.to_list(~U32,Mesh.index_quad(12284,0,[0 : U32^3n])) == [12284,12285,12286,12286,12287,12284,0,0] : List<U32>}

law voxel_quad_outward:
  {[Geometry.quad_normal(0),Geometry.quad_normal(1),Geometry.quad_normal(2),Geometry.quad_normal(3),Geometry.quad_normal(4),Geometry.quad_normal(5)] == [Voxel.Cell{4294967295,0,0},Voxel.Cell{1,0,0},Voxel.Cell{0,4294967295,0},Voxel.Cell{0,1,0},Voxel.Cell{0,0,4294967295},Voxel.Cell{0,0,1}] : List<Voxel.Cell>}

law voxel_second_triangle_outward:
  {[Geometry.quad_second_normal(0),Geometry.quad_second_normal(1),Geometry.quad_second_normal(2),Geometry.quad_second_normal(3),Geometry.quad_second_normal(4),Geometry.quad_second_normal(5)] == [Voxel.Cell{4294967295,0,0},Voxel.Cell{1,0,0},Voxel.Cell{0,4294967295,0},Voxel.Cell{0,1,0},Voxel.Cell{0,0,4294967295},Voxel.Cell{0,0,1}] : List<Voxel.Cell>}

law voxel_all_8cube_indices_bounded:
  {Geometry.fixture_index_bounds(3072n,0) == True{} : Bool}

law exterior_subtract_center_four_disjoint_pieces:
  {Exterior.subtract(Exterior.Rect2{0,7,0,9},Exterior.Rect2{2,5,3,6}) == [Exterior.Rect2{0,2,0,9},Exterior.Rect2{5,7,0,9},Exterior.Rect2{2,5,0,3},Exterior.Rect2{2,5,6,9}] : List<&2,Exterior.Rect2>}

law exterior_subtract_touching_unchanged:
  {Exterior.subtract(Exterior.Rect2{1,4,2,7},Exterior.Rect2{4,8,3,5}) == [Exterior.Rect2{1,4,2,7}] : List<&2,Exterior.Rect2>}

law exterior_subtract_contains_empty:
  {Exterior.subtract(Exterior.Rect2{1,4,2,7},Exterior.Rect2{0,5,0,8}) == Nil{} : List<&2,Exterior.Rect2>}

law exterior_rectangle_preserves_full_material:
  for normal: U32
  for d: Voxel.Direction
  for m: U32
  for r: Exterior.Rect2
  {GeometryLaws.material(Exterior.face(normal,d,m,r)) == m : U32}

law exterior_rectangle_preserves_direction:
  for normal: U32
  for +d: Voxel.Direction
  for m: U32
  for r: Exterior.Rect2
  {GeometryLaws.face_direction(Exterior.face(normal,d,m,r)) == d : Voxel.Direction}

law exterior_indices_preserve_order:
  for +base: U32
  {Array.to_list(~U32,Mesh.index_quad(base,0,[0 : U32^3n])) == [base,(base + 1 : U32),(base + 2 : U32),(base + 2 : U32),(base + 3 : U32),base,0,0] : List<U32>}

law exterior_coordinate_bound_exact:
  {Exterior.box_bounded(Voxel.Cuboid{Voxel.Cell{1048575,0,0},Voxel.Cell{1048576,1,1},4294967295}) == True{} : Bool}

law exterior_coordinate_bound_rejects_next:
  {Exterior.box_bounded(Voxel.Cuboid{Voxel.Cell{1048576,0,0},Voxel.Cell{1048577,1,1},1}) == False{} : Bool}

law exterior_count_limit_accepts_exact:
  {Result.is_done(&2,&2,Exterior.Error,Mesh.PackedSize,Mesh.size(26843545)) == True{} : Bool}

law exterior_count_limit_rejects_next:
  {Mesh.size(26843546) == Fail{Exterior.GeometryTooLarge{}} : Result<&2,&2,Exterior.Error,Mesh.PackedSize>}

law exterior_count_limit_rejects_wrapping_product:
  {Mesh.size(4294967295) == Fail{Exterior.GeometryTooLarge{}} : Result<&2,&2,Exterior.Error,Mesh.PackedSize>}

law exterior_capacity_bytes_keep_high_limb:
  {Mesh.word_bytes(1073741824) == W.U64{0,1} : W.U64}

law exterior_asymmetric_first_normals:
  {[GeometryLaws.first(0),GeometryLaws.first(1),GeometryLaws.first(2),GeometryLaws.first(3),GeometryLaws.first(4),GeometryLaws.first(5)] == [Voxel.Cell{4294967290,0,0},Voxel.Cell{6,0,0},Voxel.Cell{0,4294967290,0},Voxel.Cell{0,6,0},Voxel.Cell{0,0,4294967290},Voxel.Cell{0,0,6}] : List<&2,Voxel.Cell>}

law exterior_asymmetric_second_normals:
  {[GeometryLaws.second(0),GeometryLaws.second(1),GeometryLaws.second(2),GeometryLaws.second(3),GeometryLaws.second(4),GeometryLaws.second(5)] == [Voxel.Cell{4294967290,0,0},Voxel.Cell{6,0,0},Voxel.Cell{0,4294967290,0},Voxel.Cell{0,6,0},Voxel.Cell{0,0,4294967290},Voxel.Cell{0,0,6}] : List<&2,Voxel.Cell>}

law exterior_overlap_rejected_with_sources:
  {Exterior.validate([Voxel.Cuboid{Voxel.Cell{0,0,0},Voxel.Cell{3,3,3},1},Voxel.Cuboid{Voxel.Cell{1,1,1},Voxel.Cell{2,2,2},2}],0) == Fail{Exterior.OverlappingBoxes{0,1}} : Result<&2,&2,Exterior.Error,Unit>}

law exterior_clipping_preserves_every_material:
  for rs: List<&2,Exterior.Rect2>
  for +normal: U32
  for +d: Voxel.Direction
  for +m: U32
  for +old: Exterior.Rect2
  {GeometryLaws.materials(Exterior.lift(rs,Exterior.Patch{normal,d,m,old})) == GeometryLaws.repeated(rs,m) : List<U32>}


law appearance_payload_bytes:
  {Uniform.byte_size() == 2336 : U32}

law appearance_payload_words:
  {Uniform.word_count() == 584 : U32}

law appearance_selected_offset:
  {Uniform.offset_selected() == 336 : U32}

law appearance_ring_index_count:
  {Appearance.ring_index_count() == 576 : U32}


law chunk_region_boundary:
  {[Chunks.region(32,Voxel.Cell{31,32,63}),Chunks.region(32,Voxel.Cell{32,31,64})] == [Chunks.ChunkKey{0,32,32,32},Chunks.ChunkKey{32,0,64,32}] : List<&2,Chunks.ChunkKey>}

law chunk_huge_source_stays_analytic:
  {Chunks.source_key(Voxel.Cuboid{Voxel.Cell{0,0,0},Voxel.Cell{1048576,1048576,1048576},1}) == Chunks.ChunkKey{0,0,0,1048576} : Chunks.ChunkKey}

law chunk_dirty_neighbor_boundary:
  {Chunks.dependency_region(Chunks.ChunkKey{32,0,0,32},64) == Voxel.Cuboid{Voxel.Cell{31,0,0},Voxel.Cell{64,33,33},1} : Voxel.Cuboid}

law chunk_low_boundary_clamped:
  {Chunks.dependency_region(Chunks.ChunkKey{0,0,0,32},64) == Voxel.Cuboid{Voxel.Cell{0,0,0},Voxel.Cell{33,33,33},1} : Voxel.Cuboid}

law chunk_full_source_tuple_required:
  {Chunks.box_equal(Voxel.Cuboid{Voxel.Cell{0,0,0},Voxel.Cell{4,4,4},1},Voxel.Cuboid{Voxel.Cell{0,0,0},Voxel.Cell{4,4,4},4294967295}) == False{} : Bool}

law greedy_exact_shared_edge:
  {Greedy.join(Exterior.Patch{7,Voxel.PosZ{},4294967295,Exterior.Rect2{0,3,2,6}},Exterior.Patch{7,Voxel.PosZ{},4294967295,Exterior.Rect2{3,8,2,6}},Greedy.Horizontal{}) == Some{Exterior.Patch{7,Voxel.PosZ{},4294967295,Exterior.Rect2{0,8,2,6}}} : Maybe<&2,Exterior.Patch>}

law greedy_material_boundary:
  {Greedy.join(Exterior.Patch{7,Voxel.PosZ{},1,Exterior.Rect2{0,3,2,6}},Exterior.Patch{7,Voxel.PosZ{},4294967295,Exterior.Rect2{3,8,2,6}},Greedy.Horizontal{}) == None{} : Maybe<&2,Exterior.Patch>}

law greedy_plane_boundary:
  {Greedy.join(Exterior.Patch{7,Voxel.PosZ{},1,Exterior.Rect2{0,3,2,6}},Exterior.Patch{8,Voxel.PosZ{},1,Exterior.Rect2{3,8,2,6}},Greedy.Horizontal{}) == None{} : Maybe<&2,Exterior.Patch>}

law greedy_gap_rejected:
  {Greedy.join(Exterior.Patch{7,Voxel.PosZ{},1,Exterior.Rect2{0,3,2,6}},Exterior.Patch{7,Voxel.PosZ{},1,Exterior.Rect2{4,8,2,6}},Greedy.Horizontal{}) == None{} : Maybe<&2,Exterior.Patch>}

law greedy_four_tiles_one_rectangle:
  {Greedy.merge_faces([Voxel.Rectangle{Voxel.Cell{0,0,7},Voxel.PosZ{},1,2,3},Voxel.Rectangle{Voxel.Cell{2,0,7},Voxel.PosZ{},1,2,3},Voxel.Rectangle{Voxel.Cell{0,3,7},Voxel.PosZ{},1,2,3},Voxel.Rectangle{Voxel.Cell{2,3,7},Voxel.PosZ{},1,2,3}]) == [Voxel.Rectangle{Voxel.Cell{0,0,7},Voxel.PosZ{},1,4,6}] : List<&2,Voxel.Face>}


law chunk_runs_merge_only_adjacent_local_ranges:
  {Chunks.runs([Chunks.Primitive{Chunks.ChunkKey{0,0,0,32},0,Voxel.Face{Voxel.Cell{0,0,0},Voxel.NegX{},1}},Chunks.Primitive{Chunks.ChunkKey{0,0,0,32},1,Voxel.Face{Voxel.Cell{0,0,0},Voxel.PosX{},1}},Chunks.Primitive{Chunks.ChunkKey{0,0,0,32},3,Voxel.Face{Voxel.Cell{0,0,0},Voxel.NegY{},1}}]) == [Chunks.Run{Chunks.ChunkKey{0,0,0,32},0,2},Chunks.Run{Chunks.ChunkKey{0,0,0,32},3,1}] : List<&2,Chunks.Run>}

law retirement_keeps_exact_key_and_version:
  {Residency.obsolete(~Residency.Version,~(version => version),[Residency.Version{Chunks.ChunkKey{0,0,0,32},7}],[Residency.Version{Chunks.ChunkKey{0,0,0,32},7}]) == Nil{} : List<&2,Residency.Version>}

law retirement_selects_changed_and_removed:
  {Residency.obsolete(~Residency.Version,~(version => version),[Residency.Version{Chunks.ChunkKey{0,0,0,32},7},Residency.Version{Chunks.ChunkKey{32,0,0,32},7},Residency.Version{Chunks.ChunkKey{64,0,0,32},7}],[Residency.Version{Chunks.ChunkKey{0,0,0,32},7},Residency.Version{Chunks.ChunkKey{32,0,0,32},8}]) == [Residency.Version{Chunks.ChunkKey{32,0,0,32},7},Residency.Version{Chunks.ChunkKey{64,0,0,32},7}] : List<&2,Residency.Version>}

law retirement_equal_version_different_key_is_obsolete:
  {Residency.contains([Residency.Version{Chunks.ChunkKey{32,0,0,32},7}],Residency.Version{Chunks.ChunkKey{0,0,0,32},7}) == False{} : Bool}

law retirement_empty_has_no_allocations:
  {Residency.obsolete(~Residency.Version,~(version => version),Nil{},Nil{}) == Nil{} : List<&2,Residency.Version>}
