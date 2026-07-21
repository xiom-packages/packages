#ifndef XVK_INSTANCE_H_
#define XVK_INSTANCE_H_

#include "xvk_types.h"
#include "xvk_util.h"

VkInstance create_instance(const char* app_name, int* have_validation);
VkInstance create_instance_headless(const char* app_name, int* have_validation);
int pick_physical_device(VkInstance inst, VkSurfaceKHR surface,
                          VkPhysicalDevice* out_pd, int* out_type);
VkDevice create_device(VkPhysicalDevice pd, uint32_t gfx_family,
                        uint32_t pres_family, VkSurfaceKHR surface);
VkSurfaceKHR create_surface(VkInstance inst, GLFWwindow* win);

#endif
