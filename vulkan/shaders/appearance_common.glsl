#ifndef APPEARANCE_COMMON
#define APPEARANCE_COMMON
#include "appearance_frame.glsl"

vec3 appearance_decode(vec3 display) {
  return mix(pow((display + 0.055) / 1.055, vec3(2.4)), display / 12.92,
             lessThanEqual(display, vec3(0.04045)));
}
vec3 appearance_encode(vec3 linear) {
  vec3 c = clamp(linear, 0.0, 1.0);
  return mix(1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, 12.92 * c,
             lessThanEqual(c, vec3(0.0031308)));
}
vec4 appearance_finish(vec3 linear) {
  return vec4(frame.flags.y != 0u ? clamp(linear, 0.0, 1.0) : appearance_encode(linear), 1.0);
}
vec4 appearance_raw(vec4 bytes) {
  return vec4(frame.flags.y != 0u ? appearance_decode(bytes.rgb) : bytes.rgb, bytes.a);
}
vec3 appearance_ray(vec2 pixel) {
  precise vec2 offset = vec2(pixel.x - frame.viewport.x * 0.5,
                             frame.viewport.y * 0.5 - pixel.y);
  precise vec3 horizontal = frame.camera_right.xyz * (offset.x / frame.camera_forward_focal.w);
  precise vec3 vertical = frame.camera_up.xyz * (offset.y / frame.camera_forward_focal.w);
  precise vec3 tangent = horizontal + vertical;
  precise vec3 ray = frame.camera_forward_focal.xyz + tangent;
  return ray;
}
vec3 appearance_normal(uint d) {
  if (d < 2u) return vec3(d == 0u ? -1.0 : 1.0, 0, 0);
  if (d < 4u) return vec3(0, d == 2u ? -1.0 : 1.0, 0);
  return vec3(0, 0, d == 4u ? -1.0 : 1.0);
}
vec3 appearance_axes(vec3 p, uint d) {
  return d < 2u ? p.xyz : d < 4u ? p.yxz : p.zxy;
}
bool appearance_intersection(vec3 anchor, vec2 extent, uint d, vec3 ray,
                             out precise float t, out precise float u, out precise float v) {
  precise vec3 eye = appearance_axes(frame.eye_near.xyz, d);
  precise vec3 origin = appearance_axes(anchor, d);
  precise vec3 delta = appearance_axes(ray, d);
  precise float plane = origin.x + ((d & 1u) != 0u ? 1.0 : 0.0);
  precise float distance = plane - eye.x;
  precise float uEye = eye.y - origin.y;
  precise float vEye = eye.z - origin.z;
  if (delta.x == 0.0) return false;
  t = distance / delta.x;
  precise float uNumerator = uEye + t * delta.y;
  precise float vNumerator = vEye + t * delta.z;
  u = uNumerator / extent.x;
  v = vNumerator / extent.y;
  if (isnan(t) || isinf(t) || t < frame.eye_near.w) return false;
  return true;
}
bool appearance_cell(vec3 anchor, vec2 extent, uint d, vec3 ray,
                     out uvec3 cell, out vec3 point) {
  precise float t;
  precise float u;
  precise float v;
  if (!appearance_intersection(anchor, extent, d, ray, t, u, v)) return false;
  precise float localU = u * extent.x;
  precise float localV = v * extent.y;
  uvec2 offset = uvec2(clamp(floor(vec2(localU, localV)), vec2(0.0), extent - 1.0));
  cell = uvec3(anchor);
  if (d < 2u) cell.yz += offset;
  else if (d < 4u) cell.xz += offset;
  else cell.xy += offset;
  precise vec3 step = ray * t;
  point = frame.eye_near.xyz + step;
  return true;
}
bool appearance_selected(uvec3 cell) {
  if (frame.flags.x == 0u) return false;
  for (uint i = 0u; i < frame.flags.w; ++i) {
    if (all(equal(cell, frame.selected[i].xyz))) return true;
  }
  return false;
}
vec3 appearance_day(vec3 base, vec3 normal, float visibility) {
  vec3 sun = normalize(vec3(-0.45, 0.35, 0.82));
  float sky = normal.z < -0.5 ? 0.0 : normal.z > 0.5 ? 1.0 : 0.5;
  float direct = max(dot(normal, sun), 0.0) * visibility;
  return base * (vec3(0.17, 0.20, 0.27) + sky * vec3(0.23, 0.24, 0.21)
                 + direct * vec3(0.88, 0.76, 0.61));
}
#endif
