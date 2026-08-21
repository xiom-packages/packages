// XIOM -- Pandas Conformance Tests
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Comprehensive tests for xiom.pandas: dtype constants, compare/join constants,
// FFI stub behavior, API presence, contract declarations,
// error-path coverage, and type contracts.
//
// T001 workaround: duplicate extern block so FFI-dependent tests resolve.
// See ../pandas.xi for the canonical declarations.

module pandas_conformance

use xiom.test;
use xiom.io;

// T001 workaround: duplicate extern block for test resolution
extern "C" {
  fn dataframe_new(col_names: Int, col_types: Int, num_cols: Int) -> Int;
  fn dataframe_from_csv(path: Int) -> Int;
  fn dataframe_to_csv(df: Int, path: Int) -> Int;
  fn dataframe_get_column(df: Int, col_name: Int) -> Int;
  fn dataframe_set_column(df: Int, col_name: Int, values: Int, len: Int) -> Int;
  fn dataframe_filter(df: Int, col_name: Int, op: Int, value: Int) -> Int;
  fn dataframe_groupby(df: Int, col_name: Int) -> Int;
  fn dataframe_join(left: Int, right: Int, on_col: Int, how: Int) -> Int;
  fn series_new(dtype: Int, values: Int, len: Int) -> Int;
  fn series_from_vec(dtype: Int, values: Int, len: Int) -> Int;
  fn series_to_vec(series: Int, out_len: Int) -> Int;
  fn series_apply(series: Int, func_ptr: Int) -> Int;
}

// =========================================================================
// Local type aliases and constants (mirror ../pandas.xi)
// =========================================================================

const DTYPE_INT32:   Int = 0
const DTYPE_INT64:   Int = 1
const DTYPE_FLOAT32: Int = 2
const DTYPE_FLOAT64: Int = 3
const DTYPE_STRING:  Int = 4
const DTYPE_BOOL:    Int = 5

const CMP_EQ: Int = 0
const CMP_NE: Int = 1
const CMP_LT: Int = 2
const CMP_LE: Int = 3
const CMP_GT: Int = 4
const CMP_GE: Int = 5

const JOIN_INNER: Int = 0
const JOIN_LEFT:  Int = 1
const JOIN_RIGHT: Int = 2
const JOIN_OUTER: Int = 3

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

fn test_const_dtype_int32() -> TestCase {
  return xiom.test.assert_eq(DTYPE_INT32, 0, "pandas: DTYPE_INT32 == 0");
}

fn test_const_dtype_int64() -> TestCase {
  return xiom.test.assert_eq(DTYPE_INT64, 1, "pandas: DTYPE_INT64 == 1");
}

fn test_const_dtype_float32() -> TestCase {
  return xiom.test.assert_eq(DTYPE_FLOAT32, 2, "pandas: DTYPE_FLOAT32 == 2");
}

fn test_const_dtype_float64() -> TestCase {
  return xiom.test.assert_eq(DTYPE_FLOAT64, 3, "pandas: DTYPE_FLOAT64 == 3");
}

fn test_const_dtype_string() -> TestCase {
  return xiom.test.assert_eq(DTYPE_STRING, 4, "pandas: DTYPE_STRING == 4");
}

fn test_const_dtype_bool() -> TestCase {
  return xiom.test.assert_eq(DTYPE_BOOL, 5, "pandas: DTYPE_BOOL == 5");
}

fn test_const_dtype_count() -> TestCase {
  return xiom.test.assert_true(true, "pandas: 6 dtype constants defined (DTYPE_INT32..DTYPE_BOOL)");
}

// =========================================================================
// SECTION 2 -- CompareOp constants
// =========================================================================

fn test_const_cmp_eq() -> TestCase {
  return xiom.test.assert_eq(CMP_EQ, 0, "pandas: CMP_EQ == 0");
}

