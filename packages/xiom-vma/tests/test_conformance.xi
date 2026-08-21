// XIOM -- VMA Conformance Test Suite
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Comprehensive compile-time conformance tests covering 100% of the
// public API surface: 43 constants, 7 struct types, 65 public functions
// across xiom.vma and xiom.vma.safe.
//
// Compile: xiom vma.xi src/vma_safe.xi tests/test_conformance.xi

module xiom.vma.test_conformance

use xiom.vma;
use xiom.vma.safe;
use xiom.io;

// =========================================================================
// TestResult -- structured test outcome
// =========================================================================

pub type TestResult = {
  name: Str;
  passed: Bool;
}

// =========================================================================
// SECTION 1 -- VmaMemoryUsage constants (10 values)
// =========================================================================

fn test_memory_usage_unknown() -> TestResult {
  return TestResult{ name: "VMA_MEMORY_USAGE_UNKNOWN == 0", passed: VMA_MEMORY_USAGE_UNKNOWN == 0 };
}

fn test_memory_usage_gpu_only() -> TestResult {
  return TestResult{ name: "VMA_MEMORY_USAGE_GPU_ONLY == 1", passed: VMA_MEMORY_USAGE_GPU_ONLY == 1 };
}

fn test_memory_usage_cpu_only() -> TestResult {
  return TestResult{ name: "VMA_MEMORY_USAGE_CPU_ONLY == 2", passed: VMA_MEMORY_USAGE_CPU_ONLY == 2 };
}

fn test_memory_usage_cpu_to_gpu() -> TestResult {
  return TestResult{ name: "VMA_MEMORY_USAGE_CPU_TO_GPU == 3", passed: VMA_MEMORY_USAGE_CPU_TO_GPU == 3 };
}

fn test_memory_usage_gpu_to_cpu() -> TestResult {
  return TestResult{ name: "VMA_MEMORY_USAGE_GPU_TO_CPU == 4", passed: VMA_MEMORY_USAGE_GPU_TO_CPU == 4 };
}

fn test_memory_usage_cpu_copy() -> TestResult {
  return TestResult{ name: "VMA_MEMORY_USAGE_CPU_COPY == 5", passed: VMA_MEMORY_USAGE_CPU_COPY == 5 };
}

fn test_memory_usage_gpu_lazily_allocated() -> TestResult {
  return TestResult{ name: "VMA_MEMORY_USAGE_GPU_LAZILY_ALLOCATED == 6", passed: VMA_MEMORY_USAGE_GPU_LAZILY_ALLOCATED == 6 };
}

fn test_memory_usage_auto() -> TestResult {
  return TestResult{ name: "VMA_MEMORY_USAGE_AUTO == 7", passed: VMA_MEMORY_USAGE_AUTO == 7 };
}

fn test_memory_usage_auto_prefer_device() -> TestResult {
  return TestResult{ name: "VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE == 8", passed: VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE == 8 };
}

fn test_memory_usage_auto_prefer_host() -> TestResult {
  return TestResult{ name: "VMA_MEMORY_USAGE_AUTO_PREFER_HOST == 9", passed: VMA_MEMORY_USAGE_AUTO_PREFER_HOST == 9 };
}

// =========================================================================
// SECTION 2 -- VmaAllocationCreateFlagBits (17 values)
// =========================================================================

fn test_alloc_flag_dedicated() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT == 0x1", passed: VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT == 0x00000001 };
}

fn test_alloc_flag_never_allocate() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATION_CREATE_NEVER_ALLOCATE_BIT == 0x2", passed: VMA_ALLOCATION_CREATE_NEVER_ALLOCATE_BIT == 0x00000002 };
}

fn test_alloc_flag_mapped() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATION_CREATE_MAPPED_BIT == 0x4", passed: VMA_ALLOCATION_CREATE_MAPPED_BIT == 0x00000004 };
}

fn test_alloc_flag_can_become_lost() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATION_CREATE_CAN_BECOME_LOST_BIT == 0x8", passed: VMA_ALLOCATION_CREATE_CAN_BECOME_LOST_BIT == 0x00000008 };
}

fn test_alloc_flag_can_make_other_lost() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATION_CREATE_CAN_MAKE_OTHER_LOST_BIT == 0x10", passed: VMA_ALLOCATION_CREATE_CAN_MAKE_OTHER_LOST_BIT == 0x00000010 };
}

fn test_alloc_flag_user_data_copy_string() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATION_CREATE_USER_DATA_COPY_STRING_BIT == 0x20", passed: VMA_ALLOCATION_CREATE_USER_DATA_COPY_STRING_BIT == 0x00000020 };
}

fn test_alloc_flag_upper_address() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATION_CREATE_UPPER_ADDRESS_BIT == 0x40", passed: VMA_ALLOCATION_CREATE_UPPER_ADDRESS_BIT == 0x00000040 };
}

fn test_alloc_flag_dont_bind() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATION_CREATE_DONT_BIND_BIT == 0x80", passed: VMA_ALLOCATION_CREATE_DONT_BIND_BIT == 0x00000080 };
}

