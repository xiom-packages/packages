#ifndef XVK_BRIDGE_H_
#define XVK_BRIDGE_H_
#define _CRT_SECURE_NO_WARNINGS
#include <stdint.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
#include <vulkan/vulkan.h>
#define GLFW_INCLUDE_VULKAN
#include <GLFW/glfw3.h>

#include "xvk_shaders.h"
#include "xvk_types.h"
#include "xvk_util.h"
#include "xvk_math.h"

/* Struct marshalling + direct VK bindings (100% VK API coverage) */
#include "xvk_structs.h"
#include "xvk_bind_instance.h"
#include "xvk_bind_device.h"
#include "xvk_bind_swapchain.h"
#include "xvk_bind_buffer.h"
#include "xvk_bind_image.h"
#include "xvk_bind_memory.h"
#include "xvk_bind_pipeline.h"
#include "xvk_bind_descriptor.h"
#include "xvk_bind_renderpass.h"
#include "xvk_bind_command.h"
#include "xvk_bind_sync.h"
#include "xvk_bind_query.h"
#include "xvk_bind_extensions.h"
#include "xvk_bind_raytracing.h"

/* Legacy app lifecycle + simplified demo API */
#include "xvk_memory_alloc.h"
#include "xvk_shader_compile.h"
#include "xvk_texture.h"
#include "xvk_instance.h"
#include "xvk_swapchain.h"
#include "xvk_pipeline.h"
#include "xvk_renderpass.h"
#include "xvk_descriptor.h"
#include "xvk_buffer.h"
#include "xvk_command.h"
#include "xvk_query.h"
#include "xvk_legacy.h"
#include "xvk_offscreen.h"
#include "xvk_frame.h"
#include "xvk_app.h"

#include "xiom_vk_bridge.h"
#endif
