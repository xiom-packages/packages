// XIOM -- xiom.cusparse: NVIDIA cuSPARSE (CUDA sparse math library) bindings.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: system-library path -- **nothing from NVIDIA is vendored or
// linked at build time**.  The user's own cuSPARSE runtime is loaded at
// run time (`cusparse64_13.dll` / `_12` / `_11` / `_10` soname fallbacks)
// by the integer-only C bridge (src/cusparse_bridge.c); every entry point
// is resolved with GetProcAddress.  Opaque handles/descriptors cross the
// FFI as Int values; XIOM never dereferences foreign memory.
//
// The bridge also creates the CUDA context (nvcuda.dll) and exposes
// minimal device-memory helpers (Float32/Float64/Int32 spans) so the
// SpMV/SpMM surface is usable and testable without a separate memory
// package.
//
// DECLARED surface (0.1.0): handle lifecycle, setStream, version, the
// legacy mat descriptor (create/destroy/type/index-base) plus the generic
// CSR / dense-vector / dense-matrix descriptors, and SpMV + SpMM with the
// buffer-size query and external-buffer execution forms.  Scalar alpha/
// beta are passed by value to the typed wrappers and marshalled to the
// computeType (CUDA_R_32F / CUDA_R_64F).
//
// Classification: cuSPARSE module missing or no CUDA device -> SKIP; a
// loaded module with missing entry points or a runtime step failure ->
// FAIL.  The deterministic SKIP path is exercisable on any host with a
// bogus directory in `cusparse_load_from`.
//
// All `unsafe`/`extern "C"` live in this single module (G5).

module xiom.cusparse

extern "C" {
  fn cusparseb_load(dir: *UInt8) -> Int;
  fn cusparseb_unload(mod: Int) -> Int32;
  fn cusparseb_last_kind() -> Int32;
  fn cusparseb_last_status() -> Int32;
  fn cusparseb_last_driver() -> Int32;

  fn cusparseb_create(mod: Int) -> Int;
  fn cusparseb_destroy(h: Int) -> Int32;
  fn cusparseb_get_version(h: Int) -> Int32;
  fn cusparseb_set_stream(h: Int, stream: Int) -> Int32;

  fn cusparseb_create_mat_descr() -> Int;
  fn cusparseb_destroy_mat_descr(d: Int) -> Int32;
  fn cusparseb_set_mat_type(d: Int, mat_type: Int32) -> Int32;
  fn cusparseb_set_mat_index_base(d: Int, index_base: Int32) -> Int32;

  fn cusparseb_create_csr(rows: Int, cols: Int, nnz: Int,
                          row_offsets: Int, col_indices: Int, values: Int,
                          row_off_type: Int32, col_ind_type: Int32,
                          index_base: Int32, value_type: Int32) -> Int;
  fn cusparseb_create_dnvec(size: Int, values: Int, value_type: Int32) -> Int;
  fn cusparseb_create_dnmat(rows: Int, cols: Int, ld: Int, values: Int,
                            value_type: Int32, order: Int32) -> Int;
  fn cusparseb_destroy_spmat(d: Int) -> Int32;
  fn cusparseb_destroy_dnvec(d: Int) -> Int32;
  fn cusparseb_destroy_dnmat(d: Int) -> Int32;

  fn cusparseb_spmv_buffer_size(h: Int, op: Int32, alpha: Float64, sp: Int,
                                x: Int, beta: Float64, y: Int,
                                compute_type: Int32, alg: Int32) -> Int;
  fn cusparseb_spmv(h: Int, op: Int32, alpha: Float64, sp: Int, x: Int,
                    beta: Float64, y: Int, compute_type: Int32, alg: Int32,
                    external_buffer: Int) -> Int32;
  fn cusparseb_spmm_buffer_size(h: Int, op_a: Int32, op_b: Int32, alpha: Float64,
                                sp: Int, b: Int, beta: Float64, c: Int,
                                compute_type: Int32, alg: Int32) -> Int;
  fn cusparseb_spmm(h: Int, op_a: Int32, op_b: Int32, alpha: Float64, sp: Int,
                    b: Int, beta: Float64, c: Int, compute_type: Int32,
                    alg: Int32, external_buffer: Int) -> Int32;

  fn cusparseb_dev_alloc(bytes: Int) -> Int;
  fn cusparseb_dev_free(p: Int) -> Int32;
  fn cusparseb_dev_upload_f32(p: Int, src: *Float32, count: Int) -> Int32;
  fn cusparseb_dev_download_f32(p: Int, dst: *Float32, count: Int) -> Int32;
  fn cusparseb_dev_upload_f64(p: Int, src: *Float64, count: Int) -> Int32;
  fn cusparseb_dev_download_f64(p: Int, dst: *Float64, count: Int) -> Int32;
  fn cusparseb_dev_upload_i32(p: Int, src: *Int32, count: Int) -> Int32;
  fn cusparseb_dev_download_i32(p: Int, dst: *Int32, count: Int) -> Int32;
}

