// XIOM — Vulkan FFI Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Raw `extern "C"` declarations for the Vulkan 1.3 API targeting
// vulkan-1.dll (Windows) / libvulkan.so (Linux) / libvulkan.dylib (macOS).
//
// ALL pointer/handle parameters use `Int`.  VkResult values are `Int32`.
// Generated from vulkan_core.h (SDK 1.4.350.0) + manual curation.
//
// 120+ entry points covering: Instance, Device, Memory, Buffer, Image,
// Command Buffers, Pipeline, Descriptor Sets, Synchronisation, Swapchain,
// Dynamic Rendering, Debug Utils, and Compute.
//
// Enum constants are split across src/vulkan_constants{1,2,3}.xi
// to stay under the compiler's pub const per-module limit (~99).

module xiom.vulkan.extern

use xiom.vulkan.constants;
use xiom.vulkan.constants2;
use xiom.vulkan.constants3;

// =========================================================================
// Instance
// =========================================================================
extern "C" {
  fn vkCreateInstance(create_info: Int, allocator: Int, instance: Int) -> Int32;
  fn vkDestroyInstance(instance: Int, allocator: Int);
  fn vkEnumerateInstanceExtensionProperties(layer_name: Int, count: Int, props: Int) -> Int32;
  fn vkEnumerateInstanceLayerProperties(count: Int, props: Int) -> Int32;
  fn vkEnumerateInstanceVersion(api_version: Int) -> Int32;
  fn vkGetInstanceProcAddr(instance: Int, name: Int) -> Int;
}

// =========================================================================
// Physical Device
// =========================================================================
extern "C" {
  fn vkEnumeratePhysicalDevices(instance: Int, count: Int, devices: Int) -> Int32;
  fn vkGetPhysicalDeviceProperties(device: Int, props: Int);
  fn vkGetPhysicalDeviceProperties2(device: Int, props: Int);
  fn vkGetPhysicalDeviceFeatures(device: Int, features: Int);
  fn vkGetPhysicalDeviceFeatures2(device: Int, features: Int);
  fn vkGetPhysicalDeviceMemoryProperties(device: Int, props: Int);
  fn vkGetPhysicalDeviceMemoryProperties2(device: Int, props: Int);
  fn vkGetPhysicalDeviceFormatProperties(device: Int, format: Int32, props: Int);
  fn vkGetPhysicalDeviceFormatProperties2(device: Int, format: Int32, props: Int);
  fn vkGetPhysicalDeviceImageFormatProperties(device: Int, format: Int32, image_type: Int32, tiling: Int32, usage: Int32, flags: Int32, props: Int) -> Int32;
  fn vkGetPhysicalDeviceQueueFamilyProperties(device: Int, count: Int, props: Int);
  fn vkGetPhysicalDeviceQueueFamilyProperties2(device: Int, count: Int, props: Int);
  fn vkGetPhysicalDeviceSurfaceSupportKHR(device: Int, queue_family: Int32, surface: Int, supported: Int) -> Int32;
  fn vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device: Int, surface: Int, caps: Int) -> Int32;
  fn vkGetPhysicalDeviceSurfaceFormatsKHR(device: Int, surface: Int, count: Int, formats: Int) -> Int32;
  fn vkGetPhysicalDeviceSurfacePresentModesKHR(device: Int, surface: Int, count: Int, modes: Int) -> Int32;
  fn vkEnumerateDeviceExtensionProperties(device: Int, layer_name: Int, count: Int, props: Int) -> Int32;
}

// =========================================================================
// Device
// =========================================================================
extern "C" {
  fn vkCreateDevice(physical_device: Int, create_info: Int, allocator: Int, device: Int) -> Int32;
  fn vkDestroyDevice(device: Int, allocator: Int);
  fn vkGetDeviceQueue(device: Int, queue_family: Int32, queue_index: Int32, queue: Int);
  fn vkGetDeviceQueue2(device: Int, queue_info: Int, queue: Int);
  fn vkDeviceWaitIdle(device: Int) -> Int32;
  fn vkGetDeviceProcAddr(device: Int, name: Int) -> Int;
}

