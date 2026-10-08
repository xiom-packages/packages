// XIOM -- xiom.directx12: Direct3D 12 / DXGI capability probe via dynamic loader.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: dynamic loader + capability probe (same pattern as xiom.directx11).
// No link-time dependency and no SDK headers: `src/d3d12_probe.c` declares the
// minimal ABI locally (verified against the pinned Windows SDK headers) and
// resolves `d3d12.dll` + `dxgi.dll` at runtime. All XIOM `unsafe`/`extern`
// live in this single module (G5).
//
// Classification (the suite maps it to markers):
//   D3D12_LOAD_ABSENT    -> d3d12/dxgi missing -> SKIP (CI stays green)
//   D3D12_LOAD_NO_DEVICE -> D3D12CreateDevice refused every level -> SKIP
//   D3D12_LOAD_ABI       -> entry points missing -> FAIL
//
// Coverage (pilot smoke): DXGI adapter enumeration + first-adapter
// description, and the highest accepted D3D_FEATURE_LEVEL by descending
// D3D12CreateDevice attempts (12_2 -> 11_0).
//
// G2 pin (SPEC.md): sonames + SDK header hashes + IID/vtable slots/struct
// offsets + feature levels + local runtime sample.

module xiom.directx12

extern "C" {
  fn xd12_load_named(d3d12_soname: *UInt8, dxgi_soname: *UInt8) -> Int32;
  fn xd12_load() -> Int32;
  fn xd12_error() -> *UInt8;
  fn xd12_device_probe() -> Int32;
  fn xd12_feature_level() -> Int32;
  fn xd12_adapter_name() -> *UInt8;
  fn xd12_vendor_id() -> UInt32;
  fn xd12_device_id() -> UInt32;
  fn xd12_adapter_count() -> Int32;
  fn xd12_unload();
}

// =========================================================================
// Identity, kinds, feature levels
// =========================================================================

pub const D3D12_SONAME: Str = "d3d12.dll";
pub const DXGI_SONAME: Str = "dxgi.dll";

pub const D3D12_LOAD_ABSENT: Int = 0;    // libraries missing -> SKIP
pub const D3D12_LOAD_NO_DEVICE: Int = 1; // no D3D12 device -> SKIP
pub const D3D12_LOAD_ABI: Int = 2;       // entry points missing -> FAIL

pub const D3D_FEATURE_LEVEL_11_0: Int = 0xb000;
pub const D3D_FEATURE_LEVEL_11_1: Int = 0xb100;
pub const D3D_FEATURE_LEVEL_12_0: Int = 0xc000;
pub const D3D_FEATURE_LEVEL_12_1: Int = 0xc100;
pub const D3D_FEATURE_LEVEL_12_2: Int = 0xc200;

pub type D3d12LoadError = {
  kind: Int;
  message: Str;
}

pub type D3d12Info = {
  feature_level: Int;
  adapter_name: Str;
  vendor_id: Int;
  device_id: Int;
  adapter_count: Int;
}

/// Human name for a D3D_FEATURE_LEVEL value.
/// Complexity: O(1).
pub fn d3d12_feature_level_name(fl: Int) -> Str {
  if fl == 0xc200 { return "12_2"; }
  if fl == 0xc100 { return "12_1"; }
  if fl == 0xc000 { return "12_0"; }
  if fl == 0xb100 { return "11_1"; }
  if fl == 0xb000 { return "11_0"; }
  return "unknown";
}

// =========================================================================
// Probe API (atomic: load -> adapter -> device -> unload)
// =========================================================================

/// Probe explicitly named D3D12/DXGI runtimes.  A bogus soname exercises the
/// ABSENT/SKIP classification deterministically on any host.
/// Complexity: O(load + adapter enumeration + up to 5 device attempts).
pub fn d3d12_probe_named(d3d12_soname: Str, dxgi_soname: Str) -> Result[D3d12Info, D3d12LoadError]
  requires: d3d12_soname.len() > 0
  requires: dxgi_soname.len() > 0
{
  let rc = unsafe { xd12_load_named(d3d12_soname.c_str(), dxgi_soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xd12_error()) };
    if rc == 1 {
      return Err(D3d12LoadError{ kind: D3D12_LOAD_ABSENT; message: msg });
    }
    return Err(D3d12LoadError{ kind: D3D12_LOAD_ABI; message: msg });
  }

  let probe = unsafe { xd12_device_probe() as Int };
  if probe != 0 {
    let msg = unsafe { Str::from_c_str(xd12_error()) };
    unsafe { xd12_unload(); }
    if probe == 2 {
      return Err(D3d12LoadError{ kind: D3D12_LOAD_ABI; message: msg });
    }
    return Err(D3d12LoadError{ kind: D3D12_LOAD_NO_DEVICE; message: msg });
  }

  let fl = unsafe { xd12_feature_level() as Int };
  let name = unsafe { Str::from_c_str(xd12_adapter_name()) };
  let vendor = unsafe { xd12_vendor_id() as Int };
  let device = unsafe { xd12_device_id() as Int };
  let count = unsafe { xd12_adapter_count() as Int };
  unsafe { xd12_unload(); }

  return Ok(D3d12Info{
    feature_level: fl,
    adapter_name: name,
    vendor_id: vendor,
    device_id: device,
    adapter_count: count,
  });
}

/// Probe the default runtimes (`d3d12.dll` + `dxgi.dll`).
/// Complexity: O(load + adapter enumeration + up to 5 device attempts).
pub fn d3d12_probe() -> Result[D3d12Info, D3d12LoadError]
  requires: true
{
  return d3d12_probe_named(D3D12_SONAME, DXGI_SONAME);
}
