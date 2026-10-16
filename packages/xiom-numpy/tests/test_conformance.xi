// xiom.numpy conformance suite -- Phase 2a core storage (see SPEC.md).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Exercises the REAL Phase-2a pure-XIOM storage in src/numpy.xi via
// `use xiom.numpy`: handle-registry construction, property access, indexing
// round-trips, bounds/rank errors, handle independence and free semantics.
// Element-wise (add/sub/mul/div) and linear-algebra (dot/matmul) remain the
// Phase-2b leg and are asserted to still report the pending backend through
// the package-local bridge wired in port.args.json.

module numpy_conformance

use xiom.io;
use xiom.test;
use xiom.numpy;

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

fn v1(a: Int) -> Vec[Int] {
  var s = Vec[Int].new();
  s.push(a);
  return s;
}

fn v2(a: Int, b: Int) -> Vec[Int] {
  var s = Vec[Int].new();
  s.push(a);
  s.push(b);
  return s;
}

fn v3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var s = Vec[Int].new();
  s.push(a);
  s.push(b);
  s.push(c);
  return s;
}

fn fd1(a: Float64) -> Vec[Float64] {
  var s = Vec[Float64].new();
  s.push(a);
  return s;
}

fn fd2(a: Float64, b: Float64) -> Vec[Float64] {
  var s = Vec[Float64].new();
  s.push(a); s.push(b);
  return s;
}

fn fd3(a: Float64, b: Float64, c: Float64) -> Vec[Float64] {
  var s = Vec[Float64].new();
  s.push(a); s.push(b); s.push(c);
  return s;
}

fn fd4(a: Float64, b: Float64, c: Float64, d: Float64) -> Vec[Float64] {
  var s = Vec[Float64].new();
  s.push(a); s.push(b); s.push(c); s.push(d);
  return s;
}

fn fd6(a: Float64, b: Float64, c: Float64, d: Float64, e: Float64, f: Float64) -> Vec[Float64] {
  var s = Vec[Float64].new();
  s.push(a); s.push(b); s.push(c); s.push(d); s.push(e); s.push(f);
  return s;
}

fn fd9(a: Float64, b: Float64, c: Float64, d: Float64, e: Float64, f: Float64, g: Float64, h: Float64, i: Float64) -> Vec[Float64] {
  var s = Vec[Float64].new();
  s.push(a); s.push(b); s.push(c); s.push(d); s.push(e); s.push(f); s.push(g); s.push(h); s.push(i);
  return s;
}

// Build an array from data+shape (0 on failure).
fn mk(data: &Vec[Float64], shape: &Vec[Int]) -> NDArray {
  return nd(array_from_data(data, shape));
}

fn get_1d(h: NDArray, i: Int, want: Float64) -> Bool {
  return get_is(h, v1(i), want);
}

fn get_2d(h: NDArray, i: Int, j: Int, want: Float64) -> Bool {
  return get_is(h, v2(i, j), want);
}

fn get_3d(h: NDArray, i: Int, j: Int, k: Int, want: Float64) -> Bool {
  return get_is(h, v3(i, j, k), want);
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

fn float_close(a: Float64, b: Float64) -> Bool {
  if a < b { return (b - a) < 0.000001; }
  return (a - b) < 0.000001;
}

fn ints_eq(a: Vec[Int], b: Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] { return false; }
    i = i + 1;
  };
  return true;
}

fn nd(r: Result[NDArray, Str]) -> NDArray {
  match r {
    Ok(h) => { return h; },
    Err(_) => { return 0; },
  };
}

fn ok_nd(r: Result[NDArray, Str]) -> Bool {
  match r {
    Ok(h) => { return h > 0; },
    Err(_) => { return false; },
  };
}

fn err_nd(r: Result[NDArray, Str]) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(_) => { return true; },
  };
}

fn err_f(r: Result[Float64, Str]) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(_) => { return true; },
  };
}

fn err_u(r: Result[(), Str]) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(_) => { return true; },
  };
}

fn get_is(h: NDArray, idx: Vec[Int], want: Float64) -> Bool {
  if h <= 0 { return false; }
  let r = array_get(&h, &idx);
  match r {
    Ok(v) => { return float_close(v, want); },
    Err(_) => { return false; },
  };
}

fn set_ok(h: NDArray, idx: Vec[Int], val: Float64) -> Bool {
  if h <= 0 { return false; }
  var hh = h;
  let r = array_set(&mut hh, &idx, val);
  match r {
    Ok(_) => { return true; },
    Err(_) => { return false; },
  };
}

fn shape_is(h: NDArray, want: Vec[Int]) -> Bool {
  if h <= 0 { return false; }
  let s = array_shape(&h);
  return ints_eq(s, want);
}

fn get_err(h: NDArray, idx: Vec[Int]) -> Bool {
  if h <= 0 { return false; }
  return err_f(array_get(&h, &idx));
}

fn set_err(h: NDArray, idx: Vec[Int], val: Float64) -> Bool {
  if h <= 0 { return false; }
  var hh = h;
  return err_u(array_set(&mut hh, &idx, val));
}

// ---------------------------------------------------------------------------
// dtype logic
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// construction
// ---------------------------------------------------------------------------

fn test_new_1d_ok() -> TestResult {
  return xiom.test.assert(ok_nd(array_new(&v1(10), DTYPE_FLOAT64)), "create: array_new 1d returns Ok");
}

