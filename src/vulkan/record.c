#include <time.h>
#include <dlfcn.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
// Shared append-only recorder ABI v1. Linux, lock-free aligned 64-bit atomics.
// Slots are never reused: a killed producer cannot erase a committed record.
#ifndef MEGASCENE_REFERENCE_H
#define MEGASCENE_REFERENCE_H
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#if __GCC_ATOMIC_LLONG_LOCK_FREE != 2
#error Megascene requires lock-free 64-bit shared atomics
#endif
#define MEGA_REFERENCE_MAGIC 0x4d45474152454631ull
#define MEGA_REFERENCE_SLOT 1024
struct MegaReferenceHeader { uint64_t magic, capacity, written, overflow; };
struct MegaReferenceSlot { uint64_t committed; char payload[MEGA_REFERENCE_SLOT-8]; };
static inline int mega_reference_commit(void* memory, const char* payload, size_t size) {
  struct MegaReferenceHeader* h=(struct MegaReferenceHeader*)memory;
  uint64_t n=__atomic_load_n(&h->written,__ATOMIC_RELAXED);
  if (h->magic!=MEGA_REFERENCE_MAGIC || n>=h->capacity || size>=MEGA_REFERENCE_SLOT-8) {
    __atomic_store_n(&h->overflow,1,__ATOMIC_RELEASE); return 0;
  }
  struct MegaReferenceSlot* slot=(struct MegaReferenceSlot*)(h+1)+n;
  memcpy(slot->payload,payload,size); slot->payload[size]=0;
  __atomic_store_n(&slot->committed,n+1,__ATOMIC_RELEASE);
  __atomic_store_n(&h->written,n+1,__ATOMIC_RELEASE);
  return 1;
}
#endif

#ifndef MEGA_REFERENCE_ONLY
static u64 mega_tick(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC,&now)) err_fail("monotonic clock failed");
  return (u64)now.tv_sec*1000000000ull+(u64)now.tv_nsec;
}
// Detailed events stream directly to the archive. The minimal reference path
// commits to supervisor-owned preallocated shared memory before ordinary logging.
static FILE* mega_stream;
static u64 mega_sequence, mega_frame, mega_previous_end;
static u64 mega_stage_begin[32];
static u32 mega_warmup, mega_measured;
static float mega_ground;
static const char *mega_attempt, *mega_campaign, *mega_series;
static void* mega_reference_memory;
static u64 mega_reference_sequence;
static u64 mega_edit_begin;
static u32 mega_edit_action,mega_edit_removed,mega_edit_status;
static int mega_edit_pending;
static char mega_action_outcomes[65536]="[]";
static void mega_reference(const char* fields) {
  char record[MEGA_REFERENCE_SLOT-8];
  int n=snprintf(record,sizeof record,
    "{\"schema\":\"megascene-evidence/1\",\"campaign_id\":\"%s\",\"series_id\":\"%s\",\"attempt_id\":\"%s\",\"sequence\":\"%llu\",\"clock_id\":\"linux.CLOCK_MONOTONIC\",\"time_ns\":\"%llu\",\"frame\":\"%llu\",%s}\n",
    mega_campaign,mega_series,mega_attempt,(unsigned long long)mega_reference_sequence++,
    (unsigned long long)mega_tick(),(unsigned long long)mega_frame,fields);
  if(n<0 || n>=(int)sizeof record || !mega_reference_commit(mega_reference_memory,record,(size_t)n))
    err_fail("Megascene reference overflow");
}
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

