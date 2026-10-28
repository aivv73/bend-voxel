#version 450
#extension GL_GOOGLE_include_directive : require
#include "appearance_frame.glsl"
layout(location=0) in vec3 position;
void main() { gl_Position = frame.light_clip * vec4(position, 1.0); }
