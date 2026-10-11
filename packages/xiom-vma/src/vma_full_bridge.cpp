// xiom.vma -- GENERATED full-surface bridge over the top-level vma* API.
// Generator: tools/gen_vma_full.py (do not edit by hand).
// Oracle: C:\VulkanSDK\1.4.350.0\Include\vma\vk_mem_alloc.h
//         sha256=90CE12FC4A2466235A09AE02905DD0C13AEE80C1BBF11B331AB61230C2CEB112  functions=72
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// COMPOSITION: this single TU is the package's only compiled C++ unit.
// It composes the existing probe bridge (src/vma_bridge.cpp -- included
// verbatim, unchanged: VMA implementation + packed probe) with the
// generated wrappers below.  The TU-level config makes the two
// config-gated API families reachable:
//   VK_USE_PLATFORM_WIN32_KHR -> vendor/vulkan/vulkan_win32.h ->
//     VMA_EXTERNAL_MEMORY_WIN32=1 -> vmaGetMemoryWin32Handle
//   VOLK_IMPLEMENTATION + vendor/volk -> VOLK_HEADER_VERSION ->
//     vmaImportVulkanFunctionsFromVolk (volk loader is NOT initialized;
//     the wrapper is bridged and null-guard-probed only).
//
// ABI (B-20 discipline): every wrapper mirrors the C signature; XIOM
// passes pointers as Int and scalars as Int32/Int64.  Bridge -> XIOM data
// crosses as scalar returns only (packed ints and getter calls), never by
// reading foreign memory through pointers; the B-11 slot-recycle shape is
// avoided.  VMA_NOT_NULL pointer parameters are guarded: a null argument
// returns VK_ERROR_INITIALIZATION_FAILED (or VK_FALSE / no-op for
// VkBool32 / void wrappers) instead of tripping VMA_ASSERT.
#define NOMINMAX 1
#define WIN32_LEAN_AND_MEAN 1
#define VK_USE_PLATFORM_WIN32_KHR 1
#define VOLK_IMPLEMENTATION 1
#include "../vendor/volk/volk.h"

// Existing probe bridge + VMA implementation (unchanged file).
#include "vma_bridge.cpp"

#include <cstdint>

#if !defined(VOLK_HEADER_VERSION)
#error gen_vma_full: volk.h must define VOLK_HEADER_VERSION
#endif
#if !defined(VK_KHR_external_memory_win32)
#error gen_vma_full: vendor/vulkan/vulkan_win32.h must be reachable
#endif
#if !defined(VMA_EXTERNAL_MEMORY_WIN32) || !VMA_EXTERNAL_MEMORY_WIN32
#error gen_vma_full: VMA_EXTERNAL_MEMORY_WIN32 must be 1
#endif

// ---------------------------------------------------------------------------
// Generated wrappers: one per top-level vma* function (signature mirrored,
// VMA_NOT_NULL pointer args null-guarded).
// ---------------------------------------------------------------------------

