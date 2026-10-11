// XIOM -- GENERATED typed wrappers: allocation family (20 functions).
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

module xiom.vma.full_allocation

extern "C" {
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
}

/// vmaAllocateMemory -> Int32
pub fn vma_full_allocate_memory(allocator: Int, pVkMemoryRequirements: Int, pCreateInfo: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaAllocateMemory(allocator, pVkMemoryRequirements, pCreateInfo, pAllocation, pAllocationInfo) };
}

/// vmaAllocateMemoryPages -> Int32
pub fn vma_full_allocate_memory_pages(allocator: Int, pVkMemoryRequirements: Int, pCreateInfo: Int, allocationCount: Int, pAllocations: Int, pAllocationInfo: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaAllocateMemoryPages(allocator, pVkMemoryRequirements, pCreateInfo, allocationCount, pAllocations, pAllocationInfo) };
}

/// vmaAllocateMemoryForBuffer -> Int32
pub fn vma_full_allocate_memory_for_buffer(allocator: Int, buffer: Int64, pCreateInfo: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaAllocateMemoryForBuffer(allocator, buffer, pCreateInfo, pAllocation, pAllocationInfo) };
}

/// vmaAllocateMemoryForImage -> Int32
pub fn vma_full_allocate_memory_for_image(allocator: Int, image: Int64, pCreateInfo: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaAllocateMemoryForImage(allocator, image, pCreateInfo, pAllocation, pAllocationInfo) };
}

/// vmaFreeMemory -> Unit
pub fn vma_full_free_memory(allocator: Int, allocation: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaFreeMemory(allocator, allocation); }
}

/// vmaFreeMemoryPages -> Unit
pub fn vma_full_free_memory_pages(allocator: Int, allocationCount: Int, pAllocations: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaFreeMemoryPages(allocator, allocationCount, pAllocations); }
}

/// vmaGetAllocationInfo -> Unit
pub fn vma_full_get_allocation_info(allocator: Int, allocation: Int, pAllocationInfo: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaGetAllocationInfo(allocator, allocation, pAllocationInfo); }
}

/// vmaGetAllocationInfo2 -> Unit
pub fn vma_full_get_allocation_info2(allocator: Int, allocation: Int, pAllocationInfo: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaGetAllocationInfo2(allocator, allocation, pAllocationInfo); }
}

/// vmaSetAllocationUserData -> Unit
pub fn vma_full_set_allocation_user_data(allocator: Int, allocation: Int, pUserData: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaSetAllocationUserData(allocator, allocation, pUserData); }
}

/// vmaSetAllocationName -> Unit
pub fn vma_full_set_allocation_name(allocator: Int, allocation: Int, pName: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaSetAllocationName(allocator, allocation, pName); }
}

/// vmaGetAllocationMemoryProperties -> Unit
pub fn vma_full_get_allocation_memory_properties(allocator: Int, allocation: Int, pFlags: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaGetAllocationMemoryProperties(allocator, allocation, pFlags); }
}

/// vmaGetMemoryWin32Handle -> Int32
pub fn vma_full_get_memory_win32_handle(allocator: Int, allocation: Int, hTargetProcess: Int, pHandle: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaGetMemoryWin32Handle(allocator, allocation, hTargetProcess, pHandle) };
}

/// vmaMapMemory -> Int32
pub fn vma_full_map_memory(allocator: Int, allocation: Int, ppData: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaMapMemory(allocator, allocation, ppData) };
}

/// vmaUnmapMemory -> Unit
pub fn vma_full_unmap_memory(allocator: Int, allocation: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaUnmapMemory(allocator, allocation); }
}

/// vmaFlushAllocation -> Int32
pub fn vma_full_flush_allocation(allocator: Int, allocation: Int, offset: Int64, size: Int64) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaFlushAllocation(allocator, allocation, offset, size) };
}

/// vmaInvalidateAllocation -> Int32
pub fn vma_full_invalidate_allocation(allocator: Int, allocation: Int, offset: Int64, size: Int64) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaInvalidateAllocation(allocator, allocation, offset, size) };
}

/// vmaFlushAllocations -> Int32
pub fn vma_full_flush_allocations(allocator: Int, allocationCount: Int32, allocations: Int, offsets: Int, sizes: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaFlushAllocations(allocator, allocationCount, allocations, offsets, sizes) };
}

/// vmaInvalidateAllocations -> Int32
pub fn vma_full_invalidate_allocations(allocator: Int, allocationCount: Int32, allocations: Int, offsets: Int, sizes: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaInvalidateAllocations(allocator, allocationCount, allocations, offsets, sizes) };
}

/// vmaCopyMemoryToAllocation -> Int32
pub fn vma_full_copy_memory_to_allocation(allocator: Int, pSrcHostPointer: Int, dstAllocation: Int, dstAllocationLocalOffset: Int64, size: Int64) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaCopyMemoryToAllocation(allocator, pSrcHostPointer, dstAllocation, dstAllocationLocalOffset, size) };
}

/// vmaCopyAllocationToMemory -> Int32
pub fn vma_full_copy_allocation_to_memory(allocator: Int, srcAllocation: Int, srcAllocationLocalOffset: Int64, pDstHostPointer: Int, size: Int64) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaCopyAllocationToMemory(allocator, srcAllocation, srcAllocationLocalOffset, pDstHostPointer, size) };
}

