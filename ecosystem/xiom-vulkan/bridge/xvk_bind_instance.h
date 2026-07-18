#ifndef XVK_BIND_INSTANCE_H_
#define XVK_BIND_INSTANCE_H_

#include <stdint.h>

/*
 * Direct Vulkan instance bindings for XIOM.
 *
 * Exposes the REAL vkCreateInstance / vkDestroyInstance /
 * vkEnumeratePhysicalDevices / vkGetPhysicalDeviceProperties entry points.
 * All VkCreateInfo structs are built internally through the generic struct
 * marshalling layer (xvk_structs.h). All handles/pointers are int64_t
 * (0 = NULL/invalid). Errors are reported via xvk_last_error().
 */

/* Create a Vulkan instance (API version 1.3).
 * app_name:            application name string (may be NULL)
 * engine_name:         engine name string (may be NULL)
 * enabled_layer_count: number of validation layers
 * enabled_layer_names: char** — pointer to array of layer name strings (0 if none)
 * enabled_ext_count:   number of instance extensions
 * enabled_ext_names:   char** — pointer to array of extension name strings (0 if none)
 * Returns: VkInstance handle (int64_t), or 0 on failure. */
int64_t xvk_create_instance(
    const char* app_name,
    const char* engine_name,
    int32_t enabled_layer_count,
    int64_t enabled_layer_names,
    int32_t enabled_ext_count,
    int64_t enabled_ext_names
);

/* Destroy a Vulkan instance. No-op for 0. */
void xvk_destroy_instance(int64_t instance);

/* Enumerate physical devices.
 * out_count:   uint32_t* — in: capacity of out_devices, out: number of devices
 * out_devices: VkPhysicalDevice* — array of 8-byte handles, or 0 to query count only
 * Returns: VkResult (0 = VK_SUCCESS, 5 = VK_INCOMPLETE, negative = error). */
int32_t xvk_enumerate_physical_devices(int64_t instance, int64_t out_count, int64_t out_devices);

/* Get physical device properties (fills a pre-allocated struct).
 * out_props: VkPhysicalDeviceProperties* — allocate sizeof = 824 bytes via xvk_alloc.
 * Key byte offsets (x64, verified by compile-time asserts):
 *   apiVersion    u32 @ 0
 *   driverVersion u32 @ 4
 *   vendorID      u32 @ 8
 *   deviceID      u32 @ 12
 *   deviceType    u32 @ 16
 *   deviceName    char[256] @ 20 */
void xvk_get_physical_device_properties(int64_t device, int64_t out_props);

#endif
