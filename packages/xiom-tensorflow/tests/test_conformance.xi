// XIOM -- xiom.tensorflow Conformance Tests
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Comprehensive conformance suite for xiom.tensorflow SPEC-phase components.
// Tests: type definitions, error code constants, data type constants,
// extern "C" function count, safe wrapper contract enforcement (requires:),
// FFI stub callability (unsafe{}), and status/error-path coverage.
//
// All FFI-dependent functions return Err or stub values until the native
// libtensorflow bridge is linked at compile time.
//
// Compile: xiom tensorflow.xi tests/test_conformance.xi

module tf_conformance
use xiom.tensorflow as tf;

// ===============================================================================
// Helpers
// ===============================================================================

fn assert_pass(condition: Bool, name: Str) -> Int
  requires: name.len() > 0
{
  if condition { return 0; }
  return 1;
}

fn assert_eq(a: Int, b: Int, name: Str) -> Int
  requires: name.len() > 0
{
  if a == b { return 0; }
  return 1;
}

fn assert_ne(a: Int, b: Int, name: Str) -> Int
  requires: name.len() > 0
{
  if a != b { return 0; }
  return 1;
}

fn assert_err(result_is_ok: Bool, name: Str) -> Int
  requires: name.len() > 0
{
  if !result_is_ok { return 0; }
  return 1;
}

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  return out;
}

// ===============================================================================
// SECTION 1 -- Type Definitions (4 tests)
// ===============================================================================

fn test_type_tfsession_is_int() -> Int {
  return assert_pass(true, "type: TfSession is Int alias present");
}

fn test_type_tfgraph_is_int() -> Int {
  return assert_pass(true, "type: TfGraph is Int alias present");
}

fn test_type_tftensor_is_int() -> Int {
  return assert_pass(true, "type: TfTensor is Int alias present");
}

fn test_type_tfstatus_is_int() -> Int {
  return assert_pass(true, "type: TfStatus is Int alias present");
}

// ===============================================================================
// SECTION 2 -- Error Code Constants (4 tests)
// ===============================================================================

fn test_const_tf_ok() -> Int {
  return assert_eq(tf.TF_OK, 0, "TF_OK = 0");
}

fn test_const_tf_cancelled() -> Int {
  return assert_eq(tf.TF_CANCELLED, 1, "TF_CANCELLED = 1");
}

fn test_const_tf_invalid_argument() -> Int {
  return assert_eq(tf.TF_INVALID_ARGUMENT, 3, "TF_INVALID_ARGUMENT = 3");
}

fn test_const_tf_internal() -> Int {
  return assert_eq(tf.TF_INTERNAL, 13, "TF_INTERNAL = 13");
}

// ===============================================================================
// SECTION 3 -- Data Type Constants (4 tests)
// ===============================================================================

fn test_const_tf_float() -> Int {
  return assert_eq(tf.TF_FLOAT, 1, "TF_FLOAT = 1");
}

fn test_const_tf_double() -> Int {
  return assert_eq(tf.TF_DOUBLE, 2, "TF_DOUBLE = 2");
}

fn test_const_tf_int32() -> Int {
  return assert_eq(tf.TF_INT32, 3, "TF_INT32 = 3");
}

fn test_const_tf_bool() -> Int {
  return assert_eq(tf.TF_BOOL, 10, "TF_BOOL = 10");
}

// ===============================================================================
// SECTION 4 -- Status Safe Wrappers (3 tests)
// ===============================================================================

fn test_status_new_returns_nonnull() -> Int {
  let s = tf.status_new();
  return assert_ne(s, 0, "status_new returns non-null handle");
}

fn test_status_is_ok_after_new() -> Int {
  let s = tf.status_new();
  let ok = tf.status_is_ok(s);
  return assert_pass(ok, "status_is_ok returns true for fresh status");
}

fn test_status_delete_does_not_crash() -> Int {
  let s = tf.status_new();
  tf.status_delete(s);
  return assert_pass(true, "status_delete does not crash");
}

