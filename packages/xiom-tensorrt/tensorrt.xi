// XIOM -- xiom.tensorrt: NVIDIA TensorRT 10.x bindings (runtime loader).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: system-library path -- **nothing is vendored**.  `nvinfer_10.dll`
// is loaded at runtime; the C++ bridge (src/trt_bridge.cpp) resolves the
// three documented C entry points and reaches the TensorRT 10.16
// implementation through the pinned apiv vtable facts (SPEC.md section 3).
// No NVIDIA header, import library or binary is part of this package.
//
// All `unsafe` / `extern "C"` live in this one module (G5).  Runtime absent
// or no CUDA device -> typed SKIP classification; call failures -> typed
// errors.  The deterministic SKIP path is exercisable on every host via
// `trt_probe_named` with a bogus module name.
//
// Usage order for the full path:
//   trt_cuda_init -> trt_probe -> logger -> builder -> network/config ->
//   build_serialized -> runtime -> deserialize -> execution context ->
//   cuda buffers/stream -> set addresses -> enqueue -> download.
//
// The CUDA context must exist before the TensorRT builder is created:
// TensorRT executes on the current context, and the bridge activates the
// same primary context on every build/execute call.

module xiom.tensorrt

// =========================================================================
// Bridge ABI (all in the single confined module)
// =========================================================================

extern "C" {
  fn trt_c_last_error_kind() -> Int32;
  fn trt_c_last_error_message() -> *UInt8;

  fn trt_c_probe() -> Int32;
  fn trt_c_probe_named(name: *UInt8) -> Int32;
  fn trt_c_close() -> Int32;
  fn trt_c_loaded() -> Int32;
  fn trt_c_version_raw() -> Int32;
  fn trt_c_version_major() -> Int32;
  fn trt_c_version_minor() -> Int32;
  fn trt_c_version_patch() -> Int32;
  fn trt_c_loaded_module() -> *UInt8;
  fn trt_c_symbols_resolved() -> Int32;
  fn trt_c_symbols_required() -> Int32;
  fn trt_c_enqueue_mode() -> *UInt8;

  fn trt_c_logger_create(severity: Int32) -> Int;
  fn trt_c_logger_destroy(id: Int) -> Int32;
  fn trt_c_logger_set_severity(id: Int, severity: Int32) -> Int32;
  fn trt_c_logger_severity(id: Int) -> Int32;
  fn trt_c_logger_message_count(id: Int) -> Int32;
  fn trt_c_logger_last_message(id: Int) -> *UInt8;
  fn trt_c_logger_last_severity(id: Int) -> Int32;

  fn trt_c_builder_create(logger: Int) -> Int;
  fn trt_c_builder_destroy(id: Int) -> Int32;
  fn trt_c_builder_platform_has_fp16(id: Int) -> Int32;
  fn trt_c_builder_platform_has_int8(id: Int) -> Int32;
  fn trt_c_builder_platform_has_tf32(id: Int) -> Int32;
  fn trt_c_builder_create_network(id: Int) -> Int;
  fn trt_c_builder_create_config(id: Int) -> Int;
  fn trt_c_builder_build_serialized(builder: Int, network: Int, config: Int) -> Int;

  fn trt_c_network_add_input(net: Int, name: *UInt8, dtype: Int32,
                           d0: Int, d1: Int, d2: Int, d3: Int,
                           d4: Int, d5: Int, d6: Int, d7: Int, ndim: Int32) -> Int;
  fn trt_c_network_add_identity(net: Int, input: Int) -> Int;
  fn trt_c_network_add_constant_f32(net: Int, value: Float32,
                                  d0: Int, d1: Int, d2: Int, d3: Int,
                                  d4: Int, d5: Int, d6: Int, d7: Int, ndim: Int32) -> Int;
  fn trt_c_network_add_elementwise(net: Int, op: Int32, a: Int, b: Int) -> Int;
  fn trt_c_network_mark_output(net: Int, tensor: Int) -> Int32;
  fn trt_c_network_nb_layers(net: Int) -> Int32;
  fn trt_c_network_nb_inputs(net: Int) -> Int32;
  fn trt_c_network_nb_outputs(net: Int) -> Int32;
  fn trt_c_network_input(net: Int, index: Int32) -> Int;
  fn trt_c_network_output(net: Int, index: Int32) -> Int;
  fn trt_c_network_layer(net: Int, index: Int32) -> Int;
  fn trt_c_network_destroy(net: Int) -> Int32;

  fn trt_c_tensor_set_name(tensor: Int, name: *UInt8) -> Int32;
  fn trt_c_tensor_name(tensor: Int) -> *UInt8;
  fn trt_c_tensor_dtype(tensor: Int) -> Int32;
  fn trt_c_tensor_ndim(tensor: Int) -> Int32;
  fn trt_c_tensor_dim(tensor: Int, index: Int32) -> Int;
  fn trt_c_tensor_is_input(tensor: Int) -> Int32;
  fn trt_c_tensor_is_output(tensor: Int) -> Int32;

  fn trt_c_layer_type(layer: Int) -> Int32;
  fn trt_c_layer_name(layer: Int) -> *UInt8;

  fn trt_c_config_set_flag(config: Int, flag: Int32, value: Int32) -> Int32;
  fn trt_c_config_get_flag(config: Int, flag: Int32) -> Int32;
  fn trt_c_config_set_memory_pool_limit(config: Int, pool: Int32, bytes: Int) -> Int32;
  fn trt_c_config_memory_pool_limit(config: Int, pool: Int32) -> Int;
  fn trt_c_config_set_tactic_sources(config: Int, mask: Int) -> Int32;
  fn trt_c_config_tactic_sources(config: Int) -> Int;
  fn trt_c_config_destroy(config: Int) -> Int32;

  fn trt_c_host_memory_size(host: Int) -> Int;
  fn trt_c_host_memory_data(host: Int) -> Int;
  fn trt_c_host_memory_save(host: Int, path: *UInt8) -> Int32;
  fn trt_c_host_memory_load(path: *UInt8) -> Int;
  fn trt_c_host_memory_destroy(host: Int) -> Int32;

  fn trt_c_runtime_create(logger: Int) -> Int;
  fn trt_c_runtime_destroy(id: Int) -> Int32;
  fn trt_c_runtime_deserialize(runtime: Int, data_addr: Int, size: Int) -> Int;
  fn trt_c_runtime_deserialize_memory(runtime: Int, host: Int) -> Int;

  fn trt_c_engine_destroy(id: Int) -> Int32;
  fn trt_c_engine_nb_io_tensors(engine: Int) -> Int32;
  fn trt_c_engine_io_tensor_name(engine: Int, index: Int32) -> *UInt8;
  fn trt_c_engine_tensor_dtype(engine: Int, name: *UInt8) -> Int32;
  fn trt_c_engine_tensor_location(engine: Int, name: *UInt8) -> Int32;
  fn trt_c_engine_tensor_io_mode(engine: Int, name: *UInt8) -> Int32;
  fn trt_c_engine_tensor_ndim(engine: Int, name: *UInt8) -> Int32;
  fn trt_c_engine_tensor_dim(engine: Int, name: *UInt8, index: Int32) -> Int;
  fn trt_c_engine_create_context(engine: Int) -> Int;

  fn trt_c_context_destroy(id: Int) -> Int32;
  fn trt_c_context_set_input_shape(ctx: Int, name: *UInt8,
                                 d0: Int, d1: Int, d2: Int, d3: Int,
                                 d4: Int, d5: Int, d6: Int, d7: Int, ndim: Int32) -> Int32;
  fn trt_c_context_set_tensor_address(ctx: Int, name: *UInt8, addr: Int) -> Int32;
  fn trt_c_context_tensor_address(ctx: Int, name: *UInt8) -> Int;
  fn trt_c_context_all_input_dims_specified(ctx: Int) -> Int32;
  fn trt_c_context_enqueue(ctx: Int, stream: Int) -> Int32;

  fn trt_c_cuda_init() -> Int32;
  fn trt_c_cuda_shutdown() -> Int32;
  fn trt_c_cuda_alloc(bytes: Int) -> Int;
  fn trt_c_cuda_free(ptr: Int) -> Int32;
  fn trt_c_cuda_upload(dev: Int, src: Int, bytes: Int) -> Int32;
  fn trt_c_cuda_download(dst: Int, dev: Int, bytes: Int) -> Int32;
  fn trt_c_cuda_stream_create() -> Int;
  fn trt_c_cuda_stream_destroy(stream: Int) -> Int32;
  fn trt_c_cuda_stream_sync(stream: Int) -> Int32;
  fn trt_c_cuda_device_name() -> *UInt8;
  fn trt_c_cuda_device_count() -> Int32;
}

