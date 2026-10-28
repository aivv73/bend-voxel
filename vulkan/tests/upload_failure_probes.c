static uint32_t upload_fault_mode,upload_fault_count;
static Term test_upload_fault(Env e,Term* f,IoWork* w) {
  upload_fault_mode=(uint32_t)bv_u64(e,term_keep(e,f[0],1));upload_fault_count=0;
  return bv_u64_roundtrip(e,f,w);
}
static bool upload_fail(uint32_t first) {
  return upload_fault_mode>=first && upload_fault_mode<first+2 && ++upload_fault_count==upload_fault_mode-first+1;
}
static Term test_upload_create(Env e,Term* f,IoWork* w) {
  if (upload_fail(1)) {term_sink(e,f[1]);return bv_vk_error(e,VK_ERROR_OUT_OF_DEVICE_MEMORY,"controlled geometry buffer allocation");}
  return bv_create_buffer(e,f,w);
}
static Term test_upload_allocate(Env e,Term* f,IoWork* w) {
  if (upload_fail(3)) {term_sink(e,f[1]);return bv_vk_error(e,VK_ERROR_OUT_OF_DEVICE_MEMORY,"controlled geometry memory allocation");}
  return bv_allocate_memory(e,f,w);
}
static Term test_upload_write(Env e,Term* f,IoWork* w) {
  if (upload_fail(5)) {
    for (uint32_t j=2;j<5;j++) term_sink(e,f[j]);
    return io_tup(e,f[5],bv_vk_error(e,VK_ERROR_OUT_OF_DEVICE_MEMORY,"controlled geometry mapped upload"));
  }
  return bv_write_memory_words(e,f,w);
}
