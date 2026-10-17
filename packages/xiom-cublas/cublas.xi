// XIOM -- xiom.cublas: NVIDIA cuBLAS (CUDA math library) bindings.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: system-library path -- **nothing from NVIDIA is vendored or
// linked at build time**.  The user's own cuBLAS runtime is loaded at run
// time (`cublas64_13.dll` / `_12` / `_11` / `_10` soname fallbacks) by the
// integer-only C bridge (src/cublas_bridge.c); every entry point is
// resolved with GetProcAddress.  Opaque handles cross the FFI as Int
// values; XIOM never dereferences foreign memory.
//
// The bridge also creates the CUDA context (nvcuda.dll, a system component
// of any NVIDIA driver) and exposes minimal device-memory helpers so the
// typed cuBLAS surface is usable and testable without a separate memory
// package.  These helpers are NOT cuBLAS: they are the driver-side
// scaffolding (`cuMemAlloc_v2` / `cuMemcpyHtoD_v2` / `cuMemcpyDtoH_v2` /
// `cuMemFree_v2`) the same way xiom.cuda's probe uses the driver API.
//
// Classification: cuBLAS module missing or no CUDA device -> SKIP; a
// loaded module with missing entry points or a runtime step failure ->
// FAIL.  The deterministic SKIP path is exercisable on any host with a
// bogus directory in `cublas_load_from`.
//
// cuBLAS is column-major: the typed wrappers pass the caller's arguments
// straight through to the `_v2` ABI (CUBLAS_OP_N/T/C, lda/ldb/ldc).
//
// All `unsafe`/`extern "C"` live in this single module (G5).

module xiom.cublas

extern "C" {
  fn cublasb_load(dir: *UInt8) -> Int;
  fn cublasb_unload(mod: Int) -> Int32;
  fn cublasb_last_kind() -> Int32;
  fn cublasb_last_status() -> Int32;
  fn cublasb_last_driver() -> Int32;
  fn cublasb_last_f32() -> Float32;
  fn cublasb_last_f64() -> Float64;

  fn cublasb_create(mod: Int) -> Int;
  fn cublasb_destroy(h: Int) -> Int32;
  fn cublasb_get_version(h: Int) -> Int32;
  fn cublasb_set_stream(h: Int, stream: Int) -> Int32;

  fn cublasb_sgemm(h: Int, transa: Int32, transb: Int32, m: Int32, n: Int32,
                   k: Int32, alpha: Float32, a: Int, lda: Int32, b: Int,
                   ldb: Int32, beta: Float32, c: Int, ldc: Int32) -> Int32;
  fn cublasb_dgemm(h: Int, transa: Int32, transb: Int32, m: Int32, n: Int32,
                   k: Int32, alpha: Float64, a: Int, lda: Int32, b: Int,
                   ldb: Int32, beta: Float64, c: Int, ldc: Int32) -> Int32;
  fn cublasb_saxpy(h: Int, n: Int32, alpha: Float32, x: Int, incx: Int32,
                   y: Int, incy: Int32) -> Int32;
  fn cublasb_daxpy(h: Int, n: Int32, alpha: Float64, x: Int, incx: Int32,
                   y: Int, incy: Int32) -> Int32;
  fn cublasb_sdot(h: Int, n: Int32, x: Int, incx: Int32, y: Int,
                  incy: Int32) -> Int32;
  fn cublasb_ddot(h: Int, n: Int32, x: Int, incx: Int32, y: Int,
                  incy: Int32) -> Int32;
  fn cublasb_sscal(h: Int, n: Int32, alpha: Float32, x: Int, incx: Int32) -> Int32;
  fn cublasb_dscal(h: Int, n: Int32, alpha: Float64, x: Int, incx: Int32) -> Int32;
  fn cublasb_snrm2(h: Int, n: Int32, x: Int, incx: Int32) -> Int32;
  fn cublasb_dnrm2(h: Int, n: Int32, x: Int, incx: Int32) -> Int32;
  fn cublasb_sgemv(h: Int, trans: Int32, m: Int32, n: Int32, alpha: Float32,
                   a: Int, lda: Int32, x: Int, incx: Int32, beta: Float32,
                   y: Int, incy: Int32) -> Int32;
  fn cublasb_dgemv(h: Int, trans: Int32, m: Int32, n: Int32, alpha: Float64,
                   a: Int, lda: Int32, x: Int, incx: Int32, beta: Float64,
                   y: Int, incy: Int32) -> Int32;

  fn cublasb_dev_alloc(bytes: Int) -> Int;
  fn cublasb_dev_free(p: Int) -> Int32;
  fn cublasb_dev_upload_f32(p: Int, src: *Float32, count: Int) -> Int32;
  fn cublasb_dev_download_f32(p: Int, dst: *Float32, count: Int) -> Int32;
  fn cublasb_dev_upload_f64(p: Int, src: *Float64, count: Int) -> Int32;
  fn cublasb_dev_download_f64(p: Int, dst: *Float64, count: Int) -> Int32;
}

