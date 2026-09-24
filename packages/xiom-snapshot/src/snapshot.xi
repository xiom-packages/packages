// XIOM -- xiom.snapshot: normalization, line equality and first-difference summaries
// Port task: replace the xiom.snapshot placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Snapshot comparison over two in-memory texts. Every entry point is a free
// function and is infallible (Str/Bool/Int/Vec[Str]-returning, no Result
// channel). The normalization pipeline is: split on LF with each line's
// trailing CR removed, optionally strip per-line trailing spaces and tabs,
// then drop trailing empty lines. See SPEC.md for the exact rules and the
// summary grammar.
//
// Str values read from Vec[Str] elements are compared only through
// xiom.string.compare.str_compare (BUG 17: `==` on such values lowers to a
// pointer comparison). Byte reads go through UInt8 constants, so no
// `byte_at ... as Int` widening is involved.

module xiom.snapshot

use xiom.string;
use xiom.string.compare;
use xiom.convert.int;

// --- byte constants ---------------------------------------------------------

const _SN_TAB: UInt8 = 9u8;
const _SN_LF: UInt8 = 10u8;
const _SN_CR: UInt8 = 13u8;
const _SN_SPACE: UInt8 = 32u8;

// --- internal helpers -------------------------------------------------------

// Line equality. Uses str_compare, never `==` (BUG 17).
fn _lines_eq(a: Str, b: Str) -> Bool {
  return str_compare(a, b) == 0;
}

// s without one trailing CR (the tail of a CRLF pair or a lone final CR).
fn _strip_cr(s: Str) -> Str {
  let n = s.len();
  if n > 0 {
    if byte_at(s, n - 1) == _SN_CR {
      return str_slice(s, 0, n - 1);
    }
  }
  return s;
}

// s without its trailing run of spaces and tabs.
fn _strip_trailing_ws(s: Str) -> Str {
  var end = s.len();
  while end > 0 {
    let b: UInt8 = byte_at(s, end - 1);
    if b == _SN_SPACE || b == _SN_TAB {
      end = end - 1;
    } else {
      break;
    }
  }
  return str_slice(s, 0, end);
}

// Raw line split (before normalization): split on LF; every line has one
// trailing CR removed; a single trailing newline adds no line.
fn _raw_lines(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let n = text.len();
  if n == 0 {
    return out;
  }
  var start = 0;
  var i = 0;
  while i < n {
    let b: UInt8 = byte_at(text, i);
    if b == _SN_LF {
      out.push(_strip_cr(str_slice(text, start, i)));
      start = i + 1;
    }
    i = i + 1;
  }
  if start < n {
    out.push(_strip_cr(str_slice(text, start, n)));
  }
  return out;
}

// Normalized line vector: raw lines, optional per-line trailing space/tab
// trim, then trailing empty lines dropped.
fn _normalized_lines(text: Str, trim_trailing_ws: Bool) -> Vec[Str] {
  let raw = _raw_lines(text);
  var out = Vec[Str].new();
  var i = 0;
  while i < raw.len() {
    let line: Str = raw[i];
    if trim_trailing_ws {
      out.push(_strip_trailing_ws(line));
    } else {
      out.push(line);
    }
    i = i + 1;
  }
  while out.len() > 0 {
    let last: Str = out[out.len() - 1];
    if last.len() == 0 {
      out.pop();
    } else {
      break;
    }
  }
  return out;
}

// 1-based line number of the first differing position, -1 when equal.
// A missing line on either side counts as a difference.
fn _first_diff(a: &Vec[Str], b: &Vec[Str]) -> Int {
  let n = a.len();
  let m = b.len();
  var i = 0;
  while i < n {
    if i >= m {
      return i + 1;
    }
    if !_lines_eq(a[i], b[i]) {
      return i + 1;
    }
    i = i + 1;
  }
  if m > n {
    return n + 1;
  }
  return -1;
}

