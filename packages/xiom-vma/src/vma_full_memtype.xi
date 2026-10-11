// XIOM -- GENERATED typed wrappers: memtype family (3 functions).
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

module xiom.vma.full_memtype

extern "C" {
  fn vmafull_wrap_vmaFindMemoryTypeIndex(allocator: Int, memoryTypeBits: Int32, pAllocationCreateInfo: Int, pMemoryTypeIndex: Int) -> Int32;
  fn vmafull_wrap_vmaFindMemoryTypeIndexForBufferInfo(allocator: Int, pBufferCreateInfo: Int, pAllocationCreateInfo: Int, pMemoryTypeIndex: Int) -> Int32;
  fn vmafull_wrap_vmaFindMemoryTypeIndexForImageInfo(allocator: Int, pImageCreateInfo: Int, pAllocationCreateInfo: Int, pMemoryTypeIndex: Int) -> Int32;
}

/// vmaFindMemoryTypeIndex -> Int32
pub fn vma_full_find_memory_type_index(allocator: Int, memoryTypeBits: Int32, pAllocationCreateInfo: Int, pMemoryTypeIndex: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaFindMemoryTypeIndex(allocator, memoryTypeBits, pAllocationCreateInfo, pMemoryTypeIndex) };
}

/// vmaFindMemoryTypeIndexForBufferInfo -> Int32
pub fn vma_full_find_memory_type_index_for_buffer_info(allocator: Int, pBufferCreateInfo: Int, pAllocationCreateInfo: Int, pMemoryTypeIndex: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaFindMemoryTypeIndexForBufferInfo(allocator, pBufferCreateInfo, pAllocationCreateInfo, pMemoryTypeIndex) };
}

/// vmaFindMemoryTypeIndexForImageInfo -> Int32
pub fn vma_full_find_memory_type_index_for_image_info(allocator: Int, pImageCreateInfo: Int, pAllocationCreateInfo: Int, pMemoryTypeIndex: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaFindMemoryTypeIndexForImageInfo(allocator, pImageCreateInfo, pAllocationCreateInfo, pMemoryTypeIndex) };
}

