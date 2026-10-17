// XIOM -- xiom.cudnn: NVIDIA cuDNN bindings (runtime loader, nothing vendored).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: the official cuDNN runtime is USER-SUPPLIED and loaded at runtime.
// Nothing from NVIDIA is vendored: no headers, no import libraries, no DLLs.
// The loader probes (in this order) an explicit directory, XIOM_CUDNN_DIR,
// CUDNN_DIR, then PATH for `cudnn64_9.dll` and the `cudnn64_8.dll` fallback.
// The companion CUDA driver (`nvcuda.dll`) comes from the installed NVIDIA
// driver; it provides the context and device-memory round trip used by the
// declared operation surface.
//
// Declared surface (essentials subset; exact list in SPEC.md):
//   * core: cudnnGetVersion / cudnnCreate / cudnnDestroy / cudnnGetErrorString
//   * tensor descriptors: create / destroy / set 4D / get 4D (dims + strides)
//   * convolution: filter + convolution descriptor create/set/destroy,
//     cudnnGetConvolutionForwardWorkspaceSize, cudnnConvolutionForward
//   * activation: descriptor create/set/destroy, cudnnActivationForward (ReLU)
//   * pooling: descriptor create/set/destroy, cudnnPoolingForward
//   * softmax: cudnnSoftmaxForward
//   * support (CUDA driver): context, device alloc/free/upload/download/sync
//
// The classic graph-free API is used; cuDNN 9.27 still exports it (upstream
// marks it deprecated, not removed).  A graph/frontend surface is ROADMAP.
//
// All `unsafe`/`extern "C"` lives in this single module (G5).  The C bridge
// (src/cudnn_bridge.c) owns the function-pointer table, the CUDA context and
// the self-contained live probe.  Out-parameters cross into XIOM-owned slots
// (Vec[Int] / Vec[Float32]) -- never foreign-pointer reads (B-20/B-11).
//
// Classification: loader absent / no CUDA device -> SKIP; missing export,
// cuDNN status failure or CUDA-driver failure -> FAIL.  The deterministic
// SKIP path is exercisable on any host through an explicit bogus directory.

module xiom.cudnn

extern "C" {
  fn cn_load(dir: *UInt8) -> Int32;
  fn cn_version() -> Int64;
  fn cn_module() -> *UInt8;
  fn cn_device_name() -> *UInt8;
  fn cn_device_cc() -> Int32;
  fn cn_last_status() -> Int32;
  fn cn_last_error() -> *UInt8;
  fn cn_status_string(status: Int32) -> *UInt8;
  fn cn_shutdown();

  fn cn_handle_create() -> Int64;
  fn cn_handle_destroy(handle: Int64) -> Int32;

  fn cn_tensor_create() -> Int64;
  fn cn_tensor_destroy(desc: Int64) -> Int32;
  fn cn_tensor_set4d(desc: Int64, format: Int32, data_type: Int32, n: Int32, c: Int32, h: Int32, w: Int32) -> Int32;
  fn cn_tensor_get4d(desc: Int64, out: Int64) -> Int32;

  fn cn_filter_create() -> Int64;
  fn cn_filter_destroy(desc: Int64) -> Int32;
  fn cn_filter_set4d(desc: Int64, data_type: Int32, format: Int32, k: Int32, c: Int32, h: Int32, w: Int32) -> Int32;

  fn cn_conv_create() -> Int64;
  fn cn_conv_destroy(desc: Int64) -> Int32;
  fn cn_conv_set2d(desc: Int64, pad_h: Int32, pad_w: Int32, stride_h: Int32, stride_w: Int32,
                   dilation_h: Int32, dilation_w: Int32, mode: Int32, compute_type: Int32) -> Int32;
  fn cn_conv_workspace_size(handle: Int64, x_desc: Int64, w_desc: Int64, conv_desc: Int64,
                            y_desc: Int64, algo: Int32) -> Int64;
  fn cn_conv_forward(handle: Int64, x_desc: Int64, x: Int64, w_desc: Int64, w: Int64,
                     conv_desc: Int64, algo: Int32, workspace: Int64, workspace_bytes: Int64,
                     alpha: Float32, beta: Float32, y_desc: Int64, y: Int64) -> Int32;

  fn cn_act_create() -> Int64;
  fn cn_act_destroy(desc: Int64) -> Int32;
  fn cn_act_set(desc: Int64, mode: Int32, nan_opt: Int32, coef: Float64) -> Int32;
  fn cn_act_forward(handle: Int64, act_desc: Int64, alpha: Float32, x_desc: Int64, x: Int64,
                    beta: Float32, y_desc: Int64, y: Int64) -> Int32;

  fn cn_pool_create() -> Int64;
  fn cn_pool_destroy(desc: Int64) -> Int32;
  fn cn_pool_set2d(desc: Int64, mode: Int32, nan_opt: Int32, window_h: Int32, window_w: Int32,
                   pad_h: Int32, pad_w: Int32, stride_h: Int32, stride_w: Int32) -> Int32;
  fn cn_pool_forward(handle: Int64, pool_desc: Int64, alpha: Float32, x_desc: Int64, x: Int64,
                     beta: Float32, y_desc: Int64, y: Int64) -> Int32;

  fn cn_softmax_forward(handle: Int64, algo: Int32, mode: Int32, alpha: Float32,
                        x_desc: Int64, x: Int64, beta: Float32, y_desc: Int64, y: Int64) -> Int32;

  fn cn_dev_alloc(bytes: Int64) -> Int64;
  fn cn_dev_free(ptr: Int64) -> Int32;
  fn cn_dev_upload(dst: Int64, src: Int64, count: Int64) -> Int32;
  fn cn_dev_download(src: Int64, dst: Int64, count: Int64) -> Int32;
  fn cn_dev_sync() -> Int32;

  fn cn_probe(dir: *UInt8, out_ints: Int64, out_floats: Int64) -> Int32;
}

