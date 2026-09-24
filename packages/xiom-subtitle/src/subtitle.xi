// XIOM -- xiom.subtitle: SRT and WebVTT parsing, formatting and time shifting
// Port task: replace the xiom.subtitle placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: two subtitle text formats over in-memory Str documents:
//   * SRT (SubRip): blocks separated by blank lines; each block is a 1-based
//     index line, a "HH:MM:SS,mmm --> HH:MM:SS,mmm" line, and one or more
//     text lines.
//   * WebVTT: a "WEBVTT" header line, blank-line separated cues with
//     "HH:MM:SS.mmm" timestamps, NOTE comment blocks skipped, cue settings
//     after the arrow ignored. Cue identifiers are not supported.
// The text lines of one cue are joined with "\n" into a single Str.
//
// v0.61.3 notes that shaped this module (see SPEC.md section 7):
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (_ok_sub / _err_sub); the Subtitle literal itself is built by
//     _make_sub, mirroring the xiom.wav _ok_fmt / builder split.
//   * every byte of a Str is read through _byte() as an Int, so no UInt8
//     constant >= 128 is ever involved in a comparison.
//   * no Str equality uses `==`: the module scans bytes and lengths only,
//     and the tests route element checks through str_compare (BUG 17).
//   * no Vec[StructType] is needed: cues live in three parallel Vecs.
//
// See SPEC.md for the grammar, timestamp grammar, error catalog and test plan.

module xiom.subtitle

use xiom.string;
use xiom.string.compare;

/// A subtitle track: parallel per-cue arrays.
/// `starts` and `ends` hold cue start/end times in milliseconds; `texts`
/// holds each cue's text with embedded "\n" line breaks. All three Vecs have
/// the same length (the cue count).
pub type Subtitle = {
  starts: Vec[Int];
  ends: Vec[Int];
  texts: Vec[Str];
}

// --------------------------------------------------
//  Byte and digit constants (Int, see the header note)
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
//  Result constructors (see the module header)
// --------------------------------------------------

// The one place a Subtitle value is assembled from the three cue arrays.
fn _make_sub(starts: Vec[Int], ends: Vec[Int], texts: Vec[Str]) -> Subtitle {
  return Subtitle{
    starts: starts;
    ends: ends;
    texts: texts;
  };
}

// Ok(s) for Result[Subtitle, Str].
fn _ok_sub(s: Subtitle) -> Result[Subtitle, Str] {
  return Ok(s);
}

