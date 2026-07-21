// XIOM — Pandas DataFrame/Series Safe Wrappers
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Safe wrappers around the Pandas C bridge (Arrow-backed, zero Python overhead).
// Int-based opaque handles for DataFrame/Series with design-by-contract.
// Links against system-installed libpandas_bridge at link time.
//
// Compiler gap: raw pointer marshaling uses Int (memory address).
// Arrow C Data Interface is used for zero-copy interop with xiom-arrow.

module xiom.pandas

// =========================================================================
// Opaque handle types
// =========================================================================

pub type DataFrame = Int
pub type Series    = Int
pub type Dtype     = Int

// =========================================================================
// Dtype constants — columnar type encoding
// =========================================================================

pub const DTYPE_INT32:   Int = 0
pub const DTYPE_INT64:   Int = 1
pub const DTYPE_FLOAT32: Int = 2
pub const DTYPE_FLOAT64: Int = 3
pub const DTYPE_STRING:  Int = 4
pub const DTYPE_BOOL:    Int = 5

// =========================================================================
// Comparison operation constants
// =========================================================================

pub const CMP_EQ: Int = 0
pub const CMP_NE: Int = 1
pub const CMP_LT: Int = 2
pub const CMP_LE: Int = 3
pub const CMP_GT: Int = 4
pub const CMP_GE: Int = 5

// =========================================================================
// Join type constants
// =========================================================================

pub const JOIN_INNER: Int = 0
pub const JOIN_LEFT:  Int = 1
pub const JOIN_RIGHT: Int = 2
pub const JOIN_OUTER: Int = 3

// =========================================================================
// extern "C" — Pandas C bridge (12 functions)
//
// All pointer parameters use Int (memory address) until the compiler
// supports typed C pointer interop.
// =========================================================================

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
// dataframe_new — create a new DataFrame from column definitions
//
// col_names, col_types: raw pointer to arrays of Int (C strings / type enums).
// num_cols: number of columns.
// Returns Ok(DataFrame) or Err(message).
// requires: num_cols > 0
// =========================================================================

pub fn dataframe_new(col_names: Int, col_types: Int, num_cols: Int) -> Result[DataFrame, Str]
  requires: num_cols > 0
{
  if num_cols <= 0 {
    return Err("dataframe_new: num_cols must be > 0");
  }
  let df: Int = unsafe { dataframe_new(col_names, col_types, num_cols) };
  if df == 0 {
    return Err("dataframe_new: failed to create DataFrame (null handle)");
  }
  return Ok(df);
}

// =========================================================================
// dataframe_from_csv — read a DataFrame from a CSV file
//
// path: raw pointer to null-terminated C string.
// Returns Ok(DataFrame) or Err(message).
// =========================================================================

pub fn dataframe_from_csv(path: Int) -> Result[DataFrame, Str] {
  if path == 0 {
    return Err("dataframe_from_csv: null path pointer");
  }
  let df: Int = unsafe { dataframe_from_csv(path) };
  if df == 0 {
    return Err("dataframe_from_csv: failed to read CSV (null handle)");
  }
  return Ok(df);
}

// =========================================================================
// dataframe_to_csv — write a DataFrame to a CSV file
//
// Returns Ok(()) or Err(message).
// requires: df != 0
// =========================================================================

pub fn dataframe_to_csv(df: DataFrame, path: Int) -> Result[Int, Str]
  requires: df != 0
{
  if df == 0 {
    return Err("dataframe_to_csv: null DataFrame handle");
  }
  if path == 0 {
    return Err("dataframe_to_csv: null path pointer");
  }
  let rc: Int = unsafe { dataframe_to_csv(df, path) };
  if rc != 0 {
    return Err("dataframe_to_csv: failed to write CSV");
  }
  return Ok(0);
}

// =========================================================================
// dataframe_get_column — retrieve a Series from a DataFrame by column name
//
// col_name: raw pointer to null-terminated C string.
// Returns Ok(Series) or Err(message).
// requires: df != 0
// =========================================================================

