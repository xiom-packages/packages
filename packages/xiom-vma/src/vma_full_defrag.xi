// XIOM -- GENERATED typed wrappers: defrag family (5 functions).
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

module xiom.vma.full_defrag

extern "C" {
  fn vmafull_wrap_vmaCheckCorruption(allocator: Int, memoryTypeBits: Int32) -> Int32;
  fn vmafull_wrap_vmaBeginDefragmentation(allocator: Int, pInfo: Int, pContext: Int) -> Int32;
  fn vmafull_wrap_vmaEndDefragmentation(allocator: Int, context: Int, pStats: Int);
  fn vmafull_wrap_vmaBeginDefragmentationPass(allocator: Int, context: Int, pPassInfo: Int) -> Int32;
  fn vmafull_wrap_vmaEndDefragmentationPass(allocator: Int, context: Int, pPassInfo: Int) -> Int32;
}

/// vmaCheckCorruption -> Int32
pub fn vma_full_check_corruption(allocator: Int, memoryTypeBits: Int32) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaCheckCorruption(allocator, memoryTypeBits) };
}

/// vmaBeginDefragmentation -> Int32
pub fn vma_full_begin_defragmentation(allocator: Int, pInfo: Int, pContext: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaBeginDefragmentation(allocator, pInfo, pContext) };
}

/// vmaEndDefragmentation -> Unit
pub fn vma_full_end_defragmentation(allocator: Int, context: Int, pStats: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaEndDefragmentation(allocator, context, pStats); }
}

/// vmaBeginDefragmentationPass -> Int32
pub fn vma_full_begin_defragmentation_pass(allocator: Int, context: Int, pPassInfo: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaBeginDefragmentationPass(allocator, context, pPassInfo) };
}

/// vmaEndDefragmentationPass -> Int32
pub fn vma_full_end_defragmentation_pass(allocator: Int, context: Int, pPassInfo: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaEndDefragmentationPass(allocator, context, pPassInfo) };
}

