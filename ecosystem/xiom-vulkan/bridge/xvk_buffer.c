#include "xvk_buffer.h"
#include <stdlib.h>
#include <string.h>

int64_t xvk_buffer_create(int64_t app_h, int64_t size, int32_t usage, int32_t memory)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || size <= 0) return 0;

    XvkBuffer* b = (XvkBuffer*)calloc(1, sizeof(XvkBuffer));
    if (!b) { xvk_set_error("calloc buffer"); return 0; }

    VkBufferCreateInfo bci = {0};
    bci.sType       = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bci.size        = (VkDeviceSize)size;
    bci.usage       = xvk_map_buffer_usage(usage);
    bci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    VkResult res = vkCreateBuffer(a->device, &bci, NULL, &b->buffer);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateBuffer: %d", (int)res);
        free(b); return 0;
    }

    VkMemoryRequirements mr;
    vkGetBufferMemoryRequirements(a->device, b->buffer, &mr);
    VkMemoryPropertyFlags props = xvk_map_memory_props(memory);
    uint32_t mi = find_memory_type(&a->mem_props, mr.memoryTypeBits, props);
    if (mi == UINT32_MAX) {
        xvk_set_error("no suitable memory type for buffer");
        vkDestroyBuffer(a->device, b->buffer, NULL); free(b); return 0;
    }

    VkMemoryAllocateInfo mai = {0};
    mai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    mai.allocationSize  = mr.size;
    mai.memoryTypeIndex = mi;
    res = vkAllocateMemory(a->device, &mai, NULL, &b->memory);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkAllocateMemory(buf): %d", (int)res);
        vkDestroyBuffer(a->device, b->buffer, NULL); free(b); return 0;
    }
    vkBindBufferMemory(a->device, b->buffer, b->memory, 0);

    b->size  = (VkDeviceSize)size;
    b->magic = XVK_BUFFER_MAGIC;
    return xvk_buffer_to_handle(b);
}

void xvk_buffer_destroy(int64_t app_h, int64_t buf_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkBuffer* b = xvk_buffer_from_handle(buf_h);
    if (!a || !b) return;
    if (b->mapped && b->mapped_ptr) vkUnmapMemory(a->device, b->memory);
    if (b->buffer)  vkDestroyBuffer(a->device, b->buffer, NULL);
    if (b->memory)  vkFreeMemory(a->device, b->memory, NULL);
    b->magic = 0;
    free(b);
}

int64_t xvk_buffer_size(int64_t app_h, int64_t buf_h)
{
    XvkBuffer* b = xvk_buffer_from_handle(buf_h);
    (void)app_h;
    return b ? (int64_t)b->size : 0;
}

int64_t xvk_buffer_map(int64_t app_h, int64_t buf_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkBuffer* b = xvk_buffer_from_handle(buf_h);
    if (!a || !b) return 0;
    if (b->mapped) return 1;
    VkResult res = vkMapMemory(a->device, b->memory, 0, b->size, 0, &b->mapped_ptr);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkMapMemory: %d", (int)res);
        return 0;
    }
    b->mapped = 1;
    return 1;
}

void xvk_buffer_unmap(int64_t app_h, int64_t buf_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkBuffer* b = xvk_buffer_from_handle(buf_h);
    if (!a || !b || !b->mapped) return;
    vkUnmapMemory(a->device, b->memory);
    b->mapped = 0;
    b->mapped_ptr = NULL;
}

void xvk_buffer_write(int64_t app_h, int64_t buf_h, int64_t offset,
                       const void* data, int64_t data_size)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkBuffer* b = xvk_buffer_from_handle(buf_h);
    if (!a || !b || !b->mapped_ptr) return;
    if (offset + data_size > (int64_t)b->size) return;
    memcpy((char*)b->mapped_ptr + offset, data, (size_t)data_size);
}

void xvk_buffer_read(int64_t app_h, int64_t buf_h, int64_t offset,
                      void* out, int64_t out_size)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkBuffer* b = xvk_buffer_from_handle(buf_h);
    if (!a || !b || !b->mapped_ptr) return;
    if (offset + out_size > (int64_t)b->size) return;
    memcpy(out, (char*)b->mapped_ptr + offset, (size_t)out_size);
}