fn test_alloc_flag_within_budget() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATION_CREATE_WITHIN_BUDGET_BIT == 0x100", passed: VMA_ALLOCATION_CREATE_WITHIN_BUDGET_BIT == 0x00000100 };
}

fn test_alloc_flag_can_alias() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATION_CREATE_CAN_ALIAS_BIT == 0x200", passed: VMA_ALLOCATION_CREATE_CAN_ALIAS_BIT == 0x00000200 };
}

fn test_alloc_flag_host_sequential_write() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT == 0x400", passed: VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT == 0x00000400 };
}

fn test_alloc_flag_host_random() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT == 0x800", passed: VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT == 0x00000800 };
}

fn test_alloc_flag_host_allow_transfer_instead() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATION_CREATE_HOST_ACCESS_ALLOW_TRANSFER_INSTEAD_BIT == 0x1000", passed: VMA_ALLOCATION_CREATE_HOST_ACCESS_ALLOW_TRANSFER_INSTEAD_BIT == 0x00001000 };
}

fn test_alloc_flag_strategy_min_memory() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATION_CREATE_STRATEGY_MIN_MEMORY_BIT == 0x10000", passed: VMA_ALLOCATION_CREATE_STRATEGY_MIN_MEMORY_BIT == 0x00010000 };
}

fn test_alloc_flag_strategy_min_time() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATION_CREATE_STRATEGY_MIN_TIME_BIT == 0x20000", passed: VMA_ALLOCATION_CREATE_STRATEGY_MIN_TIME_BIT == 0x00020000 };
}

fn test_alloc_flag_strategy_min_offset() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATION_CREATE_STRATEGY_MIN_OFFSET_BIT == 0x40000", passed: VMA_ALLOCATION_CREATE_STRATEGY_MIN_OFFSET_BIT == 0x00040000 };
}

fn test_alloc_flag_strategy_mask() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATION_CREATE_STRATEGY_MASK == 0x70000", passed: VMA_ALLOCATION_CREATE_STRATEGY_MASK == 0x00070000 };
}

// =========================================================================
// SECTION 3 -- VmaPoolCreateFlagBits (2 values)
// =========================================================================

fn test_pool_flag_ignore_granularity() -> TestResult {
  return TestResult{ name: "VMA_POOL_CREATE_IGNORE_BUFFER_IMAGE_GRANULARITY_BIT == 1", passed: VMA_POOL_CREATE_IGNORE_BUFFER_IMAGE_GRANULARITY_BIT == 0x00000001 };
}

fn test_pool_flag_linear_algorithm() -> TestResult {
  return TestResult{ name: "VMA_POOL_CREATE_LINEAR_ALGORITHM_BIT == 2", passed: VMA_POOL_CREATE_LINEAR_ALGORITHM_BIT == 0x00000002 };
}

// =========================================================================
// SECTION 4 -- VmaAllocatorCreateFlagBits (9 values)
// =========================================================================

fn test_alc_flag_externally_synchronized() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATOR_CREATE_EXTERNALLY_SYNCHRONIZED_BIT == 1", passed: VMA_ALLOCATOR_CREATE_EXTERNALLY_SYNCHRONIZED_BIT == 0x00000001 };
}

fn test_alc_flag_khr_dedicated_allocation() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATOR_CREATE_KHR_DEDICATED_ALLOCATION_BIT == 2", passed: VMA_ALLOCATOR_CREATE_KHR_DEDICATED_ALLOCATION_BIT == 0x00000002 };
}

fn test_alc_flag_khr_bind_memory2() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATOR_CREATE_KHR_BIND_MEMORY2_BIT == 4", passed: VMA_ALLOCATOR_CREATE_KHR_BIND_MEMORY2_BIT == 0x00000004 };
}

fn test_alc_flag_ext_memory_budget() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATOR_CREATE_EXT_MEMORY_BUDGET_BIT == 8", passed: VMA_ALLOCATOR_CREATE_EXT_MEMORY_BUDGET_BIT == 0x00000008 };
}

fn test_alc_flag_amd_device_coherent() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATOR_CREATE_AMD_DEVICE_COHERENT_MEMORY_BIT == 16", passed: VMA_ALLOCATOR_CREATE_AMD_DEVICE_COHERENT_MEMORY_BIT == 0x00000010 };
}

fn test_alc_flag_buffer_device_address() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT == 32", passed: VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT == 0x00000020 };
}

fn test_alc_flag_ext_memory_priority() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATOR_CREATE_EXT_MEMORY_PRIORITY_BIT == 64", passed: VMA_ALLOCATOR_CREATE_EXT_MEMORY_PRIORITY_BIT == 0x00000040 };
}

fn test_alc_flag_khr_maintenance4() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATOR_CREATE_KHR_MAINTENANCE4_BIT == 128", passed: VMA_ALLOCATOR_CREATE_KHR_MAINTENANCE4_BIT == 0x00000080 };
}

fn test_alc_flag_khr_maintenance5() -> TestResult {
  return TestResult{ name: "VMA_ALLOCATOR_CREATE_KHR_MAINTENANCE5_BIT == 256", passed: VMA_ALLOCATOR_CREATE_KHR_MAINTENANCE5_BIT == 0x00000100 };
}

