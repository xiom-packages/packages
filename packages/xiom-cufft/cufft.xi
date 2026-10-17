// XIOM -- xiom.cufft: NVIDIA cuFFT (CUDA FFT library) bindings.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: system-library path -- **nothing from NVIDIA is vendored or
// linked at build time**.  The user's own cuFFT runtime is loaded at run
// time (`cufft64_12.dll` / `_11` / `_10` soname fallbacks) by the
// integer-only C bridge (src/cufft_bridge.c); every entry point is
// resolved with GetProcAddress.  Opaque plans cross the FFI as Int values;
// XIOM never dereferences foreign memory.
//
// The bridge also creates the CUDA context (nvcuda.dll) and exposes
// minimal device-memory helpers so plans can be executed and tested
// without a separate memory package.
//
// Classification: cuFFT module missing or no CUDA device -> SKIP; a
// loaded module with missing entry points or a runtime step failure ->
// FAIL.  The deterministic SKIP path is exercisable on any host with a
// bogus directory in `cufft_load_from`.
//
// Transform types: R2C/C2R (single real <-> interleaved complex),
// C2C, D2Z/Z2D (double real <-> interleaved complex), Z2Z.  Directions:
// CUFFT_FORWARD (-1) / CUFFT_INVERSE (+1); cuFFT transforms are
// unnormalized (scale by 1/N after an inverse pass).
//
// All `unsafe`/`extern "C"` live in this single module (G5).

module xiom.cufft

extern "C" {
  fn cufftb_load(dir: *UInt8) -> Int;
  fn cufftb_unload(mod: Int) -> Int32;
  fn cufftb_last_kind() -> Int32;
  fn cufftb_last_status() -> Int32;
  fn cufftb_last_driver() -> Int32;

  fn cufftb_plan1d(mod: Int, nx: Int32, fft_type: Int32, batch: Int32) -> Int;
  fn cufftb_plan2d(mod: Int, nx: Int32, ny: Int32, fft_type: Int32) -> Int;
  fn cufftb_destroy(plan: Int) -> Int32;
  fn cufftb_set_stream(plan: Int, stream: Int) -> Int32;
  fn cufftb_get_version() -> Int32;
  fn cufftb_estimate1d(nx: Int32, fft_type: Int32, batch: Int32) -> Int;
  fn cufftb_estimate2d(nx: Int32, ny: Int32, fft_type: Int32) -> Int;

  fn cufftb_exec_r2c(plan: Int, idata: Int, odata: Int) -> Int32;
  fn cufftb_exec_c2r(plan: Int, idata: Int, odata: Int) -> Int32;
  fn cufftb_exec_z2z(plan: Int, idata: Int, odata: Int, direction: Int32) -> Int32;
  fn cufftb_exec_d2z(plan: Int, idata: Int, odata: Int) -> Int32;
  fn cufftb_exec_z2d(plan: Int, idata: Int, odata: Int) -> Int32;

  fn cufftb_dev_alloc(bytes: Int) -> Int;
  fn cufftb_dev_free(p: Int) -> Int32;
  fn cufftb_dev_upload_f32(p: Int, src: *Float32, count: Int) -> Int32;
  fn cufftb_dev_download_f32(p: Int, dst: *Float32, count: Int) -> Int32;
  fn cufftb_dev_upload_f64(p: Int, src: *Float64, count: Int) -> Int32;
  fn cufftb_dev_download_f64(p: Int, dst: *Float64, count: Int) -> Int32;
}

// ---- classification ------------------------------------------------------

/// No cuFFT module could be found (loader absent) -> typed SKIP.
pub const CUFFT_LOAD_ABSENT: Int = 0;
/// A module opened but required entry points are missing -> FAIL (ABI).
pub const CUFFT_LOAD_ABI: Int = 1;
/// No CUDA driver or no CUDA device -> typed SKIP.
pub const CUFFT_LOAD_NO_DEVICE: Int = 2;
/// Context creation or another runtime step failed -> FAIL.
pub const CUFFT_LOAD_RUNTIME: Int = 3;

// ---- cuFFT constants (cufft.h, pinned 11.4.1.4) --------------------------

pub const CUFFT_R2C: Int = 42;
pub const CUFFT_C2R: Int = 44;
pub const CUFFT_C2C: Int = 41;
pub const CUFFT_D2Z: Int = 106;
pub const CUFFT_Z2D: Int = 108;
pub const CUFFT_Z2Z: Int = 105;

pub const CUFFT_FORWARD: Int = -1;
pub const CUFFT_INVERSE: Int = 1;

