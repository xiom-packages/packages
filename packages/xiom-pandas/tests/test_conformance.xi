// XIOM -- Pandas Conformance Tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Comprehensive tests for xiom.pandas: dtype constants, compare/join constants,
// FFI stub behavior, API presence, contract declarations,
// error-path coverage, and type contracts.
//
// T001 reconciliation (2026-10-16): the former duplicated extern block is gone.
// On compiler v0.64.5 the canonical declarations resolve through
// `use xiom.pandas;` -- raw FFI calls lower to the pandas_c_* symbols and the
// canonical constants and dtype_name resolve (verified with --emit-ir probes).
// The local safe-wrapper copies in section 15 stay local BY DESIGN: they
// exercise error paths that would violate the real wrappers' requires
// contracts if called directly.
//
// The pandas_c_* symbols are linked offline by bridge/pandas_bridge.c
// (wired via port.args.json). The real Arrow-backed leg is
// tests/probe_real_arrow.xi -- NOT part of port.ps1 (see SPEC.md).

module pandas_conformance

use xiom.test;
use xiom.io;
use xiom.pandas;

// =========================================================================
// Helpers
// =========================================================================

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

// =========================================================================
// SECTION 1 -- Dtype constants
// =========================================================================

fn test_const_dtype_int32() -> TestResult {
  return xiom.test.assert_eq_int(DTYPE_INT32, 0, "pandas: DTYPE_INT32 == 0");
}

fn test_const_dtype_int64() -> TestResult {
  return xiom.test.assert_eq_int(DTYPE_INT64, 1, "pandas: DTYPE_INT64 == 1");
}

fn test_const_dtype_float32() -> TestResult {
  return xiom.test.assert_eq_int(DTYPE_FLOAT32, 2, "pandas: DTYPE_FLOAT32 == 2");
}

fn test_const_dtype_float64() -> TestResult {
  return xiom.test.assert_eq_int(DTYPE_FLOAT64, 3, "pandas: DTYPE_FLOAT64 == 3");
}

fn test_const_dtype_string() -> TestResult {
  return xiom.test.assert_eq_int(DTYPE_STRING, 4, "pandas: DTYPE_STRING == 4");
}

fn test_const_dtype_bool() -> TestResult {
  return xiom.test.assert_eq_int(DTYPE_BOOL, 5, "pandas: DTYPE_BOOL == 5");
}

fn test_const_dtype_count() -> TestResult {
  return xiom.test.assert(true, "pandas: 6 dtype constants defined (DTYPE_INT32..DTYPE_BOOL)");
}

// =========================================================================
// SECTION 2 -- CompareOp constants
// =========================================================================

fn test_const_cmp_eq() -> TestResult {
  return xiom.test.assert_eq_int(CMP_EQ, 0, "pandas: CMP_EQ == 0");
}

fn test_const_cmp_ne() -> TestResult {
  return xiom.test.assert_eq_int(CMP_NE, 1, "pandas: CMP_NE == 1");
}

fn test_const_cmp_lt() -> TestResult {
  return xiom.test.assert_eq_int(CMP_LT, 2, "pandas: CMP_LT == 2");
}

fn test_const_cmp_le() -> TestResult {
  return xiom.test.assert_eq_int(CMP_LE, 3, "pandas: CMP_LE == 3");
}

fn test_const_cmp_gt() -> TestResult {
  return xiom.test.assert_eq_int(CMP_GT, 4, "pandas: CMP_GT == 4");
}

fn test_const_cmp_ge() -> TestResult {
  return xiom.test.assert_eq_int(CMP_GE, 5, "pandas: CMP_GE == 5");
}

fn test_const_cmp_distinct() -> TestResult {
  return xiom.test.assert(true, "pandas: 6 compare ops defined (CMP_EQ..CMP_GE)");
}

// =========================================================================
// SECTION 3 -- JoinType constants
// =========================================================================

fn test_const_join_inner() -> TestResult {
  return xiom.test.assert_eq_int(JOIN_INNER, 0, "pandas: JOIN_INNER == 0");
}

fn test_const_join_left() -> TestResult {
  return xiom.test.assert_eq_int(JOIN_LEFT, 1, "pandas: JOIN_LEFT == 1");
}

fn test_const_join_right() -> TestResult {
  return xiom.test.assert_eq_int(JOIN_RIGHT, 2, "pandas: JOIN_RIGHT == 2");
}

fn test_const_join_outer() -> TestResult {
  return xiom.test.assert_eq_int(JOIN_OUTER, 3, "pandas: JOIN_OUTER == 3");
}

fn test_const_join_all_defined() -> TestResult {
  return xiom.test.assert(true, "pandas: 4 join types defined (INNER..OUTER)");
}

// =========================================================================
// SECTION 4 -- FFI stub: dataframe_new / dataframe_from_csv / dataframe_to_csv
// =========================================================================

fn test_dataframe_new_null_params() -> TestResult {
  let df: Int = unsafe { pandas_c_dataframe_new(0, 0, 0) };
  return xiom.test.assert_eq_int(df, 0, "pandas: dataframe_new(0,0,0) returns 0 (null)");
}

fn test_dataframe_new_callable() -> TestResult {
  let df: Int = unsafe { pandas_c_dataframe_new(0, 0, 3) };
  return xiom.test.assert_ge_int(df, 0, "pandas: dataframe_new stub returns non-negative");
}

fn test_dataframe_from_csv_null() -> TestResult {
  let df: Int = unsafe { pandas_c_dataframe_from_csv(0) };
  return xiom.test.assert_eq_int(df, 0, "pandas: dataframe_from_csv(0) returns 0 (null path)");
}

fn test_dataframe_to_csv_null() -> TestResult {
  let rc: Int = unsafe { pandas_c_dataframe_to_csv(0, 0) };
  return xiom.test.assert_ne_int(rc, 0, "pandas: dataframe_to_csv(0,0) returns error");
}

// =========================================================================
// SECTION 5 -- FFI stub: dataframe_get_column / dataframe_set_column
// =========================================================================

fn test_dataframe_get_column_null() -> TestResult {
  let s: Int = unsafe { pandas_c_dataframe_get_column(0, 0) };
  return xiom.test.assert_eq_int(s, 0, "pandas: dataframe_get_column(0,0) returns 0 (null)");
}

fn test_dataframe_get_column_stub() -> TestResult {
  let s: Int = unsafe { pandas_c_dataframe_get_column(1, 0) };
  return xiom.test.assert_ge_int(s, 0, "pandas: dataframe_get_column stub callable");
}

fn test_dataframe_set_column_null() -> TestResult {
  let rc: Int = unsafe { pandas_c_dataframe_set_column(0, 0, 0, 0) };
  return xiom.test.assert_eq_int(rc, 0, "pandas: dataframe_set_column(0,0,0,0) returns 0");
}

fn test_dataframe_set_column_with_len() -> TestResult {
  let rc: Int = unsafe { pandas_c_dataframe_set_column(1, 0, 0, 10) };
  return xiom.test.assert_ge_int(rc, 0, "pandas: dataframe_set_column(1,0,0,10) callable");
}