// ---- classification ------------------------------------------------------

/// No cuSPARSE module could be found (loader absent) -> typed SKIP.
pub const CUSPARSE_LOAD_ABSENT: Int = 0;
/// A module opened but required entry points are missing -> FAIL (ABI).
pub const CUSPARSE_LOAD_ABI: Int = 1;
/// No CUDA driver or no CUDA device -> typed SKIP.
pub const CUSPARSE_LOAD_NO_DEVICE: Int = 2;
/// Context creation or another runtime step failed -> FAIL.
pub const CUSPARSE_LOAD_RUNTIME: Int = 3;

// ---- cuSPARSE constants (cusparse.h, pinned 12.5.10.65) ------------------

pub const CUSPARSE_STATUS_SUCCESS: Int = 0;
pub const CUSPARSE_STATUS_NOT_INITIALIZED: Int = 1;
pub const CUSPARSE_STATUS_ALLOC_FAILED: Int = 2;
pub const CUSPARSE_STATUS_INVALID_VALUE: Int = 3;
pub const CUSPARSE_STATUS_ARCH_MISMATCH: Int = 4;
pub const CUSPARSE_STATUS_MAPPING_ERROR: Int = 5;
pub const CUSPARSE_STATUS_EXECUTION_FAILED: Int = 6;
pub const CUSPARSE_STATUS_INTERNAL_ERROR: Int = 7;
pub const CUSPARSE_STATUS_MATRIX_TYPE_NOT_SUPPORTED: Int = 8;
pub const CUSPARSE_STATUS_ZERO_PIVOT: Int = 9;
pub const CUSPARSE_STATUS_NOT_SUPPORTED: Int = 10;
pub const CUSPARSE_STATUS_INSUFFICIENT_RESOURCES: Int = 11;

pub const CUSPARSE_MATRIX_TYPE_GENERAL: Int = 0;

pub const CUSPARSE_INDEX_BASE_ZERO: Int = 0;
pub const CUSPARSE_INDEX_BASE_ONE: Int = 1;
pub const CUSPARSE_INDEX_32I: Int = 2;
pub const CUSPARSE_INDEX_64I: Int = 3;

pub const CUSPARSE_OPERATION_NON_TRANSPOSE: Int = 0;
pub const CUSPARSE_OPERATION_TRANSPOSE: Int = 1;
pub const CUSPARSE_OPERATION_CONJUGATE_TRANSPOSE: Int = 2;

pub const CUSPARSE_ORDER_COL: Int = 1;
pub const CUSPARSE_ORDER_ROW: Int = 2;

pub const CUSPARSE_SPMV_ALG_DEFAULT: Int = 0;
pub const CUSPARSE_SPMM_ALG_DEFAULT: Int = 0;
pub const CUSPARSE_SPMM_CSR_ALG1: Int = 4;

pub const CUDA_R_32F: Int = 0;
pub const CUDA_R_64F: Int = 1;

/// Runtime soname candidates, newest first (the bridge tries them in order).
pub const CUSPARSE_DLL_13: Str = "cusparse64_13.dll";
pub const CUSPARSE_DLL_12: Str = "cusparse64_12.dll";
pub const CUSPARSE_DLL_11: Str = "cusparse64_11.dll";
pub const CUSPARSE_DLL_10: Str = "cusparse64_10.dll";

// ---- types ---------------------------------------------------------------

/// Flat loader/runtime error (G3 typed errors).
pub type CusparseError = {
  kind: Int;   // CUSPARSE_LOAD_*
  code: Int;   // cusparseStatus_t, or CUDA driver error for device helpers
  message: Str;
}

/// A loaded cuSPARSE module (opaque HMODULE as Int).
pub type CusparseLibrary = {
  h: Int;
}

/// A cuSPARSE handle (opaque pointer as Int).
pub type CusparseHandle = {
  h: Int;
}

