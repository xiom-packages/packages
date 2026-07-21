#ifndef XVK_RENDERPASS_H_
#define XVK_RENDERPASS_H_

#include "xvk_types.h"
#include "xvk_util.h"

VkRenderPass create_render_pass(VkDevice dev, VkFormat colour_fmt,
                                 VkFormat depth_fmt);
int create_framebuffers(XvkApp* a);

int64_t xvk_render_pass_create(int64_t app_h, const int32_t* color_formats,
                                int32_t color_count, int32_t depth_format);
void xvk_render_pass_destroy(int64_t app_h, int64_t rp_h);
int64_t xvk_framebuffer_create(int64_t app_h, int64_t render_pass_h,
                                const int64_t* attachments, int32_t attachment_count,
                                int32_t width, int32_t height);
void xvk_framebuffer_destroy(int64_t app_h, int64_t fb_h);

#endif
