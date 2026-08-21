# XIOM Vulkan -- API Reference

## XIOM Modules

### vulkan_extern.xi -- Raw VK Bindings (755 functions)

Auto-generated from vulkan_core.h (SDK 1.4.350.0). Every Vulkan 1.3 core function plus KHR/EXT/NV/AMD/ARM/INTEL/QCOM extensions. All pointer/handle params use `Int`. VkResult values are `Int32`.

```xiom
module xiom.vulkan.extern
extern "C" {
  fn vkCreateInstance(pCreateInfo: Int, pAllocator: Int, pInstance: Int) -> Int32;
  fn vkDestroyInstance(instance: Int, pAllocator: Int);
  fn vkEnumeratePhysicalDevices(instance: Int, count: Int32, devices: Int) -> Int32;
  // ... 752 more functions
}
```

**Categories:** Instance (12), Device (8), Pipeline (4), Shader (2), Descriptor (5), Command (14), Sync (5), Buffer/Image/Memory (13), RenderPass/Framebuffer (3), Sampler (2), Swapchain (8), Query (0 in core), RayTracing (30+), Mesh (3), Video (10+), Debug (10), Extensions (100+), Surface (10+)

### vulkan_safe.xi -- Safe Wrappers (29 types + 5 create_from_struct)

Each type provides create/destroy with contracts, error handling, and RAII semantics.

| Type | Create | Destroy | Dedicated |
|------|--------|---------|-----------|
| VulkanInstance | create(app, eng, layers, exts) / create_from_struct(ci) | destroy() | -- |
| VulkanDevice | create(pd, family, exts) / create_from_struct(pd, ci) | destroy() | wait_idle() |
| VulkanBuffer | create(device, ci) / create_from_struct(device, ci) | destroy() | bind_memory(), map(), unmap() |
| VulkanImage | create(device, ci) / create_from_struct(device, ci) | destroy() | bind_memory() |
| VulkanImageView | create(device, ci) | destroy() | -- |
| VulkanSampler | create(device, ci) | destroy() | -- |
| VulkanShaderModule | create(device, ci) | destroy() | -- |
| VulkanPipelineLayout | create(device, ci) / create_from_struct(device, ci) | destroy() | -- |
| VulkanPipeline | create_graphics(device, ci) / create_compute(device, ci) | destroy() | bind() |
| VulkanDescriptorSetLayout | create(device, ci) | destroy() | -- |
| VulkanDescriptorPool | create(device, ci) | destroy() | reset() |
| VulkanDescriptorSet | allocate(device, pool, layout) | free(pool, sets) | bind() |
| VulkanCommandPool | create(device, ci) | destroy() | reset() |
| VulkanCommandBuffer | allocate(device, pool, ci) | free(pool, bufs) | begin/end/submit/draw/dispatch/barrier/begin_rendering/end_rendering |
| VulkanRenderPass | create(device, ci) | destroy() | -- |
| VulkanFramebuffer | create(device, ci) | destroy() | -- |
| VulkanFence | create(device, ci) | destroy() | wait()/reset()/status() |
| VulkanSemaphore | create(device, ci) | destroy() | -- |
| VulkanSwapchain | create(device, ci) | destroy() | acquire()/present() |
| VulkanEvent | create(device, ci) | destroy() | get_status()/set()/reset() |
| VulkanQueryPool | create(device, ci) | destroy() | get_results()/begin()/end()/reset()/timestamp()/copy() |
| VulkanPipelineCache | create(device, ci) | destroy() | get_data()/merge() |
| VulkanBufferView | create(device, ci) | destroy() | -- |
| VulkanDebugUtilsMessenger | create(instance, ci) | destroy() | -- |
| VulkanAccelerationStructureKHR | create(device, ci) | destroy() | -- |
| VulkanSurfaceKHR | (platform-specific) | destroy() | -- |
| VulkanPhysicalDevice | from_handle(pd) | -- | properties/features/memory/queue_families |
| VulkanDeviceMemory | allocate(device, ci) | free() | map()/unmap() |
| VulkanDescriptorUpdateTemplate | create(device, ci) | destroy() | -- |

**Struct Builder Integration (create_from_struct):** The 5 `create_from_struct` variants accept pre-built struct pointers from `vulkan_structs.xi` builders. This is the recommended path for production use -- builders guarantee correct memory layout.

### vulkan_structs.xi -- Struct Builders (30+ types)

Typed builders for every common VK create-info struct. Each builder allocates zeroed memory, writes the correct sType tag, and populates all fields at verified byte offsets.

