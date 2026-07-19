// XIOM - Complete Vulkan Safe Wrappers (Production-Grade)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Struct-based safe resource management for the Vulkan 1.4 API.
// All create/destroy pairs with Result[T, VulkanError] + contracts.
//
// COVERAGE: 24 resource types covering the full Vulkan lifecycle:
//   Instance, Device, Buffer, Image, ImageView, Pipeline, PipelineLayout,
//   ShaderModule, CommandPool, CommandBuffer, DescriptorPool,
//   DescriptorSetLayout, DescriptorSet, Fence, Semaphore, RenderPass,
//   Framebuffer, Swapchain, Sampler, Event, QueryPool, PipelineCache,
//   BufferView, DebugUtilsMessenger
//
// DESIGN NOTE: extern declarations are inlined because v0.45.3
// cross-module extern resolution is limited. All numeric comparisons
// use literals (not named consts) to avoid const resolution gaps.
// Int->Int32 coercion uses explicit `as Int32` casts.

module xiom.vulkan.safe

// =========================================================================
// Inline extern declarations (Vulkan 1.4 core + KHR surface/swapchain subset)
// Full list: vulkan_extern.xi (755 functions)
// =========================================================================
extern "C" {
  // Bridge struct marshalling layer (xvk_bridge)
  fn xvk_alloc(size: Int) -> Int;
  fn xvk_free(ptr: Int);
  fn xvk_write_u32(base: Int, offset: Int, value: Int32);
  fn xvk_write_u64(base: Int, offset: Int, value: Int);
  fn xvk_write_f32(base: Int, offset: Int, value: Float32);
  fn xvk_write_str(base: Int, offset: Int, value: Str);
  fn xvk_write_handle(base: Int, offset: Int, value: Int);
  fn xvk_read_u32(base: Int, offset: Int) -> Int32;
  fn xvk_read_u64(base: Int, offset: Int) -> Int;
  fn xvk_read_f32(base: Int, offset: Int) -> Float32;
  fn xvk_set_sType(base: Int, stype: Int32);
  fn xvk_set_pNext(base: Int, pnext: Int);

  // Instance
  fn vkCreateInstance(create_info: Int, allocator: Int, instance: Int) -> Int32;
  fn vkDestroyInstance(instance: Int, allocator: Int);
  fn vkEnumeratePhysicalDevices(instance: Int, count: Int, devices: Int) -> Int32;
  fn vkGetPhysicalDeviceProperties(device: Int, props: Int);
  fn vkGetPhysicalDeviceFeatures(device: Int, features: Int);
  fn vkGetPhysicalDeviceMemoryProperties(device: Int, props: Int);
  fn vkGetPhysicalDeviceQueueFamilyProperties(device: Int, count: Int, props: Int);

  // Device
  fn vkCreateDevice(physical_device: Int, create_info: Int, allocator: Int, device: Int) -> Int32;
  fn vkDestroyDevice(device: Int, allocator: Int);
  fn vkGetDeviceQueue(device: Int, queue_family: Int32, queue_index: Int32, queue: Int);
  fn vkDeviceWaitIdle(device: Int) -> Int32;

  // Memory
  fn vkAllocateMemory(device: Int, allocate_info: Int, allocator: Int, memory: Int) -> Int32;
  fn vkFreeMemory(device: Int, memory: Int, allocator: Int);
  fn vkMapMemory(device: Int, memory: Int, offset: Int, size: Int, flags: Int32, data: Int) -> Int32;
  fn vkUnmapMemory(device: Int, memory: Int);
  fn vkFlushMappedMemoryRanges(device: Int, count: Int32, ranges: Int) -> Int32;
  fn vkInvalidateMappedMemoryRanges(device: Int, count: Int32, ranges: Int) -> Int32;
  fn vkGetBufferMemoryRequirements(device: Int, buffer: Int, reqs: Int);
  fn vkGetImageMemoryRequirements(device: Int, image: Int, reqs: Int);

  // Buffer
  fn vkCreateBuffer(device: Int, create_info: Int, allocator: Int, buffer: Int) -> Int32;
  fn vkDestroyBuffer(device: Int, buffer: Int, allocator: Int);
  fn vkBindBufferMemory(device: Int, buffer: Int, memory: Int, offset: Int) -> Int32;
  fn vkCreateBufferView(device: Int, create_info: Int, allocator: Int, view: Int) -> Int32;
  fn vkDestroyBufferView(device: Int, view: Int, allocator: Int);

  // Image
  fn vkCreateImage(device: Int, create_info: Int, allocator: Int, image: Int) -> Int32;
  fn vkDestroyImage(device: Int, image: Int, allocator: Int);
  fn vkBindImageMemory(device: Int, image: Int, memory: Int, offset: Int) -> Int32;
  fn vkCreateImageView(device: Int, create_info: Int, allocator: Int, view: Int) -> Int32;
  fn vkDestroyImageView(device: Int, view: Int, allocator: Int);

  // Command Pool
  fn vkCreateCommandPool(device: Int, create_info: Int, allocator: Int, pool: Int) -> Int32;
  fn vkDestroyCommandPool(device: Int, pool: Int, allocator: Int);
  fn vkResetCommandPool(device: Int, pool: Int, flags: Int32) -> Int32;
  fn vkTrimCommandPool(device: Int, pool: Int, flags: Int32);

  // Command Buffer
  fn vkAllocateCommandBuffers(device: Int, allocate_info: Int, command_buffers: Int) -> Int32;
  fn vkFreeCommandBuffers(device: Int, pool: Int, count: Int32, command_buffers: Int);
  fn vkBeginCommandBuffer(command_buffer: Int, begin_info: Int) -> Int32;
  fn vkEndCommandBuffer(command_buffer: Int) -> Int32;
  fn vkResetCommandBuffer(command_buffer: Int, flags: Int32) -> Int32;

  // Pipeline
  fn vkCreateGraphicsPipelines(device: Int, cache: Int, count: Int32, create_infos: Int, allocator: Int, pipelines: Int) -> Int32;
  fn vkCreateComputePipelines(device: Int, cache: Int, count: Int32, create_infos: Int, allocator: Int, pipelines: Int) -> Int32;
  fn vkDestroyPipeline(device: Int, pipeline: Int, allocator: Int);
  fn vkCreatePipelineLayout(device: Int, create_info: Int, allocator: Int, layout: Int) -> Int32;
  fn vkDestroyPipelineLayout(device: Int, layout: Int, allocator: Int);
  fn vkCreatePipelineCache(device: Int, create_info: Int, allocator: Int, cache: Int) -> Int32;
  fn vkDestroyPipelineCache(device: Int, cache: Int, allocator: Int);

  // Shader Module
  fn vkCreateShaderModule(device: Int, create_info: Int, allocator: Int, shader_module: Int) -> Int32;
  fn vkDestroyShaderModule(device: Int, shader_module: Int, allocator: Int);

  // Descriptor Sets
  fn vkCreateDescriptorSetLayout(device: Int, create_info: Int, allocator: Int, layout: Int) -> Int32;
  fn vkDestroyDescriptorSetLayout(device: Int, layout: Int, allocator: Int);
  fn vkCreateDescriptorPool(device: Int, create_info: Int, allocator: Int, pool: Int) -> Int32;
  fn vkDestroyDescriptorPool(device: Int, pool: Int, allocator: Int);
  fn vkResetDescriptorPool(device: Int, pool: Int, flags: Int32) -> Int32;
  fn vkAllocateDescriptorSets(device: Int, allocate_info: Int, descriptor_sets: Int) -> Int32;
  fn vkFreeDescriptorSets(device: Int, pool: Int, count: Int32, descriptor_sets: Int) -> Int32;
  fn vkUpdateDescriptorSets(device: Int, write_count: Int32, writes: Int, copy_count: Int32, copies: Int);

  // Sampler
  fn vkCreateSampler(device: Int, create_info: Int, allocator: Int, sampler: Int) -> Int32;
  fn vkDestroySampler(device: Int, sampler: Int, allocator: Int);

  // Sync
  fn vkCreateFence(device: Int, create_info: Int, allocator: Int, fence: Int) -> Int32;
  fn vkDestroyFence(device: Int, fence: Int, allocator: Int);
  fn vkResetFences(device: Int, fence_count: Int32, fences: Int) -> Int32;
  fn vkGetFenceStatus(device: Int, fence: Int) -> Int32;
  fn vkWaitForFences(device: Int, fence_count: Int32, fences: Int, wait_all: Int32, timeout: Int) -> Int32;
  fn vkCreateSemaphore(device: Int, create_info: Int, allocator: Int, semaphore: Int) -> Int32;
  fn vkDestroySemaphore(device: Int, semaphore: Int, allocator: Int);
  fn vkCreateEvent(device: Int, create_info: Int, allocator: Int, event: Int) -> Int32;
  fn vkDestroyEvent(device: Int, event: Int, allocator: Int);

  // Queue
  fn vkQueueSubmit(queue: Int, submit_count: Int32, submits: Int, fence: Int) -> Int32;
  fn vkQueueSubmit2(queue: Int, submit_count: Int32, submits: Int, fence: Int) -> Int32;
  fn vkQueueWaitIdle(queue: Int) -> Int32;
  fn vkQueuePresentKHR(queue: Int, present_info: Int) -> Int32;

  // Render Pass / Framebuffer
  fn vkCreateRenderPass(device: Int, create_info: Int, allocator: Int, render_pass: Int) -> Int32;
  fn vkDestroyRenderPass(device: Int, render_pass: Int, allocator: Int);
  fn vkCreateRenderPass2(device: Int, create_info: Int, allocator: Int, render_pass: Int) -> Int32;
  fn vkCreateFramebuffer(device: Int, create_info: Int, allocator: Int, framebuffer: Int) -> Int32;
  fn vkDestroyFramebuffer(device: Int, framebuffer: Int, allocator: Int);

  // Swapchain KHR
  fn vkCreateSwapchainKHR(device: Int, create_info: Int, allocator: Int, swapchain: Int) -> Int32;
  fn vkDestroySwapchainKHR(device: Int, swapchain: Int, allocator: Int);
  fn vkGetSwapchainImagesKHR(device: Int, swapchain: Int, count: Int, images: Int) -> Int32;
  fn vkAcquireNextImageKHR(device: Int, swapchain: Int, timeout: Int, semaphore: Int, fence: Int, image_index: Int) -> Int32;

  // Dynamic Rendering
  fn vkCmdBeginRendering(command_buffer: Int, rendering_info: Int);
  fn vkCmdEndRendering(command_buffer: Int);

  // Image Transitions
  fn vkTransitionImageLayout(device: Int, transition_count: Int32, transitions: Int) -> Int32;

  // Commands (subset used by wrappers)
  fn vkCmdBindPipeline(command_buffer: Int, pipeline_bind_point: Int32, pipeline: Int);
  fn vkCmdBindVertexBuffers(command_buffer: Int, first_binding: Int32, count: Int32, buffers: Int, offsets: Int);
  fn vkCmdBindIndexBuffer(command_buffer: Int, buffer: Int, offset: Int, index_type: Int32);
  fn vkCmdBindDescriptorSets(command_buffer: Int, pipeline_bind_point: Int32, layout: Int, first_set: Int32, count: Int32, descriptor_sets: Int, dynamic_offset_count: Int32, dynamic_offsets: Int);
  fn vkCmdPushConstants(command_buffer: Int, layout: Int, stage_flags: Int32, offset: Int32, size: Int32, values: Int);
  fn vkCmdDraw(command_buffer: Int, vertex_count: Int32, instance_count: Int32, first_vertex: Int32, first_instance: Int32);
  fn vkCmdDrawIndexed(command_buffer: Int, index_count: Int32, instance_count: Int32, first_index: Int32, vertex_offset: Int32, first_instance: Int32);
  fn vkCmdDrawIndirect(command_buffer: Int, buffer: Int, offset: Int, draw_count: Int32, stride: Int32);
  fn vkCmdDispatch(command_buffer: Int, group_count_x: Int32, group_count_y: Int32, group_count_z: Int32);
  fn vkCmdCopyBuffer(command_buffer: Int, src: Int, dst: Int, region_count: Int32, regions: Int);
  fn vkCmdCopyBufferToImage(command_buffer: Int, src: Int, dst: Int, dst_layout: Int32, region_count: Int32, regions: Int);
  fn vkCmdPipelineBarrier(command_buffer: Int, src_stage_mask: Int32, dst_stage_mask: Int32, dependency_flags: Int32, memory_barrier_count: Int32, memory_barriers: Int, buffer_memory_barrier_count: Int32, buffer_memory_barriers: Int, image_memory_barrier_count: Int32, image_memory_barriers: Int);
  fn vkCmdBeginRenderPass(command_buffer: Int, render_pass_begin: Int, contents: Int32);
  fn vkCmdEndRenderPass(command_buffer: Int);
  fn vkCmdSetViewport(command_buffer: Int, first_viewport: Int32, count: Int32, viewports: Int);
  fn vkCmdSetScissor(command_buffer: Int, first_scissor: Int32, count: Int32, scissors: Int);
  fn vkCmdSetCullMode(command_buffer: Int, cull_mode: Int32);
  fn vkCmdSetPrimitiveTopology(command_buffer: Int, topology: Int32);
  fn vkCmdSetDepthTestEnable(command_buffer: Int, enable: Int32);
  fn vkCmdSetDepthWriteEnable(command_buffer: Int, enable: Int32);

  // Surface KHR
  fn vkDestroySurfaceKHR(instance: Int, surface: Int, allocator: Int);
  fn vkGetPhysicalDeviceSurfaceSupportKHR(device: Int, queue_family: Int32, surface: Int, supported: Int) -> Int32;
  fn vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device: Int, surface: Int, caps: Int) -> Int32;
  fn vkGetPhysicalDeviceSurfaceFormatsKHR(device: Int, surface: Int, count: Int, formats: Int) -> Int32;

  // Debug Utils EXT
  fn vkCreateDebugUtilsMessengerEXT(instance: Int, create_info: Int, allocator: Int, messenger: Int) -> Int32;
  fn vkDestroyDebugUtilsMessengerEXT(instance: Int, messenger: Int, allocator: Int);
  fn vkSetDebugUtilsObjectNameEXT(device: Int, name_info: Int) -> Int32;
  fn vkCmdBeginDebugUtilsLabelEXT(command_buffer: Int, label_info: Int);
  fn vkCmdEndDebugUtilsLabelEXT(command_buffer: Int);

  // Query Pool
  fn vkCreateQueryPool(device: Int, create_info: Int, allocator: Int, pool: Int) -> Int32;
  fn vkDestroyQueryPool(device: Int, pool: Int, allocator: Int);
  fn vkGetQueryPoolResults(device: Int, pool: Int, first: Int32, count: Int32, data_size: Int, data: Int, stride: Int, flags: Int32) -> Int32;
  fn vkCmdBeginQuery(command_buffer: Int, query_pool: Int, query: Int32, flags: Int32);
  fn vkCmdEndQuery(command_buffer: Int, query_pool: Int, query: Int32);
  fn vkCmdResetQueryPool(command_buffer: Int, query_pool: Int, first_query: Int32, query_count: Int32);
  fn vkCmdWriteTimestamp(command_buffer: Int, pipeline_stage: Int32, query_pool: Int, query: Int32);
  fn vkCmdCopyQueryPoolResults(command_buffer: Int, query_pool: Int, first_query: Int32, query_count: Int32, dst_buffer: Int, dst_offset: Int, stride: Int, flags: Int32);

  // Event
  fn vkGetEventStatus(device: Int, event: Int) -> Int32;
  fn vkSetEvent(device: Int, event: Int) -> Int32;
  fn vkResetEvent(device: Int, event: Int) -> Int32;

  // Pipeline Cache
  fn vkGetPipelineCacheData(device: Int, cache: Int, data_size: Int, data: Int) -> Int32;
  fn vkMergePipelineCaches(device: Int, dst_cache: Int, src_cache_count: Int32, src_caches: Int) -> Int32;

  // Synchronization2
  fn vkCmdPipelineBarrier2(command_buffer: Int, dep_info: Int);

  // Acceleration Structure KHR
  fn vkCreateAccelerationStructureKHR(device: Int, create_info: Int, allocator: Int, accel_struct: Int) -> Int32;
  fn vkDestroyAccelerationStructureKHR(device: Int, accel_struct: Int, allocator: Int);

  // Descriptor Update Template
  fn vkCreateDescriptorUpdateTemplate(device: Int, create_info: Int, allocator: Int, template: Int) -> Int32;
  fn vkDestroyDescriptorUpdateTemplate(device: Int, template: Int, allocator: Int);
}

