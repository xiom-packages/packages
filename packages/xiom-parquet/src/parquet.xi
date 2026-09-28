// XIOM -- xiom.parquet: Apache Parquet file metadata codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM (no FFI, no dependencies beyond xiom.std) parser for the
// STRUCTURE of an Apache Parquet file. Only the container skeleton and the
// metadata are parsed; page data is never decoded:
//
//   [4]   magic "PAR1"
//   [..]  row-group data (column chunks with page headers and page data)
//   [..]  FileMetaData (Thrift *compact* protocol struct)
//   [4]   footer length: u32 little-endian byte count of FileMetaData
//   [4]   magic "PAR1"
//
// With `meta = len - 8 - footer_len` the footer is a compact-protocol
// struct; this module implements the compact protocol subset Parquet needs:
// varints, zigzag, bool (field value in the header nibble, element value as
// 1/2), byte, i16/i32/i64, double (8-byte little-endian IEEE-754 bit
// pattern carried in an Int), binary/string (varint length + bytes),
// list/set (one-byte short header or long header + varint size), map
// (varint size + key/value type nibbles), struct (delta-encoded field
// headers, long form zigzag field id, STOP 0), bounded nesting (64
// container levels).
//
// Decoded metadata:
//   * FileMetaData: version, schema (flattened depth-first SchemaElement
//     list with computed parent/depth/path/max-definition-level/
//     max-repetition-level/leaf-index), num_rows, row groups, file-level
//     key_value_metadata, created_by, column_orders (raw union member id);
//   * RowGroup: columns, total_byte_size, num_rows, sorting_columns,
//     file_offset, total_compressed_size, ordinal;
//   * ColumnChunk: file_path, file_offset, meta_data, offset/column index
//     offsets and lengths; ColumnMetaData: type, encodings, path_in_schema,
//     codec, num_values, total_uncompressed_size, total_compressed_size,
//     key_value_metadata, data/index/dictionary page offsets, statistics
//     (raw min/max/min_value/max_value bytes plus null_count,
//     distinct_count and the *_exact flags), encoding_stats;
//   * PageHeader (parsed separately at an absolute offset, returning the
//     consumed byte count): page type, uncompressed/compressed sizes, crc,
//     DataPageHeader, IndexPageHeader, DictionaryPageHeader,
//     DataPageHeaderV2; page-level Statistics are preserved as raw byte
//     ranges (offset/end) rather than decoded.
//
// Unknown enum values are preserved raw (0 = absent markers, *_name
// helpers return "unknown" beyond the documented range). Unknown struct
// fields of any supported type are skipped, so newer Parquet writers stay
// readable.
//
// Everything that would need a page decoder is out of scope: PLAIN,
// RLE/bit-packing, dictionary (PLAIN_DICTIONARY/RLE_DICTIONARY), delta and
// byte-stream-split encodings, compression codecs, encryption, bloom
// filters, page indexes (the offset/length fields are exposed but their
// payloads are not read) and external column data. See SPEC.md.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods, no lambdas, no Vec[fn]
//     dispatch, no Vec[StructType] fields (parallel vectors instead);
//   * Ok/Err construction is confined to the tiny leaf helpers below;
//   * every UInt8 is widened once with `(b as Int) & 0xFF` before entering
//     Int arithmetic or comparisons;
//   * every Vec element read is bound to an explicitly typed local first;
//   * struct fields are never passed as `&struct.field` where a
//     `&Vec[UInt8]` parameter is expected (that yields an empty vector);
//     payloads are bound to typed locals first;
//   * Str output is collected in a `Vec[UInt8]` and materialized with
//     `xiom.string.builder.sb_to_str` only after the bytes were validated
//     as NUL-free UTF-8 (sb_to_str aborts on a 0x00 byte);
//   * zigzag decoding is pure divisor/modulo arithmetic and little-endian
//     u32 composition uses explicit byte multiplication;
//   * `&mut Int` out-params are miscompiled, so every helper returns its
//     results; the reader cursor is the only mutated state.

module xiom.parquet

use xiom.string.builder;
use xiom.convert;
use xiom.string.compare;

// --------------------------------------------------
//  Result leaf constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[ParquetField, Str].
fn _ok_field(v: ParquetField) -> Result[ParquetField, Str] {
  return Ok(v);
}

// Err(m) for Result[ParquetField, Str].
fn _err_field(m: Str) -> Result[ParquetField, Str] {
  return Err(m);
}

