#define MEGA_REFERENCE_ONLY
#include "../src/vulkan/record.c"
#include <vector>
int main(int argc,char** argv) {
  if(argc!=3) return 2;
  FILE* input=fopen(argv[1],"rb");
  if(!input) return 2;
  std::vector<uint32_t> rows(21721*2);
  bool valid=mega_policy_read(input,rows.data(),21721,strcmp(argv[2],"history")==0);
  fclose(input);
  return valid?0:2;
}
