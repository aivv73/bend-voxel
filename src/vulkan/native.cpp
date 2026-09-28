#define VK_USE_PLATFORM_XLIB_KHR
#include <X11/Xlib.h>
#include <vulkan/vulkan.h>
#include "native.h"
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <memory>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>
#include <unordered_map>

namespace {
constexpr uint32_t DEFAULT_WIDTH=640, DEFAULT_HEIGHT=360;
void record_vk_failure(VkResult result,const char* what);
void check(VkResult result, const char* what) {
  if(result!=VK_SUCCESS) record_vk_failure(result,what);
  if (result!=VK_SUCCESS) throw std::runtime_error(std::string(what)+": Vulkan "+std::to_string(result));
}
} // namespace
#include "supervision.h"
#include "gpu_timing.h"
#include "checkpoint.h"
#include "visibility_reference.h"
namespace {
void record_vk_failure(VkResult result,const char* what) {
  supervision::emit(supervision::allocations,supervision::allocation_seq,
    "\"record_type\":\"vulkan_error\",\"operation\":\""+std::string(what)+"\",\"vk_result\":\""+std::to_string(result)+"\"");
}
struct Vec3 { float x,y,z; };
Vec3 operator+(Vec3 a,Vec3 b) { return {a.x+b.x,a.y+b.y,a.z+b.z}; }
Vec3 operator-(Vec3 a,Vec3 b) { return {a.x-b.x,a.y-b.y,a.z-b.z}; }
Vec3 operator*(Vec3 a,float k) { return {a.x*k,a.y*k,a.z*k}; }
float dot(Vec3 a,Vec3 b) { return a.x*b.x+a.y*b.y+a.z*b.z; }
Vec3 cross(Vec3 a,Vec3 b) {
  return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};
}
Vec3 normalized(Vec3 v) { return v*(1.f/std::sqrt(dot(v,v))); }
constexpr uint32_t MATERIAL_COUNT=5, GROUND_COLOR=10, BACKGROUND_LINEAR=11,
  BACKGROUND_DISPLAY=12, HUD_PALE=13, HUD_CYAN=14, HUD_ACCENT=15,
  HUD_RESET=16, AIM_PROTECTED=17, BRUSH_PREVIEW=18;
