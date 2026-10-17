// XIOM -- xiom.onnx.types: shared types and the ONNX Runtime C API constant set.
// Copyright (c) 2026 Eleftheros Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Oracle: microsoft/onnxruntime, pinned v1.31.0 =
// commit 402979ac1bef89dcd55add41eaa7277c407599eb
// (include/onnxruntime/core/session/onnxruntime_c_api.h +
// onnxruntime_error_code.h). Every constant below is transcribed from that
// header; the OrtApi member indices are declared in the loader module and
// verified against the header mechanically (see SPEC.md section 2).

module xiom.onnx.types

// =========================================================================
// High-level model/tensor/config types (pure XIOM tier)
// =========================================================================

/// A model handle: the runtime library, ORT env, session and allocator kept
/// together so the high-level API can run inference without extra plumbing.
/// `session == 0` only ever exists for a value that failed to load.
pub type OnnxModel = {
  path: Str;
  session: Int;
  env: Int;
  allocator: Int;
  api: Int;
  handle: Int;
  input_names: Vec[Str];
  output_names: Vec[Str];
}

pub type OnnxTensor = {
  name: Str;
  data: Vec[Float32];
  shape: Vec[Int];
  dtype: Int;
}

pub type OnnxConfig = {
  num_threads: Int;
  graph_optimization_level: Int;
  enable_profiling: Bool;
}

pub fn onnx_config_default() -> OnnxConfig {
  return OnnxConfig{
    num_threads: 4,
    graph_optimization_level: 1,
    enable_profiling: false,
  };
}

// =========================================================================
// Loader classification + typed error
// =========================================================================

/// No candidate soname loaded: the typed SKIP state.
pub const ONNX_LOAD_ABSENT: Int = 0;
/// A candidate loaded but the entry-point set / version is unusable: FAIL.
pub const ONNX_LOAD_ABI: Int = 1;
/// The loaded runtime does not expose the requested execution provider (for
/// example a CPU-only ORT build asked for DirectML): the typed SKIP state for
/// provider-specific legs. Distinct from ONNX_LOAD_ABSENT (no runtime at all).
pub const ONNX_EP_ABSENT: Int = 3;

/// Loader/runtime failure: kind is ONNX_LOAD_ABSENT / ONNX_LOAD_ABI (or a
/// call-failure kind below).
pub type OnnxError = {
  kind: Int;
  message: Str;
}

/// One loaded ONNX Runtime build: the dl handle, the OrtApiBase pointer, the
/// resolved OrtApi table, the negotiated API version and the resolved-entry
/// counts of the declared surface.
pub type OnnxLibrary = {
  handle: Int;
  soname: Str;
  base: Int;
  api: Int;
  api_version: Int;
  version: Str;
  resolved: Int;
  required: Int;
}

/// Probe result (version + surface counts).
pub type OnnxInfo = {
  soname: Str;
  version: Str;
  api_version: Int;
  resolved: Int;
  required: Int;
}

/// A list of strings. Wrapped in a struct because a bare `Vec[Str]` as a
/// Result payload loses its elements on the pinned compiler (v0.64.5
/// codegen defect; see AUDIT.md "Compiler findings"): struct-wrapped it
/// round-trips correctly.
pub type OnnxStrList = {
  items: Vec[Str];
}

/// A list of Float32 values (same Result-payload wrapper reason as
/// OnnxStrList).
pub type OnnxF32List = {
  items: Vec[Float32];
}

/// A list of tensors (same Result-payload wrapper reason; OnnxTensor
/// carries Str/Vec fields).
pub type OnnxTensorList = {
  items: Vec[OnnxTensor];
}

// =========================================================================
// API versioning (oracle: onnxruntime_c_api.h defines)
// =========================================================================

/// The ORT_API_VERSION this package compiled its table indices against
/// (oracle: `#define ORT_API_VERSION 31` at the pinned header).
pub const ORT_API_VERSION_PIN: Int = 31;

/// Declared floor: every declared surface member exists (at the same table
/// index, append-only) since runtime 1.14; older builds are rejected as ABI.
pub const ONNX_MIN_API_VERSION: Int = 14;

// =========================================================================
// ONNXTensorElementDataType (oracle: enum, header lines 194..227)
// =========================================================================