pub const CUFFT_SUCCESS: Int = 0;
pub const CUFFT_INVALID_PLAN: Int = 1;
pub const CUFFT_ALLOC_FAILED: Int = 2;
pub const CUFFT_INVALID_TYPE: Int = 3;
pub const CUFFT_INVALID_VALUE: Int = 4;
pub const CUFFT_INTERNAL_ERROR: Int = 5;
pub const CUFFT_EXEC_FAILED: Int = 6;
pub const CUFFT_SETUP_FAILED: Int = 7;
pub const CUFFT_INVALID_SIZE: Int = 8;
pub const CUFFT_UNALIGNED_DATA: Int = 9;
pub const CUFFT_INCOMPLETE_PARAMETER_LIST: Int = 10;
pub const CUFFT_INVALID_DEVICE: Int = 11;
pub const CUFFT_PARSE_ERROR: Int = 12;
pub const CUFFT_NO_WORKSPACE: Int = 13;
pub const CUFFT_NOT_IMPLEMENTED: Int = 14;
pub const CUFFT_LICENSE_ERROR: Int = 15;
pub const CUFFT_NOT_SUPPORTED: Int = 16;

/// Runtime soname candidates, newest first (the bridge tries them in order).
pub const CUFFT_DLL_12: Str = "cufft64_12.dll";
pub const CUFFT_DLL_11: Str = "cufft64_11.dll";
pub const CUFFT_DLL_10: Str = "cufft64_10.dll";

// ---- types ---------------------------------------------------------------

/// Flat loader/runtime error (G3 typed errors).
pub type CufftError = {
  kind: Int;   // CUFFT_LOAD_*
  code: Int;   // cufftResult, or CUDA driver error for device helpers
  message: Str;
}

/// A loaded cuFFT module (opaque HMODULE as Int).
pub type CufftLibrary = {
  h: Int;
}

/// A cuFFT plan created by `cufft_plan1d` / `cufft_plan2d`.
pub type CufftPlan = {
  p: Int;
}

/// An opaque device-memory address (CUdeviceptr as Int).
pub type CufftDevicePtr = {
  p: Int;
}

// ---- loader --------------------------------------------------------------

/// Load the user's cuFFT runtime: `XIOM_CUFFT_DIR` when set, else the OS
/// module search (bare sonames).  Err(CUFFT_LOAD_ABSENT / _NO_DEVICE) is
/// the typed SKIP path.  Complexity: O(load).
pub fn cufft_load() -> Result[CufftLibrary, CufftError]
  requires: true
{
  let h = unsafe { cufftb_load(0 as *UInt8) };
  if h == 0 {
    let kind = unsafe { cufftb_last_kind() } as Int;
    return Err(cufft_classify(kind, "cuFFT runtime not found"));
  }
  return Ok(CufftLibrary{ h: h });
}

/// Load from an explicit directory (strict: no bare-name fallback, so an
/// absent directory is a deterministic CUFFT_LOAD_ABSENT on every host).
/// Complexity: O(load).
pub fn cufft_load_from(dir: Str) -> Result[CufftLibrary, CufftError]
  requires: dir.len() > 0
{
  let h = unsafe { cufftb_load(dir.c_str()) };
  if h == 0 {
    let kind = unsafe { cufftb_last_kind() } as Int;
    return Err(cufft_classify(kind, dir + ": cuFFT runtime not found"));
  }
  return Ok(CufftLibrary{ h: h });
}

/// Unload the module and release the bridge-owned CUDA context.  Plans
/// must be destroyed first.  Complexity: O(unload).
pub fn cufft_unload(lib: &CufftLibrary) -> Result[Unit, CufftError]
  requires: lib.h != 0
{
  let rc = unsafe { cufftb_unload(lib.h) } as Int;
  if rc != 0 {
    return Err(CufftError{ kind: CUFFT_LOAD_RUNTIME; code: rc;
                           message: "cuFFT module handle mismatch"; });
  }
  return Ok({});
}

// ---- plans ---------------------------------------------------------------

/// Create a 1D plan (`cufftPlan1d`); type is CUFFT_R2C/C2R/C2C/D2Z/Z2D/Z2Z.
/// Complexity: O(plan).
pub fn cufft_plan1d(lib: &CufftLibrary, nx: Int, fft_type: Int,
                    batch: Int) -> Result[CufftPlan, CufftError]
  requires: lib.h != 0
  requires: nx > 0
  requires: batch > 0
{
  let p = unsafe {
    cufftb_plan1d(lib.h, nx as Int32, fft_type as Int32, batch as Int32)
  };
  if p < 0 {
    return Err(cufft_status_error(unsafe { cufftb_last_status() } as Int));
  }
  return Ok(CufftPlan{ p: p });
}

