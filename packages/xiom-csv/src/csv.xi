// XIOM -- xiom.csv: CSV parsing and writing with RFC 4180-style quoting
// Port task: replace the xiom.csv placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Reader model matches xiom.serialize.csv in the standard library: fields are
// separated by commas; records end at LF, CR or CRLF (a CRLF pair is one
// boundary); a trailing terminator at EOF does not produce an extra empty
// record; a quoted field may contain commas, CR/LF and doubled quotes
// ("" = literal "). This module exposes an infallible Vec-returning API (no
// Result channel), so a quoted field left unterminated at EOF is closed
// leniently and contributes its content (documented in SPEC.md).
//
// Writer model: quote a field only when csv_needs_quoting reports it, double
// embedded quotes, join rows with LF and emit no trailing terminator.

module xiom.csv

use xiom.string;

const _CSV_COMMA: UInt8 = 44u8;
const _CSV_QUOTE: UInt8 = 34u8;
const _CSV_SPACE: UInt8 = 32u8;
const _CSV_CR: UInt8 = 13u8;
const _CSV_LF: UInt8 = 10u8;

/// Parse a single CSV record (no embedded record terminators expected).
/// Params: text - one record, possibly using RFC 4180 quoting.
/// Returns: the record's fields. Empty text yields one empty field (the
/// RFC 4180 record with a single empty field); text containing several
/// records yields the first record only.
/// Error case: none.
/// Complexity: O(n).
pub fn csv_parse_line(text: Str) -> Vec[Str] {
  let rows = csv_parse(text);
  var out = Vec[Str].new();
  if rows.len() == 0 {
    out.push("");
    return out;
  }
  var i = 0;
  while i < rows[0].len() {
    out.push(rows[0][i]);
    i = i + 1;
  }
  return out;
}

/// Parse a whole CSV document into records of fields.
/// Params: text - the document; LF, CR and CRLF all terminate records, and a
/// CRLF pair counts as one terminator.
/// Returns: one Vec[Str] per record. Empty text produces no records; a single
/// trailing terminator produces no extra empty record; a blank line produces
/// one record with a single empty field. UTF-8 passes through byte-exact.
/// Error case: none; an unterminated quoted field is closed at EOF.
/// Complexity: O(n).
pub fn csv_parse(text: Str) -> Vec[Vec[Str]] {
  var rows = Vec[Vec[Str]].new();
  let len = text.len();
  if len == 0 {
    return rows;
  }
  var record = Vec[Str].new();
  var field = Vec[UInt8].new();
  var in_quotes = false;
  var record_open = false;
  var i = 0;
  while i < len {
    let b = string.byte_at(text, i);
    if in_quotes {
      if b == _CSV_QUOTE {
        if i + 1 < len && string.byte_at(text, i + 1) == _CSV_QUOTE {
          field.push(_CSV_QUOTE);
          i = i + 2;
        } else {
          in_quotes = false;
          i = i + 1;
        }
      } else {
        field.push(b);
        i = i + 1;
      }
    } elif b == _CSV_QUOTE {
      in_quotes = true;
      record_open = true;
      i = i + 1;
    } elif b == _CSV_COMMA {
      record.push(Str::from_utf8(field));
      field = Vec[UInt8].new();
      record_open = true;
      i = i + 1;
    } elif b == _CSV_CR || b == _CSV_LF {
      record.push(Str::from_utf8(field));
      field = Vec[UInt8].new();
      rows.push(record);
      record = Vec[Str].new();
      record_open = false;
      if b == _CSV_CR && i + 1 < len && string.byte_at(text, i + 1) == _CSV_LF {
        i = i + 2;
      } else {
        i = i + 1;
      }
    } else {
      field.push(b);
      record_open = true;
      i = i + 1;
    }
  }
  if record_open || field.len() > 0 || record.len() > 0 {
    record.push(Str::from_utf8(field));
    rows.push(record);
  }
  return rows;
}

/// True when a field must be quoted to survive a write-then-parse round trip.
/// Params: field - the field text.
/// Returns: true when field contains a comma, a double quote, LF or CR, or
/// when it starts or ends with an ASCII space. False for the empty string.
/// Complexity: O(n).
pub fn csv_needs_quoting(field: Str) -> Bool {
  let len = field.len();
  if len == 0 {
    return false;
  }
  if string.byte_at(field, 0) == _CSV_SPACE {
    return true;
  }
  if string.byte_at(field, len - 1) == _CSV_SPACE {
    return true;
  }
  var i = 0;
  while i < len {
    let b = string.byte_at(field, i);
    if b == _CSV_COMMA || b == _CSV_QUOTE || b == _CSV_CR || b == _CSV_LF {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Quote and escape one field: wrap in quotes only when csv_needs_quoting,
// doubling every embedded quote. UTF-8 passes through byte-exact.
fn _quote_field(field: Str) -> Str {
  if !csv_needs_quoting(field) {
    return field;
  }
  var out = "\"";
  var i = 0;
  while i < field.len() {
    let b = string.byte_at(field, i);
    if b == _CSV_QUOTE {
      out = out + "\"\"";
    } else {
      out = out + string.str_slice(field, i, i + 1);
    }
    i = i + 1;
  }
  return out + "\"";
}

/// Serialize one record (fields joined with commas, no terminator).
/// Params: fields - the record's fields.
/// Returns: the encoded record; fields needing it are quoted and escaped.
/// Error case: none.
/// Complexity: O(n) over the total field length.
pub fn csv_write_row(fields: &Vec[Str]) -> Str {
  var out = "";
  var i = 0;
  while i < fields.len() {
    if i > 0 {
      out = out + ",";
    }
    out = out + _quote_field(fields[i]);
    i = i + 1;
  }
  return out;
}

/// Serialize a whole document.
/// Params: rows - the records to write.
/// Returns: records joined with LF and no trailing newline; an empty input
/// yields the empty string.
/// Error case: none.
/// Complexity: O(n) over the total field length.
pub fn csv_write(rows: &Vec[Vec[Str]]) -> Str {
  var out = "";
  var i = 0;
  while i < rows.len() {
    if i > 0 {
      out = out + "\n";
    }
    out = out + csv_write_row(&rows[i]);
    i = i + 1;
  }
  return out;
}

/// True when every record has the same field count.
/// Params: rows - the records to inspect.
/// Returns: true for zero or one records, and for any set of equal-width
/// records (including zero-width records); false when widths differ.
/// Complexity: O(rows).
pub fn csv_is_rectangular(rows: &Vec[Vec[Str]]) -> Bool {
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

/// Look up one cell by row and column index.
/// Params: rows - the records; r - zero-based row index; c - zero-based
/// column index.
/// Returns: Some(field) on a hit, None when r or c is negative or out of
/// range.
/// Complexity: O(1).
pub fn csv_get(rows: &Vec[Vec[Str]], r: Int, c: Int) -> Option[Str] {
  if r < 0 || c < 0 {
    return None;
  }
  if r >= rows.len() {
    return None;
  }
  if c >= rows[r].len() {
    return None;
  }
  return Some(rows[r][c]);
}

/// Field count of the first record.
/// Params: rows - the records to inspect.
/// Returns: the number of fields in rows[0], or 0 when there are no records.
/// Complexity: O(1).
pub fn csv_field_count(rows: &Vec[Vec[Str]]) -> Int {
  if rows.len() == 0 {
    return 0;
  }
  return rows[0].len();
}
