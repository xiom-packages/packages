// XIOM -- xiom.fixed: fixed-width text table parsing and writing
// Port task: greenfield pure-XIOM package for column-width text tables (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
// - Every field occupies exactly widths[c] bytes: parsing slices each line at
//   the cumulative widths, writing left-aligns each cell into its column and
//   pads or truncates it to the column width. Widths are byte counts, never
//   character counts (see the ASCII limitation in SPEC.md).
// - A width <= 0 defines an empty column: parsing yields "" for it and
//   consumes no input, writing emits nothing for it even when a cell exists.
// - Lines end at LF or CRLF; the CR immediately before the LF is dropped and
//   is not field data. A single trailing terminator produces no extra row;
//   empty text produces no rows; a blank line is one row whose fields are
//   all "". A bare CR (no following LF) is ordinary field data.
// - Parsed fields are raw (untrimmed); fixed_parse_trimmed applies
//   xiom.string.str_trim to every field.
// - Written rows are joined with LF and no trailing terminator.
//
// v0.61.3 notes that shaped this module: free functions only (no self methods,
// no lambdas, no Vec[StructType], no Vec[fn]); no `==` on Str values (this
// module performs no string equality at all); byte comparisons widen the
// UInt8 from xiom.string.byte_at to Int; every Vec element read is bound with
// an explicit type; all byte work goes through xiom.string helpers.

module xiom.fixed

use xiom.string;

const _FIXED_CR: Int = 13;
const _FIXED_LF: Int = 10;

/// Total byte width of a column layout.
/// Params: widths - the column widths, read only.
/// Returns: the sum of the non-negative widths (zero and negative widths add
/// nothing). An empty layout has total width 0.
/// Error case: none.
/// Complexity: O(widths).
pub fn fixed_total_width(widths: &Vec[Int]) -> Int {
  var total = 0;
  var i = 0;
  while i < widths.len() {
    let w: Int = widths[i];
    if w > 0 {
      total = total + w;
    }
    i = i + 1;
  }
  return total;
}

/// Number of columns defined by a layout.
/// Params: widths - the column widths, read only.
/// Returns: widths.len(), the number of fields every parsed or written row
/// carries. An empty layout has 0 columns.
/// Error case: none.
/// Complexity: O(1).
pub fn fixed_column_count(widths: &Vec[Int]) -> Int {
  return widths.len();
}

/// Parse a fixed-width document into rows of raw fields.
/// Params: text - the document; widths - the column widths (byte counts),
/// read only.
/// Returns: one Vec[Str] per line, each with exactly widths.len() fields. A
/// width <= 0 yields "" and consumes no input; a line shorter than the layout
/// yields "" for every field starting at or past its end; fields are returned
/// raw, untrimmed. Lines end at LF or CRLF (the CR is not field data); a
/// single trailing terminator adds no row; empty text yields no rows; a blank
/// line is one row of empty fields.
/// Error case: none.
/// Complexity: O(text bytes + rows * widths).
pub fn fixed_parse(text: Str, widths: &Vec[Int]) -> Vec[Vec[Str]] {
  return _fixed_parse_all(text, widths, false);
}

/// Parse a fixed-width document with every field trimmed.
/// Params: text - the document; widths - the column widths (byte counts),
/// read only.
/// Returns: the same rows as fixed_parse, with xiom.string.str_trim applied
/// to every field (leading and trailing ASCII whitespace removed).
/// Error case: none.
/// Complexity: O(text bytes + rows * widths).
pub fn fixed_parse_trimmed(text: Str, widths: &Vec[Int]) -> Vec[Vec[Str]] {
  return _fixed_parse_all(text, widths, true);
}

