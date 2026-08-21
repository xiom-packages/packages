#include "xvk_bind_sync.h"

#include <vulkan/vulkan.h>

#include "xvk_util.h"

int64_t xvk_create_fence(int64_t device, int64_t create_info_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    const VkFenceCreateInfo* ci = (const VkFenceCreateInfo*)(intptr_t)create_info_struct;
    if (!dev) { xvk_set_error("xvk_create_fence: null device"); return 0; }

    VkFenceCreateInfo def = {0};
    if (!ci) {
        def.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
        ci = &def;
    }
    VkFence fence = VK_NULL_HANDLE;
    VkResult res = vkCreateFence(dev, ci, NULL, &fence);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateFence failed: %d", (int)res);
        return 0;
    }
    return (int64_t)(uint64_t)fence;
}

void xvk_destroy_fence(int64_t device, int64_t fence)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    if (!dev || !fence) return;
    vkDestroyFence(dev, (VkFence)(uint64_t)fence, NULL);
}

int32_t xvk_wait_for_fences(int64_t device, int32_t count, int64_t fences, int32_t wait_all, int64_t timeout)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    const VkFence* fs = (const VkFence*)(intptr_t)fences;
    if (!dev || !fs || count <= 0) return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    return (int32_t)vkWaitForFences(dev, (uint32_t)count, fs,
                                    wait_all ? VK_TRUE : VK_FALSE, (uint64_t)timeout);
}

int32_t xvk_reset_fences(int64_t device, int32_t count, int64_t fences)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    const VkFence* fs = (const VkFence*)(intptr_t)fences;
    if (!dev || !fs || count <= 0) return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    return (int32_t)vkResetFences(dev, (uint32_t)count, fs);
}

int64_t xvk_create_semaphore(int64_t device, int64_t create_info_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    const VkSemaphoreCreateInfo* ci = (const VkSemaphoreCreateInfo*)(intptr_t)create_info_struct;
    if (!dev) { xvk_set_error("xvk_create_semaphore: null device"); return 0; }

    VkSemaphoreCreateInfo def = {0};
    if (!ci) {
        def.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
        ci = &def;
    }
    VkSemaphore sem = VK_NULL_HANDLE;
    VkResult res = vkCreateSemaphore(dev, ci, NULL, &sem);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateSemaphore failed: %d", (int)res);
        return 0;
    }
    return (int64_t)(uint64_t)sem;
}

void xvk_destroy_semaphore(int64_t device, int64_t semaphore)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    if (!dev || !semaphore) return;
    vkDestroySemaphore(dev, (VkSemaphore)(uint64_t)semaphore, NULL);
}

int64_t xvk_create_event(int64_t device, int64_t create_info_struct)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    const VkEventCreateInfo* ci = (const VkEventCreateInfo*)(intptr_t)create_info_struct;
    if (!dev) { xvk_set_error("xvk_create_event: null device"); return 0; }

    VkEventCreateInfo def = {0};
    if (!ci) {
        def.sType = VK_STRUCTURE_TYPE_EVENT_CREATE_INFO;
        ci = &def;
    }
    VkEvent event = VK_NULL_HANDLE;
    VkResult res = vkCreateEvent(dev, ci, NULL, &event);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateEvent failed: %d", (int)res);
        return 0;
    }
    return (int64_t)(uint64_t)event;
}

void xvk_destroy_event(int64_t device, int64_t event)
{
    VkDevice dev = (VkDevice)(intptr_t)device;
    if (!dev || !event) return;
    vkDestroyEvent(dev, (VkEvent)(uint64_t)event, NULL);
}

int32_t xvk_queue_submit(int64_t queue, int32_t submit_count, int64_t submits_struct, int64_t fence)
{
    VkQueue q = (VkQueue)(intptr_t)queue;
    const VkSubmitInfo* submits = (const VkSubmitInfo*)(intptr_t)submits_struct;
    if (!q) return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    if (submit_count > 0 && !submits) return (int32_t)VK_ERROR_INITIALIZATION_FAILED;

    VkResult res = vkQueueSubmit(q, (uint32_t)(submit_count > 0 ? submit_count : 0),
                                 submits, (VkFence)(uint64_t)fence);
    if (res != VK_SUCCESS) xvk_set_error_fmt("vkQueueSubmit failed: %d", (int)res);
    return (int32_t)res;
}

/* Phase 7.5: Convenience multi-submit -- submits count command buffers to a queue.
 * Builds VkSubmitInfo internally from cmd_bufs_array (array of int64_t VK handles).
 * fence is a VkFence handle (0 for none). */
int32_t xvk_queue_submit_multi(int64_t queue, int32_t cmd_buf_count, int64_t cmd_bufs_array, int64_t fence)
{
    VkQueue q = (VkQueue)(intptr_t)queue;
    const VkCommandBuffer* cbs = (const VkCommandBuffer*)(intptr_t)cmd_bufs_array;
    if (!q || cmd_buf_count <= 0 || !cbs) {
        xvk_set_error("xvk_queue_submit_multi: null queue or command buffers");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }

    VkSubmitInfo si = {0};
    si.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    si.commandBufferCount = (uint32_t)cmd_buf_count;
    si.pCommandBuffers = cbs;

    VkResult res = vkQueueSubmit(q, 1, &si, (VkFence)(uint64_t)fence);
    if (res != VK_SUCCESS) xvk_set_error_fmt("vkQueueSubmit multi failed: %d", (int)res);
    return (int32_t)res;
}

/* xvk_queue_present_khr is implemented in xvk_bind_swapchain.c */
