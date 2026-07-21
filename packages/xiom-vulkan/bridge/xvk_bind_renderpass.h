#ifndef XVK_BIND_RENDERPASS_H_
#define XVK_BIND_RENDERPASS_H_

#include <stdint.h>

/* Direct Vulkan render pass / framebuffer bindings.
 * Handles are raw Vulkan handles as int64_t (0 = VK_NULL_HANDLE).
 * *_struct parameters are raw pointers (as int64_t) to fully-built Vulkan
 * structs produced by the xvk_structs marshalling layer. */

int64_t xvk_create_render_pass(int64_t device, int64_t create_info_struct);
void xvk_destroy_render_pass(int64_t device, int64_t render_pass);

int64_t xvk_create_framebuffer(int64_t device, int64_t create_info_struct);
void xvk_destroy_framebuffer(int64_t device, int64_t framebuffer);

#endif