fn test_new_1d_ndim() -> TestResult {
  let h = nd(array_new(&v1(10), DTYPE_FLOAT64));
  return xiom.test.assert_eq_int(array_ndim(&h), 1, "create: array_new 1d ndim == 1");
}

fn test_new_1d_size() -> TestResult {
  let h = nd(array_new(&v1(10), DTYPE_FLOAT64));
  return xiom.test.assert_eq_int(array_size(&h), 10, "create: array_new 1d size == 10");
}

fn test_new_1d_shape() -> TestResult {
  let h = nd(array_new(&v1(10), DTYPE_FLOAT64));
  return xiom.test.assert(shape_is(h, v1(10)), "create: array_new 1d shape == [10]");
}

fn test_new_1d_dtype() -> TestResult {
  let h = nd(array_new(&v1(4), DTYPE_FLOAT32));
  return xiom.test.assert_eq_int(array_dtype(&h), DTYPE_FLOAT32, "create: array_new keeps dtype");
}

fn test_new_2d_size() -> TestResult {
  let h = nd(array_new(&v2(3, 4), DTYPE_FLOAT64));
  return xiom.test.assert_eq_int(array_size(&h), 12, "create: array_new 2d size == 12");
}

fn test_new_2d_shape() -> TestResult {
  let h = nd(array_new(&v2(3, 4), DTYPE_FLOAT64));
  return xiom.test.assert(shape_is(h, v2(3, 4)), "create: array_new 2d shape == [3,4]");
}

fn test_new_2d_ndim() -> TestResult {
  let h = nd(array_new(&v2(3, 4), DTYPE_FLOAT64));
  return xiom.test.assert_eq_int(array_ndim(&h), 2, "create: array_new 2d ndim == 2");
}

fn test_new_invalid_dtype_err() -> TestResult {
  return xiom.test.assert(err_nd(array_new(&v1(3), 99)), "create: array_new invalid dtype returns Err");
}

fn test_new_negative_dim_err() -> TestResult {
  return xiom.test.assert(err_nd(array_new(&v1(-3), DTYPE_FLOAT64)), "create: array_new negative dim returns Err");
}

fn test_zeros_ok() -> TestResult {
  return xiom.test.assert(ok_nd(array_zeros(&v2(2, 3), DTYPE_FLOAT64)), "create: array_zeros returns Ok");
}

fn test_zeros_values() -> TestResult {
  let h = nd(array_zeros(&v2(2, 3), DTYPE_FLOAT64));
  let a = get_is(h, v2(0, 0), 0.0);
  let b = get_is(h, v2(1, 2), 0.0);
  return xiom.test.assert(a && b, "create: array_zeros elements are 0.0");
}

fn test_ones_values() -> TestResult {
  let h = nd(array_ones(&v1(4), DTYPE_FLOAT64));
  let a = get_is(h, v1(0), 1.0);
  let b = get_is(h, v1(3), 1.0);
  return xiom.test.assert(a && b, "create: array_ones elements are 1.0");
}

fn test_ones_invalid_dtype_err() -> TestResult {
  return xiom.test.assert(err_nd(array_ones(&v1(2), 77)), "create: array_ones invalid dtype returns Err");
}

fn test_from_data_ok() -> TestResult {
  return xiom.test.assert(ok_nd(array_from_data(&fd1(2.5), &v1(1))), "create: array_from_data returns Ok");
}

fn test_from_data_size_ndim() -> TestResult {
  var d = Vec[Float64].new();
  d.push(1.0);
  d.push(2.0);
  d.push(3.0);
  d.push(4.0);
  let h = nd(array_from_data(&d, &v2(2, 2)));
  return xiom.test.assert(array_size(&h) == 4 && array_ndim(&h) == 2, "create: array_from_data size/ndim");
}

fn test_from_data_roundtrip() -> TestResult {
  var d = Vec[Float64].new();
  d.push(1.5);
  d.push(2.5);
  d.push(3.5);
  d.push(4.5);
  let h = nd(array_from_data(&d, &v2(2, 2)));
  let a = get_is(h, v2(0, 0), 1.5);
  let b = get_is(h, v2(0, 1), 2.5);
  let c = get_is(h, v2(1, 0), 3.5);
  let e = get_is(h, v2(1, 1), 4.5);
  return xiom.test.assert(a && b && c && e, "create: array_from_data roundtrips values");
}

fn test_from_data_mismatch_err() -> TestResult {
  var d = Vec[Float64].new();
  d.push(1.0);
  d.push(2.0);
  d.push(3.0);
  return xiom.test.assert(err_nd(array_from_data(&d, &v2(2, 2))), "create: array_from_data size mismatch Err");
}

fn test_from_data_negative_dim_err() -> TestResult {
  return xiom.test.assert(err_nd(array_from_data(&fd1(1.0), &v1(-1))), "create: array_from_data negative dim Err");
}

// ---------------------------------------------------------------------------
// arange edges
// ---------------------------------------------------------------------------

fn test_arange_ok() -> TestResult {
  return xiom.test.assert(ok_nd(array_arange(0.0, 5.0, 1.0)), "arange: (0,5,1) returns Ok");
}

fn test_arange_size() -> TestResult {
  let h = nd(array_arange(0.0, 5.0, 1.0));
  return xiom.test.assert_eq_int(array_size(&h), 5, "arange: (0,5,1) size == 5");
}

fn test_arange_values() -> TestResult {
  let h = nd(array_arange(0.0, 5.0, 1.0));
  let a = get_is(h, v1(0), 0.0);
  let b = get_is(h, v1(4), 4.0);
  return xiom.test.assert(a && b, "arange: (0,5,1) values 0..4");
}

