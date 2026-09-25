#define VK_USE_PLATFORM_XLIB_KHR
#include <X11/Xlib.h>
#include <vulkan/vulkan.h>
#include "native.h"
#include "material.hpp"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
#include <unordered_map>

namespace {
constexpr uint32_t WIDTH=640, HEIGHT=360;
void check(VkResult result, const char* what) {
  if (result!=VK_SUCCESS) throw std::runtime_error(std::string(what)+": Vulkan "+std::to_string(result));
}
struct Vec3 { float x,y,z; };
Vec3 operator+(Vec3 a,Vec3 b) { return {a.x+b.x,a.y+b.y,a.z+b.z}; }
Vec3 operator-(Vec3 a,Vec3 b) { return {a.x-b.x,a.y-b.y,a.z-b.z}; }
float dot(Vec3 a,Vec3 b) { return a.x*b.x+a.y*b.y+a.z*b.z; }
Vec3 rgb(uint32_t word) { return {float((word>>16)&255)/255,float((word>>8)&255)/255,float(word&255)/255}; }
Vec3 shaded_rgb(uint32_t word,uint32_t side) {
  Vec3 encoded=rgb(word);
  auto linear=material::decode({encoded.x,encoded.y,encoded.z});
  float amount=material::light(side);
  auto shaded=material::encode({linear.r*amount,linear.g*amount,linear.b*amount});
  return {shaded.r,shaded.g,shaded.b};
}
Vec3 quantize(Vec3 c) { return {std::floor(c.x*255)/255,std::floor(c.y*255)/255,std::floor(c.z*255)/255}; }
struct Vertex { Vec3 position,color; };
struct Geometry { std::vector<Vertex> vertices; uint32_t triangles=0,lines=0,hud=0; };
using Clock=std::chrono::steady_clock;
uint32_t microseconds(Clock::time_point start,Clock::time_point end) {
  return uint32_t(std::chrono::duration_cast<std::chrono::microseconds>(end-start).count());
}
void quad(Geometry& g,Vec3 a,Vec3 b,Vec3 c,Vec3 d,Vec3 color) {
  color=quantize(color);
  for (Vec3 p:{a,b,c,a,c,d}) g.vertices.push_back({p,color});
  g.triangles+=6;
}
void line(Geometry& g,Vec3 a,Vec3 b,Vec3 color) {
  g.vertices.push_back({a,color}); g.vertices.push_back({b,color}); g.lines+=2;
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
void hud_text(Geometry& g,float x,float baseline,const char* begin,size_t length,Vec3 color) {
  for (size_t i=0;i<length;i++,x+=6) {
    if (begin[i]==' ') continue;
    const uint8_t* rows=glyph(begin[i]);
    for (int y=0;y<7;y++) for (int bit=0;bit<5;bit++) if (rows[y]&(16>>bit)) {
      float left=x+bit,top=baseline-10.5f+y*1.5f;
      Vec3 a{left,top,0},b{left+1,top,0},c{left+1,top+1.5f,0},d{left,top+1.5f,0};
      for (Vec3 p:{a,b,c,a,c,d}) g.vertices.push_back({p,color});
      g.hud+=6;
    }
  }
}
void add_hud(Geometry& g,const char* hud) {
  constexpr int ys[]={20,38,55,72,325,347};
  constexpr uint32_t colors[]={0xe7e8e7,0x9fdbdd,0x9fdbdd,0xffdf68,0xe7e8e7,0x9fdbdd};
  if (hud) for (int row=0;row<6 && *hud;row++) {
    const char* end=std::strchr(hud,'\n');
    hud_text(g,12,float(ys[row]),hud,end?size_t(end-hud):std::strlen(hud),rgb(colors[row]));
    if (!end) break;
    hud=end+1;
  }
  hud_text(g,577,20,"RESET",5,rgb(0x4bc1a4));
}
Vec3 vector(const float* p) { return {p[0],p[1],p[2]}; }
void face_quad(Geometry& g,const VoxelVkFace& f,Vec3 color,float offset=0) {
  uint32_t a=f.side/2,u=(a+1)%3,v=(a+2)%3;
  float p[4][3];
  for (auto& corner:p) for (uint32_t i=0;i<3;i++) corner[i]=f.lo[i]*.1f;
  p[1][u]=p[2][u]=f.hi[u]*.1f;
  p[2][v]=p[3][v]=f.hi[v]*.1f;
  for (auto& corner:p) corner[1]+=offset;
  // Culling is disabled, but keep the winding consistent with the outward normal.
  if (f.side%2) quad(g,vector(p[0]),vector(p[1]),vector(p[2]),vector(p[3]),color);
  else quad(g,vector(p[3]),vector(p[2]),vector(p[1]),vector(p[0]),color);
}
void face(Geometry& g,const VoxelVkFace& f,bool anchored) {
  if (f.side>=6) throw std::runtime_error("invalid Bend face");
  uint32_t a=f.side/2;
  for (uint32_t i=0;i<3;i++) {
    if (!std::isfinite(f.lo[i]) || !std::isfinite(f.hi[i]) ||
        (i==a ? f.hi[i]!=f.lo[i] : f.hi[i]<=f.lo[i]))
      throw std::runtime_error("invalid Bend face bounds");
  }
  auto color=material::surface(f.material,!anchored,f.side);
  face_quad(g,f,{color.r,color.g,color.b});
}
bool near_aim(const VoxelVkBody& body,const VoxelVkFrame& frame) {
  for (uint32_t i=0;i<3;i++) {
    float p=frame.aim[i]-(i==1?body.offset:0);
    if (p<body.lo[i]*.1f-.201f || p>body.hi[i]*.1f+.201f) return false;
  }
  return true;
}
void preview_face(Geometry& g,const VoxelVkFace& f,const VoxelVkBody& body,const VoxelVkFrame& frame) {
  if (f.material==material::foundation_id) return;
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
    face_quad(g,preview,shaded_rgb(0xffdf68,f.side),body.offset);
  }
}
Vec3 ring_point(Vec3 p,uint32_t axis,float angle) {
  float c=.2f*std::cos(angle),s=.2f*std::sin(angle);
  return axis==0?p+Vec3{0,c,s}:axis==1?p+Vec3{c,0,s}:p+Vec3{c,s,0};
}
Vec3 view_position(Vec3 p,const VoxelVkFrame& f) {
  float sy=std::sin(f.yaw),cy=std::cos(f.yaw),sp=std::sin(f.pitch),cp=std::cos(f.pitch);
  Vec3 d=p-Vec3{f.eye[0],f.eye[1],f.eye[2]};
  return {dot(d,{-cy,0,sy}),dot(d,{-sy*sp,cp,-cy*sp}),dot(d,{sy*cp,sp,cy*cp})};
}
float view_depth(Vec3 p,const VoxelVkFrame& f) { return view_position(p,f).z; }
bool visible(const VoxelVkBody& body,const VoxelVkFrame& frame) {
  unsigned outside=31;
  for (unsigned corner=0;corner<8;corner++) {
    Vec3 p={(corner&1?body.hi[0]:body.lo[0])*.1f,
      (corner&2?body.hi[1]:body.lo[1])*.1f+body.offset,
      (corner&4?body.hi[2]:body.lo[2])*.1f};
    auto v=view_position(p,frame);
    unsigned mask=(v.z<.05f?1u:0u)|(v.x*1.25f>v.z?2u:0u)|
      (-v.x*1.25f>v.z?4u:0u)|(v.y*(400.f/180)>v.z?8u:0u)|
      (-v.y*(400.f/180)>v.z?16u:0u);
    outside&=mask;
  }
  return outside==0;
}
struct Range { uint32_t first,count; };
struct Draw { uint32_t first,count; float offset; };
struct Mesh { uint32_t revision,anchored,first,count,seen; };
struct GeometryCache {
  Geometry geometry;
  std::unordered_map<uint32_t,Mesh> meshes;
  std::vector<Range> free,dirty;
  std::vector<Draw> draws;
  uint32_t scene_vertices=0,generation=0,rebuilt=0;
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
// Geometry identity consists of body ID + revision. Camera, aim, culling and
// transforms affect only draws/overlays. Dirty ranges upload edited meshes.
Geometry& geometry(const VoxelVkFrame& frame,GeometryCache& cache,bool& scene_reused) {
  Geometry& g=cache.geometry;
  cache.generation++; cache.dirty.clear(); cache.draws.clear(); cache.rebuilt=0;
  if (!cache.scene_vertices) {
    quad(g,{-512,0,-512},{-512,0,512},{512,0,512},{512,0,-512},rgb(0x1e303d));
    cache.scene_vertices=6; cache.dirty.push_back({0,6});
  }
  for (uint32_t i=0;i<frame.body_count;i++) {
    auto it=cache.meshes.find(frame.bodies[i].id);
    if (it!=cache.meshes.end()) it->second.seen=cache.generation;
  }
  for (auto it=cache.meshes.begin();it!=cache.meshes.end();) {
    if (it->second.seen!=cache.generation) {
      cache.release({it->second.first,it->second.count});
      it=cache.meshes.erase(it);
    } else ++it;
  }
  g.vertices.resize(cache.scene_vertices);
  for (uint32_t i=0;i<frame.body_count;i++) {
    const auto& b=frame.bodies[i];
    auto it=cache.meshes.find(b.id);
    if (it==cache.meshes.end() || it->second.revision!=b.revision || it->second.anchored!=b.anchored) {
      if (it!=cache.meshes.end()) cache.release({it->second.first,it->second.count});
      Geometry mesh;
      for (uint32_t f=0;f<b.face_count;f++) face(mesh,b.faces[f],b.anchored);
      uint32_t first=cache.allocate(mesh.triangles);
      g.vertices.resize(cache.scene_vertices);
      std::copy(mesh.vertices.begin(),mesh.vertices.end(),g.vertices.begin()+first);
      cache.dirty.push_back({first,mesh.triangles}); cache.rebuilt++;
      cache.meshes[b.id]={b.revision,b.anchored,first,mesh.triangles,cache.generation};
    }
    const auto& mesh=cache.meshes.at(b.id);
    if (visible(b,frame)) cache.draws.push_back({mesh.first,mesh.count,b.offset});
  }
  scene_reused=cache.dirty.empty();
  g.triangles=cache.scene_vertices; g.lines=0; g.hud=0;
  if (frame.aim_kind==1) for (uint32_t i=0;i<frame.body_count;i++) {
    const auto& b=frame.bodies[i];
    if (near_aim(b,frame)) for (uint32_t f=0;f<b.face_count;f++) preview_face(g,b.faces[f],b,frame);
  }
  if (frame.aim_kind) {
    Vec3 p={frame.aim[0],frame.aim[1],frame.aim[2]};
    Vec3 color=rgb(frame.aim_kind==1?16768872u:16552594u);
    for (uint32_t axis=0;axis<3;axis++) for (uint32_t i=0;i<12;i++) {
      Vec3 a=ring_point(p,axis,float(i)*.5235988f),b=ring_point(p,axis,float(i+1)*.5235988f);
      if (view_depth(a,frame)>=.05f && view_depth(b,frame)>=.05f) line(g,a,b,color);
    }
  }
  add_hud(g,frame.hud);
  return g;
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
struct Push { float eye_yaw[4],pitch_offset[4]; };

class Renderer {
  Display* display;
  ::Window window;
  VkInstance instance=VK_NULL_HANDLE;
  VkSurfaceKHR surface=VK_NULL_HANDLE;
  VkPhysicalDevice physical=VK_NULL_HANDLE;
  VkDevice device=VK_NULL_HANDLE;
  VkQueue queue=VK_NULL_HANDLE;
  uint32_t family=0;
  VkSwapchainKHR swapchain=VK_NULL_HANDLE;
  VkFormat format=VK_FORMAT_UNDEFINED;
  VkExtent2D extent{WIDTH,HEIGHT};
  std::vector<VkImage> images;
  std::vector<VkImageView> views;
  std::vector<VkSemaphore> finished;
  VkImage depth=VK_NULL_HANDLE;
  VkDeviceMemory depth_memory=VK_NULL_HANDLE;
  VkImageView depth_view=VK_NULL_HANDLE;
  VkBuffer vertices=VK_NULL_HANDLE;
  VkDeviceMemory vertex_memory=VK_NULL_HANDLE;
  VkDeviceSize capacity=0;
  void* mapped=nullptr;
  VkShaderModule vs=VK_NULL_HANDLE,fs=VK_NULL_HANDLE;
  VkPipelineLayout layout=VK_NULL_HANDLE;
  VkPipeline triangles=VK_NULL_HANDLE,lines=VK_NULL_HANDLE,hud_pipeline=VK_NULL_HANDLE;
  VkCommandPool pool=VK_NULL_HANDLE;
  VkCommandBuffer command=VK_NULL_HANDLE;
  VkFence fence=VK_NULL_HANDLE;
  VkSemaphore acquired=VK_NULL_HANDLE;
  GeometryCache geometry_cache;

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
    check(vkAllocateMemory(device,&ai,nullptr,&depth_memory),"allocate depth image");
    check(vkBindImageMemory(device,depth,depth_memory,0),"bind depth image");
    VkImageViewCreateInfo vi{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    vi.image=depth; vi.viewType=VK_IMAGE_VIEW_TYPE_2D; vi.format=VK_FORMAT_D32_SFLOAT;
    vi.subresourceRange={VK_IMAGE_ASPECT_DEPTH_BIT,0,1,0,1};
    check(vkCreateImageView(device,&vi,nullptr,&depth_view),"create depth view");
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
    if (depth_view) vkDestroyImageView(device,depth_view,nullptr);
    depth_view=VK_NULL_HANDLE;
    if (depth) vkDestroyImage(device,depth,nullptr);
    depth=VK_NULL_HANDLE;
    if (depth_memory) vkFreeMemory(device,depth_memory,nullptr);
    depth_memory=VK_NULL_HANDLE;
    if (swapchain) vkDestroySwapchainKHR(device,swapchain,nullptr);
    swapchain=VK_NULL_HANDLE;
  }
  VkPipeline pipeline(VkPrimitiveTopology topology,bool depth_test) {
    VkPipelineShaderStageCreateInfo stages[2]{};
    stages[0].sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[0].stage=VK_SHADER_STAGE_VERTEX_BIT; stages[0].module=vs; stages[0].pName="main";
    stages[1].sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[1].stage=VK_SHADER_STAGE_FRAGMENT_BIT; stages[1].module=fs; stages[1].pName="main";
    uint32_t srgb_attachment=(format==VK_FORMAT_B8G8R8A8_SRGB || format==VK_FORMAT_R8G8B8A8_SRGB);
    VkSpecializationMapEntry transfer_entry{0,0,sizeof(srgb_attachment)};
    VkSpecializationInfo transfer{1,&transfer_entry,sizeof(srgb_attachment),&srgb_attachment};
    stages[1].pSpecializationInfo=&transfer;
    VkVertexInputBindingDescription binding{0,sizeof(Vertex),VK_VERTEX_INPUT_RATE_VERTEX};
    VkVertexInputAttributeDescription attrs[2]={{0,0,VK_FORMAT_R32G32B32_SFLOAT,offsetof(Vertex,position)},
      {1,0,VK_FORMAT_R32G32B32_SFLOAT,offsetof(Vertex,color)}};
    VkPipelineVertexInputStateCreateInfo input{VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
    input.vertexBindingDescriptionCount=1; input.pVertexBindingDescriptions=&binding;
    input.vertexAttributeDescriptionCount=2; input.pVertexAttributeDescriptions=attrs;
    VkPipelineInputAssemblyStateCreateInfo assembly{VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO};
    assembly.topology=topology;
    VkPipelineViewportStateCreateInfo viewport{VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO};
    viewport.viewportCount=1; viewport.scissorCount=1;
    VkDynamicState dynamic_states[]={VK_DYNAMIC_STATE_VIEWPORT,VK_DYNAMIC_STATE_SCISSOR};
    VkPipelineDynamicStateCreateInfo dynamic{VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO};
    dynamic.dynamicStateCount=2; dynamic.pDynamicStates=dynamic_states;
    VkPipelineRasterizationStateCreateInfo raster{VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO};
    raster.polygonMode=VK_POLYGON_MODE_FILL; raster.cullMode=VK_CULL_MODE_NONE; raster.lineWidth=1;
    VkPipelineMultisampleStateCreateInfo ms{VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO};
    ms.rasterizationSamples=VK_SAMPLE_COUNT_1_BIT;
    VkPipelineDepthStencilStateCreateInfo ds{VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO};
    ds.depthTestEnable=depth_test; ds.depthWriteEnable=depth_test; ds.depthCompareOp=VK_COMPARE_OP_LESS;
    VkPipelineColorBlendAttachmentState attachment{};
    attachment.colorWriteMask=VK_COLOR_COMPONENT_R_BIT|VK_COLOR_COMPONENT_G_BIT|
      VK_COLOR_COMPONENT_B_BIT|VK_COLOR_COMPONENT_A_BIT;
    VkPipelineColorBlendStateCreateInfo blend{VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
    blend.attachmentCount=1; blend.pAttachments=&attachment;
    VkPipelineRenderingCreateInfo rendering{VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO};
    rendering.colorAttachmentCount=1; rendering.pColorAttachmentFormats=&format;
    rendering.depthAttachmentFormat=VK_FORMAT_D32_SFLOAT;
    VkGraphicsPipelineCreateInfo info{VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO};
    info.pNext=&rendering; info.stageCount=2; info.pStages=stages;
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
      if (std::find(modes.begin(),modes.end(),VK_PRESENT_MODE_IMMEDIATE_KHR)!=modes.end())
        ci.presentMode=VK_PRESENT_MODE_IMMEDIATE_KHR;
      else if (std::find(modes.begin(),modes.end(),VK_PRESENT_MODE_MAILBOX_KHR)!=modes.end())
        ci.presentMode=VK_PRESENT_MODE_MAILBOX_KHR;
      else throw std::runtime_error("unpaced Vulkan present mode unavailable");
      std::fprintf(stderr,"stress_present_mode,%s\n",
        ci.presentMode==VK_PRESENT_MODE_IMMEDIATE_KHR?"immediate":"mailbox");
    }
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
  }
  bool ensure_vertices(VkDeviceSize bytes) {
    if (bytes<=capacity) return false;
    if (mapped) vkUnmapMemory(device,vertex_memory);
    if (vertices) vkDestroyBuffer(device,vertices,nullptr);
    if (vertex_memory) vkFreeMemory(device,vertex_memory,nullptr);
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
    check(vkAllocateMemory(device,&ai,nullptr,&vertex_memory),"allocate vertex buffer");
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
    VkShaderModuleCreateInfo mi{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
    mi.codeSize=vertex_code.size()*4; mi.pCode=vertex_code.data();
    check(vkCreateShaderModule(device,&mi,nullptr,&vs),"create vertex shader");
    mi.codeSize=fragment_code.size()*4; mi.pCode=fragment_code.data();
    check(vkCreateShaderModule(device,&mi,nullptr,&fs),"create fragment shader");
    VkPushConstantRange range{VK_SHADER_STAGE_VERTEX_BIT,0,sizeof(Push)};
    VkPipelineLayoutCreateInfo li{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
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
      vkDeviceWaitIdle(device);
      clear_swapchain();
      if (mapped) vkUnmapMemory(device,vertex_memory);
      if (vertices) vkDestroyBuffer(device,vertices,nullptr);
      if (vertex_memory) vkFreeMemory(device,vertex_memory,nullptr);
      if (acquired) vkDestroySemaphore(device,acquired,nullptr);
      if (fence) vkDestroyFence(device,fence,nullptr);
      if (pool) vkDestroyCommandPool(device,pool,nullptr);
      if (layout) vkDestroyPipelineLayout(device,layout,nullptr);
      if (vs) vkDestroyShaderModule(device,vs,nullptr);
      if (fs) vkDestroyShaderModule(device,fs,nullptr);
      vkDestroyDevice(device,nullptr);
    }
    if (surface) vkDestroySurfaceKHR(instance,surface,nullptr);
    if (instance) vkDestroyInstance(instance,nullptr);
  }
  bool matches(Display* d,::Window w) const { return d==display&&w==window; }
  void render(const VoxelVkFrame& frame,VoxelVkTimings& timings) {
    auto start=Clock::now();
    bool scene_reused=false;
    Geometry& g=geometry(frame,geometry_cache,scene_reused);
    auto after_geometry=Clock::now();
    timings.geometry_us=microseconds(start,after_geometry);
    check(vkWaitForFences(device,1,&fence,VK_TRUE,UINT64_MAX),"wait for frame fence");
    auto after_fence=Clock::now();
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
    if (std::getenv("VOXEL_STRESS_SCENE")) {
      static uint32_t cache_frame;
      std::fprintf(stdout,"mesh_cache,%u,%u,%u,%zu,%u,%zu\n",cache_frame++,
        geometry_cache.rebuilt,frame.body_count,geometry_cache.draws.size(),
        geometry_cache.scene_vertices,uploaded_vertices*sizeof(Vertex));
    }
    timings.vertex_upload_us=microseconds(after_fence,after_upload);
    uint32_t index=0;
    VkResult acquire=vkAcquireNextImageKHR(device,swapchain,UINT64_MAX,acquired,VK_NULL_HANDLE,&index);
    auto after_acquire=Clock::now();
    timings.acquire_us=microseconds(after_upload,after_acquire);
    if (acquire==VK_ERROR_OUT_OF_DATE_KHR) {
      check(vkDeviceWaitIdle(device),"wait for swapchain recreation");
      clear_swapchain(); make_swapchain(); return;
    }
    if (acquire!=VK_SUCCESS&&acquire!=VK_SUBOPTIMAL_KHR) check(acquire,"acquire swapchain image");
    check(vkResetCommandBuffer(command,0),"reset command buffer");
    VkCommandBufferBeginInfo bi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    check(vkBeginCommandBuffer(command,&bi),"begin command buffer");
    barrier(images[index],VK_IMAGE_ASPECT_COLOR_BIT,VK_IMAGE_LAYOUT_UNDEFINED,
      VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
      VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,0,VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT);
    barrier(depth,VK_IMAGE_ASPECT_DEPTH_BIT,VK_IMAGE_LAYOUT_UNDEFINED,
      VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
      VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,0,VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT);
    VkRenderingAttachmentInfo color{VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
    color.imageView=views[index]; color.imageLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    color.loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR; color.storeOp=VK_ATTACHMENT_STORE_OP_STORE;
    auto background=rgb(0x12202e);
    if (format==VK_FORMAT_B8G8R8A8_SRGB || format==VK_FORMAT_R8G8B8A8_SRGB) {
      auto linear=material::decode({background.x,background.y,background.z});
      background={linear.r,linear.g,linear.b};
    }
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
    VkDeviceSize offset=0; vkCmdBindVertexBuffers(command,0,1,&vertices,&offset);
    Push push{{frame.eye[0],frame.eye[1],frame.eye[2],frame.yaw},{frame.pitch,0,0,0}};
    vkCmdPushConstants(command,layout,VK_SHADER_STAGE_VERTEX_BIT,0,sizeof(Push),&push);
    vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_GRAPHICS,triangles);
    vkCmdDraw(command,6,1,0,0); // Ground.
    for (auto draw:geometry_cache.draws) {
      push.pitch_offset[1]=draw.offset;
      vkCmdPushConstants(command,layout,VK_SHADER_STAGE_VERTEX_BIT,0,sizeof(Push),&push);
      vkCmdDraw(command,draw.count,1,draw.first,0);
    }
    push.pitch_offset[1]=0;
    vkCmdPushConstants(command,layout,VK_SHADER_STAGE_VERTEX_BIT,0,sizeof(Push),&push);
    vkCmdDraw(command,g.triangles-geometry_cache.scene_vertices,1,geometry_cache.scene_vertices,0);
    if (g.lines) {
      vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_GRAPHICS,lines);
      vkCmdDraw(command,g.lines,1,g.triangles,0);
    }
    if (g.hud) {
      push.pitch_offset[2]=1;
      vkCmdPushConstants(command,layout,VK_SHADER_STAGE_VERTEX_BIT,0,sizeof(Push),&push);
      vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_GRAPHICS,hud_pipeline);
      vkCmdDraw(command,g.hud,1,g.triangles+g.lines,0);
    }
    vkCmdEndRendering(command);
    barrier(images[index],VK_IMAGE_ASPECT_COLOR_BIT,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
      VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
      VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,0);
    check(vkEndCommandBuffer(command),"end command buffer");
    auto after_record=Clock::now();
    timings.command_record_us=microseconds(after_acquire,after_record);
    check(vkResetFences(device,1,&fence),"reset frame fence");
    VkPipelineStageFlags wait_stage=VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    submit.waitSemaphoreCount=1; submit.pWaitSemaphores=&acquired;
    submit.pWaitDstStageMask=&wait_stage; submit.commandBufferCount=1;
    submit.pCommandBuffers=&command; submit.signalSemaphoreCount=1;
    submit.pSignalSemaphores=&finished[index];
    check(vkQueueSubmit(queue,1,&submit,fence),"submit frame");
    VkPresentInfoKHR present{VK_STRUCTURE_TYPE_PRESENT_INFO_KHR};
    present.waitSemaphoreCount=1; present.pWaitSemaphores=&finished[index];
    present.swapchainCount=1; present.pSwapchains=&swapchain; present.pImageIndices=&index;
    VkResult result=vkQueuePresentKHR(queue,&present);
    timings.submit_present_us=microseconds(after_record,Clock::now());
    if (result==VK_ERROR_OUT_OF_DATE_KHR||result==VK_SUBOPTIMAL_KHR) {
      check(vkDeviceWaitIdle(device),"wait for swapchain recreation");
      clear_swapchain(); make_swapchain();
    } else check(result,"present frame");
  }
};
std::unique_ptr<Renderer> renderer;
}

extern "C" int voxel_vk_render(void* display,unsigned long window,const VoxelVkFrame* frame,
  VoxelVkTimings* timings,char* error,size_t error_cap) {
  try {
    if (!frame || !display || !window || !timings) throw std::runtime_error("invalid Vulkan frame");
    *timings={};
    if (!renderer) renderer=std::make_unique<Renderer>(static_cast<Display*>(display),window);
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
extern "C" void voxel_vk_release(void) { renderer.reset(); }