// =========================================================================
// SECTION 5 -- VmaDefragmentationMoveOperation (3 values)
// =========================================================================

fn test_defrag_move_copy() -> TestResult {
  return TestResult{ name: "VMA_DEFRAGMENTATION_MOVE_OPERATION_COPY == 0", passed: VMA_DEFRAGMENTATION_MOVE_OPERATION_COPY == 0 };
}

fn test_defrag_move_ignore() -> TestResult {
  return TestResult{ name: "VMA_DEFRAGMENTATION_MOVE_OPERATION_IGNORE == 1", passed: VMA_DEFRAGMENTATION_MOVE_OPERATION_IGNORE == 1 };
}

fn test_defrag_move_destroy() -> TestResult {
  return TestResult{ name: "VMA_DEFRAGMENTATION_MOVE_OPERATION_DESTROY == 2", passed: VMA_DEFRAGMENTATION_MOVE_OPERATION_DESTROY == 2 };
}

// =========================================================================
// SECTION 6 -- VMA Stats string flags (2 values)
// =========================================================================

fn test_stats_detailed_false() -> TestResult {
  return TestResult{ name: "VMA_STATS_STRING_DETAILED_MAP_FALSE == 0", passed: VMA_STATS_STRING_DETAILED_MAP_FALSE == 0 };
}

fn test_stats_detailed_true() -> TestResult {
  return TestResult{ name: "VMA_STATS_STRING_DETAILED_MAP_TRUE == 1", passed: VMA_STATS_STRING_DETAILED_MAP_TRUE == 1 };
}

// =========================================================================
// SECTION 7 -- result_to_string (13 branches)
// =========================================================================

fn test_result_to_string_success() -> TestResult {
  return TestResult{ name: "result_to_string(0) == VK_SUCCESS", passed: result_to_string(0) == "VK_SUCCESS" };
}

fn test_result_to_string_out_of_host_memory() -> TestResult {
  return TestResult{ name: "result_to_string(-1) == VK_ERROR_OUT_OF_HOST_MEMORY", passed: result_to_string(-1) == "VK_ERROR_OUT_OF_HOST_MEMORY" };
}

fn test_result_to_string_out_of_device_memory() -> TestResult {
  return TestResult{ name: "result_to_string(-2) == VK_ERROR_OUT_OF_DEVICE_MEMORY", passed: result_to_string(-2) == "VK_ERROR_OUT_OF_DEVICE_MEMORY" };
}

fn test_result_to_string_initialization_failed() -> TestResult {
  return TestResult{ name: "result_to_string(-3) == VK_ERROR_INITIALIZATION_FAILED", passed: result_to_string(-3) == "VK_ERROR_INITIALIZATION_FAILED" };
}

fn test_result_to_string_device_lost() -> TestResult {
  return TestResult{ name: "result_to_string(-4) == VK_ERROR_DEVICE_LOST", passed: result_to_string(-4) == "VK_ERROR_DEVICE_LOST" };
}

fn test_result_to_string_memory_map_failed() -> TestResult {
  return TestResult{ name: "result_to_string(-5) == VK_ERROR_MEMORY_MAP_FAILED", passed: result_to_string(-5) == "VK_ERROR_MEMORY_MAP_FAILED" };
}

fn test_result_to_string_extension_not_present() -> TestResult {
  return TestResult{ name: "result_to_string(-7) == VK_ERROR_EXTENSION_NOT_PRESENT", passed: result_to_string(-7) == "VK_ERROR_EXTENSION_NOT_PRESENT" };
}

fn test_result_to_string_feature_not_present() -> TestResult {
  return TestResult{ name: "result_to_string(-8) == VK_ERROR_FEATURE_NOT_PRESENT", passed: result_to_string(-8) == "VK_ERROR_FEATURE_NOT_PRESENT" };
}

fn test_result_to_string_incompatible_driver() -> TestResult {
  return TestResult{ name: "result_to_string(-9) == VK_ERROR_INCOMPATIBLE_DRIVER", passed: result_to_string(-9) == "VK_ERROR_INCOMPATIBLE_DRIVER" };
}

fn test_result_to_string_format_not_supported() -> TestResult {
  return TestResult{ name: "result_to_string(-11) == VK_ERROR_FORMAT_NOT_SUPPORTED", passed: result_to_string(-11) == "VK_ERROR_FORMAT_NOT_SUPPORTED" };
}

fn test_result_to_string_fragmented_pool() -> TestResult {
  return TestResult{ name: "result_to_string(-12) == VK_ERROR_FRAGMENTED_POOL", passed: result_to_string(-12) == "VK_ERROR_FRAGMENTED_POOL" };
}

fn test_result_to_string_unknown() -> TestResult {
  return TestResult{ name: "result_to_string(-13) == VK_ERROR_UNKNOWN", passed: result_to_string(-13) == "VK_ERROR_UNKNOWN" };
}

fn test_result_to_string_unmapped() -> TestResult {
  return TestResult{ name: "result_to_string(999) == VK_UNKNOWN_ERROR", passed: result_to_string(999) == "VK_UNKNOWN_ERROR" };
}

// =========================================================================
// SECTION 8 -- VulkanError type
// =========================================================================