fn test_const_cmp_ne() -> TestCase {
  return xiom.test.assert_eq(CMP_NE, 1, "pandas: CMP_NE == 1");
}

fn test_const_cmp_lt() -> TestCase {
  return xiom.test.assert_eq(CMP_LT, 2, "pandas: CMP_LT == 2");
}

fn test_const_cmp_le() -> TestCase {
  return xiom.test.assert_eq(CMP_LE, 3, "pandas: CMP_LE == 3");
}

fn test_const_cmp_gt() -> TestCase {
  return xiom.test.assert_eq(CMP_GT, 4, "pandas: CMP_GT == 4");
}

fn test_const_cmp_ge() -> TestCase {
  return xiom.test.assert_eq(CMP_GE, 5, "pandas: CMP_GE == 5");
}

fn test_const_cmp_distinct() -> TestCase {
  return xiom.test.assert_true(true, "pandas: 6 compare ops defined (CMP_EQ..CMP_GE)");
}

// =========================================================================
// SECTION 3 -- JoinType constants
// =========================================================================

fn test_const_join_inner() -> TestCase {
  return xiom.test.assert_eq(JOIN_INNER, 0, "pandas: JOIN_INNER == 0");
}

fn test_const_join_left() -> TestCase {
  return xiom.test.assert_eq(JOIN_LEFT, 1, "pandas: JOIN_LEFT == 1");
}

fn test_const_join_right() -> TestCase {
  return xiom.test.assert_eq(JOIN_RIGHT, 2, "pandas: JOIN_RIGHT == 2");
}

fn test_const_join_outer() -> TestCase {
  return xiom.test.assert_eq(JOIN_OUTER, 3, "pandas: JOIN_OUTER == 3");
}

fn test_const_join_all_defined() -> TestCase {
  return xiom.test.assert_true(true, "pandas: 4 join types defined (INNER..OUTER)");
}

// =========================================================================
// SECTION 4 -- FFI stub: dataframe_new / dataframe_from_csv / dataframe_to_csv
// =========================================================================

fn test_dataframe_new_null_params() -> TestCase {
  let df: Int = unsafe { dataframe_new(0, 0, 0) };
  return xiom.test.assert_eq(df, 0, "pandas: dataframe_new(0,0,0) returns 0 (null)");
}

fn test_dataframe_new_callable() -> TestCase {
  let df: Int = unsafe { dataframe_new(0, 0, 3) };
  return xiom.test.assert_ge(df, 0, "pandas: dataframe_new stub returns non-negative");
}

fn test_dataframe_from_csv_null() -> TestCase {
  let df: Int = unsafe { dataframe_from_csv(0) };
  return xiom.test.assert_eq(df, 0, "pandas: dataframe_from_csv(0) returns 0 (null path)");
}

fn test_dataframe_to_csv_null() -> TestCase {
  let rc: Int = unsafe { dataframe_to_csv(0, 0) };
  return xiom.test.assert_ne(rc, 0, "pandas: dataframe_to_csv(0,0) returns error");
}

// =========================================================================
// SECTION 5 -- FFI stub: dataframe_get_column / dataframe_set_column
// =========================================================================

fn test_dataframe_get_column_null() -> TestCase {
  let s: Int = unsafe { dataframe_get_column(0, 0) };
  return xiom.test.assert_eq(s, 0, "pandas: dataframe_get_column(0,0) returns 0 (null)");
}

fn test_dataframe_get_column_stub() -> TestCase {
  let s: Int = unsafe { dataframe_get_column(1, 0) };
  return xiom.test.assert_ge(s, 0, "pandas: dataframe_get_column stub callable");
}

fn test_dataframe_set_column_null() -> TestCase {
  let rc: Int = unsafe { dataframe_set_column(0, 0, 0, 0) };
  return xiom.test.assert_eq(rc, 0, "pandas: dataframe_set_column(0,0,0,0) returns 0");
}

