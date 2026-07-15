// XIOM — Vulkan Safe Wrappers (Self-Contained)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Struct-based safe resource management over the raw Vulkan FFI bindings.
// Converts VkResult → Result[T, VulkanError] with create/destroy lifecycle
// safety via `requires:`/`ensures:` contracts.
//
// DESIGN NOTE: extern declarations are inlined here because v0.45.3
// cross-module extern resolution is incomplete (see ROADMAP.md §5c.12).

module xiom.vulkan.safe

// =========================================================================
// Inline extern declarations (Vulkan 1.3 core subset)
// =========================================================================
extern "C" {
  fn vkCreateInstance(create_info: Int, allocator: Int, instance: Int) -> Int32;
  fn vkDestroyInstance(instance: Int, allocator: Int);
  fn vkEnumeratePhysicalDevices(instance: Int, count: Int, devices: Int) -> Int32;
  fn vkCreateDevice(physical_device: Int, create_info: Int, allocator: Int, device: Int) -> Int32;
  fn vkDestroyDevice(device: Int, allocator: Int);
  fn vkGetDeviceQueue(device: Int, queue_family: Int32, queue_index: Int32, queue: Int);
  fn vkDeviceWaitIdle(device: Int) -> Int32;
  fn vkAllocateMemory(device: Int, allocate_info: Int, allocator: Int, memory: Int) -> Int32;
  fn vkFreeMemory(device: Int, memory: Int, allocator: Int);
  fn vkMapMemory(device: Int, memory: Int, offset: Int, size: Int, flags: Int32, data: Int) -> Int32;
  fn vkUnmapMemory(device: Int, memory: Int);
  fn vkCreateBuffer(device: Int, create_info: Int, allocator: Int, buffer: Int) -> Int32;
  fn vkDestroyBuffer(device: Int, buffer: Int, allocator: Int);
  fn vkBindBufferMemory(device: Int, buffer: Int, memory: Int, offset: Int) -> Int32;
  fn vkCreateImage(device: Int, create_info: Int, allocator: Int, image: Int) -> Int32;
  fn vkDestroyImage(device: Int, image: Int, allocator: Int);
  fn vkBindImageMemory(device: Int, image: Int, memory: Int, offset: Int) -> Int32;
  fn vkCreateImageView(device: Int, create_info: Int, allocator: Int, view: Int) -> Int32;
  fn vkDestroyImageView(device: Int, view: Int, allocator: Int);
  fn vkCreateCommandPool(device: Int, create_info: Int, allocator: Int, pool: Int) -> Int32;
  fn vkDestroyCommandPool(device: Int, pool: Int, allocator: Int);
  fn vkAllocateCommandBuffers(device: Int, allocate_info: Int, command_buffers: Int) -> Int32;
  fn vkFreeCommandBuffers(device: Int, pool: Int, count: Int32, command_buffers: Int);
  fn vkBeginCommandBuffer(command_buffer: Int, begin_info: Int) -> Int32;
  fn vkEndCommandBuffer(command_buffer: Int) -> Int32;
  fn vkCreateGraphicsPipelines(device: Int, cache: Int, count: Int32, create_infos: Int, allocator: Int, pipelines: Int) -> Int32;
  fn vkCreateComputePipelines(device: Int, cache: Int, count: Int32, create_infos: Int, allocator: Int, pipelines: Int) -> Int32;
  fn vkDestroyPipeline(device: Int, pipeline: Int, allocator: Int);
  fn vkCreatePipelineLayout(device: Int, create_info: Int, allocator: Int, layout: Int) -> Int32;
  fn vkDestroyPipelineLayout(device: Int, layout: Int, allocator: Int);
  fn vkCreateShaderModule(device: Int, create_info: Int, allocator: Int, shader_module: Int) -> Int32;
  fn vkDestroyShaderModule(device: Int, shader_module: Int, allocator: Int);
  fn vkCreateDescriptorSetLayout(device: Int, create_info: Int, allocator: Int, layout: Int) -> Int32;
  fn vkDestroyDescriptorSetLayout(device: Int, layout: Int, allocator: Int);
  fn vkCreateDescriptorPool(device: Int, create_info: Int, allocator: Int, pool: Int) -> Int32;
  fn vkDestroyDescriptorPool(device: Int, pool: Int, allocator: Int);
  fn vkAllocateDescriptorSets(device: Int, allocate_info: Int, descriptor_sets: Int) -> Int32;
  fn vkFreeDescriptorSets(device: Int, pool: Int, count: Int32, descriptor_sets: Int) -> Int32;
  fn vkUpdateDescriptorSets(device: Int, write_count: Int32, writes: Int, copy_count: Int32, copies: Int);
  fn vkCreateFence(device: Int, create_info: Int, allocator: Int, fence: Int) -> Int32;
  fn vkDestroyFence(device: Int, fence: Int, allocator: Int);
  fn vkWaitForFences(device: Int, fence_count: Int32, fences: Int, wait_all: Int32, timeout: Int) -> Int32;
  fn vkCreateSemaphore(device: Int, create_info: Int, allocator: Int, semaphore: Int) -> Int32;
  fn vkDestroySemaphore(device: Int, semaphore: Int, allocator: Int);
  fn vkQueueSubmit(queue: Int, submit_count: Int32, submits: Int, fence: Int) -> Int32;
  fn vkQueueWaitIdle(queue: Int) -> Int32;
  fn vkCreateSwapchainKHR(device: Int, create_info: Int, allocator: Int, swapchain: Int) -> Int32;
  fn vkDestroySwapchainKHR(device: Int, swapchain: Int, allocator: Int);
  fn vkGetSwapchainImagesKHR(device: Int, swapchain: Int, count: Int, images: Int) -> Int32;
  fn vkAcquireNextImageKHR(device: Int, swapchain: Int, timeout: Int, semaphore: Int, fence: Int, image_index: Int) -> Int32;
  fn vkQueuePresentKHR(queue: Int, present_info: Int) -> Int32;
  fn vkCmdBeginRendering(command_buffer: Int, rendering_info: Int);
  fn vkCmdEndRendering(command_buffer: Int);
  fn vkTransitionImageLayout(device: Int, transition_count: Int32, transitions: Int) -> Int32;
}