/// The legacy matrix descriptor (cusparseMatDescr_t).
pub type CusparseMatDescr = {
  d: Int;
}

/// A generic CSR sparse-matrix descriptor (cusparseSpMatDescr_t).
pub type CusparseSpMat = {
  d: Int;
}

/// A dense-vector descriptor (cusparseDnVecDescr_t).
pub type CusparseDnVec = {
  d: Int;
}

/// A dense-matrix descriptor (cusparseDnMatDescr_t).
pub type CusparseDnMat = {
  d: Int;
}

/// An opaque device-memory address (CUdeviceptr as Int).
pub type CusparseDevicePtr = {
  p: Int;
}

// ---- loader --------------------------------------------------------------

/// Load the user's cuSPARSE runtime: `XIOM_CUSPARSE_DIR` when set, else the
/// OS module search (bare sonames).  Err(CUSPARSE_LOAD_ABSENT / _NO_DEVICE)
/// is the typed SKIP path.  Complexity: O(load).
pub fn cusparse_load() -> Result[CusparseLibrary, CusparseError]
  requires: true
{
  let h = unsafe { cusparseb_load(0 as *UInt8) };
  if h == 0 {
    let kind = unsafe { cusparseb_last_kind() } as Int;
    return Err(cusparse_classify(kind, "cuSPARSE runtime not found"));
  }
  return Ok(CusparseLibrary{ h: h });
}

/// Load from an explicit directory (strict: no bare-name fallback, so an
/// absent directory is a deterministic CUSPARSE_LOAD_ABSENT on every host).
/// Complexity: O(load).
pub fn cusparse_load_from(dir: Str) -> Result[CusparseLibrary, CusparseError]
  requires: dir.len() > 0
{
  let h = unsafe { cusparseb_load(dir.c_str()) };
  if h == 0 {
    let kind = unsafe { cusparseb_last_kind() } as Int;
    return Err(cusparse_classify(kind, dir + ": cuSPARSE runtime not found"));
  }
  return Ok(CusparseLibrary{ h: h });
}

/// Unload the module and release the bridge-owned CUDA context.  Handles
/// must be destroyed first.  Complexity: O(unload).
pub fn cusparse_unload(lib: &CusparseLibrary) -> Result[Unit, CusparseError]
  requires: lib.h != 0
{
  let rc = unsafe { cusparseb_unload(lib.h) } as Int;
  if rc != 0 {
    return Err(CusparseError{ kind: CUSPARSE_LOAD_RUNTIME; code: rc;
                              message: "cuSPARSE module handle mismatch"; });
  }
  return Ok({});
}

// ---- handle lifecycle ----------------------------------------------------

/// Create a cuSPARSE handle (`cusparseCreate`).
/// Complexity: O(create).
pub fn cusparse_create(lib: &CusparseLibrary) -> Result[CusparseHandle, CusparseError]
  requires: lib.h != 0
{
  let h = unsafe { cusparseb_create(lib.h) };
  if h == 0 {
    return Err(cusparse_status_error(unsafe { cusparseb_last_status() } as Int));
  }
  return Ok(CusparseHandle{ h: h });
}

/// Destroy a cuSPARSE handle (`cusparseDestroy`).
/// Complexity: O(destroy).
pub fn cusparse_destroy(h: &CusparseHandle) -> Result[Unit, CusparseError]
  requires: h.h != 0
{
  let rc = unsafe { cusparseb_destroy(h.h) } as Int;
  if rc != CUSPARSE_STATUS_SUCCESS {
    return Err(cusparse_status_error(rc));
  }
  return Ok({});
}

/// cuSPARSE library version (`cusparseGetVersion`, e.g. 120510).
/// Complexity: O(1).
pub fn cusparse_get_version(h: &CusparseHandle) -> Result[Int, CusparseError]
  requires: h.h != 0
{
  let v = unsafe { cusparseb_get_version(h.h) } as Int;
  if v < 0 {
    return Err(cusparse_status_error(unsafe { cusparseb_last_status() } as Int));
  }
  return Ok(v);
}

/// Bind a CUDA stream (`cusparseSetStream`); 0 selects the default stream.
/// Complexity: O(1).
pub fn cusparse_set_stream(h: &CusparseHandle, stream: Int)
  -> Result[Unit, CusparseError]
  requires: h.h != 0
{
  let rc = unsafe { cusparseb_set_stream(h.h, stream) } as Int;
  if rc != CUSPARSE_STATUS_SUCCESS {
    return Err(cusparse_status_error(rc));
  }
  return Ok({});
}

