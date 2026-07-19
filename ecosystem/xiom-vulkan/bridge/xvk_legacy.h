#ifndef XVK_LEGACY_H_
#define XVK_LEGACY_H_

#include <stdint.h>
#include "xvk_types.h"
#include "xvk_util.h"

void xvk_draw_triangle_2d(int64_t app_h, float r, float g, float b);
void xvk_draw_cube_3d(int64_t app_h, float angle);
void xvk_draw_quad_2d(int64_t app_h, float cx, float cy,
                       float hw, float hh, float r, float g, float b);
void xvk_draw_cube_3d_at(int64_t app_h, float angle,
                          float px, float py, float pz, float scale);
int32_t xvk_particles_enable(int64_t app_h, int32_t count);
void xvk_draw_particles(int64_t app_h, float dt);
void xvk_draw_texture_quad(int64_t app_h, int64_t image_view, int64_t sampler,
                           float cx, float cy, float hw, float hh);
void xvk_draw_mesh_lit(int64_t app_h, int64_t mesh_h, float angle, float px, float py, float pz, float scale);

#endif
