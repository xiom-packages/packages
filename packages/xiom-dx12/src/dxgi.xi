// XIOM -- xiom.dx12.dxgi: DXGI factory/adapter/WARP/swapchain bindings.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: runtime-loaded DXGI probe backed by the vendored bridge
// `src/dxgi_probe.c` (compiled with `--c-source`, see port.args.json).  The
// bridge resolves `dxgi.dll` at RUNTIME and drives the COM objects through
// the vtable ABI pinned from the Windows SDK 10.0.26100.0 headers
// (PROVENANCE.md):
//
//   stage 1 symbols   -- CreateDXGIFactory2 resolved
//   stage 2 factory   -- CreateDXGIFactory2(IID_IDXGIFactory2) + adapter
//                        enumeration (EnumAdapters1) + WARP adapter
//                        (IDXGIFactory4::EnumWarpAdapter)
//   stage 3 device    -- D3D12 device on the WARP adapter (adapter-less
//                        hosts reach a real device)
//   stage 4 swapchain -- hidden Win32 window + DIRECT queue + BGRA8/FIFO
//                        swapchain (CreateSwapChainForHwnd) + GetBuffer +
//                        GetDesc1 + Present
//
// Classification (the suite maps it to markers):
//   DXGI_LOAD_ABSENT  -> SKIP (dxgi.dll missing; CI stays green)
//   DXGI_LOAD_ABI     -> FAIL (library present but exports missing)
//   DXGI_LOAD_FACTORY -> FAIL (factory creation failed)
//   DXGI_LOAD_OK      -> the factory is live (adapter_count/additional
//                        stages may still be reported per-call)
//
// The full generated IDXGI* surface lives in `xiom.dx12.dxgi_iface_01..06`
// and `xiom.dx12.dxgi_functions`; struct metadata for DXGI_* shapes ships in
// `xiom.dx12.struct_meta_*` (DXGI_SIZEOF_* / DXGI_OFF_*).

module xiom.dx12.dxgi

extern "C" {
  fn xd12_load_dxgi_named(soname: *UInt8) -> Int32;
  fn xd12_load_dxgi() -> Int32;
  fn xd12_dxgi_error() -> *UInt8;
  fn xd12_resolve_dxgi(name: *UInt8) -> *UInt8;
  fn xd12_dxgi_iid(which: Int32, dst16: *UInt8) -> Int32;
  fn xd12_dxgi_factory_probe(flags: UInt32) -> Int32;
  fn xd12_dxgi_factory_ptr() -> Int;
  fn xd12_dxgi_adapter_count() -> Int32;
  fn xd12_dxgi_enum_adapter(index: Int32) -> Int;
  fn xd12_dxgi_warp_adapter() -> Int;
  fn xd12_dxgi_warp_ok() -> Int32;
  fn xd12_dxgi_warp_device_probe() -> Int32;
  fn xd12_swapchain_probe(w: Int32, h: Int32) -> Int32;
  fn xd12_swapchain_hr() -> Int32;
  fn xd12_swapchain_present_hr() -> Int32;
  fn xd12_swapchain_buffer_hr() -> Int32;
  fn xd12_swapchain_getdesc_hr() -> Int32;
  fn xd12_swapchain_desc_width() -> Int32;
  fn xd12_swapchain_desc_height() -> Int32;
  fn xd12_swapchain_desc_format() -> Int32;
  fn xd12_dxgi_unload();
}

// =========================================================================
// Identity and pinned ABI constants (Windows SDK 10.0.26100.0 headers)
// =========================================================================

pub const DXGI_SONAME: Str = "dxgi.dll";

pub const DXGI_LOAD_OK: Int = 0;       // factory live
pub const DXGI_LOAD_ABSENT: Int = 1;   // runtime missing -> SKIP
pub const DXGI_LOAD_ABI: Int = 2;      // exports missing -> FAIL
pub const DXGI_LOAD_FACTORY: Int = 3;  // factory creation failed -> FAIL

// DXGI_FORMAT
pub const DXGI_FORMAT_B8G8R8A8_UNORM: Int = 0x57;
pub const DXGI_FORMAT_R8G8B8A8_UNORM: Int = 0x1C;
// DXGI_SWAP_EFFECT
pub const DXGI_SWAP_EFFECT_DISCARD: Int = 0;
pub const DXGI_SWAP_EFFECT_FLIP_DISCARD: Int = 4;
// DXGI_USAGE
pub const DXGI_USAGE_RENDER_TARGET_OUTPUT: Int = 0x20;

