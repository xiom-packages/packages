// XIOM -- xiom.windows: Windows Registry hive (REGF) structure parser
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Read-only STRUCTURE parser for Windows Registry hive files (REGF):
// base block, hbin blocks, cell table (allocated and free/deleted cells),
// nk/vk/sk records, lf/lh/li/ri subkey lists, db big data, a BFS key-tree
// walk with flat key/value tables, accessors, case-insensitive child
// lookup and path resolution.
//
// Non-goals: hive writes, transactional log replay, cell allocation,
// security-descriptor interpretation, registry API semantics.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods, no lambdas, no Vec[StructType].
//   * Ok/Err construction is confined to the tiny leaf helpers below.
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic.
//   * Vec[Int] and Vec[Str] element reads are bound to typed locals.
//   * 64-bit fields use the overflow-safe shape (low seven bytes with a
//     `place` factor, top byte applied separately).
//   * Str values read from Vec[Str] fields are only compared through
//     xiom.string.compare str_compare (BUG 17 discipline).
//   * accessors that need raw bytes take the parse buffer explicitly.
// See SPEC.md for byte layouts, validation order and the error catalog.

module xiom.windows

use xiom.string;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

// Base block size in bytes.
pub const REGF_BASE_BLOCK_SIZE: Int = 4096;

// hbin block header size in bytes.
pub const REGF_HBIN_HEADER_SIZE: Int = 32;

// Cell header size in bytes.
pub const REGF_CELL_HEADER_SIZE: Int = 4;

// Largest data size stored directly in one data cell; bigger value data
// is stored through a db (big data) record.
pub const REGF_MAX_DIRECT_DATA_SIZE: Int = 16344;

// The same bound is the per-segment capacity of big data.
pub const REGF_MAX_SEGMENT_SIZE: Int = 16344;

// Version of the base block this parser accepts: 1.3 .. 1.5.
pub const REGF_MAJOR_VERSION: Int = 1;
pub const REGF_MINOR_VERSION_MIN: Int = 3;
pub const REGF_MINOR_VERSION_MAX: Int = 5;

// Base block file format (must be 1).
pub const REGF_FILE_FORMAT: Int = 1;

// Base block file types.
pub const REGF_FILE_TYPE_PRIMARY: Int = 0;
pub const REGF_FILE_TYPE_LOG: Int = 1;
pub const REGF_FILE_TYPE_EXTERNAL: Int = 2;

// "regf" signature bytes.
pub const REGF_SIG_REG_R: Int = 114;
pub const REGF_SIG_REG_E: Int = 101;
pub const REGF_SIG_REG_G: Int = 103;
pub const REGF_SIG_REG_F: Int = 102;

// "hbin" signature bytes.
pub const REGF_SIG_HBIN_H: Int = 104;
pub const REGF_SIG_HBIN_B: Int = 98;
pub const REGF_SIG_HBIN_I: Int = 105;
pub const REGF_SIG_HBIN_N: Int = 110;

// A cell offset field with all bits set means "no cell".
pub const REGF_OFFSET_NONE: Int = 4294967295;

// nk flags bits.
pub const REGF_NK_FLAG_VOLATILE: Int = 1;
pub const REGF_NK_FLAG_HIVE_EXIT: Int = 2;
pub const REGF_NK_FLAG_HIVE_ENTRY: Int = 4;
pub const REGF_NK_FLAG_NO_DELETE: Int = 8;
pub const REGF_NK_FLAG_SYM_LINK: Int = 16;
pub const REGF_NK_FLAG_COMP_NAME: Int = 32;
pub const REGF_NK_FLAG_PREDEF_HANDLE: Int = 64;

// vk flags bits (bit 0: value name is compressed ASCII).
pub const REGF_VK_FLAG_COMP_NAME: Int = 1;

// REG_* value data types.
pub const REGF_REG_NONE: Int = 0;
pub const REGF_REG_SZ: Int = 1;
pub const REGF_REG_EXPAND_SZ: Int = 2;
pub const REGF_REG_BINARY: Int = 3;
pub const REGF_REG_DWORD: Int = 4;
pub const REGF_REG_DWORD_BIG_ENDIAN: Int = 5;
pub const REGF_REG_LINK: Int = 6;
pub const REGF_REG_MULTI_SZ: Int = 7;
pub const REGF_REG_RESOURCE_LIST: Int = 8;
pub const REGF_REG_FULL_RESOURCE_DESCRIPTOR: Int = 9;
pub const REGF_REG_RESOURCE_REQUIREMENTS_LIST: Int = 10;
pub const REGF_REG_QWORD: Int = 11;

// Cell kind tags (signature detection; best effort on free cells).
pub const REGF_KIND_UNKNOWN: Int = 0;
pub const REGF_KIND_NK: Int = 1;
pub const REGF_KIND_VK: Int = 2;
pub const REGF_KIND_SK: Int = 3;
pub const REGF_KIND_LF: Int = 4;
pub const REGF_KIND_LH: Int = 5;
pub const REGF_KIND_LI: Int = 6;
pub const REGF_KIND_RI: Int = 7;
pub const REGF_KIND_DB: Int = 8;

// regf_key_field selectors.
pub const REGF_KEY_FIELD_FLAGS: Int = 0;
pub const REGF_KEY_FIELD_TIMESTAMP: Int = 1;
pub const REGF_KEY_FIELD_ACCESS_BITS: Int = 2;
pub const REGF_KEY_FIELD_PARENT_OFFSET: Int = 3;
pub const REGF_KEY_FIELD_SUBKEY_COUNT: Int = 4;
pub const REGF_KEY_FIELD_VOLATILE_SUBKEY_COUNT: Int = 5;
pub const REGF_KEY_FIELD_SUBKEY_LIST_OFFSET: Int = 6;
pub const REGF_KEY_FIELD_VOLATILE_SUBKEY_LIST_OFFSET: Int = 7;
pub const REGF_KEY_FIELD_VALUE_COUNT: Int = 8;
pub const REGF_KEY_FIELD_VALUE_LIST_OFFSET: Int = 9;
pub const REGF_KEY_FIELD_SECURITY_OFFSET: Int = 10;
pub const REGF_KEY_FIELD_CLASS_OFFSET: Int = 11;
pub const REGF_KEY_FIELD_LARGEST_SUBKEY_NAME: Int = 12;
pub const REGF_KEY_FIELD_LARGEST_SUBKEY_CLASS: Int = 13;
pub const REGF_KEY_FIELD_LARGEST_VALUE_NAME: Int = 14;
pub const REGF_KEY_FIELD_LARGEST_VALUE_DATA: Int = 15;
pub const REGF_KEY_FIELD_WORK_VAR: Int = 16;
pub const REGF_KEY_FIELD_NAME_LENGTH: Int = 17;
pub const REGF_KEY_FIELD_CLASS_NAME_LENGTH: Int = 18;
pub const REGF_KEY_FIELD_CELL_OFFSET: Int = 19;
pub const REGF_KEY_FIELD_SUBKEY_LIST_COUNT: Int = 20;
pub const REGF_KEY_FIELD_VALUE_LIST_COUNT: Int = 21;
pub const REGF_KEY_FIELD_COUNT: Int = 22;

// regf_value_field selectors.
pub const REGF_VALUE_FIELD_NAME_LENGTH: Int = 0;
pub const REGF_VALUE_FIELD_DATA_SIZE: Int = 1;
pub const REGF_VALUE_FIELD_DATA_OFFSET: Int = 2;
pub const REGF_VALUE_FIELD_DATA_TYPE: Int = 3;
pub const REGF_VALUE_FIELD_FLAGS: Int = 4;
pub const REGF_VALUE_FIELD_CELL_OFFSET: Int = 5;
pub const REGF_VALUE_FIELD_INLINE: Int = 6;
pub const REGF_VALUE_FIELD_BIG_DATA: Int = 7;
pub const REGF_VALUE_FIELD_SEGMENT_COUNT: Int = 8;
pub const REGF_VALUE_FIELD_COUNT: Int = 9;

// regf_key_sk selectors.
pub const REGF_SK_FIELD_OFFSET: Int = 0;
pub const REGF_SK_FIELD_REFERENCE_COUNT: Int = 1;
pub const REGF_SK_FIELD_DESCRIPTOR_SIZE: Int = 2;
pub const REGF_SK_FIELD_FLAGS: Int = 3;
pub const REGF_SK_FIELD_COUNT: Int = 4;

// --------------------------------------------------
//  Parsed hive index
// --------------------------------------------------

