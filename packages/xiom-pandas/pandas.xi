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