Vec3 palette_color(const VoxelVkFrame& frame,uint32_t index) {
  return {frame.colors[index][0],frame.colors[index][1],frame.colors[index][2]};
}
Vec3 material_color(const VoxelVkFrame& frame,uint32_t id,bool detached) {
  if (id==0 || id>MATERIAL_COUNT) throw std::runtime_error("unknown voxel material");
  return palette_color(frame,(id-1)*2+(detached?1:0));
}
// Sides 0..5 are face normals; 6 marks flat HUD, brush, and line colors.
struct Vertex { Vec3 position,color; uint32_t side; };
struct Geometry { std::vector<Vertex> vertices; uint32_t triangles=0,lines=0,hud=0; };
using Clock=std::chrono::steady_clock;
uint32_t microseconds(Clock::time_point start,Clock::time_point end) {
  return uint32_t(std::chrono::duration_cast<std::chrono::microseconds>(end-start).count());
}
void quad(Geometry& g,Vec3 a,Vec3 b,Vec3 c,Vec3 d,Vec3 color,uint32_t side=6) {
  for (Vec3 p:{a,b,c,a,c,d}) g.vertices.push_back({p,color,side});
  g.triangles+=6;
}
void line(Geometry& g,Vec3 a,Vec3 b,Vec3 color) {
  g.vertices.push_back({a,color,6}); g.vertices.push_back({b,color,6}); g.lines+=2;
}
struct Glyph { char character; uint8_t rows[7]; };
// Five-column bitmap glyphs for the demo's uppercase ASCII HUD.
constexpr Glyph glyphs[]={
  {'A',{14,17,17,31,17,17,17}}, {'B',{30,17,17,30,17,17,30}},
  {'C',{14,17,16,16,16,17,14}}, {'D',{30,17,17,17,17,17,30}},
  {'E',{31,16,16,30,16,16,31}}, {'F',{31,16,16,30,16,16,16}},
  {'G',{14,17,16,23,17,17,14}}, {'H',{17,17,17,31,17,17,17}},
  {'I',{31,4,4,4,4,4,31}}, {'J',{7,2,2,2,18,18,12}},
  {'K',{17,18,20,24,20,18,17}}, {'L',{16,16,16,16,16,16,31}},
  {'M',{17,27,21,21,17,17,17}}, {'N',{17,25,21,19,17,17,17}},
  {'O',{14,17,17,17,17,17,14}}, {'P',{30,17,17,30,16,16,16}},
  {'Q',{14,17,17,17,21,18,13}}, {'R',{30,17,17,30,20,18,17}},
  {'S',{15,16,16,14,1,1,30}}, {'T',{31,4,4,4,4,4,4}},
  {'U',{17,17,17,17,17,17,14}}, {'V',{17,17,17,17,17,10,4}},
  {'W',{17,17,17,21,21,21,10}}, {'X',{17,17,10,4,10,17,17}},
  {'Y',{17,17,10,4,4,4,4}}, {'Z',{31,1,2,4,8,16,31}},
  {'0',{14,17,19,21,25,17,14}}, {'1',{4,12,4,4,4,4,14}},
  {'2',{14,17,1,2,4,8,31}}, {'3',{30,1,1,14,1,1,30}},
  {'4',{2,6,10,18,31,2,2}}, {'5',{31,16,16,30,1,1,30}},
  {'6',{14,16,16,30,17,17,14}}, {'7',{31,1,2,4,8,8,8}},
  {'8',{14,17,17,14,17,17,14}}, {'9',{14,17,17,15,1,1,14}},
  {'/',{1,1,2,4,8,16,16}}, {'-',{0,0,0,31,0,0,0}},
  {'?',{14,17,1,2,4,0,4}}
};
const uint8_t* glyph(char c) {
  for (const auto& entry:glyphs) if (entry.character==c) return entry.rows;
  return glyphs[sizeof(glyphs)/sizeof(glyphs[0])-1].rows;
}
void hud_text(Geometry& g,float x,float baseline,const char* begin,size_t length,Vec3 color,float scale) {
  for (size_t i=0;i<length;i++,x+=6*scale) {
    if (begin[i]==' ') continue;
    const uint8_t* rows=glyph(begin[i]);
    for (int y=0;y<7;y++) for (int bit=0;bit<5;bit++) if (rows[y]&(16>>bit)) {
      float left=x+bit*scale,top=baseline-10.5f*scale+y*1.5f*scale;
      Vec3 a{left,top,0},b{left+scale,top,0},c{left+scale,top+1.5f*scale,0},d{left,top+1.5f*scale,0};
      for (Vec3 p:{a,b,c,a,c,d}) g.vertices.push_back({p,color,6});
      g.hud+=6;
    }
  }
}
void add_hud(Geometry& g,const VoxelVkFrame& frame) {
  const char* hud=frame.hud;
  uint32_t width=frame.width,height=frame.height;
  float scale=std::min(float(width)/640.f,float(height)/360.f);
  // Keep the controls readable against the atelier's pale shadow receivers.
  Vec3 a{0,float(height)-51.f*scale,0},b{float(width),a.y,0},
    c{float(width),float(height),0},d{0,float(height),0};
  for (Vec3 p:{a,b,c,a,c,d})
    g.vertices.push_back({p,palette_color(frame,BACKGROUND_DISPLAY),6});
  g.hud+=6;
  const float ys[]={20.f*scale,38.f*scale,55.f*scale,72.f*scale,
    float(height)-35.f*scale,float(height)-13.f*scale};
  constexpr uint32_t colors[]={HUD_PALE,HUD_CYAN,HUD_CYAN,HUD_ACCENT,HUD_PALE,HUD_CYAN};
  if (hud) for (int row=0;row<6 && *hud;row++) {
    const char* end=std::strchr(hud,'\n');
    hud_text(g,12.f*scale,ys[row],hud,end?size_t(end-hud):std::strlen(hud),
      palette_color(frame,colors[row]),scale);
    if (!end) break;
    hud=end+1;
  }
  if (!frame.full_geometry) hud_text(g,float(width)-63.f*scale,20.f*scale,"RESET",5,
    palette_color(frame,HUD_RESET),scale);
}
Vec3 vector(const float* p) { return {p[0],p[1],p[2]}; }
void face_quad(Geometry& g,const VoxelVkFace& f,Vec3 color,float offset=0,bool lit=true) {
  uint32_t a=f.side/2,u=(a+1)%3,v=(a+2)%3;
  float p[4][3];
  for (auto& corner:p) for (uint32_t i=0;i<3;i++) corner[i]=f.lo[i]*.1f;
  p[1][u]=p[2][u]=f.hi[u]*.1f;
  p[2][v]=p[3][v]=f.hi[v]*.1f;
  for (auto& corner:p) corner[1]+=offset;
  // Culling is disabled, but keep the winding consistent with the outward normal.
  uint32_t side=lit?f.side:6;
  if (f.side%2) quad(g,vector(p[0]),vector(p[1]),vector(p[2]),vector(p[3]),color,side);
  else quad(g,vector(p[3]),vector(p[2]),vector(p[1]),vector(p[0]),color,side);
}
void face(Geometry& g,const VoxelVkFace& f,bool anchored,const VoxelVkFrame& frame) {
  if (f.side>=6) throw std::runtime_error("invalid Bend face");
  uint32_t a=f.side/2;
  for (uint32_t i=0;i<3;i++) {
    if (!std::isfinite(f.lo[i]) || !std::isfinite(f.hi[i]) ||
        (i==a ? f.hi[i]!=f.lo[i] : f.hi[i]<=f.lo[i]))
      throw std::runtime_error("invalid Bend face bounds");
  }
  face_quad(g,f,material_color(frame,f.material,!anchored));
}
void body_vertices(Geometry& g,const VoxelVkBody& body,const VoxelVkFrame& frame) {
  if (!body.vertex_count) {
    // The native geometry fixtures still provide faces directly.
    for (uint32_t i=0;i<body.face_count;i++) face(g,body.faces[i],body.anchored,frame);
    return;
  }
  if (body.vertex_count!=uint64_t(body.face_count)*6)
    throw std::runtime_error("invalid Bend body vertex count");
  g.vertices.reserve(body.vertex_count);
  for (uint32_t i=0;i<body.vertex_count;i++) {
    const auto& source=body.vertices[i];
    if (source.side>=6 || !std::isfinite(source.position[0]) ||
        !std::isfinite(source.position[1]) || !std::isfinite(source.position[2]))
      throw std::runtime_error("invalid Bend body vertex");
    g.vertices.push_back({vector(source.position),
      material_color(frame,source.material,!body.anchored),source.side});
  }
  g.triangles=body.vertex_count;
  if (std::getenv("VOXEL_VERIFY_BEND_MESH")) {
    Geometry expected;
    for (uint32_t i=0;i<body.face_count;i++) face(expected,body.faces[i],body.anchored,frame);
    if (expected.vertices.size()!=g.vertices.size())
      throw std::runtime_error("Bend body mesh vertex count differs from native reference");
    for (size_t i=0;i<g.vertices.size();i++) {
      const auto& a=g.vertices[i];
      const auto& b=expected.vertices[i];
      if (a.side!=b.side || std::memcmp(&a.position,&b.position,sizeof(Vec3)) ||
          std::memcmp(&a.color,&b.color,sizeof(Vec3)))
        throw std::runtime_error("Bend body mesh differs from native reference");
    }
  }
}
bool near_aim(const VoxelVkBody& body,const VoxelVkFrame& frame) {
  for (uint32_t i=0;i<3;i++) {
    float p=frame.aim[i]-(i==1?body.offset:0);
    if (p<body.lo[i]*.1f-.201f || p>body.hi[i]*.1f+.201f) return false;
  }
  return true;
}
void preview_face(Geometry& g,const VoxelVkFace& f,const VoxelVkBody& body,const VoxelVkFrame& frame) {
  if (f.material==1) return;
  uint32_t a=f.side/2,u=(a+1)%3,v=(a+2)%3;
  float aim[3]={frame.aim[0]*10,(frame.aim[1]-body.offset)*10,frame.aim[2]*10};
  float cell_a=f.lo[a]+(f.side%2?-.5f:.5f);
  if (std::abs(cell_a-aim[a])>2.00001f) return;
  float eye=frame.eye[a]-(a==1?body.offset:0);
  if ((eye-f.lo[a]*.1f)*(f.side%2?1.f:-1.f)<=0) return;
  // Clip the iteration to the 20 cm sphere, even for an enormous merged face.
  int u0=int(std::max(f.lo[u],std::ceil(aim[u]-2.50001f)));
  int u1=int(std::min(f.hi[u]-1,std::floor(aim[u]+1.50001f)));
  int v0=int(std::max(f.lo[v],std::ceil(aim[v]-2.50001f)));
  int v1=int(std::min(f.hi[v]-1,std::floor(aim[v]+1.50001f)));
  for (int x=u0;x<=u1;x++) for (int y=v0;y<=v1;y++) {
    float da=cell_a-aim[a],du=x+.5f-aim[u],dv=y+.5f-aim[v];
    if (da*da+du*du+dv*dv>4.00001f) continue;
    VoxelVkFace preview=f;
    preview.lo[u]=float(x); preview.hi[u]=float(x+1);
    preview.lo[v]=float(y); preview.hi[v]=float(y+1);
    preview.lo[a]=preview.hi[a]=f.lo[a]+(f.side%2?.01f:-.01f);
    face_quad(g,preview,palette_color(frame,BRUSH_PREVIEW),body.offset,false);
  }
}
Vec3 ring_point(Vec3 p,uint32_t axis,float angle) {
  float c=.2f*std::cos(angle),s=.2f*std::sin(angle);
  return axis==0?p+Vec3{0,c,s}:axis==1?p+Vec3{c,0,s}:p+Vec3{c,s,0};
}
struct ViewBasis {
  float sy,cy,sp,cp;
  explicit ViewBasis(const VoxelVkFrame& f):sy(std::sin(f.yaw)),cy(std::cos(f.yaw)),
    sp(std::sin(f.pitch)),cp(std::cos(f.pitch)) {}
};
constexpr uint32_t SHADOW_SIZE=2048;
struct ShadowMatrix { float values[16]{}; };
struct ShadowIdentity { uint32_t id,revision,anchored; float offset; };
bool shadow_changed(const std::vector<ShadowIdentity>& saved,const VoxelVkFrame& frame) {
  if (saved.size()!=frame.body_count) return true;
  for (uint32_t i=0;i<frame.body_count;i++) {
    const auto& a=saved[i];
    const auto& b=frame.bodies[i];
    if (a.id!=b.id || a.revision!=b.revision || a.anchored!=b.anchored ||
        a.offset!=b.offset) return true;
  }
  return false;
}
// Fit one orthographic sun map to the occupied world, including translated
// bodies. Camera motion changes only the main view; it does not move the map.
ShadowMatrix shadow_matrix(const VoxelVkFrame& frame) {
  Vec3 lo{INFINITY,INFINITY,INFINITY},hi{-INFINITY,-INFINITY,-INFINITY};
  for (uint32_t i=0;i<frame.body_count;i++) {
    const auto& b=frame.bodies[i];
    Vec3 a{b.lo[0]*.1f,b.lo[1]*.1f+b.offset,b.lo[2]*.1f};
    Vec3 z{b.hi[0]*.1f,b.hi[1]*.1f+b.offset,b.hi[2]*.1f};
    lo={std::min(lo.x,a.x),std::min(lo.y,a.y),std::min(lo.z,a.z)};
    hi={std::max(hi.x,z.x),std::max(hi.y,z.y),std::max(hi.z,z.z)};
  }
  if (!frame.body_count) { lo={-16,0,-16}; hi={16,32,16}; }
  lo=lo-Vec3{8,4,8}; hi=hi+Vec3{8,8,8};
  Vec3 toward_sun=normalized({-.62f,.62f,.48f});
  Vec3 right=normalized(cross({0,1,0},toward_sun));
  Vec3 up=cross(toward_sun,right),forward=toward_sun*(-1.f);
  Vec3 low{INFINITY,INFINITY,INFINITY},high{-INFINITY,-INFINITY,-INFINITY};
  for (unsigned corner=0;corner<8;corner++) {
    Vec3 p{corner&1?hi.x:lo.x,corner&2?hi.y:lo.y,corner&4?hi.z:lo.z};
    Vec3 q{dot(p,right),dot(p,up),dot(p,forward)};
    low={std::min(low.x,q.x),std::min(low.y,q.y),std::min(low.z,q.z)};
    high={std::max(high.x,q.x),std::max(high.y,q.y),std::max(high.z,q.z)};
  }
  low=low-Vec3{2,2,4}; high=high+Vec3{2,2,4};
  float sx=2.f/(high.x-low.x),sy=2.f/(high.y-low.y),sz=1.f/(high.z-low.z);
  float rows[4][4]={{right.x*sx,right.y*sx,right.z*sx,-1.f-low.x*sx},
    {up.x*sy,up.y*sy,up.z*sy,-1.f-low.y*sy},
    {forward.x*sz,forward.y*sz,forward.z*sz,-low.z*sz},{0,0,0,1}};
  ShadowMatrix result;
  for (unsigned row=0;row<4;row++) for (unsigned col=0;col<4;col++)
    result.values[col*4+row]=rows[row][col]; // GLSL mat4 column-major order.
  return result;
}
Vec3 view_position(Vec3 p,const VoxelVkFrame& f,const ViewBasis& basis) {
  float sy=basis.sy,cy=basis.cy,sp=basis.sp,cp=basis.cp;
  Vec3 d=p-Vec3{f.eye[0],f.eye[1],f.eye[2]};
  return {dot(d,{-cy,0,sy}),dot(d,{-sy*sp,cp,-cy*sp}),dot(d,{sy*cp,sp,cy*cp})};
}
float view_depth(Vec3 p,const VoxelVkFrame& f,const ViewBasis& basis) {
  return view_position(p,f,basis).z;
}
bool visible(const VoxelVkBody& body,const VoxelVkFrame& frame,const ViewBasis& basis) {
  unsigned outside=31;
  float horizontal=800.f*float(frame.height)/(360.f*float(frame.width));
  for (unsigned corner=0;corner<8;corner++) {
    Vec3 p={(corner&1?body.hi[0]:body.lo[0])*.1f,
      (corner&2?body.hi[1]:body.lo[1])*.1f+body.offset,
      (corner&4?body.hi[2]:body.lo[2])*.1f};
    auto v=view_position(p,frame,basis);
    unsigned mask=(v.z<.05f?1u:0u)|(v.x*horizontal>v.z?2u:0u)|
      (-v.x*horizontal>v.z?4u:0u)|(v.y*(400.f/180)>v.z?8u:0u)|
      (-v.y*(400.f/180)>v.z?16u:0u);
    outside&=mask;
  }
  return outside==0;
}
struct Range { uint32_t first,count; };
struct Draw { uint32_t first,count; float offset; };
struct Mesh { uint32_t revision,anchored,first,count,seen; };
struct Proxy {
  std::vector<uint64_t> members;
  uint32_t first,count,seen;
  bool selected;
};
struct BodyIdentity { uint32_t id,revision,anchored; };
struct ProxyGroup {
  std::vector<uint32_t> bodies;
  std::vector<uint64_t> members;
  std::array<float,3> lo,hi;
  bool selected=false;
  uint32_t visible_bodies=0;
  ProxyGroup():lo{INFINITY,INFINITY,INFINITY},hi{-INFINITY,-INFINITY,-INFINITY} {}
};
// Render tiles are independent of the world's cuboid and component boundaries.
// A 64 m tile groups small static objects, while large structures and all
// detached bodies retain their full meshes.
bool proxy_eligible(const VoxelVkBody& body) {
  if (!body.anchored || body.offset!=0 || !body.face_count) return false;
  for (uint32_t axis=0;axis<3;axis++)
    if (body.hi[axis]-body.lo[axis]>35.f) return false;
  return true;
}
uint64_t proxy_key(const VoxelVkBody& body) {
  int32_t x=int32_t(std::floor(((body.lo[0]+body.hi[0])*.5f+320.f)/640.f));
  int32_t z=int32_t(std::floor(((body.lo[2]+body.hi[2])*.5f+320.f)/640.f));
  return (uint64_t(uint32_t(x))<<32)|uint32_t(z);
}
void proxy_add(ProxyGroup& group,const VoxelVkBody& body,uint32_t index) {
  group.bodies.push_back(index);
  group.members.push_back((uint64_t(body.id)<<32)|body.revision);
  for (uint32_t axis=0;axis<3;axis++) {
    group.lo[axis]=std::min(group.lo[axis],body.lo[axis]);
    group.hi[axis]=std::max(group.hi[axis],body.hi[axis]);
  }
}
float proxy_pixels(const ProxyGroup& group,const VoxelVkFrame& frame,const ViewBasis& basis) {
  Vec3 center={(group.lo[0]+group.hi[0])*.05f,
    (group.lo[1]+group.hi[1])*.05f,(group.lo[2]+group.hi[2])*.05f};
  Vec3 half={(group.hi[0]-group.lo[0])*.05f,
    (group.hi[1]-group.lo[1])*.05f,(group.hi[2]-group.lo[2])*.05f};
  float radius=std::sqrt(dot(half,half));
  float depth=view_depth(center,frame,basis)-radius;
  return depth<=.05f ? INFINITY : 800.f*(float(frame.height)/360.f)*radius/depth;
}
bool proxy_near_aim(const ProxyGroup& group,const VoxelVkFrame& frame) {
  if (!frame.aim_kind) return false;
  for (uint32_t axis=0;axis<3;axis++)
    if (frame.aim[axis]*10.f<group.lo[axis]-2.f ||
        frame.aim[axis]*10.f>group.hi[axis]+2.f) return false;
  return true;
}
bool proxy_visible(const ProxyGroup& group,const VoxelVkFrame& frame,const ViewBasis& basis) {
  VoxelVkBody bounds{};
  for (uint32_t axis=0;axis<3;axis++) {
    bounds.lo[axis]=group.lo[axis]; bounds.hi[axis]=group.hi[axis];
  }
  return visible(bounds,frame,basis);
}
uint32_t proxy_material(const VoxelVkBody& body) {
  std::array<float,MATERIAL_COUNT+1> area{};
  for (uint32_t i=0;i<body.face_count;i++) {
    const auto& f=body.faces[i];
    if (f.material==0 || f.material>MATERIAL_COUNT)
      throw std::runtime_error("unknown voxel material");
    if (f.side>=6) throw std::runtime_error("invalid Bend face");
    uint32_t u=(f.side/2+1)%3,v=(f.side/2+2)%3;
    area[f.material]+=(f.hi[u]-f.lo[u])*(f.hi[v]-f.lo[v]);
  }
  return uint32_t(std::max_element(area.begin()+1,area.end())-area.begin());
}
void proxy_box(Geometry& mesh,const VoxelVkBody& body,const VoxelVkFrame& frame) {
  uint32_t m=proxy_material(body);
  for (uint32_t side=0;side<6;side++) {
    VoxelVkFace f{};
    for (uint32_t axis=0;axis<3;axis++) {
      f.lo[axis]=body.lo[axis]; f.hi[axis]=body.hi[axis];
    }
    uint32_t axis=side/2;
    f.lo[axis]=f.hi[axis]=side%2 ? body.hi[axis] : body.lo[axis];
    f.side=side; f.material=m;
    face(mesh,f,true,frame);
  }
}
struct GeometryCache {
  Geometry geometry;
  std::unordered_map<uint32_t,Mesh> meshes;
  std::unordered_map<uint64_t,Proxy> proxies;
  std::vector<BodyIdentity> group_world;
  std::map<uint64_t,ProxyGroup> groups;
  std::vector<ProxyGroup*> group_for_body;
  std::vector<Range> free,dirty;
  std::vector<Draw> draws;
  std::vector<Draw> shadow_draws;
  uint32_t scene_vertices=0,generation=0,rebuilt=0,proxy_rebuilt=0;
  uint32_t proxy_draws=0,proxied_bodies=0,visible_bodies=0;
  size_t proxy_vertices=0;
  void release(Range range) {
    free.push_back(range);
    std::sort(free.begin(),free.end(),[](Range a,Range b){return a.first<b.first;});
    std::vector<Range> joined;
    for (auto r:free) {
      if (!joined.empty() && joined.back().first+joined.back().count==r.first)
        joined.back().count+=r.count;
      else joined.push_back(r);
    }
    free.swap(joined);
  }
  uint32_t allocate(uint32_t count) {
    for (size_t i=0;i<free.size();i++) if (free[i].count>=count) {
      uint32_t first=free[i].first;
      free[i].first+=count; free[i].count-=count;
      if (!free[i].count) free.erase(free.begin()+i);
      return first;
    }
    if (count>UINT32_MAX-scene_vertices) throw std::runtime_error("vertex arena overflow");
    uint32_t first=scene_vertices; scene_vertices+=count;
    return first;
  }
};
// Full meshes use body ID + revision + anchor status. Proxy groups use their
// member IDs and revisions; camera, aim, culling, and transforms only select
// draws/overlays. Dirty ranges upload edited meshes and changed proxies.
Geometry& geometry(const VoxelVkFrame& frame,GeometryCache& cache,bool& scene_reused) {
  Geometry& g=cache.geometry;
  ViewBasis basis(frame);
  cache.generation++; cache.dirty.clear(); cache.draws.clear(); cache.shadow_draws.clear(); cache.rebuilt=0;
  cache.proxy_rebuilt=cache.proxy_draws=cache.proxied_bodies=cache.visible_bodies=0;
  cache.proxy_vertices=0;
  if (!cache.scene_vertices) {
    float h=frame.full_geometry ? frame.ground_half_extent : 512.f;
    if (!std::isfinite(h) || h<=0) throw std::runtime_error("invalid visual ground bounds");
    quad(g,{-h,0,-h},{-h,0,h},{h,0,h},{h,0,-h},
      palette_color(frame,GROUND_COLOR),3);
    cache.scene_vertices=6; cache.dirty.push_back({0,6});
  }
  bool world_changed=cache.group_world.size()!=frame.body_count;
  for (uint32_t i=0;i<frame.body_count;i++) {
    const auto& body=frame.bodies[i];
    auto it=cache.meshes.find(body.id);
    if (it!=cache.meshes.end()) it->second.seen=cache.generation;
    if (!world_changed) {
      const auto& old=cache.group_world[i];
      world_changed=old.id!=body.id || old.revision!=body.revision || old.anchored!=body.anchored;
    }
  }
  for (auto it=cache.meshes.begin();it!=cache.meshes.end();) {
    if (it->second.seen!=cache.generation) {
      cache.release({it->second.first,it->second.count});
      it=cache.meshes.erase(it);
    } else ++it;
  }
  if (world_changed) {
    cache.group_world.clear(); cache.groups.clear();
    cache.group_for_body.assign(frame.body_count,nullptr);
    for (uint32_t i=0;i<frame.body_count;i++) {
      const auto& body=frame.bodies[i];
      cache.group_world.push_back({body.id,body.revision,body.anchored});
      if (proxy_eligible(body)) proxy_add(cache.groups[proxy_key(body)],body,i);
    }
    for (auto it=cache.groups.begin();it!=cache.groups.end();) {
      if (it->second.bodies.size()<4) { it=cache.groups.erase(it); continue; }
      std::sort(it->second.members.begin(),it->second.members.end());
      for (auto index:it->second.bodies) cache.group_for_body[index]=&it->second;
      ++it;
    }
  }
  for (auto it=cache.groups.begin();it!=cache.groups.end();++it) {
    it->second.visible_bodies=0;
    auto prior=cache.proxies.find(it->first);
    bool was_selected=prior!=cache.proxies.end() && prior->second.selected;
    it->second.selected=proxy_pixels(it->second,frame,basis)<(was_selected?100.f:80.f) &&
      !proxy_near_aim(it->second,frame);
  }
  g.vertices.resize(cache.scene_vertices);
  for (uint32_t i=0;i<frame.body_count;i++) {
    const auto& b=frame.bodies[i];
    auto it=cache.meshes.find(b.id);
    if (it==cache.meshes.end() || it->second.revision!=b.revision || it->second.anchored!=b.anchored) {
      if (it!=cache.meshes.end()) cache.release({it->second.first,it->second.count});
      Geometry mesh;
      body_vertices(mesh,b,frame);
      uint32_t first=cache.allocate(mesh.triangles);
      g.vertices.resize(cache.scene_vertices);
      std::copy(mesh.vertices.begin(),mesh.vertices.end(),g.vertices.begin()+first);
      cache.dirty.push_back({first,mesh.triangles}); cache.rebuilt++;
      cache.meshes[b.id]={b.revision,b.anchored,first,mesh.triangles,cache.generation};
    }
    const auto& mesh=cache.meshes.at(b.id);
    // Sun depth uses full meshes, independent of camera, aim, and render LOD.
    cache.shadow_draws.push_back({mesh.first,mesh.count,b.offset});
    auto group=cache.group_for_body[i];
    if (visible(b,frame,basis)) {
      cache.visible_bodies++;
      if (frame.full_geometry || !group || !group->selected)
        cache.draws.push_back({mesh.first,mesh.count,b.offset});
      else group->visible_bodies++;
    }
  }
  for (auto& [key,group]:cache.groups) {
    auto it=cache.proxies.find(key);
    if (it==cache.proxies.end() || it->second.members!=group.members) {
      if (it!=cache.proxies.end()) cache.release({it->second.first,it->second.count});
      Geometry mesh;
      for (auto index:group.bodies) proxy_box(mesh,frame.bodies[index],frame);
      uint32_t first=cache.allocate(mesh.triangles);
      g.vertices.resize(cache.scene_vertices);
      std::copy(mesh.vertices.begin(),mesh.vertices.end(),g.vertices.begin()+first);
      cache.dirty.push_back({first,mesh.triangles}); cache.proxy_rebuilt++;
      cache.proxies[key]={group.members,first,mesh.triangles,
        cache.generation,group.selected};
      it=cache.proxies.find(key);
    } else {
      it->second.seen=cache.generation;
      it->second.selected=group.selected;
    }
    cache.proxy_vertices+=it->second.count;
    if (!frame.full_geometry && group.selected && group.visible_bodies && proxy_visible(group,frame,basis)) {
      cache.draws.push_back({it->second.first,it->second.count,0});
      cache.proxy_draws++; cache.proxied_bodies+=group.visible_bodies;
    }
  }
  for (auto it=cache.proxies.begin();it!=cache.proxies.end();) {
    if (it->second.seen!=cache.generation) {
      cache.release({it->second.first,it->second.count});
      it=cache.proxies.erase(it);
    } else ++it;
  }
  scene_reused=cache.dirty.empty();
  g.triangles=cache.scene_vertices; g.lines=0; g.hud=0;
  if (frame.aim_kind==1) for (uint32_t i=0;i<frame.body_count;i++) {
    const auto& b=frame.bodies[i];
    if (near_aim(b,frame)) for (uint32_t f=0;f<b.face_count;f++) preview_face(g,b.faces[f],b,frame);
  }
  if (frame.aim_kind) {
    Vec3 p={frame.aim[0],frame.aim[1],frame.aim[2]};
    Vec3 color=palette_color(frame,frame.aim_kind==1?HUD_ACCENT:AIM_PROTECTED);
    for (uint32_t axis=0;axis<3;axis++) for (uint32_t i=0;i<12;i++) {
      Vec3 a=ring_point(p,axis,float(i)*.5235988f),b=ring_point(p,axis,float(i+1)*.5235988f);
      if (view_depth(a,frame,basis)>=.05f && view_depth(b,frame,basis)>=.05f) line(g,a,b,color);
    }
  }
  add_hud(g,frame);
  return g;
}
// Verify actual cached mesh slots and submitted draw ranges, independent of slot
// allocation order. Culling is checked against unculled full-mesh triangles.
void audit_native(const VoxelVkFrame& f,const GeometryCache& cache) {
  using checkpoint::require;
  require(f.full_geometry&&cache.meshes.size()==f.body_count,"native full-mesh ownership mismatch");
  require(cache.proxy_draws==0&&cache.shadow_draws.size()==f.body_count,"native shadow/proxy draw mismatch");
  uint64_t vertices_checked=0,reference_visible=0;
  std::vector<checkpoint::J> drawn_ids;
  for(unsigned i=0;i<f.body_count;i++) {
    const auto& b=f.bodies[i]; auto it=cache.meshes.find(b.id);
    require(it!=cache.meshes.end(),"missing native mesh"); const auto& mesh=it->second;
    require(mesh.revision==b.revision&&mesh.anchored==b.anchored&&mesh.count==b.vertex_count,"native mesh identity mismatch");
    require(uint64_t(mesh.first)+mesh.count<=cache.geometry.vertices.size(),"native mesh range overflow");
    for(unsigned j=0;j<b.vertex_count;j++) {
      const auto& actual=cache.geometry.vertices[mesh.first+j]; const auto& expected=b.vertices[j];
      auto color=material_color(f,expected.material,!b.anchored);
      require(std::memcmp(&actual.position,expected.position,12)==0&&actual.side==expected.side&&
        std::memcmp(&actual.color,&color,sizeof color)==0,"stale native mesh vertex/material");
      vertices_checked++;
    }
    auto matches=[&](const Draw& d){return d.first==mesh.first&&d.count==mesh.count&&checkpoint::real(d.offset)==checkpoint::real(b.offset);};
    auto drawn=std::count_if(cache.draws.begin(),cache.draws.end(),matches);
    require(drawn<=1&&std::count_if(cache.shadow_draws.begin(),cache.shadow_draws.end(),matches)==1,"duplicate/missing native draw");
    bool visible_reference=visibility_reference::body(b,f); reference_visible+=visible_reference;
    require(!visible_reference||drawn==1,"visible full geometry was culled");
    if(drawn) drawn_ids.push_back(checkpoint::number(b.id));
  }
  require(drawn_ids.size()==cache.draws.size(),"unknown native draw ownership");
  auto record=checkpoint::object({{"drawn_ids",checkpoint::array(drawn_ids)},
    {"record_type",checkpoint::quote("native_audit")},{"reference_visible",checkpoint::number(reference_visible)},
    {"vertices_checked",checkpoint::number(vertices_checked)}});
  f.record(record.substr(1,record.size()-2).c_str());
}