/// Create a 2D plan (`cufftPlan2d`) of nx by ny elements.
/// Complexity: O(plan).
pub fn cufft_plan2d(lib: &CufftLibrary, nx: Int, ny: Int,
                    fft_type: Int) -> Result[CufftPlan, CufftError]
  requires: lib.h != 0
  requires: nx > 0
  requires: ny > 0
{
  let p = unsafe {
    cufftb_plan2d(lib.h, nx as Int32, ny as Int32, fft_type as Int32)
  };
  if p < 0 {
    return Err(cufft_status_error(unsafe { cufftb_last_status() } as Int));
  }
  return Ok(CufftPlan{ p: p });
}

/// Destroy a plan (`cufftDestroy`).
/// Complexity: O(destroy).
pub fn cufft_destroy(plan: &CufftPlan) -> Result[Unit, CufftError]
  requires: plan.p >= 0
{
  let rc = unsafe { cufftb_destroy(plan.p) } as Int;
  if rc != CUFFT_SUCCESS {
    return Err(cufft_status_error(rc));
  }
  return Ok({});
}

/// Bind a CUDA stream (`cufftSetStream`); 0 selects the default stream.
/// Complexity: O(1).
pub fn cufft_set_stream(plan: &CufftPlan, stream: Int) -> Result[Unit, CufftError]
  requires: plan.p >= 0
{
  let rc = unsafe { cufftb_set_stream(plan.p, stream) } as Int;
  if rc != CUFFT_SUCCESS {
    return Err(cufft_status_error(rc));
  }
  return Ok({});
}

/// cuFFT library version (`cufftGetVersion`); Ok(0) when the entry point
/// is not exported by an older runtime.  Complexity: O(1).
pub fn cufft_get_version(lib: &CufftLibrary) -> Result[Int, CufftError]
  requires: lib.h != 0
{
  let v = unsafe { cufftb_get_version() } as Int;
  if v < 0 {
    let st = unsafe { cufftb_last_status() } as Int;
    if st == 0 { return Ok(0); }
    return Err(cufft_status_error(st));
  }
  return Ok(v);
}

/// Estimated workspace bytes for a 1D plan (`cufftEstimate1d`).
/// Complexity: O(1).
pub fn cufft_estimate1d(lib: &CufftLibrary, nx: Int, fft_type: Int,
                        batch: Int) -> Result[Int, CufftError]
  requires: lib.h != 0
  requires: nx > 0
  requires: batch > 0
{
  let n = unsafe {
    cufftb_estimate1d(nx as Int32, fft_type as Int32, batch as Int32)
  };
  if n < 0 {
    return Err(cufft_status_error(unsafe { cufftb_last_status() } as Int));
  }
  return Ok(n);
}

/// Estimated workspace bytes for a 2D plan (`cufftEstimate2d`).
/// Complexity: O(1).
pub fn cufft_estimate2d(lib: &CufftLibrary, nx: Int, ny: Int,
                        fft_type: Int) -> Result[Int, CufftError]
  requires: lib.h != 0
  requires: nx > 0
  requires: ny > 0
{
  let n = unsafe {
    cufftb_estimate2d(nx as Int32, ny as Int32, fft_type as Int32)
  };
  if n < 0 {
    return Err(cufft_status_error(unsafe { cufftb_last_status() } as Int));
  }
  return Ok(n);
}

// ---- execution -----------------------------------------------------------

/// Execute a real -> complex transform (interleaved complex output).
/// Complexity: O(n log n).
pub fn cufft_exec_r2c(plan: &CufftPlan, idata: &CufftDevicePtr,
                      odata: &CufftDevicePtr) -> Result[Unit, CufftError]
  requires: plan.p >= 0
  requires: idata.p != 0
  requires: odata.p != 0
{
  let rc = unsafe { cufftb_exec_r2c(plan.p, idata.p, odata.p) } as Int;
  if rc != CUFFT_SUCCESS {
    return Err(cufft_status_error(rc));
  }
  return Ok({});
}

