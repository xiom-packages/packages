// XIOM -- xiom.tsv: IANA-style TSV with backslash escaping (parse and write)
// Port task: replace the xiom.tsv placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Reader model (see SPEC.md for the full semantics): fields are separated by
// RAW TAB bytes; records end at LF, and a single trailing CR is stripped when a
// line is terminated by CRLF. Inside a field the escape sequences \\ \t \n \r
// decode to backslash, TAB, LF and CR; any other backslash sequence is
// rejected by tsv_unescape_field/tsv_parse_line with Err("tsv: invalid
// escape"). tsv_parse has no error channel (it returns a Vec), so it decodes
// leniently: an unrecognized backslash sequence is kept verbatim (this matches
// the stdlib's xiom.string.str_unescape policy and keeps write-then-parse
// round trips exact).
//
// Writer model: escape_field maps backslash, TAB, LF and CR to their two-byte
// sequences and passes every other byte (including UTF-8 multi-byte
// sequences) through unchanged; write_row joins fields with a raw TAB;
// tsv_write joins rows with LF and emits no trailing newline.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * No self methods, no inline lambdas, no Vec[StructType], no Vec[fn].
//   * Output bytes are collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str (one allocation per result Str).
//   * Ok/Err for the Result returns are constructed only in the tiny leaf
//     helpers _ok_str/_err_str/_ok_fields/_err_fields (constructing Results
//     directly inside other functions miscompiles in this compiler).
//   * Str equality is never tested with `==` (BUG 17 lowers `==` on Str
//     values read from Vec[Str] elements to a pointer comparison); this module
//     performs no string equality at all, it only scans bytes.