// Err(m) for Result[Subtitle, Str].
fn _err_sub(m: Str) -> Result[Subtitle, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal text helpers
// --------------------------------------------------

// Byte `pos` of `s` as an Int (0..255). Callers guarantee the bounds. Going
// through Int keeps every comparison away from UInt8 (see the header note).
fn _byte(s: Str, pos: Int) -> Int {
  return string.byte_at(s, pos) as Int;
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

// Parse a 12-byte "HH:MM:SS,mmm" or "HH:MM:SS.mmm" timestamp to whole
// milliseconds; -1 when malformed (wrong length, bad separators or digits,
// or minutes/seconds above 59). Hours may be 00..99.
fn _time_ms(t: Str) -> Int {
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
  if mm > 59 || ss > 59 { return -1; }
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

// Parse a 1-based cue index line: decimal digits only, value >= 1; -1 when
// the line is empty or not a positive decimal number.
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

// True when line `i` is zero bytes long.
fn _line_is_blank(lines: &Vec[Str], i: Int) -> Bool {
  let s: Str = lines[i];
  return s.len() == 0;
}

// True for a WebVTT NOTE line: "NOTE" alone or "NOTE" followed by a
// space/tab.
fn _is_note_line(lines: &Vec[Str], i: Int) -> Bool {
  let s: Str = lines[i];
  if !string.str_starts_with(s, "NOTE") { return false; }
  if s.len() == 4 { return true; }
  let c = _byte(s, 4);
  if c == _SPACE || c == _TAB { return true; }
  return false;
}

// True for the WebVTT header line: "WEBVTT" alone or followed by a
// space/tab (a signature suffix).
fn _is_header_line(s: Str) -> Bool {
  if !string.str_starts_with(s, "WEBVTT") { return false; }
  if s.len() == 6 { return true; }
  let c = _byte(s, 6);
  if c == _SPACE || c == _TAB { return true; }
  return false;
}

// Index of the first blank line at or after `from` (or the line count).
fn _text_end(lines: &Vec[Str], from: Int) -> Int {
  let n = lines.len();
  var i = from;
  while i < n && !_line_is_blank(lines, i) { i = i + 1; }
  return i;
}

// Join lines [from, to) with LF. Callers guarantee from < to (at least one
// text line was validated before calling).
fn _join_lines(lines: &Vec[Str], from: Int, to: Int) -> Str {
  var acc = "";
  var i = from;
  while i < to {
    let tl: Str = lines[i];
    if i > from { acc = acc + "\n"; }
    acc = acc + tl;
    i = i + 1;
  }
  return acc;
}

// Start timestamp: the range before the arrow, trimmed, parsed exactly.
fn _time_before(s: Str, arrow_end: Int) -> Int {
  let seg = _trim_range(s, 0, arrow_end - 3);
  return _time_ms(seg);
}

// SRT end timestamp: the whole range after the arrow must be one timestamp.
fn _time_after_exact(s: Str, arrow_end: Int) -> Int {
  let seg = _trim_range(s, arrow_end, s.len());
  return _time_ms(seg);
}

// WebVTT end timestamp: the first token after the arrow; the rest of the
// line (cue settings) is ignored.
fn _time_after_settings(s: Str, arrow_end: Int) -> Int {
  let a = _skip_ws(s, arrow_end);
  let b = _token_end(s, a);
  if b <= a { return -1; }
  return _time_ms(string.str_slice(s, a, b));
}

// --------------------------------------------------
//  Parsers
// --------------------------------------------------

// SRT: blank-line separated blocks, each with a strictly sequential 1-based
// index, one timestamp line and at least one text line.
fn _srt_parse_lines(lines: &Vec[Str]) -> Result[Subtitle, Str] {
  var starts = Vec[Int].new();
  var ends = Vec[Int].new();
  var texts = Vec[Str].new();
  let n = lines.len();
  var i = 0;
  while i < n {
    if _line_is_blank(lines, i) {
      i = i + 1;
    } else {
      let idx_line: Str = lines[i];
      let idx = _index_of(idx_line);
      if idx != starts.len() + 1 { return _err_sub("subtitle: bad index"); }
      i = i + 1;
      if i >= n { return _err_sub("subtitle: malformed block"); }
      let ts_line: Str = lines[i];
      let arrow = _arrow_end(ts_line);
      if arrow < 0 { return _err_sub("subtitle: missing arrow"); }
      let a = _time_before(ts_line, arrow);
      if a < 0 { return _err_sub("subtitle: bad time"); }
      let b = _time_after_exact(ts_line, arrow);
      if b < 0 { return _err_sub("subtitle: bad time"); }
      i = i + 1;
      if i >= n { return _err_sub("subtitle: missing cue text"); }
      if _line_is_blank(lines, i) { return _err_sub("subtitle: missing cue text"); }
      let tend = _text_end(lines, i);
      let acc = _join_lines(lines, i, tend);
      i = tend;
      starts.push(a);
      ends.push(b);
      texts.push(acc);
    }
  }
  if starts.len() == 0 { return _err_sub("subtitle: empty input"); }
  return _ok_sub(_make_sub(starts, ends, texts));
}

// WebVTT body (after the header line): blank-line separated cues; NOTE
// blocks are skipped; cue settings after the arrow are ignored.
fn _vtt_parse_lines(lines: &Vec[Str]) -> Result[Subtitle, Str] {
  var starts = Vec[Int].new();
  var ends = Vec[Int].new();
  var texts = Vec[Str].new();
  let n = lines.len();
  var i = 1;
  while i < n {
    if _line_is_blank(lines, i) {
      i = i + 1;
    } elif _is_note_line(lines, i) {
      i = i + 1;
      while i < n && !_line_is_blank(lines, i) { i = i + 1; }
    } else {
      let ts_line: Str = lines[i];
      let arrow = _arrow_end(ts_line);
      if arrow < 0 { return _err_sub("subtitle: missing arrow"); }
      let a = _time_before(ts_line, arrow);
      if a < 0 { return _err_sub("subtitle: bad time"); }
      let b = _time_after_settings(ts_line, arrow);
      if b < 0 { return _err_sub("subtitle: bad time"); }
      i = i + 1;
      if i >= n { return _err_sub("subtitle: missing cue text"); }
      if _line_is_blank(lines, i) { return _err_sub("subtitle: missing cue text"); }
      let tend = _text_end(lines, i);
      let acc = _join_lines(lines, i, tend);
      i = tend;
      starts.push(a);
      ends.push(b);
      texts.push(acc);
    }
  }
  return _ok_sub(_make_sub(starts, ends, texts));
}

/// Parse a SubRip (SRT) document.
/// Accepts LF and CRLF line endings. Blocks must be separated by blank
/// lines; each block is a 1-based index line that must be exactly
/// (cue number + 1) -- indices are strict and sequential -- a timestamp line
/// "HH:MM:SS,mmm --> HH:MM:SS,mmm" (a '.' separator is also accepted), and
/// one or more text lines. The cue text is the text lines joined with "\n".
/// Errors: "subtitle: empty input" (no cue blocks), "subtitle: bad index",
/// "subtitle: malformed block", "subtitle: missing arrow",
/// "subtitle: bad time", "subtitle: missing cue text"; see SPEC.md.
pub fn srt_parse(text: Str) -> Result[Subtitle, Str] {
  let lines = _split_lines(text);
  if lines.len() == 0 { return _err_sub("subtitle: empty input"); }
  return _srt_parse_lines(&lines);
}

/// Parse a WebVTT document.
/// The first line must be a "WEBVTT" header (optionally followed by a
/// space/tab and a signature suffix). Cues are blank-line separated,
/// timestamp lines are "HH:MM:SS.mmm --> HH:MM:SS.mmm" (a ',' separator is
/// also accepted), cue settings after the end timestamp are ignored, and
/// NOTE comment blocks are skipped. Cue identifiers are not supported.
/// A header with no cues is a valid, empty Subtitle.
/// Errors: "subtitle: missing WEBVTT header", "subtitle: missing arrow",
/// "subtitle: bad time", "subtitle: missing cue text"; see SPEC.md.
pub fn vtt_parse(text: Str) -> Result[Subtitle, Str] {
  let lines = _split_lines(text);
  if lines.len() == 0 { return _err_sub("subtitle: missing WEBVTT header"); }
  let header: Str = lines[0];
  if !_is_header_line(header) { return _err_sub("subtitle: missing WEBVTT header"); }
  return _vtt_parse_lines(&lines);
}

// --------------------------------------------------
//  Formatters
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

/// Serialize a Subtitle as SRT.
/// Cues are re-numbered from 1 in order; timestamps use the ',' separator;
/// lines are joined with LF; cue blocks are separated by a blank line and
/// the last cue's text line is terminated by LF. An empty Subtitle yields "".
pub fn srt_format(s: &Subtitle) -> Str {
  var out = "";
  let n = s.starts.len();
  var i = 0;
  while i < n {
    let a: Int = s.starts[i];
    let b: Int = s.ends[i];
    let t: Str = s.texts[i];
    if i > 0 { out = out + "\n"; }
    out = out + _int_str(i + 1);
    out = out + "\n";
    out = out + _fmt_time(a, ",");
    out = out + " --> ";
    out = out + _fmt_time(b, ",");
    out = out + "\n";
    out = out + t;
    out = out + "\n";
    i = i + 1;
  }
  return out;
}

/// Serialize a Subtitle as WebVTT.
/// Starts with a "WEBVTT" header line followed by a blank separator line
/// (when there is at least one cue), then the cues without indices;
/// timestamps use the '.' separator; cue blocks are separated by a blank
/// line. An empty Subtitle yields "WEBVTT\n".
pub fn vtt_format(s: &Subtitle) -> Str {
  var out = "WEBVTT\n";
  let n = s.starts.len();
  if n > 0 { out = out + "\n"; }
  var i = 0;
  while i < n {
    let a: Int = s.starts[i];
    let b: Int = s.ends[i];
    let t: Str = s.texts[i];
    if i > 0 { out = out + "\n"; }
    out = out + _fmt_time(a, ".");
    out = out + " --> ";
    out = out + _fmt_time(b, ".");
    out = out + "\n";
    out = out + t;
    out = out + "\n";
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Shift every cue by `delta_ms` (positive = later, negative = earlier),
/// clamping both times at 0. The cue count, texts and ordering are
/// preserved.
pub fn subtitle_shift(s: &Subtitle, delta_ms: Int) -> Subtitle {
  var ns = Vec[Int].new();
  var ne = Vec[Int].new();
  var nt = Vec[Str].new();
  let n = s.starts.len();
  var i = 0;
  while i < n {
    let a: Int = s.starts[i];
    let b: Int = s.ends[i];
    let t: Str = s.texts[i];
    var a2 = a + delta_ms;
    if a2 < 0 { a2 = 0; }
    var b2 = b + delta_ms;
    if b2 < 0 { b2 = 0; }
    ns.push(a2);
    ne.push(b2);
    nt.push(t);
    i = i + 1;
  }
  return _make_sub(ns, ne, nt);
}

/// Number of cues in the track.
pub fn subtitle_cue_count(s: &Subtitle) -> Int {
  return s.starts.len();
}

/// Start time of cue `i` in milliseconds; -1 when `i` is negative or out of
/// range.
pub fn subtitle_start_ms(s: &Subtitle, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= s.starts.len() { return -1; }
  let v: Int = s.starts[i];
  return v;
}

/// End time of cue `i` in milliseconds; -1 when `i` is negative or out of
/// range.
pub fn subtitle_end_ms(s: &Subtitle, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= s.ends.len() { return -1; }
  let v: Int = s.ends[i];
  return v;
}

/// Text of cue `i` (lines joined with "\n"); "" when `i` is negative or out
/// of range.
pub fn subtitle_text(s: &Subtitle, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= s.texts.len() { return ""; }
  let v: Str = s.texts[i];
  return v;
}

/// Duration of the track in milliseconds: the maximum cue end time,
/// clamped at 0, and 0 for an empty track.
pub fn subtitle_total_duration_ms(s: &Subtitle) -> Int {
  var m = 0;
  let n = s.ends.len();
  var i = 0;
  while i < n {
    let v: Int = s.ends[i];
    if v > m { m = v; }
    i = i + 1;
  }
  return m;
}