// ---- classification ------------------------------------------------------

/// No cuBLAS module could be found (loader absent) -> typed SKIP.
pub const CUBLAS_LOAD_ABSENT: Int = 0;
/// A module opened but required entry points are missing -> FAIL (ABI).
pub const CUBLAS_LOAD_ABI: Int = 1;
/// No CUDA driver or no CUDA device -> typed SKIP.
pub const CUBLAS_LOAD_NO_DEVICE: Int = 2;
/// Context creation or another runtime step failed -> FAIL.
pub const CUBLAS_LOAD_RUNTIME: Int = 3;

// ---- cuBLAS constants (cublas_api.h, pinned 12.9.2.10) -------------------

pub const CUBLAS_OP_N: Int = 0;
pub const CUBLAS_OP_T: Int = 1;
pub const CUBLAS_OP_C: Int = 2;

pub const CUBLAS_STATUS_SUCCESS: Int = 0;
pub const CUBLAS_STATUS_NOT_INITIALIZED: Int = 1;
pub const CUBLAS_STATUS_ALLOC_FAILED: Int = 3;
pub const CUBLAS_STATUS_INVALID_VALUE: Int = 7;
pub const CUBLAS_STATUS_ARCH_MISMATCH: Int = 8;
pub const CUBLAS_STATUS_MAPPING_ERROR: Int = 11;
pub const CUBLAS_STATUS_EXECUTION_FAILED: Int = 13;
pub const CUBLAS_STATUS_INTERNAL_ERROR: Int = 14;
pub const CUBLAS_STATUS_NOT_SUPPORTED: Int = 15;
pub const CUBLAS_STATUS_LICENSE_ERROR: Int = 16;

/// Runtime soname candidates, newest first (the bridge tries them in order).
pub const CUBLAS_DLL_13: Str = "cublas64_13.dll";
pub const CUBLAS_DLL_12: Str = "cublas64_12.dll";
pub const CUBLAS_DLL_11: Str = "cublas64_11.dll";
pub const CUBLAS_DLL_10: Str = "cublas64_10.dll";

// ---- types ---------------------------------------------------------------

/// Flat loader/runtime error (G3 typed errors).
pub type CublasError = {
  kind: Int;   // CUBLAS_LOAD_*
  code: Int;   // cuBLAS status, or CUDA driver error for device helpers
  message: Str;
}

/// A loaded cuBLAS module (opaque HMODULE as Int).
pub type CublasLibrary = {
  h: Int;
}

/// A cuBLAS handle created by `cublas_create` (opaque pointer as Int).
pub type CublasHandle = {
  h: Int;
}

/// An opaque device-memory address (CUdeviceptr as Int).
pub type CublasDevicePtr = {
  p: Int;
}

// ---- loader --------------------------------------------------------------

/// Load the user's cuBLAS runtime: `XIOM_CUBLAS_DIR` when set, else the OS
/// module search (bare sonames).  Err(CUBLAS_LOAD_ABSENT / _NO_DEVICE) is
/// the typed SKIP path.  Complexity: O(load).
pub fn cublas_load() -> Result[CublasLibrary, CublasError]
  requires: true
{
  let h = unsafe { cublasb_load(0 as *UInt8) };
  if h == 0 {
    let kind = unsafe { cublasb_last_kind() } as Int;
    return Err(cublas_classify(kind, "cuBLAS runtime not found"));
  }
  return Ok(CublasLibrary{ h: h });
}

