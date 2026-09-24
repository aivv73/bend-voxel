#include "../src/vulkan/native.cpp"
#include <cassert>

static void expect_fresh_geometry(const VoxelVkFrame& frame,GeometryCache& cache,bool expected_hit) {
  bool hit=false;
  const Geometry& actual=geometry(frame,cache,hit);
  assert(hit==expected_hit);
  GeometryCache fresh;
  bool fresh_hit=false;
  const Geometry& expected=geometry(frame,fresh,fresh_hit);
  assert(!fresh_hit);
  assert(actual.triangles==expected.triangles);
  assert(actual.lines==expected.lines);
  assert(actual.hud==expected.hud);
  assert(actual.vertices.size()==expected.vertices.size());
  assert(std::memcmp(actual.vertices.data(),expected.vertices.data(),
    actual.vertices.size()*sizeof(Vertex))==0);
}

int main() {
  VoxelVkFace faces[]={{10540,3,2,1,1,0}, {10500,5,2,1,1,0}};
  VoxelVkFrame frame{};
  frame.eye[0]=0; frame.eye[1]=3; frame.eye[2]=5;
  frame.aim[0]=0; frame.aim[1]=2; frame.aim[2]=0;
  frame.aim_kind=1;
  frame.face_count=2;
  frame.faces=faces;
  frame.hud="FRAME 1";
  GeometryCache cache;
  expect_fresh_geometry(frame,cache,false);
  frame.hud="FRAME 2";
  expect_fresh_geometry(frame,cache,true);
  frame.yaw=.2f;
  expect_fresh_geometry(frame,cache,true);
  frame.eye[0]=1;
  expect_fresh_geometry(frame,cache,false);
  frame.aim[0]=.2f;
  expect_fresh_geometry(frame,cache,false);
  faces[0].offset=.1f;
  expect_fresh_geometry(frame,cache,false);
  expect_fresh_geometry(frame,cache,true);
  frame.face_count=1;
  expect_fresh_geometry(frame,cache,false);
  frame.face_count=2;
  setenv("VOXEL_STRESS_COPIES","4",1);
  expect_fresh_geometry(frame,cache,false);
  expect_fresh_geometry(frame,cache,true);
  unsetenv("VOXEL_STRESS_COPIES");
  expect_fresh_geometry(frame,cache,false);
}