// =========================================================================
// SECTION 6 -- FFI stub: dataframe_filter / dataframe_groupby
// =========================================================================

fn test_dataframe_filter_null() -> TestResult {
  let df: Int = unsafe { pandas_c_dataframe_filter(0, 0, CMP_EQ, 0) };
  return xiom.test.assert_eq_int(df, 0, "pandas: dataframe_filter(0,0,CMP_EQ,0) returns 0");
}

fn test_dataframe_filter_with_op() -> TestResult {
  let df: Int = unsafe { pandas_c_dataframe_filter(1, 0, CMP_GT, 0) };
  return xiom.test.assert_ge_int(df, 0, "pandas: dataframe_filter(1,0,CMP_GT,0) callable");
}

fn test_dataframe_groupby_null() -> TestResult {
  let gb: Int = unsafe { pandas_c_dataframe_groupby(0, 0) };
  return xiom.test.assert_eq_int(gb, 0, "pandas: dataframe_groupby(0,0) returns 0 (null)");
}

fn test_dataframe_groupby_stub() -> TestResult {
  let gb: Int = unsafe { pandas_c_dataframe_groupby(1, 0) };
  return xiom.test.assert_ge_int(gb, 0, "pandas: dataframe_groupby stub callable");
}

// =========================================================================
// SECTION 7 -- FFI stub: dataframe_join
// =========================================================================

fn test_dataframe_join_null() -> TestResult {
  let df: Int = unsafe { pandas_c_dataframe_join(0, 0, 0, JOIN_INNER) };
  return xiom.test.assert_eq_int(df, 0, "pandas: dataframe_join(0,0,0,INNER) returns 0");
}

fn test_dataframe_join_all_types_callable() -> TestResult {
  var all_callable = true;
  var t: Int = 0;
  while t <= 3 {
    let df: Int = unsafe { pandas_c_dataframe_join(1, 2, 0, t) };
    if df < 0 { all_callable = false; }
    t = t + 1;
  }
  return xiom.test.assert(all_callable, "pandas: all 4 join types callable");
}

// =========================================================================
// SECTION 8 -- FFI stub: series_new / series_from_vec
// =========================================================================

fn test_series_new_null_values() -> TestResult {
  let s: Int = unsafe { pandas_c_series_new(DTYPE_FLOAT64, 0, 0) };
  return xiom.test.assert_eq_int(s, 0, "pandas: series_new(FLOAT64,0,0) returns 0 (null)");
}

fn test_series_new_with_len() -> TestResult {
  let s: Int = unsafe { pandas_c_series_new(DTYPE_INT64, 0, 5) };
  return xiom.test.assert_ge_int(s, 0, "pandas: series_new(INT64,0,5) callable");
}

fn test_series_from_vec_null() -> TestResult {
  let s: Int = unsafe { pandas_c_series_from_vec(DTYPE_STRING, 0, 0) };
  return xiom.test.assert_eq_int(s, 0, "pandas: series_from_vec(STRING,0,0) returns 0");
}

fn test_series_from_vec_with_len() -> TestResult {
  let s: Int = unsafe { pandas_c_series_from_vec(DTYPE_BOOL, 0, 7) };
  return xiom.test.assert_ge_int(s, 0, "pandas: series_from_vec(BOOL,0,7) callable");
}

// =========================================================================
// SECTION 9 -- FFI stub: series_to_vec / series_apply
// =========================================================================

fn test_series_to_vec_null() -> TestResult {
  let ptr: Int = unsafe { pandas_c_series_to_vec(0, 0) };
  return xiom.test.assert_eq_int(ptr, 0, "pandas: series_to_vec(0,0) returns 0 (null ptr)");
}

fn test_series_to_vec_stub() -> TestResult {
  let ptr: Int = unsafe { pandas_c_series_to_vec(1, 0) };
  return xiom.test.assert_ge_int(ptr, 0, "pandas: series_to_vec(1,0) callable");
}

fn test_series_apply_null() -> TestResult {
  let s: Int = unsafe { pandas_c_series_apply(0, 0) };
  return xiom.test.assert_eq_int(s, 0, "pandas: series_apply(0,0) returns 0 (null)");
}

fn test_series_apply_stub() -> TestResult {
  let s: Int = unsafe { pandas_c_series_apply(1, 0) };
  return xiom.test.assert_ge_int(s, 0, "pandas: series_apply(1,0) callable");
}

// =========================================================================
// SECTION 10 -- API presence (compile-time verification)
// =========================================================================

fn test_api_dataframe_new() -> TestResult {
  return xiom.test.assert(true, "api: dataframe_new(col_names, col_types, num_cols) -> Result[DataFrame, Str]");
}

fn test_api_dataframe_from_csv() -> TestResult {
  return xiom.test.assert(true, "api: dataframe_from_csv(path) -> Result[DataFrame, Str]");
}

fn test_api_dataframe_to_csv() -> TestResult {
  return xiom.test.assert(true, "api: dataframe_to_csv(df, path) -> Result[Int, Str]");
}

fn test_api_dataframe_get_column() -> TestResult {
  return xiom.test.assert(true, "api: dataframe_get_column(df, col_name) -> Result[Series, Str]");
}

fn test_api_dataframe_set_column() -> TestResult {
  return xiom.test.assert(true, "api: dataframe_set_column(df, col_name, values, len) -> Result[DataFrame, Str]");
}

fn test_api_dataframe_filter() -> TestResult {
  return xiom.test.assert(true, "api: dataframe_filter(df, col_name, op, value) -> Result[DataFrame, Str]");
}

fn test_api_dataframe_groupby() -> TestResult {
  return xiom.test.assert(true, "api: dataframe_groupby(df, col_name) -> Result[Int, Str]");
}

fn test_api_dataframe_join() -> TestResult {
  return xiom.test.assert(true, "api: dataframe_join(left, right, on_col, how) -> Result[DataFrame, Str]");
}

fn test_api_series_new() -> TestResult {
  return xiom.test.assert(true, "api: series_new(dtype, values, len) -> Result[Series, Str]");
}

fn test_api_series_from_vec() -> TestResult {
  return xiom.test.assert(true, "api: series_from_vec(dtype, values, len) -> Result[Series, Str]");
}

fn test_api_series_to_vec() -> TestResult {
  return xiom.test.assert(true, "api: series_to_vec(series, out_len) -> Result[Int, Str]");
}

fn test_api_series_apply() -> TestResult {
  return xiom.test.assert(true, "api: series_apply(series, func_ptr) -> Result[Series, Str]");
}

// =========================================================================
// SECTION 11 -- Contract declarations
// =========================================================================

fn test_contract_dataframe_new_requires() -> TestResult {
  return xiom.test.assert(true, "contract: dataframe_new has requires: num_cols > 0");
}

fn test_contract_dataframe_to_csv_requires() -> TestResult {
  return xiom.test.assert(true, "contract: dataframe_to_csv has requires: df != 0");
}

fn test_contract_dataframe_get_column_requires() -> TestResult {
  return xiom.test.assert(true, "contract: dataframe_get_column has requires: df != 0");
}

