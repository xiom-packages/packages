// XIOM -- xiom.vtt: a strict, in-memory WebVTT subtitle codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (SPEC.md states the exact grammar):
//   * a "WEBVTT" signature line, optionally followed by space/tab and
//     trailing text, kept verbatim;
//   * header metadata lines: everything between the signature line and the
//     first blank line, kept verbatim;
//   * blank-line separated cue blocks with an optional cue identifier line,
//     a "hh:mm:ss.mmm --> hh:mm:ss.mmm" timing line (settings after the end
//     timestamp are passed through verbatim), and zero or more payload
//     lines;
//   * NOTE / STYLE / REGION blocks, preserved as raw text.
// The codec validates the documented subset strictly, keeps payload bytes
// exact, and round-trips canonical documents parse -> format -> parse.
// It does no rendering, no HTML/CSS parsing, and gives no semantics to cue
// settings, regions or voice spans beyond pass-through.
//
// Model: cues are stored flat, never as a Vec[StructType] (unsupported by
// this compiler). Parallel Vecs hold the start/end milliseconds, the
// optional identifier, the verbatim settings, and the payload-line range of
// every cue into one shared line buffer (`lines`). `order` interleaves cue
// entries (value 0) and raw blocks (value 1) so document structure
// round-trips.
//
// v0.61.3 notes that shaped this module (SPEC.md section 7):
//   * free functions only; no methods, lambdas, or match;
//   * Ok/Err are constructed only in the tiny leaf helpers below;
//   * Str values read from Vec[Str] are compared through
//     xiom.string.compare.str_compare, never `==` (BUG 17);
//   * every byte is read as Int through _byte(), so no UInt8 constant
//     >= 128 is involved in a comparison.

module xiom.vtt

use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Public data model
// --------------------------------------------------

/// A parsed WebVTT track: parallel per-cue arrays plus the preserved
/// non-cue material.
/// `signature` is the full signature line ("WEBVTT", "WEBVTT - title", ...).
/// `headers` holds the header metadata lines in document order. `order`
/// interleaves cue entries (value 0) and raw blocks (value 1) in document
/// order. Cue `i` has start/end milliseconds in `starts`/`ends`, an optional
/// identifier in `ids` ("" when absent), verbatim settings in `settings`
/// ("" when absent), and payload lines
/// `lines[payload_starts[i] .. payload_ends[i])`.
/// `raw_texts` holds each NOTE/STYLE/REGION block's lines joined with "\n",
/// and `raw_kinds` its keyword ("NOTE", "STYLE" or "REGION"), both in
/// document order. All cue vectors have `starts.len()` elements;
/// `raw_texts`/`raw_kinds` have one entry per order value of 1.
pub type Vtt = {
  signature: Str;
  headers: Vec[Str];
  order: Vec[Int];
  starts: Vec[Int];
  ends: Vec[Int];
  ids: Vec[Str];
  settings: Vec[Str];
  payload_starts: Vec[Int];
  payload_ends: Vec[Int];
  lines: Vec[Str];
  raw_texts: Vec[Str];
  raw_kinds: Vec[Str];
}

// --------------------------------------------------
//  Byte constants (Int, see the header note)
// --------------------------------------------------

const _TAB: Int = 9;
const _LF: Int = 10;
const _CR: Int = 13;
const _SPACE: Int = 32;
const _DOT: Int = 46;
const _COLON: Int = 58;
const _DASH: Int = 45;
const _GT: Int = 62;
const _ZERO: Int = 48;
const _NINE: Int = 57;

// --------------------------------------------------
//  Result and struct constructors (leaf helpers)
// --------------------------------------------------

// The one place a Vtt value is assembled from its parallel vectors.
fn _make_vtt(signature: Str, headers: Vec[Str], order: Vec[Int], starts: Vec[Int], ends: Vec[Int], ids: Vec[Str], settings: Vec[Str], payload_starts: Vec[Int], payload_ends: Vec[Int], lines: Vec[Str], raw_texts: Vec[Str], raw_kinds: Vec[Str]) -> Vtt {
  return Vtt{
    signature: signature;
    headers: headers;
    order: order;
    starts: starts;
    ends: ends;
    ids: ids;
    settings: settings;
    payload_starts: payload_starts;
    payload_ends: payload_ends;
    lines: lines;
    raw_texts: raw_texts;
    raw_kinds: raw_kinds;
  };
}

// Ok(v) for Result[Vtt, Str].
fn _ok_vtt(v: Vtt) -> Result[Vtt, Str] {
  return Ok(v);
}

