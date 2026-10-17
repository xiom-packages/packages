// XIOM -- xiom.tensorflow.types: shared types + the TF C API constant set.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Oracle: tensorflow/tensorflow, pinned commit
// 9dd1241c2a15417ac0c9eb3940f67bd7639b4646 (sparse checkout tensorflow/c;
// headers also cross-checked against the official CPU distribution
// libtensorflow 2.18.1 headers, sha256 in PROVENANCE.md).
//
// Every constant below is transcribed from:
//   tensorflow/c/tf_status.h   (TF_Code via tsl_status.h)
//   tensorflow/c/tf_datatype.h (TF_DataType)
//   tensorflow/c/tf_attrtype.h (TF_AttrType)
//   tensorflow/c/c_api.h       (remainder)

module xiom.tensorflow.types

// =========================================================================
// Loader classification + typed error
// =========================================================================

/// No candidate soname loaded: the typed SKIP state.
pub const TF_LOAD_ABSENT: Int = 0;
/// A candidate loaded but the declared entry-point set / version is unusable.
pub const TF_LOAD_ABI: Int = 1;
/// A call returned a non-OK TF_Status (typed message).
pub const TF_CALL_FAILED: Int = 2;
/// Call shape not expressible on this platform ABI (documented; see AUDIT).
pub const TF_ABI_UNSUPPORTED: Int = 3;

/// Loader/runtime failure: kind is one of the TF_LOAD_*/TF_CALL_FAILED/
/// TF_ABI_UNSUPPORTED constants above.
pub type TfError = {
  kind: Int;
  message: Str;
}

/// One loaded libtensorflow build: the dl handle, the resolved entry-point
/// table (index-aligned with `tf_surface_names()`), the runtime version and
/// the resolved/required surface counts.
pub type TfLibrary = {
  handle: Int;
  soname: Str;
  version: Str;
  fns: Vec[Int];
  resolved: Int;
  required: Int;
}

/// Probe result (version + surface counts).
pub type TfInfo = {
  soname: Str;
  version: Str;
  resolved: Int;
  required: Int;
}

/// A TF_Tensor description read back through the C API.
pub type TfTensorInfo = {
  dtype: Int;
  dims: Vec[Int];
  bytes: Int;
  elements: Int;
}

/// A list of strings (struct-wrapped: a bare `Vec[Str]` as a Result payload
/// loses its elements on the pinned compiler v0.64.5; see AUDIT.md).
pub type TfStrList = {
  items: Vec[Str];
}

/// A list of tensor handles (same Result-payload wrapper reason).
pub type TfTensorList = {
  items: Vec[Int];
}

/// A list of Int values as a Result payload (same wrapper reason).
pub type TfIntList = {
  items: Vec[Int];
}

/// A list of Float32 values as a Result payload (same wrapper reason).
pub type TfF32List = {
  items: Vec[Float32];
}

/// A list of UInt8 bytes as a Result payload (same wrapper reason).
pub type TfByteList = {
  items: Vec[UInt8];
}

// =========================================================================
// Version floor (the declared surface needs TF 2.x C API symbols)
// =========================================================================

/// Declared major-version floor: every declared entry point exists (by
/// symbol name) in the TF 2.x C API line; 1.x builds are rejected as ABI.
pub const TF_MIN_MAJOR: Int = 2;

// =========================================================================
// TF_Code (oracle: tf_status.h -> tsl_status.h; note UNAUTHENTICATED = 16)
// =========================================================================

pub const TF_OK: Int = 0;
pub const TF_CANCELLED: Int = 1;
pub const TF_UNKNOWN: Int = 2;
pub const TF_INVALID_ARGUMENT: Int = 3;
pub const TF_DEADLINE_EXCEEDED: Int = 4;
pub const TF_NOT_FOUND: Int = 5;
pub const TF_ALREADY_EXISTS: Int = 6;
pub const TF_PERMISSION_DENIED: Int = 7;
pub const TF_RESOURCE_EXHAUSTED: Int = 8;
pub const TF_FAILED_PRECONDITION: Int = 9;
pub const TF_ABORTED: Int = 10;
pub const TF_OUT_OF_RANGE: Int = 11;
pub const TF_UNIMPLEMENTED: Int = 12;
pub const TF_INTERNAL: Int = 13;
pub const TF_UNAVAILABLE: Int = 14;
pub const TF_DATA_LOSS: Int = 15;
pub const TF_UNAUTHENTICATED: Int = 16;