// Ok(v) for Result[ParquetListHeader, Str].
fn _ok_lhdr(v: ParquetListHeader) -> Result[ParquetListHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[ParquetListHeader, Str].
fn _err_lhdr(m: Str) -> Result[ParquetListHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[ParquetMapHeader, Str].
fn _ok_mhdr(v: ParquetMapHeader) -> Result[ParquetMapHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[ParquetMapHeader, Str].
fn _err_mhdr(m: Str) -> Result[ParquetMapHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[ParquetFile, Str].
fn _ok_file(v: ParquetFile) -> Result[ParquetFile, Str] {
  return Ok(v);
}

// Err(m) for Result[ParquetFile, Str].
fn _err_file(m: Str) -> Result[ParquetFile, Str] {
  return Err(m);
}

// Ok(v) for Result[_Meta, Str].
fn _ok_meta(v: _Meta) -> Result[_Meta, Str] {
  return Ok(v);
}

// Err(m) for Result[_Meta, Str].
fn _err_meta(m: Str) -> Result[_Meta, Str] {
  return Err(m);
}

// Ok(v) for Result[ParquetPageHeader, Str].
fn _ok_ph(v: ParquetPageHeader) -> Result[ParquetPageHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[ParquetPageHeader, Str].
fn _err_ph(m: Str) -> Result[ParquetPageHeader, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// A bounds-checked cursor over immutable bytes. `pos` and `end` are
/// absolute buffer offsets; every reader refuses to cross `end`. Create
/// with `parquet_reader_new` (whole buffer) or `parquet_reader_new_at`
/// (window).
pub type ParquetReader = {
  data: Vec[UInt8];
  pos: Int;
  end: Int;
}

/// A decoded compact-protocol field header. `ftype` is a compact type code
/// (`parquet_compact_stop()` for the struct terminator); `fid` is the field
/// id. For BOOLEAN_TRUE/BOOLEAN_FALSE the value is carried in the type
/// nibble (see `parquet_field_bool`) and no bytes follow.
pub type ParquetField = {
  ftype: Int;
  fid: Int;
}

/// A decoded compact-protocol list or set header: element type code plus
/// element count.
pub type ParquetListHeader = {
  etype: Int;
  size: Int;
}

/// A decoded compact-protocol map header: key type code, value type code
/// and pair count. An empty map has all three fields 0.
pub type ParquetMapHeader = {
  ktype: Int;
  vtype: Int;
  size: Int;
}

/// A decoded Parquet PageHeader. `consumed` is the number of bytes the
/// header occupied from the offset passed to `parquet_parse_page_header`.
/// The `*_present` fields are 1 when the optional member was on the wire.
/// Page-level statistics are not decoded: `dp_stats_offset`/`dp_stats_end`
/// and `v2_stats_offset`/`v2_stats_end` delimit the raw Statistics struct
/// inside the parsed buffer (end = offset just past its STOP byte).
pub type ParquetPageHeader = {
  ptype: Int;
  ptype_present: Int;
  uncompressed_page_size: Int;
  ups_present: Int;
  compressed_page_size: Int;
  cps_present: Int;
  crc: Int;
  crc_present: Int;
  consumed: Int;
  dp_present: Int;
  dp_num_values: Int;
  dp_encoding: Int;
  dp_def_encoding: Int;
  dp_rep_encoding: Int;
  dp_stats_present: Int;
  dp_stats_offset: Int;
  dp_stats_end: Int;
  ix_present: Int;
  dict_present: Int;
  dict_num_values: Int;
  dict_encoding: Int;
  dict_is_sorted_present: Int;
  dict_is_sorted: Int;
  v2_present: Int;
  v2_num_values: Int;
  v2_num_nulls: Int;
  v2_num_rows: Int;
  v2_encoding: Int;
  v2_def_len: Int;
  v2_rep_len: Int;
  v2_is_compressed_present: Int;
  v2_is_compressed: Int;
  v2_stats_present: Int;
  v2_stats_offset: Int;
  v2_stats_end: Int;
}

// Per-ColumnMetaData decode result, consumed by _parse_column_chunk which
// mirrors every entry into the flat ParquetFile vectors.
type _Meta = {
  type_raw: Int;
  type_present: Int;
  codec: Int;
  codec_present: Int;
  num_values: Int;
  nv_present: Int;
  total_us: Int;
  tus_present: Int;
  total_cs: Int;
  tcs_present: Int;
  dpo: Int;
  dpo_present: Int;
  ipo: Int;
  ipo_present: Int;
  dict_po: Int;
  dict_present: Int;
  enc_off: Int;
  enc_count: Int;
  path_off: Int;
  path_count: Int;
  kv_off: Int;
  kv_count: Int;
  es_off: Int;
  es_count: Int;
  stats_pushed: Int;
}

/// Parsed Parquet file metadata. All schema/row-group/column-chunk data
/// lives in parallel flat vectors (never `Vec[StructType]`); each
/// `*_off`/`*_count` pair locates a run inside a shared pool vector.
///
/// Schema (depth-first, element 0 is the root):
///   * `s_name[i]`, `s_type[i]`/`s_type_present[i]`,
///     `s_type_length[i]`/`_present`, `s_repetition[i]`/`_present`,
///     `s_num_children[i]`/`_present`, `s_converted[i]`/`_present`,
///     `s_scale[i]`/`_present`, `s_precision[i]`/`_present`,
///     `s_field_id[i]`/`_present`, `s_logical[i]`/`_present` (the
///     LogicalType union member id) are the raw SchemaElement fields;
///   * `s_parent[i]`, `s_depth[i]`, `s_path[i]` (dotted path, empty for the
///     root), `s_max_def[i]`/`s_max_rep[i]` (computed maximum definition
///     and repetition levels) and `s_leaf_index[i]` (-1 for groups) are
///     computed by `parquet_parse`.
///
/// Row groups: `rg_cc_off`/`rg_cc_count` locate the group's column chunks
/// in the flattened chunk arrays; plus total_byte_size, num_rows,
/// file_offset, total_compressed_size and ordinal (values 0 plus
/// `*_present` flags when absent). `rg_sort_off`/`rg_sort_count` locate the
/// group's entries in `sort_column_idx`/`sort_descending`/
/// `sort_nulls_first`.
///
/// Column chunks (same order as the schema leaves):
///   * raw fields with parallel presence flags, the `cc_oi_*`/`cc_ci_*`
///     offset-index and column-index location pairs;
///   * `cc_enc_off`/`cc_enc_count` index `enc_pool` (raw Encoding codes);
///   * `cc_path_off`/`cc_path_count` index `path_pool` (path_in_schema
///     string parts);
///   * `cc_kv_off`/`cc_kv_count` index the shared `kv_key`/`kv_value`/
///     `kv_value_present` pools;
///   * `cc_es_off`/`cc_es_count` index `es_page_type`/`es_encoding`/
///     `es_count` (PageEncodingStats entries);
///   * one statistics block per chunk: `st_present` plus `st_max_*`,
///     `st_min_*`, `st_maxv_*`, `st_minv_*` (raw bytes in `st_pool`),
///     `st_null_count`/`st_distinct_count` and
///     `st_max_exact`/`st_min_exact` with presence flags.
///
/// File level: `file_kv_off`/`file_kv_count` locate key_value_metadata in
/// the shared KV pools; `created_by`/`created_by_present`; `co_type`/
/// `co_type_present` hold each ColumnOrder union member id.
///
/// Fields are implementation details; use the parquet_* accessors. A value
/// is only produced by parquet_parse, so the invariants always hold.
pub type ParquetFile = {
  file_length: Int;
  footer_len: Int;
  metadata_start: Int;
  version: Int;
  num_rows: Int;
  created_by: Str;
  created_by_present: Int;
  s_name: Vec[Str];
  s_type: Vec[Int];
  s_type_present: Vec[Int];
  s_type_length: Vec[Int];
  s_type_length_present: Vec[Int];
  s_repetition: Vec[Int];
  s_repetition_present: Vec[Int];
  s_num_children: Vec[Int];
  s_num_children_present: Vec[Int];
  s_converted: Vec[Int];
  s_converted_present: Vec[Int];
  s_scale: Vec[Int];
  s_scale_present: Vec[Int];
  s_precision: Vec[Int];
  s_precision_present: Vec[Int];
  s_field_id: Vec[Int];
  s_field_id_present: Vec[Int];
  s_logical: Vec[Int];
  s_logical_present: Vec[Int];
  s_parent: Vec[Int];
  s_depth: Vec[Int];
  s_max_def: Vec[Int];
  s_max_rep: Vec[Int];
  s_leaf_index: Vec[Int];
  s_path: Vec[Str];
  rg_cc_off: Vec[Int];
  rg_cc_count: Vec[Int];
  rg_total_byte_size: Vec[Int];
  rg_num_rows: Vec[Int];
  rg_file_offset: Vec[Int];
  rg_file_offset_present: Vec[Int];
  rg_total_compressed_size: Vec[Int];
  rg_total_compressed_size_present: Vec[Int];
  rg_ordinal: Vec[Int];
  rg_ordinal_present: Vec[Int];
  rg_sort_off: Vec[Int];
  rg_sort_count: Vec[Int];
  sort_column_idx: Vec[Int];
  sort_descending: Vec[Int];
  sort_nulls_first: Vec[Int];
  cc_file_path: Vec[Str];
  cc_file_path_present: Vec[Int];
  cc_file_offset: Vec[Int];
  cc_meta_present: Vec[Int];
  cc_type: Vec[Int];
  cc_type_present: Vec[Int];
  cc_codec: Vec[Int];
  cc_codec_present: Vec[Int];
  cc_num_values: Vec[Int];
  cc_num_values_present: Vec[Int];
  cc_total_uncompressed_size: Vec[Int];
  cc_total_us_present: Vec[Int];
  cc_total_compressed_size: Vec[Int];
  cc_total_cs_present: Vec[Int];
  cc_data_page_offset: Vec[Int];
  cc_dpo_present: Vec[Int];
  cc_index_page_offset: Vec[Int];
  cc_ipo_present: Vec[Int];
  cc_dictionary_page_offset: Vec[Int];
  cc_dict_po_present: Vec[Int];
  cc_oi_off: Vec[Int];
  cc_oi_off_present: Vec[Int];
  cc_oi_len: Vec[Int];
  cc_oi_len_present: Vec[Int];
  cc_ci_off: Vec[Int];
  cc_ci_off_present: Vec[Int];
  cc_ci_len: Vec[Int];
  cc_ci_len_present: Vec[Int];
  cc_enc_off: Vec[Int];
  cc_enc_count: Vec[Int];
  enc_pool: Vec[Int];
  cc_path_off: Vec[Int];
  cc_path_count: Vec[Int];
  path_pool: Vec[Str];
  cc_kv_off: Vec[Int];
  cc_kv_count: Vec[Int];
  cc_es_off: Vec[Int];
  cc_es_count: Vec[Int];
  es_page_type: Vec[Int];
  es_encoding: Vec[Int];
  es_count: Vec[Int];
  file_kv_off: Int;
  file_kv_count: Int;
  kv_key: Vec[Str];
  kv_value: Vec[Str];
  kv_value_present: Vec[Int];
  co_type: Vec[Int];
  co_type_present: Vec[Int];
  st_present: Vec[Int];
  st_max_off: Vec[Int];
  st_max_len: Vec[Int];
  st_max_present: Vec[Int];
  st_min_off: Vec[Int];
  st_min_len: Vec[Int];
  st_min_present: Vec[Int];
  st_maxv_off: Vec[Int];
  st_maxv_len: Vec[Int];
  st_maxv_present: Vec[Int];
  st_minv_off: Vec[Int];
  st_minv_len: Vec[Int];
  st_minv_present: Vec[Int];
  st_null_count: Vec[Int];
  st_null_present: Vec[Int];
  st_distinct_count: Vec[Int];
  st_distinct_present: Vec[Int];
  st_max_exact: Vec[Int];
  st_max_exact_present: Vec[Int];
  st_min_exact: Vec[Int];
  st_min_exact_present: Vec[Int];
  st_pool: Vec[UInt8];
}

// --------------------------------------------------
//  Constants
// --------------------------------------------------

const _C_STOP: Int = 0;     // struct terminator
const _C_TRUE: Int = 1;     // BOOLEAN_TRUE (field value lives in the nibble)
const _C_FALSE: Int = 2;    // BOOLEAN_FALSE (field value lives in the nibble)
const _C_BYTE: Int = 3;
const _C_I16: Int = 4;
const _C_I32: Int = 5;
const _C_I64: Int = 6;
const _C_DOUBLE: Int = 7;
const _C_BINARY: Int = 8;
const _C_LIST: Int = 9;
const _C_SET: Int = 10;
const _C_MAP: Int = 11;
const _C_STRUCT: Int = 12;

const _MAX_DEPTH: Int = 64; // compact-protocol container nesting cap

const _MAGIC_P: Int = 80;   // 'P'
const _MAGIC_A: Int = 65;   // 'A'
const _MAGIC_R: Int = 82;   // 'R'
const _MAGIC_1: Int = 49;   // '1'

// --------------------------------------------------
//  Small helpers
// --------------------------------------------------

// 2^k for 0 <= k <= 32.
fn _pow2(k: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// Sign-extend the unsigned value `v` (0 <= v < 2^bits) to a signed Int.
fn _sign_extend(v: Int, bits: Int) -> Int {
  let half = _pow2(bits - 1);
  if v >= half {
    let full = _pow2(bits);
    return v - full;
  }
  return v;
}

// " at offset N" suffix shared by the parse error catalog.
fn _at(pos: Int) -> Str {
  return " at offset " + convert.int_to_string(pos);
}

// `prefix` followed by the shared offset suffix.
fn _moff(prefix: Str, pos: Int) -> Str {
  return prefix + _at(pos);
}

// The documented unknown-type error.
fn _type_msg(ctype: Int, pos: Int) -> Str {
  return "parquet: unknown compact type " + convert.int_to_string(ctype) + _at(pos);
}

// The documented nesting-depth error.
fn _depth_msg(pos: Int) -> Str {
  return "parquet: nesting depth exceeds limit of 64" + _at(pos);
}

// Byte `pos` of `buf` widened to 0..255. Callers bound-check first.
fn _byte(buf: &Vec[UInt8], pos: Int) -> Int {
  let raw: UInt8 = buf[pos];
  return (raw as Int) & 0xFF;
}

// Byte at absolute position `pos` of the reader, widened to 0..255.
// Callers guarantee pos is inside [pos, end).
fn _r_byte(r: &ParquetReader, pos: Int) -> Int {
  let raw: UInt8 = r.data[pos];
  return (raw as Int) & 0xFF;
}

// Same as _r_byte but takes &mut, so reader bodies never mix a `&` call
// before a `&mut` access on the same local (advisory E001).
fn _r_byte_mut(r: &mut ParquetReader, pos: Int) -> Int {
  return _r_byte(r, pos);
}

// A fresh copy of `src` (used where a returned vector must not alias).
fn _copy_bytes(src: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < src.len() {
    let b: UInt8 = src[i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

// Append every byte of `src` to `dst`.
fn _append_bytes(dst: &mut Vec[UInt8], src: &Vec[UInt8]) {
  var i = 0;
  while i < src.len() {
    let b: UInt8 = src[i];
    dst.push(b);
    i = i + 1;
  }
}

// The bytes of `v` as a Str. Only called on NUL-free byte vectors that
// were validated at the API boundary, so sb_to_str cannot abort.
fn _bytes_to_str(v: &Vec[UInt8]) -> Str {
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    let b: UInt8 = v[i];
    sb.push(b);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Strict UTF-8 validation of a string payload (RFC 3629: overlong forms
// and surrogate halves rejected, NUL rejected). Returns "" when valid,
// otherwise the deterministic message with the absolute offset of the
// offending byte (`base` is the payload start).
fn _utf8_error(bytes: &Vec[UInt8], base: Int) -> Str {
  let n = bytes.len();
  var i = 0;
  while i < n {
    let b: Int = (bytes[i] as Int) & 0xFF;
    if b == 0 {
      return "parquet: string contains nul" + _at(base + i);
    }
    if b < 128 {
      i = i + 1;
    } else if b < 194 {
      return "parquet: invalid utf-8" + _at(base + i);
    } else if b < 224 {
      if i + 1 >= n {
        return "parquet: invalid utf-8" + _at(base + i);
      }
      let c1: Int = (bytes[i + 1] as Int) & 0xFF;
      if c1 < 128 || c1 >= 192 {
        return "parquet: invalid utf-8" + _at(base + i + 1);
      }
      i = i + 2;
    } else if b < 240 {
      if i + 2 >= n {
        return "parquet: invalid utf-8" + _at(base + i);
      }
      let c1: Int = (bytes[i + 1] as Int) & 0xFF;
      let c2: Int = (bytes[i + 2] as Int) & 0xFF;
      if c1 < 128 || c1 >= 192 {
        return "parquet: invalid utf-8" + _at(base + i + 1);
      }
      if c2 < 128 || c2 >= 192 {
        return "parquet: invalid utf-8" + _at(base + i + 2);
      }
      if b == 224 && c1 < 160 {
        return "parquet: invalid utf-8" + _at(base + i + 1);
      }
      if b == 237 && c1 >= 160 {
        return "parquet: invalid utf-8" + _at(base + i + 1);
      }
      i = i + 3;
    } else {
      if b >= 245 {
        return "parquet: invalid utf-8" + _at(base + i);
      }
      if i + 3 >= n {
        return "parquet: invalid utf-8" + _at(base + i);
      }
      let c1: Int = (bytes[i + 1] as Int) & 0xFF;
      let c2: Int = (bytes[i + 2] as Int) & 0xFF;
      let c3: Int = (bytes[i + 3] as Int) & 0xFF;
      if c1 < 128 || c1 >= 192 {
        return "parquet: invalid utf-8" + _at(base + i + 1);
      }
      if c2 < 128 || c2 >= 192 {
        return "parquet: invalid utf-8" + _at(base + i + 2);
      }
      if c3 < 128 || c3 >= 192 {
        return "parquet: invalid utf-8" + _at(base + i + 3);
      }
      if b == 240 && c1 < 144 {
        return "parquet: invalid utf-8" + _at(base + i + 1);
      }
      if b == 244 && c1 >= 144 {
        return "parquet: invalid utf-8" + _at(base + i + 1);
      }
      i = i + 4;
    }
  }
  return "";
}

// --------------------------------------------------
//  Codec metadata
// --------------------------------------------------

/// Compact type id of the struct terminator (STOP 0). Complexity: O(1).
pub fn parquet_compact_stop() -> Int {
  return 0;
}

/// Compact type id of BOOLEAN_TRUE (1). Complexity: O(1).
pub fn parquet_compact_bool_true() -> Int {
  return 1;
}

/// Compact type id of BOOLEAN_FALSE (2). Complexity: O(1).
pub fn parquet_compact_bool_false() -> Int {
  return 2;
}

/// Compact type id of BYTE / I8 (3). Complexity: O(1).
pub fn parquet_compact_byte() -> Int {
  return 3;
}

/// Compact type id of I16 (4). Complexity: O(1).
pub fn parquet_compact_i16() -> Int {
  return 4;
}

/// Compact type id of I32 (5). Complexity: O(1).
pub fn parquet_compact_i32() -> Int {
  return 5;
}

/// Compact type id of I64 (6). Complexity: O(1).
pub fn parquet_compact_i64() -> Int {
  return 6;
}

/// Compact type id of DOUBLE (7). Complexity: O(1).
pub fn parquet_compact_double() -> Int {
  return 7;
}

/// Compact type id of BINARY/STRING (8). Complexity: O(1).
pub fn parquet_compact_binary() -> Int {
  return 8;
}

/// Compact type id of LIST (9). Complexity: O(1).
pub fn parquet_compact_list() -> Int {
  return 9;
}

/// Compact type id of SET (10). Complexity: O(1).
pub fn parquet_compact_set() -> Int {
  return 10;
}

/// Compact type id of MAP (11). Complexity: O(1).
pub fn parquet_compact_map() -> Int {
  return 11;
}

/// Compact type id of STRUCT (12). Complexity: O(1).
pub fn parquet_compact_struct() -> Int {
  return 12;
}

/// Maximum container nesting depth accepted by the reader (64): a container
/// at depth 63 is the deepest accepted one. Complexity: O(1).
pub fn parquet_max_depth() -> Int {
  return 64;
}

/// True when `t` is a compact type this codec understands: BOOLEAN_TRUE 1,
/// BOOLEAN_FALSE 2, BYTE 3, I16 4, I32 5, I64 6, DOUBLE 7, BINARY 8,
/// LIST 9, SET 10, MAP 11, STRUCT 12. STOP 0 and UUID 13+ are not value
/// types here (STOP is handled separately as a struct terminator).
/// Complexity: O(1).
pub fn parquet_compact_type_known(t: Int) -> Bool {
  return _type_known(t);
}

/// Documented name of a compact type code ("unknown" beyond STRUCT).
/// Complexity: O(1).
pub fn parquet_compact_type_name(t: Int) -> Str {
  if t == 0 {
    return "STOP";
  }
  if t == 1 {
    return "BOOLEAN_TRUE";
  }
  if t == 2 {
    return "BOOLEAN_FALSE";
  }
  if t == 3 {
    return "BYTE";
  }
  if t == 4 {
    return "I16";
  }
  if t == 5 {
    return "I32";
  }
  if t == 6 {
    return "I64";
  }
  if t == 7 {
    return "DOUBLE";
  }
  if t == 8 {
    return "BINARY";
  }
  if t == 9 {
    return "LIST";
  }
  if t == 10 {
    return "SET";
  }
  if t == 11 {
    return "MAP";
  }
  if t == 12 {
    return "STRUCT";
  }
  return "unknown";
}

// True for the value type ids the codec understands (see
// `parquet_compact_type_known`); STOP 0 and UUID 13 are not included.
fn _type_known(t: Int) -> Bool {
  if t == _C_TRUE || t == _C_FALSE || t == _C_BYTE {
    return true;
  }
  if t == _C_I16 || t == _C_I32 || t == _C_I64 {
    return true;
  }
  if t == _C_DOUBLE || t == _C_BINARY {
    return true;
  }
  if t == _C_LIST || t == _C_SET || t == _C_MAP || t == _C_STRUCT {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  Reader lifecycle
// --------------------------------------------------

/// A reader over the whole buffer, positioned at offset 0.
/// Complexity: O(1).
pub fn parquet_reader_new(data: Vec[UInt8]) -> ParquetReader {
  let n = data.len();
  return ParquetReader{ data: data; pos: 0; end: n; };
}

/// A reader over the window [start, end) of `data`. The window is not
/// validated here; every read that would cross `end` fails with a
/// truncation error. Complexity: O(1).
pub fn parquet_reader_new_at(data: Vec[UInt8], start: Int, end: Int) -> ParquetReader {
  return ParquetReader{ data: data; pos: start; end: end; };
}

/// Current cursor offset. Complexity: O(1).
pub fn parquet_reader_pos(r: &ParquetReader) -> Int {
  return r.pos;
}

/// Bytes left before the window end (0 when the cursor is at or past it).
/// Complexity: O(1).
pub fn parquet_reader_remaining(r: &ParquetReader) -> Int {
  let rem: Int = r.end - r.pos;
  if rem < 0 {
    return 0;
  }
  return rem;
}

// --------------------------------------------------
//  Compact protocol primitives
// --------------------------------------------------

// Read one base-128 varint (ULEB128, at most 10 bytes) and return the
// 64-bit pattern reinterpreted as a signed Int: values with bit 63 set
// come back as the corresponding negative Int. Non-minimal encodings are
// accepted; an 11th byte is "parquet: varint too long" and a 10th byte
// whose payload exceeds one bit is "parquet: varint overflow" (both at the
// varint start). A window ending inside the varint is "parquet: truncated
// varint".
fn _read_varint(r: &mut ParquetReader) -> Result[Int, Str] {
  let start = r.pos;
  var v: Int = 0;
  var place: Int = 1;
  var i = 0;
  var done = false;
  while !done {
    if r.pos >= r.end {
      return _err_int(_moff("parquet: truncated varint", start));
    }
    let b = _r_byte_mut(r, r.pos);
    r.pos = r.pos + 1;
    let payload = b % 128;
    if i < 9 {
      // Byte i contributes payload * 128^i; for i <= 8 the running sum
      // cannot exceed 2^63 - 1.
      v = v + payload * place;
      if i < 8 {
        place = place * 128;
      }
    } else {
      // 10th byte: a continuation bit means an 11th byte would follow; a
      // payload above 1 has bits above bit 63.
      if b >= 128 {
        return _err_int(_moff("parquet: varint too long", start));
      }
      if payload > 1 {
        return _err_int(_moff("parquet: varint overflow", start));
      }
      if payload == 1 {
        v = v - 9223372036854775807 - 1;
      }
    }
    i = i + 1;
    if b < 128 {
      done = true;
    } else {
      if i >= 10 {
        return _err_int(_moff("parquet: varint too long", start));
      }
    }
  }
  return _ok_int(v);
}

/// Read one unsigned LEB128 varint (at most 10 bytes) and return the
/// 64-bit pattern reinterpreted as a signed Int (so unsigned values with
/// bit 63 set come back negative). Errors as documented in SPEC.md.
/// Complexity: O(1).
pub fn parquet_read_varint(r: &mut ParquetReader) -> Result[Int, Str] {
  return _read_varint(r);
}

/// Read one zigzag-encoded signed integer varint: `u` maps to `u / 2` when
/// even and `-(u / 2) - 1` when odd, over the full signed 64-bit range.
/// Errors as `parquet_read_varint`. Complexity: O(1).
pub fn parquet_read_zigzag(r: &mut ParquetReader) -> Result[Int, Str] {
  let vr = _read_varint(r);
  if !vr.is_ok {
    return _err_int(vr.error);
  }
  let p: Int = vr.value;
  if p >= 0 {
    let q = p / 2;
    if p % 2 == 0 {
      return _ok_int(q);
    }
    return _ok_int(0 - q - 1);
  }
  if p % 2 == 0 {
    let q2 = p / 2;
    return _ok_int(q2 + 4611686018427387904 + 4611686018427387904);
  }
  let q3 = (p - 1) / 2;
  return _ok_int(0 - q3 - 4611686018427387904 - 4611686018427387904 - 1);
}

/// Read an I16 as a zigzag varint (the compact protocol does not fix the
/// width, so values outside int16 round-trip as read).
/// Complexity: O(1).
pub fn parquet_read_i16(r: &mut ParquetReader) -> Result[Int, Str] {
  return parquet_read_zigzag(r);
}

/// Read an I32 as a zigzag varint. Complexity: O(1).
pub fn parquet_read_i32(r: &mut ParquetReader) -> Result[Int, Str] {
  return parquet_read_zigzag(r);
}

/// Read an I64 as a zigzag varint (the full signed 64-bit range).
/// Complexity: O(1).
pub fn parquet_read_i64(r: &mut ParquetReader) -> Result[Int, Str] {
  return parquet_read_zigzag(r);
}

/// Read a BYTE (int8) as one byte, sign-extended to -128..127.
/// Complexity: O(1).
pub fn parquet_read_byte(r: &mut ParquetReader) -> Result[Int, Str] {
  let start = r.pos;
  if r.pos >= r.end {
    return _err_int(_moff("parquet: truncated input", start));
  }
  let b = _r_byte_mut(r, r.pos);
  r.pos = r.pos + 1;
  return _ok_int(_sign_extend(b, 8));
}

/// Read a bool *element* as one byte: 1 = true, 2 = false (the compact
/// protocol element form). Any other byte is "parquet: invalid compact
/// bool value N". Complexity: O(1).
pub fn parquet_read_bool(r: &mut ParquetReader) -> Result[Bool, Str] {
  let start = r.pos;
  if r.pos >= r.end {
    return _err_bool(_moff("parquet: truncated input", start));
  }
  let b = _r_byte_mut(r, r.pos);
  r.pos = r.pos + 1;
  if b == 1 {
    return _ok_bool(true);
  }
  if b == 2 {
    return _ok_bool(false);
  }
  return _err_bool("parquet: invalid compact bool value " + convert.int_to_string(b) + _at(start));
}

/// Read a DOUBLE as its raw 64-bit IEEE-754 bit pattern from 8
/// little-endian bytes (compact protocol order), carried in an Int. For
/// example 1.0 is 0x3FF0000000000000 = 4607182418800017408.
/// Complexity: O(1).
pub fn parquet_read_double_bits(r: &mut ParquetReader) -> Result[Int, Str] {
  let start = r.pos;
  if r.pos + 8 > r.end {
    return _err_int(_moff("parquet: truncated input", start));
  }
  let b0 = _r_byte_mut(r, r.pos);
  let b1 = _r_byte_mut(r, r.pos + 1);
  let b2 = _r_byte_mut(r, r.pos + 2);
  let b3 = _r_byte_mut(r, r.pos + 3);
  let b4 = _r_byte_mut(r, r.pos + 4);
  let b5 = _r_byte_mut(r, r.pos + 5);
  let b6 = _r_byte_mut(r, r.pos + 6);
  let b7 = _r_byte_mut(r, r.pos + 7);
  r.pos = r.pos + 8;
  let neg = b7 >= 128;
  var v: Int = b7 % 128;
  v = v * 256 + b6;
  v = v * 256 + b5;
  v = v * 256 + b4;
  v = v * 256 + b3;
  v = v * 256 + b2;
  v = v * 256 + b1;
  v = v * 256 + b0;
  if neg {
    v = v - 9223372036854775807 - 1;
  }
  return _ok_int(v);
}

/// Read a binary/string value: a varint byte length then that many bytes,
/// verbatim. No content validation. "parquet: binary length out of bounds"
/// when the length is negative or overruns the window (offset of the
/// length prefix). Complexity: O(payload bytes).
pub fn parquet_read_binary(r: &mut ParquetReader) -> Result[Vec[UInt8], Str] {
  let start = r.pos;
  let lr = _read_varint(r);
  if !lr.is_ok {
    return _err_bytes(lr.error);
  }
  let n: Int = lr.value;
  if n < 0 || n > r.end - r.pos {
    return _err_bytes(_moff("parquet: binary length out of bounds", start));
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let b: UInt8 = r.data[r.pos + i];
    out.push(b);
    i = i + 1;
  }
  r.pos = r.pos + n;
  return _ok_bytes(out);
}

/// Read a string value as a `Str`: a varint byte length then that many
/// UTF-8 bytes. The payload must be valid UTF-8 with no 0x00 byte:
/// "parquet: invalid utf-8 at offset N" (overlong forms and surrogate
/// halves included) and "parquet: string contains nul at offset N" (a NUL
/// would abort the v0.61.3 string builder). Use `parquet_read_binary` for
/// arbitrary bytes. Complexity: O(payload bytes).
pub fn parquet_read_string(r: &mut ParquetReader) -> Result[Str, Str] {
  let br = parquet_read_binary(r);
  if !br.is_ok {
    return _err_str(br.error);
  }
  let bytes: Vec[UInt8] = br.value;
  let base = r.pos - bytes.len();
  let ue = _utf8_error(&bytes, base);
  if ue.len() > 0 {
    return _err_str(ue);
  }
  return _ok_str(_bytes_to_str(&bytes));
}

/// Read a LIST or SET header: one byte with the element type in the low
/// nibble and the size in the high nibble, or (size nibble 15) the type in
/// the low nibble of the first byte and an unsigned varint size. Errors:
/// "parquet: unknown compact type N", "parquet: oversized collection"
/// (size negative or larger than the bytes remaining) and truncation, all
/// with the header offset. Complexity: O(1).
pub fn parquet_read_list_header(r: &mut ParquetReader) -> Result[ParquetListHeader, Str] {
  let start = r.pos;
  if r.pos >= r.end {
    return _err_lhdr(_moff("parquet: truncated input", start));
  }
  let b = _r_byte_mut(r, r.pos);
  r.pos = r.pos + 1;
  let size_nib = b / 16;
  let et = b % 16;
  if !_type_known(et) {
    return _err_lhdr(_type_msg(et, start));
  }
  var size = size_nib;
  if size_nib == 15 {
    let vr = _read_varint(r);
    if !vr.is_ok {
      return _err_lhdr(vr.error);
    }
    size = vr.value;
  }
  if size < 0 || size > r.end - r.pos {
    return _err_lhdr(_moff("parquet: oversized collection", start));
  }
  return _ok_lhdr(ParquetListHeader{ etype: et; size: size; });
}

/// Read a SET header. Identical wire layout and errors to
/// `parquet_read_list_header`. Complexity: O(1).
pub fn parquet_read_set_header(r: &mut ParquetReader) -> Result[ParquetListHeader, Str] {
  return parquet_read_list_header(r);
}

/// Read a MAP header: an unsigned varint size then, when the size is
/// non-zero, one byte with the key type in the high nibble and the value
/// type in the low nibble. An empty map is a single `0x00` byte.
/// Errors as `parquet_read_list_header` (the pair-size guard is half the
/// remaining bytes). Complexity: O(1).
pub fn parquet_read_map_header(r: &mut ParquetReader) -> Result[ParquetMapHeader, Str] {
  let start = r.pos;
  let vr = _read_varint(r);
  if !vr.is_ok {
    return _err_mhdr(vr.error);
  }
  let size: Int = vr.value;
  if size == 0 {
    return _ok_mhdr(ParquetMapHeader{ ktype: 0; vtype: 0; size: 0; });
  }
  if size < 0 {
    return _err_mhdr(_moff("parquet: oversized collection", start));
  }
  if r.pos >= r.end {
    return _err_mhdr(_moff("parquet: truncated input", r.pos));
  }
  let b = _r_byte_mut(r, r.pos);
  r.pos = r.pos + 1;
  let kt = b / 16;
  let vt = b % 16;
  if !_type_known(kt) {
    return _err_mhdr(_type_msg(kt, start));
  }
  if !_type_known(vt) {
    return _err_mhdr(_type_msg(vt, start));
  }
  if size > (r.end - r.pos) / 2 {
    return _err_mhdr(_moff("parquet: oversized collection", start));
  }
  return _ok_mhdr(ParquetMapHeader{ ktype: kt; vtype: vt; size: size; });
}

/// Read a field header using the caller-tracked previous field id
/// `last_fid` (0 at the start of each struct). The delta form is
/// `delta << 4 | type` with `field_id = last_fid + delta` for deltas 1..15;
/// otherwise the long form is one byte with a zero high nibble followed by
/// the field id as a zigzag varint. STOP yields `ftype == 0`, `fid == 0`.
/// Errors: "parquet: unknown compact type N" and truncation, with the
/// header offset. Complexity: O(1).
pub fn parquet_read_field_header(r: &mut ParquetReader, last_fid: Int) -> Result[ParquetField, Str] {
  let start = r.pos;
  if r.pos >= r.end {
    return _err_field(_moff("parquet: truncated input", start));
  }
  let b = _r_byte_mut(r, r.pos);
  r.pos = r.pos + 1;
  if b == 0 {
    return _ok_field(ParquetField{ ftype: 0; fid: 0; });
  }
  let delta = b / 16;
  let ctype = b % 16;
  if !_type_known(ctype) {
    return _err_field(_type_msg(ctype, start));
  }
  var fid = last_fid + delta;
  if delta == 0 {
    let zr = parquet_read_zigzag(r);
    if !zr.is_ok {
      return _err_field(zr.error);
    }
    fid = zr.value;
  }
  return _ok_field(ParquetField{ ftype: ctype; fid: fid; });
}

/// The bool value carried by a BOOLEAN_TRUE/BOOLEAN_FALSE field header:
/// true for BOOLEAN_TRUE (1), false for BOOLEAN_FALSE (2). Only call this
/// for bool fields (no bytes follow such a field).
/// Complexity: O(1).
pub fn parquet_field_bool(f: &ParquetField) -> Bool {
  if f.ftype == 1 {
    return true;
  }
  return false;
}

/// Type code of a decoded field header (0 = STOP). Complexity: O(1).
pub fn parquet_field_type(f: &ParquetField) -> Int {
  return f.ftype;
}

/// Field id of a decoded field header (0 for STOP). Complexity: O(1).
pub fn parquet_field_id(f: &ParquetField) -> Int {
  return f.fid;
}

/// Element type code of a decoded list or set header. Complexity: O(1).
pub fn parquet_list_header_type(h: &ParquetListHeader) -> Int {
  return h.etype;
}

/// Element count of a decoded list or set header. Complexity: O(1).
pub fn parquet_list_header_size(h: &ParquetListHeader) -> Int {
  return h.size;
}

/// Key type code of a decoded map header (0 for an empty map).
/// Complexity: O(1).
pub fn parquet_map_header_key_type(h: &ParquetMapHeader) -> Int {
  return h.ktype;
}

/// Value type code of a decoded map header (0 for an empty map).
/// Complexity: O(1).
pub fn parquet_map_header_value_type(h: &ParquetMapHeader) -> Int {
  return h.vtype;
}

/// Pair count of a decoded map header. Complexity: O(1).
pub fn parquet_map_header_size(h: &ParquetMapHeader) -> Int {
  return h.size;
}

// Consume exactly `size` bytes or fail with truncation at `start`.
fn _skip_fixed(r: &mut ParquetReader, size: Int, start: Int) -> Result[Int, Str] {
  if r.pos + size > r.end {
    return _err_int(_moff("parquet: truncated input", start));
  }
  r.pos = r.pos + size;
  return _ok_int(r.pos - start);
}

// Skip one *element* of type `ctype` inside a list/set/map: bool elements
// occupy one byte (1 = true, 2 = false).
fn _skip_element(r: &mut ParquetReader, ctype: Int, depth: Int) -> Result[Int, Str] {
  if ctype == _C_TRUE || ctype == _C_FALSE {
    return _skip_fixed(r, 1, r.pos);
  }
  return _skip_value(r, ctype, depth);
}

// Skip one value of type `ctype` at container depth `depth`, returning the
// bytes consumed. Fields of type BOOLEAN_TRUE/BOOLEAN_FALSE consume zero
// bytes (the value is in the header); use `_skip_element` for container
// elements. Containers count against `parquet_max_depth()`.
fn _skip_value(r: &mut ParquetReader, ctype: Int, depth: Int) -> Result[Int, Str] {
  let start = r.pos;
  if ctype == _C_TRUE || ctype == _C_FALSE {
    return _ok_int(0);
  }
  if ctype == _C_BYTE {
    return _skip_fixed(r, 1, start);
  }
  if ctype == _C_I16 || ctype == _C_I32 || ctype == _C_I64 {
    let zr = parquet_read_zigzag(r);
    if !zr.is_ok {
      return _err_int(zr.error);
    }
    return _ok_int(r.pos - start);
  }
  if ctype == _C_DOUBLE {
    return _skip_fixed(r, 8, start);
  }
  if ctype == _C_BINARY {
    let br = parquet_read_binary(r);
    if !br.is_ok {
      return _err_int(br.error);
    }
    return _ok_int(r.pos - start);
  }
  if ctype == _C_STRUCT {
    if depth >= _MAX_DEPTH {
      return _err_int(_depth_msg(start));
    }
    var last = 0;
    var go = true;
    while go {
      let fr = parquet_read_field_header(r, last);
      if !fr.is_ok {
        return _err_int(fr.error);
      }
      let fld: ParquetField = fr.value;
      if fld.ftype == _C_STOP {
        go = false;
      } else {
        last = fld.fid;
        let sv = _skip_value(r, fld.ftype, depth + 1);
        if !sv.is_ok {
          return _err_int(sv.error);
        }
      }
    }
    return _ok_int(r.pos - start);
  }
  if ctype == _C_MAP {
    if depth >= _MAX_DEPTH {
      return _err_int(_depth_msg(start));
    }
    let mr = parquet_read_map_header(r);
    if !mr.is_ok {
      return _err_int(mr.error);
    }
    let h: ParquetMapHeader = mr.value;
    var i = 0;
    while i < h.size {
      let kt: Int = h.ktype;
      let vt: Int = h.vtype;
      let ks = _skip_element(r, kt, depth + 1);
      if !ks.is_ok {
        return _err_int(ks.error);
      }
      let vs = _skip_element(r, vt, depth + 1);
      if !vs.is_ok {
        return _err_int(vs.error);
      }
      i = i + 1;
    }
    return _ok_int(r.pos - start);
  }
  if ctype == _C_SET || ctype == _C_LIST {
    if depth >= _MAX_DEPTH {
      return _err_int(_depth_msg(start));
    }
    let lr = parquet_read_list_header(r);
    if !lr.is_ok {
      return _err_int(lr.error);
    }
    let h2: ParquetListHeader = lr.value;
    var j = 0;
    while j < h2.size {
      let et: Int = h2.etype;
      let es = _skip_element(r, et, depth + 1);
      if !es.is_ok {
        return _err_int(es.error);
      }
      j = j + 1;
    }
    return _ok_int(r.pos - start);
  }
  return _err_int(_type_msg(ctype, start));
}

/// Skip one field value of type `ctype` at the cursor and return the bytes
/// consumed, recursing structurally through struct/map/list/set. Bool
/// fields (type 1/2) consume zero bytes (their value is in the header);
/// container elements are skipped with the one-byte bool element form.
/// Skipped values are not content-validated (a skipped bool element may
/// hold any byte, a skipped string may hold invalid UTF-8). Errors:
/// unknown type, truncation and the 64-level nesting cap, all with byte
/// offsets. Complexity: O(skipped bytes).
pub fn parquet_skip_value(r: &mut ParquetReader, ctype: Int) -> Result[Int, Str] {
  return _skip_value(r, ctype, 0);
}

// --------------------------------------------------
//  Parquet metadata: parse helpers
// --------------------------------------------------

// The default (absent) ColumnMetaData decode result.
fn _default_meta() -> _Meta {
  return _Meta{
    type_raw: 0; type_present: 0;
    codec: 0; codec_present: 0;
    num_values: 0; nv_present: 0;
    total_us: 0; tus_present: 0;
    total_cs: 0; tcs_present: 0;
    dpo: 0; dpo_present: 0;
    ipo: 0; ipo_present: 0;
    dict_po: 0; dict_present: 0;
    enc_off: 0; enc_count: 0;
    path_off: 0; path_count: 0;
    kv_off: 0; kv_count: 0;
    es_off: 0; es_count: 0;
    stats_pushed: 0;
  };
}

// Push one all-absent statistics block (used for chunks without a
// Statistics struct); mirrors `_parse_statistics` push-for-push.
fn _push_default_stats(f: &mut ParquetFile) {
  f.st_present.push(0);
  f.st_max_off.push(0);
  f.st_max_len.push(0);
  f.st_max_present.push(0);
  f.st_min_off.push(0);
  f.st_min_len.push(0);
  f.st_min_present.push(0);
  f.st_maxv_off.push(0);
  f.st_maxv_len.push(0);
  f.st_maxv_present.push(0);
  f.st_minv_off.push(0);
  f.st_minv_len.push(0);
  f.st_minv_present.push(0);
  f.st_null_count.push(0);
  f.st_null_present.push(0);
  f.st_distinct_count.push(0);
  f.st_distinct_present.push(0);
  f.st_max_exact.push(0);
  f.st_max_exact_present.push(0);
  f.st_min_exact.push(0);
  f.st_min_exact_present.push(0);
}

// KeyValue: 1 key (string), 2 value (string, optional). Pushes one entry
// into the shared KV pools.
fn _parse_key_value(f: &mut ParquetFile, r: &mut ParquetReader) -> Result[Int, Str] {
  var key = "";
  var value = "";
  var value_present = 0;
  var last = 0;
  var go = true;
  while go {
    let fr = parquet_read_field_header(r, last);
    if !fr.is_ok {
      return _err_int(fr.error);
    }
    let fld: ParquetField = fr.value;
    let t: Int = fld.ftype;
    let fid: Int = fld.fid;
    if t == _C_STOP {
      go = false;
    } else if fid == 1 && t == _C_BINARY {
      last = fid;
      let sr = parquet_read_string(r);
      if !sr.is_ok {
        return _err_int(sr.error);
      }
      key = sr.value;
    } else if fid == 2 && t == _C_BINARY {
      last = fid;
      let sr2 = parquet_read_string(r);
      if !sr2.is_ok {
        return _err_int(sr2.error);
      }
      value = sr2.value;
      value_present = 1;
    } else {
      last = fid;
      let sk = _skip_value(r, t, 0);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    }
  }
  f.kv_key.push(key);
  f.kv_value.push(value);
  f.kv_value_present.push(value_present);
  return _ok_int(0);
}

// PageEncodingStats: 1 page_type (i32 enum), 2 encoding (i32 enum),
// 3 count (i32). Pushes one entry into the shared ES vectors.
fn _parse_encoding_stats(f: &mut ParquetFile, r: &mut ParquetReader) -> Result[Int, Str] {
  var page_type = 0;
  var encoding = 0;
  var count = 0;
  var last = 0;
  var go = true;
  while go {
    let fr = parquet_read_field_header(r, last);
    if !fr.is_ok {
      return _err_int(fr.error);
    }
    let fld: ParquetField = fr.value;
    let t: Int = fld.ftype;
    let fid: Int = fld.fid;
    if t == _C_STOP {
      go = false;
    } else if fid == 1 && t == _C_I32 {
      last = fid;
      let zr = parquet_read_zigzag(r);
      if !zr.is_ok {
        return _err_int(zr.error);
      }
      page_type = zr.value;
    } else if fid == 2 && t == _C_I32 {
      last = fid;
      let zr2 = parquet_read_zigzag(r);
      if !zr2.is_ok {
        return _err_int(zr2.error);
      }
      encoding = zr2.value;
    } else if fid == 3 && t == _C_I32 {
      last = fid;
      let zr3 = parquet_read_zigzag(r);
      if !zr3.is_ok {
        return _err_int(zr3.error);
      }
      count = zr3.value;
    } else {
      last = fid;
      let sk = _skip_value(r, t, 0);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    }
  }
  f.es_page_type.push(page_type);
  f.es_encoding.push(encoding);
  f.es_count.push(count);
  return _ok_int(0);
}

// Statistics (all fields optional): 1 max, 2 min, 3 null_count,
// 4 distinct_count, 5 max_value, 6 min_value, 7 is_max_value_exact,
// 8 is_min_value_exact, 9 nan_count (unknown here, skipped). Raw byte
// fields are appended to f.st_pool and located by offset/length. Pushes
// exactly one statistics block (present = 1) on success.
fn _parse_statistics(f: &mut ParquetFile, r: &mut ParquetReader) -> Result[Int, Str] {
  var max_off = 0;
  var max_len = 0;
  var max_present = 0;
  var min_off = 0;
  var min_len = 0;
  var min_present = 0;
  var maxv_off = 0;
  var maxv_len = 0;
  var maxv_present = 0;
  var minv_off = 0;
  var minv_len = 0;
  var minv_present = 0;
  var null_count = 0;
  var null_present = 0;
  var distinct_count = 0;
  var distinct_present = 0;
  var max_exact = 0;
  var max_exact_present = 0;
  var min_exact = 0;
  var min_exact_present = 0;
  var last = 0;
  var go = true;
  while go {
    let fr = parquet_read_field_header(r, last);
    if !fr.is_ok {
      return _err_int(fr.error);
    }
    let fld: ParquetField = fr.value;
    let t: Int = fld.ftype;
    let fid: Int = fld.fid;
    if t == _C_STOP {
      go = false;
    } else if fid == 1 && t == _C_BINARY {
      last = fid;
      let br = parquet_read_binary(r);
      if !br.is_ok {
        return _err_int(br.error);
      }
      let payload: Vec[UInt8] = br.value;
      max_off = f.st_pool.len();
      _append_bytes(&mut f.st_pool, &payload);
      max_len = f.st_pool.len() - max_off;
      max_present = 1;
    } else if fid == 2 && t == _C_BINARY {
      last = fid;
      let br2 = parquet_read_binary(r);
      if !br2.is_ok {
        return _err_int(br2.error);
      }
      let payload2: Vec[UInt8] = br2.value;
      min_off = f.st_pool.len();
      _append_bytes(&mut f.st_pool, &payload2);
      min_len = f.st_pool.len() - min_off;
      min_present = 1;
    } else if fid == 3 && t == _C_I64 {
      last = fid;
      let zr = parquet_read_zigzag(r);
      if !zr.is_ok {
        return _err_int(zr.error);
      }
      null_count = zr.value;
      null_present = 1;
    } else if fid == 4 && t == _C_I64 {
      last = fid;
      let zr2 = parquet_read_zigzag(r);
      if !zr2.is_ok {
        return _err_int(zr2.error);
      }
      distinct_count = zr2.value;
      distinct_present = 1;
    } else if fid == 5 && t == _C_BINARY {
      last = fid;
      let br3 = parquet_read_binary(r);
      if !br3.is_ok {
        return _err_int(br3.error);
      }
      let payload3: Vec[UInt8] = br3.value;
      maxv_off = f.st_pool.len();
      _append_bytes(&mut f.st_pool, &payload3);
      maxv_len = f.st_pool.len() - maxv_off;
      maxv_present = 1;
    } else if fid == 6 && t == _C_BINARY {
      last = fid;
      let br4 = parquet_read_binary(r);
      if !br4.is_ok {
        return _err_int(br4.error);
      }
      let payload4: Vec[UInt8] = br4.value;
      minv_off = f.st_pool.len();
      _append_bytes(&mut f.st_pool, &payload4);
      minv_len = f.st_pool.len() - minv_off;
      minv_present = 1;
    } else if fid == 7 && (t == _C_TRUE || t == _C_FALSE) {
      last = fid;
      max_exact = 0;
      if t == _C_TRUE {
        max_exact = 1;
      }
      max_exact_present = 1;
    } else if fid == 8 && (t == _C_TRUE || t == _C_FALSE) {
      last = fid;
      min_exact = 0;
      if t == _C_TRUE {
        min_exact = 1;
      }
      min_exact_present = 1;
    } else {
      last = fid;
      let sk = _skip_value(r, t, 0);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    }
  }
  f.st_present.push(1);
  f.st_max_off.push(max_off);
  f.st_max_len.push(max_len);
  f.st_max_present.push(max_present);
  f.st_min_off.push(min_off);
  f.st_min_len.push(min_len);
  f.st_min_present.push(min_present);
  f.st_maxv_off.push(maxv_off);
  f.st_maxv_len.push(maxv_len);
  f.st_maxv_present.push(maxv_present);
  f.st_minv_off.push(minv_off);
  f.st_minv_len.push(minv_len);
  f.st_minv_present.push(minv_present);
  f.st_null_count.push(null_count);
  f.st_null_present.push(null_present);
  f.st_distinct_count.push(distinct_count);
  f.st_distinct_present.push(distinct_present);
  f.st_max_exact.push(max_exact);
  f.st_max_exact_present.push(max_exact_present);
  f.st_min_exact.push(min_exact);
  f.st_min_exact_present.push(min_exact_present);
  return _ok_int(0);
}

// LogicalType union: records the member field id (1..19 documented) and
// skips the member body (all members are structs here). Unknown members are
// preserved raw. Returns the member id (0 when the union was empty).
fn _parse_logical_type(r: &mut ParquetReader) -> Result[Int, Str] {
  var member = 0;
  var last = 0;
  var go = true;
  while go {
    let fr = parquet_read_field_header(r, last);
    if !fr.is_ok {
      return _err_int(fr.error);
    }
    let fld: ParquetField = fr.value;
    let t: Int = fld.ftype;
    let fid: Int = fld.fid;
    if t == _C_STOP {
      go = false;
    } else if t == _C_STRUCT {
      last = fid;
      if member == 0 {
        member = fid;
      }
      let sk = _skip_value(r, t, 0);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    } else {
      last = fid;
      let sk2 = _skip_value(r, t, 0);
      if !sk2.is_ok {
        return _err_int(sk2.error);
      }
    }
  }
  return _ok_int(member);
}

// SchemaElement: 1 type, 2 type_length, 3 repetition_type, 4 name,
// 5 num_children, 6 converted_type, 7 scale, 8 precision, 9 field_id,
// 10 logicalType. Pushes one entry (all parallel vectors) on success.
fn _parse_schema_element(f: &mut ParquetFile, r: &mut ParquetReader) -> Result[Int, Str] {
  var type_raw = 0;
  var type_present = 0;
  var type_length = 0;
  var tl_present = 0;
  var repetition = 0;
  var rep_present = 0;
  var name = "";
  var num_children = 0;
  var nc_present = 0;
  var converted = 0;
  var conv_present = 0;
  var scale = 0;
  var scale_present = 0;
  var precision = 0;
  var prec_present = 0;
  var field_id = 0;
  var fid_present = 0;
  var logical = 0;
  var logical_present = 0;
  var last = 0;
  var go = true;
  while go {
    let fr = parquet_read_field_header(r, last);
    if !fr.is_ok {
      return _err_int(fr.error);
    }
    let fld: ParquetField = fr.value;
    let t: Int = fld.ftype;
    let fid: Int = fld.fid;
    if t == _C_STOP {
      go = false;
    } else if fid == 1 && t == _C_I32 {
      last = fid;
      let zr = parquet_read_zigzag(r);
      if !zr.is_ok {
        return _err_int(zr.error);
      }
      type_raw = zr.value;
      type_present = 1;
    } else if fid == 2 && t == _C_I32 {
      last = fid;
      let zr2 = parquet_read_zigzag(r);
      if !zr2.is_ok {
        return _err_int(zr2.error);
      }
      type_length = zr2.value;
      tl_present = 1;
    } else if fid == 3 && t == _C_I32 {
      last = fid;
      let zr3 = parquet_read_zigzag(r);
      if !zr3.is_ok {
        return _err_int(zr3.error);
      }
      repetition = zr3.value;
      rep_present = 1;
    } else if fid == 4 && t == _C_BINARY {
      last = fid;
      let sr = parquet_read_string(r);
      if !sr.is_ok {
        return _err_int(sr.error);
      }
      name = sr.value;
    } else if fid == 5 && t == _C_I32 {
      last = fid;
      let zr4 = parquet_read_zigzag(r);
      if !zr4.is_ok {
        return _err_int(zr4.error);
      }
      num_children = zr4.value;
      nc_present = 1;
    } else if fid == 6 && t == _C_I32 {
      last = fid;
      let zr5 = parquet_read_zigzag(r);
      if !zr5.is_ok {
        return _err_int(zr5.error);
      }
      converted = zr5.value;
      conv_present = 1;
    } else if fid == 7 && t == _C_I32 {
      last = fid;
      let zr6 = parquet_read_zigzag(r);
      if !zr6.is_ok {
        return _err_int(zr6.error);
      }
      scale = zr6.value;
      scale_present = 1;
    } else if fid == 8 && t == _C_I32 {
      last = fid;
      let zr7 = parquet_read_zigzag(r);
      if !zr7.is_ok {
        return _err_int(zr7.error);
      }
      precision = zr7.value;
      prec_present = 1;
    } else if fid == 9 && t == _C_I32 {
      last = fid;
      let zr8 = parquet_read_zigzag(r);
      if !zr8.is_ok {
        return _err_int(zr8.error);
      }
      field_id = zr8.value;
      fid_present = 1;
    } else if fid == 10 && t == _C_STRUCT {
      last = fid;
      let lr = _parse_logical_type(r);
      if !lr.is_ok {
        return _err_int(lr.error);
      }
      logical = lr.value;
      logical_present = 1;
    } else {
      last = fid;
      let sk = _skip_value(r, t, 0);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    }
  }
  f.s_name.push(name);
  f.s_type.push(type_raw);
  f.s_type_present.push(type_present);
  f.s_type_length.push(type_length);
  f.s_type_length_present.push(tl_present);
  f.s_repetition.push(repetition);
  f.s_repetition_present.push(rep_present);
  f.s_num_children.push(num_children);
  f.s_num_children_present.push(nc_present);
  f.s_converted.push(converted);
  f.s_converted_present.push(conv_present);
  f.s_scale.push(scale);
  f.s_scale_present.push(scale_present);
  f.s_precision.push(precision);
  f.s_precision_present.push(prec_present);
  f.s_field_id.push(field_id);
  f.s_field_id_present.push(fid_present);
  f.s_logical.push(logical);
  f.s_logical_present.push(logical_present);
  return _ok_int(0);
}

// ColumnMetaData: 1 type, 2 encodings (list<i32>), 3 path_in_schema
// (list<string>), 4 codec, 5 num_values, 6 total_uncompressed_size,
// 7 total_compressed_size, 8 key_value_metadata, 9 data_page_offset,
// 10 index_page_offset, 11 dictionary_page_offset, 12 statistics,
// 13 encoding_stats. Pools (encoding/path/KV/ES/statistics) are appended
// here; the per-chunk location pairs travel back in _Meta.
fn _parse_column_meta_data(f: &mut ParquetFile, r: &mut ParquetReader) -> Result[_Meta, Str] {
  var m = _default_meta();
  var last = 0;
  var go = true;
  while go {
    let fr = parquet_read_field_header(r, last);
    if !fr.is_ok {
      return _err_meta(fr.error);
    }
    let fld: ParquetField = fr.value;
    let t: Int = fld.ftype;
    let fid: Int = fld.fid;
    if t == _C_STOP {
      go = false;
    } else if fid == 1 && t == _C_I32 {
      last = fid;
      let zr = parquet_read_zigzag(r);
      if !zr.is_ok {
        return _err_meta(zr.error);
      }
      m.type_raw = zr.value;
      m.type_present = 1;
    } else if fid == 2 && t == _C_LIST {
      last = fid;
      let lstart = r.pos;
      let lr = parquet_read_list_header(r);
      if !lr.is_ok {
        return _err_meta(lr.error);
      }
      let h: ParquetListHeader = lr.value;
      if h.etype != _C_I32 {
        return _err_meta("parquet: unexpected list element type " + convert.int_to_string(h.etype) + _at(lstart));
      }
      m.enc_off = f.enc_pool.len();
      var i = 0;
      while i < h.size {
        let zr2 = parquet_read_zigzag(r);
        if !zr2.is_ok {
          return _err_meta(zr2.error);
        }
        let ev: Int = zr2.value;
        f.enc_pool.push(ev);
        i = i + 1;
      }
      m.enc_count = h.size;
    } else if fid == 3 && t == _C_LIST {
      last = fid;
      let lstart2 = r.pos;
      let lr2 = parquet_read_list_header(r);
      if !lr2.is_ok {
        return _err_meta(lr2.error);
      }
      let h2: ParquetListHeader = lr2.value;
      if h2.etype != _C_BINARY {
        return _err_meta("parquet: unexpected list element type " + convert.int_to_string(h2.etype) + _at(lstart2));
      }
      m.path_off = f.path_pool.len();
      var j = 0;
      while j < h2.size {
        let sr = parquet_read_string(r);
        if !sr.is_ok {
          return _err_meta(sr.error);
        }
        let part: Str = sr.value;
        f.path_pool.push(part);
        j = j + 1;
      }
      m.path_count = h2.size;
    } else if fid == 4 && t == _C_I32 {
      last = fid;
      let zr3 = parquet_read_zigzag(r);
      if !zr3.is_ok {
        return _err_meta(zr3.error);
      }
      m.codec = zr3.value;
      m.codec_present = 1;
    } else if fid == 5 && t == _C_I64 {
      last = fid;
      let zr4 = parquet_read_zigzag(r);
      if !zr4.is_ok {
        return _err_meta(zr4.error);
      }
      m.num_values = zr4.value;
      m.nv_present = 1;
    } else if fid == 6 && t == _C_I64 {
      last = fid;
      let zr5 = parquet_read_zigzag(r);
      if !zr5.is_ok {
        return _err_meta(zr5.error);
      }
      m.total_us = zr5.value;
      m.tus_present = 1;
    } else if fid == 7 && t == _C_I64 {
      last = fid;
      let zr6 = parquet_read_zigzag(r);
      if !zr6.is_ok {
        return _err_meta(zr6.error);
      }
      m.total_cs = zr6.value;
      m.tcs_present = 1;
    } else if fid == 8 && t == _C_LIST {
      last = fid;
      let lstart3 = r.pos;
      let lr3 = parquet_read_list_header(r);
      if !lr3.is_ok {
        return _err_meta(lr3.error);
      }
      let h3: ParquetListHeader = lr3.value;
      if h3.etype != _C_STRUCT {
        return _err_meta("parquet: unexpected list element type " + convert.int_to_string(h3.etype) + _at(lstart3));
      }
      m.kv_off = f.kv_key.len();
      var k = 0;
      while k < h3.size {
        let kr = _parse_key_value(f, r);
        if !kr.is_ok {
          return _err_meta(kr.error);
        }
        k = k + 1;
      }
      m.kv_count = h3.size;
    } else if fid == 9 && t == _C_I64 {
      last = fid;
      let zr7 = parquet_read_zigzag(r);
      if !zr7.is_ok {
        return _err_meta(zr7.error);
      }
      m.dpo = zr7.value;
      m.dpo_present = 1;
    } else if fid == 10 && t == _C_I64 {
      last = fid;
      let zr8 = parquet_read_zigzag(r);
      if !zr8.is_ok {
        return _err_meta(zr8.error);
      }
      m.ipo = zr8.value;
      m.ipo_present = 1;
    } else if fid == 11 && t == _C_I64 {
      last = fid;
      let zr9 = parquet_read_zigzag(r);
      if !zr9.is_ok {
        return _err_meta(zr9.error);
      }
      m.dict_po = zr9.value;
      m.dict_present = 1;
    } else if fid == 12 && t == _C_STRUCT {
      last = fid;
      let sr = _parse_statistics(f, r);
      if !sr.is_ok {
        return _err_meta(sr.error);
      }
      m.stats_pushed = 1;
    } else if fid == 13 && t == _C_LIST {
      last = fid;
      let lstart4 = r.pos;
      let lr4 = parquet_read_list_header(r);
      if !lr4.is_ok {
        return _err_meta(lr4.error);
      }
      let h4: ParquetListHeader = lr4.value;
      if h4.etype != _C_STRUCT {
        return _err_meta("parquet: unexpected list element type " + convert.int_to_string(h4.etype) + _at(lstart4));
      }
      m.es_off = f.es_page_type.len();
      var e = 0;
      while e < h4.size {
        let er = _parse_encoding_stats(f, r);
        if !er.is_ok {
          return _err_meta(er.error);
        }
        e = e + 1;
      }
      m.es_count = h4.size;
    } else {
      last = fid;
      let sk = _skip_value(r, t, 0);
      if !sk.is_ok {
        return _err_meta(sk.error);
      }
    }
  }
  return _ok_meta(m);
}

// SortingColumn: 1 column_idx (i32), 2 descending (bool), 3 nulls_first
// (bool). Pushes one entry into the three sorting vectors.
fn _parse_sorting_column(f: &mut ParquetFile, r: &mut ParquetReader) -> Result[Int, Str] {
  var column_idx = 0;
  var descending = 0;
  var nulls_first = 0;
  var last = 0;
  var go = true;
  while go {
    let fr = parquet_read_field_header(r, last);
    if !fr.is_ok {
      return _err_int(fr.error);
    }
    let fld: ParquetField = fr.value;
    let t: Int = fld.ftype;
    let fid: Int = fld.fid;
    if t == _C_STOP {
      go = false;
    } else if fid == 1 && t == _C_I32 {
      last = fid;
      let zr = parquet_read_zigzag(r);
      if !zr.is_ok {
        return _err_int(zr.error);
      }
      column_idx = zr.value;
    } else if fid == 2 && (t == _C_TRUE || t == _C_FALSE) {
      last = fid;
      descending = 0;
      if t == _C_TRUE {
        descending = 1;
      }
    } else if fid == 3 && (t == _C_TRUE || t == _C_FALSE) {
      last = fid;
      nulls_first = 0;
      if t == _C_TRUE {
        nulls_first = 1;
      }
    } else {
      last = fid;
      let sk = _skip_value(r, t, 0);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    }
  }
  f.sort_column_idx.push(column_idx);
  f.sort_descending.push(descending);
  f.sort_nulls_first.push(nulls_first);
  return _ok_int(0);
}

// ColumnOrder union: records the member field id (1 TypeDefinedOrder,
// 2 IEEE754TotalOrder, 3 Int96TimestampOrder; unknown members preserved
// raw) and skips the member body. Pushes one entry into the co vectors.
fn _parse_column_order(f: &mut ParquetFile, r: &mut ParquetReader) -> Result[Int, Str] {
  var member = 0;
  var member_present = 0;
  var last = 0;
  var go = true;
  while go {
    let fr = parquet_read_field_header(r, last);
    if !fr.is_ok {
      return _err_int(fr.error);
    }
    let fld: ParquetField = fr.value;
    let t: Int = fld.ftype;
    let fid: Int = fld.fid;
    if t == _C_STOP {
      go = false;
    } else if t == _C_STRUCT {
      last = fid;
      if member_present == 0 {
        member = fid;
        member_present = 1;
      }
      let sk = _skip_value(r, t, 0);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    } else {
      last = fid;
      let sk2 = _skip_value(r, t, 0);
      if !sk2.is_ok {
        return _err_int(sk2.error);
      }
    }
  }
  f.co_type.push(member);
  f.co_type_present.push(member_present);
  return _ok_int(0);
}

// ColumnChunk: 1 file_path, 2 file_offset, 3 meta_data, 4/5 offset_index
// offset/length, 6/7 column_index offset/length; 8 crypto_metadata and
// 9 encrypted_column_metadata are skipped. Pushes one entry into every
// per-chunk vector (mirrored), plus a statistics block.
fn _parse_column_chunk(f: &mut ParquetFile, r: &mut ParquetReader) -> Result[Int, Str] {
  var file_path = "";
  var fp_present = 0;
  var file_offset = 0;
  var oi_off = 0;
  var oi_off_present = 0;
  var oi_len = 0;
  var oi_len_present = 0;
  var ci_off = 0;
  var ci_off_present = 0;
  var ci_len = 0;
  var ci_len_present = 0;
  var meta_present = 0;
  var m = _default_meta();
  var last = 0;
  var go = true;
  while go {
    let fr = parquet_read_field_header(r, last);
    if !fr.is_ok {
      return _err_int(fr.error);
    }
    let fld: ParquetField = fr.value;
    let t: Int = fld.ftype;
    let fid: Int = fld.fid;
    if t == _C_STOP {
      go = false;
    } else if fid == 1 && t == _C_BINARY {
      last = fid;
      let sr = parquet_read_string(r);
      if !sr.is_ok {
        return _err_int(sr.error);
      }
      file_path = sr.value;
      fp_present = 1;
    } else if fid == 2 && t == _C_I64 {
      last = fid;
      let zr = parquet_read_zigzag(r);
      if !zr.is_ok {
        return _err_int(zr.error);
      }
      file_offset = zr.value;
    } else if fid == 3 && t == _C_STRUCT {
      last = fid;
      let mr = _parse_column_meta_data(f, r);
      if !mr.is_ok {
        return _err_int(mr.error);
      }
      m = mr.value;
      meta_present = 1;
    } else if fid == 4 && t == _C_I64 {
      last = fid;
      let zr2 = parquet_read_zigzag(r);
      if !zr2.is_ok {
        return _err_int(zr2.error);
      }
      oi_off = zr2.value;
      oi_off_present = 1;
    } else if fid == 5 && t == _C_I32 {
      last = fid;
      let zr3 = parquet_read_zigzag(r);
      if !zr3.is_ok {
        return _err_int(zr3.error);
      }
      oi_len = zr3.value;
      oi_len_present = 1;
    } else if fid == 6 && t == _C_I64 {
      last = fid;
      let zr4 = parquet_read_zigzag(r);
      if !zr4.is_ok {
        return _err_int(zr4.error);
      }
      ci_off = zr4.value;
      ci_off_present = 1;
    } else if fid == 7 && t == _C_I32 {
      last = fid;
      let zr5 = parquet_read_zigzag(r);
      if !zr5.is_ok {
        return _err_int(zr5.error);
      }
      ci_len = zr5.value;
      ci_len_present = 1;
    } else {
      last = fid;
      let sk = _skip_value(r, t, 0);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    }
  }
  f.cc_file_path.push(file_path);
  f.cc_file_path_present.push(fp_present);
  f.cc_file_offset.push(file_offset);
  f.cc_meta_present.push(meta_present);
  f.cc_type.push(m.type_raw);
  f.cc_type_present.push(m.type_present);
  f.cc_codec.push(m.codec);
  f.cc_codec_present.push(m.codec_present);
  f.cc_num_values.push(m.num_values);
  f.cc_num_values_present.push(m.nv_present);
  f.cc_total_uncompressed_size.push(m.total_us);
  f.cc_total_us_present.push(m.tus_present);
  f.cc_total_compressed_size.push(m.total_cs);
  f.cc_total_cs_present.push(m.tcs_present);
  f.cc_data_page_offset.push(m.dpo);
  f.cc_dpo_present.push(m.dpo_present);
  f.cc_index_page_offset.push(m.ipo);
  f.cc_ipo_present.push(m.ipo_present);
  f.cc_dictionary_page_offset.push(m.dict_po);
  f.cc_dict_po_present.push(m.dict_present);
  f.cc_oi_off.push(oi_off);
  f.cc_oi_off_present.push(oi_off_present);
  f.cc_oi_len.push(oi_len);
  f.cc_oi_len_present.push(oi_len_present);
  f.cc_ci_off.push(ci_off);
  f.cc_ci_off_present.push(ci_off_present);
  f.cc_ci_len.push(ci_len);
  f.cc_ci_len_present.push(ci_len_present);
  f.cc_enc_off.push(m.enc_off);
  f.cc_enc_count.push(m.enc_count);
  f.cc_path_off.push(m.path_off);
  f.cc_path_count.push(m.path_count);
  f.cc_kv_off.push(m.kv_off);
  f.cc_kv_count.push(m.kv_count);
  f.cc_es_off.push(m.es_off);
  f.cc_es_count.push(m.es_count);
  if m.stats_pushed == 0 {
    _push_default_stats(f);
  }
  return _ok_int(0);
}

// RowGroup: 1 columns, 2 total_byte_size, 3 num_rows, 4 sorting_columns,
// 5 file_offset, 6 total_compressed_size, 7 ordinal. Pushes one entry in
// each row-group vector with the column/sorting spans already parsed.
fn _parse_row_group(f: &mut ParquetFile, r: &mut ParquetReader) -> Result[Int, Str] {
  var total_byte_size = 0;
  var num_rows = 0;
  var file_offset = 0;
  var file_offset_present = 0;
  var total_cs = 0;
  var total_cs_present = 0;
  var ordinal = 0;
  var ordinal_present = 0;
  let cc_off = f.cc_file_offset.len();
  let sort_off = f.sort_column_idx.len();
  var last = 0;
  var go = true;
  while go {
    let fr = parquet_read_field_header(r, last);
    if !fr.is_ok {
      return _err_int(fr.error);
    }
    let fld: ParquetField = fr.value;
    let t: Int = fld.ftype;
    let fid: Int = fld.fid;
    if t == _C_STOP {
      go = false;
    } else if fid == 1 && t == _C_LIST {
      last = fid;
      let lstart = r.pos;
      let lr = parquet_read_list_header(r);
      if !lr.is_ok {
        return _err_int(lr.error);
      }
      let h: ParquetListHeader = lr.value;
      if h.etype != _C_STRUCT {
        return _err_int("parquet: unexpected list element type " + convert.int_to_string(h.etype) + _at(lstart));
      }
      var i = 0;
      while i < h.size {
        let cr = _parse_column_chunk(f, r);
        if !cr.is_ok {
          return _err_int(cr.error);
        }
        i = i + 1;
      }
    } else if fid == 2 && t == _C_I64 {
      last = fid;
      let zr = parquet_read_zigzag(r);
      if !zr.is_ok {
        return _err_int(zr.error);
      }
      total_byte_size = zr.value;
    } else if fid == 3 && t == _C_I64 {
      last = fid;
      let zr2 = parquet_read_zigzag(r);
      if !zr2.is_ok {
        return _err_int(zr2.error);
      }
      num_rows = zr2.value;
    } else if fid == 4 && t == _C_LIST {
      last = fid;
      let lstart2 = r.pos;
      let lr2 = parquet_read_list_header(r);
      if !lr2.is_ok {
        return _err_int(lr2.error);
      }
      let h2: ParquetListHeader = lr2.value;
      if h2.etype != _C_STRUCT {
        return _err_int("parquet: unexpected list element type " + convert.int_to_string(h2.etype) + _at(lstart2));
      }
      var j = 0;
      while j < h2.size {
        let scr = _parse_sorting_column(f, r);
        if !scr.is_ok {
          return _err_int(scr.error);
        }
        j = j + 1;
      }
    } else if fid == 5 && t == _C_I64 {
      last = fid;
      let zr3 = parquet_read_zigzag(r);
      if !zr3.is_ok {
        return _err_int(zr3.error);
      }
      file_offset = zr3.value;
      file_offset_present = 1;
    } else if fid == 6 && t == _C_I64 {
      last = fid;
      let zr4 = parquet_read_zigzag(r);
      if !zr4.is_ok {
        return _err_int(zr4.error);
      }
      total_cs = zr4.value;
      total_cs_present = 1;
    } else if fid == 7 && (t == _C_I16 || t == _C_I32) {
      last = fid;
      let zr5 = parquet_read_zigzag(r);
      if !zr5.is_ok {
        return _err_int(zr5.error);
      }
      ordinal = zr5.value;
      ordinal_present = 1;
    } else {
      last = fid;
      let sk = _skip_value(r, t, 0);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    }
  }
  f.rg_cc_off.push(cc_off);
  f.rg_cc_count.push(f.cc_file_offset.len() - cc_off);
  f.rg_total_byte_size.push(total_byte_size);
  f.rg_num_rows.push(num_rows);
  f.rg_file_offset.push(file_offset);
  f.rg_file_offset_present.push(file_offset_present);
  f.rg_total_compressed_size.push(total_cs);
  f.rg_total_compressed_size_present.push(total_cs_present);
  f.rg_ordinal.push(ordinal);
  f.rg_ordinal_present.push(ordinal_present);
  f.rg_sort_off.push(sort_off);
  f.rg_sort_count.push(f.sort_column_idx.len() - sort_off);
  return _ok_int(0);
}

// FileMetaData: 1 version, 2 schema, 3 num_rows, 4 row_groups,
// 5 key_value_metadata, 6 created_by, 7 column_orders; 8
// encryption_algorithm and 9 footer_signing_key_metadata are skipped.
fn _parse_file_metadata(f: &mut ParquetFile, r: &mut ParquetReader) -> Result[Int, Str] {
  var last = 0;
  var go = true;
  while go {
    let fr = parquet_read_field_header(r, last);
    if !fr.is_ok {
      return _err_int(fr.error);
    }
    let fld: ParquetField = fr.value;
    let t: Int = fld.ftype;
    let fid: Int = fld.fid;
    if t == _C_STOP {
      go = false;
    } else if fid == 1 && t == _C_I32 {
      last = fid;
      let zr = parquet_read_zigzag(r);
      if !zr.is_ok {
        return _err_int(zr.error);
      }
      f.version = zr.value;
    } else if fid == 2 && t == _C_LIST {
      last = fid;
      let lstart = r.pos;
      let lr = parquet_read_list_header(r);
      if !lr.is_ok {
        return _err_int(lr.error);
      }
      let h: ParquetListHeader = lr.value;
      if h.etype != _C_STRUCT {
        return _err_int("parquet: unexpected list element type " + convert.int_to_string(h.etype) + _at(lstart));
      }
      var i = 0;
      while i < h.size {
        let er = _parse_schema_element(f, r);
        if !er.is_ok {
          return _err_int(er.error);
        }
        i = i + 1;
      }
    } else if fid == 3 && t == _C_I64 {
      last = fid;
      let zr2 = parquet_read_zigzag(r);
      if !zr2.is_ok {
        return _err_int(zr2.error);
      }
      f.num_rows = zr2.value;
    } else if fid == 4 && t == _C_LIST {
      last = fid;
      let lstart2 = r.pos;
      let lr2 = parquet_read_list_header(r);
      if !lr2.is_ok {
        return _err_int(lr2.error);
      }
      let h2: ParquetListHeader = lr2.value;
      if h2.etype != _C_STRUCT {
        return _err_int("parquet: unexpected list element type " + convert.int_to_string(h2.etype) + _at(lstart2));
      }
      var j = 0;
      while j < h2.size {
        let rr = _parse_row_group(f, r);
        if !rr.is_ok {
          return _err_int(rr.error);
        }
        j = j + 1;
      }
    } else if fid == 5 && t == _C_LIST {
      last = fid;
      let lstart3 = r.pos;
      let lr3 = parquet_read_list_header(r);
      if !lr3.is_ok {
        return _err_int(lr3.error);
      }
      let h3: ParquetListHeader = lr3.value;
      if h3.etype != _C_STRUCT {
        return _err_int("parquet: unexpected list element type " + convert.int_to_string(h3.etype) + _at(lstart3));
      }
      let kv_off = f.kv_key.len();
      var k = 0;
      while k < h3.size {
        let kr = _parse_key_value(f, r);
        if !kr.is_ok {
          return _err_int(kr.error);
        }
        k = k + 1;
      }
      f.file_kv_off = kv_off;
      f.file_kv_count = f.kv_key.len() - kv_off;
    } else if fid == 6 && t == _C_BINARY {
      last = fid;
      let sr = parquet_read_string(r);
      if !sr.is_ok {
        return _err_int(sr.error);
      }
      f.created_by = sr.value;
      f.created_by_present = 1;
    } else if fid == 7 && t == _C_LIST {
      last = fid;
      let lstart4 = r.pos;
      let lr4 = parquet_read_list_header(r);
      if !lr4.is_ok {
        return _err_int(lr4.error);
      }
      let h4: ParquetListHeader = lr4.value;
      if h4.etype != _C_STRUCT {
        return _err_int("parquet: unexpected list element type " + convert.int_to_string(h4.etype) + _at(lstart4));
      }
      var e = 0;
      while e < h4.size {
        let cor = _parse_column_order(f, r);
        if !cor.is_ok {
          return _err_int(cor.error);
        }
        e = e + 1;
      }
    } else {
      last = fid;
      let sk = _skip_value(r, t, 0);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    }
  }
  return _ok_int(0);
}

// --------------------------------------------------
//  Schema tree walk
// --------------------------------------------------

// Compute s_parent/s_depth/s_path/s_max_def/s_max_rep/s_leaf_index over the
// already-parsed schema element vectors, validating the flattened
// depth-first structure against each node's num_children. `schema_off` is
// the byte offset reported by structural errors.
fn _build_schema(f: &mut ParquetFile, schema_off: Int) -> Result[Int, Str] {
  let n = f.s_name.len();
  if n == 0 {
    return _ok_int(0);
  }
  if f.s_num_children[0] < 0 {
    return _err_int(_moff("parquet: schema element has negative num_children", schema_off));
  }
  var stack = Vec[Int].new();
  var used = Vec[Int].new();
  stack.push(0);
  used.push(0);
  var top = 0;
  var leaf = 0;
  f.s_parent.push(-1);
  f.s_depth.push(0);
  f.s_max_def.push(0);
  f.s_max_rep.push(0);
  f.s_leaf_index.push(-1);
  f.s_path.push("");
  var i = 1;
  while i < n {
    // Pop every group whose declared children are all accounted for.
    var go = true;
    while go {
      let si: Int = stack[top];
      let cn: Int = f.s_num_children[si];
      let u: Int = used[top];
      if u < cn {
        go = false;
      } else {
        if top == 0 {
          return _err_int(_moff("parquet: schema element count does not match num_children", schema_off));
        }
        top = top - 1;
      }
    }
    let p: Int = stack[top];
    let nc_raw: Int = f.s_num_children[i];
    if nc_raw < 0 {
      return _err_int(_moff("parquet: schema element has negative num_children", schema_off));
    }
    let rep: Int = f.s_repetition[i];
    let rep_p: Int = f.s_repetition_present[i];
    var md: Int = f.s_max_def[p];
    var mr: Int = f.s_max_rep[p];
    if rep_p == 1 {
      if rep != 0 {
        md = md + 1;
      }
      if rep == 2 {
        mr = mr + 1;
      }
    }
    let dep: Int = f.s_depth[p] + 1;
    var path: Str = "";
    if p == 0 {
      let nm: Str = f.s_name[i];
      path = nm;
    } else {
      let pp: Str = f.s_path[p];
      let nm2: Str = f.s_name[i];
      path = pp + "." + nm2;
    }
    var li = -1;
    if nc_raw == 0 {
      li = leaf;
      leaf = leaf + 1;
    }
    f.s_parent.push(p);
    f.s_depth.push(dep);
    f.s_max_def.push(md);
    f.s_max_rep.push(mr);
    f.s_leaf_index.push(li);
    f.s_path.push(path);
    used[top] = used[top] + 1;
    if nc_raw > 0 {
      stack.push(i);
      used.push(0);
      top = top + 1;
    }
    i = i + 1;
  }
  // Every still-open group must be exactly consumed.
  var t = 0;
  while t <= top {
    let si2: Int = stack[t];
    let cn2: Int = f.s_num_children[si2];
    let u2: Int = used[t];
    if u2 != cn2 {
      return _err_int(_moff("parquet: schema element count does not match num_children", schema_off));
    }
    t = t + 1;
  }
  return _ok_int(0);
}

// --------------------------------------------------
//  Parser
// --------------------------------------------------

/// Parse the metadata of a Parquet file buffer.
///
/// The buffer must hold the whole file (the header magic, the row-group
/// data, the FileMetaData footer and the trailing length + magic). The
/// metadata is decoded; page data between the magics is not touched.
///
/// Errors (deterministic, `parquet: ` prefixed; byte offsets in the
/// compact-protocol and metadata failures):
///   * "parquet: file too small" / "parquet: bad header magic" /
///     "parquet: bad footer magic";
///   * "parquet: footer length out of bounds (len=N)";
///   * "parquet: truncated varint at offset N" / "parquet: varint too long
///     at offset N" / "parquet: varint overflow at offset N";
///   * "parquet: truncated input at offset N" / "parquet: unknown compact
///     type N at offset M" / "parquet: invalid compact bool value N at
///     offset M" / "parquet: binary length out of bounds at offset N" /
///     "parquet: oversized collection at offset N" / "parquet: nesting
///     depth exceeds limit of 64 at offset N";
///   * "parquet: string contains nul at offset N" / "parquet: invalid
///     utf-8 at offset N";
///   * "parquet: unexpected list element type N at offset M";
///   * "parquet: trailing data in metadata at offset N";
///   * "parquet: schema element count does not match num_children" /
///     "parquet: schema element has negative num_children".
///
/// A metadata struct missing a field that Thrift declares required is
/// accepted with that field's default (0 / empty); real writers always set
/// them, and leniency keeps forward compatibility. Complexity: O(metadata
/// bytes + schema elements + chunks).
pub fn parquet_parse(buffer: &Vec[UInt8]) -> Result[ParquetFile, Str] {
  let total = buffer.len();
  if total < 12 {
    return _err_file("parquet: file too small");
  }
  if _byte(buffer, 0) != _MAGIC_P || _byte(buffer, 1) != _MAGIC_A || _byte(buffer, 2) != _MAGIC_R || _byte(buffer, 3) != _MAGIC_1 {
    return _err_file("parquet: bad header magic");
  }
  if _byte(buffer, total - 4) != _MAGIC_P || _byte(buffer, total - 3) != _MAGIC_A || _byte(buffer, total - 2) != _MAGIC_R || _byte(buffer, total - 1) != _MAGIC_1 {
    return _err_file("parquet: bad footer magic");
  }
  let footer_len = _byte(buffer, total - 8) + _byte(buffer, total - 7) * 256 + _byte(buffer, total - 6) * 65536 + _byte(buffer, total - 5) * 16777216;
  if footer_len > total - 12 {
    return _err_file("parquet: footer length out of bounds (len=" + convert.int_to_string(footer_len) + ")");
  }
  let metadata_start = total - 8 - footer_len;
  var f = ParquetFile{
    file_length: total;
    footer_len: footer_len;
    metadata_start: metadata_start;
    version: 0;
    num_rows: 0;
    created_by: "";
    created_by_present: 0;
    s_name: Vec[Str].new();
    s_type: Vec[Int].new();
    s_type_present: Vec[Int].new();
    s_type_length: Vec[Int].new();
    s_type_length_present: Vec[Int].new();
    s_repetition: Vec[Int].new();
    s_repetition_present: Vec[Int].new();
    s_num_children: Vec[Int].new();
    s_num_children_present: Vec[Int].new();
    s_converted: Vec[Int].new();
    s_converted_present: Vec[Int].new();
    s_scale: Vec[Int].new();
    s_scale_present: Vec[Int].new();
    s_precision: Vec[Int].new();
    s_precision_present: Vec[Int].new();
    s_field_id: Vec[Int].new();
    s_field_id_present: Vec[Int].new();
    s_logical: Vec[Int].new();
    s_logical_present: Vec[Int].new();
    s_parent: Vec[Int].new();
    s_depth: Vec[Int].new();
    s_max_def: Vec[Int].new();
    s_max_rep: Vec[Int].new();
    s_leaf_index: Vec[Int].new();
    s_path: Vec[Str].new();
    rg_cc_off: Vec[Int].new();
    rg_cc_count: Vec[Int].new();
    rg_total_byte_size: Vec[Int].new();
    rg_num_rows: Vec[Int].new();
    rg_file_offset: Vec[Int].new();
    rg_file_offset_present: Vec[Int].new();
    rg_total_compressed_size: Vec[Int].new();
    rg_total_compressed_size_present: Vec[Int].new();
    rg_ordinal: Vec[Int].new();
    rg_ordinal_present: Vec[Int].new();
    rg_sort_off: Vec[Int].new();
    rg_sort_count: Vec[Int].new();
    sort_column_idx: Vec[Int].new();
    sort_descending: Vec[Int].new();
    sort_nulls_first: Vec[Int].new();
    cc_file_path: Vec[Str].new();
    cc_file_path_present: Vec[Int].new();
    cc_file_offset: Vec[Int].new();
    cc_meta_present: Vec[Int].new();
    cc_type: Vec[Int].new();
    cc_type_present: Vec[Int].new();
    cc_codec: Vec[Int].new();
    cc_codec_present: Vec[Int].new();
    cc_num_values: Vec[Int].new();
    cc_num_values_present: Vec[Int].new();
    cc_total_uncompressed_size: Vec[Int].new();
    cc_total_us_present: Vec[Int].new();
    cc_total_compressed_size: Vec[Int].new();
    cc_total_cs_present: Vec[Int].new();
    cc_data_page_offset: Vec[Int].new();
    cc_dpo_present: Vec[Int].new();
    cc_index_page_offset: Vec[Int].new();
    cc_ipo_present: Vec[Int].new();
    cc_dictionary_page_offset: Vec[Int].new();
    cc_dict_po_present: Vec[Int].new();
    cc_oi_off: Vec[Int].new();
    cc_oi_off_present: Vec[Int].new();
    cc_oi_len: Vec[Int].new();
    cc_oi_len_present: Vec[Int].new();
    cc_ci_off: Vec[Int].new();
    cc_ci_off_present: Vec[Int].new();
    cc_ci_len: Vec[Int].new();
    cc_ci_len_present: Vec[Int].new();
    cc_enc_off: Vec[Int].new();
    cc_enc_count: Vec[Int].new();
    enc_pool: Vec[Int].new();
    cc_path_off: Vec[Int].new();
    cc_path_count: Vec[Int].new();
    path_pool: Vec[Str].new();
    cc_kv_off: Vec[Int].new();
    cc_kv_count: Vec[Int].new();
    cc_es_off: Vec[Int].new();
    cc_es_count: Vec[Int].new();
    es_page_type: Vec[Int].new();
    es_encoding: Vec[Int].new();
    es_count: Vec[Int].new();
    file_kv_off: 0;
    file_kv_count: 0;
    kv_key: Vec[Str].new();
    kv_value: Vec[Str].new();
    kv_value_present: Vec[Int].new();
    co_type: Vec[Int].new();
    co_type_present: Vec[Int].new();
    st_present: Vec[Int].new();
    st_max_off: Vec[Int].new();
    st_max_len: Vec[Int].new();
    st_max_present: Vec[Int].new();
    st_min_off: Vec[Int].new();
    st_min_len: Vec[Int].new();
    st_min_present: Vec[Int].new();
    st_maxv_off: Vec[Int].new();
    st_maxv_len: Vec[Int].new();
    st_maxv_present: Vec[Int].new();
    st_minv_off: Vec[Int].new();
    st_minv_len: Vec[Int].new();
    st_minv_present: Vec[Int].new();
    st_null_count: Vec[Int].new();
    st_null_present: Vec[Int].new();
    st_distinct_count: Vec[Int].new();
    st_distinct_present: Vec[Int].new();
    st_max_exact: Vec[Int].new();
    st_max_exact_present: Vec[Int].new();
    st_min_exact: Vec[Int].new();
    st_min_exact_present: Vec[Int].new();
    st_pool: Vec[UInt8].new();
  };
  let data = _copy_bytes(buffer);
  var r = parquet_reader_new_at(data, metadata_start, total - 8);
  let mr = _parse_file_metadata(&mut f, &mut r);
  if !mr.is_ok {
    return _err_file(mr.error);
  }
  if r.pos != r.end {
    return _err_file(_moff("parquet: trailing data in metadata", r.pos));
  }
  let vr = _build_schema(&mut f, metadata_start);
  if !vr.is_ok {
    return _err_file(vr.error);
  }
  return _ok_file(f);
}

// --------------------------------------------------
//  File accessors
// --------------------------------------------------

/// Total length in bytes of the parsed buffer. Complexity: O(1).
pub fn parquet_file_length(f: &ParquetFile) -> Int {
  return f.file_length;
}

/// Footer length in bytes (the FileMetaData region size).
/// Complexity: O(1).
pub fn parquet_footer_length(f: &ParquetFile) -> Int {
  return f.footer_len;
}

/// Absolute offset of the FileMetaData region (`len - 8 - footer_len`).
/// Complexity: O(1).
pub fn parquet_metadata_offset(f: &ParquetFile) -> Int {
  return f.metadata_start;
}

/// FileMetaData.version. Complexity: O(1).
pub fn parquet_version(f: &ParquetFile) -> Int {
  return f.version;
}

/// FileMetaData.num_rows. Complexity: O(1).
pub fn parquet_num_rows(f: &ParquetFile) -> Int {
  return f.num_rows;
}

/// FileMetaData.created_by ("" when absent). Complexity: O(1).
pub fn parquet_created_by(f: &ParquetFile) -> Str {
  return f.created_by;
}

/// True when FileMetaData.created_by was present. Complexity: O(1).
pub fn parquet_created_by_present(f: &ParquetFile) -> Bool {
  if f.created_by_present == 1 {
    return true;
  }
  return false;
}

// Shared bounds check for schema indices.
fn _schema_ready(f: &ParquetFile, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.s_name.len() {
    return _err_int("parquet: schema index out of range");
  }
  return _ok_int(0);
}

/// Number of SchemaElement entries (including the root).
/// Complexity: O(1).
pub fn parquet_schema_count(f: &ParquetFile) -> Int {
  return f.s_name.len();
}

/// Number of leaf columns (schema elements with no children).
/// Complexity: O(schema elements).
pub fn parquet_schema_leaf_count(f: &ParquetFile) -> Int {
  var count = 0;
  var i = 0;
  while i < f.s_leaf_index.len() {
    let li: Int = f.s_leaf_index[i];
    if li >= 0 {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

/// Name of schema element `i`. Complexity: O(1).
pub fn parquet_schema_name(f: &ParquetFile, i: Int) -> Result[Str, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_str(r.error);
  }
  let names: Vec[Str] = f.s_name;
  let s: Str = names[i];
  return _ok_str(s);
}

/// Physical type code of schema element `i` (see
/// `parquet_schema_type_name`; 0 with `parquet_schema_type_present` false
/// for group nodes). Complexity: O(1).
pub fn parquet_schema_type(f: &ParquetFile, i: Int) -> Result[Int, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.s_type;
  let x: Int = v[i];
  return _ok_int(x);
}

/// True when schema element `i` carried a Type field.
/// Complexity: O(1).
pub fn parquet_schema_type_present(f: &ParquetFile, i: Int) -> Result[Bool, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let v: Vec[Int] = f.s_type_present;
  let x: Int = v[i];
  if x == 1 {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// Documented name of a Type code ("unknown" beyond
/// FIXED_LEN_BYTE_ARRAY). Complexity: O(1).
pub fn parquet_schema_type_name(t: Int) -> Str {
  if t == 0 {
    return "BOOLEAN";
  }
  if t == 1 {
    return "INT32";
  }
  if t == 2 {
    return "INT64";
  }
  if t == 3 {
    return "INT96";
  }
  if t == 4 {
    return "FLOAT";
  }
  if t == 5 {
    return "DOUBLE";
  }
  if t == 6 {
    return "BYTE_ARRAY";
  }
  if t == 7 {
    return "FIXED_LEN_BYTE_ARRAY";
  }
  return "unknown";
}

/// Type_length of schema element `i` (0 when absent).
/// Complexity: O(1).
pub fn parquet_schema_type_length(f: &ParquetFile, i: Int) -> Result[Int, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.s_type_length;
  let x: Int = v[i];
  return _ok_int(x);
}

/// Repetition code of schema element `i` (see
/// `parquet_schema_repetition_name`; 0 REQUIRED plus presence). The root
/// normally has no repetition field.
/// Complexity: O(1).
pub fn parquet_schema_repetition(f: &ParquetFile, i: Int) -> Result[Int, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.s_repetition;
  let x: Int = v[i];
  return _ok_int(x);
}

/// True when schema element `i` carried a repetition_type field.
/// Complexity: O(1).
pub fn parquet_schema_repetition_present(f: &ParquetFile, i: Int) -> Result[Bool, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let v: Vec[Int] = f.s_repetition_present;
  let x: Int = v[i];
  if x == 1 {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// Documented name of a FieldRepetitionType code ("unknown" beyond
/// REPEATED). Complexity: O(1).
pub fn parquet_schema_repetition_name(rep: Int) -> Str {
  if rep == 0 {
    return "REQUIRED";
  }
  if rep == 1 {
    return "OPTIONAL";
  }
  if rep == 2 {
    return "REPEATED";
  }
  return "unknown";
}

/// num_children of schema element `i` (0 when absent).
/// Complexity: O(1).
pub fn parquet_schema_num_children(f: &ParquetFile, i: Int) -> Result[Int, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.s_num_children;
  let x: Int = v[i];
  return _ok_int(x);
}

/// ConvertedType code of schema element `i` (see
/// `parquet_converted_type_name`; 0 when absent).
/// Complexity: O(1).
pub fn parquet_schema_converted_type(f: &ParquetFile, i: Int) -> Result[Int, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.s_converted;
  let x: Int = v[i];
  return _ok_int(x);
}

/// True when schema element `i` carried a converted_type field.
/// Complexity: O(1).
pub fn parquet_schema_converted_present(f: &ParquetFile, i: Int) -> Result[Bool, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let v: Vec[Int] = f.s_converted_present;
  let x: Int = v[i];
  if x == 1 {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// Documented name of a ConvertedType code ("unknown" beyond INTERVAL).
/// Complexity: O(1).
pub fn parquet_converted_type_name(c: Int) -> Str {
  if c == 0 {
    return "UTF8";
  }
  if c == 1 {
    return "MAP";
  }
  if c == 2 {
    return "MAP_KEY_VALUE";
  }
  if c == 3 {
    return "LIST";
  }
  if c == 4 {
    return "ENUM";
  }
  if c == 5 {
    return "DECIMAL";
  }
  if c == 6 {
    return "DATE";
  }
  if c == 7 {
    return "TIME_MILLIS";
  }
  if c == 8 {
    return "TIME_MICROS";
  }
  if c == 9 {
    return "TIMESTAMP_MILLIS";
  }
  if c == 10 {
    return "TIMESTAMP_MICROS";
  }
  if c == 11 {
    return "UINT_8";
  }
  if c == 12 {
    return "UINT_16";
  }
  if c == 13 {
    return "UINT_32";
  }
  if c == 14 {
    return "UINT_64";
  }
  if c == 15 {
    return "INT_8";
  }
  if c == 16 {
    return "INT_16";
  }
  if c == 17 {
    return "INT_32";
  }
  if c == 18 {
    return "INT_64";
  }
  if c == 19 {
    return "JSON";
  }
  if c == 20 {
    return "BSON";
  }
  if c == 21 {
    return "INTERVAL";
  }
  return "unknown";
}

/// scale of schema element `i` (0 when absent; DECIMAL).
/// Complexity: O(1).
pub fn parquet_schema_scale(f: &ParquetFile, i: Int) -> Result[Int, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.s_scale;
  let x: Int = v[i];
  return _ok_int(x);
}

/// precision of schema element `i` (0 when absent; DECIMAL).
/// Complexity: O(1).
pub fn parquet_schema_precision(f: &ParquetFile, i: Int) -> Result[Int, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.s_precision;
  let x: Int = v[i];
  return _ok_int(x);
}

/// field_id of schema element `i` (0 when absent).
/// Complexity: O(1).
pub fn parquet_schema_field_id(f: &ParquetFile, i: Int) -> Result[Int, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.s_field_id;
  let x: Int = v[i];
  return _ok_int(x);
}

/// LogicalType union member id of schema element `i` (0 when absent; see
/// `parquet_logical_type_name`, unknown members preserved raw).
/// Complexity: O(1).
pub fn parquet_schema_logical_type(f: &ParquetFile, i: Int) -> Result[Int, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.s_logical;
  let x: Int = v[i];
  return _ok_int(x);
}

/// True when schema element `i` carried a logicalType union.
/// Complexity: O(1).
pub fn parquet_schema_logical_present(f: &ParquetFile, i: Int) -> Result[Bool, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let v: Vec[Int] = f.s_logical_present;
  let x: Int = v[i];
  if x == 1 {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// Documented name of a LogicalType union member id ("unknown" beyond
/// FILE). Complexity: O(1).
pub fn parquet_logical_type_name(m: Int) -> Str {
  if m == 1 {
    return "STRING";
  }
  if m == 2 {
    return "MAP";
  }
  if m == 3 {
    return "LIST";
  }
  if m == 4 {
    return "ENUM";
  }
  if m == 5 {
    return "DECIMAL";
  }
  if m == 6 {
    return "DATE";
  }
  if m == 7 {
    return "TIME";
  }
  if m == 8 {
    return "TIMESTAMP";
  }
  if m == 10 {
    return "INTEGER";
  }
  if m == 11 {
    return "UNKNOWN";
  }
  if m == 12 {
    return "JSON";
  }
  if m == 13 {
    return "BSON";
  }
  if m == 14 {
    return "UUID";
  }
  if m == 15 {
    return "FLOAT16";
  }
  if m == 16 {
    return "VARIANT";
  }
  if m == 17 {
    return "GEOMETRY";
  }
  if m == 18 {
    return "GEOGRAPHY";
  }
  if m == 19 {
    return "FILE";
  }
  return "unknown";
}

/// Parent schema index of element `i` (-1 for the root).
/// Complexity: O(1).
pub fn parquet_schema_parent(f: &ParquetFile, i: Int) -> Result[Int, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.s_parent;
  let x: Int = v[i];
  return _ok_int(x);
}

/// Depth of element `i` in the schema tree (root = 0).
/// Complexity: O(1).
pub fn parquet_schema_depth(f: &ParquetFile, i: Int) -> Result[Int, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.s_depth;
  let x: Int = v[i];
  return _ok_int(x);
}

/// Dotted path of element `i` built from the element names ("id" for a
/// root child, "a.b" deeper; "" for the root itself). These are the parts
/// that ColumnMetaData.path_in_schema lists.
/// Complexity: O(path bytes).
pub fn parquet_schema_path(f: &ParquetFile, i: Int) -> Result[Str, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_str(r.error);
  }
  let v: Vec[Str] = f.s_path;
  let s: Str = v[i];
  return _ok_str(s);
}

/// Computed maximum definition level of element `i` (OPTIONAL and REPEATED
/// ancestors each add 1). Complexity: O(1).
pub fn parquet_schema_max_definition_level(f: &ParquetFile, i: Int) -> Result[Int, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.s_max_def;
  let x: Int = v[i];
  return _ok_int(x);
}

/// Computed maximum repetition level of element `i` (REPEATED ancestors
/// each add 1). Complexity: O(1).
pub fn parquet_schema_max_repetition_level(f: &ParquetFile, i: Int) -> Result[Int, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.s_max_rep;
  let x: Int = v[i];
  return _ok_int(x);
}

/// True when element `i` is a leaf (num_children absent or 0).
/// Complexity: O(1).
pub fn parquet_schema_is_leaf(f: &ParquetFile, i: Int) -> Result[Bool, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let v: Vec[Int] = f.s_leaf_index;
  let x: Int = v[i];
  if x >= 0 {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// Leaf ordinal of element `i` (-1 for group nodes); leaf ordinals are the
/// order used by RowGroup.columns. Complexity: O(1).
pub fn parquet_schema_leaf_index(f: &ParquetFile, i: Int) -> Result[Int, Str] {
  let r = _schema_ready(f, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.s_leaf_index;
  let x: Int = v[i];
  return _ok_int(x);
}

/// First schema index whose computed dotted path equals `path`, or -1 when
/// none does. Complexity: O(schema elements * path length).
pub fn parquet_schema_find_path(f: &ParquetFile, path: Str) -> Int {
  var i = 0;
  while i < f.s_path.len() {
    let v: Vec[Str] = f.s_path;
    let p: Str = v[i];
    if compare.str_compare(p, path) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Row group accessors
// --------------------------------------------------

// Shared bounds check for row-group indices.
fn _rg_ready(f: &ParquetFile, g: Int) -> Result[Int, Str] {
  if g < 0 || g >= f.rg_num_rows.len() {
    return _err_int("parquet: row group index out of range");
  }
  return _ok_int(0);
}

/// Number of RowGroup entries. Complexity: O(1).
pub fn parquet_row_group_count(f: &ParquetFile) -> Int {
  return f.rg_num_rows.len();
}

/// num_rows of row group `g`. Complexity: O(1).
pub fn parquet_row_group_num_rows(f: &ParquetFile, g: Int) -> Result[Int, Str] {
  let r = _rg_ready(f, g);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.rg_num_rows;
  let x: Int = v[g];
  return _ok_int(x);
}

/// total_byte_size of row group `g`. Complexity: O(1).
pub fn parquet_row_group_total_byte_size(f: &ParquetFile, g: Int) -> Result[Int, Str] {
  let r = _rg_ready(f, g);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.rg_total_byte_size;
  let x: Int = v[g];
  return _ok_int(x);
}

/// file_offset of row group `g` (0 when absent).
/// Complexity: O(1).
pub fn parquet_row_group_file_offset(f: &ParquetFile, g: Int) -> Result[Int, Str] {
  let r = _rg_ready(f, g);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.rg_file_offset;
  let x: Int = v[g];
  return _ok_int(x);
}

/// True when row group `g` carried file_offset. Complexity: O(1).
pub fn parquet_row_group_file_offset_present(f: &ParquetFile, g: Int) -> Result[Bool, Str] {
  let r = _rg_ready(f, g);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let v: Vec[Int] = f.rg_file_offset_present;
  let x: Int = v[g];
  if x == 1 {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// total_compressed_size of row group `g` (0 when absent).
/// Complexity: O(1).
pub fn parquet_row_group_total_compressed_size(f: &ParquetFile, g: Int) -> Result[Int, Str] {
  let r = _rg_ready(f, g);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.rg_total_compressed_size;
  let x: Int = v[g];
  return _ok_int(x);
}

/// ordinal of row group `g` (0 when absent). Complexity: O(1).
pub fn parquet_row_group_ordinal(f: &ParquetFile, g: Int) -> Result[Int, Str] {
  let r = _rg_ready(f, g);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.rg_ordinal;
  let x: Int = v[g];
  return _ok_int(x);
}

/// Number of ColumnChunk entries in row group `g`.
/// Complexity: O(1).
pub fn parquet_row_group_column_count(f: &ParquetFile, g: Int) -> Result[Int, Str] {
  let r = _rg_ready(f, g);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.rg_cc_count;
  let x: Int = v[g];
  return _ok_int(x);
}

/// Global column-chunk index of column `c` in row group `g`; feed it to
/// the parquet_chunk_* accessors. Complexity: O(1).
pub fn parquet_row_group_column(f: &ParquetFile, g: Int, c: Int) -> Result[Int, Str] {
  let r = _rg_ready(f, g);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let cntv: Vec[Int] = f.rg_cc_count;
  let count: Int = cntv[g];
  if c < 0 || c >= count {
    return _err_int("parquet: row group column index out of range");
  }
  let offv: Vec[Int] = f.rg_cc_off;
  let off: Int = offv[g];
  return _ok_int(off + c);
}

/// Number of SortingColumn entries in row group `g`.
/// Complexity: O(1).
pub fn parquet_row_group_sorting_count(f: &ParquetFile, g: Int) -> Result[Int, Str] {
  let r = _rg_ready(f, g);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.rg_sort_count;
  let x: Int = v[g];
  return _ok_int(x);
}

// Shared bounds check for sorting-column indices.
fn _sort_ready(f: &ParquetFile, g: Int, s: Int) -> Result[Int, Str] {
  let r = _rg_ready(f, g);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let cntv: Vec[Int] = f.rg_sort_count;
  let count: Int = cntv[g];
  if s < 0 || s >= count {
    return _err_int("parquet: sorting column index out of range");
  }
  return _ok_int(0);
}

// Global sorting index of entry `s` in row group `g` (preconditions
// checked by the caller).
fn _sort_global(f: &ParquetFile, g: Int, s: Int) -> Int {
  let offv: Vec[Int] = f.rg_sort_off;
  let off: Int = offv[g];
  return off + s;
}

/// column_idx of sorting entry `s` in row group `g`.
/// Complexity: O(1).
pub fn parquet_sorting_column_idx(f: &ParquetFile, g: Int, s: Int) -> Result[Int, Str] {
  let r = _sort_ready(f, g, s);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let idx = _sort_global(f, g, s);
  let v: Vec[Int] = f.sort_column_idx;
  let x: Int = v[idx];
  return _ok_int(x);
}

/// True when sorting entry `s` in row group `g` is descending.
/// Complexity: O(1).
pub fn parquet_sorting_column_descending(f: &ParquetFile, g: Int, s: Int) -> Result[Bool, Str] {
  let r = _sort_ready(f, g, s);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let idx = _sort_global(f, g, s);
  let v: Vec[Int] = f.sort_descending;
  let x: Int = v[idx];
  if x == 1 {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// True when sorting entry `s` in row group `g` puts nulls first.
/// Complexity: O(1).
pub fn parquet_sorting_column_nulls_first(f: &ParquetFile, g: Int, s: Int) -> Result[Bool, Str] {
  let r = _sort_ready(f, g, s);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let idx = _sort_global(f, g, s);
  let v: Vec[Int] = f.sort_nulls_first;
  let x: Int = v[idx];
  if x == 1 {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// --------------------------------------------------
//  Column chunk accessors
// --------------------------------------------------

// Shared bounds check for global column-chunk indices.
fn _chunk_ready(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  if c < 0 || c >= f.cc_file_offset.len() {
    return _err_int("parquet: column chunk index out of range");
  }
  return _ok_int(0);
}

/// Total number of column chunks across every row group.
/// Complexity: O(1).
pub fn parquet_chunk_count(f: &ParquetFile) -> Int {
  return f.cc_file_offset.len();
}

/// ColumnChunk.file_path of chunk `c`; Err when the chunk has no
/// file_path. Complexity: O(1).
pub fn parquet_chunk_file_path(f: &ParquetFile, c: Int) -> Result[Str, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_str(r.error);
  }
  let pv: Vec[Int] = f.cc_file_path_present;
  let p: Int = pv[c];
  if p == 0 {
    return _err_str("parquet: column chunk has no file_path");
  }
  let v: Vec[Str] = f.cc_file_path;
  let s: Str = v[c];
  return _ok_str(s);
}

/// True when chunk `c` carried file_path. Complexity: O(1).
pub fn parquet_chunk_file_path_present(f: &ParquetFile, c: Int) -> Result[Bool, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let v: Vec[Int] = f.cc_file_path_present;
  let x: Int = v[c];
  if x == 1 {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// ColumnChunk.file_offset of chunk `c`. Complexity: O(1).
pub fn parquet_chunk_file_offset(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.cc_file_offset;
  let x: Int = v[c];
  return _ok_int(x);
}

/// True when chunk `c` carried a meta_data struct. Complexity: O(1).
pub fn parquet_chunk_meta_present(f: &ParquetFile, c: Int) -> Result[Bool, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let v: Vec[Int] = f.cc_meta_present;
  let x: Int = v[c];
  if x == 1 {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// ColumnMetaData.type of chunk `c` (see `parquet_schema_type_name`).
/// Complexity: O(1).
pub fn parquet_chunk_type(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.cc_type;
  let x: Int = v[c];
  return _ok_int(x);
}

/// CompressionCodec code of chunk `c` (see `parquet_codec_name`).
/// Complexity: O(1).
pub fn parquet_chunk_codec(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.cc_codec;
  let x: Int = v[c];
  return _ok_int(x);
}

/// ColumnMetaData.num_values of chunk `c`. Complexity: O(1).
pub fn parquet_chunk_num_values(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.cc_num_values;
  let x: Int = v[c];
  return _ok_int(x);
}

/// ColumnMetaData.total_uncompressed_size of chunk `c`.
/// Complexity: O(1).
pub fn parquet_chunk_total_uncompressed_size(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.cc_total_uncompressed_size;
  let x: Int = v[c];
  return _ok_int(x);
}

/// ColumnMetaData.total_compressed_size of chunk `c`.
/// Complexity: O(1).
pub fn parquet_chunk_total_compressed_size(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.cc_total_compressed_size;
  let x: Int = v[c];
  return _ok_int(x);
}

/// ColumnMetaData.data_page_offset of chunk `c`. Complexity: O(1).
pub fn parquet_chunk_data_page_offset(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.cc_data_page_offset;
  let x: Int = v[c];
  return _ok_int(x);
}

/// ColumnMetaData.index_page_offset of chunk `c`; Err when absent.
/// Complexity: O(1).
pub fn parquet_chunk_index_page_offset(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let pv: Vec[Int] = f.cc_ipo_present;
  let p: Int = pv[c];
  if p == 0 {
    return _err_int("parquet: column chunk has no index_page_offset");
  }
  let v: Vec[Int] = f.cc_index_page_offset;
  let x: Int = v[c];
  return _ok_int(x);
}

/// ColumnMetaData.dictionary_page_offset of chunk `c`; Err when absent.
/// Complexity: O(1).
pub fn parquet_chunk_dictionary_page_offset(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let pv: Vec[Int] = f.cc_dict_po_present;
  let p: Int = pv[c];
  if p == 0 {
    return _err_int("parquet: column chunk has no dictionary_page_offset");
  }
  let v: Vec[Int] = f.cc_dictionary_page_offset;
  let x: Int = v[c];
  return _ok_int(x);
}

/// OffsetIndex offset of chunk `c` (0 when absent).
/// Complexity: O(1).
pub fn parquet_chunk_offset_index_offset(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.cc_oi_off;
  let x: Int = v[c];
  return _ok_int(x);
}

/// OffsetIndex length of chunk `c` (0 when absent).
/// Complexity: O(1).
pub fn parquet_chunk_offset_index_length(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.cc_oi_len;
  let x: Int = v[c];
  return _ok_int(x);
}

/// ColumnIndex offset of chunk `c` (0 when absent).
/// Complexity: O(1).
pub fn parquet_chunk_column_index_offset(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.cc_ci_off;
  let x: Int = v[c];
  return _ok_int(x);
}

/// ColumnIndex length of chunk `c` (0 when absent).
/// Complexity: O(1).
pub fn parquet_chunk_column_index_length(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.cc_ci_len;
  let x: Int = v[c];
  return _ok_int(x);
}

/// Number of ColumnMetaData.encodings entries of chunk `c`.
/// Complexity: O(1).
pub fn parquet_chunk_encoding_count(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.cc_enc_count;
  let x: Int = v[c];
  return _ok_int(x);
}

/// Encoding code `e` of chunk `c` (raw; see `parquet_encoding_name`).
/// Complexity: O(1).
pub fn parquet_chunk_encoding(f: &ParquetFile, c: Int, e: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let cntv: Vec[Int] = f.cc_enc_count;
  let count: Int = cntv[c];
  if e < 0 || e >= count {
    return _err_int("parquet: encoding index out of range");
  }
  let offv: Vec[Int] = f.cc_enc_off;
  let off: Int = offv[c];
  let pool: Vec[Int] = f.enc_pool;
  let x: Int = pool[off + e];
  return _ok_int(x);
}

/// Number of path_in_schema parts of chunk `c`.
/// Complexity: O(1).
pub fn parquet_chunk_path_count(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.cc_path_count;
  let x: Int = v[c];
  return _ok_int(x);
}

/// path_in_schema part `p` of chunk `c`. Complexity: O(1).
pub fn parquet_chunk_path(f: &ParquetFile, c: Int, p: Int) -> Result[Str, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_str(r.error);
  }
  let cntv: Vec[Int] = f.cc_path_count;
  let count: Int = cntv[c];
  if p < 0 || p >= count {
    return _err_str("parquet: path index out of range");
  }
  let offv: Vec[Int] = f.cc_path_off;
  let off: Int = offv[c];
  let pool: Vec[Str] = f.path_pool;
  let s: Str = pool[off + p];
  return _ok_str(s);
}

/// path_in_schema of chunk `c` joined with "."; Err when the chunk has an
/// empty path. Complexity: O(path bytes).
pub fn parquet_chunk_path_joined(f: &ParquetFile, c: Int) -> Result[Str, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_str(r.error);
  }
  let cntv: Vec[Int] = f.cc_path_count;
  let count: Int = cntv[c];
  if count == 0 {
    return _err_str("parquet: column chunk has no path_in_schema");
  }
  let offv: Vec[Int] = f.cc_path_off;
  let off: Int = offv[c];
  var s = "";
  var i = 0;
  while i < count {
    let pool: Vec[Str] = f.path_pool;
    let part: Str = pool[off + i];
    if i == 0 {
      s = part;
    } else {
      s = s + "." + part;
    }
    i = i + 1;
  }
  return _ok_str(s);
}

/// Number of ColumnMetaData.key_value_metadata entries of chunk `c`.
/// Complexity: O(1).
pub fn parquet_chunk_key_value_count(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.cc_kv_count;
  let x: Int = v[c];
  return _ok_int(x);
}

/// key of key/value entry `i` in chunk `c`. Complexity: O(1).
pub fn parquet_chunk_key_value_key(f: &ParquetFile, c: Int, i: Int) -> Result[Str, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_str(r.error);
  }
  let cntv: Vec[Int] = f.cc_kv_count;
  let count: Int = cntv[c];
  if i < 0 || i >= count {
    return _err_str("parquet: key value index out of range");
  }
  let offv: Vec[Int] = f.cc_kv_off;
  let off: Int = offv[c];
  let pool: Vec[Str] = f.kv_key;
  let s: Str = pool[off + i];
  return _ok_str(s);
}

/// value of key/value entry `i` in chunk `c`; Err when the entry has no
/// value. Complexity: O(1).
pub fn parquet_chunk_key_value_value(f: &ParquetFile, c: Int, i: Int) -> Result[Str, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_str(r.error);
  }
  let cntv: Vec[Int] = f.cc_kv_count;
  let count: Int = cntv[c];
  if i < 0 || i >= count {
    return _err_str("parquet: key value index out of range");
  }
  let offv: Vec[Int] = f.cc_kv_off;
  let off: Int = offv[c];
  let pv: Vec[Int] = f.kv_value_present;
  let p: Int = pv[off + i];
  if p == 0 {
    return _err_str("parquet: key value entry has no value");
  }
  let pool: Vec[Str] = f.kv_value;
  let s: Str = pool[off + i];
  return _ok_str(s);
}

/// Number of PageEncodingStats entries of chunk `c`.
/// Complexity: O(1).
pub fn parquet_chunk_encoding_stats_count(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let v: Vec[Int] = f.cc_es_count;
  let x: Int = v[c];
  return _ok_int(x);
}

// Shared bounds check for encoding-stats indices; returns the global index.
fn _es_ready(f: &ParquetFile, c: Int, i: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let cntv: Vec[Int] = f.cc_es_count;
  let count: Int = cntv[c];
  if i < 0 || i >= count {
    return _err_int("parquet: encoding stats index out of range");
  }
  let offv: Vec[Int] = f.cc_es_off;
  let off: Int = offv[c];
  return _ok_int(off + i);
}

/// PageEncodingStats.page_type of entry `i` in chunk `c` (see
/// `parquet_page_type_name`). Complexity: O(1).
pub fn parquet_chunk_encoding_stat_page_type(f: &ParquetFile, c: Int, i: Int) -> Result[Int, Str] {
  let r = _es_ready(f, c, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let idx: Int = r.value;
  let v: Vec[Int] = f.es_page_type;
  let x: Int = v[idx];
  return _ok_int(x);
}

/// PageEncodingStats.encoding of entry `i` in chunk `c`.
/// Complexity: O(1).
pub fn parquet_chunk_encoding_stat_encoding(f: &ParquetFile, c: Int, i: Int) -> Result[Int, Str] {
  let r = _es_ready(f, c, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let idx: Int = r.value;
  let v: Vec[Int] = f.es_encoding;
  let x: Int = v[idx];
  return _ok_int(x);
}

/// PageEncodingStats.count of entry `i` in chunk `c`.
/// Complexity: O(1).
pub fn parquet_chunk_encoding_stat_count(f: &ParquetFile, c: Int, i: Int) -> Result[Int, Str] {
  let r = _es_ready(f, c, i);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let idx: Int = r.value;
  let v: Vec[Int] = f.es_count;
  let x: Int = v[idx];
  return _ok_int(x);
}

// --------------------------------------------------
//  Statistics accessors
// --------------------------------------------------

// Copy `n` bytes of the shared statistics pool starting at `off`.
fn _slice(f: &ParquetFile, off: Int, n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let b: UInt8 = f.st_pool[off + i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

// Deterministic "which" tag: 1 max, 2 min, 5 max_value, 6 min_value.
fn _stat_tag(which: Int) -> Str {
  if which == 1 {
    return "max";
  }
  if which == 2 {
    return "min";
  }
  if which == 5 {
    return "max_value";
  }
  return "min_value";
}

// The not-present error for statistic `which` of chunk `c`.
fn _stat_missing(c: Int, which: Int) -> Str {
  return "parquet: statistic not present (chunk=" + convert.int_to_string(c) + ", stat=" + _stat_tag(which) + ")";
}

// Raw bytes of statistic `which` of chunk `c`.
fn _chunk_stat_bytes(f: &ParquetFile, c: Int, which: Int) -> Result[Vec[UInt8], Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_bytes(r.error);
  }
  var pres = 0;
  if which == 1 {
    let pv: Vec[Int] = f.st_max_present;
    pres = pv[c];
  } else if which == 2 {
    let pv2: Vec[Int] = f.st_min_present;
    pres = pv2[c];
  } else if which == 5 {
    let pv3: Vec[Int] = f.st_maxv_present;
    pres = pv3[c];
  } else {
    let pv4: Vec[Int] = f.st_minv_present;
    pres = pv4[c];
  }
  if pres == 0 {
    return _err_bytes(_stat_missing(c, which));
  }
  var off = 0;
  var n = 0;
  if which == 1 {
    let ov: Vec[Int] = f.st_max_off;
    let lv: Vec[Int] = f.st_max_len;
    off = ov[c];
    n = lv[c];
  } else if which == 2 {
    let ov2: Vec[Int] = f.st_min_off;
    let lv2: Vec[Int] = f.st_min_len;
    off = ov2[c];
    n = lv2[c];
  } else if which == 5 {
    let ov3: Vec[Int] = f.st_maxv_off;
    let lv3: Vec[Int] = f.st_maxv_len;
    off = ov3[c];
    n = lv3[c];
  } else {
    let ov4: Vec[Int] = f.st_minv_off;
    let lv4: Vec[Int] = f.st_minv_len;
    off = ov4[c];
    n = lv4[c];
  }
  return _ok_bytes(_slice(f, off, n));
}

/// True when chunk `c` carried a Statistics struct. Complexity: O(1).
pub fn parquet_chunk_stat_present(f: &ParquetFile, c: Int) -> Result[Bool, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let v: Vec[Int] = f.st_present;
  let x: Int = v[c];
  if x == 1 {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// Deprecated Statistics.max raw bytes of chunk `c` (PLAIN-encoded value
/// without a length prefix); Err when absent. Complexity: O(bytes).
pub fn parquet_chunk_stat_max(f: &ParquetFile, c: Int) -> Result[Vec[UInt8], Str] {
  return _chunk_stat_bytes(f, c, 1);
}

/// Deprecated Statistics.min raw bytes of chunk `c`; Err when absent.
/// Complexity: O(bytes).
pub fn parquet_chunk_stat_min(f: &ParquetFile, c: Int) -> Result[Vec[UInt8], Str] {
  return _chunk_stat_bytes(f, c, 2);
}

/// Statistics.max_value raw bytes of chunk `c`; Err when absent.
/// Complexity: O(bytes).
pub fn parquet_chunk_stat_max_value(f: &ParquetFile, c: Int) -> Result[Vec[UInt8], Str] {
  return _chunk_stat_bytes(f, c, 5);
}

/// Statistics.min_value raw bytes of chunk `c`; Err when absent.
/// Complexity: O(bytes).
pub fn parquet_chunk_stat_min_value(f: &ParquetFile, c: Int) -> Result[Vec[UInt8], Str] {
  return _chunk_stat_bytes(f, c, 6);
}

/// Statistics.null_count of chunk `c`; Err when absent.
/// Complexity: O(1).
pub fn parquet_chunk_stat_null_count(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let pv: Vec[Int] = f.st_null_present;
  let p: Int = pv[c];
  if p == 0 {
    return _err_int("parquet: statistic not present (chunk=" + convert.int_to_string(c) + ", stat=null_count)");
  }
  let v: Vec[Int] = f.st_null_count;
  let x: Int = v[c];
  return _ok_int(x);
}

/// Statistics.distinct_count of chunk `c`; Err when absent.
/// Complexity: O(1).
pub fn parquet_chunk_stat_distinct_count(f: &ParquetFile, c: Int) -> Result[Int, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_int(r.error);
  }
  let pv: Vec[Int] = f.st_distinct_present;
  let p: Int = pv[c];
  if p == 0 {
    return _err_int("parquet: statistic not present (chunk=" + convert.int_to_string(c) + ", stat=distinct_count)");
  }
  let v: Vec[Int] = f.st_distinct_count;
  let x: Int = v[c];
  return _ok_int(x);
}

/// Statistics.is_max_value_exact of chunk `c`; Err when absent.
/// Complexity: O(1).
pub fn parquet_chunk_stat_max_exact(f: &ParquetFile, c: Int) -> Result[Bool, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let pv: Vec[Int] = f.st_max_exact_present;
  let p: Int = pv[c];
  if p == 0 {
    return _err_bool("parquet: statistic not present (chunk=" + convert.int_to_string(c) + ", stat=is_max_value_exact)");
  }
  let v: Vec[Int] = f.st_max_exact;
  let x: Int = v[c];
  if x == 1 {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// Statistics.is_min_value_exact of chunk `c`; Err when absent.
/// Complexity: O(1).
pub fn parquet_chunk_stat_min_exact(f: &ParquetFile, c: Int) -> Result[Bool, Str] {
  let r = _chunk_ready(f, c);
  if !r.is_ok {
    return _err_bool(r.error);
  }
  let pv: Vec[Int] = f.st_min_exact_present;
  let p: Int = pv[c];
  if p == 0 {
    return _err_bool("parquet: statistic not present (chunk=" + convert.int_to_string(c) + ", stat=is_min_value_exact)");
  }
  let v: Vec[Int] = f.st_min_exact;
  let x: Int = v[c];
  if x == 1 {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// --------------------------------------------------
//  File-level key values and column orders
// --------------------------------------------------

/// Number of file-level key_value_metadata entries. Complexity: O(1).
pub fn parquet_file_key_value_count(f: &ParquetFile) -> Int {
  return f.file_kv_count;
}

/// key of file-level key/value entry `i`. Complexity: O(1).
pub fn parquet_file_key_value_key(f: &ParquetFile, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= f.file_kv_count {
    return _err_str("parquet: key value index out of range");
  }
  let pool: Vec[Str] = f.kv_key;
  let s: Str = pool[f.file_kv_off + i];
  return _ok_str(s);
}

/// value of file-level key/value entry `i`; Err when the entry has no
/// value. Complexity: O(1).
pub fn parquet_file_key_value_value(f: &ParquetFile, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= f.file_kv_count {
    return _err_str("parquet: key value index out of range");
  }
  let pv: Vec[Int] = f.kv_value_present;
  let p: Int = pv[f.file_kv_off + i];
  if p == 0 {
    return _err_str("parquet: key value entry has no value");
  }
  let pool: Vec[Str] = f.kv_value;
  let s: Str = pool[f.file_kv_off + i];
  return _ok_str(s);
}

/// Number of FileMetaData.column_orders entries. Complexity: O(1).
pub fn parquet_column_order_count(f: &ParquetFile) -> Int {
  return f.co_type.len();
}

/// ColumnOrder union member id `i` (1 TYPE_ORDER, 2 IEEE_754_TOTAL_ORDER,
/// 3 INT96_TIMESTAMP_ORDER; unknown members preserved raw; 0 when the
/// union was empty). Complexity: O(1).
pub fn parquet_column_order(f: &ParquetFile, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.co_type.len() {
    return _err_int("parquet: column order index out of range");
  }
  let v: Vec[Int] = f.co_type;
  let x: Int = v[i];
  return _ok_int(x);
}

/// Documented name of a ColumnOrder union member id ("unknown" beyond
/// INT96_TIMESTAMP_ORDER). Complexity: O(1).
pub fn parquet_column_order_name(m: Int) -> Str {
  if m == 1 {
    return "TYPE_ORDER";
  }
  if m == 2 {
    return "IEEE_754_TOTAL_ORDER";
  }
  if m == 3 {
    return "INT96_TIMESTAMP_ORDER";
  }
  return "unknown";
}

/// Documented name of an Encoding code ("unknown" beyond ALP and for the
/// retired GROUP_VAR_INT 1). Complexity: O(1).
pub fn parquet_encoding_name(e: Int) -> Str {
  if e == 0 {
    return "PLAIN";
  }
  if e == 2 {
    return "PLAIN_DICTIONARY";
  }
  if e == 3 {
    return "RLE";
  }
  if e == 4 {
    return "BIT_PACKED";
  }
  if e == 5 {
    return "DELTA_BINARY_PACKED";
  }
  if e == 6 {
    return "DELTA_LENGTH_BYTE_ARRAY";
  }
  if e == 7 {
    return "DELTA_BYTE_ARRAY";
  }
  if e == 8 {
    return "RLE_DICTIONARY";
  }
  if e == 9 {
    return "BYTE_STREAM_SPLIT";
  }
  if e == 10 {
    return "ALP";
  }
  return "unknown";
}

/// Documented name of a CompressionCodec code ("unknown" beyond LZ4_RAW).
/// Complexity: O(1).
pub fn parquet_codec_name(c: Int) -> Str {
  if c == 0 {
    return "UNCOMPRESSED";
  }
  if c == 1 {
    return "SNAPPY";
  }
  if c == 2 {
    return "GZIP";
  }
  if c == 3 {
    return "LZO";
  }
  if c == 4 {
    return "BROTLI";
  }
  if c == 5 {
    return "LZ4";
  }
  if c == 6 {
    return "ZSTD";
  }
  if c == 7 {
    return "LZ4_RAW";
  }
  return "unknown";
}

// --------------------------------------------------
//  Page headers
// --------------------------------------------------

// DataPageHeader: 1 num_values, 2 encoding, 3 definition_level_encoding,
// 4 repetition_level_encoding, 5 statistics (recorded as a raw range).
fn _parse_data_page_header(h: &mut ParquetPageHeader, r: &mut ParquetReader) -> Result[Int, Str] {
  var last = 0;
  var go = true;
  while go {
    let fr = parquet_read_field_header(r, last);
    if !fr.is_ok {
      return _err_int(fr.error);
    }
    let fld: ParquetField = fr.value;
    let t: Int = fld.ftype;
    let fid: Int = fld.fid;
    if t == _C_STOP {
      go = false;
    } else if fid == 1 && t == _C_I32 {
      last = fid;
      let zr = parquet_read_zigzag(r);
      if !zr.is_ok {
        return _err_int(zr.error);
      }
      h.dp_num_values = zr.value;
    } else if fid == 2 && t == _C_I32 {
      last = fid;
      let zr2 = parquet_read_zigzag(r);
      if !zr2.is_ok {
        return _err_int(zr2.error);
      }
      h.dp_encoding = zr2.value;
    } else if fid == 3 && t == _C_I32 {
      last = fid;
      let zr3 = parquet_read_zigzag(r);
      if !zr3.is_ok {
        return _err_int(zr3.error);
      }
      h.dp_def_encoding = zr3.value;
    } else if fid == 4 && t == _C_I32 {
      last = fid;
      let zr4 = parquet_read_zigzag(r);
      if !zr4.is_ok {
        return _err_int(zr4.error);
      }
      h.dp_rep_encoding = zr4.value;
    } else if fid == 5 && t == _C_STRUCT {
      last = fid;
      let st = r.pos;
      let sk = _skip_value(r, t, 0);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
      h.dp_stats_present = 1;
      h.dp_stats_offset = st;
      h.dp_stats_end = r.pos;
    } else {
      last = fid;
      let sk2 = _skip_value(r, t, 0);
      if !sk2.is_ok {
        return _err_int(sk2.error);
      }
    }
  }
  return _ok_int(0);
}

// DictionaryPageHeader: 1 num_values, 2 encoding, 3 is_sorted (optional
// bool, value in the field header nibble).
fn _parse_dict_page_header(h: &mut ParquetPageHeader, r: &mut ParquetReader) -> Result[Int, Str] {
  var last = 0;
  var go = true;
  while go {
    let fr = parquet_read_field_header(r, last);
    if !fr.is_ok {
      return _err_int(fr.error);
    }
    let fld: ParquetField = fr.value;
    let t: Int = fld.ftype;
    let fid: Int = fld.fid;
    if t == _C_STOP {
      go = false;
    } else if fid == 1 && t == _C_I32 {
      last = fid;
      let zr = parquet_read_zigzag(r);
      if !zr.is_ok {
        return _err_int(zr.error);
      }
      h.dict_num_values = zr.value;
    } else if fid == 2 && t == _C_I32 {
      last = fid;
      let zr2 = parquet_read_zigzag(r);
      if !zr2.is_ok {
        return _err_int(zr2.error);
      }
      h.dict_encoding = zr2.value;
    } else if fid == 3 && (t == _C_TRUE || t == _C_FALSE) {
      last = fid;
      h.dict_is_sorted = 0;
      if t == _C_TRUE {
        h.dict_is_sorted = 1;
      }
      h.dict_is_sorted_present = 1;
    } else {
      last = fid;
      let sk = _skip_value(r, t, 0);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    }
  }
  return _ok_int(0);
}

// DataPageHeaderV2: 1 num_values, 2 num_nulls, 3 num_rows, 4 encoding,
// 5 definition_levels_byte_length, 6 repetition_levels_byte_length,
// 7 is_compressed (optional bool), 8 statistics (raw range).
fn _parse_data_page_header_v2(h: &mut ParquetPageHeader, r: &mut ParquetReader) -> Result[Int, Str] {
  var last = 0;
  var go = true;
  while go {
    let fr = parquet_read_field_header(r, last);
    if !fr.is_ok {
      return _err_int(fr.error);
    }
    let fld: ParquetField = fr.value;
    let t: Int = fld.ftype;
    let fid: Int = fld.fid;
    if t == _C_STOP {
      go = false;
    } else if fid == 1 && t == _C_I32 {
      last = fid;
      let zr = parquet_read_zigzag(r);
      if !zr.is_ok {
        return _err_int(zr.error);
      }
      h.v2_num_values = zr.value;
    } else if fid == 2 && t == _C_I32 {
      last = fid;
      let zr2 = parquet_read_zigzag(r);
      if !zr2.is_ok {
        return _err_int(zr2.error);
      }
      h.v2_num_nulls = zr2.value;
    } else if fid == 3 && t == _C_I32 {
      last = fid;
      let zr3 = parquet_read_zigzag(r);
      if !zr3.is_ok {
        return _err_int(zr3.error);
      }
      h.v2_num_rows = zr3.value;
    } else if fid == 4 && t == _C_I32 {
      last = fid;
      let zr4 = parquet_read_zigzag(r);
      if !zr4.is_ok {
        return _err_int(zr4.error);
      }
      h.v2_encoding = zr4.value;
    } else if fid == 5 && t == _C_I32 {
      last = fid;
      let zr5 = parquet_read_zigzag(r);
      if !zr5.is_ok {
        return _err_int(zr5.error);
      }
      h.v2_def_len = zr5.value;
    } else if fid == 6 && t == _C_I32 {
      last = fid;
      let zr6 = parquet_read_zigzag(r);
      if !zr6.is_ok {
        return _err_int(zr6.error);
      }
      h.v2_rep_len = zr6.value;
    } else if fid == 7 && (t == _C_TRUE || t == _C_FALSE) {
      last = fid;
      h.v2_is_compressed = 0;
      if t == _C_TRUE {
        h.v2_is_compressed = 1;
      }
      h.v2_is_compressed_present = 1;
    } else if fid == 8 && t == _C_STRUCT {
      last = fid;
      let st = r.pos;
      let sk = _skip_value(r, t, 0);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
      h.v2_stats_present = 1;
      h.v2_stats_offset = st;
      h.v2_stats_end = r.pos;
    } else {
      last = fid;
      let sk2 = _skip_value(r, t, 0);
      if !sk2.is_ok {
        return _err_int(sk2.error);
      }
    }
  }
  return _ok_int(0);
}

// PageHeader: 1 type, 2 uncompressed_page_size, 3 compressed_page_size,
// 4 crc, 5 data_page_header, 6 index_page_header, 7 dictionary_page_header,
// 8 data_page_header_v2. One member header is set in practice; every
// present member is recorded.
fn _parse_page_header_fields(h: &mut ParquetPageHeader, r: &mut ParquetReader) -> Result[Int, Str] {
  var last = 0;
  var go = true;
  while go {
    let fr = parquet_read_field_header(r, last);
    if !fr.is_ok {
      return _err_int(fr.error);
    }
    let fld: ParquetField = fr.value;
    let t: Int = fld.ftype;
    let fid: Int = fld.fid;
    if t == _C_STOP {
      go = false;
    } else if fid == 1 && t == _C_I32 {
      last = fid;
      let zr = parquet_read_zigzag(r);
      if !zr.is_ok {
        return _err_int(zr.error);
      }
      h.ptype = zr.value;
      h.ptype_present = 1;
    } else if fid == 2 && t == _C_I32 {
      last = fid;
      let zr2 = parquet_read_zigzag(r);
      if !zr2.is_ok {
        return _err_int(zr2.error);
      }
      h.uncompressed_page_size = zr2.value;
      h.ups_present = 1;
    } else if fid == 3 && t == _C_I32 {
      last = fid;
      let zr3 = parquet_read_zigzag(r);
      if !zr3.is_ok {
        return _err_int(zr3.error);
      }
      h.compressed_page_size = zr3.value;
      h.cps_present = 1;
    } else if fid == 4 && t == _C_I32 {
      last = fid;
      let zr4 = parquet_read_zigzag(r);
      if !zr4.is_ok {
        return _err_int(zr4.error);
      }
      h.crc = zr4.value;
      h.crc_present = 1;
    } else if fid == 5 && t == _C_STRUCT {
      last = fid;
      h.dp_present = 1;
      let dr = _parse_data_page_header(h, r);
      if !dr.is_ok {
        return _err_int(dr.error);
      }
    } else if fid == 6 && t == _C_STRUCT {
      last = fid;
      h.ix_present = 1;
      let sk = _skip_value(r, t, 0);
      if !sk.is_ok {
        return _err_int(sk.error);
      }
    } else if fid == 7 && t == _C_STRUCT {
      last = fid;
      h.dict_present = 1;
      let dr2 = _parse_dict_page_header(h, r);
      if !dr2.is_ok {
        return _err_int(dr2.error);
      }
    } else if fid == 8 && t == _C_STRUCT {
      last = fid;
      h.v2_present = 1;
      let dr3 = _parse_data_page_header_v2(h, r);
      if !dr3.is_ok {
        return _err_int(dr3.error);
      }
    } else {
      last = fid;
      let sk2 = _skip_value(r, t, 0);
      if !sk2.is_ok {
        return _err_int(sk2.error);
      }
    }
  }
  return _ok_int(0);
}

/// Parse one PageHeader at absolute `offset` of `buffer`.
///
/// Reads exactly the header struct (the page body is not touched);
/// `consumed` on the result is the header's byte length. The `*_present`
/// members record which optional sub-headers were on the wire. Page-level
/// Statistics structs inside DataPageHeader/DataPageHeaderV2 are not
/// decoded: their raw byte range is exposed via the *_stats_offset/
/// *_stats_end accessors. Page type / sub-header mismatches are not
/// enforced (real writers set the matching member).
///
/// Errors: "parquet: page header offset out of range (offset=N)" for a
/// negative or beyond-end offset, otherwise the reader's compact-protocol
/// errors with absolute byte offsets. Complexity: O(header bytes).
pub fn parquet_parse_page_header(buffer: &Vec[UInt8], offset: Int) -> Result[ParquetPageHeader, Str] {
  let total = buffer.len();
  if offset < 0 || offset >= total {
    return _err_ph("parquet: page header offset out of range (offset=" + convert.int_to_string(offset) + ")");
  }
  let data = _copy_bytes(buffer);
  var r = parquet_reader_new_at(data, offset, total);
  var h = ParquetPageHeader{
    ptype: 0;
    ptype_present: 0;
    uncompressed_page_size: 0;
    ups_present: 0;
    compressed_page_size: 0;
    cps_present: 0;
    crc: 0;
    crc_present: 0;
    consumed: 0;
    dp_present: 0;
    dp_num_values: 0;
    dp_encoding: 0;
    dp_def_encoding: 0;
    dp_rep_encoding: 0;
    dp_stats_present: 0;
    dp_stats_offset: 0;
    dp_stats_end: 0;
    ix_present: 0;
    dict_present: 0;
    dict_num_values: 0;
    dict_encoding: 0;
    dict_is_sorted_present: 0;
    dict_is_sorted: 0;
    v2_present: 0;
    v2_num_values: 0;
    v2_num_nulls: 0;
    v2_num_rows: 0;
    v2_encoding: 0;
    v2_def_len: 0;
    v2_rep_len: 0;
    v2_is_compressed_present: 0;
    v2_is_compressed: 0;
    v2_stats_present: 0;
    v2_stats_offset: 0;
    v2_stats_end: 0;
  };
  let pr = _parse_page_header_fields(&mut h, &mut r);
  if !pr.is_ok {
    return _err_ph(pr.error);
  }
  h.consumed = r.pos - offset;
  return _ok_ph(h);
}

/// PageType code of a parsed page header (see `parquet_page_type_name`).
/// Complexity: O(1).
pub fn parquet_page_type(h: &ParquetPageHeader) -> Int {
  return h.ptype;
}

/// True when the page header carried a type field. Complexity: O(1).
pub fn parquet_page_type_present(h: &ParquetPageHeader) -> Bool {
  if h.ptype_present == 1 {
    return true;
  }
  return false;
}

/// Documented name of a PageType code ("unknown" beyond DATA_PAGE_V2).
/// Complexity: O(1).
pub fn parquet_page_type_name(t: Int) -> Str {
  if t == 0 {
    return "DATA_PAGE";
  }
  if t == 1 {
    return "INDEX_PAGE";
  }
  if t == 2 {
    return "DICTIONARY_PAGE";
  }
  if t == 3 {
    return "DATA_PAGE_V2";
  }
  return "unknown";
}

/// PageHeader.uncompressed_page_size. Complexity: O(1).
pub fn parquet_page_uncompressed_size(h: &ParquetPageHeader) -> Int {
  return h.uncompressed_page_size;
}

/// PageHeader.compressed_page_size. Complexity: O(1).
pub fn parquet_page_compressed_size(h: &ParquetPageHeader) -> Int {
  return h.compressed_page_size;
}

/// PageHeader.crc; Err when absent. Complexity: O(1).
pub fn parquet_page_crc(h: &ParquetPageHeader) -> Result[Int, Str] {
  if h.crc_present == 0 {
    return _err_int("parquet: page header has no crc");
  }
  return _ok_int(h.crc);
}

/// Number of bytes the parsed page header occupied. Complexity: O(1).
pub fn parquet_page_consumed(h: &ParquetPageHeader) -> Int {
  return h.consumed;
}

/// True when a DataPageHeader member was present. Complexity: O(1).
pub fn parquet_page_has_data_header(h: &ParquetPageHeader) -> Bool {
  if h.dp_present == 1 {
    return true;
  }
  return false;
}

/// DataPageHeader.num_values. Complexity: O(1).
pub fn parquet_page_data_num_values(h: &ParquetPageHeader) -> Int {
  return h.dp_num_values;
}

/// DataPageHeader.encoding. Complexity: O(1).
pub fn parquet_page_data_encoding(h: &ParquetPageHeader) -> Int {
  return h.dp_encoding;
}

/// DataPageHeader.definition_level_encoding. Complexity: O(1).
pub fn parquet_page_data_definition_level_encoding(h: &ParquetPageHeader) -> Int {
  return h.dp_def_encoding;
}

/// DataPageHeader.repetition_level_encoding. Complexity: O(1).
pub fn parquet_page_data_repetition_level_encoding(h: &ParquetPageHeader) -> Int {
  return h.dp_rep_encoding;
}

/// True when the DataPageHeader carried a Statistics struct.
/// Complexity: O(1).
pub fn parquet_page_data_stats_present(h: &ParquetPageHeader) -> Bool {
  if h.dp_stats_present == 1 {
    return true;
  }
  return false;
}

/// Absolute offset of the DataPageHeader's raw Statistics struct.
/// Complexity: O(1).
pub fn parquet_page_data_stats_offset(h: &ParquetPageHeader) -> Int {
  return h.dp_stats_offset;
}

/// Length in bytes of the DataPageHeader's raw Statistics struct
/// (including its STOP byte; 0 when absent). Complexity: O(1).
pub fn parquet_page_data_stats_length(h: &ParquetPageHeader) -> Int {
  return h.dp_stats_end - h.dp_stats_offset;
}

/// True when an IndexPageHeader member was present. Complexity: O(1).
pub fn parquet_page_has_index_header(h: &ParquetPageHeader) -> Bool {
  if h.ix_present == 1 {
    return true;
  }
  return false;
}

/// True when a DictionaryPageHeader member was present. Complexity: O(1).
pub fn parquet_page_has_dictionary_header(h: &ParquetPageHeader) -> Bool {
  if h.dict_present == 1 {
    return true;
  }
  return false;
}

/// DictionaryPageHeader.num_values. Complexity: O(1).
pub fn parquet_page_dictionary_num_values(h: &ParquetPageHeader) -> Int {
  return h.dict_num_values;
}

/// DictionaryPageHeader.encoding. Complexity: O(1).
pub fn parquet_page_dictionary_encoding(h: &ParquetPageHeader) -> Int {
  return h.dict_encoding;
}

/// DictionaryPageHeader.is_sorted; Err when absent.
/// Complexity: O(1).
pub fn parquet_page_dictionary_is_sorted(h: &ParquetPageHeader) -> Result[Bool, Str] {
  if h.dict_is_sorted_present == 0 {
    return _err_bool("parquet: dictionary page header has no is_sorted");
  }
  if h.dict_is_sorted == 1 {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// True when a DataPageHeaderV2 member was present. Complexity: O(1).
pub fn parquet_page_has_data_header_v2(h: &ParquetPageHeader) -> Bool {
  if h.v2_present == 1 {
    return true;
  }
  return false;
}

/// DataPageHeaderV2.num_values. Complexity: O(1).
pub fn parquet_page_v2_num_values(h: &ParquetPageHeader) -> Int {
  return h.v2_num_values;
}

/// DataPageHeaderV2.num_nulls. Complexity: O(1).
pub fn parquet_page_v2_num_nulls(h: &ParquetPageHeader) -> Int {
  return h.v2_num_nulls;
}

/// DataPageHeaderV2.num_rows. Complexity: O(1).
pub fn parquet_page_v2_num_rows(h: &ParquetPageHeader) -> Int {
  return h.v2_num_rows;
}

/// DataPageHeaderV2.encoding. Complexity: O(1).
pub fn parquet_page_v2_encoding(h: &ParquetPageHeader) -> Int {
  return h.v2_encoding;
}

/// DataPageHeaderV2.definition_levels_byte_length. Complexity: O(1).
pub fn parquet_page_v2_definition_levels_byte_length(h: &ParquetPageHeader) -> Int {
  return h.v2_def_len;
}

/// DataPageHeaderV2.repetition_levels_byte_length. Complexity: O(1).
pub fn parquet_page_v2_repetition_levels_byte_length(h: &ParquetPageHeader) -> Int {
  return h.v2_rep_len;
}

/// DataPageHeaderV2.is_compressed; Err when absent (the Parquet default is
/// compressed, but this codec reports presence explicitly).
/// Complexity: O(1).
pub fn parquet_page_v2_is_compressed(h: &ParquetPageHeader) -> Result[Bool, Str] {
  if h.v2_is_compressed_present == 0 {
    return _err_bool("parquet: data page header v2 has no is_compressed");
  }
  if h.v2_is_compressed == 1 {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

/// True when the DataPageHeaderV2 carried a Statistics struct.
/// Complexity: O(1).
pub fn parquet_page_v2_stats_present(h: &ParquetPageHeader) -> Bool {
  if h.v2_stats_present == 1 {
    return true;
  }
  return false;
}

/// Absolute offset of the DataPageHeaderV2's raw Statistics struct.
/// Complexity: O(1).
pub fn parquet_page_v2_stats_offset(h: &ParquetPageHeader) -> Int {
  return h.v2_stats_offset;
}

/// Length in bytes of the DataPageHeaderV2's raw Statistics struct
/// (including its STOP byte; 0 when absent). Complexity: O(1).
pub fn parquet_page_v2_stats_length(h: &ParquetPageHeader) -> Int {
  return h.v2_stats_end - h.v2_stats_offset;
}