// =========================================================================
// Constants (pinned 10.16 interface facts)
// =========================================================================

pub const TRT_OK: Int = 0;
pub const TRT_LOAD_ABSENT: Int = 1;
pub const TRT_LOAD_ABI: Int = 2;
pub const TRT_VERSION_UNSUPPORTED: Int = 3;
pub const TRT_NO_DEVICE: Int = 4;
pub const TRT_CALL_FAILED: Int = 5;
pub const TRT_BAD_HANDLE: Int = 6;
pub const TRT_INVALID_ARG: Int = 7;
pub const TRT_IO_FAILED: Int = 8;
pub const TRT_CUDA_FAILED: Int = 9;
pub const TRT_UNSUPPORTED: Int = 10;

pub const TRT_PINNED_MAJOR: Int = 10;
pub const TRT_PINNED_MINOR: Int = 16;

pub const TRT_DTYPE_FLOAT: Int = 0;
pub const TRT_DTYPE_HALF: Int = 1;
pub const TRT_DTYPE_INT8: Int = 2;
pub const TRT_DTYPE_INT32: Int = 3;
pub const TRT_DTYPE_BOOL: Int = 4;
pub const TRT_DTYPE_UINT8: Int = 5;
pub const TRT_DTYPE_FP8: Int = 6;
pub const TRT_DTYPE_BF16: Int = 7;
pub const TRT_DTYPE_INT64: Int = 8;
pub const TRT_DTYPE_INT4: Int = 9;

pub const TRT_IO_INPUT: Int = 1;
pub const TRT_IO_OUTPUT: Int = 2;

pub const TRT_SEVERITY_INTERNAL_ERROR: Int = 0;
pub const TRT_SEVERITY_ERROR: Int = 1;
pub const TRT_SEVERITY_WARNING: Int = 2;
pub const TRT_SEVERITY_INFO: Int = 3;
pub const TRT_SEVERITY_VERBOSE: Int = 4;

pub const TRT_ELEMENTWISE_SUM: Int = 0;
pub const TRT_ELEMENTWISE_PROD: Int = 1;
pub const TRT_ELEMENTWISE_MAX: Int = 2;
pub const TRT_ELEMENTWISE_MIN: Int = 3;
pub const TRT_ELEMENTWISE_SUB: Int = 4;
pub const TRT_ELEMENTWISE_DIV: Int = 5;
pub const TRT_ELEMENTWISE_POW: Int = 6;
pub const TRT_ELEMENTWISE_FLOOR_DIV: Int = 7;

pub const TRT_POOL_WORKSPACE: Int = 0;
pub const TRT_POOL_DLA_MANAGED_SRAM: Int = 1;
pub const TRT_POOL_DLA_LOCAL_DRAM: Int = 2;
pub const TRT_POOL_DLA_GLOBAL_DRAM: Int = 3;
pub const TRT_POOL_HOST_DRAM: Int = 4;

pub const TRT_FLAG_FP16: Int = 0;
pub const TRT_FLAG_INT8: Int = 1;
pub const TRT_FLAG_DEBUG: Int = 2;
pub const TRT_FLAG_GPU_FALLBACK: Int = 3;
pub const TRT_FLAG_REFIT: Int = 4;
pub const TRT_FLAG_DISABLE_TIMING_CACHE: Int = 5;
pub const TRT_FLAG_TF32: Int = 6;
pub const TRT_FLAG_SPARSE_WEIGHTS: Int = 7;

pub const TRT_TENSOR_LOCATION_DEVICE: Int = 0;
pub const TRT_TENSOR_LOCATION_HOST: Int = 1;

// =========================================================================
// Types
// =========================================================================

/// Typed TensorRT/loader failure.  `kind` is one of the TRT_* constants.
pub type TrtError = {
  kind: Int;
  message: Str;
}

/// Decoded `getInferLibVersion` value.  TensorRT encodes
/// major*10000 + minor*100 + patch (e.g. 101601 = 10.16.1).
pub type TrtVersion = {
  raw: Int;
  major: Int;
  minor: Int;
  patch: Int;
  build: Int;
}