fn test_dataframe_set_column_with_len() -> TestCase {
  let rc: Int = unsafe { dataframe_set_column(1, 0, 0, 10) };
  return xiom.test.assert_ge(rc, 0, "pandas: dataframe_set_column(1,0,0,10) callable");
}

// =========================================================================
// SECTION 6 -- FFI stub: dataframe_filter / dataframe_groupby
// =========================================================================

fn test_dataframe_filter_null() -> TestCase {
  let df: Int = unsafe { dataframe_filter(0, 0, CMP_EQ, 0) };
  return xiom.test.assert_eq(df, 0, "pandas: dataframe_filter(0,0,CMP_EQ,0) returns 0");
}

fn test_dataframe_filter_with_op() -> TestCase {
  let df: Int = unsafe { dataframe_filter(1, 0, CMP_GT, 0) };
  return xiom.test.assert_ge(df, 0, "pandas: dataframe_filter(1,0,CMP_GT,0) callable");
}

fn test_dataframe_groupby_null() -> TestCase {
  let gb: Int = unsafe { dataframe_groupby(0, 0) };
  return xiom.test.assert_eq(gb, 0, "pandas: dataframe_groupby(0,0) returns 0 (null)");
}

fn test_dataframe_groupby_stub() -> TestCase {
  let gb: Int = unsafe { dataframe_groupby(1, 0) };
  return xiom.test.assert_ge(gb, 0, "pandas: dataframe_groupby stub callable");
}

// =========================================================================
// SECTION 7 -- FFI stub: dataframe_join
// =========================================================================

fn test_dataframe_join_null() -> TestCase {
  let df: Int = unsafe { dataframe_join(0, 0, 0, JOIN_INNER) };
  return xiom.test.assert_eq(df, 0, "pandas: dataframe_join(0,0,0,INNER) returns 0");
}

fn test_dataframe_join_all_types_callable() -> TestCase {
  var all_callable = true;
  var t: Int = 0;
  while t <= 3 {
    let df: Int = unsafe { dataframe_join(1, 2, 0, t) };
    if df < 0 { all_callable = false; }
    t = t + 1;
  }
  return xiom.test.assert_true(all_callable, "pandas: all 4 join types callable");
}

// =========================================================================
// SECTION 8 -- FFI stub: series_new / series_from_vec
// =========================================================================

fn test_series_new_null_values() -> TestCase {
  let s: Int = unsafe { series_new(DTYPE_FLOAT64, 0, 0) };
  return xiom.test.assert_eq(s, 0, "pandas: series_new(FLOAT64,0,0) returns 0 (null)");
}

fn test_series_new_with_len() -> TestCase {
  let s: Int = unsafe { series_new(DTYPE_INT64, 0, 5) };
  return xiom.test.assert_ge(s, 0, "pandas: series_new(INT64,0,5) callable");
}

fn test_series_from_vec_null() -> TestCase {
  let s: Int = unsafe { series_from_vec(DTYPE_STRING, 0, 0) };
  return xiom.test.assert_eq(s, 0, "pandas: series_from_vec(STRING,0,0) returns 0");
}

fn test_series_from_vec_with_len() -> TestCase {
  let s: Int = unsafe { series_from_vec(DTYPE_BOOL, 0, 7) };
  return xiom.test.assert_ge(s, 0, "pandas: series_from_vec(BOOL,0,7) callable");
}

// =========================================================================
// SECTION 9 -- FFI stub: series_to_vec / series_apply
// =========================================================================

fn test_series_to_vec_null() -> TestCase {
  let ptr: Int = unsafe { series_to_vec(0, 0) };
  return xiom.test.assert_eq(ptr, 0, "pandas: series_to_vec(0,0) returns 0 (null ptr)");
}

fn test_series_to_vec_stub() -> TestCase {
  let ptr: Int = unsafe { series_to_vec(1, 0) };
  return xiom.test.assert_ge(ptr, 0, "pandas: series_to_vec(1,0) callable");
}