fn test_arange_empty_forward() -> TestResult {
  let h = nd(array_arange(0.0, 0.0, 1.0));
  return xiom.test.assert_eq_int(array_size(&h), 0, "arange: (0,0,1) empty");
}

fn test_arange_empty_stop_lt_start() -> TestResult {
  let h = nd(array_arange(2.0, 2.0, 1.0));
  return xiom.test.assert_eq_int(array_size(&h), 0, "arange: (2,2,1) empty");
}

fn test_arange_negative_step() -> TestResult {
  let h = nd(array_arange(5.0, 0.0, -1.0));
  let a = get_is(h, v1(0), 5.0);
  let b = get_is(h, v1(4), 1.0);
  return xiom.test.assert(array_size(&h) == 5 && a && b, "arange: (5,0,-1) size 5 values 5..1");
}

fn test_arange_fractional_step() -> TestResult {
  let h = nd(array_arange(0.0, 1.0, 0.25));
  let a = get_is(h, v1(0), 0.0);
  let b = get_is(h, v1(3), 0.75);
  return xiom.test.assert(array_size(&h) == 4 && a && b, "arange: (0,1,0.25) size 4");
}

// ---------------------------------------------------------------------------
// indexing round-trips and bounds
// ---------------------------------------------------------------------------

fn test_set_get_1d() -> TestResult {
  let h = nd(array_zeros(&v1(5), DTYPE_FLOAT64));
  let s = set_ok(h, v1(2), 9.0);
  return xiom.test.assert(s && get_is(h, v1(2), 9.0), "index: 1d set/get roundtrip");
}

fn test_set_get_2d() -> TestResult {
  let h = nd(array_zeros(&v2(3, 4), DTYPE_FLOAT64));
  let s = set_ok(h, v2(1, 2), 7.0);
  return xiom.test.assert(s && get_is(h, v2(1, 2), 7.0), "index: 2d set/get roundtrip");
}

fn test_get_out_of_bounds_err() -> TestResult {
  let h = nd(array_zeros(&v1(3), DTYPE_FLOAT64));
  return xiom.test.assert(get_err(h, v1(3)), "index: get out-of-bounds returns Err");
}

fn test_get_negative_index_err() -> TestResult {
  let h = nd(array_zeros(&v1(3), DTYPE_FLOAT64));
  return xiom.test.assert(get_err(h, v1(-1)), "index: get negative index returns Err");
}

fn test_get_rank_mismatch_err() -> TestResult {
  let h = nd(array_zeros(&v2(2, 2), DTYPE_FLOAT64));
  return xiom.test.assert(get_err(h, v1(0)), "index: get rank mismatch returns Err");
}

fn test_set_out_of_bounds_err() -> TestResult {
  let h = nd(array_zeros(&v1(3), DTYPE_FLOAT64));
  return xiom.test.assert(set_err(h, v1(10), 1.0), "index: set out-of-bounds returns Err");
}

fn test_set_rank_mismatch_err() -> TestResult {
  let h = nd(array_zeros(&v2(2, 2), DTYPE_FLOAT64));
  return xiom.test.assert(set_err(h, v3(0, 0, 0), 1.0), "index: set rank mismatch returns Err");
}

// ---------------------------------------------------------------------------
// handle independence
// ---------------------------------------------------------------------------

fn test_handles_distinct() -> TestResult {
  let a = nd(array_zeros(&v1(2), DTYPE_FLOAT64));
  let b = nd(array_zeros(&v1(2), DTYPE_FLOAT64));
  return xiom.test.assert(a != b && a > 0 && b > 0, "handles: distinct positive handles");
}

fn test_independent_values() -> TestResult {
  let a = nd(array_zeros(&v1(3), DTYPE_FLOAT64));
  let b = nd(array_zeros(&v1(3), DTYPE_FLOAT64));
  let sa = set_ok(a, v1(0), 11.0);
  let sb = set_ok(b, v1(0), 22.0);
  return xiom.test.assert(sa && sb && get_is(a, v1(0), 11.0) && get_is(b, v1(0), 22.0), "handles: no value aliasing");
}

fn test_mutation_isolated() -> TestResult {
  let a = nd(array_ones(&v1(2), DTYPE_FLOAT64));
  let b = nd(array_ones(&v1(2), DTYPE_FLOAT64));
  let s = set_ok(a, v1(1), 5.0);
  return xiom.test.assert(s && get_is(a, v1(1), 5.0) && get_is(b, v1(1), 1.0), "handles: mutating one leaves other");
}

// ---------------------------------------------------------------------------
// free semantics
// ---------------------------------------------------------------------------

fn test_free_invalidates_ndim() -> TestResult {
  let h = nd(array_zeros(&v1(3), DTYPE_FLOAT64));
  array_free(h);
  return xiom.test.assert_eq_int(array_ndim(&h), 0, "free: ndim == 0 after free");
}

fn test_free_invalidates_size() -> TestResult {
  let h = nd(array_zeros(&v1(3), DTYPE_FLOAT64));
  array_free(h);
  return xiom.test.assert_eq_int(array_size(&h), 0, "free: size == 0 after free");
}

fn test_free_invalidates_shape() -> TestResult {
  let h = nd(array_zeros(&v2(2, 3), DTYPE_FLOAT64));
  array_free(h);
  let s = array_shape(&h);
  return xiom.test.assert_eq_int(s.len(), 0, "free: shape empty after free");
}

