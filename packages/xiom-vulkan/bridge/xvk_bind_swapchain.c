#include "xvk_bind_swapchain.h"

#include <stddef.h>
#include <string.h>
#include <vulkan/vulkan.h>

#include "xvk_util.h"

#define XVK_BSWAP_DH(T, h)   ((T)(intptr_t)(h))
#define XVK_BSWAP_NDH(T, h)  ((T)(uintptr_t)(h))
#define XVK_BSWAP_PTR(T, h)  ((T)(intptr_t)(h))
#define XVK_BSWAP_H64(h)     ((int64_t)(uintptr_t)(h))

#if UINTPTR_MAX > 0xFFFFFFFFu
_Static_assert(sizeof(VkSwapchainCreateInfoKHR) == 104, "VkSwapchainCreateInfoKHR ABI mismatch");
_Static_assert(offsetof(VkSwapchainCreateInfoKHR, surface) == 24, "VkSwapchainCreateInfoKHR.surface offset mismatch");
_Static_assert(offsetof(VkSwapchainCreateInfoKHR, pQueueFamilyIndices) == 72, "VkSwapchainCreateInfoKHR.pQueueFamilyIndices offset mismatch");
_Static_assert(offsetof(VkSwapchainCreateInfoKHR, oldSwapchain) == 96, "VkSwapchainCreateInfoKHR.oldSwapchain offset mismatch");
_Static_assert(sizeof(VkPresentInfoKHR) == 64, "VkPresentInfoKHR ABI mismatch");
_Static_assert(sizeof(VkPhysicalDeviceSurfaceInfo2KHR) == 24, "VkPhysicalDeviceSurfaceInfo2KHR ABI mismatch");
_Static_assert(sizeof(VkSurfaceCapabilities2KHR) == 72, "VkSurfaceCapabilities2KHR ABI mismatch");
_Static_assert(sizeof(VkSurfaceFormat2KHR) == 24, "VkSurfaceFormat2KHR ABI mismatch");
_Static_assert(sizeof(VkDisplayModeCreateInfoKHR) == 32, "VkDisplayModeCreateInfoKHR ABI mismatch");
_Static_assert(sizeof(VkDisplaySurfaceCreateInfoKHR) == 64, "VkDisplaySurfaceCreateInfoKHR ABI mismatch");
_Static_assert(sizeof(VkHeadlessSurfaceCreateInfoEXT) == 24, "VkHeadlessSurfaceCreateInfoEXT ABI mismatch");
_Static_assert(sizeof(VkHdrMetadataEXT) == 64, "VkHdrMetadataEXT ABI mismatch");
#endif

typedef VkResult (VKAPI_PTR *PFN_xvk_GetPhysicalDeviceSurfacePresentModes2EXT)(
    VkPhysicalDevice physicalDevice,
    const VkPhysicalDeviceSurfaceInfo2KHR* pSurfaceInfo,
    uint32_t* pPresentModeCount,
    VkPresentModeKHR* pPresentModes);

static VkInstance g_xvk_bswap_instance = VK_NULL_HANDLE;

static const char* xvk_bswap_result_name(VkResult r)
{
    switch (r) {
        case VK_SUCCESS: return "VK_SUCCESS";
        case VK_NOT_READY: return "VK_NOT_READY";
        case VK_TIMEOUT: return "VK_TIMEOUT";
        case VK_INCOMPLETE: return "VK_INCOMPLETE";
        case VK_SUBOPTIMAL_KHR: return "VK_SUBOPTIMAL_KHR";
        case VK_ERROR_OUT_OF_HOST_MEMORY: return "VK_ERROR_OUT_OF_HOST_MEMORY";
        case VK_ERROR_OUT_OF_DEVICE_MEMORY: return "VK_ERROR_OUT_OF_DEVICE_MEMORY";
        case VK_ERROR_INITIALIZATION_FAILED: return "VK_ERROR_INITIALIZATION_FAILED";
        case VK_ERROR_DEVICE_LOST: return "VK_ERROR_DEVICE_LOST";
        case VK_ERROR_EXTENSION_NOT_PRESENT: return "VK_ERROR_EXTENSION_NOT_PRESENT";
        case VK_ERROR_FEATURE_NOT_PRESENT: return "VK_ERROR_FEATURE_NOT_PRESENT";
        case VK_ERROR_SURFACE_LOST_KHR: return "VK_ERROR_SURFACE_LOST_KHR";
        case VK_ERROR_NATIVE_WINDOW_IN_USE_KHR: return "VK_ERROR_NATIVE_WINDOW_IN_USE_KHR";
        case VK_ERROR_OUT_OF_DATE_KHR: return "VK_ERROR_OUT_OF_DATE_KHR";
        case VK_ERROR_INCOMPATIBLE_DISPLAY_KHR: return "VK_ERROR_INCOMPATIBLE_DISPLAY_KHR";
        case VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT: return "VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT";
        default: return "VK_ERROR_UNKNOWN";
    }
}

