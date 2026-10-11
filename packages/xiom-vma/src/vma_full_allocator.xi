// XIOM -- GENERATED typed wrappers: allocator family (8 functions).
// Generator: tools/gen_vma_full.py (do not edit by hand).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Thin typed pass-throughs over the bridge wrappers (same mapping,
// same names as the C API).  VMA_NOT_NULL pointer args are guarded in
// the bridge (null -> VK_ERROR_INITIALIZATION_FAILED).  The extern
// block is module-local: v0.64.3 resolves `use` only in the entry
// module, so family modules are self-contained (duplicate extern
// declarations of the same C symbol are legal).

module xiom.vma.full_allocator

extern "C" {
  fn vmafull_wrap_vmaImportVulkanFunctionsFromVolk(pAllocatorCreateInfo: Int, pDstVulkanFunctions: Int) -> Int32;
  fn vmafull_wrap_vmaCreateAllocator(pCreateInfo: Int, pAllocator: Int) -> Int32;
  fn vmafull_wrap_vmaDestroyAllocator(allocator: Int);
  fn vmafull_wrap_vmaGetAllocatorInfo(allocator: Int, pAllocatorInfo: Int);
  fn vmafull_wrap_vmaGetPhysicalDeviceProperties(allocator: Int, ppPhysicalDeviceProperties: Int);
  fn vmafull_wrap_vmaGetMemoryProperties(allocator: Int, ppPhysicalDeviceMemoryProperties: Int);
  fn vmafull_wrap_vmaGetMemoryTypeProperties(allocator: Int, memoryTypeIndex: Int32, pFlags: Int);
  fn vmafull_wrap_vmaSetCurrentFrameIndex(allocator: Int, frameIndex: Int32);
}

/// vmaImportVulkanFunctionsFromVolk -> Int32
pub fn vma_full_import_vulkan_functions_from_volk(pAllocatorCreateInfo: Int, pDstVulkanFunctions: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaImportVulkanFunctionsFromVolk(pAllocatorCreateInfo, pDstVulkanFunctions) };
}

/// vmaCreateAllocator -> Int32
pub fn vma_full_create_allocator(pCreateInfo: Int, pAllocator: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaCreateAllocator(pCreateInfo, pAllocator) };
}

/// vmaDestroyAllocator -> Unit
pub fn vma_full_destroy_allocator(allocator: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaDestroyAllocator(allocator); }
}

/// vmaGetAllocatorInfo -> Unit
pub fn vma_full_get_allocator_info(allocator: Int, pAllocatorInfo: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaGetAllocatorInfo(allocator, pAllocatorInfo); }
}

/// vmaGetPhysicalDeviceProperties -> Unit
pub fn vma_full_get_physical_device_properties(allocator: Int, ppPhysicalDeviceProperties: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaGetPhysicalDeviceProperties(allocator, ppPhysicalDeviceProperties); }
}

/// vmaGetMemoryProperties -> Unit
pub fn vma_full_get_memory_properties(allocator: Int, ppPhysicalDeviceMemoryProperties: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaGetMemoryProperties(allocator, ppPhysicalDeviceMemoryProperties); }
}

/// vmaGetMemoryTypeProperties -> Unit
pub fn vma_full_get_memory_type_properties(allocator: Int, memoryTypeIndex: Int32, pFlags: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaGetMemoryTypeProperties(allocator, memoryTypeIndex, pFlags); }
}

/// vmaSetCurrentFrameIndex -> Unit
pub fn vma_full_set_current_frame_index(allocator: Int, frameIndex: Int32)
  requires: true
{
  unsafe { vmafull_wrap_vmaSetCurrentFrameIndex(allocator, frameIndex); }
}