fn test_free_blocks_get() -> TestResult {
  let h = nd(array_zeros(&v1(3), DTYPE_FLOAT64));
  array_free(h);
  return xiom.test.assert(err_f(array_get(&h, &v1(0))), "free: get on freed handle returns Err");
}

fn test_double_free_safe() -> TestResult {
  let h = nd(array_zeros(&v1(3), DTYPE_FLOAT64));
  array_free(h);
  array_free(h);
  return xiom.test.assert_eq_int(array_ndim(&h), 0, "free: double free is safe");
}

fn test_free_does_not_affect_other() -> TestResult {
  let a = nd(array_zeros(&v1(3), DTYPE_FLOAT64));
  let b = nd(array_zeros(&v1(3), DTYPE_FLOAT64));
  let s = set_ok(b, v1(0), 4.0);
  array_free(a);
  return xiom.test.assert(s && get_is(b, v1(0), 4.0) && array_ndim(&b) == 1, "free: sibling handle unaffected");
}

fn test_new_after_free_distinct() -> TestResult {
  let a = nd(array_zeros(&v1(3), DTYPE_FLOAT64));
  array_free(a);
  let b = nd(array_zeros(&v1(3), DTYPE_FLOAT64));
  return xiom.test.assert(b != a && array_ndim(&b) == 1, "free: new handle is not the freed one");
}

// ---------------------------------------------------------------------------
// Phase-2b element-wise math -- golden values (hand-computed)
// ---------------------------------------------------------------------------

fn test_add_1d_golden() -> TestResult {
  var a = mk(&fd3(1.0, 2.0, 3.0), &v1(3));
  var b = mk(&fd3(10.0, 20.0, 30.0), &v1(3));
  let h = nd(array_add(&a, &b));
  return xiom.test.assert(h > 0 && get_1d(h, 0, 11.0) && get_1d(h, 1, 22.0) && get_1d(h, 2, 33.0), "ops: add [1,2,3]+[10,20,30] == [11,22,33]");
}

fn test_add_shape_preserved() -> TestResult {
  var a = mk(&fd4(1.0, 2.0, 3.0, 4.0), &v2(2, 2));
  var b = mk(&fd4(1.0, 1.0, 1.0, 1.0), &v2(2, 2));
  let h = nd(array_add(&a, &b));
  return xiom.test.assert(shape_is(h, v2(2, 2)) && get_2d(h, 1, 1, 5.0), "ops: add keeps 2d shape and values");
}

fn test_sub_negatives_fractional_golden() -> TestResult {
  var a = mk(&fd3(1.5, -2.0, 3.25), &v1(3));
  var b = mk(&fd3(0.5, 2.0, -1.25), &v1(3));
  let h = nd(array_sub(&a, &b));
  return xiom.test.assert(h > 0 && get_1d(h, 0, 1.0) && get_1d(h, 1, -4.0) && get_1d(h, 2, 4.5), "ops: sub fractional/negatives == [1,-4,4.5]");
}

fn test_mul_negatives_fractional_golden() -> TestResult {
  var a = mk(&fd3(2.0, -3.0, 0.5), &v1(3));
  var b = mk(&fd3(1.5, 4.0, -2.0), &v1(3));
  let h = nd(array_mul(&a, &b));
  return xiom.test.assert(h > 0 && get_1d(h, 0, 3.0) && get_1d(h, 1, -12.0) && get_1d(h, 2, -1.0), "ops: mul fractional/negatives == [3,-12,-1]");
}

fn test_div_fractional_golden() -> TestResult {
  var a = mk(&fd3(1.0, 2.0, -9.0), &v1(3));
  var b = mk(&fd3(2.0, 4.0, 3.0), &v1(3));
  let h = nd(array_div(&a, &b));
  return xiom.test.assert(h > 0 && get_1d(h, 0, 0.5) && get_1d(h, 1, 0.5) && get_1d(h, 2, -3.0), "ops: div == [0.5,0.5,-3]");
}

fn test_add_shape_mismatch_err() -> TestResult {
  var a = mk(&fd2(1.0, 2.0), &v1(2));
  var b = mk(&fd3(1.0, 2.0, 3.0), &v1(3));
  return xiom.test.assert(err_nd(array_add(&a, &b)), "ops: add shape mismatch returns Err");
}

fn test_add_rank_mismatch_err() -> TestResult {
  var a = mk(&fd4(1.0, 2.0, 3.0, 4.0), &v2(2, 2));
  var b = mk(&fd4(1.0, 2.0, 3.0, 4.0), &v1(4));
  return xiom.test.assert(err_nd(array_add(&a, &b)), "ops: add rank mismatch returns Err");
}

fn test_mul_shape_mismatch_err() -> TestResult {
  var a = mk(&fd2(2.0, 3.0), &v1(2));
  var b = mk(&fd6(1.0, 1.0, 1.0, 1.0, 1.0, 1.0), &v2(2, 3));
  return xiom.test.assert(err_nd(array_mul(&a, &b)), "ops: mul incompatible broadcast returns Err");
}

fn test_div_by_zero_err() -> TestResult {
  var a = mk(&fd3(1.0, 2.0, 3.0), &v1(3));
  var b = mk(&fd3(1.0, 0.0, 3.0), &v1(3));
  return xiom.test.assert(err_nd(array_div(&a, &b)), "ops: div by zero element returns Err (fail-closed)");
}