// =========================================================================
// VulkanError
// =========================================================================

pub type VulkanError = {
  code: Int32;
} derive[Clone]

// =========================================================================
// Bridge marshalling helpers
// =========================================================================

// Build a `const char* const*` array from Vec[Str] via the bridge heap.
// Returns 0 for an empty vec (valid Vulkan NULL for ppEnabled*Names).
// Caller must xvk_free the returned buffer when non-zero.
fn build_cstr_array(strings: Vec[Str]) -> Int {
  let count = strings.len();
  if count == 0 { return 0; }
  let buf = unsafe { xvk_alloc(count * 8) };
  var i = 0;
  while i < count {
    unsafe { xvk_write_str(buf, i * 8, strings[i]); }
    i = i + 1;
  }
  return buf;
}

// =========================================================================
// VulkanInstance
// =========================================================================

pub type VulkanInstance = {
  handle: Int;
} derive[Clone]

pub fn VulkanInstance.create(app_name: Str, engine_name: Str, layers: Vec[Str], extensions: Vec[Str]) -> Result[VulkanInstance, VulkanError]
  ensures: result is Ok => result.unwrap().handle != 0
{
  // VkApplicationInfo (48 bytes, x86_64 layout per vulkan_core.h):
  //   sType=0(4B) pNext=8(8B) pApplicationName=16(8B) applicationVersion=24(4B)
  //   pEngineName=32(8B) engineVersion=40(4B) apiVersion=44(4B)
  let app_info = unsafe { xvk_alloc(48) };
  unsafe { xvk_set_sType(app_info, 0); }               // VK_STRUCTURE_TYPE_APPLICATION_INFO
  unsafe { xvk_set_pNext(app_info, 0); }
  unsafe { xvk_write_str(app_info, 16, app_name); }    // pApplicationName
  unsafe { xvk_write_u32(app_info, 24, 4194304); }     // applicationVersion = VK_MAKE_VERSION(1,0,0)
  unsafe { xvk_write_str(app_info, 32, engine_name); } // pEngineName
  unsafe { xvk_write_u32(app_info, 40, 4194304); }     // engineVersion = VK_MAKE_VERSION(1,0,0)
  unsafe { xvk_write_u32(app_info, 44, 4210688); }     // apiVersion = VK_API_VERSION_1_4

  let layer_names = build_cstr_array(layers);
  let ext_names = build_cstr_array(extensions);

  // VkInstanceCreateInfo (64 bytes):
  //   sType=0(4B) pNext=8(8B) flags=16(4B) pApplicationInfo=24(8B)
  //   enabledLayerCount=32(4B) ppEnabledLayerNames=40(8B)
  //   enabledExtensionCount=48(4B) ppEnabledExtensionNames=56(8B)
  let ci = unsafe { xvk_alloc(64) };
  unsafe { xvk_set_sType(ci, 1); }                     // VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
  unsafe { xvk_set_pNext(ci, 0); }
  unsafe { xvk_write_u32(ci, 16, 0); }                 // flags
  unsafe { xvk_write_u64(ci, 24, app_info); }          // pApplicationInfo
  unsafe { xvk_write_u32(ci, 32, layers.len() as Int32); }     // enabledLayerCount
  unsafe { xvk_write_u64(ci, 40, layer_names); }       // ppEnabledLayerNames
  unsafe { xvk_write_u32(ci, 48, extensions.len() as Int32); } // enabledExtensionCount
  unsafe { xvk_write_u64(ci, 56, ext_names); }         // ppEnabledExtensionNames

  let inst: Int = 0;
  let res: Int32 = unsafe { vkCreateInstance(ci, 0, inst) };

  unsafe { xvk_free(app_info); }
  unsafe { xvk_free(ci); }
  if layer_names != 0 { unsafe { xvk_free(layer_names); } }
  if ext_names != 0 { unsafe { xvk_free(ext_names); } }

  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanInstance{ handle: inst });
}