// =========================================================================
// Identity, loader names and error kinds
// =========================================================================

pub const CUDNN_PACKAGE_VERSION: Str = "0.1.0";
pub const CUDNN_SONAME_9: Str = "cudnn64_9.dll";
pub const CUDNN_SONAME_8: Str = "cudnn64_8.dll";
pub const CUDNN_PIN_MAJOR: Int = 9;
pub const CUDNN_PIN_MINOR: Int = 27;
pub const CUDNN_PIN_PATCH: Int = 0;

/// Loader/runtime module missing or no explicit runtime directory matched.
/// SKIP: the suite stays green on a host without a user-supplied cuDNN.
pub const CUDNN_LOAD_ABSENT: Int = 0;

/// A cuDNN runtime loaded but no CUDA device is available. SKIP.
pub const CUDNN_NO_DEVICE: Int = 1;

/// A runtime loaded but a required export is missing (ABI mismatch). FAIL.
pub const CUDNN_LOAD_ABI: Int = 2;

/// A cuDNN call returned a non-success cudnnStatus_t. FAIL.
pub const CUDNN_API_ERROR: Int = 3;

/// Loader/context/device-memory failure not covered by the kinds above. FAIL.
pub const CUDNN_RUNTIME_ERROR: Int = 4;

/// Typed loader/probe error. `status` is the raw bridge code: negative for
/// loader/CUDA classifier codes, positive for cudnnStatus_t.
pub type CudnnError = {
  kind: Int;
  status: Int;
  message: Str;
}

/// 4D tensor descriptor contents (NCHW strides as reported by cuDNN).
pub type Tensor4d = {
  data_type: Int;
  n: Int;
  c: Int;
  h: Int;
  w: Int;
  n_stride: Int;
  c_stride: Int;
  h_stride: Int;
  w_stride: Int;
}