pub const ORT_DTYPE_UNDEFINED: Int = 0;
pub const ORT_DTYPE_FLOAT: Int = 1;
pub const ORT_DTYPE_UINT8: Int = 2;
pub const ORT_DTYPE_INT8: Int = 3;
pub const ORT_DTYPE_UINT16: Int = 4;
pub const ORT_DTYPE_INT16: Int = 5;
pub const ORT_DTYPE_INT32: Int = 6;
pub const ORT_DTYPE_INT64: Int = 7;
pub const ORT_DTYPE_STRING: Int = 8;
pub const ORT_DTYPE_BOOL: Int = 9;
pub const ORT_DTYPE_FLOAT16: Int = 10;
pub const ORT_DTYPE_DOUBLE: Int = 11;
pub const ORT_DTYPE_UINT32: Int = 12;
pub const ORT_DTYPE_UINT64: Int = 13;
pub const ORT_DTYPE_COMPLEX64: Int = 14;
pub const ORT_DTYPE_COMPLEX128: Int = 15;
pub const ORT_DTYPE_BFLOAT16: Int = 16;
pub const ORT_DTYPE_FLOAT8E4M3FN: Int = 17;
pub const ORT_DTYPE_FLOAT8E4M3FNUZ: Int = 18;
pub const ORT_DTYPE_FLOAT8E5M2: Int = 19;
pub const ORT_DTYPE_FLOAT8E5M2FNUZ: Int = 20;
pub const ORT_DTYPE_UINT4: Int = 21;
pub const ORT_DTYPE_INT4: Int = 22;
pub const ORT_DTYPE_FLOAT4E2M1: Int = 23;
pub const ORT_DTYPE_UINT2: Int = 24;
pub const ORT_DTYPE_INT2: Int = 25;
pub const ORT_DTYPE_FLOAT8E8M0: Int = 26;

// =========================================================================
// GraphOptimizationLevel / ExecutionMode (oracle: enums)
// =========================================================================

pub const ORT_GRAPH_OPT_DISABLE: Int = 0;
pub const ORT_GRAPH_OPT_BASIC: Int = 1;
pub const ORT_GRAPH_OPT_EXTENDED: Int = 2;
pub const ORT_GRAPH_OPT_LAYOUT: Int = 3;
pub const ORT_GRAPH_OPT_ALL: Int = 99;

pub const ORT_EXECUTION_MODE_SEQUENTIAL: Int = 0;
pub const ORT_EXECUTION_MODE_PARALLEL: Int = 1;

// =========================================================================
// OrtLoggingLevel (oracle: enum)
// =========================================================================

pub const ORT_LOGGING_LEVEL_VERBOSE: Int = 0;
pub const ORT_LOGGING_LEVEL_INFO: Int = 1;
pub const ORT_LOGGING_LEVEL_WARNING: Int = 2;
pub const ORT_LOGGING_LEVEL_ERROR: Int = 3;
pub const ORT_LOGGING_LEVEL_FATAL: Int = 4;

// =========================================================================
// ONNXType (oracle: enum ONNXType)
// =========================================================================

pub const ONNX_TYPE_UNKNOWN: Int = 0;
pub const ONNX_TYPE_TENSOR: Int = 1;
pub const ONNX_TYPE_SEQUENCE: Int = 2;
pub const ONNX_TYPE_MAP: Int = 3;
pub const ONNX_TYPE_OPAQUE: Int = 4;
pub const ONNX_TYPE_SPARSETENSOR: Int = 5;
pub const ONNX_TYPE_OPTIONAL: Int = 6;

// =========================================================================
// OrtErrorCode (oracle: onnxruntime_error_code.h)
// =========================================================================

pub const ORT_OK: Int = 0;
pub const ORT_FAIL: Int = 1;
pub const ORT_INVALID_ARGUMENT: Int = 2;
pub const ORT_NO_SUCHFILE: Int = 3;
pub const ORT_NO_MODEL: Int = 4;
pub const ORT_ENGINE_ERROR: Int = 5;
pub const ORT_RUNTIME_EXCEPTION: Int = 6;
pub const ORT_INVALID_PROTOBUF: Int = 7;
pub const ORT_MODEL_LOADED: Int = 8;
pub const ORT_NOT_IMPLEMENTED: Int = 9;
pub const ORT_INVALID_GRAPH: Int = 10;
pub const ORT_EP_FAIL: Int = 11;
pub const ORT_MODEL_LOAD_CANCELED: Int = 12;
pub const ORT_MODEL_REQUIRES_COMPILATION: Int = 13;
pub const ORT_NOT_FOUND: Int = 14;
pub const ORT_DEVICE_RESET: Int = 15;

