static uint32_t generation_fault_mode,generation_fault_count;
static Term test_generation_fault(Env e,Term* f,IoWork* w) {
  generation_fault_mode=(uint32_t)bv_u64(e,term_keep(e,f[0],1));generation_fault_count=0;
  return bv_u64_roundtrip(e,f,w);
}
static bool generation_fail(uint32_t first) {
  return generation_fault_mode>=first && generation_fault_mode<first+4 && ++generation_fault_count==generation_fault_mode-first+1;
}
static Term test_generation_create(Env e,Term* f,IoWork* w) {
  if (generation_fail(1)) {term_sink(e,f[1]);return bv_vk_error(e,VK_ERROR_OUT_OF_DEVICE_MEMORY,"controlled chunk buffer allocation");}
  return bv_create_buffer(e,f,w);
}
static Term test_generation_allocate(Env e,Term* f,IoWork* w) {
  if (generation_fail(5)) {term_sink(e,f[1]);return bv_vk_error(e,VK_ERROR_OUT_OF_DEVICE_MEMORY,"controlled chunk memory allocation");}
  return bv_allocate_memory(e,f,w);
}
static Term test_generation_write(Env e,Term* f,IoWork* w) {
  if (generation_fail(9)) {
    for (uint32_t j=2;j<5;j++) term_sink(e,f[j]);
    return io_tup(e,f[5],bv_vk_error(e,VK_ERROR_OUT_OF_DEVICE_MEMORY,"controlled chunk staging upload"));
  }
  return bv_write_memory_words(e,f,w);
}