/// Self-contained live probe result.  The deterministic shape is
/// 1x1x4x4 input * 1x1x3x3 all-ones filter -> 1x1x2x2 convolution, then
/// ReLU, 2x2 max pooling, and a 4-way channel softmax.
pub type CudnnProbe = {
  version: Int;
  module_name: Str;
  device_name: Str;
  compute_capability: Int;
  dims: Vec[Int];           // n, c, h, w of the input tensor
  strides: Vec[Int];        // n, c, h, w strides
  workspace_bytes: Int;
  conv: Vec[Float32];       // 54, 63, 90, 99
  relu: Vec[Float32];       // ReLU of conv (identity here)
  relu_negative: Vec[Float32]; // ReLU(-1, 2, -3, 4) = 0, 2, 0, 4
  pool_max: Float32;        // 99
  softmax: Vec[Float32];    // softmax(1, 2, 3, 4)
  softmax_sum: Float32;     // ~1.0
}

// =========================================================================
// cuDNN constants (pinned from the 9.27.0.42 headers; see SPEC.md)
// =========================================================================

pub const CUDNN_STATUS_SUCCESS: Int = 0;
pub const CUDNN_STATUS_NOT_INITIALIZED: Int = 1001;
pub const CUDNN_STATUS_BAD_PARAM: Int = 2000;
pub const CUDNN_STATUS_NOT_SUPPORTED: Int = 3000;
pub const CUDNN_STATUS_INTERNAL_ERROR: Int = 4000;
pub const CUDNN_STATUS_EXECUTION_FAILED: Int = 5000;

pub const CUDNN_DATA_FLOAT: Int = 0;
pub const CUDNN_TENSOR_NCHW: Int = 0;

pub const CUDNN_CONVOLUTION: Int = 0;
pub const CUDNN_CROSS_CORRELATION: Int = 1;

pub const CUDNN_CONVOLUTION_FWD_ALGO_IMPLICIT_GEMM: Int = 0;

pub const CUDNN_ACTIVATION_RELU: Int = 1;
pub const CUDNN_NOT_PROPAGATE_NAN: Int = 0;
pub const CUDNN_PROPAGATE_NAN: Int = 1;

pub const CUDNN_POOLING_MAX: Int = 0;

pub const CUDNN_SOFTMAX_FAST: Int = 0;
pub const CUDNN_SOFTMAX_ACCURATE: Int = 1;
pub const CUDNN_SOFTMAX_MODE_INSTANCE: Int = 0;
pub const CUDNN_SOFTMAX_MODE_CHANNEL: Int = 1;

// =========================================================================
// Error helpers
// =========================================================================

fn cudnn_last_error_text() -> Str
  requires: true
{
  unsafe {
    let p = cn_last_error();
    if (p as Int) != 0 {
      let s = Str::from_c_str(p);
      if s.len() > 0 { return s; }
    }
  }
  return "cudnn operation failed";
}

fn cudnn_error(code: Int) -> CudnnError
  requires: true
{
  var c = code;
  if c == 0 { c = -105; }
  var kind = CUDNN_RUNTIME_ERROR;
  if c == -100 { kind = CUDNN_LOAD_ABSENT; }
  elif c == -102 { kind = CUDNN_NO_DEVICE; }
  elif c == -104 { kind = CUDNN_NO_DEVICE; }
  elif c == -101 { kind = CUDNN_LOAD_ABI; }
  elif c > 0 { kind = CUDNN_API_ERROR; }
  return CudnnError{ kind: kind; status: code; message: cudnn_last_error_text(); };
}

fn cudnn_check(code: Int) -> Result[Unit, CudnnError]
  requires: true
{
  if code == 0 { return Ok(()); }
  return Err(cudnn_error(code));
}

/// Upstream text for a cudnnStatus_t (cudnnGetErrorString). O(1).
pub fn cudnn_error_text(status: Int) -> Str
  requires: true
{
  unsafe {
    let p = cn_status_string(status as Int32);
    if (p as Int) != 0 { return Str::from_c_str(p); }
  }
  return "unknown cuDNN status";
}

// =========================================================================
// Loader and version
// =========================================================================

