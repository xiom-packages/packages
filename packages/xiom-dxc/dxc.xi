// XIOM -- xiom.dxc: DirectX Shader Compiler probe via dynamic loader.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: dynamic loader + capability probe (same pattern as xiom.opengl /
// xiom.vulkan). The package does NOT link DXC at build time and requires no
// dxcapi.h: `src/dxc_probe.c` declares the minimal COM ABI locally (GUIDs +
// vtable slots, verified against the pinned header) and drives
// `dxcompiler.dll` through raw vtable pointers. All XIOM `unsafe`/`extern`
// live in this single module (G5).
//
// Classification (the suite maps it to markers):
//   DXC_LOAD_ABSENT  -> compiler missing -> SKIP (CI stays green)
//   DXC_LOAD_ABI     -> DxcCreateInstance missing / instance refused -> FAIL
//   DXC_COMPILE_FAILED -> present but a shell-level probe compile failed -> FAIL
//
// Coverage (pilot smoke): load, create IDxcCompiler3, compile a trivial
// ps_6_0 pixel shader to a DXIL object blob and report its size.  A `dxil.dll`
// signing companion is optional for this probe (unsigned DXIL is fine).
//
// G2 pin (SPEC.md): soname `dxcompiler.dll` + the pinned `dxcapi.h` hash +
// the GUID/vtable ABI + local DLL sample.

module xiom.dxc

extern "C" {
  fn xdxc_load_named(soname: *UInt8) -> Int32;
  fn xdxc_load() -> Int32;
  fn xdxc_error() -> *UInt8;
  fn xdxc_instance_probe() -> Int32;
  fn xdxc_compile_probe() -> Int32;
  fn xdxc_object_size() -> Int32;
  fn xdxc_unload();
}

// =========================================================================
// Identity, kinds
// =========================================================================

pub const DXC_SONAME: Str = "dxcompiler.dll";

pub const DXC_LOAD_ABSENT: Int = 0;      // compiler missing -> SKIP
pub const DXC_LOAD_ABI: Int = 1;         // entry points/instance failed -> FAIL
pub const DXC_COMPILE_FAILED: Int = 2;   // probe compile failed -> FAIL

pub type DxcLoadError = {
  kind: Int;
  message: Str;
}

pub type DxcInfo = {
  object_size: Int;
}

// =========================================================================
// Probe API (atomic: load -> instance -> compile -> unload)
// =========================================================================

/// Probe an explicitly named DXC runtime.  A bogus soname exercises the
/// ABSENT/SKIP classification deterministically on any host.
/// Complexity: O(load + COM instance + one shader compile).
pub fn dxc_probe_named(soname: Str) -> Result[DxcInfo, DxcLoadError]
  requires: soname.len() > 0
{
  let rc = unsafe { xdxc_load_named(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xdxc_error()) };
    if rc == 1 {
      return Err(DxcLoadError{ kind: DXC_LOAD_ABSENT; message: msg });
    }
    return Err(DxcLoadError{ kind: DXC_LOAD_ABI; message: msg });
  }

  let inst = unsafe { xdxc_instance_probe() as Int };
  if inst != 0 {
    let msg = unsafe { Str::from_c_str(xdxc_error()) };
    unsafe { xdxc_unload(); }
    return Err(DxcLoadError{ kind: DXC_LOAD_ABI; message: msg });
  }

  let comp = unsafe { xdxc_compile_probe() as Int };
  if comp != 0 {
    let msg = unsafe { Str::from_c_str(xdxc_error()) };
    unsafe { xdxc_unload(); }
    if comp == 2 {
      return Err(DxcLoadError{ kind: DXC_LOAD_ABI; message: msg });
    }
    return Err(DxcLoadError{ kind: DXC_COMPILE_FAILED; message: msg });
  }

  let size = unsafe { xdxc_object_size() as Int };
  unsafe { xdxc_unload(); }
  return Ok(DxcInfo{ object_size: size });
}

/// Probe the default runtime (`dxcompiler.dll`).
/// Complexity: O(load + COM instance + one shader compile).
pub fn dxc_probe() -> Result[DxcInfo, DxcLoadError]
  requires: true
{
  return dxc_probe_named(DXC_SONAME);
}