// =========================================================================
// OrtAllocatorType / OrtMemType (oracle: enums)
// =========================================================================

pub const ORT_ALLOCATOR_INVALID: Int = -1;
pub const ORT_ALLOCATOR_DEVICE: Int = 0;
pub const ORT_ALLOCATOR_ARENA: Int = 1;
pub const ORT_ALLOCATOR_READONLY: Int = 2;

pub const ORT_MEM_TYPE_CPU_INPUT: Int = -2;
pub const ORT_MEM_TYPE_CPU_OUTPUT: Int = -1;
pub const ORT_MEM_TYPE_DEFAULT: Int = 0;

// =========================================================================
// DirectML device expectations (oracle: dml_provider_factory.h @ v1.31.0)
// =========================================================================

/// DirectML `device_id` 0: the default DXGI adapter, typically the primary
/// display GPU. DML device ids are DXGI adapter indices in
/// `IDXGIFactory::EnumAdapters` order (0-based); a negative id is invalid and
/// an id beyond the adapter count fails EP creation. On the recorded live
/// host DXGI adapter 0 is the RTX 3070 Ti.
pub const ORT_DML_DEVICE_DEFAULT: Int = 0;

// =========================================================================
// Dtype byte sizes (oracle: element sizes of ONNXTensorElementDataType;
// used by the F32 copy path and by callers sizing buffers)
// =========================================================================

pub fn ort_dtype_size(dtype: Int) -> Int {
  if dtype == ORT_DTYPE_FLOAT { return 4; }
  if dtype == ORT_DTYPE_DOUBLE { return 8; }
  if dtype == ORT_DTYPE_INT8 { return 1; }
  if dtype == ORT_DTYPE_UINT8 { return 1; }
  if dtype == ORT_DTYPE_INT16 { return 2; }
  if dtype == ORT_DTYPE_UINT16 { return 2; }
  if dtype == ORT_DTYPE_INT32 { return 4; }
  if dtype == ORT_DTYPE_UINT32 { return 4; }
  if dtype == ORT_DTYPE_INT64 { return 8; }
  if dtype == ORT_DTYPE_UINT64 { return 8; }
  if dtype == ORT_DTYPE_BOOL { return 1; }
  if dtype == ORT_DTYPE_FLOAT16 { return 2; }
  if dtype == ORT_DTYPE_BFLOAT16 { return 2; }
  return 0;
}

/// Human name of an OrtErrorCode ("" for unknown).
pub fn ort_error_code_name(code: Int) -> Str {
  if code == ORT_OK { return "ok"; }
  if code == ORT_FAIL { return "fail"; }
  if code == ORT_INVALID_ARGUMENT { return "invalid_argument"; }
  if code == ORT_NO_SUCHFILE { return "no_suchfile"; }
  if code == ORT_NO_MODEL { return "no_model"; }
  if code == ORT_ENGINE_ERROR { return "engine_error"; }
  if code == ORT_RUNTIME_EXCEPTION { return "runtime_exception"; }
  if code == ORT_INVALID_PROTOBUF { return "invalid_protobuf"; }
  if code == ORT_MODEL_LOADED { return "model_loaded"; }
  if code == ORT_NOT_IMPLEMENTED { return "not_implemented"; }
  if code == ORT_INVALID_GRAPH { return "invalid_graph"; }
  if code == ORT_EP_FAIL { return "ep_fail"; }
  if code == ORT_MODEL_LOAD_CANCELED { return "model_load_canceled"; }
  if code == ORT_MODEL_REQUIRES_COMPILATION { return "model_requires_compilation"; }
  if code == ORT_NOT_FOUND { return "not_found"; }
  if code == ORT_DEVICE_RESET { return "device_reset"; }
  return "";
}
