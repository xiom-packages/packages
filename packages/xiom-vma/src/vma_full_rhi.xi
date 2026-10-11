// XIOM -- GENERATED typed RHI-path helpers over the bridge support API.
// Generator: tools/gen_vma_full.py (do not edit by hand).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// The suite drives the prescribed path through these helpers:
// device setup -> vmaCreateAllocator -> vmaCreateBuffer ->
// vmaGetAllocationInfo -> vmaDestroyBuffer -> vmaDestroyAllocator ->
// teardown.  Every VMA step goes through a generated bridge wrapper;
// handles stay in bridge slots and cross as scalars (B-11/B-20 safe).

module xiom.vma.full_rhi

extern "C" {
  fn vmafull_export_count() -> Int32;
  fn vmafull_oracle_count() -> Int32;
  fn vmafull_export_name_is(index: Int32, expected: *UInt8) -> Int32;
  fn vmafull_link_proof() -> Int32;
  fn vmafull_device_setup(dll_name: *UInt8) -> Int32;
  fn vmafull_device_teardown(slot: Int32) -> Int32;
  fn vmafull_allocator_create(slot: Int32) -> Int32;
  fn vmafull_allocator_destroy(slot: Int32) -> Int32;
  fn vmafull_slot_allocator(slot: Int32) -> Int;
  fn vmafull_buffer_create(slot: Int32, size: Int64) -> Int32;
  fn vmafull_allocation_info(slot: Int32) -> Int32;
  fn vmafull_buffer_handle(slot: Int32) -> Int;
  fn vmafull_allocation_handle(slot: Int32) -> Int;
  fn vmafull_info_size(slot: Int32) -> Int64;
  fn vmafull_info_offset(slot: Int32) -> Int64;
  fn vmafull_info_memory_type(slot: Int32) -> Int32;
  fn vmafull_info_device_memory(slot: Int32) -> Int64;
  fn vmafull_buffer_destroy(slot: Int32) -> Int32;
  fn vmafull_win32_handle_probe(slot: Int32) -> Int32;
  fn vmafull_error_probe() -> Int32;
}

/// rhi_setup classification for the deterministic SKIP path.
pub const RHI_SKIP_LOADER: Int = -100;
pub const RHI_SKIP_DEVICE: Int = -101;
pub const RHI_SKIP_QUEUE: Int = -102;

/// error_probe_mask() expected value: every null-arg guard behaved.
pub const ERROR_PROBE_EXPECTED: Int = 0;

fn loader_name() -> Str
  requires: true
{
  return "vulkan-1.dll";
}

/// Bridge-exposed function count (export table size).
pub fn surface_count() -> Int
  requires: true
{
  return unsafe { vmafull_export_count() as Int };
}

/// Runtime oracle count baked by the generator.
pub fn surface_oracle() -> Int
  requires: true
{
  return unsafe { vmafull_oracle_count() as Int };
}

/// Link proof: number of wrappers whose symbols are present (== oracle
/// when the full generated surface linked).
pub fn link_proof_count() -> Int
  requires: true
{
  return unsafe { vmafull_link_proof() as Int };
}

/// True when export table entry `index` carries exactly `expected`.
pub fn surface_name_is(index: Int, expected: Str) -> Bool
  requires: index >= 0
{
  return unsafe { (vmafull_export_name_is(index as Int32, expected.c_str()) as Int) != 0 };
}

/// Create instance -> physical device -> graphics-queue device (the
/// package's device creation path).  Returns a 1-based slot, or a negative
/// classification (see RHI_SKIP_*; -1..-9 = step failures).
pub fn rhi_setup() -> Int
  requires: true
{
  return unsafe { vmafull_device_setup(loader_name().c_str()) as Int };
}

/// Same, against an explicitly named loader module (deterministic SKIP
/// classification on any host with a bogus name).
pub fn rhi_setup_named(dll: Str) -> Int
  requires: dll.len() > 0
{
  return unsafe { vmafull_device_setup(dll.c_str()) as Int };
}

pub fn rhi_teardown(slot: Int) -> Int32
  requires: slot > 0
{
  return unsafe { vmafull_device_teardown(slot as Int32) };
}

/// vmaCreateAllocator through the generated wrapper (VkResult).
pub fn rhi_allocator_create(slot: Int) -> Int32
  requires: slot > 0
{
  return unsafe { vmafull_allocator_create(slot as Int32) };
}

/// vmaDestroyAllocator through the generated wrapper.
pub fn rhi_allocator_destroy(slot: Int) -> Int32
  requires: slot > 0
{
  return unsafe { vmafull_allocator_destroy(slot as Int32) };
}

pub fn rhi_slot_allocator(slot: Int) -> Int
  requires: slot > 0
{
  return unsafe { vmafull_slot_allocator(slot as Int32) };
}

/// vmaCreateBuffer (64 KiB path) through the generated wrapper.
pub fn rhi_buffer_create(slot: Int, size: Int) -> Int32
  requires: slot > 0
  requires: size > 0
{
  return unsafe { vmafull_buffer_create(slot as Int32, size as Int64) };
}

/// vmaGetAllocationInfo through the generated wrapper.
pub fn rhi_allocation_info(slot: Int) -> Int32
  requires: slot > 0
{
  return unsafe { vmafull_allocation_info(slot as Int32) };
}

pub fn rhi_buffer_handle(slot: Int) -> Int
  requires: slot > 0
{
  return unsafe { vmafull_buffer_handle(slot as Int32) };
}

pub fn rhi_allocation_handle(slot: Int) -> Int
  requires: slot > 0
{
  return unsafe { vmafull_allocation_handle(slot as Int32) };
}

pub fn rhi_info_size(slot: Int) -> Int
  requires: slot > 0
{
  return unsafe { vmafull_info_size(slot as Int32) as Int };
}

pub fn rhi_info_offset(slot: Int) -> Int
  requires: slot > 0
{
  return unsafe { vmafull_info_offset(slot as Int32) as Int };
}

pub fn rhi_info_memory_type(slot: Int) -> Int32
  requires: slot > 0
{
  return unsafe { vmafull_info_memory_type(slot as Int32) };
}

pub fn rhi_info_device_memory(slot: Int) -> Int
  requires: slot > 0
{
  return unsafe { vmafull_info_device_memory(slot as Int32) as Int };
}

/// vmaDestroyBuffer through the generated wrapper.
pub fn rhi_buffer_destroy(slot: Int) -> Int32
  requires: slot > 0
{
  return unsafe { vmafull_buffer_destroy(slot as Int32) };
}

/// Functional probe for the config-gated vmaGetMemoryWin32Handle on the
/// live allocation: VK_SUCCESS or VK_ERROR_FEATURE_NOT_PRESENT (the
/// win32 handle fn is not enabled at device creation).
pub fn rhi_win32_handle_probe(slot: Int) -> Int32
  requires: slot > 0
{
  return unsafe { vmafull_win32_handle_probe(slot as Int32) };
}

/// Null-argument guard bitmask over seven wrapper shapes; 0 = all good.
pub fn error_probe_mask() -> Int
  requires: true
{
  return unsafe { vmafull_error_probe() as Int };
}
