// XIOM -- xiom.dx12: Direct3D 12 foundation bindings (0.1.0).
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
// enums/struct metadata from the pinned headers) is the 0.2.0 wave.

module xiom.dx12

extern "C" {
  fn xd12_load_named(soname: *UInt8) -> Int32;
  fn xd12_load() -> Int32;
  fn xd12_error() -> *UInt8;
  fn xd12_device_probe() -> Int32;
  fn xd12_device_node_count() -> Int32;
  fn xd12_allocator_ok() -> Int32;
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

/// Release any runtime handles held by the probe.  Safe when nothing is
/// loaded.
/// Complexity: O(1).
pub fn dx12_unload()
  requires: true
{
  unsafe { xd12_unload(); }
}
