// XIOM -- GENERATED typed wrappers: virtual family (12 functions).
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

module xiom.vma.full_virtual

extern "C" {
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
}

/// vmaCreateVirtualBlock -> Int32
pub fn vma_full_create_virtual_block(pCreateInfo: Int, pVirtualBlock: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaCreateVirtualBlock(pCreateInfo, pVirtualBlock) };
}

/// vmaDestroyVirtualBlock -> Unit
pub fn vma_full_destroy_virtual_block(virtualBlock: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaDestroyVirtualBlock(virtualBlock); }
}

/// vmaIsVirtualBlockEmpty -> Int32
pub fn vma_full_is_virtual_block_empty(virtualBlock: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaIsVirtualBlockEmpty(virtualBlock) };
}

/// vmaGetVirtualAllocationInfo -> Unit
pub fn vma_full_get_virtual_allocation_info(virtualBlock: Int, allocation: Int64, pVirtualAllocInfo: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaGetVirtualAllocationInfo(virtualBlock, allocation, pVirtualAllocInfo); }
}

/// vmaVirtualAllocate -> Int32
pub fn vma_full_virtual_allocate(virtualBlock: Int, pCreateInfo: Int, pAllocation: Int, pOffset: Int) -> Int32
  requires: true
{
  return unsafe { vmafull_wrap_vmaVirtualAllocate(virtualBlock, pCreateInfo, pAllocation, pOffset) };
}

/// vmaVirtualFree -> Unit
pub fn vma_full_virtual_free(virtualBlock: Int, allocation: Int64)
  requires: true
{
  unsafe { vmafull_wrap_vmaVirtualFree(virtualBlock, allocation); }
}

/// vmaClearVirtualBlock -> Unit
pub fn vma_full_clear_virtual_block(virtualBlock: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaClearVirtualBlock(virtualBlock); }
}

/// vmaSetVirtualAllocationUserData -> Unit
pub fn vma_full_set_virtual_allocation_user_data(virtualBlock: Int, allocation: Int64, pUserData: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaSetVirtualAllocationUserData(virtualBlock, allocation, pUserData); }
}

/// vmaGetVirtualBlockStatistics -> Unit
pub fn vma_full_get_virtual_block_statistics(virtualBlock: Int, pStats: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaGetVirtualBlockStatistics(virtualBlock, pStats); }
}

/// vmaCalculateVirtualBlockStatistics -> Unit
pub fn vma_full_calculate_virtual_block_statistics(virtualBlock: Int, pStats: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaCalculateVirtualBlockStatistics(virtualBlock, pStats); }
}

/// vmaBuildVirtualBlockStatsString -> Unit
pub fn vma_full_build_virtual_block_stats_string(virtualBlock: Int, ppStatsString: Int, detailedMap: Int32)
  requires: true
{
  unsafe { vmafull_wrap_vmaBuildVirtualBlockStatsString(virtualBlock, ppStatsString, detailedMap); }
}

/// vmaFreeVirtualBlockStatsString -> Unit
pub fn vma_full_free_virtual_block_stats_string(virtualBlock: Int, pStatsString: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaFreeVirtualBlockStatsString(virtualBlock, pStatsString); }
}

