#include "xvk_bind_instance.h"

#include <stddef.h>
#include <stdint.h>
#include <vulkan/vulkan.h>

#include "xvk_structs.h"
#include "xvk_util.h"

#ifndef XVK_STATIC_ASSERT
#define XVK_STATIC_ASSERT(cond, name) typedef char name[(cond) ? 1 : -1]
#endif

XVK_STATIC_ASSERT(offsetof(VkPhysicalDeviceProperties, apiVersion) == 0,  xvk_sa_bi_props_apiversion);
XVK_STATIC_ASSERT(offsetof(VkPhysicalDeviceProperties, deviceType) == 16, xvk_sa_bi_props_devicetype);
XVK_STATIC_ASSERT(offsetof(VkPhysicalDeviceProperties, deviceName) == 20, xvk_sa_bi_props_devicename);

int64_t xvk_create_instance(
    const char* app_name,
    const char* engine_name,
    int32_t enabled_layer_count,
    int64_t enabled_layer_names,
    int32_t enabled_ext_count,
    int64_t enabled_ext_names)
{
    if (enabled_layer_count < 0 || enabled_ext_count < 0) {
        xvk_set_error("xvk_create_instance: negative layer/extension count");
        return 0;
    }
    if (enabled_layer_count > 0 && enabled_layer_names == 0) {
        xvk_set_error("xvk_create_instance: layer count > 0 but layer names is NULL");
        return 0;
    }
    if (enabled_ext_count > 0 && enabled_ext_names == 0) {
        xvk_set_error("xvk_create_instance: extension count > 0 but extension names is NULL");
        return 0;
    }

    int64_t app_info = xvk_alloc((int64_t)sizeof(VkApplicationInfo));
    int64_t create_info = xvk_alloc((int64_t)sizeof(VkInstanceCreateInfo));
    if (app_info == 0 || create_info == 0) {
        xvk_free(app_info);
        xvk_free(create_info);
        xvk_set_error("xvk_create_instance: allocation failed");
        return 0;
    }

    xvk_set_sType(app_info, (int32_t)VK_STRUCTURE_TYPE_APPLICATION_INFO);
    xvk_write_u64(app_info, (int64_t)offsetof(VkApplicationInfo, pApplicationName),
                  (int64_t)(intptr_t)app_name);
    xvk_write_u32(app_info, (int64_t)offsetof(VkApplicationInfo, applicationVersion), 1);
    xvk_write_u64(app_info, (int64_t)offsetof(VkApplicationInfo, pEngineName),
                  (int64_t)(intptr_t)engine_name);
    xvk_write_u32(app_info, (int64_t)offsetof(VkApplicationInfo, engineVersion), 1);
    xvk_write_u32(app_info, (int64_t)offsetof(VkApplicationInfo, apiVersion),
                  (int32_t)VK_API_VERSION_1_3);

    xvk_set_sType(create_info, (int32_t)VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO);
    xvk_write_u64(create_info, (int64_t)offsetof(VkInstanceCreateInfo, pApplicationInfo),
                  app_info);
    xvk_write_u32(create_info, (int64_t)offsetof(VkInstanceCreateInfo, enabledLayerCount),
                  enabled_layer_count);
    xvk_write_u64(create_info, (int64_t)offsetof(VkInstanceCreateInfo, ppEnabledLayerNames),
                  enabled_layer_names);
    xvk_write_u32(create_info, (int64_t)offsetof(VkInstanceCreateInfo, enabledExtensionCount),
                  enabled_ext_count);
    xvk_write_u64(create_info, (int64_t)offsetof(VkInstanceCreateInfo, ppEnabledExtensionNames),
                  enabled_ext_names);

    VkInstance instance = VK_NULL_HANDLE;
    VkResult res = vkCreateInstance(
        (const VkInstanceCreateInfo*)(intptr_t)create_info, NULL, &instance);

    xvk_free(create_info);
    xvk_free(app_info);

    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateInstance failed: VkResult %d", (int)res);
        return 0;
    }
    return (int64_t)(intptr_t)instance;
}

void xvk_destroy_instance(int64_t instance)
{
    if (instance == 0) return;
    vkDestroyInstance((VkInstance)(intptr_t)instance, NULL);
}

int32_t xvk_enumerate_physical_devices(int64_t instance, int64_t out_count, int64_t out_devices)
{
    if (instance == 0) {
        xvk_set_error("xvk_enumerate_physical_devices: instance is NULL");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    if (out_count == 0) {
        xvk_set_error("xvk_enumerate_physical_devices: out_count is NULL");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkEnumeratePhysicalDevices(
        (VkInstance)(intptr_t)instance,
        (uint32_t*)(intptr_t)out_count,
        (VkPhysicalDevice*)(intptr_t)out_devices);
    if (res != VK_SUCCESS && res != VK_INCOMPLETE) {
        xvk_set_error_fmt("vkEnumeratePhysicalDevices failed: VkResult %d", (int)res);
    }
    return (int32_t)res;
}

void xvk_get_physical_device_properties(int64_t device, int64_t out_props)
{
    if (device == 0) {
        xvk_set_error("xvk_get_physical_device_properties: device is NULL");
        return;
    }
    if (out_props == 0) {
        xvk_set_error("xvk_get_physical_device_properties: out_props is NULL");
        return;
    }
    vkGetPhysicalDeviceProperties(
        (VkPhysicalDevice)(intptr_t)device,
        (VkPhysicalDeviceProperties*)(intptr_t)out_props);
}
