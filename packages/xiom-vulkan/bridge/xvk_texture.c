#include "xvk_texture.h"

#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <vulkan/vulkan.h>

#include "xvk_util.h"  /* find_memory_type, xvk_set_error_fmt */

/* ---- Internal texture state ---- */
typedef struct {
    VkImage        image;
    VkImageView    image_view;
    VkSampler      sampler;
    VkDeviceMemory memory;
    int32_t        width;
    int32_t        height;
    int32_t        mip_levels;
    uint32_t       format;      /* VkFormat */
    uint32_t       aspect_mask; /* VkImageAspectFlags */
} XvkTexture;

static XvkTexture* tex_get(int64_t handle) {
    if (!handle) return NULL;
    return (XvkTexture*)(intptr_t)handle;
}

/* ---- Helper: create a VkImage for the texture ---- */
static VkImage create_gpu_image(VkDevice dev, uint32_t width, uint32_t height,
                                 uint32_t mip_levels, VkFormat format)
{
    VkImageCreateInfo ci = {0};
    ci.sType         = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    ci.imageType     = VK_IMAGE_TYPE_2D;
    ci.format        = format;
    ci.extent.width  = width;
    ci.extent.height = height;
    ci.extent.depth  = 1;
    ci.mipLevels     = mip_levels;
    ci.arrayLayers   = 1;
    ci.samples       = VK_SAMPLE_COUNT_1_BIT;
    ci.tiling        = VK_IMAGE_TILING_OPTIMAL;
    ci.usage         = VK_IMAGE_USAGE_TRANSFER_DST_BIT
                     | VK_IMAGE_USAGE_TRANSFER_SRC_BIT  /* needed for mipmap blits */
                     | VK_IMAGE_USAGE_SAMPLED_BIT;
    ci.sharingMode   = VK_SHARING_MODE_EXCLUSIVE;
    ci.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

    VkImage img = VK_NULL_HANDLE;
    VkResult res = vkCreateImage(dev, &ci, NULL, &img);
    if (res != VK_SUCCESS) return VK_NULL_HANDLE;
    return img;
}

/* ---- Helper: create VkImageView ---- */
static VkImageView create_image_view(VkDevice dev, VkImage img, VkFormat format,
                                      uint32_t aspect_mask, uint32_t mip_levels)
{
    VkImageViewCreateInfo ci = {0};
    ci.sType                           = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    ci.image                           = img;
    ci.viewType                        = VK_IMAGE_VIEW_TYPE_2D;
    ci.format                          = format;
    ci.subresourceRange.aspectMask     = aspect_mask;
    ci.subresourceRange.baseMipLevel   = 0;
    ci.subresourceRange.levelCount     = mip_levels;
    ci.subresourceRange.baseArrayLayer = 0;
    ci.subresourceRange.layerCount     = 1;

    VkImageView view = VK_NULL_HANDLE;
    VkResult res = vkCreateImageView(dev, &ci, NULL, &view);
    if (res != VK_SUCCESS) return VK_NULL_HANDLE;
    return view;
}

/* ---- Helper: create default linear sampler ---- */
static VkSampler create_default_sampler(VkDevice dev, float max_lod)
{
    VkSamplerCreateInfo ci = {0};
    ci.sType                   = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    ci.magFilter               = VK_FILTER_LINEAR;
    ci.minFilter               = VK_FILTER_LINEAR;
    ci.mipmapMode              = VK_SAMPLER_MIPMAP_MODE_LINEAR;
    ci.addressModeU            = VK_SAMPLER_ADDRESS_MODE_REPEAT;
    ci.addressModeV            = VK_SAMPLER_ADDRESS_MODE_REPEAT;
    ci.addressModeW            = VK_SAMPLER_ADDRESS_MODE_REPEAT;
    ci.mipLodBias              = 0.0f;
    ci.anisotropyEnable        = VK_FALSE;
    ci.maxAnisotropy           = 1.0f;
    ci.compareEnable           = VK_FALSE;
    ci.compareOp               = VK_COMPARE_OP_ALWAYS;
    ci.minLod                  = 0.0f;
    ci.maxLod                  = max_lod;
    ci.borderColor             = VK_BORDER_COLOR_FLOAT_OPAQUE_BLACK;
    ci.unnormalizedCoordinates = VK_FALSE;

    VkSampler sampler = VK_NULL_HANDLE;
    VkResult res = vkCreateSampler(dev, &ci, NULL, &sampler);
    if (res != VK_SUCCESS) return VK_NULL_HANDLE;
    return sampler;
}

