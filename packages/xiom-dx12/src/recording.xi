// XIOM -- xiom.dx12.recording: command-recording helpers (0.4.0).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Typed convenience over the GENERATED surface (src/iface_*.xi):
// submission + fence flows that would otherwise need a raw pointer-array
// slot at every call site.  The single-entry command-list array is built
// in an OWNED slot with byte-indexed writes (B-24) and the pointer-edged
// flow stays on C return values; there is no `unsafe`/`extern` here (the
// root module `xiom.dx12` owns the bridge contract).
//
// Usage sketch (all handles come from the generated surface):
//   // allocator + list created via d3d12_device_create_command_allocator /
//   // d3d12_device_create_command_list (IIDs 1 and 4 through dx12_iid)
//   d3d12_graphics_command_list_close(list);
//   dx12_execute_one(queue, list);
//   d3d12_command_queue_signal(queue, fence as *UInt8, 1 as UInt64);
//   dx12_fence_wait(fence as *UInt8, 1 as UInt64, 5000);

module xiom.dx12.recording

use xiom.dx12;
use xiom.dx12.iface_03;

/// Execute one closed command list on a queue.  Builds the
/// `ID3D12CommandList* const*` array (one entry) in an owned slot and
/// calls the generated `ID3D12CommandQueue::ExecuteCommandLists`.
/// Complexity: O(1) + submission.
pub fn dx12_execute_one(queue: Int, list: Int)
  requires: queue != 0
  requires: list != 0
{
  var slot: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < 8 { slot.push(0 as UInt8); i = i + 1; }
  dx12_poke_u64(slot.as_mut_ptr(), 0, list as UInt64);
  d3d12_command_queue_execute_command_lists(queue, 1 as UInt32, slot.as_mut_ptr());
}