/// Load from an explicit directory (strict: no bare-name fallback, so an
/// absent directory is a deterministic CUBLAS_LOAD_ABSENT on every host).
/// Complexity: O(load).
pub fn cublas_load_from(dir: Str) -> Result[CublasLibrary, CublasError]
  requires: dir.len() > 0
{
  let h = unsafe { cublasb_load(dir.c_str()) };
  if h == 0 {
    let kind = unsafe { cublasb_last_kind() } as Int;
    return Err(cublas_classify(kind, dir + ": cuBLAS runtime not found"));
  }
  return Ok(CublasLibrary{ h: h });
}

/// Unload the module and release the bridge-owned CUDA context.  Handles
/// must be destroyed first.  Complexity: O(unload).
pub fn cublas_unload(lib: &CublasLibrary) -> Result[Unit, CublasError]
  requires: lib.h != 0
{
  let rc = unsafe { cublasb_unload(lib.h) } as Int;
  if rc != 0 {
    return Err(CublasError{ kind: CUBLAS_LOAD_RUNTIME; code: rc;
                            message: "cuBLAS module handle mismatch"; });
  }
  return Ok({});
}

// ---- handle lifecycle ----------------------------------------------------

/// Create a cuBLAS handle (`cublasCreate_v2`) on the bridge-owned context.
/// Complexity: O(create).
pub fn cublas_create(lib: &CublasLibrary) -> Result[CublasHandle, CublasError]
  requires: lib.h != 0
{
  let h = unsafe { cublasb_create(lib.h) };
  if h == 0 {
    let st = unsafe { cublasb_last_status() } as Int;
    return Err(cublas_status_error(st));
  }
  return Ok(CublasHandle{ h: h });
}

/// Destroy a cuBLAS handle (`cublasDestroy_v2`).
/// Complexity: O(destroy).
pub fn cublas_destroy(h: &CublasHandle) -> Result[Unit, CublasError]
  requires: h.h != 0
{
  let rc = unsafe { cublasb_destroy(h.h) } as Int;
  if rc != CUBLAS_STATUS_SUCCESS {
    return Err(cublas_status_error(rc));
  }
  return Ok({});
}

/// cuBLAS library version (`cublasGetVersion_v2`, e.g. 120902).
/// Complexity: O(1).
pub fn cublas_get_version(h: &CublasHandle) -> Result[Int, CublasError]
  requires: h.h != 0
{
  let v = unsafe { cublasb_get_version(h.h) } as Int;
  if v < 0 {
    let st = unsafe { cublasb_last_status() } as Int;
    return Err(cublas_status_error(st));
  }
  return Ok(v);
}

/// Bind a CUDA stream (`cublasSetStream_v2`); 0 selects the default stream.
/// Complexity: O(1).
pub fn cublas_set_stream(h: &CublasHandle, stream: Int) -> Result[Unit, CublasError]
  requires: h.h != 0
{
  let rc = unsafe { cublasb_set_stream(h.h, stream) } as Int;
  if rc != CUBLAS_STATUS_SUCCESS {
    return Err(cublas_status_error(rc));
  }
  return Ok({});
}

// ---- BLAS level 3 --------------------------------------------------------

/// C = alpha * op(A) * op(B) + beta * C (single precision, column-major).
/// Complexity: O(m*n*k).
pub fn cublas_sgemm(h: &CublasHandle, transa: Int, transb: Int, m: Int, n: Int,
                    k: Int, alpha: Float32, a: &CublasDevicePtr, lda: Int,
                    b: &CublasDevicePtr, ldb: Int, beta: Float32,
                    c: &CublasDevicePtr, ldc: Int) -> Result[Unit, CublasError]
  requires: h.h != 0
  requires: m > 0 && n > 0 && k > 0
{
  let rc = unsafe {
    cublasb_sgemm(h.h, transa as Int32, transb as Int32, m as Int32, n as Int32,
                  k as Int32, alpha, a.p, lda as Int32, b.p, ldb as Int32,
                  beta, c.p, ldc as Int32)
  } as Int;
  if rc != CUBLAS_STATUS_SUCCESS {
    return Err(cublas_status_error(rc));
  }
  return Ok({});
}