// =========================================================================
// Memory
// =========================================================================
extern "C" {
  fn vkAllocateMemory(device: Int, allocate_info: Int, allocator: Int, memory: Int) -> Int32;
  fn vkFreeMemory(device: Int, memory: Int, allocator: Int);
  fn vkMapMemory(device: Int, memory: Int, offset: Int, size: Int, flags: Int32, data: Int) -> Int32;
  fn vkUnmapMemory(device: Int, memory: Int);
  fn vkFlushMappedMemoryRanges(device: Int, count: Int32, ranges: Int) -> Int32;
  fn vkInvalidateMappedMemoryRanges(device: Int, count: Int32, ranges: Int) -> Int32;
  fn vkGetDeviceMemoryCommitment(device: Int, memory: Int, committed: Int);
  fn vkGetBufferMemoryRequirements(device: Int, buffer: Int, reqs: Int);
  fn vkGetBufferMemoryRequirements2(device: Int, info: Int, reqs: Int);
  fn vkGetImageMemoryRequirements(device: Int, image: Int, reqs: Int);
  fn vkGetImageMemoryRequirements2(device: Int, info: Int, reqs: Int);
}

// =========================================================================
// Buffer
// =========================================================================
extern "C" {
  fn vkCreateBuffer(device: Int, create_info: Int, allocator: Int, buffer: Int) -> Int32;
  fn vkDestroyBuffer(device: Int, buffer: Int, allocator: Int);
  fn vkBindBufferMemory(device: Int, buffer: Int, memory: Int, offset: Int) -> Int32;
  fn vkBindBufferMemory2(device: Int, count: Int32, bind_infos: Int) -> Int32;
  fn vkCreateBufferView(device: Int, create_info: Int, allocator: Int, view: Int) -> Int32;
  fn vkDestroyBufferView(device: Int, view: Int, allocator: Int);
  fn vkGetBufferDeviceAddress(device: Int, info: Int) -> Int;
}

// =========================================================================
// Image
// =========================================================================
extern "C" {
  fn vkCreateImage(device: Int, create_info: Int, allocator: Int, image: Int) -> Int32;
  fn vkDestroyImage(device: Int, image: Int, allocator: Int);
  fn vkBindImageMemory(device: Int, image: Int, memory: Int, offset: Int) -> Int32;
  fn vkBindImageMemory2(device: Int, count: Int32, bind_infos: Int) -> Int32;
  fn vkGetImageSubresourceLayout(device: Int, image: Int, subresource: Int, layout: Int);
  fn vkCreateImageView(device: Int, create_info: Int, allocator: Int, view: Int) -> Int32;
  fn vkDestroyImageView(device: Int, view: Int, allocator: Int);
}

// =========================================================================
// Command Pool & Command Buffer
// =========================================================================
extern "C" {
  fn vkCreateCommandPool(device: Int, create_info: Int, allocator: Int, pool: Int) -> Int32;
  fn vkDestroyCommandPool(device: Int, pool: Int, allocator: Int);
  fn vkResetCommandPool(device: Int, pool: Int, flags: Int32) -> Int32;
  fn vkTrimCommandPool(device: Int, pool: Int, flags: Int32);
  fn vkAllocateCommandBuffers(device: Int, allocate_info: Int, command_buffers: Int) -> Int32;
  fn vkFreeCommandBuffers(device: Int, pool: Int, count: Int32, command_buffers: Int);
  fn vkBeginCommandBuffer(command_buffer: Int, begin_info: Int) -> Int32;
  fn vkEndCommandBuffer(command_buffer: Int) -> Int32;
  fn vkResetCommandBuffer(command_buffer: Int, flags: Int32) -> Int32;
}

