#define PICK_NUMERIC_ONLY
#include "../src/picking/guard.c"
#include <cassert>
#include <cstdio>
int main() {
  float lo[]={2560,10,0}, hi[]={2561,11,1}, o[]={0,1.05f,.05f}, d[]={1,0,0};
  assert(pick_box_valid(lo,hi,0,o,d));
  o[0]=nextafterf(0.f,1.f); assert(pick_box_valid(lo,hi,0,o,d));
  o[0]=0;
  // Exact integral F32 endpoints lose 10 cm separation after metre conversion.
  lo[0]=8388600; hi[0]=8388601;
  assert(float(int(lo[0]))==lo[0] && float(int(hi[0]))==hi[0]);
  assert(!pick_box_valid(lo,hi,0,o,d));
  lo[0]=0; hi[0]=1;
  assert(!pick_box_valid(lo,hi,16777216,o,d)); // Offset swallows the cell.
  lo[0]=.5f; assert(!pick_box_valid(lo,hi,0,o,d)); lo[0]=0;
  o[0]=INFINITY; assert(!pick_box_valid(lo,hi,0,o,d)); o[0]=0;
  d[0]=0; assert(!pick_box_valid(lo,hi,0,o,d));
  d[0]=NAN; assert(!pick_box_valid(lo,hi,0,o,d));
  d[0]=1; d[1]=1e-8f; assert(pick_box_valid(lo,hi,0,o,d));
  d[1]=1e-7f; assert(pick_box_valid(lo,hi,0,o,d));
  // Signed cells, signed offsets and finite non-exact metre endpoints admitted.
  float sl[]={-21,-11,-31}, sh[]={-20,-10,-30}, so[]={-3,-3.05f,-3.05f};
  d[1]=0; assert(pick_box_valid(sl,sh,-2,so,d));
  puts("ALL PICKING OPERATION GUARDS PASSED");
}