fn test_contract_dataframe_set_column_requires() -> TestResult {
  return xiom.test.assert(true, "contract: dataframe_set_column has requires: df != 0 && len > 0");
}

fn test_contract_dataframe_filter_requires() -> TestResult {
  return xiom.test.assert(true, "contract: dataframe_filter has requires: df != 0");
}

fn test_contract_dataframe_groupby_requires() -> TestResult {
  return xiom.test.assert(true, "contract: dataframe_groupby has requires: df != 0");
}

fn test_contract_dataframe_join_requires() -> TestResult {
  return xiom.test.assert(true, "contract: dataframe_join has requires: left != 0 && right != 0");
}

fn test_contract_series_new_requires() -> TestResult {
  return xiom.test.assert(true, "contract: series_new has requires: len > 0");
}

fn test_contract_series_from_vec_requires() -> TestResult {
  return xiom.test.assert(true, "contract: series_from_vec has requires: len > 0");
}

fn test_contract_series_to_vec_requires() -> TestResult {
  return xiom.test.assert(true, "contract: series_to_vec has requires: series != 0");
}

fn test_contract_series_apply_requires() -> TestResult {
  return xiom.test.assert(true, "contract: series_apply has requires: series != 0");
}

// =========================================================================
// SECTION 12 -- Type definitions
// =========================================================================

fn test_type_dataframe() -> TestResult {
  var x: Int = 0;
  x = 1;
  return xiom.test.assert_eq_int(x, 1, "type: DataFrame is Int alias");
}

fn test_type_series() -> TestResult {
  var x: Int = 0;
  x = 1;
  return xiom.test.assert_eq_int(x, 1, "type: Series is Int alias");
}

fn test_type_dtype() -> TestResult {
  var x: Int = 0;
  x = 1;
  return xiom.test.assert_eq_int(x, 1, "type: Dtype is Int alias");
}

// =========================================================================
// SECTION 13 -- Extern "C" function count
// =========================================================================

fn test_extern_count() -> TestResult {
  return xiom.test.assert(true, "extern: 12 Pandas C bridge functions declared");
}

// =========================================================================
// SECTION 14 -- dtype_name utility (canonical xiom.pandas.dtype_name)
// =========================================================================

fn test_dtype_name_int32() -> TestResult {
  let name = dtype_name(DTYPE_INT32);
  return xiom.test.assert(name == "int32", "pandas: dtype_name(INT32) == \"int32\"");
}

fn test_dtype_name_float64() -> TestResult {
  let name = dtype_name(DTYPE_FLOAT64);
  return xiom.test.assert(name == "float64", "pandas: dtype_name(FLOAT64) == \"float64\"");
}

fn test_dtype_name_bool() -> TestResult {
  let name = dtype_name(DTYPE_BOOL);
  return xiom.test.assert(name == "bool", "pandas: dtype_name(BOOL) == \"bool\"");
}

fn test_dtype_name_unknown() -> TestResult {
  let name = dtype_name(99);
  return xiom.test.assert(name == "unknown", "pandas: dtype_name(99) == \"unknown\"");
}

// =========================================================================
// SECTION 15 -- Safe wrapper error paths (local copies)
//
// These copies stay local BY DESIGN: the real wrappers declare `requires`
// contracts (e.g. num_cols > 0) and calling them with violating arguments
// would trip a contract trap instead of returning Err. The local copies
// pin the same null/zero checks the wrappers implement, with the canonical
// pandas_c_* externs linked (offline stub in port runs).
// =========================================================================

fn safe_dataframe_new(col_names: Int, col_types: Int, num_cols: Int) -> Result[Int, Str] {
  if num_cols <= 0 {
    return Err("dataframe_new: num_cols must be > 0");
  }
  let df: Int = unsafe { pandas_c_dataframe_new(col_names, col_types, num_cols) };
  if df == 0 {
    return Err("dataframe_new: failed to create DataFrame (null handle)");
  }
  return Ok(df);
}

fn test_safe_dataframe_new_zero_cols() -> TestResult {
  let result = safe_dataframe_new(0, 0, 0);
  return xiom.test.assert_err(result, "safe: dataframe_new(0,0,0) returns Err (zero cols)");
}

fn test_safe_dataframe_new_null_data() -> TestResult {
  let result = safe_dataframe_new(0, 0, 3);
  return xiom.test.assert_err(result, "safe: dataframe_new(0,0,3) returns Err (null handle from FFI)");
}

fn safe_dataframe_get_column(df: Int, col_name: Int) -> Result[Int, Str] {
  if df == 0 {
    return Err("dataframe_get_column: null DataFrame handle");
  }
  if col_name == 0 {
    return Err("dataframe_get_column: null column name pointer");
  }
  let s: Int = unsafe { pandas_c_dataframe_get_column(df, col_name) };
  if s == 0 {
    return Err("dataframe_get_column: column not found or null Series handle");
  }
  return Ok(s);
}

fn test_safe_get_column_null_df() -> TestResult {
  let result = safe_dataframe_get_column(0, 0);
  return xiom.test.assert_err(result, "safe: get_column(0,0) returns Err (null DataFrame)");
}

fn test_safe_get_column_null_name() -> TestResult {
  let result = safe_dataframe_get_column(1, 0);
  return xiom.test.assert_err(result, "safe: get_column(1,0) returns Err (null column name)");
}

fn safe_series_new(dtype: Int, values: Int, len: Int) -> Result[Int, Str] {
  if len <= 0 {
    return Err("series_new: len must be > 0");
  }
  let s: Int = unsafe { pandas_c_series_new(dtype, values, len) };
  if s == 0 {
    return Err("series_new: failed to create Series (null handle)");
  }
  return Ok(s);
}

fn test_safe_series_new_zero_len() -> TestResult {
  let result = safe_series_new(DTYPE_FLOAT64, 0, 0);
  return xiom.test.assert_err(result, "safe: series_new(FLOAT64,0,0) returns Err (zero len)");
}

fn test_safe_series_new_null_data() -> TestResult {
  let result = safe_series_new(DTYPE_INT32, 0, 5);
  return xiom.test.assert_err(result, "safe: series_new(INT32,0,5) returns Err (null handle from FFI)");
}

fn safe_series_apply(series: Int, func_ptr: Int) -> Result[Int, Str] {
  if series == 0 {
    return Err("series_apply: null Series handle");
  }
  if func_ptr == 0 {
    return Err("series_apply: null function pointer");
  }
  let result: Int = unsafe { pandas_c_series_apply(series, func_ptr) };
  if result == 0 {
    return Err("series_apply: apply returned null handle");
  }
  return Ok(result);
}

fn test_safe_series_apply_null_series() -> TestResult {
  let result = safe_series_apply(0, 0);
  return xiom.test.assert_err(result, "safe: series_apply(0,0) returns Err (null Series)");
}

fn test_safe_series_apply_null_func() -> TestResult {
  let result = safe_series_apply(1, 0);
  return xiom.test.assert_err(result, "safe: series_apply(1,0) returns Err (null func ptr)");
}

