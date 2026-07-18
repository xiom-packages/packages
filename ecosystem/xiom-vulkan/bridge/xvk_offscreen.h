#ifndef XVK_OFFSCREEN_H_
#define XVK_OFFSCREEN_H_

#include <stdint.h>
#include "xvk_types.h"
#include "xvk_util.h"

int create_offscreen_rendertarget(XvkApp* a);
VkRenderPass create_offscreen_render_pass(VkDevice dev, VkFormat fmt);
int64_t xvk_offscreen_create(int32_t width, int32_t height);
int32_t xvk_offscreen_render_triangle(int64_t app_h, float r, float g, float b);
uint32_t xvk_offscreen_pixel(int64_t app_h, int32_t x, int32_t y);
uint64_t xvk_offscreen_hash(int64_t app_h);
void xvk_offscreen_destroy(int64_t app_h);

#endif
