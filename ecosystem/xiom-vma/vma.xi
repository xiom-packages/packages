// XIOM — Vulkan Memory Allocator (VMA) Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Low-level FFI declarations for VMA v3.3.0 (vk_mem_alloc.h).
// VMA is a Vulkan memory sub-allocation library used in production engines.
//
// Types: all Vulkan handles/pointers map to Int. VkResult → Int32.
// VkDeviceSize → Int. VkBool32 → Int32. uint32_t → Int32.
// Naming follows the C API verbatim (vmaCreateAllocator, etc.).

module xiom.vma

// =========================================================================
// VMA Memory Usage (VmaMemoryUsage)
// =========================================================================

pub const VMA_MEMORY_USAGE_UNKNOWN: Int32 = 0 as Int32;
pub const VMA_MEMORY_USAGE_GPU_ONLY: Int32 = 1 as Int32;
pub const VMA_MEMORY_USAGE_CPU_ONLY: Int32 = 2 as Int32;
pub const VMA_MEMORY_USAGE_CPU_TO_GPU: Int32 = 3 as Int32;
pub const VMA_MEMORY_USAGE_GPU_TO_CPU: Int32 = 4 as Int32;
pub const VMA_MEMORY_USAGE_CPU_COPY: Int32 = 5 as Int32;
pub const VMA_MEMORY_USAGE_GPU_LAZILY_ALLOCATED: Int32 = 6 as Int32;
pub const VMA_MEMORY_USAGE_AUTO: Int32 = 7 as Int32;
pub const VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE: Int32 = 8 as Int32;
pub const VMA_MEMORY_USAGE_AUTO_PREFER_HOST: Int32 = 9 as Int32;

// VMA Allocation Create Flags (VmaAllocationCreateFlagBits)
pub const VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT: Int32 = 1 as Int32;
pub const VMA_ALLOCATION_CREATE_NEVER_ALLOCATE_BIT: Int32 = 2 as Int32;
pub const VMA_ALLOCATION_CREATE_MAPPED_BIT: Int32 = 4 as Int32;
pub const VMA_ALLOCATION_CREATE_CAN_BECOME_LOST_BIT: Int32 = 8 as Int32;
pub const VMA_ALLOCATION_CREATE_CAN_MAKE_OTHER_LOST_BIT: Int32 = 16 as Int32;
pub const VMA_ALLOCATION_CREATE_USER_DATA_COPY_STRING_BIT: Int32 = 32 as Int32;
pub const VMA_ALLOCATION_CREATE_UPPER_ADDRESS_BIT: Int32 = 64 as Int32;
pub const VMA_ALLOCATION_CREATE_DONT_BIND_BIT: Int32 = 128 as Int32;
pub const VMA_ALLOCATION_CREATE_WITHIN_BUDGET_BIT: Int32 = 256 as Int32;
pub const VMA_ALLOCATION_CREATE_CAN_ALIAS_BIT: Int32 = 512 as Int32;
pub const VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT: Int32 = 1024 as Int32;
pub const VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT: Int32 = 2048 as Int32;
pub const VMA_ALLOCATION_CREATE_HOST_ACCESS_ALLOW_TRANSFER_INSTEAD_BIT: Int32 = 4096 as Int32;
pub const VMA_ALLOCATION_CREATE_STRATEGY_MIN_MEMORY_BIT: Int32 = 65536 as Int32;
pub const VMA_ALLOCATION_CREATE_STRATEGY_MIN_TIME_BIT: Int32 = 131072 as Int32;
pub const VMA_ALLOCATION_CREATE_STRATEGY_MIN_OFFSET_BIT: Int32 = 262144 as Int32;
pub const VMA_ALLOCATION_CREATE_STRATEGY_MASK: Int32 = 458752 as Int32;

// VMA Pool Create Flags (VmaPoolCreateFlagBits)
pub const VMA_POOL_CREATE_IGNORE_BUFFER_IMAGE_GRANULARITY_BIT: Int32 = 1 as Int32;
pub const VMA_POOL_CREATE_LINEAR_ALGORITHM_BIT: Int32 = 2 as Int32;