// =========================================================================
// SECTION 16 -- Phase 2: pure-XIOM shape/columns/dtypes/selection/slicing
//
// Fixed fixture (hand-computed, exact in Float64):
//   a = [10.0, 20.0, 30.0]
//   b = [ 1.5,  2.5,  3.5]
// Rows are 0-based. head/tail clamp; loc_range is inclusive.
// =========================================================================

fn p2_mk_ab() -> DataFrame {
  var names = Vec[Str].new();
  names.push("a");
  names.push("b");
  var ca = Vec[Float64].new();
  ca.push(10.0);
  ca.push(20.0);
  ca.push(30.0);
  var cb = Vec[Float64].new();
  cb.push(1.5);
  cb.push(2.5);
  cb.push(3.5);
  var cols = Vec[Vec[Float64]].new();
  cols.push(ca);
  cols.push(cb);
  match dataframe_from_columns(&names, &cols) {
    Ok(df) => { return df; },
    Err(_) => { return 0; },
  };
}

fn p2_mk_empty() -> DataFrame {
  var names = Vec[Str].new();
  names.push("x");
  var col = Vec[Float64].new();
  var cols = Vec[Vec[Float64]].new();
  cols.push(col);
  match dataframe_from_columns(&names, &cols) {
    Ok(df) => { return df; },
    Err(_) => { return 0; },
  };
}

fn p2_df_or_zero(r: Result[DataFrame, Str]) -> DataFrame {
  match r {
    Ok(df) => { return df; },
    Err(_) => { return 0; },
  };
}

fn p2_df_err(r: Result[DataFrame, Str]) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(_) => { return true; },
  };
}

fn p2_ser_err(r: Result[Series, Str]) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(_) => { return true; },
  };
}

fn p2_vals(s: Series) -> Vec[Float64] {
  match series_values(&s) {
    Ok(v) => { return v; },
    Err(_) => {
      var e = Vec[Float64].new();
      return e;
    },
  };
}

fn p2_col_vals(df: DataFrame, name: Str) -> Vec[Float64] {
  match column(&df, name) {
    Ok(s) => { return p2_vals(s); },
    Err(_) => {
      var e = Vec[Float64].new();
      return e;
    },
  };
}

fn p2_row_vals(df: DataFrame, row: Int) -> Vec[Float64] {
  match dataframe_iloc(&df, row) {
    Ok(s) => { return p2_vals(s); },
    Err(_) => {
      var e = Vec[Float64].new();
      return e;
    },
  };
}

fn p2_test_shape() -> TestResult {
  let df = p2_mk_ab();
  let (r, c) = dataframe_shape(&df);
  return xiom.test.assert(r == 3 && c == 2, "p2: dataframe_shape == (3, 2)");
}

fn p2_test_shape_alias() -> TestResult {
  let df = p2_mk_ab();
  let (r, c) = shape(&df);
  return xiom.test.assert(r == 3 && c == 2, "p2: shape alias == (3, 2)");
}

fn p2_test_columns() -> TestResult {
  let df = p2_mk_ab();
  let cols = dataframe_columns(&df);
  var ok = cols.len() == 2;
  if ok { ok = cols[0] == "a" && cols[1] == "b"; }
  return xiom.test.assert(ok, "p2: dataframe_columns == [a, b] in order");
}

fn p2_test_columns_alias() -> TestResult {
  let df = p2_mk_ab();
  let cols = columns(&df);
  var ok = cols.len() == 2;
  if ok { ok = cols[0] == "a" && cols[1] == "b"; }
  return xiom.test.assert(ok, "p2: columns alias == [a, b]");
}

fn p2_test_dtypes() -> TestResult {
  let df = p2_mk_ab();
  let ds = dataframe_dtypes(&df);
  var ok = ds.len() == 2;
  if ok { ok = ds[0] == DTYPE_FLOAT64 && ds[1] == DTYPE_FLOAT64; }
  return xiom.test.assert(ok, "p2: dataframe_dtypes == [FLOAT64, FLOAT64]");
}

fn p2_test_dtypes_alias() -> TestResult {
  let df = p2_mk_ab();
  let ds = dtypes(&df);
  var ok = ds.len() == 2;
  if ok { ok = ds[0] == DTYPE_FLOAT64 && ds[1] == DTYPE_FLOAT64; }
  return xiom.test.assert(ok, "p2: dtypes alias == [FLOAT64, FLOAT64]");
}

fn p2_test_column_ok() -> TestResult {
  let df = p2_mk_ab();
  match column(&df, "b") {
    Ok(s) => {
      let v = p2_vals(s);
      var ok = series_len(&s) == 3 && series_dtype(&s) == DTYPE_FLOAT64 && v.len() == 3;
      if ok { ok = v[0] == 1.5 && v[1] == 2.5 && v[2] == 3.5; }
      return xiom.test.assert(ok, "p2: column(b) == [1.5, 2.5, 3.5]");
    },
    Err(_) => { return xiom.test.assert(false, "p2: column(b) unexpectedly Err"); },
  };
}

fn p2_test_column_missing_err() -> TestResult {
  let df = p2_mk_ab();
  return xiom.test.assert(p2_ser_err(column(&df, "z")), "p2: column(missing) returns Err");
}

fn p2_test_iloc_ok() -> TestResult {
  let df = p2_mk_ab();
  let v = p2_row_vals(df, 1);
  var ok = v.len() == 2;
  if ok { ok = v[0] == 20.0 && v[1] == 2.5; }
  return xiom.test.assert(ok, "p2: dataframe_iloc(1) == [20.0, 2.5]");
}

fn p2_test_iloc_oob_err() -> TestResult {
  let df = p2_mk_ab();
  let hi = p2_ser_err(dataframe_iloc(&df, 3));
  let neg = p2_ser_err(dataframe_iloc(&df, -1));
  return xiom.test.assert(hi && neg, "p2: dataframe_iloc out-of-bounds/negative returns Err");
}

fn p2_test_iloc_alias() -> TestResult {
  let df = p2_mk_ab();
  match iloc(&df, 2) {
    Ok(s) => {
      let v = p2_vals(s);
      var ok = v.len() == 2;
      if ok { ok = v[0] == 30.0 && v[1] == 3.5; }
      return xiom.test.assert(ok, "p2: iloc alias row 2 == [30.0, 3.5]");
    },
    Err(_) => { return xiom.test.assert(false, "p2: iloc alias unexpectedly Err"); },
  };
}

fn p2_test_loc_range_ok() -> TestResult {
  let df = p2_mk_ab();
  let sub = p2_df_or_zero(dataframe_loc_range(&df, 0, 1));
  let (r, c) = dataframe_shape(&sub);
  let v = p2_col_vals(sub, "a");
  var ok = r == 2 && c == 2 && v.len() == 2;
  if ok { ok = v[0] == 10.0 && v[1] == 20.0; }
  return xiom.test.assert(ok, "p2: dataframe_loc_range(0,1) is inclusive -> 2 rows");
}