/// Load the user-supplied runtime (empty `dir` = XIOM_CUDNN_DIR, CUDNN_DIR,
/// then PATH; an explicit directory is searched as-is, with `bin\` and
/// `nvidia\cudnn\bin\` variants). Returns the cuDNN version. Idempotent.
/// Complexity: O(load).
pub fn cudnn_load(dir: Str) -> Result[Int, CudnnError]
  requires: true
{
  let rc = unsafe { cn_load(dir.c_str()) as Int };
  if rc != 0 { return Err(cudnn_error(rc)); }
  let v = unsafe { cn_version() as Int };
  if v < 0 { return Err(cudnn_error(v)); }
  return Ok(v);
}

/// cuDNN version (MAJOR*10000 + MINOR*100 + PATCH), auto-loading from the
/// environment/PATH when needed. O(1).
pub fn cudnn_version() -> Result[Int, CudnnError]
  requires: true
{
  let v = unsafe { cn_version() as Int };
  if v < 0 { return Err(cudnn_error(v)); }
  return Ok(v);
}

/// Module path/name recorded by the loader (empty before a successful load).
pub fn cudnn_loaded_module() -> Str
  requires: true
{
  unsafe {
    let p = cn_module();
    if (p as Int) != 0 { return Str::from_c_str(p); }
  }
  return "";
}

/// Device 0 name recorded by the probe (empty before a context exists).
pub fn cudnn_device_name() -> Str
  requires: true
{
  unsafe {
    let p = cn_device_name();
    if (p as Int) != 0 { return Str::from_c_str(p); }
  }
  return "";
}

/// Device 0 compute capability (e.g. 860 = 8.6), 0 before a context exists.
pub fn cudnn_compute_capability() -> Int
  requires: true
{
  return unsafe { cn_device_cc() as Int };
}

// =========================================================================
// Self-contained live probe (conv + ReLU + pooling + softmax)
// =========================================================================

/// Run the full known-shape probe. Empty `dir` uses the environment/PATH
/// search; a bogus explicit directory exercises the deterministic SKIP path.
/// Complexity: O(probe).
pub fn cudnn_probe(dir: Str) -> Result[CudnnProbe, CudnnError]
  requires: true
{
  var ints: Vec[Int] = Vec[Int].new();
  var floats: Vec[Float32] = Vec[Float32].new();
  var i = 0;
  while i < 12 {
    ints.push(0);
    i = i + 1;
  }
  i = 0;
  while i < 16 {
    floats.push(0.0 as Float32);
    i = i + 1;
  }
  var ia = 0;
  var fa = 0;
  unsafe {
    ia = ints.as_mut_ptr() as Int;
    fa = floats.as_mut_ptr() as Int;
  }
  let rc = unsafe { cn_probe(dir.c_str(), ia as Int64, fa as Int64) as Int };
  if rc != 0 { return Err(cudnn_error(rc)); }

  var dims = Vec[Int].new();
  dims.push(ints[1]);
  dims.push(ints[2]);
  dims.push(ints[3]);
  dims.push(ints[4]);
  var strides = Vec[Int].new();
  strides.push(ints[5]);
  strides.push(ints[6]);
  strides.push(ints[7]);
  strides.push(ints[8]);

  var conv = Vec[Float32].new();
  var relu = Vec[Float32].new();
  var relu_negative = Vec[Float32].new();
  var softmax = Vec[Float32].new();
  i = 0;
  while i < 4 {
    conv.push(floats[i]);
    relu.push(floats[4 + i]);
    softmax.push(floats[11 + i]);
    i = i + 1;
  }
  relu_negative.push(floats[8]);
  relu_negative.push(floats[9]);

  return Ok(CudnnProbe{
    version: ints[0];
    module_name: cudnn_loaded_module();
    device_name: cudnn_device_name();
    compute_capability: ints[10];
    dims: dims;
    strides: strides;
    workspace_bytes: ints[9];
    conv: conv;
    relu: relu;
    relu_negative: relu_negative;
    pool_max: floats[10];
    softmax: softmax;
    softmax_sum: floats[15];
  });
}

/// Probe with the environment/PATH loader search. O(probe).
pub fn cudnn_probe_auto() -> Result[CudnnProbe, CudnnError]
  requires: true
{
  return cudnn_probe("");
}