/// Parsed REGF hive: base block scalars, flat hbin/cell tables and the
/// key/value tables produced by a BFS walk from the root nk.
///
/// Table shapes:
///   * hbins: one entry per hbin block.
///   * cells: every cell of every hbin in file order, with absolute
///     offsets, absolute sizes, an allocated flag (1 = negative size,
///     0 = free/deleted) and a best-effort signature tag.
///   * keys: BFS order; key i's children are the walk indices
///     key_sub_offsets[key_sub_index[i] .. key_sub_index[i+1]], and its
///     values are the global value indices
///     key_val_indices[key_val_index[i] .. key_val_index[i+1]].
///   * values: one entry per vk record; value i's data segments are
///     value_seg_offsets[value_seg_index[i] .. value_seg_index[i+1]].
/// Bytes stay in the parse buffer: byte-level accessors take it back.
/// Fields are implementation details; callers use the free functions.
pub type RegfHive = {
  primary_seq: Int;
  secondary_seq: Int;
  timestamp: Int;
  major: Int;
  minor: Int;
  file_type: Int;
  file_format: Int;
  root_cell_offset: Int;
  hbin_data_size: Int;
  cluster_factor: Int;
  checksum: Int;
  file_name: Str;
  warn_sequence: Int;
  root_offset: Int;
  hbin_offsets: Vec[Int];
  hbin_rel_offsets: Vec[Int];
  hbin_sizes: Vec[Int];
  hbin_timestamps: Vec[Int];
  hbin_spares: Vec[Int];
  cell_offsets: Vec[Int];
  cell_sizes: Vec[Int];
  cell_allocated: Vec[Int];
  cell_kinds: Vec[Int];
  cell_hbin_index: Vec[Int];
  key_cell_offsets: Vec[Int];
  key_flags: Vec[Int];
  key_timestamps: Vec[Int];
  key_access_bits: Vec[Int];
  key_parent_offsets: Vec[Int];
  key_subkey_counts: Vec[Int];
  key_volatile_subkey_counts: Vec[Int];
  key_subkey_list_offsets: Vec[Int];
  key_volatile_subkey_list_offsets: Vec[Int];
  key_value_counts: Vec[Int];
  key_value_list_offsets: Vec[Int];
  key_security_offsets: Vec[Int];
  key_class_offsets: Vec[Int];
  key_largest_subkey_name: Vec[Int];
  key_largest_subkey_class: Vec[Int];
  key_largest_value_name: Vec[Int];
  key_largest_value_data: Vec[Int];
  key_work_var: Vec[Int];
  key_name_lengths: Vec[Int];
  key_class_name_lengths: Vec[Int];
  key_names: Vec[Str];
  key_parent_key_index: Vec[Int];
  key_sk_offsets: Vec[Int];
  key_sk_refcounts: Vec[Int];
  key_sk_sizes: Vec[Int];
  key_sk_flags: Vec[Int];
  key_sub_index: Vec[Int];
  key_sub_offsets: Vec[Int];
  key_val_index: Vec[Int];
  key_val_indices: Vec[Int];
  value_offsets: Vec[Int];
  value_name_lengths: Vec[Int];
  value_data_sizes: Vec[Int];
  value_data_types: Vec[Int];
  value_data_offsets: Vec[Int];
  value_flags: Vec[Int];
  value_names: Vec[Str];
  value_inline: Vec[Int];
  value_big: Vec[Int];
  value_seg_count: Vec[Int];
  value_seg_index: Vec[Int];
  value_seg_offsets: Vec[Int];
  value_seg_sizes: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
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

// Ok(v) for Result[Vec[Int], Str].
fn _ok_ints(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _err_ints(m: Str) -> Result[Vec[Int], Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Str], Str].
fn _ok_strs(v: Vec[Str]) -> Result[Vec[Str], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Str], Str].
fn _err_strs(m: Str) -> Result[Vec[Str], Str] {
  return Err(m);
}

// Ok(v) for Result[RegfHive, Str].
fn _ok_hive(v: RegfHive) -> Result[RegfHive, Str] {
  return Ok(v);
}

// Err(m) for Result[RegfHive, Str].
fn _err_hive(m: Str) -> Result[RegfHive, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Message helpers
// --------------------------------------------------

// `m` with the offending absolute byte offset appended as 0x%08x.
fn _msg_at(m: Str, off: Int) -> Str {
  return m + " at 0x" + _hex8(off);
}

// Err(m + offset) for Result[Unit, Str].
fn _err_unit_at(m: Str, off: Int) -> Result[Unit, Str] {
  return _err_unit(_msg_at(m, off));
}

// Err(m + offset) for Result[Int, Str].
fn _err_int_at(m: Str, off: Int) -> Result[Int, Str] {
  return _err_int(_msg_at(m, off));
}

// Err(m + offset) for Result[Vec[Int], Str].
fn _err_ints_at(m: Str, off: Int) -> Result[Vec[Int], Str] {
  return _err_ints(_msg_at(m, off));
}

// --------------------------------------------------
//  Internal byte and field helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Bit `m` (a power of two) of small non-negative `v`.
fn _bit(v: Int, m: Int) -> Int {
  return (v / m) % 2;
}

// Little-endian u16 at `pos` (0..65535).
fn _u16(data: &Vec[UInt8], pos: Int) -> Int {
  let b0 = _byte(data, pos);
  let b1 = _byte(data, pos + 1);
  return b0 + b1 * 256;
}

// Little-endian u32 at `pos` (0..4294967295).
fn _u32(data: &Vec[UInt8], pos: Int) -> Int {
  let b0 = _byte(data, pos);
  let b1 = _byte(data, pos + 1);
  let b2 = _byte(data, pos + 2);
  let b3 = _byte(data, pos + 3);
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

// Little-endian u64 at `pos` as the raw two's-complement Int (bit 63 set
// decodes as a negative Int). The low seven bytes accumulate with a
// `place` factor and the top byte is applied separately.
fn _u64(data: &Vec[UInt8], pos: Int) -> Int {
  var low: Int = 0;
  var place: Int = 1;
  var i = 0;
  while i < 7 {
    let b = _byte(data, pos + i);
    low = low + b * place;
    place = place * 256;
    i = i + 1;
  }
  let top = _byte(data, pos + 7);
  if top < 128 {
    return low + top * place;
  }
  let t = top - 128;
  return low + t * place + (0 - 9223372036854775807 - 1);
}

// Lowercase hex digit (0..15) as a byte value.
fn _hex_digit(d: Int) -> Int {
  if d < 10 {
    return 48 + d;
  }
  return 87 + d;
}

// 8 lowercase hex digits of `v` (two's-complement for negatives).
fn _hex8(v: Int) -> Str {
  var out = Vec[UInt8].new();
  var q = v;
  var i = 0;
  while i < 8 {
    var r = q % 16;
    if r < 0 {
      r = r + 16;
    }
    q = (q - r) / 16;
    out.push(_hex_digit(r) as UInt8);
    i = i + 1;
  }
  var lo = 0;
  var hi = 7;
  while lo < hi {
    let tmp: UInt8 = out[lo];
    out[lo] = out[hi];
    out[hi] = tmp;
    lo = lo + 1;
    hi = hi - 1;
  }
  return Str::from_utf8(out);
}

// Append the UTF-8 encoding of code point `cp` to `out`.
fn _push_utf8(out: &mut Vec[UInt8], cp: Int) {
  if cp < 128 {
    out.push(cp as UInt8);
    return;
  }
  if cp < 2048 {
    out.push((192 + cp / 64) as UInt8);
    out.push((128 + cp % 64) as UInt8);
    return;
  }
  if cp < 65536 {
    out.push((224 + cp / 4096) as UInt8);
    out.push((128 + (cp / 64) % 64) as UInt8);
    out.push((128 + cp % 64) as UInt8);
    return;
  }
  out.push((240 + cp / 262144) as UInt8);
  out.push((128 + (cp / 4096) % 64) as UInt8);
  out.push((128 + (cp / 64) % 64) as UInt8);
  out.push((128 + cp % 64) as UInt8);
}

// --------------------------------------------------
//  Name decoding
// --------------------------------------------------

// Decode `byte_len` UTF-16LE bytes at `off` into a Str (UTF-8). Lone
// surrogates and code unit 0 decode to U+FFFD, so the result never
// contains a NUL byte; a trailing odd byte is ignored.
fn _utf16le_bytes_to_str(v: &Vec[UInt8], off: Int, byte_len: Int) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i + 1 < byte_len {
    let lo = (v[off + i] as Int) & 0xFF;
    let hi = (v[off + i + 1] as Int) & 0xFF;
    let cu = lo + hi * 256;
    var cp = cu;
    var consumed = 2;
    if cu >= 55296 && cu <= 56319 && i + 3 < byte_len {
      let lo2 = (v[off + i + 2] as Int) & 0xFF;
      let hi2 = (v[off + i + 3] as Int) & 0xFF;
      let cu2 = lo2 + hi2 * 256;
      if cu2 >= 56320 && cu2 <= 57343 {
        cp = 65536 + (cu - 55296) * 1024 + (cu2 - 56320);
        consumed = 4;
      } else {
        cp = 65533;
      }
    } else if cu >= 55296 && cu <= 57343 {
      cp = 65533;
    }
    if cp == 0 {
      cp = 65533;
    }
    _push_utf8(&mut out, cp);
    i = i + consumed;
  }
  return Str::from_utf8(out);
}

// Decode a UTF-16LE field of `byte_len` bytes; when `stop_at_nul` is true
// the first zero code unit terminates the name (base block file name).
fn _utf16le_str(data: &Vec[UInt8], off: Int, byte_len: Int, stop_at_nul: Bool) -> Str {
  var n = byte_len;
  if stop_at_nul {
    var i = 0;
    while i + 1 < byte_len {
      let lo = _byte(data, off + i);
      let hi = _byte(data, off + i + 1);
      if lo == 0 && hi == 0 {
        n = i;
        break;
      }
      i = i + 2;
    }
  }
  return _utf16le_bytes_to_str(data, off, n);
}

// Decode `byte_len` bytes of a compressed (ASCII) name; bytes >= 128
// decode to U+FFFD so the result is always valid UTF-8 and NUL-free.
fn _ascii_name(data: &Vec[UInt8], off: Int, byte_len: Int) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < byte_len {
    let b = _byte(data, off + i);
    if b == 0 || b >= 128 {
      out.push(239 as UInt8);
      out.push(191 as UInt8);
      out.push(189 as UInt8);
    } else {
      out.push(b as UInt8);
    }
    i = i + 1;
  }
  return Str::from_utf8(out);
}

