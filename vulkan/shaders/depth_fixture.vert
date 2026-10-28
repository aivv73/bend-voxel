#version 450
void main() {
  const vec2 corners[6] = vec2[6](vec2(-1,-1), vec2(1,-1), vec2(1,1), vec2(1,1), vec2(-1,1), vec2(-1,-1));
  gl_Position = vec4(corners[gl_VertexIndex], 0.25, 1.0);
}
