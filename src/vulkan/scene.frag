#version 450
layout(location = 0) in vec3 pixel_color;
layout(location = 1) in vec3 world_position;
layout(location = 2) flat in uint face_side;
layout(location = 3) in vec3 shadow_coord;
layout(location = 0) out vec4 output_color;
layout(set = 0, binding = 0) uniform sampler2DShadow sun_shadow;
// World vertex colors are linear RGB; flat overlay colors are display-encoded sRGB.
layout(constant_id = 0) const uint SRGB_ATTACHMENT = 0u;
layout(push_constant) uniform Camera {
  vec4 eye_yaw;
  vec4 pitch_offset;
  mat4 shadow_matrix;
} pc;
vec3 srgb_to_linear(vec3 value) {
  vec3 low = value / 12.92;
  vec3 high = pow((value + 0.055) / 1.055, vec3(2.4));
  return mix(high, low, lessThanEqual(value, vec3(0.04045)));
}
vec3 linear_to_srgb(vec3 value) {
  value = clamp(value, 0.0, 1.0);
  vec3 low = value * 12.92;
  vec3 high = 1.055 * pow(value, vec3(1.0 / 2.4)) - 0.055;
  return mix(high, low, lessThanEqual(value, vec3(0.0031308)));
}
float sun_visibility(float sun) {
  vec2 uv = shadow_coord.xy * 0.5 + 0.5;
  if (shadow_coord.z <= 0.0 || shadow_coord.z >= 1.0 ||
      any(lessThanEqual(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0))))
    return 1.0;
  float bias = max(0.00012, 0.00045 * (1.0 - sun));
  float visibility = 0.0;
  for (int y = -1; y <= 1; ++y)
    for (int x = -1; x <= 1; ++x)
      visibility += texture(sun_shadow,
        vec3(uv + vec2(x, y) / 2048.0, shadow_coord.z - bias));
  return visibility / 9.0;
}
void main() {
  // Side 6 is unlit overlay geometry (HUD, cut preview, aim rings).
  if (face_side < 6u) {
    vec3 normal = vec3(0.0);
    normal[face_side / 2u] = (face_side & 1u) == 0u ? -1.0 : 1.0;
    float sky = normal.y * 0.5 + 0.5;
    vec3 ambient = mix(vec3(0.17, 0.20, 0.27), vec3(0.40, 0.44, 0.48), sky);
    float sun = max(dot(normal, vec3(-0.45, 0.82, 0.35)), 0.0);
    float visibility = sun > 0.0 ? sun_visibility(sun) : 1.0;
    vec3 to_eye = pc.eye_yaw.xyz - world_position;
    float distance2 = dot(to_eye, to_eye);
    float attenuation = 1.0 / (1.0 + distance2 / 100.0);
    attenuation *= attenuation;
    float work_light = max(dot(normal, to_eye * inversesqrt(max(distance2, 0.0001))), 0.0)
      * attenuation;
    bool night = pc.pitch_offset.w > 0.5;
    vec3 irradiance = night
      ? ambient * 0.23 + vec3(0.07, 0.11, 0.19) * sun * visibility
        + vec3(1.20, 1.07, 0.89) * work_light * 2.0
      : ambient + vec3(0.88, 0.76, 0.61) * sun * visibility
        + vec3(1.00, 0.94, 0.84) * work_light * 0.25;
    vec3 lit = pixel_color * irradiance;
    output_color = vec4(SRGB_ATTACHMENT == 0u ? linear_to_srgb(lit) : lit, 1.0);
  } else {
    output_color = vec4(SRGB_ATTACHMENT == 0u ? pixel_color : srgb_to_linear(pixel_color), 1.0);
  }
}