/// Loaded module identity + declared-surface counts.
pub type TrtInfo = {
  dll: Str;
  abi: Str;
  enqueue: Str;
  version: TrtVersion;
  symbols_resolved: Int;
  symbols_required: Int;
}

// =========================================================================
// Internal error/result helpers
// =========================================================================

fn trt_err() -> TrtError
  requires: true
{
  let k = unsafe { trt_c_last_error_kind() as Int };
  if k == 0 {
    return TrtError{ kind: TRT_OK; message: ""; };
  }
  var msg = "";
  unsafe {
    let p = trt_c_last_error_message();
    if (p as Int) != 0 {
      msg = Str::from_c_str(p);
    }
  }
  return TrtError{ kind: k; message: msg; };
}

fn trt_handle_result(h: Int, what: Str) -> Result[Int, TrtError]
  requires: true
{
  let e = trt_err();
  if e.kind != TRT_OK {
    return Err(e);
  }
  if h <= 0 {
    return Err(TrtError{ kind: TRT_CALL_FAILED; message: what + " returned no handle"; });
  }
  return Ok(h);
}

fn trt_ok_result(v: Int, what: Str) -> Result[Int, TrtError]
  requires: true
{
  let e = trt_err();
  if e.kind != TRT_OK {
    return Err(e);
  }
  if v <= 0 {
    return Err(TrtError{ kind: TRT_CALL_FAILED; message: what + " failed"; });
  }
  return Ok(v);
}

fn trt_int_result(v: Int, what: Str) -> Result[Int, TrtError]
  requires: true
{
  let e = trt_err();
  if e.kind != TRT_OK {
    return Err(e);
  }
  if v < 0 {
    return Err(TrtError{ kind: TRT_CALL_FAILED; message: what + " failed"; });
  }
  return Ok(v);
}

fn trt_dim_result(v: Int, what: Str) -> Result[Int, TrtError]
  requires: true
{
  let e = trt_err();
  if e.kind != TRT_OK {
    return Err(e);
  }
  return Ok(v);
}

fn trt_bool_result(v: Int, what: Str) -> Result[Bool, TrtError]
  requires: true
{
  let e = trt_err();
  if e.kind != TRT_OK {
    return Err(e);
  }
  if v < 0 {
    return Err(TrtError{ kind: TRT_CALL_FAILED; message: what + " failed"; });
  }
  return Ok(v != 0);
}



fn trt_info_from_raw(raw: Int) -> TrtInfo
  requires: raw > 0
{
  var module_path = "";
  var enqueue = "";
  unsafe {
    let pm = trt_c_loaded_module();
    if (pm as Int) != 0 {
      module_path = Str::from_c_str(pm);
    }
    let pe = trt_c_enqueue_mode();
    if (pe as Int) != 0 {
      enqueue = Str::from_c_str(pe);
    }
  }
  let major = unsafe { trt_c_version_major() as Int };
  let minor = unsafe { trt_c_version_minor() as Int };
  let patch = unsafe { trt_c_version_patch() as Int };
  let resolved = unsafe { trt_c_symbols_resolved() as Int };
  let required = unsafe { trt_c_symbols_required() as Int };
  return TrtInfo{
    dll: module_path;
    abi: "10.x";
    enqueue: enqueue;
    version: TrtVersion{ raw: raw; major: major; minor: minor; patch: patch; build: 0; };
    symbols_resolved: resolved;
    symbols_required: required;
  };
}

// =========================================================================
// Loader / version
// =========================================================================

/// Load the default TensorRT module and report its identity.  The bridge
/// reads `XIOM_TENSORRT_DIR` (a directory or a full DLL path) and otherwise
/// tries `nvinfer_10.dll` then `nvinfer.dll`.  Absent module -> SKIP.
/// Complexity: O(load).
pub fn trt_probe() -> Result[TrtInfo, TrtError]
  requires: true
{
  let v = unsafe { trt_c_probe() as Int };
  let e = trt_err();
  if e.kind != TRT_OK {
    return Err(e);
  }
  if v <= 0 {
    return Err(TrtError{ kind: TRT_CALL_FAILED; message: "TensorRT probe failed"; });
  }
  return Ok(trt_info_from_raw(v));
}

/// Same probe against an explicitly named module/path (the deterministic
/// SKIP path with a bogus name on any host).  A previous load is closed
/// first.  Complexity: O(load).
pub fn trt_probe_named(dll: Str) -> Result[TrtInfo, TrtError]
  requires: dll.len() > 0
{
  var v = 0;
  unsafe {
    v = trt_c_probe_named(dll.c_str()) as Int;
  }
  let e = trt_err();
  if e.kind != TRT_OK {
    return Err(e);
  }
  if v <= 0 {
    return Err(TrtError{ kind: TRT_CALL_FAILED; message: "TensorRT probe failed"; });
  }
  return Ok(trt_info_from_raw(v));
}

/// Close all TensorRT objects and unload the module.  CUDA helpers keep
/// their own lifetime (`trt_cuda_shutdown`).  Complexity: O(objects).
pub fn trt_close() -> Int
  requires: true
{
  return unsafe { trt_c_close() as Int };
}

/// Whether a TensorRT module is currently loaded.  Complexity: O(1).
pub fn trt_loaded() -> Bool
  requires: true
{
  return unsafe { trt_c_loaded() as Int } != 0;
}

/// Decoded version of the loaded module (probes first when not loaded).
/// Complexity: O(1) after load.
pub fn trt_version() -> Result[TrtVersion, TrtError]
  requires: true
{
  if !trt_loaded() {
    let p = trt_probe();
    if p.is_err {
      return Err(p.error);
    }
  }
  let raw = unsafe { trt_c_version_raw() as Int };
  if raw <= 0 {
    return Err(TrtError{ kind: TRT_CALL_FAILED; message: "TensorRT is not loaded"; });
  }
  let major = unsafe { trt_c_version_major() as Int };
  let minor = unsafe { trt_c_version_minor() as Int };
  let patch = unsafe { trt_c_version_patch() as Int };
  return Ok(TrtVersion{ raw: raw; major: major; minor: minor; patch: patch; build: 0; });
}

// =========================================================================
// Logger plumbing
// =========================================================================

/// Create an application logger.  Severity 0..4; messages at or below the
/// threshold are retained (the last one is readable).  Complexity: O(1).
pub fn trt_logger_create(severity: Int) -> Result[Int, TrtError]
  requires: severity >= 0 && severity <= 4
{
  let h = unsafe { trt_c_logger_create(severity as Int32) as Int };
  return trt_handle_result(h, "trt_logger_create");
}

