#version 450
layout(location = 0) in vec3 position;

layout(push_constant) uniform Camera {
  vec4 eye_yaw;
  vec4 pitch_offset;
  mat4 shadow_matrix;
} pc;

void main() {
  vec3 world_position = position + vec3(0.0, pc.pitch_offset.y, 0.0);
  gl_Position = pc.shadow_matrix * vec4(world_position, 1.0);
}
