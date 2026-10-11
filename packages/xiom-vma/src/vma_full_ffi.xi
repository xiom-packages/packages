// XIOM -- GENERATED raw FFI surface for the full top-level vma* API.
// Generator: tools/gen_vma_full.py (do not edit by hand).
// Oracle: 72 top-level vma* functions (Vulkan SDK 1.4.350.0 vk_mem_alloc.h, VMA v3.3.0).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Type mapping: pointers/opaque handles/size_t/HANDLE -> Int (0 = null);
// uint32_t/VkBool32/flags -> Int32; VkDeviceSize/VkBuffer/VkImage/
// VmaVirtualAllocation -> Int64; void -> Unit.  Out-params are C-side
// bridge slots: never read through foreign pointers (B-20).

module xiom.vma.full_ffi

pub const VMA_FULL_ORACLE_COUNT: Int = 72;

// Vulkan result codes used by the generated surface (VkResult).
pub const VK_SUCCESS: Int32 = 0;
pub const VK_ERROR_OUT_OF_HOST_MEMORY: Int32 = -1;
pub const VK_ERROR_OUT_OF_DEVICE_MEMORY: Int32 = -2;
pub const VK_ERROR_INITIALIZATION_FAILED: Int32 = -3;
pub const VK_ERROR_FEATURE_NOT_PRESENT: Int32 = -8;

// ---------------------------------------------------------------------
// The bound surface: one extern per oracle function (header order).
// ---------------------------------------------------------------------

