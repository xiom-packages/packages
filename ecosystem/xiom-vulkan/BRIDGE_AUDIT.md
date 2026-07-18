# XIOM Vulkan Bridge — Production Audit

**File:** `bridge/xiom_vk_bridge.c` (3984 lines)  
**Date:** 2026-07-18  
**Compiler:** xiomc v0.47.7

## Executive Summary

The bridge uses **82 unique real Vulkan API functions**, all calling through to the actual driver with zero stubs or simulated calls. Coverage is approximately **Vulkan 1.0 core level** — adequate for 2D/3D visualization, offscreen rendering, and basic compute. ~60 advanced Vulkan features are absent (MSAA, indirect draw, dynamic state, tessellation, ray tracing, etc.).

---

## (A) Fully Implemented — 82 Real Vulkan Functions

### Instance / Device / Surface (12)
`vkCreateInstance`, `vkEnumerateInstanceLayerProperties`, `vkEnumeratePhysicalDevices`, `vkGetPhysicalDeviceProperties`, `vkGetPhysicalDeviceQueueFamilyProperties`, `vkGetPhysicalDeviceSurfaceSupportKHR`, `vkCreateDevice`, `vkGetDeviceQueue`, `vkGetPhysicalDeviceMemoryProperties`, `vkDestroyInstance`, `vkDestroySurfaceKHR`, `vkDestroyDevice`

### Swapchain (8)
`vkGetPhysicalDeviceSurfaceFormatsKHR`, `vkGetPhysicalDeviceSurfacePresentModesKHR`, `vkGetPhysicalDeviceSurfaceCapabilitiesKHR`, `vkCreateSwapchainKHR`, `vkGetSwapchainImagesKHR`, `vkAcquireNextImageKHR`, `vkQueuePresentKHR`, `vkDestroySwapchainKHR`

### Image / Buffer / Memory (13)
`vkCreateImage`, `vkGetImageMemoryRequirements`, `vkBindImageMemory`, `vkCreateImageView`, `vkCreateBuffer`, `vkGetBufferMemoryRequirements`, `vkBindBufferMemory`, `vkAllocateMemory`, `vkMapMemory`, `vkUnmapMemory`, `vkFreeMemory`, `vkDestroyImage`/`vkDestroyImageView`/`vkDestroyBuffer`

### Render Pass / Framebuffer (3)
`vkCreateRenderPass`, `vkCreateFramebuffer`, destroy counterparts

### Shader Modules (2)
`vkCreateShaderModule`, `vkDestroyShaderModule`

### Pipeline (4)
`vkCreatePipelineLayout`, `vkCreateGraphicsPipelines`, `vkCreateComputePipelines`, destroy counterparts

### Descriptor Sets (5)
`vkCreateDescriptorSetLayout`, `vkCreateDescriptorPool`, `vkAllocateDescriptorSets`, `vkUpdateDescriptorSets`, `vkFreeDescriptorSets`

### Sampler (2)
`vkCreateSampler`, `vkDestroySampler`

### Command Recording (14)
`vkCreateCommandPool`, `vkAllocateCommandBuffers`, `vkResetCommandBuffer`, `vkBeginCommandBuffer`, `vkEndCommandBuffer`, `vkCmdBeginRenderPass`, `vkCmdEndRenderPass`, `vkCmdBindPipeline`, `vkCmdPushConstants`, `vkCmdBindVertexBuffers`, `vkCmdBindIndexBuffer`, `vkCmdBindDescriptorSets`, `vkCmdDraw`, `vkCmdDrawIndexed`, `vkCmdPipelineBarrier`, `vkCmdCopyImageToBuffer`, `vkCmdDispatch`

### Synchronization (5)
`vkCreateSemaphore`, `vkCreateFence`, `vkWaitForFences`, `vkResetFences`, `vkQueueSubmit`, `vkDeviceWaitIdle`

---

## (B) Hardcoded / Simulated Design Patterns (0 API stubs)

