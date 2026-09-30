#include "../src/vulkan/native.cpp"
#include <cassert>

static void test_colors(VoxelVkFrame& frame) {
  for (uint32_t i=0;i<19;i++) for (uint32_t channel=0;channel<3;channel++)
    frame.colors[i][channel]=float(i*3+channel+1)/60.f;
}

static void expect_bend_palette() {
  VoxelVkFrame frame{};
  test_colors(frame);
  auto anchored=material_color(frame,2,false);
  auto detached=material_color(frame,2,true);
  assert(anchored.x==frame.colors[2][0] && anchored.y==frame.colors[2][1]);
  assert(detached.x==frame.colors[3][0] && detached.z==frame.colors[3][2]);
  bool rejected=false;
  try { material_color(frame,6,false); } catch (const std::runtime_error&) { rejected=true; }
  assert(rejected);
}

static void expect_bend_body_vertices() {
  VoxelVkFace source{{0,0,0},{1,0,1},3,2};
  VoxelVkVertex vertices[6]{};
  for (uint32_t i=0;i<6;i++) {
    vertices[i].position[0]=float(i);
    vertices[i].side=3;
    vertices[i].material=2;
  }
  VoxelVkBody body{};
  body.anchored=1; body.face_count=1; body.faces=&source;
  body.vertex_count=6; body.vertices=vertices;
  Geometry output;
  VoxelVkFrame frame{}; test_colors(frame);
  body_vertices(output,body,frame);
  assert(output.triangles==6 && output.vertices.size()==6);
  for (uint32_t i=0;i<6;i++) {
    assert(output.vertices[i].position.x==float(i));
    assert(output.vertices[i].side==3);
    assert(output.vertices[i].color.x==frame.colors[2][0]);
  }
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
  test_colors(frame);
  GeometryCache cache;
  expect_fresh(frame,cache,5);
  assert(cache.proxy_draws==1 && cache.proxied_bodies==5);
  assert(cache.draws.size()==1 && cache.proxy_rebuilt==1);
  // The primary profile changes selection only: full visible meshes, identical
  // eligibility, retained proxies, full shadow work and fixed declared ground.
  VoxelVkFrame full=frame;
  full.full_geometry=1; full.ground_half_extent=40;
  GeometryCache full_cache;
  expect_fresh(full,full_cache,5);
  assert(full_cache.proxies.size()==cache.proxies.size());
  assert(full_cache.proxy_vertices==cache.proxy_vertices);
  assert(full_cache.proxy_rebuilt==1 && full_cache.proxy_draws==0);
  assert(full_cache.draws.size()==5 && full_cache.shadow_draws.size()==5);
  assert(full_cache.meshes.size()==5 && full_cache.proxied_bodies==0);
  for (size_t i=0;i<6;i++) {
    auto p=full_cache.geometry.vertices[i].position;
    assert(std::abs(p.x)==40 && std::abs(p.z)==40 && p.y==0);
  }
  expect_fresh(full,full_cache,0);
  assert(full_cache.proxy_rebuilt==0 && full_cache.draws.size()==5);
  auto old_shadow=shadow_matrix(frame),full_shadow=shadow_matrix(full);
  assert(std::memcmp(old_shadow.values,full_shadow.values,sizeof old_shadow.values)==0);
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

static void expect_visibility_fixtures() {
  auto check=[](std::array<float,3> lo,std::array<float,3> hi,float offset,
                std::array<float,3> eye,bool expected) {
    std::vector<VoxelVkVertex> vertices;
    for(unsigned side=0;side<6;side++) {
      unsigned axis=side/2,u=(axis+1)%3,v=(axis+2)%3;
      auto corner=[&](unsigned a,unsigned b) {
        std::array<float,3> p=lo;
        p[axis]=side%2?hi[axis]:lo[axis];
        p[u]=a?hi[u]:lo[u]; p[v]=b?hi[v]:lo[v];
        return VoxelVkVertex{{p[0]*.1f,p[1]*.1f,p[2]*.1f},side,2};
      };
      for(auto [a,b]:std::initializer_list<std::pair<unsigned,unsigned>>{{0,0},{1,0},{1,1},{0,0},{1,1},{0,1}})
        vertices.push_back(corner(a,b));
    }
    VoxelVkBody body{};
    body.id=1; body.offset=offset;
    std::copy(lo.begin(),lo.end(),body.lo);
    std::copy(hi.begin(),hi.end(),body.hi);
    body.vertex_count=vertices.size(); body.vertices=vertices.data();
    VoxelVkFrame frame{}; frame.width=640; frame.height=360;
    std::copy(eye.begin(),eye.end(),frame.eye);
    bool reference=visibility_reference::body(body,frame);
    assert(reference==expected);
    if(reference) assert(visible(body,frame,ViewBasis(frame)));
  };
  check({8,-1,9},{12,1,12},0,{0,0,0},true); // Frustum side boundary.
  check({-10,-10,-10},{10,10,10},0,{0,0,0},true); // Eye inside the owner.
  check({-35,10,-30},{-25,20,-20},-.5f,{-3,1,-4},true); // Signed/translated.
  check({-1,-1,0},{1,1,1},0,{0,0,0},true); // Near-plane intersection.
  check({-1,-1,-20},{1,1,-10},0,{0,0,0},false);
}

int main() {
  GeometryCache selection_cache;
  selection_cache.proxies[1].selected=true;
  selection_cache.groups[2].selected=false;
  auto change=[&]() { selection_cache.proxies.at(1).selected=false; selection_cache.groups.at(2).selected=true; };
  with_preserved_proxy_selection(selection_cache,change);
  assert(selection_cache.proxies.at(1).selected && !selection_cache.groups.at(2).selected);
  bool detail_failed=false;
  try { with_preserved_proxy_selection(selection_cache,[&]() { change(); throw std::runtime_error("detail failure"); }); }
  catch(const std::runtime_error&) { detail_failed=true; }
  assert(detail_failed && selection_cache.proxies.at(1).selected && !selection_cache.groups.at(2).selected);

  expect_visibility_fixtures();
  assert(unpaced_mode({VK_PRESENT_MODE_FIFO_KHR,VK_PRESENT_MODE_MAILBOX_KHR,VK_PRESENT_MODE_IMMEDIATE_KHR})==VK_PRESENT_MODE_IMMEDIATE_KHR);
  assert(unpaced_mode({VK_PRESENT_MODE_FIFO_KHR,VK_PRESENT_MODE_MAILBOX_KHR})==VK_PRESENT_MODE_MAILBOX_KHR);
  bool unsupported=false;
  try { unpaced_mode({VK_PRESENT_MODE_FIFO_KHR}); } catch (const std::runtime_error&) { unsupported=true; }
  assert(unsupported);
  expect_bend_palette();
  expect_bend_body_vertices();
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
  test_colors(frame);
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
  try { face(g,invalid,true,frame); } catch (const std::runtime_error&) { rejected=true; }
  assert(rejected);
  invalid=faces[0]; invalid.material=0; rejected=false;
  try { face(g,invalid,true,frame); } catch (const std::runtime_error&) { rejected=true; }
  assert(rejected);
  std::puts("ALL NATIVE BODY CACHE CHECKS PASSED");
}
