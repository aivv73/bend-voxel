#version 450
#extension GL_GOOGLE_include_directive : require
#include "appearance_frame.glsl"
layout(location=0) flat out vec4 endpoints;
layout(location=1) flat out vec2 inverseDepth;
layout(location=2) flat out uint visible;
vec3 ringPoint(uint ring, uint index) {
  float angle = float(index) * 0.1963495408;
  float c = frame.brush_cm.w / 10.0 * cos(angle);
  float s = frame.brush_cm.w / 10.0 * sin(angle);
  vec3 delta = ring == 0u ? vec3(c,s,0) : ring == 1u ? vec3(c,0,s) : vec3(0,c,s);
  return frame.brush_cm.xyz / 10.0 + delta;
}
vec3 eyePoint(vec3 p) {
  vec3 d = p - frame.eye_near.xyz;
  return vec3(dot(d, frame.camera_right.xyz), dot(d, frame.camera_up.xyz), dot(d, frame.camera_forward_focal.xyz));
}
vec3 nearCross(vec3 a, vec3 b, float near) {
  vec3 low = a.z < b.z ? a : b;
  vec3 high = a.z < b.z ? b : a;
  float t = (near - low.z) / (high.z - low.z);
  return vec3(low.xy + t * (high.xy - low.xy), near);
}
void main() {
  uint segment = uint(gl_VertexIndex) / 6u;
  uint corner = uint(gl_VertexIndex) % 6u;
  uint ring = segment / 32u;
  uint index = segment % 32u;
  vec3 a = eyePoint(ringPoint(ring, index));
  vec3 b = eyePoint(ringPoint(ring, index + 1u));
  float near = frame.eye_near.w;
  visible = frame.flags.x != 0u && (a.z >= near || b.z >= near) ? 1u : 0u;
  endpoints = vec4(0);
  inverseDepth = vec2(1);
  if (visible == 0u) { gl_Position = vec4(0,0,0,1); return; }
  if (a.z < near) a = nearCross(a, b, near);
  else if (b.z < near) b = nearCross(a, b, near);
  vec2 p = frame.viewport.xy * 0.5 + frame.camera_forward_focal.w * vec2(a.x, -a.y) / a.z;
  vec2 q = frame.viewport.xy * 0.5 + frame.camera_forward_focal.w * vec2(b.x, -b.y) / b.z;
  endpoints = vec4(p,q);
  inverseDepth = 1.0 / vec2(a.z,b.z);
  vec2 delta = q - p;
  float squared = dot(delta,delta);
  vec2 tangent = squared > 0.0 ? delta / sqrt(squared) : vec2(1,0);
  vec2 normal = vec2(-tangent.y,tangent.x);
  bool end = corner == 1u || corner == 2u || corner == 3u;
  bool plus = corner == 2u || corner == 3u || corner == 4u;
  vec2 pixel = (end ? q : p) + (end ? 0.75 : -0.75) * tangent + (plus ? 0.75 : -0.75) * normal;
  gl_Position = vec4(pixel / frame.viewport.xy * 2.0 - 1.0, 0.0, 1.0);
}
