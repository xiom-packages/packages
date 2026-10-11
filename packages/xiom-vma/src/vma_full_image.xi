// XIOM -- GENERATED typed wrappers: image family (4 functions).
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

module xiom.vma.full_image

extern "C" {
  fn vmafull_wrap_vmaCreateImage(allocator: Int, pImageCreateInfo: Int, pAllocationCreateInfo: Int, pImage: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32;
  fn vmafull_wrap_vmaCreateAliasingImage(allocator: Int, allocation: Int, pImageCreateInfo: Int, pImage: Int) -> Int32;
  fn vmafull_wrap_vmaCreateAliasingImage2(allocator: Int, allocation: Int, allocationLocalOffset: Int64, pImageCreateInfo: Int, pImage: Int) -> Int32;
  fn vmafull_wrap_vmaDestroyImage(allocator: Int, image: Int64, allocation: Int);
}

/// vmaCreateImage -> Int32
pub fn vma_full_create_image(allocator: Int, pImageCreateInfo: Int, pAllocationCreateInfo: Int, pImage: Int, pAllocation: Int, pAllocationInfo: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaCreateImage(allocator, pImageCreateInfo, pAllocationCreateInfo, pImage, pAllocation, pAllocationInfo) };
}

/// vmaCreateAliasingImage -> Int32
pub fn vma_full_create_aliasing_image(allocator: Int, allocation: Int, pImageCreateInfo: Int, pImage: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaCreateAliasingImage(allocator, allocation, pImageCreateInfo, pImage) };
}

/// vmaCreateAliasingImage2 -> Int32
pub fn vma_full_create_aliasing_image2(allocator: Int, allocation: Int, allocationLocalOffset: Int64, pImageCreateInfo: Int, pImage: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaCreateAliasingImage2(allocator, allocation, allocationLocalOffset, pImageCreateInfo, pImage) };
}

/// vmaDestroyImage -> Unit
pub fn vma_full_destroy_image(allocator: Int, image: Int64, allocation: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaDestroyImage(allocator, image, allocation); }
}