/// Human name of a TF_Code ("" for unknown).
/// Complexity: O(1).
pub fn tf_code_name(code: Int) -> Str {
  if code == TF_OK { return "ok"; }
  if code == TF_CANCELLED { return "cancelled"; }
  if code == TF_UNKNOWN { return "unknown"; }
  if code == TF_INVALID_ARGUMENT { return "invalid_argument"; }
  if code == TF_DEADLINE_EXCEEDED { return "deadline_exceeded"; }
  if code == TF_NOT_FOUND { return "not_found"; }
  if code == TF_ALREADY_EXISTS { return "already_exists"; }
  if code == TF_PERMISSION_DENIED { return "permission_denied"; }
  if code == TF_RESOURCE_EXHAUSTED { return "resource_exhausted"; }
  if code == TF_FAILED_PRECONDITION { return "failed_precondition"; }
  if code == TF_ABORTED { return "aborted"; }
  if code == TF_OUT_OF_RANGE { return "out_of_range"; }
  if code == TF_UNIMPLEMENTED { return "unimplemented"; }
  if code == TF_INTERNAL { return "internal"; }
  if code == TF_UNAVAILABLE { return "unavailable"; }
  if code == TF_DATA_LOSS { return "data_loss"; }
  if code == TF_UNAUTHENTICATED { return "unauthenticated"; }
  return "";
}

// =========================================================================
// TF_DataType (oracle: tf_datatype.h; values 1..34, ids as pinned)
// =========================================================================

pub const TF_FLOAT: Int = 1;
pub const TF_DOUBLE: Int = 2;
pub const TF_INT32: Int = 3;
pub const TF_UINT8: Int = 4;
pub const TF_INT16: Int = 5;
pub const TF_INT8: Int = 6;
pub const TF_STRING: Int = 7;
pub const TF_COMPLEX64: Int = 8;
pub const TF_INT64: Int = 9;
pub const TF_BOOL: Int = 10;
pub const TF_QINT8: Int = 11;
pub const TF_QUINT8: Int = 12;
pub const TF_QINT32: Int = 13;
pub const TF_BFLOAT16: Int = 14;
pub const TF_QINT16: Int = 15;
pub const TF_QUINT16: Int = 16;
pub const TF_UINT16: Int = 17;
pub const TF_COMPLEX128: Int = 18;
pub const TF_HALF: Int = 19;
pub const TF_RESOURCE: Int = 20;
pub const TF_VARIANT: Int = 21;
pub const TF_UINT32: Int = 22;
pub const TF_UINT64: Int = 23;
pub const TF_FLOAT8_E5M2: Int = 24;
pub const TF_FLOAT8_E4M3FN: Int = 25;
pub const TF_FLOAT8_E4M3FNUZ: Int = 26;
pub const TF_FLOAT8_E4M3B11FNUZ: Int = 27;
pub const TF_FLOAT8_E5M2FNUZ: Int = 28;
pub const TF_INT4: Int = 29;
pub const TF_UINT4: Int = 30;
pub const TF_INT2: Int = 31;
pub const TF_UINT2: Int = 32;
pub const TF_FLOAT4_E2M1FN: Int = 33;
pub const TF_FLOAT8_E8M0FNU: Int = 34;

