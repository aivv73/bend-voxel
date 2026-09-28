// Exercise real ledger wrappers with deterministic driver responses. No Vulkan
// allocation or real exhaustion occurs; expected records are checked in Python.
#include "../src/vulkan/native.cpp"
static VkResult injected_result=VK_SUCCESS;
static uintptr_t next_handle=1;
extern "C" VkResult __wrap_vkAllocateMemory(VkDevice,const VkMemoryAllocateInfo*,const VkAllocationCallbacks*,VkDeviceMemory* memory) {
  if(injected_result==VK_SUCCESS) *memory=reinterpret_cast<VkDeviceMemory>(next_handle++);
  return injected_result;
}
extern "C" void __wrap_vkFreeMemory(VkDevice,VkDeviceMemory,const VkAllocationCallbacks*) {}
extern "C" void __wrap_vkGetPhysicalDeviceMemoryProperties(VkPhysicalDevice,VkPhysicalDeviceMemoryProperties* p) {
  *p={}; p->memoryTypeCount=3; p->memoryHeapCount=2;
  p->memoryTypes[2].heapIndex=1;
}
int main(int argc,char** argv) {
  if(argc!=2) return 2;
  setenv("MEGASCENE_CAMPAIGN","fixture",1); setenv("MEGASCENE_SERIES","fixture",1); setenv("MEGASCENE_ATTEMPT","fixture",1);
  supervision::allocations=std::fopen(argv[1],"wx");
  if(!supervision::allocations) return 3;
  supervision::pci="fixture";
  supervision::emit(supervision::allocations,supervision::allocation_seq,
    "\"record_type\":\"ledger_start\",\"live_bytes\":\"0\",\"peak_bytes\":\"0\"");
  VkMemoryAllocateInfo info{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO}; info.allocationSize=4096; info.memoryTypeIndex=2;
  VkDeviceMemory a{},b{},failed{};
  supervision::allocate({}, {}, &info, &a);
  info.allocationSize=8192; info.memoryTypeIndex=0;
  supervision::allocate({}, {}, &info, &b);
  supervision::free({},a);
  injected_result=VK_ERROR_OUT_OF_DEVICE_MEMORY;
  info.allocationSize=16384;
  if(supervision::allocate({}, {}, &info, &failed)!=VK_ERROR_OUT_OF_DEVICE_MEMORY) return 4;
  supervision::free({},b);
  try { check(VK_ERROR_DEVICE_LOST,"fixture device loss"); } catch(const std::exception&) {}
  std::fclose(supervision::allocations); supervision::allocations=nullptr;
  return 0;
}
