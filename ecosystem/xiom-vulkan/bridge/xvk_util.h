#ifndef XVK_UTIL_H_
#define XVK_UTIL_H_

#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <vulkan/vulkan.h>

#include "xvk_types.h"

extern char g_xvk_error[512];

void xvk_set_error(const char* msg);
void xvk_set_error_fmt(const char* fmt, ...);

XvkApp* xvk_from_handle(int64_t h);
int64_t xvk_to_handle(XvkApp* a);

#define XVK_HANDLE_IMPL(T, magic_val, field)                                      \
    static T* xvk_##field##_from_handle(int64_t h) {                            \
        if (h == 0) return NULL;                                                \
        T* p = (T*)(intptr_t)(h);                                                 \
        if (p->magic != magic_val) return NULL;                                 \
        return p;                                                               \
    }                                                                           \
    static int64_t xvk_##field##_to_handle(T* p) {                              \
        return p ? (int64_t)(intptr_t)(p) : 0;                                    \
    }

XVK_HANDLE_IMPL(XvkBuffer,       XVK_BUFFER_MAGIC,       buffer)
XVK_HANDLE_IMPL(XvkImage,        XVK_IMAGE_MAGIC,        image)
XVK_HANDLE_IMPL(XvkImageView,    XVK_IMAGEVIEW_MAGIC,    view)
XVK_HANDLE_IMPL(XvkSampler,      XVK_SAMPLER_MAGIC,      sampler)
XVK_HANDLE_IMPL(XvkShaderModule, XVK_SHADER_MAGIC,       shader)
XVK_HANDLE_IMPL(XvkPipeline,     XVK_PIPELINE_MAGIC,     pipeline)
XVK_HANDLE_IMPL(XvkPipelineLayout, XVK_PLAYOUT_MAGIC,    playout)
XVK_HANDLE_IMPL(XvkDescSetLayout,  XVK_DESC_LAYOUT_MAGIC,  dslayout)
XVK_HANDLE_IMPL(XvkDescPool,  XVK_DESC_POOL_MAGIC,  descpool)
XVK_HANDLE_IMPL(XvkDescSet,   XVK_DESC_SET_MAGIC,   descset)
XVK_HANDLE_IMPL(XvkRenderPass,  XVK_RENDERPASS_MAGIC,  rp)
XVK_HANDLE_IMPL(XvkFramebuffer, XVK_FRAMEBUFFER_MAGIC, fb)

VkFormat xvk_map_format(int32_t f);
VkImageUsageFlags xvk_map_image_usage(int32_t u);
VkBufferUsageFlags xvk_map_buffer_usage(int32_t u);
VkMemoryPropertyFlags xvk_map_memory_props(int32_t m);
VkFilter xvk_map_filter(int32_t f);
VkSamplerAddressMode xvk_map_address(int32_t a);
VkSamplerMipmapMode xvk_map_mip(int32_t m);
VkPrimitiveTopology xvk_map_topology(int32_t t);
VkFormat xvk_map_vertex_format(int32_t f);
VkIndexType xvk_map_index_type(int32_t t);
VkDescriptorType xvk_map_desc_type(int32_t t);
VkShaderStageFlags xvk_map_stage_flags(int32_t s);
VkImageLayout xvk_map_image_layout(int32_t l);
VkImageAspectFlags xvk_map_aspect(int32_t a);

uint32_t find_memory_type(const VkPhysicalDeviceMemoryProperties* mp,
                           uint32_t type_filter,
                           VkMemoryPropertyFlags props);
int find_queue_families(VkPhysicalDevice pd, VkSurfaceKHR surface,
                         uint32_t* gfx, uint32_t* pres);
VkFormat find_depth_format(VkPhysicalDevice pd);

float xvk_pfrand(int idx, int offset);

#endif
