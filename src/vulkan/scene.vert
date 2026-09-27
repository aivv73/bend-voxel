#version 450
layout(location = 0) in vec3 position;
layout(location = 1) in vec3 color;
layout(location = 2) in uint side;
layout(location = 0) out vec3 pixel_color;
layout(location = 1) out vec3 world_position;
layout(location = 2) flat out uint face_side;
layout(location = 3) out vec3 shadow_coord;

layout(push_constant) uniform Camera {
  vec4 eye_yaw;
  vec4 pitch_offset;
  mat4 shadow_matrix;
} pc;

void main() {
  if (pc.pitch_offset.z > 0.5) {
    gl_Position = vec4(position.x / 320.0 - 1.0, position.y / 180.0 - 1.0, 0.0, 1.0);
    pixel_color = color;
    world_position = vec3(0.0);
    face_side = side;
    shadow_coord = vec3(0.0);
    return;
  }
  float yaw = pc.eye_yaw.w;
  float pitch = pc.pitch_offset.x;
  float sy = sin(yaw), cy = cos(yaw);
  float sp = sin(pitch), cp = cos(pitch);
  vec3 right = vec3(-cy, 0.0, sy);
  vec3 up = vec3(-sy * sp, cp, -cy * sp);
  vec3 forward = vec3(sy * cp, sp, cy * cp);
  world_position = position + vec3(0.0, pc.pitch_offset.y, 0.0);
  vec4 light_clip = pc.shadow_matrix * vec4(world_position, 1.0);
  shadow_coord = light_clip.xyz / light_clip.w;
  vec3 delta = world_position - pc.eye_yaw.xyz;
  float x = dot(delta, right);
  float y = dot(delta, up);
  float z = dot(delta, forward);
  gl_Position = vec4(1.25 * x, -(400.0 / 180.0) * y, z - 0.05, z);
  pixel_color = color;
  face_side = side;
}
