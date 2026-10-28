layout(set=1, binding=0) uniform sampler2D appearance_shadow_map;
float appearance_visibility(vec3 point, vec3 normal) {
  if (dot(normal, normalize(vec3(-0.45, 0.35, 0.82))) <= 0.0) return 1.0;
  float resolution = frame.shadow_params.x;
  float span = frame.shadow_params.y;
  float inverseDepth = frame.shadow_params.z;
  vec3 right = vec3(frame.light_clip[0][0], frame.light_clip[1][0], frame.light_clip[2][0]) * (span * 0.5);
  vec3 up = vec3(frame.light_clip[0][1], frame.light_clip[1][1], frame.light_clip[2][1]) * (-span * 0.5);
  vec3 forward = vec3(frame.light_clip[0][2], frame.light_clip[1][2], frame.light_clip[2][2]) / inverseDepth;
  vec3 localNormal = vec3(dot(normal, right), dot(normal, up), dot(normal, forward));
  float nz = localNormal.z < 0.0 ? -max(abs(localNormal.z), 1e-6) : max(abs(localNormal.z), 1e-6);
  vec2 slope = vec2(-localNormal.x / nz, localNormal.y / nz) * (span / resolution);
  vec3 clip = (frame.light_clip * vec4(point, 1.0)).xyz;
  if (clip.z < 0.0 || clip.z > 1.0) return 1.0;
  vec2 uv = (clip.xy * 0.5 + 0.5) * resolution;
  ivec2 base = ivec2(floor(uv));
  float lit = 0.0;
  for (int y = -1; y <= 1; ++y) {
    for (int x = -1; x <= 1; ++x) {
      ivec2 tap = base + ivec2(x, y);
      if (any(lessThan(tap, ivec2(0))) || any(greaterThanEqual(tap, ivec2(resolution)))) {
        lit += 1.0;
      } else {
        vec2 delta = vec2(tap) + 0.5 - uv;
        float receiver = clip.z + (dot(slope, delta) - frame.shadow_params.w) * inverseDepth;
        float stored = textureLod(appearance_shadow_map, (vec2(tap) + 0.5) / resolution, 0.0).r;
        lit += receiver <= stored ? 1.0 : 0.0;
      }
    }
  }
  return lit / 9.0;
}