/// C = alpha * op(A) * op(B) + beta * C (double precision, column-major).
/// Complexity: O(m*n*k).
pub fn cublas_dgemm(h: &CublasHandle, transa: Int, transb: Int, m: Int, n: Int,
                    k: Int, alpha: Float64, a: &CublasDevicePtr, lda: Int,
                    b: &CublasDevicePtr, ldb: Int, beta: Float64,
                    c: &CublasDevicePtr, ldc: Int) -> Result[Unit, CublasError]
  requires: h.h != 0
  requires: m > 0 && n > 0 && k > 0
{
  let rc = unsafe {
    cublasb_dgemm(h.h, transa as Int32, transb as Int32, m as Int32, n as Int32,
                  k as Int32, alpha, a.p, lda as Int32, b.p, ldb as Int32,
                  beta, c.p, ldc as Int32)
  } as Int;
  if rc != CUBLAS_STATUS_SUCCESS {
    return Err(cublas_status_error(rc));
  }
  return Ok({});
}

// ---- BLAS level 1 --------------------------------------------------------

/// y = alpha * x + y (single precision).
/// Complexity: O(n).
pub fn cublas_saxpy(h: &CublasHandle, n: Int, alpha: Float32,
                    x: &CublasDevicePtr, incx: Int, y: &CublasDevicePtr,
                    incy: Int) -> Result[Unit, CublasError]
  requires: h.h != 0
  requires: n > 0
{
  let rc = unsafe {
    cublasb_saxpy(h.h, n as Int32, alpha, x.p, incx as Int32, y.p, incy as Int32)
  } as Int;
  if rc != CUBLAS_STATUS_SUCCESS {
    return Err(cublas_status_error(rc));
  }
  return Ok({});
}

/// y = alpha * x + y (double precision).
/// Complexity: O(n).
pub fn cublas_daxpy(h: &CublasHandle, n: Int, alpha: Float64,
                    x: &CublasDevicePtr, incx: Int, y: &CublasDevicePtr,
                    incy: Int) -> Result[Unit, CublasError]
  requires: h.h != 0
  requires: n > 0
{
  let rc = unsafe {
    cublasb_daxpy(h.h, n as Int32, alpha, x.p, incx as Int32, y.p, incy as Int32)
  } as Int;
  if rc != CUBLAS_STATUS_SUCCESS {
    return Err(cublas_status_error(rc));
  }
  return Ok({});
}

/// Dot product of x and y (single precision).
/// Complexity: O(n).
pub fn cublas_sdot(h: &CublasHandle, n: Int, x: &CublasDevicePtr, incx: Int,
                   y: &CublasDevicePtr, incy: Int) -> Result[Float32, CublasError]
  requires: h.h != 0
  requires: n > 0
{
  let rc = unsafe {
    cublasb_sdot(h.h, n as Int32, x.p, incx as Int32, y.p, incy as Int32)
  } as Int;
  if rc != CUBLAS_STATUS_SUCCESS {
    return Err(cublas_status_error(rc));
  }
  return Ok(unsafe { cublasb_last_f32() });
}

/// Dot product of x and y (double precision).
/// Complexity: O(n).
pub fn cublas_ddot(h: &CublasHandle, n: Int, x: &CublasDevicePtr, incx: Int,
                   y: &CublasDevicePtr, incy: Int) -> Result[Float64, CublasError]
  requires: h.h != 0
  requires: n > 0
{
  let rc = unsafe {
    cublasb_ddot(h.h, n as Int32, x.p, incx as Int32, y.p, incy as Int32)
  } as Int;
  if rc != CUBLAS_STATUS_SUCCESS {
    return Err(cublas_status_error(rc));
  }
  return Ok(unsafe { cublasb_last_f64() });
}

/// x = alpha * x (single precision).
/// Complexity: O(n).
pub fn cublas_sscal(h: &CublasHandle, n: Int, alpha: Float32,
                    x: &CublasDevicePtr, incx: Int) -> Result[Unit, CublasError]
  requires: h.h != 0
  requires: n > 0
{
  let rc = unsafe {
    cublasb_sscal(h.h, n as Int32, alpha, x.p, incx as Int32)
  } as Int;
  if rc != CUBLAS_STATUS_SUCCESS {
    return Err(cublas_status_error(rc));
  }
  return Ok({});
}

/// x = alpha * x (double precision).
/// Complexity: O(n).
pub fn cublas_dscal(h: &CublasHandle, n: Int, alpha: Float64,
                    x: &CublasDevicePtr, incx: Int) -> Result[Unit, CublasError]
  requires: h.h != 0
  requires: n > 0
{
  let rc = unsafe {
    cublasb_dscal(h.h, n as Int32, alpha, x.p, incx as Int32)
  } as Int;
  if rc != CUBLAS_STATUS_SUCCESS {
    return Err(cublas_status_error(rc));
  }
  return Ok({});
}