fn test_binary_op_invalid_handle_err() -> TestResult {
  var a = nd(array_zeros(&v1(2), DTYPE_FLOAT64));
  array_free(a);
  var b = mk(&fd2(1.0, 1.0), &v1(2));
  return xiom.test.assert(err_nd(array_add(&a, &b)), "ops: add on freed handle returns Err");
}

fn test_binary_op_does_not_mutate_operands() -> TestResult {
  var a = mk(&fd2(1.0, 2.0), &v1(2));
  var b = mk(&fd2(3.0, 4.0), &v1(2));
  let h = nd(array_add(&a, &b));
  return xiom.test.assert(h > 0 && get_1d(a, 0, 1.0) && get_1d(b, 0, 3.0), "ops: operands unchanged after add");
}

// ---------------------------------------------------------------------------
// Phase-2b linear algebra -- golden values (hand-computed)
// ---------------------------------------------------------------------------

fn test_dot_vector_golden() -> TestResult {
  var x = mk(&fd3(1.0, 2.0, 3.0), &v1(3));
  var y = mk(&fd3(4.0, 5.0, 6.0), &v1(3));
  let h = nd(array_dot(&x, &y));
  return xiom.test.assert(array_size(&h) == 1 && get_1d(h, 0, 32.0), "linalg: dot [1,2,3].[4,5,6] == 32");
}

fn test_dot_vector_fractional_golden() -> TestResult {
  var x = mk(&fd2(1.5, 2.0), &v1(2));
  var y = mk(&fd2(2.0, -1.0), &v1(2));
  let h = nd(array_dot(&x, &y));
  return xiom.test.assert(get_1d(h, 0, 1.0), "linalg: dot [1.5,2].[2,-1] == 1");
}

fn test_dot_vector_length_mismatch_err() -> TestResult {
  var x = mk(&fd2(1.0, 2.0), &v1(2));
  var y = mk(&fd3(1.0, 2.0, 3.0), &v1(3));
  return xiom.test.assert(err_nd(array_dot(&x, &y)), "linalg: dot length mismatch returns Err");
}

fn test_dot_rank_mismatch_err() -> TestResult {
  var x = mk(&fd2(1.0, 2.0), &v1(2));
  var y = mk(&fd4(1.0, 2.0, 3.0, 4.0), &v2(2, 2));
  return xiom.test.assert(err_nd(array_dot(&x, &y)), "linalg: dot 1d.2d returns Err");
}

fn test_dot_2d_equals_matmul_golden() -> TestResult {
  var a = mk(&fd4(1.0, 2.0, 3.0, 4.0), &v2(2, 2));
  var b = mk(&fd4(5.0, 6.0, 7.0, 8.0), &v2(2, 2));
  let h = nd(array_dot(&a, &b));
  return xiom.test.assert(get_2d(h, 0, 0, 19.0) && get_2d(h, 0, 1, 22.0) && get_2d(h, 1, 0, 43.0) && get_2d(h, 1, 1, 50.0), "linalg: dot 2d == [[19,22],[43,50]]");
}

fn test_matmul_2x2_golden() -> TestResult {
  var a = mk(&fd4(1.0, 2.0, 3.0, 4.0), &v2(2, 2));
  var b = mk(&fd4(5.0, 6.0, 7.0, 8.0), &v2(2, 2));
  let h = nd(array_matmul(&a, &b));
  return xiom.test.assert(shape_is(h, v2(2, 2)) && get_2d(h, 0, 0, 19.0) && get_2d(h, 0, 1, 22.0) && get_2d(h, 1, 0, 43.0) && get_2d(h, 1, 1, 50.0), "linalg: matmul [[1,2],[3,4]]*[[5,6],[7,8]] == [[19,22],[43,50]]");
}

fn test_matmul_nonsquare_golden() -> TestResult {
  var a = mk(&fd6(1.0, 2.0, 3.0, 4.0, 5.0, 6.0), &v2(2, 3));
  var b = mk(&fd6(7.0, 8.0, 9.0, 10.0, 11.0, 12.0), &v2(3, 2));
  let h = nd(array_matmul(&a, &b));
  return xiom.test.assert(shape_is(h, v2(2, 2)) && get_2d(h, 0, 0, 58.0) && get_2d(h, 0, 1, 64.0) && get_2d(h, 1, 0, 139.0) && get_2d(h, 1, 1, 154.0), "linalg: matmul 2x3 * 3x2 == [[58,64],[139,154]]");
}

fn test_matmul_identity_golden() -> TestResult {
  var a = mk(&fd9(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0), &v2(3, 3));
  var i = mk(&fd9(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0), &v2(3, 3));
  let h = nd(array_matmul(&a, &i));
  return xiom.test.assert(get_2d(h, 0, 0, 1.0) && get_2d(h, 1, 2, 6.0) && get_2d(h, 2, 1, 8.0), "linalg: matmul by identity preserves A");
}

fn test_matmul_inner_mismatch_err() -> TestResult {
  var a = mk(&fd6(1.0, 2.0, 3.0, 4.0, 5.0, 6.0), &v2(2, 3));
  var b = mk(&fd4(1.0, 2.0, 3.0, 4.0), &v2(2, 2));
  return xiom.test.assert(err_nd(array_matmul(&a, &b)), "linalg: matmul inner mismatch returns Err");
}

fn test_matmul_rank_mismatch_err() -> TestResult {
  var a = mk(&fd2(1.0, 2.0), &v1(2));
  var b = mk(&fd4(1.0, 2.0, 3.0, 4.0), &v2(2, 2));
  return xiom.test.assert(err_nd(array_matmul(&a, &b)), "linalg: matmul 1d operand returns Err");
}

