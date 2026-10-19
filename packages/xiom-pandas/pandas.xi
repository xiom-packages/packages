// XIOM -- Pandas DataFrame/Series Safe Wrappers
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Safe wrappers around the Pandas C bridge (Arrow-backed, zero Python overhead).
// Int-based opaque handles for DataFrame/Series with design-by-contract.
// Links against system-installed libpandas_bridge at link time.
//
// Compiler gap: raw pointer marshaling uses Int (memory address).
// Arrow C Data Interface is used for zero-copy interop with xiom.arrow.

module xiom.pandas

// =========================================================================
// Opaque handle types
// =========================================================================

pub type DataFrame = Int;
pub type Series    = Int;
pub type Dtype     = Int;
pub type GroupBy   = Int;

// =========================================================================
// Dtype constants -- columnar type encoding
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
// extern "C" -- Pandas C bridge (12 functions)
//
// The extern names carry a `pandas_c_` prefix and ARE the C symbol names
// (the numpy_c_* convention used by xiom.numpy). A wrapper must never be
// named after its C symbol (language rule 10: the collision is silently
// dropped); the `pandas_c_` prefix keeps every wrapper name distinct.
// All pointer parameters use Int (memory address) until the compiler
// supports typed C pointer interop. Handles: 0 = null/failure, > 0 = ok.
// =========================================================================

extern "C" {
  fn pandas_c_dataframe_new(col_names: Int, col_types: Int, num_cols: Int) -> Int;
  fn pandas_c_dataframe_from_csv(path: Int) -> Int;
  fn pandas_c_dataframe_to_csv(df: Int, path: Int) -> Int;
  fn pandas_c_dataframe_get_column(df: Int, col_name: Int) -> Int;
  fn pandas_c_dataframe_set_column(df: Int, col_name: Int, values: Int, len: Int) -> Int;
  fn pandas_c_dataframe_filter(df: Int, col_name: Int, op: Int, value: Int) -> Int;
  fn pandas_c_dataframe_groupby(df: Int, col_name: Int) -> Int;
  fn pandas_c_dataframe_join(left: Int, right: Int, on_col: Int, how: Int) -> Int;
  fn pandas_c_series_new(dtype: Int, values: Int, len: Int) -> Int;
  fn pandas_c_series_from_vec(dtype: Int, values: Int, len: Int) -> Int;
  fn pandas_c_series_to_vec(series: Int, out_len: Int) -> Int;
  fn pandas_c_series_apply(series: Int, func_ptr: Int) -> Int;
}

// =========================================================================
// dataframe_new -- create a new DataFrame from column definitions
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
  let df: Int = unsafe { pandas_c_dataframe_new(col_names, col_types, num_cols) };
  if df == 0 {
    return Err("dataframe_new: failed to create DataFrame (null handle)");
  }
  return Ok(df);
}

// =========================================================================
// dataframe_from_csv -- read a DataFrame from a CSV file
//
// path: raw pointer to null-terminated C string.
// Returns Ok(DataFrame) or Err(message).
// =========================================================================

pub fn dataframe_from_csv(path: Int) -> Result[DataFrame, Str] {
  if path == 0 {
    return Err("dataframe_from_csv: null path pointer");
  }
  let df: Int = unsafe { pandas_c_dataframe_from_csv(path) };
  if df == 0 {
    return Err("dataframe_from_csv: failed to read CSV (null handle)");
  }
  return Ok(df);
}

// =========================================================================
// dataframe_to_csv -- write a DataFrame to a CSV file
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
  let rc: Int = unsafe { pandas_c_dataframe_to_csv(df, path) };
  if rc != 0 {
    return Err("dataframe_to_csv: failed to write CSV");
  }
  return Ok(0);
}

// =========================================================================
// dataframe_get_column -- retrieve a Series from a DataFrame by column name
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
  let s: Int = unsafe { pandas_c_dataframe_get_column(df, col_name) };
  if s == 0 {
    return Err("dataframe_get_column: column not found or null Series handle");
  }
  return Ok(s);
}