// Err(m) for Result[Vtt, Str].
fn _err_vtt(m: Str) -> Result[Vtt, Str] {
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

// Slice [from, end) with surrounding spaces/tabs removed. Use this instead
// of calling _trim_range(s, from, s.len()) on a value read from a Vec[Str]
// element (see the header note).
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

// Parse a WebVTT timestamp to whole milliseconds.
// Accepted forms: "hh:mm:ss.mmm" (hours exactly two digits) and "mm:ss.mmm"
// (hours omitted, hours = 0). Minutes and seconds are two digits 00..59,
// milliseconds exactly three digits 000..999, separator exactly ".".
// Returns the millisecond value (>= 0), -1 for a bad shape, or -2 for an
// out-of-range component (minutes or seconds above 59).
fn _timestamp_ms(t: Str) -> Int {
  let n = t.len();
  if n == 12 {
    if _byte(t, 2) != _COLON { return -1; }
    if _byte(t, 5) != _COLON { return -1; }
    if _byte(t, 8) != _DOT { return -1; }
    let hh = _two_digits(t, 0);
    let mm = _two_digits(t, 3);
    let ss = _two_digits(t, 6);
    let mmm = _three_digits(t, 9);
    if hh < 0 || mm < 0 || ss < 0 || mmm < 0 { return -1; }
    if mm > 59 || ss > 59 { return -2; }
    return hh * 3600000 + mm * 60000 + ss * 1000 + mmm;
  }
  if n == 9 {
    if _byte(t, 2) != _COLON { return -1; }
    if _byte(t, 5) != _DOT { return -1; }
    let mm = _two_digits(t, 0);
    let ss = _two_digits(t, 3);
    let mmm = _three_digits(t, 6);
    if mm < 0 || ss < 0 || mmm < 0 { return -1; }
    if mm > 59 || ss > 59 { return -2; }
    return mm * 60000 + ss * 1000 + mmm;
  }
  return -1;
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

// True when `s` is a zero-byte line. Str comparison goes through str_compare
// (BUG 17).
fn _is_blank(s: Str) -> Bool {
  return compare.str_compare(s, "") == 0;
}

// True for a "WEBVTT" signature line: "WEBVTT" alone or followed by a
// space/tab and optional trailing text. Case-sensitive, per the format.
fn _is_signature_line(s: Str) -> Bool {
  if compare.str_compare(s, "WEBVTT") == 0 { return true; }
  if string.str_starts_with(s, "WEBVTT ") { return true; }
  if string.str_starts_with(s, "WEBVTT\t") { return true; }
  return false;
}

// True for a "NOTE" comment line: "NOTE" alone or followed by space/tab.
fn _is_note_line(s: Str) -> Bool {
  if compare.str_compare(s, "NOTE") == 0 { return true; }
  if string.str_starts_with(s, "NOTE ") { return true; }
  if string.str_starts_with(s, "NOTE\t") { return true; }
  return false;
}

// True for a "STYLE" block line: "STYLE" alone or followed by space/tab.
fn _is_style_line(s: Str) -> Bool {
  if compare.str_compare(s, "STYLE") == 0 { return true; }
  if string.str_starts_with(s, "STYLE ") { return true; }
  if string.str_starts_with(s, "STYLE\t") { return true; }
  return false;
}

// True for a "REGION" block line: "REGION" alone or followed by space/tab.
fn _is_region_line(s: Str) -> Bool {
  if compare.str_compare(s, "REGION") == 0 { return true; }
  if string.str_starts_with(s, "REGION ") { return true; }
  if string.str_starts_with(s, "REGION\t") { return true; }
  return false;
}

// Keyword of a raw block's first line: "NOTE", "STYLE", "REGION", or ""
// when the line would start a cue instead.
fn _kind_of_line(s: Str) -> Str {
  if _is_note_line(s) { return "NOTE"; }
  if _is_style_line(s) { return "STYLE"; }
  if _is_region_line(s) { return "REGION"; }
  return "";
}

// Join lines [from, to) with LF. Used for raw blocks; callers guarantee
// from < to.
fn _join_span(lines: &Vec[Str], from: Int, to: Int) -> Str {
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

// --------------------------------------------------
//  Parser
// --------------------------------------------------

// WebVTT body after the signature line. Everything before the first blank
// line is header metadata; the remainder is blank-line separated blocks,
// parsed as raw NOTE/STYLE/REGION blocks or as cues.
fn _parse_body(lines: &Vec[Str], signature: Str) -> Result[Vtt, Str] {
  var headers = Vec[Str].new();
  var order = Vec[Int].new();
  var starts = Vec[Int].new();
  var ends = Vec[Int].new();
  var ids = Vec[Str].new();
  var settings = Vec[Str].new();
  var payload_starts = Vec[Int].new();
  var payload_ends = Vec[Int].new();
  var store = Vec[Str].new();
  var raw_texts = Vec[Str].new();
  var raw_kinds = Vec[Str].new();

  let n = lines.len();
  var i = 1;
  // Header metadata: up to the first blank line (or end of input).
  while i < n {
    let hl: Str = lines[i];
    if _is_blank(hl) { break; }
    headers.push(hl);
    i = i + 1;
  }
  while i < n {
    let bl: Str = lines[i];
    if _is_blank(bl) {
      i = i + 1;
    } else {
      let bstart = i;
      var bend = i;
      while bend < n {
        let bl2: Str = lines[bend];
        if _is_blank(bl2) { break; }
        bend = bend + 1;
      }
      let first: Str = lines[bstart];
      let kind = _kind_of_line(first);
      if !_is_blank(kind) {
        raw_texts.push(_join_span(lines, bstart, bend));
        raw_kinds.push(kind);
        order.push(1);
      } else {
        // A cue block: optional identifier line, then the timing line.
        var ts = -1;
        var k = bstart;
        while k < bend {
          let kl: Str = lines[k];
          if _has_arrow(kl) {
            ts = k;
            break;
          }
          k = k + 1;
        }
        if ts < 0 { return _err_vtt("vtt: cue without timing"); }
        if ts > bstart + 1 { return _err_vtt("vtt: payload before timing"); }
        var cid = "";
        if ts == bstart + 1 {
          cid = lines[bstart];
        }
        let tl: Str = lines[ts];
        let arrow = _arrow_end(tl);
        let seg = _trim_range(tl, 0, arrow - 3);
        let ca = _timestamp_ms(seg);
        if ca == -1 { return _err_vtt("vtt: bad timestamp shape"); }
        if ca == -2 { return _err_vtt("vtt: timestamp out of range"); }
        let ea = _skip_ws(tl, arrow);
        let eb = _token_end(tl, ea);
        let et = string.str_slice(tl, ea, eb);
        let cb = _timestamp_ms(et);
        if cb == -1 { return _err_vtt("vtt: bad timestamp shape"); }
        if cb == -2 { return _err_vtt("vtt: timestamp out of range"); }
        if cb < ca { return _err_vtt("vtt: end before start"); }
        let stg = _trim_from(tl, eb);
        let p0 = store.len();
        var pl = ts + 1;
        while pl < bend {
          let pll: Str = lines[pl];
          store.push(pll);
          pl = pl + 1;
        }
        let p1 = store.len();
        starts.push(ca);
        ends.push(cb);
        ids.push(cid);
        settings.push(stg);
        payload_starts.push(p0);
        payload_ends.push(p1);
        order.push(0);
      }
      i = bend;
    }
  }
  return _ok_vtt(_make_vtt(signature, headers, order, starts, ends, ids, settings, payload_starts, payload_ends, store, raw_texts, raw_kinds));
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

// Canonical "HH:MM:SS.mmm" for `ms` (negative values clamp to zero). Hours
// print with more than two digits when they exceed 99.
fn _fmt_time(ms: Int) -> Str {
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
  out = out + ".";
  out = out + _pad3(mmm);
  return out;
}

// --------------------------------------------------
//  Public API -- parsing and formatting
// --------------------------------------------------

/// Parse a WebVTT document.
/// The first line must be a "WEBVTT" signature line (exactly "WEBVTT", or
/// "WEBVTT" followed by a space/tab and optional trailing text). Everything
/// between the signature line and the first blank line is header metadata
/// (kept verbatim; when there is no blank line, all remaining lines are
/// metadata and the track is empty). The body is blank-line separated
/// blocks: NOTE / STYLE / REGION blocks are preserved as raw text, and every
/// other block is a cue with an optional identifier line, a timing line and
/// zero or more payload lines. Timestamps accept "hh:mm:ss.mmm" and
/// "mm:ss.mmm"; settings after the end timestamp are passed through and not
/// interpreted. A blank line always ends a block, so payloads cannot
/// contain blank lines.
/// Errors: "vtt: missing signature", "vtt: cue without timing",
/// "vtt: payload before timing", "vtt: bad timestamp shape",
/// "vtt: timestamp out of range", "vtt: end before start"; see SPEC.md.
/// Complexity: O(input length).
pub fn vtt_parse(text: Str) -> Result[Vtt, Str] {
  let lines = _split_lines(text);
  if lines.len() == 0 { return _err_vtt("vtt: missing signature"); }
  let first: Str = lines[0];
  if !_is_signature_line(first) { return _err_vtt("vtt: missing signature"); }
  return _parse_body(&lines, first);
}

/// Serialize a track as canonical WebVTT.
/// Writes the stored signature line verbatim, then the header metadata lines,
/// then a blank separator line (when the track has cues or raw blocks), then
/// the blocks in document order separated by one blank line. Timestamps are
/// written "HH:MM:SS.mmm" (hours at least two digits); cue identifiers and
/// settings are written verbatim when present; every line is terminated by
/// LF. An empty track with the default signature serializes to "WEBVTT\n".
pub fn vtt_format(v: &Vtt) -> Str {
  var out = v.signature;
  out = out + "\n";
  var h = 0;
  while h < v.headers.len() {
    let hl: Str = v.headers[h];
    out = out + hl;
    out = out + "\n";
    h = h + 1;
  }
  let total = v.order.len();
  if total > 0 {
    out = out + "\n";
  }
  var ci = 0;
  var bi = 0;
  var k = 0;
  while k < total {
    let kind: Int = v.order[k];
    if kind == 0 {
      let cid: Str = v.ids[ci];
      if !_is_blank(cid) {
        out = out + cid;
        out = out + "\n";
      }
      let a: Int = v.starts[ci];
      let b: Int = v.ends[ci];
      out = out + _fmt_time(a);
      out = out + " --> ";
      out = out + _fmt_time(b);
      let stg: Str = v.settings[ci];
      if !_is_blank(stg) {
        out = out + " ";
        out = out + stg;
      }
      out = out + "\n";
      let p0: Int = v.payload_starts[ci];
      let p1: Int = v.payload_ends[ci];
      var p = p0;
      while p < p1 {
        let pl: Str = v.lines[p];
        out = out + pl;
        out = out + "\n";
        p = p + 1;
      }
      ci = ci + 1;
    } else {
      let rt: Str = v.raw_texts[bi];
      out = out + rt;
      out = out + "\n";
      bi = bi + 1;
    }
    if k + 1 < total {
      out = out + "\n";
    }
    k = k + 1;
  }
  return out;
}

// --------------------------------------------------
//  Public API -- timestamps
// --------------------------------------------------

/// Parse one WebVTT timestamp and return whole milliseconds.
/// Accepted forms: "hh:mm:ss.mmm" (hours exactly two digits, 00..99) and
/// "mm:ss.mmm" (hours omitted, treated as 00). Minutes and seconds must be
/// 00..59; milliseconds must be exactly three digits; the separator must be
/// ".". Leading/trailing whitespace is not allowed.
/// Errors: "vtt: bad timestamp shape" for a malformed shape,
/// "vtt: timestamp out of range" when minutes or seconds exceed 59.
pub fn vtt_timestamp_parse(t: Str) -> Result[Int, Str] {
  let ms = _timestamp_ms(t);
  if ms == -1 { return _err_int("vtt: bad timestamp shape"); }
  if ms == -2 { return _err_int("vtt: timestamp out of range"); }
  return _ok_int(ms);
}

/// Canonical timestamp text "HH:MM:SS.mmm" for `ms` (the reverse of
/// `vtt_timestamp_parse`). Negative values clamp to zero. Hours always print
/// with at least two digits, and with more than two digits above 99 hours
/// (such values are accepted here but rejected on parse, so they do not
/// round-trip; see SPEC.md).
pub fn vtt_timestamp_format(ms: Int) -> Str {
  return _fmt_time(ms);
}

// --------------------------------------------------
//  Public API -- accessors
// --------------------------------------------------

/// The signature line, exactly as stored by the parser (e.g. "WEBVTT" or
/// "WEBVTT - My captions").
pub fn vtt_signature(v: &Vtt) -> Str {
  return v.signature;
}

/// Number of header metadata lines.
pub fn vtt_header_count(v: &Vtt) -> Int {
  return v.headers.len();
}

/// Header metadata line `i`, verbatim; "" when `i` is negative or out of
/// range.
pub fn vtt_header(v: &Vtt, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= v.headers.len() { return ""; }
  let x: Str = v.headers[i];
  return x;
}

/// Number of cues.
pub fn vtt_cue_count(v: &Vtt) -> Int {
  return v.starts.len();
}

/// Identifier of cue `i` ("" when the cue has none, or when `i` is negative
/// or out of range).
pub fn vtt_cue_id(v: &Vtt, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= v.ids.len() { return ""; }
  let x: Str = v.ids[i];
  return x;
}

/// Start time of cue `i` in milliseconds; -1 when `i` is negative or out of
/// range.
pub fn vtt_cue_start_ms(v: &Vtt, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= v.starts.len() { return -1; }
  let x: Int = v.starts[i];
  return x;
}

/// End time of cue `i` in milliseconds; -1 when `i` is negative or out of
/// range.
pub fn vtt_cue_end_ms(v: &Vtt, i: Int) -> Int {
  if i < 0 { return -1; }
  if i >= v.ends.len() { return -1; }
  let x: Int = v.ends[i];
  return x;
}

/// Cue settings text of cue `i`, verbatim ("" when the cue has none, or when
/// `i` is negative or out of range).
pub fn vtt_cue_settings(v: &Vtt, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= v.settings.len() { return ""; }
  let x: Str = v.settings[i];
  return x;
}

/// Number of payload lines of cue `i`; 0 when `i` is negative or out of
/// range. A cue may legitimately have zero payload lines.
pub fn vtt_cue_line_count(v: &Vtt, i: Int) -> Int {
  if i < 0 { return 0; }
  if i >= v.payload_starts.len() { return 0; }
  let p0: Int = v.payload_starts[i];
  let p1: Int = v.payload_ends[i];
  return p1 - p0;
}

/// Payload line `j` of cue `i`, verbatim; "" when `i` or `j` is negative or
/// out of range.
pub fn vtt_cue_line(v: &Vtt, i: Int, j: Int) -> Str {
  if i < 0 { return ""; }
  if i >= v.payload_starts.len() { return ""; }
  if j < 0 { return ""; }
  let p0: Int = v.payload_starts[i];
  let p1: Int = v.payload_ends[i];
  if j >= p1 - p0 { return ""; }
  let idx = p0 + j;
  let x: Str = v.lines[idx];
  return x;
}

/// Payload of cue `i` as one Str, its lines joined with "\n"; "" when the cue
/// is empty or `i` is negative or out of range.
pub fn vtt_cue_text(v: &Vtt, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= v.payload_starts.len() { return ""; }
  let p0: Int = v.payload_starts[i];
  let p1: Int = v.payload_ends[i];
  var acc = "";
  var k = p0;
  while k < p1 {
    let x: Str = v.lines[k];
    if k > p0 { acc = acc + "\n"; }
    acc = acc + x;
    k = k + 1;
  }
  return acc;
}

/// Number of raw NOTE/STYLE/REGION blocks in document order.
pub fn vtt_block_count(v: &Vtt) -> Int {
  return v.raw_texts.len();
}

/// Raw text of block `i`: its lines joined with "\n", first line included;
/// "" when `i` is negative or out of range.
pub fn vtt_block_text(v: &Vtt, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= v.raw_texts.len() { return ""; }
  let x: Str = v.raw_texts[i];
  return x;
}

/// Keyword of raw block `i`: "NOTE", "STYLE" or "REGION"; "" when `i` is
/// negative or out of range.
pub fn vtt_block_kind(v: &Vtt, i: Int) -> Str {
  if i < 0 { return ""; }
  if i >= v.raw_kinds.len() { return ""; }
  let x: Str = v.raw_kinds[i];
  return x;
}

// --------------------------------------------------
//  Public API -- building
// --------------------------------------------------

/// Create an empty track with the default "WEBVTT" signature line, no header
/// metadata, no cues and no raw blocks.
pub fn vtt_new() -> Vtt {
  let headers = Vec[Str].new();
  let order = Vec[Int].new();
  let starts = Vec[Int].new();
  let ends = Vec[Int].new();
  let ids = Vec[Str].new();
  let settings = Vec[Str].new();
  let payload_starts = Vec[Int].new();
  let payload_ends = Vec[Int].new();
  let lines = Vec[Str].new();
  let raw_texts = Vec[Str].new();
  let raw_kinds = Vec[Str].new();
  return _make_vtt("WEBVTT", headers, order, starts, ends, ids, settings, payload_starts, payload_ends, lines, raw_texts, raw_kinds);
}

/// Return a copy of `v` with one cue appended at the end (after every
/// existing cue and raw block).
/// Params: id - cue identifier, "" for none; start_ms / end_ms - cue times in
/// milliseconds; settings - cue settings text passed through verbatim, ""
/// for none; text - cue payload, split into lines on LF.
/// Errors: "vtt: negative time" (a negative start or end);
/// "vtt: end before start"; "vtt: bad cue identifier" (id contains "-->" or
/// LF); "vtt: bad settings" (settings contains LF); "vtt: blank payload
/// line" (text contains an empty line, which WebVTT cannot represent because
/// a blank line ends the block). An empty `text` appends a cue with no
/// payload lines, which is valid. The input track is not modified.
pub fn vtt_cue_add(v: &Vtt, id: Str, start_ms: Int, end_ms: Int, settings: Str, text: Str) -> Result[Vtt, Str] {
  if start_ms < 0 { return _err_vtt("vtt: negative time"); }
  if end_ms < 0 { return _err_vtt("vtt: negative time"); }
  if end_ms < start_ms { return _err_vtt("vtt: end before start"); }
  if _has_arrow(id) { return _err_vtt("vtt: bad cue identifier"); }
  if string.str_contains(id, "\n") { return _err_vtt("vtt: bad cue identifier"); }
  if string.str_contains(settings, "\n") { return _err_vtt("vtt: bad settings"); }
  let plines = _split_lines(text);
  var j = 0;
  while j < plines.len() {
    let pl: Str = plines[j];
    if _is_blank(pl) { return _err_vtt("vtt: blank payload line"); }
    j = j + 1;
  }
  var n_headers = Vec[Str].new();
  var h = 0;
  while h < v.headers.len() {
    let x: Str = v.headers[h];
    n_headers.push(x);
    h = h + 1;
  }
  var n_order = Vec[Int].new();
  var ko = 0;
  while ko < v.order.len() {
    let x: Int = v.order[ko];
    n_order.push(x);
    ko = ko + 1;
  }
  var n_starts = Vec[Int].new();
  var ks = 0;
  while ks < v.starts.len() {
    let x: Int = v.starts[ks];
    n_starts.push(x);
    ks = ks + 1;
  }
  var n_ends = Vec[Int].new();
  var ke = 0;
  while ke < v.ends.len() {
    let x: Int = v.ends[ke];
    n_ends.push(x);
    ke = ke + 1;
  }
  var n_ids = Vec[Str].new();
  var ki = 0;
  while ki < v.ids.len() {
    let x: Str = v.ids[ki];
    n_ids.push(x);
    ki = ki + 1;
  }
  var n_settings = Vec[Str].new();
  var kt = 0;
  while kt < v.settings.len() {
    let x: Str = v.settings[kt];
    n_settings.push(x);
    kt = kt + 1;
  }
  var n_ps = Vec[Int].new();
  var kp = 0;
  while kp < v.payload_starts.len() {
    let x: Int = v.payload_starts[kp];
    n_ps.push(x);
    kp = kp + 1;
  }
  var n_pe = Vec[Int].new();
  var kq = 0;
  while kq < v.payload_ends.len() {
    let x: Int = v.payload_ends[kq];
    n_pe.push(x);
    kq = kq + 1;
  }
  var n_lines = Vec[Str].new();
  var kl = 0;
  while kl < v.lines.len() {
    let x: Str = v.lines[kl];
    n_lines.push(x);
    kl = kl + 1;
  }
  var n_raws = Vec[Str].new();
  var kr = 0;
  while kr < v.raw_texts.len() {
    let x: Str = v.raw_texts[kr];
    n_raws.push(x);
    kr = kr + 1;
  }
  var n_kinds = Vec[Str].new();
  var kk = 0;
  while kk < v.raw_kinds.len() {
    let x: Str = v.raw_kinds[kk];
    n_kinds.push(x);
    kk = kk + 1;
  }
  let p0 = n_lines.len();
  var q = 0;
  while q < plines.len() {
    let x: Str = plines[q];
    n_lines.push(x);
    q = q + 1;
  }
  let p1 = n_lines.len();
  n_order.push(0);
  n_starts.push(start_ms);
  n_ends.push(end_ms);
  n_ids.push(id);
  n_settings.push(settings);
  n_ps.push(p0);
  n_pe.push(p1);
  return _ok_vtt(_make_vtt(v.signature, n_headers, n_order, n_starts, n_ends, n_ids, n_settings, n_ps, n_pe, n_lines, n_raws, n_kinds));
}
