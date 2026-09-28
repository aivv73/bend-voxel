// Fixture recorder sink. Actual action formatting and Bend edit execution use
// production code. This fixture has no window, GPU, or performance claim.
static FILE* mega_stream;
static const char *mega_attempt,*mega_campaign,*mega_series;
static u64 mega_frame;
static void* mega_reference_memory;
static int mega_edit_pending;
static char mega_action_outcomes[4096];
Term test_record_start_run(Env e,Term* f,IoWork* work) {
  io_sync();
  mega_stream=stdout; mega_attempt=mega_campaign=mega_series="fixture";
  mega_frame=121;
  mega_reference_memory=calloc(1,32+64*1024);
  uint64_t* header=(uint64_t*)mega_reference_memory;
  header[0]=0x4d45474152454631ull; header[1]=64;
  return term_pak(CID_UNIT,0);
}
Term test_record_end_run(Env e,Term* f,IoWork* work) {
  io_sync();
  printf("{\"record_type\":\"history\",\"action_outcomes\":%s}\n",mega_action_outcomes);
  mega_edit_pending=0; mega_frame++;
  return term_pak(CID_UNIT,0);
}
static void __attribute__((constructor)) test_record_effects(void) {
  io_eff(CID_TEST_RECORD_START,test_record_start_run,0);
  io_eff(CID_TEST_RECORD_END,test_record_end_run,0);
}
