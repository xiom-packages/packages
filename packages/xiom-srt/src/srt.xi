// XIOM -- xiom.srt: a strict, in-memory SubRip (SRT) subtitle codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (SPEC.md states the exact grammar):
//   * blank-line separated cue blocks: an integer index line (1-based,
//     positive decimal digits), a timing line
//     "hh:mm:ss,mmm --> hh:mm:ss,mmm" with optional trailing settings passed
//     through verbatim, and one or more payload lines;
//   * payload lines are preserved in order and kept flat: cue `i` owns the
//     half-open range [payload_starts[i], payload_ends[i]) of the shared
//     `lines` buffer;
//   * CRLF and LF documents parse to the same track; the emitter writes LF,
//     renumbers cues sequentially from 1, and uses the canonical comma
//     timestamp separator.
//
// Non-goals: no rendering, no HTML/tag sanitization, no encoding conversion,
// no frame/SMPTE timecodes, no SSA/ASS or other subtitle formats.
//
// v0.61.3 notes that shaped this module (SPEC.md section 11):
//   * free functions only; no methods, lambdas, or match;
//   * Ok/Err are constructed only in the tiny leaf helpers below;
//   * Str values read from Vec[Str] are compared through
//     xiom.string.compare.str_compare, never `==` (BUG 17);
//   * every byte is widened with `(string.byte_at(s, pos) as Int) & 0xFF`,
//     so no UInt8 constant >= 128 is involved in a comparison;
//   * cues are flat: parallel Vecs plus payload-line ranges; there is no
//     Vec[StructType].

module xiom.srt

use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Public data model
// --------------------------------------------------

/// A parsed SRT track: parallel per-cue arrays plus one shared payload-line
/// buffer.
/// Cue `i` has the index read from the document in `indexes`, start and end
/// times in milliseconds in `starts`/`ends`, verbatim trailing settings in
/// `settings` ("" when absent), and payload lines
/// `lines[payload_starts[i] .. payload_ends[i])`.
/// All six cue vectors have the same length (the cue count); every payload
/// range is non-empty, does not overlap its neighbours and lies inside
/// `lines`. Parsed indices need not be sequential or unique -- the
/// canonical emitter renumbers cues from 1 in order.
pub type Srt = {
  indexes: Vec[Int];
  starts: Vec[Int];
  ends: Vec[Int];
  settings: Vec[Str];
  payload_starts: Vec[Int];
  payload_ends: Vec[Int];
  lines: Vec[Str];
}

// --------------------------------------------------
//  Byte constants (Int, see the header note)
// --------------------------------------------------

const _TAB: Int = 9;
const _LF: Int = 10;
const _CR: Int = 13;
const _SPACE: Int = 32;
const _COMMA: Int = 44;
const _DASH: Int = 45;
const _DOT: Int = 46;
const _COLON: Int = 58;
const _GT: Int = 62;
const _ZERO: Int = 48;
const _NINE: Int = 57;

// --------------------------------------------------
//  Result and struct constructors (leaf helpers)
// --------------------------------------------------

// The one place an Srt value is assembled from its parallel vectors.
fn _make_srt(indexes: Vec[Int], starts: Vec[Int], ends: Vec[Int], settings: Vec[Str], payload_starts: Vec[Int], payload_ends: Vec[Int], lines: Vec[Str]) -> Srt {
  return Srt{
    indexes: indexes;
    starts: starts;
    ends: ends;
    settings: settings;
    payload_starts: payload_starts;
    payload_ends: payload_ends;
    lines: lines;
  };
}

// Ok(v) for Result[Srt, Str].
fn _ok_srt(v: Srt) -> Result[Srt, Str] {
  return Ok(v);
}