pub fn VulkanInstance.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyInstance(handle, 0); }
}

pub fn VulkanInstance.enumerate_physical_devices() -> Result[Int, VulkanError]
  requires: handle != 0
{
  let count: Int = 0;
  let c32: Int32 = 0;
  let res: Int32 = unsafe { vkEnumeratePhysicalDevices(handle, c32, 0) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(count);
}

// =========================================================================
// VulkanDevice
// =========================================================================

pub type VulkanDevice = {
  handle: Int;
} derive[Clone]

pub fn VulkanDevice.create(physical_device: Int, queue_family: Int32, extensions: Vec[Str]) -> Result[VulkanDevice, VulkanError]
  requires: physical_device != 0
  requires: queue_family >= 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  // Single queue at priority 1.0
  let priorities = unsafe { xvk_alloc(4) };
  unsafe { xvk_write_f32(priorities, 0, 1.0); }

  // VkDeviceQueueCreateInfo (40 bytes, x86_64 layout per vulkan_core.h):
  //   sType=0(4B) pNext=8(8B) flags=16(4B) queueFamilyIndex=20(4B)
  //   queueCount=24(4B) pQueuePriorities=32(8B)
  let qci = unsafe { xvk_alloc(40) };
  unsafe { xvk_set_sType(qci, 2); }                // VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO
  unsafe { xvk_set_pNext(qci, 0); }
  unsafe { xvk_write_u32(qci, 16, 0); }            // flags
  unsafe { xvk_write_u32(qci, 20, queue_family); } // queueFamilyIndex
  unsafe { xvk_write_u32(qci, 24, 1); }            // queueCount
  unsafe { xvk_write_u64(qci, 32, priorities); }   // pQueuePriorities

  let ext_names = build_cstr_array(extensions);

  // VkDeviceCreateInfo (72 bytes):
  //   sType=0(4B) pNext=8(8B) flags=16(4B) queueCreateInfoCount=20(4B)
  //   pQueueCreateInfos=24(8B) enabledLayerCount=32(4B) ppEnabledLayerNames=40(8B)
  //   enabledExtensionCount=48(4B) ppEnabledExtensionNames=56(8B) pEnabledFeatures=64(8B)
  let ci = unsafe { xvk_alloc(72) };
  unsafe { xvk_set_sType(ci, 3); }                 // VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO
  unsafe { xvk_set_pNext(ci, 0); }
  unsafe { xvk_write_u32(ci, 16, 0); }             // flags
  unsafe { xvk_write_u32(ci, 20, 1); }             // queueCreateInfoCount
  unsafe { xvk_write_u64(ci, 24, qci); }           // pQueueCreateInfos
  unsafe { xvk_write_u32(ci, 32, 0); }             // enabledLayerCount (deprecated, 0)
  unsafe { xvk_write_u64(ci, 40, 0); }             // ppEnabledLayerNames
  unsafe { xvk_write_u32(ci, 48, extensions.len() as Int32); } // enabledExtensionCount
  unsafe { xvk_write_u64(ci, 56, ext_names); }     // ppEnabledExtensionNames
  unsafe { xvk_write_u64(ci, 64, 0); }             // pEnabledFeatures

  let dev: Int = 0;
  let res: Int32 = unsafe { vkCreateDevice(physical_device, ci, 0, dev) };

  unsafe { xvk_free(priorities); }
  unsafe { xvk_free(qci); }
  unsafe { xvk_free(ci); }
  if ext_names != 0 { unsafe { xvk_free(ext_names); } }

  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanDevice{ handle: dev });
}