// =========================================================================
// Commands — Draw, State, Copy
// =========================================================================
extern "C" {
  fn vkCmdBindPipeline(command_buffer: Int, pipeline_bind_point: Int32, pipeline: Int);
  fn vkCmdSetViewport(command_buffer: Int, first_viewport: Int32, count: Int32, viewports: Int);
  fn vkCmdSetScissor(command_buffer: Int, first_scissor: Int32, count: Int32, scissors: Int);
  fn vkCmdSetLineWidth(command_buffer: Int, line_width: Float32);
  fn vkCmdSetDepthBias(command_buffer: Int, constant_factor: Float32, clamp: Float32, slope_factor: Float32);
  fn vkCmdSetBlendConstants(command_buffer: Int, blend_constants: Int);
  fn vkCmdSetDepthBounds(command_buffer: Int, min_depth: Float32, max_depth: Float32);
  fn vkCmdSetStencilCompareMask(command_buffer: Int, face_mask: Int32, compare_mask: Int32);
  fn vkCmdSetStencilWriteMask(command_buffer: Int, face_mask: Int32, write_mask: Int32);
  fn vkCmdSetStencilReference(command_buffer: Int, face_mask: Int32, reference: Int32);
  fn vkCmdBindVertexBuffers(command_buffer: Int, first_binding: Int32, count: Int32, buffers: Int, offsets: Int);
  fn vkCmdBindIndexBuffer(command_buffer: Int, buffer: Int, offset: Int, index_type: Int32);
  fn vkCmdBindDescriptorSets(command_buffer: Int, pipeline_bind_point: Int32, layout: Int, first_set: Int32, count: Int32, descriptor_sets: Int, dynamic_offset_count: Int32, dynamic_offsets: Int);
  fn vkCmdPushConstants(command_buffer: Int, layout: Int, stage_flags: Int32, offset: Int32, size: Int32, values: Int);
  fn vkCmdDraw(command_buffer: Int, vertex_count: Int32, instance_count: Int32, first_vertex: Int32, first_instance: Int32);
  fn vkCmdDrawIndexed(command_buffer: Int, index_count: Int32, instance_count: Int32, first_index: Int32, vertex_offset: Int32, first_instance: Int32);
  fn vkCmdDrawIndirect(command_buffer: Int, buffer: Int, offset: Int, draw_count: Int32, stride: Int32);
  fn vkCmdDrawIndexedIndirect(command_buffer: Int, buffer: Int, offset: Int, draw_count: Int32, stride: Int32);
  fn vkCmdDispatch(command_buffer: Int, group_count_x: Int32, group_count_y: Int32, group_count_z: Int32);
  fn vkCmdDispatchIndirect(command_buffer: Int, buffer: Int, offset: Int);
  fn vkCmdCopyBuffer(command_buffer: Int, src: Int, dst: Int, region_count: Int32, regions: Int);
  fn vkCmdCopyImage(command_buffer: Int, src: Int, src_layout: Int32, dst: Int, dst_layout: Int32, region_count: Int32, regions: Int);
  fn vkCmdCopyBufferToImage(command_buffer: Int, src: Int, dst: Int, dst_layout: Int32, region_count: Int32, regions: Int);
  fn vkCmdCopyImageToBuffer(command_buffer: Int, src: Int, src_layout: Int32, dst: Int, region_count: Int32, regions: Int);
  fn vkCmdUpdateBuffer(command_buffer: Int, dst: Int, dst_offset: Int, data_size: Int, data: Int);
  fn vkCmdFillBuffer(command_buffer: Int, dst: Int, dst_offset: Int, size: Int, data: Int32);
  fn vkCmdClearColorImage(command_buffer: Int, image: Int, image_layout: Int32, color: Int, range_count: Int32, ranges: Int);
  fn vkCmdClearDepthStencilImage(command_buffer: Int, image: Int, image_layout: Int32, depth_stencil: Int, range_count: Int32, ranges: Int);
  fn vkCmdBlitImage(command_buffer: Int, src: Int, src_layout: Int32, dst: Int, dst_layout: Int32, region_count: Int32, regions: Int, filter: Int32);
  fn vkCmdResolveImage(command_buffer: Int, src: Int, src_layout: Int32, dst: Int, dst_layout: Int32, region_count: Int32, regions: Int);
  fn vkCmdPipelineBarrier(command_buffer: Int, src_stage_mask: Int32, dst_stage_mask: Int32, dependency_flags: Int32, memory_barrier_count: Int32, memory_barriers: Int, buffer_memory_barrier_count: Int32, buffer_memory_barriers: Int, image_memory_barrier_count: Int32, image_memory_barriers: Int);
  fn vkCmdBeginQuery(command_buffer: Int, query_pool: Int, query: Int32, flags: Int32);
  fn vkCmdEndQuery(command_buffer: Int, query_pool: Int, query: Int32);
  fn vkCmdResetQueryPool(command_buffer: Int, query_pool: Int, first: Int32, count: Int32);
  fn vkCmdWriteTimestamp(command_buffer: Int, stage: Int32, query_pool: Int, query: Int32);
  fn vkCmdCopyQueryPoolResults(command_buffer: Int, query_pool: Int, first_query: Int32, query_count: Int32, dst: Int, dst_offset: Int, stride: Int, flags: Int32);
  fn vkCmdExecuteCommands(command_buffer: Int, count: Int32, secondary_command_buffers: Int);
}

