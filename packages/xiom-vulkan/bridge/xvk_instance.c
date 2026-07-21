#include "xvk_instance.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

VkInstance create_instance(const char* app_name, int* have_validation)
{
    *have_validation = 0;

    const char* env = getenv("XVK_VALIDATION");
    int want_validation = (env && env[0] == '1');

    VkApplicationInfo app_info = {0};
    app_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app_info.pApplicationName = app_name;
    app_info.applicationVersion = 1;
    app_info.pEngineName = "XIOM-Vulkan-Bridge";
    app_info.engineVersion = 1;
    app_info.apiVersion = VK_API_VERSION_1_3;

    uint32_t glfw_ext_count = 0;
    const char** glfw_ext = glfwGetRequiredInstanceExtensions(&glfw_ext_count);
    if (!glfw_ext) {
        xvk_set_error("glfwGetRequiredInstanceExtensions returned NULL");
        return VK_NULL_HANDLE;
    }

    VkInstanceCreateInfo ci = {0};
    ci.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    ci.pApplicationInfo = &app_info;
    ci.enabledExtensionCount = glfw_ext_count;
    ci.ppEnabledExtensionNames = glfw_ext;

    const char* layer_name = "VK_LAYER_KHRONOS_validation";
    VkLayerProperties* layers = NULL;
    uint32_t layer_count = 0;
    if (vkEnumerateInstanceLayerProperties(&layer_count, NULL) != VK_SUCCESS)
        layer_count = 0;
    int layer_avail = 0;
    if (layer_count > 0) {
        layers = (VkLayerProperties*)malloc(
            layer_count * sizeof(VkLayerProperties));
        if (layers) {
            vkEnumerateInstanceLayerProperties(&layer_count, layers);
            for (uint32_t i = 0; i < layer_count; ++i) {
                if (strcmp(layers[i].layerName, layer_name) == 0) {
                    layer_avail = 1;
                    break;
                }
            }
            free(layers);
        }
    }

    if (want_validation && layer_avail) {
        ci.enabledLayerCount = 1;
        ci.ppEnabledLayerNames = &layer_name;
        *have_validation = 1;
    }

    VkInstance inst = VK_NULL_HANDLE;
    VkResult res = vkCreateInstance(&ci, NULL, &inst);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateInstance failed: %d", (int)res);
        return VK_NULL_HANDLE;
    }
    printf("XIOM-Vulkan-Bridge: instance created (validation=%d)\n",
           *have_validation);
    return inst;
}

/* Phase 8.5: Headless instance creation — no GLFW, no surface.
 * Uses VK_EXT_headless_surface if available (optional, for drivers that require
 * a surface extension to create a device). Does NOT call glfwInit or
 * glfwGetRequiredInstanceExtensions. Safe to use on CI servers and headless VMs. */
VkInstance create_instance_headless(const char* app_name, int* have_validation)
{
    *have_validation = 0;

    VkApplicationInfo app_info = {0};
    app_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app_info.pApplicationName = app_name;
    app_info.applicationVersion = 1;
    app_info.pEngineName = "XIOM-Vulkan-Bridge";
    app_info.engineVersion = 1;
    app_info.apiVersion = VK_API_VERSION_1_3;

    /* Minimal extensions for headless: no surface, no swapchain needed.
     * VK_EXT_headless_surface is optional — some GPU drivers require a surface
     * extension to be enabled even for device-level operations. */
    const char* headless_exts[] = {
        "VK_EXT_headless_surface",
        /* VK_KHR_surface is implicitly available if headless_surface is present */
    };
    uint32_t ext_count = 0;
    const char** enabled_exts = NULL;

    /* Check if VK_EXT_headless_surface is available */
    uint32_t avail_ext_count = 0;
    vkEnumerateInstanceExtensionProperties(NULL, &avail_ext_count, NULL);
    VkExtensionProperties* available = NULL;
    if (avail_ext_count > 0) {
        available = (VkExtensionProperties*)malloc(
            avail_ext_count * sizeof(VkExtensionProperties));
        if (available) {
            vkEnumerateInstanceExtensionProperties(NULL, &avail_ext_count, available);
            int has_headless = 0;
            for (uint32_t i = 0; i < avail_ext_count; i++) {
                if (strcmp(available[i].extensionName,
                           "VK_EXT_headless_surface") == 0) {
                    has_headless = 1;
                    break;
                }
            }
            free(available);
            if (has_headless) {
                enabled_exts = headless_exts;
                ext_count = 1;
            }
            /* If headless surface not available, proceed with zero extensions.
             * Most GPUs handle this correctly — the device can be created
             * without any instance extensions. */
        }
    }

    VkInstanceCreateInfo ci = {0};
    ci.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    ci.pApplicationInfo = &app_info;
    ci.enabledExtensionCount = ext_count;
    ci.ppEnabledExtensionNames = enabled_exts;

    const char* env = getenv("XVK_VALIDATION");
    int want_validation = (env && env[0] == '1');
    const char* layer_name = "VK_LAYER_KHRONOS_validation";
    uint32_t layer_count = 0;
    vkEnumerateInstanceLayerProperties(&layer_count, NULL);
    VkLayerProperties* layers = NULL;
    int layer_avail = 0;
    if (layer_count > 0) {
        layers = (VkLayerProperties*)malloc(
            layer_count * sizeof(VkLayerProperties));
        if (layers) {
            vkEnumerateInstanceLayerProperties(&layer_count, layers);
            for (uint32_t i = 0; i < layer_count; ++i) {
                if (strcmp(layers[i].layerName, layer_name) == 0) {
                    layer_avail = 1;
                    break;
                }
            }
            free(layers);
        }
    }

    if (want_validation && layer_avail) {
        ci.enabledLayerCount = 1;
        ci.ppEnabledLayerNames = &layer_name;
        *have_validation = 1;
    }

    VkInstance inst = VK_NULL_HANDLE;
    VkResult res = vkCreateInstance(&ci, NULL, &inst);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("headless vkCreateInstance failed: %d", (int)res);
        return VK_NULL_HANDLE;
    }
    printf("XIOM-Vulkan-Bridge: headless instance created (validation=%d)\n",
           *have_validation);
    return inst;
}