/// Release the CUDA context and the loaded modules. Call after destroying
/// every cuDNN handle/descriptor. O(1).
pub fn cudnn_shutdown() -> Unit
  requires: true
{
  unsafe { cn_shutdown(); }
  return ();
}

// =========================================================================
// Core handles
// =========================================================================

/// cudnnCreate. Returns an opaque handle (Int). O(1).
pub fn cudnn_handle_create() -> Result[Int, CudnnError]
  requires: true
{
  let h = unsafe { cn_handle_create() as Int };
  if h == 0 { return Err(cudnn_error(unsafe { cn_last_status() as Int })); }
  return Ok(h);
}

/// cudnnDestroy. O(1).
pub fn cudnn_handle_destroy(handle: Int) -> Result[Unit, CudnnError]
  requires: true
{
  return cudnn_check(unsafe { cn_handle_destroy(handle as Int64) as Int });
}

// =========================================================================
// Tensor descriptors
// =========================================================================

pub fn cudnn_tensor_create() -> Result[Int, CudnnError]
  requires: true
{
  let d = unsafe { cn_tensor_create() as Int };
  if d == 0 { return Err(cudnn_error(unsafe { cn_last_status() as Int })); }
  return Ok(d);
}

pub fn cudnn_tensor_destroy(desc: Int) -> Result[Unit, CudnnError]
  requires: true
{
  return cudnn_check(unsafe { cn_tensor_destroy(desc as Int64) as Int });
}

/// cudnnSetTensor4dDescriptor. O(1).
pub fn cudnn_tensor_set_4d(desc: Int, format: Int, data_type: Int, n: Int, c: Int, h: Int, w: Int) -> Result[Unit, CudnnError]
  requires: true
{
  return cudnn_check(unsafe {
    cn_tensor_set4d(desc as Int64, format as Int32, data_type as Int32,
                    n as Int32, c as Int32, h as Int32, w as Int32) as Int
  });
}

/// cudnnGetTensor4dDescriptor -> typed dims and strides. O(1).
pub fn cudnn_tensor_get_4d(desc: Int) -> Result[Tensor4d, CudnnError]
  requires: true
{
  var slot: Vec[Int] = Vec[Int].new();
  var i = 0;
  while i < 9 {
    slot.push(0);
    i = i + 1;
  }
  var addr = 0;
  unsafe { addr = slot.as_mut_ptr() as Int; }
  let rc = unsafe { cn_tensor_get4d(desc as Int64, addr as Int64) as Int };
  if rc != 0 { return Err(cudnn_error(rc)); }
  return Ok(Tensor4d{
    data_type: slot[0];
    n: slot[1];
    c: slot[2];
    h: slot[3];
    w: slot[4];
    n_stride: slot[5];
    c_stride: slot[6];
    h_stride: slot[7];
    w_stride: slot[8];
  });
}

// =========================================================================
// Filter descriptors
// =========================================================================

pub fn cudnn_filter_create() -> Result[Int, CudnnError]
  requires: true
{
  let d = unsafe { cn_filter_create() as Int };
  if d == 0 { return Err(cudnn_error(unsafe { cn_last_status() as Int })); }
  return Ok(d);
}

pub fn cudnn_filter_destroy(desc: Int) -> Result[Unit, CudnnError]
  requires: true
{
  return cudnn_check(unsafe { cn_filter_destroy(desc as Int64) as Int });
}

/// cudnnSetFilter4dDescriptor. O(1).
pub fn cudnn_filter_set_4d(desc: Int, data_type: Int, format: Int, k: Int, c: Int, h: Int, w: Int) -> Result[Unit, CudnnError]
  requires: true
{
  return cudnn_check(unsafe {
    cn_filter_set4d(desc as Int64, data_type as Int32, format as Int32,
                    k as Int32, c as Int32, h as Int32, w as Int32) as Int
  });
}

// =========================================================================
// Convolution descriptors and forward pass
// =========================================================================

pub fn cudnn_convolution_create() -> Result[Int, CudnnError]
  requires: true
{
  let d = unsafe { cn_conv_create() as Int };
  if d == 0 { return Err(cudnn_error(unsafe { cn_last_status() as Int })); }
  return Ok(d);
}

