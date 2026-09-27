#include "../src/vulkan/native.cpp"
#include <cassert>

static void expect_material_palette() {
  constexpr uint32_t original[]={0x4bc1a4,0xd19d68,0x668fac,0xd9954f};
  for (uint32_t id=1;id<=4;id++) {
    assert(material::find(id).id==id);
    auto top=material::surface(id,false);
    auto encoded=material::encode(top);
    float expected[3]={float((original[id-1]>>16)&255)/255,
      float((original[id-1]>>8)&255)/255,float(original[id-1]&255)/255};
    assert(std::abs(encoded.r-expected[0])<0.002f);
    assert(std::abs(encoded.g-expected[1])<0.002f);
    assert(std::abs(encoded.b-expected[2])<0.002f);
    auto detached=material::surface(id,true);
    assert(detached.r!=top.r || detached.g!=top.g || detached.b!=top.b);
  }
  auto concrete=material::surface(2,true);
  auto frame=material::surface(3,true);
  assert(std::abs(concrete.r-frame.r)+std::abs(concrete.g-frame.g)+
    std::abs(concrete.b-frame.b)>0.25f);
  assert(material::in_gamut(material::to_linear({0.7f,0.5f,30.0f})));
  auto roundtrip=material::encode(material::decode({0.2f,0.5f,0.8f}));
  assert(std::abs(roundtrip.r-0.2f)<0.00001f);
  assert(std::abs(roundtrip.g-0.5f)<0.00001f);
  assert(std::abs(roundtrip.b-0.8f)<0.00001f);
  bool rejected=false;
  auto plaster=material::surface(5,false);
  assert(material::in_gamut(plaster));
  assert(plaster.r>material::surface(2,false).r && plaster.b>material::surface(2,false).b);
  try { material::surface(6,false); } catch (const std::runtime_error&) { rejected=true; }
  assert(rejected);
}

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
  assert(cache.proxies.size()==fresh.proxies.size());
  for (const auto& [key,a]:cache.proxies) {
    const auto& b=fresh.proxies.at(key);
    assert(a.members==b.members && a.count==b.count);
    assert(std::memcmp(actual.vertices.data()+a.first,expected.vertices.data()+b.first,
      a.count*sizeof(Vertex))==0);
  }
  assert(actual.lines==expected.lines && actual.hud==expected.hud);
  assert(cache.shadow_draws.size()==frame.body_count);
  for (uint32_t i=0;i<frame.body_count;i++) {
    const auto& draw=cache.shadow_draws[i];
    const auto& mesh=cache.meshes.at(frame.bodies[i].id);
    assert(draw.first==mesh.first && draw.count==mesh.count);
    assert(draw.offset==frame.bodies[i].offset);
  }
  auto overlays=actual.vertices.size()-cache.scene_vertices;
  assert(overlays==expected.vertices.size()-fresh.scene_vertices);
  assert(std::memcmp(actual.vertices.data()+cache.scene_vertices,
    expected.vertices.data()+fresh.scene_vertices,overlays*sizeof(Vertex))==0);
}

static Vec3 light_clip(const ShadowMatrix& matrix,Vec3 point) {
  const auto* m=matrix.values;
  return {m[0]*point.x+m[4]*point.y+m[8]*point.z+m[12],
    m[1]*point.x+m[5]*point.y+m[9]*point.z+m[13],
    m[2]*point.x+m[6]*point.y+m[10]*point.z+m[14]};
}