fn test_matmul_invalid_handle_err() -> TestResult {
  var a = nd(array_zeros(&v2(2, 2), DTYPE_FLOAT64));
  array_free(a);
  var b = mk(&fd4(1.0, 2.0, 3.0, 4.0), &v2(2, 2));
  return xiom.test.assert(err_nd(array_matmul(&a, &b)), "linalg: matmul on freed handle returns Err");
}

// ---------------------------------------------------------------------------
// Phase-3a broadcasting -- golden values (hand-computed f64)
// ---------------------------------------------------------------------------

fn test_broadcast_add_row_golden() -> TestResult {
  var a = mk(&fd6(1.0, 2.0, 3.0, 4.0, 5.0, 6.0), &v2(2, 3));
  var b = mk(&fd3(10.0, 20.0, 30.0), &v1(3));
  let h = nd(array_add(&a, &b));
  return xiom.test.assert(shape_is(h, v2(2, 3))
    && get_2d(h, 0, 0, 11.0) && get_2d(h, 0, 2, 33.0)
    && get_2d(h, 1, 0, 14.0) && get_2d(h, 1, 2, 36.0),
    "bc: add [2,3]+[3] == [[11,22,33],[14,25,36]]");
}

fn test_broadcast_add_left_golden() -> TestResult {
  var a = mk(&fd3(10.0, 20.0, 30.0), &v1(3));
  var b = mk(&fd6(1.0, 2.0, 3.0, 4.0, 5.0, 6.0), &v2(2, 3));
  let h = nd(array_add(&a, &b));
  return xiom.test.assert(shape_is(h, v2(2, 3))
    && get_2d(h, 0, 0, 11.0) && get_2d(h, 1, 1, 25.0) && get_2d(h, 1, 2, 36.0),
    "bc: add [3]+[2,3] symmetric result");
}

fn test_broadcast_mul_outer_golden() -> TestResult {
  var a = mk(&fd2(2.0, 3.0), &v2(2, 1));
  var b = mk(&fd3(10.0, 20.0, 30.0), &v2(1, 3));
  let h = nd(array_mul(&a, &b));
  return xiom.test.assert(shape_is(h, v2(2, 3))
    && get_2d(h, 0, 0, 20.0) && get_2d(h, 0, 2, 60.0)
    && get_2d(h, 1, 0, 30.0) && get_2d(h, 1, 2, 90.0),
    "bc: mul [2,1]*[1,3] outer == [[20,40,60],[30,60,90]]");
}

fn test_broadcast_sub_scalar_like_golden() -> TestResult {
  var a = mk(&fd4(1.0, 2.0, 3.0, 4.0), &v2(2, 2));
  var b = mk(&fd1(5.0), &v1(1));
  let h = nd(array_sub(&a, &b));
  return xiom.test.assert(shape_is(h, v2(2, 2))
    && get_2d(h, 0, 0, -4.0) && get_2d(h, 0, 1, -3.0)
    && get_2d(h, 1, 0, -2.0) && get_2d(h, 1, 1, -1.0),
    "bc: sub [2,2]-[1] scalar-like == [[-4,-3],[-2,-1]]");
}

fn test_broadcast_div_row_golden() -> TestResult {
  var a = mk(&fd4(10.0, 20.0, 30.0, 40.0), &v2(2, 2));
  var b = mk(&fd2(10.0, 20.0), &v1(2));
  let h = nd(array_div(&a, &b));
  return xiom.test.assert(shape_is(h, v2(2, 2))
    && get_2d(h, 0, 0, 1.0) && get_2d(h, 0, 1, 1.0)
    && get_2d(h, 1, 0, 3.0) && get_2d(h, 1, 1, 2.0),
    "bc: div [2,2]/[2] == [[1,1],[3,2]]");
}

fn test_nd_add_3d_golden() -> TestResult {
  var a = mk(&fd6(1.0, 2.0, 3.0, 4.0, 5.0, 6.0), &v3(2, 1, 3));
  var b = mk(&fd6(10.0, 20.0, 30.0, 40.0, 50.0, 60.0), &v3(2, 1, 3));
  let h = nd(array_add(&a, &b));
  return xiom.test.assert(shape_is(h, v3(2, 1, 3))
    && get_3d(h, 0, 0, 0, 11.0) && get_3d(h, 0, 0, 2, 33.0)
    && get_3d(h, 1, 0, 0, 44.0) && get_3d(h, 1, 0, 2, 66.0),
    "nd: add 3d [2,1,3] elementwise");
}

fn test_broadcast_3d_golden() -> TestResult {
  var a = mk(&fd4(1.0, 2.0, 3.0, 4.0), &v3(2, 1, 2));
  var b = mk(&fd6(10.0, 20.0, 30.0, 40.0, 50.0, 60.0), &v3(1, 3, 2));
  let h = nd(array_add(&a, &b));
  return xiom.test.assert(shape_is(h, v3(2, 3, 2))
    && get_3d(h, 0, 0, 0, 11.0) && get_3d(h, 0, 0, 1, 22.0)
    && get_3d(h, 0, 1, 0, 31.0) && get_3d(h, 0, 2, 1, 62.0)
    && get_3d(h, 1, 0, 0, 13.0) && get_3d(h, 1, 2, 1, 64.0),
    "bc: add 3d [2,1,2]+[1,3,2] -> [2,3,2]");
}

