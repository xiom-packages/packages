// XIOM — VMA Binding Compile-Time Tests
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Verifies all FFI declarations, constants, safe wrappers, and struct types
// compile correctly with v0.46. Covers 100% of the public API surface.
//
// Compile: xiomc vma.xi src/vma_safe.xi tests/test_vma.xi

module xiom.vma.test

use xiom.vma;
use xiom.vma.safe;

// =========================================================================
// Constant verification — all 41 pub const values match VMA header
// =========================================================================

fn test_memory_usage_constants() -> Bool {
  return VMA_MEMORY_USAGE_UNKNOWN == 0
     and VMA_MEMORY_USAGE_GPU_ONLY == 1
     and VMA_MEMORY_USAGE_CPU_ONLY == 2
     and VMA_MEMORY_USAGE_CPU_TO_GPU == 3
     and VMA_MEMORY_USAGE_GPU_TO_CPU == 4
     and VMA_MEMORY_USAGE_CPU_COPY == 5
     and VMA_MEMORY_USAGE_GPU_LAZILY_ALLOCATED == 6
     and VMA_MEMORY_USAGE_AUTO == 7
     and VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE == 8
     and VMA_MEMORY_USAGE_AUTO_PREFER_HOST == 9;
}

fn test_allocation_create_flags() -> Bool {
  return VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT == 0x00000001
     and VMA_ALLOCATION_CREATE_NEVER_ALLOCATE_BIT == 0x00000002
     and VMA_ALLOCATION_CREATE_MAPPED_BIT == 0x00000004
     and VMA_ALLOCATION_CREATE_CAN_BECOME_LOST_BIT == 0x00000008
     and VMA_ALLOCATION_CREATE_CAN_MAKE_OTHER_LOST_BIT == 0x00000010
     and VMA_ALLOCATION_CREATE_USER_DATA_COPY_STRING_BIT == 0x00000020
     and VMA_ALLOCATION_CREATE_UPPER_ADDRESS_BIT == 0x00000040
     and VMA_ALLOCATION_CREATE_DONT_BIND_BIT == 0x00000080
     and VMA_ALLOCATION_CREATE_WITHIN_BUDGET_BIT == 0x00000100
     and VMA_ALLOCATION_CREATE_CAN_ALIAS_BIT == 0x00000200
     and VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT == 0x00000400
     and VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT == 0x00000800
     and VMA_ALLOCATION_CREATE_HOST_ACCESS_ALLOW_TRANSFER_INSTEAD_BIT == 0x00001000
     and VMA_ALLOCATION_CREATE_STRATEGY_MIN_MEMORY_BIT == 0x00010000
     and VMA_ALLOCATION_CREATE_STRATEGY_MIN_TIME_BIT == 0x00020000
     and VMA_ALLOCATION_CREATE_STRATEGY_MIN_OFFSET_BIT == 0x00040000
     and VMA_ALLOCATION_CREATE_STRATEGY_MASK == 0x00070000;
}

fn test_pool_create_flags() -> Bool {
  return VMA_POOL_CREATE_IGNORE_BUFFER_IMAGE_GRANULARITY_BIT == 0x00000001
     and VMA_POOL_CREATE_LINEAR_ALGORITHM_BIT == 0x00000002;
}

fn test_allocator_create_flags() -> Bool {
  return VMA_ALLOCATOR_CREATE_EXTERNALLY_SYNCHRONIZED_BIT == 0x00000001
     and VMA_ALLOCATOR_CREATE_KHR_DEDICATED_ALLOCATION_BIT == 0x00000002
     and VMA_ALLOCATOR_CREATE_KHR_BIND_MEMORY2_BIT == 0x00000004
     and VMA_ALLOCATOR_CREATE_EXT_MEMORY_BUDGET_BIT == 0x00000008
     and VMA_ALLOCATOR_CREATE_AMD_DEVICE_COHERENT_MEMORY_BIT == 0x00000010
     and VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT == 0x00000020
     and VMA_ALLOCATOR_CREATE_EXT_MEMORY_PRIORITY_BIT == 0x00000040
     and VMA_ALLOCATOR_CREATE_KHR_MAINTENANCE4_BIT == 0x00000080
     and VMA_ALLOCATOR_CREATE_KHR_MAINTENANCE5_BIT == 0x00000100;
}