// =========================================================================
// dataframe_set_column -- set/replace a column in a DataFrame
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
  let result: Int = unsafe { pandas_c_dataframe_set_column(df, col_name, values, len) };
  if result == 0 {
    return Err("dataframe_set_column: failed to set column");
  }
  return Ok(result);
}

// =========================================================================
// dataframe_filter -- filter DataFrame rows by column comparison
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
  let result: Int = unsafe { pandas_c_dataframe_filter(df, col_name, op, value) };
  if result == 0 {
    return Err("dataframe_filter: filter returned null (no matching rows or error)");
  }
  return Ok(result);
}

// =========================================================================
// dataframe_groupby -- group DataFrame by a column, returns group handle
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
  let gb: Int = unsafe { pandas_c_dataframe_groupby(df, col_name) };
  if gb == 0 {
    return Err("dataframe_groupby: groupby returned null handle");
  }
  return Ok(gb);
}

// =========================================================================
// dataframe_join -- join two DataFrames on a column
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
  let result: Int = unsafe { pandas_c_dataframe_join(left, right, on_col, how) };
  if result == 0 {
    return Err("dataframe_join: join returned null handle");
  }
  return Ok(result);
}

// =========================================================================
// series_new -- create a new Series from typed data
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
  let s: Int = unsafe { pandas_c_series_new(dtype, values, len) };
  if s == 0 {
    return Err("series_new: failed to create Series (null handle)");
  }
  return Ok(s);
}

// =========================================================================
// series_from_vec -- create a Series from a Vec[Float64]
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
  let s: Int = unsafe { pandas_c_series_from_vec(dtype, values, len) };
  if s == 0 {
    return Err("series_from_vec: failed to create Series from Vec (null handle)");
  }
  return Ok(s);
}

// =========================================================================
// series_to_vec -- extract Series data into a raw array
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
  let ptr: Int = unsafe { pandas_c_series_to_vec(series, out_len) };
  if ptr == 0 {
    return Err("series_to_vec: failed to extract data (null pointer)");
  }
  return Ok(ptr);
}

// =========================================================================
// series_apply -- apply a function to each element of a Series
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
  let result: Int = unsafe { pandas_c_series_apply(series, func_ptr) };
  if result == 0 {
    return Err("series_apply: apply returned null handle");
  }
  return Ok(result);
}

// =========================================================================
// Phase 2 -- pure-XIOM DataFrame/Series operations (no FFI)
//
// The Phase-2 leg owns a self-contained in-memory registry, following the
// xiom.numpy Phase-2a decision: `DataFrame`/`Series` stay opaque Int handles,
// handle 0 is invalid, and handles are 1 + slot index. Slots are append-only
// and never reused, so a stale handle cannot alias a later allocation.
//
// Storage model (pinned by SPEC's `Map[Str, Vec[Float64]]` construction):
// every column is Float64. Column values live in one flat arena; frames hold
// a flat list of column-slot indices. No FFI is used on any Phase-2 path, and
// the C-bridge seam above is untouched (the offline stub still serves the
// Phase-1 extern checks).
//
// Phase-2 surface (ROADMAP + SPEC API): shape, columns, dtypes, column,
// iloc, loc_range, head, tail. Rename/reorder, concat, and merge are NOT
// implemented because SPEC/ROADMAP do not pin their semantics.
// =========================================================================

// --- registry state ------------------------------------------------------

var _p2_col_name:  Vec[Str]     = Vec[Str].new();
var _p2_col_dtype: Vec[Int]     = Vec[Int].new();
var _p2_col_base:  Vec[Int]     = Vec[Int].new();
var _p2_col_len:   Vec[Int]     = Vec[Int].new();
var _p2_col_live:  Vec[Bool]    = Vec[Bool].new();
var _p2_col_data:  Vec[Float64] = Vec[Float64].new();

