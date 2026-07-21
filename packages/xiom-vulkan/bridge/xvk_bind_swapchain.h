#ifndef XVK_BIND_SWAPCHAIN_H_
#define XVK_BIND_SWAPCHAIN_H_

#include <stdint.h>

/*
 * xvk_bind_swapchain — direct VkSurfaceKHR / VkSwapchainKHR API bindings.
 *
 * Conventions (shared with all xvk_bind_* modules):
 *   - Every Vulkan handle crosses the FFI boundary as int64_t (0 = VK_NULL_HANDLE).
 *   - `*_struct` parameters are addresses (as int64_t) of native-layout Vulkan
 *     structs built with the xvk_structs.h marshalling helpers.
 *   - int32_t returns are raw VkResult values. Negative results additionally
 *     store a message retrievable via xvk_last_error().
 *   - Handle-returning creators return 0 on failure and set the error string.
 *   - The bridge ensures the correct top-level sType on input structs, so the
 *     XIOM side may leave sType zeroed. pNext chains are passed through.
 *   - Out structs carrying sType/pNext headers (VkSurfaceCapabilities2KHR,
 *     VkSurfaceFormat2KHR) may be zero-initialized; the bridge fills in sType
 *     and clears pNext when they are not pre-set.
 *   - Count/array queries follow the standard Vulkan two-call idiom:
 *     pass out array = 0 to query the count, then call again with a buffer
 *     (out_count then holds the buffer capacity in elements).
 *
 * Input struct field offsets (64-bit):
 *   VkSwapchainCreateInfoKHR (104 bytes):
 *     sType=0 pNext=8 flags=16 surface=24 minImageCount=32 imageFormat=36
 *     imageColorSpace=40 imageExtent=44 (width=44,height=48) imageArrayLayers=52
 *     imageUsage=56 imageSharingMode=60 queueFamilyIndexCount=64
 *     pQueueFamilyIndices=72 preTransform=80 compositeAlpha=84 presentMode=88
 *     clipped=92 oldSwapchain=96
 *   VkPresentInfoKHR (64 bytes):
 *     sType=0 pNext=8 waitSemaphoreCount=16 pWaitSemaphores=24
 *     swapchainCount=32 pSwapchains=40 pImageIndices=48 pResults=56
 *   VkPhysicalDeviceSurfaceInfo2KHR (24 bytes): sType=0 pNext=8 surface=16
 *   VkDisplayModeCreateInfoKHR (32 bytes):
 *     sType=0 pNext=8 flags=16 parameters.visibleRegion.width=20 .height=24
 *     parameters.refreshRate=28
 *   VkDisplaySurfaceCreateInfoKHR (64 bytes):
 *     sType=0 pNext=8 flags=16 displayMode=24 planeIndex=32 planeStackIndex=36
 *     transform=40 globalAlpha=44 alphaMode=48 imageExtent.width=52 .height=56
 *   VkHeadlessSurfaceCreateInfoEXT (24 bytes): sType=0 pNext=8 flags=16
 *   VkHdrMetadataEXT (64 bytes, array of swapchain_count entries):
 *     sType=0 pNext=8 displayPrimaryRed=16,20 displayPrimaryGreen=24,28
 *     displayPrimaryBlue=32,36 whitePoint=40,44 maxLuminance=48 minLuminance=52
 *     maxContentLightLevel=56 maxFrameAverageLightLevel=60
 *
 * Out-struct sizes for pre-allocation on the XIOM side:
 *   VkBool32=4  uint32_t=4  VkImage=8  VkDisplayKHR=8  VkPresentModeKHR=4
 *   VkSurfaceFormatKHR=8 (format=0,colorSpace=4)
 *   VkSurfaceCapabilitiesKHR=52  VkSurfaceCapabilities2KHR=72 (caps start at 16)
 *   VkSurfaceFormat2KHR=24 (format=16,colorSpace=20)
 *   VkDisplayPropertiesKHR=48  VkDisplayPlanePropertiesKHR=16
 *   VkDisplayModePropertiesKHR=24  VkDisplayPlaneCapabilitiesKHR=68
 */

