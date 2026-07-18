#include "xvk_util.h"
#include <stdlib.h>

char g_xvk_error[512] = "";

void xvk_set_error(const char* msg)
{
    strncpy(g_xvk_error, msg, sizeof(g_xvk_error) - 1);
    g_xvk_error[sizeof(g_xvk_error) - 1] = '\0';
}

void xvk_set_error_fmt(const char* fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    vsnprintf(g_xvk_error, sizeof(g_xvk_error), fmt, args);
    va_end(args);
    g_xvk_error[sizeof(g_xvk_error) - 1] = '\0';
}

XvkApp* xvk_from_handle(int64_t h)
{
    if (h == 0) return NULL;
    XvkApp* a = (XvkApp*)(intptr_t)h;
    if (a->magic != XVK_MAGIC) return NULL;
    return a;
}

int64_t xvk_to_handle(XvkApp* a)
{
    return (int64_t)(intptr_t)a;
}

VkFormat xvk_map_format(int32_t f) {
    switch (f) {
        case 1: return VK_FORMAT_R8G8B8A8_UNORM;
        case 2: return VK_FORMAT_R8G8B8A8_SRGB;
        case 3: return VK_FORMAT_R32G32B32A32_SFLOAT;
        case 4: return VK_FORMAT_R32_SFLOAT;
        case 5: return VK_FORMAT_D32_SFLOAT;
        default: return VK_FORMAT_R8G8B8A8_UNORM;
    }
}

VkImageUsageFlags xvk_map_image_usage(int32_t u) {
    VkImageUsageFlags f = 0;
    if (u & 1)  f |= VK_IMAGE_USAGE_SAMPLED_BIT;
    if (u & 2)  f |= VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    if (u & 4)  f |= VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
    if (u & 8)  f |= VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    if (u & 16) f |= VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    if (u & 32) f |= VK_IMAGE_USAGE_STORAGE_BIT;
    return f ? f : VK_IMAGE_USAGE_SAMPLED_BIT;
}

VkBufferUsageFlags xvk_map_buffer_usage(int32_t u) {
    VkBufferUsageFlags f = 0;
    if (u & 1) f |= VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
    if (u & 2) f |= VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
    if (u & 4) f |= VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
    if (u & 8) f |= VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
    if (u & 16) f |= VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    if (u & 32) f |= VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    return f ? f : VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
}

VkMemoryPropertyFlags xvk_map_memory_props(int32_t m) {
    if (m == 1) return VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
    if (m == 2) return VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    if (m == 3) return VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_CACHED_BIT;
    return VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
}

VkFilter xvk_map_filter(int32_t f) { return f == 1 ? VK_FILTER_LINEAR : VK_FILTER_NEAREST; }
VkSamplerAddressMode xvk_map_address(int32_t a) {
    if (a == 1) return VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    if (a == 2) return VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER;
    return VK_SAMPLER_ADDRESS_MODE_REPEAT;
}
VkSamplerMipmapMode xvk_map_mip(int32_t m) { return m == 1 ? VK_SAMPLER_MIPMAP_MODE_LINEAR : VK_SAMPLER_MIPMAP_MODE_NEAREST; }

VkPrimitiveTopology xvk_map_topology(int32_t t) {
    if (t == 1) return VK_PRIMITIVE_TOPOLOGY_POINT_LIST;
    if (t == 2) return VK_PRIMITIVE_TOPOLOGY_LINE_LIST;
    return VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
}

VkFormat xvk_map_vertex_format(int32_t f) {
    switch (f) {
        case 1: return VK_FORMAT_R32G32_SFLOAT;
        case 2: return VK_FORMAT_R32G32B32_SFLOAT;
        case 3: return VK_FORMAT_R32G32B32A32_SFLOAT;
        case 4: return VK_FORMAT_R8G8B8A8_UNORM;
        case 5: return VK_FORMAT_R32_SINT;
        default: return VK_FORMAT_R32G32B32A32_SFLOAT;
    }
}

VkIndexType xvk_map_index_type(int32_t t) {
    return t == 1 ? VK_INDEX_TYPE_UINT32 : VK_INDEX_TYPE_UINT16;
}

VkDescriptorType xvk_map_desc_type(int32_t t) {
    if (t == 1) return VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    if (t == 2) return VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    if (t == 3) return VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
    return VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
}

VkShaderStageFlags xvk_map_stage_flags(int32_t s) {
    VkShaderStageFlags f = 0;
    if (s & 1) f |= VK_SHADER_STAGE_VERTEX_BIT;
    if (s & 2) f |= VK_SHADER_STAGE_FRAGMENT_BIT;
    if (s & 4) f |= VK_SHADER_STAGE_COMPUTE_BIT;
    return f ? f : (VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT);
}

VkImageLayout xvk_map_image_layout(int32_t l) {
    switch (l) {
        case 1: return VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
        case 2: return VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        case 3: return VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        case 4: return VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        case 5: return VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
        case 6: return VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        default: return VK_IMAGE_LAYOUT_UNDEFINED;
    }
}

VkImageAspectFlags xvk_map_aspect(int32_t a) {
    if (a == 2) return VK_IMAGE_ASPECT_DEPTH_BIT;
    return VK_IMAGE_ASPECT_COLOR_BIT;
}

uint32_t find_memory_type(const VkPhysicalDeviceMemoryProperties* mp,
                           uint32_t type_filter,
                           VkMemoryPropertyFlags props)
{
    for (uint32_t i = 0; i < mp->memoryTypeCount; ++i) {
        if ((type_filter & (1u << i)) &&
            (mp->memoryTypes[i].propertyFlags & props) == props)
            return i;
    }
    return UINT32_MAX;
}

int find_queue_families(VkPhysicalDevice pd, VkSurfaceKHR surface,
                         uint32_t* gfx, uint32_t* pres)
{
    uint32_t n = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(pd, &n, NULL);
    VkQueueFamilyProperties* props = (VkQueueFamilyProperties*)
        malloc(n * sizeof(VkQueueFamilyProperties));
    if (!props) return 0;
    vkGetPhysicalDeviceQueueFamilyProperties(pd, &n, props);

    int found_gfx = 0, found_pres = 0;
    for (uint32_t i = 0; i < n; ++i) {
        if (!found_gfx && (props[i].queueFlags & VK_QUEUE_GRAPHICS_BIT)) {
            *gfx = i;
            found_gfx = 1;
        }
        if (!found_pres && surface != VK_NULL_HANDLE) {
            VkBool32 supp = VK_FALSE;
            vkGetPhysicalDeviceSurfaceSupportKHR(pd, i, surface, &supp);
            if (supp) {
                *pres = i;
                found_pres = 1;
            }
        }
        if (found_gfx && (found_pres || surface == VK_NULL_HANDLE)) break;
    }
    free(props);
    return found_gfx;
}

VkFormat find_depth_format(VkPhysicalDevice pd)
{
    VkFormat candidates[] = {
        VK_FORMAT_D32_SFLOAT,
        VK_FORMAT_D24_UNORM_S8_UINT,
        VK_FORMAT_D16_UNORM
    };
    for (int i = 0; i < 3; ++i) {
        VkFormatProperties p;
        vkGetPhysicalDeviceFormatProperties(pd, candidates[i], &p);
        if (p.optimalTilingFeatures & VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT)
            return candidates[i];
    }
    return VK_FORMAT_UNDEFINED;
}

float xvk_pfrand(int idx, int offset)
{
    uint32_t x = (uint32_t)(idx * 2654435761u + offset * 1013904223u);
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return (float)(x & 0x7FFF) / 32768.0f;
}