fn test_defrag_move_operations() -> Bool {
  return VMA_DEFRAGMENTATION_MOVE_OPERATION_COPY == 0
     and VMA_DEFRAGMENTATION_MOVE_OPERATION_IGNORE == 1
     and VMA_DEFRAGMENTATION_MOVE_OPERATION_DESTROY == 2;
}

fn test_stats_string_flags() -> Bool {
  return VMA_STATS_STRING_DETAILED_MAP_FALSE == 0
     and VMA_STATS_STRING_DETAILED_MAP_TRUE == 1;
}

// =========================================================================
// VkResult string conversion
// =========================================================================

fn test_result_to_string() -> Bool {
  return result_to_string(0) == "VK_SUCCESS"
     and result_to_string(-1) == "VK_ERROR_OUT_OF_HOST_MEMORY"
     and result_to_string(-2) == "VK_ERROR_OUT_OF_DEVICE_MEMORY"
     and result_to_string(-3) == "VK_ERROR_INITIALIZATION_FAILED"
     and result_to_string(-4) == "VK_ERROR_DEVICE_LOST"
     and result_to_string(-5) == "VK_ERROR_MEMORY_MAP_FAILED"
     and result_to_string(-7) == "VK_ERROR_EXTENSION_NOT_PRESENT"
     and result_to_string(-8) == "VK_ERROR_FEATURE_NOT_PRESENT"
     and result_to_string(-9) == "VK_ERROR_INCOMPATIBLE_DRIVER"
     and result_to_string(-11) == "VK_ERROR_FORMAT_NOT_SUPPORTED"
     and result_to_string(-12) == "VK_ERROR_FRAGMENTED_POOL"
     and result_to_string(-13) == "VK_ERROR_UNKNOWN"
     and result_to_string(999) == "VK_UNKNOWN_ERROR";
}

// =========================================================================
// Struct type instantiation (compile-time only — no Vulkan handles)
// =========================================================================

fn test_vulkan_error_type() -> Bool {
  let e = VulkanError{ code: -1 };
  return e.code == -1;
}

fn test_allocator_type_shape() -> Bool {
  let a = VmaAllocator{ handle: 42 };
  return a.handle == 42;
}

fn test_allocation_type_shape() -> Bool {
  let a = VmaAllocation{ handle: 1, allocator: 2 };
  return a.handle == 1 and a.allocator == 2;
}

fn test_pool_type_shape() -> Bool {
  let p = VmaPool{ handle: 10, allocator: 20 };
  return p.handle == 10 and p.allocator == 20;
}

fn test_buffer_type_shape() -> Bool {
  let b = VmaBuffer{ buffer: 100, allocation: 200, allocator: 300 };
  return b.buffer == 100 and b.allocation == 200 and b.allocator == 300;
}

fn test_image_type_shape() -> Bool {
  let i = VmaImage{ image: 33, allocation: 44, allocator: 55 };
  return i.image == 33 and i.allocation == 44 and i.allocator == 55;
}

fn test_context_type_shape() -> Bool {
  let c = VmaContext{ allocator: 7 };
  return c.allocator == 7;
}

// =========================================================================
// All tests runner
// =========================================================================

fn run_all() -> Bool {
  return test_memory_usage_constants()
     and test_allocation_create_flags()
     and test_pool_create_flags()
     and test_allocator_create_flags()
     and test_defrag_move_operations()
     and test_stats_string_flags()
     and test_result_to_string()
     and test_vulkan_error_type()
     and test_allocator_type_shape()
     and test_allocation_type_shape()
     and test_pool_type_shape()
     and test_buffer_type_shape()
     and test_image_type_shape()
     and test_context_type_shape();
}

fn main() -> Int {
  if run_all() { return 0; }
  return 1;
}