int pick_physical_device(VkInstance inst, VkSurfaceKHR surface,
                          VkPhysicalDevice* out_pd, int* out_type)
{
    uint32_t n = 0;
    vkEnumeratePhysicalDevices(inst, &n, NULL);
    if (n == 0) {
        xvk_set_error("no Vulkan-capable physical devices found");
        return 0;
    }
    VkPhysicalDevice* devs = (VkPhysicalDevice*)
        malloc(n * sizeof(VkPhysicalDevice));
    vkEnumeratePhysicalDevices(inst, &n, devs);

    int chosen = -1;
    for (uint32_t i = 0; i < n; ++i) {
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(devs[i], &props);
        printf("  GPU %u: %s  (type %d)\n", i, props.deviceName,
               props.deviceType);

        uint32_t gfx, pres;
        if (find_queue_families(devs[i], surface, &gfx, &pres)) {
            if (surface == VK_NULL_HANDLE || surface != VK_NULL_HANDLE) {
                if (chosen < 0 ||
                    props.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
                    chosen = (int)i;
                }
                if (chosen == (int)i) {
                    *out_type = (int)props.deviceType;
                }
            }
        }
    }

    if (chosen < 0) {
        free(devs);
        xvk_set_error("no suitable GPU found (need graphics queue)");
        return 0;
    }

    *out_pd = devs[chosen];
    VkPhysicalDeviceProperties props;
    vkGetPhysicalDeviceProperties(*out_pd, &props);
    printf("XIOM-Vulkan-Bridge: selected GPU = %s\n", props.deviceName);
    free(devs);
    return 1;
}

VkDevice create_device(VkPhysicalDevice pd, uint32_t gfx_family,
                        uint32_t pres_family, VkSurfaceKHR surface)
{
    float q_priority = 1.0f;
    uint32_t families[2];
    int n_families = 0;
    families[n_families++] = gfx_family;
    if (pres_family != gfx_family && surface != VK_NULL_HANDLE)
        families[n_families++] = pres_family;

    VkDeviceQueueCreateInfo qci[2];
    for (int i = 0; i < n_families; ++i) {
        qci[i].sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        qci[i].pNext = NULL;
        qci[i].flags = 0;
        qci[i].queueFamilyIndex = families[i];
        qci[i].queueCount = 1;
        qci[i].pQueuePriorities = &q_priority;
    }

    const char* dev_exts[4];
    int n_dev_exts = 0;
    dev_exts[n_dev_exts++] = VK_KHR_SWAPCHAIN_EXTENSION_NAME;
    /* VK_EXT_debug_marker is optional — skip if unavailable */

    VkPhysicalDeviceFeatures features = {0};
    features.samplerAnisotropy = VK_TRUE;
    features.fillModeNonSolid  = VK_TRUE;
    features.wideLines         = VK_TRUE;

    VkDeviceCreateInfo dci = {0};
    dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    dci.queueCreateInfoCount = (uint32_t)n_families;
    dci.pQueueCreateInfos = qci;
    dci.enabledExtensionCount = (uint32_t)n_dev_exts;
    dci.ppEnabledExtensionNames = dev_exts;
    dci.pEnabledFeatures = &features;

    VkDevice dev = VK_NULL_HANDLE;
    VkResult res = vkCreateDevice(pd, &dci, NULL, &dev);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateDevice failed: %d", (int)res);
        return VK_NULL_HANDLE;
    }
    return dev;
}

VkSurfaceKHR create_surface(VkInstance inst, GLFWwindow* win)
{
    VkSurfaceKHR surf = VK_NULL_HANDLE;
    VkResult res = glfwCreateWindowSurface(inst, win, NULL, &surf);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("glfwCreateWindowSurface failed: %d", (int)res);
        return VK_NULL_HANDLE;
    }
    return surf;
}