/// Euclidean norm of x (single precision).
/// Complexity: O(n).
pub fn cublas_snrm2(h: &CublasHandle, n: Int, x: &CublasDevicePtr,
                    incx: Int) -> Result[Float32, CublasError]
  requires: h.h != 0
  requires: n > 0
{
  let rc = unsafe {
    cublasb_snrm2(h.h, n as Int32, x.p, incx as Int32)
  } as Int;
  if rc != CUBLAS_STATUS_SUCCESS {
    return Err(cublas_status_error(rc));
  }
  return Ok(unsafe { cublasb_last_f32() });
}

/// Euclidean norm of x (double precision).
/// Complexity: O(n).
pub fn cublas_dnrm2(h: &CublasHandle, n: Int, x: &CublasDevicePtr,
                    incx: Int) -> Result[Float64, CublasError]
  requires: h.h != 0
  requires: n > 0
{
  let rc = unsafe {
    cublasb_dnrm2(h.h, n as Int32, x.p, incx as Int32)
  } as Int;
  if rc != CUBLAS_STATUS_SUCCESS {
    return Err(cublas_status_error(rc));
  }
  return Ok(unsafe { cublasb_last_f64() });
}

// ---- BLAS level 2 --------------------------------------------------------

/// y = alpha * op(A) * x + beta * y (single precision, column-major).
/// Complexity: O(m*n).
pub fn cublas_sgemv(h: &CublasHandle, trans: Int, m: Int, n: Int,
                    alpha: Float32, a: &CublasDevicePtr, lda: Int,
                    x: &CublasDevicePtr, incx: Int, beta: Float32,
                    y: &CublasDevicePtr, incy: Int) -> Result[Unit, CublasError]
  requires: h.h != 0
  requires: m > 0 && n > 0
{
  let rc = unsafe {
    cublasb_sgemv(h.h, trans as Int32, m as Int32, n as Int32, alpha, a.p,
                  lda as Int32, x.p, incx as Int32, beta, y.p, incy as Int32)
  } as Int;
  if rc != CUBLAS_STATUS_SUCCESS {
    return Err(cublas_status_error(rc));
  }
  return Ok({});
}

/// y = alpha * op(A) * x + beta * y (double precision, column-major).
/// Complexity: O(m*n).
pub fn cublas_dgemv(h: &CublasHandle, trans: Int, m: Int, n: Int,
                    alpha: Float64, a: &CublasDevicePtr, lda: Int,
                    x: &CublasDevicePtr, incx: Int, beta: Float64,
                    y: &CublasDevicePtr, incy: Int) -> Result[Unit, CublasError]
  requires: h.h != 0
  requires: m > 0 && n > 0
{
  let rc = unsafe {
    cublasb_dgemv(h.h, trans as Int32, m as Int32, n as Int32, alpha, a.p,
                  lda as Int32, x.p, incx as Int32, beta, y.p, incy as Int32)
  } as Int;
  if rc != CUBLAS_STATUS_SUCCESS {
    return Err(cublas_status_error(rc));
  }
  return Ok({});
}

// ---- device-memory helpers (driver API) ---------------------------------

/// Allocate `bytes` of device memory (cuMemAlloc_v2).
/// Complexity: O(alloc).
pub fn cublas_buffer_alloc(bytes: Int) -> Result[CublasDevicePtr, CublasError]
  requires: bytes > 0
{
  let p = unsafe { cublasb_dev_alloc(bytes) };
  if p == 0 {
    return Err(cublas_device_error());
  }
  return Ok(CublasDevicePtr{ p: p });
}

/// Free device memory allocated by `cublas_buffer_alloc`.
/// Complexity: O(free).
pub fn cublas_buffer_free(p: &CublasDevicePtr) -> Result[Unit, CublasError]
  requires: p.p != 0
{
  let rc = unsafe { cublasb_dev_free(p.p) } as Int;
  if rc != 0 {
    return Err(cublas_device_error());
  }
  return Ok({});
}

/// Host -> device copy of a Float32 span (count = data.len()).
/// Complexity: O(n).
pub fn cublas_buffer_upload_f32(p: &CublasDevicePtr, data: &Vec[Float32])
  -> Result[Unit, CublasError]
  requires: p.p != 0
  requires: data.len() > 0
{
  let rc = unsafe {
    cublasb_dev_upload_f32(p.p, &data[0], data.len())
  } as Int;
  if rc != 0 {
    return Err(cublas_device_error());
  }
  return Ok({});
}