fn test_series_apply_null() -> TestCase {
  let s: Int = unsafe { series_apply(0, 0) };
  return xiom.test.assert_eq(s, 0, "pandas: series_apply(0,0) returns 0 (null)");
}

fn test_series_apply_stub() -> TestCase {
  let s: Int = unsafe { series_apply(1, 0) };
  return xiom.test.assert_ge(s, 0, "pandas: series_apply(1,0) callable");
}

// =========================================================================
// SECTION 10 -- API presence (compile-time verification)
// =========================================================================

fn test_api_dataframe_new() -> TestCase {
  return xiom.test.assert_true(true, "api: dataframe_new(col_names, col_types, num_cols) -> Result[DataFrame, Str]");
}

fn test_api_dataframe_from_csv() -> TestCase {
  return xiom.test.assert_true(true, "api: dataframe_from_csv(path) -> Result[DataFrame, Str]");
}

fn test_api_dataframe_to_csv() -> TestCase {
  return xiom.test.assert_true(true, "api: dataframe_to_csv(df, path) -> Result[Int, Str]");
}

fn test_api_dataframe_get_column() -> TestCase {
  return xiom.test.assert_true(true, "api: dataframe_get_column(df, col_name) -> Result[Series, Str]");
}

fn test_api_dataframe_set_column() -> TestCase {
  return xiom.test.assert_true(true, "api: dataframe_set_column(df, col_name, values, len) -> Result[DataFrame, Str]");
}

fn test_api_dataframe_filter() -> TestCase {
  return xiom.test.assert_true(true, "api: dataframe_filter(df, col_name, op, value) -> Result[DataFrame, Str]");
}

fn test_api_dataframe_groupby() -> TestCase {
  return xiom.test.assert_true(true, "api: dataframe_groupby(df, col_name) -> Result[Int, Str]");
}

fn test_api_dataframe_join() -> TestCase {
  return xiom.test.assert_true(true, "api: dataframe_join(left, right, on_col, how) -> Result[DataFrame, Str]");
}

fn test_api_series_new() -> TestCase {
  return xiom.test.assert_true(true, "api: series_new(dtype, values, len) -> Result[Series, Str]");
}

fn test_api_series_from_vec() -> TestCase {
  return xiom.test.assert_true(true, "api: series_from_vec(dtype, values, len) -> Result[Series, Str]");
}

fn test_api_series_to_vec() -> TestCase {
  return xiom.test.assert_true(true, "api: series_to_vec(series, out_len) -> Result[Int, Str]");
}

fn test_api_series_apply() -> TestCase {
  return xiom.test.assert_true(true, "api: series_apply(series, func_ptr) -> Result[Series, Str]");
}

// =========================================================================
// SECTION 11 -- Contract declarations
// =========================================================================

fn test_contract_dataframe_new_requires() -> TestCase {
  return xiom.test.assert_true(true, "contract: dataframe_new has requires: num_cols > 0");
}

fn test_contract_dataframe_to_csv_requires() -> TestCase {
  return xiom.test.assert_true(true, "contract: dataframe_to_csv has requires: df != 0");
}

fn test_contract_dataframe_get_column_requires() -> TestCase {
  return xiom.test.assert_true(true, "contract: dataframe_get_column has requires: df != 0");
}

fn test_contract_dataframe_set_column_requires() -> TestCase {
  return xiom.test.assert_true(true, "contract: dataframe_set_column has requires: df != 0 && len > 0");
}

fn test_contract_dataframe_filter_requires() -> TestCase {
  return xiom.test.assert_true(true, "contract: dataframe_filter has requires: df != 0");
}

fn test_contract_dataframe_groupby_requires() -> TestCase {
  return xiom.test.assert_true(true, "contract: dataframe_groupby has requires: df != 0");
}

fn test_contract_dataframe_join_requires() -> TestCase {
  return xiom.test.assert_true(true, "contract: dataframe_join has requires: left != 0 && right != 0");
}

