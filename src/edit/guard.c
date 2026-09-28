#ifndef VOXEL_EDIT_NUMERIC_H
#define VOXEL_EDIT_NUMERIC_H
#include <math.h>
#include <stdint.h>
#include <stddef.h>
// Admit a bounded half-cell brush grid. Exact endpoints alone are insufficient:
// compare each potentially visited sphere predicate before Bend's recursion.
static int edit_point_valid(const float* point,float offset,float* local) {
  if(!isfinite(offset)||fabsf(offset)>1024) return 0;
  for(unsigned k=0;k<3;k++) {
    float relative=point[k]-(k==1?offset:0.f);
    local[k]=relative*10.f;
    if(!isfinite(point[k])||!isfinite(local[k])||fabsf(local[k])>1024 ||
       fabsf(local[k]*2.f-roundf(local[k]*2.f))>0.0001f ||
       fabs((double)local[k]-((double)point[k]-(k==1?offset:0.))*10.)>0.00001) return 0;
  }
  return 1;
}
static int edit_box_valid(const float* lo,const float* hi) {
  for(unsigned k=0;k<3;k++)
    if(!isfinite(lo[k])||!isfinite(hi[k])||fabsf(lo[k])>1024||fabsf(hi[k])>1024||
       floorf(lo[k])!=lo[k]||floorf(hi[k])!=hi[k]||lo[k]>=hi[k]) return 0;
  return 1;
}
// An unrelated translated body need not put the brush on a half-cell grid.
// Certify separation on any axis in both exact metre arithmetic and the
// actual rounded local coordinates. A vertical separation is needed when a
// moved beam is cut over terrain. Its traversal returns unchanged at the root.
static int edit_remote_valid(const float* point,float offset,const float* lo,const float* hi,float* local) {
  if(!isfinite(offset)||fabsf(offset)>1024||!edit_box_valid(lo,hi)) return 0;
  int separate=0;
  for(unsigned k=0;k<3;k++) {
    local[k]=(point[k]-(k==1?offset:0.f))*10.f;
    if(!isfinite(point[k])||!isfinite(local[k])||fabsf(local[k])>1024) return 0;
    double exact=((double)point[k]-(k==1?(double)offset:0.))*10.;
    separate |= (exact < lo[k]-4. && local[k]<lo[k]-4.f) ||
                (exact > hi[k]+4. && local[k]>hi[k]+4.f);
  }
  return separate;
}
static int edit_predicate(const float* lo,const float* hi,const float* p,int far,int* hit) {
  float sums[3]; double exact=0;
  for(unsigned k=0;k<3;k++) {
    float a=lo[k]+.5f,b=hi[k]-.5f;
    float d=far?fmaxf(fabsf(p[k]-a),fabsf(p[k]-b)):p[k]-fmaxf(a,fminf(p[k],b));
    sums[k]=d*d; exact+=(double)d*d;
  }
  float rounded=(sums[0]+sums[1])+sums[2];
  *hit=rounded<=4.00001f;
  return isfinite(rounded) && *hit==(exact<=4.00001);
}
// Bound all subdivision output, even protected leaves, without materializing it.
static int edit_subdivision(const float* lo,const float* hi,const float* p,uint64_t* leaves,unsigned depth) {
  int near,far;
  if(depth>128||!edit_predicate(lo,hi,p,0,&near)||!edit_predicate(lo,hi,p,1,&far)) return 0;
  if(!near||far) { (*leaves)++; return *leaves<=UINT32_MAX; }
  unsigned axis=0;
  for(unsigned k=1;k<3;k++) if(hi[k]-lo[k]>hi[axis]-lo[axis]) axis=k;
  float mid=floorf((lo[axis]+hi[axis])*.5f);
  if(mid<=lo[axis]||mid>=hi[axis]) return 0;
  float low[3],high[3];
  for(unsigned k=0;k<3;k++) { low[k]=lo[k]; high[k]=hi[k]; }
  high[axis]=mid;
  if(!edit_subdivision(lo,high,p,leaves,depth+1)) return 0;
  low[axis]=mid;
  return edit_subdivision(low,hi,p,leaves,depth+1);
}
#endif
#ifndef EDIT_NUMERIC_ONLY
static float edit_float(Term word) {
  uint32_t bits=(uint32_t)word; float value; memcpy(&value,&bits,4); return value;
}
static void edit_tree(Env e,Term tree,const float* p,uint64_t* cells,uint64_t* leaves,unsigned depth) {
  if(depth>128) err_fail("edit numeric guard: tree depth");
  uint32_t kind=term_aux(tree);
  if(kind!=CID_SPATIAL_LEAF&&kind!=CID_SPATIAL_BRANCH) err_fail("edit numeric guard: tree layout");
  uint64_t at=term_peek(e.mem,tree); float lo[3],hi[3];
  for(unsigned k=0;k<3;k++) { lo[k]=edit_float(e.mem[at+k]); hi[k]=edit_float(e.mem[at+3+k]); }
  int near,far;
  if(!edit_box_valid(lo,hi)||!edit_predicate(lo,hi,p,0,&near)||!edit_predicate(lo,hi,p,1,&far))
    err_fail("edit numeric guard: unsupported bounds/predicate");
  if(kind==CID_SPATIAL_BRANCH) {
    edit_tree(e,e.mem[at+7],p,cells,leaves,depth+1);
    edit_tree(e,e.mem[at+8],p,cells,leaves,depth+1);
  } else {
    if(e.mem[at+6]<1||e.mem[at+6]>5) err_fail("edit numeric guard: material");
    uint64_t volume=1;
    for(unsigned k=0;k<3;k++) volume*=(uint64_t)(hi[k]-lo[k]);
    *cells+=volume;
    if(*cells>UINT32_MAX||!edit_subdivision(lo,hi,p,leaves,0)) err_fail("edit numeric guard: counts/subdivision");
  }
}
Term megascene_edit_guard_run(Env e,Term* f,IoWork* work) {
  io_sync();
  if(cid_arity(CID_WORLD_WORLD)!=7||cid_arity(CID_WORLD_BODY)!=8||cid_arity(CID_MATH_VEC)!=3)
    err_fail("edit numeric guard: ABI");
  uint64_t world=term_peek(e.mem,f[0]),point=term_peek(e.mem,f[1]);
  float p[3]; for(unsigned k=0;k<3;k++) p[k]=edit_float(e.mem[point+k]);
  Term list=e.mem[world]; uint64_t cells=0,leaves=0,count=0,fragments=0;
  while(term_aux(list)==CID_CON) {
    uint64_t link=term_peek(e.mem,list),body=term_peek(e.mem,e.mem[link]); float local[3];
    uint32_t id=(uint32_t)e.mem[body];
    Term tree=e.mem[body+5];
    if(term_aux(tree)!=CID_SPATIAL_LEAF&&term_aux(tree)!=CID_SPATIAL_BRANCH) err_fail("edit numeric guard: tree layout");
    uint64_t root=term_peek(e.mem,tree); float lo[3],hi[3];
    for(unsigned k=0;k<3;k++) { lo[k]=edit_float(e.mem[root+k]); hi[k]=edit_float(e.mem[root+3+k]); }
    if(!id||id>=e.mem[world+5]||e.mem[body+4]>1||!isfinite(edit_float(e.mem[body+3]))||
       !(edit_point_valid(p,edit_float(e.mem[body+2]),local)||
         edit_remote_valid(p,edit_float(e.mem[body+2]),lo,hi,local))) err_fail("edit numeric guard: ID/motion/target");
    edit_tree(e,e.mem[body+5],local,&cells,&leaves,0);
    count++; fragments+=!e.mem[body+4]; list=e.mem[link+1];
  }
  // At most one component per surviving leaf. At most six unit faces per
  // occupied cell, six vertices per face. These conservative bounds also cover
  // temporary surface subtraction, native slots, byte multiplication and IDs.
  if(term_aux(list)!=CID_NIL||cells!=e.mem[world+1]||fragments!=e.mem[world+2]||
     count>UINT32_MAX||leaves*2>UINT32_MAX||e.mem[world+5]+leaves>UINT32_MAX||
     cells>UINT32_MAX/36||cells>SIZE_MAX/(36*64)) err_fail("edit numeric guard: evolving count/ID/native size");
  term_sink(e,f[0]); term_sink(e,f[1]);
  return term_pak(CID_UNIT,0);
}
static void __attribute__((constructor)) edit_guard_effect(void) {
  io_eff(CID_MEGASCENE_EDIT_GUARD,megascene_edit_guard_run,0);
}
#endif