static int32_t xvk_bswap_check(const char* fn, VkResult res)
{
    if ((int32_t)res < 0) {
        xvk_set_error_fmt("%s failed: %s (%d)", fn, xvk_bswap_result_name(res), (int)res);
    }
    return (int32_t)res;
}

static PFN_vkVoidFunction xvk_bswap_instance_proc(const char* name)
{
    if (g_xvk_bswap_instance == VK_NULL_HANDLE) {
        xvk_set_error_fmt("%s: no VkInstance registered; call xvk_bind_swapchain_set_instance first", name);
        return NULL;
    }
    PFN_vkVoidFunction p = vkGetInstanceProcAddr(g_xvk_bswap_instance, name);
    if (!p) {
        xvk_set_error_fmt("%s: unavailable (instance extension not enabled)", name);
    }
    return p;
}

static PFN_vkVoidFunction xvk_bswap_device_proc(VkDevice dev, const char* name)
{
    PFN_vkVoidFunction p = vkGetDeviceProcAddr(dev, name);
    if (!p) {
        xvk_set_error_fmt("%s: unavailable (device extension not enabled)", name);
    }
    return p;
}

void xvk_bind_swapchain_set_instance(int64_t instance)
{
    g_xvk_bswap_instance = XVK_BSWAP_DH(VkInstance, instance);
}

/* ------------------------------------------------------------------ */
/* Surface queries                                                     */
/* ------------------------------------------------------------------ */