static void expect_shadow_bounds() {
  VoxelVkBody bodies[2]{};
  bodies[0].lo[0]=-300; bodies[0].lo[1]=0; bodies[0].lo[2]=-200;
  bodies[0].hi[0]=200; bodies[0].hi[1]=460; bodies[0].hi[2]=100;
  bodies[1].lo[0]=220; bodies[1].lo[1]=0; bodies[1].lo[2]=300;
  bodies[1].hi[0]=260; bodies[1].hi[1]=40; bodies[1].hi[2]=360;
  bodies[1].offset=3.5f;
  VoxelVkFrame frame{}; frame.body_count=2; frame.bodies=bodies;
  auto matrix=shadow_matrix(frame);
  for (const auto& b:bodies) for (unsigned corner=0;corner<8;corner++) {
    Vec3 point{(corner&1?b.hi[0]:b.lo[0])*.1f,
      (corner&2?b.hi[1]:b.lo[1])*.1f+b.offset,
      (corner&4?b.hi[2]:b.lo[2])*.1f};
    Vec3 clip=light_clip(matrix,point);
    assert(clip.x>-1 && clip.x<1 && clip.y>-1 && clip.y<1);
    assert(clip.z>0 && clip.z<1);
  }
  Vec3 point{0,2,0},toward_sun=normalized({-.62f,.62f,.48f});
  assert(light_clip(matrix,point+toward_sun).z<light_clip(matrix,point).z);
  std::vector<ShadowIdentity> saved{{1,2,1,0.5f}};
  VoxelVkBody body{}; body.id=1; body.revision=2; body.anchored=1; body.offset=.5f;
  VoxelVkFrame current{}; current.body_count=1; current.bodies=&body;
  assert(!shadow_changed(saved,current));
  current.eye[0]=18; current.yaw=.5f; current.night=1; current.aim_kind=1;
  assert(!shadow_changed(saved,current)); // View and lighting never dirty the map.
  body.offset=.6f; assert(shadow_changed(saved,current));
  body.offset=.5f; body.revision++; assert(shadow_changed(saved,current));
}

static void expect_render_lod() {
  VoxelVkFace faces[5]{};
  VoxelVkBody bodies[5]{};
  for (uint32_t i=0;i<5;i++) {
    faces[i].lo[0]=float(i*4); faces[i].hi[0]=float(i*4+2);
    faces[i].lo[1]=0; faces[i].hi[1]=20;
    faces[i].lo[2]=faces[i].hi[2]=10;
    faces[i].side=5; faces[i].material=2;
    bodies[i].id=i+1; bodies[i].anchored=1; bodies[i].revision=1;
    bodies[i].face_count=1; bodies[i].faces=faces+i;
    bodies[i].lo[0]=faces[i].lo[0]; bodies[i].hi[0]=faces[i].hi[0];
    bodies[i].lo[1]=0; bodies[i].hi[1]=20;
    bodies[i].lo[2]=0; bodies[i].hi[2]=10;
  }
  VoxelVkFrame frame{};
  frame.width=640; frame.height=360;
  frame.eye[0]=.9f; frame.eye[1]=1; frame.eye[2]=50;
  frame.yaw=3.14159265f;
  frame.body_count=5; frame.bodies=bodies;
  GeometryCache cache;
  expect_fresh(frame,cache,5);
  assert(cache.proxy_draws==1 && cache.proxied_bodies==5);
  assert(cache.draws.size()==1 && cache.proxy_rebuilt==1);
  faces[0].material=5; bodies[0].revision++;
  expect_fresh(frame,cache,1);
  assert(proxy_material(bodies[0])==5); // New plaster participates in LOD safely.
  assert(cache.shadow_draws.size()==5);
  frame.yaw=0; // Camera culls the group, but the sun can still see it.
  expect_fresh(frame,cache,0);
  assert(cache.draws.empty() && cache.shadow_draws.size()==5);
  frame.yaw=3.14159265f;
  expect_fresh(frame,cache,0);
  assert(cache.proxy_draws==1);
  frame.eye[2]=14.7f; // Between the 80 and 100 pixel thresholds.
  expect_fresh(frame,cache,0);
  assert(cache.proxy_draws==1 && cache.proxy_rebuilt==0);
  frame.eye[2]=11;
  expect_fresh(frame,cache,0);
  assert(cache.proxy_draws==0 && cache.draws.size()==5);
  assert(cache.shadow_draws.size()==5);
  frame.eye[2]=14.7f;
  expect_fresh(frame,cache,0);
  assert(cache.proxy_draws==0 && cache.proxy_rebuilt==0);
  frame.eye[2]=50;
  expect_fresh(frame,cache,0);
  assert(cache.proxy_draws==1);
  frame.aim_kind=1; frame.aim[0]=.1f; frame.aim[1]=1; frame.aim[2]=.5f;
  expect_fresh(frame,cache,0);
  assert(cache.proxy_draws==0 && cache.draws.size()==5);
  frame.aim_kind=0;
  bodies[0].anchored=0; bodies[0].revision++;
  expect_fresh(frame,cache,1);
  assert(cache.proxy_rebuilt==1 && cache.proxy_draws==1);
  assert(cache.proxied_bodies==4 && cache.draws.size()==2);
  bodies[1].revision++; faces[1].material=3;
  expect_fresh(frame,cache,1);
  assert(cache.proxy_rebuilt==1 && cache.proxy_draws==1);
  assert(cache.proxied_bodies==4);
  bodies[4].id=6; bodies[4].revision++;
  expect_fresh(frame,cache,1);
  assert(cache.proxy_rebuilt==1 && cache.proxy_draws==1);
  frame.body_count=4; frame.bodies=bodies+1;
  expect_fresh(frame,cache,0);
  assert(cache.proxy_rebuilt==0 && cache.proxy_draws==1);
  assert(cache.proxied_bodies==4 && cache.draws.size()==1);
  frame.body_count=3;
  expect_fresh(frame,cache,0);
  assert(cache.proxies.empty() && cache.proxy_draws==0);
  assert(cache.draws.size()==3);
}

