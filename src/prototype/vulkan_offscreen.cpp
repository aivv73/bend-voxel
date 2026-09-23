// PROTOTYPE: native Vulkan raster pass for Bend's cached face rectangles.
// A fixed-clock Bend exporter supplies scene data; no simulation lives here.
#include <vulkan/vulkan.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <numeric>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

static void check(VkResult result, const char* operation) {
  if (result != VK_SUCCESS) throw std::runtime_error(std::string(operation) + ": Vulkan result " + std::to_string(result));
}

struct Vec3 { float x, y, z; };
static Vec3 operator+(Vec3 a, Vec3 b) { return {a.x+b.x,a.y+b.y,a.z+b.z}; }
static Vec3 operator-(Vec3 a, Vec3 b) { return {a.x-b.x,a.y-b.y,a.z-b.z}; }
static Vec3 operator*(Vec3 a, float k) { return {a.x*k,a.y*k,a.z*k}; }
static Vec3 cross(Vec3 a, Vec3 b) { return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x}; }
struct Vertex { Vec3 position, color; };
struct Draw { uint32_t first, count; float offset; };
struct Scene {
  Vec3 eye{};
  float yaw=0, pitch=0;
  uint32_t tick=0, solids=0, bodies=0;
  std::vector<Vertex> vertices;
  std::vector<Draw> draws;
};
static std::vector<std::string> split(const std::string& line) {
  std::vector<std::string> out;
  std::stringstream stream(line);
  std::string part;
  while (std::getline(stream, part, ',')) out.push_back(part);
  return out;
}
static Vec3 rgb(uint32_t word) {
  return {float((word>>16)&255)/255.0f,float((word>>8)&255)/255.0f,float(word&255)/255.0f};
}
static void quad(Scene& s, Vec3 a, Vec3 b, Vec3 c, Vec3 d, Vec3 color) {
  color={std::floor(color.x*255.0f)/255.0f,std::floor(color.y*255.0f)/255.0f,std::floor(color.z*255.0f)/255.0f};
  for (Vec3 p : {a,b,c,a,c,d}) s.vertices.push_back({p,color});
}
static void face(Scene& s, int body, int index, int side, int length, int rows) {
  if (index<0 || index>=19200 || side<0 || side>5 || length<1 || rows<1) throw std::runtime_error("bad face fields");
  const int x=index%40, y=index/40%24, z=index/960;
  Vec3 p={x*0.1f-1.95f,y*0.1f+0.05f,z*0.1f-0.95f};
  const float half=(length-1)*0.05f;
  if (side<2) p.z+=half;
  else { p.x+=half; p.z+=(rows-1)*0.05f; }
  const Vec3 normal[]={{-1,0,0},{1,0,0},{0,-1,0},{0,1,0},{0,0,-1},{0,0,1}};
  const Vec3 tangent[]={{0,0,.05f},{0,.05f,0},{.05f,0,0},{0,0,.05f},{0,.05f,0},{.05f,0,0}};
  Vec3 n=normal[side];
  Vec3 u=tangent[side], v=cross(n,u);
  u=u*float(side==0 || side==2 || side==5 ? length:1);
  v=v*float(side==1 || side==3 || side==4 ? length:1);
  u=u*float(side==3 ? rows:1);
  v=v*float(side==2 ? rows:1);
  Vec3 c=p+n*0.05f;
  uint32_t word=(body==1 && y==0) ? 4964772u : (body>1 ? 11375835u:13736040u);
  float shade=side==3 ? 1.0f : (side<2 ? .78f:.62f);
  quad(s,c-u-v,c+u-v,c+u+v,c-u+v,rgb(word)*shade);
}
static Scene read_scene(const std::string& path) {
  std::ifstream in(path);
  if (!in) throw std::runtime_error("cannot read scene: "+path);
  Scene s;
  quad(s,{-6,0,-6},{-6,0,6},{6,0,6},{6,0,-6},{.12f,.19f,.24f});
  s.draws.push_back({0,6,0});
  std::string line;
  int body=-1;
  bool ended=false;
  while (std::getline(in,line)) {
    auto a=split(line);
    if (a.empty()) continue;
    if (a[0]=="scene" && a.size()==5) {
      if (a[1]!="1" || a[2]!="640" || a[3]!="360") throw std::runtime_error("unsupported scene format");
      s.tick=std::stoul(a[4]);
    } else if (a[0]=="camera" && a.size()==6) {
      s.eye={std::stof(a[1]),std::stof(a[2]),std::stof(a[3])};
      s.yaw=std::stof(a[4]); s.pitch=std::stof(a[5]);
    } else if (a[0]=="state" && a.size()==5) {
      s.solids=std::stoul(a[1]); s.bodies=std::stoul(a[2]);
    } else if (a[0]=="body" && a.size()==3 && body<0) {
      body=std::stoi(a[1]);
      s.draws.push_back({uint32_t(s.vertices.size()),0,std::stof(a[2])});
    } else if (a[0]=="face" && a.size()==5 && body>=0) {
      face(s,body,std::stoi(a[1]),std::stoi(a[2]),std::stoi(a[3]),std::stoi(a[4]));
    } else if (a[0]=="endbody" && a.size()==1 && body>=0) {
      s.draws.back().count=uint32_t(s.vertices.size())-s.draws.back().first;
      body=-1;
    } else if (a[0]=="end" && a.size()==1 && body<0) {
      ended=true;
    } else throw std::runtime_error("invalid scene line: "+line);
  }
  if (!ended || s.draws.size()<2) throw std::runtime_error("incomplete scene");
  return s;
}

