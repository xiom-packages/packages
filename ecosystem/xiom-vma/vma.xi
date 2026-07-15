// XIOM — Vulkan Memory Allocator (VMA) Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Low-level FFI declarations for VMA v3.3.0 (vk_mem_alloc.h).
// VMA is a Vulkan memory sub-allocation library used in production engines.
//
// DESIGN NOTE: All pointer/handle params use Int. VkResult returns Int32.
// VkDeviceSize uses Int. VkBool32 uses Int32. VmaStats*String* guarded by VMA_STATS_STRING_ENABLED.
// Cross-module extern resolution is broken in v0.45.3 — safe wrappers are in
// src/vma_safe.xi which duplicates the extern block inline.

module xiom.vma

extern "C" {
  // --- Initialization ---
  fn vmaCreateAllocator(pCreateInfo: Int, pAllocator: Int) -> Int32;
  fn vmaDestroyAllocator(allocator: Int);
  fn vmaGetAllocatorInfo(allocator: Int, pAllocatorInfo: Int);
  fn vmaGetPhysicalDeviceProperties(allocator: Int, ppPhysicalDeviceProperties: Int);
  fn vmaGetMemoryProperties(allocator: Int, ppPhysicalDeviceMemoryProperties: Int);
  fn vmaGetMemoryTypeProperties(allocator: Int, memoryTypeIndex: Int32, pFlags: Int);
  fn vmaSetCurrentFrameIndex(allocator: Int, frameIndex: Int32);

  // --- Statistics ---
  fn vmaCalculateStatistics(allocator: Int, pStats: Int);
  fn vmaGetHeapBudgets(allocator: Int, pBudgets: Int);

  // --- Memory Type Discovery ---
  fn vmaFindMemoryTypeIndex(allocator: Int, memoryTypeBits: Int32, pAllocationCreateInfo: Int, pMemoryTypeIndex: Int) -> Int32;
  fn vmaFindMemoryTypeIndexForBufferInfo(allocator: Int, pBufferCreateInfo: Int, pAllocationCreateInfo: Int, pMemoryTypeIndex: Int) -> Int32;
  fn vmaFindMemoryTypeIndexForImageInfo(allocator: Int, pImageCreateInfo: Int, pAllocationCreateInfo: Int, pMemoryTypeIndex: Int) -> Int32;

  // --- Pools ---
  fn vmaCreatePool(allocator: Int, pCreateInfo: Int, pPool: Int) -> Int32;
  fn vmaDestroyPool(allocator: Int, pool: Int);
  fn vmaGetPoolStatistics(allocator: Int, pool: Int, pPoolStats: Int);
  fn vmaCalculatePoolStatistics(allocator: Int, pool: Int, pPoolStats: Int);
  fn vmaCheckPoolCorruption(allocator: Int, pool: Int) -> Int32;
  fn vmaGetPoolName(allocator: Int, pool: Int, ppName: Int);
  fn vmaSetPoolName(allocator: Int, pool: Int, pName: Int);

  // --- Allocation ---
  fn vmaAllocateMemory(allocator: Int, pVkMemoryRequirements: Int, pCreateInfo: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmaAllocateMemoryPages(allocator: Int, pVkMemoryRequirements: Int, pCreateInfo: Int, allocationCount: Int, pAllocations: Int, pAllocationInfo: Int) -> Int32;
  fn vmaAllocateMemoryForBuffer(allocator: Int, buffer: Int, pCreateInfo: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmaAllocateMemoryForImage(allocator: Int, image: Int, pCreateInfo: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmaFreeMemory(allocator: Int, allocation: Int);
  fn vmaFreeMemoryPages(allocator: Int, allocationCount: Int, pAllocations: Int);

  // --- Allocation Info ---
  fn vmaGetAllocationInfo(allocator: Int, allocation: Int, pAllocationInfo: Int);
  fn vmaGetAllocationInfo2(allocator: Int, allocation: Int, pAllocationInfo: Int);
  fn vmaSetAllocationUserData(allocator: Int, allocation: Int, pUserData: Int);
  fn vmaSetAllocationName(allocator: Int, allocation: Int, pName: Int);
  fn vmaGetAllocationMemoryProperties(allocator: Int, allocation: Int, pFlags: Int);

  // --- Mapping ---
  fn vmaMapMemory(allocator: Int, allocation: Int, ppData: Int) -> Int32;
  fn vmaUnmapMemory(allocator: Int, allocation: Int);

  // --- Cache Control ---
  fn vmaFlushAllocation(allocator: Int, allocation: Int, offset: Int, size: Int) -> Int32;
  fn vmaInvalidateAllocation(allocator: Int, allocation: Int, offset: Int, size: Int) -> Int32;
  fn vmaFlushAllocations(allocator: Int, allocationCount: Int32, allocations: Int, offsets: Int, sizes: Int) -> Int32;
  fn vmaInvalidateAllocations(allocator: Int, allocationCount: Int32, allocations: Int, offsets: Int, sizes: Int) -> Int32;

  // --- Copy Utilities ---
  fn vmaCopyMemoryToAllocation(allocator: Int, pSrcHostPointer: Int, dstAllocation: Int, dstAllocationLocalOffset: Int, size: Int) -> Int32;
  fn vmaCopyAllocationToMemory(allocator: Int, srcAllocation: Int, srcAllocationLocalOffset: Int, pDstHostPointer: Int, size: Int) -> Int32;

  // --- Corruption Detection ---
  fn vmaCheckCorruption(allocator: Int, memoryTypeBits: Int32) -> Int32;

  // --- Defragmentation ---
  fn vmaBeginDefragmentation(allocator: Int, pInfo: Int, pContext: Int) -> Int32;
  fn vmaEndDefragmentation(allocator: Int, context: Int, pStats: Int);
  fn vmaBeginDefragmentationPass(allocator: Int, context: Int, pPassInfo: Int) -> Int32;
  fn vmaEndDefragmentationPass(allocator: Int, context: Int, pPassInfo: Int) -> Int32;

  // --- Binding ---
  fn vmaBindBufferMemory(allocator: Int, allocation: Int, buffer: Int) -> Int32;
  fn vmaBindBufferMemory2(allocator: Int, allocation: Int, allocationLocalOffset: Int, buffer: Int, pNext: Int) -> Int32;
  fn vmaBindImageMemory(allocator: Int, allocation: Int, image: Int) -> Int32;
  fn vmaBindImageMemory2(allocator: Int, allocation: Int, allocationLocalOffset: Int, image: Int, pNext: Int) -> Int32;

  // --- Buffer Creation ---
  fn vmaCreateBuffer(allocator: Int, pBufferCreateInfo: Int, pAllocationCreateInfo: Int, pBuffer: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmaCreateBufferWithAlignment(allocator: Int, pBufferCreateInfo: Int, pAllocationCreateInfo: Int, minAlignment: Int, pBuffer: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmaCreateAliasingBuffer(allocator: Int, allocation: Int, pBufferCreateInfo: Int, pBuffer: Int) -> Int32;
  fn vmaCreateAliasingBuffer2(allocator: Int, allocation: Int, allocationLocalOffset: Int, pBufferCreateInfo: Int, pBuffer: Int) -> Int32;
  fn vmaDestroyBuffer(allocator: Int, buffer: Int, allocation: Int);

  // --- Image Creation ---
  fn vmaCreateImage(allocator: Int, pImageCreateInfo: Int, pAllocationCreateInfo: Int, pImage: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmaCreateAliasingImage(allocator: Int, allocation: Int, pImageCreateInfo: Int, pImage: Int) -> Int32;
  fn vmaCreateAliasingImage2(allocator: Int, allocation: Int, allocationLocalOffset: Int, pImageCreateInfo: Int, pImage: Int) -> Int32;
  fn vmaDestroyImage(allocator: Int, image: Int, allocation: Int);

  // --- Virtual Allocator ---
  fn vmaCreateVirtualBlock(pCreateInfo: Int, pVirtualBlock: Int) -> Int32;
  fn vmaDestroyVirtualBlock(virtualBlock: Int);
  fn vmaIsVirtualBlockEmpty(virtualBlock: Int) -> Int32;
  fn vmaGetVirtualAllocationInfo(virtualBlock: Int, allocation: Int, pVirtualAllocInfo: Int);
  fn vmaVirtualAllocate(virtualBlock: Int, pCreateInfo: Int, pAllocation: Int, pOffset: Int) -> Int32;
  fn vmaVirtualFree(virtualBlock: Int, allocation: Int);
  fn vmaClearVirtualBlock(virtualBlock: Int);
  fn vmaSetVirtualAllocationUserData(virtualBlock: Int, allocation: Int, pUserData: Int);
  fn vmaGetVirtualBlockStatistics(virtualBlock: Int, pStats: Int);
  fn vmaCalculateVirtualBlockStatistics(virtualBlock: Int, pStats: Int);
  fn vmaBuildVirtualBlockStatsString(virtualBlock: Int, ppStatsString: Int, detailedMap: Int32);
  fn vmaFreeVirtualBlockStatsString(virtualBlock: Int, pStatsString: Int);

  // --- Stats String ---
  fn vmaBuildStatsString(allocator: Int, ppStatsString: Int, detailedMap: Int32);
  fn vmaFreeStatsString(allocator: Int, pStatsString: Int);

  // --- Volk Integration ---
  fn vmaImportVulkanFunctionsFromVolk(createInfo: Int, dstVulkanFunctions: Int) -> Int32;
}

// =========================================================================
// Core safe wrappers (inline — cross-module extern resolution is broken)
// =========================================================================

// --- Allocator create/destroy ---

pub fn create_allocator(create_info: Int) -> Result[Int, Str]
  requires: create_info != 0
{
  let alloc: Int = 0;
  let res: Int32 = unsafe { vmaCreateAllocator(create_info, alloc) };
  if res != 0 {
    return Err("vmaCreateAllocator failed");
  }
  return Ok(alloc);
}

pub fn destroy_allocator(allocator: Int)
  requires: allocator != 0
{
  unsafe { vmaDestroyAllocator(allocator); }
}

// --- Allocation ---

pub fn allocate_memory(allocator: Int, p_vk_memory_requirements: Int, p_create_info: Int) -> Result[Int, Str]
  requires: allocator != 0
  requires: p_vk_memory_requirements != 0
  requires: p_create_info != 0
{
  let alloc: Int = 0;
  let res: Int32 = unsafe { vmaAllocateMemory(allocator, p_vk_memory_requirements, p_create_info, alloc, 0) };
  if res != 0 {
    return Err("vmaAllocateMemory failed");
  }
  return Ok(alloc);
}

pub fn free_memory(allocator: Int, allocation: Int)
  requires: allocator != 0
  requires: allocation != 0
{
  unsafe { vmaFreeMemory(allocator, allocation); }
}

pub fn allocate_memory_for_buffer(allocator: Int, buffer: Int, p_create_info: Int) -> Result[Int, Str]
  requires: allocator != 0
  requires: buffer != 0
  requires: p_create_info != 0
{
  let alloc: Int = 0;
  let res: Int32 = unsafe { vmaAllocateMemoryForBuffer(allocator, buffer, p_create_info, alloc, 0) };
  if res != 0 {
    return Err("vmaAllocateMemoryForBuffer failed");
  }
  return Ok(alloc);
}

pub fn allocate_memory_for_image(allocator: Int, image: Int, p_create_info: Int) -> Result[Int, Str]
  requires: allocator != 0
  requires: image != 0
  requires: p_create_info != 0
{
  let alloc: Int = 0;
  let res: Int32 = unsafe { vmaAllocateMemoryForImage(allocator, image, p_create_info, alloc, 0) };
  if res != 0 {
    return Err("vmaAllocateMemoryForImage failed");
  }
  return Ok(alloc);
}

pub fn free_memory_pages(allocator: Int, allocation_count: Int, p_allocations: Int)
  requires: allocator != 0
  requires: allocation_count > 0
  requires: p_allocations != 0
{
  unsafe { vmaFreeMemoryPages(allocator, allocation_count, p_allocations); }
}

// --- Mapping ---

pub fn map_memory(allocator: Int, allocation: Int) -> Result[Int, Str]
  requires: allocator != 0
  requires: allocation != 0
{
  let data: Int = 0;
  let res: Int32 = unsafe { vmaMapMemory(allocator, allocation, data) };
  if res != 0 {
    return Err("vmaMapMemory failed");
  }
  return Ok(data);
}

pub fn unmap_memory(allocator: Int, allocation: Int)
  requires: allocator != 0
  requires: allocation != 0
{
  unsafe { vmaUnmapMemory(allocator, allocation); }
}

// --- Cache control ---

pub fn flush_allocation(allocator: Int, allocation: Int, offset: Int, size: Int) -> Bool
  requires: allocator != 0
  requires: allocation != 0
{
  let res: Int32 = unsafe { vmaFlushAllocation(allocator, allocation, offset, size) };
  return res == 0;
}

pub fn invalidate_allocation(allocator: Int, allocation: Int, offset: Int, size: Int) -> Bool
  requires: allocator != 0
  requires: allocation != 0
{
  let res: Int32 = unsafe { vmaInvalidateAllocation(allocator, allocation, offset, size) };
  return res == 0;
}

// --- Pool create/destroy ---

pub fn create_pool(allocator: Int, p_create_info: Int) -> Result[Int, Str]
  requires: allocator != 0
  requires: p_create_info != 0
{
  let pool: Int = 0;
  let res: Int32 = unsafe { vmaCreatePool(allocator, p_create_info, pool) };
  if res != 0 {
    return Err("vmaCreatePool failed");
  }
  return Ok(pool);
}

pub fn destroy_pool(allocator: Int, pool: Int)
  requires: allocator != 0
  requires: pool != 0
{
  unsafe { vmaDestroyPool(allocator, pool); }
}

// --- Buffer create/destroy (convenience: creates buffer + allocates + binds) ---

pub fn create_buffer(allocator: Int, p_buffer_create_info: Int, p_alloc_create_info: Int) -> Result[Int, Str]
  requires: allocator != 0
  requires: p_buffer_create_info != 0
  requires: p_alloc_create_info != 0
{
  let buf: Int = 0;
  let alloc: Int = 0;
  let res: Int32 = unsafe { vmaCreateBuffer(allocator, p_buffer_create_info, p_alloc_create_info, buf, alloc, 0) };
  if res != 0 {
    return Err("vmaCreateBuffer failed");
  }
  return Ok(buf);
}

pub fn destroy_buffer(allocator: Int, buffer: Int, allocation: Int)
  requires: allocator != 0
{
  unsafe { vmaDestroyBuffer(allocator, buffer, allocation); }
}

// --- Image create/destroy (convenience: creates image + allocates + binds) ---

pub fn create_image(allocator: Int, p_image_create_info: Int, p_alloc_create_info: Int) -> Result[Int, Str]
  requires: allocator != 0
  requires: p_image_create_info != 0
  requires: p_alloc_create_info != 0
{
  let img: Int = 0;
  let alloc: Int = 0;
  let res: Int32 = unsafe { vmaCreateImage(allocator, p_image_create_info, p_alloc_create_info, img, alloc, 0) };
  if res != 0 {
    return Err("vmaCreateImage failed");
  }
  return Ok(img);
}

pub fn destroy_image(allocator: Int, image: Int, allocation: Int)
  requires: allocator != 0
{
  unsafe { vmaDestroyImage(allocator, image, allocation); }
}

// --- Binding ---

pub fn bind_buffer_memory(allocator: Int, allocation: Int, buffer: Int) -> Bool
  requires: allocator != 0
  requires: allocation != 0
  requires: buffer != 0
{
  let res: Int32 = unsafe { vmaBindBufferMemory(allocator, allocation, buffer) };
  return res == 0;
}

pub fn bind_image_memory(allocator: Int, allocation: Int, image: Int) -> Bool
  requires: allocator != 0
  requires: allocation != 0
  requires: image != 0
{
  let res: Int32 = unsafe { vmaBindImageMemory(allocator, allocation, image) };
  return res == 0;
}

// --- Memory type index ---

pub fn find_memory_type_index(allocator: Int, memory_type_bits: Int32, p_alloc_create_info: Int) -> Result[Int, Str]
  requires: allocator != 0
  requires: p_alloc_create_info != 0
{
  let index: Int = 0;
  let res: Int32 = unsafe { vmaFindMemoryTypeIndex(allocator, memory_type_bits, p_alloc_create_info, index) };
  if res != 0 {
    return Err("vmaFindMemoryTypeIndex failed");
  }
  return Ok(index);
}

// --- Corruption check ---

pub fn check_corruption(allocator: Int, memory_type_bits: Int32) -> Bool
  requires: allocator != 0
{
  let res: Int32 = unsafe { vmaCheckCorruption(allocator, memory_type_bits) };
  return res == 0;
}

// --- Defragmentation ---

pub fn begin_defragmentation(allocator: Int, p_info: Int) -> Result[Int, Str]
  requires: allocator != 0
  requires: p_info != 0
{
  let context: Int = 0;
  let res: Int32 = unsafe { vmaBeginDefragmentation(allocator, p_info, context) };
  if res != 0 {
    return Err("vmaBeginDefragmentation failed");
  }
  return Ok(context);
}

pub fn end_defragmentation(allocator: Int, context: Int)
  requires: allocator != 0
  requires: context != 0
{
  unsafe { vmaEndDefragmentation(allocator, context, 0); }
}

// --- Stats string ---

pub fn build_stats_string(allocator: Int, detailed: Int32) -> Result[Int, Str]
  requires: allocator != 0
{
  let str_ptr: Int = 0;
  unsafe { vmaBuildStatsString(allocator, str_ptr, detailed); }
  if str_ptr == 0 {
    return Err("vmaBuildStatsString returned null");
  }
  return Ok(str_ptr);
}

pub fn free_stats_string(allocator: Int, p_stats_string: Int)
  requires: allocator != 0
  requires: p_stats_string != 0
{
  unsafe { vmaFreeStatsString(allocator, p_stats_string); }
}

// --- VMA Error → human-readable string ---

pub fn result_to_string(code: Int32) -> Str {
  if code == 0     { return "VK_SUCCESS"; }
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
