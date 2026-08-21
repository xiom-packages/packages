// XIOM -- Vulkan Memory Allocator Safe Wrappers
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Struct-based safe resource management for VMA v3.3.0.
// All create/destroy pairs with Result[T, VulkanError] + design-by-contract.
//
// COVERAGE: 5 resource types spanning the full VMA lifecycle:
//   VmaAllocator, VmaAllocation, VmaPool, VmaBuffer, VmaImage
//
// Compiler: XIOM v0.46.0 -- cross-module extern resolution fixed.
// Uses `pub extern "C"` declarations from xiom.vma via `use xiom.vma`.

module xiom.vma.safe

use xiom.vma;

// =========================================================================
// VulkanError
// =========================================================================

pub type VulkanError = {
  code: Int32;
} derive[Clone]

// =========================================================================
// VmaAllocator -- central allocator object
// =========================================================================

pub type VmaAllocator = {
  handle: Int;
} derive[Clone]

pub fn VmaAllocator.create(create_info: Int) -> Result[VmaAllocator, VulkanError]
  requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let alloc: Int = 0;
  let res: Int32 = unsafe { vmaCreateAllocator(create_info, alloc) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VmaAllocator{ handle: alloc });
}

pub fn VmaAllocator.destroy()
  requires: handle != 0
{
  unsafe { vmaDestroyAllocator(handle); }
}

