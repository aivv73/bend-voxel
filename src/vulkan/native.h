#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  float lo[3], hi[3];  // Integer cell coordinates; zero thickness on side / 2.
  uint32_t side, material;
} VoxelVkFace;

typedef struct {
  uint32_t id, revision, anchored, face_count;
  float offset, lo[3], hi[3];
  const VoxelVkFace* faces;
} VoxelVkBody;

typedef struct {
  float eye[3], yaw, pitch, aim[3];
  uint32_t aim_kind, body_count;
  const VoxelVkBody* bodies;
  const char* hud;
} VoxelVkFrame;

typedef struct {
  uint32_t geometry_us, fence_wait_us, vertex_upload_us, acquire_us;
  uint32_t command_record_us, submit_present_us;
} VoxelVkTimings;

int voxel_vk_render(void* display, unsigned long window, const VoxelVkFrame* frame,
                    VoxelVkTimings* timings, char* error, size_t error_cap);
void voxel_vk_release(void);

#ifdef __cplusplus
}
#endif