/// SWAPCHAIN probe statuses (xd12_swapchain_probe return codes).
pub const DXGI_SWAPCHAIN_OK: Int = 0;
pub const DXGI_SWAPCHAIN_NO_DEVICE: Int = 1;
pub const DXGI_SWAPCHAIN_FAILED: Int = 2;
pub const DXGI_SWAPCHAIN_ABI: Int = 3;

pub type DxgiProbeError = {
  kind: Int;
  message: Str;
}

/// Live factory state: how many adapters EnumAdapters1 reported and whether
/// the WARP adapter (IDXGIFactory4) is available.
pub type DxgiFactoryInfo = {
  adapter_count: Int;
  warp: Bool;
}

// =========================================================================
// Factory API
// =========================================================================

/// Probe an explicitly named DXGI runtime (bogus name -> deterministic
/// ABSENT classification even on hosts that have DXGI).
/// Complexity: O(load + factory + adapter enumeration).
pub fn dxgi_probe_named(soname: Str) -> Result[DxgiFactoryInfo, DxgiProbeError]
  requires: soname.len() > 0
{
  let rc = unsafe { xd12_load_dxgi_named(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xd12_dxgi_error()) };
    if rc == 1 {
      return Err(DxgiProbeError{ kind: DXGI_LOAD_ABSENT; message: msg });
    }
    return Err(DxgiProbeError{ kind: DXGI_LOAD_ABI; message: msg });
  }
  let fr = unsafe { xd12_dxgi_factory_probe(0 as UInt32) as Int };
  if fr != 0 {
    let msg = unsafe { Str::from_c_str(xd12_dxgi_error()) };
    unsafe { xd12_dxgi_unload(); }
    if fr == 2 {
      return Err(DxgiProbeError{ kind: DXGI_LOAD_ABI; message: msg });
    }
    return Err(DxgiProbeError{ kind: DXGI_LOAD_FACTORY; message: msg });
  }
  let n = unsafe { xd12_dxgi_adapter_count() as Int };
  let warp = (unsafe { xd12_dxgi_warp_ok() as Int }) == 1;
  unsafe { xd12_dxgi_unload(); }
  return Ok(DxgiFactoryInfo{ adapter_count: n, warp: warp });
}

/// Probe the default DXGI runtime (`dxgi.dll`).
/// Complexity: O(load + factory + adapter enumeration).
pub fn dxgi_probe() -> Result[DxgiFactoryInfo, DxgiProbeError]
  requires: true
{
  return dxgi_probe_named(DXGI_SONAME);
}

/// Load dxgi.dll + create the factory and KEEP it live (the factory feeds
/// `dxgi_enum_adapter`/`dxgi_warp_adapter`/`dxgi_swapchain_probe`).  Close
/// with `dxgi_unload`.  Same classification as `dxgi_probe`.
/// Complexity: O(load + factory + adapter enumeration).
pub fn dxgi_open_factory() -> Result[DxgiFactoryInfo, DxgiProbeError]
  requires: true
{
  let rc = unsafe { xd12_load_dxgi() as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xd12_dxgi_error()) };
    if rc == 1 {
      return Err(DxgiProbeError{ kind: DXGI_LOAD_ABSENT; message: msg });
    }
    return Err(DxgiProbeError{ kind: DXGI_LOAD_ABI; message: msg });
  }
  let fr = unsafe { xd12_dxgi_factory_probe(0 as UInt32) as Int };
  if fr != 0 {
    let msg = unsafe { Str::from_c_str(xd12_dxgi_error()) };
    unsafe { xd12_dxgi_unload(); }
    if fr == 2 {
      return Err(DxgiProbeError{ kind: DXGI_LOAD_ABI; message: msg });
    }
    return Err(DxgiProbeError{ kind: DXGI_LOAD_FACTORY; message: msg });
  }
  let n = unsafe { xd12_dxgi_adapter_count() as Int };
  let warp = (unsafe { xd12_dxgi_warp_ok() as Int }) == 1;
  return Ok(DxgiFactoryInfo{ adapter_count: n, warp: warp });
}

/// The live `IDXGIFactory2*` (0 when none).
/// Complexity: O(1).
pub fn dxgi_factory_ptr() -> Int
  requires: true
{
  unsafe { return xd12_dxgi_factory_ptr(); }
}

/// `IDXGIFactory2::EnumAdapters1(index)` -> owned `IDXGIAdapter1*` (0 when
/// out of range).  The caller releases it (`dxgi_object_release`).
/// Complexity: O(1).
pub fn dxgi_enum_adapter(index: Int) -> Int
  requires: index >= 0
{
  unsafe { return xd12_dxgi_enum_adapter(index as Int32); }
}