var _p2_df_cols_off: Vec[Int]  = Vec[Int].new();
var _p2_df_cols_n:   Vec[Int]  = Vec[Int].new();
var _p2_df_cols:     Vec[Int]  = Vec[Int].new();
var _p2_df_rows:     Vec[Int]  = Vec[Int].new();
var _p2_df_live:     Vec[Bool] = Vec[Bool].new();

var _p2_s_base:  Vec[Int]  = Vec[Int].new();
var _p2_s_len:   Vec[Int]  = Vec[Int].new();
var _p2_s_dtype: Vec[Int]  = Vec[Int].new();
var _p2_s_live:  Vec[Bool] = Vec[Bool].new();

// --- registry helpers ----------------------------------------------------

fn _p2_df_valid(h: Int) -> Bool {
  if h <= 0 { return false; }
  let i = h - 1;
  if i >= _p2_df_live.len() { return false; }
  return _p2_df_live[i];
}

fn _p2_s_valid(h: Int) -> Bool {
  if h <= 0 { return false; }
  let i = h - 1;
  if i >= _p2_s_live.len() { return false; }
  return _p2_s_live[i];
}

fn _p2_df_ncols(h: Int) -> Int {
  return _p2_df_cols_n[h - 1];
}

fn _p2_df_row_count(h: Int) -> Int {
  return _p2_df_rows[h - 1];
}

// Global column-slot index for frame column `ci`.
fn _p2_df_col(h: Int, ci: Int) -> Int {
  let off = _p2_df_cols_off[h - 1];
  return _p2_df_cols[off + ci];
}

// Global column-slot index for `name` in the frame, or -1.
fn _p2_df_find_col(h: Int, name: Str) -> Int {
  var ci = 0;
  while ci < _p2_df_ncols(h) {
    let c = _p2_df_col(h, ci);
    if _p2_col_name[c] == name { return c; }
    ci = ci + 1;
  };
  return -1;
}

// Append a column holding `count` values copied from `_p2_col_data`.
fn _p2_col_alloc_slice(name: Str, dtype: Dtype, srcbase: Int, start: Int, count: Int) -> Int {
  let base = _p2_col_data.len();
  var j = 0;
  while j < count {
    _p2_col_data.push(_p2_col_data[srcbase + start + j]);
    j = j + 1;
  };
  _p2_col_name.push(name);
  _p2_col_dtype.push(dtype);
  _p2_col_base.push(base);
  _p2_col_len.push(count);
  _p2_col_live.push(true);
  return _p2_col_live.len() - 1;
}

// Append a column holding a copy of `values`.
fn _p2_col_alloc_values(name: Str, dtype: Dtype, values: &Vec[Float64]) -> Int {
  let base = _p2_col_data.len();
  var j = 0;
  while j < values.len() {
    _p2_col_data.push(values[j]);
    j = j + 1;
  };
  _p2_col_name.push(name);
  _p2_col_dtype.push(dtype);
  _p2_col_base.push(base);
  _p2_col_len.push(values.len());
  _p2_col_live.push(true);
  return _p2_col_live.len() - 1;
}

// Append a frame slot over `slot_ids`; returns the 1-based handle.
fn _p2_frame_alloc(slot_ids: &Vec[Int], rows: Int) -> DataFrame {
  let off = _p2_df_cols.len();
  var i = 0;
  while i < slot_ids.len() {
    _p2_df_cols.push(slot_ids[i]);
    i = i + 1;
  };
  _p2_df_cols_off.push(off);
  _p2_df_cols_n.push(slot_ids.len());
  _p2_df_rows.push(rows);
  _p2_df_live.push(true);
  return _p2_df_live.len();
}

// Copy `take` rows starting at `start` into a fresh frame.
fn _p2_slice(h: Int, start: Int, take: Int) -> DataFrame {
  var slots = Vec[Int].new();
  var ci = 0;
  while ci < _p2_df_ncols(h) {
    let c = _p2_df_col(h, ci);
    let ns = _p2_col_alloc_slice(_p2_col_name[c], _p2_col_dtype[c], _p2_col_base[c], start, take);
    slots.push(ns);
    ci = ci + 1;
  };
  return _p2_frame_alloc(&slots, take);
}

