#version 450
#extension GL_GOOGLE_include_directive : require
#include "appearance_common.glsl"
#include "appearance_pcf.glsl"
layout(location=0) out vec4 outputColor;
void main() {
  uint canonicalY = uint(floor(gl_FragCoord.y * 512.0 / frame.viewport.y));
  uint packed = 1054752u + (min(canonicalY, 511u) / 32u) * 65793u;
  vec3 display = vec3(uvec3(packed >> 16u, packed >> 8u, packed) & uvec3(255u)) / 255.0;
  vec3 linear = appearance_decode(display);
  vec3 ray = appearance_ray(gl_FragCoord.xy);
  if (frame.eye_near.z > -0.5 && ray.z < 0.0) {
    float t = (-0.5 - frame.eye_near.z) / ray.z;
    vec3 point = frame.eye_near.xyz + t * ray;
    if (all(greaterThanEqual(point.xy, vec2(-16))) && all(lessThanEqual(point.xy, vec2(24)))) {
      vec2 f = fract(point.xy * 0.5);
      bool grid = any(lessThan(f, vec2(0.0125))) || any(greaterThan(f, vec2(0.9875)));
      vec3 base = grid ? vec3(0.055, 0.065, 0.08) : vec3(0.10, 0.12, 0.15);
      linear = appearance_day(base, vec3(0,0,1), appearance_visibility(point, vec3(0,0,1)));
    }
  }
  outputColor = appearance_finish(linear);
}