/// Device -> host copy into a pre-sized Float32 span.
/// Complexity: O(n).
pub fn cublas_buffer_download_f32(p: &CublasDevicePtr, out: &mut Vec[Float32])
  -> Result[Unit, CublasError]
  requires: p.p != 0
  requires: out.len() > 0
{
  let rc = unsafe {
    cublasb_dev_download_f32(p.p, &mut out[0], out.len())
  } as Int;
  if rc != 0 {
    return Err(cublas_device_error());
  }
  return Ok({});
}

/// Host -> device copy of a Float64 span (count = data.len()).
/// Complexity: O(n).
pub fn cublas_buffer_upload_f64(p: &CublasDevicePtr, data: &Vec[Float64])
  -> Result[Unit, CublasError]
  requires: p.p != 0
  requires: data.len() > 0
{
  let rc = unsafe {
    cublasb_dev_upload_f64(p.p, &data[0], data.len())
  } as Int;
  if rc != 0 {
    return Err(cublas_device_error());
  }
  return Ok({});
}

/// Device -> host copy into a pre-sized Float64 span.
/// Complexity: O(n).
pub fn cublas_buffer_download_f64(p: &CublasDevicePtr, out: &mut Vec[Float64])
  -> Result[Unit, CublasError]
  requires: p.p != 0
  requires: out.len() > 0
{
  let rc = unsafe {
    cublasb_dev_download_f64(p.p, &mut out[0], out.len())
  } as Int;
  if rc != 0 {
    return Err(cublas_device_error());
  }
  return Ok({});
}

// ---- status text ---------------------------------------------------------

/// Human-readable cuBLAS status name (0..16; unknown codes are printed).
/// Complexity: O(1).
pub fn cublas_status_name(code: Int) -> Str
  requires: true
{
  if code == 0 { return "CUBLAS_STATUS_SUCCESS"; }
  if code == 1 { return "CUBLAS_STATUS_NOT_INITIALIZED"; }
  if code == 3 { return "CUBLAS_STATUS_ALLOC_FAILED"; }
  if code == 7 { return "CUBLAS_STATUS_INVALID_VALUE"; }
  if code == 8 { return "CUBLAS_STATUS_ARCH_MISMATCH"; }
  if code == 11 { return "CUBLAS_STATUS_MAPPING_ERROR"; }
  if code == 13 { return "CUBLAS_STATUS_EXECUTION_FAILED"; }
  if code == 14 { return "CUBLAS_STATUS_INTERNAL_ERROR"; }
  if code == 15 { return "CUBLAS_STATUS_NOT_SUPPORTED"; }
  if code == 16 { return "CUBLAS_STATUS_LICENSE_ERROR"; }
  return "cuBLAS status " + cublas_i2s(code);
}

// ---- internals -----------------------------------------------------------

fn cublas_classify(kind: Int, msg: Str) -> CublasError
  requires: true
{
  if kind == CUBLAS_LOAD_ABSENT {
    return CublasError{ kind: kind; code: 0;
                        message: msg + " (module absent -- SKIP)"; };
  }
  if kind == CUBLAS_LOAD_NO_DEVICE {
    return CublasError{ kind: kind; code: 0;
                        message: "no CUDA driver/device (SKIP)"; };
  }
  if kind == CUBLAS_LOAD_ABI {
    return CublasError{ kind: kind; code: 0;
                        message: msg + " (required entry points missing)"; };
  }
  let d = unsafe { cublasb_last_driver() } as Int;
  return CublasError{ kind: CUBLAS_LOAD_RUNTIME; code: d;
                      message: msg + " (CUDA driver error " + cublas_i2s(d) + ")"; };
}

fn cublas_status_error(code: Int) -> CublasError
  requires: code >= 0
{
  return CublasError{ kind: CUBLAS_LOAD_RUNTIME; code: code;
                      message: cublas_status_name(code); };
}

fn cublas_device_error() -> CublasError
  requires: true
{
  let d = unsafe { cublasb_last_driver() } as Int;
  return CublasError{ kind: CUBLAS_LOAD_RUNTIME; code: d;
                      message: "CUDA driver error " + cublas_i2s(d); };
}

fn cublas_i2s(n: Int) -> Str
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
