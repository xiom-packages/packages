// XIOM -- xiom.dx12.video: d3d12video.h slice helpers.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// The full generated ID3D12Video* surface lives in
// `xiom.dx12.video_iface_01..NN` (190 wrappers) + `xiom.dx12.video_consts_*`
// (661 consts); struct metadata for the D3D12_VIDEO_* shapes ships in
// `xiom.dx12.struct_meta_*` (D3D12_SIZEOF_* / D3D12_OFF_*).
//
// This module adds the bridge helpers: video IIDs (pinned from
// d3d12video.h @ 461ef513) and a QI classification probe on the live
// ID3D12Device.  Video command lists are created through the CORE device
// (`d3d12_device_create_command_list` with
// `D3D12_COMMAND_LIST_TYPE_VIDEO_DECODE` (4) and the video IID).

module xiom.dx12.video

extern "C" {
  fn xd12_video_iid(which: Int32, dst16: *UInt8) -> Int32;
  fn xd12_video_probe() -> Int32;
  fn xd12_video_error() -> *UInt8;
  fn xd12_video_cmdlist_create() -> Int;
  fn xd12_video_cmdlist_hr() -> Int32;
  fn xd12_video_cmdlist_alloc() -> Int;
  fn xd12_video_cmdlist_cleanup();
}

/// QI probe statuses.
pub const DX12_VIDEO_OK: Int = 0;         // ID3D12VideoDevice live
pub const DX12_VIDEO_NO_DEVICE: Int = 1;  // no D3D12 device -> SKIP
pub const DX12_VIDEO_QI_FAILED: Int = 2;  // device present, QI failed -> FAIL

/// Video IID table indices (order of `video_iids.inc`).
pub const DX12_VIDEO_IID_DEVICE: Int = 0;
pub const DX12_VIDEO_IID_DEVICE1: Int = 1;
pub const DX12_VIDEO_IID_DEVICE2: Int = 2;
pub const DX12_VIDEO_IID_DEVICE3: Int = 3;
pub const DX12_VIDEO_IID_DEVICE4: Int = 4;
pub const DX12_VIDEO_IID_DECODE_COMMAND_LIST: Int = 5;
pub const DX12_VIDEO_IID_PROCESS_COMMAND_LIST: Int = 6;
pub const DX12_VIDEO_IID_ENCODE_COMMAND_LIST: Int = 7;
pub const DX12_VIDEO_IID_DECODER: Int = 8;
pub const DX12_VIDEO_IID_DECODER_HEAP: Int = 9;
pub const DX12_VIDEO_IID_PROCESSOR: Int = 10;
pub const DX12_VIDEO_IID_MOTION_ESTIMATOR: Int = 11;
pub const DX12_VIDEO_IID_MOTION_VECTOR_HEAP: Int = 12;

pub type Dx12VideoProbeError = {
  kind: Int;
  message: Str;
}

/// QI the live device for `ID3D12VideoDevice` (loads + probes the D3D12
/// device if needed).  `DX12_VIDEO_*` status.
/// Complexity: O(load + device probe + QI).
pub fn dx12_video_probe() -> Int
  requires: true
{
  unsafe { return xd12_video_probe() as Int; }
}

/// Error text from the last video probe (empty when none).
/// Complexity: O(1).
pub fn dx12_video_probe_error() -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xd12_video_error()); }
}

/// The video decode command-list chain, created C-side (device -> type-4
/// allocator -> `CreateCommandList` with the video IID).  Returns the
/// created `ID3D12VideoDecodeCommandList*` (0 on failure) so the generated
/// video wrappers can drive it; `dx12_video_cmdlist_hr()` carries the raw
/// HRESULT and `dx12_video_cmdlist_alloc()` the chain allocator.  The C
/// side owns the ABI edge here: consuming allocator out-pointers on the
/// XIOM side is unreliable (B-24).
/// Complexity: O(load + allocator + list).
pub fn dx12_video_cmdlist_create() -> Int
  requires: true
{
  unsafe { return xd12_video_cmdlist_create(); }
}

/// Raw `CreateCommandList` HRESULT from the last
/// `dx12_video_cmdlist_create` (-1 = not run).
/// Complexity: O(1).
pub fn dx12_video_cmdlist_hr() -> Int
  requires: true
{
  unsafe { return xd12_video_cmdlist_hr() as Int; }
}

/// The chain allocator pointer from the last `dx12_video_cmdlist_create`
/// (0 = none).
/// Complexity: O(1).
pub fn dx12_video_cmdlist_alloc() -> Int
  requires: true
{
  unsafe { return xd12_video_cmdlist_alloc(); }
}

/// Release the chain allocator (call after releasing the list).
/// Complexity: O(1).
pub fn dx12_video_cmdlist_cleanup()
  requires: true
{
  unsafe { xd12_video_cmdlist_cleanup(); }
}

/// Copy one of the pinned video IID byte images into `dst16` (16 bytes).
/// 0 ID3D12VideoDevice .. 12 ID3D12VideoMotionVectorHeap (`DX12_VIDEO_IID_*`).
/// Complexity: O(1).
pub fn dx12_video_iid(which: Int, dst16: *UInt8) -> Int
  requires: true
{
  unsafe { return xd12_video_iid(which as Int32, dst16) as Int; }
}