// Number of differing line positions up to the longer length.
fn _diff_count(a: &Vec[Str], b: &Vec[Str]) -> Int {
  let n = a.len();
  let m = b.len();
  var limit = n;
  if m > limit {
    limit = m;
  }
  var count = 0;
  var i = 0;
  while i < limit {
    var differ: Bool = false;
    if i >= n {
      differ = true;
    } else {
      if i >= m {
        differ = true;
      } else {
        if !_lines_eq(a[i], b[i]) {
          differ = true;
        }
      }
    }
    if differ {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

// --- public API -------------------------------------------------------------

/// Split `text` into lines.
/// Split on LF (byte 10); one CR immediately before a line's LF terminator or
/// at the very end of the text is removed; a single trailing newline adds no
/// line, so "" is zero lines while "\n" is one empty line. UTF-8 bytes pass
/// through byte-exact.
/// Params: text - the text to split.
/// Returns: a fresh Vec[Str], one entry per line.
/// Errors: none.
/// Complexity: O(n).
pub fn snapshot_lines(text: Str) -> Vec[Str] {
  return _raw_lines(text);
}

/// Canonical normalized form of `text`.
/// Rules: CRLF (and a final lone CR) becomes LF; when `trim_trailing_ws` is
/// true every line loses its trailing run of spaces and tabs; then trailing
/// empty lines are dropped. Lines are rejoined with a single LF and no
/// trailing newline, so "" and "\n\n" both normalize to "".
/// Params: text - the text to normalize; trim_trailing_ws - trim per-line
/// trailing spaces and tabs.
/// Returns: the normalized text.
/// Errors: none.
/// Complexity: O(n).
pub fn snapshot_normalized(text: Str, trim_trailing_ws: Bool) -> Str {
  let lines = _normalized_lines(text, trim_trailing_ws);
  var out = "";
  var i = 0;
  while i < lines.len() {
    if i > 0 {
      out = out + "\n";
    }
    out = out + lines[i];
    i = i + 1;
  }
  return out;
}

/// True when two texts are equal after normalization.
/// Params: a, b - the texts; trim_trailing_ws - as in snapshot_normalized.
/// Returns: true when both normalize to the same line sequence.
/// Errors: none.
/// Complexity: O(n + m).
pub fn snapshot_equal(a: Str, b: Str, trim_trailing_ws: Bool) -> Bool {
  let al = _normalized_lines(a, trim_trailing_ws);
  let bl = _normalized_lines(b, trim_trailing_ws);
  if al.len() != bl.len() {
    return false;
  }
  var i = 0;
  while i < al.len() {
    if !_lines_eq(al[i], bl[i]) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// 1-based number of the first differing normalized line.
/// Params: a, b - the texts; trim_trailing_ws - as in snapshot_normalized.
/// Returns: the line number (1-based) of the first position where the
/// normalized lines differ, or where one side has run out of lines; -1 when
/// the normalized texts are equal.
/// Errors: none.
/// Complexity: O(n + m).
pub fn snapshot_first_diff_line(a: Str, b: Str, trim_trailing_ws: Bool) -> Int {
  let al = _normalized_lines(a, trim_trailing_ws);
  let bl = _normalized_lines(b, trim_trailing_ws);
  return _first_diff(&al, &bl);
}

/// Human-readable first-difference summary.
/// Params: a, b - the texts, `a` being the expected side; trim_trailing_ws -
/// as in snapshot_normalized.
/// Returns: "equal" when the normalized texts match; otherwise
/// "N line(s) differ; first at line L\n  expected: <line>\n  actual:   <line>"
/// where N counts differing positions up to the longer length, L is the
/// 1-based first difference (see snapshot_first_diff_line), and a side that
/// has run out of lines is shown as "<missing>".
/// Errors: none.
/// Complexity: O(n + m).
pub fn snapshot_diff_summary(a: Str, b: Str, trim_trailing_ws: Bool) -> Str {
  let al = _normalized_lines(a, trim_trailing_ws);
  let bl = _normalized_lines(b, trim_trailing_ws);
  let count = _diff_count(&al, &bl);
  if count == 0 {
    return "equal";
  }
  let first = _first_diff(&al, &bl);
  var expected: Str = "<missing>";
  if first - 1 < al.len() {
    expected = al[first - 1];
  }
  var actual: Str = "<missing>";
  if first - 1 < bl.len() {
    actual = bl[first - 1];
  }
  return int_to_string(count) + " line(s) differ; first at line " + int_to_string(first) + "\n  expected: " + expected + "\n  actual:   " + actual;
}

/// Convenience clean check with the default normalization.
/// Params: a, b - the texts.
/// Returns: snapshot_equal(a, b, true).
/// Errors: none.
/// Complexity: O(n + m).
pub fn snapshot_is_clean(a: Str, b: Str) -> Bool {
  return snapshot_equal(a, b, true);
}
