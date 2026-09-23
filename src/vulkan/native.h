#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  uint32_t index, side, length, rows, owner;
  float offset;
} VoxelVkFace;

typedef struct {
  float eye[3], yaw, pitch, aim[3];
  uint32_t aim_kind, face_count;
  const VoxelVkFace* faces;
  const char* hud;
} VoxelVkFrame;

int voxel_vk_render(void* display, unsigned long window, const VoxelVkFrame* frame,
                    char* error, size_t error_cap);
void voxel_vk_release(void);

#ifdef __cplusplus
}
#endif