/// Size in bytes of one element of a TF_DataType; 0 for variable-length
/// types (TF_STRING, TF_RESOURCE, TF_VARIANT) and unknown ids. Mirrors
/// TF_DataTypeSize; the live leg cross-checks this table against the
/// library (see tests + SPEC coverage table).
/// Complexity: O(1).
pub fn tf_dtype_size(dtype: Int) -> Int {
  if dtype == TF_FLOAT { return 4; }
  if dtype == TF_DOUBLE { return 8; }
  if dtype == TF_INT32 { return 4; }
  if dtype == TF_UINT8 { return 1; }
  if dtype == TF_INT16 { return 2; }
  if dtype == TF_INT8 { return 1; }
  if dtype == TF_STRING { return 0; }
  if dtype == TF_COMPLEX64 { return 8; }
  if dtype == TF_INT64 { return 8; }
  if dtype == TF_BOOL { return 1; }
  if dtype == TF_QINT8 { return 1; }
  if dtype == TF_QUINT8 { return 1; }
  if dtype == TF_QINT32 { return 4; }
  if dtype == TF_BFLOAT16 { return 2; }
  if dtype == TF_QINT16 { return 2; }
  if dtype == TF_QUINT16 { return 2; }
  if dtype == TF_UINT16 { return 2; }
  if dtype == TF_COMPLEX128 { return 16; }
  if dtype == TF_HALF { return 2; }
  if dtype == TF_RESOURCE { return 0; }
  if dtype == TF_VARIANT { return 0; }
  if dtype == TF_UINT32 { return 4; }
  if dtype == TF_UINT64 { return 8; }
  if dtype == TF_FLOAT8_E5M2 { return 1; }
  if dtype == TF_FLOAT8_E4M3FN { return 1; }
  if dtype == TF_FLOAT8_E4M3FNUZ { return 1; }
  if dtype == TF_FLOAT8_E4M3B11FNUZ { return 1; }
  if dtype == TF_FLOAT8_E5M2FNUZ { return 1; }
  if dtype == TF_INT4 { return 0; }
  if dtype == TF_UINT4 { return 0; }
  if dtype == TF_INT2 { return 0; }
  if dtype == TF_UINT2 { return 0; }
  if dtype == TF_FLOAT4_E2M1FN { return 0; }
  if dtype == TF_FLOAT8_E8M0FNU { return 1; }
  return 0;
}

/// Human name of a TF_DataType ("" for unknown).
/// Complexity: O(1).
pub fn tf_dtype_name(dtype: Int) -> Str {
  if dtype == TF_FLOAT { return "float"; }
  if dtype == TF_DOUBLE { return "double"; }
  if dtype == TF_INT32 { return "int32"; }
  if dtype == TF_UINT8 { return "uint8"; }
  if dtype == TF_INT16 { return "int16"; }
  if dtype == TF_INT8 { return "int8"; }
  if dtype == TF_STRING { return "string"; }
  if dtype == TF_COMPLEX64 { return "complex64"; }
  if dtype == TF_INT64 { return "int64"; }
  if dtype == TF_BOOL { return "bool"; }
  if dtype == TF_BFLOAT16 { return "bfloat16"; }
  if dtype == TF_UINT16 { return "uint16"; }
  if dtype == TF_COMPLEX128 { return "complex128"; }
  if dtype == TF_HALF { return "half"; }
  if dtype == TF_RESOURCE { return "resource"; }
  if dtype == TF_VARIANT { return "variant"; }
  if dtype == TF_UINT32 { return "uint32"; }
  if dtype == TF_UINT64 { return "uint64"; }
  if dtype == TF_FLOAT8_E5M2 { return "float8_e5m2"; }
  if dtype == TF_FLOAT8_E4M3FN { return "float8_e4m3fn"; }
  return "";
}

// =========================================================================
// TF_AttrType (oracle: tf_attrtype.h)
// =========================================================================

pub const TF_ATTR_STRING: Int = 0;
pub const TF_ATTR_INT: Int = 1;
pub const TF_ATTR_FLOAT: Int = 2;
pub const TF_ATTR_BOOL: Int = 3;
pub const TF_ATTR_TYPE: Int = 4;
pub const TF_ATTR_SHAPE: Int = 5;
pub const TF_ATTR_TENSOR: Int = 6;
pub const TF_ATTR_PLACEHOLDER: Int = 7;
pub const TF_ATTR_FUNC: Int = 8;
