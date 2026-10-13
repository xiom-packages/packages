// XIOM -- xiom.dx12: Direct3D 12 foundation bindings (0.3.1).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: runtime-loaded foundation probe with SKIP semantics, backed by the
// vendored bridge `src/dx12_probe.c` (compiled with `--c-source`, see
// port.args.json).  The bridge resolves `d3d12.dll` at RUNTIME and drives
// the COM objects through the vtable ABI pinned from the
// microsoft/DirectX-Headers clone (PROVENANCE.md):
//
//   stage 1 symbols   -- D3D12CreateDevice resolved
//   stage 2 device    -- D3D12CreateDevice(NULL, 11_0, IID_ID3D12Device)
//                        + a GetNodeCount vtable call (slot 7)
//   stage 3 object    -- CreateCommandAllocator (slot 9) out-param
//                        interface roundtrip, then Release
//
// Classification (the suite maps it to markers):
//   DX12_LOAD_ABSENT    -> SKIP (d3d12.dll missing; CI stays green)
//   DX12_LOAD_NO_DEVICE -> SKIP (no D3D12-capable adapter on this host)
//   DX12_LOAD_ABI       -> FAIL (library present but exports missing)
//
// The Agility SDK runtime is NOT required or vendored (see PROVENANCE.md).
// The full generated surface (all ID3D12* interfaces + free functions +
// enums/struct metadata from the pinned headers) lives in the generated
// modules; the struct-metadata + DXGI + d3d12video slices are complete as
// of 0.3.0 (stable at 0.3.1).

module xiom.dx12

extern "C" {
  fn xd12_load_named(soname: *UInt8) -> Int32;
  fn xd12_load() -> Int32;
  fn xd12_error() -> *UInt8;
  fn xd12_device_probe() -> Int32;
  fn xd12_device_node_count() -> Int32;
  fn xd12_allocator_ok() -> Int32;
  fn xd12_device_ptr() -> Int;
  fn xd12_resolve(name: *UInt8) -> *UInt8;
  fn xd12_iid(which: Int32, dst16: *UInt8) -> Int32;
  fn xd12_blob_size(blob: *UInt8) -> Int32;
  fn xd12_blob_size64(blob: *UInt8) -> Int64;
  fn xd12_blob_head64(blob: *UInt8) -> Int64;
  fn xd12_root_signature_probe() -> Int32;
  fn xd12_root_signature_size() -> Int32;
  fn xd12_root_signature_magic() -> Int64;
  fn xd12_poke_u32(dst: *UInt8, off: Int32, v: UInt32);
  fn xd12_poke_u64(dst: *UInt8, off: Int32, v: UInt64);
  fn xd12_null_ptr() -> *UInt8;
  fn xd12_unload();
}

// =========================================================================
// Identity and pinned ABI constants (DirectX-Headers @ the pin)
// =========================================================================

pub const DX12_SONAME: Str = "d3d12.dll";

pub const DX12_LOAD_ABSENT: Int = 0;    // runtime missing -> SKIP
pub const DX12_LOAD_NO_DEVICE: Int = 1; // no D3D12-capable adapter -> SKIP
pub const DX12_LOAD_ABI: Int = 2;       // exports missing -> FAIL

// D3D_FEATURE_LEVEL
pub const D3D_FEATURE_LEVEL_11_0: Int = 0xB000;
pub const D3D_FEATURE_LEVEL_11_1: Int = 0xB100;
pub const D3D_FEATURE_LEVEL_12_0: Int = 0xC000;
pub const D3D_FEATURE_LEVEL_12_1: Int = 0xC100;
pub const D3D_FEATURE_LEVEL_12_2: Int = 0xC200;

// D3D12_COMMAND_LIST_TYPE
pub const D3D12_COMMAND_LIST_TYPE_DIRECT: Int = 0;
pub const D3D12_COMMAND_LIST_TYPE_BUNDLE: Int = 1;
pub const D3D12_COMMAND_LIST_TYPE_COMPUTE: Int = 2;
pub const D3D12_COMMAND_LIST_TYPE_COPY: Int = 3;

