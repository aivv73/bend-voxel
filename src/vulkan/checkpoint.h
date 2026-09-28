#pragma once
// Runtime checks over actual Bend/native data. None of this is a formal proof.
#include <openssl/sha.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>
#include <set>
#include <sstream>
#include <limits>
namespace checkpoint {
using J = std::string;
using Object = std::map<std::string,J>;
void require(bool yes,const std::string& why) { if(!yes) throw std::runtime_error(why); }
J quote(const std::string& s) {
  require(!s.empty() && s.find_first_not_of("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./:+-")==std::string::npos,"checkpoint string vocabulary");
  return "\""+s+"\"";
}
J number(int64_t n) { return quote(std::to_string(n)); }
J real(float n) {
  require(std::isfinite(n),"nonfinite checkpoint value");
  uint32_t bits; std::memcpy(&bits,&n,4); char s[11]; std::snprintf(s,sizeof s,"0x%08x",bits); return quote(s);
}
J array(const std::vector<J>& values) {
  J s="["; for(const auto& v:values) { if(s.size()>1) s+=","; s+=v; } return s+"]";
}
J object(const Object& values) {
  J s="{"; for(const auto& [k,v]:values) { if(s.size()>1) s+=","; s+=quote(k)+":"+v; } return s+"}";
}
std::string hash(const std::string& s) {
  unsigned char out[SHA256_DIGEST_LENGTH]; SHA256((const unsigned char*)s.data(),s.size(),out);
  char hex[65]; for(unsigned i=0;i<32;i++) std::snprintf(hex+2*i,3,"%02x",out[i]); return hex;
}
int64_t cell(float x) {
  require(std::isfinite(x)&&std::floor(x)==x&&std::abs(x)<=8388608,"invalid integral cell coordinate"); return int64_t(x);
}
struct Box { std::array<int64_t,3> lo,hi; uint32_t material; };
struct Rect { int64_t x0,x1,y0,y1; uint32_t material; };
struct Strip { int64_t lo,hi; J content; };
J strips(const std::vector<Strip>& xs) {
  std::vector<J> out; for(const auto& x:xs) out.push_back(array({number(x.lo),number(x.hi),x.content})); return array(out);
}
void append(std::vector<Strip>& xs,int64_t lo,int64_t hi,const J& content) {
  if(content=="[]") return;
  if(!xs.empty()&&xs.back().hi==lo&&xs.back().content==content) xs.back().hi=hi;
  else xs.push_back({lo,hi,content});
}
// Exact endpoint sweeps, independent of production recursive face subtraction.
J plane(const std::vector<Rect>& front,const std::vector<Rect>& back={}) {
  std::set<int64_t> boundaries;
  for(const auto* group:{&front,&back}) for(const auto& r:*group) {
    require(r.x0<r.x1&&r.y0<r.y1,"empty drawable rectangle"); boundaries.insert(r.x0); boundaries.insert(r.x1);
  }
  std::vector<int64_t> xs(boundaries.begin(),boundaries.end()); std::vector<Strip> result;
  for(size_t i=1;i<xs.size();i++) {
    // Event tuple: front multiplicity, back multiplicity, material delta.
    std::map<int64_t,std::vector<std::array<int64_t,3>>> events;
    for(unsigned g=0;g<2;g++) for(const auto& r:g?back:front) if(r.x0<=xs[i-1]&&xs[i]<=r.x1) {
      events[r.y0].push_back({g,1,r.material}); events[r.y1].push_back({g,-1,r.material});
    }
    int64_t count[2]={0,0},material=0; std::vector<Strip> intervals;
    for(auto it=events.begin();it!=events.end();++it) {
      for(auto e:it->second) { count[e[0]]+=e[1]; if(e[0]==0) material+=e[1]*e[2]; }
      auto next=std::next(it); if(next==events.end()) break;
      require(count[0]<=1,"duplicate drawable or occupancy coverage");
      if(count[0]==1&&count[1]==0) append(intervals,it->first,next->first,number(material));
    }
    append(result,xs[i-1],xs[i],strips(intervals));
  }
  return strips(result);
}
J occupancy(const std::vector<Box>& boxes) {
  std::set<int64_t> bounds; for(const auto& b:boxes) { bounds.insert(b.lo[0]); bounds.insert(b.hi[0]); }
  std::vector<int64_t> xs(bounds.begin(),bounds.end()); std::vector<Strip> out;
  for(size_t i=1;i<xs.size();i++) {
    std::vector<Rect> rs;
    for(const auto& b:boxes) if(b.lo[0]<=xs[i-1]&&xs[i]<=b.hi[0]) rs.push_back({b.lo[1],b.hi[1],b.lo[2],b.hi[2],b.material});
    append(out,xs[i-1],xs[i],plane(rs));
  }
  return strips(out);
}
using Planes=std::map<std::pair<uint32_t,int64_t>,std::vector<Rect>>;
Planes boundaries(const std::vector<Box>& boxes) {
  Planes out;
  for(const auto& b:boxes) for(unsigned side=0;side<6;side++) {
    unsigned a=side/2,u=(a+1)%3,v=(a+2)%3;
    out[{side,side%2?b.hi[a]:b.lo[a]}].push_back({b.lo[u],b.hi[u],b.lo[v],b.hi[v],b.material});
  }
  return out;
}
J surfaces(const Planes& ps,bool subtract=false) {
  std::map<std::tuple<uint32_t,uint32_t,int64_t>,J> groups;
  for(const auto& [key,rs]:ps) {
    plane(rs); // Reject duplicates across materials before separating labels.
    auto other=ps.find({key.first^1,key.second});
    for(uint32_t material=1;material<=5;material++) {
      std::vector<Rect> front;
      for(const auto& r:rs) if(r.material==material) front.push_back(r);
      if(front.empty()) continue;
      J coverage=plane(front,subtract&&other!=ps.end()?other->second:std::vector<Rect>{});
      if(coverage!="[]") groups[{key.first,material,key.second}]=coverage;
    }
  }
  std::vector<J> out;
  for(const auto& [key,coverage]:groups)
    out.push_back(array({number(std::get<0>(key)),number(std::get<1>(key)),number(std::get<2>(key)),coverage}));
  return array(out);
}

bool touches(const Box& a,const Box& b) {
  for(unsigned axis=0;axis<3;axis++) if(a.lo[axis]==b.hi[axis]||a.hi[axis]==b.lo[axis]) {
    bool overlap=true; for(unsigned k=0;k<3;k++) if(k!=axis) overlap&=std::max(a.lo[k],b.lo[k])<std::min(a.hi[k],b.hi[k]);
    if(overlap) return true;
  }
  return false;
}
void connected(const std::vector<Box>& boxes) {
  require(!boxes.empty(),"empty owner"); std::vector<bool> seen(boxes.size()); seen[0]=true;
  std::vector<size_t> queue{0};
  for(size_t i=0;i<queue.size();i++) for(size_t j=0;j<boxes.size();j++)
    if(!seen[j]&&touches(boxes[queue[i]],boxes[j])) { seen[j]=true; queue.push_back(j); }
  require(queue.size()==boxes.size(),"disconnected owner");
}
void vertices(const VoxelVkBody& b) {
  require(uint64_t(b.face_count)*6==b.vertex_count,"surface vertex count");
  for(unsigned i=0;i<b.face_count;i++) {
    auto& face=b.faces[i]; unsigned axis=face.side/2,u=(axis+1)%3,v=(axis+2)%3;
    std::set<std::array<float,3>> expected,actual;
    for(unsigned c=0;c<4;c++) {
      std::array<float,3> p; for(unsigned k=0;k<3;k++) p[k]=((k==u&&(c&1))||(k==v&&(c&2))?face.hi[k]:face.lo[k])*.1f;
      expected.insert(p);
    }
    std::set<std::array<float,3>> tris[2];
    for(unsigned j=0;j<6;j++) {
      const auto& t=b.vertices[i*6+j];
      require(t.side==face.side&&t.material==face.material,"vertex label mismatch");
      std::array<float,3> p; for(unsigned k=0;k<3;k++) { require(std::isfinite(t.position[k]),"nonfinite vertex"); p[k]=t.position[k]; }
      actual.insert(p); tris[j/3].insert(p);
    }
    require(actual==expected,"vertex corner mismatch");
    for(unsigned j:{0u,3u}) {
      const auto *a=b.vertices[i*6+j].position,*q=b.vertices[i*6+j+1].position,*c=b.vertices[i*6+j+2].position;
      double cross=(double(q[u])-a[u])*(double(c[v])-a[v])-(double(q[v])-a[v])*(double(c[u])-a[u]);
      require(cross*(face.side%2?1:-1)>0,"wrong drawable winding");
    }
    std::vector<std::array<float,3>> shared;
    std::set_intersection(tris[0].begin(),tris[0].end(),tris[1].begin(),tris[1].end(),std::back_inserter(shared));
    require(shared.size()==2&&shared[0][u]!=shared[1][u]&&shared[0][v]!=shared[1][v],"duplicate or incomplete drawable triangles");
  }
}
J body(const VoxelVkBody& b,const VoxelMegaBody& raw,J& work,std::vector<Box>& global) {
  require(b.anchored<=1,"invalid anchor boolean");
  std::vector<Box> boxes; uint64_t cells=0,protected_cells=0;
  for(unsigned i=0;i<raw.box_count;i++) {
    const auto& r=raw.boxes[i]; Box box;
    uint64_t volume=1;
    for(unsigned k=0;k<3;k++) {
      box.lo[k]=cell(r.lo[k]); box.hi[k]=cell(r.hi[k]); require(box.lo[k]<box.hi[k],"empty cuboid");
      auto width=uint64_t(box.hi[k]-box.lo[k]); require(volume<=UINT32_MAX/width,"cuboid volume overflow"); volume*=width;
    }
    require(r.material>=1&&r.material<=5,"invalid material"); box.material=r.material;
    cells+=volume; require(cells<=UINT32_MAX,"owner cell overflow"); if(r.material==1) protected_cells+=volume;
    boxes.push_back(box); global.push_back(box);
  }
  J occupied=occupancy(boxes); // Reject overlap before connectivity or normalization can obscure it.
  connected(boxes);
  require(bool(b.anchored)==(protected_cells>0),"anchor mismatch");
  require(raw.tree_nodes==2*uint64_t(raw.box_count)-1,"tree node inventory mismatch");
  for(unsigned k=0;k<3;k++) {
    int64_t lo=boxes[0].lo[k],hi=boxes[0].hi[k];
    for(auto& box:boxes) { lo=std::min(lo,box.lo[k]); hi=std::max(hi,box.hi[k]); }
    require(lo==cell(b.lo[k])&&hi==cell(b.hi[k]),"body bounds mismatch");
  }
  Planes drawn;
  for(unsigned i=0;i<b.face_count;i++) {
    const auto& f=b.faces[i]; require(f.side<6&&f.material>=1&&f.material<=5,"surface label mismatch");
    unsigned a=f.side/2,u=(a+1)%3,v=(a+2)%3;
    require(cell(f.lo[a])==cell(f.hi[a]),"nonplanar drawable");
    drawn[{f.side,cell(f.lo[a])}].push_back({cell(f.lo[u]),cell(f.hi[u]),cell(f.lo[v]),cell(f.hi[v]),f.material});
  }
  J surface=surfaces(drawn);
  require(surface==surfaces(boundaries(boxes),true),"missing or incorrect drawable coverage");
  vertices(b);
  work=object({{"cells",number(cells)},{"cuboids",number(raw.box_count)},{"id",number(b.id)},
    {"protected_cells",number(protected_cells)},{"surface_rectangles",number(b.face_count)},
    {"tree_nodes",number(raw.tree_nodes)},{"vertices",number(b.vertex_count)}});
  return object({{"anchored",b.anchored?"true":"false"},{"id",number(b.id)},{"occupancy",occupied},
    {"offset_m",real(b.offset)},{"revision",number(b.revision)},{"surface",surface},{"velocity_m_s",real(raw.speed)}});
}
void emit(const VoxelVkFrame& f,const VoxelMegaState& s) {
  std::vector<unsigned> order; for(unsigned i=0;i<f.body_count;i++) order.push_back(i);
  std::sort(order.begin(),order.end(),[&](unsigned a,unsigned b){return f.bodies[a].id<f.bodies[b].id;});
  std::vector<J> bodies,work; Object hashes; std::vector<Box> global;
  for(unsigned i:order) {
    const auto& b=f.bodies[i]; require(b.id>0&&b.id<s.world[4]&&!hashes.count(std::to_string(b.id)),"duplicate or invalid body ID");
    J inventory; J value;
    try { value=body(b,s.bodies[i],inventory,global); }
    catch(const std::exception& e) { throw std::runtime_error("body "+std::to_string(b.id)+": "+e.what()); }
    bodies.push_back(value); work.push_back(inventory); hashes[std::to_string(b.id)]=quote(hash(value));
  }
  // Static owners cannot duplicate source ownership. No dense world expansion.
  occupancy(global);
  uint64_t total=0; for(const auto& b:global) total+=uint64_t(b.hi[0]-b.lo[0])*(b.hi[1]-b.lo[1])*(b.hi[2]-b.lo[2]);
  require(total==s.world[0],"world conservation mismatch");
  J view=object({{"aim",object({{"kind",number(f.aim_kind)},{"position_m",array({real(f.aim[0]),real(f.aim[1]),real(f.aim[2])})},{"radius_m",real(s.aim_radius)}})},
    {"eye_m",array({real(f.eye[0]),real(f.eye[1]),real(f.eye[2])})},{"height",number(f.height)},
    {"pitch",real(f.pitch)},{"width",number(f.width)},{"yaw",real(f.yaw)}});
  J payload=object({{"action_outcomes","[]"},{"bodies",array(bodies)},{"budget",number(s.world[5])},
    {"cells",number(s.world[0])},{"fixed_step",quote("0x3c888889")},{"fragments",number(s.world[1])},
    {"next_id",number(s.world[4])},{"removed",number(s.world[2])},{"schedule_sha256",quote(s.schedule_sha256)},
    {"schema",quote("megascene-checkpoint/1")},{"status",number(s.world[3])},{"view",view}});
  std::vector<J> names;
  if(s.frame==0) { names.push_back(quote("initialization")); names.push_back(quote("review_opening")); }
  if(s.frame==s.warmup) names.push_back(quote("warmup_end"));
  if(s.frame==uint64_t(s.warmup)+s.measured) names.push_back(quote("completion"));
  Object record={{"body_sha256",object(hashes)},{"names",array(names)},{"record_type",quote(names.empty()?"static_audit":"checkpoint")},
    {"sha256",quote(hash(payload))},{"work",array(work)}};
  if(!names.empty()) record["payload"]=payload;
  J serialized=object(record); f.record(serialized.substr(1,serialized.size()-2).c_str());
}
} // namespace checkpoint
extern "C" int voxel_mega_checkpoint(const VoxelVkFrame* frame,const VoxelMegaState* state,char* error,size_t cap) {
  try { checkpoint::emit(*frame,*state); return 1; }
  catch(const std::exception& e) { std::snprintf(error,cap,"%s",e.what()); return 0; }
}