```xiom
module xiom.vulkan.structs

// Lifecycle
pub fn build_application_info(app_name, engine_name, api_version) -> Int;
pub fn build_instance_create_info(app_info, layers, extensions) -> Int;
pub fn build_device_queue_create_info(family, count, priority) -> Int;
pub fn build_device_create_info(queue_infos, queue_count, extensions, features) -> Int;

// Resources
pub fn build_buffer_create_info(size, usage, sharing_mode, qf_count, qf_indices) -> Int;
pub fn build_image_create_info(type, fmt, w, h, d, mips, layers, samples, tiling, usage, sharing, qf_count, qf, init_layout) -> Int;
pub fn build_image_view_create_info(image, view_type, format, components, aspect, mip, layer, layers) -> Int;
pub fn build_sampler_create_info(mag, min, mip, addrU, addrV, addrW, lod_bias, aniso, cmp_enable, cmp_op, min_lod, max_lod, border, unnorm) -> Int;
pub fn build_shader_module_create_info(code_size, code_data) -> Int;

// Pipeline
pub fn build_pipeline_layout_create_info(set_count, set_layouts, pc_count, pc_ranges) -> Int;

// Descriptors
pub fn build_descriptor_set_layout_binding(binding, type, count, stages, samplers) -> Int;
pub fn build_descriptor_set_layout_create_info(count, bindings) -> Int;
pub fn build_descriptor_pool_size(type, count) -> Int;
pub fn build_descriptor_pool_create_info(flags, max_sets, count, sizes) -> Int;
pub fn build_descriptor_set_allocate_info(pool, count, layouts) -> Int;
pub fn build_write_descriptor_set_buffer(set, binding, element, type, count, infos) -> Int;

// Render Pass
pub fn build_render_pass_create_info(att_count, atts, sub_count, subs, dep_count, deps) -> Int;
pub fn build_framebuffer_create_info(rp, count, atts, w, h, layers) -> Int;
pub fn build_render_pass_begin_info(rp, fb, ox, oy, ew, eh, cv_count, cvs) -> Int;

// Command
pub fn build_command_pool_create_info(flags, family) -> Int;
pub fn build_command_buffer_allocate_info(pool, level, count) -> Int;

// Sync
pub fn build_fence_create_info(flags) -> Int;
pub fn build_semaphore_create_info(flags) -> Int;
pub fn build_submit_info(wait_count, sems, stages, cmd_count, cmds, sig_count, sigs) -> Int;

// Swapchain
pub fn build_swapchain_create_info(surface, min_images, fmt, cs, ew, eh, layers, usage, sharing, qf_count, qfs, pre_xform, alpha, present_mode, clipped, old) -> Int;
pub fn build_present_info(wait_count, sems, sc_count, scs, indices) -> Int;

// Memory
pub fn build_memory_allocate_info(size, type_index) -> Int;
pub fn build_mapped_memory_range(memory, offset, size) -> Int;

// Query
pub fn build_query_pool_create_info(flags, type, count, stats) -> Int;

// Utility
pub fn free_struct(ptr: Int);
pub fn read_u32(base: Int, offset: Int) -> Int32;
pub fn read_u64(base: Int, offset: Int) -> Int;
pub fn read_f32(base: Int, offset: Int) -> Float32;
```

### vulkan_constants_all.xi -- Constants (3691 values)

Every `VK_*` constant from vulkan_core.h: structure types, enum values, flags, format codes, API versions, vendor IDs.

```xiom
pub const VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO: Int = 1;
pub const VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO: Int = 12;
pub const VK_FORMAT_R8G8B8A8_UNORM: Int = 37;
pub const VK_IMAGE_TYPE_2D: Int = 1;
pub const VK_API_VERSION_1_3: Int = 4202496;
// ... 3686 more constants
```

## C Bridge Modules (318 functions across 30 modules)

### xvk_structs.c -- Struct Marshalling (13 functions)

Generic alloc/write/read for C struct creation from XIOM.

| Function | Signature |
|----------|-----------|
| xvk_alloc | `(size: Int) -> Int` |
| xvk_free | `(handle: Int)` |
| xvk_write_u32 | `(handle: Int, offset: Int, value: Int32)` |
| xvk_write_u64 | `(handle: Int, offset: Int, value: Int)` |
| xvk_write_f32 | `(handle: Int, offset: Int, value: Float32)` |
| xvk_write_str | `(handle: Int, offset: Int, str: Str)` |
| xvk_write_handle | `(handle: Int, offset: Int, vk_handle: Int)` |
| xvk_write_array | `(handle, offset, src, elem_count, elem_size)` |
| xvk_read_u32 | `(handle: Int, offset: Int) -> Int32` |
| xvk_read_u64 | `(handle: Int, offset: Int) -> Int` |
| xvk_read_f32 | `(handle: Int, offset: Int) -> Float32` |
| xvk_set_sType | `(handle: Int, sType: Int32)` |
| xvk_set_pNext | `(handle: Int, pNext: Int)` |

### xvk_bind_instance.c (4), xvk_bind_device.c (4)

Raw instance and device creation.

| Function | Description |
|----------|-------------|
| xvk_create_instance | vkCreateInstance wrapper |
| xvk_destroy_instance | vkDestroyInstance wrapper |
| xvk_enumerate_physical_devices | Returns count+handles |
| xvk_get_physical_device_properties | Fills VkPhysicalDeviceProperties |
| xvk_create_device | vkCreateDevice with pNext chain |
| xvk_destroy_device | vkDestroyDevice wrapper |
| xvk_get_device_queue | Returns queue handle |
| xvk_device_wait_idle | Waits for device idle |

### xvk_bind_buffer.c (6), xvk_bind_image.c (8), xvk_bind_memory.c (6)

Buffer, image, and memory resource management.

### xvk_bind_pipeline.c (9), xvk_bind_descriptor.c (9), xvk_bind_renderpass.c (4)

Shader modules, pipeline layouts, graphics/compute pipelines, descriptor set layouts/pools/sets, render passes, framebuffers.

### xvk_bind_command.c (63)

Complete command buffer API: allocate, begin, end, bind pipeline, bind vertex/index buffers, bind descriptor sets, push constants, draw/draw_indexed/draw_indirect, dispatch, copy buffer/image, blit, begin/end render pass, begin/end rendering, pipeline barrier, set viewport/scissor, all dynamic state commands.

### xvk_bind_sync.c (9), xvk_bind_query.c (8)

Fences, semaphores, events, queue submit, present. Query pools, timestamps, pipeline statistics.

### xvk_bind_swapchain.c (24), xvk_bind_extensions.c (82), xvk_bind_raytracing.c (54)

Swapchain/surface management. Extension functions: mesh shaders, video encode/decode, debug utils, fragment shading rate, extended dynamic state, push descriptors, copy commands 2, host image copy, timeline semaphores, dynamic rendering, synchronisation2, shader objects. Ray tracing: acceleration structures, RT pipelines, trace rays, shader binding tables, micromaps.