/// Release a logger handle.  Builders created from it hold a shared
/// reference until they are destroyed.  Complexity: O(1).
pub fn trt_logger_destroy(id: Int) {
  let ig = unsafe { trt_c_logger_destroy(id) as Int };
}

/// Set the capture threshold (0 = internal error .. 4 = verbose).
/// Complexity: O(1).
pub fn trt_logger_set_severity(id: Int, severity: Int) -> Result[Int, TrtError]
  requires: severity >= 0 && severity <= 4
{
  let v = unsafe { trt_c_logger_set_severity(id, severity as Int32) as Int };
  return trt_ok_result(v, "trt_logger_set_severity");
}

/// Current capture threshold.  Complexity: O(1).
pub fn trt_logger_severity(id: Int) -> Result[Int, TrtError]
  requires: true
{
  let v = unsafe { trt_c_logger_severity(id) as Int };
  return trt_int_result(v, "trt_logger_severity");
}

/// Number of messages observed since the logger was created.
/// Complexity: O(1).
pub fn trt_logger_message_count(id: Int) -> Result[Int, TrtError]
  requires: true
{
  let v = unsafe { trt_c_logger_message_count(id) as Int };
  return trt_int_result(v, "trt_logger_message_count");
}

/// Last captured message (empty when nothing at/below the threshold was
/// logged).  Complexity: O(1).
pub fn trt_logger_last_message(id: Int) -> Result[Str, TrtError]
  requires: true
{
  var s = "";
  unsafe {
    let p = trt_c_logger_last_message(id);
    if (p as Int) != 0 {
      s = Str::from_c_str(p);
    }
  }
  let e = trt_err();
  if e.kind != TRT_OK {
    return Err(e);
  }
  return Ok(s);
}

/// Severity of the last observed message (-1 before the first message).
/// Complexity: O(1).
pub fn trt_logger_last_severity(id: Int) -> Result[Int, TrtError]
  requires: true
{
  let v = unsafe { trt_c_logger_last_severity(id) as Int };
  return trt_int_result(v, "trt_logger_last_severity");
}

// =========================================================================
// Builder
// =========================================================================

/// Create an inference builder bound to `logger` (TensorRT 10 factory).
/// Complexity: O(builder init).
pub fn trt_builder_create(logger: Int) -> Result[Int, TrtError]
  requires: logger > 0
{
  let h = unsafe { trt_c_builder_create(logger) as Int };
  return trt_handle_result(h, "trt_builder_create");
}

/// Release a builder.  Destroy its networks/configs first.
/// Complexity: O(1).
pub fn trt_builder_destroy(id: Int) {
  let ig = unsafe { trt_c_builder_destroy(id) as Int };
}

/// Native FP16 support on the active platform.  Complexity: O(1).
pub fn trt_builder_platform_has_fp16(id: Int) -> Result[Bool, TrtError]
  requires: id > 0
{
  let v = unsafe { trt_c_builder_platform_has_fp16(id) as Int };
  return trt_bool_result(v, "trt_builder_platform_has_fp16");
}

/// Native INT8 support on the active platform.  Complexity: O(1).
pub fn trt_builder_platform_has_int8(id: Int) -> Result[Bool, TrtError]
  requires: id > 0
{
  let v = unsafe { trt_c_builder_platform_has_int8(id) as Int };
  return trt_bool_result(v, "trt_builder_platform_has_int8");
}

/// Native TF32 support on the active platform.  Complexity: O(1).
pub fn trt_builder_platform_has_tf32(id: Int) -> Result[Bool, TrtError]
  requires: id > 0
{
  let v = unsafe { trt_c_builder_platform_has_tf32(id) as Int };
  return trt_bool_result(v, "trt_builder_platform_has_tf32");
}

/// Create an empty network definition (explicit batch is the 10.x default).
/// Complexity: O(1).
pub fn trt_builder_create_network(id: Int) -> Result[Int, TrtError]
  requires: id > 0
{
  let h = unsafe { trt_c_builder_create_network(id) as Int };
  return trt_handle_result(h, "trt_builder_create_network");
}

/// Create a builder configuration (default profiles/tactics/memory pools).
/// Complexity: O(1).
pub fn trt_builder_create_config(id: Int) -> Result[Int, TrtError]
  requires: id > 0
{
  let h = unsafe { trt_c_builder_create_config(id) as Int };
  return trt_handle_result(h, "trt_builder_create_config");
}

/// Build the network and return a serialized plan (`IHostMemory` handle).
/// This is the TensorRT 10 build+serialize path.  Complexity: O(build).
pub fn trt_builder_build_serialized(builder: Int, network: Int, config: Int) -> Result[Int, TrtError]
  requires: builder > 0 && network > 0 && config > 0
{
  let h = unsafe { trt_c_builder_build_serialized(builder, network, config) as Int };
  return trt_handle_result(h, "trt_builder_build_serialized");
}

// =========================================================================
// Network definition
// =========================================================================

/// Add a network input with a 0..8 dimensional shape (`-1` is dynamic).
/// Complexity: O(1).
pub fn trt_network_add_input(net: Int, name: Str, dtype: Int,
                             d0: Int, d1: Int, d2: Int, d3: Int,
                             d4: Int, d5: Int, d6: Int, d7: Int,
                             ndim: Int) -> Result[Int, TrtError]
  requires: net > 0 && name.len() > 0 && ndim >= 0 && ndim <= 8
{
  let h = unsafe {
    trt_c_network_add_input(net, name.c_str(), dtype as Int32,
                          d0, d1, d2, d3, d4, d5, d6, d7, ndim as Int32) as Int
  };
  return trt_handle_result(h, "trt_network_add_input");
}

/// Convenience: 2-D input.  Complexity: O(1).
pub fn trt_network_add_input_2d(net: Int, name: Str, dtype: Int,
                                d0: Int, d1: Int) -> Result[Int, TrtError]
  requires: net > 0 && name.len() > 0
{
  return trt_network_add_input(net, name, dtype, d0, d1, 0, 0, 0, 0, 0, 0, 2);
}

/// Add an identity layer and return its output tensor.  Complexity: O(1).
pub fn trt_network_add_identity(net: Int, input: Int) -> Result[Int, TrtError]
  requires: net > 0 && input > 0
{
  let h = unsafe { trt_c_network_add_identity(net, input) as Int };
  return trt_handle_result(h, "trt_network_add_identity");
}