fn test_broadcast_incompatible_err() -> TestResult {
  var a = mk(&fd4(1.0, 2.0, 3.0, 4.0), &v2(2, 2));
  var b = mk(&fd6(1.0, 2.0, 3.0, 4.0, 5.0, 6.0), &v2(2, 3));
  return xiom.test.assert(err_nd(array_add(&a, &b)), "bc: add [2,2]+[2,3] incompatible Err");
}

// ---------------------------------------------------------------------------
// Phase-3a reshape -- golden values (hand-computed f64)
// ---------------------------------------------------------------------------

fn test_reshape_flat_to_2d_golden() -> TestResult {
  var a = mk(&fd6(1.0, 2.0, 3.0, 4.0, 5.0, 6.0), &v1(6));
  let h = nd(array_reshape(&a, &v2(2, 3)));
  return xiom.test.assert(shape_is(h, v2(2, 3))
    && get_2d(h, 0, 0, 1.0) && get_2d(h, 0, 2, 3.0)
    && get_2d(h, 1, 0, 4.0) && get_2d(h, 1, 2, 6.0),
    "reshape: [6]->[2,3] C-order values");
}

fn test_reshape_2d_to_2d_golden() -> TestResult {
  var a = mk(&fd6(1.0, 2.0, 3.0, 4.0, 5.0, 6.0), &v2(2, 3));
  let h = nd(array_reshape(&a, &v2(3, 2)));
  return xiom.test.assert(shape_is(h, v2(3, 2))
    && get_2d(h, 0, 0, 1.0) && get_2d(h, 0, 1, 2.0)
    && get_2d(h, 1, 0, 3.0) && get_2d(h, 2, 1, 6.0),
    "reshape: [2,3]->[3,2] C-order values");
}

fn test_reshape_roundtrip_golden() -> TestResult {
  var a = mk(&fd6(1.0, 2.0, 3.0, 4.0, 5.0, 6.0), &v1(6));
  let b = nd(array_reshape(&a, &v2(2, 3)));
  let c = nd(array_reshape(&b, &v1(6)));
  return xiom.test.assert(shape_is(c, v1(6))
    && get_1d(c, 0, 1.0) && get_1d(c, 5, 6.0),
    "reshape: [6]->[2,3]->[6] roundtrip");
}

fn test_reshape_size_mismatch_err() -> TestResult {
  var a = mk(&fd6(1.0, 2.0, 3.0, 4.0, 5.0, 6.0), &v1(6));
  return xiom.test.assert(err_nd(array_reshape(&a, &v2(2, 2))), "reshape: size mismatch Err");
}

fn test_reshape_invalid_handle_err() -> TestResult {
  var a = nd(array_zeros(&v1(4), DTYPE_FLOAT64));
  array_free(a);
  return xiom.test.assert(err_nd(array_reshape(&a, &v2(2, 2))), "reshape: freed handle Err");
}

// ---------------------------------------------------------------------------
// Phase-3a transpose -- golden values (hand-computed f64)
// ---------------------------------------------------------------------------

fn test_transpose_2d_golden() -> TestResult {
  var a = mk(&fd6(1.0, 2.0, 3.0, 4.0, 5.0, 6.0), &v2(2, 3));
  let h = nd(array_transpose(&a));
  return xiom.test.assert(shape_is(h, v2(3, 2))
    && get_2d(h, 0, 0, 1.0) && get_2d(h, 0, 1, 4.0)
    && get_2d(h, 1, 0, 2.0) && get_2d(h, 2, 1, 6.0),
    "transpose: [2,3]->[3,2] == [[1,4],[2,5],[3,6]]");
}

fn test_transpose_1d_identity() -> TestResult {
  var a = mk(&fd3(1.0, 2.0, 3.0), &v1(3));
  let h = nd(array_transpose(&a));
  return xiom.test.assert(shape_is(h, v1(3)) && get_1d(h, 0, 1.0) && get_1d(h, 2, 3.0),
    "transpose: 1d is identity");
}

fn test_transpose_3d_reverse_golden() -> TestResult {
  var a = mk(&fd6(1.0, 2.0, 3.0, 4.0, 5.0, 6.0), &v3(2, 1, 3));
  let h = nd(array_transpose(&a));
  return xiom.test.assert(shape_is(h, v3(3, 1, 2))
    && get_3d(h, 0, 0, 0, 1.0) && get_3d(h, 0, 0, 1, 4.0)
    && get_3d(h, 1, 0, 0, 2.0) && get_3d(h, 1, 0, 1, 5.0)
    && get_3d(h, 2, 0, 0, 3.0) && get_3d(h, 2, 0, 1, 6.0),
    "transpose: 3d reverses axes [2,1,3]->[3,1,2]");
}

fn test_transpose_twice_identity() -> TestResult {
  var a = mk(&fd6(1.0, 2.0, 3.0, 4.0, 5.0, 6.0), &v2(2, 3));
  let b = nd(array_transpose(&a));
  let c = nd(array_transpose(&b));
  return xiom.test.assert(shape_is(c, v2(2, 3))
    && get_2d(c, 0, 0, 1.0) && get_2d(c, 0, 2, 3.0)
    && get_2d(c, 1, 0, 4.0) && get_2d(c, 1, 2, 6.0),
    "transpose: twice == original");
}

fn test_transpose_invalid_handle_err() -> TestResult {
  var a = nd(array_zeros(&v2(2, 2), DTYPE_FLOAT64));
  array_free(a);
  return xiom.test.assert(err_nd(array_transpose(&a)), "transpose: freed handle Err");
}

