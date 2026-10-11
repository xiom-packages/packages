// XIOM -- GENERATED typed wrappers: buffer family (5 functions).
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

module xiom.vma.full_buffer

extern "C" {
  fn vmafull_wrap_vmaCreateBuffer(allocator: Int, pBufferCreateInfo: Int, pAllocationCreateInfo: Int, pBuffer: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmafull_wrap_vmaCreateBufferWithAlignment(allocator: Int, pBufferCreateInfo: Int, pAllocationCreateInfo: Int, minAlignment: Int64, pBuffer: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmafull_wrap_vmaCreateAliasingBuffer(allocator: Int, allocation: Int, pBufferCreateInfo: Int, pBuffer: Int) -> Int32;
  fn vmafull_wrap_vmaCreateAliasingBuffer2(allocator: Int, allocation: Int, allocationLocalOffset: Int64, pBufferCreateInfo: Int, pBuffer: Int) -> Int32;
  fn vmafull_wrap_vmaDestroyBuffer(allocator: Int, buffer: Int64, allocation: Int);
}

/// vmaCreateBuffer -> Int32
pub fn vma_full_create_buffer(allocator: Int, pBufferCreateInfo: Int, pAllocationCreateInfo: Int, pBuffer: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaCreateBuffer(allocator, pBufferCreateInfo, pAllocationCreateInfo, pBuffer, pAllocation, pAllocationInfo) };
}

/// vmaCreateBufferWithAlignment -> Int32
pub fn vma_full_create_buffer_with_alignment(allocator: Int, pBufferCreateInfo: Int, pAllocationCreateInfo: Int, minAlignment: Int64, pBuffer: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaCreateBufferWithAlignment(allocator, pBufferCreateInfo, pAllocationCreateInfo, minAlignment, pBuffer, pAllocation, pAllocationInfo) };
}

/// vmaCreateAliasingBuffer -> Int32
pub fn vma_full_create_aliasing_buffer(allocator: Int, allocation: Int, pBufferCreateInfo: Int, pBuffer: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaCreateAliasingBuffer(allocator, allocation, pBufferCreateInfo, pBuffer) };
}

/// vmaCreateAliasingBuffer2 -> Int32
pub fn vma_full_create_aliasing_buffer2(allocator: Int, allocation: Int, allocationLocalOffset: Int64, pBufferCreateInfo: Int, pBuffer: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaCreateAliasingBuffer2(allocator, allocation, allocationLocalOffset, pBufferCreateInfo, pBuffer) };
}

/// vmaDestroyBuffer -> Unit
pub fn vma_full_destroy_buffer(allocator: Int, buffer: Int64, allocation: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaDestroyBuffer(allocator, buffer, allocation); }
}