// Decode `byte_len` UTF-16LE bytes into NUL-separated strings; empty
// groups are dropped (REG_MULTI_SZ semantics).
fn _utf16le_multi(data: &Vec[UInt8], off: Int, byte_len: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  var cur = Vec[UInt8].new();
  var i = 0;
  while i + 1 < byte_len {
    let lo = _byte(data, off + i);
    let hi = _byte(data, off + i + 1);
    let cu = lo + hi * 256;
    var consumed = 2;
    if cu == 0 {
      if cur.len() > 0 {
        out.push(Str::from_utf8(cur));
        cur = Vec[UInt8].new();
      }
    } else {
      var cp = cu;
      if cu >= 55296 && cu <= 56319 && i + 3 < byte_len {
        let lo2 = _byte(data, off + i + 2);
        let hi2 = _byte(data, off + i + 3);
        let cu2 = lo2 + hi2 * 256;
        if cu2 >= 56320 && cu2 <= 57343 {
          cp = 65536 + (cu - 55296) * 1024 + (cu2 - 56320);
          consumed = 4;
        } else {
          cp = 65533;
        }
      } else if cu >= 55296 && cu <= 57343 {
        cp = 65533;
      }
      if cp != 0 {
        _push_utf8(&mut cur, cp);
      }
    }
    i = i + consumed;
  }
  if cur.len() > 0 {
    out.push(Str::from_utf8(cur));
  }
  return out;
}

// --------------------------------------------------
//  Cell helpers
// --------------------------------------------------

// Two-byte signature at cell data start, as a kind tag. Uses the cell
// size only to guarantee the two header bytes are inside the cell.
fn _cell_kind(data: &Vec[UInt8], cell_off: Int, cell_size: Int) -> Int {
  if cell_size < 8 {
    return REGF_KIND_UNKNOWN;
  }
  let b0 = _byte(data, cell_off + 4);
  let b1 = _byte(data, cell_off + 5);
  if b0 == 110 && b1 == 107 {
    return REGF_KIND_NK;
  }
  if b0 == 118 && b1 == 107 {
    return REGF_KIND_VK;
  }
  if b0 == 115 && b1 == 107 {
    return REGF_KIND_SK;
  }
  if b0 == 108 && b1 == 102 {
    return REGF_KIND_LF;
  }
  if b0 == 108 && b1 == 104 {
    return REGF_KIND_LH;
  }
  if b0 == 108 && b1 == 105 {
    return REGF_KIND_LI;
  }
  if b0 == 114 && b1 == 105 {
    return REGF_KIND_RI;
  }
  if b0 == 100 && b1 == 98 {
    return REGF_KIND_DB;
  }
  return REGF_KIND_UNKNOWN;
}