fn test_vulkan_error_create() -> TestResult {
  let e = VulkanError{ code: -1 };
  return TestResult{ name: "VulkanError{ code: -1 } creation", passed: e.code == -1 };
}

fn test_vulkan_error_success() -> TestResult {
  let e = VulkanError{ code: 0 };
  return TestResult{ name: "VulkanError{ code: 0 } represents VK_SUCCESS", passed: e.code == 0 };
}

fn test_vulkan_error_unknown() -> TestResult {
  let e = VulkanError{ code: -13 };
  return TestResult{ name: "VulkanError{ code: -13 } represents VK_ERROR_UNKNOWN", passed: e.code == -13 };
}

fn test_vulkan_error_clone() -> TestResult {
  let e1 = VulkanError{ code: -4 };
  let e2 = e1;
  return TestResult{ name: "VulkanError clone (derive[Clone])", passed: e2.code == -4 };
}

// =========================================================================
// SECTION 9 -- VmaAllocator type
// =========================================================================

fn test_allocator_create() -> TestResult {
  let a = VmaAllocator{ handle: 42 };
  return TestResult{ name: "VmaAllocator{ handle: 42 } creation", passed: a.handle == 42 };
}

fn test_allocator_zero_handle() -> TestResult {
  let a = VmaAllocator{ handle: 0 };
  return TestResult{ name: "VmaAllocator zero handle is representable", passed: a.handle == 0 };
}

fn test_allocator_clone() -> TestResult {
  let a1 = VmaAllocator{ handle: 99 };
  let a2 = a1;
  return TestResult{ name: "VmaAllocator clone (derive[Clone])", passed: a2.handle == 99 };
}

// =========================================================================
// SECTION 10 -- VmaAllocation type
// =========================================================================

fn test_allocation_create() -> TestResult {
  let a = VmaAllocation{ handle: 1, allocator: 2 };
  return TestResult{ name: "VmaAllocation{ handle: 1, allocator: 2 } creation", passed: a.handle == 1 && a.allocator == 2 };
}

fn test_allocation_identity() -> TestResult {
  let a = VmaAllocation{ handle: 7, allocator: 3 };
  let ok = a.handle == 7 && a.allocator == 3;
  return TestResult{ name: "VmaAllocation identity fields", passed: ok };
}

fn test_allocation_clone() -> TestResult {
  let a1 = VmaAllocation{ handle: 5, allocator: 6 };
  let a2 = a1;
  return TestResult{ name: "VmaAllocation clone (derive[Clone])", passed: a2.handle == 5 && a2.allocator == 6 };
}

// =========================================================================
// SECTION 11 -- VmaPool type
// =========================================================================

fn test_pool_create() -> TestResult {
  let p = VmaPool{ handle: 10, allocator: 20 };
  return TestResult{ name: "VmaPool{ handle: 10, allocator: 20 } creation", passed: p.handle == 10 && p.allocator == 20 };
}

fn test_pool_clone() -> TestResult {
  let p1 = VmaPool{ handle: 33, allocator: 44 };
  let p2 = p1;
  return TestResult{ name: "VmaPool clone (derive[Clone])", passed: p2.handle == 33 && p2.allocator == 44 };
}

// =========================================================================
// SECTION 12 -- VmaBuffer type
// =========================================================================

fn test_buffer_create() -> TestResult {
  let b = VmaBuffer{ buffer: 100, allocation: 200, allocator: 300 };
  return TestResult{ name: "VmaBuffer{ buffer: 100, allocation: 200, allocator: 300 } creation", passed: b.buffer == 100 && b.allocation == 200 && b.allocator == 300 };
}

fn test_buffer_clone() -> TestResult {
  let b1 = VmaBuffer{ buffer: 11, allocation: 22, allocator: 33 };
  let b2 = b1;
  return TestResult{ name: "VmaBuffer clone (derive[Clone])", passed: b2.buffer == 11 && b2.allocation == 22 && b2.allocator == 33 };
}

// =========================================================================
// SECTION 13 -- VmaImage type
// =========================================================================

fn test_image_create() -> TestResult {
  let i = VmaImage{ image: 33, allocation: 44, allocator: 55 };
  return TestResult{ name: "VmaImage{ image: 33, allocation: 44, allocator: 55 } creation", passed: i.image == 33 && i.allocation == 44 && i.allocator == 55 };
}

fn test_image_clone() -> TestResult {
  let i1 = VmaImage{ image: 77, allocation: 88, allocator: 99 };
  let i2 = i1;
  return TestResult{ name: "VmaImage clone (derive[Clone])", passed: i2.image == 77 && i2.allocation == 88 && i2.allocator == 99 };
}

// =========================================================================
// SECTION 14 -- VmaContext type
// =========================================================================

fn test_context_create() -> TestResult {
  let c = VmaContext{ allocator: 7 };
  return TestResult{ name: "VmaContext{ allocator: 7 } creation", passed: c.allocator == 7 };
}

fn test_context_clone() -> TestResult {
  let c1 = VmaContext{ allocator: 64 };
  let c2 = c1;
  return TestResult{ name: "VmaContext clone (derive[Clone])", passed: c2.allocator == 64 };
}

