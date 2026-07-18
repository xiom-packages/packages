#include "xvk_bind_buffer.h"

#include <string.h>
#include <vulkan/vulkan.h>

#include "xvk_util.h"

int64_t xvk_create_buffer(int64_t device, int64_t create_info_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkBufferCreateInfo* ci = (VkBufferCreateInfo*)(intptr_t)create_info_struct;
    if (!dev || !ci) {
        xvk_set_error("xvk_create_buffer: null device or create info");
        return 0;
    }
    ci->sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;

    VkBuffer buffer = VK_NULL_HANDLE;
    VkResult res = vkCreateBuffer(dev, ci, NULL, &buffer);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateBuffer: %d", (int)res);
        return 0;
    }
    return (int64_t)(uintptr_t)buffer;
}

void xvk_destroy_buffer(int64_t device, int64_t buffer)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkBuffer buf = (VkBuffer)(uintptr_t)buffer;
    if (!dev || !buf) return;
    vkDestroyBuffer(dev, buf, NULL);
}

int32_t xvk_bind_buffer_memory(int64_t device, int64_t buffer, int64_t memory, int64_t offset)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkBuffer buf = (VkBuffer)(uintptr_t)buffer;
    VkDeviceMemory mem = (VkDeviceMemory)(uintptr_t)memory;
    if (!dev || !buf || !mem) {
        xvk_set_error("xvk_bind_buffer_memory: null device, buffer or memory");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkBindBufferMemory(dev, buf, mem, (VkDeviceSize)offset);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkBindBufferMemory: %d", (int)res);
    }
    return (int32_t)res;
}

void xvk_get_buffer_memory_requirements(int64_t device, int64_t buffer, int64_t out_reqs)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkBuffer buf = (VkBuffer)(uintptr_t)buffer;
    void* out = (void*)(intptr_t)out_reqs;
    if (!dev || !buf || !out) {
        xvk_set_error("xvk_get_buffer_memory_requirements: null argument");
        return;
    }
    VkMemoryRequirements mr;
    vkGetBufferMemoryRequirements(dev, buf, &mr);
    memcpy(out, &mr, sizeof(mr));
}

int64_t xvk_create_buffer_view(int64_t device, int64_t create_info_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkBufferViewCreateInfo* ci = (VkBufferViewCreateInfo*)(intptr_t)create_info_struct;
    if (!dev || !ci) {
        xvk_set_error("xvk_create_buffer_view: null device or create info");
        return 0;
    }
    ci->sType = VK_STRUCTURE_TYPE_BUFFER_VIEW_CREATE_INFO;

    VkBufferView view = VK_NULL_HANDLE;
    VkResult res = vkCreateBufferView(dev, ci, NULL, &view);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateBufferView: %d", (int)res);
        return 0;
    }
    return (int64_t)(uintptr_t)view;
}

void xvk_destroy_buffer_view(int64_t device, int64_t view)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkBufferView v = (VkBufferView)(uintptr_t)view;
    if (!dev || !v) return;
    vkDestroyBufferView(dev, v, NULL);
}
