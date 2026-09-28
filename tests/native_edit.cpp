#define EDIT_NUMERIC_ONLY
#include "../src/edit/guard.c"
#include <cassert>
#include <initializer_list>
#include <limits>
int main() {
  float point[]={-16.f,2.4f,-16.f},local[3];
  assert(edit_point_valid(point,0,local));
  assert(local[0]==-160 && local[1]==24);
  float lo[]={-320.f,8.f,-320.f},hi[]={320.f,24.f,320.f};
  assert(edit_box_valid(lo,hi));
  uint64_t leaves=0; assert(edit_subdivision(lo,hi,local,&leaves,0)); assert(leaves>1);
  float positive_decimal[]={-24.4f,7.303800106f,22.8f};
  assert(edit_point_valid(positive_decimal,-.196200043f,local));
  assert(fabsf(local[2]-228.f)<.0001f);
  float moved[]={-.05f,9.05f,.05f}; assert(edit_point_valid(moved,-1,local));
  assert(local[1]==100.5f);
  float falling[]={-29.5f,4.f,-11.6f},span_lo[]={-304.f,42.f,-144.f},span_hi[]={-184.f,76.f,-136.f};
  assert(!edit_point_valid(falling,-.196200043f,local));
  assert(edit_remote_valid(falling,-.196200043f,span_lo,span_hi,local));
  falling[2]=-14.f;
  assert(!edit_remote_valid(falling,-.196200043f,span_lo,span_hi,local));
  float terrain_lo[]={-320.f,0.f,-320.f},terrain_hi[]={320.f,24.f,320.f};
  float beam_cut[]={-24.4f,7.203800201f,-14.f};
  assert(edit_remote_valid(beam_cut,0.f,terrain_lo,terrain_hi,local));
  terrain_hi[1]=72.f;
  assert(!edit_remote_valid(beam_cut,0.f,terrain_lo,terrain_hi,local));
  falling[2]=std::numeric_limits<float>::infinity();
  assert(!edit_remote_valid(falling,-.196200043f,span_lo,span_hi,local));
  for(float invalid:{std::numeric_limits<float>::infinity(),std::numeric_limits<float>::quiet_NaN(),1025.f,0.123f}) {
    float bad[]={invalid,0,0}; assert(!edit_point_valid(bad,0,local));
    float low[]={invalid,0,0},high[]={1026.f,1,1}; assert(!edit_box_valid(low,high));
  }
  float p[]={0,0,0};
  for(int x=-5;x<5;x++) for(int y=-5;y<5;y++) for(int z=-5;z<5;z++) {
    float a[]={float(x),float(y),float(z)},b[]={float(x+1),float(y+1),float(z+1)};
    int near,far; assert(edit_predicate(a,b,p,0,&near)&&edit_predicate(a,b,p,1,&far));
    double d=(x+.5)*(x+.5)+(y+.5)*(y+.5)+(z+.5)*(z+.5);
    assert(near==(d<=4.00001)&&far==near);
  }
}
