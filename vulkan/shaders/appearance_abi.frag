#version 450
#extension GL_GOOGLE_include_directive : require
#include "appearance_frame.glsl"
#include "appearance_words.glsl"
layout(location=0) out vec4 outputColor;
void main() {
  uint word = appearance_frame_word(uint(gl_FragCoord.y) * 512u + uint(gl_FragCoord.x));
  outputColor = vec4(uvec4(word,word>>8u,word>>16u,word>>24u) & uvec4(255u)) / 255.0;
}