pub fn VmaAllocator.find_memory_type_index(memory_type_bits: Int32, alloc_create_info: Int) -> Result[Int, VulkanError]
  requires: handle != 0; requires: alloc_create_info != 0
{
  let idx: Int = 0;
  let res: Int32 = unsafe { vmaFindMemoryTypeIndex(handle, memory_type_bits, alloc_create_info, idx) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(idx);
}

pub fn VmaAllocator.find_memory_type_index_for_buffer(buffer_create_info: Int, alloc_create_info: Int) -> Result[Int, VulkanError]
  requires: handle != 0; requires: buffer_create_info != 0; requires: alloc_create_info != 0
{
  let idx: Int = 0;
  let res: Int32 = unsafe { vmaFindMemoryTypeIndexForBufferInfo(handle, buffer_create_info, alloc_create_info, idx) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(idx);
}

pub fn VmaAllocator.find_memory_type_index_for_image(image_create_info: Int, alloc_create_info: Int) -> Result[Int, VulkanError]
  requires: handle != 0; requires: image_create_info != 0; requires: alloc_create_info != 0
{
  let idx: Int = 0;
  let res: Int32 = unsafe { vmaFindMemoryTypeIndexForImageInfo(handle, image_create_info, alloc_create_info, idx) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(idx);
}

pub fn VmaAllocator.check_corruption(memory_type_bits: Int32) -> Result[Int, VulkanError]
  requires: handle != 0
{
  let res: Int32 = unsafe { vmaCheckCorruption(handle, memory_type_bits) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

pub fn VmaAllocator.get_heap_budgets(budgets_ptr: Int)
  requires: handle != 0; requires: budgets_ptr != 0
{
  unsafe { vmaGetHeapBudgets(handle, budgets_ptr); }
}

pub fn VmaAllocator.calculate_statistics(stats_ptr: Int)
  requires: handle != 0; requires: stats_ptr != 0
{
  unsafe { vmaCalculateStatistics(handle, stats_ptr); }
}

pub fn VmaAllocator.build_stats_string(detailed: Int32) -> Result[Int, VulkanError]
  requires: handle != 0
{
  let str_ptr: Int = 0;
  unsafe { vmaBuildStatsString(handle, str_ptr, detailed); }
  if str_ptr == 0 { return Err(VulkanError{ code: 1 }); }
  return Ok(str_ptr);
}

pub fn VmaAllocator.free_stats_string(stats_string: Int)
  requires: handle != 0; requires: stats_string != 0
{
  unsafe { vmaFreeStatsString(handle, stats_string); }
}

pub fn VmaAllocator.get_memory_type_properties(memory_type_index: Int32, flags_ptr: Int)
  requires: handle != 0; requires: flags_ptr != 0
{
  unsafe { vmaGetMemoryTypeProperties(handle, memory_type_index, flags_ptr); }
}

// =========================================================================
// VmaAllocation -- a memory allocation
// =========================================================================

pub type VmaAllocation = {
  handle: Int;
  allocator: Int;
} derive[Clone]

pub fn VmaAllocation.allocate(allocator: Int, vk_memory_requirements: Int, create_info: Int) -> Result[VmaAllocation, VulkanError]
  requires: allocator != 0; requires: vk_memory_requirements != 0; requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let alloc: Int = 0;
  let res: Int32 = unsafe { vmaAllocateMemory(allocator, vk_memory_requirements, create_info, alloc, 0) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VmaAllocation{ handle: alloc, allocator: allocator });
}

pub fn VmaAllocation.allocate_for_buffer(allocator: Int, buffer: Int, create_info: Int) -> Result[VmaAllocation, VulkanError]
  requires: allocator != 0; requires: buffer != 0; requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let alloc: Int = 0;
  let res: Int32 = unsafe { vmaAllocateMemoryForBuffer(allocator, buffer, create_info, alloc, 0) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VmaAllocation{ handle: alloc, allocator: allocator });
}

pub fn VmaAllocation.allocate_for_image(allocator: Int, image: Int, create_info: Int) -> Result[VmaAllocation, VulkanError]
  requires: allocator != 0; requires: image != 0; requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let alloc: Int = 0;
  let res: Int32 = unsafe { vmaAllocateMemoryForImage(allocator, image, create_info, alloc, 0) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VmaAllocation{ handle: alloc, allocator: allocator });
}

pub fn VmaAllocation.free()
  requires: handle != 0; requires: allocator != 0
{
  unsafe { vmaFreeMemory(allocator, handle); }
}

pub fn VmaAllocation.get_info(info_ptr: Int)
  requires: handle != 0; requires: allocator != 0; requires: info_ptr != 0
{
  unsafe { vmaGetAllocationInfo(allocator, handle, info_ptr); }
}

pub fn VmaAllocation.set_user_data(user_data: Int)
  requires: handle != 0; requires: allocator != 0
{
  unsafe { vmaSetAllocationUserData(allocator, handle, user_data); }
}

pub fn VmaAllocation.map_memory() -> Result[Int, VulkanError]
  requires: handle != 0; requires: allocator != 0
{
  let data: Int = 0;
  let res: Int32 = unsafe { vmaMapMemory(allocator, handle, data) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(data);
}

pub fn VmaAllocation.unmap_memory()
  requires: handle != 0; requires: allocator != 0
{
  unsafe { vmaUnmapMemory(allocator, handle); }
}

pub fn VmaAllocation.flush(offset: Int, size: Int) -> Result[Int, VulkanError]
  requires: handle != 0; requires: allocator != 0
{
  let res: Int32 = unsafe { vmaFlushAllocation(allocator, handle, offset, size) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

pub fn VmaAllocation.invalidate(offset: Int, size: Int) -> Result[Int, VulkanError]
  requires: handle != 0; requires: allocator != 0
{
  let res: Int32 = unsafe { vmaInvalidateAllocation(allocator, handle, offset, size) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

pub fn VmaAllocation.bind_buffer(buffer: Int) -> Result[Int, VulkanError]
  requires: handle != 0; requires: allocator != 0; requires: buffer != 0
{
  let res: Int32 = unsafe { vmaBindBufferMemory(allocator, handle, buffer) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

pub fn VmaAllocation.bind_image(image: Int) -> Result[Int, VulkanError]
  requires: handle != 0; requires: allocator != 0; requires: image != 0
{
  let res: Int32 = unsafe { vmaBindImageMemory(allocator, handle, image) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

// =========================================================================
// VmaPool -- a custom memory pool
// =========================================================================

pub type VmaPool = {
  handle: Int;
  allocator: Int;
} derive[Clone]

pub fn VmaPool.create(allocator: Int, create_info: Int) -> Result[VmaPool, VulkanError]
  requires: allocator != 0; requires: create_info != 0
  ensures: result is Ok => result.unwrap().handle != 0
{
  let pool: Int = 0;
  let res: Int32 = unsafe { vmaCreatePool(allocator, create_info, pool) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VmaPool{ handle: pool, allocator: allocator });
}

pub fn VmaPool.destroy()
  requires: handle != 0; requires: allocator != 0
{
  unsafe { vmaDestroyPool(allocator, handle); }
}

pub fn VmaPool.check_corruption() -> Result[Int, VulkanError]
  requires: handle != 0; requires: allocator != 0
{
  let res: Int32 = unsafe { vmaCheckPoolCorruption(allocator, handle) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(0);
}

pub fn VmaPool.get_name() -> Int
  requires: handle != 0; requires: allocator != 0
{
  let name: Int = 0;
  unsafe { vmaGetPoolName(allocator, handle, name); }
  return name;
}

pub fn VmaPool.set_name(p_name: Int)
  requires: handle != 0; requires: allocator != 0
{
  unsafe { vmaSetPoolName(allocator, handle, p_name); }
}

// =========================================================================
// VmaBuffer -- a VkBuffer created and managed by VMA
// =========================================================================

pub type VmaBuffer = {
  buffer: Int;
  allocation: Int;
  allocator: Int;
} derive[Clone]

pub fn VmaBuffer.create(allocator: Int, buffer_create_info: Int, alloc_create_info: Int) -> Result[VmaBuffer, VulkanError]
  requires: allocator != 0; requires: buffer_create_info != 0; requires: alloc_create_info != 0
  ensures: result is Ok => result.unwrap().buffer != 0
{
  let buf: Int = 0;
  let alloc: Int = 0;
  let res: Int32 = unsafe { vmaCreateBuffer(allocator, buffer_create_info, alloc_create_info, buf, alloc, 0) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VmaBuffer{ buffer: buf, allocation: alloc, allocator: allocator });
}

pub fn VmaBuffer.destroy()
  requires: allocator != 0; requires: buffer != 0; requires: allocation != 0
{
  unsafe { vmaDestroyBuffer(allocator, buffer, allocation); }
}

// =========================================================================
// VmaImage -- a VkImage created and managed by VMA
// =========================================================================

pub type VmaImage = {
  image: Int;
  allocation: Int;
  allocator: Int;
} derive[Clone]

pub fn VmaImage.create(allocator: Int, image_create_info: Int, alloc_create_info: Int) -> Result[VmaImage, VulkanError]
  requires: allocator != 0; requires: image_create_info != 0; requires: alloc_create_info != 0
  ensures: result is Ok => result.unwrap().image != 0
{
  let img: Int = 0;
  let alloc: Int = 0;
  let res: Int32 = unsafe { vmaCreateImage(allocator, image_create_info, alloc_create_info, img, alloc, 0) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(VmaImage{ image: img, allocation: alloc, allocator: allocator });
}

pub fn VmaImage.destroy()
  requires: allocator != 0; requires: image != 0; requires: allocation != 0
{
  unsafe { vmaDestroyImage(allocator, image, allocation); }
}

// =========================================================================
// Defragmentation helpers
// =========================================================================

pub fn begin_defragmentation(allocator: Int, p_info: Int) -> Result[Int, VulkanError]
  requires: allocator != 0; requires: p_info != 0
{
  let context: Int = 0;
  let res: Int32 = unsafe { vmaBeginDefragmentation(allocator, p_info, context) };
  if res != 0 { return Err(VulkanError{ code: res }); }
  return Ok(context);
}

pub fn end_defragmentation(allocator: Int, context: Int)
  requires: allocator != 0; requires: context != 0
{
  unsafe { vmaEndDefragmentation(allocator, context, 0); }
}

// =========================================================================
// VmaContext -- high-level lifecycle manager
// =========================================================================

pub type VmaContext = {
  allocator: Int;
} derive[Clone]

pub fn VmaContext.init(create_info: Int) -> Result[VmaContext, VulkanError]
  requires: create_info != 0
{
  let a = VmaAllocator.create(create_info)?;
  return Ok(VmaContext{ allocator: a.handle });
}

pub fn VmaContext.destroy()
  requires: allocator != 0
{
  unsafe { vmaDestroyAllocator(allocator); }
}

pub fn VmaContext.create_buffer(buffer_create_info: Int, alloc_create_info: Int) -> Result[VmaBuffer, VulkanError]
  requires: allocator != 0; requires: buffer_create_info != 0; requires: alloc_create_info != 0
{
  return VmaBuffer.create(allocator, buffer_create_info, alloc_create_info);
}

pub fn VmaContext.create_image(image_create_info: Int, alloc_create_info: Int) -> Result[VmaImage, VulkanError]
  requires: allocator != 0; requires: image_create_info != 0; requires: alloc_create_info != 0
{
  return VmaImage.create(allocator, image_create_info, alloc_create_info);
}

pub fn VmaContext.create_pool(pool_create_info: Int) -> Result[VmaPool, VulkanError]
  requires: allocator != 0; requires: pool_create_info != 0
{
  return VmaPool.create(allocator, pool_create_info);
}