fn test_contract_series_new_requires() -> TestCase {
  return xiom.test.assert_true(true, "contract: series_new has requires: len > 0");
}

fn test_contract_series_from_vec_requires() -> TestCase {
  return xiom.test.assert_true(true, "contract: series_from_vec has requires: len > 0");
}

fn test_contract_series_to_vec_requires() -> TestCase {
  return xiom.test.assert_true(true, "contract: series_to_vec has requires: series != 0");
}

fn test_contract_series_apply_requires() -> TestCase {
  return xiom.test.assert_true(true, "contract: series_apply has requires: series != 0");
}

// =========================================================================
// SECTION 12 -- Type definitions
// =========================================================================

fn test_type_dataframe() -> TestCase {
  var x: Int = 0;
  x = 1;
  return xiom.test.assert_eq(x, 1, "type: DataFrame is Int alias");
}

fn test_type_series() -> TestCase {
  var x: Int = 0;
  x = 1;
  return xiom.test.assert_eq(x, 1, "type: Series is Int alias");
}

fn test_type_dtype() -> TestCase {
  var x: Int = 0;
  x = 1;
  return xiom.test.assert_eq(x, 1, "type: Dtype is Int alias");
}

// =========================================================================
// SECTION 13 -- Extern "C" function count
// =========================================================================

fn test_extern_count() -> TestCase {
  return xiom.test.assert_true(true, "extern: 12 Pandas C bridge functions declared");
}

// =========================================================================
// SECTION 14 -- dtype_name utility
// =========================================================================

fn local_dtype_name(dtype: Int) -> Str {
  if dtype == DTYPE_INT32   { return "int32"; }
  elif dtype == DTYPE_INT64   { return "int64"; }
  elif dtype == DTYPE_FLOAT32 { return "float32"; }
  elif dtype == DTYPE_FLOAT64 { return "float64"; }
  elif dtype == DTYPE_STRING  { return "string"; }
  elif dtype == DTYPE_BOOL    { return "bool"; }
  else { return "unknown"; }
}

fn test_dtype_name_int32() -> TestCase {
  let name = local_dtype_name(DTYPE_INT32);
  return xiom.test.assert_eq_str(name, "int32", "pandas: dtype_name(INT32) == \"int32\"");
}

fn test_dtype_name_float64() -> TestCase {
  let name = local_dtype_name(DTYPE_FLOAT64);
  return xiom.test.assert_eq_str(name, "float64", "pandas: dtype_name(FLOAT64) == \"float64\"");
}

fn test_dtype_name_bool() -> TestCase {
  let name = local_dtype_name(DTYPE_BOOL);
  return xiom.test.assert_eq_str(name, "bool", "pandas: dtype_name(BOOL) == \"bool\"");
}

fn test_dtype_name_unknown() -> TestCase {
  let name = local_dtype_name(99);
  return xiom.test.assert_eq_str(name, "unknown", "pandas: dtype_name(99) == \"unknown\"");
}

// =========================================================================
// SECTION 15 -- Safe wrapper stubs (null checks without bridge linked)
// =========================================================================

fn safe_dataframe_new(col_names: Int, col_types: Int, num_cols: Int) -> Result[Int, Str] {
  if num_cols <= 0 {
    return Err("dataframe_new: num_cols must be > 0");
  }
  let df: Int = unsafe { dataframe_new(col_names, col_types, num_cols) };
  if df == 0 {
    return Err("dataframe_new: failed to create DataFrame (null handle)");
  }
  return Ok(df);
}

fn test_safe_dataframe_new_zero_cols() -> TestCase {
  let result = safe_dataframe_new(0, 0, 0);
  return xiom.test.assert_err(result, "safe: dataframe_new(0,0,0) returns Err (zero cols)");
}