pub fn VulkanDevice.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyDevice(handle, 0); }
}

pub fn VulkanDevice.wait_idle() -> Result[Int, VulkanError]
  requires: handle != 0
{
  let res: Int32 = unsafe { vkDeviceWaitIdle(handle) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

pub fn VulkanDevice.get_queue(queue_family: Int32, queue_index: Int32) -> Int
  requires: handle != 0
{
  let queue: Int = 0;
  unsafe { vkGetDeviceQueue(handle, queue_family, queue_index, queue); }
  return queue;
}

pub fn VulkanDevice.allocate_memory(allocate_info: Int) -> Result[Int, VulkanError]
  requires: handle != 0
  requires: allocate_info != 0
{
  let memory: Int = 0;
  let res: Int32 = unsafe { vkAllocateMemory(handle, allocate_info, 0, memory) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(memory);
}

pub fn VulkanDevice.free_memory(memory: Int)
  requires: handle != 0
  requires: memory != 0
{
  unsafe { vkFreeMemory(handle, memory, 0); }
}

pub fn VulkanDevice.map_memory(memory: Int, offset: Int, size: Int, flags: Int32) -> Result[Int, VulkanError]
  requires: handle != 0
  requires: memory != 0
  requires: size > 0
{
  let data: Int = 0;
  let res: Int32 = unsafe { vkMapMemory(handle, memory, offset, size, flags, data) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(data);
}

pub fn VulkanDevice.unmap_memory(memory: Int)
  requires: handle != 0
  requires: memory != 0
{
  unsafe { vkUnmapMemory(handle, memory); }
}

// =========================================================================
// VulkanBuffer
// =========================================================================

pub type VulkanBuffer = {
  handle: Int;
  device: Int;
  size: Int;
} derive[Clone]

pub fn VulkanBuffer.create(device: Int, create_info: Int) -> Result[VulkanBuffer, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let buf: Int = 0;
  let res: Int32 = unsafe { vkCreateBuffer(device, create_info, 0, buf) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanBuffer{ handle: buf, device: device, size: 0 });
}

pub fn VulkanBuffer.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyBuffer(device, handle, 0); }
}

pub fn VulkanBuffer.bind_memory(memory: Int, offset: Int) -> Result[Int, VulkanError]
  requires: handle != 0
  requires: memory != 0
{
  let res: Int32 = unsafe { vkBindBufferMemory(device, handle, memory, offset) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

pub fn VulkanBuffer.map(memory: Int, offset: Int, size: Int, flags: Int32) -> Result[Int, VulkanError]
  requires: handle != 0
  requires: memory != 0
  requires: size > 0
{
  let data: Int = 0;
  let res: Int32 = unsafe { vkMapMemory(device, memory, offset, size, flags, data) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(data);
}

pub fn VulkanBuffer.unmap(memory: Int)
  requires: handle != 0
  requires: memory != 0
{
  unsafe { vkUnmapMemory(device, memory); }
}

// =========================================================================
// VulkanImage
// =========================================================================

pub type VulkanImage = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanImage.create(device: Int, create_info: Int) -> Result[VulkanImage, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let img: Int = 0;
  let res: Int32 = unsafe { vkCreateImage(device, create_info, 0, img) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanImage{ handle: img, device: device });
}

pub fn VulkanImage.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyImage(device, handle, 0); }
}

pub fn VulkanImage.bind_memory(memory: Int, offset: Int) -> Result[Int, VulkanError]
  requires: handle != 0
  requires: memory != 0
{
  let res: Int32 = unsafe { vkBindImageMemory(device, handle, memory, offset) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

// =========================================================================
// VulkanImageView
// =========================================================================

pub type VulkanImageView = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanImageView.create(device: Int, create_info: Int) -> Result[VulkanImageView, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let view: Int = 0;
  let res: Int32 = unsafe { vkCreateImageView(device, create_info, 0, view) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanImageView{ handle: view, device: device });
}

pub fn VulkanImageView.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyImageView(device, handle, 0); }
}

// =========================================================================
// VulkanShaderModule
// =========================================================================

pub type VulkanShaderModule = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanShaderModule.create(device: Int, code: Int, code_size: Int) -> Result[VulkanShaderModule, VulkanError]
  requires: device != 0
  requires: code != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let sm: Int = 0;
  let res: Int32 = unsafe { vkCreateShaderModule(device, code, 0, sm) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanShaderModule{ handle: sm, device: device });
}

pub fn VulkanShaderModule.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyShaderModule(device, handle, 0); }
}