// Append a Series view over `_p2_col_data[base .. base + len)`.
fn _p2_series_alloc_view(base: Int, len: Int, dtype: Dtype) -> Series {
  _p2_s_base.push(base);
  _p2_s_len.push(len);
  _p2_s_dtype.push(dtype);
  _p2_s_live.push(true);
  return _p2_s_live.len();
}

fn _p2_series_alloc_values(values: &Vec[Float64], dtype: Dtype) -> Series {
  let base = _p2_col_data.len();
  var j = 0;
  while j < values.len() {
    _p2_col_data.push(values[j]);
    j = j + 1;
  };
  return _p2_series_alloc_view(base, values.len(), dtype);
}

// --- construction --------------------------------------------------------

// Build a Float64 DataFrame from parallel name/value-column vectors.
// `names.len() == col_values.len()`, at least one column, every column the
// same row count, and names unique; violations return a typed Err.
pub fn dataframe_from_columns(names: &Vec[Str], col_values: &Vec[Vec[Float64]]) -> Result[DataFrame, Str] {
  if names.len() != col_values.len() {
    return Err("pandas: dataframe_from_columns name/column count mismatch");
  }
  if names.len() == 0 {
    return Err("pandas: dataframe_from_columns requires at least one column");
  }
  let rows = col_values[0].len();
  var i = 1;
  while i < col_values.len() {
    if col_values[i].len() != rows {
      return Err("pandas: dataframe_from_columns column length mismatch");
    }
    i = i + 1;
  };
  i = 0;
  while i < names.len() {
    var j = i + 1;
    while j < names.len() {
      if names[i] == names[j] {
        return Err("pandas: dataframe_from_columns duplicate column name");
      }
      j = j + 1;
    };
    i = i + 1;
  };
  var slots = Vec[Int].new();
  i = 0;
  while i < names.len() {
    let c = _p2_col_alloc_values(names[i], DTYPE_FLOAT64, &col_values[i]);
    slots.push(c);
    i = i + 1;
  };
  return Ok(_p2_frame_alloc(&slots, rows));
}

// --- properties ----------------------------------------------------------

// (row count, column count). Invalid/dead handles report (0, 0).
pub fn dataframe_shape(df: &DataFrame) -> (Int, Int)
  requires: df != 0
{
  let h: Int = *df;
  if !_p2_df_valid(h) { return (0, 0); }
  return (_p2_df_row_count(h), _p2_df_ncols(h));
}

// SPEC API name for dataframe_shape.
pub fn shape(df: &DataFrame) -> (Int, Int)
  requires: df != 0
{
  return dataframe_shape(df);
}

// Column names in storage order.
pub fn dataframe_columns(df: &DataFrame) -> Vec[Str]
  requires: df != 0
{
  var out = Vec[Str].new();
  let h: Int = *df;
  if !_p2_df_valid(h) { return out; }
  var ci = 0;
  while ci < _p2_df_ncols(h) {
    out.push(_p2_col_name[_p2_df_col(h, ci)]);
    ci = ci + 1;
  };
  return out;
}

// SPEC API name for dataframe_columns.
pub fn columns(df: &DataFrame) -> Vec[Str]
  requires: df != 0
{
  return dataframe_columns(df);
}

// Per-column dtype tags, in storage order.
pub fn dataframe_dtypes(df: &DataFrame) -> Vec[Dtype]
  requires: df != 0
{
  var out = Vec[Dtype].new();
  let h: Int = *df;
  if !_p2_df_valid(h) { return out; }
  var ci = 0;
  while ci < _p2_df_ncols(h) {
    out.push(_p2_col_dtype[_p2_df_col(h, ci)]);
    ci = ci + 1;
  };
  return out;
}

// SPEC API name for dataframe_dtypes.
pub fn dtypes(df: &DataFrame) -> Vec[Dtype]
  requires: df != 0
{
  return dataframe_dtypes(df);
}

// --- selection -----------------------------------------------------------