/// Write rows as a fixed-width document.
/// Params: rows - the rows, read only; widths - the column widths (byte
/// counts), read only; pad - the padding text, only its first byte is used
/// (an empty pad means an ASCII space).
/// Returns: rows joined with LF and no trailing newline. Every row has
/// exactly widths.len() columns: column c is the cell left-aligned into
/// widths[c] bytes, truncated when longer and padded when shorter. Missing
/// cells are empty; cells beyond widths.len() are ignored; a width <= 0 emits
/// no bytes for that column. An empty rows input yields "".
/// Error case: none.
/// Complexity: O(rows * widths + total cell bytes).
pub fn fixed_write(rows: &Vec[Vec[Str]], widths: &Vec[Int], pad: Str) -> Str {
  var fill = " ";
  if pad.len() > 0 {
    fill = string.str_slice(pad, 0, 1);
  }
  var out = "";
  var r = 0;
  while r < rows.len() {
    if r > 0 {
      out = out + "\n";
    }
    var c = 0;
    while c < widths.len() {
      let w: Int = widths[c];
      if w > 0 {
        var cell = "";
        if c < rows[r].len() {
          let cell_text: Str = rows[r][c];
          cell = cell_text;
        }
        if cell.len() > w {
          cell = string.str_slice(cell, 0, w);
        }
        out = out + cell;
        var fill_count = w - cell.len();
        while fill_count > 0 {
          out = out + fill;
          fill_count = fill_count - 1;
        }
      }
      c = c + 1;
    }
    r = r + 1;
  }
  return out;
}

/// Look up one field by row and column index.
/// Params: rows - the parsed rows; r - zero-based row index; c - zero-based
/// column index.
/// Returns: Some(field) on a hit, None when r or c is negative or out of
/// range.
/// Error case: none.
/// Complexity: O(1).
pub fn fixed_field(rows: &Vec[Vec[Str]], r: Int, c: Int) -> Option[Str] {
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

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Split text into logical lines. LF terminates a line; a CR immediately before
// that LF is dropped (CRLF counts as one terminator). A single trailing
// terminator adds no line, so "a\n" has one line and "a\n\n" has two. Empty
// text has no lines at all (not even one empty line). A bare CR that is not
// followed by LF is left in the line as ordinary data.
fn _fixed_lines(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let len = text.len();
  if len == 0 {
    return out;
  }
  let parts = string.lines(text);
  var count = parts.len();
  let last_byte: Int = string.byte_at(text, len - 1) as Int;
  if last_byte == _FIXED_LF {
    count = count - 1;
  }
  var i = 0;
  while i < count {
    let part: Str = parts[i];
    var line = part;
    let followed_by_lf = i < parts.len() - 1;
    if followed_by_lf {
      let part_len = part.len();
      if part_len > 0 {
        let trailing: Int = string.byte_at(part, part_len - 1) as Int;
        if trailing == _FIXED_CR {
          line = string.str_slice(part, 0, part_len - 1);
        }
      }
    }
    out.push(line);
    i = i + 1;
  }
  return out;
}

// Slice one LF-free line into exactly widths.len() fields. Widths <= 0 yield
// "" and consume no bytes; slicing past the line end yields "" through
// str_slice's clamping.
fn _fixed_fields(line: Str, widths: &Vec[Int], trimmed: Bool) -> Vec[Str] {
  var out = Vec[Str].new();
  var start = 0;
  var c = 0;
  while c < widths.len() {
    let w: Int = widths[c];
    var field = "";
    if w > 0 {
      field = string.str_slice(line, start, start + w);
      start = start + w;
    }
    if trimmed {
      field = string.str_trim(field);
    }
    out.push(field);
    c = c + 1;
  }
  return out;
}

// Shared parse driver for fixed_parse and fixed_parse_trimmed.
fn _fixed_parse_all(text: Str, widths: &Vec[Int], trimmed: Bool) -> Vec[Vec[Str]] {
  var rows = Vec[Vec[Str]].new();
  let lines = _fixed_lines(text);
  var i = 0;
  while i < lines.len() {
    let line: Str = lines[i];
    rows.push(_fixed_fields(line, widths, trimmed));
    i = i + 1;
  }
  return rows;
}
