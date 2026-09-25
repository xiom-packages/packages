// XIOM -- xiom.sbv: a strict, in-memory YouTube SBV subtitle codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (SPEC.md states the exact grammar):
//   * blank-line separated cue blocks: a timing line
//     "h:mm:ss.mmm,h:mm:ss.mmm" and one or more payload lines;
//   * the hour field is one or two digits (0..99), minutes and seconds are
//     exactly two digits, milliseconds exactly three; optional spaces/tabs
//     are accepted around the comma on read and never written by the
//     canonical emitter;
//   * payload lines are preserved in order and kept flat: cue `i` owns the
//     half-open range [payload_starts[i], payload_ends[i]) of the shared
//     `lines` buffer;
//   * CRLF and LF documents parse to the same track; the emitter writes
//     single LF and canonical "h:mm:ss.mmm" timestamps.
//
// Non-goals: no rendering, no HTML sanitization, no style tags, no
// conversion to SRT (the sibling xiom.srt covers SRT), no encoding
// conversion, no file I/O.
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

module xiom.sbv

use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Public data model
// --------------------------------------------------

/// A parsed SBV track: parallel per-cue arrays plus one shared payload-line
/// buffer.
/// Cue `i` has start and end times in milliseconds in `starts`/`ends` and
/// payload lines `lines[payload_starts[i] .. payload_ends[i])`.
/// All four cue vectors have the same length (the cue count); every payload
/// range is non-empty, does not overlap its neighbours and lies inside
/// `lines`.
pub type Sbv = {
  starts: Vec[Int];
  ends: Vec[Int];
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
const _DOT: Int = 46;
const _COLON: Int = 58;
const _ZERO: Int = 48;
const _NINE: Int = 57;

// --------------------------------------------------
//  Result and struct constructors (leaf helpers)
// --------------------------------------------------

// The one place an Sbv value is assembled from its parallel vectors.
fn _make_sbv(starts: Vec[Int], ends: Vec[Int], payload_starts: Vec[Int], payload_ends: Vec[Int], lines: Vec[Str]) -> Sbv {
  return Sbv{
    starts: starts;
    ends: ends;
    payload_starts: payload_starts;
    payload_ends: payload_ends;
    lines: lines;
  };
}

// Ok(v) for Result[Sbv, Str].
fn _ok_sbv(v: Sbv) -> Result[Sbv, Str] {
  return Ok(v);
}

// Err(m) for Result[Sbv, Str].
fn _err_sbv(m: Str) -> Result[Sbv, Str] {
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

// Value of one or two ASCII digits at `pos` (`count` is 1 or 2), or -1 when
// any byte is not a digit. Used for the variable-width hour field.
fn _hour_digits(s: Str, pos: Int, count: Int) -> Int {
  let a = _byte(s, pos);
  if a < _ZERO || a > _NINE { return -1; }
  if count == 1 { return a - _ZERO; }
  let b = _byte(s, pos + 1);
  if b < _ZERO || b > _NINE { return -1; }
  return (a - _ZERO) * 10 + (b - _ZERO);
}

// Parse an SBV timestamp to whole milliseconds.
// The form is "h:mm:ss.mmm": an hour field of one or two ASCII digits
// (0..99), a colon, exactly two minute digits and two second digits, a dot,
// and exactly three millisecond digits. Returns the millisecond value
// (>= 0), -1 for a bad shape, or -2 when minutes or seconds exceed 59.
fn _timestamp_ms(t: Str) -> Int {
  var hd = 1;
  if t.len() >= 2 {
    if _byte(t, 1) != _COLON { hd = 2; }
  }
  if t.len() != hd + 10 { return -1; }
  if _byte(t, hd) != _COLON { return -1; }
  if _byte(t, hd + 3) != _COLON { return -1; }
  if _byte(t, hd + 6) != _DOT { return -1; }
  let hh = _hour_digits(t, 0, hd);
  let mm = _two_digits(t, hd + 1);
  let ss = _two_digits(t, hd + 4);
  let mmm = _three_digits(t, hd + 7);
  if hh < 0 || mm < 0 || ss < 0 || mmm < 0 { return -1; }
  if mm > 59 || ss > 59 { return -2; }
  return hh * 3600000 + mm * 60000 + ss * 1000 + mmm;
}

// Position of the first comma in `s`, or -1 when absent.
fn _comma_pos(s: Str) -> Int {
  let len = s.len();
  var i = 0;
  while i < len {
    if _byte(s, i) == _COMMA { return i; }
    i = i + 1;
  }
  return -1;
}

// True when `s` contains a ':' byte; tells a timing line missing its comma
// apart from misplaced payload text.
fn _has_colon(s: Str) -> Bool {
  let len = s.len();
  var i = 0;
  while i < len {
    if _byte(s, i) == _COLON { return true; }
    i = i + 1;
  }
  return false;
}

// True when `s` is a zero-byte line. Str equality goes through str_compare
// (BUG 17).
fn _is_blank(s: Str) -> Bool {
  return compare.str_compare(s, "") == 0;
}

// --------------------------------------------------
//  Parser
// --------------------------------------------------

// SBV body: blank lines separate blocks; each block is a timing line and one
// or more payload lines (payload runs greedily to the next blank line).
fn _sbv_parse_lines(lines: &Vec[Str]) -> Result[Sbv, Str] {
  var starts = Vec[Int].new();
  var ends = Vec[Int].new();
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
      let comma = _comma_pos(head);
      if comma < 0 {
        // No comma: a timing-line attempt missing its separator (a colon is
        // present), or payload text where a timing line belongs.
        if _has_colon(head) { return _err_sbv("sbv: missing comma"); }
        if starts.len() == 0 { return _err_sbv("sbv: text before first cue"); }
        return _err_sbv("sbv: payload before timing");
      }
      // Timing line: the first comma splits it; spaces/tabs around the comma
      // and at both ends of the line are ignored.
      let seg_a = _trim_range(head, 0, comma);
      let a = _timestamp_ms(seg_a);
      if a == -1 { return _err_sbv("sbv: bad timestamp shape"); }
      if a == -2 { return _err_sbv("sbv: timestamp out of range"); }
      let seg_b = _trim_from(head, comma + 1);
      let b = _timestamp_ms(seg_b);
      if b == -1 { return _err_sbv("sbv: bad timestamp shape"); }
      if b == -2 { return _err_sbv("sbv: timestamp out of range"); }
      if b < a { return _err_sbv("sbv: end before start"); }
      i = i + 1;
      // Payload: at least one line; consumed up to a blank line or the end.
      if i >= n { return _err_sbv("sbv: cue without payload"); }
      let first_pl: Str = lines[i];
      if _is_blank(first_pl) { return _err_sbv("sbv: cue without payload"); }
      let p0 = store.len();
      while i < n {
        let pl: Str = lines[i];
        if _is_blank(pl) { break; }
        store.push(pl);
        i = i + 1;
      }
      let p1 = store.len();
      starts.push(a);
      ends.push(b);
      payload_starts.push(p0);
      payload_ends.push(p1);
    }
  }
  if starts.len() == 0 { return _err_sbv("sbv: empty input"); }
  return _ok_sbv(_make_sbv(starts, ends, payload_starts, payload_ends, store));
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

// Canonical "h:mm:ss.mmm" for `ms` (negative values clamp to zero). The hour
// field prints without leading zeros and grows past two digits above 99
// hours (such values are accepted here but rejected on parse, so they do not
// round-trip; see SPEC.md).
fn _fmt_time(ms: Int) -> Str {
  var t = ms;
  if t < 0 { t = 0; }
  let hh = t / 3600000;
  let mm = (t / 60000) % 60;
  let ss = (t / 1000) % 60;
  let mmm = t % 1000;
  var out = _int_str(hh);
  out = out + ":";
  out = out + _pad2(mm);
  out = out + ":";
  out = out + _pad2(ss);
  out = out + ".";
  out = out + _pad3(mmm);
  return out;
}

// --------------------------------------------------
//  Public API -- parsing and formatting
// --------------------------------------------------

/// Parse a YouTube SBV subtitle document.
/// Accepts LF and CRLF line endings. Blank lines separate cue blocks; each
/// block is a timing line "h:mm:ss.mmm,h:mm:ss.mmm" (hours 1..2 digits,
/// minutes/seconds exactly two digits, milliseconds exactly three; spaces
/// and tabs are allowed around the comma and at both ends of the line) and
/// one or more payload lines, preserved in order. Payload lines are consumed
/// greedily up to the next blank line, so a payload line may itself look
/// like a timing line.
/// Errors: "sbv: empty input" (no cue blocks), "sbv: missing comma",
/// "sbv: text before first cue", "sbv: payload before timing",
/// "sbv: bad timestamp shape", "sbv: timestamp out of range",
/// "sbv: end before start", "sbv: cue without payload"; see SPEC.md.
/// Complexity: O(input length).
pub fn sbv_parse(text: Str) -> Result[Sbv, Str] {
  let lines = _split_lines(text);
  return _sbv_parse_lines(&lines);
}

/// Serialize a track as canonical SBV.
/// Timestamps are "h:mm:ss.mmm" with an unpadded hour field and no
/// whitespace around the comma; each payload line is written verbatim; cue
/// blocks are separated by one blank line and the last line is terminated by
/// LF. An empty track (no cues) yields "". Because a parsed cue always has
/// at least one payload line, parsed tracks round-trip.
/// Complexity: O(total payload lines).
pub fn sbv_format(s: &Sbv) -> Str {
  var n = s.starts.len();
  if s.ends.len() < n { n = s.ends.len(); }
  if s.payload_starts.len() < n { n = s.payload_starts.len(); }
  if s.payload_ends.len() < n { n = s.payload_ends.len(); }
  let total_lines = s.lines.len();
  var out = "";
  var i = 0;
  while i < n {
    let a: Int = s.starts[i];
    let b: Int = s.ends[i];
    if i > 0 { out = out + "\n"; }
    out = out + _fmt_time(a);
    out = out + ",";
    out = out + _fmt_time(b);
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

/// Parse one SBV timestamp and return whole milliseconds.
/// The form is "h:mm:ss.mmm": an hour field of one or two digits (0..99),
/// minutes and seconds exactly two digits (00..59), a dot separator, and
/// exactly three millisecond digits (000..999). Leading/trailing whitespace
/// is not allowed.
/// Errors: "sbv: bad timestamp shape" for a malformed shape (including a
/// wrong digit count or separator), "sbv: timestamp out of range" when
/// minutes or seconds exceed 59.
pub fn sbv_parse_timestamp(t: Str) -> Result[Int, Str] {
  let ms = _timestamp_ms(t);
  if ms == -1 { return _err_int("sbv: bad timestamp shape"); }
  if ms == -2 { return _err_int("sbv: timestamp out of range"); }
  return _ok_int(ms);
}

/// Canonical SBV timestamp text "h:mm:ss.mmm" for `ms` (the reverse of
/// `sbv_parse_timestamp`). Negative values clamp to zero. The hour field has
/// no leading zeros and grows past two digits above 99 hours (such values
/// are accepted here but rejected on parse, so they do not round-trip; see
/// SPEC.md).
pub fn sbv_format_timestamp(ms: Int) -> Str {
  return _fmt_time(ms);
}

// --------------------------------------------------
//  Public API -- accessors
// --------------------------------------------------

// Smallest of two Ints.
fn _min2(a: Int, b: Int) -> Int {
  if a < b { return a; }
  return b;
}

// Cue count: the minimum length of the four per-cue vectors, so a hand-built
// Sbv with drifted vectors can never cause an out-of-range read.
fn _cue_count(s: &Sbv) -> Int {
  var n = s.starts.len();
  n = _min2(n, s.ends.len());
  n = _min2(n, s.payload_starts.len());
  n = _min2(n, s.payload_ends.len());
  return n;
}

/// Number of cues in the track.
pub fn sbv_cue_count(s: &Sbv) -> Int {
  return _cue_count(s);
}

/// Start time of cue `i` in milliseconds; -1 when `i` is negative or out of
/// range.
pub fn sbv_cue_start_ms(s: &Sbv, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= s.starts.len() { return -1; }
  let x: Int = s.starts[i];
  return x;
}

/// End time of cue `i` in milliseconds; -1 when `i` is negative or out of
/// range.
pub fn sbv_cue_end_ms(s: &Sbv, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= s.ends.len() { return -1; }
  let x: Int = s.ends[i];
  return x;
}

/// Duration of cue `i` in milliseconds (`end - start`); -1 when `i` is
/// negative or out of range. Parsed cues always have a non-negative
/// duration; a hand-built track with `end < start` returns the computed
/// negative difference.
pub fn sbv_cue_duration_ms(s: &Sbv, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= s.starts.len() { return -1; }
  if i >= s.ends.len() { return -1; }
  let a: Int = s.starts[i];
  let b: Int = s.ends[i];
  return b - a;
}

/// Number of payload lines of cue `i`; 0 when `i` is negative or out of
/// range. Parsed cues always have at least one payload line.
pub fn sbv_cue_line_count(s: &Sbv, i: Int) -> Int {
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
pub fn sbv_cue_line(s: &Sbv, i: Int, j: Int) -> Str {
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

/// Payload of cue `i` as one Str, its lines joined with "\n"; "" when the
/// cue has no lines or `i` is negative or out of range.
pub fn sbv_cue_text(s: &Sbv, i: Int) -> Str {
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