// Cell-table index of the cell starting at absolute offset `off`, or -1.
// Cells are recorded in ascending offset order, so this is binary search.
fn _cell_index(f: &RegfHive, off: Int) -> Int {
  var lo = 0;
  var hi = f.cell_offsets.len() - 1;
  while lo <= hi {
    let mid = lo + (hi - lo) / 2;
    let v: Int = f.cell_offsets[mid];
    if v == off {
      return mid;
    }
    if v < off {
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return -1;
}

// Resolve a hive-bins-relative cell offset into an absolute offset of an
// allocated cell, optionally requiring a kind tag. `ref_off` is the byte
// offset of the field that carried the bad offset (used in the error).
fn _resolve_cell(data: &Vec[UInt8], f: &RegfHive, rel: Int, want_kind: Int, ref_off: Int) -> Result[Int, Str] {
  if rel < 0 || rel >= 2147483648 {
    return _err_int_at("regf: bad cell offset", ref_off);
  }
  let region: Int = f.hbin_data_size;
  if rel + 4 > region {
    return _err_int_at("regf: bad cell offset", ref_off);
  }
  let abs = REGF_BASE_BLOCK_SIZE + rel;
  let ci = _cell_index(f, abs);
  if ci < 0 {
    return _err_int_at("regf: bad cell offset", ref_off);
  }
  let alloc: Int = f.cell_allocated[ci];
  if alloc == 0 {
    return _err_int_at("regf: cell not allocated", abs);
  }
  if want_kind != REGF_KIND_UNKNOWN {
    let k: Int = f.cell_kinds[ci];
    if k != want_kind {
      return _err_int_at("regf: unexpected cell kind", abs);
    }
  }
  return _ok_int(abs);
}

// --------------------------------------------------
//  Base block
// --------------------------------------------------

// Parse and validate the 4096-byte base block.
fn _read_base(data: &Vec[UInt8], f: &mut RegfHive) -> Result[Unit, Str] {
  let total = data.len();
  if total < REGF_BASE_BLOCK_SIZE {
    return _err_unit_at("regf: truncated base block", 0);
  }
  if _byte(data, 0) != REGF_SIG_REG_R {
    return _err_unit_at("regf: bad base block signature", 0);
  }
  if _byte(data, 1) != REGF_SIG_REG_E {
    return _err_unit_at("regf: bad base block signature", 0);
  }
  if _byte(data, 2) != REGF_SIG_REG_G {
    return _err_unit_at("regf: bad base block signature", 0);
  }
  if _byte(data, 3) != REGF_SIG_REG_F {
    return _err_unit_at("regf: bad base block signature", 0);
  }
  f.primary_seq = _u32(data, 4);
  f.secondary_seq = _u32(data, 8);
  f.timestamp = _u64(data, 12);
  f.major = _u32(data, 20);
  f.minor = _u32(data, 24);
  let minor: Int = f.minor;
  if f.major != REGF_MAJOR_VERSION || minor < REGF_MINOR_VERSION_MIN || minor > REGF_MINOR_VERSION_MAX {
    return _err_unit_at("regf: bad version", 20);
  }
  f.file_type = _u32(data, 28);
  let ftype: Int = f.file_type;
  if ftype < REGF_FILE_TYPE_PRIMARY || ftype > REGF_FILE_TYPE_EXTERNAL {
    return _err_unit_at("regf: bad file type", 28);
  }
  f.file_format = _u32(data, 32);
  if f.file_format != REGF_FILE_FORMAT {
    return _err_unit_at("regf: bad file format", 32);
  }
  f.root_cell_offset = _u32(data, 36);
  f.hbin_data_size = _u32(data, 40);
  f.cluster_factor = _u32(data, 44);
  f.checksum = _u32(data, 112);
  let declared: Int = f.hbin_data_size;
  if declared == 0 || declared % 4096 != 0 || declared > total - REGF_BASE_BLOCK_SIZE {
    return _err_unit_at("regf: bad hive bins data size", 40);
  }
  let root: Int = f.root_cell_offset;
  if root == REGF_OFFSET_NONE || root >= 2147483648 || root + 4 > declared {
    return _err_unit_at("regf: bad root cell offset", 36);
  }
  if f.primary_seq != f.secondary_seq {
    f.warn_sequence = 1;
  }
  f.file_name = _utf16le_str(data, 48, 64, true);
  return _ok_unit();
}

// --------------------------------------------------
//  hbin blocks and cells
// --------------------------------------------------

// Parse every hbin block in the declared hive-bins region and record the
// cell table. Cell sizes are signed: negative = allocated, positive =
// free. Every cell must be 8-byte aligned, at least 8 bytes and inside its
// hbin.
fn _read_hbins(data: &Vec[UInt8], f: &mut RegfHive) -> Result[Unit, Str] {
  let total = data.len();
  let declared: Int = f.hbin_data_size;
  let region_end = REGF_BASE_BLOCK_SIZE + declared;
  var abs = REGF_BASE_BLOCK_SIZE;
  var rel = 0;
  while rel < declared {
    if abs + REGF_HBIN_HEADER_SIZE > region_end {
      return _err_unit_at("regf: truncated hbin", abs);
    }
    if _byte(data, abs) != REGF_SIG_HBIN_H || _byte(data, abs + 1) != REGF_SIG_HBIN_B ||
       _byte(data, abs + 2) != REGF_SIG_HBIN_I || _byte(data, abs + 3) != REGF_SIG_HBIN_N {
      return _err_unit_at("regf: bad hbin signature", abs);
    }
    let raw_rel = _u32(data, abs + 4);
    if raw_rel != rel {
      return _err_unit_at("regf: bad hbin offset", abs + 4);
    }
    let hsize = _u32(data, abs + 8);
    if hsize == 0 || hsize % 4096 != 0 || hsize > declared - rel || abs + hsize > total {
      return _err_unit_at("regf: bad hbin size", abs + 8);
    }
    f.hbin_offsets.push(abs);
    f.hbin_rel_offsets.push(rel);
    f.hbin_sizes.push(hsize);
    f.hbin_timestamps.push(_u64(data, abs + 20));
    f.hbin_spares.push(_u32(data, abs + 28));
    let hbin_index = f.hbin_offsets.len() - 1;
    let hbin_end = abs + hsize;
    var pos = abs + REGF_HBIN_HEADER_SIZE;
    while pos < hbin_end {
      if pos + 4 > hbin_end {
        return _err_unit_at("regf: truncated cell", pos);
      }
      let raw = _u32(data, pos);
      var csize = raw;
      var alloc = 0;
      if raw >= 2147483648 {
        csize = raw - 4294967296;
        alloc = 1;
      }
      var asize = csize;
      if asize < 0 {
        asize = 0 - asize;
      }
      if asize < 8 || asize % 8 != 0 {
        return _err_unit_at("regf: bad cell size", pos);
      }
      if pos + asize > hbin_end {
        return _err_unit_at("regf: bad cell size", pos);
      }
      f.cell_offsets.push(pos);
      f.cell_sizes.push(asize);
      f.cell_allocated.push(alloc);
      f.cell_kinds.push(_cell_kind(data, pos, asize));
      f.cell_hbin_index.push(hbin_index);
      pos = pos + asize;
    }
    abs = abs + hsize;
    rel = rel + hsize;
  }
  if rel != declared {
    return _err_unit_at("regf: bad hive bins data size", 40);
  }
  return _ok_unit();
}

// --------------------------------------------------
//  Key records
// --------------------------------------------------

// Record the sk cell referenced by a key's security offset (0 and
// 0xFFFFFFFF mean "none"). Validates the descriptor span.
fn _append_sk(data: &Vec[UInt8], f: &mut RegfHive, sec_raw: Int, field_off: Int) -> Result[Unit, Str] {
  if sec_raw == REGF_OFFSET_NONE || sec_raw == 0 {
    f.key_sk_offsets.push(-1);
    f.key_sk_refcounts.push(0);
    f.key_sk_sizes.push(0);
    f.key_sk_flags.push(0);
    return _ok_unit();
  }
  let r = _resolve_cell(data, f, sec_raw, REGF_KIND_SK, field_off);
  if !r.is_ok {
    return _err_unit(r.error);
  }
  let abs: Int = r.value;
  let ci = _cell_index(f, abs);
  let csz: Int = f.cell_sizes[ci];
  let d = abs + 4;
  if csz < 24 {
    return _err_unit_at("regf: bad sk record", abs);
  }
  let sflags = _u16(data, d + 2);
  let refc = _u32(data, d + 12);
  let dsize = _u32(data, d + 16);
  if d + 20 + dsize > abs + csz {
    return _err_unit_at("regf: bad security descriptor size", d + 16);
  }
  f.key_sk_offsets.push(abs);
  f.key_sk_refcounts.push(refc);
  f.key_sk_sizes.push(dsize);
  f.key_sk_flags.push(sflags);
  return _ok_unit();
}

// Parse the nk record at `cell_abs` and append one key entry; returns the
// new key's walk index. `parent_index` is the parent's walk index
// (-1 for the root).
fn _add_key(data: &Vec[UInt8], f: &mut RegfHive, cell_abs: Int, parent_index: Int) -> Result[Int, Str] {
  let ci = _cell_index(f, cell_abs);
  if ci < 0 {
    return _err_int_at("regf: bad cell offset", cell_abs);
  }
  let csz: Int = f.cell_sizes[ci];
  let d = cell_abs + 4;
  if csz < 80 {
    return _err_int_at("regf: truncated nk record", cell_abs);
  }
  let flags = _u16(data, d + 2);
  let name_len = _u16(data, d + 72);
  if d + 76 + name_len > cell_abs + csz {
    return _err_int_at("regf: bad key name length", d + 72);
  }
  var nm = "";
  if _bit(flags, REGF_NK_FLAG_COMP_NAME) == 1 {
    nm = _ascii_name(data, d + 76, name_len);
  } else {
    if name_len % 2 != 0 {
      return _err_int_at("regf: bad key name length", d + 72);
    }
    nm = _utf16le_str(data, d + 76, name_len, false);
  }
  let sr = _append_sk(data, f, _u32(data, d + 44), d + 44);
  if !sr.is_ok {
    return _err_int(sr.error);
  }
  f.key_cell_offsets.push(cell_abs);
  f.key_flags.push(flags);
  f.key_timestamps.push(_u64(data, d + 4));
  f.key_access_bits.push(_u32(data, d + 12));
  f.key_parent_offsets.push(_u32(data, d + 16));
  f.key_subkey_counts.push(_u32(data, d + 20));
  f.key_volatile_subkey_counts.push(_u32(data, d + 24));
  f.key_subkey_list_offsets.push(_u32(data, d + 28));
  f.key_volatile_subkey_list_offsets.push(_u32(data, d + 32));
  f.key_value_counts.push(_u32(data, d + 36));
  f.key_value_list_offsets.push(_u32(data, d + 40));
  f.key_security_offsets.push(_u32(data, d + 44));
  f.key_class_offsets.push(_u32(data, d + 48));
  f.key_largest_subkey_name.push(_u32(data, d + 52));
  f.key_largest_subkey_class.push(_u32(data, d + 56));
  f.key_largest_value_name.push(_u32(data, d + 60));
  f.key_largest_value_data.push(_u32(data, d + 64));
  f.key_work_var.push(_u32(data, d + 68));
  f.key_name_lengths.push(name_len);
  f.key_class_name_lengths.push(_u16(data, d + 74));
  f.key_names.push(nm);
  f.key_parent_key_index.push(parent_index);
  return _ok_int(f.key_cell_offsets.len() - 1);
}

// Resolve a subkey list cell (lf/lh/li, with ri lists of lists) into the
// absolute nk cell offsets it names, in list order. `depth` bounds ri
// nesting.
fn _resolve_subkeys(data: &Vec[UInt8], f: &RegfHive, list_raw: Int, field_off: Int, depth: Int) -> Result[Vec[Int], Str] {
  if depth > 8 {
    return _err_ints_at("regf: ri nesting too deep", field_off);
  }
  let r = _resolve_cell(data, f, list_raw, REGF_KIND_UNKNOWN, field_off);
  if !r.is_ok {
    return _err_ints(r.error);
  }
  let abs: Int = r.value;
  let ci = _cell_index(f, abs);
  let csz: Int = f.cell_sizes[ci];
  let kind: Int = f.cell_kinds[ci];
  let d = abs + 4;
  var out = Vec[Int].new();
  if kind == REGF_KIND_LF || kind == REGF_KIND_LH {
    if csz < 8 {
      return _err_ints_at("regf: bad subkey list size", abs);
    }
    let cnt = _u16(data, d + 2);
    if 8 + cnt * 8 > csz {
      return _err_ints_at("regf: bad subkey list size", abs);
    }
    var j = 0;
    while j < cnt {
      let eoff = d + 4 + j * 8;
      let er = _resolve_cell(data, f, _u32(data, eoff), REGF_KIND_NK, eoff);
      if !er.is_ok {
        return _err_ints(er.error);
      }
      out.push(er.value);
      j = j + 1;
    }
    return _ok_ints(out);
  }
  if kind == REGF_KIND_LI {
    if csz < 8 {
      return _err_ints_at("regf: bad subkey list size", abs);
    }
    let cnt = _u16(data, d + 2);
    if 8 + cnt * 4 > csz {
      return _err_ints_at("regf: bad subkey list size", abs);
    }
    var j = 0;
    while j < cnt {
      let eoff = d + 4 + j * 4;
      let er = _resolve_cell(data, f, _u32(data, eoff), REGF_KIND_NK, eoff);
      if !er.is_ok {
        return _err_ints(er.error);
      }
      out.push(er.value);
      j = j + 1;
    }
    return _ok_ints(out);
  }
  if kind == REGF_KIND_RI {
    if csz < 8 {
      return _err_ints_at("regf: bad subkey list size", abs);
    }
    let cnt = _u16(data, d + 2);
    if 8 + cnt * 4 > csz {
      return _err_ints_at("regf: bad subkey list size", abs);
    }
    var j = 0;
    while j < cnt {
      let eoff = d + 4 + j * 4;
      let sr = _resolve_subkeys(data, f, _u32(data, eoff), eoff, depth + 1);
      if !sr.is_ok {
        return _err_ints(sr.error);
      }
      let sub: Vec[Int] = sr.value;
      var k = 0;
      while k < sub.len() {
        let so: Int = sub[k];
        out.push(so);
        k = k + 1;
      }
      j = j + 1;
    }
    return _ok_ints(out);
  }
  return _err_ints_at("regf: bad subkey list", abs);
}

// --------------------------------------------------
//  Value records
// --------------------------------------------------

// Parse the vk record at `vk_abs` and append one value entry. Data is
// classified as inline (bit 31 of the size field), direct (one data cell,
// up to REGF_MAX_DIRECT_DATA_SIZE bytes) or big (db record with a segment
// list); segments are validated here and copied by regf_value_data.
fn _append_value(data: &Vec[UInt8], f: &mut RegfHive, vk_abs: Int) -> Result[Unit, Str] {
  let ci = _cell_index(f, vk_abs);
  let csz: Int = f.cell_sizes[ci];
  let d = vk_abs + 4;
  if csz < 24 {
    return _err_unit_at("regf: truncated vk record", vk_abs);
  }
  let name_len = _u16(data, d + 2);
  let size_raw = _u32(data, d + 4);
  let data_raw = _u32(data, d + 8);
  let dtype = _u32(data, d + 12);
  let vflags = _u16(data, d + 16);
  if d + 20 + name_len > vk_abs + csz {
    return _err_unit_at("regf: bad value name length", d + 2);
  }
  var nm = "";
  if _bit(vflags, REGF_VK_FLAG_COMP_NAME) == 1 {
    nm = _ascii_name(data, d + 20, name_len);
  } else {
    if name_len % 2 != 0 {
      return _err_unit_at("regf: bad value name length", d + 2);
    }
    nm = _utf16le_str(data, d + 20, name_len, false);
  }
  var inline = 0;
  var dsize = size_raw;
  if size_raw >= 2147483648 {
    inline = 1;
    dsize = size_raw - 2147483648;
  }
  var seg_count = 0;
  var big = 0;
  var seg_abs = Vec[Int].new();
  var seg_sz = Vec[Int].new();
  if inline == 1 {
    if dsize > 4 {
      return _err_unit_at("regf: bad inline data size", d + 4);
    }
  } else if dsize > 0 {
    if dsize <= REGF_MAX_DIRECT_DATA_SIZE {
      let dr = _resolve_cell(data, f, data_raw, REGF_KIND_UNKNOWN, d + 8);
      if !dr.is_ok {
        return _err_unit(dr.error);
      }
      let dabs: Int = dr.value;
      let dci = _cell_index(f, dabs);
      let dcsz: Int = f.cell_sizes[dci];
      if 4 + dsize > dcsz {
        return _err_unit_at("regf: bad value data size", d + 4);
      }
      seg_abs.push(dabs);
      seg_sz.push(dsize);
      seg_count = 1;
    } else {
      let br = _resolve_cell(data, f, data_raw, REGF_KIND_DB, d + 8);
      if !br.is_ok {
        return _err_unit(br.error);
      }
      let dabs: Int = br.value;
      let dci = _cell_index(f, dabs);
      let dcsz: Int = f.cell_sizes[dci];
      if dcsz < 12 {
        return _err_unit_at("regf: bad big data record", dabs);
      }
      let nseg = _u16(data, dabs + 6);
      var need = dsize / REGF_MAX_SEGMENT_SIZE;
      let rem0 = dsize % REGF_MAX_SEGMENT_SIZE;
      if rem0 > 0 {
        need = need + 1;
      }
      if nseg < 1 || nseg < need {
        return _err_unit_at("regf: bad big data segment count", dabs + 6);
      }
      let lr = _resolve_cell(data, f, _u32(data, dabs + 8), REGF_KIND_UNKNOWN, dabs + 8);
      if !lr.is_ok {
        return _err_unit(lr.error);
      }
      let labs: Int = lr.value;
      let lci = _cell_index(f, labs);
      let lcsz: Int = f.cell_sizes[lci];
      if 4 + nseg * 4 > lcsz {
        return _err_unit_at("regf: bad big data segment list", labs);
      }
      var remaining = dsize;
      var j = 0;
      while j < nseg {
        if remaining > 0 {
          let soff = labs + 4 + j * 4;
          let srr = _resolve_cell(data, f, _u32(data, soff), REGF_KIND_UNKNOWN, soff);
          if !srr.is_ok {
            return _err_unit(srr.error);
          }
          let sabs: Int = srr.value;
          var take = REGF_MAX_SEGMENT_SIZE;
          if remaining < take {
            take = remaining;
          }
          let sci = _cell_index(f, sabs);
          let scsz: Int = f.cell_sizes[sci];
          if 4 + take > scsz {
            return _err_unit_at("regf: bad big data segment size", sabs);
          }
          seg_abs.push(sabs);
          seg_sz.push(take);
          remaining = remaining - take;
        }
        j = j + 1;
      }
      if remaining != 0 {
        return _err_unit_at("regf: bad big data size", dabs + 6);
      }
      big = 1;
      seg_count = nseg;
    }
  }
  f.value_seg_index.push(f.value_seg_offsets.len());
  f.value_offsets.push(vk_abs);
  f.value_name_lengths.push(name_len);
  f.value_data_sizes.push(dsize);
  f.value_data_types.push(dtype);
  f.value_data_offsets.push(data_raw);
  f.value_flags.push(vflags);
  f.value_names.push(nm);
  f.value_inline.push(inline);
  f.value_big.push(big);
  f.value_seg_count.push(seg_count);
  var k = 0;
  while k < seg_abs.len() {
    let sa: Int = seg_abs[k];
    let ss: Int = seg_sz[k];
    f.value_seg_offsets.push(sa);
    f.value_seg_sizes.push(ss);
    k = k + 1;
  }
  return _ok_unit();
}

// Parse a key's value list cell: `count` vk offsets at the cell data
// start, every one resolved as an allocated vk cell.
fn _read_value_list(data: &Vec[UInt8], f: &mut RegfHive, list_raw: Int, count: Int, count_field_off: Int) -> Result[Unit, Str] {
  let r = _resolve_cell(data, f, list_raw, REGF_KIND_UNKNOWN, count_field_off);
  if !r.is_ok {
    return _err_unit(r.error);
  }
  let abs: Int = r.value;
  let ci = _cell_index(f, abs);
  let csz: Int = f.cell_sizes[ci];
  if 4 + count * 4 > csz {
    return _err_unit_at("regf: bad value list size", abs);
  }
  var j = 0;
  while j < count {
    let voff = abs + 4 + j * 4;
    let vr = _resolve_cell(data, f, _u32(data, voff), REGF_KIND_VK, voff);
    if !vr.is_ok {
      return _err_unit(vr.error);
    }
    let vabs: Int = vr.value;
    let ar = _append_value(data, f, vabs);
    if !ar.is_ok {
      return _err_unit(ar.error);
    }
    f.key_val_indices.push(f.value_offsets.len() - 1);
    j = j + 1;
  }
  return _ok_unit();
}

// --------------------------------------------------
//  Walk
// --------------------------------------------------

// Process key `i` (already discovered, in BFS order): resolve stable and
// volatile subkey lists, add each child key, parse its value list. Keys
// are processed in walk-index order, so the CSR boundaries appended here
// stay contiguous.
fn _process_key(data: &Vec[UInt8], f: &mut RegfHive, i: Int) -> Result[Unit, Str] {
  let cell: Int = f.key_cell_offsets[i];
  let sub_count: Int = f.key_subkey_counts[i];
  let sub_list: Int = f.key_subkey_list_offsets[i];
  if sub_count > 0 {
    let count_off = cell + 24;
    let r = _resolve_subkeys(data, f, sub_list, count_off, 0);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    let kids: Vec[Int] = r.value;
    if kids.len() != sub_count {
      return _err_unit_at("regf: subkey count mismatch", count_off);
    }
    var j = 0;
    while j < kids.len() {
      let ka: Int = kids[j];
      let ar = _add_key(data, f, ka, i);
      if !ar.is_ok {
        return _err_unit(ar.error);
      }
      f.key_sub_offsets.push(ar.value);
      j = j + 1;
    }
  }
  let vol_count: Int = f.key_volatile_subkey_counts[i];
  let vol_list: Int = f.key_volatile_subkey_list_offsets[i];
  if vol_count > 0 && vol_list != REGF_OFFSET_NONE {
    let count_off = cell + 28;
    let r = _resolve_subkeys(data, f, vol_list, count_off, 0);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    let kids: Vec[Int] = r.value;
    if kids.len() != vol_count {
      return _err_unit_at("regf: subkey count mismatch", count_off);
    }
    var j = 0;
    while j < kids.len() {
      let ka: Int = kids[j];
      let ar = _add_key(data, f, ka, i);
      if !ar.is_ok {
        return _err_unit(ar.error);
      }
      f.key_sub_offsets.push(ar.value);
      j = j + 1;
    }
  }
  let vcount: Int = f.key_value_counts[i];
  let vlist: Int = f.key_value_list_offsets[i];
  if vcount > 0 {
    let count_off = cell + 40;
    let r = _read_value_list(data, f, vlist, vcount, count_off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
  }
  f.key_sub_index.push(f.key_sub_offsets.len());
  f.key_val_index.push(f.key_val_indices.len());
  return _ok_unit();
}

// --------------------------------------------------
//  Parse
// --------------------------------------------------

/// Parse a Windows Registry hive (REGF) structure.
///
/// Validates, in order: the base block (length, signature, version 1.3..
/// 1.5, file type 0..2, format 1, hive-bins data size, root cell offset),
/// every hbin (signature, monotonic offset-from-first, 4096-multiple size
/// inside the declared region) and every cell (signed size: negative =
/// allocated, positive = free; 8-byte aligned, at least 8 bytes, inside
/// its hbin), then walks the key tree from the root nk in BFS order:
/// subkey lists (lf/lh/li/ri), value lists (vk), value data (inline,
/// direct or db big data) and the security cell of every key. A
/// primary/secondary sequence mismatch is recorded as a warning
/// (regf_sequence_mismatch) and does not fail the parse.
///
/// On success the returned RegfHive holds the base block fields, every
/// hbin, every cell (allocated and free/deleted) and flat key/value
/// tables. Err(m) with a "regf: " message carrying the offending byte
/// offset ("... at 0x......... ") on malformed input; no partial hive is
/// returned. Byte-level accessors take `data` back. Complexity: O(data
/// length) for the cell table, O(cells log cells) for offset lookups.
pub fn regf_parse(data: &Vec[UInt8]) -> Result[RegfHive, Str] {
  var f = RegfHive{
    primary_seq: 0;
    secondary_seq: 0;
    timestamp: 0;
    major: 0;
    minor: 0;
    file_type: 0;
    file_format: 0;
    root_cell_offset: 0;
    hbin_data_size: 0;
    cluster_factor: 0;
    checksum: 0;
    file_name: "";
    warn_sequence: 0;
    root_offset: 0;
    hbin_offsets: Vec[Int].new();
    hbin_rel_offsets: Vec[Int].new();
    hbin_sizes: Vec[Int].new();
    hbin_timestamps: Vec[Int].new();
    hbin_spares: Vec[Int].new();
    cell_offsets: Vec[Int].new();
    cell_sizes: Vec[Int].new();
    cell_allocated: Vec[Int].new();
    cell_kinds: Vec[Int].new();
    cell_hbin_index: Vec[Int].new();
    key_cell_offsets: Vec[Int].new();
    key_flags: Vec[Int].new();
    key_timestamps: Vec[Int].new();
    key_access_bits: Vec[Int].new();
    key_parent_offsets: Vec[Int].new();
    key_subkey_counts: Vec[Int].new();
    key_volatile_subkey_counts: Vec[Int].new();
    key_subkey_list_offsets: Vec[Int].new();
    key_volatile_subkey_list_offsets: Vec[Int].new();
    key_value_counts: Vec[Int].new();
    key_value_list_offsets: Vec[Int].new();
    key_security_offsets: Vec[Int].new();
    key_class_offsets: Vec[Int].new();
    key_largest_subkey_name: Vec[Int].new();
    key_largest_subkey_class: Vec[Int].new();
    key_largest_value_name: Vec[Int].new();
    key_largest_value_data: Vec[Int].new();
    key_work_var: Vec[Int].new();
    key_name_lengths: Vec[Int].new();
    key_class_name_lengths: Vec[Int].new();
    key_names: Vec[Str].new();
    key_parent_key_index: Vec[Int].new();
    key_sk_offsets: Vec[Int].new();
    key_sk_refcounts: Vec[Int].new();
    key_sk_sizes: Vec[Int].new();
    key_sk_flags: Vec[Int].new();
    key_sub_index: Vec[Int].new();
    key_sub_offsets: Vec[Int].new();
    key_val_index: Vec[Int].new();
    key_val_indices: Vec[Int].new();
    value_offsets: Vec[Int].new();
    value_name_lengths: Vec[Int].new();
    value_data_sizes: Vec[Int].new();
    value_data_types: Vec[Int].new();
    value_data_offsets: Vec[Int].new();
    value_flags: Vec[Int].new();
    value_names: Vec[Str].new();
    value_inline: Vec[Int].new();
    value_big: Vec[Int].new();
    value_seg_count: Vec[Int].new();
    value_seg_index: Vec[Int].new();
    value_seg_offsets: Vec[Int].new();
    value_seg_sizes: Vec[Int].new();
  };
  let r1 = _read_base(data, &mut f);
  if !r1.is_ok {
    return _err_hive(r1.error);
  }
  let r2 = _read_hbins(data, &mut f);
  if !r2.is_ok {
    return _err_hive(r2.error);
  }
  let cr = _resolve_cell(data, &f, f.root_cell_offset, REGF_KIND_NK, 36);
  if !cr.is_ok {
    return _err_hive(cr.error);
  }
  let root_abs: Int = cr.value;
  f.root_offset = root_abs;
  f.key_sub_index.push(0);
  f.key_val_index.push(0);
  let kr = _add_key(data, &mut f, root_abs, -1);
  if !kr.is_ok {
    return _err_hive(kr.error);
  }
  var head = 0;
  while head < f.key_cell_offsets.len() {
    let pr = _process_key(data, &mut f, head);
    if !pr.is_ok {
      return _err_hive(pr.error);
    }
    head = head + 1;
  }
  f.value_seg_index.push(f.value_seg_offsets.len());
  return _ok_hive(f);
}

// --------------------------------------------------
//  Hive accessors
// --------------------------------------------------

/// Base block primary sequence number. Complexity: O(1).
pub fn regf_primary_sequence(f: &RegfHive) -> Int {
  return f.primary_seq;
}

/// Base block secondary sequence number. Complexity: O(1).
pub fn regf_secondary_sequence(f: &RegfHive) -> Int {
  return f.secondary_seq;
}

/// True when the primary and secondary sequence numbers differ (a
/// warning state: the parse still succeeds). Complexity: O(1).
pub fn regf_sequence_mismatch(f: &RegfHive) -> Bool {
  return f.warn_sequence == 1;
}

/// Base block last-written timestamp (raw u64 two's-complement Int).
/// Complexity: O(1).
pub fn regf_timestamp(f: &RegfHive) -> Int {
  return f.timestamp;
}

/// Base block major version. Complexity: O(1).
pub fn regf_version_major(f: &RegfHive) -> Int {
  return f.major;
}

/// Base block minor version. Complexity: O(1).
pub fn regf_version_minor(f: &RegfHive) -> Int {
  return f.minor;
}

/// Base block file type (0 primary, 1 log, 2 external). Complexity: O(1).
pub fn regf_file_type(f: &RegfHive) -> Int {
  return f.file_type;
}

/// Base block file format (1 for this parser). Complexity: O(1).
pub fn regf_file_format(f: &RegfHive) -> Int {
  return f.file_format;
}

/// Raw root cell offset (hive-bins-relative). Complexity: O(1).
pub fn regf_root_cell_offset(f: &RegfHive) -> Int {
  return f.root_cell_offset;
}

/// Absolute file offset of the root nk cell. Complexity: O(1).
pub fn regf_root_offset(f: &RegfHive) -> Int {
  return f.root_offset;
}

/// Declared hive-bins data size in bytes. Complexity: O(1).
pub fn regf_hbin_data_size(f: &RegfHive) -> Int {
  return f.hbin_data_size;
}

/// Base block cluster factor as stored (pass-through). Complexity: O(1).
pub fn regf_cluster_factor(f: &RegfHive) -> Int {
  return f.cluster_factor;
}

/// Base block checksum field as stored (not validated). Complexity: O(1).
pub fn regf_checksum(f: &RegfHive) -> Int {
  return f.checksum;
}

/// Base block file name, decoded from UTF-16LE up to the first NUL
/// (non-ASCII code units decode to UTF-8). Complexity: O(1).
pub fn regf_file_name(f: &RegfHive) -> Str {
  return f.file_name;
}

// --------------------------------------------------
//  hbin accessors
// --------------------------------------------------

/// Number of parsed hbin blocks. Complexity: O(1).
pub fn regf_hbin_count(f: &RegfHive) -> Int {
  return f.hbin_offsets.len();
}

/// Absolute file offset of hbin `i`. Complexity: O(1).
pub fn regf_hbin_offset(f: &RegfHive, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.hbin_offsets.len() {
    return _err_int("regf: index out of range");
  }
  let v: Int = f.hbin_offsets[i];
  return _ok_int(v);
}

/// Offset-from-first-hbin of hbin `i`. Complexity: O(1).
pub fn regf_hbin_rel_offset(f: &RegfHive, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.hbin_rel_offsets.len() {
    return _err_int("regf: index out of range");
  }
  let v: Int = f.hbin_rel_offsets[i];
  return _ok_int(v);
}

/// Declared size of hbin `i` (multiple of 4096). Complexity: O(1).
pub fn regf_hbin_size(f: &RegfHive, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.hbin_sizes.len() {
    return _err_int("regf: index out of range");
  }
  let v: Int = f.hbin_sizes[i];
  return _ok_int(v);
}

/// hbin `i` timestamp (raw u64 two's-complement Int). Complexity: O(1).
pub fn regf_hbin_timestamp(f: &RegfHive, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.hbin_timestamps.len() {
    return _err_int("regf: index out of range");
  }
  let v: Int = f.hbin_timestamps[i];
  return _ok_int(v);
}

/// hbin `i` spare field as stored. Complexity: O(1).
pub fn regf_hbin_spare(f: &RegfHive, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.hbin_spares.len() {
    return _err_int("regf: index out of range");
  }
  let v: Int = f.hbin_spares[i];
  return _ok_int(v);
}

// --------------------------------------------------
//  Cell accessors
// --------------------------------------------------

/// Number of cells across all hbins. Complexity: O(1).
pub fn regf_cell_count(f: &RegfHive) -> Int {
  return f.cell_offsets.len();
}

/// Absolute file offset of cell `i`. Complexity: O(1).
pub fn regf_cell_offset(f: &RegfHive, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.cell_offsets.len() {
    return _err_int("regf: index out of range");
  }
  let v: Int = f.cell_offsets[i];
  return _ok_int(v);
}

/// Absolute size of cell `i` (including the 4-byte size field).
/// Complexity: O(1).
pub fn regf_cell_size(f: &RegfHive, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.cell_sizes.len() {
    return _err_int("regf: index out of range");
  }
  let v: Int = f.cell_sizes[i];
  return _ok_int(v);
}

/// 1 when cell `i` is allocated (negative size field), 0 when free
/// (deleted). Complexity: O(1).
pub fn regf_cell_allocated(f: &RegfHive, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.cell_allocated.len() {
    return _err_int("regf: index out of range");
  }
  let v: Int = f.cell_allocated[i];
  return _ok_int(v);
}

/// Best-effort REGF_KIND_* tag of cell `i` from its first two data bytes
/// (also applied to free cells, so a deleted nk stays visible).
/// Complexity: O(1).
pub fn regf_cell_kind(f: &RegfHive, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.cell_kinds.len() {
    return _err_int("regf: index out of range");
  }
  let v: Int = f.cell_kinds[i];
  return _ok_int(v);
}

/// Index of the hbin containing cell `i`. Complexity: O(1).
pub fn regf_cell_hbin(f: &RegfHive, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.cell_hbin_index.len() {
    return _err_int("regf: index out of range");
  }
  let v: Int = f.cell_hbin_index[i];
  return _ok_int(v);
}

/// Number of free (deleted) cells. Complexity: O(cells).
pub fn regf_free_cell_count(f: &RegfHive) -> Int {
  var n = 0;
  var i = 0;
  while i < f.cell_allocated.len() {
    let a: Int = f.cell_allocated[i];
    if a == 0 {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Number of free cells whose bytes still tag as nk (deleted keys).
/// Complexity: O(cells).
pub fn regf_deleted_nk_count(f: &RegfHive) -> Int {
  var n = 0;
  var i = 0;
  while i < f.cell_allocated.len() {
    let a: Int = f.cell_allocated[i];
    let k: Int = f.cell_kinds[i];
    if a == 0 && k == REGF_KIND_NK {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Cell-table index of the cell whose size field starts at absolute
/// `off`, or -1 when no cell starts there. Complexity: O(log cells).
pub fn regf_cell_index_by_offset(f: &RegfHive, off: Int) -> Int {
  return _cell_index(f, off);
}

// --------------------------------------------------
//  Key accessors
// --------------------------------------------------

/// Number of keys discovered by the BFS walk (the root is key 0).
/// Complexity: O(1).
pub fn regf_key_count(f: &RegfHive) -> Int {
  return f.key_cell_offsets.len();
}

/// Decoded name of key `i` (ASCII or UTF-16LE per the nk flags).
/// Err("regf: index out of range") for a bad index. The returned Str is
/// read from a Vec[Str] field: compare with regf_name_equal, not `==`.
/// Complexity: O(1).
pub fn regf_key_name(f: &RegfHive, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= f.key_names.len() {
    return _err_str("regf: index out of range");
  }
  let nm: Str = f.key_names[i];
  return _ok_str(nm);
}

/// Walk index of the parent of key `i`, or -1 for the root.
/// Complexity: O(1).
pub fn regf_key_parent(f: &RegfHive, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.key_parent_key_index.len() {
    return _err_int("regf: index out of range");
  }
  let v: Int = f.key_parent_key_index[i];
  return _ok_int(v);
}

/// Number of children of key `i` in the walk (stable + volatile).
/// Complexity: O(1).
pub fn regf_key_subkey_count(f: &RegfHive, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.key_cell_offsets.len() {
    return _err_int("regf: index out of range");
  }
  let lo: Int = f.key_sub_index[i];
  let hi: Int = f.key_sub_index[i + 1];
  return _ok_int(hi - lo);
}

/// Walk index of child `j` of key `i`, in subkey-list order.
/// Complexity: O(1).
pub fn regf_key_subkey(f: &RegfHive, i: Int, j: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.key_cell_offsets.len() {
    return _err_int("regf: index out of range");
  }
  let lo: Int = f.key_sub_index[i];
  let hi: Int = f.key_sub_index[i + 1];
  if j < 0 || j >= hi - lo {
    return _err_int("regf: index out of range");
  }
  let v: Int = f.key_sub_offsets[lo + j];
  return _ok_int(v);
}

/// Number of values of key `i` in the walk. Complexity: O(1).
pub fn regf_key_value_count(f: &RegfHive, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.key_cell_offsets.len() {
    return _err_int("regf: index out of range");
  }
  let lo: Int = f.key_val_index[i];
  let hi: Int = f.key_val_index[i + 1];
  return _ok_int(hi - lo);
}

/// Global value index of value `j` of key `i`, in value-list order.
/// Complexity: O(1).
pub fn regf_key_value(f: &RegfHive, i: Int, j: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.key_cell_offsets.len() {
    return _err_int("regf: index out of range");
  }
  let lo: Int = f.key_val_index[i];
  let hi: Int = f.key_val_index[i + 1];
  if j < 0 || j >= hi - lo {
    return _err_int("regf: index out of range");
  }
  let v: Int = f.key_val_indices[lo + j];
  return _ok_int(v);
}

// ASCII-case-insensitive name equality (byte >= 128 compares exactly).
// Str values are folded with xiom.string.str_lower and compared with
// str_compare (BUG 17 discipline: `==` on a Str read from a Vec lowers to
// a pointer comparison). Complexity: O(len(a) + len(b)).
pub fn regf_name_equal(a: Str, b: Str) -> Bool {
  return string.str_compare(string.str_lower(a), string.str_lower(b)) == 0;
}

// Byte at `pos` of a Str widened to an Int (0..255); callers bound-check.
fn _str_byte(s: Str, pos: Int) -> Int {
  return (s.byte_at(pos) as Int) & 0xFF;
}

/// Walk index of the child of key `i` whose name equals `name`
/// (case-insensitive), or -1 when absent. Complexity: O(children * name
/// length).
pub fn regf_key_find(f: &RegfHive, i: Int, name: Str) -> Int {
  if i < 0 || i >= f.key_cell_offsets.len() {
    return -1;
  }
  let lo: Int = f.key_sub_index[i];
  let hi: Int = f.key_sub_index[i + 1];
  var j = lo;
  while j < hi {
    let ci: Int = f.key_sub_offsets[j];
    let cand: Str = f.key_names[ci];
    if regf_name_equal(cand, name) {
      return ci;
    }
    j = j + 1;
  }
  return -1;
}

/// Resolve a backslash-separated path from the root key. The first
/// component may name the root itself (case-insensitive); later
/// components are matched case-insensitively against children. Empty
/// components (leading, trailing or doubled separators) are skipped; the
/// root itself is the empty path or a path of separators only.
/// Err("regf: key not found") when a component has no match.
/// Complexity: O(components * children * name length).
pub fn regf_path_resolve(f: &RegfHive, path: Str) -> Result[Int, Str] {
  let n = path.len();
  var cur = 0;
  var start = 0;
  var k = 0;
  while k <= n {
    var is_sep = false;
    if k < n {
      if _str_byte(path, k) == 92 {
        is_sep = true;
      }
    }
    if k == n || is_sep {
      if k > start {
        let seg = string.str_slice(path, start, k);
        if seg.len() > 0 {
          var matched = false;
          if cur == 0 {
            let root_name: Str = f.key_names[0];
            if regf_name_equal(root_name, seg) {
              matched = true;
            }
          }
          if !matched {
            let ci = regf_key_find(f, cur, seg);
            if ci < 0 {
              return _err_int("regf: key not found");
            }
            cur = ci;
          }
        }
      }
      start = k + 1;
    }
    k = k + 1;
  }
  return _ok_int(cur);
}

/// Raw nk field `field` (a REGF_KEY_FIELD_* selector) of key `i`.
///
/// Err("regf: index out of range") for a bad key index, Err("regf: bad
/// field selector") for an unknown selector. Offsets stay raw
/// (hive-bins-relative); REGF_KEY_FIELD_PARENT_OFFSET is 0xFFFFFFFF for
/// the root. REGF_KEY_FIELD_SUBKEY_LIST_COUNT / VALUE_LIST_COUNT are the
/// walked child/value counts (0 when the raw count was 0). No range or
/// semantic validation is applied to the field. Complexity: O(1).
pub fn regf_key_field(f: &RegfHive, i: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.key_cell_offsets.len() {
    return _err_int("regf: index out of range");
  }
  if field == REGF_KEY_FIELD_FLAGS {
    let v: Int = f.key_flags[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_TIMESTAMP {
    let v: Int = f.key_timestamps[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_ACCESS_BITS {
    let v: Int = f.key_access_bits[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_PARENT_OFFSET {
    let v: Int = f.key_parent_offsets[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_SUBKEY_COUNT {
    let v: Int = f.key_subkey_counts[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_VOLATILE_SUBKEY_COUNT {
    let v: Int = f.key_volatile_subkey_counts[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_SUBKEY_LIST_OFFSET {
    let v: Int = f.key_subkey_list_offsets[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_VOLATILE_SUBKEY_LIST_OFFSET {
    let v: Int = f.key_volatile_subkey_list_offsets[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_VALUE_COUNT {
    let v: Int = f.key_value_counts[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_VALUE_LIST_OFFSET {
    let v: Int = f.key_value_list_offsets[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_SECURITY_OFFSET {
    let v: Int = f.key_security_offsets[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_CLASS_OFFSET {
    let v: Int = f.key_class_offsets[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_LARGEST_SUBKEY_NAME {
    let v: Int = f.key_largest_subkey_name[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_LARGEST_SUBKEY_CLASS {
    let v: Int = f.key_largest_subkey_class[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_LARGEST_VALUE_NAME {
    let v: Int = f.key_largest_value_name[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_LARGEST_VALUE_DATA {
    let v: Int = f.key_largest_value_data[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_WORK_VAR {
    let v: Int = f.key_work_var[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_NAME_LENGTH {
    let v: Int = f.key_name_lengths[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_CLASS_NAME_LENGTH {
    let v: Int = f.key_class_name_lengths[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_CELL_OFFSET {
    let v: Int = f.key_cell_offsets[i];
    return _ok_int(v);
  }
  if field == REGF_KEY_FIELD_SUBKEY_LIST_COUNT {
    let lo: Int = f.key_sub_index[i];
    let hi: Int = f.key_sub_index[i + 1];
    return _ok_int(hi - lo);
  }
  if field == REGF_KEY_FIELD_VALUE_LIST_COUNT {
    let lo: Int = f.key_val_index[i];
    let hi: Int = f.key_val_index[i + 1];
    return _ok_int(hi - lo);
  }
  return _err_int("regf: bad field selector");
}

/// Field `field` (a REGF_SK_FIELD_* selector) of the sk cell referenced
/// by key `i`; -1 / 0 when the key has no security cell (offset 0 or
/// 0xFFFFFFFF). Complexity: O(1).
pub fn regf_key_sk(f: &RegfHive, i: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.key_sk_offsets.len() {
    return _err_int("regf: index out of range");
  }
  if field == REGF_SK_FIELD_OFFSET {
    let v: Int = f.key_sk_offsets[i];
    return _ok_int(v);
  }
  if field == REGF_SK_FIELD_REFERENCE_COUNT {
    let v: Int = f.key_sk_refcounts[i];
    return _ok_int(v);
  }
  if field == REGF_SK_FIELD_DESCRIPTOR_SIZE {
    let v: Int = f.key_sk_sizes[i];
    return _ok_int(v);
  }
  if field == REGF_SK_FIELD_FLAGS {
    let v: Int = f.key_sk_flags[i];
    return _ok_int(v);
  }
  return _err_int("regf: bad field selector");
}

// --------------------------------------------------
//  Value accessors
// --------------------------------------------------

/// Number of parsed vk records. Complexity: O(1).
pub fn regf_value_count(f: &RegfHive) -> Int {
  return f.value_offsets.len();
}

/// Raw vk field `field` (a REGF_VALUE_FIELD_* selector) of value `i`.
///
/// Err("regf: index out of range") for a bad index, Err("regf: bad field
/// selector") for an unknown selector. DATA_SIZE is the size with the
/// inline bit removed; DATA_OFFSET is the raw field (inline bytes live
/// there); INLINE / BIG_DATA are 1/0; SEGMENT_COUNT is 0 for inline and
/// empty data. Complexity: O(1).
pub fn regf_value_field(f: &RegfHive, i: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.value_offsets.len() {
    return _err_int("regf: index out of range");
  }
  if field == REGF_VALUE_FIELD_NAME_LENGTH {
    let v: Int = f.value_name_lengths[i];
    return _ok_int(v);
  }
  if field == REGF_VALUE_FIELD_DATA_SIZE {
    let v: Int = f.value_data_sizes[i];
    return _ok_int(v);
  }
  if field == REGF_VALUE_FIELD_DATA_OFFSET {
    let v: Int = f.value_data_offsets[i];
    return _ok_int(v);
  }
  if field == REGF_VALUE_FIELD_DATA_TYPE {
    let v: Int = f.value_data_types[i];
    return _ok_int(v);
  }
  if field == REGF_VALUE_FIELD_FLAGS {
    let v: Int = f.value_flags[i];
    return _ok_int(v);
  }
  if field == REGF_VALUE_FIELD_CELL_OFFSET {
    let v: Int = f.value_offsets[i];
    return _ok_int(v);
  }
  if field == REGF_VALUE_FIELD_INLINE {
    let v: Int = f.value_inline[i];
    return _ok_int(v);
  }
  if field == REGF_VALUE_FIELD_BIG_DATA {
    let v: Int = f.value_big[i];
    return _ok_int(v);
  }
  if field == REGF_VALUE_FIELD_SEGMENT_COUNT {
    let v: Int = f.value_seg_count[i];
    return _ok_int(v);
  }
  return _err_int("regf: bad field selector");
}

/// Decoded name of value `i` (ASCII or UTF-16LE per the vk flags).
/// Complexity: O(1).
pub fn regf_value_name(f: &RegfHive, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= f.value_names.len() {
    return _err_str("regf: index out of range");
  }
  let nm: Str = f.value_names[i];
  return _ok_str(nm);
}

/// Raw value data of value `i` as bytes, reassembling inline, direct and
/// big-data storage. `data` is the buffer passed to regf_parse.
/// Complexity: O(data size).
pub fn regf_value_data(data: &Vec[UInt8], f: &RegfHive, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= f.value_offsets.len() {
    return _err_bytes("regf: index out of range");
  }
  var out = Vec[UInt8].new();
  let inline: Int = f.value_inline[i];
  let dsize: Int = f.value_data_sizes[i];
  if inline == 1 {
    let vk: Int = f.value_offsets[i];
    var k = 0;
    while k < dsize {
      out.push(_byte(data, vk + 12 + k) as UInt8);
      k = k + 1;
    }
    return _ok_bytes(out);
  }
  let lo: Int = f.value_seg_index[i];
  let hi: Int = f.value_seg_index[i + 1];
  var j = lo;
  while j < hi {
    let cell: Int = f.value_seg_offsets[j];
    let n: Int = f.value_seg_sizes[j];
    var k = 0;
    while k < n {
      out.push(_byte(data, cell + 4 + k) as UInt8);
      k = k + 1;
    }
    j = j + 1;
  }
  return _ok_bytes(out);
}

/// REG_DWORD (LE) / REG_DWORD_BIG_ENDIAN value `i` as an Int.
/// Err("regf: value is not a dword") unless the type is 4 or 5 and the
/// data size is exactly 4. Complexity: O(1).
pub fn regf_value_dword(data: &Vec[UInt8], f: &RegfHive, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.value_offsets.len() {
    return _err_int("regf: index out of range");
  }
  let dtype: Int = f.value_data_types[i];
  let dsize: Int = f.value_data_sizes[i];
  if dsize != 4 {
    return _err_int("regf: value is not a dword");
  }
  if dtype != REGF_REG_DWORD && dtype != REGF_REG_DWORD_BIG_ENDIAN {
    return _err_int("regf: value is not a dword");
  }
  let dr = regf_value_data(data, f, i);
  if !dr.is_ok {
    return _err_int(dr.error);
  }
  let b: Vec[UInt8] = dr.value;
  let b0 = (b[0] as Int) & 0xFF;
  let b1 = (b[1] as Int) & 0xFF;
  let b2 = (b[2] as Int) & 0xFF;
  let b3 = (b[3] as Int) & 0xFF;
  if dtype == REGF_REG_DWORD_BIG_ENDIAN {
    return _ok_int(b0 * 16777216 + b1 * 65536 + b2 * 256 + b3);
  }
  return _ok_int(b0 + b1 * 256 + b2 * 65536 + b3 * 16777216);
}

/// REG_QWORD value `i` as the raw little-endian two's-complement Int.
/// Err("regf: value is not a qword") unless the type is 11 and the data
/// size is exactly 8. Complexity: O(1).
pub fn regf_value_qword(data: &Vec[UInt8], f: &RegfHive, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.value_offsets.len() {
    return _err_int("regf: index out of range");
  }
  let dtype: Int = f.value_data_types[i];
  let dsize: Int = f.value_data_sizes[i];
  if dsize != 8 || dtype != REGF_REG_QWORD {
    return _err_int("regf: value is not a qword");
  }
  let dr = regf_value_data(data, f, i);
  if !dr.is_ok {
    return _err_int(dr.error);
  }
  let b: Vec[UInt8] = dr.value;
  var low: Int = 0;
  var place: Int = 1;
  var k = 0;
  while k < 7 {
    let bb = (b[k] as Int) & 0xFF;
    low = low + bb * place;
    place = place * 256;
    k = k + 1;
  }
  let top = (b[7] as Int) & 0xFF;
  if top < 128 {
    return _ok_int(low + top * place);
  }
  let t = top - 128;
  return _ok_int(low + t * place + (0 - 9223372036854775807 - 1));
}

/// REG_SZ / REG_EXPAND_SZ value `i` decoded from UTF-16LE, with one
/// trailing NUL code unit removed when present.
/// Err("regf: value is not a string") for other types. Complexity: O(data
/// size).
pub fn regf_value_str(data: &Vec[UInt8], f: &RegfHive, i: Int) -> Result[Str, Str] {
  if i < 0 || i >= f.value_offsets.len() {
    return _err_str("regf: index out of range");
  }
  let dtype: Int = f.value_data_types[i];
  if dtype != REGF_REG_SZ && dtype != REGF_REG_EXPAND_SZ {
    return _err_str("regf: value is not a string");
  }
  let dr = regf_value_data(data, f, i);
  if !dr.is_ok {
    return _err_str(dr.error);
  }
  let b: Vec[UInt8] = dr.value;
  var n = b.len();
  if n >= 2 {
    let z0 = (b[n - 2] as Int) & 0xFF;
    let z1 = (b[n - 1] as Int) & 0xFF;
    if z0 == 0 && z1 == 0 {
      n = n - 2;
    }
  }
  return _ok_str(_utf16le_bytes_to_str(&b, 0, n));
}

/// REG_MULTI_SZ value `i` decoded from UTF-16LE into NUL-separated
/// strings (empty groups dropped, so a terminating double NUL adds
/// nothing). Err("regf: value is not a multi string") for other types.
/// Complexity: O(data size).
pub fn regf_value_multi_str(data: &Vec[UInt8], f: &RegfHive, i: Int) -> Result[Vec[Str], Str] {
  if i < 0 || i >= f.value_offsets.len() {
    return _err_strs("regf: index out of range");
  }
  let dtype: Int = f.value_data_types[i];
  if dtype != REGF_REG_MULTI_SZ {
    return _err_strs("regf: value is not a multi string");
  }
  let dr = regf_value_data(data, f, i);
  if !dr.is_ok {
    return _err_strs(dr.error);
  }
  let b: Vec[UInt8] = dr.value;
  let n = b.len();
  return _ok_strs(_utf16le_multi(&b, 0, n));
}