/// Add a constant Float32 tensor filled with `value`, returning its output
/// tensor.  The bridge keeps the weights alive until the network is
/// destroyed (TensorRT holds them by reference until build).
/// Complexity: O(volume).
pub fn trt_network_add_constant_f32(net: Int, value: Float32,
                                    d0: Int, d1: Int, d2: Int, d3: Int,
                                    d4: Int, d5: Int, d6: Int, d7: Int,
                                    ndim: Int) -> Result[Int, TrtError]
  requires: net > 0 && ndim >= 0 && ndim <= 8
{
  let h = unsafe {
    trt_c_network_add_constant_f32(net, value, d0, d1, d2, d3, d4, d5, d6, d7, ndim as Int32) as Int
  };
  return trt_handle_result(h, "trt_network_add_constant_f32");
}

/// Convenience: 2-D Float32 constant.  Complexity: O(volume).
pub fn trt_network_add_constant_f32_2d(net: Int, value: Float32,
                                       d0: Int, d1: Int) -> Result[Int, TrtError]
  requires: net > 0
{
  return trt_network_add_constant_f32(net, value, d0, d1, 0, 0, 0, 0, 0, 0, 2);
}

/// Add an element-wise layer (`TRT_ELEMENTWISE_*`) and return its output
/// tensor.  Complexity: O(1).
pub fn trt_network_add_elementwise(net: Int, op: Int, a: Int, b: Int) -> Result[Int, TrtError]
  requires: net > 0 && a > 0 && b > 0 && op >= 0 && op <= 13
{
  let h = unsafe { trt_c_network_add_elementwise(net, op as Int32, a, b) as Int };
  return trt_handle_result(h, "trt_network_add_elementwise");
}

/// Mark a tensor as a network output.  Complexity: O(1).
pub fn trt_network_mark_output(net: Int, tensor: Int) -> Result[Int, TrtError]
  requires: net > 0 && tensor > 0
{
  let v = unsafe { trt_c_network_mark_output(net, tensor) as Int };
  return trt_ok_result(v, "trt_network_mark_output");
}

/// Number of layers in the definition.  Complexity: O(1).
pub fn trt_network_nb_layers(net: Int) -> Result[Int, TrtError]
  requires: net > 0
{
  let v = unsafe { trt_c_network_nb_layers(net) as Int };
  return trt_int_result(v, "trt_network_nb_layers");
}

/// Number of network inputs.  Complexity: O(1).
pub fn trt_network_nb_inputs(net: Int) -> Result[Int, TrtError]
  requires: net > 0
{
  let v = unsafe { trt_c_network_nb_inputs(net) as Int };
  return trt_int_result(v, "trt_network_nb_inputs");
}

/// Number of network outputs.  Complexity: O(1).
pub fn trt_network_nb_outputs(net: Int) -> Result[Int, TrtError]
  requires: net > 0
{
  let v = unsafe { trt_c_network_nb_outputs(net) as Int };
  return trt_int_result(v, "trt_network_nb_outputs");
}

/// Borrowed input tensor at `index`.  Complexity: O(1).
pub fn trt_network_input(net: Int, index: Int) -> Result[Int, TrtError]
  requires: net > 0 && index >= 0
{
  let h = unsafe { trt_c_network_input(net, index as Int32) as Int };
  return trt_handle_result(h, "trt_network_input");
}

/// Borrowed output tensor at `index`.  Complexity: O(1).
pub fn trt_network_output(net: Int, index: Int) -> Result[Int, TrtError]
  requires: net > 0 && index >= 0
{
  let h = unsafe { trt_c_network_output(net, index as Int32) as Int };
  return trt_handle_result(h, "trt_network_output");
}

/// Borrowed layer at `index`.  Complexity: O(1).
pub fn trt_network_layer(net: Int, index: Int) -> Result[Int, TrtError]
  requires: net > 0 && index >= 0
{
  let h = unsafe { trt_c_network_layer(net, index as Int32) as Int };
  return trt_handle_result(h, "trt_network_layer");
}

/// Release a network.  All tensor/layer handles borrowed from it become
/// invalid; destroy configs/builders separately.  Complexity: O(1).
pub fn trt_network_destroy(net: Int) {
  let ig = unsafe { trt_c_network_destroy(net) as Int };
}

// =========================================================================
// Tensor / layer
// =========================================================================

/// Name a tensor (e.g. the output so it can be addressed by name).
/// Complexity: O(1).
pub fn trt_tensor_set_name(tensor: Int, name: Str) -> Result[Int, TrtError]
  requires: tensor > 0 && name.len() > 0
{
  let v = unsafe { trt_c_tensor_set_name(tensor, name.c_str()) as Int };
  return trt_ok_result(v, "trt_tensor_set_name");
}

/// Tensor name.  Complexity: O(1).
pub fn trt_tensor_name(tensor: Int) -> Result[Str, TrtError]
  requires: tensor > 0
{
  var s = "";
  unsafe {
    let p = trt_c_tensor_name(tensor);
    if (p as Int) != 0 {
      s = Str::from_c_str(p);
    }
  }
  let e = trt_err();
  if e.kind != TRT_OK {
    return Err(e);
  }
  return Ok(s);
}

/// Tensor data type code (`TRT_DTYPE_*`).  Complexity: O(1).
pub fn trt_tensor_dtype(tensor: Int) -> Result[Int, TrtError]
  requires: tensor > 0
{
  let v = unsafe { trt_c_tensor_dtype(tensor) as Int };
  return trt_int_result(v, "trt_tensor_dtype");
}

/// Tensor rank.  Complexity: O(1).
pub fn trt_tensor_ndim(tensor: Int) -> Result[Int, TrtError]
  requires: tensor > 0
{
  let v = unsafe { trt_c_tensor_ndim(tensor) as Int };
  return trt_int_result(v, "trt_tensor_ndim");
}

/// Extent of dimension `index` (-1 for a dynamic extent).
/// Complexity: O(1).
pub fn trt_tensor_dim(tensor: Int, index: Int) -> Result[Int, TrtError]
  requires: tensor > 0 && index >= 0
{
  let v = unsafe { trt_c_tensor_dim(tensor, index as Int32) as Int };
  return trt_dim_result(v, "trt_tensor_dim");
}