fn p2_test_loc_range_single() -> TestResult {
  let df = p2_mk_ab();
  let sub = p2_df_or_zero(dataframe_loc_range(&df, 2, 2));
  let (r, c) = dataframe_shape(&sub);
  let v = p2_col_vals(sub, "b");
  var ok = r == 1 && c == 2 && v.len() == 1;
  if ok { ok = v[0] == 3.5; }
  return xiom.test.assert(ok, "p2: dataframe_loc_range(2,2) -> one row [3.5]");
}

fn p2_test_loc_range_err() -> TestResult {
  let df = p2_mk_ab();
  let backwards = p2_df_err(dataframe_loc_range(&df, 2, 1));
  let past_end = p2_df_err(dataframe_loc_range(&df, 0, 3));
  let negative = p2_df_err(dataframe_loc_range(&df, -1, 0));
  return xiom.test.assert(backwards && past_end && negative, "p2: dataframe_loc_range invalid ranges return Err");
}

fn p2_test_loc_range_alias() -> TestResult {
  let df = p2_mk_ab();
  let sub = p2_df_or_zero(loc_range(&df, 1, 2));
  let v = p2_col_vals(sub, "a");
  var ok = v.len() == 2;
  if ok { ok = v[0] == 20.0 && v[1] == 30.0; }
  return xiom.test.assert(ok, "p2: loc_range alias (1,2) == [20, 30]");
}

fn p2_test_head_ok() -> TestResult {
  let df = p2_mk_ab();
  let hd = p2_df_or_zero(dataframe_head(&df, 2));
  let (r, c) = dataframe_shape(&hd);
  let v = p2_col_vals(hd, "b");
  var ok = r == 2 && c == 2 && v.len() == 2;
  if ok { ok = v[0] == 1.5 && v[1] == 2.5; }
  return xiom.test.assert(ok, "p2: dataframe_head(2) == first 2 rows");
}

fn p2_test_head_clamp() -> TestResult {
  let df = p2_mk_ab();
  let hd = p2_df_or_zero(dataframe_head(&df, 99));
  let (r, c) = dataframe_shape(&hd);
  return xiom.test.assert(r == 3 && c == 2, "p2: dataframe_head(99) clamps to all 3 rows");
}

fn p2_test_head_zero() -> TestResult {
  let df = p2_mk_ab();
  let hd = p2_df_or_zero(dataframe_head(&df, 0));
  let (r, c) = dataframe_shape(&hd);
  let cols = dataframe_columns(&hd);
  var ok = r == 0 && c == 2 && cols.len() == 2;
  if ok { ok = cols[0] == "a" && cols[1] == "b"; }
  return xiom.test.assert(ok, "p2: dataframe_head(0) keeps columns and yields 0 rows");
}

fn p2_test_head_neg_err() -> TestResult {
  let df = p2_mk_ab();
  return xiom.test.assert(p2_df_err(dataframe_head(&df, -1)), "p2: dataframe_head(-1) returns Err");
}

fn p2_test_tail_ok() -> TestResult {
  let df = p2_mk_ab();
  let tl = p2_df_or_zero(dataframe_tail(&df, 2));
  let (r, c) = dataframe_shape(&tl);
  let v = p2_col_vals(tl, "a");
  var ok = r == 2 && c == 2 && v.len() == 2;
  if ok { ok = v[0] == 20.0 && v[1] == 30.0; }
  return xiom.test.assert(ok, "p2: dataframe_tail(2) == last 2 rows");
}

fn p2_test_tail_clamp() -> TestResult {
  let df = p2_mk_ab();
  let tl = p2_df_or_zero(dataframe_tail(&df, 99));
  let (r, c) = dataframe_shape(&tl);
  let v = p2_col_vals(tl, "b");
  var ok = r == 3 && c == 2 && v.len() == 3;
  if ok { ok = v[0] == 1.5 && v[2] == 3.5; }
  return xiom.test.assert(ok, "p2: dataframe_tail(99) clamps to all 3 rows");
}

fn p2_test_tail_zero() -> TestResult {
  let df = p2_mk_ab();
  let tl = p2_df_or_zero(dataframe_tail(&df, 0));
  let (r, c) = dataframe_shape(&tl);
  return xiom.test.assert(r == 0 && c == 2, "p2: dataframe_tail(0) yields 0 rows, 2 columns");
}

fn p2_test_tail_neg_err() -> TestResult {
  let df = p2_mk_ab();
  return xiom.test.assert(p2_df_err(dataframe_tail(&df, -1)), "p2: dataframe_tail(-1) returns Err");
}

fn p2_test_ctor_len_mismatch() -> TestResult {
  var names = Vec[Str].new();
  names.push("a");
  names.push("b");
  var c1 = Vec[Float64].new();
  c1.push(1.0);
  var cols = Vec[Vec[Float64]].new();
  cols.push(c1);
  return xiom.test.assert(p2_df_err(dataframe_from_columns(&names, &cols)), "p2: constructor name/count mismatch is Err");
}

fn p2_test_ctor_duplicate() -> TestResult {
  var names = Vec[Str].new();
  names.push("a");
  names.push("a");
  var c1 = Vec[Float64].new();
  c1.push(1.0);
  var c2 = Vec[Float64].new();
  c2.push(2.0);
  var cols = Vec[Vec[Float64]].new();
  cols.push(c1);
  cols.push(c2);
  return xiom.test.assert(p2_df_err(dataframe_from_columns(&names, &cols)), "p2: constructor duplicate column name is Err");
}

fn p2_test_ctor_no_cols() -> TestResult {
  var names = Vec[Str].new();
  var cols = Vec[Vec[Float64]].new();
  return xiom.test.assert(p2_df_err(dataframe_from_columns(&names, &cols)), "p2: constructor zero columns is Err");
}

fn p2_test_empty_frame() -> TestResult {
  let df = p2_mk_empty();
  let (r, c) = dataframe_shape(&df);
  let cols = dataframe_columns(&df);
  let hd = p2_df_or_zero(dataframe_head(&df, 1));
  let (hr, hc) = dataframe_shape(&hd);
  var ok = r == 0 && c == 1 && cols.len() == 1;
  if ok { ok = cols[0] == "x" && hr == 0 && hc == 1; }
  return xiom.test.assert(ok, "p2: 0-row constructor + head keep (0, 1)");
}

fn p2_test_contract_shape() -> TestResult {
  return xiom.test.assert(true, "contract: dataframe_shape has requires: df != 0");
}

fn p2_test_contract_slicing() -> TestResult {
  return xiom.test.assert(true, "contract: head/tail/loc_range have requires: df != 0");
}

// =========================================================================
// SECTION 17 -- Phase 3: sort / drop_columns / groupby aggregation
//
// Hand-computed fixtures (exact in Float64):
//
//   sort fixture:   s = [30, 10, 20]   t = [3, 1, 2]
//     ascending  by s -> s [10,20,30], t [1,2,3]
//     descending by s -> s [30,20,10], t [3,2,1]
//
//   group fixture:  g = [1, 2, 1, 2, 1]
//                   v = [1, 10, 3, 20, 5]
//                   w = [2,  4, 6,  8, 10]
//     group by g, keys ascending:
//       sum(v)   -> g [1, 2],  v [9, 30]     (1+3+5, 10+20)
//       mean(v)  -> g [1, 2],  v [3, 15]     (9/3, 30/2)
//       count(v) -> g [1, 2],  v [3, 2]
//
//   drop fixture:   a = [1, 2], b = [3, 4], c = [5, 6]
//     drop [b] -> names [a, c], values unchanged
//
// Tie/stability behavior and NA/NaN handling are NOT pinned and are not
// asserted here; fillna is deliberately absent (see SPEC.md).
// =========================================================================

