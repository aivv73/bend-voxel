// Required Megascene monitoring is independent of render/frame progress.
// All opt-in state is absent on the legacy renderer path.
#include <atomic>
#include <condition_variable>
#include <mutex>
#include <thread>
#include <unistd.h>

namespace supervision {
using U=unsigned long long;
static uint64_t tick() {
  timespec t{}; if(clock_gettime(CLOCK_MONOTONIC,&t)) throw std::runtime_error("monitor clock failed");
  return uint64_t(t.tv_sec)*1000000000ull+t.tv_nsec;
}
static FILE *resources=nullptr,*allocations=nullptr;
static std::mutex mutex;
static std::condition_variable wake;
static std::thread monitor;
static bool stopped=false;
static VkInstance instance=VK_NULL_HANDLE;
static VkPhysicalDevice physical=VK_NULL_HANDLE;
static std::string pci;
static uint64_t resource_seq=0,allocation_seq=0,next_id=1,live=0,peak=0;
struct Allocation { uint64_t id,size; uint32_t type,heap; };
static std::map<VkDeviceMemory,Allocation> ledger;
static uint64_t heap_live[VK_MAX_MEMORY_HEAPS]{},heap_peak[VK_MAX_MEMORY_HEAPS]{};
static void emit(FILE* stream,uint64_t& sequence,const std::string& fields) {
  if (!stream) return;
  if (std::fprintf(stream,"{\"schema\":\"megascene-evidence/1\",\"campaign_id\":\"%s\",\"series_id\":\"%s\",\"attempt_id\":\"%s\",\"sequence\":\"%llu\",\"clock_id\":\"linux.CLOCK_MONOTONIC\",\"time_ns\":\"%llu\",%s}\n",
      std::getenv("MEGASCENE_CAMPAIGN"),std::getenv("MEGASCENE_SERIES"),std::getenv("MEGASCENE_ATTEMPT"),U(sequence++),U(tick()),fields.c_str())<0 || std::fflush(stream)) {
    std::fputs("Megascene native persistence failure\n",stderr); std::_Exit(74);
  }
}
static void setup() {
  VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO}; app.apiVersion=VK_API_VERSION_1_3;
  VkInstanceCreateInfo ci{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO}; ci.pApplicationInfo=&app;
  check(vkCreateInstance(&ci,nullptr,&instance),"monitor instance");
  uint32_t n=0; check(vkEnumeratePhysicalDevices(instance,&n,nullptr),"monitor devices");
  std::vector<VkPhysicalDevice> devices(n); check(vkEnumeratePhysicalDevices(instance,&n,devices.data()),"monitor devices");
  for(auto candidate:devices) {
    VkPhysicalDeviceProperties p{}; vkGetPhysicalDeviceProperties(candidate,&p);
    if(p.apiVersion<VK_API_VERSION_1_3) continue;
    uint32_t count=0; vkGetPhysicalDeviceQueueFamilyProperties(candidate,&count,nullptr);
    std::vector<VkQueueFamilyProperties> queues(count); vkGetPhysicalDeviceQueueFamilyProperties(candidate,&count,queues.data());
    for(auto q:queues) if(q.queueFlags&VK_QUEUE_GRAPHICS_BIT) { physical=candidate; break; }
    if(physical) break;
  }
  if(!physical) throw std::runtime_error("required monitor Vulkan device unavailable");
  uint32_t count=0; check(vkEnumerateDeviceExtensionProperties(physical,nullptr,&count,nullptr),"monitor extensions");
  std::vector<VkExtensionProperties> extensions(count);
  check(vkEnumerateDeviceExtensionProperties(physical,nullptr,&count,extensions.data()),"monitor extensions");
  bool budget=false,bus=false;
  for(auto e:extensions) { budget|=!std::strcmp(e.extensionName,VK_EXT_MEMORY_BUDGET_EXTENSION_NAME); bus|=!std::strcmp(e.extensionName,VK_EXT_PCI_BUS_INFO_EXTENSION_NAME); }
  if(!budget || !bus) throw std::runtime_error("required VK_EXT_memory_budget / VK_EXT_pci_bus_info unsupported");
  VkPhysicalDevicePCIBusInfoPropertiesEXT info{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PCI_BUS_INFO_PROPERTIES_EXT};
  VkPhysicalDeviceProperties2 props{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2}; props.pNext=&info;
  vkGetPhysicalDeviceProperties2(physical,&props);
  char name[64]; std::snprintf(name,sizeof name,"%08x:%02x:%02x.%x",info.pciDomain,info.pciBus,info.pciDevice,info.pciFunction); pci=name;
}
static std::string sample() {
  uint64_t begin=tick();
  VkPhysicalDeviceMemoryBudgetPropertiesEXT b{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT};
  VkPhysicalDeviceMemoryProperties2 p{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_PROPERTIES_2}; p.pNext=&b;
  vkGetPhysicalDeviceMemoryProperties2(physical,&p);
  std::string s="\"record_type\":\"heap_sample\",\"status\":\"measured\",\"source\":\"VK_EXT_memory_budget\",\"scope\":\"worker_process_driver_estimate\",\"unit\":\"bytes\",\"device\":\""+pci+"\",\"sample_begin_ns\":\""+std::to_string(begin)+"\",\"sample_end_ns\":\""+std::to_string(tick())+"\",\"heaps\":[";
  for(uint32_t i=0;i<p.memoryProperties.memoryHeapCount;i++) {
    if(i) s+=",";
    s+="{\"heap\":\""+std::to_string(i)+"\",\"flags\":\""+std::to_string(p.memoryProperties.memoryHeaps[i].flags)+"\",\"usage_bytes\":\""+std::to_string(b.heapUsage[i])+"\",\"budget_bytes\":\""+std::to_string(b.heapBudget[i])+"\"}";
  }
  return s+"]";
}
static void finish() {
  { std::lock_guard<std::mutex> lock(mutex); stopped=true; wake.notify_all(); }
  if(monitor.joinable()) monitor.join();
  if(resources) { std::fclose(resources); resources=nullptr; }
  if(allocations) { std::fclose(allocations); allocations=nullptr; }
  if(instance) { vkDestroyInstance(instance,nullptr); instance=VK_NULL_HANDLE; }
}
static void start() {
  setup();
  resources=std::fopen(std::getenv("MEGASCENE_HEAPS"),"wx");
  allocations=std::fopen(std::getenv("MEGASCENE_ALLOCATIONS"),"wx");
  if(!resources || !allocations) throw std::runtime_error("cannot create native supervision streams");
  emit(resources,resource_seq,sample());
  emit(allocations,allocation_seq,"\"record_type\":\"ledger_start\",\"scope\":\"explicit_vkDeviceMemory_not_residency\",\"live_bytes\":\"0\",\"peak_bytes\":\"0\"");
  monitor=std::thread([] {
    std::unique_lock<std::mutex> lock(mutex);
    auto next=std::chrono::steady_clock::now();
    while(!stopped) {
      next+=std::chrono::milliseconds(100);
      if(wake.wait_until(lock,next,[]{return stopped;})) break;
      emit(resources,resource_seq,sample());
    }
  });
  std::atexit(finish);
}
static void verify(VkPhysicalDevice renderer_device) {
  if(!resources) return;
  VkPhysicalDeviceIDProperties a{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ID_PROPERTIES},b{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ID_PROPERTIES};
  VkPhysicalDeviceProperties2 p{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2};
  p.pNext=&a; vkGetPhysicalDeviceProperties2(physical,&p);
  p.pNext=&b; vkGetPhysicalDeviceProperties2(renderer_device,&p);
  if(std::memcmp(a.deviceUUID,b.deviceUUID,VK_UUID_SIZE)) throw std::runtime_error("renderer/monitor device mismatch");
}
static void event(const char* kind,const Allocation& a,int result) {
  std::string s="\"record_type\":\""+std::string(kind)+"\",\"device\":\""+pci+"\",\"scope\":\"explicit_vkDeviceMemory_not_residency\",\"allocation_id\":\""+std::to_string(a.id)+"\",\"size_bytes\":\""+std::to_string(a.size)+"\",\"memory_type\":\""+std::to_string(a.type)+"\",\"heap\":\""+std::to_string(a.heap)+"\",\"vk_result\":\""+std::to_string(result)+"\",\"live_bytes\":\""+std::to_string(live)+"\",\"peak_bytes\":\""+std::to_string(peak)+"\",\"heap_live_bytes\":\""+std::to_string(heap_live[a.heap])+"\",\"heap_peak_bytes\":\""+std::to_string(heap_peak[a.heap])+"\"";
  emit(allocations,allocation_seq,s);
}
static VkResult allocate(VkDevice device,VkPhysicalDevice gpu,const VkMemoryAllocateInfo* info,VkDeviceMemory* memory) {
  VkResult result=vkAllocateMemory(device,info,nullptr,memory);
  if(!allocations) return result;
  VkPhysicalDeviceMemoryProperties p{}; vkGetPhysicalDeviceMemoryProperties(gpu,&p);
  Allocation a{next_id++,info->allocationSize,info->memoryTypeIndex,p.memoryTypes[info->memoryTypeIndex].heapIndex};
  if(result==VK_SUCCESS) {
    live+=a.size; peak=std::max(live,peak); heap_live[a.heap]+=a.size; heap_peak[a.heap]=std::max(heap_peak[a.heap],heap_live[a.heap]); ledger.emplace(*memory,a);
  }
  event(result==VK_SUCCESS?"allocate":"allocation_failed",a,result);
  return result;
}
static void free(VkDevice device,VkDeviceMemory memory) {
  vkFreeMemory(device,memory,nullptr);
  if(!allocations) return;
  auto it=ledger.find(memory); if(it==ledger.end()) { std::fputs("allocation ledger lost identity\n",stderr); std::_Exit(74); }
  Allocation a=it->second; live-=a.size; heap_live[a.heap]-=a.size; ledger.erase(it); event("free",a,0);
}
}