/// Full shape as an independent Vec.  Complexity: O(rank).
pub fn trt_tensor_dims(tensor: Int) -> Result[Vec[Int], TrtError]
  requires: tensor > 0
{
  let n = trt_tensor_ndim(tensor);
  if n.is_err {
    return Err(n.error);
  }
  var out: Vec[Int] = Vec[Int].new();
  var i = 0;
  while i < n.value {
    let d = trt_tensor_dim(tensor, i);
    if d.is_err {
      return Err(d.error);
    }
    out.push(d.value);
    i = i + 1;
  }
  return Ok(out);
}

/// Whether the tensor is a network input.  Complexity: O(1).
pub fn trt_tensor_is_input(tensor: Int) -> Result[Bool, TrtError]
  requires: tensor > 0
{
  let v = unsafe { trt_c_tensor_is_input(tensor) as Int };
  return trt_bool_result(v, "trt_tensor_is_input");
}

/// Whether the tensor is a network output.  Complexity: O(1).
pub fn trt_tensor_is_output(tensor: Int) -> Result[Bool, TrtError]
  requires: tensor > 0
{
  let v = unsafe { trt_c_tensor_is_output(tensor) as Int };
  return trt_bool_result(v, "trt_tensor_is_output");
}

/// Layer type code (`LayerType`).  Complexity: O(1).
pub fn trt_layer_type(layer: Int) -> Result[Int, TrtError]
  requires: layer > 0
{
  let v = unsafe { trt_c_layer_type(layer) as Int };
  return trt_int_result(v, "trt_layer_type");
}

/// Layer name (empty for an unnamed layer).  Complexity: O(1).
pub fn trt_layer_name(layer: Int) -> Result[Str, TrtError]
  requires: layer > 0
{
  var s = "";
  unsafe {
    let p = trt_c_layer_name(layer);
    if (p as Int) != 0 {
      s = Str::from_c_str(p);
    }
  }
  let e = trt_err();
  if e.kind != TRT_OK {
    return Err(e);
  }
  return Ok(s);
}

// =========================================================================
// Builder config
// =========================================================================

/// Set a builder flag (`TRT_FLAG_*`).  Complexity: O(1).
pub fn trt_config_set_flag(config: Int, flag: Int, value: Bool) -> Result[Int, TrtError]
  requires: config > 0 && flag >= 0
{
  let v32: Int32 = if value { 1 } else { 0 };
  let v = unsafe { trt_c_config_set_flag(config, flag as Int32, v32) as Int };
  return trt_ok_result(v, "trt_config_set_flag");
}

/// Read a builder flag.  Complexity: O(1).
pub fn trt_config_get_flag(config: Int, flag: Int) -> Result[Bool, TrtError]
  requires: config > 0 && flag >= 0
{
  let v = unsafe { trt_c_config_get_flag(config, flag as Int32) as Int };
  return trt_bool_result(v, "trt_config_get_flag");
}

/// Set a memory-pool limit in bytes (`TRT_POOL_*`).  Complexity: O(1).
pub fn trt_config_set_memory_pool_limit(config: Int, pool: Int, bytes: Int) -> Result[Int, TrtError]
  requires: config > 0 && pool >= 0 && bytes >= 0
{
  let v = unsafe { trt_c_config_set_memory_pool_limit(config, pool as Int32, bytes) as Int };
  return trt_ok_result(v, "trt_config_set_memory_pool_limit");
}

/// Current memory-pool limit in bytes.  Complexity: O(1).
pub fn trt_config_memory_pool_limit(config: Int, pool: Int) -> Result[Int, TrtError]
  requires: config > 0 && pool >= 0
{
  let v = unsafe { trt_c_config_memory_pool_limit(config, pool as Int32) as Int };
  return trt_dim_result(v, "trt_config_memory_pool_limit");
}

/// Restrict the tactic sources (bitmask; 0 = all defaults).
/// Complexity: O(1).
pub fn trt_config_set_tactic_sources(config: Int, mask: Int) -> Result[Int, TrtError]
  requires: config > 0 && mask >= 0
{
  let v = unsafe { trt_c_config_set_tactic_sources(config, mask) as Int };
  return trt_ok_result(v, "trt_config_set_tactic_sources");
}

/// Current tactic-source bitmask.  Complexity: O(1).
pub fn trt_config_tactic_sources(config: Int) -> Result[Int, TrtError]
  requires: config > 0
{
  let v = unsafe { trt_c_config_tactic_sources(config) as Int };
  return trt_dim_result(v, "trt_config_tactic_sources");
}

/// Release a builder config.  Complexity: O(1).
pub fn trt_config_destroy(config: Int) {
  let ig = unsafe { trt_c_config_destroy(config) as Int };
}

// =========================================================================
// Serialized plan (host memory)
// =========================================================================

/// Serialized plan size in bytes.  Complexity: O(1).
pub fn trt_host_memory_size(host: Int) -> Result[Int, TrtError]
  requires: host > 0
{
  let v = unsafe { trt_c_host_memory_size(host) as Int };
  return trt_int_result(v, "trt_host_memory_size");
}

/// Borrowed plan data address (valid until the host-memory handle is
/// destroyed).  Complexity: O(1).
pub fn trt_host_memory_data(host: Int) -> Result[Int, TrtError]
  requires: host > 0
{
  let v = unsafe { trt_c_host_memory_data(host) as Int };
  return trt_dim_result(v, "trt_host_memory_data");
}

/// Write the serialized plan to a file.  Complexity: O(size).
pub fn trt_host_memory_save(host: Int, path: Str) -> Result[Int, TrtError]
  requires: host > 0 && path.len() > 0
{
  let v = unsafe { trt_c_host_memory_save(host, path.c_str()) as Int };
  return trt_ok_result(v, "trt_host_memory_save");
}

/// Read a serialized plan from a file into a host-memory handle.
/// Complexity: O(size).
pub fn trt_host_memory_load(path: Str) -> Result[Int, TrtError]
  requires: path.len() > 0
{
  let h = unsafe { trt_c_host_memory_load(path.c_str()) as Int };
  return trt_handle_result(h, "trt_host_memory_load");
}

/// Release a host-memory handle (engine plan or file-backed plan).
/// Complexity: O(1).
pub fn trt_host_memory_destroy(host: Int) {
  let ig = unsafe { trt_c_host_memory_destroy(host) as Int };
}

// =========================================================================
// Runtime / engine
// =========================================================================

