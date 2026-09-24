#include "../src/vulkan/native.cpp"
#include <cassert>

static void expect_fresh(const VoxelVkFrame& frame,GeometryCache& cache,uint32_t rebuilt) {
  bool reused=false;
  const auto& actual=geometry(frame,cache,reused);
  assert(cache.rebuilt==rebuilt);
  GeometryCache fresh;
  bool fresh_hit=false;
  const auto& expected=geometry(frame,fresh,fresh_hit);
  for (uint32_t i=0;i<frame.body_count;i++) {
    const auto& a=cache.meshes.at(frame.bodies[i].id);
    const auto& b=fresh.meshes.at(frame.bodies[i].id);
    assert(a.count==b.count);
    assert(std::memcmp(actual.vertices.data()+a.first,expected.vertices.data()+b.first,
      a.count*sizeof(Vertex))==0);
  }
  assert(actual.lines==expected.lines && actual.hud==expected.hud);
  auto overlays=actual.vertices.size()-cache.scene_vertices;
  assert(overlays==expected.vertices.size()-fresh.scene_vertices);
  assert(std::memcmp(actual.vertices.data()+cache.scene_vertices,
    expected.vertices.data()+fresh.scene_vertices,overlays*sizeof(Vertex))==0);
}

int main() {
  VoxelVkFace faces[]={{{-400,20,-10},{400,20,10},3,2},{{-1,0,10},{1,20,10},5,3}};
  VoxelVkBody bodies[]={
    {1,0,1,1,0,{-400,0,-10},{400,20,10},faces},
    {2,0,0,1,0,{-1,0,0},{1,20,10},faces+1}};
  VoxelVkFrame frame{};
  frame.eye[1]=3; frame.eye[2]=5; frame.yaw=3.14159265f;
  frame.aim[1]=2; frame.aim[2]=.05f; frame.aim_kind=1;
  frame.body_count=2; frame.bodies=bodies; frame.hud="FRAME 1";
  GeometryCache cache;
  expect_fresh(frame,cache,2);
  auto first=cache.meshes.at(1).first;
  auto original=cache.geometry.vertices;
  assert(cache.geometry.triangles>cache.scene_vertices);
  frame.hud="FRAME 2"; frame.eye[0]=1; frame.yaw+=.2f;
  expect_fresh(frame,cache,0);
  frame.aim[0]=.2f;
  expect_fresh(frame,cache,0);
  frame.aim_kind=0;
  expect_fresh(frame,cache,0);
  bodies[1].offset=-.7f;
  expect_fresh(frame,cache,0);
  assert(cache.dirty.empty());
  assert(std::memcmp(original.data(),cache.geometry.vertices.data(),cache.scene_vertices*sizeof(Vertex))==0);
  bool translated=false;
  for (auto draw:cache.draws) translated|=draw.offset==-.7f;
  assert(translated);
  faces[1].hi[1]=19; bodies[1].revision++;
  expect_fresh(frame,cache,1);
  assert(cache.meshes.at(1).first==first);
  assert(cache.dirty.size()==1 && cache.dirty[0].first==cache.meshes.at(2).first);
  frame.body_count=1;
  expect_fresh(frame,cache,0);
  assert(cache.meshes.size()==1);
  frame.body_count=2; bodies[1].id=3;
  expect_fresh(frame,cache,1);
  assert(cache.scene_vertices==18); // Freed mesh slot reused.
  frame.aim_kind=1; frame.aim[1]=1.3f; frame.aim[2]=1;
  expect_fresh(frame,cache,0);
  // Signed bounds, moved preview, anchors, and large faces use the same geometry.
  faces[0].material=1; bodies[0].revision++;
  expect_fresh(frame,cache,1);
  assert(cache.geometry.triangles-cache.scene_vertices<=6*25);
  VoxelVkFace invalid=faces[0]; invalid.side=6;
  Geometry g;
  bool rejected=false;
  try { face(g,invalid,true); } catch (const std::runtime_error&) { rejected=true; }
  assert(rejected);
  std::puts("ALL NATIVE BODY CACHE CHECKS PASSED");
}
