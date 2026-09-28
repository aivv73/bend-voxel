#ifndef VOXEL_PICK_NUMERIC_H
#define VOXEL_PICK_NUMERIC_H
#include <math.h>
// A deliberately bounded operational envelope, not universal F32 admission.
// Check rounded operations against double reference arithmetic before Bend's
// unsafe tree traversal. No FMA: the production expression has separate ops.
static int pick_close(float actual, double exact, double tolerance) {
  return isfinite(actual) && fabs((double)actual-exact)<=tolerance;
}
static int pick_ray_valid(const float* o,const float* d) {
  double norm=0;
  for(int k=0;k<3;k++) {
    if(!isfinite(o[k])||fabsf(o[k])>2048||!isfinite(d[k])||fabsf(d[k])>1.000001f) return 0;
    norm+=(double)d[k]*d[k];
    // End of the admitted distance interval; bounds every accepted hit multiply/add.
    float travel=d[k]*256.f, point=o[k]+travel;
    if(!pick_close(travel,(double)d[k]*256,0.0001)||!pick_close(point,(double)o[k]+travel,0.00025)) return 0;
  }
  float divisor=fabsf(d[1])>0.000001f?d[1]:0.000001f;
  float ground=0.f-o[1]/divisor;
  double exact=-(double)o[1]/divisor;
  return fabs(norm-1)<0.000002 && pick_close(ground,exact,0.0001+fabs(exact)*0.0000002);
}
static int pick_box_valid(const float* lo,const float* hi,float offset,const float* o,const float* d) {
  if(!pick_ray_valid(o,d)||!isfinite(offset)||fabsf(offset)>1024) return 0;
  for(int k=0;k<3;k++) {
    float converted[2];
    for(int end=0;end<2;end++) {
      float cell=end?hi[k]:lo[k];
      if(!isfinite(cell)||fabsf(cell)>8192||floorf(cell)!=cell) return 0;
      float metres=cell*0.1f;
      if(!pick_close(metres,(double)cell/10,0.0001)) return 0;
      float world=metres+(k==1?offset:0.f);
      if(!pick_close(world,(double)cell/10+(k==1?offset:0),0.0002)) return 0;
      converted[end]=world;
      float delta=world-o[k];
      if(!pick_close(delta,(double)world-o[k],0.00025)) return 0;
      if(fabsf(d[k])>=0.0000001f) {
        float distance=delta/d[k];
        double exact=((double)world-o[k])/d[k];
        if(!pick_close(distance,exact,0.0005+fabs(exact)*0.0000003)) return 0;
        if(distance>=0 && distance<256) {
          for(int j=0;j<3;j++) {
            float travel=d[j]*distance, point=o[j]+travel;
            if(!pick_close(travel,(double)d[j]*distance,0.0001)||
               !pick_close(point,(double)o[j]+(double)d[j]*distance,0.00025)) return 0;
          }
        }
      }
    }
    // Reject collapsed/reversed cells even when integral endpoints are exact.
    if(hi[k]<=lo[k] || converted[1]-converted[0]<0.0995f) return 0;
  }
  return 1;
}
#endif

#ifndef PICK_NUMERIC_ONLY
static float picking_float(Term word) {
  uint32_t bits=(uint32_t)word; float value; memcpy(&value,&bits,4); return value;
}
static void picking_tree(Env e,Term tree,float offset,const float* origin,const float* direction,unsigned depth) {
  if(depth>128) err_fail("picking numeric guard: tree depth");
  uint32_t kind=term_aux(tree);
  if(kind==CID_SPATIAL_EMPTY) return;
  if(kind!=CID_SPATIAL_LEAF&&kind!=CID_SPATIAL_BRANCH) err_fail("picking numeric guard: tree layout");
  uint64_t at=term_peek(e.mem,tree); float lo[3],hi[3];
  for(int k=0;k<3;k++) { lo[k]=picking_float(e.mem[at+k]); hi[k]=picking_float(e.mem[at+3+k]); }
  if(!pick_box_valid(lo,hi,offset,origin,direction)) err_fail("picking numeric guard: unsupported cell/metre/offset/distance operation");
  if(kind==CID_SPATIAL_BRANCH) {
    picking_tree(e,e.mem[at+7],offset,origin,direction,depth+1);
    picking_tree(e,e.mem[at+8],offset,origin,direction,depth+1);
  }
}
Term megascene_picking_guard_run(Env e,Term* f,IoWork* work) {
  io_sync();
  if(cid_arity(CID_MEGASCENE_PICKING_RAY)!=7||cid_arity(CID_WORLD_BODY)!=8) err_fail("picking numeric guard: ABI");
  uint64_t ray=term_peek(e.mem,f[1]);
  if(e.mem[ray]) {
    float origin[3],direction[3];
    for(int k=0;k<3;k++) { origin[k]=picking_float(e.mem[ray+1+k]); direction[k]=picking_float(e.mem[ray+4+k]); }
    if(!pick_ray_valid(origin,direction)) err_fail("picking numeric guard: unsupported ray");
    Term list=f[0];
    while(term_aux(list)==CID_CON) {
      uint64_t link=term_peek(e.mem,list),body=term_peek(e.mem,e.mem[link]);
      picking_tree(e,e.mem[body+5],picking_float(e.mem[body+2]),origin,direction,0);
      list=e.mem[link+1];
    }
    if(term_aux(list)!=CID_NIL) err_fail("picking numeric guard: body list");
  }
  term_sink(e,f[0]); term_sink(e,f[1]);
  return term_pak(CID_UNIT,0);
}
static void __attribute__((constructor)) picking_guard_effect(void) {
  io_eff(CID_MEGASCENE_PICKING_GUARD,megascene_picking_guard_run,0);
}

#endif