// VMA Allocator Create Flags (VmaAllocatorCreateFlagBits)
pub const VMA_ALLOCATOR_CREATE_EXTERNALLY_SYNCHRONIZED_BIT: Int32 = 1 as Int32;
pub const VMA_ALLOCATOR_CREATE_KHR_DEDICATED_ALLOCATION_BIT: Int32 = 2 as Int32;
pub const VMA_ALLOCATOR_CREATE_KHR_BIND_MEMORY2_BIT: Int32 = 4 as Int32;
pub const VMA_ALLOCATOR_CREATE_EXT_MEMORY_BUDGET_BIT: Int32 = 8 as Int32;
pub const VMA_ALLOCATOR_CREATE_AMD_DEVICE_COHERENT_MEMORY_BIT: Int32 = 16 as Int32;
pub const VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT: Int32 = 32 as Int32;
pub const VMA_ALLOCATOR_CREATE_EXT_MEMORY_PRIORITY_BIT: Int32 = 64 as Int32;
pub const VMA_ALLOCATOR_CREATE_KHR_MAINTENANCE4_BIT: Int32 = 128 as Int32;
pub const VMA_ALLOCATOR_CREATE_KHR_MAINTENANCE5_BIT: Int32 = 256 as Int32;

// VMA Defragmentation Flags
pub const VMA_DEFRAGMENTATION_MOVE_OPERATION_COPY: Int32 = 0 as Int32;
pub const VMA_DEFRAGMENTATION_MOVE_OPERATION_IGNORE: Int32 = 1 as Int32;
pub const VMA_DEFRAGMENTATION_MOVE_OPERATION_DESTROY: Int32 = 2 as Int32;

// =========================================================================
// FFI: 72 extern C functions from VMA v3.3.0
// =========================================================================

