#include "../src/vulkan/native.h"
#include "../src/vulkan/checkpoint.h"

int main(int argc,char** argv) {
  if(argc!=5) return 2;
  char error[1024];
  int selected=voxel_mega_schedule_selected(std::strtoul(argv[1],nullptr,10),std::strtoull(argv[2],nullptr,10),
    std::strtoul(argv[3],nullptr,10),std::strtoul(argv[4],nullptr,10),error,sizeof error);
  if(selected<0) { std::fprintf(stderr,"%s\n",error); return 2; }
  std::printf("%d\n",selected);
}
