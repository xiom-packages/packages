#include "xvk_bind_device.h"

#include <stddef.h>
#include <stdint.h>
#include <vulkan/vulkan.h>

#include "xvk_structs.h"
#include "xvk_util.h"

#ifndef XVK_STATIC_ASSERT
#define XVK_STATIC_ASSERT(cond, name) typedef char name[(cond) ? 1 : -1]
#endif

XVK_STATIC_ASSERT(sizeof(VkDeviceQueueCreateInfo) == 40, xvk_sa_bd_qci_size);
XVK_STATIC_ASSERT(offsetof(VkDeviceQueueCreateInfo, queueFamilyIndex) == 20, xvk_sa_bd_qci_family);
XVK_STATIC_ASSERT(offsetof(VkDeviceQueueCreateInfo, queueCount) == 24, xvk_sa_bd_qci_count);
XVK_STATIC_ASSERT(offsetof(VkDeviceQueueCreateInfo, pQueuePriorities) == 32, xvk_sa_bd_qci_prio);

int64_t xvk_create_device(
    int64_t physical_device,
    int32_t queue_count,
    int64_t queue_create_infos,
    int32_t enabled_ext_count,
    int64_t enabled_ext_names,
    int64_t enabled_features,
    int64_t pNext_chain)
{
    if (physical_device == 0) {
        xvk_set_error("xvk_create_device: physical_device is NULL");
        return 0;
    }
    if (queue_count <= 0 || queue_create_infos == 0) {
        xvk_set_error("xvk_create_device: at least one VkDeviceQueueCreateInfo is required");
        return 0;
    }
    if (enabled_ext_count < 0) {
        xvk_set_error("xvk_create_device: negative extension count");
        return 0;
    }
    if (enabled_ext_count > 0 && enabled_ext_names == 0) {
        xvk_set_error("xvk_create_device: extension count > 0 but extension names is NULL");
        return 0;
    }

    int64_t create_info = xvk_alloc((int64_t)sizeof(VkDeviceCreateInfo));
    if (create_info == 0) {
        xvk_set_error("xvk_create_device: allocation failed");
        return 0;
    }

    xvk_set_sType(create_info, (int32_t)VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO);
    xvk_set_pNext(create_info, pNext_chain);
    xvk_write_u32(create_info, (int64_t)offsetof(VkDeviceCreateInfo, queueCreateInfoCount),
                  queue_count);
    xvk_write_u64(create_info, (int64_t)offsetof(VkDeviceCreateInfo, pQueueCreateInfos),
                  queue_create_infos);
    xvk_write_u32(create_info, (int64_t)offsetof(VkDeviceCreateInfo, enabledExtensionCount),
                  enabled_ext_count);
    xvk_write_u64(create_info, (int64_t)offsetof(VkDeviceCreateInfo, ppEnabledExtensionNames),
                  enabled_ext_names);
    xvk_write_u64(create_info, (int64_t)offsetof(VkDeviceCreateInfo, pEnabledFeatures),
                  enabled_features);

    VkDevice device = VK_NULL_HANDLE;
    VkResult res = vkCreateDevice(
        (VkPhysicalDevice)(intptr_t)physical_device,
        (const VkDeviceCreateInfo*)(intptr_t)create_info,
        NULL, &device);

    xvk_free(create_info);

    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateDevice failed: VkResult %d", (int)res);
        return 0;
    }
    return (int64_t)(intptr_t)device;
}

void xvk_destroy_device(int64_t device)
{
    if (device == 0) return;
    vkDestroyDevice((VkDevice)(intptr_t)device, NULL);
}

void xvk_get_device_queue(int64_t device, int32_t family, int32_t index, int64_t out_queue)
{
    if (device == 0) {
        xvk_set_error("xvk_get_device_queue: device is NULL");
        return;
    }
    if (out_queue == 0) {
        xvk_set_error("xvk_get_device_queue: out_queue is NULL");
        return;
    }
    if (family < 0 || index < 0) {
        xvk_set_error("xvk_get_device_queue: negative family or index");
        return;
    }
    VkQueue queue = VK_NULL_HANDLE;
    vkGetDeviceQueue((VkDevice)(intptr_t)device, (uint32_t)family, (uint32_t)index, &queue);
    xvk_write_u64(out_queue, 0, (int64_t)(intptr_t)queue);
}

/* Phase 7.5: Get a device queue via VkDeviceQueueInfo2 for extended flags (e.g. protected, video).
 * queue_info_struct: VkDeviceQueueInfo2* — caller-built struct.
 * out_queue:         VkQueue* — pre-allocated 8 bytes; receives the queue handle. */
int32_t xvk_get_device_queue2(int64_t device, int64_t queue_info_struct, int64_t out_queue)
{
    if (device == 0 || out_queue == 0) {
        xvk_set_error("xvk_get_device_queue2: null device or out_queue");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    const VkDeviceQueueInfo2* qi = (const VkDeviceQueueInfo2*)(intptr_t)queue_info_struct;
    if (!qi || qi->sType != VK_STRUCTURE_TYPE_DEVICE_QUEUE_INFO_2) {
        xvk_set_error("xvk_get_device_queue2: invalid queue info struct");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkQueue queue = VK_NULL_HANDLE;
    vkGetDeviceQueue2((VkDevice)(intptr_t)device, qi, &queue);
    xvk_write_u64(out_queue, 0, (int64_t)(intptr_t)queue);
    if (queue == VK_NULL_HANDLE) {
        xvk_set_error("xvk_get_device_queue2: returned null queue");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    return (int32_t)VK_SUCCESS;
}

int32_t xvk_device_wait_idle(int64_t device)
{
    if (device == 0) {
        xvk_set_error("xvk_device_wait_idle: device is NULL");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkDeviceWaitIdle((VkDevice)(intptr_t)device);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkDeviceWaitIdle failed: VkResult %d", (int)res);
    }
    return (int32_t)res;
}