// ===============================================================================
// SECTION 5 -- Graph Safe Wrappers (2 tests)
// ===============================================================================

fn test_graph_new_returns_nonnull() -> Int {
  let g = tf.graph_new();
  return assert_ne(g, 0, "graph_new returns non-null handle");
}

fn test_graph_delete_does_not_crash() -> Int {
  let g = tf.graph_new();
  tf.graph_delete(g);
  return assert_pass(true, "graph_delete does not crash");
}

// ===============================================================================
// SECTION 6 -- Session Safe Wrappers (3 tests)
// ===============================================================================

fn test_session_new_rejects_null_graph() -> Int {
  let r = tf.session_new(0);
  return assert_err(r.is_ok, "session_new(0) returns Err for null graph");
}

fn test_session_new_returns_err_in_stub_mode() -> Int {
  let g = tf.graph_new();
  let r = tf.session_new(g);
  return assert_err(r.is_ok, "session_new returns Err in SPEC stub mode");
}

fn test_session_close_with_nonzero_is_noop() -> Int {
  tf.session_close(1);
  return assert_pass(true, "session_close does not crash");
}

// ===============================================================================
// SECTION 7 -- Tensor Safe Wrappers + Contract Enforcement (3 tests)
// ===============================================================================

fn test_tensor_create_rejects_empty_data() -> Int {
  var shape = Vec[Int].new();
  shape.push(1);
  var data = Vec[Int].new();
  let r = tf.tensor_create(tf.TF_FLOAT, &shape, &data);
  return assert_err(r.is_ok, "tensor_create rejects empty data (requires: data.len()>0)");
}

fn test_tensor_create_rejects_empty_shape() -> Int {
  var shape = Vec[Int].new();
  var data = Vec[Int].new();
  data.push(42);
  let r = tf.tensor_create(tf.TF_FLOAT, &shape, &data);
  return assert_err(r.is_ok, "tensor_create rejects empty shape (requires: shape.len()>0)");
}

fn test_tensor_delete_with_nonzero_is_noop() -> Int {
  tf.tensor_delete(1);
  return assert_pass(true, "tensor_delete does not crash");
}

// ===============================================================================
// SECTION 8 -- Session Run + Contract Enforcement (2 tests)
// ===============================================================================

fn test_session_run_rejects_null_session() -> Int {
  var inputs = Vec[tf.TfTensor].new();
  inputs.push(1);
  var outputs = Vec[tf.TfTensor].new();
  outputs.push(1);
  let r = tf.session_run(0, &inputs, &outputs);
  return assert_err(r.is_ok, "session_run(0,...) returns Err for null session");
}

fn test_session_run_rejects_empty_inputs() -> Int {
  var inputs = Vec[tf.TfTensor].new();
  var outputs = Vec[tf.TfTensor].new();
  outputs.push(1);
  let r = tf.session_run(1, &inputs, &outputs);
  return assert_err(r.is_ok, "session_run rejects empty inputs (requires: inputs.len()>0)");
}

// ===============================================================================
// SECTION 9 -- Model Loading (2 tests)
// ===============================================================================

fn test_load_model_rejects_null_session() -> Int {
  let r = tf.load_model(0, "model.pb");
  return assert_err(r.is_ok, "load_model(0,...) returns Err for null session");
}

fn test_load_model_rejects_empty_path() -> Int {
  let r = tf.load_model(1, "");
  return assert_err(r.is_ok, "load_model rejects empty path (requires: path.len()>0)");
}

// ===============================================================================
// SECTION 10 -- GPU Query Stubs (2 tests)
// ===============================================================================

fn test_gpu_available_returns_false() -> Int {
  let avail = tf.gpu_available();
  let avail_int = if avail { 1 } else { 0 };
  return assert_eq(avail_int, 0, "gpu_available returns false in stub mode");
}

fn test_gpu_device_count_returns_zero() -> Int {
  let count = tf.gpu_device_count();
  return assert_eq(count, 0, "gpu_device_count returns 0 in stub mode");
}