// Err(m) for Result[Srt, Str].
fn _err_srt(m: Str) -> Result[Srt, Str] {
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

// --------------------------------------------------
//  Internal text helpers
// --------------------------------------------------

// Byte `pos` of `s` as an Int (0..255). Callers guarantee the bounds. The
// mask keeps every widened byte non-negative (see the header note).
fn _byte(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

// Split `text` into lines on LF. A CR immediately before LF is dropped, so
// CRLF documents produce the same lines as LF documents. A trailing LF does
// not produce a final empty line.
fn _split_lines(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let len = text.len();
  var start = 0;
  var i = 0;
  while i < len {
    if _byte(text, i) == _LF {
      var end = i;
      if end > start && _byte(text, end - 1) == _CR { end = end - 1; }
      out.push(string.str_slice(text, start, end));
      start = i + 1;
    }
    i = i + 1;
  }
  if start < len {
    var end = len;
    if end > start && _byte(text, end - 1) == _CR { end = end - 1; }
    out.push(string.str_slice(text, start, end));
  }
  return out;
}

// Position of the first byte at or after `from` that is not a space or tab.
fn _skip_ws(s: Str, from: Int) -> Int {
  let len = s.len();
  var a = from;
  var go = true;
  while a < len && go {
    let c = _byte(s, a);
    if c == _SPACE || c == _TAB { a = a + 1; } else { go = false; }
  }
  return a;
}

// End position (exclusive) of the token starting at `from`, i.e. the first
// space/tab at or after `from` (or the end of the string).
fn _token_end(s: Str, from: Int) -> Int {
  let len = s.len();
  var b = from;
  var go = true;
  while b < len && go {
    let c = _byte(s, b);
    if c == _SPACE || c == _TAB { go = false; } else { b = b + 1; }
  }
  return b;
}

// Slice [from, to) with surrounding spaces/tabs removed.
fn _trim_range(s: Str, from: Int, to: Int) -> Str {
  let a = _skip_ws(s, from);
  var b = to;
  var go = true;
  while b > a && go {
    let c = _byte(s, b - 1);
    if c == _SPACE || c == _TAB { b = b - 1; } else { go = false; }
  }
  if a > b { return ""; }
  return string.str_slice(s, a, b);
}

// Trim [from, end of string] on a Str that may have been read from a
// Vec[Str] element (see the header note).
fn _trim_from(s: Str, from: Int) -> Str {
  return _trim_range(s, from, s.len());
}

// Value of two ASCII digits at `pos`, or -1 when either byte is not a digit.
fn _two_digits(s: Str, pos: Int) -> Int {
  let a = _byte(s, pos);
  let b = _byte(s, pos + 1);
  if a < _ZERO || a > _NINE { return -1; }
  if b < _ZERO || b > _NINE { return -1; }
  return (a - _ZERO) * 10 + (b - _ZERO);
}

// Value of three ASCII digits at `pos`, or -1 when any byte is not a digit.
fn _three_digits(s: Str, pos: Int) -> Int {
  let a = _byte(s, pos);
  let b = _byte(s, pos + 1);
  let c = _byte(s, pos + 2);
  if a < _ZERO || a > _NINE { return -1; }
  if b < _ZERO || b > _NINE { return -1; }
  if c < _ZERO || c > _NINE { return -1; }
  return (a - _ZERO) * 100 + (b - _ZERO) * 10 + (c - _ZERO);
}

// Parse an SRT timestamp to whole milliseconds.
// The form is exactly "HH:MM:SS,mmm": two hour digits 00..99, colons at
// positions 2 and 5, two minute and two second digits, a comma (or,
// leniently, a dot) at position 8, and exactly three millisecond digits.
// Returns the millisecond value (>= 0), -1 for a bad shape, or -2 when
// minutes or seconds exceed 59.
fn _timestamp_ms(t: Str) -> Int {
  if t.len() != 12 { return -1; }
  if _byte(t, 2) != _COLON { return -1; }
  if _byte(t, 5) != _COLON { return -1; }
  let sep = _byte(t, 8);
  if sep != _COMMA && sep != _DOT { return -1; }
  let hh = _two_digits(t, 0);
  let mm = _two_digits(t, 3);
  let ss = _two_digits(t, 6);
  let mmm = _three_digits(t, 9);
  if hh < 0 || mm < 0 || ss < 0 || mmm < 0 { return -1; }
  if mm > 59 || ss > 59 { return -2; }
  return hh * 3600000 + mm * 60000 + ss * 1000 + mmm;
}

// Index just past the first "-->" in `s`, or -1 when absent.
fn _arrow_end(s: Str) -> Int {
  let len = s.len();
  var i = 0;
  while i + 2 < len {
    if _byte(s, i) == _DASH {
      if _byte(s, i + 1) == _DASH {
        if _byte(s, i + 2) == _GT {
          return i + 3;
        }
      }
    }
    i = i + 1;
  }
  return -1;
}

// True when `s` contains the timing arrow "-->" (stdlib byte search).
fn _has_arrow(s: Str) -> Bool {
  return string.str_contains(s, "-->");
}

// True when `s` is a zero-byte line. Str equality goes through str_compare
// (BUG 17).
fn _is_blank(s: Str) -> Bool {
  return compare.str_compare(s, "") == 0;
}

// Parse a 1-based cue index line: decimal digits only, value >= 1; -1 when
// the line is empty, non-numeric or zero. Leading zeros are accepted
// ("007" is the index 7).
fn _index_of(s: Str) -> Int {
  let len = s.len();
  if len == 0 { return -1; }
  var v = 0;
  var i = 0;
  while i < len {
    let c = _byte(s, i);
    if c < _ZERO || c > _NINE { return -1; }
    v = v * 10 + (c - _ZERO);
    i = i + 1;
  }
  if v == 0 { return -1; }
  return v;
}

// --------------------------------------------------
//  Parser
// --------------------------------------------------

// SRT body: blank lines separate blocks; each block is an index line, a
// timing line and one or more payload lines.
fn _srt_parse_lines(lines: &Vec[Str]) -> Result[Srt, Str] {
  var indexes = Vec[Int].new();
  var starts = Vec[Int].new();
  var ends = Vec[Int].new();
  var settings = Vec[Str].new();
  var payload_starts = Vec[Int].new();
  var payload_ends = Vec[Int].new();
  var store = Vec[Str].new();

  let n = lines.len();
  var i = 0;
  while i < n {
    let head: Str = lines[i];
    if _is_blank(head) {
      i = i + 1;
    } else {
      // Block head: either the cue index or a misplaced timing line.
      if _has_arrow(head) { return _err_srt("srt: missing index"); }
      let idx = _index_of(head);
      if idx < 1 { return _err_srt("srt: bad index"); }
      i = i + 1;
      // Timing line.
      if i >= n { return _err_srt("srt: missing timing line"); }
      let tsline: Str = lines[i];
      if _is_blank(tsline) { return _err_srt("srt: missing timing line"); }
      if !_has_arrow(tsline) { return _err_srt("srt: stray text"); }
      let arrow = _arrow_end(tsline);
      let seg = _trim_range(tsline, 0, arrow - 3);
      let a = _timestamp_ms(seg);
      if a == -1 { return _err_srt("srt: bad timestamp shape"); }
      if a == -2 { return _err_srt("srt: timestamp out of range"); }
      let ea = _skip_ws(tsline, arrow);
      let eb = _token_end(tsline, ea);
      let et = string.str_slice(tsline, ea, eb);
      let b = _timestamp_ms(et);
      if b == -1 { return _err_srt("srt: bad timestamp shape"); }
      if b == -2 { return _err_srt("srt: timestamp out of range"); }
      if b < a { return _err_srt("srt: end before start"); }
      let stg = _trim_from(tsline, eb);
      i = i + 1;
      // Payload: at least one line; consumed up to a blank line or the end.
      if i >= n { return _err_srt("srt: cue without payload"); }
      let first_pl: Str = lines[i];
      if _is_blank(first_pl) { return _err_srt("srt: cue without payload"); }
      let p0 = store.len();
      while i < n {
        let pl: Str = lines[i];
        if _is_blank(pl) { break; }
        store.push(pl);
        i = i + 1;
      }
      let p1 = store.len();
      indexes.push(idx);
      starts.push(a);
      ends.push(b);
      settings.push(stg);
      payload_starts.push(p0);
      payload_ends.push(p1);
    }
  }
  if starts.len() == 0 { return _err_srt("srt: empty input"); }
  return _ok_srt(_make_srt(indexes, starts, ends, settings, payload_starts, payload_ends, store));
}

// --------------------------------------------------
//  Formatter helpers
// --------------------------------------------------

// Decimal formatting for non-negative values; local so the module needs no
// conversion imports.
fn _int_str(n: Int) -> Str {
  if n <= 0 { return "0"; }
  var digits = Vec[Int].new();
  var x = n;
  while x > 0 {
    let d: Int = x % 10;
    digits.push(d);
    x = x / 10;
  }
  var out = "";
  var i = digits.len() - 1;
  while i >= 0 {
    let d: Int = digits[i];
    out = out + string.str_slice("0123456789", d, d + 1);
    i = i - 1;
  }
  return out;
}

// Zero-padded to at least two digits.
fn _pad2(n: Int) -> Str {
  let s = _int_str(n);
  if n < 10 { return "0" + s; }
  return s;
}

// Zero-padded to at least three digits.
fn _pad3(n: Int) -> Str {
  if n < 10 { return "00" + _int_str(n); }
  if n < 100 { return "0" + _int_str(n); }
  return _int_str(n);
}

// "HH:MM:SS<sep>mmm" for `ms` (negative values clamp to zero). Hours print
// with more than two digits when they exceed 99.
fn _fmt_time(ms: Int, sep: Str) -> Str {
  var t = ms;
  if t < 0 { t = 0; }
  let hh = t / 3600000;
  let mm = (t / 60000) % 60;
  let ss = (t / 1000) % 60;
  let mmm = t % 1000;
  var out = _pad2(hh);
  out = out + ":";
  out = out + _pad2(mm);
  out = out + ":";
  out = out + _pad2(ss);
  out = out + sep;
  out = out + _pad3(mmm);
  return out;
}

// --------------------------------------------------
//  Public API -- parsing and formatting
// --------------------------------------------------

/// Parse a SubRip (SRT) document.
/// Accepts LF and CRLF line endings. Blank lines separate cue blocks; each
/// block is an index line (positive decimal digits, value >= 1; it need not
/// be sequential or unique), a timing line
/// "HH:MM:SS,mmm --> HH:MM:SS,mmm" (a dot separator is also accepted; the
/// trailing settings after the end timestamp are stored verbatim), and one
/// or more payload lines. Payload lines are preserved in order and the cue
/// text is their LF-joined form.
/// Errors: "srt: empty input" (no cue blocks), "srt: missing index",
/// "srt: bad index", "srt: missing timing line", "srt: stray text",
/// "srt: bad timestamp shape", "srt: timestamp out of range",
/// "srt: end before start", "srt: cue without payload"; see SPEC.md.
/// Complexity: O(input length).
pub fn srt_parse(text: Str) -> Result[Srt, Str] {
  let lines = _split_lines(text);
  return _srt_parse_lines(&lines);
}

/// Serialize a track as canonical SRT.
/// Cues are renumbered from 1 in order; timestamps use the comma separator
/// with two-digit hours; a non-empty settings string is written after the
/// end timestamp separated by one space; each payload line is written
/// verbatim; cue blocks are separated by one blank line and the last line is
/// terminated by LF. An empty track (no cues) yields "". Because a parsed
/// cue always has at least one payload line, parsed tracks round-trip.
/// Complexity: O(total payload lines).
pub fn srt_format(s: &Srt) -> Str {
  var n = s.starts.len();
  if s.ends.len() < n { n = s.ends.len(); }
  if s.settings.len() < n { n = s.settings.len(); }
  if s.payload_starts.len() < n { n = s.payload_starts.len(); }
  if s.payload_ends.len() < n { n = s.payload_ends.len(); }
  let total_lines = s.lines.len();
  var out = "";
  var i = 0;
  while i < n {
    let a: Int = s.starts[i];
    let b: Int = s.ends[i];
    let stg: Str = s.settings[i];
    if i > 0 { out = out + "\n"; }
    out = out + _int_str(i + 1);
    out = out + "\n";
    out = out + _fmt_time(a, ",");
    out = out + " --> ";
    out = out + _fmt_time(b, ",");
    if !_is_blank(stg) {
      out = out + " ";
      out = out + stg;
    }
    out = out + "\n";
    var p0: Int = s.payload_starts[i];
    var p1: Int = s.payload_ends[i];
    if p0 < 0 { p0 = 0; }
    if p0 > total_lines { p0 = total_lines; }
    if p1 < p0 { p1 = p0; }
    if p1 > total_lines { p1 = total_lines; }
    var p = p0;
    while p < p1 {
      let pl: Str = s.lines[p];
      out = out + pl;
      out = out + "\n";
      p = p + 1;
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Public API -- timestamps
// --------------------------------------------------

/// Parse one SRT timestamp and return whole milliseconds.
/// The form is exactly "HH:MM:SS,mmm": hours exactly two digits (00..99),
/// minutes and seconds two digits (00..59), a comma (or, leniently, a dot)
/// separator, and exactly three millisecond digits. Leading/trailing
/// whitespace is not allowed.
/// Errors: "srt: bad timestamp shape" for a malformed shape (including a
/// wrong number of millisecond digits), "srt: timestamp out of range" when
/// minutes or seconds exceed 59.
pub fn srt_parse_timestamp(t: Str) -> Result[Int, Str] {
  let ms = _timestamp_ms(t);
  if ms == -1 { return _err_int("srt: bad timestamp shape"); }
  if ms == -2 { return _err_int("srt: timestamp out of range"); }
  return _ok_int(ms);
}

/// Canonical SRT timestamp text "HH:MM:SS,mmm" for `ms` (the reverse of
/// `srt_parse_timestamp`). Negative values clamp to zero. Hours always print
/// with at least two digits, and with more than two digits above 99 hours
/// (such values are accepted here but rejected on parse, so they do not
/// round-trip; see SPEC.md).
pub fn srt_format_timestamp(ms: Int) -> Str {
  return _fmt_time(ms, ",");
}

// --------------------------------------------------
//  Public API -- accessors
// --------------------------------------------------

// Smallest of two Ints.
fn _min2(a: Int, b: Int) -> Int {
  if a < b { return a; }
  return b;
}

// Cue count: the minimum length of the six per-cue vectors, so a hand-built
// Srt with drifted vectors can never cause an out-of-range read.
fn _cue_count(s: &Srt) -> Int {
  var n = s.starts.len();
  n = _min2(n, s.ends.len());
  n = _min2(n, s.indexes.len());
  n = _min2(n, s.settings.len());
  n = _min2(n, s.payload_starts.len());
  n = _min2(n, s.payload_ends.len());
  return n;
}

/// Number of cues in the track.
pub fn srt_cue_count(s: &Srt) -> Int {
  return _cue_count(s);
}

/// Index of cue `i` as read from the document (the emitter renumbers cues
/// from 1); -1 when `i` is negative or out of range.
pub fn srt_cue_index(s: &Srt, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= s.indexes.len() { return -1; }
  let x: Int = s.indexes[i];
  return x;
}

/// Start time of cue `i` in milliseconds; -1 when `i` is negative or out of
/// range.
pub fn srt_cue_start_ms(s: &Srt, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= s.starts.len() { return -1; }
  let x: Int = s.starts[i];
  return x;
}

/// End time of cue `i` in milliseconds; -1 when `i` is negative or out of
/// range.
pub fn srt_cue_end_ms(s: &Srt, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= s.ends.len() { return -1; }
  let x: Int = s.ends[i];
  return x;
}

/// Trailing settings text of cue `i`, verbatim ("" when the cue has none, or
/// when `i` is negative or out of range).
pub fn srt_cue_settings(s: &Srt, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= s.settings.len() { return ""; }
  let x: Str = s.settings[i];
  return x;
}

/// Number of payload lines of cue `i`; 0 when `i` is negative or out of
/// range. Parsed cues always have at least one payload line.
pub fn srt_cue_line_count(s: &Srt, i: Int) -> Int {
  if i < 0 { return 0; }
  if i >= s.payload_starts.len() { return 0; }
  if i >= s.payload_ends.len() { return 0; }
  let total = s.lines.len();
  var p0: Int = s.payload_starts[i];
  var p1: Int = s.payload_ends[i];
  if p0 < 0 { p0 = 0; }
  if p0 > total { p0 = total; }
  if p1 < p0 { p1 = p0; }
  if p1 > total { p1 = total; }
  return p1 - p0;
}

/// Payload line `j` of cue `i`, verbatim; "" when `i` or `j` is negative or
/// out of range.
pub fn srt_cue_line(s: &Srt, i: Int, j: Int) -> Str {
  if i < 0 { return ""; }
  if i >= s.payload_starts.len() { return ""; }
  if i >= s.payload_ends.len() { return ""; }
  if j < 0 { return ""; }
  let total = s.lines.len();
  var p0: Int = s.payload_starts[i];
  var p1: Int = s.payload_ends[i];
  if p0 < 0 { p0 = 0; }
  if p0 > total { p0 = total; }
  if p1 < p0 { p1 = p0; }
  if p1 > total { p1 = total; }
  if j >= p1 - p0 { return ""; }
  let idx = p0 + j;
  let x: Str = s.lines[idx];
  return x;
}

/// Payload of cue `i` as one Str, its lines joined with "\n"; "" when the cue
/// has no lines or `i` is negative or out of range.
pub fn srt_cue_text(s: &Srt, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= s.payload_starts.len() { return ""; }
  if i >= s.payload_ends.len() { return ""; }
  let total = s.lines.len();
  var p0: Int = s.payload_starts[i];
  var p1: Int = s.payload_ends[i];
  if p0 < 0 { p0 = 0; }
  if p0 > total { p0 = total; }
  if p1 < p0 { p1 = p0; }
  if p1 > total { p1 = total; }
  var acc = "";
  var k = p0;
  while k < p1 {
    let x: Str = s.lines[k];
    if k > p0 { acc = acc + "\n"; }
    acc = acc + x;
    k = k + 1;
  }
  return acc;
}
