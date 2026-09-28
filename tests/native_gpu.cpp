// Controlled driver responses through the production query/evidence boundary.
#include "../src/vulkan/native.cpp"
static std::string mode;
static unsigned reads=0,writes=0,resets=0;
extern "C" VkResult __wrap_vkCreateQueryPool(VkDevice,const VkQueryPoolCreateInfo* info,const VkAllocationCallbacks*,VkQueryPool* pool) {
  if(info->queryType!=VK_QUERY_TYPE_TIMESTAMP||info->queryCount!=4) std::abort();
  *pool=reinterpret_cast<VkQueryPool>(1);
  return mode=="create_failure"?VK_ERROR_OUT_OF_HOST_MEMORY:VK_SUCCESS;
}
extern "C" void __wrap_vkDestroyQueryPool(VkDevice,VkQueryPool,const VkAllocationCallbacks*) {}
extern "C" void __wrap_vkCmdResetQueryPool(VkCommandBuffer,VkQueryPool,uint32_t first,uint32_t count) {
  if(first!=resets++*2||count!=2) std::abort();
}
extern "C" void __wrap_vkCmdWriteTimestamp(VkCommandBuffer,VkPipelineStageFlagBits stage,VkQueryPool,uint32_t query) {
  if(query!=writes || stage!=(writes%2?VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT:VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT)) std::abort();
  writes++;
}
extern "C" VkResult __wrap_vkGetQueryPoolResults(VkDevice,VkQueryPool,uint32_t first,uint32_t count,size_t size,void* output,VkDeviceSize stride,VkQueryResultFlags flags) {
  if(count!=2||size!=32||stride!=16||flags!=(VK_QUERY_RESULT_64_BIT|VK_QUERY_RESULT_WITH_AVAILABILITY_BIT)) std::abort();
  auto* data=static_cast<uint64_t*>(output);
  reads++;
  data[0]=mode=="wrapped"?250:10; data[1]=1;
  data[2]=mode=="wrapped"?4:mode=="zero"?10:20; data[3]=1;
  if(mode=="wide") { data[0]=UINT64_MAX-5; data[2]=3; }
  if(mode=="high_bits") data[0]=1ull<<40;
  if(mode=="delayed"&&reads==1) { data[3]=0; return VK_NOT_READY; }
  if(mode=="missing_tail"&&first==2) { data[1]=data[3]=0; return VK_NOT_READY; }
  return mode=="collection_failure"?VK_ERROR_DEVICE_LOST:VK_SUCCESS;
}
int main(int argc,char** argv) {
  if(argc!=3) return 2;
  mode=argv[2];
  setenv("MEGASCENE_GPU",argv[1],1);
  setenv("MEGASCENE_CAMPAIGN","fixture",1); setenv("MEGASCENE_SERIES","fixture",1); setenv("MEGASCENE_ATTEMPT","fixture",1);
  gpu_timing::Queries queries;
  uint32_t bits=mode=="unsupported"?0:mode=="wrapped"||mode=="ambiguous"?8:mode=="wide"?64:32;
  float period=mode=="fractional"?0.5f:1.f;
  queries.start({},3,period,bits,2,mode!="disabled");
  uint64_t now=supervision::tick(),begin=now-1000;
  queries.begin({}); queries.end({}); queries.submitted(0,begin);
  queries.collect(1,false,VK_SUCCESS,mode=="invalid_cpu"?begin-1:mode=="ambiguous"?now:begin+100);
  queries.begin({}); queries.end({}); queries.submitted(1,begin+10);
  queries.finish(mode=="sync_failure"?VK_ERROR_DEVICE_LOST:VK_SUCCESS,begin+110);
  return 0;
}