extern "C" VkResult vmafull_wrap_vmaImportVulkanFunctionsFromVolk(const VmaAllocatorCreateInfo* pAllocatorCreateInfo, VmaVulkanFunctions* pDstVulkanFunctions) {
  if (pAllocatorCreateInfo == 0 || pDstVulkanFunctions == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaImportVulkanFunctionsFromVolk(pAllocatorCreateInfo, pDstVulkanFunctions);
}

extern "C" VkResult vmafull_wrap_vmaCreateAllocator(const VmaAllocatorCreateInfo* pCreateInfo, VmaAllocator* pAllocator) {
  if (pCreateInfo == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaCreateAllocator(pCreateInfo, pAllocator);
}

extern "C" void vmafull_wrap_vmaDestroyAllocator(VmaAllocator allocator) {
  vmaDestroyAllocator(allocator);
}

extern "C" void vmafull_wrap_vmaGetAllocatorInfo(VmaAllocator allocator, VmaAllocatorInfo* pAllocatorInfo) {
  if (allocator == 0 || pAllocatorInfo == 0) return;
  vmaGetAllocatorInfo(allocator, pAllocatorInfo);
}

extern "C" void vmafull_wrap_vmaGetPhysicalDeviceProperties(VmaAllocator allocator, const VkPhysicalDeviceProperties** ppPhysicalDeviceProperties) {
  if (allocator == 0) return;
  vmaGetPhysicalDeviceProperties(allocator, ppPhysicalDeviceProperties);
}

extern "C" void vmafull_wrap_vmaGetMemoryProperties(VmaAllocator allocator, const VkPhysicalDeviceMemoryProperties** ppPhysicalDeviceMemoryProperties) {
  if (allocator == 0) return;
  vmaGetMemoryProperties(allocator, ppPhysicalDeviceMemoryProperties);
}

extern "C" void vmafull_wrap_vmaGetMemoryTypeProperties(VmaAllocator allocator, uint32_t memoryTypeIndex, VkMemoryPropertyFlags* pFlags) {
  if (allocator == 0 || pFlags == 0) return;
  vmaGetMemoryTypeProperties(allocator, memoryTypeIndex, pFlags);
}

extern "C" void vmafull_wrap_vmaSetCurrentFrameIndex(VmaAllocator allocator, uint32_t frameIndex) {
  if (allocator == 0) return;
  vmaSetCurrentFrameIndex(allocator, frameIndex);
}

extern "C" void vmafull_wrap_vmaCalculateStatistics(VmaAllocator allocator, VmaTotalStatistics* pStats) {
  if (allocator == 0 || pStats == 0) return;
  vmaCalculateStatistics(allocator, pStats);
}

extern "C" void vmafull_wrap_vmaGetHeapBudgets(VmaAllocator allocator, VmaBudget* pBudgets) {
  if (allocator == 0 || pBudgets == 0) return;
  vmaGetHeapBudgets(allocator, pBudgets);
}

extern "C" VkResult vmafull_wrap_vmaFindMemoryTypeIndex(VmaAllocator allocator, uint32_t memoryTypeBits, const VmaAllocationCreateInfo* pAllocationCreateInfo, uint32_t* pMemoryTypeIndex) {
  if (allocator == 0 || pAllocationCreateInfo == 0 || pMemoryTypeIndex == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaFindMemoryTypeIndex(allocator, memoryTypeBits, pAllocationCreateInfo, pMemoryTypeIndex);
}

extern "C" VkResult vmafull_wrap_vmaFindMemoryTypeIndexForBufferInfo(VmaAllocator allocator, const VkBufferCreateInfo* pBufferCreateInfo, const VmaAllocationCreateInfo* pAllocationCreateInfo, uint32_t* pMemoryTypeIndex) {
  if (allocator == 0 || pBufferCreateInfo == 0 || pAllocationCreateInfo == 0 || pMemoryTypeIndex == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaFindMemoryTypeIndexForBufferInfo(allocator, pBufferCreateInfo, pAllocationCreateInfo, pMemoryTypeIndex);
}

extern "C" VkResult vmafull_wrap_vmaFindMemoryTypeIndexForImageInfo(VmaAllocator allocator, const VkImageCreateInfo* pImageCreateInfo, const VmaAllocationCreateInfo* pAllocationCreateInfo, uint32_t* pMemoryTypeIndex) {
  if (allocator == 0 || pImageCreateInfo == 0 || pAllocationCreateInfo == 0 || pMemoryTypeIndex == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaFindMemoryTypeIndexForImageInfo(allocator, pImageCreateInfo, pAllocationCreateInfo, pMemoryTypeIndex);
}

extern "C" VkResult vmafull_wrap_vmaCreatePool(VmaAllocator allocator, const VmaPoolCreateInfo* pCreateInfo, VmaPool* pPool) {
  if (allocator == 0 || pCreateInfo == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaCreatePool(allocator, pCreateInfo, pPool);
}

extern "C" void vmafull_wrap_vmaDestroyPool(VmaAllocator allocator, VmaPool pool) {
  if (allocator == 0) return;
  vmaDestroyPool(allocator, pool);
}

extern "C" void vmafull_wrap_vmaGetPoolStatistics(VmaAllocator allocator, VmaPool pool, VmaStatistics* pPoolStats) {
  if (allocator == 0 || pool == 0 || pPoolStats == 0) return;
  vmaGetPoolStatistics(allocator, pool, pPoolStats);
}

extern "C" void vmafull_wrap_vmaCalculatePoolStatistics(VmaAllocator allocator, VmaPool pool, VmaDetailedStatistics* pPoolStats) {
  if (allocator == 0 || pool == 0 || pPoolStats == 0) return;
  vmaCalculatePoolStatistics(allocator, pool, pPoolStats);
}

extern "C" VkResult vmafull_wrap_vmaCheckPoolCorruption(VmaAllocator allocator, VmaPool pool) {
  if (allocator == 0 || pool == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaCheckPoolCorruption(allocator, pool);
}

extern "C" void vmafull_wrap_vmaGetPoolName(VmaAllocator allocator, VmaPool pool, const char** ppName) {
  if (allocator == 0 || pool == 0) return;
  vmaGetPoolName(allocator, pool, ppName);
}

extern "C" void vmafull_wrap_vmaSetPoolName(VmaAllocator allocator, VmaPool pool, const char* pName) {
  if (allocator == 0 || pool == 0) return;
  vmaSetPoolName(allocator, pool, pName);
}

extern "C" VkResult vmafull_wrap_vmaAllocateMemory(VmaAllocator allocator, const VkMemoryRequirements* pVkMemoryRequirements, const VmaAllocationCreateInfo* pCreateInfo, VmaAllocation* pAllocation, VmaAllocationInfo* pAllocationInfo) {
  if (allocator == 0 || pVkMemoryRequirements == 0 || pCreateInfo == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaAllocateMemory(allocator, pVkMemoryRequirements, pCreateInfo, pAllocation, pAllocationInfo);
}

extern "C" VkResult vmafull_wrap_vmaAllocateMemoryPages(VmaAllocator allocator, const VkMemoryRequirements* pVkMemoryRequirements, const VmaAllocationCreateInfo* pCreateInfo, size_t allocationCount, VmaAllocation* pAllocations, VmaAllocationInfo* pAllocationInfo) {
  if (allocator == 0 || pVkMemoryRequirements == 0 || pCreateInfo == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaAllocateMemoryPages(allocator, pVkMemoryRequirements, pCreateInfo, allocationCount, pAllocations, pAllocationInfo);
}

extern "C" VkResult vmafull_wrap_vmaAllocateMemoryForBuffer(VmaAllocator allocator, VkBuffer buffer, const VmaAllocationCreateInfo* pCreateInfo, VmaAllocation* pAllocation, VmaAllocationInfo* pAllocationInfo) {
  if (allocator == 0 || pCreateInfo == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaAllocateMemoryForBuffer(allocator, buffer, pCreateInfo, pAllocation, pAllocationInfo);
}

extern "C" VkResult vmafull_wrap_vmaAllocateMemoryForImage(VmaAllocator allocator, VkImage image, const VmaAllocationCreateInfo* pCreateInfo, VmaAllocation* pAllocation, VmaAllocationInfo* pAllocationInfo) {
  if (allocator == 0 || pCreateInfo == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaAllocateMemoryForImage(allocator, image, pCreateInfo, pAllocation, pAllocationInfo);
}

extern "C" void vmafull_wrap_vmaFreeMemory(VmaAllocator allocator, VmaAllocation allocation) {
  if (allocator == 0) return;
  vmaFreeMemory(allocator, allocation);
}

extern "C" void vmafull_wrap_vmaFreeMemoryPages(VmaAllocator allocator, size_t allocationCount, const VmaAllocation* pAllocations) {
  if (allocator == 0) return;
  vmaFreeMemoryPages(allocator, allocationCount, pAllocations);
}

extern "C" void vmafull_wrap_vmaGetAllocationInfo(VmaAllocator allocator, VmaAllocation allocation, VmaAllocationInfo* pAllocationInfo) {
  if (allocator == 0 || allocation == 0 || pAllocationInfo == 0) return;
  vmaGetAllocationInfo(allocator, allocation, pAllocationInfo);
}

extern "C" void vmafull_wrap_vmaGetAllocationInfo2(VmaAllocator allocator, VmaAllocation allocation, VmaAllocationInfo2* pAllocationInfo) {
  if (allocator == 0 || allocation == 0 || pAllocationInfo == 0) return;
  vmaGetAllocationInfo2(allocator, allocation, pAllocationInfo);
}

extern "C" void vmafull_wrap_vmaSetAllocationUserData(VmaAllocator allocator, VmaAllocation allocation, void* pUserData) {
  if (allocator == 0 || allocation == 0) return;
  vmaSetAllocationUserData(allocator, allocation, pUserData);
}

extern "C" void vmafull_wrap_vmaSetAllocationName(VmaAllocator allocator, VmaAllocation allocation, const char* pName) {
  if (allocator == 0 || allocation == 0) return;
  vmaSetAllocationName(allocator, allocation, pName);
}

extern "C" void vmafull_wrap_vmaGetAllocationMemoryProperties(VmaAllocator allocator, VmaAllocation allocation, VkMemoryPropertyFlags* pFlags) {
  if (allocator == 0 || allocation == 0 || pFlags == 0) return;
  vmaGetAllocationMemoryProperties(allocator, allocation, pFlags);
}

extern "C" VkResult vmafull_wrap_vmaGetMemoryWin32Handle(VmaAllocator allocator, VmaAllocation allocation, HANDLE hTargetProcess, HANDLE* pHandle) {
  if (allocator == 0 || allocation == 0 || pHandle == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaGetMemoryWin32Handle(allocator, allocation, hTargetProcess, pHandle);
}

extern "C" VkResult vmafull_wrap_vmaMapMemory(VmaAllocator allocator, VmaAllocation allocation, void** ppData) {
  if (allocator == 0 || allocation == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaMapMemory(allocator, allocation, ppData);
}

extern "C" void vmafull_wrap_vmaUnmapMemory(VmaAllocator allocator, VmaAllocation allocation) {
  if (allocator == 0 || allocation == 0) return;
  vmaUnmapMemory(allocator, allocation);
}

extern "C" VkResult vmafull_wrap_vmaFlushAllocation(VmaAllocator allocator, VmaAllocation allocation, VkDeviceSize offset, VkDeviceSize size) {
  if (allocator == 0 || allocation == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaFlushAllocation(allocator, allocation, offset, size);
}

extern "C" VkResult vmafull_wrap_vmaInvalidateAllocation(VmaAllocator allocator, VmaAllocation allocation, VkDeviceSize offset, VkDeviceSize size) {
  if (allocator == 0 || allocation == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaInvalidateAllocation(allocator, allocation, offset, size);
}

extern "C" VkResult vmafull_wrap_vmaFlushAllocations(VmaAllocator allocator, uint32_t allocationCount, const VmaAllocation* allocations, const VkDeviceSize* offsets, const VkDeviceSize* sizes) {
  if (allocator == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaFlushAllocations(allocator, allocationCount, allocations, offsets, sizes);
}

extern "C" VkResult vmafull_wrap_vmaInvalidateAllocations(VmaAllocator allocator, uint32_t allocationCount, const VmaAllocation* allocations, const VkDeviceSize* offsets, const VkDeviceSize* sizes) {
  if (allocator == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaInvalidateAllocations(allocator, allocationCount, allocations, offsets, sizes);
}

extern "C" VkResult vmafull_wrap_vmaCopyMemoryToAllocation(VmaAllocator allocator, const void* pSrcHostPointer, VmaAllocation dstAllocation, VkDeviceSize dstAllocationLocalOffset, VkDeviceSize size) {
  if (allocator == 0 || pSrcHostPointer == 0 || dstAllocation == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaCopyMemoryToAllocation(allocator, pSrcHostPointer, dstAllocation, dstAllocationLocalOffset, size);
}

extern "C" VkResult vmafull_wrap_vmaCopyAllocationToMemory(VmaAllocator allocator, VmaAllocation srcAllocation, VkDeviceSize srcAllocationLocalOffset, void* pDstHostPointer, VkDeviceSize size) {
  if (allocator == 0 || srcAllocation == 0 || pDstHostPointer == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaCopyAllocationToMemory(allocator, srcAllocation, srcAllocationLocalOffset, pDstHostPointer, size);
}

extern "C" VkResult vmafull_wrap_vmaCheckCorruption(VmaAllocator allocator, uint32_t memoryTypeBits) {
  if (allocator == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaCheckCorruption(allocator, memoryTypeBits);
}

extern "C" VkResult vmafull_wrap_vmaBeginDefragmentation(VmaAllocator allocator, const VmaDefragmentationInfo* pInfo, VmaDefragmentationContext* pContext) {
  if (allocator == 0 || pInfo == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaBeginDefragmentation(allocator, pInfo, pContext);
}

extern "C" void vmafull_wrap_vmaEndDefragmentation(VmaAllocator allocator, VmaDefragmentationContext context, VmaDefragmentationStats* pStats) {
  if (allocator == 0 || context == 0) return;
  vmaEndDefragmentation(allocator, context, pStats);
}

extern "C" VkResult vmafull_wrap_vmaBeginDefragmentationPass(VmaAllocator allocator, VmaDefragmentationContext context, VmaDefragmentationPassMoveInfo* pPassInfo) {
  if (allocator == 0 || context == 0 || pPassInfo == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaBeginDefragmentationPass(allocator, context, pPassInfo);
}

extern "C" VkResult vmafull_wrap_vmaEndDefragmentationPass(VmaAllocator allocator, VmaDefragmentationContext context, VmaDefragmentationPassMoveInfo* pPassInfo) {
  if (allocator == 0 || context == 0 || pPassInfo == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaEndDefragmentationPass(allocator, context, pPassInfo);
}

extern "C" VkResult vmafull_wrap_vmaBindBufferMemory(VmaAllocator allocator, VmaAllocation allocation, VkBuffer buffer) {
  if (allocator == 0 || allocation == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaBindBufferMemory(allocator, allocation, buffer);
}

extern "C" VkResult vmafull_wrap_vmaBindBufferMemory2(VmaAllocator allocator, VmaAllocation allocation, VkDeviceSize allocationLocalOffset, VkBuffer buffer, const void* pNext) {
  if (allocator == 0 || allocation == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaBindBufferMemory2(allocator, allocation, allocationLocalOffset, buffer, pNext);
}

extern "C" VkResult vmafull_wrap_vmaBindImageMemory(VmaAllocator allocator, VmaAllocation allocation, VkImage image) {
  if (allocator == 0 || allocation == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaBindImageMemory(allocator, allocation, image);
}

extern "C" VkResult vmafull_wrap_vmaBindImageMemory2(VmaAllocator allocator, VmaAllocation allocation, VkDeviceSize allocationLocalOffset, VkImage image, const void* pNext) {
  if (allocator == 0 || allocation == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaBindImageMemory2(allocator, allocation, allocationLocalOffset, image, pNext);
}

extern "C" VkResult vmafull_wrap_vmaCreateBuffer(VmaAllocator allocator, const VkBufferCreateInfo* pBufferCreateInfo, const VmaAllocationCreateInfo* pAllocationCreateInfo, VkBuffer* pBuffer, VmaAllocation* pAllocation, VmaAllocationInfo* pAllocationInfo) {
  if (allocator == 0 || pBufferCreateInfo == 0 || pAllocationCreateInfo == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaCreateBuffer(allocator, pBufferCreateInfo, pAllocationCreateInfo, pBuffer, pAllocation, pAllocationInfo);
}

extern "C" VkResult vmafull_wrap_vmaCreateBufferWithAlignment(VmaAllocator allocator, const VkBufferCreateInfo* pBufferCreateInfo, const VmaAllocationCreateInfo* pAllocationCreateInfo, VkDeviceSize minAlignment, VkBuffer* pBuffer, VmaAllocation* pAllocation, VmaAllocationInfo* pAllocationInfo) {
  if (allocator == 0 || pBufferCreateInfo == 0 || pAllocationCreateInfo == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaCreateBufferWithAlignment(allocator, pBufferCreateInfo, pAllocationCreateInfo, minAlignment, pBuffer, pAllocation, pAllocationInfo);
}

extern "C" VkResult vmafull_wrap_vmaCreateAliasingBuffer(VmaAllocator allocator, VmaAllocation allocation, const VkBufferCreateInfo* pBufferCreateInfo, VkBuffer* pBuffer) {
  if (allocator == 0 || allocation == 0 || pBufferCreateInfo == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaCreateAliasingBuffer(allocator, allocation, pBufferCreateInfo, pBuffer);
}

extern "C" VkResult vmafull_wrap_vmaCreateAliasingBuffer2(VmaAllocator allocator, VmaAllocation allocation, VkDeviceSize allocationLocalOffset, const VkBufferCreateInfo* pBufferCreateInfo, VkBuffer* pBuffer) {
  if (allocator == 0 || allocation == 0 || pBufferCreateInfo == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaCreateAliasingBuffer2(allocator, allocation, allocationLocalOffset, pBufferCreateInfo, pBuffer);
}

extern "C" void vmafull_wrap_vmaDestroyBuffer(VmaAllocator allocator, VkBuffer buffer, VmaAllocation allocation) {
  if (allocator == 0) return;
  vmaDestroyBuffer(allocator, buffer, allocation);
}

extern "C" VkResult vmafull_wrap_vmaCreateImage(VmaAllocator allocator, const VkImageCreateInfo* pImageCreateInfo, const VmaAllocationCreateInfo* pAllocationCreateInfo, VkImage* pImage, VmaAllocation* pAllocation, VmaAllocationInfo* pAllocationInfo) {
  if (allocator == 0 || pImageCreateInfo == 0 || pAllocationCreateInfo == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaCreateImage(allocator, pImageCreateInfo, pAllocationCreateInfo, pImage, pAllocation, pAllocationInfo);
}

extern "C" VkResult vmafull_wrap_vmaCreateAliasingImage(VmaAllocator allocator, VmaAllocation allocation, const VkImageCreateInfo* pImageCreateInfo, VkImage* pImage) {
  if (allocator == 0 || allocation == 0 || pImageCreateInfo == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaCreateAliasingImage(allocator, allocation, pImageCreateInfo, pImage);
}

extern "C" VkResult vmafull_wrap_vmaCreateAliasingImage2(VmaAllocator allocator, VmaAllocation allocation, VkDeviceSize allocationLocalOffset, const VkImageCreateInfo* pImageCreateInfo, VkImage* pImage) {
  if (allocator == 0 || allocation == 0 || pImageCreateInfo == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaCreateAliasingImage2(allocator, allocation, allocationLocalOffset, pImageCreateInfo, pImage);
}

extern "C" void vmafull_wrap_vmaDestroyImage(VmaAllocator allocator, VkImage image, VmaAllocation allocation) {
  if (allocator == 0) return;
  vmaDestroyImage(allocator, image, allocation);
}

extern "C" VkResult vmafull_wrap_vmaCreateVirtualBlock(const VmaVirtualBlockCreateInfo* pCreateInfo, VmaVirtualBlock* pVirtualBlock) {
  if (pCreateInfo == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaCreateVirtualBlock(pCreateInfo, pVirtualBlock);
}

extern "C" void vmafull_wrap_vmaDestroyVirtualBlock(VmaVirtualBlock virtualBlock) {
  vmaDestroyVirtualBlock(virtualBlock);
}

extern "C" VkBool32 vmafull_wrap_vmaIsVirtualBlockEmpty(VmaVirtualBlock virtualBlock) {
  if (virtualBlock == 0) return VK_FALSE;
  return vmaIsVirtualBlockEmpty(virtualBlock);
}

extern "C" void vmafull_wrap_vmaGetVirtualAllocationInfo(VmaVirtualBlock virtualBlock, VmaVirtualAllocation allocation, VmaVirtualAllocationInfo* pVirtualAllocInfo) {
  if (virtualBlock == 0 || pVirtualAllocInfo == 0) return;
  vmaGetVirtualAllocationInfo(virtualBlock, allocation, pVirtualAllocInfo);
}

extern "C" VkResult vmafull_wrap_vmaVirtualAllocate(VmaVirtualBlock virtualBlock, const VmaVirtualAllocationCreateInfo* pCreateInfo, VmaVirtualAllocation* pAllocation, VkDeviceSize* pOffset) {
  if (virtualBlock == 0 || pCreateInfo == 0) return VK_ERROR_INITIALIZATION_FAILED;
  return vmaVirtualAllocate(virtualBlock, pCreateInfo, pAllocation, pOffset);
}

extern "C" void vmafull_wrap_vmaVirtualFree(VmaVirtualBlock virtualBlock, VmaVirtualAllocation allocation) {
  if (virtualBlock == 0) return;
  vmaVirtualFree(virtualBlock, allocation);
}

extern "C" void vmafull_wrap_vmaClearVirtualBlock(VmaVirtualBlock virtualBlock) {
  if (virtualBlock == 0) return;
  vmaClearVirtualBlock(virtualBlock);
}

extern "C" void vmafull_wrap_vmaSetVirtualAllocationUserData(VmaVirtualBlock virtualBlock, VmaVirtualAllocation allocation, void* pUserData) {
  if (virtualBlock == 0) return;
  vmaSetVirtualAllocationUserData(virtualBlock, allocation, pUserData);
}

extern "C" void vmafull_wrap_vmaGetVirtualBlockStatistics(VmaVirtualBlock virtualBlock, VmaStatistics* pStats) {
  if (virtualBlock == 0 || pStats == 0) return;
  vmaGetVirtualBlockStatistics(virtualBlock, pStats);
}

extern "C" void vmafull_wrap_vmaCalculateVirtualBlockStatistics(VmaVirtualBlock virtualBlock, VmaDetailedStatistics* pStats) {
  if (virtualBlock == 0 || pStats == 0) return;
  vmaCalculateVirtualBlockStatistics(virtualBlock, pStats);
}

extern "C" void vmafull_wrap_vmaBuildVirtualBlockStatsString(VmaVirtualBlock virtualBlock, char** ppStatsString, VkBool32 detailedMap) {
  if (virtualBlock == 0) return;
  vmaBuildVirtualBlockStatsString(virtualBlock, ppStatsString, detailedMap);
}

extern "C" void vmafull_wrap_vmaFreeVirtualBlockStatsString(VmaVirtualBlock virtualBlock, char* pStatsString) {
  if (virtualBlock == 0) return;
  vmaFreeVirtualBlockStatsString(virtualBlock, pStatsString);
}

extern "C" void vmafull_wrap_vmaBuildStatsString(VmaAllocator allocator, char** ppStatsString, VkBool32 detailedMap) {
  if (allocator == 0) return;
  vmaBuildStatsString(allocator, ppStatsString, detailedMap);
}

extern "C" void vmafull_wrap_vmaFreeStatsString(VmaAllocator allocator, char* pStatsString) {
  if (allocator == 0) return;
  vmaFreeStatsString(allocator, pStatsString);
}


// ---------------------------------------------------------------------------
// Export table + self-description (runtime coverage proof for the suite).
// ---------------------------------------------------------------------------

static const char* const g_vmafull_export_names[72] = {
    "vmaImportVulkanFunctionsFromVolk",
    "vmaCreateAllocator",
    "vmaDestroyAllocator",
    "vmaGetAllocatorInfo",
    "vmaGetPhysicalDeviceProperties",
    "vmaGetMemoryProperties",
    "vmaGetMemoryTypeProperties",
    "vmaSetCurrentFrameIndex",
    "vmaCalculateStatistics",
    "vmaGetHeapBudgets",
    "vmaFindMemoryTypeIndex",
    "vmaFindMemoryTypeIndexForBufferInfo",
    "vmaFindMemoryTypeIndexForImageInfo",
    "vmaCreatePool",
    "vmaDestroyPool",
    "vmaGetPoolStatistics",
    "vmaCalculatePoolStatistics",
    "vmaCheckPoolCorruption",
    "vmaGetPoolName",
    "vmaSetPoolName",
    "vmaAllocateMemory",
    "vmaAllocateMemoryPages",
    "vmaAllocateMemoryForBuffer",
    "vmaAllocateMemoryForImage",
    "vmaFreeMemory",
    "vmaFreeMemoryPages",
    "vmaGetAllocationInfo",
    "vmaGetAllocationInfo2",
    "vmaSetAllocationUserData",
    "vmaSetAllocationName",
    "vmaGetAllocationMemoryProperties",
    "vmaGetMemoryWin32Handle",
    "vmaMapMemory",
    "vmaUnmapMemory",
    "vmaFlushAllocation",
    "vmaInvalidateAllocation",
    "vmaFlushAllocations",
    "vmaInvalidateAllocations",
    "vmaCopyMemoryToAllocation",
    "vmaCopyAllocationToMemory",
    "vmaCheckCorruption",
    "vmaBeginDefragmentation",
    "vmaEndDefragmentation",
    "vmaBeginDefragmentationPass",
    "vmaEndDefragmentationPass",
    "vmaBindBufferMemory",
    "vmaBindBufferMemory2",
    "vmaBindImageMemory",
    "vmaBindImageMemory2",
    "vmaCreateBuffer",
    "vmaCreateBufferWithAlignment",
    "vmaCreateAliasingBuffer",
    "vmaCreateAliasingBuffer2",
    "vmaDestroyBuffer",
    "vmaCreateImage",
    "vmaCreateAliasingImage",
    "vmaCreateAliasingImage2",
    "vmaDestroyImage",
    "vmaCreateVirtualBlock",
    "vmaDestroyVirtualBlock",
    "vmaIsVirtualBlockEmpty",
    "vmaGetVirtualAllocationInfo",
    "vmaVirtualAllocate",
    "vmaVirtualFree",
    "vmaClearVirtualBlock",
    "vmaSetVirtualAllocationUserData",
    "vmaGetVirtualBlockStatistics",
    "vmaCalculateVirtualBlockStatistics",
    "vmaBuildVirtualBlockStatsString",
    "vmaFreeVirtualBlockStatsString",
    "vmaBuildStatsString",
    "vmaFreeStatsString",
};

extern "C" int vmafull_export_count(void) { return 72; }
extern "C" int vmafull_oracle_count(void) { return 72; }

extern "C" int vmafull_export_name_is(int index, const char* expected) {
  if (index < 0 || index >= 72 || expected == 0) return 0;
  const char* a = g_vmafull_export_names[index];
  const char* b = expected;
  while (*a != '\0' && *a == *b) { ++a; ++b; }
  return (*a == '\0' && *b == '\0') ? 1 : 0;
}

// Forces a link-time reference to every wrapper; returns 72 when all
// of them are present in the binary (a missing symbol fails the link).
extern "C" int vmafull_link_proof(void) {
  static volatile int sink = 0;
  int hits = 0;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaImportVulkanFunctionsFromVolk != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaCreateAllocator != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaDestroyAllocator != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaGetAllocatorInfo != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaGetPhysicalDeviceProperties != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaGetMemoryProperties != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaGetMemoryTypeProperties != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaSetCurrentFrameIndex != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaCalculateStatistics != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaGetHeapBudgets != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaFindMemoryTypeIndex != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaFindMemoryTypeIndexForBufferInfo != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaFindMemoryTypeIndexForImageInfo != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaCreatePool != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaDestroyPool != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaGetPoolStatistics != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaCalculatePoolStatistics != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaCheckPoolCorruption != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaGetPoolName != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaSetPoolName != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaAllocateMemory != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaAllocateMemoryPages != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaAllocateMemoryForBuffer != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaAllocateMemoryForImage != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaFreeMemory != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaFreeMemoryPages != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaGetAllocationInfo != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaGetAllocationInfo2 != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaSetAllocationUserData != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaSetAllocationName != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaGetAllocationMemoryProperties != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaGetMemoryWin32Handle != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaMapMemory != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaUnmapMemory != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaFlushAllocation != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaInvalidateAllocation != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaFlushAllocations != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaInvalidateAllocations != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaCopyMemoryToAllocation != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaCopyAllocationToMemory != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaCheckCorruption != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaBeginDefragmentation != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaEndDefragmentation != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaBeginDefragmentationPass != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaEndDefragmentationPass != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaBindBufferMemory != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaBindBufferMemory2 != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaBindImageMemory != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaBindImageMemory2 != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaCreateBuffer != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaCreateBufferWithAlignment != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaCreateAliasingBuffer != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaCreateAliasingBuffer2 != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaDestroyBuffer != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaCreateImage != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaCreateAliasingImage != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaCreateAliasingImage2 != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaDestroyImage != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaCreateVirtualBlock != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaDestroyVirtualBlock != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaIsVirtualBlockEmpty != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaGetVirtualAllocationInfo != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaVirtualAllocate != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaVirtualFree != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaClearVirtualBlock != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaSetVirtualAllocationUserData != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaGetVirtualBlockStatistics != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaCalculateVirtualBlockStatistics != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaBuildVirtualBlockStatsString != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaFreeVirtualBlockStatsString != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaBuildStatsString != 0); ++hits;
  sink ^= (int)((intptr_t)(void*)&vmafull_wrap_vmaFreeStatsString != 0); ++hits;

  return hits;
}

// ---------------------------------------------------------------------------
// RHI path support: device -> allocator -> buffer -> info -> teardown.
// Every VMA step below goes through the generated wrappers above (the
// device/instance/queue creation mirrors src/vma_bridge.cpp run_probe).
// Handles stay in bridge-owned slots; XIOM reads scalars via getters.
// ---------------------------------------------------------------------------

namespace {

struct VmaFullSlot {
  int state;  // 0 free; 1 device; 2 allocator; 3 buffer
  HMODULE mod;
  PFN_vkGetInstanceProcAddr gipa;
  PFN_vkGetDeviceProcAddr gdpa;
  VkInstance instance;
  VkPhysicalDevice physical;
  VkDevice device;
  uint32_t queue_family;
  PFN_vkDestroyInstance destroy_instance;
  PFN_vkDestroyDevice destroy_device;
  VmaAllocator allocator;
  VkBuffer buffer;
  VmaAllocation allocation;
  VmaAllocationInfo info;
};

VmaFullSlot g_vmafull_slots[4] = {};

VmaFullSlot* vmafull_slot(int handle) {
  if (handle < 1 || handle > 4) return 0;
  return &g_vmafull_slots[handle - 1];
}

int vmafull_alloc_slot(void) {
  for (int i = 0; i < 4; ++i) {
    if (g_vmafull_slots[i].state == 0) return i + 1;
  }
  return 0;
}

void vmafull_slot_cleanup(VmaFullSlot* s) {
  if (s->allocator != 0) vmaDestroyAllocator(s->allocator);
  if (s->device != 0 && s->destroy_device != 0) s->destroy_device(s->device, 0);
  if (s->instance != 0 && s->destroy_instance != 0) s->destroy_instance(s->instance, 0);
  if (s->mod != 0) FreeLibrary(s->mod);
  *s = VmaFullSlot{};
}

} // namespace

// Creates instance -> physical device -> graphics-queue device (the
// package's device creation path); returns a 1-based slot, or a negative
// classification: -100 loader missing, -101 no physical device,
// -102 no graphics queue family, -1..-9 step failures.
extern "C" int vmafull_device_setup(const char* dll_name) {
  if (dll_name == 0) return -1;
  int h = vmafull_alloc_slot();
  if (h == 0) return -1;
  VmaFullSlot* s = &g_vmafull_slots[h - 1];
  s->state = 1;

  s->mod = LoadLibraryA(dll_name);
  if (s->mod == 0) { *s = VmaFullSlot{}; return -100; }
  s->gipa = (PFN_vkGetInstanceProcAddr)(void*)GetProcAddress(s->mod, "vkGetInstanceProcAddr");
  if (s->gipa == 0) { vmafull_slot_cleanup(s); return -100; }

  PFN_vkCreateInstance create_instance =
      (PFN_vkCreateInstance)s->gipa(VK_NULL_HANDLE, "vkCreateInstance");
  if (create_instance == 0) { vmafull_slot_cleanup(s); return -2; }

  VkApplicationInfo app_info = { VK_STRUCTURE_TYPE_APPLICATION_INFO };
  app_info.apiVersion = VK_API_VERSION_1_0;
  VkInstanceCreateInfo instance_info = { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO };
  instance_info.pApplicationInfo = &app_info;
  if (create_instance(&instance_info, 0, &s->instance) != VK_SUCCESS) {
    vmafull_slot_cleanup(s);
    return -2;
  }
  s->destroy_instance = (PFN_vkDestroyInstance)s->gipa(s->instance, "vkDestroyInstance");

  PFN_vkEnumeratePhysicalDevices enumerate_devices =
      (PFN_vkEnumeratePhysicalDevices)s->gipa(s->instance, "vkEnumeratePhysicalDevices");
  if (enumerate_devices == 0) { vmafull_slot_cleanup(s); return -3; }
  uint32_t device_count = 0;
  if (enumerate_devices(s->instance, &device_count, 0) != VK_SUCCESS || device_count == 0) {
    vmafull_slot_cleanup(s);
    return -101;
  }
  VkPhysicalDevice devices[8] = {};
  uint32_t n = device_count < 8 ? device_count : 8;
  if (enumerate_devices(s->instance, &n, devices) != VK_SUCCESS || n == 0) {
    vmafull_slot_cleanup(s);
    return -101;
  }

  PFN_vkGetPhysicalDeviceQueueFamilyProperties get_queue_props =
      (PFN_vkGetPhysicalDeviceQueueFamilyProperties)s->gipa(s->instance, "vkGetPhysicalDeviceQueueFamilyProperties");
  PFN_vkCreateDevice create_device =
      (PFN_vkCreateDevice)s->gipa(s->instance, "vkCreateDevice");
  if (get_queue_props == 0 || create_device == 0) { vmafull_slot_cleanup(s); return -3; }

  uint32_t queue_family = UINT32_MAX;
  for (uint32_t i = 0; i < n && s->physical == VK_NULL_HANDLE; ++i) {
    uint32_t qcount = 0;
    get_queue_props(devices[i], &qcount, 0);
    VkQueueFamilyProperties props[32] = {};
    uint32_t qn = qcount < 32 ? qcount : 32;
    get_queue_props(devices[i], &qn, props);
    for (uint32_t q = 0; q < qn; ++q) {
      if ((props[q].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0) {
        s->physical = devices[i];
        queue_family = q;
        break;
      }
    }
  }
  if (s->physical == VK_NULL_HANDLE) { vmafull_slot_cleanup(s); return -102; }

  float priority = 1.0f;
  VkDeviceQueueCreateInfo queue_info = { VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO };
  queue_info.queueFamilyIndex = queue_family;
  queue_info.queueCount = 1;
  queue_info.pQueuePriorities = &priority;
  VkDeviceCreateInfo device_info = { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO };
  device_info.queueCreateInfoCount = 1;
  device_info.pQueueCreateInfos = &queue_info;
  if (create_device(s->physical, &device_info, 0, &s->device) != VK_SUCCESS) {
    vmafull_slot_cleanup(s);
    return -4;
  }
  s->destroy_device = (PFN_vkDestroyDevice)s->gipa(s->instance, "vkDestroyDevice");
  s->gdpa = (PFN_vkGetDeviceProcAddr)s->gipa(s->instance, "vkGetDeviceProcAddr");
  if (s->gdpa == 0) { vmafull_slot_cleanup(s); return -3; }
  s->queue_family = queue_family;
  s->state = 1;
  return h;
}

extern "C" int vmafull_device_teardown(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0) return -1;
  vmafull_slot_cleanup(s);
  return 0;
}

// vmaCreateAllocator through the generated wrapper (VMA dynamic functions
// over the setup's gipa/gdpa).  Returns the VkResult.
extern "C" int vmafull_allocator_create(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0 || s->state < 1) return -1;
  if (s->allocator != 0) return -2;
  VmaVulkanFunctions fns = {};
  fns.vkGetInstanceProcAddr = s->gipa;
  fns.vkGetDeviceProcAddr = s->gdpa;
  VmaAllocatorCreateInfo info = {};
  info.physicalDevice = s->physical;
  info.device = s->device;
  info.instance = s->instance;
  info.vulkanApiVersion = VK_API_VERSION_1_0;
  info.pVulkanFunctions = &fns;
  VmaAllocator allocator = VK_NULL_HANDLE;
  VkResult res = vmafull_wrap_vmaCreateAllocator(&info, &allocator);
  if (res == VK_SUCCESS) {
    s->allocator = allocator;
    s->state = 2;
  }
  return (int)res;
}

// vmaDestroyAllocator through the generated wrapper.
extern "C" int vmafull_allocator_destroy(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0 || s->allocator == 0) return -1;
  vmafull_wrap_vmaDestroyAllocator(s->allocator);
  s->allocator = VK_NULL_HANDLE;
  s->state = 1;
  return 0;
}

extern "C" int64_t vmafull_slot_allocator(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0) return 0;
  return (int64_t)(intptr_t)s->allocator;
}

// vmaCreateBuffer through the generated wrapper: 64 KiB transfer-src
// buffer with a host-visible sequential-write allocation (AUTO memory).
extern "C" int vmafull_buffer_create(int handle, int64_t size) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0 || s->allocator == 0) return -1;
  VkBufferCreateInfo buffer_info = { VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO };
  buffer_info.size = (VkDeviceSize)size;
  buffer_info.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
  buffer_info.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
  VmaAllocationCreateInfo alloc_info = {};
  alloc_info.usage = VMA_MEMORY_USAGE_AUTO;
  alloc_info.flags = VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT;
  VkBuffer buffer = VK_NULL_HANDLE;
  VmaAllocation allocation = VK_NULL_HANDLE;
  VkResult res = vmafull_wrap_vmaCreateBuffer(
      s->allocator, &buffer_info, &alloc_info, &buffer, &allocation, 0);
  if (res == VK_SUCCESS) {
    s->buffer = buffer;
    s->allocation = allocation;
    s->state = 3;
  }
  return (int)res;
}

// vmaGetAllocationInfo through the generated wrapper; the C-side struct is
// copied into the slot and read back via scalar getters.
extern "C" int vmafull_allocation_info(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0 || s->allocation == 0) return -1;
  VmaAllocationInfo info = {};
  vmafull_wrap_vmaGetAllocationInfo(s->allocator, s->allocation, &info);
  s->info = info;
  return 0;
}

extern "C" int64_t vmafull_buffer_handle(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0) return 0;
  return (int64_t)s->buffer;
}

extern "C" int64_t vmafull_allocation_handle(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0) return 0;
  return (int64_t)(intptr_t)s->allocation;
}

extern "C" int64_t vmafull_info_size(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0) return 0;
  return (int64_t)s->info.size;
}

extern "C" int64_t vmafull_info_offset(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0) return 0;
  return (int64_t)s->info.offset;
}

extern "C" int vmafull_info_memory_type(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0) return -1;
  return (int)s->info.memoryType;
}

extern "C" int64_t vmafull_info_device_memory(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0) return 0;
  return (int64_t)s->info.deviceMemory;
}

// vmaDestroyBuffer through the generated wrapper.
extern "C" int vmafull_buffer_destroy(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0) return -1;
  vmafull_wrap_vmaDestroyBuffer(s->allocator, s->buffer, s->allocation);
  s->buffer = VK_NULL_HANDLE;
  s->allocation = VK_NULL_HANDLE;
  s->state = 2;
  return 0;
}

// Functional probe for the config-gated win32 function on a real
// allocation: with the win32 handle fn not enabled at device creation VMA
// returns VK_ERROR_FEATURE_NOT_PRESENT (documented); the probe accepts
// that or VK_SUCCESS.
extern "C" int vmafull_win32_handle_probe(int handle) {
  VmaFullSlot* s = vmafull_slot(handle);
  if (s == 0 || s->allocation == 0) return -1;
  HANDLE out_handle = 0;
  VkResult res =
      vmafull_wrap_vmaGetMemoryWin32Handle(s->allocator, s->allocation, 0, &out_handle);
  return (int)res;
}

// Null-argument error path: every check must match its expected guarded
// return; the returned bitmask is 0 when all guards behaved.
extern "C" int vmafull_error_probe(void) {
  int mask = 0;
  if (vmafull_wrap_vmaCreateAllocator(0, 0) != VK_ERROR_INITIALIZATION_FAILED) mask |= 1;
  if (vmafull_wrap_vmaCreateBuffer(0, 0, 0, 0, 0, 0) != VK_ERROR_INITIALIZATION_FAILED) mask |= 2;
  if (vmafull_wrap_vmaFindMemoryTypeIndex(0, 0, 0, 0) != VK_ERROR_INITIALIZATION_FAILED) mask |= 4;
  if (vmafull_wrap_vmaMapMemory(0, 0, 0) != VK_ERROR_INITIALIZATION_FAILED) mask |= 8;
  if (vmafull_wrap_vmaIsVirtualBlockEmpty(0) != VK_FALSE) mask |= 16;
  if (vmafull_wrap_vmaImportVulkanFunctionsFromVolk(0, 0) != VK_ERROR_INITIALIZATION_FAILED) mask |= 32;
  if (vmafull_wrap_vmaGetMemoryWin32Handle(0, 0, 0, 0) != VK_ERROR_INITIALIZATION_FAILED) mask |= 64;
  vmafull_wrap_vmaDestroyBuffer(0, 0, 0);
  vmafull_wrap_vmaGetAllocationInfo(0, 0, 0);
  vmafull_wrap_vmaFreeMemory(0, 0);
  return mask;
}
