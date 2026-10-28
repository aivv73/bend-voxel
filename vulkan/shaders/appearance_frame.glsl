layout(std140, set=0, binding=0) uniform AppearanceFrame {
  mat4 camera_clip;
  mat4 light_clip;
  vec4 eye_near;
  vec4 camera_right;
  vec4 camera_up;
  vec4 camera_forward_focal;
  vec4 viewport;
  vec4 brush_cm;
  uvec4 flags;
  vec4 palette[5];
  vec4 shadow_params;
  uvec4 selected[125];
} frame;