pub fn cudnn_convolution_destroy(desc: Int) -> Result[Unit, CudnnError]
  requires: true
{
  return cudnn_check(unsafe { cn_conv_destroy(desc as Int64) as Int });
}

/// cudnnSetConvolution2dDescriptor. O(1).
pub fn cudnn_convolution_set_2d(desc: Int, pad_h: Int, pad_w: Int, stride_h: Int, stride_w: Int,
                                dilation_h: Int, dilation_w: Int, mode: Int, compute_type: Int) -> Result[Unit, CudnnError]
  requires: true
{
  return cudnn_check(unsafe {
    cn_conv_set2d(desc as Int64, pad_h as Int32, pad_w as Int32, stride_h as Int32,
                  stride_w as Int32, dilation_h as Int32, dilation_w as Int32,
                  mode as Int32, compute_type as Int32) as Int
  });
}

/// cudnnGetConvolutionForwardWorkspaceSize. O(1).
pub fn cudnn_convolution_workspace_size(handle: Int, x_desc: Int, w_desc: Int, conv_desc: Int,
                                         y_desc: Int, algo: Int) -> Result[Int, CudnnError]
  requires: true
{
  let size = unsafe {
    cn_conv_workspace_size(handle as Int64, x_desc as Int64, w_desc as Int64,
                           conv_desc as Int64, y_desc as Int64, algo as Int32) as Int
  };
  if size < 0 { return Err(cudnn_error(unsafe { cn_last_status() as Int })); }
  return Ok(size);
}

/// cudnnConvolutionForward (classic graph-free path). O(conv).
pub fn cudnn_convolution_forward(handle: Int, x_desc: Int, x: Int, w_desc: Int, w: Int,
                                 conv_desc: Int, algo: Int, workspace: Int, workspace_bytes: Int,
                                 alpha: Float32, beta: Float32, y_desc: Int, y: Int) -> Result[Unit, CudnnError]
  requires: true
{
  return cudnn_check(unsafe {
    cn_conv_forward(handle as Int64, x_desc as Int64, x as Int64, w_desc as Int64, w as Int64,
                    conv_desc as Int64, algo as Int32, workspace as Int64,
                    workspace_bytes as Int64, alpha, beta, y_desc as Int64, y as Int64) as Int
  });
}

// =========================================================================
// Activation descriptors and forward pass
// =========================================================================

pub fn cudnn_activation_create() -> Result[Int, CudnnError]
  requires: true
{
  let d = unsafe { cn_act_create() as Int };
  if d == 0 { return Err(cudnn_error(unsafe { cn_last_status() as Int })); }
  return Ok(d);
}

pub fn cudnn_activation_destroy(desc: Int) -> Result[Unit, CudnnError]
  requires: true
{
  return cudnn_check(unsafe { cn_act_destroy(desc as Int64) as Int });
}

/// cudnnSetActivationDescriptor (use CUDNN_ACTIVATION_RELU for ReLU). O(1).
pub fn cudnn_activation_set(desc: Int, mode: Int, nan_opt: Int, coef: Float64) -> Result[Unit, CudnnError]
  requires: true
{
  return cudnn_check(unsafe {
    cn_act_set(desc as Int64, mode as Int32, nan_opt as Int32, coef) as Int
  });
}

/// cudnnActivationForward. O(activation).
pub fn cudnn_activation_forward(handle: Int, act_desc: Int, alpha: Float32,
                                x_desc: Int, x: Int, beta: Float32,
                                y_desc: Int, y: Int) -> Result[Unit, CudnnError]
  requires: true
{
  return cudnn_check(unsafe {
    cn_act_forward(handle as Int64, act_desc as Int64, alpha, x_desc as Int64, x as Int64,
                   beta, y_desc as Int64, y as Int64) as Int
  });
}

// =========================================================================
// Pooling descriptors and forward pass
// =========================================================================