int main() {
  expect_material_palette();
  expect_shadow_bounds();
  expect_render_lod();
  VoxelVkFace faces[]={{{-400,20,-10},{400,20,10},3,2},{{-1,0,10},{1,20,10},5,3}};
  VoxelVkBody bodies[]={
    {1,0,1,1,0,{-400,0,-10},{400,20,10},faces},
    {2,0,0,1,0,{-1,0,0},{1,20,10},faces+1}};
  VoxelVkFrame frame{};
  frame.width=640; frame.height=360;
  frame.eye[1]=3; frame.eye[2]=5; frame.yaw=3.14159265f;
  frame.aim[1]=2; frame.aim[2]=.05f; frame.aim_kind=1;
  frame.body_count=2; frame.bodies=bodies; frame.hud="FRAME 1";
  GeometryCache cache;
  expect_fresh(frame,cache,2);
  assert(cache.geometry.vertices[0].side==3); // Ground is sunlit.
  assert(cache.geometry.vertices[cache.meshes.at(1).first].side==3);
  assert(cache.geometry.vertices[cache.meshes.at(2).first].side==5);
  auto first=cache.meshes.at(1).first;
  auto original=cache.geometry.vertices;
  assert(cache.geometry.triangles>cache.scene_vertices);
  frame.hud="FRAME 2"; frame.eye[0]=1; frame.yaw+=.2f;
  expect_fresh(frame,cache,0);
  frame.night=1;
  expect_fresh(frame,cache,0); // Lighting changes do not rebuild world meshes.
  frame.aim[0]=.2f;
  expect_fresh(frame,cache,0);
  frame.aim_kind=0;
  expect_fresh(frame,cache,0);
  bodies[1].anchored=1;
  expect_fresh(frame,cache,1);
  bodies[1].anchored=0;
  expect_fresh(frame,cache,1);
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
  invalid=faces[0]; invalid.material=0; rejected=false;
  try { face(g,invalid,true); } catch (const std::runtime_error&) { rejected=true; }
  assert(rejected);
  std::puts("ALL NATIVE BODY CACHE CHECKS PASSED");
}
