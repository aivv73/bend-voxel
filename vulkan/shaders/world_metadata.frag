#version 450
#extension GL_GOOGLE_include_directive : require
#include "appearance_common.glsl"
layout(location=0) flat in vec3 legacyColor;
layout(location=1) flat in uvec4 material;
layout(location=2) flat in uint direction;
layout(location=3) flat in vec3 anchor;
layout(location=4) flat in vec2 extent;
layout(location=0) out vec4 outputColor;
void main() {
  precise float t;
  precise float u;
  precise float v;
  if (!appearance_intersection(anchor, extent, direction, appearance_ray(gl_FragCoord.xy), t, u, v)) discard;
  uint fields[8] = uint[8](floatBitsToUint(u), floatBitsToUint(v),
    floatBitsToUint(anchor.x), floatBitsToUint(anchor.y), floatBitsToUint(anchor.z),
    floatBitsToUint(extent.x), floatBitsToUint(extent.y), floatBitsToUint(t));
  uint word = fields[frame.flags.z];
  outputColor = appearance_raw(vec4(uvec4(word,word>>8u,word>>16u,word>>24u)&255u)/255.0);
}
