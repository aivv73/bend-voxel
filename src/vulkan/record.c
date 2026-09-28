#include <time.h>
static u64 mega_tick(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC,&now)) err_fail("monotonic clock failed");
  return (u64)now.tv_sec*1000000000ull+(u64)now.tv_nsec;
}
// Opt-in Megascene recorder. Each committed line is flushed directly into the
// durable attempt directory. This is development evidence, not the later
// shared calibration recorder or resource supervisor.
static FILE* mega_stream;
static u64 mega_sequence, mega_frame, mega_previous_end;
static u64 mega_stage_begin[32];
static u32 mega_warmup, mega_measured;
static float mega_ground;
static const char *mega_attempt, *mega_campaign, *mega_series;
static void mega_record(const char* fields) {
  if (!mega_stream) return;
  u64 now=mega_tick();
  if (fprintf(mega_stream,
      "{\"schema\":\"megascene-evidence/1\",\"campaign_id\":\"%s\",\"series_id\":\"%s\","
      "\"attempt_id\":\"%s\",\"sequence\":\"%llu\",\"clock_id\":\"linux.CLOCK_MONOTONIC\","
      "\"time_ns\":\"%llu\",\"frame\":\"%llu\",%s}\n",
      mega_campaign,mega_series,mega_attempt,(unsigned long long)mega_sequence++,
      (unsigned long long)now,(unsigned long long)mega_frame,fields)<0 || fflush(mega_stream))
    err_fail("Megascene evidence persistence failed");
}
static void mega_stage(const char* name,u64 begin,u64 end) {
  char record[512];
  snprintf(record,sizeof record,
    "\"record_type\":\"stage\",\"stage\":\"%s\",\"begin_ns\":\"%llu\",\"end_ns\":\"%llu\",\"duration_ns\":\"%llu\",\"status\":\"measured\",\"unit\":\"ns\",\"scope\":\"cpu_stage\"",
    name,(unsigned long long)begin,(unsigned long long)end,(unsigned long long)(end-begin));
  mega_record(record);
}
static const char* mega_env(const char* name) {
  const char* value=getenv(name);
  if (!value || !*value) err_fail("missing Megascene environment setting");
  return value;
}
static u32 mega_number(const char* name,u32 maximum) {
  const char* value=mega_env(name);
  char* end=NULL;
  unsigned long n=strtoul(value,&end,10);
  if (*end || n>maximum || *value<'0' || *value>'9') err_fail("invalid Megascene numeric setting");
  return (u32)n;
}
Term vulkan_mark_run(Env e, Term* f, IoWork* work) {
  io_sync();
  u32 code=(u32)f[0];
  u64 now=mega_tick();
  if (!code) {
    mega_attempt=mega_env("MEGASCENE_ATTEMPT");
    mega_campaign=mega_env("MEGASCENE_CAMPAIGN");
    mega_series=mega_env("MEGASCENE_SERIES");
    // IDs are generated UUIDs by the runner; reject text unsafe for JSON.
    const char* ids[]={mega_attempt,mega_campaign,mega_series};
    for (u32 i=0;i<3;i++) for (const char* p=ids[i];*p;p++)
      if (!((*p>='a'&&*p<='z')||(*p>='0'&&*p<='9')||*p=='-')) err_fail("invalid Megascene identity");
    mega_warmup=mega_number("MEGASCENE_WARMUP",120);
    mega_measured=mega_number("MEGASCENE_MEASURED",3600);
    mega_ground=(float)mega_number("MEGASCENE_GROUND",72);
    if (mega_stream) err_fail("Megascene recorder already open");
    mega_stream=fopen(mega_env("MEGASCENE_EVENTS"),"wx");
    if (!mega_stream) err_fail("cannot create Megascene evidence stream");
    mega_record("\"record_type\":\"worker_start\"");
  } else if (code==15) {
    mega_record("\"record_type\":\"complete\"");
    if (fclose(mega_stream)) err_fail("cannot close Megascene evidence");
    mega_stream=NULL;
  } else if (code==17) {
    mega_record("\"record_type\":\"window_closed\"");
  } else {
    static const char* stages[]={"", "generation", "initial_surfaces", "initial_inventory", "window_setup", "physics", "view", "teardown"};
    if (code>14) err_fail("invalid Megascene marker");
    if (code&1) mega_stage_begin[code]=now;
    else mega_stage(stages[code/2],mega_stage_begin[code-1],now);
  }
  return term_pak(CID_UNIT,0);
}

static void __attribute__((constructor)) mega_effects(void) {
  io_eff(CID_VULKAN_VULKAN_MARK,vulkan_mark_run,0);
}
