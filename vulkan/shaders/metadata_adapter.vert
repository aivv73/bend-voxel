#version 450
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
  const vec2 corners[6] = vec2[6](vec2(-1,-1), vec2(1,-1), vec2(1,1), vec2(1,1), vec2(-1,1), vec2(-1,-1));
  gl_Position = vec4(corners[gl_VertexIndex], 0.5, 1.0);
  legacyColor = rgbDirection.rgb;
  material = uvec4(round(materialBytes * 255.0));
  direction = uint(round(rgbDirection.a * 255.0));
  anchor = owningAnchor;
  extent = rectangleExtent;
}