/* ---- Helper: pipeline barrier for image layout transition ---- */
static void transition_layout(VkCommandBuffer cb, VkImage img,
                               VkImageLayout old_layout, VkImageLayout new_layout,
                               uint32_t mip_level, uint32_t mip_count,
                               VkAccessFlags src_access, VkAccessFlags dst_access,
                               VkPipelineStageFlags src_stage, VkPipelineStageFlags dst_stage)
{
    VkImageMemoryBarrier barrier = {0};
    barrier.sType                           = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.oldLayout                       = old_layout;
    barrier.newLayout                       = new_layout;
    barrier.srcQueueFamilyIndex             = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex             = VK_QUEUE_FAMILY_IGNORED;
    barrier.image                           = img;
    barrier.subresourceRange.aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT;
    barrier.subresourceRange.baseMipLevel   = mip_level;
    barrier.subresourceRange.levelCount     = mip_count;
    barrier.subresourceRange.baseArrayLayer = 0;
    barrier.subresourceRange.layerCount     = 1;
    barrier.srcAccessMask                   = src_access;
    barrier.dstAccessMask                   = dst_access;

    vkCmdPipelineBarrier(cb, src_stage, dst_stage, 0,
                         0, NULL, 0, NULL, 1, &barrier);
}

/* ---- Helper: generate mipmaps via blit ---- */
static void generate_mipmaps(VkCommandBuffer cb, VkImage img,
                              uint32_t width, uint32_t height, uint32_t mip_levels)
{
    int32_t mip_w = (int32_t)width;
    int32_t mip_h = (int32_t)height;

    for (uint32_t i = 1; i < mip_levels; i++) {
        /* Transition mip i-1 from TRANSFER_DST to TRANSFER_SRC */
        VkImageMemoryBarrier barrier = {0};
        barrier.sType                           = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barrier.srcAccessMask                   = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask                   = VK_ACCESS_TRANSFER_READ_BIT;
        barrier.oldLayout                       = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.newLayout                       = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        barrier.srcQueueFamilyIndex             = VK_QUEUE_FAMILY_IGNORED;
        barrier.dstQueueFamilyIndex             = VK_QUEUE_FAMILY_IGNORED;
        barrier.image                           = img;
        barrier.subresourceRange.aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT;
        barrier.subresourceRange.baseMipLevel   = i - 1;
        barrier.subresourceRange.levelCount     = 1;
        barrier.subresourceRange.baseArrayLayer = 0;
        barrier.subresourceRange.layerCount     = 1;
        vkCmdPipelineBarrier(cb,
            VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
            0, 0, NULL, 0, NULL, 1, &barrier);

        /* Blit mip i-1 -> mip i */
        VkImageBlit blit = {0};
        blit.srcSubresource.aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT;
        blit.srcSubresource.mipLevel       = i - 1;
        blit.srcSubresource.baseArrayLayer = 0;
        blit.srcSubresource.layerCount     = 1;
        blit.srcOffsets[0] = (VkOffset3D){0, 0, 0};
        blit.srcOffsets[1] = (VkOffset3D){mip_w, mip_h, 1};
        blit.dstSubresource.aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT;
        blit.dstSubresource.mipLevel       = i;
        blit.dstSubresource.baseArrayLayer = 0;
        blit.dstSubresource.layerCount     = 1;
        blit.dstOffsets[0] = (VkOffset3D){0, 0, 0};
        int32_t next_w = mip_w > 1 ? mip_w / 2 : 1;
        int32_t next_h = mip_h > 1 ? mip_h / 2 : 1;
        blit.dstOffsets[1] = (VkOffset3D){next_w, next_h, 1};

        vkCmdBlitImage(cb, img, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                       img, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                       1, &blit, VK_FILTER_LINEAR);

        /* Transition mip i-1 to SHADER_READ_ONLY */
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        barrier.oldLayout     = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        barrier.newLayout     = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        vkCmdPipelineBarrier(cb,
            VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
            0, 0, NULL, 0, NULL, 1, &barrier);

        mip_w = next_w;
        mip_h = next_h;
    }

    /* Transition the last mip (mip_levels-1) from TRANSFER_DST to SHADER_READ_ONLY */
    VkImageMemoryBarrier final_barrier = {0};
    final_barrier.sType                           = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    final_barrier.srcAccessMask                   = VK_ACCESS_TRANSFER_WRITE_BIT;
    final_barrier.dstAccessMask                   = VK_ACCESS_SHADER_READ_BIT;
    final_barrier.oldLayout                       = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    final_barrier.newLayout                       = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    final_barrier.srcQueueFamilyIndex             = VK_QUEUE_FAMILY_IGNORED;
    final_barrier.dstQueueFamilyIndex             = VK_QUEUE_FAMILY_IGNORED;
    final_barrier.image                           = img;
    final_barrier.subresourceRange.aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT;
    final_barrier.subresourceRange.baseMipLevel   = mip_levels - 1;
    final_barrier.subresourceRange.levelCount     = 1;
    final_barrier.subresourceRange.baseArrayLayer = 0;
    final_barrier.subresourceRange.layerCount     = 1;
    vkCmdPipelineBarrier(cb,
        VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
        0, 0, NULL, 0, NULL, 1, &final_barrier);
}

