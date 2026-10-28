#version 450
#extension GL_GOOGLE_include_directive : require
#include "appearance_common.glsl"
#include "appearance_pcf.glsl"
layout(location=0) flat in vec3 legacyColor;
layout(location=1) flat in uvec4 material;
layout(location=2) flat in uint direction;
layout(location=3) flat in vec3 anchor;
layout(location=4) flat in vec2 extent;
layout(location=0) out vec4 outputColor;
vec4 integerBytes(uint value) {
  return vec4(uvec4(value, value >> 8u, value >> 16u, value >> 24u) & uvec4(255u)) / 255.0;
}
void main() {
  if (frame.flags.z == 1u) { outputColor = appearance_raw(vec4(legacyColor, 1.0)); return; }
  if (frame.flags.z == 2u) { outputColor = appearance_raw(vec4(material) / 255.0); return; }
  if (frame.flags.z == 3u) { outputColor = appearance_raw(vec4(float(direction) / 255.0, 0, 0, 1)); return; }
  uvec3 cell;
  vec3 point;
  if (!appearance_cell(anchor, extent, direction, appearance_ray(gl_FragCoord.xy), cell, point)) discard;
  if (frame.flags.z >= 4u && frame.flags.z <= 6u) {
    outputColor = appearance_raw(integerBytes(cell[frame.flags.z - 4u])); return;
  }
  if (frame.flags.z == 7u) {
    outputColor = appearance_raw(vec4(appearance_selected(cell) ? 1.0 : 0.0, 0, 0, 1)); return;
  }
  uint id = material.x | (material.y << 8u) | (material.z << 16u) | (material.w << 24u);
  vec3 normal = appearance_normal(direction);
  vec3 lit = vec3(1, 0, 1);
  if (id >= 1u && id <= 5u) {
    lit = appearance_day(frame.palette[id - 1u].rgb, normal, appearance_visibility(point, normal));
  }
  if (appearance_selected(cell)) lit = vec3(1, 1, 0);
  outputColor = appearance_finish(lit);
}