// Series view over one named column. Exact, case-sensitive name match.
pub fn column(df: &DataFrame, name: Str) -> Result[Series, Str]
  requires: df != 0
{
  let h: Int = *df;
  if !_p2_df_valid(h) {
    return Err("pandas: column invalid DataFrame handle");
  }
  let c = _p2_df_find_col(h, name);
  if c < 0 {
    return Err("pandas: column not found");
  }
  return Ok(_p2_series_alloc_view(_p2_col_base[c], _p2_col_len[c], _p2_col_dtype[c]));
}

// Series of one row's values, in column order (0-based; negative is Err).
pub fn dataframe_iloc(df: &DataFrame, row: Int) -> Result[Series, Str]
  requires: df != 0
{
  let h: Int = *df;
  if !_p2_df_valid(h) {
    return Err("pandas: dataframe_iloc invalid DataFrame handle");
  }
  let rows = _p2_df_row_count(h);
  if row < 0 || row >= rows {
    return Err("pandas: dataframe_iloc row out of bounds");
  }
  var vals = Vec[Float64].new();
  var ci = 0;
  while ci < _p2_df_ncols(h) {
    let c = _p2_df_col(h, ci);
    vals.push(_p2_col_data[_p2_col_base[c] + row]);
    ci = ci + 1;
  };
  return Ok(_p2_series_alloc_values(&vals, DTYPE_FLOAT64));
}

// SPEC API name for dataframe_iloc.
pub fn iloc(df: &DataFrame, row: Int) -> Result[Series, Str]
  requires: df != 0
{
  return dataframe_iloc(df, row);
}

// Inclusive row slice [start, end] (pandas .loc endpoint semantics).
// Bounds are strict: 0 <= start <= end < row count, else Err.
pub fn dataframe_loc_range(df: &DataFrame, start: Int, end: Int) -> Result[DataFrame, Str]
  requires: df != 0
{
  let h: Int = *df;
  if !_p2_df_valid(h) {
    return Err("pandas: dataframe_loc_range invalid DataFrame handle");
  }
  let rows = _p2_df_row_count(h);
  if start < 0 || end < start {
    return Err("pandas: dataframe_loc_range invalid range");
  }
  if end >= rows {
    return Err("pandas: dataframe_loc_range range past end of frame");
  }
  return Ok(_p2_slice(h, start, end - start + 1));
}

// SPEC API name for dataframe_loc_range.
pub fn loc_range(df: &DataFrame, start: Int, end: Int) -> Result[DataFrame, Str]
  requires: df != 0
{
  return dataframe_loc_range(df, start, end);
}

// First `n` rows; n > row count clamps, n == 0 yields a 0-row frame,
// n < 0 is Err.
pub fn dataframe_head(df: &DataFrame, n: Int) -> Result[DataFrame, Str]
  requires: df != 0
{
  let h: Int = *df;
  if !_p2_df_valid(h) {
    return Err("pandas: dataframe_head invalid DataFrame handle");
  }
  if n < 0 {
    return Err("pandas: dataframe_head negative row count");
  }
  let rows = _p2_df_row_count(h);
  var take = n;
  if take > rows { take = rows; }
  return Ok(_p2_slice(h, 0, take));
}

// Last `n` rows; clamps and 0-row behavior mirror dataframe_head.
pub fn dataframe_tail(df: &DataFrame, n: Int) -> Result[DataFrame, Str]
  requires: df != 0
{
  let h: Int = *df;
  if !_p2_df_valid(h) {
    return Err("pandas: dataframe_tail invalid DataFrame handle");
  }
  if n < 0 {
    return Err("pandas: dataframe_tail negative row count");
  }
  let rows = _p2_df_row_count(h);
  var take = n;
  if take > rows { take = rows; }
  let start = rows - take;
  return Ok(_p2_slice(h, start, take));
}

// --- Series inspection (pure-XIOM registry) ------------------------------

pub fn series_len(s: &Series) -> Int
  requires: s != 0
{
  let h: Int = *s;
  if !_p2_s_valid(h) { return 0; }
  return _p2_s_len[h - 1];
}

