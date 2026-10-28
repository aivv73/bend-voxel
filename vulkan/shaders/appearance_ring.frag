#version 450
#extension GL_GOOGLE_include_directive : require
#include "appearance_common.glsl"
layout(location=0) flat in vec4 endpoints;
layout(location=1) flat in vec2 inverseDepth;
layout(location=2) flat in uint visible;
layout(location=0) out vec4 outputColor;
void main() {
  if (visible == 0u) discard;
  vec2 delta = endpoints.zw - endpoints.xy;
  float squared = dot(delta,delta);
  float t = squared > 0.0 ? clamp(dot(gl_FragCoord.xy - endpoints.xy, delta) / squared, 0.0, 1.0) : 0.0;
  vec2 error = gl_FragCoord.xy - endpoints.xy - t * delta;
  if (dot(error,error) > 0.5625) discard;
  float inverse = inverseDepth.x + t * (inverseDepth.y - inverseDepth.x);
  if (inverse <= 0.0) discard;
  float depth = 1.0 / inverse;
  if (depth < frame.eye_near.w) discard;
  float biasedDepth = max(frame.eye_near.w, depth - 0.0001);
  gl_FragDepth = 1.0 - frame.eye_near.w / biasedDepth;
  outputColor = appearance_finish(vec3(1,1,0));
}
