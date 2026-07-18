#include "xvk_bind_memory.h"

#include <string.h>
#include <vulkan/vulkan.h>

#include "xvk_util.h"

int64_t xvk_allocate_memory(int64_t device, int64_t allocate_info_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkMemoryAllocateInfo* ai = (VkMemoryAllocateInfo*)(intptr_t)allocate_info_struct;
    if (!dev || !ai) {
        xvk_set_error("xvk_allocate_memory: null device or allocate info");
        return 0;
    }
    ai->sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;

    VkDeviceMemory memory = VK_NULL_HANDLE;
    VkResult res = vkAllocateMemory(dev, ai, NULL, &memory);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkAllocateMemory: %d", (int)res);
        return 0;
    }
    return (int64_t)(uintptr_t)memory;
}

void xvk_free_memory(int64_t device, int64_t memory)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkDeviceMemory mem = (VkDeviceMemory)(uintptr_t)memory;
    if (!dev || !mem) return;
    vkFreeMemory(dev, mem, NULL);
}

int32_t xvk_map_memory(int64_t device, int64_t memory, int64_t offset, int64_t size, int32_t flags, int64_t out_data)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkDeviceMemory mem = (VkDeviceMemory)(uintptr_t)memory;
    uint64_t* out = (uint64_t*)(intptr_t)out_data;
    if (!dev || !mem || !out) {
        xvk_set_error("xvk_map_memory: null device, memory or out pointer");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    void* ptr = NULL;
    VkResult res = vkMapMemory(dev, mem, (VkDeviceSize)offset, (VkDeviceSize)size,
                               (VkMemoryMapFlags)(uint32_t)flags, &ptr);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkMapMemory: %d", (int)res);
        *out = 0;
        return (int32_t)res;
    }
    *out = (uint64_t)(uintptr_t)ptr;
    return (int32_t)res;
}

void xvk_unmap_memory(int64_t device, int64_t memory)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkDeviceMemory mem = (VkDeviceMemory)(uintptr_t)memory;
    if (!dev || !mem) return;
    vkUnmapMemory(dev, mem);
}

int32_t xvk_flush_mapped_memory_ranges(int64_t device, int32_t count, int64_t ranges_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkMappedMemoryRange* ranges = (VkMappedMemoryRange*)(intptr_t)ranges_struct;
    if (!dev || !ranges || count <= 0) {
        xvk_set_error("xvk_flush_mapped_memory_ranges: null argument or bad count");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    for (int32_t i = 0; i < count; ++i) {
        ranges[i].sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE;
    }
    VkResult res = vkFlushMappedMemoryRanges(dev, (uint32_t)count, ranges);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkFlushMappedMemoryRanges: %d", (int)res);
    }
    return (int32_t)res;
}

int32_t xvk_invalidate_mapped_memory_ranges(int64_t device, int32_t count, int64_t ranges_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    VkMappedMemoryRange* ranges = (VkMappedMemoryRange*)(intptr_t)ranges_struct;
    if (!dev || !ranges || count <= 0) {
        xvk_set_error("xvk_invalidate_mapped_memory_ranges: null argument or bad count");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    for (int32_t i = 0; i < count; ++i) {
        ranges[i].sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE;
    }
    VkResult res = vkInvalidateMappedMemoryRanges(dev, (uint32_t)count, ranges);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkInvalidateMappedMemoryRanges: %d", (int)res);
    }
    return (int32_t)res;
}