pub fn series_dtype(s: &Series) -> Dtype
  requires: s != 0
{
  let h: Int = *s;
  if !_p2_s_valid(h) { return -1; }
  return _p2_s_dtype[h - 1];
}

pub fn series_values(s: &Series) -> Result[Vec[Float64], Str]
  requires: s != 0
{
  let h: Int = *s;
  if !_p2_s_valid(h) {
    return Err("pandas: series_values invalid Series handle");
  }
  var out = Vec[Float64].new();
  let base = _p2_s_base[h - 1];
  let n = _p2_s_len[h - 1];
  var j = 0;
  while j < n {
    out.push(_p2_col_data[base + j]);
    j = j + 1;
  };
  return Ok(out);
}

// =========================================================================
// Phase 3 -- pinned aggregation / transformation (pure XIOM, no FFI)
//
// Implemented from the SPEC API sketch (group_by/groupby_sum/groupby_mean,
// sort, drop_columns) and the ROADMAP Phase-3 list (groupby_count). Only the
// parts whose semantics the docs pin are implemented:
//
// - group_by stores the source frame handle and the grouping column slot.
// - groupby_sum/mean/count return a fresh frame with exactly two columns:
//   [grouping column, aggregated column], one row per distinct Float64 key,
//   ordered by ascending key (pandas' default groupby sort=True).
//   Equality on group keys is exact Float64 equality; NA/NaN is not part of
//   the pinned Float64 model (SPEC), so no NA drop/fill policy is invented.
// - Aggregating the grouping column itself returns Err (the result would
//   otherwise carry two identically named columns).
// - sort returns a new frame whose rows are ordered by `by`; ties keep their
//   source order in this implementation, but tie/stability behavior is NOT
//   part of the pinned contract (documented in SPEC).
// - drop_columns removes the requested names, preserves the remaining
//   column order, and returns Err for a missing name or when every column
//   would be dropped (the constructor requires >= 1 column).
// - dataframe_fillna is deliberately NOT implemented: SPEC/ROADMAP pin no
//   NA/NaN representation or fill strategy in the Float64 model.
// =========================================================================

// --- GroupBy registry ----------------------------------------------------

var _p3_gb_df:   Vec[Int]  = Vec[Int].new();
var _p3_gb_key:  Vec[Int]  = Vec[Int].new();
var _p3_gb_live: Vec[Bool] = Vec[Bool].new();

fn _p3_gb_valid(h: Int) -> Bool {
  if h <= 0 { return false; }
  let i = h - 1;
  if i >= _p3_gb_live.len() { return false; }
  return _p3_gb_live[i];
}

fn _p3_gb_alloc(dfh: Int, keyslot: Int) -> GroupBy {
  _p3_gb_df.push(dfh);
  _p3_gb_key.push(keyslot);
  _p3_gb_live.push(true);
  return _p3_gb_live.len();
}

// --- transformation helpers ---------------------------------------------

fn _p3_name_in(cols: &Vec[Str], name: Str) -> Bool {
  var i = 0;
  while i < cols.len() {
    if cols[i] == name { return true; }
    i = i + 1;
  };
  return false;
}

// Append a column holding rows from `srcbase` in `order`.
fn _p2_col_alloc_order(name: Str, dtype: Dtype, srcbase: Int, order: &Vec[Int]) -> Int {
  let base = _p2_col_data.len();
  var j = 0;
  while j < order.len() {
    _p2_col_data.push(_p2_col_data[srcbase + order[j]]);
    j = j + 1;
  };
  _p2_col_name.push(name);
  _p2_col_dtype.push(dtype);
  _p2_col_base.push(base);
  _p2_col_len.push(order.len());
  _p2_col_live.push(true);
  return _p2_col_live.len() - 1;
}

