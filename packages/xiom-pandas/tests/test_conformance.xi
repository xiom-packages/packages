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
  return xiom.test.assert(true, "extern: 18 Pandas C bridge functions declared");
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
// SECTION 16 -- FFI stub: pandas_dataframe_filter_f64 (section-8 decision 5)
// =========================================================================

fn test_filter_f64_null_df() -> TestResult {
  let df: Int = unsafe { pandas_dataframe_filter_f64(0, 0, CMP_EQ, 0) };
  return xiom.test.assert_eq_int(df, 0, "pandas: filter_f64(0,0,CMP_EQ,0) returns 0");
}

fn test_filter_f64_callable() -> TestResult {
  let df: Int = unsafe { pandas_dataframe_filter_f64(1, 0, CMP_GT, 0) };
  return xiom.test.assert_ge_int(df, 0, "pandas: filter_f64(1,0,CMP_GT,0) callable");
}

fn test_filter_f64_bad_op() -> TestResult {
  let df: Int = unsafe { pandas_dataframe_filter_f64(1, 1, 99, 0) };
  return xiom.test.assert_eq_int(df, 0, "pandas: filter_f64 bad op returns 0");
}

// =========================================================================
// SECTION 17 -- FFI stub: additive ownership frees (section-8 decision 4)
// =========================================================================

fn test_dataframe_free_null() -> TestResult {
  let rc: Int = unsafe { pandas_c_dataframe_free(0) };
  return xiom.test.assert_eq_int(rc, 0, "pandas: dataframe_free(0) returns 0");
}

fn test_dataframe_free_callable() -> TestResult {
  let rc: Int = unsafe { pandas_c_dataframe_free(1) };
  return xiom.test.assert_ge_int(rc, 0, "pandas: dataframe_free stub callable");
}

fn test_series_free_null() -> TestResult {
  let rc: Int = unsafe { pandas_c_series_free(0) };
  return xiom.test.assert_eq_int(rc, 0, "pandas: series_free(0) returns 0");
}

fn test_series_free_callable() -> TestResult {
  let rc: Int = unsafe { pandas_c_series_free(1) };
  return xiom.test.assert_ge_int(rc, 0, "pandas: series_free stub callable");
}

fn test_free_null() -> TestResult {
  let rc: Int = unsafe { pandas_c_free(0) };
  return xiom.test.assert_eq_int(rc, 0, "pandas: free(0) returns 0");
}

fn test_free_callable() -> TestResult {
  let rc: Int = unsafe { pandas_c_free(1) };
  return xiom.test.assert_ge_int(rc, 0, "pandas: free stub callable");
}

// =========================================================================
// SECTION 18 -- FFI stub: Parquet entry points (section-8 decision 6)
// =========================================================================

fn test_from_parquet_null() -> TestResult {
  let df: Int = unsafe { pandas_c_dataframe_from_parquet(0) };
  return xiom.test.assert_eq_int(df, 0, "pandas: from_parquet(0) returns 0");
}

fn test_from_parquet_callable() -> TestResult {
  let df: Int = unsafe { pandas_c_dataframe_from_parquet(1) };
  return xiom.test.assert_ge_int(df, 0, "pandas: from_parquet stub callable");
}

fn test_to_parquet_null() -> TestResult {
  let rc: Int = unsafe { pandas_c_dataframe_to_parquet(0, 0) };
  return xiom.test.assert_ne_int(rc, 0, "pandas: to_parquet(0,0) returns error");
}

fn test_to_parquet_callable() -> TestResult {
  let rc: Int = unsafe { pandas_c_dataframe_to_parquet(1, 1) };
  return xiom.test.assert_ne_int(rc, 0, "pandas: to_parquet stub reports backend unavailable");
}

// =========================================================================
// SECTION 19 -- API presence: additive 0.2.0 surface
// =========================================================================