std::vector<uint32_t> spirv(const char* path) {
  std::ifstream in(path,std::ios::binary|std::ios::ate);
  if (!in) throw std::runtime_error(std::string("cannot open shader ")+path);
  auto size=in.tellg();
  if (size<=0 || size%4) throw std::runtime_error("invalid SPIR-V file");
  std::vector<uint32_t> code(size/4);
  in.seekg(0); in.read(reinterpret_cast<char*>(code.data()),size);
  return code;
}
// These CPU markers share CLOCK_MONOTONIC with the runner and bridge. They
// measure actual boundaries, including intervening instrumentation and waits.
uint32_t float_bits(float value) {
  uint32_t bits;
  std::memcpy(&bits,&value,sizeof bits);
  return bits;
}
uint64_t monotonic_ns() {
  timespec now{};
  if (clock_gettime(CLOCK_MONOTONIC,&now)) throw std::runtime_error("monotonic clock failed");
  return uint64_t(now.tv_sec)*1000000000ull+uint64_t(now.tv_nsec);
}
void stage(const VoxelVkFrame& frame,const char* name,uint64_t begin,uint64_t end) {
  if (!frame.record) return;
  char record[512];
  std::snprintf(record,sizeof record,
    "\"record_type\":\"stage\",\"stage\":\"%s\",\"begin_ns\":\"%llu\",\"end_ns\":\"%llu\",\"duration_ns\":\"%llu\",\"status\":\"measured\",\"unit\":\"ns\",\"scope\":\"cpu_stage\"",
    name,(unsigned long long)begin,(unsigned long long)end,(unsigned long long)(end-begin));
  frame.record(record);
}
VkPresentModeKHR unpaced_mode(const std::vector<VkPresentModeKHR>& modes) {
  for (auto mode:{VK_PRESENT_MODE_IMMEDIATE_KHR,VK_PRESENT_MODE_MAILBOX_KHR})
    if (std::find(modes.begin(),modes.end(),mode)!=modes.end()) return mode;
  throw std::runtime_error("unpaced Vulkan present mode unavailable");
}
struct Push { float eye_yaw[4],pitch_offset[4],viewport[4],shadow_matrix[16]; };
static_assert(sizeof(Push)==112,"shadow push constants must fit Vulkan's 128-byte minimum");