/* ======================================================================== */
/* PUBLIC API                                                               */
/* ======================================================================== */

int64_t xvk_texture_create(int64_t device, int64_t physical_device,
                           int64_t cmd_pool, int64_t queue,
                           int64_t pixel_data,
                           int32_t width, int32_t height,
                           int32_t generate_mips)
{
    VkDevice       dev      = (VkDevice)(intptr_t)device;
    VkPhysicalDevice phys_dev = (VkPhysicalDevice)(intptr_t)physical_device;
    VkCommandPool  pool     = (VkCommandPool)(intptr_t)cmd_pool;
    VkQueue        q        = (VkQueue)(intptr_t)queue;
    const void*    pixels   = (const void*)(intptr_t)pixel_data;

    if (!dev || !phys_dev || !pool || !q || !pixels || width <= 0 || height <= 0) {
        return 0;
    }

    VkFormat format = VK_FORMAT_R8G8B8A8_UNORM;
    VkDeviceSize image_size = (VkDeviceSize)width * (VkDeviceSize)height * 4;
    uint32_t mip_levels = generate_mips
        ? (uint32_t)(floorf(log2f((float)(width > height ? width : height))) + 1)
        : 1;

    /* 1. Allocate and populate staging buffer */
    VkBuffer staging_buf = VK_NULL_HANDLE;
    VkDeviceMemory staging_mem = VK_NULL_HANDLE;
    {
        VkBufferCreateInfo bci = {0};
        bci.sType       = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
        bci.size        = image_size;
        bci.usage       = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
        bci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

        if (vkCreateBuffer(dev, &bci, NULL, &staging_buf) != VK_SUCCESS) goto fail_staging;

        VkMemoryRequirements mem_reqs;
        vkGetBufferMemoryRequirements(dev, staging_buf, &mem_reqs);

        VkPhysicalDeviceMemoryProperties mem_props;
        vkGetPhysicalDeviceMemoryProperties(phys_dev, &mem_props);

        VkMemoryAllocateInfo mai = {0};
        mai.sType           = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        mai.allocationSize  = mem_reqs.size;
        mai.memoryTypeIndex = find_memory_type(&mem_props, mem_reqs.memoryTypeBits,
            VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);

        if (vkAllocateMemory(dev, &mai, NULL, &staging_mem) != VK_SUCCESS) goto fail_staging;
        if (vkBindBufferMemory(dev, staging_buf, staging_mem, 0) != VK_SUCCESS) goto fail_staging;

        void* mapped = NULL;
        if (vkMapMemory(dev, staging_mem, 0, image_size, 0, &mapped) != VK_SUCCESS) goto fail_staging;
        memcpy(mapped, pixels, (size_t)image_size);
        vkUnmapMemory(dev, staging_mem);
    }

    /* 2. Create GPU image */
    VkImage gpu_image = VK_NULL_HANDLE;
    VkDeviceMemory gpu_mem = VK_NULL_HANDLE;
    {
        gpu_image = create_gpu_image(dev, (uint32_t)width, (uint32_t)height,
                                      mip_levels, format);
        if (gpu_image == VK_NULL_HANDLE) goto fail_gpu;

        VkMemoryRequirements mem_reqs;
        vkGetImageMemoryRequirements(dev, gpu_image, &mem_reqs);

        VkPhysicalDeviceMemoryProperties mem_props;
        vkGetPhysicalDeviceMemoryProperties(phys_dev, &mem_props);

        VkMemoryAllocateInfo mai = {0};
        mai.sType           = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        mai.allocationSize  = mem_reqs.size;
        mai.memoryTypeIndex = find_memory_type(&mem_props, mem_reqs.memoryTypeBits,
            VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

        if (vkAllocateMemory(dev, &mai, NULL, &gpu_mem) != VK_SUCCESS) goto fail_gpu;
        if (vkBindImageMemory(dev, gpu_image, gpu_mem, 0) != VK_SUCCESS) goto fail_gpu;
    }

    /* 3. Record upload commands */
    {
        VkCommandBufferAllocateInfo cbai = {0};
        cbai.sType              = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        cbai.commandPool        = pool;
        cbai.level              = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        cbai.commandBufferCount = 1;

        VkCommandBuffer cb = VK_NULL_HANDLE;
        if (vkAllocateCommandBuffers(dev, &cbai, &cb) != VK_SUCCESS) goto fail_gpu;

        VkCommandBufferBeginInfo cbbi = {0};
        cbbi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        cbbi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

        if (vkBeginCommandBuffer(cb, &cbbi) != VK_SUCCESS) goto fail_gpu;

        /* Transition UNDEFINED -> TRANSFER_DST (all mips) */
        transition_layout(cb, gpu_image,
            VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            0, mip_levels, 0, VK_ACCESS_TRANSFER_WRITE_BIT,
            VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);

        /* Copy staging buffer -> image mip 0 */
        VkBufferImageCopy copy_region = {0};
        copy_region.bufferOffset                    = 0;
        copy_region.bufferRowLength                 = 0;
        copy_region.bufferImageHeight               = 0;
        copy_region.imageSubresource.aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT;
        copy_region.imageSubresource.mipLevel       = 0;
        copy_region.imageSubresource.baseArrayLayer = 0;
        copy_region.imageSubresource.layerCount     = 1;
        copy_region.imageOffset                     = (VkOffset3D){0, 0, 0};
        copy_region.imageExtent                     = (VkExtent3D){(uint32_t)width, (uint32_t)height, 1};

        vkCmdCopyBufferToImage(cb, staging_buf, gpu_image,
            VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy_region);

        if (generate_mips) {
            /* Mip 0 is already in TRANSFER_DST -- generate mipmaps (handles transitions internally) */
            generate_mipmaps(cb, gpu_image, (uint32_t)width, (uint32_t)height, mip_levels);
        } else {
            /* Transition mip 0: TRANSFER_DST -> SHADER_READ_ONLY */
            transition_layout(cb, gpu_image,
                VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                0, 1, VK_ACCESS_TRANSFER_WRITE_BIT, VK_ACCESS_SHADER_READ_BIT,
                VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT);
        }

        if (vkEndCommandBuffer(cb) != VK_SUCCESS) goto fail_gpu;

        /* Submit and wait */
        VkSubmitInfo si = {0};
        si.sType              = VK_STRUCTURE_TYPE_SUBMIT_INFO;
        si.commandBufferCount = 1;
        si.pCommandBuffers    = &cb;

        VkFence fence = VK_NULL_HANDLE;
        VkFenceCreateInfo fci = {0};
        fci.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
        if (vkCreateFence(dev, &fci, NULL, &fence) != VK_SUCCESS) goto fail_gpu;

        if (vkQueueSubmit(q, 1, &si, fence) != VK_SUCCESS) {
            vkDestroyFence(dev, fence, NULL);
            goto fail_gpu;
        }
        vkWaitForFences(dev, 1, &fence, VK_TRUE, UINT64_MAX);
        vkDestroyFence(dev, fence, NULL);

        vkFreeCommandBuffers(dev, pool, 1, &cb);
    }

    /* 4. Clean up staging resources */
    vkDestroyBuffer(dev, staging_buf, NULL);
    vkFreeMemory(dev, staging_mem, NULL);

    /* 5. Create image view and sampler */
    VkImageView image_view = create_image_view(dev, gpu_image, format,
        VK_IMAGE_ASPECT_COLOR_BIT, mip_levels);
    if (image_view == VK_NULL_HANDLE) goto fail_gpu;

    VkSampler sampler = create_default_sampler(dev, (float)mip_levels);
    if (sampler == VK_NULL_HANDLE) {
        vkDestroyImageView(dev, image_view, NULL);
        goto fail_gpu;
    }

    /* 6. Allocate and populate texture handle */
    XvkTexture* tex = (XvkTexture*)malloc(sizeof(XvkTexture));
    if (!tex) {
        vkDestroySampler(dev, sampler, NULL);
        vkDestroyImageView(dev, image_view, NULL);
        goto fail_gpu;
    }

    tex->image       = gpu_image;
    tex->image_view  = image_view;
    tex->sampler     = sampler;
    tex->memory      = gpu_mem;
    tex->width       = width;
    tex->height      = height;
    tex->mip_levels  = (int32_t)mip_levels;
    tex->format      = (uint32_t)format;
    tex->aspect_mask = VK_IMAGE_ASPECT_COLOR_BIT;

    return (int64_t)(intptr_t)tex;

fail_gpu:
    if (gpu_image) vkDestroyImage(dev, gpu_image, NULL);
    if (gpu_mem)   vkFreeMemory(dev, gpu_mem, NULL);
fail_staging:
    if (staging_buf)  vkDestroyBuffer(dev, staging_buf, NULL);
    if (staging_mem)  vkFreeMemory(dev, staging_mem, NULL);
    return 0;
}

int64_t xvk_texture_get_image(int64_t texture)
{
    XvkTexture* t = tex_get(texture);
    return t ? (int64_t)(uintptr_t)t->image : 0;
}

int64_t xvk_texture_get_image_view(int64_t texture)
{
    XvkTexture* t = tex_get(texture);
    return t ? (int64_t)(uintptr_t)t->image_view : 0;
}

int64_t xvk_texture_get_sampler(int64_t texture)
{
    XvkTexture* t = tex_get(texture);
    return t ? (int64_t)(uintptr_t)t->sampler : 0;
}

int32_t xvk_texture_get_width(int64_t texture)
{
    XvkTexture* t = tex_get(texture);
    return t ? t->width : 0;
}

int32_t xvk_texture_get_height(int64_t texture)
{
    XvkTexture* t = tex_get(texture);
    return t ? t->height : 0;
}

int32_t xvk_texture_get_mip_levels(int64_t texture)
{
    XvkTexture* t = tex_get(texture);
    return t ? t->mip_levels : 0;
}

void xvk_texture_destroy(int64_t device, int64_t texture)
{
    XvkTexture* t = tex_get(texture);
    if (!t) return;

    VkDevice dev = (VkDevice)(intptr_t)device;
    vkDestroySampler(dev, t->sampler, NULL);
    vkDestroyImageView(dev, t->image_view, NULL);
    vkDestroyImage(dev, t->image, NULL);
    vkFreeMemory(dev, t->memory, NULL);
    free(t);
}