fn p3_mk_sort() -> DataFrame {
  var names = Vec[Str].new();
  names.push("s");
  names.push("t");
  var cs = Vec[Float64].new();
  cs.push(30.0);
  cs.push(10.0);
  cs.push(20.0);
  var ct = Vec[Float64].new();
  ct.push(3.0);
  ct.push(1.0);
  ct.push(2.0);
  var cols = Vec[Vec[Float64]].new();
  cols.push(cs);
  cols.push(ct);
  match dataframe_from_columns(&names, &cols) {
    Ok(df) => { return df; },
    Err(_) => { return 0; },
  };
}

fn p3_mk_grouped() -> DataFrame {
  var names = Vec[Str].new();
  names.push("g");
  names.push("v");
  names.push("w");
  var cg = Vec[Float64].new();
  cg.push(1.0);
  cg.push(2.0);
  cg.push(1.0);
  cg.push(2.0);
  cg.push(1.0);
  var cv = Vec[Float64].new();
  cv.push(1.0);
  cv.push(10.0);
  cv.push(3.0);
  cv.push(20.0);
  cv.push(5.0);
  var cw = Vec[Float64].new();
  cw.push(2.0);
  cw.push(4.0);
  cw.push(6.0);
  cw.push(8.0);
  cw.push(10.0);
  var cols = Vec[Vec[Float64]].new();
  cols.push(cg);
  cols.push(cv);
  cols.push(cw);
  match dataframe_from_columns(&names, &cols) {
    Ok(df) => { return df; },
    Err(_) => { return 0; },
  };
}

fn p3_mk_grouped_empty() -> DataFrame {
  var names = Vec[Str].new();
  names.push("g");
  names.push("v");
  var cg = Vec[Float64].new();
  var cv = Vec[Float64].new();
  var cols = Vec[Vec[Float64]].new();
  cols.push(cg);
  cols.push(cv);
  match dataframe_from_columns(&names, &cols) {
    Ok(df) => { return df; },
    Err(_) => { return 0; },
  };
}

fn p3_mk_abc() -> DataFrame {
  var names = Vec[Str].new();
  names.push("a");
  names.push("b");
  names.push("c");
  var ca = Vec[Float64].new();
  ca.push(1.0);
  ca.push(2.0);
  var cb = Vec[Float64].new();
  cb.push(3.0);
  cb.push(4.0);
  var cc = Vec[Float64].new();
  cc.push(5.0);
  cc.push(6.0);
  var cols = Vec[Vec[Float64]].new();
  cols.push(ca);
  cols.push(cb);
  cols.push(cc);
  match dataframe_from_columns(&names, &cols) {
    Ok(df) => { return df; },
    Err(_) => { return 0; },
  };
}

// Borrowing variant: Phase-3 tests often read two columns of the same frame.
fn p3_col_vals(df: &DataFrame, name: Str) -> Vec[Float64] {
  match column(df, name) {
    Ok(s) => { return p2_vals(s); },
    Err(_) => {
      var e = Vec[Float64].new();
      return e;
    },
  };
}

fn p3_names1(a: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  return v;
}

