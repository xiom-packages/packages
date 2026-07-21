#include "xvk_bind_query.h"

#include <vulkan/vulkan.h>

#include "xvk_util.h"

int64_t xvk_create_query_pool(int64_t device, int64_t create_info_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    const VkQueryPoolCreateInfo* ci = (const VkQueryPoolCreateInfo*)(intptr_t)create_info_struct;
    if (!dev || !ci) { xvk_set_error("xvk_create_query_pool: null device or create_info"); return 0; }

    VkQueryPool pool = VK_NULL_HANDLE;
    VkResult res = vkCreateQueryPool(dev, ci, NULL, &pool);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateQueryPool failed: %d", (int)res);
        return 0;
    }
    return (int64_t)(uint64_t)pool;
}

void xvk_destroy_query_pool(int64_t device, int64_t pool)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    if (!dev || !pool) return;
    vkDestroyQueryPool(dev, (VkQueryPool)(uint64_t)pool, NULL);
}

int32_t xvk_get_query_pool_results(int64_t device, int64_t pool, int32_t first, int32_t count, int64_t data_size, int64_t data, int64_t stride, int32_t flags)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    void* p = (void*)(intptr_t)data;
    if (!dev || !pool || !p || count <= 0 || data_size <= 0) {
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    return (int32_t)vkGetQueryPoolResults(dev, (VkQueryPool)(uint64_t)pool,
                                          (uint32_t)first, (uint32_t)count,
                                          (size_t)data_size, p,
                                          (VkDeviceSize)stride,
                                          (VkQueryResultFlags)flags);
}

void xvk_cmd_begin_query(int64_t cmd_buf, int64_t pool, int32_t query, int32_t flags)
{
    VkCommandBuffer cb = (VkCommandBuffer)(intptr_t)cmd_buf;
    if (!cb || !pool) return;
    vkCmdBeginQuery(cb, (VkQueryPool)(uint64_t)pool, (uint32_t)query, (VkQueryControlFlags)flags);
}

void xvk_cmd_end_query(int64_t cmd_buf, int64_t pool, int32_t query)
{
    VkCommandBuffer cb = (VkCommandBuffer)(intptr_t)cmd_buf;
    if (!cb || !pool) return;
    vkCmdEndQuery(cb, (VkQueryPool)(uint64_t)pool, (uint32_t)query);
}

void xvk_cmd_write_timestamp(int64_t cmd_buf, int32_t stage, int64_t pool, int32_t query)
{
    VkCommandBuffer cb = (VkCommandBuffer)(intptr_t)cmd_buf;
    if (!cb || !pool) return;
    vkCmdWriteTimestamp(cb, (VkPipelineStageFlagBits)stage,
                        (VkQueryPool)(uint64_t)pool, (uint32_t)query);
}

void xvk_cmd_reset_query_pool(int64_t cmd_buf, int64_t pool, int32_t first, int32_t count)
{
    VkCommandBuffer cb = (VkCommandBuffer)(intptr_t)cmd_buf;
    if (!cb || !pool || count <= 0) return;
    vkCmdResetQueryPool(cb, (VkQueryPool)(uint64_t)pool, (uint32_t)first, (uint32_t)count);
}

void xvk_cmd_copy_query_pool_results(int64_t cmd_buf, int64_t pool, int32_t first, int32_t count, int64_t dst, int64_t dst_offset, int64_t stride, int32_t flags)
{
    VkCommandBuffer cb = (VkCommandBuffer)(intptr_t)cmd_buf;
    if (!cb || !pool || !dst || count <= 0) return;
    vkCmdCopyQueryPoolResults(cb, (VkQueryPool)(uint64_t)pool,
                              (uint32_t)first, (uint32_t)count,
                              (VkBuffer)(uint64_t)dst, (VkDeviceSize)dst_offset,
                              (VkDeviceSize)stride, (VkQueryResultFlags)flags);
}
