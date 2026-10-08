// XIOM -- xiom.directx11: Direct3D 11 / DXGI capability probe via dynamic loader.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: dynamic loader + capability probe (same pattern as xiom.opengl /
// xiom.vulkan / xiom.dxc). No link-time dependency and no SDK headers:
// `src/d3d11_probe.c` declares the minimal ABI locally (entry points, IIDs,
// vtable slots, struct offsets verified against the pinned Windows SDK
// headers) and resolves `d3d11.dll` + `dxgi.dll` at runtime. All XIOM
// `unsafe`/`extern` live in this single module (G5).
//
// Classification (the suite maps it to markers):
//   D3D11_LOAD_ABSENT    -> d3d11/dxgi missing -> SKIP (CI stays green)
//   D3D11_LOAD_NO_DEVICE -> D3D11CreateDevice(HARDWARE) failed -> SKIP
//   D3D11_LOAD_ABI       -> entry points missing -> FAIL
//
// Coverage (pilot smoke): hardware device creation, returned feature level,
// DXGI adapter count + first-adapter description (name/vendor/device id).
//
// G2 pin (SPEC.md): sonames + SDK header hashes (d3d11.h/dxgi.h/d3dcommon.h)
// + IIDs/vtable slots/struct offsets + local runtime sample.

module xiom.directx11

extern "C" {
  fn xd3d_load_named(d3d11_soname: *UInt8, dxgi_soname: *UInt8) -> Int32;
  fn xd3d_load() -> Int32;
  fn xd3d_error() -> *UInt8;
  fn xd3d_device_probe() -> Int32;
  fn xd3d_feature_level() -> Int32;
  fn xd3d_adapter_name() -> *UInt8;
  fn xd3d_vendor_id() -> UInt32;
  fn xd3d_device_id() -> UInt32;
  fn xd3d_adapter_count() -> Int32;
  fn xd3d_unload();
}

// =========================================================================
// Identity, kinds, feature levels
// =========================================================================

pub const D3D11_SONAME: Str = "d3d11.dll";
pub const DXGI_SONAME: Str = "dxgi.dll";

pub const D3D11_LOAD_ABSENT: Int = 0;    // libraries missing -> SKIP
pub const D3D11_LOAD_NO_DEVICE: Int = 1; // no hardware device -> SKIP
pub const D3D11_LOAD_ABI: Int = 2;       // entry points missing -> FAIL

pub const D3D_FEATURE_LEVEL_1_0: Int = 0x1000;
pub const D3D_FEATURE_LEVEL_9_1: Int = 0x9100;
pub const D3D_FEATURE_LEVEL_9_2: Int = 0x9200;
pub const D3D_FEATURE_LEVEL_9_3: Int = 0x9300;
pub const D3D_FEATURE_LEVEL_10_0: Int = 0xa000;
pub const D3D_FEATURE_LEVEL_10_1: Int = 0xa100;
pub const D3D_FEATURE_LEVEL_11_0: Int = 0xb000;
pub const D3D_FEATURE_LEVEL_11_1: Int = 0xb100;

pub type D3d11LoadError = {
  kind: Int;
  message: Str;
}

pub type D3d11Info = {
  feature_level: Int;
  adapter_name: Str;
  vendor_id: Int;
  device_id: Int;
  adapter_count: Int;
}

/// Human name for a D3D_FEATURE_LEVEL value.
/// Complexity: O(1).
pub fn d3d11_feature_level_name(fl: Int) -> Str {
  if fl == 0xb100 { return "11_1"; }
  if fl == 0xb000 { return "11_0"; }
  if fl == 0xa100 { return "10_1"; }
  if fl == 0xa000 { return "10_0"; }
  if fl == 0x9300 { return "9_3"; }
  if fl == 0x9200 { return "9_2"; }
  if fl == 0x9100 { return "9_1"; }
  if fl == 0x1000 { return "1_0"; }
  return "unknown";
}

// =========================================================================
// Probe API (atomic: load -> device -> adapter -> unload)
// =========================================================================

/// Probe explicitly named D3D11/DXGI runtimes.  A bogus soname exercises the
/// ABSENT/SKIP classification deterministically on any host.
/// Complexity: O(load + device creation + adapter enumeration).
pub fn d3d11_probe_named(d3d11_soname: Str, dxgi_soname: Str) -> Result[D3d11Info, D3d11LoadError]
  requires: d3d11_soname.len() > 0
  requires: dxgi_soname.len() > 0
{
  let rc = unsafe { xd3d_load_named(d3d11_soname.c_str(), dxgi_soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xd3d_error()) };
    if rc == 1 {
      return Err(D3d11LoadError{ kind: D3D11_LOAD_ABSENT; message: msg });
    }
    return Err(D3d11LoadError{ kind: D3D11_LOAD_ABI; message: msg });
  }

  let probe = unsafe { xd3d_device_probe() as Int };
  if probe != 0 {
    let msg = unsafe { Str::from_c_str(xd3d_error()) };
    unsafe { xd3d_unload(); }
    if probe == 2 {
      return Err(D3d11LoadError{ kind: D3D11_LOAD_ABI; message: msg });
    }
    return Err(D3d11LoadError{ kind: D3D11_LOAD_NO_DEVICE; message: msg });
  }

  let fl = unsafe { xd3d_feature_level() as Int };
  let name = unsafe { Str::from_c_str(xd3d_adapter_name()) };
  let vendor = unsafe { xd3d_vendor_id() as Int };
  let device = unsafe { xd3d_device_id() as Int };
  let count = unsafe { xd3d_adapter_count() as Int };
  unsafe { xd3d_unload(); }

  return Ok(D3d11Info{
    feature_level: fl,
    adapter_name: name,
    vendor_id: vendor,
    device_id: device,
    adapter_count: count,
  });
}

/// Probe the default runtimes (`d3d11.dll` + `dxgi.dll`).
/// Complexity: O(load + device creation + adapter enumeration).
pub fn d3d11_probe() -> Result[D3d11Info, D3d11LoadError]
  requires: true
{
  return d3d11_probe_named(D3D11_SONAME, DXGI_SONAME);
}