/// Create an inference runtime bound to `logger`.  Complexity: O(1).
pub fn trt_runtime_create(logger: Int) -> Result[Int, TrtError]
  requires: logger > 0
{
  let h = unsafe { trt_c_runtime_create(logger) as Int };
  return trt_handle_result(h, "trt_runtime_create");
}

/// Release a runtime.  Destroy its engines first.  Complexity: O(1).
pub fn trt_runtime_destroy(runtime: Int) {
  let ig = unsafe { trt_c_runtime_destroy(runtime) as Int };
}

/// Deserialize an engine from a raw plan address/size.  Complexity: O(load).
pub fn trt_runtime_deserialize(runtime: Int, data_addr: Int, size: Int) -> Result[Int, TrtError]
  requires: runtime > 0 && data_addr > 0 && size > 0
{
  let h = unsafe { trt_c_runtime_deserialize(runtime, data_addr, size) as Int };
  return trt_handle_result(h, "trt_runtime_deserialize");
}

/// Deserialize an engine from a host-memory plan handle.  Complexity: O(load).
pub fn trt_runtime_deserialize_memory(runtime: Int, host: Int) -> Result[Int, TrtError]
  requires: runtime > 0 && host > 0
{
  let h = unsafe { trt_c_runtime_deserialize_memory(runtime, host) as Int };
  return trt_handle_result(h, "trt_runtime_deserialize_memory");
}

/// Release an engine.  Destroy its execution contexts first.
/// Complexity: O(1).
pub fn trt_engine_destroy(engine: Int) {
  let ig = unsafe { trt_c_engine_destroy(engine) as Int };
}

/// Number of IO tensors in the engine.  Complexity: O(1).
pub fn trt_engine_nb_io_tensors(engine: Int) -> Result[Int, TrtError]
  requires: engine > 0
{
  let v = unsafe { trt_c_engine_nb_io_tensors(engine) as Int };
  return trt_int_result(v, "trt_engine_nb_io_tensors");
}

/// IO tensor name at `index`.  Complexity: O(1).
pub fn trt_engine_io_tensor_name(engine: Int, index: Int) -> Result[Str, TrtError]
  requires: engine > 0 && index >= 0
{
  var s = "";
  unsafe {
    let p = trt_c_engine_io_tensor_name(engine, index as Int32);
    if (p as Int) != 0 {
      s = Str::from_c_str(p);
    }
  }
  let e = trt_err();
  if e.kind != TRT_OK {
    return Err(e);
  }
  return Ok(s);
}

/// Engine tensor data type (`TRT_DTYPE_*`).  Complexity: O(1).
pub fn trt_engine_tensor_dtype(engine: Int, name: Str) -> Result[Int, TrtError]
  requires: engine > 0 && name.len() > 0
{
  let v = unsafe { trt_c_engine_tensor_dtype(engine, name.c_str()) as Int };
  return trt_int_result(v, "trt_engine_tensor_dtype");
}

/// Engine tensor location (`TRT_TENSOR_LOCATION_*`).  Complexity: O(1).
pub fn trt_engine_tensor_location(engine: Int, name: Str) -> Result[Int, TrtError]
  requires: engine > 0 && name.len() > 0
{
  let v = unsafe { trt_c_engine_tensor_location(engine, name.c_str()) as Int };
  return trt_int_result(v, "trt_engine_tensor_location");
}

/// Engine tensor IO mode (`TRT_IO_INPUT` / `TRT_IO_OUTPUT`).
/// Complexity: O(1).
pub fn trt_engine_tensor_io_mode(engine: Int, name: Str) -> Result[Int, TrtError]
  requires: engine > 0 && name.len() > 0
{
  let v = unsafe { trt_c_engine_tensor_io_mode(engine, name.c_str()) as Int };
  return trt_int_result(v, "trt_engine_tensor_io_mode");
}

/// Engine tensor rank.  Complexity: O(1).
pub fn trt_engine_tensor_ndim(engine: Int, name: Str) -> Result[Int, TrtError]
  requires: engine > 0 && name.len() > 0
{
  let v = unsafe { trt_c_engine_tensor_ndim(engine, name.c_str()) as Int };
  return trt_int_result(v, "trt_engine_tensor_ndim");
}

/// Engine tensor extent at `index`.  Complexity: O(1).
pub fn trt_engine_tensor_dim(engine: Int, name: Str, index: Int) -> Result[Int, TrtError]
  requires: engine > 0 && name.len() > 0 && index >= 0
{
  let v = unsafe { trt_c_engine_tensor_dim(engine, name.c_str(), index as Int32) as Int };
  return trt_dim_result(v, "trt_engine_tensor_dim");
}

/// Full engine tensor shape.  Complexity: O(rank).
pub fn trt_engine_tensor_dims(engine: Int, name: Str) -> Result[Vec[Int], TrtError]
  requires: engine > 0 && name.len() > 0
{
  let n = trt_engine_tensor_ndim(engine, name);
  if n.is_err {
    return Err(n.error);
  }
  var out: Vec[Int] = Vec[Int].new();
  var i = 0;
  while i < n.value {
    let d = trt_engine_tensor_dim(engine, name, i);
    if d.is_err {
      return Err(d.error);
    }
    out.push(d.value);
    i = i + 1;
  }
  return Ok(out);
}

/// Create an execution context (engine device memory allocated).
/// Complexity: O(engine).
pub fn trt_engine_create_context(engine: Int) -> Result[Int, TrtError]
  requires: engine > 0
{
  let h = unsafe { trt_c_engine_create_context(engine) as Int };
  return trt_handle_result(h, "trt_engine_create_context");
}

// =========================================================================
// Execution context
// =========================================================================

/// Release an execution context.  Complexity: O(1).
pub fn trt_context_destroy(ctx: Int) {
  let ig = unsafe { trt_c_context_destroy(ctx) as Int };
}

/// Set an input shape (required for dynamic inputs; harmless for static).
/// Complexity: O(1).
pub fn trt_context_set_input_shape(ctx: Int, name: Str,
                                   d0: Int, d1: Int, d2: Int, d3: Int,
                                   d4: Int, d5: Int, d6: Int, d7: Int,
                                   ndim: Int) -> Result[Int, TrtError]
  requires: ctx > 0 && name.len() > 0 && ndim >= 0 && ndim <= 8
{
  let v = unsafe {
    trt_c_context_set_input_shape(ctx, name.c_str(), d0, d1, d2, d3, d4, d5, d6, d7, ndim as Int32) as Int
  };
  return trt_ok_result(v, "trt_context_set_input_shape");
}