// ---- legacy matrix descriptor -------------------------------------------

/// Create the legacy matrix descriptor (`cusparseCreateMatDescr`).
/// Complexity: O(1).
pub fn cusparse_create_mat_descr() -> Result[CusparseMatDescr, CusparseError]
  requires: true
{
  let d = unsafe { cusparseb_create_mat_descr() };
  if d == 0 {
    return Err(cusparse_status_error(unsafe { cusparseb_last_status() } as Int));
  }
  return Ok(CusparseMatDescr{ d: d });
}

/// Destroy the legacy matrix descriptor (`cusparseDestroyMatDescr`).
/// Complexity: O(1).
pub fn cusparse_destroy_mat_descr(d: &CusparseMatDescr) -> Result[Unit, CusparseError]
  requires: d.d != 0
{
  let rc = unsafe { cusparseb_destroy_mat_descr(d.d) } as Int;
  if rc != CUSPARSE_STATUS_SUCCESS {
    return Err(cusparse_status_error(rc));
  }
  return Ok({});
}

/// Set the matrix type (`cusparseSetMatType`; GENERAL is 0).
/// Complexity: O(1).
pub fn cusparse_set_mat_type(d: &CusparseMatDescr, mat_type: Int)
  -> Result[Unit, CusparseError]
  requires: d.d != 0
{
  let rc = unsafe { cusparseb_set_mat_type(d.d, mat_type as Int32) } as Int;
  if rc != CUSPARSE_STATUS_SUCCESS {
    return Err(cusparse_status_error(rc));
  }
  return Ok({});
}

/// Set the index base (`cusparseSetMatIndexBase`; ZERO is 0, ONE is 1).
/// Complexity: O(1).
pub fn cusparse_set_mat_index_base(d: &CusparseMatDescr, index_base: Int)
  -> Result[Unit, CusparseError]
  requires: d.d != 0
{
  let rc = unsafe { cusparseb_set_mat_index_base(d.d, index_base as Int32) } as Int;
  if rc != CUSPARSE_STATUS_SUCCESS {
    return Err(cusparse_status_error(rc));
  }
  return Ok({});
}

// ---- generic CSR / dense descriptors ------------------------------------

/// Create a CSR sparse-matrix descriptor over device arrays
/// (`cusparseCreateCsr`).  Index type is CUSPARSE_INDEX_32I/_64I.
/// Complexity: O(1).
pub fn cusparse_create_csr(h: &CusparseHandle, rows: Int, cols: Int, nnz: Int,
                           row_offsets: &CusparseDevicePtr,
                           col_indices: &CusparseDevicePtr,
                           values: &CusparseDevicePtr, row_off_type: Int,
                           col_ind_type: Int, index_base: Int, value_type: Int)
  -> Result[CusparseSpMat, CusparseError]
  requires: h.h != 0
  requires: rows > 0 && cols > 0 && nnz >= 0
  requires: row_offsets.p != 0 && col_indices.p != 0 && values.p != 0
{
  let d = unsafe {
    cusparseb_create_csr(rows, cols, nnz, row_offsets.p, col_indices.p, values.p,
                         row_off_type as Int32, col_ind_type as Int32,
                         index_base as Int32, value_type as Int32)
  };
  if d == 0 {
    return Err(cusparse_status_error(unsafe { cusparseb_last_status() } as Int));
  }
  return Ok(CusparseSpMat{ d: d });
}

/// Create a dense-vector descriptor (`cusparseCreateDnVec`).
/// Complexity: O(1).
pub fn cusparse_create_dnvec(h: &CusparseHandle, size: Int,
                             values: &CusparseDevicePtr, value_type: Int)
  -> Result[CusparseDnVec, CusparseError]
  requires: h.h != 0
  requires: size > 0
  requires: values.p != 0
{
  let d = unsafe {
    cusparseb_create_dnvec(size, values.p, value_type as Int32)
  };
  if d == 0 {
    return Err(cusparse_status_error(unsafe { cusparseb_last_status() } as Int));
  }
  return Ok(CusparseDnVec{ d: d });
}

