#include "../src/vulkan/native.cpp"
#include <cassert>

void visibility_fixtures() {
  VoxelVkFrame f{}; f.width=640; f.height=360;
  VoxelVkVertex tri[3]={{{-.01f,-.01f,.05f},0,1},{{.01f,-.01f,.05f},0,1},{{0,.01f,.05f},0,1}};
  assert(visibility_reference::triangle(tri,0,f)); // Near plane itself.
  for(auto& p:tri) p.position[2]=.04f;
  assert(!visibility_reference::triangle(tri,0,f));
  tri[2].position[2]=.1f;
  assert(visibility_reference::triangle(tri,0,f)); // Near-plane intersection.
  for(auto& p:tri) p.position[0]-=10;
  assert(!visibility_reference::triangle(tri,0,f));
  f.eye[0]=-10; assert(visibility_reference::triangle(tri,0,f)); // Signed translation.
  for(auto& p:tri) p.position[1]-=2;
  assert(!visibility_reference::triangle(tri,0,f));
  assert(visibility_reference::triangle(tri,2,f)); // Moving-body offset.
  f.eye[0]=0;
  VoxelVkBody bounds{}; for(unsigned k=0;k<3;k++) { bounds.lo[k]=-10; bounds.hi[k]=10; }
  assert(visible(bounds,f,ViewBasis(f))); // Eye inside bounds.
  // Side-plane contact with an integer-cell box must remain conservative.
  bounds.lo[0]=8; bounds.hi[0]=9; bounds.lo[2]=10; bounds.hi[2]=11;
  assert(visible(bounds,f,ViewBasis(f)));
}

int main(int argc,char** argv) {
  visibility_fixtures();
  std::string mode=argc>1?argv[1]:"whole";
  VoxelMegaBox box{{-2,0,-1},{2,2,1},1};
  std::vector<VoxelMegaBox> boxes{box};
  if(mode=="partitioned") { boxes[0].hi[0]=0; auto other=box; other.lo[0]=0; boxes.push_back(other); }
  if(mode=="overlap") boxes.push_back(box);
  std::vector<VoxelVkFace> faces;
  std::vector<VoxelVkVertex> vertices;
  for(unsigned side=0;side<6;side++) {
    VoxelVkFace face{}; std::copy(box.lo,box.lo+3,face.lo); std::copy(box.hi,box.hi+3,face.hi);
    face.side=side; face.material=1; unsigned axis=side/2;
    face.lo[axis]=face.hi[axis]=side%2?box.hi[axis]:box.lo[axis]; faces.push_back(face);
  }
  if(mode=="rectangles") {
    auto original=faces; faces.clear();
    for(auto face:original) { auto other=face; unsigned u=(face.side/2+1)%3; float mid=(face.lo[u]+face.hi[u])/2;
      face.hi[u]=mid; other.lo[u]=mid; faces.push_back(face); faces.push_back(other); }
  }
  if(mode=="missing") faces.pop_back();
  if(mode=="duplicate") faces.push_back(faces[0]);
  if(mode=="material") faces[0].material=2;
  for(const auto& face:faces) {
    unsigned a=face.side/2,u=(a+1)%3,v=(a+2)%3;
    std::array<float,3> corners[4];
    for(unsigned c=0;c<4;c++) for(unsigned k=0;k<3;k++) corners[c][k]=((k==u&&(c&1))||(k==v&&(c&2))?face.hi[k]:face.lo[k])*.1f;
    unsigned positive[]={0,1,3,0,3,2},negative[]={0,3,1,0,2,3};
    for(unsigned j=0;j<6;j++) { VoxelVkVertex vert{}; auto p=corners[(face.side%2?positive:negative)[j]];
      std::copy(p.begin(),p.end(),vert.position); vert.side=face.side; vert.material=face.material; vertices.push_back(vert); }
  }
  if(mode=="winding") std::swap(vertices[0],vertices[1]);
  VoxelVkBody body{}; body.id=1; body.anchored=1; body.face_count=faces.size(); body.faces=faces.data();
  body.vertex_count=vertices.size(); body.vertices=vertices.data();
  std::copy(box.lo,box.lo+3,body.lo); std::copy(box.hi,box.hi+3,body.hi);
  VoxelMegaBody raw{0.f,uint32_t(boxes.size()),boxes.data(),boxes.size()*2-1};
  if(mode=="tree") raw.tree_nodes++;
  if(mode=="negative_zero") raw.speed=-0.f;
  VoxelVkFrame frame{}; frame.width=640; frame.height=360; frame.bodies=&body; frame.body_count=1;
  frame.record=[](const char* text){ std::printf("{%s}\n",text); };
  VoxelMegaState state{&raw,{16,0,0,1,2,2048},0.f,0,0,1,"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"};
  char error[1024];
  if(!voxel_mega_checkpoint(&frame,&state,error,sizeof error)) { std::fprintf(stderr,"%s\n",error); return 2; }
  // The same logical mesh can occupy a different native allocation slot.
  frame.full_geometry=1; frame.ground_half_extent=40; GeometryCache cache; bool reused; geometry(frame,cache,reused);
  frame.record=[](const char*){}; audit_native(frame,cache);
  if(mode=="stale_native") { cache.geometry.vertices[cache.meshes.at(1).first].position.x+=1;
    try { audit_native(frame,cache); } catch(const std::runtime_error& e) { std::fprintf(stderr,"%s\n",e.what()); return 2; } return 3; }
  return 0;
}
