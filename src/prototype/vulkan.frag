#version 450
layout(location = 0) in vec3 pixel_color;
layout(location = 0) out vec4 output_color;
void main() {
  output_color = vec4(pixel_color, 1.0);
}