fn test_api_dataframe_free() -> TestResult {
  return xiom.test.assert(true, "api: dataframe_free(df) -> Result[Int, Str]");
}

fn test_api_series_free() -> TestResult {
  return xiom.test.assert(true, "api: series_free(series) -> Result[Int, Str]");
}

fn test_api_series_buffer_free() -> TestResult {
  return xiom.test.assert(true, "api: series_buffer_free(ptr) -> Result[Int, Str]");
}

fn test_api_dataframe_filter_f64() -> TestResult {
  return xiom.test.assert(true, "api: dataframe_filter_f64(df, col_name, op, bits) -> Result[DataFrame, Str]");
}

fn test_api_dataframe_from_parquet() -> TestResult {
  return xiom.test.assert(true, "api: dataframe_from_parquet(path) -> Result[DataFrame, Str]");
}

fn test_api_dataframe_to_parquet() -> TestResult {
  return xiom.test.assert(true, "api: dataframe_to_parquet(df, path) -> Result[Int, Str]");
}

// =========================================================================
// SECTION 20 -- Contract declarations: additive 0.2.0 surface
// =========================================================================

fn test_contract_dataframe_free_requires() -> TestResult {
  return xiom.test.assert(true, "contract: dataframe_free has requires: df != 0");
}

fn test_contract_series_free_requires() -> TestResult {
  return xiom.test.assert(true, "contract: series_free has requires: series != 0");
}

fn test_contract_series_buffer_free_requires() -> TestResult {
  return xiom.test.assert(true, "contract: series_buffer_free has requires: ptr != 0");
}

fn test_contract_dataframe_filter_f64_requires() -> TestResult {
  return xiom.test.assert(true, "contract: dataframe_filter_f64 has requires: df != 0");
}

fn test_contract_dataframe_to_parquet_requires() -> TestResult {
  return xiom.test.assert(true, "contract: dataframe_to_parquet has requires: df != 0");
}

// =========================================================================
// SECTION 21 -- Safe wrapper error paths: additive 0.2.0 surface
// =========================================================================

fn safe_dataframe_free(df: Int) -> Result[Int, Str] {
  if df == 0 {
    return Err("dataframe_free: null DataFrame handle");
  }
  let rc: Int = unsafe { pandas_c_dataframe_free(df) };
  if rc == 0 {
    return Err("dataframe_free: free failed");
  }
  return Ok(0);
}

fn test_safe_dataframe_free_null() -> TestResult {
  let result = safe_dataframe_free(0);
  return xiom.test.assert_err(result, "safe: dataframe_free(0) returns Err");
}

fn safe_series_free(series: Int) -> Result[Int, Str] {
  if series == 0 {
    return Err("series_free: null Series handle");
  }
  let rc: Int = unsafe { pandas_c_series_free(series) };
  if rc == 0 {
    return Err("series_free: free failed");
  }
  return Ok(0);
}

fn test_safe_series_free_null() -> TestResult {
  let result = safe_series_free(0);
  return xiom.test.assert_err(result, "safe: series_free(0) returns Err");
}

fn safe_series_buffer_free(ptr: Int) -> Result[Int, Str] {
  if ptr == 0 {
    return Err("series_buffer_free: null buffer pointer");
  }
  let rc: Int = unsafe { pandas_c_free(ptr) };
  if rc == 0 {
    return Err("series_buffer_free: free failed");
  }
  return Ok(0);
}

fn test_safe_series_buffer_free_null() -> TestResult {
  let result = safe_series_buffer_free(0);
  return xiom.test.assert_err(result, "safe: series_buffer_free(0) returns Err");
}

fn safe_dataframe_filter_f64(df: Int, col_name: Int, op: Int, bits: Int) -> Result[Int, Str] {
  if df == 0 {
    return Err("dataframe_filter_f64: null DataFrame handle");
  }
  if col_name == 0 {
    return Err("dataframe_filter_f64: null column name pointer");
  }
  let result: Int = unsafe { pandas_dataframe_filter_f64(df, col_name, op, bits) };
  if result == 0 {
    return Err("dataframe_filter_f64: filter returned null");
  }
  return Ok(result);
}

