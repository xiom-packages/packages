# xiom-vulkan — 100% Vulkan SDK Coverage Architecture

**Date:** 2026-07-18  
**Compiler:** xiomc v0.47.7  

## Architecture Overview

```
ecosystem/xiom-vulkan/
├── vulkan_extern.xi          (768 lines)  755 VK functions — complete 1.3 core + KHR/EXT/NV
├── vulkan.xi                 ( ~400 lines) Simplified demo API (create_app, draw_*, etc.)
├── src/
│   ├── wrapper.xi            ( ~200 lines) Demo-specific helpers (VK_APP_DESTROY etc.)
│   ├── vulkan_safe.xi        (1439 lines) 29 resource-type safe wrappers
│   ├── vulkan_structs.xi     ( 163 lines) Struct marshalling helpers
│   ├── vulkan_constants_all.xi (274 KB)   3691 VK constants
│   └── vulkan_constants*.xi  (legacy)     Split constant files (deprecated, merged)
├── bridge/
│   ├── xiom_vk_bridge.c      ( 14 lines)  Integration: #includes bridge/xvk_bridge.h
│   ├── xvk_bridge.obj        (118 KB)     Prebuilt x64 object
│   ├── xvk_bridge.h          (master)     Includes all module headers
│   ├── xvk_shaders.h                      SPIR-V extern declarations
│   ├── xvk_shaders_generated.h            Generated SPIR-V data arrays (15 shaders)
│   ├── xvk_types.h                        Resource types + magic constants
│   ├── xvk_util.h/c                       Error reporting, handle helpers
│   ├── xvk_math.h/c                       Matrix math
│   ├── xvk_instance.h/c                   Instance + device creation
│   ├── xvk_swapchain.h/c                  Swapchain management
│   ├── xvk_pipeline.h/c                   Pipelines + shader modules + sync objects
│   ├── xvk_renderpass.h/c                 Render passes + framebuffers
│   ├── xvk_descriptor.h/c                 Descriptor sets (Phase 1)
│   ├── xvk_buffer.h/c                     Buffer/image/sampler create/destroy/map
│   ├── xvk_command.h/c                    Bind/draw commands + custom passes
│   ├── xvk_query.h/c                      [NEW] Query pool create/destroy/timestamp
│   ├── xvk_legacy.h/c                     Legacy drawing API (2D/3D/particles)
│   ├── xvk_offscreen.h/c                  Offscreen rendering
│   ├── xvk_frame.h/c                      Frame lifecycle (begin/end/clear)
│   └── xvk_app.h/c                        App lifecycle (create/destroy/poll)
├── examples/                 11 demo .xi files
├── tests/                    test_vulkan.xi
├── shaders/                  15 GLSL shader sources
├── build.ps1                 Full pipeline script (12 targets)
├── run.ps1                   Single-command build+run
├── BRIDGE_AUDIT.md           Detailed VK function audit
└── AUDIT.md                  Compiler gap tracking
```

## Coverage Matrix

| Layer | Functions | Status |
|-------|-----------|--------|
| **vulkan_extern.xi** | 755 extern "C" declarations | 100% VK 1.3 core + KHR/EXT/NV/AMD/ARM/INTEL/QCOM |
| **vulkan_safe.xi** | 29 resource types | 29/29 with create/destroy + contracts |
| **vulkan_constants_all.xi** | 3691 constants | All VK_* enums, flags, structure types |
| **C bridge (xvk_*)** | ~50 simplified functions + Phase 1 API | VK 1.3 apiVersion + dynamic state + dynamic rendering + sync2 |
| **Struct marshalling** | vk_instance_create_info, vk_desc_binding | Builders for common structs |

## Safe Wrapper Types (29)