#ifdef CID_VULKAN_VULKAN_ROUTE
static u32* mega_route;
static u32 mega_route_count;
Term vulkan_route_run(Env e, Term* f, IoWork* work) {
  io_sync();
  if (!mega_stream) err_fail("route requested outside Megascene replay");
  if (!mega_route) {
    FILE* input=fopen(mega_env("MEGASCENE_CAMERA_FILE"),"rb");
    if (!input || fseek(input,0,SEEK_END)) err_fail("frozen camera input unavailable");
    long size=ftell(input);
    mega_route_count=1+mega_warmup+mega_measured;
    if (size!=(long)mega_route_count*20 || fseek(input,0,SEEK_SET)) err_fail("frozen camera count mismatch");
    mega_route=io_mem(malloc((size_t)size));
    if (fread(mega_route,1,(size_t)size,input)!=(size_t)size || fclose(input))
      err_fail("incomplete frozen camera input");
  }
  u32 index=(u32)f[0];
  if (index>=mega_route_count || index!=mega_frame) err_fail("frozen camera frame mismatch");
  u32* words=mega_route+5*index;
  for (u32 i=0;i<5;i++) {
    float value;
    memcpy(&value,words+i,4);
    if (!isfinite(value)) err_fail("nonfinite frozen camera");
  }
  if (cid_arity(CID_RENDER_CAMERA)!=7) err_fail("Bend camera layout changed");
  u64 camera=heap_alloc(e,cls_fit(7));
  for (u32 i=0;i<5;i++) e.mem[camera+i]=words[i];
  e.mem[camera+5]=f[1]; e.mem[camera+6]=f[2];
  return term_ctr(CID_RENDER_CAMERA,camera);
}
#endif
#ifdef CID_VULKAN_VULKAN_PICKRAY
static u32* mega_rays;
Term vulkan_pickray_run(Env e, Term* f, IoWork* work) {
  io_sync();
  if(!mega_stream || (u32)f[0]!=mega_frame) err_fail("picking frame mismatch");
  u32 count=1+mega_warmup+mega_measured;
  if(!mega_rays) {
    FILE* input=fopen(mega_env("MEGASCENE_RAY_FILE"),"rb");
    if(!input) err_fail("frozen rays unavailable");
    mega_rays=io_mem(malloc((size_t)count*28));
    if(fread(mega_rays,28,count,input)!=count || fgetc(input)!=EOF || fclose(input)) err_fail("frozen ray count mismatch");
  }
  if((u32)f[0]>=count || cid_arity(CID_MEGASCENE_PICKING_RAY)!=7) err_fail("picking input layout mismatch");
  u32* words=mega_rays+7*(u32)f[0];
  if(words[0]>1) err_fail("invalid picking enable bit");
  u64 ray=heap_alloc(e,cls_fit(7));
  for(u32 i=0;i<7;i++) e.mem[ray+i]=words[i];
  return term_ctr(CID_MEGASCENE_PICKING_RAY,ray);
}
Term vulkan_pickrecord_run(Env e, Term* f, IoWork* work) {
  io_sync();
  if(!mega_stream || cid_arity(CID_RENDER_HIT)!=7) err_fail("picking recorder unavailable");
  u64 ray=term_peek(e.mem,f[0]), hit=term_peek(e.mem,f[1]);
  char ray_json[256],record[1024];
  if(e.mem[ray]) snprintf(ray_json,sizeof ray_json,
    "{\"origin_m\":[\"0x%08x\",\"0x%08x\",\"0x%08x\"],\"direction\":[\"0x%08x\",\"0x%08x\",\"0x%08x\"]}",
    (u32)e.mem[ray+1],(u32)e.mem[ray+2],(u32)e.mem[ray+3],(u32)e.mem[ray+4],(u32)e.mem[ray+5],(u32)e.mem[ray+6]);
  else strcpy(ray_json,"null");
  snprintf(record,sizeof record,
    "\"record_type\":\"picking\",\"enabled\":%s,\"ray\":%s,\"result\":{\"owner\":\"%u\",\"material\":\"%u\",\"kind\":\"%u\",\"distance_m\":\"0x%08x\",\"position_m\":[\"0x%08x\",\"0x%08x\",\"0x%08x\"]}",
    e.mem[ray]?"true":"false",ray_json,(u32)e.mem[hit+5],(u32)e.mem[hit+6],(u32)e.mem[hit+4],
    (u32)e.mem[hit+3],(u32)e.mem[hit],(u32)e.mem[hit+1],(u32)e.mem[hit+2]);
  mega_record(record);
  term_sink(e,f[0]); term_sink(e,f[1]);
  return term_pak(CID_UNIT,0);
}
#endif
#ifdef CID_VULKAN_VULKAN_EDITBEGIN
Term vulkan_editbegin_run(Env e, Term* f, IoWork* work) {
  io_sync();
  if(!mega_stream || mega_edit_pending) err_fail("invalid edit start");
  mega_edit_begin=mega_tick(); mega_edit_action=(u32)f[0]; mega_edit_pending=1;
  char record[256];
  snprintf(record,sizeof record,"\"record_type\":\"edit_begin\",\"action\":\"%u\",\"begin_ns\":\"%llu\"",mega_edit_action,(unsigned long long)mega_edit_begin);
  mega_reference(record); mega_record(record); term_sink(e,f[1]);
  return term_pak(CID_UNIT,0);
}
Term vulkan_editrecord_run(Env e, Term* f, IoWork* work) {
  io_sync();
  if(!mega_stream || !mega_edit_pending || (u32)f[1]!=mega_edit_action) err_fail("invalid edit outcome");
  u64 world=term_peek(e.mem,f[0]),point=term_peek(e.mem,f[2]);
  mega_edit_removed=(u32)e.mem[world+3]; mega_edit_status=(u32)e.mem[world+4];
  if(mega_edit_status<1||mega_edit_status>3||(mega_edit_status!=1&&mega_edit_removed)) err_fail("invalid edit status/removal");
  const char* accepted=mega_edit_status==1&&mega_edit_removed?"true":"false";
  const char* outcome=mega_edit_status==3?"rejected_budget":mega_edit_removed?"accepted":"no_op";
  char action[512],record[768];
  snprintf(action,sizeof action,"{\"accepted\":%s,\"action\":\"%u\",\"frame\":\"%llu\",\"outcome\":\"%s\",\"removed_cells\":\"%u\",\"target_m\":[\"0x%08x\",\"0x%08x\",\"0x%08x\"]}",
    accepted,mega_edit_action,(unsigned long long)mega_frame,outcome,mega_edit_removed,(u32)e.mem[point],(u32)e.mem[point+1],(u32)e.mem[point+2]);
  size_t length=strlen(mega_action_outcomes),extra=strlen(action);
  if(length+extra+2>=sizeof mega_action_outcomes) err_fail("action history capacity exceeded");
  snprintf(mega_action_outcomes+length-1,sizeof mega_action_outcomes-length+1,"%s%s]",length>2?",":"",action);
  snprintf(record,sizeof record,"\"record_type\":\"action\",\"action\":\"%u\",\"accepted\":%s,\"removed_cells\":\"%u\",\"outcome\":%s",mega_edit_action,accepted,mega_edit_removed,action);
  mega_reference(record); mega_record(record);
  term_sink(e,f[0]); term_sink(e,f[2]);
  return term_pak(CID_UNIT,0);
}
#endif
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
    int fd=open(mega_env("MEGASCENE_REFERENCE"),O_RDWR);
    struct stat st;
    if(fd<0 || fstat(fd,&st) || st.st_size<32) err_fail("shared reference recorder unavailable");
    mega_reference_memory=mmap(NULL,(size_t)st.st_size,PROT_READ|PROT_WRITE,MAP_SHARED,fd,0);
    close(fd);
    if(mega_reference_memory==MAP_FAILED) err_fail("shared reference mapping failed");
    struct MegaReferenceHeader* h=(struct MegaReferenceHeader*)mega_reference_memory;
    if(h->magic!=MEGA_REFERENCE_MAGIC || h->capacity!=(st.st_size-32)/MEGA_REFERENCE_SLOT || h->written || h->overflow)
      err_fail("invalid shared reference capacity/state");
    const char* lib=mega_env("VOXEL_VULKAN_LIBRARY");
    void* native=dlopen(lib,RTLD_NOW|RTLD_LOCAL);
    int (*start)(char*,size_t)=native?(int (*)(char*,size_t))dlsym(native,"voxel_mega_start"):NULL;
    char error[512];
    if(!start) err_fail("native supervision unavailable");
    if(!start(error,sizeof error)) err_fail(error);
    // Supervisor checks process-attributed heap samples before allowing work.
    while(access(mega_env("MEGASCENE_GO"),F_OK)) usleep(1000);
    mega_record("\"record_type\":\"worker_start\"");
  } else if (code==15) {
    mega_record("\"record_type\":\"complete\"");
    if (fclose(mega_stream)) err_fail("cannot close Megascene evidence");
    mega_stream=NULL;
  } else if (code==17) {
    mega_record("\"record_type\":\"window_closed\"");
  } else if(code>=19 && code<=26) {
    static const char* stages[]={"carve","connectivity","surfaces","commit"};
    if(code&1) mega_stage_begin[code]=now;
    else mega_stage(stages[(code-20)/2],mega_stage_begin[code-1],now);
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
#ifdef CID_VULKAN_VULKAN_EDITBEGIN
  io_eff(CID_VULKAN_VULKAN_EDITBEGIN,vulkan_editbegin_run,0);
  io_eff(CID_VULKAN_VULKAN_EDITRECORD,vulkan_editrecord_run,0);
#endif
#ifdef CID_VULKAN_VULKAN_PICKRAY
  io_eff(CID_VULKAN_VULKAN_PICKRAY,vulkan_pickray_run,0);
  io_eff(CID_VULKAN_VULKAN_PICKRECORD,vulkan_pickrecord_run,0);
#endif
#ifdef CID_VULKAN_VULKAN_ROUTE
  io_eff(CID_VULKAN_VULKAN_ROUTE,vulkan_route_run,0);
#endif
}

#endif // MEGA_REFERENCE_ONLY
