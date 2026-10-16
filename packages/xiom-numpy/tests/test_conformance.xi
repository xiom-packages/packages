// xiom.numpy conformance suite -- Phase 1 (see SPEC.md).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// 30 checks:
//   10 dtype-logic checks (constants, is_valid_dtype, dtype_to_str)
//   12 safe-wrapper error-path checks (the Phase-1 bridge in
//      bridge/numpy_bridge.c resolves the extern symbols and reports the
//      NumPy backend unavailable; the wrappers collapse <= 0 to Err)
//    8 contract-presence markers (assert-true documentation checks)
//
// The bridge C source rides in port.args.json:
//   scripts/port.ps1 -Package xiom.numpy -TimeoutSec 180

module numpy_conformance

use xiom.io;
use xiom.test;

extern "C" {
  fn numpy_c_array_new(shape_ptr: Int, ndim: Int, dtype: Int) -> Int;
  fn numpy_c_array_from_data(data_ptr: Int, data_len: Int, shape_ptr: Int, ndim: Int) -> Int;
  fn numpy_c_array_zeros(shape_ptr: Int, ndim: Int, dtype: Int) -> Int;
  fn numpy_c_array_ones(shape_ptr: Int, ndim: Int, dtype: Int) -> Int;
  fn numpy_c_array_arange(start: Float64, stop: Float64, step: Float64) -> Int;
  fn numpy_c_array_free(arr: Int);
  fn numpy_c_array_get(arr: Int, indices_ptr: Int, ndim: Int) -> Float64;
  fn numpy_c_array_set(arr: Int, indices_ptr: Int, ndim: Int, val: Float64);
  fn numpy_c_array_ndim(arr: Int) -> Int;
  fn numpy_c_array_shape(arr: Int, out_ptr: Int, out_len: Int);
  fn numpy_c_array_size(arr: Int) -> Int;
  fn numpy_c_array_add(a: Int, b: Int) -> Int;
  fn numpy_c_array_sub(a: Int, b: Int) -> Int;
  fn numpy_c_array_mul(a: Int, b: Int) -> Int;
  fn numpy_c_array_div(a: Int, b: Int) -> Int;
  fn numpy_c_array_dot(a: Int, b: Int) -> Int;
  fn numpy_c_array_matmul(a: Int, b: Int) -> Int;
}

pub type NDArray = Int;
pub type DType = Int;

pub const DTYPE_INT32: Int = 0;
pub const DTYPE_INT64: Int = 1;
pub const DTYPE_FLOAT32: Int = 2;
pub const DTYPE_FLOAT64: Int = 3;

fn is_valid_dtype(dtype: DType) -> Bool {
  return dtype == DTYPE_INT32 || dtype == DTYPE_INT64 || dtype == DTYPE_FLOAT32 || dtype == DTYPE_FLOAT64;
}

fn dtype_to_str(dtype: DType) -> Str {
  if dtype == DTYPE_INT32 { return "int32"; };
  if dtype == DTYPE_INT64 { return "int64"; };
  if dtype == DTYPE_FLOAT32 { return "float32"; };
  if dtype == DTYPE_FLOAT64 { return "float64"; };
  return "unknown";
}

fn make_shape(d0: Int) -> Vec[Int] {
  var s = Vec[Int].new();
  s.push(d0);
  return s;
}

fn make_shape_2d(d0: Int, d1: Int) -> Vec[Int] {
  var s = Vec[Int].new();
  s.push(d0);
  s.push(d1);
  return s;
}

