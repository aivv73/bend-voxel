#version 450
layout(location = 0) in vec3 pixel_color;
layout(location = 0) out vec4 output_color;
// Vertex colors are display-encoded sRGB. A UNORM attachment stores them
// directly; an SRGB attachment encodes automatically, so decode first.
layout(constant_id = 0) const uint SRGB_ATTACHMENT = 0u;
vec3 srgb_to_linear(vec3 value) {
  vec3 low = value / 12.92;
  vec3 high = pow((value + 0.055) / 1.055, vec3(2.4));
  return mix(high, low, lessThanEqual(value, vec3(0.04045)));
}
void main() {
  output_color = vec4(SRGB_ATTACHMENT == 0u ? pixel_color : srgb_to_linear(pixel_color), 1.0);
}