pub extern "C" {
  fn vmafull_wrap_vmaImportVulkanFunctionsFromVolk(pAllocatorCreateInfo: Int, pDstVulkanFunctions: Int) -> Int32;
  fn vmafull_wrap_vmaCreateAllocator(pCreateInfo: Int, pAllocator: Int) -> Int32;
  fn vmafull_wrap_vmaDestroyAllocator(allocator: Int);
  fn vmafull_wrap_vmaGetAllocatorInfo(allocator: Int, pAllocatorInfo: Int);
  fn vmafull_wrap_vmaGetPhysicalDeviceProperties(allocator: Int, ppPhysicalDeviceProperties: Int);
  fn vmafull_wrap_vmaGetMemoryProperties(allocator: Int, ppPhysicalDeviceMemoryProperties: Int);
  fn vmafull_wrap_vmaGetMemoryTypeProperties(allocator: Int, memoryTypeIndex: Int32, pFlags: Int);
  fn vmafull_wrap_vmaSetCurrentFrameIndex(allocator: Int, frameIndex: Int32);
  fn vmafull_wrap_vmaCalculateStatistics(allocator: Int, pStats: Int);
  fn vmafull_wrap_vmaGetHeapBudgets(allocator: Int, pBudgets: Int);
  fn vmafull_wrap_vmaFindMemoryTypeIndex(allocator: Int, memoryTypeBits: Int32, pAllocationCreateInfo: Int, pMemoryTypeIndex: Int) -> Int32;
  fn vmafull_wrap_vmaFindMemoryTypeIndexForBufferInfo(allocator: Int, pBufferCreateInfo: Int, pAllocationCreateInfo: Int, pMemoryTypeIndex: Int) -> Int32;
  fn vmafull_wrap_vmaFindMemoryTypeIndexForImageInfo(allocator: Int, pImageCreateInfo: Int, pAllocationCreateInfo: Int, pMemoryTypeIndex: Int) -> Int32;
  fn vmafull_wrap_vmaCreatePool(allocator: Int, pCreateInfo: Int, pPool: Int) -> Int32;
  fn vmafull_wrap_vmaDestroyPool(allocator: Int, pool: Int);
  fn vmafull_wrap_vmaGetPoolStatistics(allocator: Int, pool: Int, pPoolStats: Int);
  fn vmafull_wrap_vmaCalculatePoolStatistics(allocator: Int, pool: Int, pPoolStats: Int);
  fn vmafull_wrap_vmaCheckPoolCorruption(allocator: Int, pool: Int) -> Int32;
  fn vmafull_wrap_vmaGetPoolName(allocator: Int, pool: Int, ppName: Int);
  fn vmafull_wrap_vmaSetPoolName(allocator: Int, pool: Int, pName: Int);
  fn vmafull_wrap_vmaAllocateMemory(allocator: Int, pVkMemoryRequirements: Int, pCreateInfo: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmafull_wrap_vmaAllocateMemoryPages(allocator: Int, pVkMemoryRequirements: Int, pCreateInfo: Int, allocationCount: Int, pAllocations: Int, pAllocationInfo: Int) -> Int32;
  fn vmafull_wrap_vmaAllocateMemoryForBuffer(allocator: Int, buffer: Int64, pCreateInfo: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmafull_wrap_vmaAllocateMemoryForImage(allocator: Int, image: Int64, pCreateInfo: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmafull_wrap_vmaFreeMemory(allocator: Int, allocation: Int);
  fn vmafull_wrap_vmaFreeMemoryPages(allocator: Int, allocationCount: Int, pAllocations: Int);
  fn vmafull_wrap_vmaGetAllocationInfo(allocator: Int, allocation: Int, pAllocationInfo: Int);
  fn vmafull_wrap_vmaGetAllocationInfo2(allocator: Int, allocation: Int, pAllocationInfo: Int);
  fn vmafull_wrap_vmaSetAllocationUserData(allocator: Int, allocation: Int, pUserData: Int);
  fn vmafull_wrap_vmaSetAllocationName(allocator: Int, allocation: Int, pName: Int);
  fn vmafull_wrap_vmaGetAllocationMemoryProperties(allocator: Int, allocation: Int, pFlags: Int);
  fn vmafull_wrap_vmaGetMemoryWin32Handle(allocator: Int, allocation: Int, hTargetProcess: Int, pHandle: Int) -> Int32;
  fn vmafull_wrap_vmaMapMemory(allocator: Int, allocation: Int, ppData: Int) -> Int32;
  fn vmafull_wrap_vmaUnmapMemory(allocator: Int, allocation: Int);
  fn vmafull_wrap_vmaFlushAllocation(allocator: Int, allocation: Int, offset: Int64, size: Int64) -> Int32;
  fn vmafull_wrap_vmaInvalidateAllocation(allocator: Int, allocation: Int, offset: Int64, size: Int64) -> Int32;
  fn vmafull_wrap_vmaFlushAllocations(allocator: Int, allocationCount: Int32, allocations: Int, offsets: Int, sizes: Int) -> Int32;
  fn vmafull_wrap_vmaInvalidateAllocations(allocator: Int, allocationCount: Int32, allocations: Int, offsets: Int, sizes: Int) -> Int32;
  fn vmafull_wrap_vmaCopyMemoryToAllocation(allocator: Int, pSrcHostPointer: Int, dstAllocation: Int, dstAllocationLocalOffset: Int64, size: Int64) -> Int32;
  fn vmafull_wrap_vmaCopyAllocationToMemory(allocator: Int, srcAllocation: Int, srcAllocationLocalOffset: Int64, pDstHostPointer: Int, size: Int64) -> Int32;
  fn vmafull_wrap_vmaCheckCorruption(allocator: Int, memoryTypeBits: Int32) -> Int32;
  fn vmafull_wrap_vmaBeginDefragmentation(allocator: Int, pInfo: Int, pContext: Int) -> Int32;
  fn vmafull_wrap_vmaEndDefragmentation(allocator: Int, context: Int, pStats: Int);
  fn vmafull_wrap_vmaBeginDefragmentationPass(allocator: Int, context: Int, pPassInfo: Int) -> Int32;
  fn vmafull_wrap_vmaEndDefragmentationPass(allocator: Int, context: Int, pPassInfo: Int) -> Int32;
  fn vmafull_wrap_vmaBindBufferMemory(allocator: Int, allocation: Int, buffer: Int64) -> Int32;
  fn vmafull_wrap_vmaBindBufferMemory2(allocator: Int, allocation: Int, allocationLocalOffset: Int64, buffer: Int64, pNext: Int) -> Int32;
  fn vmafull_wrap_vmaBindImageMemory(allocator: Int, allocation: Int, image: Int64) -> Int32;
  fn vmafull_wrap_vmaBindImageMemory2(allocator: Int, allocation: Int, allocationLocalOffset: Int64, image: Int64, pNext: Int) -> Int32;
  fn vmafull_wrap_vmaCreateBuffer(allocator: Int, pBufferCreateInfo: Int, pAllocationCreateInfo: Int, pBuffer: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmafull_wrap_vmaCreateBufferWithAlignment(allocator: Int, pBufferCreateInfo: Int, pAllocationCreateInfo: Int, minAlignment: Int64, pBuffer: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmafull_wrap_vmaCreateAliasingBuffer(allocator: Int, allocation: Int, pBufferCreateInfo: Int, pBuffer: Int) -> Int32;
  fn vmafull_wrap_vmaCreateAliasingBuffer2(allocator: Int, allocation: Int, allocationLocalOffset: Int64, pBufferCreateInfo: Int, pBuffer: Int) -> Int32;
  fn vmafull_wrap_vmaDestroyBuffer(allocator: Int, buffer: Int64, allocation: Int);
  fn vmafull_wrap_vmaCreateImage(allocator: Int, pImageCreateInfo: Int, pAllocationCreateInfo: Int, pImage: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmafull_wrap_vmaCreateAliasingImage(allocator: Int, allocation: Int, pImageCreateInfo: Int, pImage: Int) -> Int32;
  fn vmafull_wrap_vmaCreateAliasingImage2(allocator: Int, allocation: Int, allocationLocalOffset: Int64, pImageCreateInfo: Int, pImage: Int) -> Int32;
  fn vmafull_wrap_vmaDestroyImage(allocator: Int, image: Int64, allocation: Int);
  fn vmafull_wrap_vmaCreateVirtualBlock(pCreateInfo: Int, pVirtualBlock: Int) -> Int32;
  fn vmafull_wrap_vmaDestroyVirtualBlock(virtualBlock: Int);
  fn vmafull_wrap_vmaIsVirtualBlockEmpty(virtualBlock: Int) -> Int32;
  fn vmafull_wrap_vmaGetVirtualAllocationInfo(virtualBlock: Int, allocation: Int64, pVirtualAllocInfo: Int);
  fn vmafull_wrap_vmaVirtualAllocate(virtualBlock: Int, pCreateInfo: Int, pAllocation: Int, pOffset: Int) -> Int32;
  fn vmafull_wrap_vmaVirtualFree(virtualBlock: Int, allocation: Int64);
  fn vmafull_wrap_vmaClearVirtualBlock(virtualBlock: Int);
  fn vmafull_wrap_vmaSetVirtualAllocationUserData(virtualBlock: Int, allocation: Int64, pUserData: Int);
  fn vmafull_wrap_vmaGetVirtualBlockStatistics(virtualBlock: Int, pStats: Int);
  fn vmafull_wrap_vmaCalculateVirtualBlockStatistics(virtualBlock: Int, pStats: Int);
  fn vmafull_wrap_vmaBuildVirtualBlockStatsString(virtualBlock: Int, ppStatsString: Int, detailedMap: Int32);
  fn vmafull_wrap_vmaFreeVirtualBlockStatsString(virtualBlock: Int, pStatsString: Int);
  fn vmafull_wrap_vmaBuildStatsString(allocator: Int, ppStatsString: Int, detailedMap: Int32);
  fn vmafull_wrap_vmaFreeStatsString(allocator: Int, pStatsString: Int);
}

// ---------------------------------------------------------------------
// Bridge self-description + RHI-path support (src/vma_full_bridge.cpp).
// ---------------------------------------------------------------------

pub extern "C" {
  fn vmafull_export_count() -> Int32;
  fn vmafull_oracle_count() -> Int32;
  fn vmafull_export_name_is(index: Int32, expected: *UInt8) -> Int32;
  fn vmafull_link_proof() -> Int32;
  fn vmafull_device_setup(dll_name: *UInt8) -> Int32;
  fn vmafull_device_teardown(slot: Int32) -> Int32;
  fn vmafull_allocator_create(slot: Int32) -> Int32;
  fn vmafull_allocator_destroy(slot: Int32) -> Int32;
  fn vmafull_slot_allocator(slot: Int32) -> Int;
  fn vmafull_buffer_create(slot: Int32, size: Int64) -> Int32;
  fn vmafull_allocation_info(slot: Int32) -> Int32;
  fn vmafull_buffer_handle(slot: Int32) -> Int;
  fn vmafull_allocation_handle(slot: Int32) -> Int;
  fn vmafull_info_size(slot: Int32) -> Int64;
  fn vmafull_info_offset(slot: Int32) -> Int64;
  fn vmafull_info_memory_type(slot: Int32) -> Int32;
  fn vmafull_info_device_memory(slot: Int32) -> Int64;
  fn vmafull_buffer_destroy(slot: Int32) -> Int32;
  fn vmafull_win32_handle_probe(slot: Int32) -> Int32;
  fn vmafull_error_probe() -> Int32;
}
