// XIOM -- GENERATED typed wrappers: pool family (7 functions).
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

module xiom.vma.full_pool

extern "C" {
  fn vmafull_wrap_vmaCreatePool(allocator: Int, pCreateInfo: Int, pPool: Int) -> Int32;
  fn vmafull_wrap_vmaDestroyPool(allocator: Int, pool: Int);
  fn vmafull_wrap_vmaGetPoolStatistics(allocator: Int, pool: Int, pPoolStats: Int);
  fn vmafull_wrap_vmaCalculatePoolStatistics(allocator: Int, pool: Int, pPoolStats: Int);
  fn vmafull_wrap_vmaCheckPoolCorruption(allocator: Int, pool: Int) -> Int32;
  fn vmafull_wrap_vmaGetPoolName(allocator: Int, pool: Int, ppName: Int);
  fn vmafull_wrap_vmaSetPoolName(allocator: Int, pool: Int, pName: Int);
}

/// vmaCreatePool -> Int32
pub fn vma_full_create_pool(allocator: Int, pCreateInfo: Int, pPool: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaCreatePool(allocator, pCreateInfo, pPool) };
}

/// vmaDestroyPool -> Unit
pub fn vma_full_destroy_pool(allocator: Int, pool: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaDestroyPool(allocator, pool); }
}

/// vmaGetPoolStatistics -> Unit
pub fn vma_full_get_pool_statistics(allocator: Int, pool: Int, pPoolStats: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaGetPoolStatistics(allocator, pool, pPoolStats); }
}

/// vmaCalculatePoolStatistics -> Unit
pub fn vma_full_calculate_pool_statistics(allocator: Int, pool: Int, pPoolStats: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaCalculatePoolStatistics(allocator, pool, pPoolStats); }
}

/// vmaCheckPoolCorruption -> Int32
pub fn vma_full_check_pool_corruption(allocator: Int, pool: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaCheckPoolCorruption(allocator, pool) };
}

/// vmaGetPoolName -> Unit
pub fn vma_full_get_pool_name(allocator: Int, pool: Int, ppName: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaGetPoolName(allocator, pool, ppName); }
}

/// vmaSetPoolName -> Unit
pub fn vma_full_set_pool_name(allocator: Int, pool: Int, pName: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaSetPoolName(allocator, pool, pName); }
}