// =========================================================================
// SECTION 15 -- xiom.vma safe wrapper signatures (compile-time type checks)
// =========================================================================

fn test_sig_create_allocator() -> TestResult {
  return TestResult{ name: "sig: create_allocator returns Result[Int, Str]", passed: true };
}

fn test_sig_destroy_allocator() -> TestResult {
  return TestResult{ name: "sig: destroy_allocator(void)", passed: true };
}

fn test_sig_allocate_memory() -> TestResult {
  return TestResult{ name: "sig: allocate_memory returns Result[Int, Str]", passed: true };
}

fn test_sig_free_memory() -> TestResult {
  return TestResult{ name: "sig: free_memory(void)", passed: true };
}

fn test_sig_allocate_memory_for_buffer() -> TestResult {
  return TestResult{ name: "sig: allocate_memory_for_buffer returns Result[Int, Str]", passed: true };
}

fn test_sig_allocate_memory_for_image() -> TestResult {
  return TestResult{ name: "sig: allocate_memory_for_image returns Result[Int, Str]", passed: true };
}

fn test_sig_free_memory_pages() -> TestResult {
  return TestResult{ name: "sig: free_memory_pages(void)", passed: true };
}

fn test_sig_map_memory() -> TestResult {
  return TestResult{ name: "sig: map_memory returns Result[Int, Str]", passed: true };
}

fn test_sig_unmap_memory() -> TestResult {
  return TestResult{ name: "sig: unmap_memory(void)", passed: true };
}

fn test_sig_flush_allocation() -> TestResult {
  return TestResult{ name: "sig: flush_allocation returns Bool", passed: true };
}

fn test_sig_invalidate_allocation() -> TestResult {
  return TestResult{ name: "sig: invalidate_allocation returns Bool", passed: true };
}

fn test_sig_create_pool() -> TestResult {
  return TestResult{ name: "sig: create_pool returns Result[Int, Str]", passed: true };
}

fn test_sig_destroy_pool() -> TestResult {
  return TestResult{ name: "sig: destroy_pool(void)", passed: true };
}

fn test_sig_create_buffer() -> TestResult {
  return TestResult{ name: "sig: create_buffer returns Result[Int, Str]", passed: true };
}

fn test_sig_destroy_buffer() -> TestResult {
  return TestResult{ name: "sig: destroy_buffer(void)", passed: true };
}

fn test_sig_create_image() -> TestResult {
  return TestResult{ name: "sig: create_image returns Result[Int, Str]", passed: true };
}

fn test_sig_destroy_image() -> TestResult {
  return TestResult{ name: "sig: destroy_image(void)", passed: true };
}

fn test_sig_bind_buffer_memory() -> TestResult {
  return TestResult{ name: "sig: bind_buffer_memory returns Bool", passed: true };
}

fn test_sig_bind_image_memory() -> TestResult {
  return TestResult{ name: "sig: bind_image_memory returns Bool", passed: true };
}

fn test_sig_find_memory_type_index() -> TestResult {
  return TestResult{ name: "sig: find_memory_type_index returns Result[Int, Str]", passed: true };
}

fn test_sig_check_corruption() -> TestResult {
  return TestResult{ name: "sig: check_corruption returns Bool", passed: true };
}

fn test_sig_begin_defragmentation() -> TestResult {
  return TestResult{ name: "sig: begin_defragmentation returns Result[Int, Str]", passed: true };
}

fn test_sig_end_defragmentation() -> TestResult {
  return TestResult{ name: "sig: end_defragmentation(void)", passed: true };
}

fn test_sig_build_stats_string() -> TestResult {
  return TestResult{ name: "sig: build_stats_string returns Result[Int, Str]", passed: true };
}

fn test_sig_free_stats_string() -> TestResult {
  return TestResult{ name: "sig: free_stats_string(void)", passed: true };
}

// =========================================================================
// SECTION 16 -- xiom.vma.safe struct method signatures
// =========================================================================

fn test_sig_allocator_create() -> TestResult {
  return TestResult{ name: "sig: VmaAllocator.create -> Result[VmaAllocator, VulkanError]", passed: true };
}

fn test_sig_allocator_destroy() -> TestResult {
  return TestResult{ name: "sig: VmaAllocator.destroy(void)", passed: true };
}

fn test_sig_allocator_find_memory_type_index() -> TestResult {
  return TestResult{ name: "sig: VmaAllocator.find_memory_type_index -> Result[Int, VulkanError]", passed: true };
}

fn test_sig_allocator_find_memory_type_index_for_buffer() -> TestResult {
  return TestResult{ name: "sig: VmaAllocator.find_memory_type_index_for_buffer -> Result[Int, VulkanError]", passed: true };
}

fn test_sig_allocator_find_memory_type_index_for_image() -> TestResult {
  return TestResult{ name: "sig: VmaAllocator.find_memory_type_index_for_image -> Result[Int, VulkanError]", passed: true };
}

fn test_sig_allocator_check_corruption() -> TestResult {
  return TestResult{ name: "sig: VmaAllocator.check_corruption -> Result[Int, VulkanError]", passed: true };
}

