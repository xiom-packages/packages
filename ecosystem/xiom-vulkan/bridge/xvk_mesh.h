#ifndef XVK_MESH_H_
#define XVK_MESH_H_

#include <stdint.h>

/* Simple OBJ mesh loader. Extracts positions + normals, computes
 * flat normals. Returns a mesh handle with uploaded vertex/index buffers. */

/* Load an OBJ file, upload to GPU vertex + index buffers.
 * device/phys_dev: VK handles for buffer allocation.
 * Returns mesh handle (> 0) or 0 on failure. */
int64_t xvk_mesh_load(int64_t device, int64_t phys_dev,
                       const char* filepath);

/* Get vertex count, index count, vertex buffer, index buffer. */
int32_t xvk_mesh_vertex_count(int64_t mesh);
int32_t xvk_mesh_index_count(int64_t mesh);
int64_t xvk_mesh_vertex_buffer(int64_t mesh);
int64_t xvk_mesh_index_buffer(int64_t mesh);

/* Draw the mesh using the current pipeline. */
void xvk_mesh_draw(int64_t app_h, int64_t mesh);

/* Destroy mesh and free GPU resources. */
void xvk_mesh_destroy(int64_t device, int64_t mesh);

#endif