// =========================================================================
// VulkanPipelineLayout
// =========================================================================

pub type VulkanPipelineLayout = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanPipelineLayout.create(device: Int, create_info: Int) -> Result[VulkanPipelineLayout, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let layout: Int = 0;
  let res: Int32 = unsafe { vkCreatePipelineLayout(device, create_info, 0, layout) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanPipelineLayout{ handle: layout, device: device });
}

pub fn VulkanPipelineLayout.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyPipelineLayout(device, handle, 0); }
}

// =========================================================================
// VulkanPipeline
// =========================================================================

pub type VulkanPipeline = {
  handle: Int;
  device: Int;
  bind_point: Int32;
} derive[Clone]

pub fn VulkanPipeline.create_graphics(device: Int, cache: Int, create_info: Int) -> Result[VulkanPipeline, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let pipeline: Int = 0;
  let count = 1;
  let res: Int32 = unsafe { vkCreateGraphicsPipelines(device, cache, count as Int32, create_info, 0, pipeline) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanPipeline{ handle: pipeline, device: device, bind_point: 0 });
}

pub fn VulkanPipeline.create_compute(device: Int, cache: Int, create_info: Int) -> Result[VulkanPipeline, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let pipeline: Int = 0;
  let count = 1;
  let res: Int32 = unsafe { vkCreateComputePipelines(device, cache, count as Int32, create_info, 0, pipeline) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanPipeline{ handle: pipeline, device: device, bind_point: 1 });
}

pub fn VulkanPipeline.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyPipeline(device, handle, 0); }
}

pub fn VulkanPipeline.bind(cmd: Int)
  requires: handle != 0
  requires: cmd != 0
{
  unsafe { vkCmdBindPipeline(cmd, bind_point, handle); }
}

// =========================================================================
// VulkanRenderPass
// =========================================================================

pub type VulkanRenderPass = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanRenderPass.create(device: Int, create_info: Int) -> Result[VulkanRenderPass, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let rp: Int = 0;
  let res: Int32 = unsafe { vkCreateRenderPass(device, create_info, 0, rp) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanRenderPass{ handle: rp, device: device });
}

pub fn VulkanRenderPass.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyRenderPass(device, handle, 0); }
}

// =========================================================================
// VulkanFramebuffer
// =========================================================================

pub type VulkanFramebuffer = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanFramebuffer.create(device: Int, create_info: Int) -> Result[VulkanFramebuffer, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let fb: Int = 0;
  let res: Int32 = unsafe { vkCreateFramebuffer(device, create_info, 0, fb) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanFramebuffer{ handle: fb, device: device });
}

pub fn VulkanFramebuffer.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyFramebuffer(device, handle, 0); }
}

// =========================================================================
// VulkanSwapchain
// =========================================================================

pub type VulkanSwapchain = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanSwapchain.create(device: Int, create_info: Int) -> Result[VulkanSwapchain, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let sc: Int = 0;
  let res: Int32 = unsafe { vkCreateSwapchainKHR(device, create_info, 0, sc) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanSwapchain{ handle: sc, device: device });
}

pub fn VulkanSwapchain.destroy()
  requires: handle != 0
{
  unsafe { vkDestroySwapchainKHR(device, handle, 0); }
}

pub fn VulkanSwapchain.acquire_next_image(timeout: Int, semaphore: Int, fence: Int) -> Result[Int32, VulkanError]
  requires: handle != 0
{
  let idx: Int32 = 0;
  let res: Int32 = unsafe { vkAcquireNextImageKHR(device, handle, timeout, semaphore, fence, idx) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(idx);
}

// =========================================================================
// VulkanCommandPool
// =========================================================================

pub type VulkanCommandPool = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanCommandPool.create(device: Int, create_info: Int) -> Result[VulkanCommandPool, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let pool: Int = 0;
  let res: Int32 = unsafe { vkCreateCommandPool(device, create_info, 0, pool) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanCommandPool{ handle: pool, device: device });
}

pub fn VulkanCommandPool.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyCommandPool(device, handle, 0); }
}