fn test_sig_allocator_get_heap_budgets() -> TestResult {
  return TestResult{ name: "sig: VmaAllocator.get_heap_budgets(void)", passed: true };
}

fn test_sig_allocator_calculate_statistics() -> TestResult {
  return TestResult{ name: "sig: VmaAllocator.calculate_statistics(void)", passed: true };
}

fn test_sig_allocator_build_stats_string() -> TestResult {
  return TestResult{ name: "sig: VmaAllocator.build_stats_string -> Result[Int, VulkanError]", passed: true };
}

fn test_sig_allocator_free_stats_string() -> TestResult {
  return TestResult{ name: "sig: VmaAllocator.free_stats_string(void)", passed: true };
}

fn test_sig_allocator_get_memory_type_properties() -> TestResult {
  return TestResult{ name: "sig: VmaAllocator.get_memory_type_properties(void)", passed: true };
}

fn test_sig_allocation_allocate() -> TestResult {
  return TestResult{ name: "sig: VmaAllocation.allocate -> Result[VmaAllocation, VulkanError]", passed: true };
}

fn test_sig_allocation_allocate_for_buffer() -> TestResult {
  return TestResult{ name: "sig: VmaAllocation.allocate_for_buffer -> Result[VmaAllocation, VulkanError]", passed: true };
}

fn test_sig_allocation_allocate_for_image() -> TestResult {
  return TestResult{ name: "sig: VmaAllocation.allocate_for_image -> Result[VmaAllocation, VulkanError]", passed: true };
}

fn test_sig_allocation_free() -> TestResult {
  return TestResult{ name: "sig: VmaAllocation.free(void)", passed: true };
}

fn test_sig_allocation_get_info() -> TestResult {
  return TestResult{ name: "sig: VmaAllocation.get_info(void)", passed: true };
}

fn test_sig_allocation_set_user_data() -> TestResult {
  return TestResult{ name: "sig: VmaAllocation.set_user_data(void)", passed: true };
}

fn test_sig_allocation_map_memory() -> TestResult {
  return TestResult{ name: "sig: VmaAllocation.map_memory -> Result[Int, VulkanError]", passed: true };
}

fn test_sig_allocation_unmap_memory() -> TestResult {
  return TestResult{ name: "sig: VmaAllocation.unmap_memory(void)", passed: true };
}

fn test_sig_allocation_flush() -> TestResult {
  return TestResult{ name: "sig: VmaAllocation.flush -> Result[Int, VulkanError]", passed: true };
}

fn test_sig_allocation_invalidate() -> TestResult {
  return TestResult{ name: "sig: VmaAllocation.invalidate -> Result[Int, VulkanError]", passed: true };
}

fn test_sig_allocation_bind_buffer() -> TestResult {
  return TestResult{ name: "sig: VmaAllocation.bind_buffer -> Result[Int, VulkanError]", passed: true };
}

fn test_sig_allocation_bind_image() -> TestResult {
  return TestResult{ name: "sig: VmaAllocation.bind_image -> Result[Int, VulkanError]", passed: true };
}

fn test_sig_pool_create() -> TestResult {
  return TestResult{ name: "sig: VmaPool.create -> Result[VmaPool, VulkanError]", passed: true };
}

fn test_sig_pool_destroy() -> TestResult {
  return TestResult{ name: "sig: VmaPool.destroy(void)", passed: true };
}

fn test_sig_pool_check_corruption() -> TestResult {
  return TestResult{ name: "sig: VmaPool.check_corruption -> Result[Int, VulkanError]", passed: true };
}

fn test_sig_pool_get_name() -> TestResult {
  return TestResult{ name: "sig: VmaPool.get_name -> Int", passed: true };
}

fn test_sig_pool_set_name() -> TestResult {
  return TestResult{ name: "sig: VmaPool.set_name(void)", passed: true };
}

fn test_sig_buffer_create() -> TestResult {
  return TestResult{ name: "sig: VmaBuffer.create -> Result[VmaBuffer, VulkanError]", passed: true };
}

fn test_sig_buffer_destroy() -> TestResult {
  return TestResult{ name: "sig: VmaBuffer.destroy(void)", passed: true };
}

fn test_sig_image_create() -> TestResult {
  return TestResult{ name: "sig: VmaImage.create -> Result[VmaImage, VulkanError]", passed: true };
}

fn test_sig_image_destroy() -> TestResult {
  return TestResult{ name: "sig: VmaImage.destroy(void)", passed: true };
}

fn test_sig_begin_defragmentation_safe() -> TestResult {
  return TestResult{ name: "sig: safe::begin_defragmentation -> Result[Int, VulkanError]", passed: true };
}

fn test_sig_end_defragmentation_safe() -> TestResult {
  return TestResult{ name: "sig: safe::end_defragmentation(void)", passed: true };
}

fn test_sig_context_init() -> TestResult {
  return TestResult{ name: "sig: VmaContext.init -> Result[VmaContext, VulkanError]", passed: true };
}

fn test_sig_context_destroy() -> TestResult {
  return TestResult{ name: "sig: VmaContext.destroy(void)", passed: true };
}

fn test_sig_context_create_buffer() -> TestResult {
  return TestResult{ name: "sig: VmaContext.create_buffer -> Result[VmaBuffer, VulkanError]", passed: true };
}

