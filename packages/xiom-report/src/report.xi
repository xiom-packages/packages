// XIOM -- xiom.report: plain-text report building (tables, key/value blocks,
// bullets, word wrap and rules).
// Port task: replace the xiom.report placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Layout model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
// - report_table renders fixed-width columns: the width of a column is
//   max(header length, longest cell in that column) + pad, with pad clamped
//   to >= 0, and the column count is max(headers.len(), widest row). Every
//   line is the concatenation of its padded cells, so all lines of a table
//   share one byte length and short rows are padded with empty cells. The
//   separator line of '-' sits directly under the header row and exists only
//   when headers is non-empty; columns without a header contribute header
//   spaces. A table with no headers and no cells renders as "".
// - report_kv left-justifies every rendered key to the longest rendered key,
//   then appends the separator and the value verbatim: for separator ": " the
//   output is "name: Ada" / "id  : 42". Rendering stops at the shorter length
//   of keys and values.
// - report_bullets renders "marker item" lines joined with LF; an embedded LF
//   inside an item starts a continuation line indented by marker.len() spaces.
// - report_wrap greedily wraps each LF-separated logical line on ASCII spaces
//   (space runs collapse to one space, leading/trailing spaces are dropped);
//   words longer than width are hard-broken into exactly-width chunks; every
//   output line is prefixed with indent. width < 1 returns text unchanged.
// - report_rule repeats the first byte of ch width times; an empty ch means
//   '-'; width <= 0 yields "".
//
// v0.61.3 notes that shaped this module: free functions only (no self methods,
// no lambdas, no Vec[StructType], no Vec[fn]); no `==` on Str values (this
// module performs no string equality at all); every Vec element read is bound
// with an explicit type; xiom.string helpers (str_split, lines, str_slice,
// str_repeat) cover all byte work, so no raw byte_at scan is needed.

module xiom.report

use xiom.string;

/// Render a fixed-width table.
/// Params: headers - the header cells, read only; rows - the data rows, read
/// only; pad - extra width added to every column, clamped to >= 0.
/// Returns: the header line, a separator line of '-' (only when headers is
/// non-empty) and one line per row, joined with LF and with no trailing
/// newline. The column count is max(headers.len(), widest row) and column c
/// is max(len(headers[c]), longest cell in column c) + pad wide; missing
/// cells are treated as "" and padded, so every line has the same byte
/// length. Cells beyond headers.len() get data-only widths. A table with no
/// headers and no cells renders as "".
/// Examples: headers ["name", "age"], rows [["Ada", "36"], ["Bob", "7"]],
/// pad 1 renders "name age ", "---------", "Ada  36  ", "Bob  7   " on four
/// lines.
/// Error case: none.
/// Complexity: O(rows * ncols + total cell bytes).
pub fn report_table(headers: &Vec[Str], rows: &Vec[Vec[Str]], pad: Int) -> Str {
  let gap = _non_negative(pad);
  var ncols = headers.len();
  var r = 0;
  while r < rows.len() {
    if rows[r].len() > ncols {
      ncols = rows[r].len();
    }
    r = r + 1;
  }
  if ncols == 0 {
    return "";
  }
  var widths = Vec[Int].new();
  var c = 0;
  while c < ncols {
    var w = 0;
    if c < headers.len() {
      let header: Str = headers[c];
      w = header.len();
    }
    r = 0;
    while r < rows.len() {
      if c < rows[r].len() {
        let cell: Str = rows[r][c];
        if cell.len() > w {
          w = cell.len();
        }
      }
      r = r + 1;
    }
    widths.push(w + gap);
    c = c + 1;
  }
  var lines = Vec[Str].new();
  if headers.len() > 0 {
    var header_line = "";
    c = 0;
    while c < ncols {
      var header = "";
      if c < headers.len() {
        let header_cell: Str = headers[c];
        header = header_cell;
      }
      let width: Int = widths[c];
      header_line = header_line + _pad_right(header, width);
      c = c + 1;
    }
    lines.push(header_line);
    var separator = "";
    c = 0;
    while c < ncols {
      let width: Int = widths[c];
      separator = separator + string.str_repeat("-", width);
      c = c + 1;
    }
    lines.push(separator);
  }
  r = 0;
  while r < rows.len() {
    var line = "";
    c = 0;
    while c < ncols {
      var cell = "";
      if c < rows[r].len() {
        let row_cell: Str = rows[r][c];
        cell = row_cell;
      }
      let width: Int = widths[c];
      line = line + _pad_right(cell, width);
      c = c + 1;
    }
    lines.push(line);
    r = r + 1;
  }
  return _join(&lines);
}

/// Render aligned key/value lines.
/// Params: keys - the keys, read only; values - the values, read only;
/// separator - the text placed between a key and its value, used verbatim
/// (": " provides the customary colon and gap).
/// Returns: one "key<separator>value" line per rendered pair, joined with LF
/// and with no trailing newline. Every rendered key is left-justified to the
/// longest rendered key, so the separators line up; rendering stops at the
/// shorter length of keys and values, and an empty key or value list renders
/// as "".
/// Examples: keys ["name", "id"], values ["Ada", "42"], separator ": "
/// renders "name: Ada" and "id  : 42".
/// Error case: none.
/// Complexity: O(rendered pairs + total key bytes).
pub fn report_kv(keys: &Vec[Str], values: &Vec[Str], separator: Str) -> Str {
  var count = keys.len();
  if values.len() < count {
    count = values.len();
  }
  if count <= 0 {
    return "";
  }
  var key_width = 0;
  var i = 0;
  while i < count {
    let key: Str = keys[i];
    if key.len() > key_width {
      key_width = key.len();
    }
    i = i + 1;
  }
  var lines = Vec[Str].new();
  i = 0;
  while i < count {
    let key: Str = keys[i];
    let value: Str = values[i];
    lines.push(_pad_right(key, key_width) + separator + value);
    i = i + 1;
  }
  return _join(&lines);
}

