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
  float position[3];
  uint32_t side, material;
} VoxelVkVertex;

typedef struct {
  uint32_t id, revision, anchored, face_count;
  float offset, lo[3], hi[3];
  const VoxelVkFace* faces;
  uint32_t vertex_count;
  const VoxelVkVertex* vertices;
} VoxelVkBody;

typedef struct {
  float eye[3], yaw, pitch, aim[3];
  uint32_t aim_kind, body_count, night, width, height;
  const VoxelVkBody* bodies;
  const char* hud;
  float colors[19][3]; // Material pairs, linear surfaces, display overlays.
  // Additive explicit profile; zero retains the Light Atelier defaults.
  unsigned full_geometry;
  float ground_half_extent;
  void (*record)(const char* fields); // Megascene CPU evidence, NULL for legacy.
  uint64_t evidence_frame;
  unsigned gpu_evidence; // Only the versioned timing ABI reads these fields.
} VoxelVkFrame;

// Checkpoint-only ABI: independently read tree leaves and current Bend geometry.
typedef struct { float lo[3], hi[3]; uint32_t material; } VoxelMegaBox;
typedef struct {
  float speed;
  uint32_t box_count;
  const VoxelMegaBox* boxes;
  uint64_t tree_nodes;
} VoxelMegaBody;
typedef struct {
  const VoxelMegaBody* bodies;
  uint32_t world[6]; // cells, fragments, removed, status, next ID, budget
  float aim_radius;
  uint64_t frame;
  uint32_t warmup, measured;
  const char* schedule_sha256;
  const char* action_outcomes; // Canonical action history, including no-ops/rejections.
  unsigned action_frame;
  unsigned action_id;
} VoxelMegaState;

typedef struct {
  uint32_t geometry_us, fence_wait_us, vertex_upload_us, acquire_us;
  uint32_t command_record_us, submit_present_us;
} VoxelVkTimings;

int voxel_vk_render(void* display, unsigned long window, const VoxelVkFrame* frame,
                    VoxelVkTimings* timings, char* error, size_t error_cap);
int voxel_vk_render_profile(void* display, unsigned long window, const VoxelVkFrame* frame,
                            VoxelVkTimings* timings, char* error, size_t error_cap);
int voxel_vk_render_timed(void* display, unsigned long window, const VoxelVkFrame* frame,
                         VoxelVkTimings* timings, char* error, size_t error_cap);
void voxel_vk_release(void);

#ifdef __cplusplus
}
#endif