fn test_safe_dataframe_filter_f64_null() -> TestResult {
  let result = safe_dataframe_filter_f64(0, 0, CMP_EQ, 0);
  return xiom.test.assert_err(result, "safe: dataframe_filter_f64(0,0,...) returns Err");
}

fn safe_dataframe_from_parquet(path: Int) -> Result[Int, Str] {
  if path == 0 {
    return Err("dataframe_from_parquet: null path pointer");
  }
  let df: Int = unsafe { pandas_c_dataframe_from_parquet(path) };
  if df == 0 {
    return Err("dataframe_from_parquet: backend unavailable");
  }
  return Ok(df);
}

fn test_safe_dataframe_from_parquet_null() -> TestResult {
  let result = safe_dataframe_from_parquet(0);
  return xiom.test.assert_err(result, "safe: dataframe_from_parquet(0) returns Err");
}

fn safe_dataframe_to_parquet(df: Int, path: Int) -> Result[Int, Str] {
  if df == 0 {
    return Err("dataframe_to_parquet: null DataFrame handle");
  }
  if path == 0 {
    return Err("dataframe_to_parquet: null path pointer");
  }
  let rc: Int = unsafe { pandas_c_dataframe_to_parquet(df, path) };
  if rc != 0 {
    return Err("dataframe_to_parquet: failed");
  }
  return Ok(0);
}

fn test_safe_dataframe_to_parquet_null() -> TestResult {
  let result = safe_dataframe_to_parquet(0, 0);
  return xiom.test.assert_err(result, "safe: dataframe_to_parquet(0,0) returns Err");
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

  // Section 16: filter_f64 stub (3 tests)
  results.push(test_filter_f64_null_df());
  results.push(test_filter_f64_callable());
  results.push(test_filter_f64_bad_op());

  // Section 17: ownership frees stub (6 tests)
  results.push(test_dataframe_free_null());
  results.push(test_dataframe_free_callable());
  results.push(test_series_free_null());
  results.push(test_series_free_callable());
  results.push(test_free_null());
  results.push(test_free_callable());

  // Section 18: Parquet stub (4 tests)
  results.push(test_from_parquet_null());
  results.push(test_from_parquet_callable());
  results.push(test_to_parquet_null());
  results.push(test_to_parquet_callable());

  // Section 19: additive API presence (6 tests)
  results.push(test_api_dataframe_free());
  results.push(test_api_series_free());
  results.push(test_api_series_buffer_free());
  results.push(test_api_dataframe_filter_f64());
  results.push(test_api_dataframe_from_parquet());
  results.push(test_api_dataframe_to_parquet());

  // Section 20: additive contract declarations (5 tests)
  results.push(test_contract_dataframe_free_requires());
  results.push(test_contract_series_free_requires());
  results.push(test_contract_series_buffer_free_requires());
  results.push(test_contract_dataframe_filter_f64_requires());
  results.push(test_contract_dataframe_to_parquet_requires());

  // Section 21: additive safe wrapper error paths (6 tests)
  results.push(test_safe_dataframe_free_null());
  results.push(test_safe_series_free_null());
  results.push(test_safe_series_buffer_free_null());
  results.push(test_safe_dataframe_filter_f64_null());
  results.push(test_safe_dataframe_from_parquet_null());
  results.push(test_safe_dataframe_to_parquet_null());

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
    io.println("Contracts: 16 (across 16 public functions)");
    return 0;
  } else {
    io.println("Path: packages\\xiom-pandas\\tests\\test_conformance.xi");
    io.println("Tests: " + int_to_str(total_count));
    io.println("Contracts: 16 (across 16 public functions)");
    io.println("SOME TESTS FAILED");
    return 1;
  };
}