class Renderer {
  Display* display;
  ::Window window;
  VkInstance instance=VK_NULL_HANDLE;
  VkSurfaceKHR surface=VK_NULL_HANDLE;
  VkPhysicalDevice physical=VK_NULL_HANDLE;
  VkSurfaceCapabilitiesKHR frozen_surface{};
  VkDevice device=VK_NULL_HANDLE;
  VkQueue queue=VK_NULL_HANDLE;
  uint32_t family=0;
  VkSwapchainKHR swapchain=VK_NULL_HANDLE;
  VkFormat format=VK_FORMAT_UNDEFINED;
  VkPresentModeKHR present_mode=VK_PRESENT_MODE_FIFO_KHR;
  bool settings_recorded=false;
  VkExtent2D extent{DEFAULT_WIDTH,DEFAULT_HEIGHT};
  std::vector<VkImage> images;
  std::vector<VkImageView> views;
  std::vector<VkSemaphore> finished;
  VkImage depth=VK_NULL_HANDLE;
  VkDeviceMemory depth_memory=VK_NULL_HANDLE;
  VkImageView depth_view=VK_NULL_HANDLE;
  VkImage shadow_image=VK_NULL_HANDLE;
  VkDeviceMemory shadow_memory=VK_NULL_HANDLE;
  VkImageView shadow_view=VK_NULL_HANDLE;
  VkSampler shadow_sampler=VK_NULL_HANDLE;
  VkDescriptorSetLayout shadow_set_layout=VK_NULL_HANDLE;
  VkDescriptorPool shadow_pool=VK_NULL_HANDLE;
  VkDescriptorSet shadow_set=VK_NULL_HANDLE;
  VkBuffer vertices=VK_NULL_HANDLE;
  VkDeviceMemory vertex_memory=VK_NULL_HANDLE;
  VkDeviceSize capacity=0;
  void* mapped=nullptr;
  VkShaderModule vs=VK_NULL_HANDLE,fs=VK_NULL_HANDLE,shadow_vs=VK_NULL_HANDLE;
  VkPipelineLayout layout=VK_NULL_HANDLE;
  VkPipeline triangles=VK_NULL_HANDLE,lines=VK_NULL_HANDLE,hud_pipeline=VK_NULL_HANDLE,
    shadow_pipeline=VK_NULL_HANDLE;
  VkCommandPool pool=VK_NULL_HANDLE;
  VkCommandBuffer command=VK_NULL_HANDLE;
  VkFence fence=VK_NULL_HANDLE;
  VkSemaphore acquired=VK_NULL_HANDLE;
  GeometryCache geometry_cache;
  std::vector<ShadowIdentity> shadow_world;
  ShadowMatrix saved_shadow;
  bool shadow_valid=false;
  gpu_timing::Queries gpu_queries;