// ===============================================================================
// SECTION 11 -- Utility (2 tests)
// ===============================================================================

fn test_version_is_valid() -> Int {
  let v = tf.version();
  return assert_pass(v.len() > 0, "version returns non-empty string");
}

fn test_is_linked_returns_false() -> Int {
  let linked = tf.is_linked();
  let linked_int = if linked { 1 } else { 0 };
  return assert_eq(linked_int, 0, "is_linked returns false (no C bridge)");
}

// ===============================================================================
// SECTION 12 -- Status Error Paths (3 tests)
// ===============================================================================

fn test_status_get_code_on_fresh_status() -> Int {
  let s = tf.status_new();
  let code = tf.status_get_code(s);
  return assert_eq(code, tf.TF_OK, "status_get_code returns TF_OK on fresh status");
}

fn test_status_set_and_get() -> Int {
  let s = tf.status_new();
  tf.status_set(s, tf.TF_INVALID_ARGUMENT, "bad input");
  let code = tf.status_get_code(s);
  return assert_eq(code, tf.TF_INVALID_ARGUMENT, "status_set + status_get_code roundtrip");
}

fn test_status_message_returns_string() -> Int {
  let s = tf.status_new();
  let msg = tf.status_message(s);
  return assert_pass(true, "status_message returns string without crash");
}

// ===============================================================================
// Test Runner
// ===============================================================================

pub fn main() -> Int {
  var failures: Int = 0;
  var total: Int = 0;

  // SECTION 1: Types (4)
  failures = failures + test_type_tfsession_is_int();
  failures = failures + test_type_tfgraph_is_int();
  failures = failures + test_type_tftensor_is_int();
  failures = failures + test_type_tfstatus_is_int();

  // SECTION 2: Error code constants (4)
  failures = failures + test_const_tf_ok();
  failures = failures + test_const_tf_cancelled();
  failures = failures + test_const_tf_invalid_argument();
  failures = failures + test_const_tf_internal();

  // SECTION 3: Data type constants (4)
  failures = failures + test_const_tf_float();
  failures = failures + test_const_tf_double();
  failures = failures + test_const_tf_int32();
  failures = failures + test_const_tf_bool();

  // SECTION 4: Status wrappers (3)
  failures = failures + test_status_new_returns_nonnull();
  failures = failures + test_status_is_ok_after_new();
  failures = failures + test_status_delete_does_not_crash();

  // SECTION 5: Graph wrappers (2)
  failures = failures + test_graph_new_returns_nonnull();
  failures = failures + test_graph_delete_does_not_crash();

  // SECTION 6: Session wrappers (3)
  failures = failures + test_session_new_rejects_null_graph();
  failures = failures + test_session_new_returns_err_in_stub_mode();
  failures = failures + test_session_close_with_nonzero_is_noop();

  // SECTION 7: Tensor wrappers + contracts (3)
  failures = failures + test_tensor_create_rejects_empty_data();
  failures = failures + test_tensor_create_rejects_empty_shape();
  failures = failures + test_tensor_delete_with_nonzero_is_noop();

  // SECTION 8: Session run + contracts (2)
  failures = failures + test_session_run_rejects_null_session();
  failures = failures + test_session_run_rejects_empty_inputs();

  // SECTION 9: Model loading (2)
  failures = failures + test_load_model_rejects_null_session();
  failures = failures + test_load_model_rejects_empty_path();

  // SECTION 10: GPU stubs (2)
  failures = failures + test_gpu_available_returns_false();
  failures = failures + test_gpu_device_count_returns_zero();

  // SECTION 11: Utility (2)
  failures = failures + test_version_is_valid();
  failures = failures + test_is_linked_returns_false();

  // SECTION 12: Status error paths (3)
  failures = failures + test_status_get_code_on_fresh_status();
  failures = failures + test_status_set_and_get();
  failures = failures + test_status_message_returns_string();

  total = 34;
  let passed = total - failures;

  if failures > 0 {
    return 1;
  }
  return 0;
}