pub type Dx12ProbeError = {
  kind: Int;
  message: Str;
}

/// Result of the device stage: the runtime reported this many device nodes
/// (linked adapters) and the command-allocator out-param roundtrip ran.
pub type Dx12DeviceInfo = {
  node_count: Int;
  allocator_ok: Bool;
}

// =========================================================================
// Probe API
// =========================================================================

/// Probe an explicitly named D3D12 runtime.  Useful for tests: a bogus name
/// exercises the ABSENT/SKIP classification deterministically even on hosts
/// that have a D3D12 adapter.
/// Complexity: O(load + device + allocator).
pub fn dx12_probe_named(soname: Str) -> Result[Dx12DeviceInfo, Dx12ProbeError]
  requires: soname.len() > 0
{
  let rc = unsafe { xd12_load_named(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xd12_error()) };
    if rc == 1 {
      return Err(Dx12ProbeError{ kind: DX12_LOAD_ABSENT; message: msg });
    }
    return Err(Dx12ProbeError{ kind: DX12_LOAD_ABI; message: msg });
  }
  let q = unsafe { xd12_device_probe() as Int };
  if q != 0 {
    let msg = unsafe { Str::from_c_str(xd12_error()) };
    unsafe { xd12_unload(); }
    if q == 2 {
      return Err(Dx12ProbeError{ kind: DX12_LOAD_ABI; message: msg });
    }
    return Err(Dx12ProbeError{ kind: DX12_LOAD_NO_DEVICE; message: msg });
  }
  let nodes = unsafe { xd12_device_node_count() as Int };
  let alloc_ok = (unsafe { xd12_allocator_ok() as Int }) == 1;
  unsafe { xd12_unload(); }
  return Ok(Dx12DeviceInfo{ node_count: nodes, allocator_ok: alloc_ok });
}

/// Probe the default runtime (`d3d12.dll`).
/// Complexity: O(load + device + allocator).
pub fn dx12_probe() -> Result[Dx12DeviceInfo, Dx12ProbeError]
  requires: true
{
  return dx12_probe_named(DX12_SONAME);
}

/// Load the runtime + create the device and KEEP it live so the generated
/// `iface_*` wrappers can drive it (`dx12_device_ptr`).  Close with
/// `dx12_unload`.  Same classification as `dx12_probe`.
/// Complexity: O(load + device + allocator).
pub fn dx12_open_device() -> Result[Dx12DeviceInfo, Dx12ProbeError]
  requires: true
{
  let rc = unsafe { xd12_load() as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xd12_error()) };
    if rc == 1 {
      return Err(Dx12ProbeError{ kind: DX12_LOAD_ABSENT; message: msg });
    }
    return Err(Dx12ProbeError{ kind: DX12_LOAD_ABI; message: msg });
  }
  let q = unsafe { xd12_device_probe() as Int };
  if q != 0 {
    let msg = unsafe { Str::from_c_str(xd12_error()) };
    unsafe { xd12_unload(); }
    if q == 2 {
      return Err(Dx12ProbeError{ kind: DX12_LOAD_ABI; message: msg });
    }
    return Err(Dx12ProbeError{ kind: DX12_LOAD_NO_DEVICE; message: msg });
  }
  let nodes = unsafe { xd12_device_node_count() as Int };
  let alloc_ok = (unsafe { xd12_allocator_ok() as Int }) == 1;
  return Ok(Dx12DeviceInfo{ node_count: nodes, allocator_ok: alloc_ok });
}

/// Release any runtime handles held by the probe.  Safe when nothing is
/// loaded.
/// Complexity: O(1).
pub fn dx12_unload()
  requires: true
{
  unsafe { xd12_unload(); }
}