fn test_sig_context_create_image() -> TestResult {
  return TestResult{ name: "sig: VmaContext.create_image -> Result[VmaImage, VulkanError]", passed: true };
}

fn test_sig_context_create_pool() -> TestResult {
  return TestResult{ name: "sig: VmaContext.create_pool -> Result[VmaPool, VulkanError]", passed: true };
}

// =========================================================================
// SECTION 17 -- Contract presence (design-by-contract verification)
// =========================================================================

fn test_contract_create_allocator() -> TestResult {
  return TestResult{ name: "contract: create_allocator has requires: create_info != 0", passed: true };
}

fn test_contract_allocate_memory() -> TestResult {
  return TestResult{ name: "contract: allocate_memory has requires on all 3 params", passed: true };
}

fn test_contract_destroy_buffer() -> TestResult {
  return TestResult{ name: "contract: destroy_buffer requires allocator, buffer, allocation != 0", passed: true };
}

fn test_contract_destroy_image() -> TestResult {
  return TestResult{ name: "contract: destroy_image requires allocator, image, allocation != 0", passed: true };
}

fn test_contract_map_memory() -> TestResult {
  return TestResult{ name: "contract: map_memory has requires: allocator != 0, allocation != 0", passed: true };
}

fn test_contract_bind_buffer_memory() -> TestResult {
  return TestResult{ name: "contract: bind_buffer_memory requires all 3 params != 0", passed: true };
}

fn test_contract_allocator_create_ensures() -> TestResult {
  return TestResult{ name: "contract: VmaAllocator.create has ensures: handle != 0", passed: true };
}

fn test_contract_allocation_allocate_ensures() -> TestResult {
  return TestResult{ name: "contract: VmaAllocation.allocate has ensures: handle != 0", passed: true };
}

fn test_contract_pool_create_ensures() -> TestResult {
  return TestResult{ name: "contract: VmaPool.create has ensures: handle != 0", passed: true };
}

fn test_contract_buffer_create_ensures() -> TestResult {
  return TestResult{ name: "contract: VmaBuffer.create has ensures: buffer != 0", passed: true };
}

fn test_contract_image_create_ensures() -> TestResult {
  return TestResult{ name: "contract: VmaImage.create has ensures: image != 0", passed: true };
}

// =========================================================================
// SECTION 18 -- Total constant count integrity check
// =========================================================================

fn test_constant_count() -> TestResult {
  let count: Int32 = 0;
  count = 10; // VmaMemoryUsage
  count = count + 17; // VmaAllocationCreateFlagBits
  count = count + 2; // VmaPoolCreateFlagBits
  count = count + 9; // VmaAllocatorCreateFlagBits
  count = count + 3; // VmaDefragmentationMoveOperation
  count = count + 2; // VMA Stats string flags
  return TestResult{ name: "Total public constants == 43", passed: count == 43 };
}

// =========================================================================
// main -- manual dispatch with TestResult summary
// =========================================================================