/// Create a dense-matrix descriptor (`cusparseCreateDnMat`); order is
/// CUSPARSE_ORDER_ROW (2) or CUSPARSE_ORDER_COL (1).
/// Complexity: O(1).
pub fn cusparse_create_dnmat(h: &CusparseHandle, rows: Int, cols: Int, ld: Int,
                             values: &CusparseDevicePtr, value_type: Int,
                             order: Int) -> Result[CusparseDnMat, CusparseError]
  requires: h.h != 0
  requires: rows > 0 && cols > 0 && ld > 0
  requires: values.p != 0
{
  let d = unsafe {
    cusparseb_create_dnmat(rows, cols, ld, values.p, value_type as Int32,
                           order as Int32)
  };
  if d == 0 {
    return Err(cusparse_status_error(unsafe { cusparseb_last_status() } as Int));
  }
  return Ok(CusparseDnMat{ d: d });
}

/// Destroy a CSR descriptor (`cusparseDestroySpMat`).
/// Complexity: O(1).
pub fn cusparse_destroy_spmat(d: &CusparseSpMat) -> Result[Unit, CusparseError]
  requires: d.d != 0
{
  let rc = unsafe { cusparseb_destroy_spmat(d.d) } as Int;
  if rc != CUSPARSE_STATUS_SUCCESS {
    return Err(cusparse_status_error(rc));
  }
  return Ok({});
}

/// Destroy a dense-vector descriptor (`cusparseDestroyDnVec`).
/// Complexity: O(1).
pub fn cusparse_destroy_dnvec(d: &CusparseDnVec) -> Result[Unit, CusparseError]
  requires: d.d != 0
{
  let rc = unsafe { cusparseb_destroy_dnvec(d.d) } as Int;
  if rc != CUSPARSE_STATUS_SUCCESS {
    return Err(cusparse_status_error(rc));
  }
  return Ok({});
}

/// Destroy a dense-matrix descriptor (`cusparseDestroyDnMat`).
/// Complexity: O(1).
pub fn cusparse_destroy_dnmat(d: &CusparseDnMat) -> Result[Unit, CusparseError]
  requires: d.d != 0
{
  let rc = unsafe { cusparseb_destroy_dnmat(d.d) } as Int;
  if rc != CUSPARSE_STATUS_SUCCESS {
    return Err(cusparse_status_error(rc));
  }
  return Ok({});
}

// ---- SpMV / SpMM ---------------------------------------------------------

/// Workspace bytes for y = alpha*op(A)*x + beta*y (`cusparseSpMV_bufferSize`).
/// Complexity: O(1).
pub fn cusparse_spmv_buffer_size(h: &CusparseHandle, op: Int, alpha: Float64,
                                 sp: &CusparseSpMat, x: &CusparseDnVec,
                                 beta: Float64, y: &CusparseDnVec,
                                 compute_type: Int, alg: Int)
  -> Result[Int, CusparseError]
  requires: h.h != 0
  requires: sp.d != 0 && x.d != 0 && y.d != 0
{
  let n = unsafe {
    cusparseb_spmv_buffer_size(h.h, op as Int32, alpha, sp.d, x.d, beta, y.d,
                               compute_type as Int32, alg as Int32)
  };
  if n < 0 {
    return Err(cusparse_status_error(unsafe { cusparseb_last_status() } as Int));
  }
  return Ok(n);
}

/// Execute y = alpha*op(A)*x + beta*y (`cusparseSpMV`).  `external_buffer`
/// may carry p == 0 when the buffer-size query returned 0.
/// Complexity: O(nnz).
pub fn cusparse_spmv(h: &CusparseHandle, op: Int, alpha: Float64,
                     sp: &CusparseSpMat, x: &CusparseDnVec, beta: Float64,
                     y: &CusparseDnVec, compute_type: Int, alg: Int,
                     external_buffer: &CusparseDevicePtr)
  -> Result[Unit, CusparseError]
  requires: h.h != 0
  requires: sp.d != 0 && x.d != 0 && y.d != 0
{
  let rc = unsafe {
    cusparseb_spmv(h.h, op as Int32, alpha, sp.d, x.d, beta, y.d,
                   compute_type as Int32, alg as Int32, external_buffer.p)
  } as Int;
  if rc != CUSPARSE_STATUS_SUCCESS {
    return Err(cusparse_status_error(rc));
  }
  return Ok({});
}