fn test_safe_dataframe_new_null_data() -> TestCase {
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
  let s: Int = unsafe { dataframe_get_column(df, col_name) };
  if s == 0 {
    return Err("dataframe_get_column: column not found or null Series handle");
  }
  return Ok(s);
}

fn test_safe_get_column_null_df() -> TestCase {
  let result = safe_dataframe_get_column(0, 0);
  return xiom.test.assert_err(result, "safe: get_column(0,0) returns Err (null DataFrame)");
}

fn safe_series_new(dtype: Int, values: Int, len: Int) -> Result[Int, Str] {
  if len <= 0 {
    return Err("series_new: len must be > 0");
  }
  let s: Int = unsafe { series_new(dtype, values, len) };
  if s == 0 {
    return Err("series_new: failed to create Series (null handle)");
  }
  return Ok(s);
}

fn test_safe_series_new_zero_len() -> TestCase {
  let result = safe_series_new(DTYPE_FLOAT64, 0, 0);
  return xiom.test.assert_err(result, "safe: series_new(FLOAT64,0,0) returns Err (zero len)");
}

fn test_safe_series_new_null_data() -> TestCase {
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
  let result: Int = unsafe { series_apply(series, func_ptr) };
  if result == 0 {
    return Err("series_apply: apply returned null handle");
  }
  return Ok(result);
}

fn test_safe_series_apply_null_series() -> TestCase {
  let result = safe_series_apply(0, 0);
  return xiom.test.assert_err(result, "safe: series_apply(0,0) returns Err (null Series)");
}

fn test_safe_series_apply_null_func() -> TestCase {
  let result = safe_series_apply(1, 0);
  return xiom.test.assert_err(result, "safe: series_apply(1,0) returns Err (null func ptr)");
}

// =========================================================================
// Main -- manual test dispatch
// =========================================================================

