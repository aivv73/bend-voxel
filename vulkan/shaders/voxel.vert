#version 450
layout(location=0) in vec3 position;
layout(location=1) in vec4 rgbDirection;
layout(location=2) in vec4 materialBytes;
layout(push_constant) uniform Camera { mat4 camera; } pc;
layout(location=0) flat out vec3 color;
layout(location=1) flat out uvec4 material;
layout(location=2) flat out uint direction;
void main() {
  gl_Position = pc.camera * vec4(position, 1.0);
  color = rgbDirection.rgb;
  direction = uint(round(rgbDirection.a * 255.0));
  material = uvec4(round(materialBytes * 255.0));
}