/// Render bullet lines.
/// Params: items - the item texts, read only; marker - the bullet marker text
/// (e.g. "- " or "* ").
/// Returns: one "marker item" line per item, all joined with LF and with no
/// trailing newline. An LF inside an item starts a continuation line prefixed
/// with marker.len() spaces, so multi-line items stay visually nested under
/// the marker. An empty item renders the marker alone; an empty item list
/// renders as "".
/// Example: items ["first\nsecond"], marker "- " renders "- first" and
/// "  second".
/// Error case: none.
/// Complexity: O(total item bytes).
pub fn report_bullets(items: &Vec[Str], marker: Str) -> Str {
  var lines = Vec[Str].new();
  let continuation = string.str_repeat(" ", marker.len());
  var i = 0;
  while i < items.len() {
    let item: Str = items[i];
    let parts = string.lines(item);
    var j = 0;
    while j < parts.len() {
      let part: Str = parts[j];
      if j == 0 {
        lines.push(marker + part);
      } else {
        lines.push(continuation + part);
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return _join(&lines);
}

/// Greedy word wrap on ASCII spaces.
/// Params: text - the input text; width - the maximum line width in bytes;
/// indent - the prefix placed on every output line.
/// Returns: text wrapped and re-joined with LF, every line prefixed with
/// indent. LF-separated logical lines are wrapped independently; space runs
/// collapse to one space and leading/trailing spaces are dropped; words
/// longer than width are hard-broken into chunks of exactly width bytes (the
/// final chunk ends the line). width < 1 returns text unchanged with no
/// indent; empty text returns "". Each logical line yields at least one
/// output line, so a trailing LF produces a final indent-only line. Widths
/// are byte counts (see the ASCII limitation in SPEC.md).
/// Examples: report_wrap("the quick brown fox", 9, "> ") renders
/// "> the quick" and "> brown fox"; report_wrap("abcdefgh", 3, "") renders
/// "abc", "def", "gh".
/// Error case: none.
/// Complexity: O(total text bytes).
pub fn report_wrap(text: Str, width: Int, indent: Str) -> Str {
  if width < 1 {
    return text;
  }
  if text.len() == 0 {
    return "";
  }
  let logical = string.lines(text);
  var lines = Vec[Str].new();
  var i = 0;
  while i < logical.len() {
    let logical_line: Str = logical[i];
    let wrapped = _wrap_line(logical_line, width);
    var j = 0;
    while j < wrapped.len() {
      let piece: Str = wrapped[j];
      lines.push(indent + piece);
      j = j + 1;
    }
    i = i + 1;
  }
  return _join(&lines);
}

/// Render a horizontal rule line.
/// Params: width - the rule length in bytes; ch - the rule character (only
/// its first byte is used).
/// Returns: the first byte of ch repeated width times. An empty ch means '-';
/// width <= 0 yields "".
/// Examples: report_rule(5, "-") is "-----"; report_rule(4, "ab") is "aaaa";
/// report_rule(0, "=") is "".
/// Error case: none.
/// Complexity: O(width).
pub fn report_rule(width: Int, ch: Str) -> Str {
  if width <= 0 {
    return "";
  }
  var unit = "-";
  if ch.len() > 0 {
    unit = string.str_slice(ch, 0, 1);
  }
  return string.str_repeat(unit, width);
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Join lines with LF, byte-exact, without a trailing terminator.
// Empty input returns "".
fn _join(lines: &Vec[Str]) -> Str {
  var out = "";
  var i = 0;
  while i < lines.len() {
    if i > 0 {
      out = out + "\n";
    }
    let line: Str = lines[i];
    out = out + line;
    i = i + 1;
  }
  return out;
}

// Left-justify a cell into a field of exactly `width` bytes. The caller
// guarantees width >= cell.len(), so only the fill is ever appended.
fn _pad_right(cell: Str, width: Int) -> Str {
  let fill = width - cell.len();
  if fill <= 0 {
    return cell;
  }
  return cell + string.str_repeat(" ", fill);
}

// Negative pads are clamped to 0.
fn _non_negative(n: Int) -> Int {
  if n < 0 {
    return 0;
  }
  return n;
}

// The smaller of two Ints.
fn _min_int(a: Int, b: Int) -> Int {
  if a < b {
    return a;
  }
  return b;
}

// Wrap one LF-free logical line into pieces of at most `width` bytes
// (width >= 1): greedy fill on ASCII spaces, with space runs collapsing to
// one space and leading/trailing spaces dropped. A word longer than width is
// broken into exactly-width chunks; its final (possibly shorter) chunk stays
// on the current line and the next word may follow it. An all-space or empty
// line yields one empty piece.
fn _wrap_line(line: Str, width: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  let tokens = string.str_split(line, " ");
  var current = "";
  var i = 0;
  while i < tokens.len() {
    let word: Str = tokens[i];
    let wlen = word.len();
    if wlen > 0 {
      if wlen > width {
        if current.len() > 0 {
          out.push(current);
          current = "";
        }
        var pos = 0;
        while pos < wlen {
          let take = _min_int(width, wlen - pos);
          current = current + string.str_slice(word, pos, pos + take);
          pos = pos + take;
          if pos < wlen {
            out.push(current);
            current = "";
          }
        }
      } elif current.len() == 0 {
        current = word;
      } elif current.len() + 1 + wlen <= width {
        current = current + " " + word;
      } else {
        out.push(current);
        current = word;
      }
    }
    i = i + 1;
  }
  if current.len() > 0 || out.len() == 0 {
    out.push(current);
  }
  return out;
}
