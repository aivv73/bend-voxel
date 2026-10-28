#include <assert.h>
static uint32_t scene_fault_mode,scene_copy_count,scene_reset_count;
static Term test_scene_fault(Env e,Term* f,IoWork* w) {
  scene_fault_mode=(uint32_t)bv_u64(e,term_keep(e,f[0],1));scene_copy_count=0;scene_reset_count=0;
  return bv_u64_roundtrip(e,f,w);
}
static VKAPI_ATTR VkResult VKAPI_CALL test_scene_begin_oom(VkCommandBuffer c,const VkCommandBufferBeginInfo* i) {return VK_ERROR_OUT_OF_HOST_MEMORY;}
static Term test_scene_begin(Env e,Term* f,IoWork* w) {
  if (scene_fault_mode!=1) return bv_begin_command_buffer(e,f,w);
  scene_fault_mode=0;
  BvRow* command=bv_get(bv_key(e,term_keep(e,f[0],1)),BV_COMMAND);assert(command);
  BvDevice* device=bv_command_device(command)->context;PFN_vkBeginCommandBuffer saved=device->BeginCommandBuffer;
  device->BeginCommandBuffer=test_scene_begin_oom;
  Term result=bv_begin_command_buffer(e,f,w);device->BeginCommandBuffer=saved;return result;
}
static Term test_scene_copy(Env e,Term* f,IoWork* w) {
  if (scene_fault_mode==2 && ++scene_copy_count==2) {
    scene_fault_mode=0;term_sink(e,f[3]);return io_fail(e,BV_LIMIT,"controlled mid-copy metadata failure");
  }
  return bv_cmd_copy_buffer(e,f,w);
}

static VKAPI_ATTR VkResult VKAPI_CALL test_scene_reset_error(VkCommandBuffer c,VkCommandBufferResetFlags f) {
  return scene_fault_mode==4 ? VK_ERROR_DEVICE_LOST : VK_ERROR_OUT_OF_HOST_MEMORY;
}
static Term test_scene_reset(Env e,Term* f,IoWork* w) {
  if(scene_fault_mode<3 || scene_fault_mode>4 || ++scene_reset_count<2) return bv_reset_command_buffer(e,f,w);
  BvRow* command=bv_get(bv_key(e,term_keep(e,f[0],1)),BV_COMMAND);assert(command);
  BvDevice* device=bv_command_device(command)->context;PFN_vkResetCommandBuffer saved=device->ResetCommandBuffer;
  device->ResetCommandBuffer=test_scene_reset_error;
  Term result=bv_reset_command_buffer(e,f,w);device->ResetCommandBuffer=saved;return result;
}