// =========================================================================
// Render Pass & Framebuffer
// =========================================================================
extern "C" {
  fn vkCreateRenderPass(device: Int, create_info: Int, allocator: Int, render_pass: Int) -> Int32;
  fn vkDestroyRenderPass(device: Int, render_pass: Int, allocator: Int);
  fn vkGetRenderAreaGranularity(device: Int, render_pass: Int, granularity: Int);
  fn vkCreateRenderPass2(device: Int, create_info: Int, allocator: Int, render_pass: Int) -> Int32;
  fn vkCmdBeginRenderPass(command_buffer: Int, render_pass_begin: Int, contents: Int32);
  fn vkCmdNextSubpass(command_buffer: Int, contents: Int32);
  fn vkCmdEndRenderPass(command_buffer: Int);
  fn vkCmdBeginRenderPass2(command_buffer: Int, render_pass_begin: Int, subpass_begin: Int);
  fn vkCmdNextSubpass2(command_buffer: Int, subpass_begin: Int, subpass_end: Int);
  fn vkCmdEndRenderPass2(command_buffer: Int, subpass_end: Int);
  fn vkCmdClearAttachments(command_buffer: Int, attachment_count: Int32, attachments: Int, rect_count: Int32, rects: Int);
  fn vkCreateFramebuffer(device: Int, create_info: Int, allocator: Int, framebuffer: Int) -> Int32;
  fn vkDestroyFramebuffer(device: Int, framebuffer: Int, allocator: Int);
}

// =========================================================================
// Dynamic Rendering (VK_KHR_dynamic_rendering / Vulkan 1.3 core)
// =========================================================================
extern "C" {
  fn vkCmdBeginRendering(command_buffer: Int, rendering_info: Int);
  fn vkCmdEndRendering(command_buffer: Int);
}

// =========================================================================
// Pipeline
// =========================================================================
extern "C" {
  fn vkCreateGraphicsPipelines(device: Int, cache: Int, count: Int32, create_infos: Int, allocator: Int, pipelines: Int) -> Int32;
  fn vkCreateComputePipelines(device: Int, cache: Int, count: Int32, create_infos: Int, allocator: Int, pipelines: Int) -> Int32;
  fn vkDestroyPipeline(device: Int, pipeline: Int, allocator: Int);
  fn vkCreatePipelineLayout(device: Int, create_info: Int, allocator: Int, layout: Int) -> Int32;
  fn vkDestroyPipelineLayout(device: Int, layout: Int, allocator: Int);
  fn vkCreatePipelineCache(device: Int, create_info: Int, allocator: Int, cache: Int) -> Int32;
  fn vkDestroyPipelineCache(device: Int, cache: Int, allocator: Int);
  fn vkGetPipelineCacheData(device: Int, cache: Int, data_size: Int, data: Int) -> Int32;
  fn vkMergePipelineCaches(device: Int, dst: Int, src_count: Int32, srcs: Int) -> Int32;
}