// =========================================================================
// Generated-surface helpers (0.2.0): the `src/iface_*.xi` wrappers drive
// COM objects through these.
// =========================================================================

/// The live `ID3D12Device*` created by the probe (0 when none).
/// Complexity: O(1).
pub fn dx12_device_ptr() -> Int
  requires: true
{
  unsafe { return xd12_device_ptr(); }
}

/// Lazy free-function resolver on the loaded `d3d12.dll` (0 when absent).
/// Complexity: O(1).
pub fn dx12_resolve(name: *UInt8) -> *UInt8
  requires: true
{
  unsafe { return xd12_resolve(name); }
}

/// Copy one of the pinned core IID byte images into `dst16` (16 bytes).
/// 0 ID3D12Device, 1 ID3D12CommandAllocator, 2 ID3D12CommandQueue,
/// 3 ID3D12CommandList, 4 ID3D12GraphicsCommandList, 5 ID3D12Resource,
/// 6 ID3D12Fence, 7 ID3D12DescriptorHeap, 8 ID3D12RootSignature,
/// 9 ID3D12PipelineState, 10 ID3D12Heap, 11 ID3D12QueryHeap.
/// Complexity: O(1).
pub fn dx12_iid(which: Int, dst16: *UInt8) -> Int
  requires: true
{
  unsafe { return xd12_iid(which as Int32, dst16) as Int; }
}

/// `ID3DBlob::GetBufferSize` (vtable slot 4).  -1 when blob is 0.
/// Complexity: O(1).
pub fn dx12_blob_size(blob: *UInt8) -> Int
  requires: true
{
  unsafe { return xd12_blob_size(blob) as Int; }
}

/// Full 64-bit `GetBufferSize` (diagnostic).
/// Complexity: O(1).
pub fn dx12_blob_size64(blob: *UInt8) -> Int
  requires: true
{
  unsafe { return xd12_blob_size64(blob) as Int; }
}

/// First 8 bytes of the blob payload (diagnostic; `RTS0` magic witness).
/// Complexity: O(1).
pub fn dx12_blob_head64(blob: *UInt8) -> Int
  requires: true
{
  unsafe { return xd12_blob_head64(blob) as Int; }
}

/// Typed root-signature serialize probe (bridge-side struct building):
/// 0=ok, 1=serialize failed, 2=no runtime/export.
/// Complexity: O(serialize).
pub fn dx12_root_signature_probe() -> Int
  requires: true
{
  unsafe { return xd12_root_signature_probe() as Int; }
}

/// Size of the blob produced by `dx12_root_signature_probe` (-1 = failed).
/// Complexity: O(1).
pub fn dx12_root_signature_size() -> Int
  requires: true
{
  unsafe { return xd12_root_signature_size() as Int; }
}

/// First 8 payload bytes from the probe blob (RTS0 magic witness).
/// Complexity: O(1).
pub fn dx12_root_signature_magic() -> Int
  requires: true
{
  unsafe { return xd12_root_signature_magic() as Int; }
}

/// Little-endian u32 store at `dst + off` (struct building in tests).
/// Complexity: O(1).
pub fn dx12_poke_u32(dst: *UInt8, off: Int, v: UInt32)
  requires: true
{
  unsafe { xd12_poke_u32(dst, off as Int32, v); }
}

/// Little-endian u64 store at `dst + off` (struct building in tests).
/// Complexity: O(1).
pub fn dx12_poke_u64(dst: *UInt8, off: Int, v: UInt64)
  requires: true
{
  unsafe { xd12_poke_u64(dst, off as Int32, v); }
}

/// A NULL pointer that ORIGINATED in C (returns 0).  On v0.64.4 the XIOM
/// `null` literal marshals to a garbage address when passed to a C extern
/// param (B-23); use this handle for nullable pointer arguments until the
/// compiler fix ships.
/// Complexity: O(1).
pub fn dx12_null_ptr() -> *UInt8
  requires: true
{
  unsafe { return xd12_null_ptr(); }
}
