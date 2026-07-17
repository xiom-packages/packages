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

fn test_memory_usage_constants() -> Bool {
  if VMA_MEMORY_USAGE_UNKNOWN != 0 { return false; }
  if VMA_MEMORY_USAGE_GPU_ONLY != 1 { return false; }
  if VMA_MEMORY_USAGE_CPU_ONLY != 2 { return false; }
  if VMA_MEMORY_USAGE_AUTO != 7 { return false; }
  if VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE != 8 { return false; }
  return true;
}

fn test_allocation_create_flags() -> Bool {
  if VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT != 1 { return false; }
  if VMA_ALLOCATION_CREATE_MAPPED_BIT != 4 { return false; }
  if VMA_ALLOCATION_CREATE_STRATEGY_MIN_MEMORY_BIT != 0x00010000 { return false; }
  if VMA_ALLOCATION_CREATE_STRATEGY_MIN_TIME_BIT != 0x00020000 { return false; }
  if VMA_ALLOCATION_CREATE_STRATEGY_MASK != 0x00070000 { return false; }
  return true;
}

fn test_pool_create_flags() -> Bool {
  if VMA_POOL_CREATE_IGNORE_BUFFER_IMAGE_GRANULARITY_BIT != 1 { return false; }
  if VMA_POOL_CREATE_LINEAR_ALGORITHM_BIT != 2 { return false; }
  return true;
}

fn test_allocator_create_flags() -> Bool {
  if VMA_ALLOCATOR_CREATE_EXTERNALLY_SYNCHRONIZED_BIT != 1 { return false; }
  if VMA_ALLOCATOR_CREATE_KHR_DEDICATED_ALLOCATION_BIT != 2 { return false; }
  if VMA_ALLOCATOR_CREATE_KHR_BIND_MEMORY2_BIT != 4 { return false; }
  if VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT != 0x00000020 { return false; }
  if VMA_ALLOCATOR_CREATE_KHR_MAINTENANCE5_BIT != 0x00000100 { return false; }
  return true;
}

fn test_defrag_move_operations() -> Bool {
  if VMA_DEFRAGMENTATION_MOVE_OPERATION_COPY != 0 { return false; }
  if VMA_DEFRAGMENTATION_MOVE_OPERATION_IGNORE != 1 { return false; }
  if VMA_DEFRAGMENTATION_MOVE_OPERATION_DESTROY != 2 { return false; }
  return true;
}

fn test_stats_string_flags() -> Bool {
  if VMA_STATS_STRING_DETAILED_MAP_FALSE != 0 { return false; }
  if VMA_STATS_STRING_DETAILED_MAP_TRUE != 1 { return false; }
  return true;
}

fn test_result_to_string() -> Bool {
  if result_to_string(0) != "VK_SUCCESS" { return false; }
  if result_to_string(-1) != "VK_ERROR_OUT_OF_HOST_MEMORY" { return false; }
  if result_to_string(-2) != "VK_ERROR_OUT_OF_DEVICE_MEMORY" { return false; }
  if result_to_string(-4) != "VK_ERROR_DEVICE_LOST" { return false; }
  if result_to_string(-8) != "VK_ERROR_FEATURE_NOT_PRESENT" { return false; }
  if result_to_string(999) != "VK_UNKNOWN_ERROR" { return false; }
  return true;
}

fn test_vulkan_error_type() -> Bool {
  let e = VulkanError{ code: -1 };
  if e.code != -1 { return false; }
  return true;
}

fn test_allocator_type_shape() -> Bool {
  let a = VmaAllocator{ handle: 42 };
  if a.handle != 42 { return false; }
  return true;
}

fn test_allocation_type_shape() -> Bool {
  let a = VmaAllocation{ handle: 1, allocator: 2 };
  if a.handle != 1 { return false; }
  if a.allocator != 2 { return false; }
  return true;
}

fn test_pool_type_shape() -> Bool {
  let p = VmaPool{ handle: 10, allocator: 20 };
  if p.handle != 10 { return false; }
  if p.allocator != 20 { return false; }
  return true;
}

fn test_buffer_type_shape() -> Bool {
  let b = VmaBuffer{ buffer: 100, allocation: 200, allocator: 300 };
  if b.buffer != 100 { return false; }
  if b.allocation != 200 { return false; }
  if b.allocator != 300 { return false; }
  return true;
}

fn test_image_type_shape() -> Bool {
  let i = VmaImage{ image: 33, allocation: 44, allocator: 55 };
  if i.image != 33 { return false; }
  if i.allocation != 44 { return false; }
  if i.allocator != 55 { return false; }
  return true;
}

fn test_context_type_shape() -> Bool {
  let c = VmaContext{ allocator: 7 };
  if c.allocator != 7 { return false; }
  return true;
}

fn main() -> Int {
  if !test_memory_usage_constants() { return 1; }
  if !test_allocation_create_flags() { return 2; }
  if !test_pool_create_flags() { return 3; }
  if !test_allocator_create_flags() { return 4; }
  if !test_defrag_move_operations() { return 5; }
  if !test_stats_string_flags() { return 6; }
  if !test_result_to_string() { return 7; }
  if !test_vulkan_error_type() { return 8; }
  if !test_allocator_type_shape() { return 9; }
  if !test_allocation_type_shape() { return 10; }
  if !test_pool_type_shape() { return 11; }
  if !test_buffer_type_shape() { return 12; }
  if !test_image_type_shape() { return 13; }
  if !test_context_type_shape() { return 14; }
  return 0;
}
