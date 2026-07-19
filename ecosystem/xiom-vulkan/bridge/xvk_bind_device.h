#ifndef XVK_BIND_DEVICE_H_
#define XVK_BIND_DEVICE_H_

#include <stdint.h>

/*
 * Direct Vulkan logical-device bindings for XIOM.
 *
 * Exposes the REAL vkCreateDevice / vkDestroyDevice / vkGetDeviceQueue /
 * vkDeviceWaitIdle entry points. VkDeviceCreateInfo is built internally
 * through the struct marshalling layer (xvk_structs.h); queue create infos,
 * features and pNext chains are built by the caller with xvk_alloc/xvk_write_*.
 * All handles/pointers are int64_t (0 = NULL/invalid).
 */

/* Create a logical device.
 * physical_device:    VkPhysicalDevice handle
 * queue_count:        number of entries in queue_create_infos
 * queue_create_infos: VkDeviceQueueCreateInfo[] — array built by the caller.
 *                     Element stride 40 bytes, byte offsets (x64, verified by
 *                     compile-time asserts):
 *                       sType            u32 @ 0  (= 2, DEVICE_QUEUE_CREATE_INFO)
 *                       pNext            ptr @ 8
 *                       flags            u32 @ 16
 *                       queueFamilyIndex u32 @ 20
 *                       queueCount       u32 @ 24
 *                       pQueuePriorities ptr @ 32 (points to float[queueCount])
 * enabled_ext_count:  number of device extensions
 * enabled_ext_names:  char** — pointer to array of extension name strings (0 if none)
 * enabled_features:   VkPhysicalDeviceFeatures* (0 for none)
 * pNext_chain:        first struct of the pNext chain, e.g.
 *                     VkPhysicalDeviceVulkan13Features* (0 for none)
 * Returns: VkDevice handle (int64_t), or 0 on failure. */
int64_t xvk_create_device(
    int64_t physical_device,
    int32_t queue_count,
    int64_t queue_create_infos,
    int32_t enabled_ext_count,
    int64_t enabled_ext_names,
    int64_t enabled_features,
    int64_t pNext_chain
);

/* Destroy a logical device. No-op for 0. */
void xvk_destroy_device(int64_t device);

/* Get a device queue.
 * out_queue: VkQueue* — pre-allocated 8 bytes; receives the queue handle. */
void xvk_get_device_queue(int64_t device, int32_t family, int32_t index, int64_t out_queue);

/* Phase 7.5: Get a device queue with extended options via VkDeviceQueueInfo2.
 * queue_info_struct: VkDeviceQueueInfo2* — caller-built struct (must set sType=48).
 * out_queue:         VkQueue* — pre-allocated 8 bytes; receives the queue handle. */
int32_t xvk_get_device_queue2(int64_t device, int64_t queue_info_struct, int64_t out_queue);

/* Wait for the device to become idle.
 * Returns: VkResult (0 = VK_SUCCESS, negative = error). */
int32_t xvk_device_wait_idle(int64_t device);

#endif