| Pattern | Detail |
|---------|--------|
| Shader-generated vertices | Triangle/cube/quad geometry baked in SPIR-V via `gl_VertexIndex` — no configurable VBOs for legacy paths |
| CPU-side MVP | Model/view/projection multiplied on CPU, uploaded via push constants (64B mat4 per draw) |
| CPU particle physics | Gravity/velocity/lifetime computed CPU-side in `xvk_draw_particles` |
| Fixed viewport/scissor | Baked into pipeline create info at swapchain creation — no dynamic `vkCmdSetViewport` |
| Zeroed device features | `VkPhysicalDeviceFeatures features = {0}` — no optional features enabled |
| No pipeline cache | Always `VK_NULL_HANDLE` for pipeline cache |

---

## (C) Missing — ~60 Features Not Implemented

### Core Drawing
- Indirect drawing (`vkCmdDrawIndirect`, `vkCmdDrawIndexedIndirect`, `vkCmdDispatchIndirect`)
- Instanced drawing in legacy API (Phase 1 exposes `instance_count` but legacy always passes 1)

### Geometry
- Tessellation shaders (no `VK_SHADER_STAGE_TESSELLATION_*`)
- Geometry shaders (no `VK_SHADER_STAGE_GEOMETRY_BIT`)
- Mesh shaders (no `VK_EXT_mesh_shader`)

### Anti-Aliasing
- MSAA (all `rasterizationSamples = VK_SAMPLE_COUNT_1_BIT`)
- No `vkCmdResolveImage`
- No alpha-to-coverage

### Images/Textures
- Mipmap generation (no `vkCmdBlitImage`/`vkCmdGenerateMipmaps`)
- Cube maps, texture arrays, 3D images
- `vkCmdClearColorImage`, `vkCmdClearDepthStencilImage`
- `vkCmdCopyBuffer`, `vkCmdCopyBufferToImage`, `vkCmdUpdateBuffer`, `vkCmdFillBuffer`

### Render Pass
- Multi-subpass (always `subpassCount = 1`)
- Input attachments
- Dynamic rendering (`VK_KHR_dynamic_rendering`) — not used

### Dynamic State (all missing)
- `vkCmdSetViewport`, `vkCmdSetScissor`, `vkCmdSetLineWidth`
- `vkCmdSetDepthBias`, `vkCmdSetBlendConstants`, `vkCmdSetDepthBounds`
- `vkCmdSetStencilCompareMask/WriteMask/Reference`

### Synchronization
- Timeline semaphores (binary only)
- Events (`vkCreateEvent`, `vkCmdSetEvent`, `vkCmdWaitEvents`)
- `vkQueueWaitIdle` (only coarse `vkDeviceWaitIdle`)
- `VK_KHR_synchronization2`

### Query Pools (all missing)
- Occlusion queries, pipeline statistics, timestamps
- No `vkCreateQueryPool`, `vkCmdWriteTimestamp`

### Stencil
- `stencilTestEnable = VK_FALSE`
- No stencil operations

### Advanced Features (all missing)
- Ray tracing (`VK_KHR_ray_tracing_pipeline`, `VK_KHR_acceleration_structure`)
- Fragment shading rate, conservative rasterization
- Sparse resources, protected memory, external memory/semaphores
- Buffer device address, descriptor indexing, push descriptors
- Sampler YCbCr, 16-bit/8-bit storage, subgroup operations, transform feedback

### Debug
- No `VK_EXT_debug_utils`, no debug markers/labels
- Validation layers opt-in via `XVK_VALIDATION=1` env var only

---

## Assessment

| Metric | Value |
|--------|-------|
| Real Vulkan API calls | **82** (0 stubs) |
| Vulkan spec coverage | ~**Vulkan 1.0 core** |
| Suitable for | 2D/3D viz, offscreen rendering, basic compute, CI testing |
| Not suitable for | AAA rendering, deferred shading, advanced post-processing, GPU-driven rendering |
