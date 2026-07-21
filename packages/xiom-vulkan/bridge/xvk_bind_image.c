#include "xvk_bind_image.h"

#include <string.h>
#include <vulkan/vulkan.h>

#include "xvk_util.h"

int64_t xvk_create_image(int64_t device, int64_t create_info_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkImageCreateInfo* ci = (VkImageCreateInfo*)(intptr_t)create_info_struct;
    if (!dev || !ci) {
        xvk_set_error("xvk_create_image: null device or create info");
        return 0;
    }
    ci->sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;

    VkImage image = VK_NULL_HANDLE;
    VkResult res = vkCreateImage(dev, ci, NULL, &image);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateImage: %d", (int)res);
        return 0;
    }
    return (int64_t)(uintptr_t)image;
}

void xvk_destroy_image(int64_t device, int64_t image)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkImage img = (VkImage)(uintptr_t)image;
    if (!dev || !img) return;
    vkDestroyImage(dev, img, NULL);
}

int32_t xvk_bind_image_memory(int64_t device, int64_t image, int64_t memory, int64_t offset)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkImage img = (VkImage)(uintptr_t)image;
    VkDeviceMemory mem = (VkDeviceMemory)(uintptr_t)memory;
    if (!dev || !img || !mem) {
        xvk_set_error("xvk_bind_image_memory: null device, image or memory");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkBindImageMemory(dev, img, mem, (VkDeviceSize)offset);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkBindImageMemory: %d", (int)res);
    }
    return (int32_t)res;
}

void xvk_get_image_memory_requirements(int64_t device, int64_t image, int64_t out_reqs)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkImage img = (VkImage)(uintptr_t)image;
    void* out = (void*)(intptr_t)out_reqs;
    if (!dev || !img || !out) {
        xvk_set_error("xvk_get_image_memory_requirements: null argument");
        return;
    }
    VkMemoryRequirements mr;
    vkGetImageMemoryRequirements(dev, img, &mr);
    memcpy(out, &mr, sizeof(mr));
}

int64_t xvk_create_image_view(int64_t device, int64_t create_info_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkImageViewCreateInfo* ci = (VkImageViewCreateInfo*)(intptr_t)create_info_struct;
    if (!dev || !ci) {
        xvk_set_error("xvk_create_image_view: null device or create info");
        return 0;
    }
    ci->sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;

    VkImageView view = VK_NULL_HANDLE;
    VkResult res = vkCreateImageView(dev, ci, NULL, &view);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateImageView: %d", (int)res);
        return 0;
    }
    return (int64_t)(uintptr_t)view;
}

void xvk_destroy_image_view(int64_t device, int64_t view)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkImageView v = (VkImageView)(uintptr_t)view;
    if (!dev || !v) return;
    vkDestroyImageView(dev, v, NULL);
}

int64_t xvk_create_sampler(int64_t device, int64_t create_info_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkSamplerCreateInfo* ci = (VkSamplerCreateInfo*)(intptr_t)create_info_struct;
    if (!dev || !ci) {
        xvk_set_error("xvk_create_sampler: null device or create info");
        return 0;
    }
    ci->sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;

    VkSampler sampler = VK_NULL_HANDLE;
    VkResult res = vkCreateSampler(dev, ci, NULL, &sampler);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateSampler: %d", (int)res);
        return 0;
    }
    return (int64_t)(uintptr_t)sampler;
}

void xvk_destroy_sampler(int64_t device, int64_t sampler)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkSampler s = (VkSampler)(uintptr_t)sampler;
    if (!dev || !s) return;
    vkDestroySampler(dev, s, NULL);
}
