#version 450
layout(location=0) flat in vec3 color;
layout(location=1) flat in uvec4 material;
layout(location=2) flat in uint direction;
layout(location=0) out vec4 outputColor;
void main() { outputColor = vec4(float(direction) / 255.0, 0.0, 0.0, 1.0); }
