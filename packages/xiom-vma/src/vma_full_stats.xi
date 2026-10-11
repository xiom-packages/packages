// XIOM -- GENERATED typed wrappers: stats family (4 functions).
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

module xiom.vma.full_stats

extern "C" {
  fn vmafull_wrap_vmaCalculateStatistics(allocator: Int, pStats: Int);
  fn vmafull_wrap_vmaGetHeapBudgets(allocator: Int, pBudgets: Int);
  fn vmafull_wrap_vmaBuildStatsString(allocator: Int, ppStatsString: Int, detailedMap: Int32);
  fn vmafull_wrap_vmaFreeStatsString(allocator: Int, pStatsString: Int);
}

/// vmaCalculateStatistics -> Unit
pub fn vma_full_calculate_statistics(allocator: Int, pStats: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaCalculateStatistics(allocator, pStats); }
}

/// vmaGetHeapBudgets -> Unit
pub fn vma_full_get_heap_budgets(allocator: Int, pBudgets: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaGetHeapBudgets(allocator, pBudgets); }
}

/// vmaBuildStatsString -> Unit
pub fn vma_full_build_stats_string(allocator: Int, ppStatsString: Int, detailedMap: Int32)
  requires: true
{
  unsafe { vmafull_wrap_vmaBuildStatsString(allocator, ppStatsString, detailedMap); }
}

/// vmaFreeStatsString -> Unit
pub fn vma_full_free_stats_string(allocator: Int, pStatsString: Int)
  requires: true
{
  unsafe { vmafull_wrap_vmaFreeStatsString(allocator, pStatsString); }
}