// =========================================================================
// Shader Module
// =========================================================================
extern "C" {
  fn vkCreateShaderModule(device: Int, create_info: Int, allocator: Int, shader_module: Int) -> Int32;
  fn vkDestroyShaderModule(device: Int, shader_module: Int, allocator: Int);
}

// =========================================================================
// Descriptor Sets
// =========================================================================
extern "C" {
  fn vkCreateDescriptorSetLayout(device: Int, create_info: Int, allocator: Int, layout: Int) -> Int32;
  fn vkDestroyDescriptorSetLayout(device: Int, layout: Int, allocator: Int);
  fn vkCreateDescriptorPool(device: Int, create_info: Int, allocator: Int, pool: Int) -> Int32;
  fn vkDestroyDescriptorPool(device: Int, pool: Int, allocator: Int);
  fn vkResetDescriptorPool(device: Int, pool: Int, flags: Int32) -> Int32;
  fn vkAllocateDescriptorSets(device: Int, allocate_info: Int, descriptor_sets: Int) -> Int32;
  fn vkFreeDescriptorSets(device: Int, pool: Int, count: Int32, descriptor_sets: Int) -> Int32;
  fn vkUpdateDescriptorSets(device: Int, write_count: Int32, writes: Int, copy_count: Int32, copies: Int);
  fn vkCreateDescriptorUpdateTemplate(device: Int, create_info: Int, allocator: Int, template: Int) -> Int32;
  fn vkDestroyDescriptorUpdateTemplate(device: Int, template: Int, allocator: Int);
  fn vkUpdateDescriptorSetWithTemplate(device: Int, descriptor_set: Int, template: Int, data: Int);
}

// =========================================================================
// Sampler
// =========================================================================
extern "C" {
  fn vkCreateSampler(device: Int, create_info: Int, allocator: Int, sampler: Int) -> Int32;
  fn vkDestroySampler(device: Int, sampler: Int, allocator: Int);
}

// =========================================================================
// Synchronisation (Fences, Semaphores, Events)
// =========================================================================
extern "C" {
  fn vkCreateFence(device: Int, create_info: Int, allocator: Int, fence: Int) -> Int32;
  fn vkDestroyFence(device: Int, fence: Int, allocator: Int);
  fn vkResetFences(device: Int, fence_count: Int32, fences: Int) -> Int32;
  fn vkGetFenceStatus(device: Int, fence: Int) -> Int32;
  fn vkWaitForFences(device: Int, fence_count: Int32, fences: Int, wait_all: Int32, timeout: Int) -> Int32;
  fn vkCreateSemaphore(device: Int, create_info: Int, allocator: Int, semaphore: Int) -> Int32;
  fn vkDestroySemaphore(device: Int, semaphore: Int, allocator: Int);
  fn vkCreateEvent(device: Int, create_info: Int, allocator: Int, event: Int) -> Int32;
  fn vkDestroyEvent(device: Int, event: Int, allocator: Int);
  fn vkGetEventStatus(device: Int, event: Int) -> Int32;
  fn vkSetEvent(device: Int, event: Int) -> Int32;
  fn vkResetEvent(device: Int, event: Int) -> Int32;
}

// =========================================================================
// Query Pool
// =========================================================================
extern "C" {
  fn vkCreateQueryPool(device: Int, create_info: Int, allocator: Int, pool: Int) -> Int32;
  fn vkDestroyQueryPool(device: Int, pool: Int, allocator: Int);
  fn vkGetQueryPoolResults(device: Int, pool: Int, first: Int32, count: Int32, data_size: Int, data: Int, stride: Int, flags: Int32) -> Int32;
  fn vkResetQueryPool(device: Int, pool: Int, first: Int32, count: Int32);
}

