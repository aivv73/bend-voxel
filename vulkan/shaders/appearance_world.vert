#version 450
#extension GL_GOOGLE_include_directive : require
#include "appearance_frame.glsl"
layout(location=0) in vec3 position;
layout(location=1) in vec4 rgbDirection;
layout(location=2) in vec4 materialBytes;
layout(location=3) in vec3 owningAnchor;
layout(location=4) in vec2 rectangleExtent;
layout(location=0) flat out vec3 legacyColor;
layout(location=1) flat out uvec4 material;
layout(location=2) flat out uint direction;
layout(location=3) flat out vec3 anchor;
layout(location=4) flat out vec2 extent;
void main() {
  gl_Position = frame.camera_clip * vec4(position, 1.0);
  legacyColor = rgbDirection.rgb;
  material = uvec4(round(materialBytes * 255.0));
  direction = uint(round(rgbDirection.a * 255.0));
  anchor = owningAnchor;
  extent = rectangleExtent;
}