pub fn cudnn_pooling_create() -> Result[Int, CudnnError]
  requires: true
{
  let d = unsafe { cn_pool_create() as Int };
  if d == 0 { return Err(cudnn_error(unsafe { cn_last_status() as Int })); }
  return Ok(d);
}

pub fn cudnn_pooling_destroy(desc: Int) -> Result[Unit, CudnnError]
  requires: true
{
  return cudnn_check(unsafe { cn_pool_destroy(desc as Int64) as Int });
}

/// cudnnSetPooling2dDescriptor. O(1).
pub fn cudnn_pooling_set_2d(desc: Int, mode: Int, nan_opt: Int, window_h: Int, window_w: Int,
                            pad_h: Int, pad_w: Int, stride_h: Int, stride_w: Int) -> Result[Unit, CudnnError]
  requires: true
{
  return cudnn_check(unsafe {
    cn_pool_set2d(desc as Int64, mode as Int32, nan_opt as Int32, window_h as Int32,
                  window_w as Int32, pad_h as Int32, pad_w as Int32, stride_h as Int32,
                  stride_w as Int32) as Int
  });
}

/// cudnnPoolingForward. O(pooling).
pub fn cudnn_pooling_forward(handle: Int, pool_desc: Int, alpha: Float32,
                             x_desc: Int, x: Int, beta: Float32,
                             y_desc: Int, y: Int) -> Result[Unit, CudnnError]
  requires: true
{
  return cudnn_check(unsafe {
    cn_pool_forward(handle as Int64, pool_desc as Int64, alpha, x_desc as Int64, x as Int64,
                    beta, y_desc as Int64, y as Int64) as Int
  });
}

// =========================================================================
// Softmax forward pass
// =========================================================================

/// cudnnSoftmaxForward. O(softmax).
pub fn cudnn_softmax_forward(handle: Int, algo: Int, mode: Int, alpha: Float32,
                             x_desc: Int, x: Int, beta: Float32,
                             y_desc: Int, y: Int) -> Result[Unit, CudnnError]
  requires: true
{
  return cudnn_check(unsafe {
    cn_softmax_forward(handle as Int64, algo as Int32, mode as Int32, alpha,
                       x_desc as Int64, x as Int64, beta, y_desc as Int64, y as Int64) as Int
  });
}

// =========================================================================
// CUDA driver support (device memory for the operation surface)
// =========================================================================

/// Allocate a device buffer (bytes). Returns an opaque device address. O(1).
pub fn cudnn_device_alloc(bytes: Int) -> Result[Int, CudnnError]
  requires: true
{
  let p = unsafe { cn_dev_alloc(bytes as Int64) as Int };
  if p == 0 { return Err(cudnn_error(unsafe { cn_last_status() as Int })); }
  return Ok(p);
}

/// Free a device buffer. O(1).
pub fn cudnn_device_free(ptr: Int) -> Result[Unit, CudnnError]
  requires: true
{
  return cudnn_check(unsafe { cn_dev_free(ptr as Int64) as Int });
}

/// Upload a Float32 vector to a device buffer (count = src.len()). O(n).
pub fn cudnn_device_upload(dst: Int, src: &Vec[Float32]) -> Result[Unit, CudnnError]
  requires: true
{
  var addr = 0;
  unsafe { addr = src.as_ptr() as Int; }
  return cudnn_check(unsafe {
    cn_dev_upload(dst as Int64, addr as Int64, src.len() as Int64) as Int
  });
}

/// Download a device buffer into a pre-sized Float32 vector. O(n).
pub fn cudnn_device_download(src: Int, dst: &mut Vec[Float32]) -> Result[Unit, CudnnError]
  requires: true
{
  var addr = 0;
  unsafe { addr = dst.as_mut_ptr() as Int; }
  return cudnn_check(unsafe {
    cn_dev_download(src as Int64, addr as Int64, dst.len() as Int64) as Int
  });
}

/// Block until the current context's work completes. O(1).
pub fn cudnn_device_sync() -> Result[Unit, CudnnError]
  requires: true
{
  return cudnn_check(unsafe { cn_dev_sync() as Int });
}