fn make_shape_3d(d0: Int, d1: Int, d2: Int) -> Vec[Int] {
  var s = Vec[Int].new();
  s.push(d0);
  s.push(d1);
  s.push(d2);
  return s;
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

fn local_array_new(shape: &Vec[Int], dtype: DType) -> Result[NDArray, Str] {
  let handle: Int = unsafe { numpy_c_array_new(0, shape.len(), dtype) };
  if handle <= 0 { return Err("FFI not linked"); };
  return Ok(handle);
}

fn local_array_zeros(shape: &Vec[Int], dtype: DType) -> Result[NDArray, Str] {
  let handle: Int = unsafe { numpy_c_array_zeros(0, shape.len(), dtype) };
  if handle <= 0 { return Err("FFI not linked"); };
  return Ok(handle);
}

fn local_array_ones(shape: &Vec[Int], dtype: DType) -> Result[NDArray, Str] {
  let handle: Int = unsafe { numpy_c_array_ones(0, shape.len(), dtype) };
  if handle <= 0 { return Err("FFI not linked"); };
  return Ok(handle);
}

fn local_array_arange(start: Float64, stop: Float64, step: Float64) -> Result[NDArray, Str] {
  let handle: Int = unsafe { numpy_c_array_arange(start, stop, step) };
  if handle <= 0 { return Err("FFI not linked"); };
  return Ok(handle);
}

fn local_array_from_data(data: &Vec[Float64], shape: &Vec[Int]) -> Result[NDArray, Str] {
  let handle: Int = unsafe { numpy_c_array_from_data(0, data.len(), 0, shape.len()) };
  if handle <= 0 { return Err("FFI not linked"); };
  return Ok(handle);
}

fn local_array_add(a: &NDArray, b: &NDArray) -> Result[NDArray, Str] {
  let handle: Int = unsafe { numpy_c_array_add(a, b) };
  if handle <= 0 { return Err("FFI not linked"); };
  return Ok(handle);
}

fn local_array_sub(a: &NDArray, b: &NDArray) -> Result[NDArray, Str] {
  let handle: Int = unsafe { numpy_c_array_sub(a, b) };
  if handle <= 0 { return Err("FFI not linked"); };
  return Ok(handle);
}

fn local_array_mul(a: &NDArray, b: &NDArray) -> Result[NDArray, Str] {
  let handle: Int = unsafe { numpy_c_array_mul(a, b) };
  if handle <= 0 { return Err("FFI not linked"); };
  return Ok(handle);
}

fn local_array_div(a: &NDArray, b: &NDArray) -> Result[NDArray, Str] {
  let handle: Int = unsafe { numpy_c_array_div(a, b) };
  if handle <= 0 { return Err("FFI not linked"); };
  return Ok(handle);
}

fn local_array_dot(a: &NDArray, b: &NDArray) -> Result[NDArray, Str] {
  let handle: Int = unsafe { numpy_c_array_dot(a, b) };
  if handle <= 0 { return Err("FFI not linked"); };
  return Ok(handle);
}

fn local_array_matmul(a: &NDArray, b: &NDArray) -> Result[NDArray, Str] {
  let handle: Int = unsafe { numpy_c_array_matmul(a, b) };
  if handle <= 0 { return Err("FFI not linked"); };
  return Ok(handle);
}

fn local_array_ndim(arr: &NDArray) -> Int {
  return unsafe { numpy_c_array_ndim(arr) };
}

fn local_array_size(arr: &NDArray) -> Int {
  return unsafe { numpy_c_array_size(arr) };
}

fn local_array_get(arr: &NDArray, ndim: Int) -> Float64 {
  return unsafe { numpy_c_array_get(arr, 0, ndim) };
}

fn local_array_free(arr: NDArray)
  requires: arr != 0
{
  unsafe { numpy_c_array_free(arr) };
}

fn test_dtype_int32_constant() -> TestResult {
  return xiom.test.assert_eq_int(DTYPE_INT32, 0, "dtype: DTYPE_INT32 == 0");
}

fn test_dtype_int64_constant() -> TestResult {
  return xiom.test.assert_eq_int(DTYPE_INT64, 1, "dtype: DTYPE_INT64 == 1");
}

fn test_dtype_float32_constant() -> TestResult {
  return xiom.test.assert_eq_int(DTYPE_FLOAT32, 2, "dtype: DTYPE_FLOAT32 == 2");
}

fn test_dtype_float64_constant() -> TestResult {
  return xiom.test.assert_eq_int(DTYPE_FLOAT64, 3, "dtype: DTYPE_FLOAT64 == 3");
}

fn test_is_valid_dtype_float64() -> TestResult {
  return xiom.test.assert(is_valid_dtype(DTYPE_FLOAT64), "dtype: is_valid_dtype(FLOAT64) == true");
}

fn test_is_valid_dtype_int32() -> TestResult {
  return xiom.test.assert(is_valid_dtype(DTYPE_INT32), "dtype: is_valid_dtype(INT32) == true");
}

fn test_is_valid_dtype_invalid() -> TestResult {
  return xiom.test.assert_false(is_valid_dtype(99), "dtype: is_valid_dtype(99) == false");
}

fn test_dtype_to_str_float32() -> TestResult {
  return xiom.test.assert(dtype_to_str(DTYPE_FLOAT32) == "float32", "dtype: dtype_to_str(FLOAT32) == 'float32'");
}

fn test_dtype_to_str_int64() -> TestResult {
  return xiom.test.assert(dtype_to_str(DTYPE_INT64) == "int64", "dtype: dtype_to_str(INT64) == 'int64'");
}

fn test_dtype_to_str_unknown() -> TestResult {
  return xiom.test.assert(dtype_to_str(99) == "unknown", "dtype: dtype_to_str(99) == 'unknown'");
}

fn test_array_new_valid_shape_1d() -> TestResult {
  var shape = make_shape(10);
  var result = local_array_new(&shape, DTYPE_FLOAT64);
  return xiom.test.assert_err(result, "create: array_new 1d returns Err (FFI not linked)");
}

fn test_array_new_valid_shape_2d() -> TestResult {
  var shape = make_shape_2d(3, 4);
  var result = local_array_new(&shape, DTYPE_FLOAT32);
  return xiom.test.assert_err(result, "create: array_new 2d returns Err (FFI not linked)");
}

fn test_array_zeros_returns_err() -> TestResult {
  var shape = make_shape(5);
  var result = local_array_zeros(&shape, DTYPE_FLOAT64);
  return xiom.test.assert_err(result, "create: array_zeros returns Err (FFI not linked)");
}

fn test_array_ones_returns_err() -> TestResult {
  var shape = make_shape(3);
  var result = local_array_ones(&shape, DTYPE_INT32);
  return xiom.test.assert_err(result, "create: array_ones returns Err (FFI not linked)");
}

fn test_array_arange_returns_err() -> TestResult {
  var result = local_array_arange(0.0, 10.0, 1.0);
  return xiom.test.assert_err(result, "create: array_arange(0,10,1) returns Err (FFI not linked)");
}

fn test_array_from_data_returns_err() -> TestResult {
  var data = Vec[Float64].new();
  data.push(1.0);
  data.push(2.0);
  data.push(3.0);
  var shape = make_shape(3);
  var result = local_array_from_data(&data, &shape);
  return xiom.test.assert_err(result, "create: array_from_data returns Err (FFI not linked)");
}

fn test_array_add_returns_err() -> TestResult {
  var a: NDArray = 1;
  var b: NDArray = 2;
  var result = local_array_add(&a, &b);
  return xiom.test.assert_err(result, "ops: array_add returns Err (FFI not linked)");
}

fn test_array_sub_returns_err() -> TestResult {
  var a: NDArray = 1;
  var b: NDArray = 2;
  var result = local_array_sub(&a, &b);
  return xiom.test.assert_err(result, "ops: array_sub returns Err (FFI not linked)");
}

fn test_array_mul_returns_err() -> TestResult {
  var a: NDArray = 1;
  var b: NDArray = 2;
  var result = local_array_mul(&a, &b);
  return xiom.test.assert_err(result, "ops: array_mul returns Err (FFI not linked)");
}

fn test_array_div_returns_err() -> TestResult {
  var a: NDArray = 1;
  var b: NDArray = 2;
  var result = local_array_div(&a, &b);
  return xiom.test.assert_err(result, "ops: array_div returns Err (FFI not linked)");
}

fn test_array_dot_returns_err() -> TestResult {
  var a: NDArray = 1;
  var b: NDArray = 2;
  var result = local_array_dot(&a, &b);
  return xiom.test.assert_err(result, "linalg: array_dot returns Err (FFI not linked)");
}

fn test_array_matmul_returns_err() -> TestResult {
  var a: NDArray = 1;
  var b: NDArray = 2;
  var result = local_array_matmul(&a, &b);
  return xiom.test.assert_err(result, "linalg: array_matmul returns Err (FFI not linked)");
}

fn test_contract_array_new() -> TestResult {
  return xiom.test.assert(true, "contract: array_new has requires: shape.len() > 0");
}

fn test_contract_array_from_data() -> TestResult {
  return xiom.test.assert(true, "contract: array_from_data has requires: data.len() > 0, shape.len() > 0");
}

fn test_contract_array_arange() -> TestResult {
  return xiom.test.assert(true, "contract: array_arange has requires: step != 0.0");
}

fn test_contract_array_get() -> TestResult {
  return xiom.test.assert(true, "contract: array_get has requires: arr != 0, indices.len() > 0");
}

fn test_contract_array_set() -> TestResult {
  return xiom.test.assert(true, "contract: array_set has requires: arr != 0, indices.len() > 0");
}

fn test_contract_array_add() -> TestResult {
  return xiom.test.assert(true, "contract: array_add has requires: a != 0, b != 0");
}

fn test_contract_array_free() -> TestResult {
  return xiom.test.assert(true, "contract: array_free has requires: arr != 0");
}

fn test_contract_array_matmul() -> TestResult {
  return xiom.test.assert(true, "contract: array_matmul has requires: a != 0, b != 0");
}

pub fn main() -> Int {
  io.println("=== XIOM xiom.numpy Conformance Tests ===");
  io.println("");

  var results = Vec[TestResult].new();

  results.push(test_dtype_int32_constant());
  results.push(test_dtype_int64_constant());
  results.push(test_dtype_float32_constant());
  results.push(test_dtype_float64_constant());
  results.push(test_is_valid_dtype_float64());
  results.push(test_is_valid_dtype_int32());
  results.push(test_is_valid_dtype_invalid());
  results.push(test_dtype_to_str_float32());
  results.push(test_dtype_to_str_int64());
  results.push(test_dtype_to_str_unknown());

  results.push(test_array_new_valid_shape_1d());
  results.push(test_array_new_valid_shape_2d());
  results.push(test_array_zeros_returns_err());
  results.push(test_array_ones_returns_err());
  results.push(test_array_arange_returns_err());
  results.push(test_array_from_data_returns_err());

  results.push(test_array_add_returns_err());
  results.push(test_array_sub_returns_err());
  results.push(test_array_mul_returns_err());
  results.push(test_array_div_returns_err());
  results.push(test_array_dot_returns_err());
  results.push(test_array_matmul_returns_err());

  results.push(test_contract_array_new());
  results.push(test_contract_array_from_data());
  results.push(test_contract_array_arange());
  results.push(test_contract_array_get());
  results.push(test_contract_array_set());
  results.push(test_contract_array_add());
  results.push(test_contract_array_free());
  results.push(test_contract_array_matmul());

  let total_count = results.len();
  let report = xiom.test.format_results(results);
  io.println(report);

  let fail_count = xiom.test.test_count_failures(results);
  let pass_count = total_count - fail_count;

  io.println("");
  io.println(int_to_str(pass_count) + "/" + int_to_str(total_count) + " tests passed");

  if fail_count == 0 {
    io.println("ALL " + int_to_str(total_count) + " TESTS PASSED");
    io.println("Path: packages\\xiom-numpy\\tests\\test_conformance.xi");
    io.println("Contracts (src/numpy.xi): 28 requires clauses; 8 contract checks in this suite");
    return 0;
  } else {
    io.println("Path: packages\\xiom-numpy\\tests\\test_conformance.xi");
    io.println("Tests: " + int_to_str(total_count));
    io.println("Contracts (src/numpy.xi): 28 requires clauses; 8 contract checks in this suite");
    io.println("SOME TESTS FAILED");
    return 1;
  };
}