static std::vector<uint32_t> spirv(const std::string& path) {
  std::ifstream in(path,std::ios::binary|std::ios::ate);
  if (!in) throw std::runtime_error("cannot read shader: "+path);
  auto size=in.tellg();
  if (size<=0 || size%4) throw std::runtime_error("invalid shader: "+path);
  std::vector<uint32_t> code(size/4);
  in.seekg(0); in.read(reinterpret_cast<char*>(code.data()),size);
  return code;
}

struct Push { float eye_yaw[4], pitch_offset[4]; };
class Renderer {
  static constexpr uint32_t W=640,H=360;
  VkInstance instance=VK_NULL_HANDLE;
  VkPhysicalDevice physical=VK_NULL_HANDLE;
  VkDevice device=VK_NULL_HANDLE;
  VkQueue queue=VK_NULL_HANDLE;
  uint32_t family=0;
  VkCommandPool pool=VK_NULL_HANDLE;
  VkCommandBuffer command=VK_NULL_HANDLE;
  VkFence fence=VK_NULL_HANDLE;
  VkImage color=VK_NULL_HANDLE,depth=VK_NULL_HANDLE;
  VkDeviceMemory color_memory=VK_NULL_HANDLE,depth_memory=VK_NULL_HANDLE;
  VkImageView color_view=VK_NULL_HANDLE,depth_view=VK_NULL_HANDLE;
  VkBuffer vertices=VK_NULL_HANDLE,readback=VK_NULL_HANDLE;
  VkDeviceMemory vertex_memory=VK_NULL_HANDLE,readback_memory=VK_NULL_HANDLE;
  void* pixels=nullptr;
  VkPipelineLayout layout=VK_NULL_HANDLE;
  VkPipeline pipeline=VK_NULL_HANDLE;
  VkShaderModule vertex_shader=VK_NULL_HANDLE,fragment_shader=VK_NULL_HANDLE;
  VkQueryPool queries=VK_NULL_HANDLE;
  bool timestamps=false,first=true;
  float timestamp_period=0;
  std::string device_name;
  uint32_t vertex_count=0;
  VkDeviceSize vertex_bytes=0;
  uint32_t memory_type(uint32_t bits,VkMemoryPropertyFlags flags) {
    VkPhysicalDeviceMemoryProperties props{};
    vkGetPhysicalDeviceMemoryProperties(physical,&props);
    for (uint32_t i=0;i<props.memoryTypeCount;i++)
      if ((bits&(1u<<i)) && (props.memoryTypes[i].propertyFlags&flags)==flags) return i;
    throw std::runtime_error("required Vulkan memory type is unavailable");
  }
  void make_image(VkFormat format,VkImageUsageFlags usage,VkImageAspectFlags aspect,VkImage& image,VkDeviceMemory& memory,VkImageView& view) {
    VkImageCreateInfo info{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    info.imageType=VK_IMAGE_TYPE_2D; info.format=format; info.extent={W,H,1};
    info.mipLevels=1; info.arrayLayers=1; info.samples=VK_SAMPLE_COUNT_1_BIT;
    info.tiling=VK_IMAGE_TILING_OPTIMAL; info.usage=usage;
    check(vkCreateImage(device,&info,nullptr,&image),"create image");
    VkMemoryRequirements req{}; vkGetImageMemoryRequirements(device,image,&req);
    VkMemoryAllocateInfo alloc{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    alloc.allocationSize=req.size;
    alloc.memoryTypeIndex=memory_type(req.memoryTypeBits,VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    check(vkAllocateMemory(device,&alloc,nullptr,&memory),"allocate image");
    check(vkBindImageMemory(device,image,memory,0),"bind image");
    VkImageViewCreateInfo vi{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    vi.image=image; vi.viewType=VK_IMAGE_VIEW_TYPE_2D; vi.format=format;
    vi.subresourceRange={aspect,0,1,0,1};
    check(vkCreateImageView(device,&vi,nullptr,&view),"create image view");
  }
  void make_buffer(VkDeviceSize size,VkBufferUsageFlags usage,VkBuffer& buffer,VkDeviceMemory& memory) {
    VkBufferCreateInfo info{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    info.size=size; info.usage=usage; info.sharingMode=VK_SHARING_MODE_EXCLUSIVE;
    check(vkCreateBuffer(device,&info,nullptr,&buffer),"create buffer");
    VkMemoryRequirements req{}; vkGetBufferMemoryRequirements(device,buffer,&req);
    VkMemoryAllocateInfo alloc{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    alloc.allocationSize=req.size;
    alloc.memoryTypeIndex=memory_type(req.memoryTypeBits,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    check(vkAllocateMemory(device,&alloc,nullptr,&memory),"allocate buffer");
    check(vkBindBufferMemory(device,buffer,memory,0),"bind buffer");
  }
  VkShaderModule make_shader(const std::string& path) {
    auto code=spirv(path);
    VkShaderModuleCreateInfo info{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
    info.codeSize=code.size()*sizeof(uint32_t); info.pCode=code.data();
    VkShaderModule module=VK_NULL_HANDLE;
    check(vkCreateShaderModule(device,&info,nullptr,&module),"create shader module");
    return module;
  }
  void make_pipeline(const std::string& vert,const std::string& frag) {
    vertex_shader=make_shader(vert); fragment_shader=make_shader(frag);
    VkPushConstantRange range{VK_SHADER_STAGE_VERTEX_BIT,0,sizeof(Push)};
    VkPipelineLayoutCreateInfo li{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    li.pushConstantRangeCount=1; li.pPushConstantRanges=&range;
    check(vkCreatePipelineLayout(device,&li,nullptr,&layout),"create pipeline layout");
    VkPipelineShaderStageCreateInfo stages[2]{};
    stages[0].sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[0].stage=VK_SHADER_STAGE_VERTEX_BIT; stages[0].module=vertex_shader; stages[0].pName="main";
    stages[1].sType=VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[1].stage=VK_SHADER_STAGE_FRAGMENT_BIT; stages[1].module=fragment_shader; stages[1].pName="main";
    VkVertexInputBindingDescription binding{0,sizeof(Vertex),VK_VERTEX_INPUT_RATE_VERTEX};
    VkVertexInputAttributeDescription attributes[2]={{0,0,VK_FORMAT_R32G32B32_SFLOAT,offsetof(Vertex,position)},
                                                     {1,0,VK_FORMAT_R32G32B32_SFLOAT,offsetof(Vertex,color)}};
    VkPipelineVertexInputStateCreateInfo input{VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
    input.vertexBindingDescriptionCount=1; input.pVertexBindingDescriptions=&binding;
    input.vertexAttributeDescriptionCount=2; input.pVertexAttributeDescriptions=attributes;
    VkPipelineInputAssemblyStateCreateInfo assembly{VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO};
    assembly.topology=VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    VkViewport viewport{0,0,float(W),float(H),0,1};
    VkRect2D scissor{{0,0},{W,H}};
    VkPipelineViewportStateCreateInfo vp{VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO};
    vp.viewportCount=1; vp.pViewports=&viewport; vp.scissorCount=1; vp.pScissors=&scissor;
    VkPipelineRasterizationStateCreateInfo raster{VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO};
    raster.polygonMode=VK_POLYGON_MODE_FILL; raster.cullMode=VK_CULL_MODE_NONE;
    raster.frontFace=VK_FRONT_FACE_COUNTER_CLOCKWISE; raster.lineWidth=1;
    VkPipelineMultisampleStateCreateInfo ms{VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO};
    ms.rasterizationSamples=VK_SAMPLE_COUNT_1_BIT;
    VkPipelineDepthStencilStateCreateInfo ds{VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO};
    ds.depthTestEnable=VK_TRUE; ds.depthWriteEnable=VK_TRUE; ds.depthCompareOp=VK_COMPARE_OP_LESS;
    VkPipelineColorBlendAttachmentState attachment{};
    attachment.colorWriteMask=VK_COLOR_COMPONENT_R_BIT|VK_COLOR_COMPONENT_G_BIT|VK_COLOR_COMPONENT_B_BIT|VK_COLOR_COMPONENT_A_BIT;
    VkPipelineColorBlendStateCreateInfo blend{VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
    blend.attachmentCount=1; blend.pAttachments=&attachment;
    VkFormat color_format=VK_FORMAT_R8G8B8A8_UNORM;
    VkPipelineRenderingCreateInfo rendering{VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO};
    rendering.colorAttachmentCount=1; rendering.pColorAttachmentFormats=&color_format;
    rendering.depthAttachmentFormat=VK_FORMAT_D32_SFLOAT;
    VkGraphicsPipelineCreateInfo info{VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO};
    info.pNext=&rendering; info.stageCount=2; info.pStages=stages;
    info.pVertexInputState=&input; info.pInputAssemblyState=&assembly;
    info.pViewportState=&vp; info.pRasterizationState=&raster;
    info.pMultisampleState=&ms; info.pDepthStencilState=&ds;
    info.pColorBlendState=&blend; info.layout=layout;
    check(vkCreateGraphicsPipelines(device,VK_NULL_HANDLE,1,&info,nullptr,&pipeline),"create graphics pipeline");
  }
  void barrier(VkImage image,VkImageAspectFlags aspect,VkImageLayout old_layout,VkImageLayout new_layout,
               VkPipelineStageFlags src_stage,VkPipelineStageFlags dst_stage,VkAccessFlags src_access,VkAccessFlags dst_access) {
    VkImageMemoryBarrier b{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
    b.oldLayout=old_layout; b.newLayout=new_layout;
    b.srcAccessMask=src_access; b.dstAccessMask=dst_access;
    b.image=image; b.subresourceRange={aspect,0,1,0,1};
    vkCmdPipelineBarrier(command,src_stage,dst_stage,0,0,nullptr,0,nullptr,1,&b);
  }
public:
  Renderer(const Scene& scene,const std::string& vert,const std::string& frag) {
    VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    app.pApplicationName="bend-voxel-vulkan-prototype"; app.apiVersion=VK_API_VERSION_1_3;
    VkInstanceCreateInfo ci{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO}; ci.pApplicationInfo=&app;
    check(vkCreateInstance(&ci,nullptr,&instance),"create instance");
    uint32_t count=0; check(vkEnumeratePhysicalDevices(instance,&count,nullptr),"enumerate devices");
    if (!count) throw std::runtime_error("no Vulkan device");
    std::vector<VkPhysicalDevice> devices(count);
    check(vkEnumeratePhysicalDevices(instance,&count,devices.data()),"enumerate devices");
    for (auto candidate:devices) {
      uint32_t n=0; vkGetPhysicalDeviceQueueFamilyProperties(candidate,&n,nullptr);
      std::vector<VkQueueFamilyProperties> families(n);
      vkGetPhysicalDeviceQueueFamilyProperties(candidate,&n,families.data());
      for (uint32_t j=0;j<n;j++) if (families[j].queueFlags&VK_QUEUE_GRAPHICS_BIT) {
        physical=candidate; family=j; timestamps=families[j].timestampValidBits>0; break;
      }
      if (physical) break;
    }
    if (!physical) throw std::runtime_error("no graphics queue");
    VkPhysicalDeviceProperties props{}; vkGetPhysicalDeviceProperties(physical,&props);
    if (VK_API_VERSION_MAJOR(props.apiVersion)<1 ||
        (VK_API_VERSION_MAJOR(props.apiVersion)==1 && VK_API_VERSION_MINOR(props.apiVersion)<3))
      throw std::runtime_error("Vulkan 1.3 is required for dynamic rendering");
    device_name=props.deviceName;
    timestamp_period=props.limits.timestampPeriod;
    std::cerr << "Vulkan device: " << device_name << "\n";
    float priority=1;
    VkDeviceQueueCreateInfo qi{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    qi.queueFamilyIndex=family; qi.queueCount=1; qi.pQueuePriorities=&priority;
    VkPhysicalDeviceVulkan13Features features{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES};
    features.dynamicRendering=VK_TRUE;
    VkDeviceCreateInfo di{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    di.pNext=&features; di.queueCreateInfoCount=1; di.pQueueCreateInfos=&qi;
    check(vkCreateDevice(physical,&di,nullptr,&device),"create device");
    vkGetDeviceQueue(device,family,0,&queue);
    VkCommandPoolCreateInfo pi{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    pi.flags=VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT; pi.queueFamilyIndex=family;
    check(vkCreateCommandPool(device,&pi,nullptr,&pool),"create command pool");
    VkCommandBufferAllocateInfo ai{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    ai.commandPool=pool; ai.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY; ai.commandBufferCount=1;
    check(vkAllocateCommandBuffers(device,&ai,&command),"allocate command buffer");
    VkFenceCreateInfo fi{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    check(vkCreateFence(device,&fi,nullptr,&fence),"create fence");
    make_image(VK_FORMAT_R8G8B8A8_UNORM,VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
               VK_IMAGE_ASPECT_COLOR_BIT,color,color_memory,color_view);
    make_image(VK_FORMAT_D32_SFLOAT,VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
               VK_IMAGE_ASPECT_DEPTH_BIT,depth,depth_memory,depth_view);
    vertex_count=uint32_t(scene.vertices.size());
    vertex_bytes=scene.vertices.size()*sizeof(Vertex);
    make_buffer(vertex_bytes,VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,vertices,vertex_memory);
    void* mapped=nullptr;
    check(vkMapMemory(device,vertex_memory,0,vertex_bytes,0,&mapped),"map vertices");
    std::memcpy(mapped,scene.vertices.data(),vertex_bytes); vkUnmapMemory(device,vertex_memory);
    make_buffer(W*H*4,VK_BUFFER_USAGE_TRANSFER_DST_BIT,readback,readback_memory);
    check(vkMapMemory(device,readback_memory,0,W*H*4,0,&pixels),"map readback");
    make_pipeline(vert,frag);
    if (timestamps) {
      VkQueryPoolCreateInfo q{VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO};
      q.queryType=VK_QUERY_TYPE_TIMESTAMP; q.queryCount=2;
      check(vkCreateQueryPool(device,&q,nullptr,&queries),"create query pool");
    }
  }
  ~Renderer() {
    if (!device) return;
    vkDeviceWaitIdle(device);
    if (queries) vkDestroyQueryPool(device,queries,nullptr);
    if (pipeline) vkDestroyPipeline(device,pipeline,nullptr);
    if (layout) vkDestroyPipelineLayout(device,layout,nullptr);
    if (vertex_shader) vkDestroyShaderModule(device,vertex_shader,nullptr);
    if (fragment_shader) vkDestroyShaderModule(device,fragment_shader,nullptr);
    if (pixels) vkUnmapMemory(device,readback_memory);
    if (vertices) vkDestroyBuffer(device,vertices,nullptr);
    if (readback) vkDestroyBuffer(device,readback,nullptr);
    if (vertex_memory) vkFreeMemory(device,vertex_memory,nullptr);
    if (readback_memory) vkFreeMemory(device,readback_memory,nullptr);
    if (color_view) vkDestroyImageView(device,color_view,nullptr);
    if (depth_view) vkDestroyImageView(device,depth_view,nullptr);
    if (color) vkDestroyImage(device,color,nullptr);
    if (depth) vkDestroyImage(device,depth,nullptr);
    if (color_memory) vkFreeMemory(device,color_memory,nullptr);
    if (depth_memory) vkFreeMemory(device,depth_memory,nullptr);
    if (fence) vkDestroyFence(device,fence,nullptr);
    if (pool) vkDestroyCommandPool(device,pool,nullptr);
    vkDestroyDevice(device,nullptr);
    if (instance) vkDestroyInstance(instance,nullptr);
  }
  double frame(const Scene& scene,double* gpu_ms) {
    auto start=std::chrono::steady_clock::now();
    check(vkResetCommandBuffer(command,0),"reset command buffer");
    VkCommandBufferBeginInfo begin{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    check(vkBeginCommandBuffer(command,&begin),"begin command buffer");
    barrier(color,VK_IMAGE_ASPECT_COLOR_BIT,first?VK_IMAGE_LAYOUT_UNDEFINED:VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,first?VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT:VK_PIPELINE_STAGE_TRANSFER_BIT,
            VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,first?0:VK_ACCESS_TRANSFER_READ_BIT,VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT);
    barrier(depth,VK_IMAGE_ASPECT_DEPTH_BIT,first?VK_IMAGE_LAYOUT_UNDEFINED:VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
            VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,first?VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT:VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
            VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,first?0:VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT);
    if (timestamps) {
      vkCmdResetQueryPool(command,queries,0,2);
      vkCmdWriteTimestamp(command,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,queries,0);
    }
    VkRenderingAttachmentInfo ca{VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
    ca.imageView=color_view; ca.imageLayout=VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    ca.loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR; ca.storeOp=VK_ATTACHMENT_STORE_OP_STORE;
    ca.clearValue.color={{float(0x12)/255.0f,float(0x20)/255.0f,float(0x2e)/255.0f,1}};
    VkRenderingAttachmentInfo da{VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
    da.imageView=depth_view; da.imageLayout=VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    da.loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR; da.storeOp=VK_ATTACHMENT_STORE_OP_DONT_CARE;
    da.clearValue.depthStencil={1.0f,0};
    VkRenderingInfo ri{VK_STRUCTURE_TYPE_RENDERING_INFO};
    ri.renderArea={{0,0},{W,H}}; ri.layerCount=1;
    ri.colorAttachmentCount=1; ri.pColorAttachments=&ca; ri.pDepthAttachment=&da;
    vkCmdBeginRendering(command,&ri);
    vkCmdBindPipeline(command,VK_PIPELINE_BIND_POINT_GRAPHICS,pipeline);
    VkDeviceSize offset=0; vkCmdBindVertexBuffers(command,0,1,&vertices,&offset);
    for (const Draw& draw:scene.draws) {
      Push push{{scene.eye.x,scene.eye.y,scene.eye.z,scene.yaw},{scene.pitch,draw.offset,0,0}};
      vkCmdPushConstants(command,layout,VK_SHADER_STAGE_VERTEX_BIT,0,sizeof(Push),&push);
      vkCmdDraw(command,draw.count,1,draw.first,0);
    }
    vkCmdEndRendering(command);
    if (timestamps) vkCmdWriteTimestamp(command,VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,queries,1);
    barrier(color,VK_IMAGE_ASPECT_COLOR_BIT,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,
            VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,VK_ACCESS_TRANSFER_READ_BIT);
    VkBufferImageCopy copy{};
    copy.imageSubresource={VK_IMAGE_ASPECT_COLOR_BIT,0,0,1}; copy.imageExtent={W,H,1};
    vkCmdCopyImageToBuffer(command,color,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,readback,1,&copy);
    check(vkEndCommandBuffer(command),"end command buffer");
    check(vkResetFences(device,1,&fence),"reset fence");
    VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    submit.commandBufferCount=1; submit.pCommandBuffers=&command;
    check(vkQueueSubmit(queue,1,&submit,fence),"submit");
    check(vkWaitForFences(device,1,&fence,VK_TRUE,UINT64_MAX),"wait for frame");
    if (timestamps) {
      uint64_t values[2]{};
      check(vkGetQueryPoolResults(device,queries,0,2,sizeof(values),values,sizeof(uint64_t),VK_QUERY_RESULT_64_BIT),"get timestamps");
      *gpu_ms=double(values[1]-values[0])*timestamp_period/1000000.0;
    }
    first=false;
    return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
  }
  void ppm(const std::string& path) const {
    std::ofstream out(path,std::ios::binary);
    if (!out) throw std::runtime_error("cannot write image: "+path);
    out << "P6\n" << W << ' ' << H << "\n255\n";
    const auto* rgba=static_cast<const uint8_t*>(pixels);
    for (uint32_t i=0;i<W*H;i++) out.write(reinterpret_cast<const char*>(rgba+i*4),3);
  }
  const std::string& name() const { return device_name; }
};

static double median(std::vector<double> values) {
  std::sort(values.begin(),values.end());
  return values[values.size()/2];
}
int main(int argc,char** argv) {
  try {
    if (argc<5 || argc>6) {
      std::cerr << "usage: vulkan-offscreen scene.csv vertex.spv fragment.spv output.ppm [frames]\n";
      return 2;
    }
    int frames=argc==6?std::stoi(argv[5]):40;
    if (frames<1 || frames>10000) throw std::runtime_error("frames must be 1..10000");
    auto prepare_start=std::chrono::steady_clock::now();
    Scene scene=read_scene(argv[1]);
    double prepare_ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-prepare_start).count();
    Renderer renderer(scene,argv[2],argv[3]);
    std::vector<double> wall,gpu;
    for (int i=0;i<frames+5;i++) {
      double g=0,w=renderer.frame(scene,&g);
      if (i>=5) { wall.push_back(w); gpu.push_back(g); }
    }
    renderer.ppm(argv[4]);
    std::cout << "{\"device\":\"" << renderer.name() << "\",\"tick\":" << scene.tick << ",\"solids\":" << scene.solids
              << ",\"bodies\":" << scene.bodies << ",\"faces\":" << scene.vertices.size()/6-1
              << ",\"prepare_ms\":" << prepare_ms << ",\"wall_median_ms\":" << median(wall)
              << ",\"gpu_median_ms\":" << median(gpu) << ",\"frames\":" << frames << "}\n";
  } catch (const std::exception& e) { std::cerr << "vulkan-offscreen: " << e.what() << '\n'; return 1; }
}