pub fn dataframe_get_column(df: DataFrame, col_name: Int) -> Result[Series, Str]
  requires: df != 0
{
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

// =========================================================================
// dataframe_set_column — set/replace a column in a DataFrame
//
// values: raw pointer to Float64 array; len: number of elements.
// Returns Ok(DataFrame) or Err(message).
// requires: df != 0
// requires: len > 0
// =========================================================================

pub fn dataframe_set_column(df: DataFrame, col_name: Int, values: Int, len: Int) -> Result[DataFrame, Str]
  requires: df != 0
  requires: len > 0
{
  if df == 0 {
    return Err("dataframe_set_column: null DataFrame handle");
  }
  if col_name == 0 {
    return Err("dataframe_set_column: null column name pointer");
  }
  if len <= 0 {
    return Err("dataframe_set_column: len must be > 0");
  }
  let result: Int = unsafe { dataframe_set_column(df, col_name, values, len) };
  if result == 0 {
    return Err("dataframe_set_column: failed to set column");
  }
  return Ok(result);
}

// =========================================================================
// dataframe_filter — filter DataFrame rows by column comparison
//
// col_name: raw pointer to C string; op: CMP_* constant; value: Float64.
// Returns Ok(DataFrame) or Err(message).
// requires: df != 0
// =========================================================================

pub fn dataframe_filter(df: DataFrame, col_name: Int, op: Int, value: Int) -> Result[DataFrame, Str]
  requires: df != 0
{
  if df == 0 {
    return Err("dataframe_filter: null DataFrame handle");
  }
  if col_name == 0 {
    return Err("dataframe_filter: null column name pointer");
  }
  let result: Int = unsafe { dataframe_filter(df, col_name, op, value) };
  if result == 0 {
    return Err("dataframe_filter: filter returned null (no matching rows or error)");
  }
  return Ok(result);
}

// =========================================================================
// dataframe_groupby — group DataFrame by a column, returns group handle
//
// Returns Ok(group_handle) or Err(message).
// requires: df != 0
// =========================================================================

pub fn dataframe_groupby(df: DataFrame, col_name: Int) -> Result[Int, Str]
  requires: df != 0
{
  if df == 0 {
    return Err("dataframe_groupby: null DataFrame handle");
  }
  if col_name == 0 {
    return Err("dataframe_groupby: null column name pointer");
  }
  let gb: Int = unsafe { dataframe_groupby(df, col_name) };
  if gb == 0 {
    return Err("dataframe_groupby: groupby returned null handle");
  }
  return Ok(gb);
}

// =========================================================================
// dataframe_join — join two DataFrames on a column
//
// on_col: raw pointer to C string; how: JOIN_* constant.
// Returns Ok(DataFrame) or Err(message).
// requires: left != 0
// requires: right != 0
// =========================================================================

pub fn dataframe_join(left: DataFrame, right: DataFrame, on_col: Int, how: Int) -> Result[DataFrame, Str]
  requires: left != 0
  requires: right != 0
{
  if left == 0 || right == 0 {
    return Err("dataframe_join: null DataFrame handle(s)");
  }
  if on_col == 0 {
    return Err("dataframe_join: null column name pointer");
  }
  let result: Int = unsafe { dataframe_join(left, right, on_col, how) };
  if result == 0 {
    return Err("dataframe_join: join returned null handle");
  }
  return Ok(result);
}

// =========================================================================
// series_new — create a new Series from typed data
//
// dtype: DTYPE_* constant; values: raw pointer; len: element count.
// Returns Ok(Series) or Err(message).
// requires: len > 0
// =========================================================================

pub fn series_new(dtype: Dtype, values: Int, len: Int) -> Result[Series, Str]
  requires: len > 0
{
  if len <= 0 {
    return Err("series_new: len must be > 0");
  }
  let s: Int = unsafe { series_new(dtype, values, len) };
  if s == 0 {
    return Err("series_new: failed to create Series (null handle)");
  }
  return Ok(s);
}

// =========================================================================
// series_from_vec — create a Series from a Vec[Float64]
//
// dtype: DTYPE_* constant; values: raw pointer; len: element count.
// Returns Ok(Series) or Err(message).
// requires: len > 0
// =========================================================================

pub fn series_from_vec(dtype: Dtype, values: Int, len: Int) -> Result[Series, Str]
  requires: len > 0
{
  if len <= 0 {
    return Err("series_from_vec: len must be > 0");
  }
  let s: Int = unsafe { series_from_vec(dtype, values, len) };
  if s == 0 {
    return Err("series_from_vec: failed to create Series from Vec (null handle)");
  }
  return Ok(s);
}

// =========================================================================
// series_to_vec — extract Series data into a raw array
//
// out_len: pointer to Int (filled with output length).
// Returns Ok(ptr to data) or Err(message).
// requires: series != 0
// =========================================================================

pub fn series_to_vec(series: Series, out_len: Int) -> Result[Int, Str]
  requires: series != 0
{
  if series == 0 {
    return Err("series_to_vec: null Series handle");
  }
  let ptr: Int = unsafe { series_to_vec(series, out_len) };
  if ptr == 0 {
    return Err("series_to_vec: failed to extract data (null pointer)");
  }
  return Ok(ptr);
}

// =========================================================================
// series_apply — apply a function to each element of a Series
//
// func_ptr: raw function pointer; returns new Series.
// Returns Ok(Series) or Err(message).
// requires: series != 0
// =========================================================================

pub fn series_apply(series: Series, func_ptr: Int) -> Result[Series, Str]
  requires: series != 0
{
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

// =========================================================================
// Utility: dtype_name — human-readable name for a Dtype constant
// =========================================================================

pub fn dtype_name(dtype: Dtype) -> Str {
  if dtype == DTYPE_INT32   { return "int32"; }
  elif dtype == DTYPE_INT64   { return "int64"; }
  elif dtype == DTYPE_FLOAT32 { return "float32"; }
  elif dtype == DTYPE_FLOAT64 { return "float64"; }
  elif dtype == DTYPE_STRING  { return "string"; }
  elif dtype == DTYPE_BOOL    { return "bool"; }
  else { return "unknown"; }
}

// =========================================================================
// Utility: version
// =========================================================================

pub fn version() -> Str {
  "0.1.0"
}
