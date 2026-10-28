#version 450
layout(set=1,binding=0) uniform sampler2D depthMap;
layout(location=0) out vec4 color;
void main() {
  color = vec4(vec3(texture(depthMap, vec2(0.5)).r), 1.0);
}
