// XIOM -- GENERATED typed wrappers: binding family (4 functions).
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

module xiom.vma.full_binding

extern "C" {
  fn vmafull_wrap_vmaBindBufferMemory(allocator: Int, allocation: Int, buffer: Int64) -> Int32;
  fn vmafull_wrap_vmaBindBufferMemory2(allocator: Int, allocation: Int, allocationLocalOffset: Int64, buffer: Int64, pNext: Int) -> Int32;
  fn vmafull_wrap_vmaBindImageMemory(allocator: Int, allocation: Int, image: Int64) -> Int32;
  fn vmafull_wrap_vmaBindImageMemory2(allocator: Int, allocation: Int, allocationLocalOffset: Int64, image: Int64, pNext: Int) -> Int32;
}

/// vmaBindBufferMemory -> Int32
pub fn vma_full_bind_buffer_memory(allocator: Int, allocation: Int, buffer: Int64) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaBindBufferMemory(allocator, allocation, buffer) };
}

/// vmaBindBufferMemory2 -> Int32
pub fn vma_full_bind_buffer_memory2(allocator: Int, allocation: Int, allocationLocalOffset: Int64, buffer: Int64, pNext: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaBindBufferMemory2(allocator, allocation, allocationLocalOffset, buffer, pNext) };
}

/// vmaBindImageMemory -> Int32
pub fn vma_full_bind_image_memory(allocator: Int, allocation: Int, image: Int64) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaBindImageMemory(allocator, allocation, image) };
}

/// vmaBindImageMemory2 -> Int32
pub fn vma_full_bind_image_memory2(allocator: Int, allocation: Int, allocationLocalOffset: Int64, image: Int64, pNext: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaBindImageMemory2(allocator, allocation, allocationLocalOffset, image, pNext) };
}

