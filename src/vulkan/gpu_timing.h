// Static-run timestamp evidence. Native/driver behavior is runtime-tested.
#pragma once

namespace gpu_timing {
static uint32_t environment_number(const char* name,uint32_t fallback,uint32_t maximum) {
  const char* s=std::getenv(name);
  if(!s) return fallback;
  uint32_t n=0;
  if(!*s) throw std::runtime_error("empty performance numeric setting");
  for(;*s;s++) {
    if(*s<'0'||*s>'9'||n>(maximum-uint32_t(*s-'0'))/10)
      throw std::runtime_error("invalid performance numeric setting");
    n=n*10+uint32_t(*s-'0');
    if(n>maximum) throw std::runtime_error("performance numeric setting exceeds bound");
  }
  return n;
}
static uint32_t query_pairs() {
  bool performance=std::getenv("MEGASCENE_FRAME_POLICY")!=nullptr;
  uint32_t count=environment_number("MEGASCENE_QUERY_PAIRS",performance?0:3721,performance?21721:3721);
  if(!count || (performance && count!=21721)) throw std::runtime_error("GPU query capacity differs from protocol");
  return count;
}
constexpr const char* scope="submitted_frame_top_to_bottom";
struct Resolution {
  const char *status="collection_failure", *reason="invalid timestamp metadata", *range="invalid";
  uint64_t ticks=0;
  double ns=0;
};
static Resolution resolve(uint64_t start,uint64_t end,float period,uint32_t bits,
                          uint64_t submit,uint64_t completed) {
  Resolution r;
  if(!std::isfinite(period)||period<=0||!bits||bits>64) return r;
  if(completed<submit) { r.reason="invalid CPU bounding interval"; r.range="invalid_cpu_interval"; return r; }
  const uint64_t mask=bits==64?UINT64_MAX:(uint64_t(1)<<bits)-1;
  if((start&~mask)||(end&~mask)) { r.reason="ticks exceed valid bits"; r.range="out_of_range"; return r; }
  const long double bound=completed-submit, wrap=std::ldexp((long double)period,bits);
  if(bound>=wrap) { r.reason="CPU bound permits multiple timestamp wraps"; r.range="ambiguous_wrap"; return r; }
  r.ticks=(end-start)&mask;
  const long double ns=(long double)r.ticks*period;
  // One tick allows endpoint quantization; clocks are not correlated or summed.
  if(ns>bound+period || ns>UINT64_MAX) {
    r.reason="GPU interval exceeds CPU bound or nanosecond range"; r.range="out_of_range"; return r;
  }
  r.ns=double(ns); r.status="measured"; r.reason="available bounded timestamp pair";
  r.range=end<start?"single_wrap":"valid";
  return r;
}
static std::string quoted(uint64_t n) { return "\""+std::to_string(n)+"\""; }
static std::string number(double n) {
  char s[64]; std::snprintf(s,sizeof s,"%.17g",n); return s;
}
struct Submission {
  uint64_t id,frame,begin,completed=0;
  bool completion_known=false;
};
class Queries {
  FILE* stream=nullptr;
  uint64_t sequence=0,next=0;
  VkDevice device=VK_NULL_HANDLE;
  VkQueryPool pool=VK_NULL_HANDLE;
  uint32_t bits=0,capacity=0;
  float period=0;
  std::string metadata,status,reason;
  std::vector<Submission> pending;
  void emit(const std::string& fields) { supervision::emit(stream,sequence,fields); }
  void interval(const Submission& s,const char* state,const char* why,const char* range,
                uint64_t collection_frame,bool teardown,VkResult code,const uint64_t* data=nullptr,
                const Resolution* resolved=nullptr) {
    std::string fields="\"record_type\":\"gpu_interval\",\"submission\":"+quoted(s.id)+",\"frame\":"+quoted(s.frame)+
      ",\"collection_frame\":"+(teardown?"null":quoted(collection_frame))+",\"collection_phase\":\""+(teardown?"teardown":"frame")+
      "\",\"submit_begin_ns\":"+quoted(s.begin)+",\"completion_ns\":"+(s.completion_known?quoted(s.completed):"null")+
      ",\"status\":\""+state+"\",\"reason\":\""+why+"\",\"range_status\":\""+range+"\",\"unit\":\"ns\","+metadata+
      ",\"vk_result\":\""+std::to_string(code)+"\",\"availability\":"+(data?"["+quoted(data[1])+","+quoted(data[3])+"]":"null")+
      ",\"raw_ticks\":"+(data?"["+(data[1]?quoted(data[0]):"null")+","+(data[3]?quoted(data[2]):"null")+"]":"null")+
      ",\"duration_ticks\":"+(resolved&&std::string(state)=="measured"?quoted(resolved->ticks):"null")+
      ",\"value\":"+(resolved&&std::string(state)=="measured"?number(resolved->ns):"null");
    emit(fields);
  }
public:
  bool active() const { return stream!=nullptr; }
  void start(VkDevice d,uint32_t family,float p,uint32_t valid_bits,uint32_t count,bool enabled=true) {
    device=d; bits=valid_bits; period=p; capacity=count;
    const char* path=std::getenv("MEGASCENE_GPU");
    if(!path || !(stream=std::fopen(path,"wx"))) throw std::runtime_error("cannot create GPU evidence stream");
    uint32_t raw_period; std::memcpy(&raw_period,&p,4);
    char encoded[16]; std::snprintf(encoded,sizeof encoded,"0x%08x",raw_period);
    metadata="\"scope\":\""+std::string(scope)+"\",\"period_ns\":"+(std::isfinite(p)?number(p):"null")+
      ",\"period_bits\":\""+encoded+"\",\"valid_bits\":"+quoted(bits);
    status=enabled?(bits?"measured":"unsupported"):"disabled";
    reason=enabled?(bits?"queue supports timestamp queries":"queue reports zero timestamp valid bits"):"timestamp collection deliberately disabled";
    if(enabled&&bits) {
      if(bits>64||!std::isfinite(p)||p<=0||!count||count>21721) {
        status="collection_failure"; reason="invalid timestamp capability or query capacity";
      } else {
        VkQueryPoolCreateInfo info{VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO};
        info.queryType=VK_QUERY_TYPE_TIMESTAMP; info.queryCount=count*2;
        VkResult result=vkCreateQueryPool(device,&info,nullptr,&pool);
        if(result!=VK_SUCCESS) {
          record_vk_failure(result,"create GPU timestamp query pool");
          pool=VK_NULL_HANDLE; status="collection_failure"; reason="query pool creation failed: "+std::to_string(result);
        }
      }
    }
    emit("\"record_type\":\"gpu_capability\",\"status\":\""+status+"\",\"reason\":\""+reason+"\","+metadata+
      ",\"queue_family\":"+quoted(family)+",\"query_capacity\":"+quoted(capacity)+
      ",\"begin_stage\":\"TOP_OF_PIPE\",\"end_stage\":\"BOTTOM_OF_PIPE\",\"collection\":\"after existing fence or teardown idle; no query wait\"");
  }
  void begin(VkCommandBuffer command) {
    if(!pool) return;
    if(next>=capacity) throw std::runtime_error("GPU query capacity exceeded");
    vkCmdResetQueryPool(command,pool,uint32_t(next*2),2);
    vkCmdWriteTimestamp(command,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,pool,uint32_t(next*2));
  }
  void end(VkCommandBuffer command) {
    if(pool) vkCmdWriteTimestamp(command,VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,pool,uint32_t(next*2+1));
  }
  void submitted(uint64_t frame,uint64_t begin) {
    if(!active()) return;
    Submission s{next++,frame,begin};
    emit("\"record_type\":\"gpu_submission\",\"submission\":"+quoted(s.id)+",\"frame\":"+quoted(frame)+
         ",\"submit_begin_ns\":"+quoted(begin)+","+metadata);
    if(pool) pending.push_back(s);
    else interval(s,status.c_str(),reason.c_str(),"unavailable",frame,false,VK_SUCCESS);
  }
  void collect(uint64_t frame,bool teardown,VkResult sync,uint64_t completed) {
    for(auto it=pending.begin();it!=pending.end();) {
      auto& s=*it;
      if(sync!=VK_SUCCESS) {
        interval(s,"collection_failure","existing synchronization failed","unavailable",frame,teardown,sync);
        it=pending.erase(it); continue;
      }
      if(!s.completion_known) { s.completed=completed; s.completion_known=true; }
      uint64_t data[4]{};
      VkResult result=vkGetQueryPoolResults(device,pool,uint32_t(s.id*2),2,sizeof data,data,2*sizeof(uint64_t),
        VK_QUERY_RESULT_64_BIT|VK_QUERY_RESULT_WITH_AVAILABILITY_BIT);
      if(result!=VK_SUCCESS&&result!=VK_NOT_READY) {
        record_vk_failure(result,"collect GPU timestamp queries");
        interval(s,"collection_failure","query collection failed","unavailable",frame,teardown,result);
      } else if(!data[1]||!data[3]||result==VK_NOT_READY) {
        interval(s,teardown?"incomplete":"not_ready",teardown?"missing final timestamp pair":"timestamp pair not yet available",
                 "unavailable",frame,teardown,result,data);
        if(!teardown) { ++it; continue; }
      } else {
        auto r=resolve(data[0],data[2],period,bits,s.begin,s.completed);
        interval(s,r.status,r.reason,r.range,frame,teardown,result,data,&r);
      }
      it=pending.erase(it);
    }
  }
  void finish(VkResult idle,uint64_t completed) {
    if(!active()) return;
    collect(0,true,idle,completed);
    emit("\"record_type\":\"gpu_complete\",\"submissions\":"+quoted(next));
    if(pool) vkDestroyQueryPool(device,pool,nullptr);
    pool=VK_NULL_HANDLE;
    if(std::fclose(stream)) { std::fputs("GPU evidence close failed\n",stderr); std::_Exit(74); }
    stream=nullptr;
  }
};
} // namespace gpu_timing