/// Workspace bytes for C = alpha*op(A)*op(B) + beta*C
/// (`cusparseSpMM_bufferSize`).  Complexity: O(1).
pub fn cusparse_spmm_buffer_size(h: &CusparseHandle, op_a: Int, op_b: Int,
                                 alpha: Float64, sp: &CusparseSpMat,
                                 b: &CusparseDnMat, beta: Float64, c: &CusparseDnMat,
                                 compute_type: Int, alg: Int)
  -> Result[Int, CusparseError]
  requires: h.h != 0
  requires: sp.d != 0 && b.d != 0 && c.d != 0
{
  let n = unsafe {
    cusparseb_spmm_buffer_size(h.h, op_a as Int32, op_b as Int32, alpha, sp.d,
                               b.d, beta, c.d, compute_type as Int32, alg as Int32)
  };
  if n < 0 {
    return Err(cusparse_status_error(unsafe { cusparseb_last_status() } as Int));
  }
  return Ok(n);
}

/// Execute C = alpha*op(A)*op(B) + beta*C (`cusparseSpMM`).
/// Complexity: O(nnz * cols).
pub fn cusparse_spmm(h: &CusparseHandle, op_a: Int, op_b: Int, alpha: Float64,
                     sp: &CusparseSpMat, b: &CusparseDnMat, beta: Float64,
                     c: &CusparseDnMat, compute_type: Int, alg: Int,
                     external_buffer: &CusparseDevicePtr)
  -> Result[Unit, CusparseError]
  requires: h.h != 0
  requires: sp.d != 0 && b.d != 0 && c.d != 0
{
  let rc = unsafe {
    cusparseb_spmm(h.h, op_a as Int32, op_b as Int32, alpha, sp.d, b.d, beta,
                   c.d, compute_type as Int32, alg as Int32, external_buffer.p)
  } as Int;
  if rc != CUSPARSE_STATUS_SUCCESS {
    return Err(cusparse_status_error(rc));
  }
  return Ok({});
}

// ---- device-memory helpers (driver API) ---------------------------------

/// Allocate `bytes` of device memory (cuMemAlloc_v2).
/// Complexity: O(alloc).
pub fn cusparse_buffer_alloc(bytes: Int) -> Result[CusparseDevicePtr, CusparseError]
  requires: bytes > 0
{
  let p = unsafe { cusparseb_dev_alloc(bytes) };
  if p == 0 {
    return Err(cusparse_device_error());
  }
  return Ok(CusparseDevicePtr{ p: p });
}

/// Free device memory allocated by `cusparse_buffer_alloc`.
/// Complexity: O(free).
pub fn cusparse_buffer_free(p: &CusparseDevicePtr) -> Result[Unit, CusparseError]
  requires: p.p != 0
{
  let rc = unsafe { cusparseb_dev_free(p.p) } as Int;
  if rc != 0 {
    return Err(cusparse_device_error());
  }
  return Ok({});
}

/// Host -> device copy of a Float32 span (count = data.len()).
/// Complexity: O(n).
pub fn cusparse_buffer_upload_f32(p: &CusparseDevicePtr, data: &Vec[Float32])
  -> Result[Unit, CusparseError]
  requires: p.p != 0
  requires: data.len() > 0
{
  let rc = unsafe { cusparseb_dev_upload_f32(p.p, &data[0], data.len()) } as Int;
  if rc != 0 {
    return Err(cusparse_device_error());
  }
  return Ok({});
}

/// Device -> host copy into a pre-sized Float32 span.
/// Complexity: O(n).
pub fn cusparse_buffer_download_f32(p: &CusparseDevicePtr, out: &mut Vec[Float32])
  -> Result[Unit, CusparseError]
  requires: p.p != 0
  requires: out.len() > 0
{
  let rc = unsafe { cusparseb_dev_download_f32(p.p, &mut out[0], out.len()) } as Int;
  if rc != 0 {
    return Err(cusparse_device_error());
  }
  return Ok({});
}

/// Host -> device copy of a Float64 span (count = data.len()).
/// Complexity: O(n).
pub fn cusparse_buffer_upload_f64(p: &CusparseDevicePtr, data: &Vec[Float64])
  -> Result[Unit, CusparseError]
  requires: p.p != 0
  requires: data.len() > 0
{
  let rc = unsafe { cusparseb_dev_upload_f64(p.p, &data[0], data.len()) } as Int;
  if rc != 0 {
    return Err(cusparse_device_error());
  }
  return Ok({});
}