/// Bind a device address to a named engine tensor.  Complexity: O(1).
pub fn trt_context_set_tensor_address(ctx: Int, name: Str, addr: Int) -> Result[Int, TrtError]
  requires: ctx > 0 && name.len() > 0 && addr >= 0
{
  let v = unsafe { trt_c_context_set_tensor_address(ctx, name.c_str(), addr) as Int };
  return trt_ok_result(v, "trt_context_set_tensor_address");
}

/// Currently bound address for a tensor (0 when unset).  Complexity: O(1).
pub fn trt_context_tensor_address(ctx: Int, name: Str) -> Result[Int, TrtError]
  requires: ctx > 0 && name.len() > 0
{
  let v = unsafe { trt_c_context_tensor_address(ctx, name.c_str()) as Int };
  return trt_dim_result(v, "trt_context_tensor_address");
}

/// Whether all input dimensions are specified.  Complexity: O(1).
pub fn trt_context_all_input_dims_specified(ctx: Int) -> Result[Bool, TrtError]
  requires: ctx > 0
{
  let v = unsafe { trt_c_context_all_input_dims_specified(ctx) as Int };
  return trt_bool_result(v, "trt_context_all_input_dims_specified");
}

/// Enqueue inference on `stream` (a handle from `trt_cuda_stream_create`).
/// TensorRT 10 uses `enqueueV3`; the 8.x `enqueueV2` fallback is not enabled
/// in 0.1.0 (the loader rejects other majors).  Complexity: O(enqueue).
pub fn trt_context_enqueue(ctx: Int, stream: Int) -> Result[Int, TrtError]
  requires: ctx > 0 && stream > 0
{
  let v = unsafe { trt_c_context_enqueue(ctx, stream) as Int };
  return trt_ok_result(v, "trt_context_enqueue");
}

// =========================================================================
// CUDA driver helpers (device memory + stream for the live path)
// =========================================================================

/// Initialise the CUDA driver API and activate the primary context.
/// Call this BEFORE creating the TensorRT builder.  No NVIDIA GPU ->
/// `TRT_NO_DEVICE` (SKIP).  Complexity: O(init).
pub fn trt_cuda_init() -> Result[Int, TrtError]
  requires: true
{
  let v = unsafe { trt_c_cuda_init() as Int };
  return trt_ok_result(v, "trt_cuda_init");
}

/// Release CUDA resources (allocations, primary context, driver module).
/// Complexity: O(allocations).
pub fn trt_cuda_shutdown() -> Int
  requires: true
{
  return unsafe { trt_c_cuda_shutdown() as Int };
}

/// Allocate device memory; returns the device address.  Complexity: O(1).
pub fn trt_cuda_alloc(bytes: Int) -> Result[Int, TrtError]
  requires: bytes > 0
{
  let h = unsafe { trt_c_cuda_alloc(bytes) as Int };
  return trt_handle_result(h, "trt_cuda_alloc");
}

/// Free device memory.  Complexity: O(1).
pub fn trt_cuda_free(ptr: Int) {
  let ig = unsafe { trt_c_cuda_free(ptr) as Int };
}

/// Host -> device copy from a caller-owned address.  Complexity: O(bytes).
pub fn trt_cuda_upload(dev: Int, src: Int, bytes: Int) -> Result[Int, TrtError]
  requires: dev > 0 && src > 0 && bytes > 0
{
  let v = unsafe { trt_c_cuda_upload(dev, src, bytes) as Int };
  return trt_ok_result(v, "trt_cuda_upload");
}

/// Device -> host copy into a caller-owned address.  Complexity: O(bytes).
pub fn trt_cuda_download(dst: Int, dev: Int, bytes: Int) -> Result[Int, TrtError]
  requires: dst > 0 && dev > 0 && bytes > 0
{
  let v = unsafe { trt_c_cuda_download(dst, dev, bytes) as Int };
  return trt_ok_result(v, "trt_cuda_download");
}

/// Create a CUDA stream handle.  Complexity: O(1).
pub fn trt_cuda_stream_create() -> Result[Int, TrtError]
  requires: true
{
  let h = unsafe { trt_c_cuda_stream_create() as Int };
  return trt_handle_result(h, "trt_cuda_stream_create");
}

/// Destroy a stream handle.  Complexity: O(1).
pub fn trt_cuda_stream_destroy(stream: Int) {
  let ig = unsafe { trt_c_cuda_stream_destroy(stream) as Int };
}

/// Synchronise a stream handle.  Complexity: O(wait).
pub fn trt_cuda_stream_sync(stream: Int) -> Result[Int, TrtError]
  requires: stream > 0
{
  let v = unsafe { trt_c_cuda_stream_sync(stream) as Int };
  return trt_ok_result(v, "trt_cuda_stream_sync");
}

/// Device 0 name.  Complexity: O(1).
pub fn trt_cuda_device_name() -> Result[Str, TrtError]
  requires: true
{
  var s = "";
  unsafe {
    let p = trt_c_cuda_device_name();
    if (p as Int) != 0 {
      s = Str::from_c_str(p);
    }
  }
  let e = trt_err();
  if e.kind != TRT_OK {
    return Err(e);
  }
  return Ok(s);
}

/// CUDA device count.  Complexity: O(1).
pub fn trt_cuda_device_count() -> Result[Int, TrtError]
  requires: true
{
  let v = unsafe { trt_c_cuda_device_count() as Int };
  return trt_int_result(v, "trt_cuda_device_count");
}

// =========================================================================

// =========================================================================
// Bulk engine introspection helper
// =========================================================================

/// Names of all engine IO tensors, in engine order.  Use the per-name
/// accessors for dtype/mode/location/shape.  Complexity: O(io tensors).
pub fn trt_engine_io_tensor_names(engine: Int) -> Result[Vec[Str], TrtError]
  requires: engine > 0
{
  let n = trt_engine_nb_io_tensors(engine);
  if n.is_err {
    return Err(n.error);
  }
  var out: Vec[Str] = Vec[Str].new();
  var i = 0;
  while i < n.value {
    let name = trt_engine_io_tensor_name(engine, i);
    if name.is_err {
      return Err(name.error);
    }
    out.push(name.value);
    i = i + 1;
  }
  return Ok(out);
}