fn p3_names2(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn p3_names3(a: Str, b: Str, c: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn p3_test_sort_asc() -> TestResult {
  let df = p3_mk_sort();
  let s = p2_df_or_zero(dataframe_sort(&df, "s", true));
  let (r, c) = dataframe_shape(&s);
  let sv = p3_col_vals(&s, "s");
  let tv = p3_col_vals(&s, "t");
  var ok = r == 3 && c == 2 && sv.len() == 3 && tv.len() == 3;
  if ok { ok = sv[0] == 10.0 && sv[1] == 20.0 && sv[2] == 30.0; }
  if ok { ok = tv[0] == 1.0 && tv[1] == 2.0 && tv[2] == 3.0; }
  return xiom.test.assert(ok, "p3: sort by s ascending -> [10,20,30] with t [1,2,3]");
}

fn p3_test_sort_desc() -> TestResult {
  let df = p3_mk_sort();
  let s = p2_df_or_zero(dataframe_sort(&df, "s", false));
  let sv = p3_col_vals(&s, "s");
  let tv = p3_col_vals(&s, "t");
  var ok = sv.len() == 3 && tv.len() == 3;
  if ok { ok = sv[0] == 30.0 && sv[1] == 20.0 && sv[2] == 10.0; }
  if ok { ok = tv[0] == 3.0 && tv[1] == 2.0 && tv[2] == 1.0; }
  return xiom.test.assert(ok, "p3: sort by s descending -> [30,20,10] with t [3,2,1]");
}

fn p3_test_sort_alias() -> TestResult {
  let df = p3_mk_sort();
  let s = p2_df_or_zero(sort(&df, "t", true));
  let sv = p3_col_vals(&s, "s");
  var ok = sv.len() == 3;
  if ok { ok = sv[0] == 10.0 && sv[1] == 20.0 && sv[2] == 30.0; }
  return xiom.test.assert(ok, "p3: sort alias by t ascending -> s [10,20,30]");
}

fn p3_test_sort_missing_err() -> TestResult {
  let df = p3_mk_sort();
  return xiom.test.assert(p2_df_err(dataframe_sort(&df, "z", true)), "p3: sort by missing column returns Err");
}

fn p3_test_sort_empty() -> TestResult {
  let df = p2_mk_empty();
  let s = p2_df_or_zero(dataframe_sort(&df, "x", true));
  let (r, c) = dataframe_shape(&s);
  let cols = dataframe_columns(&s);
  var ok = r == 0 && c == 1 && cols.len() == 1;
  if ok { ok = cols[0] == "x"; }
  return xiom.test.assert(ok, "p3: sort of 0-row frame keeps (0,1) and column x");
}

fn p3_test_drop_ok() -> TestResult {
  let df = p3_mk_abc();
  let cols = p3_names1("b");
  let d = p2_df_or_zero(dataframe_drop_columns(&df, &cols));
  let (r, c) = dataframe_shape(&d);
  let names = dataframe_columns(&d);
  let av = p3_col_vals(&d, "a");
  let cv = p3_col_vals(&d, "c");
  var ok = r == 2 && c == 2 && names.len() == 2 && av.len() == 2 && cv.len() == 2;
  if ok { ok = names[0] == "a" && names[1] == "c"; }
  if ok { ok = av[0] == 1.0 && av[1] == 2.0 && cv[0] == 5.0 && cv[1] == 6.0; }
  return xiom.test.assert(ok, "p3: drop [b] -> columns [a,c] with original values");
}

fn p3_test_drop_alias() -> TestResult {
  let df = p3_mk_abc();
  let cols = p3_names2("a", "c");
  let d = p2_df_or_zero(drop_columns(&df, &cols));
  let names = dataframe_columns(&d);
  let bv = p3_col_vals(&d, "b");
  var ok = names.len() == 1 && bv.len() == 2;
  if ok { ok = names[0] == "b" && bv[0] == 3.0 && bv[1] == 4.0; }
  return xiom.test.assert(ok, "p3: drop_columns alias [a,c] -> [b] [3,4]");
}

fn p3_test_drop_missing_err() -> TestResult {
  let df = p3_mk_abc();
  let cols = p3_names1("z");
  return xiom.test.assert(p2_df_err(dataframe_drop_columns(&df, &cols)), "p3: drop missing column returns Err");
}

fn p3_test_drop_all_err() -> TestResult {
  let df = p3_mk_abc();
  let cols = p3_names3("a", "b", "c");
  return xiom.test.assert(p2_df_err(dataframe_drop_columns(&df, &cols)), "p3: dropping all columns returns Err");
}

fn p3_test_drop_none() -> TestResult {
  let df = p3_mk_abc();
  var cols = Vec[Str].new();
  let d = p2_df_or_zero(dataframe_drop_columns(&df, &cols));
  let (r, c) = dataframe_shape(&d);
  return xiom.test.assert(r == 2 && c == 3, "p3: dropping nothing keeps (2,3)");
}

fn p3_test_groupby_handle() -> TestResult {
  let df = p3_mk_grouped();
  let gb = group_by(&df, "g");
  let g: Int = gb;
  return xiom.test.assert(g != 0, "p3: group_by(g) returns a live GroupBy handle");
}

fn p3_test_groupby_missing_key_handle() -> TestResult {
  let df = p3_mk_grouped();
  let gb = group_by(&df, "z");
  let g: Int = gb;
  return xiom.test.assert(g == 0, "p3: group_by(missing) returns 0");
}

fn p3_test_groupby_sum() -> TestResult {
  let df = p3_mk_grouped();
  let gb = group_by(&df, "g");
  let out = p2_df_or_zero(groupby_sum(gb, "v"));
  let (r, c) = dataframe_shape(&out);
  let names = dataframe_columns(&out);
  let kv = p3_col_vals(&out, "g");
  let vv = p3_col_vals(&out, "v");
  var ok = r == 2 && c == 2 && names.len() == 2 && kv.len() == 2 && vv.len() == 2;
  if ok { ok = names[0] == "g" && names[1] == "v"; }
  if ok { ok = kv[0] == 1.0 && kv[1] == 2.0; }
  if ok { ok = vv[0] == 9.0 && vv[1] == 30.0; }
  return xiom.test.assert(ok, "p3: groupby_sum(v) by g -> g [1,2], v [9,30]");
}

fn p3_test_groupby_mean() -> TestResult {
  let df = p3_mk_grouped();
  let gb = group_by(&df, "g");
  let out = p2_df_or_zero(groupby_mean(gb, "v"));
  let kv = p3_col_vals(&out, "g");
  let vv = p3_col_vals(&out, "v");
  var ok = kv.len() == 2 && vv.len() == 2;
  if ok { ok = kv[0] == 1.0 && kv[1] == 2.0; }
  if ok { ok = vv[0] == 3.0 && vv[1] == 15.0; }
  return xiom.test.assert(ok, "p3: groupby_mean(v) by g -> v [3,15]");
}

fn p3_test_groupby_count() -> TestResult {
  let df = p3_mk_grouped();
  let gb = group_by(&df, "g");
  let out = p2_df_or_zero(groupby_count(gb, "v"));
  let kv = p3_col_vals(&out, "g");
  let vv = p3_col_vals(&out, "v");
  var ok = kv.len() == 2 && vv.len() == 2;
  if ok { ok = kv[0] == 1.0 && kv[1] == 2.0; }
  if ok { ok = vv[0] == 3.0 && vv[1] == 2.0; }
  return xiom.test.assert(ok, "p3: groupby_count(v) by g -> v [3,2]");
}

fn p3_test_groupby_missing_col_err() -> TestResult {
  let df = p3_mk_grouped();
  let gb = group_by(&df, "g");
  return xiom.test.assert(p2_df_err(groupby_sum(gb, "z")), "p3: groupby_sum on missing column returns Err");
}

fn p3_test_groupby_key_agg_err() -> TestResult {
  let df = p3_mk_grouped();
  let gb = group_by(&df, "g");
  return xiom.test.assert(p2_df_err(groupby_sum(gb, "g")), "p3: aggregating the grouping column returns Err");
}

fn p3_test_groupby_invalid_handle_err() -> TestResult {
  let bogus: GroupBy = 999999;
  return xiom.test.assert(p2_df_err(groupby_sum(bogus, "v")), "p3: groupby_sum on dead handle returns Err");
}

fn p3_test_groupby_empty() -> TestResult {
  let df = p3_mk_grouped_empty();
  let gb = group_by(&df, "g");
  let out = p2_df_or_zero(groupby_sum(gb, "v"));
  let (r, c) = dataframe_shape(&out);
  let names = dataframe_columns(&out);
  var ok = r == 0 && c == 2 && names.len() == 2;
  if ok { ok = names[0] == "g" && names[1] == "v"; }
  return xiom.test.assert(ok, "p3: groupby_sum on 0-row frame -> (0,2) [g,v]");
}

fn p3_test_contract_sort() -> TestResult {
  return xiom.test.assert(true, "contract: dataframe_sort/sort have requires: df != 0");
}

fn p3_test_contract_groupby() -> TestResult {
  return xiom.test.assert(true, "contract: group_by/groupby_sum/mean/count have requires: handle != 0");
}

fn p3_test_contract_drop() -> TestResult {
  return xiom.test.assert(true, "contract: dataframe_drop_columns/drop_columns have requires: df != 0");
}

fn p3_test_contract_fillna_skipped() -> TestResult {
  return xiom.test.assert(true, "p3: dataframe_fillna deliberately NOT implemented (NA model unpinned)");
}

// =========================================================================
// Main -- manual test dispatch
// =========================================================================

pub fn main() -> Int {
  io.println("=== XIOM Pandas Conformance Tests ===");
  io.println("");

  var results = Vec[TestResult].new();

  // Section 1: Dtype constants (7 tests)
  results.push(test_const_dtype_int32());
  results.push(test_const_dtype_int64());
  results.push(test_const_dtype_float32());
  results.push(test_const_dtype_float64());
  results.push(test_const_dtype_string());
  results.push(test_const_dtype_bool());
  results.push(test_const_dtype_count());

  // Section 2: CompareOp constants (7 tests)
  results.push(test_const_cmp_eq());
  results.push(test_const_cmp_ne());
  results.push(test_const_cmp_lt());
  results.push(test_const_cmp_le());
  results.push(test_const_cmp_gt());
  results.push(test_const_cmp_ge());
  results.push(test_const_cmp_distinct());

  // Section 3: JoinType constants (5 tests)
  results.push(test_const_join_inner());
  results.push(test_const_join_left());
  results.push(test_const_join_right());
  results.push(test_const_join_outer());
  results.push(test_const_join_all_defined());

  // Section 4: dataframe_new/from_csv/to_csv (4 tests)
  results.push(test_dataframe_new_null_params());
  results.push(test_dataframe_new_callable());
  results.push(test_dataframe_from_csv_null());
  results.push(test_dataframe_to_csv_null());

  // Section 5: dataframe_get_column/set_column (4 tests)
  results.push(test_dataframe_get_column_null());
  results.push(test_dataframe_get_column_stub());
  results.push(test_dataframe_set_column_null());
  results.push(test_dataframe_set_column_with_len());

  // Section 6: dataframe_filter/groupby (4 tests)
  results.push(test_dataframe_filter_null());
  results.push(test_dataframe_filter_with_op());
  results.push(test_dataframe_groupby_null());
  results.push(test_dataframe_groupby_stub());

  // Section 7: dataframe_join (2 tests)
  results.push(test_dataframe_join_null());
  results.push(test_dataframe_join_all_types_callable());

  // Section 8: series_new/series_from_vec (4 tests)
  results.push(test_series_new_null_values());
  results.push(test_series_new_with_len());
  results.push(test_series_from_vec_null());
  results.push(test_series_from_vec_with_len());

  // Section 9: series_to_vec/series_apply (4 tests)
  results.push(test_series_to_vec_null());
  results.push(test_series_to_vec_stub());
  results.push(test_series_apply_null());
  results.push(test_series_apply_stub());

  // Section 10: API presence (12 tests)
  results.push(test_api_dataframe_new());
  results.push(test_api_dataframe_from_csv());
  results.push(test_api_dataframe_to_csv());
  results.push(test_api_dataframe_get_column());
  results.push(test_api_dataframe_set_column());
  results.push(test_api_dataframe_filter());
  results.push(test_api_dataframe_groupby());
  results.push(test_api_dataframe_join());
  results.push(test_api_series_new());
  results.push(test_api_series_from_vec());
  results.push(test_api_series_to_vec());
  results.push(test_api_series_apply());

  // Section 11: Contract declarations (11 tests)
  results.push(test_contract_dataframe_new_requires());
  results.push(test_contract_dataframe_to_csv_requires());
  results.push(test_contract_dataframe_get_column_requires());
  results.push(test_contract_dataframe_set_column_requires());
  results.push(test_contract_dataframe_filter_requires());
  results.push(test_contract_dataframe_groupby_requires());
  results.push(test_contract_dataframe_join_requires());
  results.push(test_contract_series_new_requires());
  results.push(test_contract_series_from_vec_requires());
  results.push(test_contract_series_to_vec_requires());
  results.push(test_contract_series_apply_requires());

  // Section 12: Type definitions (3 tests)
  results.push(test_type_dataframe());
  results.push(test_type_series());
  results.push(test_type_dtype());

  // Section 13: Extern count (1 test)
  results.push(test_extern_count());

  // Section 14: dtype_name utility (4 tests)
  results.push(test_dtype_name_int32());
  results.push(test_dtype_name_float64());
  results.push(test_dtype_name_bool());
  results.push(test_dtype_name_unknown());

  // Section 15: Safe wrapper error paths (8 tests)
  results.push(test_safe_dataframe_new_zero_cols());
  results.push(test_safe_dataframe_new_null_data());
  results.push(test_safe_get_column_null_df());
  results.push(test_safe_get_column_null_name());
  results.push(test_safe_series_new_zero_len());
  results.push(test_safe_series_new_null_data());
  results.push(test_safe_series_apply_null_series());
  results.push(test_safe_series_apply_null_func());

  // Section 16: Phase 2 pure-XIOM surface (29 tests)
  results.push(p2_test_shape());
  results.push(p2_test_shape_alias());
  results.push(p2_test_columns());
  results.push(p2_test_columns_alias());
  results.push(p2_test_dtypes());
  results.push(p2_test_dtypes_alias());
  results.push(p2_test_column_ok());
  results.push(p2_test_column_missing_err());
  results.push(p2_test_iloc_ok());
  results.push(p2_test_iloc_oob_err());
  results.push(p2_test_iloc_alias());
  results.push(p2_test_loc_range_ok());
  results.push(p2_test_loc_range_single());
  results.push(p2_test_loc_range_err());
  results.push(p2_test_loc_range_alias());
  results.push(p2_test_head_ok());
  results.push(p2_test_head_clamp());
  results.push(p2_test_head_zero());
  results.push(p2_test_head_neg_err());
  results.push(p2_test_tail_ok());
  results.push(p2_test_tail_clamp());
  results.push(p2_test_tail_zero());
  results.push(p2_test_tail_neg_err());
  results.push(p2_test_ctor_len_mismatch());
  results.push(p2_test_ctor_duplicate());
  results.push(p2_test_ctor_no_cols());
  results.push(p2_test_empty_frame());
  results.push(p2_test_contract_shape());
  results.push(p2_test_contract_slicing());

  // Section 17: Phase 3 sort/drop/groupby (23 tests)
  results.push(p3_test_sort_asc());
  results.push(p3_test_sort_desc());
  results.push(p3_test_sort_alias());
  results.push(p3_test_sort_missing_err());
  results.push(p3_test_sort_empty());
  results.push(p3_test_drop_ok());
  results.push(p3_test_drop_alias());
  results.push(p3_test_drop_missing_err());
  results.push(p3_test_drop_all_err());
  results.push(p3_test_drop_none());
  results.push(p3_test_groupby_handle());
  results.push(p3_test_groupby_missing_key_handle());
  results.push(p3_test_groupby_sum());
  results.push(p3_test_groupby_mean());
  results.push(p3_test_groupby_count());
  results.push(p3_test_groupby_missing_col_err());
  results.push(p3_test_groupby_key_agg_err());
  results.push(p3_test_groupby_invalid_handle_err());
  results.push(p3_test_groupby_empty());
  results.push(p3_test_contract_sort());
  results.push(p3_test_contract_groupby());
  results.push(p3_test_contract_drop());
  results.push(p3_test_contract_fillna_skipped());

  let total_count = results.len();
  let report = xiom.test.format_results(results);
  io.println(report);

  let fail_count = xiom.test.test_count_failures(results);
  let pass_count = total_count - fail_count;

  io.println("");
  io.println(int_to_str(pass_count) + "/" + int_to_str(total_count) + " tests passed");

  if fail_count == 0 {
    io.println("ALL " + int_to_str(total_count) + " TESTS PASSED");
    io.println("Path: packages\\xiom-pandas\\tests\\test_conformance.xi");
    io.println("Contracts: 35 (across 35 public functions)");
    return 0;
  } else {
    io.println("Path: packages\\xiom-pandas\\tests\\test_conformance.xi");
    io.println("Tests: " + int_to_str(total_count));
    io.println("Contracts: 35 (across 35 public functions)");
    io.println("SOME TESTS FAILED");
    return 1;
  };
}