/// Execute a complex -> real transform (interleaved complex input).
/// Complexity: O(n log n).
pub fn cufft_exec_c2r(plan: &CufftPlan, idata: &CufftDevicePtr,
                      odata: &CufftDevicePtr) -> Result[Unit, CufftError]
  requires: plan.p >= 0
  requires: idata.p != 0
  requires: odata.p != 0
{
  let rc = unsafe { cufftb_exec_c2r(plan.p, idata.p, odata.p) } as Int;
  if rc != CUFFT_SUCCESS {
    return Err(cufft_status_error(rc));
  }
  return Ok({});
}

/// Execute a double-complex -> double-complex transform.
/// Complexity: O(n log n).
pub fn cufft_exec_z2z(plan: &CufftPlan, idata: &CufftDevicePtr,
                      odata: &CufftDevicePtr, direction: Int)
  -> Result[Unit, CufftError]
  requires: plan.p >= 0
  requires: idata.p != 0
  requires: odata.p != 0
{
  let rc = unsafe {
    cufftb_exec_z2z(plan.p, idata.p, odata.p, direction as Int32)
  } as Int;
  if rc != CUFFT_SUCCESS {
    return Err(cufft_status_error(rc));
  }
  return Ok({});
}

/// Execute a double real -> double-complex transform.
/// Complexity: O(n log n).
pub fn cufft_exec_d2z(plan: &CufftPlan, idata: &CufftDevicePtr,
                      odata: &CufftDevicePtr) -> Result[Unit, CufftError]
  requires: plan.p >= 0
  requires: idata.p != 0
  requires: odata.p != 0
{
  let rc = unsafe { cufftb_exec_d2z(plan.p, idata.p, odata.p) } as Int;
  if rc != CUFFT_SUCCESS {
    return Err(cufft_status_error(rc));
  }
  return Ok({});
}

/// Execute a double-complex -> double real transform.
/// Complexity: O(n log n).
pub fn cufft_exec_z2d(plan: &CufftPlan, idata: &CufftDevicePtr,
                      odata: &CufftDevicePtr) -> Result[Unit, CufftError]
  requires: plan.p >= 0
  requires: idata.p != 0
  requires: odata.p != 0
{
  let rc = unsafe { cufftb_exec_z2d(plan.p, idata.p, odata.p) } as Int;
  if rc != CUFFT_SUCCESS {
    return Err(cufft_status_error(rc));
  }
  return Ok({});
}

// ---- device-memory helpers (driver API) ---------------------------------

/// Allocate `bytes` of device memory (cuMemAlloc_v2).
/// Complexity: O(alloc).
pub fn cufft_buffer_alloc(bytes: Int) -> Result[CufftDevicePtr, CufftError]
  requires: bytes > 0
{
  let p = unsafe { cufftb_dev_alloc(bytes) };
  if p == 0 {
    return Err(cufft_device_error());
  }
  return Ok(CufftDevicePtr{ p: p });
}

/// Free device memory allocated by `cufft_buffer_alloc`.
/// Complexity: O(free).
pub fn cufft_buffer_free(p: &CufftDevicePtr) -> Result[Unit, CufftError]
  requires: p.p != 0
{
  let rc = unsafe { cufftb_dev_free(p.p) } as Int;
  if rc != 0 {
    return Err(cufft_device_error());
  }
  return Ok({});
}

/// Host -> device copy of a Float32 span (count = data.len()).
/// Complexity: O(n).
pub fn cufft_buffer_upload_f32(p: &CufftDevicePtr, data: &Vec[Float32])
  -> Result[Unit, CufftError]
  requires: p.p != 0
  requires: data.len() > 0
{
  let rc = unsafe { cufftb_dev_upload_f32(p.p, &data[0], data.len()) } as Int;
  if rc != 0 {
    return Err(cufft_device_error());
  }
  return Ok({});
}

/// Device -> host copy into a pre-sized Float32 span.
/// Complexity: O(n).
pub fn cufft_buffer_download_f32(p: &CufftDevicePtr, out: &mut Vec[Float32])
  -> Result[Unit, CufftError]
  requires: p.p != 0
  requires: out.len() > 0
{
  let rc = unsafe { cufftb_dev_download_f32(p.p, &mut out[0], out.len()) } as Int;
  if rc != 0 {
    return Err(cufft_device_error());
  }
  return Ok({});
}

/// Host -> device copy of a Float64 span (count = data.len()).
/// Complexity: O(n).
pub fn cufft_buffer_upload_f64(p: &CufftDevicePtr, data: &Vec[Float64])
  -> Result[Unit, CufftError]
  requires: p.p != 0
  requires: data.len() > 0
{
  let rc = unsafe { cufftb_dev_upload_f64(p.p, &data[0], data.len()) } as Int;
  if rc != 0 {
    return Err(cufft_device_error());
  }
  return Ok({});
}

