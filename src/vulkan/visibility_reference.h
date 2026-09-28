#pragma once
// Unculled triangle reference, independent of the production AABB corner mask.
// Double arithmetic clips actual full-mesh triangles against all five planes.
namespace visibility_reference {
using Point=std::array<double,3>;
Point camera(const VoxelVkVertex& v,float offset,const VoxelVkFrame& f) {
  double x=double(v.position[0])-f.eye[0],y=double(v.position[1])+offset-f.eye[1],z=double(v.position[2])-f.eye[2];
  double sy=std::sin(double(f.yaw)),cy=std::cos(double(f.yaw)),sp=std::sin(double(f.pitch)),cp=std::cos(double(f.pitch));
  return {-x*cy+z*sy,-x*sy*sp+y*cp-z*cy*sp,x*sy*cp+y*sp+z*cy*cp};
}
double distance(Point p,unsigned plane,const VoxelVkFrame& f) {
  double horizontal=800.*f.height/(360.*f.width),vertical=400./180.;
  switch(plane) { case 0:return p[2]-.05; case 1:return p[2]-p[0]*horizontal;
    case 2:return p[2]+p[0]*horizontal; case 3:return p[2]-p[1]*vertical; default:return p[2]+p[1]*vertical; }
}
bool triangle(const VoxelVkVertex* vs,float offset,const VoxelVkFrame& f) {
  std::vector<Point> polygon; for(unsigned j=0;j<3;j++) polygon.push_back(camera(vs[j],offset,f));
  for(unsigned plane=0;plane<5&&!polygon.empty();plane++) {
    std::vector<Point> clipped;
    for(size_t j=0;j<polygon.size();j++) {
      auto a=polygon[j],b=polygon[(j+1)%polygon.size()]; double da=distance(a,plane,f),db=distance(b,plane,f);
      if(da>=0) clipped.push_back(a);
      if((da>=0)!=(db>=0)) { Point p; double t=da/(da-db); for(unsigned k=0;k<3;k++) p[k]=a[k]+t*(b[k]-a[k]); clipped.push_back(p); }
    }
    polygon=std::move(clipped);
  }
  return !polygon.empty();
}
bool body(const VoxelVkBody& b,const VoxelVkFrame& f) {
  for(unsigned j=0;j+2<b.vertex_count;j+=3) if(triangle(b.vertices+j,b.offset,f)) return true;
  return false;
}
}