int32_t xvk_get_physical_device_surface_support_khr(int64_t phys_device, int32_t queue_family, int64_t surface, int64_t out_supported)
{
    VkPhysicalDevice pd = XVK_BSWAP_DH(VkPhysicalDevice, phys_device);
    VkBool32* supported = XVK_BSWAP_PTR(VkBool32*, out_supported);
    if (!pd || !surface || !supported) {
        xvk_set_error("xvk_get_physical_device_surface_support_khr: null argument");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkGetPhysicalDeviceSurfaceSupportKHR(pd, (uint32_t)queue_family,
                                                        XVK_BSWAP_NDH(VkSurfaceKHR, surface), supported);
    return xvk_bswap_check("vkGetPhysicalDeviceSurfaceSupportKHR", res);
}

int32_t xvk_get_physical_device_surface_capabilities_khr(int64_t phys_device, int64_t surface, int64_t out_caps)
{
    VkPhysicalDevice pd = XVK_BSWAP_DH(VkPhysicalDevice, phys_device);
    VkSurfaceCapabilitiesKHR* caps = XVK_BSWAP_PTR(VkSurfaceCapabilitiesKHR*, out_caps);
    if (!pd || !surface || !caps) {
        xvk_set_error("xvk_get_physical_device_surface_capabilities_khr: null argument");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(pd, XVK_BSWAP_NDH(VkSurfaceKHR, surface), caps);
    return xvk_bswap_check("vkGetPhysicalDeviceSurfaceCapabilitiesKHR", res);
}

int32_t xvk_get_physical_device_surface_formats_khr(int64_t phys_device, int64_t surface, int64_t out_count, int64_t out_formats)
{
    VkPhysicalDevice pd = XVK_BSWAP_DH(VkPhysicalDevice, phys_device);
    uint32_t* count = XVK_BSWAP_PTR(uint32_t*, out_count);
    VkSurfaceFormatKHR* formats = XVK_BSWAP_PTR(VkSurfaceFormatKHR*, out_formats);
    if (!pd || !surface || !count) {
        xvk_set_error("xvk_get_physical_device_surface_formats_khr: null argument");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkGetPhysicalDeviceSurfaceFormatsKHR(pd, XVK_BSWAP_NDH(VkSurfaceKHR, surface), count, formats);
    return xvk_bswap_check("vkGetPhysicalDeviceSurfaceFormatsKHR", res);
}

int32_t xvk_get_physical_device_surface_present_modes_khr(int64_t phys_device, int64_t surface, int64_t out_count, int64_t out_modes)
{
    VkPhysicalDevice pd = XVK_BSWAP_DH(VkPhysicalDevice, phys_device);
    uint32_t* count = XVK_BSWAP_PTR(uint32_t*, out_count);
    VkPresentModeKHR* modes = XVK_BSWAP_PTR(VkPresentModeKHR*, out_modes);
    if (!pd || !surface || !count) {
        xvk_set_error("xvk_get_physical_device_surface_present_modes_khr: null argument");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkGetPhysicalDeviceSurfacePresentModesKHR(pd, XVK_BSWAP_NDH(VkSurfaceKHR, surface), count, modes);
    return xvk_bswap_check("vkGetPhysicalDeviceSurfacePresentModesKHR", res);
}

/* ------------------------------------------------------------------ */
/* Swapchain                                                           */
/* ------------------------------------------------------------------ */

static int64_t xvk_bswap_create_swapchain(const char* fn, int64_t device, int64_t create_info_struct, int require_old)
{
    VkDevice dev = XVK_BSWAP_DH(VkDevice, device);
    const VkSwapchainCreateInfoKHR* src = XVK_BSWAP_PTR(const VkSwapchainCreateInfoKHR*, create_info_struct);
    if (!dev || !src) {
        xvk_set_error_fmt("%s: null device or create-info struct", fn);
        return 0;
    }
    VkSwapchainCreateInfoKHR ci;
    memcpy(&ci, src, sizeof(ci));
    ci.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    if (ci.surface == VK_NULL_HANDLE) {
        xvk_set_error_fmt("%s: create-info surface is null", fn);
        return 0;
    }
    if (require_old && ci.oldSwapchain == VK_NULL_HANDLE) {
        xvk_set_error_fmt("%s: oldSwapchain is null (use xvk_create_swapchain_khr for initial creation)", fn);
        return 0;
    }
    VkSwapchainKHR sc = VK_NULL_HANDLE;
    VkResult res = vkCreateSwapchainKHR(dev, &ci, NULL, &sc);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("%s: vkCreateSwapchainKHR failed: %s (%d)", fn, xvk_bswap_result_name(res), (int)res);
        return 0;
    }
    return XVK_BSWAP_H64(sc);
}

int64_t xvk_create_swapchain_khr(int64_t device, int64_t create_info_struct)
{
    return xvk_bswap_create_swapchain("xvk_create_swapchain_khr", device, create_info_struct, 0);
}

int64_t xvk_create_swapchain2_khr(int64_t device, int64_t create_info_struct)
{
    return xvk_bswap_create_swapchain("xvk_create_swapchain2_khr", device, create_info_struct, 1);
}

void xvk_destroy_swapchain_khr(int64_t device, int64_t swapchain)
{
    VkDevice dev = XVK_BSWAP_DH(VkDevice, device);
    if (!dev) {
        xvk_set_error("xvk_destroy_swapchain_khr: null device");
        return;
    }
    vkDestroySwapchainKHR(dev, XVK_BSWAP_NDH(VkSwapchainKHR, swapchain), NULL);
}

int32_t xvk_get_swapchain_images_khr(int64_t device, int64_t swapchain, int64_t out_count, int64_t out_images)
{
    VkDevice dev = XVK_BSWAP_DH(VkDevice, device);
    uint32_t* count = XVK_BSWAP_PTR(uint32_t*, out_count);
    VkImage* images = XVK_BSWAP_PTR(VkImage*, out_images);
    if (!dev || !swapchain || !count) {
        xvk_set_error("xvk_get_swapchain_images_khr: null argument");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkGetSwapchainImagesKHR(dev, XVK_BSWAP_NDH(VkSwapchainKHR, swapchain), count, images);
    return xvk_bswap_check("vkGetSwapchainImagesKHR", res);
}

int32_t xvk_acquire_next_image_khr(int64_t device, int64_t swapchain, int64_t timeout, int64_t semaphore, int64_t fence, int64_t out_image_index)
{
    VkDevice dev = XVK_BSWAP_DH(VkDevice, device);
    uint32_t* image_index = XVK_BSWAP_PTR(uint32_t*, out_image_index);
    if (!dev || !swapchain || !image_index) {
        xvk_set_error("xvk_acquire_next_image_khr: null argument");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkAcquireNextImageKHR(dev,
                                         XVK_BSWAP_NDH(VkSwapchainKHR, swapchain),
                                         (uint64_t)timeout,
                                         XVK_BSWAP_NDH(VkSemaphore, semaphore),
                                         XVK_BSWAP_NDH(VkFence, fence),
                                         image_index);
    return xvk_bswap_check("vkAcquireNextImageKHR", res);
}

int32_t xvk_queue_present_khr(int64_t queue, int64_t present_info_struct)
{
    VkQueue q = XVK_BSWAP_DH(VkQueue, queue);
    const VkPresentInfoKHR* src = XVK_BSWAP_PTR(const VkPresentInfoKHR*, present_info_struct);
    if (!q || !src) {
        xvk_set_error("xvk_queue_present_khr: null queue or present-info struct");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkPresentInfoKHR pi;
    memcpy(&pi, src, sizeof(pi));
    pi.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    if (pi.swapchainCount == 0 || pi.pSwapchains == NULL || pi.pImageIndices == NULL) {
        xvk_set_error("xvk_queue_present_khr: present-info has no swapchains or image indices");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkQueuePresentKHR(q, &pi);
    return xvk_bswap_check("vkQueuePresentKHR", res);
}

/* ------------------------------------------------------------------ */
/* VK_KHR_get_surface_capabilities2                                    */
/* ------------------------------------------------------------------ */

int32_t xvk_get_physical_device_surface_capabilities2_khr(int64_t phys_device, int64_t surface_info_struct, int64_t out_caps)
{
    VkPhysicalDevice pd = XVK_BSWAP_DH(VkPhysicalDevice, phys_device);
    const VkPhysicalDeviceSurfaceInfo2KHR* src = XVK_BSWAP_PTR(const VkPhysicalDeviceSurfaceInfo2KHR*, surface_info_struct);
    VkSurfaceCapabilities2KHR* caps = XVK_BSWAP_PTR(VkSurfaceCapabilities2KHR*, out_caps);
    if (!pd || !src || !caps) {
        xvk_set_error("xvk_get_physical_device_surface_capabilities2_khr: null argument");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    PFN_vkGetPhysicalDeviceSurfaceCapabilities2KHR pfn =
        (PFN_vkGetPhysicalDeviceSurfaceCapabilities2KHR)xvk_bswap_instance_proc("vkGetPhysicalDeviceSurfaceCapabilities2KHR");
    if (!pfn) {
        return (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT;
    }
    VkPhysicalDeviceSurfaceInfo2KHR info;
    memcpy(&info, src, sizeof(info));
    info.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SURFACE_INFO_2_KHR;
    if (caps->sType != VK_STRUCTURE_TYPE_SURFACE_CAPABILITIES_2_KHR) {
        caps->sType = VK_STRUCTURE_TYPE_SURFACE_CAPABILITIES_2_KHR;
        caps->pNext = NULL;
    }
    VkResult res = pfn(pd, &info, caps);
    return xvk_bswap_check("vkGetPhysicalDeviceSurfaceCapabilities2KHR", res);
}

int32_t xvk_get_physical_device_surface_formats2_khr(int64_t phys_device, int64_t surface_info_struct, int64_t out_count, int64_t out_formats)
{
    VkPhysicalDevice pd = XVK_BSWAP_DH(VkPhysicalDevice, phys_device);
    const VkPhysicalDeviceSurfaceInfo2KHR* src = XVK_BSWAP_PTR(const VkPhysicalDeviceSurfaceInfo2KHR*, surface_info_struct);
    uint32_t* count = XVK_BSWAP_PTR(uint32_t*, out_count);
    VkSurfaceFormat2KHR* formats = XVK_BSWAP_PTR(VkSurfaceFormat2KHR*, out_formats);
    if (!pd || !src || !count) {
        xvk_set_error("xvk_get_physical_device_surface_formats2_khr: null argument");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    PFN_vkGetPhysicalDeviceSurfaceFormats2KHR pfn =
        (PFN_vkGetPhysicalDeviceSurfaceFormats2KHR)xvk_bswap_instance_proc("vkGetPhysicalDeviceSurfaceFormats2KHR");
    if (!pfn) {
        return (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT;
    }
    VkPhysicalDeviceSurfaceInfo2KHR info;
    memcpy(&info, src, sizeof(info));
    info.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SURFACE_INFO_2_KHR;
    if (formats) {
        for (uint32_t i = 0; i < *count; ++i) {
            if (formats[i].sType != VK_STRUCTURE_TYPE_SURFACE_FORMAT_2_KHR) {
                formats[i].sType = VK_STRUCTURE_TYPE_SURFACE_FORMAT_2_KHR;
                formats[i].pNext = NULL;
            }
        }
    }
    VkResult res = pfn(pd, &info, count, formats);
    return xvk_bswap_check("vkGetPhysicalDeviceSurfaceFormats2KHR", res);
}

/* ------------------------------------------------------------------ */
/* VK_KHR_display                                                      */
/* ------------------------------------------------------------------ */

int32_t xvk_get_physical_device_display_properties_khr(int64_t phys_device, int64_t out_count, int64_t out_props)
{
    VkPhysicalDevice pd = XVK_BSWAP_DH(VkPhysicalDevice, phys_device);
    uint32_t* count = XVK_BSWAP_PTR(uint32_t*, out_count);
    VkDisplayPropertiesKHR* props = XVK_BSWAP_PTR(VkDisplayPropertiesKHR*, out_props);
    if (!pd || !count) {
        xvk_set_error("xvk_get_physical_device_display_properties_khr: null argument");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkGetPhysicalDeviceDisplayPropertiesKHR(pd, count, props);
    return xvk_bswap_check("vkGetPhysicalDeviceDisplayPropertiesKHR", res);
}

int32_t xvk_get_physical_device_display_plane_properties_khr(int64_t phys_device, int64_t out_count, int64_t out_props)
{
    VkPhysicalDevice pd = XVK_BSWAP_DH(VkPhysicalDevice, phys_device);
    uint32_t* count = XVK_BSWAP_PTR(uint32_t*, out_count);
    VkDisplayPlanePropertiesKHR* props = XVK_BSWAP_PTR(VkDisplayPlanePropertiesKHR*, out_props);
    if (!pd || !count) {
        xvk_set_error("xvk_get_physical_device_display_plane_properties_khr: null argument");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkGetPhysicalDeviceDisplayPlanePropertiesKHR(pd, count, props);
    return xvk_bswap_check("vkGetPhysicalDeviceDisplayPlanePropertiesKHR", res);
}

int32_t xvk_get_display_plane_supported_displays_khr(int64_t phys_device, int32_t plane_index, int64_t out_count, int64_t out_displays)
{
    VkPhysicalDevice pd = XVK_BSWAP_DH(VkPhysicalDevice, phys_device);
    uint32_t* count = XVK_BSWAP_PTR(uint32_t*, out_count);
    VkDisplayKHR* displays = XVK_BSWAP_PTR(VkDisplayKHR*, out_displays);
    if (!pd || !count) {
        xvk_set_error("xvk_get_display_plane_supported_displays_khr: null argument");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkGetDisplayPlaneSupportedDisplaysKHR(pd, (uint32_t)plane_index, count, displays);
    return xvk_bswap_check("vkGetDisplayPlaneSupportedDisplaysKHR", res);
}

int32_t xvk_get_display_mode_properties_khr(int64_t phys_device, int64_t display, int64_t out_count, int64_t out_modes)
{
    VkPhysicalDevice pd = XVK_BSWAP_DH(VkPhysicalDevice, phys_device);
    uint32_t* count = XVK_BSWAP_PTR(uint32_t*, out_count);
    VkDisplayModePropertiesKHR* modes = XVK_BSWAP_PTR(VkDisplayModePropertiesKHR*, out_modes);
    if (!pd || !display || !count) {
        xvk_set_error("xvk_get_display_mode_properties_khr: null argument");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkGetDisplayModePropertiesKHR(pd, XVK_BSWAP_NDH(VkDisplayKHR, display), count, modes);
    return xvk_bswap_check("vkGetDisplayModePropertiesKHR", res);
}

int64_t xvk_create_display_mode_khr(int64_t phys_device, int64_t display, int64_t create_info_struct)
{
    VkPhysicalDevice pd = XVK_BSWAP_DH(VkPhysicalDevice, phys_device);
    const VkDisplayModeCreateInfoKHR* src = XVK_BSWAP_PTR(const VkDisplayModeCreateInfoKHR*, create_info_struct);
    if (!pd || !display || !src) {
        xvk_set_error("xvk_create_display_mode_khr: null argument");
        return 0;
    }
    VkDisplayModeCreateInfoKHR ci;
    memcpy(&ci, src, sizeof(ci));
    ci.sType = VK_STRUCTURE_TYPE_DISPLAY_MODE_CREATE_INFO_KHR;
    VkDisplayModeKHR mode = VK_NULL_HANDLE;
    VkResult res = vkCreateDisplayModeKHR(pd, XVK_BSWAP_NDH(VkDisplayKHR, display), &ci, NULL, &mode);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateDisplayModeKHR failed: %s (%d)", xvk_bswap_result_name(res), (int)res);
        return 0;
    }
    return XVK_BSWAP_H64(mode);
}

int32_t xvk_get_display_plane_capabilities_khr(int64_t phys_device, int64_t mode, int32_t plane_index, int64_t out_caps)
{
    VkPhysicalDevice pd = XVK_BSWAP_DH(VkPhysicalDevice, phys_device);
    VkDisplayPlaneCapabilitiesKHR* caps = XVK_BSWAP_PTR(VkDisplayPlaneCapabilitiesKHR*, out_caps);
    if (!pd || !mode || !caps) {
        xvk_set_error("xvk_get_display_plane_capabilities_khr: null argument");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    VkResult res = vkGetDisplayPlaneCapabilitiesKHR(pd, XVK_BSWAP_NDH(VkDisplayModeKHR, mode), (uint32_t)plane_index, caps);
    return xvk_bswap_check("vkGetDisplayPlaneCapabilitiesKHR", res);
}

int64_t xvk_create_display_plane_surface_khr(int64_t instance, int64_t create_info_struct)
{
    VkInstance inst = XVK_BSWAP_DH(VkInstance, instance);
    const VkDisplaySurfaceCreateInfoKHR* src = XVK_BSWAP_PTR(const VkDisplaySurfaceCreateInfoKHR*, create_info_struct);
    if (!inst || !src) {
        xvk_set_error("xvk_create_display_plane_surface_khr: null instance or create-info struct");
        return 0;
    }
    VkDisplaySurfaceCreateInfoKHR ci;
    memcpy(&ci, src, sizeof(ci));
    ci.sType = VK_STRUCTURE_TYPE_DISPLAY_SURFACE_CREATE_INFO_KHR;
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    VkResult res = vkCreateDisplayPlaneSurfaceKHR(inst, &ci, NULL, &surface);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateDisplayPlaneSurfaceKHR failed: %s (%d)", xvk_bswap_result_name(res), (int)res);
        return 0;
    }
    g_xvk_bswap_instance = inst;
    return XVK_BSWAP_H64(surface);
}

/* ------------------------------------------------------------------ */
/* VK_EXT_headless_surface                                             */
/* ------------------------------------------------------------------ */

int64_t xvk_create_headless_surface_ext(int64_t instance, int64_t create_info_struct)
{
    VkInstance inst = XVK_BSWAP_DH(VkInstance, instance);
    if (!inst) {
        xvk_set_error("xvk_create_headless_surface_ext: null instance");
        return 0;
    }
    PFN_vkCreateHeadlessSurfaceEXT pfn =
        (PFN_vkCreateHeadlessSurfaceEXT)vkGetInstanceProcAddr(inst, "vkCreateHeadlessSurfaceEXT");
    if (!pfn) {
        xvk_set_error("vkCreateHeadlessSurfaceEXT: unavailable (VK_EXT_headless_surface not enabled)");
        return 0;
    }
    VkHeadlessSurfaceCreateInfoEXT ci;
    memset(&ci, 0, sizeof(ci));
    if (create_info_struct) {
        memcpy(&ci, XVK_BSWAP_PTR(const void*, create_info_struct), sizeof(ci));
    }
    ci.sType = VK_STRUCTURE_TYPE_HEADLESS_SURFACE_CREATE_INFO_EXT;
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    VkResult res = pfn(inst, &ci, NULL, &surface);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateHeadlessSurfaceEXT failed: %s (%d)", xvk_bswap_result_name(res), (int)res);
        return 0;
    }
    g_xvk_bswap_instance = inst;
    return XVK_BSWAP_H64(surface);
}

/* ------------------------------------------------------------------ */
/* VK_EXT_hdr_metadata                                                 */
/* ------------------------------------------------------------------ */

void xvk_set_hdr_metadata_ext(int64_t device, int32_t swapchain_count, int64_t swapchains, int64_t metadata_struct)
{
    VkDevice dev = XVK_BSWAP_DH(VkDevice, device);
    const VkSwapchainKHR* scs = XVK_BSWAP_PTR(const VkSwapchainKHR*, swapchains);
    VkHdrMetadataEXT* metadata = XVK_BSWAP_PTR(VkHdrMetadataEXT*, metadata_struct);
    if (!dev || swapchain_count <= 0 || !scs || !metadata) {
        xvk_set_error("xvk_set_hdr_metadata_ext: null argument or non-positive swapchain count");
        return;
    }
    PFN_vkSetHdrMetadataEXT pfn = (PFN_vkSetHdrMetadataEXT)xvk_bswap_device_proc(dev, "vkSetHdrMetadataEXT");
    if (!pfn) {
        return;
    }
    for (int32_t i = 0; i < swapchain_count; ++i) {
        if (metadata[i].sType != VK_STRUCTURE_TYPE_HDR_METADATA_EXT) {
            metadata[i].sType = VK_STRUCTURE_TYPE_HDR_METADATA_EXT;
            metadata[i].pNext = NULL;
        }
    }
    pfn(dev, (uint32_t)swapchain_count, scs, metadata);
}

/* ------------------------------------------------------------------ */
/* VK_EXT_full_screen_exclusive                                        */
/* ------------------------------------------------------------------ */

int32_t xvk_get_physical_device_surface_present_modes2_ext(int64_t phys_device, int64_t surface_info_struct, int64_t out_count, int64_t out_modes)
{
    VkPhysicalDevice pd = XVK_BSWAP_DH(VkPhysicalDevice, phys_device);
    const VkPhysicalDeviceSurfaceInfo2KHR* src = XVK_BSWAP_PTR(const VkPhysicalDeviceSurfaceInfo2KHR*, surface_info_struct);
    uint32_t* count = XVK_BSWAP_PTR(uint32_t*, out_count);
    VkPresentModeKHR* modes = XVK_BSWAP_PTR(VkPresentModeKHR*, out_modes);
    if (!pd || !src || !count) {
        xvk_set_error("xvk_get_physical_device_surface_present_modes2_ext: null argument");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    PFN_xvk_GetPhysicalDeviceSurfacePresentModes2EXT pfn =
        (PFN_xvk_GetPhysicalDeviceSurfacePresentModes2EXT)xvk_bswap_instance_proc("vkGetPhysicalDeviceSurfacePresentModes2EXT");
    if (!pfn) {
        return (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT;
    }
    VkPhysicalDeviceSurfaceInfo2KHR info;
    memcpy(&info, src, sizeof(info));
    info.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SURFACE_INFO_2_KHR;
    VkResult res = pfn(pd, &info, count, modes);
    return xvk_bswap_check("vkGetPhysicalDeviceSurfacePresentModes2EXT", res);
}

/* ------------------------------------------------------------------ */
/* VK_KHR_shared_presentable_image                                     */
/* ------------------------------------------------------------------ */

int32_t xvk_get_swapchain_status_khr(int64_t device, int64_t swapchain)
{
    VkDevice dev = XVK_BSWAP_DH(VkDevice, device);
    if (!dev || !swapchain) {
        xvk_set_error("xvk_get_swapchain_status_khr: null argument");
        return (int32_t)VK_ERROR_INITIALIZATION_FAILED;
    }
    PFN_vkGetSwapchainStatusKHR pfn = (PFN_vkGetSwapchainStatusKHR)xvk_bswap_device_proc(dev, "vkGetSwapchainStatusKHR");
    if (!pfn) {
        return (int32_t)VK_ERROR_EXTENSION_NOT_PRESENT;
    }
    VkResult res = pfn(dev, XVK_BSWAP_NDH(VkSwapchainKHR, swapchain));
    return xvk_bswap_check("vkGetSwapchainStatusKHR", res);
}

#undef XVK_BSWAP_DH
#undef XVK_BSWAP_NDH
#undef XVK_BSWAP_PTR
#undef XVK_BSWAP_H64