// New frame with every column permuted by `order` (a stable copy).
fn _p3_materialize(h: Int, order: &Vec[Int]) -> DataFrame {
  var slots = Vec[Int].new();
  var ci = 0;
  while ci < _p2_df_ncols(h) {
    let c = _p2_df_col(h, ci);
    let ns = _p2_col_alloc_order(_p2_col_name[c], _p2_col_dtype[c], _p2_col_base[c], order);
    slots.push(ns);
    ci = ci + 1;
  };
  return _p2_frame_alloc(&slots, order.len());
}

// Stable insertion sort of row indices by column slot `c`.
fn _p3_sort_order(h: Int, c: Int, ascending: Bool) -> Vec[Int] {
  var order = Vec[Int].new();
  let base = _p2_col_base[c];
  let rows = _p2_df_row_count(h);
  var i = 0;
  while i < rows {
    order.push(i);
    i = i + 1;
  };
  var k = 1;
  while k < order.len() {
    let cur = order[k];
    let cv = _p2_col_data[base + cur];
    var j = k - 1;
    while j >= 0 {
      let jv = _p2_col_data[base + order[j]];
      var move = false;
      if ascending {
        if jv > cv { move = true; }
      } else {
        if jv < cv { move = true; }
      };
      if !move { break; }
      order[j + 1] = order[j];
      j = j - 1;
    };
    order[j + 1] = cur;
    k = k + 1;
  };
  return order;
}

// Stable ascending permutation of group indices by key.
fn _p3_group_order(keys: &Vec[Float64]) -> Vec[Int] {
  var order = Vec[Int].new();
  var i = 0;
  while i < keys.len() {
    order.push(i);
    i = i + 1;
  };
  var k = 1;
  while k < order.len() {
    let cur = order[k];
    let cv = keys[cur];
    var j = k - 1;
    while j >= 0 {
      if keys[order[j]] <= cv { break; }
      order[j + 1] = order[j];
      j = j - 1;
    };
    order[j + 1] = cur;
    k = k + 1;
  };
  return order;
}

// --- group_by / aggregation ---------------------------------------------

// Group handle over `by`; 0 when the frame or column is invalid.
pub fn group_by(df: &DataFrame, by: Str) -> GroupBy
  requires: df != 0
{
  let h: Int = *df;
  if !_p2_df_valid(h) { return 0; }
  let c = _p2_df_find_col(h, by);
  if c < 0 { return 0; }
  return _p3_gb_alloc(h, c);
}

// mode: 0 = sum, 1 = mean, 2 = count.
fn _p3_groupby_agg(gb: GroupBy, col: Str, mode: Int) -> Result[DataFrame, Str] {
  let g: Int = gb;
  if !_p3_gb_valid(g) {
    return Err("pandas: groupby invalid GroupBy handle");
  }
  let h = _p3_gb_df[g - 1];
  if !_p2_df_valid(h) {
    return Err("pandas: groupby invalid DataFrame handle");
  }
  let kc = _p3_gb_key[g - 1];
  let vc = _p2_df_find_col(h, col);
  if vc < 0 {
    return Err("pandas: groupby aggregated column not found");
  }
  if vc == kc {
    return Err("pandas: groupby cannot aggregate the grouping column");
  }
  var keys = Vec[Float64].new();
  var acc = Vec[Float64].new();
  var cnt = Vec[Int].new();
  let kbase = _p2_col_base[kc];
  let vbase = _p2_col_base[vc];
  let rows = _p2_df_row_count(h);
  var r = 0;
  while r < rows {
    let kv = _p2_col_data[kbase + r];
    let vv = _p2_col_data[vbase + r];
    var gi = -1;
    var j = 0;
    while j < keys.len() {
      if keys[j] == kv {
        gi = j;
        break;
      }
      j = j + 1;
    };
    if gi < 0 {
      keys.push(kv);
      if mode == 2 { acc.push(1.0); } else { acc.push(vv); }
      cnt.push(1);
    } else {
      if mode == 2 { acc[gi] = acc[gi] + 1.0; } else { acc[gi] = acc[gi] + vv; }
      cnt[gi] = cnt[gi] + 1;
    }
    r = r + 1;
  };
  let gorder = _p3_group_order(&keys);
  var names = Vec[Str].new();
  names.push(_p2_col_name[kc]);
  names.push(col);
  var key_vals = Vec[Float64].new();
  var agg_vals = Vec[Float64].new();
  var q = 0;
  while q < gorder.len() {
    let g = gorder[q];
    key_vals.push(keys[g]);
    if mode == 1 {
      agg_vals.push(acc[g] / (cnt[g] as Float64));
    } else {
      agg_vals.push(acc[g]);
    }
    q = q + 1;
  };
  var outcols = Vec[Vec[Float64]].new();
  outcols.push(key_vals);
  outcols.push(agg_vals);
  return dataframe_from_columns(&names, &outcols);
}

