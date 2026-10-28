static Term test_timing_reset(Env e,Term* f,IoWork* w) {
  static unsigned calls;
  if (++calls!=2) return bv_reset_timestamp_queries(e,f,w);
  BvRow* command=bv_get(bv_key(e,term_keep(e,f[0],1)),BV_COMMAND);
  BvRow* pool=bv_get(bv_key(e,term_keep(e,f[1],1)),BV_QUERY_POOL);
  assert(command && pool && command->command.phase==BV_RECORDING);
  BvQuerySlot old[6];memcpy(old,pool->object.queries.slots,sizeof(old));
  assert(old[0].ready && old[1].ready && old[0].generation!=command->command.generation);
  bv_test_alloc_at=0;bv_test_alloc_fail=1;
  Term result=bv_reset_timestamp_queries(e,f,w);bv_test_alloc_fail=0;
  assert(term_aux(result)==CID(Fail));
  assert(!memcmp(old,pool->object.queries.slots,sizeof(old)) && !command->deps);
  puts("Actual query reset recorded-ref allocation failed with old completed data retained");
  return result;
}