/// Device -> host copy into a pre-sized Float64 span.
/// Complexity: O(n).
pub fn cusparse_buffer_download_f64(p: &CusparseDevicePtr, out: &mut Vec[Float64])
  -> Result[Unit, CusparseError]
  requires: p.p != 0
  requires: out.len() > 0
{
  let rc = unsafe { cusparseb_dev_download_f64(p.p, &mut out[0], out.len()) } as Int;
  if rc != 0 {
    return Err(cusparse_device_error());
  }
  return Ok({});
}

/// Host -> device copy of an Int32 span (CSR row offsets / column indices).
/// Complexity: O(n).
pub fn cusparse_buffer_upload_i32(p: &CusparseDevicePtr, data: &Vec[Int32])
  -> Result[Unit, CusparseError]
  requires: p.p != 0
  requires: data.len() > 0
{
  let rc = unsafe { cusparseb_dev_upload_i32(p.p, &data[0], data.len()) } as Int;
  if rc != 0 {
    return Err(cusparse_device_error());
  }
  return Ok({});
}

/// Device -> host copy into a pre-sized Int32 span.
/// Complexity: O(n).
pub fn cusparse_buffer_download_i32(p: &CusparseDevicePtr, out: &mut Vec[Int32])
  -> Result[Unit, CusparseError]
  requires: p.p != 0
  requires: out.len() > 0
{
  let rc = unsafe { cusparseb_dev_download_i32(p.p, &mut out[0], out.len()) } as Int;
  if rc != 0 {
    return Err(cusparse_device_error());
  }
  return Ok({});
}

// ---- status text ---------------------------------------------------------

/// Human-readable cuSPARSE status name (0..11; unknown codes are printed).
/// Complexity: O(1).
pub fn cusparse_status_name(code: Int) -> Str
  requires: true
{
  if code == 0 { return "CUSPARSE_STATUS_SUCCESS"; }
  if code == 1 { return "CUSPARSE_STATUS_NOT_INITIALIZED"; }
  if code == 2 { return "CUSPARSE_STATUS_ALLOC_FAILED"; }
  if code == 3 { return "CUSPARSE_STATUS_INVALID_VALUE"; }
  if code == 4 { return "CUSPARSE_STATUS_ARCH_MISMATCH"; }
  if code == 5 { return "CUSPARSE_STATUS_MAPPING_ERROR"; }
  if code == 6 { return "CUSPARSE_STATUS_EXECUTION_FAILED"; }
  if code == 7 { return "CUSPARSE_STATUS_INTERNAL_ERROR"; }
  if code == 8 { return "CUSPARSE_STATUS_MATRIX_TYPE_NOT_SUPPORTED"; }
  if code == 9 { return "CUSPARSE_STATUS_ZERO_PIVOT"; }
  if code == 10 { return "CUSPARSE_STATUS_NOT_SUPPORTED"; }
  if code == 11 { return "CUSPARSE_STATUS_INSUFFICIENT_RESOURCES"; }
  return "cuSPARSE status " + cusparse_i2s(code);
}

// ---- internals -----------------------------------------------------------

fn cusparse_classify(kind: Int, msg: Str) -> CusparseError
  requires: true
{
  if kind == CUSPARSE_LOAD_ABSENT {
    return CusparseError{ kind: kind; code: 0;
                          message: msg + " (module absent -- SKIP)"; };
  }
  if kind == CUSPARSE_LOAD_NO_DEVICE {
    return CusparseError{ kind: kind; code: 0;
                          message: "no CUDA driver/device (SKIP)"; };
  }
  if kind == CUSPARSE_LOAD_ABI {
    return CusparseError{ kind: kind; code: 0;
                          message: msg + " (required entry points missing)"; };
  }
  let d = unsafe { cusparseb_last_driver() } as Int;
  return CusparseError{ kind: CUSPARSE_LOAD_RUNTIME; code: d;
                        message: msg + " (CUDA driver error " + cusparse_i2s(d) + ")"; };
}

fn cusparse_status_error(code: Int) -> CusparseError
  requires: code >= 0
{
  return CusparseError{ kind: CUSPARSE_LOAD_RUNTIME; code: code;
                        message: cusparse_status_name(code); };
}

fn cusparse_device_error() -> CusparseError
  requires: true
{
  let d = unsafe { cusparseb_last_driver() } as Int;
  return CusparseError{ kind: CUSPARSE_LOAD_RUNTIME; code: d;
                        message: "CUDA driver error " + cusparse_i2s(d); };
}

fn cusparse_i2s(n: Int) -> Str
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