/// `IDXGIFactory4::EnumWarpAdapter` -> owned `IDXGIAdapter1*` (0 = none).
/// Complexity: O(1).
pub fn dxgi_warp_adapter() -> Int
  requires: true
{
  unsafe { return xd12_dxgi_warp_adapter(); }
}

/// Create + release an `ID3D12Device` on the WARP adapter (adapter-less
/// hosts reach a real device stage): 0 = ok, 1 = no WARP adapter,
/// 2 = creation failed (never silent).
/// Complexity: O(load + device create + release).
pub fn dxgi_warp_device_probe() -> Int
  requires: true
{
  unsafe { return xd12_dxgi_warp_device_probe() as Int; }
}

/// Copy one of the pinned DXGI IID byte images into `dst16` (16 bytes).
/// 0 IDXGIObject, 1 IDXGIFactory, 2 IDXGIFactory1, 3 IDXGIFactory2,
/// 4 IDXGIFactory3, 5 IDXGIFactory4, 6 IDXGIAdapter, 7 IDXGIAdapter1,
/// 8 IDXGIAdapter4, 9 IDXGIDevice, 10 IDXGIOutput, 11 IDXGISwapChain,
/// 12 IDXGISwapChain1, 13 IDXGISwapChain3, 14 IDXGIResource,
/// 15 IDXGISurface.
/// Complexity: O(1).
pub fn dxgi_iid(which: Int, dst16: *UInt8) -> Int
  requires: true
{
  unsafe { return xd12_dxgi_iid(which as Int32, dst16) as Int; }
}

// =========================================================================
// Hidden-window swapchain probe (BGRA8 + FLIP_DISCARD/FIFO)
// =========================================================================

/// Create a hidden window + DIRECT queue + BGRA8/FIFO swapchain on the
/// DX12 device (`d3d12.dll` path; `dx12_open_device` must have run), then
/// GetBuffer(0) + GetDesc1 + Present(1, 0).  Returns a
/// `DXGI_SWAPCHAIN_*` status; read the individual HRESULTs/getters after.
/// Complexity: O(window + queue + swapchain + present).
pub fn dxgi_swapchain_probe(width: Int, height: Int) -> Int
  requires: width > 0 && height > 0
{
  unsafe { return xd12_swapchain_probe(width as Int32, height as Int32) as Int; }
}

/// CreateSwapChainForHwnd HRESULT from the last probe (-1 = not run).
/// Complexity: O(1).
pub fn dxgi_swapchain_hr() -> Int
  requires: true
{
  unsafe { return xd12_swapchain_hr() as Int; }
}

/// Present(1, 0) HRESULT from the last probe (-1 = not run); a hidden
/// window may legally return DXGI_STATUS_OCCLUDED (0x087A0001).
/// Complexity: O(1).
pub fn dxgi_swapchain_present_hr() -> Int
  requires: true
{
  unsafe { return xd12_swapchain_present_hr() as Int; }
}

/// GetBuffer(0) HRESULT from the last probe (-1 = not run).
/// Complexity: O(1).
pub fn dxgi_swapchain_buffer_hr() -> Int
  requires: true
{
  unsafe { return xd12_swapchain_buffer_hr() as Int; }
}

/// GetDesc1 status (0 = read; -1 = not run).
/// Complexity: O(1).
pub fn dxgi_swapchain_getdesc_hr() -> Int
  requires: true
{
  unsafe { return xd12_swapchain_getdesc_hr() as Int; }
}

/// Width reported by the swapchain's `GetDesc1` (-1 = not run).
/// Complexity: O(1).
pub fn dxgi_swapchain_desc_width() -> Int
  requires: true
{
  unsafe { return xd12_swapchain_desc_width() as Int; }
}

/// Height reported by the swapchain's `GetDesc1` (-1 = not run).
/// Complexity: O(1).
pub fn dxgi_swapchain_desc_height() -> Int
  requires: true
{
  unsafe { return xd12_swapchain_desc_height() as Int; }
}

/// Format reported by the swapchain's `GetDesc1` (-1 = not run).
/// Complexity: O(1).
pub fn dxgi_swapchain_desc_format() -> Int
  requires: true
{
  unsafe { return xd12_swapchain_desc_format() as Int; }
}

/// Release the factory + runtime handles held by the probe.  Safe when
/// nothing is loaded.
/// Complexity: O(1).
pub fn dxgi_unload()
  requires: true
{
  unsafe { xd12_dxgi_unload(); }
}