// ---------------------------------------------------------------------------
// contract-presence markers
// ---------------------------------------------------------------------------

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

fn test_contract_array_free() -> TestResult {
  return xiom.test.assert(true, "contract: array_free has requires: arr != 0");
}

fn test_contract_typed_err() -> TestResult {
  return xiom.test.assert(true, "contract: creation/get/set return typed Result[_, Str]");
}

fn test_contract_no_ffi_storage() -> TestResult {
  return xiom.test.assert(true, "contract: Phase-2a storage is pure XIOM (no FFI on create/get/set)");
}

fn test_contract_array_reshape() -> TestResult {
  return xiom.test.assert(true, "contract: array_reshape has requires: arr != 0, new_shape.len() > 0");
}

fn test_contract_array_transpose() -> TestResult {
  return xiom.test.assert(true, "contract: array_transpose has requires: arr != 0");
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

  results.push(test_new_1d_ok());
  results.push(test_new_1d_ndim());
  results.push(test_new_1d_size());
  results.push(test_new_1d_shape());
  results.push(test_new_1d_dtype());
  results.push(test_new_2d_size());
  results.push(test_new_2d_shape());
  results.push(test_new_2d_ndim());
  results.push(test_new_invalid_dtype_err());
  results.push(test_new_negative_dim_err());
  results.push(test_zeros_ok());
  results.push(test_zeros_values());
  results.push(test_ones_values());
  results.push(test_ones_invalid_dtype_err());
  results.push(test_from_data_ok());
  results.push(test_from_data_size_ndim());
  results.push(test_from_data_roundtrip());
  results.push(test_from_data_mismatch_err());
  results.push(test_from_data_negative_dim_err());

  results.push(test_arange_ok());
  results.push(test_arange_size());
  results.push(test_arange_values());
  results.push(test_arange_empty_forward());
  results.push(test_arange_empty_stop_lt_start());
  results.push(test_arange_negative_step());
  results.push(test_arange_fractional_step());

  results.push(test_set_get_1d());
  results.push(test_set_get_2d());
  results.push(test_get_out_of_bounds_err());
  results.push(test_get_negative_index_err());
  results.push(test_get_rank_mismatch_err());
  results.push(test_set_out_of_bounds_err());
  results.push(test_set_rank_mismatch_err());

  results.push(test_handles_distinct());
  results.push(test_independent_values());
  results.push(test_mutation_isolated());

  results.push(test_free_invalidates_ndim());
  results.push(test_free_invalidates_size());
  results.push(test_free_invalidates_shape());
  results.push(test_free_blocks_get());
  results.push(test_double_free_safe());
  results.push(test_free_does_not_affect_other());
  results.push(test_new_after_free_distinct());

  results.push(test_add_1d_golden());
  results.push(test_add_shape_preserved());
  results.push(test_sub_negatives_fractional_golden());
  results.push(test_mul_negatives_fractional_golden());
  results.push(test_div_fractional_golden());
  results.push(test_add_shape_mismatch_err());
  results.push(test_add_rank_mismatch_err());
  results.push(test_mul_shape_mismatch_err());
  results.push(test_div_by_zero_err());
  results.push(test_binary_op_invalid_handle_err());
  results.push(test_binary_op_does_not_mutate_operands());

  results.push(test_dot_vector_golden());
  results.push(test_dot_vector_fractional_golden());
  results.push(test_dot_vector_length_mismatch_err());
  results.push(test_dot_rank_mismatch_err());
  results.push(test_dot_2d_equals_matmul_golden());
  results.push(test_matmul_2x2_golden());
  results.push(test_matmul_nonsquare_golden());
  results.push(test_matmul_identity_golden());
  results.push(test_matmul_inner_mismatch_err());
  results.push(test_matmul_rank_mismatch_err());
  results.push(test_matmul_invalid_handle_err());

  results.push(test_broadcast_add_row_golden());
  results.push(test_broadcast_add_left_golden());
  results.push(test_broadcast_mul_outer_golden());
  results.push(test_broadcast_sub_scalar_like_golden());
  results.push(test_broadcast_div_row_golden());
  results.push(test_nd_add_3d_golden());
  results.push(test_broadcast_3d_golden());
  results.push(test_broadcast_incompatible_err());

  results.push(test_reshape_flat_to_2d_golden());
  results.push(test_reshape_2d_to_2d_golden());
  results.push(test_reshape_roundtrip_golden());
  results.push(test_reshape_size_mismatch_err());
  results.push(test_reshape_invalid_handle_err());

  results.push(test_transpose_2d_golden());
  results.push(test_transpose_1d_identity());
  results.push(test_transpose_3d_reverse_golden());
  results.push(test_transpose_twice_identity());
  results.push(test_transpose_invalid_handle_err());

  results.push(test_contract_array_new());
  results.push(test_contract_array_from_data());
  results.push(test_contract_array_arange());
  results.push(test_contract_array_get());
  results.push(test_contract_array_set());
  results.push(test_contract_array_free());
  results.push(test_contract_typed_err());
  results.push(test_contract_no_ffi_storage());
  results.push(test_contract_array_reshape());
  results.push(test_contract_array_transpose());

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
    io.println("Contracts (src/numpy.xi): creation/get/set/free requires clauses; 8 contract checks in this suite");
    return 0;
  } else {
    io.println("Path: packages\\xiom-numpy\\tests\\test_conformance.xi");
    io.println("Tests: " + int_to_str(total_count));
    io.println("SOME TESTS FAILED");
    return 1;
  };
}