extern "C" {
  fn vmaCreateAllocator(pCreateInfo: Int, pAllocator: Int) -> Int32;
  fn vmaDestroyAllocator(allocator: Int);
  fn vmaGetAllocatorInfo(allocator: Int, pAllocatorInfo: Int);
  fn vmaGetPhysicalDeviceProperties(allocator: Int, ppPhysicalDeviceProperties: Int);
  fn vmaGetMemoryProperties(allocator: Int, ppPhysicalDeviceMemoryProperties: Int);
  fn vmaGetMemoryTypeProperties(allocator: Int, memoryTypeIndex: Int32, pFlags: Int);
  fn vmaSetCurrentFrameIndex(allocator: Int, frameIndex: Int32);

  fn vmaCalculateStatistics(allocator: Int, pStats: Int);
  fn vmaGetHeapBudgets(allocator: Int, pBudgets: Int);

  fn vmaFindMemoryTypeIndex(allocator: Int, memoryTypeBits: Int32, pAllocationCreateInfo: Int, pMemoryTypeIndex: Int) -> Int32;
  fn vmaFindMemoryTypeIndexForBufferInfo(allocator: Int, pBufferCreateInfo: Int, pAllocationCreateInfo: Int, pMemoryTypeIndex: Int) -> Int32;
  fn vmaFindMemoryTypeIndexForImageInfo(allocator: Int, pImageCreateInfo: Int, pAllocationCreateInfo: Int, pMemoryTypeIndex: Int) -> Int32;

  fn vmaCreatePool(allocator: Int, pCreateInfo: Int, pPool: Int) -> Int32;
  fn vmaDestroyPool(allocator: Int, pool: Int);
  fn vmaGetPoolStatistics(allocator: Int, pool: Int, pPoolStats: Int);
  fn vmaCalculatePoolStatistics(allocator: Int, pool: Int, pPoolStats: Int);
  fn vmaCheckPoolCorruption(allocator: Int, pool: Int) -> Int32;
  fn vmaGetPoolName(allocator: Int, pool: Int, ppName: Int);
  fn vmaSetPoolName(allocator: Int, pool: Int, pName: Int);

  fn vmaAllocateMemory(allocator: Int, pVkMemoryRequirements: Int, pCreateInfo: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmaAllocateMemoryPages(allocator: Int, pVkMemoryRequirements: Int, pCreateInfo: Int, allocationCount: Int, pAllocations: Int, pAllocationInfo: Int) -> Int32;
  fn vmaAllocateMemoryForBuffer(allocator: Int, buffer: Int, pCreateInfo: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmaAllocateMemoryForImage(allocator: Int, image: Int, pCreateInfo: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmaFreeMemory(allocator: Int, allocation: Int);
  fn vmaFreeMemoryPages(allocator: Int, allocationCount: Int, pAllocations: Int);

  fn vmaGetAllocationInfo(allocator: Int, allocation: Int, pAllocationInfo: Int);
  fn vmaGetAllocationInfo2(allocator: Int, allocation: Int, pAllocationInfo: Int);
  fn vmaSetAllocationUserData(allocator: Int, allocation: Int, pUserData: Int);
  fn vmaSetAllocationName(allocator: Int, allocation: Int, pName: Int);
  fn vmaGetAllocationMemoryProperties(allocator: Int, allocation: Int, pFlags: Int);

  fn vmaMapMemory(allocator: Int, allocation: Int, ppData: Int) -> Int32;
  fn vmaUnmapMemory(allocator: Int, allocation: Int);

  fn vmaFlushAllocation(allocator: Int, allocation: Int, offset: Int, size: Int) -> Int32;
  fn vmaInvalidateAllocation(allocator: Int, allocation: Int, offset: Int, size: Int) -> Int32;
  fn vmaFlushAllocations(allocator: Int, allocationCount: Int32, allocations: Int, offsets: Int, sizes: Int) -> Int32;
  fn vmaInvalidateAllocations(allocator: Int, allocationCount: Int32, allocations: Int, offsets: Int, sizes: Int) -> Int32;

  fn vmaCopyMemoryToAllocation(allocator: Int, pSrcHostPointer: Int, dstAllocation: Int, dstAllocationLocalOffset: Int, size: Int) -> Int32;
  fn vmaCopyAllocationToMemory(allocator: Int, srcAllocation: Int, srcAllocationLocalOffset: Int, pDstHostPointer: Int, size: Int) -> Int32;

  fn vmaCheckCorruption(allocator: Int, memoryTypeBits: Int32) -> Int32;

  fn vmaBeginDefragmentation(allocator: Int, pInfo: Int, pContext: Int) -> Int32;
  fn vmaEndDefragmentation(allocator: Int, context: Int, pStats: Int);
  fn vmaBeginDefragmentationPass(allocator: Int, context: Int, pPassInfo: Int) -> Int32;
  fn vmaEndDefragmentationPass(allocator: Int, context: Int, pPassInfo: Int) -> Int32;

  fn vmaBindBufferMemory(allocator: Int, allocation: Int, buffer: Int) -> Int32;
  fn vmaBindBufferMemory2(allocator: Int, allocation: Int, allocationLocalOffset: Int, buffer: Int, pNext: Int) -> Int32;
  fn vmaBindImageMemory(allocator: Int, allocation: Int, image: Int) -> Int32;
  fn vmaBindImageMemory2(allocator: Int, allocation: Int, allocationLocalOffset: Int, image: Int, pNext: Int) -> Int32;

  fn vmaCreateBuffer(allocator: Int, pBufferCreateInfo: Int, pAllocationCreateInfo: Int, pBuffer: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmaCreateBufferWithAlignment(allocator: Int, pBufferCreateInfo: Int, pAllocationCreateInfo: Int, minAlignment: Int, pBuffer: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmaCreateAliasingBuffer(allocator: Int, allocation: Int, pBufferCreateInfo: Int, pBuffer: Int) -> Int32;
  fn vmaCreateAliasingBuffer2(allocator: Int, allocation: Int, allocationLocalOffset: Int, pBufferCreateInfo: Int, pBuffer: Int) -> Int32;
  fn vmaDestroyBuffer(allocator: Int, buffer: Int, allocation: Int);

  fn vmaCreateImage(allocator: Int, pImageCreateInfo: Int, pAllocationCreateInfo: Int, pImage: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmaCreateAliasingImage(allocator: Int, allocation: Int, pImageCreateInfo: Int, pImage: Int) -> Int32;
  fn vmaCreateAliasingImage2(allocator: Int, allocation: Int, allocationLocalOffset: Int, pImageCreateInfo: Int, pImage: Int) -> Int32;
  fn vmaDestroyImage(allocator: Int, image: Int, allocation: Int);

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

  fn vmaBuildStatsString(allocator: Int, ppStatsString: Int, detailedMap: Int32);
  fn vmaFreeStatsString(allocator: Int, pStatsString: Int);

  fn vmaImportVulkanFunctionsFromVolk(createInfo: Int, dstVulkanFunctions: Int) -> Int32;
}

// =========================================================================
// Safe wrapper functions — for direct procedural use
// =========================================================================

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

pub fn check_corruption(allocator: Int, memory_type_bits: Int32) -> Bool
  requires: allocator != 0
{
  let res: Int32 = unsafe { vmaCheckCorruption(allocator, memory_type_bits) };
  return res == 0;
}

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

// =========================================================================
// VkResult → human-readable string
// =========================================================================

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