// =========================================================================
// VulkanError type
// =========================================================================

pub type VulkanError = {
  code: Int32;
} derive[Clone]

// =========================================================================
// VulkanInstance — wraps VkInstance
// =========================================================================

pub type VulkanInstance = {
  handle: Int;
} derive[Clone]

pub fn VulkanInstance.create(create_info: Int) -> Result[VulkanInstance, VulkanError]
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let inst: Int = 0;
  let res: Int32 = unsafe { vkCreateInstance(create_info, 0, inst) };
  if res != 0 {
    return Err(VulkanError{ code: res });
  }
  return Ok(VulkanInstance{ handle: inst });
}

pub fn VulkanInstance.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyInstance(handle, 0); }
}

pub fn VulkanInstance.is_valid() -> Bool {
  return handle != 0;
}

// =========================================================================
// VulkanDevice — wraps VkDevice
// =========================================================================

pub type VulkanDevice = {
  handle: Int;
} derive[Clone]

pub fn VulkanDevice.create(physical_device: Int, create_info: Int) -> Result[VulkanDevice, VulkanError]
  requires: physical_device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let dev: Int = 0;
  let res: Int32 = unsafe { vkCreateDevice(physical_device, create_info, 0, dev) };
  if res != 0 {
    return Err(VulkanError{ code: res });
  }
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
  if res != 0 {
    return Err(VulkanError{ code: res });
  }
  return Ok(0);
}

pub fn VulkanDevice.get_queue(queue_family: Int32, queue_index: Int32) -> Int
  requires: handle != 0
{
  let queue: Int = 0;
  unsafe { vkGetDeviceQueue(handle, queue_family, queue_index, queue); }
  return queue;
}

// =========================================================================
// VulkanBuffer — wraps VkBuffer + map/unmap + size bounds
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
  if res != 0 {
    return Err(VulkanError{ code: res });
  }
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
  if res != 0 {
    return Err(VulkanError{ code: res });
  }
  return Ok(0);
}

pub fn VulkanBuffer.map(offset: Int, size: Int, flags: Int32) -> Result[Int, VulkanError]
  requires: handle != 0
  requires: size > 0
{
  let data: Int = 0;
  let res: Int32 = unsafe { vkMapMemory(device, handle, offset, size, flags, data) };
  if res != 0 {
    return Err(VulkanError{ code: res });
  }
  return Ok(data);
}