/// Device -> host copy into a pre-sized Float64 span.
/// Complexity: O(n).
pub fn cufft_buffer_download_f64(p: &CufftDevicePtr, out: &mut Vec[Float64])
  -> Result[Unit, CufftError]
  requires: p.p != 0
  requires: out.len() > 0
{
  let rc = unsafe { cufftb_dev_download_f64(p.p, &mut out[0], out.len()) } as Int;
  if rc != 0 {
    return Err(cufft_device_error());
  }
  return Ok({});
}

// ---- status text ---------------------------------------------------------

/// Human-readable cuFFT result name (0..16; unknown codes are printed).
/// Complexity: O(1).
pub fn cufft_status_name(code: Int) -> Str
  requires: true
{
  if code == 0 { return "CUFFT_SUCCESS"; }
  if code == 1 { return "CUFFT_INVALID_PLAN"; }
  if code == 2 { return "CUFFT_ALLOC_FAILED"; }
  if code == 3 { return "CUFFT_INVALID_TYPE"; }
  if code == 4 { return "CUFFT_INVALID_VALUE"; }
  if code == 5 { return "CUFFT_INTERNAL_ERROR"; }
  if code == 6 { return "CUFFT_EXEC_FAILED"; }
  if code == 7 { return "CUFFT_SETUP_FAILED"; }
  if code == 8 { return "CUFFT_INVALID_SIZE"; }
  if code == 9 { return "CUFFT_UNALIGNED_DATA"; }
  if code == 10 { return "CUFFT_INCOMPLETE_PARAMETER_LIST"; }
  if code == 11 { return "CUFFT_INVALID_DEVICE"; }
  if code == 12 { return "CUFFT_PARSE_ERROR"; }
  if code == 13 { return "CUFFT_NO_WORKSPACE"; }
  if code == 14 { return "CUFFT_NOT_IMPLEMENTED"; }
  if code == 15 { return "CUFFT_LICENSE_ERROR"; }
  if code == 16 { return "CUFFT_NOT_SUPPORTED"; }
  return "cuFFT result " + cufft_i2s(code);
}

// ---- internals -----------------------------------------------------------

fn cufft_classify(kind: Int, msg: Str) -> CufftError
  requires: true
{
  if kind == CUFFT_LOAD_ABSENT {
    return CufftError{ kind: kind; code: 0;
                       message: msg + " (module absent -- SKIP)"; };
  }
  if kind == CUFFT_LOAD_NO_DEVICE {
    return CufftError{ kind: kind; code: 0;
                       message: "no CUDA driver/device (SKIP)"; };
  }
  if kind == CUFFT_LOAD_ABI {
    return CufftError{ kind: kind; code: 0;
                       message: msg + " (required entry points missing)"; };
  }
  let d = unsafe { cufftb_last_driver() } as Int;
  return CufftError{ kind: CUFFT_LOAD_RUNTIME; code: d;
                     message: msg + " (CUDA driver error " + cufft_i2s(d) + ")"; };
}

fn cufft_status_error(code: Int) -> CufftError
  requires: code >= 0
{
  return CufftError{ kind: CUFFT_LOAD_RUNTIME; code: code;
                     message: cufft_status_name(code); };
}

fn cufft_device_error() -> CufftError
  requires: true
{
  let d = unsafe { cufftb_last_driver() } as Int;
  return CufftError{ kind: CUFFT_LOAD_RUNTIME; code: d;
                     message: "CUDA driver error " + cufft_i2s(d); };
}

fn cufft_i2s(n: Int) -> Str
  requires: true
{
  if n == 0 { return "0"; }
  var neg = false;
  var val = n;
  if val < 0 {
    neg = true;
    val = 0 - val;
  }
  var buf = "";
  while val > 0 {
    let digit = val % 10;
    val = val / 10;
    if digit == 0 { buf = "0" + buf; }
    elif digit == 1 { buf = "1" + buf; }
    elif digit == 2 { buf = "2" + buf; }
    elif digit == 3 { buf = "3" + buf; }
    elif digit == 4 { buf = "4" + buf; }
    elif digit == 5 { buf = "5" + buf; }
    elif digit == 6 { buf = "6" + buf; }
    elif digit == 7 { buf = "7" + buf; }
    elif digit == 8 { buf = "8" + buf; }
    elif digit == 9 { buf = "9" + buf; }
  }
  if neg { return "-" + buf; }
  return buf;
}