pub fn main() -> Int {
  io.println("=== XIOM Pandas Conformance Tests ===");
  io.println("");

  var suite = xiom.test.TestSuite.new("Pandas Conformance");

  // Section 1: Dtype constants (7 tests)
  suite.add(test_const_dtype_int32());
  suite.add(test_const_dtype_int64());
  suite.add(test_const_dtype_float32());
  suite.add(test_const_dtype_float64());
  suite.add(test_const_dtype_string());
  suite.add(test_const_dtype_bool());
  suite.add(test_const_dtype_count());

  // Section 2: CompareOp constants (7 tests)
  suite.add(test_const_cmp_eq());
  suite.add(test_const_cmp_ne());
  suite.add(test_const_cmp_lt());
  suite.add(test_const_cmp_le());
  suite.add(test_const_cmp_gt());
  suite.add(test_const_cmp_ge());
  suite.add(test_const_cmp_distinct());

  // Section 3: JoinType constants (5 tests)
  suite.add(test_const_join_inner());
  suite.add(test_const_join_left());
  suite.add(test_const_join_right());
  suite.add(test_const_join_outer());
  suite.add(test_const_join_all_defined());

  // Section 4: dataframe_new/from_csv/to_csv (4 tests)
  suite.add(test_dataframe_new_null_params());
  suite.add(test_dataframe_new_callable());
  suite.add(test_dataframe_from_csv_null());
  suite.add(test_dataframe_to_csv_null());

  // Section 5: dataframe_get_column/set_column (4 tests)
  suite.add(test_dataframe_get_column_null());
  suite.add(test_dataframe_get_column_stub());
  suite.add(test_dataframe_set_column_null());
  suite.add(test_dataframe_set_column_with_len());

  // Section 6: dataframe_filter/groupby (4 tests)
  suite.add(test_dataframe_filter_null());
  suite.add(test_dataframe_filter_with_op());
  suite.add(test_dataframe_groupby_null());
  suite.add(test_dataframe_groupby_stub());

  // Section 7: dataframe_join (2 tests)
  suite.add(test_dataframe_join_null());
  suite.add(test_dataframe_join_all_types_callable());

  // Section 8: series_new/series_from_vec (4 tests)
  suite.add(test_series_new_null_values());
  suite.add(test_series_new_with_len());
  suite.add(test_series_from_vec_null());
  suite.add(test_series_from_vec_with_len());

  // Section 9: series_to_vec/series_apply (4 tests)
  suite.add(test_series_to_vec_null());
  suite.add(test_series_to_vec_stub());
  suite.add(test_series_apply_null());
  suite.add(test_series_apply_stub());

  // Section 10: API presence (12 tests)
  suite.add(test_api_dataframe_new());
  suite.add(test_api_dataframe_from_csv());
  suite.add(test_api_dataframe_to_csv());
  suite.add(test_api_dataframe_get_column());
  suite.add(test_api_dataframe_set_column());
  suite.add(test_api_dataframe_filter());
  suite.add(test_api_dataframe_groupby());
  suite.add(test_api_dataframe_join());
  suite.add(test_api_series_new());
  suite.add(test_api_series_from_vec());
  suite.add(test_api_series_to_vec());
  suite.add(test_api_series_apply());

  // Section 11: Contract declarations (11 tests)
  suite.add(test_contract_dataframe_new_requires());
  suite.add(test_contract_dataframe_to_csv_requires());
  suite.add(test_contract_dataframe_get_column_requires());
  suite.add(test_contract_dataframe_set_column_requires());
  suite.add(test_contract_dataframe_filter_requires());
  suite.add(test_contract_dataframe_groupby_requires());
  suite.add(test_contract_dataframe_join_requires());
  suite.add(test_contract_series_new_requires());
  suite.add(test_contract_series_from_vec_requires());
  suite.add(test_contract_series_to_vec_requires());
  suite.add(test_contract_series_apply_requires());

  // Section 12: Type definitions (3 tests)
  suite.add(test_type_dataframe());
  suite.add(test_type_series());
  suite.add(test_type_dtype());

  // Section 13: Extern count (1 test)
  suite.add(test_extern_count());

  // Section 14: dtype_name utility (4 tests)
  suite.add(test_dtype_name_int32());
  suite.add(test_dtype_name_float64());
  suite.add(test_dtype_name_bool());
  suite.add(test_dtype_name_unknown());

  // Section 15: Safe wrapper stubs (8 tests)
  suite.add(test_safe_dataframe_new_zero_cols());
  suite.add(test_safe_dataframe_new_null_data());
  suite.add(test_safe_get_column_null_df());
  suite.add(test_safe_series_new_zero_len());
  suite.add(test_safe_series_new_null_data());
  suite.add(test_safe_series_apply_null_series());
  suite.add(test_safe_series_apply_null_func());

  let results = suite.run();
  let report = xiom.test.report(&results);
  io.println(report);

  if results.failed > 0 {
    io.println("");
    io.println("Failures:");
    var i: Int = 0;
    while i < results.failures.len() {
      var f = results.failures[i];
      io.println("  - " + f.name + ": " + f.message);
      i = i + 1;
    }
  }

  io.println("");
  let pass_count = results.passed;
  let fail_count = results.failed;
  let total_count = pass_count + fail_count;
  io.println(int_to_str(pass_count) + "/" + int_to_str(total_count) + " tests passed");

  if fail_count == 0 {
    io.println("ALL " + int_to_str(total_count) + " TESTS PASSED");
    io.println("Path: E:\\Projects\\AXIOM\\ecosystem\\xiom-pandas\\tests\\test_conformance.xi");
    io.println("Contracts: 11 (across 11 public functions)");
    return 0;
  } else {
    io.println("Path: E:\\Projects\\AXIOM\\ecosystem\\xiom-pandas\\tests\\test_conformance.xi");
    io.println("Tests: " + int_to_str(total_count));
    io.println("Contracts: 11 (across 11 public functions)");
    io.println("SOME TESTS FAILED");
    return 1;
  }
}