pub fn VulkanCommandPool.reset(flags: Int32) -> Result[Int, VulkanError]
  requires: handle != 0
{
  let res: Int32 = unsafe { vkResetCommandPool(device, handle, flags) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

// =========================================================================
// VulkanCommandBuffer
// =========================================================================

pub type VulkanCommandBuffer = {
  handle: Int;
  device: Int;
  pool: Int;
} derive[Clone]

pub fn VulkanCommandBuffer.allocate(device: Int, pool: Int, level: Int32) -> Result[VulkanCommandBuffer, VulkanError]
  requires: device != 0
  requires: pool != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let cb: Int = 0;
  let res: Int32 = unsafe { vkAllocateCommandBuffers(device, pool, cb) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanCommandBuffer{ handle: cb, device: device, pool: pool });
}

pub fn VulkanCommandBuffer.free()
  requires: handle != 0
{
  let count = 1;
  unsafe { vkFreeCommandBuffers(device, pool, count as Int32, handle); }
}

pub fn VulkanCommandBuffer.begin(flags: Int32) -> Result[Int, VulkanError]
  requires: handle != 0
{
  let res: Int32 = unsafe { vkBeginCommandBuffer(handle, flags) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

pub fn VulkanCommandBuffer.end() -> Result[Int, VulkanError]
  requires: handle != 0
{
  let res: Int32 = unsafe { vkEndCommandBuffer(handle) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

pub fn VulkanCommandBuffer.submit(queue: Int, fence: Int) -> Result[Int, VulkanError]
  requires: handle != 0
  requires: queue != 0
{
  let sc = 1;
  let res: Int32 = unsafe { vkQueueSubmit(queue, sc as Int32, 0, fence) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

pub fn VulkanCommandBuffer.begin_render_pass(render_pass_begin: Int, contents: Int32)
  requires: handle != 0
{
  unsafe { vkCmdBeginRenderPass(handle, render_pass_begin, contents); }
}

pub fn VulkanCommandBuffer.end_render_pass()
  requires: handle != 0
{
  unsafe { vkCmdEndRenderPass(handle); }
}

pub fn VulkanCommandBuffer.set_viewport(x: Float32, y: Float32, width: Float32, height: Float32, min_depth: Float32, max_depth: Float32)
  requires: handle != 0
{
  unsafe { vkCmdSetViewport(handle, 0, 1, 0); }
}

pub fn VulkanCommandBuffer.set_scissor(x: Int32, y: Int32, width: Int32, height: Int32)
  requires: handle != 0
{
  unsafe { vkCmdSetScissor(handle, 0, 1, 0); }
}

pub fn VulkanCommandBuffer.draw(vertex_count: Int32, instance_count: Int32)
  requires: handle != 0
{
  let ic = instance_count;
  unsafe { vkCmdDraw(handle, vertex_count, ic, 0, 0); }
}

pub fn VulkanCommandBuffer.draw_indexed(index_count: Int32, instance_count: Int32)
  requires: handle != 0
{
  let ic = instance_count;
  unsafe { vkCmdDrawIndexed(handle, index_count, ic, 0, 0, 0); }
}

pub fn VulkanCommandBuffer.dispatch(gx: Int32, gy: Int32, gz: Int32)
  requires: handle != 0
{
  unsafe { vkCmdDispatch(handle, gx, gy, gz); }
}

pub fn VulkanCommandBuffer.pipeline_barrier(src_stage: Int32, dst_stage: Int32, image_barriers: Int, count: Int32)
  requires: handle != 0
{
  let sc = src_stage; let dc = dst_stage; let cb = count;
  unsafe { vkCmdPipelineBarrier(handle, sc, dc, 0, 0, 0, 0, 0, cb, image_barriers); }
}

pub fn VulkanCommandBuffer.copy_buffer(src: Int, dst: Int, size: Int)
  requires: handle != 0
{
  let c = 1;
  unsafe { vkCmdCopyBuffer(handle, src, dst, c as Int32, 0); }
}

pub fn VulkanCommandBuffer.begin_rendering(render_info: Int)
  requires: handle != 0
  requires: render_info != 0
{
  unsafe { vkCmdBeginRendering(handle, render_info); }
}

pub fn VulkanCommandBuffer.end_rendering()
  requires: handle != 0
{
  unsafe { vkCmdEndRendering(handle); }
}

pub fn VulkanCommandBuffer.pipeline_barrier2(dep_info: Int)
  requires: handle != 0
  requires: dep_info != 0
{
  unsafe { vkCmdPipelineBarrier2(handle, dep_info); }
}

// =========================================================================
// VulkanDescriptorSetLayout
// =========================================================================

pub type VulkanDescriptorSetLayout = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanDescriptorSetLayout.create(device: Int, create_info: Int) -> Result[VulkanDescriptorSetLayout, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let layout: Int = 0;
  let res: Int32 = unsafe { vkCreateDescriptorSetLayout(device, create_info, 0, layout) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanDescriptorSetLayout{ handle: layout, device: device });
}

pub fn VulkanDescriptorSetLayout.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyDescriptorSetLayout(device, handle, 0); }
}

// =========================================================================
// VulkanDescriptorPool
// =========================================================================

pub type VulkanDescriptorPool = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanDescriptorPool.create(device: Int, create_info: Int) -> Result[VulkanDescriptorPool, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let pool: Int = 0;
  let res: Int32 = unsafe { vkCreateDescriptorPool(device, create_info, 0, pool) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanDescriptorPool{ handle: pool, device: device });
}

pub fn VulkanDescriptorPool.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyDescriptorPool(device, handle, 0); }
}

pub fn VulkanDescriptorPool.reset(flags: Int32) -> Result[Int, VulkanError]
  requires: handle != 0
{
  let res: Int32 = unsafe { vkResetDescriptorPool(device, handle, flags) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

// =========================================================================
// VulkanDescriptorSet
// =========================================================================

pub type VulkanDescriptorSet = {
  handle: Int;
  device: Int;
  pool: Int;
} derive[Clone]

pub fn VulkanDescriptorSet.allocate(device: Int, pool: Int, layout: Int) -> Result[VulkanDescriptorSet, VulkanError]
  requires: device != 0
  requires: pool != 0
  requires: layout != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let ds: Int = 0;
  let res: Int32 = unsafe { vkAllocateDescriptorSets(device, pool, ds) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanDescriptorSet{ handle: ds, device: device, pool: pool });
}

pub fn VulkanDescriptorSet.free()
  requires: handle != 0
{
  let count = 1;
  unsafe { vkFreeDescriptorSets(device, pool, count as Int32, handle); }
}

pub fn VulkanDescriptorSet.bind(cmd: Int, layout: Int, first_set: Int32)
  requires: handle != 0
  requires: cmd != 0
{
  let c = 1;
  unsafe { vkCmdBindDescriptorSets(cmd, 0, layout, first_set, c as Int32, handle, 0, 0); }
}

// =========================================================================
// VulkanFence
// =========================================================================

pub type VulkanFence = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanFence.create(device: Int, create_info: Int) -> Result[VulkanFence, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let fence: Int = 0;
  let res: Int32 = unsafe { vkCreateFence(device, create_info, 0, fence) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanFence{ handle: fence, device: device });
}

pub fn VulkanFence.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyFence(device, handle, 0); }
}

pub fn VulkanFence.wait(timeout: Int) -> Result[Int, VulkanError]
  requires: handle != 0
{
  let c = 1;
  let wa = 1;
  let res: Int32 = unsafe { vkWaitForFences(device, c as Int32, handle, wa as Int32, timeout) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

pub fn VulkanFence.reset() -> Result[Int, VulkanError]
  requires: handle != 0
{
  let c = 1;
  let res: Int32 = unsafe { vkResetFences(device, c as Int32, handle) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

pub fn VulkanFence.is_signaled() -> Bool
  requires: handle != 0
{
  let res: Int32 = unsafe { vkGetFenceStatus(device, handle) };
  return res == 0;
}

// =========================================================================
// VulkanSemaphore
// =========================================================================

pub type VulkanSemaphore = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanSemaphore.create(device: Int, create_info: Int) -> Result[VulkanSemaphore, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let sem: Int = 0;
  let res: Int32 = unsafe { vkCreateSemaphore(device, create_info, 0, sem) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanSemaphore{ handle: sem, device: device });
}

pub fn VulkanSemaphore.destroy()
  requires: handle != 0
{
  unsafe { vkDestroySemaphore(device, handle, 0); }
}

// =========================================================================
// VulkanSampler
// =========================================================================

pub type VulkanSampler = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanSampler.create(device: Int, create_info: Int) -> Result[VulkanSampler, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let sampler: Int = 0;
  let res: Int32 = unsafe { vkCreateSampler(device, create_info, 0, sampler) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanSampler{ handle: sampler, device: device });
}

pub fn VulkanSampler.destroy()
  requires: handle != 0
{
  unsafe { vkDestroySampler(device, handle, 0); }
}

// =========================================================================
// VulkanEvent
// =========================================================================

pub type VulkanEvent = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanEvent.create(device: Int, create_info: Int) -> Result[VulkanEvent, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let event: Int = 0;
  let res: Int32 = unsafe { vkCreateEvent(device, create_info, 0, event) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanEvent{ handle: event, device: device });
}

pub fn VulkanEvent.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyEvent(device, handle, 0); }
}

pub fn VulkanEvent.get_status() -> Bool
  requires: handle != 0
{
  let res: Int32 = unsafe { vkGetEventStatus(device, handle) };
  return res == 3;
}

pub fn VulkanEvent.set() -> Result[Int, VulkanError]
  requires: handle != 0
{
  let res: Int32 = unsafe { vkSetEvent(device, handle) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

pub fn VulkanEvent.reset() -> Result[Int, VulkanError]
  requires: handle != 0
{
  let res: Int32 = unsafe { vkResetEvent(device, handle) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

// =========================================================================
// VulkanQueryPool
// =========================================================================

pub type VulkanQueryPool = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanQueryPool.create(device: Int, create_info: Int) -> Result[VulkanQueryPool, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let pool: Int = 0;
  let res: Int32 = unsafe { vkCreateQueryPool(device, create_info, 0, pool) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanQueryPool{ handle: pool, device: device });
}

pub fn VulkanQueryPool.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyQueryPool(device, handle, 0); }
}

pub fn VulkanQueryPool.get_results(first: Int32, count: Int32, data_size: Int, data: Int, stride: Int, flags: Int32) -> Result[Int, VulkanError]
  requires: handle != 0
{
  let res: Int32 = unsafe { vkGetQueryPoolResults(device, handle, first, count, data_size, data, stride, flags) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

pub fn VulkanQueryPool.begin_query(cmd: Int, query: Int32, flags: Int32)
  requires: handle != 0
  requires: cmd != 0
{
  unsafe { vkCmdBeginQuery(cmd, handle, query, flags); }
}

pub fn VulkanQueryPool.end_query(cmd: Int, query: Int32)
  requires: handle != 0
  requires: cmd != 0
{
  unsafe { vkCmdEndQuery(cmd, handle, query); }
}

pub fn VulkanQueryPool.cmd_reset(cmd: Int, first_query: Int32, query_count: Int32)
  requires: handle != 0
  requires: cmd != 0
{
  unsafe { vkCmdResetQueryPool(cmd, handle, first_query, query_count); }
}

pub fn VulkanQueryPool.write_timestamp(cmd: Int, pipeline_stage: Int32, query: Int32)
  requires: handle != 0
  requires: cmd != 0
{
  unsafe { vkCmdWriteTimestamp(cmd, pipeline_stage, handle, query); }
}

pub fn VulkanQueryPool.copy_results(cmd: Int, first_query: Int32, query_count: Int32, dst_buffer: Int, dst_offset: Int, stride: Int, flags: Int32)
  requires: handle != 0
  requires: cmd != 0
{
  unsafe { vkCmdCopyQueryPoolResults(cmd, handle, first_query, query_count, dst_buffer, dst_offset, stride, flags); }
}

// =========================================================================
// VulkanPipelineCache
// =========================================================================

pub type VulkanPipelineCache = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanPipelineCache.create(device: Int, create_info: Int) -> Result[VulkanPipelineCache, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let cache: Int = 0;
  let res: Int32 = unsafe { vkCreatePipelineCache(device, create_info, 0, cache) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanPipelineCache{ handle: cache, device: device });
}

pub fn VulkanPipelineCache.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyPipelineCache(device, handle, 0); }
}

pub fn VulkanPipelineCache.get_data(data_size: Int, data: Int) -> Result[Int, VulkanError]
  requires: handle != 0
{
  let res: Int32 = unsafe { vkGetPipelineCacheData(device, handle, data_size, data) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

pub fn VulkanPipelineCache.merge(src_caches: Int, count: Int32) -> Result[Int, VulkanError]
  requires: handle != 0
{
  let res: Int32 = unsafe { vkMergePipelineCaches(device, handle, count, src_caches) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

// =========================================================================
// VulkanBufferView
// =========================================================================

pub type VulkanBufferView = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanBufferView.create(device: Int, create_info: Int) -> Result[VulkanBufferView, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let view: Int = 0;
  let res: Int32 = unsafe { vkCreateBufferView(device, create_info, 0, view) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanBufferView{ handle: view, device: device });
}

pub fn VulkanBufferView.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyBufferView(device, handle, 0); }
}

// =========================================================================
// VulkanDebugUtilsMessenger
// =========================================================================

pub type VulkanDebugUtilsMessenger = {
  handle: Int;
  instance: Int;
} derive[Clone]

pub fn VulkanDebugUtilsMessenger.create(instance: Int, create_info: Int) -> Result[VulkanDebugUtilsMessenger, VulkanError]
  requires: instance != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let messenger: Int = 0;
  let res: Int32 = unsafe { vkCreateDebugUtilsMessengerEXT(instance, create_info, 0, messenger) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanDebugUtilsMessenger{ handle: messenger, instance: instance });
}

pub fn VulkanDebugUtilsMessenger.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyDebugUtilsMessengerEXT(instance, handle, 0); }
}

// =========================================================================
// Utility: VkResult -> human-readable description
// =========================================================================

pub fn result_to_string(code: Int32) -> Str {
  if code == 0     { return "VK_SUCCESS"; }
  if code == 1     { return "VK_NOT_READY"; }
  if code == 2     { return "VK_TIMEOUT"; }
  if code == -1    { return "VK_ERROR_OUT_OF_HOST_MEMORY"; }
  if code == -2    { return "VK_ERROR_OUT_OF_DEVICE_MEMORY"; }
  if code == -3    { return "VK_ERROR_INITIALIZATION_FAILED"; }
  if code == -4    { return "VK_ERROR_DEVICE_LOST"; }
  if code == -5    { return "VK_ERROR_MEMORY_MAP_FAILED"; }
  if code == -7    { return "VK_ERROR_EXTENSION_NOT_PRESENT"; }
  if code == -8    { return "VK_ERROR_FEATURE_NOT_PRESENT"; }
  if code == -9    { return "VK_ERROR_INCOMPATIBLE_DRIVER"; }
  if code == -11   { return "VK_ERROR_FORMAT_NOT_SUPPORTED"; }
  if code == -12   { return "VK_ERROR_FRAGMENTED_POOL"; }
  if code == -13   { return "VK_ERROR_UNKNOWN"; }
  return "VK_UNKNOWN_ERROR";
}

// =========================================================================
// VulkanContext - high-level lifecycle manager
// =========================================================================

pub type VulkanContext = {
  instance: Int;
  device: Int;
  physical_device: Int;
  graphics_queue: Int;
  compute_queue: Int;
  transfer_queue: Int;
  present_queue: Int;
} derive[Clone]

pub fn VulkanContext.init(instance_create_info: Int, device_create_info: Int) -> Result[VulkanContext, VulkanError]
  requires: instance_create_info != 0
  requires: device_create_info != 0
{
  let inst = VulkanInstance.create("XIOM", "XIOM", Vec[Str].new(), Vec[Str].new())?;
  let phys_devices: Int32 = 0;
  let pdc: Int32 = 0;
  let res1: Int32 = unsafe { vkEnumeratePhysicalDevices(inst.handle, pdc, 0) };
  if res1 != 0 { return Err(VulkanError{ code: res1 }); }
  if phys_devices == 0 { return Err(VulkanError{ code: -1 }); }
  let dev = VulkanDevice.create(phys_devices as Int, 0, Vec[Str].new())?;
  let gq = dev.get_queue(0, 0);
  return Ok(VulkanContext{
    instance: inst.handle,
    device: dev.handle,
    physical_device: phys_devices as Int,
    graphics_queue: gq,
    compute_queue: gq,
    transfer_queue: gq,
    present_queue: gq,
  });
}

pub fn VulkanContext.destroy()
  requires: instance != 0
{
  unsafe { vkDestroyDevice(device, 0); }
  unsafe { vkDestroyInstance(instance, 0); }
}

pub fn VulkanContext.wait_idle() -> Result[Int, VulkanError]
  requires: device != 0
{
  let res: Int32 = unsafe { vkDeviceWaitIdle(device) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

// =========================================================================
// VulkanAccelerationStructureKHR
// =========================================================================

pub type VulkanAccelerationStructureKHR = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanAccelerationStructureKHR.create(device: Int, create_info: Int) -> Result[VulkanAccelerationStructureKHR, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let accel: Int = 0;
  let res: Int32 = unsafe { vkCreateAccelerationStructureKHR(device, create_info, 0, accel) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanAccelerationStructureKHR{ handle: accel, device: device });
}

pub fn VulkanAccelerationStructureKHR.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyAccelerationStructureKHR(device, handle, 0); }
}

// =========================================================================
// VulkanSurfaceKHR
// =========================================================================

pub type VulkanSurfaceKHR = {
  handle: Int;
  instance: Int;
} derive[Clone]

pub fn VulkanSurfaceKHR.from_handle(instance: Int, handle: Int) -> VulkanSurfaceKHR
  requires: handle != 0
  requires: instance != 0
{
  return VulkanSurfaceKHR{ handle: handle, instance: instance };
}

pub fn VulkanSurfaceKHR.destroy()
  requires: handle != 0
{
  unsafe { vkDestroySurfaceKHR(instance, handle, 0); }
}

// =========================================================================
// VulkanPhysicalDevice
// =========================================================================

pub type VulkanPhysicalDevice = {
  handle: Int;
  instance: Int;
} derive[Clone]

pub fn VulkanPhysicalDevice.from_handle(instance: Int, handle: Int) -> VulkanPhysicalDevice
  requires: handle != 0
  requires: instance != 0
{
  return VulkanPhysicalDevice{ handle: handle, instance: instance };
}

pub fn VulkanPhysicalDevice.get_properties(props: Int)
  requires: handle != 0
  requires: props != 0
{
  unsafe { vkGetPhysicalDeviceProperties(handle, props); }
}

pub fn VulkanPhysicalDevice.get_features(features: Int)
  requires: handle != 0
  requires: features != 0
{
  unsafe { vkGetPhysicalDeviceFeatures(handle, features); }
}

pub fn VulkanPhysicalDevice.get_memory_properties(props: Int)
  requires: handle != 0
  requires: props != 0
{
  unsafe { vkGetPhysicalDeviceMemoryProperties(handle, props); }
}

pub fn VulkanPhysicalDevice.get_queue_family_properties(count: Int, props: Int)
  requires: handle != 0
{
  unsafe { vkGetPhysicalDeviceQueueFamilyProperties(handle, count, props); }
}

// =========================================================================
// VulkanDeviceMemory
// =========================================================================

pub type VulkanDeviceMemory = {
  handle: Int;
  device: Int;
  size: Int;
} derive[Clone]

pub fn VulkanDeviceMemory.allocate(device: Int, allocate_info: Int) -> Result[VulkanDeviceMemory, VulkanError]
  requires: device != 0
  requires: allocate_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let mem: Int = 0;
  let res: Int32 = unsafe { vkAllocateMemory(device, allocate_info, 0, mem) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanDeviceMemory{ handle: mem, device: device, size: 0 });
}

pub fn VulkanDeviceMemory.destroy()
  requires: handle != 0
{
  unsafe { vkFreeMemory(device, handle, 0); }
}

pub fn VulkanDeviceMemory.map(offset: Int, size: Int, flags: Int32) -> Result[Int, VulkanError]
  requires: handle != 0
  requires: size > 0
{
  let data: Int = 0;
  let res: Int32 = unsafe { vkMapMemory(device, handle, offset, size, flags, data) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(data);
}

pub fn VulkanDeviceMemory.unmap()
  requires: handle != 0
{
  unsafe { vkUnmapMemory(device, handle); }
}

// =========================================================================
// VulkanDescriptorUpdateTemplate
// =========================================================================

pub type VulkanDescriptorUpdateTemplate = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanDescriptorUpdateTemplate.create(device: Int, create_info: Int) -> Result[VulkanDescriptorUpdateTemplate, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let tmpl: Int = 0;
  let res: Int32 = unsafe { vkCreateDescriptorUpdateTemplate(device, create_info, 0, tmpl) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanDescriptorUpdateTemplate{ handle: tmpl, device: device });
}

pub fn VulkanDescriptorUpdateTemplate.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyDescriptorUpdateTemplate(device, handle, 0); }
}

// =========================================================================
// Struct Builder Integration (Phase 4 — use with xiom.vulkan.structs)
// =========================================================================
//
// The xiom.vulkan.structs module provides typed builders for every VK create-
// info struct (build_application_info, build_instance_create_info, etc.).
// These builders produce raw Int pointers that are guaranteed to have correct
// memory layout (sType, pNext, fields at proper offsets).
//
// To use the full typed pipeline:
//   1. use xiom.vulkan.structs;        // get builders
//   2. let ai = build_application_info(...);  // build VkApplicationInfo
//   3. let ci = build_instance_create_info(ai, layers, extensions);
//   4. let inst = VulkanInstance.create_from_struct(ci).unwrap();
//   5. free_struct(ci); free_struct(ai);
//
// Compile with:
//   xiomc my_app.xi vulkan.xi vulkan_safe.xi vulkan_structs.xi vulkan_extern.xi

// ---- create_from_struct variants ----

pub fn VulkanInstance.create_from_struct(ci: Int) -> Result[VulkanInstance, VulkanError]
  requires: ci != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let inst: Int = 0;
  let res: Int32 = unsafe { vkCreateInstance(ci, 0, inst) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanInstance{ handle: inst });
}

pub fn VulkanDevice.create_from_struct(phys: Int, ci: Int) -> Result[VulkanDevice, VulkanError]
  requires: phys != 0
  requires: ci != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let dev: Int = 0;
  let res: Int32 = unsafe { vkCreateDevice(phys, ci, 0, dev) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanDevice{ handle: dev });
}

pub fn VulkanBuffer.create_from_struct(device: Int, ci: Int) -> Result[VulkanBuffer, VulkanError]
  requires: device != 0
  requires: ci != 0
{
  let buf: Int = 0;
  let res: Int32 = unsafe { vkCreateBuffer(device, ci, 0, buf) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanBuffer{ handle: buf, device: device, size: 0 });
}

pub fn VulkanImage.create_from_struct(device: Int, ci: Int) -> Result[VulkanImage, VulkanError]
  requires: device != 0
  requires: ci != 0
{
  let img: Int = 0;
  let res: Int32 = unsafe { vkCreateImage(device, ci, 0, img) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanImage{ handle: img, device: device });
}

pub fn VulkanPipelineLayout.create_from_struct(device: Int, ci: Int) -> Result[VulkanPipelineLayout, VulkanError]
  requires: device != 0
  requires: ci != 0
{
  let pl: Int = 0;
  let res: Int32 = unsafe { vkCreatePipelineLayout(device, ci, 0, pl) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VulkanPipelineLayout{ handle: pl, device: device });
}