int64_t xvk_image_create_2d(int64_t app_h, int32_t width, int32_t height,
                             int32_t format, int32_t usage, int32_t mip_levels)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || width <= 0 || height <= 0) return 0;

    XvkImage* img = (XvkImage*)calloc(1, sizeof(XvkImage));
    if (!img) { xvk_set_error("calloc image"); return 0; }

    VkImageCreateInfo ici = {0};
    ici.sType         = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    ici.imageType     = VK_IMAGE_TYPE_2D;
    ici.format        = xvk_map_format(format);
    ici.extent.width  = (uint32_t)width;
    ici.extent.height = (uint32_t)height;
    ici.extent.depth  = 1;
    ici.mipLevels     = (uint32_t)(mip_levels > 0 ? mip_levels : 1);
    ici.arrayLayers   = 1;
    ici.samples       = VK_SAMPLE_COUNT_1_BIT;
    ici.tiling        = VK_IMAGE_TILING_OPTIMAL;
    ici.usage         = xvk_map_image_usage(usage);
    ici.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

    VkResult res = vkCreateImage(a->device, &ici, NULL, &img->image);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateImage: %d", (int)res);
        free(img); return 0;
    }

    VkMemoryRequirements mr;
    vkGetImageMemoryRequirements(a->device, img->image, &mr);
    uint32_t mi = find_memory_type(&a->mem_props, mr.memoryTypeBits,
                                    VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (mi == UINT32_MAX) {
        xvk_set_error("no device-local memory for image");
        vkDestroyImage(a->device, img->image, NULL); free(img); return 0;
    }

    VkMemoryAllocateInfo mai = {0};
    mai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    mai.allocationSize  = mr.size;
    mai.memoryTypeIndex = mi;
    res = vkAllocateMemory(a->device, &mai, NULL, &img->memory);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkAllocateMemory(img): %d", (int)res);
        vkDestroyImage(a->device, img->image, NULL); free(img); return 0;
    }
    vkBindImageMemory(a->device, img->image, img->memory, 0);

    img->format     = xvk_map_format(format);
    img->extent.width  = (uint32_t)width;
    img->extent.height = (uint32_t)height;
    img->mip_levels = (uint32_t)(mip_levels > 0 ? mip_levels : 1);
    img->magic      = XVK_IMAGE_MAGIC;
    return xvk_image_to_handle(img);
}

void xvk_image_destroy(int64_t app_h, int64_t img_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkImage* img = xvk_image_from_handle(img_h);
    if (!a || !img) return;
    if (img->image)  vkDestroyImage(a->device, img->image, NULL);
    if (img->memory) vkFreeMemory(a->device, img->memory, NULL);
    img->magic = 0;
    free(img);
}

int64_t xvk_image_view_create(int64_t app_h, int64_t img_h, int32_t format, int32_t aspect)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkImage* img = xvk_image_from_handle(img_h);
    if (!a || !img) return 0;

    XvkImageView* v = (XvkImageView*)calloc(1, sizeof(XvkImageView));
    if (!v) { xvk_set_error("calloc view"); return 0; }

    VkImageViewCreateInfo ivci = {0};
    ivci.sType    = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    ivci.image    = img->image;
    ivci.viewType = VK_IMAGE_VIEW_TYPE_2D;
    ivci.format   = (format > 0) ? xvk_map_format(format) : img->format;
    ivci.subresourceRange.aspectMask     = xvk_map_aspect(aspect);
    ivci.subresourceRange.baseMipLevel   = 0;
    ivci.subresourceRange.levelCount     = img->mip_levels;
    ivci.subresourceRange.baseArrayLayer = 0;
    ivci.subresourceRange.layerCount     = 1;

    VkResult res = vkCreateImageView(a->device, &ivci, NULL, &v->view);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateImageView: %d", (int)res);
        free(v); return 0;
    }
    v->magic = XVK_IMAGEVIEW_MAGIC;
    return xvk_view_to_handle(v);
}

void xvk_image_view_destroy(int64_t app_h, int64_t view_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkImageView* v = xvk_view_from_handle(view_h);
    if (!a || !v) return;
    if (v->view) vkDestroyImageView(a->device, v->view, NULL);
    v->magic = 0;
    free(v);
}

int64_t xvk_sampler_create(int64_t app_h, int32_t filter, int32_t address_u,
                            int32_t address_v, int32_t mip_mode, float max_lod)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return 0;

    XvkSampler* s = (XvkSampler*)calloc(1, sizeof(XvkSampler));
    if (!s) { xvk_set_error("calloc sampler"); return 0; }

    VkSamplerCreateInfo sci = {0};
    sci.sType                   = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    sci.magFilter               = xvk_map_filter(filter);
    sci.minFilter               = xvk_map_filter(filter);
    sci.addressModeU            = xvk_map_address(address_u);
    sci.addressModeV            = xvk_map_address(address_v);
    sci.addressModeW            = xvk_map_address(address_u);
    sci.mipmapMode              = xvk_map_mip(mip_mode);
    sci.anisotropyEnable        = VK_FALSE;
    sci.maxAnisotropy           = 1.0f;
    sci.borderColor             = VK_BORDER_COLOR_FLOAT_OPAQUE_BLACK;
    sci.unnormalizedCoordinates = VK_FALSE;
    sci.compareEnable           = VK_FALSE;
    sci.compareOp               = VK_COMPARE_OP_ALWAYS;
    sci.minLod                  = 0.0f;
    sci.maxLod                  = max_lod > 0.0f ? max_lod : VK_LOD_CLAMP_NONE;
    sci.mipLodBias              = 0.0f;

    VkResult res = vkCreateSampler(a->device, &sci, NULL, &s->sampler);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateSampler: %d", (int)res);
        free(s); return 0;
    }
    s->magic = XVK_SAMPLER_MAGIC;
    return xvk_sampler_to_handle(s);
}

void xvk_sampler_destroy(int64_t app_h, int64_t sampler_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkSampler* s = xvk_sampler_from_handle(sampler_h);
    if (!a || !s) return;
    if (s->sampler) vkDestroySampler(a->device, s->sampler, NULL);
    s->magic = 0;
    free(s);
}