/*
 * Register the VkInstance used to resolve instance-level extension entry
 * points (vkGetPhysicalDeviceSurfaceCapabilities2KHR,
 * vkGetPhysicalDeviceSurfaceFormats2KHR,
 * vkGetPhysicalDeviceSurfacePresentModes2EXT). Called automatically by
 * xvk_create_display_plane_surface_khr and xvk_create_headless_surface_ext.
 */
void xvk_bind_swapchain_set_instance(int64_t instance);

/* Surface queries */
int32_t xvk_get_physical_device_surface_support_khr(int64_t phys_device, int32_t queue_family, int64_t surface, int64_t out_supported);
int32_t xvk_get_physical_device_surface_capabilities_khr(int64_t phys_device, int64_t surface, int64_t out_caps);
int32_t xvk_get_physical_device_surface_formats_khr(int64_t phys_device, int64_t surface, int64_t out_count, int64_t out_formats);
int32_t xvk_get_physical_device_surface_present_modes_khr(int64_t phys_device, int64_t surface, int64_t out_count, int64_t out_modes);

/* Swapchain */
int64_t xvk_create_swapchain_khr(int64_t device, int64_t create_info_struct);
void xvk_destroy_swapchain_khr(int64_t device, int64_t swapchain);
int32_t xvk_get_swapchain_images_khr(int64_t device, int64_t swapchain, int64_t out_count, int64_t out_images);
int32_t xvk_acquire_next_image_khr(int64_t device, int64_t swapchain, int64_t timeout, int64_t semaphore, int64_t fence, int64_t out_image_index);
int32_t xvk_queue_present_khr(int64_t queue, int64_t present_info_struct);

/* VK_KHR_get_surface_capabilities2 */
int32_t xvk_get_physical_device_surface_capabilities2_khr(int64_t phys_device, int64_t surface_info_struct, int64_t out_caps);
int32_t xvk_get_physical_device_surface_formats2_khr(int64_t phys_device, int64_t surface_info_struct, int64_t out_count, int64_t out_formats);

/* VK_KHR_swapchain v2 (swapchain creation with oldSwapchain for resize) */
int64_t xvk_create_swapchain2_khr(int64_t device, int64_t create_info_struct);

/* VK_KHR_display / VK_KHR_get_display_properties2 */
int32_t xvk_get_physical_device_display_properties_khr(int64_t phys_device, int64_t out_count, int64_t out_props);
int32_t xvk_get_physical_device_display_plane_properties_khr(int64_t phys_device, int64_t out_count, int64_t out_props);
int32_t xvk_get_display_plane_supported_displays_khr(int64_t phys_device, int32_t plane_index, int64_t out_count, int64_t out_displays);
int32_t xvk_get_display_mode_properties_khr(int64_t phys_device, int64_t display, int64_t out_count, int64_t out_modes);
int64_t xvk_create_display_mode_khr(int64_t phys_device, int64_t display, int64_t create_info_struct);
int32_t xvk_get_display_plane_capabilities_khr(int64_t phys_device, int64_t mode, int32_t plane_index, int64_t out_caps);
int64_t xvk_create_display_plane_surface_khr(int64_t instance, int64_t create_info_struct);

/* VK_EXT_headless_surface */
int64_t xvk_create_headless_surface_ext(int64_t instance, int64_t create_info_struct);

/* VK_EXT_swapchain_maintenance1 / VK_EXT_hdr_metadata */
void xvk_set_hdr_metadata_ext(int64_t device, int32_t swapchain_count, int64_t swapchains, int64_t metadata_struct);

/* VK_EXT_full_screen_exclusive */
int32_t xvk_get_physical_device_surface_present_modes2_ext(int64_t phys_device, int64_t surface_info_struct, int64_t out_count, int64_t out_modes);

/* VK_KHR_shared_presentable_image */
int32_t xvk_get_swapchain_status_khr(int64_t device, int64_t swapchain);

#endif /* XVK_BIND_SWAPCHAIN_H_ */
