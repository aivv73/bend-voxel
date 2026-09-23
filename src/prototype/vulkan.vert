#version 450
layout(location = 0) in vec3 position;
layout(location = 1) in vec3 color;
layout(location = 0) out vec3 pixel_color;

layout(push_constant) uniform Camera {
  vec4 eye_yaw;
  vec4 pitch_offset;
} pc;

void main() {
  float yaw = pc.eye_yaw.w;
  float pitch = pc.pitch_offset.x;
  float sy = sin(yaw), cy = cos(yaw);
  float sp = sin(pitch), cp = cos(pitch);
  vec3 right = vec3(-cy, 0.0, sy);
  vec3 up = vec3(-sy * sp, cp, -cy * sp);
  vec3 forward = vec3(sy * cp, sp, cy * cp);
  vec3 delta = position + vec3(0.0, pc.pitch_offset.y, 0.0) - pc.eye_yaw.xyz;
  float x = dot(delta, right);
  float y = dot(delta, up);
  float z = dot(delta, forward);
  gl_Position = vec4(1.25 * x, -(400.0 / 180.0) * y, z - 0.05, z);
  pixel_color = color;
}