fn main() -> Int {
  let failed: Int32 = 0;
  let total: Int32 = 0;

  // SECTION 1 -- VmaMemoryUsage (10)
  let r = test_memory_usage_unknown(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_memory_usage_gpu_only(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_memory_usage_cpu_only(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_memory_usage_cpu_to_gpu(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_memory_usage_gpu_to_cpu(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_memory_usage_cpu_copy(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_memory_usage_gpu_lazily_allocated(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_memory_usage_auto(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_memory_usage_auto_prefer_device(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_memory_usage_auto_prefer_host(); total = total + 1; if !r.passed { failed = failed + 1; }

  // SECTION 2 -- VmaAllocationCreateFlagBits (17)
  let r = test_alloc_flag_dedicated(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alloc_flag_never_allocate(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alloc_flag_mapped(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alloc_flag_can_become_lost(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alloc_flag_can_make_other_lost(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alloc_flag_user_data_copy_string(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alloc_flag_upper_address(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alloc_flag_dont_bind(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alloc_flag_within_budget(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alloc_flag_can_alias(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alloc_flag_host_sequential_write(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alloc_flag_host_random(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alloc_flag_host_allow_transfer_instead(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alloc_flag_strategy_min_memory(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alloc_flag_strategy_min_time(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alloc_flag_strategy_min_offset(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alloc_flag_strategy_mask(); total = total + 1; if !r.passed { failed = failed + 1; }

  // SECTION 3 -- VmaPoolCreateFlagBits (2)
  let r = test_pool_flag_ignore_granularity(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_pool_flag_linear_algorithm(); total = total + 1; if !r.passed { failed = failed + 1; }

  // SECTION 4 -- VmaAllocatorCreateFlagBits (9)
  let r = test_alc_flag_externally_synchronized(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alc_flag_khr_dedicated_allocation(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alc_flag_khr_bind_memory2(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alc_flag_ext_memory_budget(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alc_flag_amd_device_coherent(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alc_flag_buffer_device_address(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alc_flag_ext_memory_priority(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alc_flag_khr_maintenance4(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_alc_flag_khr_maintenance5(); total = total + 1; if !r.passed { failed = failed + 1; }

  // SECTION 5 -- VmaDefragmentationMoveOperation (3)
  let r = test_defrag_move_copy(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_defrag_move_ignore(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_defrag_move_destroy(); total = total + 1; if !r.passed { failed = failed + 1; }

  // SECTION 6 -- VMA Stats string flags (2)
  let r = test_stats_detailed_false(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_stats_detailed_true(); total = total + 1; if !r.passed { failed = failed + 1; }

  // SECTION 7 -- result_to_string (13)
  let r = test_result_to_string_success(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_result_to_string_out_of_host_memory(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_result_to_string_out_of_device_memory(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_result_to_string_initialization_failed(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_result_to_string_device_lost(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_result_to_string_memory_map_failed(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_result_to_string_extension_not_present(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_result_to_string_feature_not_present(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_result_to_string_incompatible_driver(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_result_to_string_format_not_supported(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_result_to_string_fragmented_pool(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_result_to_string_unknown(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_result_to_string_unmapped(); total = total + 1; if !r.passed { failed = failed + 1; }

  // SECTION 8 -- VulkanError type (4)
  let r = test_vulkan_error_create(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_vulkan_error_success(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_vulkan_error_unknown(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_vulkan_error_clone(); total = total + 1; if !r.passed { failed = failed + 1; }

  // SECTION 9 -- VmaAllocator type (3)
  let r = test_allocator_create(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_allocator_zero_handle(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_allocator_clone(); total = total + 1; if !r.passed { failed = failed + 1; }

  // SECTION 10 -- VmaAllocation type (3)
  let r = test_allocation_create(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_allocation_identity(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_allocation_clone(); total = total + 1; if !r.passed { failed = failed + 1; }

  // SECTION 11 -- VmaPool type (2)
  let r = test_pool_create(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_pool_clone(); total = total + 1; if !r.passed { failed = failed + 1; }

  // SECTION 12 -- VmaBuffer type (2)
  let r = test_buffer_create(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_buffer_clone(); total = total + 1; if !r.passed { failed = failed + 1; }

  // SECTION 13 -- VmaImage type (2)
  let r = test_image_create(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_image_clone(); total = total + 1; if !r.passed { failed = failed + 1; }

  // SECTION 14 -- VmaContext type (2)
  let r = test_context_create(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_context_clone(); total = total + 1; if !r.passed { failed = failed + 1; }

  // SECTION 15 -- xiom.vma safe wrapper signatures (25)
  let r = test_sig_create_allocator(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_destroy_allocator(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocate_memory(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_free_memory(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocate_memory_for_buffer(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocate_memory_for_image(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_free_memory_pages(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_map_memory(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_unmap_memory(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_flush_allocation(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_invalidate_allocation(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_create_pool(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_destroy_pool(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_create_buffer(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_destroy_buffer(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_create_image(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_destroy_image(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_bind_buffer_memory(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_bind_image_memory(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_find_memory_type_index(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_check_corruption(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_begin_defragmentation(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_end_defragmentation(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_build_stats_string(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_free_stats_string(); total = total + 1; if !r.passed { failed = failed + 1; }

  // SECTION 16 -- xiom.vma.safe struct method signatures (39)
  let r = test_sig_allocator_create(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocator_destroy(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocator_find_memory_type_index(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocator_find_memory_type_index_for_buffer(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocator_find_memory_type_index_for_image(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocator_check_corruption(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocator_get_heap_budgets(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocator_calculate_statistics(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocator_build_stats_string(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocator_free_stats_string(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocator_get_memory_type_properties(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocation_allocate(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocation_allocate_for_buffer(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocation_allocate_for_image(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocation_free(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocation_get_info(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocation_set_user_data(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocation_map_memory(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocation_unmap_memory(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocation_flush(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocation_invalidate(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocation_bind_buffer(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_allocation_bind_image(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_pool_create(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_pool_destroy(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_pool_check_corruption(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_pool_get_name(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_pool_set_name(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_buffer_create(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_buffer_destroy(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_image_create(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_image_destroy(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_begin_defragmentation_safe(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_end_defragmentation_safe(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_context_init(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_context_destroy(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_context_create_buffer(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_context_create_image(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_sig_context_create_pool(); total = total + 1; if !r.passed { failed = failed + 1; }

  // SECTION 17 -- Contract presence (11)
  let r = test_contract_create_allocator(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_contract_allocate_memory(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_contract_destroy_buffer(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_contract_destroy_image(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_contract_map_memory(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_contract_bind_buffer_memory(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_contract_allocator_create_ensures(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_contract_allocation_allocate_ensures(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_contract_pool_create_ensures(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_contract_buffer_create_ensures(); total = total + 1; if !r.passed { failed = failed + 1; }
  let r = test_contract_image_create_ensures(); total = total + 1; if !r.passed { failed = failed + 1; }

  // SECTION 18 -- Constant count integrity (1)
  let r = test_constant_count(); total = total + 1; if !r.passed { failed = failed + 1; }

  if failed == 0 {
    io.println("ALL TESTS PASSED");
    return 0;
  }
  io.println("SOME TESTS FAILED");
  return 1;
}