// Per-group sum of `col`, keyed by group_by's column (ascending keys).
pub fn groupby_sum(gb: GroupBy, col: Str) -> Result[DataFrame, Str]
  requires: gb != 0
{
  return _p3_groupby_agg(gb, col, 0);
}

// Per-group arithmetic mean of `col` (ascending keys).
pub fn groupby_mean(gb: GroupBy, col: Str) -> Result[DataFrame, Str]
  requires: gb != 0
{
  return _p3_groupby_agg(gb, col, 1);
}

// Per-group row count for `col` (no NA model: every value counts).
pub fn groupby_count(gb: GroupBy, col: Str) -> Result[DataFrame, Str]
  requires: gb != 0
{
  return _p3_groupby_agg(gb, col, 2);
}

// --- sort ----------------------------------------------------------------

// New frame with rows ordered by column `by`.
// Tie order is implementation-defined (documented, not pinned).
pub fn dataframe_sort(df: &DataFrame, by: Str, ascending: Bool) -> Result[DataFrame, Str]
  requires: df != 0
{
  let h: Int = *df;
  if !_p2_df_valid(h) {
    return Err("pandas: dataframe_sort invalid DataFrame handle");
  }
  let c = _p2_df_find_col(h, by);
  if c < 0 {
    return Err("pandas: dataframe_sort column not found");
  }
  let order = _p3_sort_order(h, c, ascending);
  return Ok(_p3_materialize(h, &order));
}

// SPEC API name for dataframe_sort.
pub fn sort(df: &DataFrame, by: Str, ascending: Bool) -> Result[DataFrame, Str]
  requires: df != 0
{
  return dataframe_sort(df, by, ascending);
}

// --- drop_columns --------------------------------------------------------

// New frame without the named columns, preserving the remaining order.
// Every requested name must exist; dropping all columns is Err.
pub fn dataframe_drop_columns(df: &DataFrame, cols: &Vec[Str]) -> Result[DataFrame, Str]
  requires: df != 0
{
  let h: Int = *df;
  if !_p2_df_valid(h) {
    return Err("pandas: dataframe_drop_columns invalid DataFrame handle");
  }
  var i = 0;
  while i < cols.len() {
    if _p2_df_find_col(h, cols[i]) < 0 {
      return Err("pandas: dataframe_drop_columns column not found");
    }
    i = i + 1;
  };
  var slots = Vec[Int].new();
  var ci = 0;
  var keep = 0;
  while ci < _p2_df_ncols(h) {
    let c = _p2_df_col(h, ci);
    if !_p3_name_in(cols, _p2_col_name[c]) {
      let ns = _p2_col_alloc_slice(_p2_col_name[c], _p2_col_dtype[c], _p2_col_base[c], 0, _p2_col_len[c]);
      slots.push(ns);
      keep = keep + 1;
    }
    ci = ci + 1;
  };
  if keep == 0 {
    return Err("pandas: dataframe_drop_columns cannot drop all columns");
  }
  return Ok(_p2_frame_alloc(&slots, _p2_df_row_count(h)));
}

// SPEC API name for dataframe_drop_columns.
pub fn drop_columns(df: &DataFrame, cols: &Vec[Str]) -> Result[DataFrame, Str]
  requires: df != 0
{
  return dataframe_drop_columns(df, cols);
}

// =========================================================================
// Utility: dtype_name -- human-readable name for a Dtype constant
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