module xiom.tsv

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Result constructors (leaf helpers; see the module header)
// --------------------------------------------------

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Str], Str].
fn _ok_fields(v: Vec[Str]) -> Result[Vec[Str], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Str], Str].
fn _err_fields(m: Str) -> Result[Vec[Str], Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants (all < 128, compared directly against byte_at)
// --------------------------------------------------

const _TSV_TAB: UInt8 = 9u8;
const _TSV_LF: UInt8 = 10u8;
const _TSV_CR: UInt8 = 13u8;
const _TSV_BS: UInt8 = 92u8;
const _TSV_LOWER_N: UInt8 = 110u8;
const _TSV_LOWER_R: UInt8 = 114u8;
const _TSV_LOWER_T: UInt8 = 116u8;

// --------------------------------------------------
//  Escape / unescape
// --------------------------------------------------

/// Escape one field for a TSV document.
/// Params: f - the raw field text.
/// Returns: f with `\` -> `\\`, TAB -> `\t`, LF -> `\n` and CR -> `\r`; every
/// other byte (including UTF-8 multi-byte sequences) passes through untouched.
/// Error case: none.
/// Complexity: O(f.len()).
pub fn tsv_escape_field(f: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = f.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(f, i);
    if b == _TSV_BS {
      builder.sb_push_str(&mut out, "\\\\");
    } elif b == _TSV_TAB {
      builder.sb_push_str(&mut out, "\\t");
    } elif b == _TSV_LF {
      builder.sb_push_str(&mut out, "\\n");
    } elif b == _TSV_CR {
      builder.sb_push_str(&mut out, "\\r");
    } else {
      out.push(b);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// True when every backslash in `f` introduces one of the four valid escapes:
// `\\`, `\t`, `\n` or `\r`. False for a trailing backslash or any other
// sequence. One pass, O(f.len()).
fn _escape_ok(f: Str) -> Bool {
  let n = f.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(f, i);
    if b != _TSV_BS {
      i = i + 1;
    } else {
      if i + 1 >= n {
        return false;
      }
      let e = string.byte_at(f, i + 1);
      if e == _TSV_BS || e == _TSV_LOWER_T || e == _TSV_LOWER_N || e == _TSV_LOWER_R {
        i = i + 2;
      } else {
        return false;
      }
    }
  }
  return true;
}

// Decode `\\` `\t` `\n` `\r` into their bytes; every other byte, including a
// backslash that does not start one of those sequences, is kept verbatim.
// One pass, O(f.len()).
fn _unescape_lenient(f: Str) -> Str {
  var out = Vec[UInt8].new();
  let n = f.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(f, i);
    if b != _TSV_BS {
      out.push(b);
      i = i + 1;
    } else {
      if i + 1 >= n {
        out.push(_TSV_BS);
        i = i + 1;
      } else {
        let e = string.byte_at(f, i + 1);
        if e == _TSV_BS {
          out.push(_TSV_BS);
          i = i + 2;
        } elif e == _TSV_LOWER_T {
          out.push(_TSV_TAB);
          i = i + 2;
        } elif e == _TSV_LOWER_N {
          out.push(_TSV_LF);
          i = i + 2;
        } elif e == _TSV_LOWER_R {
          out.push(_TSV_CR);
          i = i + 2;
        } else {
          out.push(_TSV_BS);
          i = i + 1;
        }
      }
    }
  }
  return builder.sb_to_str(&out);
}

/// Decode one TSV field (inverse of tsv_escape_field).
/// Params: f - the encoded field text (no raw TAB, LF or CR expected).
/// Returns: Ok(text) with `\\` `\t` `\n` `\r` decoded to backslash, TAB, LF
/// and CR. Every other byte, including UTF-8 multi-byte sequences, is copied
/// unchanged.
/// Error case: Err("tsv: invalid escape") - a backslash followed by any byte
/// other than `\`, `t`, `n`, `r`, or a trailing backslash at end of input.
/// Complexity: O(f.len()).
pub fn tsv_unescape_field(f: Str) -> Result[Str, Str] {
  if !_escape_ok(f) {
    return _err_str("tsv: invalid escape");
  }
  return _ok_str(_unescape_lenient(f));
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

// Split one line on RAW tab bytes and strip one trailing CR (the CR of a CRLF
// pair). The raw fields are returned still escaped. `line` must not contain
// LF. One pass, O(line.len()).
fn _line_fields(line: Str) -> Vec[Str] {
  var fields = Vec[Str].new();
  var end = line.len();
  if end > 0 {
    if string.byte_at(line, end - 1) == _TSV_CR {
      end = end - 1;
    }
  }
  var start = 0;
  var i = 0;
  while i < end {
    if string.byte_at(line, i) == _TSV_TAB {
      fields.push(string.str_slice(line, start, i));
      start = i + 1;
    }
    i = i + 1;
  }
  fields.push(string.str_slice(line, start, end));
  return fields;
}

/// Parse one TSV line into its fields.
/// Params: line - one line; raw tabs delimit fields and one trailing CR (the
/// CR of a CRLF pair) is a terminator byte, not data.
/// Returns: Ok(fields) with every field unescaped. Empty input yields one
/// empty field; `"\t"` yields two empty fields. Text containing LF yields the
/// single line's fields as-is (LF is data for this entry point).
/// Error case: Err("tsv: invalid escape") when a field contains a malformed
/// backslash escape.
/// Complexity: O(line.len()).
pub fn tsv_parse_line(line: Str) -> Result[Vec[Str], Str] {
  let raw = _line_fields(line);
  var out = Vec[Str].new();
  var i = 0;
  while i < raw.len() {
    let decoded = tsv_unescape_field(raw[i]);
    if !decoded.is_ok {
      return _err_fields(decoded.error);
    }
    out.push(decoded.value);
    i = i + 1;
  }
  return _ok_fields(out);
}

// Lenient variant of tsv_parse_line used by tsv_parse: malformed escapes are
// kept verbatim instead of failing (tsv_parse has no error channel).
fn _parse_line_lenient(line: Str) -> Vec[Str] {
  let raw = _line_fields(line);
  var out = Vec[Str].new();
  var i = 0;
  while i < raw.len() {
    out.push(_unescape_lenient(raw[i]));
    i = i + 1;
  }
  return out;
}

/// Parse a whole TSV document into rows of fields.
/// Params: text - the document; LF terminates records and one trailing CR per
/// line (a CRLF pair) is stripped.
/// Returns: one Vec[Str] per record. Empty text produces no records; a single
/// trailing newline produces no extra record; a blank line produces one
/// record with a single empty field. Fields are unescaped; because this entry
/// point has no error channel, a malformed backslash escape is kept verbatim
/// (use tsv_parse_line to detect it). UTF-8 passes through byte-exact.
/// Error case: none.
/// Complexity: O(text.len()).
pub fn tsv_parse(text: Str) -> Vec[Vec[Str]] {
  var rows = Vec[Vec[Str]].new();
  let n = text.len();
  if n == 0 {
    return rows;
  }
  var start = 0;
  var i = 0;
  while i < n {
    if string.byte_at(text, i) == _TSV_LF {
      rows.push(_parse_line_lenient(string.str_slice(text, start, i)));
      start = i + 1;
    }
    i = i + 1;
  }
  if start < n {
    rows.push(_parse_line_lenient(string.str_slice(text, start, n)));
  }
  return rows;
}

// --------------------------------------------------
//  Writing
// --------------------------------------------------

/// Serialize one record: fields escaped and joined with a raw TAB.
/// Params: fields - the record's fields.
/// Returns: the encoded record; zero fields yield the empty string.
/// Error case: none.
/// Complexity: O(total field length).
pub fn tsv_write_row(fields: &Vec[Str]) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < fields.len() {
    if i > 0 {
      out.push(_TSV_TAB);
    }
    builder.sb_push_str(&mut out, tsv_escape_field(fields[i]));
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Serialize a whole document.
/// Params: rows - the records to write.
/// Returns: encoded rows joined with LF and no trailing newline; an empty
/// input yields the empty string.
/// Error case: none.
/// Complexity: O(total field length).
pub fn tsv_write(rows: &Vec[Vec[Str]]) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < rows.len() {
    if i > 0 {
      out.push(_TSV_LF);
    }
    builder.sb_push_str(&mut out, tsv_write_row(&rows[i]));
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Inspection
// --------------------------------------------------

/// True when every record has the same field count.
/// Params: rows - the records to inspect.
/// Returns: true for zero or one records, and for any set of equal-width
/// records (including zero-width records); false when widths differ.
/// Complexity: O(rows).
pub fn tsv_is_rectangular(rows: &Vec[Vec[Str]]) -> Bool {
  if rows.len() <= 1 {
    return true;
  }
  let width = rows[0].len();
  var i = 1;
  while i < rows.len() {
    if rows[i].len() != width {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Field count of the first record.
/// Params: rows - the records to inspect.
/// Returns: the number of fields in rows[0], or 0 when there are no records.
/// Complexity: O(1).
pub fn tsv_field_count(rows: &Vec[Vec[Str]]) -> Int {
  if rows.len() == 0 {
    return 0;
  }
  return rows[0].len();
}
