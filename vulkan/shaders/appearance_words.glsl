uint appearance_frame_word(uint i) {
  if (i >= 0u && i < 16u) {
    uint j = i - 0u;
    return floatBitsToUint(frame.camera_clip[j / 4u][j % 4u]);
  }
  if (i >= 16u && i < 32u) {
    uint j = i - 16u;
    return floatBitsToUint(frame.light_clip[j / 4u][j % 4u]);
  }
  if (i >= 32u && i < 36u) {
    uint j = i - 32u;
    return floatBitsToUint(frame.eye_near[j]);
  }
  if (i >= 36u && i < 40u) {
    uint j = i - 36u;
    return floatBitsToUint(frame.camera_right[j]);
  }
  if (i >= 40u && i < 44u) {
    uint j = i - 40u;
    return floatBitsToUint(frame.camera_up[j]);
  }
  if (i >= 44u && i < 48u) {
    uint j = i - 44u;
    return floatBitsToUint(frame.camera_forward_focal[j]);
  }
  if (i >= 48u && i < 52u) {
    uint j = i - 48u;
    return floatBitsToUint(frame.viewport[j]);
  }
  if (i >= 52u && i < 56u) {
    uint j = i - 52u;
    return floatBitsToUint(frame.brush_cm[j]);
  }
  if (i >= 56u && i < 60u) {
    uint j = i - 56u;
    return frame.flags[j];
  }
  if (i >= 60u && i < 80u) {
    uint j = i - 60u;
    return floatBitsToUint(frame.palette[j / 4u][j % 4u]);
  }
  if (i >= 80u && i < 84u) {
    uint j = i - 80u;
    return floatBitsToUint(frame.shadow_params[j]);
  }
  if (i >= 84u && i < 584u) {
    uint j = i - 84u;
    return frame.selected[j / 4u][j % 4u];
  }
  return 0u;
}