// =========================================================================
// Queue
// =========================================================================
extern "C" {
  fn vkQueueSubmit(queue: Int, submit_count: Int32, submits: Int, fence: Int) -> Int32;
  fn vkQueueSubmit2(queue: Int, submit_count: Int32, submits: Int, fence: Int) -> Int32;
  fn vkQueueWaitIdle(queue: Int) -> Int32;
  fn vkQueueBindSparse(queue: Int, bind_info_count: Int32, bind_infos: Int, fence: Int) -> Int32;
}

// =========================================================================
// Swapchain (KHR)
// =========================================================================
extern "C" {
  fn vkCreateSwapchainKHR(device: Int, create_info: Int, allocator: Int, swapchain: Int) -> Int32;
  fn vkDestroySwapchainKHR(device: Int, swapchain: Int, allocator: Int);
  fn vkGetSwapchainImagesKHR(device: Int, swapchain: Int, count: Int, images: Int) -> Int32;
  fn vkAcquireNextImageKHR(device: Int, swapchain: Int, timeout: Int, semaphore: Int, fence: Int, image_index: Int) -> Int32;
  fn vkQueuePresentKHR(queue: Int, present_info: Int) -> Int32;
  fn vkAcquireNextImage2KHR(device: Int, acquire_info: Int, image_index: Int) -> Int32;
  fn vkGetSwapchainStatusKHR(device: Int, swapchain: Int) -> Int32;
}

// =========================================================================
// Surface (KHR)
// =========================================================================
extern "C" {
  fn vkDestroySurfaceKHR(instance: Int, surface: Int, allocator: Int);
}

// =========================================================================
// Debug Utils (EXT)
// =========================================================================
extern "C" {
  fn vkCreateDebugUtilsMessengerEXT(instance: Int, create_info: Int, allocator: Int, messenger: Int) -> Int32;
  fn vkDestroyDebugUtilsMessengerEXT(instance: Int, messenger: Int, allocator: Int);
  fn vkSetDebugUtilsObjectNameEXT(device: Int, name_info: Int) -> Int32;
  fn vkCmdBeginDebugUtilsLabelEXT(command_buffer: Int, label_info: Int);
  fn vkCmdEndDebugUtilsLabelEXT(command_buffer: Int);
  fn vkCmdInsertDebugUtilsLabelEXT(command_buffer: Int, label_info: Int);
}

// =========================================================================
// Dynamic State (VK_EXT_extended_dynamic_state / Vulkan 1.3 core)
// =========================================================================
extern "C" {
  fn vkCmdSetCullMode(command_buffer: Int, cull_mode: Int32);
  fn vkCmdSetFrontFace(command_buffer: Int, front_face: Int32);
  fn vkCmdSetPrimitiveTopology(command_buffer: Int, topology: Int32);
  fn vkCmdSetViewportWithCount(command_buffer: Int, count: Int32, viewports: Int);
  fn vkCmdSetScissorWithCount(command_buffer: Int, count: Int32, scissors: Int);
  fn vkCmdSetDepthTestEnable(command_buffer: Int, enable: Int32);
  fn vkCmdSetDepthWriteEnable(command_buffer: Int, enable: Int32);
  fn vkCmdSetDepthCompareOp(command_buffer: Int, compare_op: Int32);
  fn vkCmdSetStencilTestEnable(command_buffer: Int, enable: Int32);
  fn vkCmdSetStencilOp(command_buffer: Int, face_mask: Int32, fail_op: Int32, pass_op: Int32, depth_fail_op: Int32, compare_op: Int32);
  fn vkCmdSetRasterizerDiscardEnable(command_buffer: Int, enable: Int32);
  fn vkCmdSetDepthBiasEnable(command_buffer: Int, enable: Int32);
  fn vkCmdSetPrimitiveRestartEnable(command_buffer: Int, enable: Int32);
}

// =========================================================================
// Image Layout Transitions (VK_KHR_maintenance5)
// =========================================================================
extern "C" {
  fn vkTransitionImageLayout(device: Int, transition_count: Int32, transitions: Int) -> Int32;
  fn vkCopyMemoryToImage(device: Int, copy_info: Int) -> Int32;
  fn vkCopyImageToMemory(device: Int, copy_info: Int) -> Int32;
}
