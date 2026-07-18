#ifndef XVK_SWAPCHAIN_H_
#define XVK_SWAPCHAIN_H_

#include "xvk_types.h"
#include "xvk_util.h"

VkSurfaceFormatKHR pick_swapchain_fmt(VkPhysicalDevice pd, VkSurfaceKHR surface);
VkPresentModeKHR pick_present_mode(VkPhysicalDevice pd, VkSurfaceKHR surface);
VkExtent2D pick_extent(VkPhysicalDevice pd, VkSurfaceKHR surface, GLFWwindow* win);
int create_depth_resources(XvkApp* a);
int create_swapchain(XvkApp* a);
void cleanup_swapchain(XvkApp* a);
int recreate_swapchain(XvkApp* a);

#endif