pub fn VulkanBuffer.unmap()
  requires: handle != 0
{
  unsafe { vkUnmapMemory(device, handle); }
}

// =========================================================================
// VulkanImage — wraps VkImage + layout transition
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
  if res != 0 {
    return Err(VulkanError{ code: res });
  }
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
  if res != 0 {
    return Err(VulkanError{ code: res });
  }
  return Ok(0);
}

// =========================================================================
// VulkanPipeline — wraps VkPipeline
// =========================================================================

pub type VulkanPipeline = {
  handle: Int;
  device: Int;
} derive[Clone]

pub fn VulkanPipeline.create_graphics(device: Int, cache: Int, create_info: Int) -> Result[VulkanPipeline, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let pipeline: Int = 0;
  let count = 1;
  let res: Int32 = unsafe { vkCreateGraphicsPipelines(device, cache, count as Int32, create_info, 0, pipeline) };
  if res != 0 {
    return Err(VulkanError{ code: res });
  }
  return Ok(VulkanPipeline{ handle: pipeline, device: device });
}

pub fn VulkanPipeline.create_compute(device: Int, cache: Int, create_info: Int) -> Result[VulkanPipeline, VulkanError]
  requires: device != 0
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let pipeline: Int = 0;
  let count = 1;
  let res: Int32 = unsafe { vkCreateComputePipelines(device, cache, count as Int32, create_info, 0, pipeline) };
  if res != 0 {
    return Err(VulkanError{ code: res });
  }
  return Ok(VulkanPipeline{ handle: pipeline, device: device });
}

pub fn VulkanPipeline.destroy()
  requires: handle != 0
{
  unsafe { vkDestroyPipeline(device, handle, 0); }
}

// =========================================================================
// VulkanCommandBuffer — wraps VkCommandBuffer
// =========================================================================

pub type VulkanCommandBuffer = {
  handle: Int;
  device: Int;
  pool: Int;
} derive[Clone]

pub fn VulkanCommandBuffer.allocate(device: Int, pool: Int) -> Result[VulkanCommandBuffer, VulkanError]
  requires: device != 0
  requires: pool != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let cb: Int = 0;
  let res: Int32 = unsafe { vkAllocateCommandBuffers(device, pool, cb) };
  if res != 0 {
    return Err(VulkanError{ code: res });
  }
  return Ok(VulkanCommandBuffer{ handle: cb, device: device, pool: pool });
}

pub fn VulkanCommandBuffer.free()
  requires: handle != 0
{
  let count = 1;
  unsafe { vkFreeCommandBuffers(device, pool, count as Int32, handle); }
}

pub fn VulkanCommandBuffer.begin() -> Result[Int, VulkanError]
  requires: handle != 0
{
  let res: Int32 = unsafe { vkBeginCommandBuffer(handle, 0) };
  if res != 0 {
    return Err(VulkanError{ code: res });
  }
  return Ok(0);
}

pub fn VulkanCommandBuffer.end() -> Result[Int, VulkanError]
  requires: handle != 0
{
  let res: Int32 = unsafe { vkEndCommandBuffer(handle) };
  if res != 0 {
    return Err(VulkanError{ code: res });
  }
  return Ok(0);
}

pub fn VulkanCommandBuffer.submit(queue: Int, fence: Int) -> Result[Int, VulkanError]
  requires: handle != 0
  requires: queue != 0
{
  let sc = 1;
  let res: Int32 = unsafe { vkQueueSubmit(queue, sc as Int32, 0, fence) };
  if res != 0 {
    return Err(VulkanError{ code: res });
  }
  return Ok(0);
}

// =========================================================================
// VulkanDescriptorSet — wraps VkDescriptorSet
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
  if res != 0 {
    return Err(VulkanError{ code: res });
  }
  return Ok(VulkanDescriptorSet{ handle: ds, device: device, pool: pool });
}

pub fn VulkanDescriptorSet.free()
  requires: handle != 0
{
  let count = 1;
  unsafe { vkFreeDescriptorSets(device, pool, count as Int32, handle); }
}

// =========================================================================
// Utility: VkResult → human-readable description
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