  uint32_t memory_type(uint32_t bits,VkMemoryPropertyFlags flags) {
    VkPhysicalDeviceMemoryProperties p{}; vkGetPhysicalDeviceMemoryProperties(physical,&p);
    for (uint32_t i=0;i<p.memoryTypeCount;i++)
      if ((bits&(1u<<i))&&(p.memoryTypes[i].propertyFlags&flags)==flags) return i;
    throw std::runtime_error("required Vulkan memory type unavailable");
  }
  void make_depth() {
    VkImageCreateInfo info{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    info.imageType=VK_IMAGE_TYPE_2D; info.format=VK_FORMAT_D32_SFLOAT;
    info.extent={extent.width,extent.height,1}; info.mipLevels=1; info.arrayLayers=1;
    info.samples=VK_SAMPLE_COUNT_1_BIT; info.tiling=VK_IMAGE_TILING_OPTIMAL;
    info.usage=VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
    check(vkCreateImage(device,&info,nullptr,&depth),"create depth image");
    VkMemoryRequirements req{}; vkGetImageMemoryRequirements(device,depth,&req);
    VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    ai.allocationSize=req.size; ai.memoryTypeIndex=memory_type(req.memoryTypeBits,VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    check(supervision::allocate(device,physical,&ai,&depth_memory),"allocate depth image");
    check(vkBindImageMemory(device,depth,depth_memory,0),"bind depth image");
    VkImageViewCreateInfo vi{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    vi.image=depth; vi.viewType=VK_IMAGE_VIEW_TYPE_2D; vi.format=VK_FORMAT_D32_SFLOAT;
    vi.subresourceRange={VK_IMAGE_ASPECT_DEPTH_BIT,0,1,0,1};
    check(vkCreateImageView(device,&vi,nullptr,&depth_view),"create depth view");
  }
  void make_shadow() {
    VkFormatProperties properties{};
    vkGetPhysicalDeviceFormatProperties(physical,VK_FORMAT_D32_SFLOAT,&properties);
    if ((properties.optimalTilingFeatures&(VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT|
        VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT))!=
        (VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT|VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT))
      throw std::runtime_error("sampled D32 shadow map unsupported");
    VkImageCreateInfo info{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    info.imageType=VK_IMAGE_TYPE_2D; info.format=VK_FORMAT_D32_SFLOAT;
    info.extent={SHADOW_SIZE,SHADOW_SIZE,1}; info.mipLevels=1; info.arrayLayers=1;
    info.samples=VK_SAMPLE_COUNT_1_BIT; info.tiling=VK_IMAGE_TILING_OPTIMAL;
    info.usage=VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT|VK_IMAGE_USAGE_SAMPLED_BIT;
    check(vkCreateImage(device,&info,nullptr,&shadow_image),"create sun shadow image");
    VkMemoryRequirements req{}; vkGetImageMemoryRequirements(device,shadow_image,&req);
    VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    ai.allocationSize=req.size;
    ai.memoryTypeIndex=memory_type(req.memoryTypeBits,VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    check(supervision::allocate(device,physical,&ai,&shadow_memory),"allocate sun shadow image");
    check(vkBindImageMemory(device,shadow_image,shadow_memory,0),"bind sun shadow image");
    VkImageViewCreateInfo vi{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    vi.image=shadow_image; vi.viewType=VK_IMAGE_VIEW_TYPE_2D; vi.format=VK_FORMAT_D32_SFLOAT;
    vi.subresourceRange={VK_IMAGE_ASPECT_DEPTH_BIT,0,1,0,1};
    check(vkCreateImageView(device,&vi,nullptr,&shadow_view),"create sun shadow view");
    VkSamplerCreateInfo si{VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
    si.magFilter=VK_FILTER_NEAREST; si.minFilter=VK_FILTER_NEAREST;
    si.mipmapMode=VK_SAMPLER_MIPMAP_MODE_NEAREST;
    si.addressModeU=si.addressModeV=si.addressModeW=VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER;
    si.borderColor=VK_BORDER_COLOR_FLOAT_OPAQUE_WHITE;
    si.compareEnable=VK_TRUE; si.compareOp=VK_COMPARE_OP_LESS_OR_EQUAL;
    si.maxLod=1;
    check(vkCreateSampler(device,&si,nullptr,&shadow_sampler),"create sun shadow sampler");
    VkDescriptorSetLayoutBinding binding{};
    binding.binding=0; binding.descriptorType=VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    binding.descriptorCount=1; binding.stageFlags=VK_SHADER_STAGE_FRAGMENT_BIT;
    VkDescriptorSetLayoutCreateInfo li{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    li.bindingCount=1; li.pBindings=&binding;
    check(vkCreateDescriptorSetLayout(device,&li,nullptr,&shadow_set_layout),"create sun shadow layout");
    VkDescriptorPoolSize size{VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,1};
    VkDescriptorPoolCreateInfo pi{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    pi.maxSets=1; pi.poolSizeCount=1; pi.pPoolSizes=&size;
    check(vkCreateDescriptorPool(device,&pi,nullptr,&shadow_pool),"create sun shadow descriptor pool");
    VkDescriptorSetAllocateInfo di{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
    di.descriptorPool=shadow_pool; di.descriptorSetCount=1; di.pSetLayouts=&shadow_set_layout;
    check(vkAllocateDescriptorSets(device,&di,&shadow_set),"allocate sun shadow descriptor");
    VkDescriptorImageInfo image{shadow_sampler,shadow_view,VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL};
    VkWriteDescriptorSet write{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET};
    write.dstSet=shadow_set; write.dstBinding=0; write.descriptorCount=1;
    write.descriptorType=VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER; write.pImageInfo=&image;
    vkUpdateDescriptorSets(device,1,&write,0,nullptr);
  }
  void clear_swapchain() {
    for (VkSemaphore s:finished) vkDestroySemaphore(device,s,nullptr);
    finished.clear();
    for (VkImageView v:views) vkDestroyImageView(device,v,nullptr);
    views.clear(); images.clear();
    if (triangles) vkDestroyPipeline(device,triangles,nullptr);
    triangles=VK_NULL_HANDLE;
    if (lines) vkDestroyPipeline(device,lines,nullptr);
    lines=VK_NULL_HANDLE;
    if (hud_pipeline) vkDestroyPipeline(device,hud_pipeline,nullptr);
    hud_pipeline=VK_NULL_HANDLE;
    if (shadow_pipeline) vkDestroyPipeline(device,shadow_pipeline,nullptr);
    shadow_pipeline=VK_NULL_HANDLE;
    if (depth_view) vkDestroyImageView(device,depth_view,nullptr);
    depth_view=VK_NULL_HANDLE;
    if (depth) vkDestroyImage(device,depth,nullptr);
    depth=VK_NULL_HANDLE;
    if (depth_memory) supervision::free(device,depth_memory);
    depth_memory=VK_NULL_HANDLE;
    if (swapchain) vkDestroySwapchainKHR(device,swapchain,nullptr);
    swapchain=VK_NULL_HANDLE;
  }
  VkPipeline pipeline(VkPrimitiveTopology topology,bool depth_test,bool shadow=false) {
    VkPipelineShaderStageCreateInfo stages[2]{};
    stages[0].sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[0].stage=VK_SHADER_STAGE_VERTEX_BIT; stages[0].module=shadow?shadow_vs:vs; stages[0].pName="main";
    stages[1].sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[1].stage=VK_SHADER_STAGE_FRAGMENT_BIT; stages[1].module=fs; stages[1].pName="main";
    uint32_t srgb_attachment=(format==VK_FORMAT_B8G8R8A8_SRGB || format==VK_FORMAT_R8G8B8A8_SRGB);
    VkSpecializationMapEntry transfer_entry{0,0,sizeof(srgb_attachment)};
    VkSpecializationInfo transfer{1,&transfer_entry,sizeof(srgb_attachment),&srgb_attachment};
    stages[1].pSpecializationInfo=&transfer;
    VkVertexInputBindingDescription binding{0,sizeof(Vertex),VK_VERTEX_INPUT_RATE_VERTEX};
    VkVertexInputAttributeDescription attrs[3]={{0,0,VK_FORMAT_R32G32B32_SFLOAT,offsetof(Vertex,position)},
      {1,0,VK_FORMAT_R32G32B32_SFLOAT,offsetof(Vertex,color)},
      {2,0,VK_FORMAT_R32_UINT,offsetof(Vertex,side)}};
    VkPipelineVertexInputStateCreateInfo input{VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
    input.vertexBindingDescriptionCount=1; input.pVertexBindingDescriptions=&binding;
    input.vertexAttributeDescriptionCount=shadow?1:3; input.pVertexAttributeDescriptions=attrs;
    VkPipelineInputAssemblyStateCreateInfo assembly{VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO};
    assembly.topology=topology;
    VkPipelineViewportStateCreateInfo viewport{VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO};
    viewport.viewportCount=1; viewport.scissorCount=1;
    VkDynamicState dynamic_states[]={VK_DYNAMIC_STATE_VIEWPORT,VK_DYNAMIC_STATE_SCISSOR};
    VkPipelineDynamicStateCreateInfo dynamic{VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO};
    dynamic.dynamicStateCount=2; dynamic.pDynamicStates=dynamic_states;
    VkPipelineRasterizationStateCreateInfo raster{VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO};
    raster.polygonMode=VK_POLYGON_MODE_FILL; raster.cullMode=VK_CULL_MODE_NONE; raster.lineWidth=1;
    raster.depthBiasEnable=shadow; raster.depthBiasConstantFactor=1.25f;
    raster.depthBiasSlopeFactor=1.5f;
    VkPipelineMultisampleStateCreateInfo ms{VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO};
    ms.rasterizationSamples=VK_SAMPLE_COUNT_1_BIT;
    VkPipelineDepthStencilStateCreateInfo ds{VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO};
    ds.depthTestEnable=depth_test; ds.depthWriteEnable=depth_test; ds.depthCompareOp=VK_COMPARE_OP_LESS;
    VkPipelineColorBlendAttachmentState attachment{};
    attachment.colorWriteMask=VK_COLOR_COMPONENT_R_BIT|VK_COLOR_COMPONENT_G_BIT|
      VK_COLOR_COMPONENT_B_BIT|VK_COLOR_COMPONENT_A_BIT;
    VkPipelineColorBlendStateCreateInfo blend{VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
    blend.attachmentCount=shadow?0:1; blend.pAttachments=shadow?nullptr:&attachment;
    VkPipelineRenderingCreateInfo rendering{VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO};
    rendering.colorAttachmentCount=shadow?0:1;
    rendering.pColorAttachmentFormats=shadow?nullptr:&format;
    rendering.depthAttachmentFormat=VK_FORMAT_D32_SFLOAT;
    VkGraphicsPipelineCreateInfo info{VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO};
    info.pNext=&rendering; info.stageCount=shadow?1:2; info.pStages=stages;
    info.pVertexInputState=&input; info.pInputAssemblyState=&assembly;
    info.pViewportState=&viewport; info.pRasterizationState=&raster;
    info.pMultisampleState=&ms; info.pDepthStencilState=&ds; info.pColorBlendState=&blend;
    info.pDynamicState=&dynamic; info.layout=layout;
    VkPipeline result=VK_NULL_HANDLE;
    check(vkCreateGraphicsPipelines(device,VK_NULL_HANDLE,1,&info,nullptr,&result),"create graphics pipeline");
    return result;
  }
  void make_swapchain() {
    VkSurfaceCapabilitiesKHR caps{};
    check(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical,surface,&caps),"query surface capabilities");
    if (caps.currentExtent.width!=UINT32_MAX) extent=caps.currentExtent;
    else {
      XWindowAttributes attr{}; XGetWindowAttributes(display,window,&attr);
      extent={std::clamp(uint32_t(std::max(attr.width,1)),caps.minImageExtent.width,caps.maxImageExtent.width),
        std::clamp(uint32_t(std::max(attr.height,1)),caps.minImageExtent.height,caps.maxImageExtent.height)};
    }
    uint32_t n=0;
    check(vkGetPhysicalDeviceSurfaceFormatsKHR(physical,surface,&n,nullptr),"query surface formats");
    if (!n) throw std::runtime_error("no Vulkan surface formats");
    std::vector<VkSurfaceFormatKHR> formats(n);
    check(vkGetPhysicalDeviceSurfaceFormatsKHR(physical,surface,&n,formats.data()),"query surface formats");
    VkSurfaceFormatKHR chosen{};
    for (auto preferred:{VK_FORMAT_B8G8R8A8_UNORM,VK_FORMAT_R8G8B8A8_UNORM,
        VK_FORMAT_B8G8R8A8_SRGB,VK_FORMAT_R8G8B8A8_SRGB}) {
      for (auto f:formats) if (f.format==preferred &&
        f.colorSpace==VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) { chosen=f; break; }
      if (chosen.format!=VK_FORMAT_UNDEFINED) break;
    }
    if (chosen.format==VK_FORMAT_UNDEFINED && formats.size()==1 &&
        formats[0].format==VK_FORMAT_UNDEFINED &&
        formats[0].colorSpace==VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
      chosen={VK_FORMAT_B8G8R8A8_UNORM,VK_COLOR_SPACE_SRGB_NONLINEAR_KHR};
    if (chosen.format==VK_FORMAT_UNDEFINED)
      throw std::runtime_error("sRGB display swapchain format unavailable");
    format=chosen.format;
    uint32_t image_count=std::max(2u,caps.minImageCount);
    if (caps.maxImageCount) image_count=std::min(image_count,caps.maxImageCount);
    VkSwapchainCreateInfoKHR ci{VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR};
    ci.surface=surface; ci.minImageCount=image_count; ci.imageFormat=chosen.format;
    ci.imageColorSpace=chosen.colorSpace; ci.imageExtent=extent; ci.imageArrayLayers=1;
    ci.imageUsage=VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    ci.imageSharingMode=VK_SHARING_MODE_EXCLUSIVE; ci.preTransform=caps.currentTransform;
    ci.compositeAlpha=(caps.supportedCompositeAlpha&VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR)
      ?VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR:VkCompositeAlphaFlagBitsKHR(caps.supportedCompositeAlpha&-caps.supportedCompositeAlpha);
    ci.presentMode=VK_PRESENT_MODE_FIFO_KHR;
    if (const char* requested=std::getenv("VOXEL_STRESS_PRESENT")) {
      if (std::strcmp(requested,"unpaced"))
        throw std::runtime_error("VOXEL_STRESS_PRESENT must be unpaced");
      uint32_t mode_count=0;
      check(vkGetPhysicalDeviceSurfacePresentModesKHR(physical,surface,&mode_count,nullptr),
        "query present modes");
      std::vector<VkPresentModeKHR> modes(mode_count);
      check(vkGetPhysicalDeviceSurfacePresentModesKHR(physical,surface,&mode_count,modes.data()),
        "query present modes");
      ci.presentMode=unpaced_mode(modes);
      std::fprintf(stderr,"stress_present_mode,%s\n",
        ci.presentMode==VK_PRESENT_MODE_IMMEDIATE_KHR?"immediate":"mailbox");
    }
    present_mode=ci.presentMode;
    frozen_surface=caps;
    ci.clipped=VK_TRUE;
    check(vkCreateSwapchainKHR(device,&ci,nullptr,&swapchain),"create swapchain");
    check(vkGetSwapchainImagesKHR(device,swapchain,&n,nullptr),"get swapchain images");
    images.resize(n);
    check(vkGetSwapchainImagesKHR(device,swapchain,&n,images.data()),"get swapchain images");
    for (auto image:images) {
      VkImageViewCreateInfo vi{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
      vi.image=image; vi.viewType=VK_IMAGE_VIEW_TYPE_2D; vi.format=format;
      vi.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1};
      VkImageView view=VK_NULL_HANDLE;
      check(vkCreateImageView(device,&vi,nullptr,&view),"create swapchain view");
      views.push_back(view);
      VkSemaphoreCreateInfo si{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
      VkSemaphore done=VK_NULL_HANDLE;
      check(vkCreateSemaphore(device,&si,nullptr,&done),"create present semaphore");
      finished.push_back(done);
    }
    make_depth();
    triangles=pipeline(VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,true);
    lines=pipeline(VK_PRIMITIVE_TOPOLOGY_LINE_LIST,false);
    hud_pipeline=pipeline(VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,false);
    shadow_pipeline=pipeline(VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,true,true);
  }
  bool ensure_vertices(VkDeviceSize bytes) {
    if (bytes<=capacity) return false;
    if (mapped) vkUnmapMemory(device,vertex_memory);
    if (vertices) vkDestroyBuffer(device,vertices,nullptr);
    if (vertex_memory) supervision::free(device,vertex_memory);
    capacity=std::max<VkDeviceSize>(bytes,capacity?capacity*2:1024*1024);
    VkBufferCreateInfo bi{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    bi.size=capacity; bi.usage=VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
    bi.sharingMode=VK_SHARING_MODE_EXCLUSIVE;
    check(vkCreateBuffer(device,&bi,nullptr,&vertices),"create vertex buffer");
    VkMemoryRequirements req{}; vkGetBufferMemoryRequirements(device,vertices,&req);
    VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    ai.allocationSize=req.size;
    ai.memoryTypeIndex=memory_type(req.memoryTypeBits,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|
      VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    check(supervision::allocate(device,physical,&ai,&vertex_memory),"allocate vertex buffer");
    check(vkBindBufferMemory(device,vertices,vertex_memory,0),"bind vertex buffer");
    check(vkMapMemory(device,vertex_memory,0,capacity,0,&mapped),"map vertex buffer");
    return true;
  }
  void barrier(VkImage image,VkImageAspectFlags aspect,VkImageLayout old_layout,
    VkImageLayout new_layout,VkPipelineStageFlags src,VkPipelineStageFlags dst,
    VkAccessFlags src_access,VkAccessFlags dst_access) {
    VkImageMemoryBarrier b{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
    b.oldLayout=old_layout; b.newLayout=new_layout;
    b.srcAccessMask=src_access; b.dstAccessMask=dst_access;
    b.image=image; b.subresourceRange={aspect,0,1,0,1};
    vkCmdPipelineBarrier(command,src,dst,0,0,nullptr,0,nullptr,1,&b);
  }
public:
  Renderer(Display* d,::Window w):display(d),window(w) {
    VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    app.pApplicationName="Bend Voxel Vulkan"; app.apiVersion=VK_API_VERSION_1_3;
    const char* extensions[]={VK_KHR_SURFACE_EXTENSION_NAME,VK_KHR_XLIB_SURFACE_EXTENSION_NAME};
    VkInstanceCreateInfo ii{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    ii.pApplicationInfo=&app; ii.enabledExtensionCount=2; ii.ppEnabledExtensionNames=extensions;
    check(vkCreateInstance(&ii,nullptr,&instance),"create instance");
    VkXlibSurfaceCreateInfoKHR si{VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR};
    si.dpy=display; si.window=window;
    check(vkCreateXlibSurfaceKHR(instance,&si,nullptr,&surface),"create Xlib surface");
    uint32_t n=0; check(vkEnumeratePhysicalDevices(instance,&n,nullptr),"enumerate devices");
    if (!n) throw std::runtime_error("no Vulkan physical device");
    std::vector<VkPhysicalDevice> devices(n);
    check(vkEnumeratePhysicalDevices(instance,&n,devices.data()),"enumerate devices");
    for (auto candidate:devices) {
      VkPhysicalDeviceProperties props{}; vkGetPhysicalDeviceProperties(candidate,&props);
      if (VK_API_VERSION_MAJOR(props.apiVersion)<1 ||
        (VK_API_VERSION_MAJOR(props.apiVersion)==1&&VK_API_VERSION_MINOR(props.apiVersion)<3)) continue;
      uint32_t count=0; vkGetPhysicalDeviceQueueFamilyProperties(candidate,&count,nullptr);
      std::vector<VkQueueFamilyProperties> queues(count);
      vkGetPhysicalDeviceQueueFamilyProperties(candidate,&count,queues.data());
      for (uint32_t i=0;i<count;i++) {
        VkBool32 present=VK_FALSE;
        check(vkGetPhysicalDeviceSurfaceSupportKHR(candidate,i,surface,&present),"query presentation support");
        if ((queues[i].queueFlags&VK_QUEUE_GRAPHICS_BIT)&&present) {
          physical=candidate; family=i; break;
        }
      }
      if (physical) break;
    }
    if (!physical) throw std::runtime_error("no Vulkan 1.3 graphics/present queue");
    supervision::verify(physical);
    float priority=1;
    VkDeviceQueueCreateInfo qi{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    qi.queueFamilyIndex=family; qi.queueCount=1; qi.pQueuePriorities=&priority;
    const char* device_extensions[]={VK_KHR_SWAPCHAIN_EXTENSION_NAME};
    VkPhysicalDeviceVulkan13Features features{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES};
    features.dynamicRendering=VK_TRUE;
    VkDeviceCreateInfo di{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    di.pNext=&features; di.queueCreateInfoCount=1; di.pQueueCreateInfos=&qi;
    di.enabledExtensionCount=1; di.ppEnabledExtensionNames=device_extensions;
    check(vkCreateDevice(physical,&di,nullptr,&device),"create device");
    vkGetDeviceQueue(device,family,0,&queue);
    auto vertex_code=spirv("build/vulkan-scene.vert.spv");
    auto fragment_code=spirv("build/vulkan-scene.frag.spv");
    auto shadow_code=spirv("build/vulkan-shadow.vert.spv");
    VkShaderModuleCreateInfo mi{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
    mi.codeSize=vertex_code.size()*4; mi.pCode=vertex_code.data();
    check(vkCreateShaderModule(device,&mi,nullptr,&vs),"create vertex shader");
    mi.codeSize=fragment_code.size()*4; mi.pCode=fragment_code.data();
    check(vkCreateShaderModule(device,&mi,nullptr,&fs),"create fragment shader");
    mi.codeSize=shadow_code.size()*4; mi.pCode=shadow_code.data();
    check(vkCreateShaderModule(device,&mi,nullptr,&shadow_vs),"create shadow shader");
    make_shadow();
    VkPushConstantRange range{VK_SHADER_STAGE_VERTEX_BIT|VK_SHADER_STAGE_FRAGMENT_BIT,0,sizeof(Push)};
    VkPipelineLayoutCreateInfo li{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    li.setLayoutCount=1; li.pSetLayouts=&shadow_set_layout;
    li.pushConstantRangeCount=1; li.pPushConstantRanges=&range;
    check(vkCreatePipelineLayout(device,&li,nullptr,&layout),"create pipeline layout");
    VkCommandPoolCreateInfo pi{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    pi.flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT; pi.queueFamilyIndex=family;
    check(vkCreateCommandPool(device,&pi,nullptr,&pool),"create command pool");
    VkCommandBufferAllocateInfo ai{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    ai.commandPool=pool; ai.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY; ai.commandBufferCount=1;
    check(vkAllocateCommandBuffers(device,&ai,&command),"allocate command buffer");
    VkFenceCreateInfo fi{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO}; fi.flags=VK_FENCE_CREATE_SIGNALED_BIT;
    check(vkCreateFence(device,&fi,nullptr,&fence),"create frame fence");
    VkSemaphoreCreateInfo sem{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
    check(vkCreateSemaphore(device,&sem,nullptr,&acquired),"create acquire semaphore");
    make_swapchain();
  }
  ~Renderer() {
    if (device) {
      VkResult idle=vkDeviceWaitIdle(device);
      if(idle!=VK_SUCCESS) record_vk_failure(idle,"device teardown wait");
      if(gpu_queries.active()) gpu_queries.finish(idle,monotonic_ns());
      clear_swapchain();
      if (mapped) vkUnmapMemory(device,vertex_memory);
      if (vertices) vkDestroyBuffer(device,vertices,nullptr);
      if (vertex_memory) supervision::free(device,vertex_memory);
      if (acquired) vkDestroySemaphore(device,acquired,nullptr);
      if (fence) vkDestroyFence(device,fence,nullptr);
      if (pool) vkDestroyCommandPool(device,pool,nullptr);
      if (layout) vkDestroyPipelineLayout(device,layout,nullptr);
      if (shadow_pool) vkDestroyDescriptorPool(device,shadow_pool,nullptr);
      if (shadow_set_layout) vkDestroyDescriptorSetLayout(device,shadow_set_layout,nullptr);
      if (shadow_sampler) vkDestroySampler(device,shadow_sampler,nullptr);
      if (shadow_view) vkDestroyImageView(device,shadow_view,nullptr);
      if (shadow_image) vkDestroyImage(device,shadow_image,nullptr);
      if (shadow_memory) supervision::free(device,shadow_memory);
      if (vs) vkDestroyShaderModule(device,vs,nullptr);
      if (fs) vkDestroyShaderModule(device,fs,nullptr);
      if (shadow_vs) vkDestroyShaderModule(device,shadow_vs,nullptr);
      vkDestroyDevice(device,nullptr);
    }
    if (surface) vkDestroySurfaceKHR(instance,surface,nullptr);
    if (instance) vkDestroyInstance(instance,nullptr);
  }
  bool matches(Display* d,::Window w) const { return d==display&&w==window; }
  void render(const VoxelVkFrame& frame,VoxelVkTimings& timings) {
    uint64_t ns_start=frame.record?monotonic_ns():0;
    if(frame.gpu_evidence && frame.record && !gpu_queries.active()) {
      VkPhysicalDeviceProperties properties{}; vkGetPhysicalDeviceProperties(physical,&properties);
      uint32_t count=0; vkGetPhysicalDeviceQueueFamilyProperties(physical,&count,nullptr);
      std::vector<VkQueueFamilyProperties> families(count);
      vkGetPhysicalDeviceQueueFamilyProperties(physical,&count,families.data());
      gpu_queries.start(device,family,properties.limits.timestampPeriod,families.at(family).timestampValidBits,3721);
    }
    if (frame.full_geometry && (extent.width!=frame.width || extent.height!=frame.height))
      throw std::runtime_error("Megascene actual swapchain resolution differs from frozen request");
    if (frame.full_geometry && present_mode!=VK_PRESENT_MODE_IMMEDIATE_KHR && present_mode!=VK_PRESENT_MODE_MAILBOX_KHR)
      throw std::runtime_error("Megascene requires immediate or mailbox presentation");
    if (frame.record && !settings_recorded) {
      VkPhysicalDeviceProperties p{}; vkGetPhysicalDeviceProperties(physical,&p);
      char name[VK_MAX_PHYSICAL_DEVICE_NAME_SIZE*2+1]{};
      for (size_t i=0;i<std::strlen(p.deviceName);i++) std::snprintf(name+i*2,3,"%02x",(unsigned char)p.deviceName[i]);
      char record[2048];
      std::snprintf(record,sizeof record,
        "\"record_type\":\"render_settings\",\"width\":\"%u\",\"height\":\"%u\",\"present_mode\":\"%s\","
        "\"profile\":\"full\",\"ground_half_extent_m\":\"%.9g\",\"shadow_size\":\"%u\",\"night\":\"%u\","
        "\"device_name_hex\":\"%s\",\"vendor_id\":\"%u\",\"device_id\":\"%u\",\"driver_version\":\"%u\",\"api_version\":\"%u\"",
        extent.width,extent.height,present_mode==VK_PRESENT_MODE_IMMEDIATE_KHR?"immediate":"mailbox",
        frame.ground_half_extent,SHADOW_SIZE,frame.night,name,p.vendorID,p.deviceID,p.driverVersion,p.apiVersion);
      frame.record(record);
      std::string palette="\"record_type\":\"palette\",\"colors\":[";
      for (unsigned color=0;color<19;color++) {
        char rgb[64];
        std::snprintf(rgb,sizeof rgb,"%s[\"0x%08x\",\"0x%08x\",\"0x%08x\"]",color?",":"",
          float_bits(frame.colors[color][0]),float_bits(frame.colors[color][1]),float_bits(frame.colors[color][2]));
        palette+=rgb;
      }
      palette+="]"; frame.record(palette.c_str());
      settings_recorded=true;
    }
    auto start=Clock::now();
    bool scene_reused=false;
    Geometry& g=geometry(frame,geometry_cache,scene_reused);
    if(frame.record) audit_native(frame,geometry_cache);
    auto after_geometry=Clock::now();
    uint64_t ns_after_geometry=frame.record?monotonic_ns():0;
    stage(frame,"geometry",ns_start,ns_after_geometry);
    timings.geometry_us=microseconds(start,after_geometry);
    VkResult waited=vkWaitForFences(device,1,&fence,VK_TRUE,UINT64_MAX);
    auto after_fence=Clock::now();
    uint64_t ns_after_fence=frame.record?monotonic_ns():0;
    if(gpu_queries.active()) gpu_queries.collect(frame.evidence_frame,false,waited,ns_after_fence);
    check(waited,"wait for frame fence");
    stage(frame,"fence_wait",ns_after_geometry,ns_after_fence);
    timings.fence_wait_us=microseconds(after_geometry,after_fence);
    bool new_buffer=ensure_vertices(g.vertices.size()*sizeof(Vertex));
    // The fence protects the single mapped arena. Its stable mesh slots survive
    // transforms and view changes; edits upload only new/changed slots.
    size_t uploaded_vertices=0;
    auto upload=[&](size_t first,size_t count) {
      uploaded_vertices+=count;
      if (count) std::memcpy(static_cast<Vertex*>(mapped)+first,
        g.vertices.data()+first,count*sizeof(Vertex));
    };
    if (new_buffer) upload(0,g.vertices.size());
    else {
      for (auto range:geometry_cache.dirty) upload(range.first,range.count);
      upload(geometry_cache.scene_vertices,g.vertices.size()-geometry_cache.scene_vertices);
    }
    auto after_upload=Clock::now();
    uint64_t ns_after_upload=frame.record?monotonic_ns():0;
    stage(frame,"vertex_upload",ns_after_fence,ns_after_upload);
    if (std::getenv("VOXEL_STRESS")) {
      static uint32_t cache_frame;
      std::fprintf(stdout,"mesh_cache,%u,%u,%u,%zu,%u,%zu\n",cache_frame++,
        geometry_cache.rebuilt,frame.body_count,size_t(geometry_cache.visible_bodies),
        geometry_cache.scene_vertices,uploaded_vertices*sizeof(Vertex));
      std::fprintf(stdout,"lod_cache,%u,%u,%u,%u,%zu,%zu\n",cache_frame-1,
        geometry_cache.proxy_draws,geometry_cache.proxied_bodies,
        geometry_cache.proxy_rebuilt,geometry_cache.draws.size(),
        geometry_cache.proxy_vertices);
    }
    timings.vertex_upload_us=microseconds(after_fence,after_upload);
    uint32_t index=0;
    VkResult acquire=vkAcquireNextImageKHR(device,swapchain,UINT64_MAX,acquired,VK_NULL_HANDLE,&index);
    auto after_acquire=Clock::now();
    uint64_t ns_after_acquire=frame.record?monotonic_ns():0;
    stage(frame,"acquire",ns_after_upload,ns_after_acquire);
    timings.acquire_us=microseconds(after_upload,after_acquire);
    if (acquire==VK_ERROR_OUT_OF_DATE_KHR) {
      check(vkDeviceWaitIdle(device),"wait for swapchain recreation");
      if (frame.full_geometry) throw std::runtime_error("Megascene swapchain became out of date");
      clear_swapchain(); make_swapchain(); return;
    }
    if (acquire!=VK_SUCCESS&&acquire!=VK_SUBOPTIMAL_KHR) check(acquire,"acquire swapchain image");
    bool shadow_dirty=!shadow_valid || shadow_changed(shadow_world,frame);
    if (std::getenv("VOXEL_STRESS")) {
      static uint32_t lighting_frame;
      std::fprintf(stdout,"lighting,%u,%u,%u\n",lighting_frame++,frame.night,shadow_dirty?1u:0u);
    }
    if (shadow_dirty && std::getenv("VOXEL_VULKAN_TRACE"))
      std::fprintf(stderr,"vulkan shadow refresh bodies %u rebuilt %u\n",
        frame.body_count,geometry_cache.rebuilt);
    ShadowMatrix light=shadow_dirty?shadow_matrix(frame):saved_shadow;
    if(frame.record) {
      auto fresh=shadow_matrix(frame);
      if(std::memcmp(light.values,fresh.values,sizeof light.values))
        throw std::runtime_error("stale native shadow transform");
      for(float value:light.values) if(!std::isfinite(value))
        throw std::runtime_error("nonfinite native shadow transform");
    }
    if (frame.record) {
      char record[1024];
      float sx=std::sqrt(light.values[0]*light.values[0]+light.values[4]*light.values[4]+light.values[8]*light.values[8]);
      float sy=std::sqrt(light.values[1]*light.values[1]+light.values[5]*light.values[5]+light.values[9]*light.values[9]);
      std::snprintf(record,sizeof record,
        "\"record_type\":\"render_work\",\"body_count\":\"%u\",\"visible_bodies\":\"%u\",\"full_meshes\":\"%zu\","
        "\"main_body_draws\":\"%zu\",\"proxy_draws\":\"%u\",\"proxy_groups\":\"%zu\",\"proxy_vertices\":\"%zu\","
        "\"mesh_rebuilt\":\"%u\",\"proxy_rebuilt\":\"%u\",\"uploaded_bytes\":\"%zu\","
        "\"shadow_refresh\":%s,\"shadow_body_draws\":\"%zu\",\"shadow_extent_m\":[\"0x%08x\",\"0x%08x\"],\"shadow_texel_m\":[\"0x%08x\",\"0x%08x\"]",
        frame.body_count,geometry_cache.visible_bodies,geometry_cache.meshes.size(),geometry_cache.draws.size(),
        geometry_cache.proxy_draws,geometry_cache.proxies.size(),geometry_cache.proxy_vertices,
        geometry_cache.rebuilt,geometry_cache.proxy_rebuilt,uploaded_vertices*sizeof(Vertex),
        shadow_dirty?"true":"false",shadow_dirty?geometry_cache.shadow_draws.size():0,
        float_bits(2.f/sx),float_bits(2.f/sy),float_bits(2.f/(sx*SHADOW_SIZE)),float_bits(2.f/(sy*SHADOW_SIZE)));
      frame.record(record);
    }
    check(vkResetCommandBuffer(command,0),"reset command buffer");
    VkCommandBufferBeginInfo bi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    check(vkBeginCommandBuffer(command,&bi),"begin command buffer");
    gpu_queries.begin(command);
    Push push{{frame.eye[0],frame.eye[1],frame.eye[2],frame.yaw},
      {frame.pitch,0,0,float(frame.night!=0)},
      {float(frame.width)*.5f,float(frame.height)*.5f,
        800.f*float(frame.height)/(360.f*float(frame.width)),0.f},{}};
    std::memcpy(push.shadow_matrix,light.values,sizeof light.values);
    VkDeviceSize offset=0;
    vkCmdBindVertexBuffers(command,0,1,&vertices,&offset);
    if (shadow_dirty) {
      barrier(shadow_image,VK_IMAGE_ASPECT_DEPTH_BIT,
        shadow_valid?VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL:VK_IMAGE_LAYOUT_UNDEFINED,
        VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        shadow_valid?VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT:VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
        shadow_valid?VK_ACCESS_SHADER_READ_BIT:0,VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT);
      VkRenderingAttachmentInfo sun_depth{VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
      sun_depth.imageView=shadow_view;
      sun_depth.imageLayout=VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
      sun_depth.loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR;
      sun_depth.storeOp=VK_ATTACHMENT_STORE_OP_STORE;
      sun_depth.clearValue.depthStencil={1,0};
      VkRenderingInfo sun_pass{VK_STRUCTURE_TYPE_RENDERING_INFO};
      sun_pass.renderArea={{0,0},{SHADOW_SIZE,SHADOW_SIZE}}; sun_pass.layerCount=1;
      sun_pass.pDepthAttachment=&sun_depth;
      vkCmdBeginRendering(command,&sun_pass);
      VkViewport sun_viewport{0,0,float(SHADOW_SIZE),float(SHADOW_SIZE),0,1};
      VkRect2D sun_scissor{{0,0},{SHADOW_SIZE,SHADOW_SIZE}};
      vkCmdSetViewport(command,0,1,&sun_viewport);
      vkCmdSetScissor(command,0,1,&sun_scissor);
      vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_GRAPHICS,shadow_pipeline);
      for (auto draw:geometry_cache.shadow_draws) {
        push.pitch_offset[1]=draw.offset;
        vkCmdPushConstants(command,layout,VK_SHADER_STAGE_VERTEX_BIT|VK_SHADER_STAGE_FRAGMENT_BIT,
          0,sizeof(Push),&push);
        vkCmdDraw(command,draw.count,1,draw.first,0);
      }
      vkCmdEndRendering(command);
      barrier(shadow_image,VK_IMAGE_ASPECT_DEPTH_BIT,VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL,
        VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT|VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
        VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        VK_ACCESS_SHADER_READ_BIT);
    }
    barrier(images[index],VK_IMAGE_ASPECT_COLOR_BIT,VK_IMAGE_LAYOUT_UNDEFINED,
      VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
      VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,0,VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT);
    barrier(depth,VK_IMAGE_ASPECT_DEPTH_BIT,VK_IMAGE_LAYOUT_UNDEFINED,
      VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
      VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,0,VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT);
    VkRenderingAttachmentInfo color{VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
    color.imageView=views[index]; color.imageLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    color.loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR; color.storeOp=VK_ATTACHMENT_STORE_OP_STORE;
    auto background=(format==VK_FORMAT_B8G8R8A8_SRGB || format==VK_FORMAT_R8G8B8A8_SRGB)
      ? palette_color(frame,BACKGROUND_LINEAR) : palette_color(frame,BACKGROUND_DISPLAY);
    color.clearValue.color={{background.x,background.y,background.z,1}};
    VkRenderingAttachmentInfo z{VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
    z.imageView=depth_view; z.imageLayout=VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    z.loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR; z.storeOp=VK_ATTACHMENT_STORE_OP_DONT_CARE;
    z.clearValue.depthStencil={1,0};
    VkRenderingInfo ri{VK_STRUCTURE_TYPE_RENDERING_INFO};
    ri.renderArea={{0,0},extent}; ri.layerCount=1;
    ri.colorAttachmentCount=1; ri.pColorAttachments=&color; ri.pDepthAttachment=&z;
    vkCmdBeginRendering(command,&ri);
    VkViewport vp{0,0,float(extent.width),float(extent.height),0,1};
    VkRect2D sc{{0,0},extent};
    vkCmdSetViewport(command,0,1,&vp); vkCmdSetScissor(command,0,1,&sc);
    vkCmdBindDescriptorSets(command,VK_PIPELINE_BIND_POINT_GRAPHICS,layout,0,1,&shadow_set,0,nullptr);
    push.pitch_offset[1]=0;
    vkCmdPushConstants(command,layout,VK_SHADER_STAGE_VERTEX_BIT|VK_SHADER_STAGE_FRAGMENT_BIT,0,sizeof(Push),&push);
    vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_GRAPHICS,triangles);
    vkCmdDraw(command,6,1,0,0); // Ground.
    for (auto draw:geometry_cache.draws) {
      push.pitch_offset[1]=draw.offset;
      vkCmdPushConstants(command,layout,VK_SHADER_STAGE_VERTEX_BIT|VK_SHADER_STAGE_FRAGMENT_BIT,0,sizeof(Push),&push);
      vkCmdDraw(command,draw.count,1,draw.first,0);
    }
    push.pitch_offset[1]=0;
    vkCmdPushConstants(command,layout,VK_SHADER_STAGE_VERTEX_BIT|VK_SHADER_STAGE_FRAGMENT_BIT,0,sizeof(Push),&push);
    vkCmdDraw(command,g.triangles-geometry_cache.scene_vertices,1,geometry_cache.scene_vertices,0);
    if (g.lines) {
      vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_GRAPHICS,lines);
      vkCmdDraw(command,g.lines,1,g.triangles,0);
    }
    if (g.hud) {
      push.pitch_offset[2]=1;
      vkCmdPushConstants(command,layout,VK_SHADER_STAGE_VERTEX_BIT|VK_SHADER_STAGE_FRAGMENT_BIT,0,sizeof(Push),&push);
      vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_GRAPHICS,hud_pipeline);
      vkCmdDraw(command,g.hud,1,g.triangles+g.lines,0);
    }
    vkCmdEndRendering(command);
    barrier(images[index],VK_IMAGE_ASPECT_COLOR_BIT,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
      VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,0);
    gpu_queries.end(command);
    check(vkEndCommandBuffer(command),"end command buffer");
    auto after_record=Clock::now();
    uint64_t ns_after_record=frame.record?monotonic_ns():0;
    stage(frame,"command_record",ns_after_acquire,ns_after_record);
    timings.command_record_us=microseconds(after_acquire,after_record);
    check(vkResetFences(device,1,&fence),"reset frame fence");
    VkPipelineStageFlags wait_stage=VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    submit.waitSemaphoreCount=1; submit.pWaitSemaphores=&acquired;
    submit.pWaitDstStageMask=&wait_stage; submit.commandBufferCount=1;
    submit.pCommandBuffers=&command; submit.signalSemaphoreCount=1;
    submit.pSignalSemaphores=&finished[index];
    uint64_t submit_begin=gpu_queries.active()?monotonic_ns():0;
    check(vkQueueSubmit(queue,1,&submit,fence),"submit frame");
    gpu_queries.submitted(frame.evidence_frame,submit_begin);
    if (shadow_dirty) {
      shadow_world.clear(); shadow_world.reserve(frame.body_count);
      for (uint32_t i=0;i<frame.body_count;i++) {
        const auto& b=frame.bodies[i];
        shadow_world.push_back({b.id,b.revision,b.anchored,b.offset});
      }
      saved_shadow=light;
      shadow_valid=true;
    }
    VkPresentInfoKHR present{VK_STRUCTURE_TYPE_PRESENT_INFO_KHR};
    present.waitSemaphoreCount=1; present.pWaitSemaphores=&finished[index];
    present.swapchainCount=1; present.pSwapchains=&swapchain; present.pImageIndices=&index;
    VkResult result=vkQueuePresentKHR(queue,&present);
    timings.submit_present_us=microseconds(after_record,Clock::now());
    stage(frame,"submit_present",ns_after_record,frame.record?monotonic_ns():0);
    if (result==VK_ERROR_OUT_OF_DATE_KHR||result==VK_SUBOPTIMAL_KHR) {
      if (frame.full_geometry) {
        if(result==VK_ERROR_OUT_OF_DATE_KHR) throw std::runtime_error("Megascene presentation became out of date");
        // SUBOPTIMAL is a successful presentation, not an out-of-date error.
        // The compositor can return it with unchanged properties. Retain the
        // exact result and accept only the original frozen surface capabilities.
        VkSurfaceCapabilitiesKHR caps{};
        check(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical,surface,&caps),"recheck frozen surface");
        if(caps.currentExtent.width!=frozen_surface.currentExtent.width||caps.currentExtent.height!=frozen_surface.currentExtent.height||
           caps.currentTransform!=frozen_surface.currentTransform||caps.supportedTransforms!=frozen_surface.supportedTransforms||
           caps.minImageCount!=frozen_surface.minImageCount||caps.maxImageCount!=frozen_surface.maxImageCount||
           caps.minImageExtent.width!=frozen_surface.minImageExtent.width||caps.minImageExtent.height!=frozen_surface.minImageExtent.height||
           caps.maxImageExtent.width!=frozen_surface.maxImageExtent.width||caps.maxImageExtent.height!=frozen_surface.maxImageExtent.height||
           caps.maxImageArrayLayers!=frozen_surface.maxImageArrayLayers||caps.supportedCompositeAlpha!=frozen_surface.supportedCompositeAlpha||
           caps.supportedUsageFlags!=frozen_surface.supportedUsageFlags)
          throw std::runtime_error("Megascene surface properties changed during frozen attempt");
        frame.record("\"record_type\":\"presentation_status\",\"result\":\"1000001003\",\"frozen_surface_unchanged\":true");
        return;
      }
      check(vkDeviceWaitIdle(device),"wait for swapchain recreation");
      clear_swapchain(); make_swapchain();
    } else check(result,"present frame");
  }
};
std::unique_ptr<Renderer> renderer;
}

extern "C" int voxel_vk_render_timed(void* display,unsigned long window,const VoxelVkFrame* frame,
  VoxelVkTimings* timings,char* error,size_t error_cap) {
  try {
    if (!frame || !display || !window || !timings) throw std::runtime_error("invalid Vulkan frame");
    *timings={};
    if (!renderer) {
      uint64_t begin=frame->record?monotonic_ns():0;
      renderer=std::make_unique<Renderer>(static_cast<Display*>(display),window);
      stage(*frame,"renderer_setup",begin,frame->record?monotonic_ns():0);
    }
    if (!renderer->matches(static_cast<Display*>(display),window))
      throw std::runtime_error("Vulkan renderer window changed");
    renderer->render(*frame,*timings);
    return 1;
  } catch (const std::exception& e) {
    if (error_cap) {
      std::strncpy(error,e.what(),error_cap-1);
      error[error_cap-1]=0;
    }
    return 0;
  }
}
// Preserve the profile ABI used by archived static workers before GPU timing.
extern "C" int voxel_vk_render_profile(void* display,unsigned long window,const VoxelVkFrame* frame,
  VoxelVkTimings* timings,char* error,size_t error_cap) {
  VoxelVkFrame previous{};
  if(frame) std::memcpy(&previous,frame,offsetof(VoxelVkFrame,evidence_frame));
  return voxel_vk_render_timed(display,window,frame?&previous:nullptr,timings,error,error_cap);
}
// Preserve the original ABI for previously built Light Atelier executables.
extern "C" int voxel_vk_render(void* display,unsigned long window,const VoxelVkFrame* frame,
  VoxelVkTimings* timings,char* error,size_t error_cap) {
  VoxelVkFrame legacy{};
  if (frame) std::memcpy(&legacy,frame,offsetof(VoxelVkFrame,full_geometry));
  return voxel_vk_render_profile(display,window,frame?&legacy:nullptr,timings,error,error_cap);
}
extern "C" void voxel_vk_release(void) { renderer.reset(); }

// The worker calls this before generation, so long pure computations cannot
// suppress heap monitoring. A separate probe establishes preflight capability;
// its usage is never attributed to the worker.
extern "C" int voxel_mega_start(char* error,size_t cap) {
  try { supervision::start(); return 1; }
  catch(const std::exception& e) { std::snprintf(error,cap,"%s",e.what()); return 0; }
}
extern "C" int voxel_mega_probe(char* output,size_t cap) {
  try {
    supervision::setup();
    std::string result="{"+supervision::sample()+"}";
    std::snprintf(output,cap,"%s",result.c_str()); supervision::finish(); return 1;
  } catch(const std::exception& e) { std::snprintf(output,cap,"%s",e.what()); supervision::finish(); return 0; }
}