| # | Type | Wraps |
|---|------|-------|
| 1 | VulkanInstance | vkCreateInstance/vkDestroyInstance |
| 2 | VulkanDevice | vkCreateDevice/vkDestroyDevice + queue/memory ops |
| 3 | VulkanBuffer | vkCreateBuffer/vkDestroyBuffer + bind/map/unmap |
| 4 | VulkanImage | vkCreateImage/vkDestroyImage + bind |
| 5 | VulkanImageView | vkCreateImageView/vkDestroyImageView |
| 6 | VulkanPipeline | vkCreateGraphicsPipelines/vkCreateComputePipelines/vkDestroyPipeline + bind |
| 7 | VulkanPipelineLayout | vkCreatePipelineLayout/vkDestroyPipelineLayout |
| 8 | VulkanShaderModule | vkCreateShaderModule/vkDestroyShaderModule |
| 9 | VulkanCommandPool | vkCreateCommandPool/vkDestroyCommandPool + reset |
| 10 | VulkanCommandBuffer | vkAllocateCommandBuffers/vkFreeCommandBuffers + begin/end/submit/draw/dispatch/barrier/begin_rendering/end_rendering |
| 11 | VulkanDescriptorPool | vkCreateDescriptorPool/vkDestroyDescriptorPool + reset |
| 12 | VulkanDescriptorSetLayout | vkCreateDescriptorSetLayout/vkDestroyDescriptorSetLayout |
| 13 | VulkanDescriptorSet | vkAllocateDescriptorSets/vkFreeDescriptorSets + bind |
| 14 | VulkanFence | vkCreateFence/vkDestroyFence + wait/reset/status |
| 15 | VulkanSemaphore | vkCreateSemaphore/vkDestroySemaphore |
| 16 | VulkanRenderPass | vkCreateRenderPass/vkDestroyRenderPass |
| 17 | VulkanFramebuffer | vkCreateFramebuffer/vkDestroyFramebuffer |
| 18 | VulkanSwapchain | vkCreateSwapchainKHR/vkDestroySwapchainKHR + acquire |
| 19 | VulkanSampler | vkCreateSampler/vkDestroySampler |
| 20 | VulkanEvent | vkCreateEvent/vkDestroyEvent + get_status/set/reset |
| 21 | VulkanQueryPool | vkCreateQueryPool/vkDestroyQueryPool + get_results/begin/end/reset/timestamp/copy |
| 22 | VulkanPipelineCache | vkCreatePipelineCache/vkDestroyPipelineCache + get_data/merge |
| 23 | VulkanBufferView | vkCreateBufferView/vkDestroyBufferView |
| 24 | VulkanDebugUtilsMessenger | vkCreateDebugUtilsMessengerEXT/vkDestroyDebugUtilsMessengerEXT |
| 25 | VulkanAccelerationStructureKHR | vkCreateAccelerationStructureKHR/vkDestroyAccelerationStructureKHR |
| 26 | VulkanSurfaceKHR | vkDestroySurfaceKHR (create is platform-specific) |
| 27 | VulkanPhysicalDevice | vkGetPhysicalDeviceProperties/Features/MemoryProperties/QueueFamilyProperties |
| 28 | VulkanDeviceMemory | vkAllocateMemory/vkFreeMemory + map/unmap |
| 29 | VulkanDescriptorUpdateTemplate | vkCreateDescriptorUpdateTemplate/vkDestroyDescriptorUpdateTemplate |

## C Bridge Modules (16)

| Module | Lines | Purpose |
|--------|-------|---------|
| xvk_types.h | ~110 | Resource types, magic, XVK_HANDLE_IMPL |
| xvk_util.h/c | ~80 | Error reporting, handle helpers |
| xvk_math.h/c | ~80 | Matrix math (identity, mul, perspective, lookat, rot, translate) |
| xvk_instance.h/c | ~220 | Instance + device creation with VK 1.3 features |
| xvk_swapchain.h/c | ~180 | Swapchain lifecycle + format/PM/extent selection |
| xvk_pipeline.h/c | ~250 | Shader modules, pipeline layouts, graphics/compute pipelines, sync objects |
| xvk_renderpass.h/c | ~200 | Render passes + framebuffers (windowed, offscreen, Phase 1) |
| xvk_descriptor.h/c | ~280 | Descriptor set layouts, pools, sets, writes |
| xvk_buffer.h/c | ~240 | Buffer/image/sampler create/destroy/map/write/read |
| xvk_command.h/c | ~220 | Bind commands, custom passes, layout transitions |
| xvk_query.h/c | ~60 | [NEW] Query pool create/destroy/timestamp/get_results |
| xvk_legacy.h/c | ~380 | draw_triangle_2d, draw_cube_3d, draw_quad_2d, particles |
| xvk_offscreen.h/c | ~160 | Offscreen render target, triangle, pixel readback, hash |
| xvk_frame.h/c | ~180 | begin_frame, end_frame, set_clear_color, poll |
| xvk_app.h/c | ~140 | app_create, app_destroy, lifecycle |

## VK 1.3 Feature Status

| Feature | Status |
|---------|--------|
| apiVersion | VK_API_VERSION_1_3 ✓ |
| Dynamic state (viewport+scissor) | ✓ Enabled in all pipelines |
| Dynamic rendering | ✓ Features enabled, ABI in VulkanCommandBuffer |
| Synchronization2 | ✓ Features enabled |
| Sampler anisotropy | ✓ Device feature enabled |
| Fill mode non-solid | ✓ Device feature enabled |
| Wide lines | ✓ Device feature enabled |
| Debug utils | ✓ In vulkan_safe.xi + vulkan_extern.xi |
| Timeline semaphores | ✓ Externs present, pending ABI |
| Query pools | ✓ Safe wrapper + C module |
| Ray tracing (KHR) | ✓ Externs + safe wrapper (AccelerationStructureKHR) |
| Mesh shaders | ✓ Externs present (EXT/NV) |
| Video encode/decode | ✓ Externs present (KHR) |
| Fragment shading rate | ✓ Externs present (KHR) |

## Build Commands

```powershell
cd ecosystem\xiom-vulkan

# Full pipeline (shaders → header → bridge → xiomc → run):
.\build.ps1 -Target demo2d -Run

# Direct xiomc (skip shader/bridge rebuild):
xiomc -o demo_2d.exe examples/demo_2d.xi vulkan.xi src/wrapper.xi `
  --c-source bridge/xvk_bridge.obj `
  --link vulkan-1 --link glfw3 --link gdi32 --link user32 --link kernel32 --link shell32 --link ole32 `
  --link-path $env:VULKAN_SDK\Lib --link-path $env:GLFW_DIR\lib-vc2022 --run

# Safe wrapper usage (29 resource types available):
#   use xiom.vulkan.safe;
#   let inst = VulkanInstance.create(ci).unwrap();
#   let dev  = VulkanDevice.create(phys, dci).unwrap();
#   let buf  = VulkanBuffer.create(dev.handle, bci).unwrap();
#   buf.destroy();
```
