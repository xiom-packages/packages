// XIOM -- xiom.systemd: systemd unit-file parsing and emitting
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: one parsed unit file is five parallel/range vectors. `sections`
// holds the distinct section names in first-seen order; section i owns the
// contiguous range [sec_starts[i], sec_starts[i] + sec_counts[i]) of the
// index-aligned `keys`/`values` vectors. Duplicate keys are preserved in
// order (no last-wins merge): `unit_get` returns the first match and
// `unit_get_last` the last. A repeated section header reopens the section and
// its entries are inserted at the end of that section's range, so ranges stay
// contiguous while per-section entry order is kept. Vec[StructType] is
// unsupported in this compiler, so the file is deliberately flat instead of a
// list of section or entry structs.
//
// Grammar (see SPEC.md for the full statement):
//   document   = *( physical )                      ; LF or CRLF terminated
//   physical   = *( byte except LF )                ; one trailing CR removed
//   logical    = physical *( "\" physical )         ; a trailing "\" joins the
//                                                     next physical line; the
//                                                     marker is removed and no
//                                                     separator is inserted
//   line       = ws* ( header / pair / comment / blank )
//   header     = "[" name "]" ws*
//   name       = 1*( ALPHA / DIGIT / "_" / "." / "-" )
//   pair       = key ws* "=" ws* value              ; value keeps trailing ws
//   key        = 1*( byte except "=", SP, TAB, LF, CR )
//   comment    = ( "#" / ";" ) *( byte except LF )  ; full line only; a
//                                                     trailing "#"/";" is data
//   ws         = SP | TAB
// A key line before the first section header, a malformed header, an empty
// key, a non-blank non-comment line without "=", a trailing continuation
// marker and C0 control bytes are Err("systemd: ...").
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Output bytes are collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str.
//   * Ok/Err for Result[Unit, Str] are constructed only in the tiny leaf
//     helpers _ok_unit/_err_unit (constructing Results directly inside other
//     functions miscompiles in this compiler).
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison).
//   * Every UInt8 read is widened with `(b as Int) & 0xFF` before a numeric
//     comparison, as required for the installed compiler.

module xiom.systemd

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(u) for Result[Unit, Str].
fn _ok_unit(u: Unit) -> Result[Unit, Str] {
  return Ok(u);
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str] (a scalar payload, see the module header).
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _SD_TAB: UInt8 = 9u8;
const _SD_LF: UInt8 = 10u8;
const _SD_CR: UInt8 = 13u8;
const _SD_SPACE: UInt8 = 32u8;
const _SD_HASH: UInt8 = 35u8;
const _SD_SEMI: UInt8 = 59u8;
const _SD_EQ: UInt8 = 61u8;
const _SD_LBRACKET: UInt8 = 91u8;
const _SD_BACKSLASH: UInt8 = 92u8;
const _SD_RBRACKET: UInt8 = 93u8;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed systemd unit file. `sections` lists the distinct section names in
/// first-seen order; section i owns the contiguous range
/// [sec_starts[i], sec_starts[i] + sec_counts[i]) of the index-aligned
/// `keys`/`values` vectors. Duplicate keys are preserved in order: the first
/// match is returned by `unit_get`, the last by `unit_get_last`.
pub type Unit = {
  sections: Vec[Str];
  sec_starts: Vec[Int];
  sec_counts: Vec[Int];
  keys: Vec[Str];
  values: Vec[Str];
}

// Internal: a clamped [start, count) span inside the flat key/value vectors.
type _Span = {
  start: Int;
  count: Int;
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// True for SP or TAB.
fn _is_ws(b: UInt8) -> Bool {
  return b == _SD_SPACE || b == _SD_TAB;
}

// True for a section-name byte: A-Z a-z 0-9 _ . -
fn _is_name_byte(c: Int) -> Bool {
  if c >= 65 && c <= 90 {
    return true;
  }
  if c >= 97 && c <= 122 {
    return true;
  }
  if c >= 48 && c <= 57 {
    return true;
  }
  return c == 95 || c == 46 || c == 45;
}

// Copy of `s` without leading SP/TAB.
fn _ltrim_ws(s: Str) -> Str {
  var i = 0;
  while i < s.len() && _is_ws(string.byte_at(s, i)) {
    i = i + 1;
  }
  return string.str_slice(s, i, s.len());
}

// Copy of `s` without trailing SP/TAB.
fn _rtrim_ws(s: Str) -> Str {
  var n = s.len();
  while n > 0 && _is_ws(string.byte_at(s, n - 1)) {
    n = n - 1;
  }
  return string.str_slice(s, 0, n);
}

// Byte index of the first '=' at or after `from`, or -1.
fn _find_eq(s: Str, from: Int) -> Int {
  var i = from;
  while i < s.len() {
    if string.byte_at(s, i) == _SD_EQ {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Smaller of two Int values.
fn _min_int(a: Int, b: Int) -> Int {
  if a < b {
    return a;
  }
  return b;
}

// Two lowercase hex digits for a byte value.
fn _hex_byte(v: Int) -> Str {
  let digits = "0123456789abcdef";
  let hi = (v / 16) % 16;
  let lo = v % 16;
  return string.str_slice(digits, hi, hi + 1) + string.str_slice(digits, lo, lo + 1);
}

// Reject C0 control bytes (any byte < 0x20 other than TAB and LF) anywhere in
// the input. CR is accepted only when it is immediately followed by LF, so a
// lone CR can never leak into a key or value. Returns None when the text is
// clean, Some(message) for the first offending byte.
fn _scan_bytes(text: Str) -> Option[Str] {
  let n = text.len();
  var i = 0;
  while i < n {
    let c = (string.byte_at(text, i) as Int) & 0xFF;
    if c < 32 && c != 9 && c != 10 {
      if c != 13 {
        return Some("systemd: control byte 0x" + _hex_byte(c) + " in input");
      }
      var next_is_lf = false;
      if i + 1 < n {
        if ((string.byte_at(text, i + 1) as Int) & 0xFF) == 10 {
          next_is_lf = true;
        }
      }
      if !next_is_lf {
        return Some("systemd: control byte 0x0d in input");
      }
    }
    i = i + 1;
  }
  return None;
}

// --------------------------------------------------
//  Storage helpers
// --------------------------------------------------

// Index of `name` in u.sections, or -1. Str comparisons go through
// str_compare (BUG 17: `==` on Str values read from Vec[Str] elements lowers
// to a pointer comparison).
fn _section_index(u: &Unit, name: Str) -> Int {
  var i = 0;
  while i < u.sections.len() {
    let s: Str = u.sections[i];
    if compare.str_compare(s, name) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of an existing section or of the freshly appended one.
fn _add_section(u: &mut Unit, name: Str) -> Int {
  let idx = _section_index(u, name);
  if idx >= 0 {
    return idx;
  }
  let at = u.keys.len();
  u.sections.push(name);
  u.sec_starts.push(at);
  u.sec_counts.push(0);
  return u.sections.len() - 1;
}

// Clamped [start, count) span of section `si`. A negative or unknown index
// yields a zero span and the count is clamped so the span never leaves either
// parallel vector; this keeps every accessor total even for a hand-built,
// drifted Unit.
fn _section_span(u: &Unit, si: Int) -> _Span {
  if si < 0 || si >= u.sections.len() || si >= u.sec_starts.len() || si >= u.sec_counts.len() {
    return _Span{ start: 0; count: 0; };
  }
  var start = u.sec_starts[si];
  var count = u.sec_counts[si];
  let n = _min_int(u.keys.len(), u.values.len());
  if start < 0 {
    start = 0;
  }
  if start > n {
    start = n;
  }
  if count < 0 {
    count = 0;
  }
  if start + count > n {
    count = n - start;
  }
  return _Span{ start: start; count: count; };
}

// Insert one entry at the end of section `si`, shifting the tail right so the
// section ranges stay contiguous and the keys/values vectors stay aligned.
fn _insert_entry(u: &mut Unit, si: Int, key: Str, value: Str) {
  if si < 0 || si >= u.sections.len() || si >= u.sec_starts.len() || si >= u.sec_counts.len() {
    return;
  }
  var at = u.sec_starts[si] + u.sec_counts[si];
  let n = u.keys.len();
  if at < 0 {
    at = 0;
  }
  if at > n {
    at = n;
  }
  u.keys.push(key);
  u.values.push(value);
  var j = n;
  while j > at {
    u.keys[j] = u.keys[j - 1];
    u.values[j] = u.values[j - 1];
    j = j - 1;
  }
  u.keys[at] = key;
  u.values[at] = value;
  u.sec_counts[si] = u.sec_counts[si] + 1;
  var t = si + 1;
  while t < u.sections.len() {
    u.sec_starts[t] = u.sec_starts[t] + 1;
    t = t + 1;
  }
}

// --------------------------------------------------
//  Line interpreter
// --------------------------------------------------

// Interpret one logical line against `u` and the current section index `cur`
// (-1 before the first header). Returns Ok(new current section index) for a
// header, Ok(cur) for a pair or a skipped blank/comment line, and Err(message)
// for the first error. Comments are recognised at the start of the line only:
// a '#' or ';' after the first byte is data and is never stripped.
fn _apply_line(u: &mut Unit, cur: Int, line: Str) -> Result[Int, Str] {
  let n = line.len();
  var p = 0;
  while p < n && _is_ws(string.byte_at(line, p)) {
    p = p + 1;
  }
  if p >= n {
    return _ok_int(cur);
  }
  let b0 = (string.byte_at(line, p) as Int) & 0xFF;
  if b0 == 35 || b0 == 59 {
    return _ok_int(cur);
  }
  if b0 == 91 {
    var e = n;
    while e > p + 1 && _is_ws(string.byte_at(line, e - 1)) {
      e = e - 1;
    }
    if e <= p + 1 || ((string.byte_at(line, e - 1) as Int) & 0xFF) != 93 {
      return _err_int("systemd: malformed section header: " + line);
    }
    let name = string.str_slice(line, p + 1, e - 1);
    let nl = name.len();
    if nl == 0 {
      return _err_int("systemd: empty section name: " + line);
    }
    var k = 0;
    while k < nl {
      if !_is_name_byte((string.byte_at(name, k) as Int) & 0xFF) {
        return _err_int("systemd: malformed section header: " + line);
      }
      k = k + 1;
    }
    return _ok_int(_add_section(u, name));
  }
  let eq = _find_eq(line, p);
  if eq < 0 {
    return _err_int("systemd: line without '=': " + line);
  }
  let key = _rtrim_ws(string.str_slice(line, p, eq));
  let kl = key.len();
  if kl == 0 {
    return _err_int("systemd: empty key in line: " + line);
  }
  var kk = 0;
  while kk < kl {
    if _is_ws(string.byte_at(key, kk)) {
      return _err_int("systemd: malformed key in line: " + line);
    }
    kk = kk + 1;
  }
  if cur < 0 {
    return _err_int("systemd: key before any section: " + line);
  }
  let value = _ltrim_ws(string.str_slice(line, eq + 1, n));
  _insert_entry(u, cur, key, value);
  return _ok_int(cur);
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse one in-memory systemd unit document.
/// Params: text - the whole file contents (LF or CRLF line endings).
/// Returns: Ok(Unit) for a valid document (including an empty one); Err with
/// a "systemd: ..." message on a C0 control byte, a key line before the first
/// section header, a malformed or empty section header, an empty or
/// whitespace-bearing key, a non-blank/non-comment line without '=', or a
/// continuation marker on the final physical line. Duplicate keys and
/// repeated section headers are not an error: duplicate keys keep their
/// document order, and a repeated header reopens the section in place.
/// Complexity: O(total input length * entry count) when sections are
/// reopened (entries are inserted into the middle of the flat vectors);
/// O(total input length) when every section appears once.
pub fn unit_parse(text: Str) -> Result[Unit, Str] {
  let clean = _scan_bytes(text);
  match clean {
    Some(m) => { return _err_unit(m); },
    None => {},
  }

  var u = Unit{
    sections: Vec[Str].new();
    sec_starts: Vec[Int].new();
    sec_counts: Vec[Int].new();
    keys: Vec[Str].new();
    values: Vec[Str].new();
  };
  var current = -1;
  let len = text.len();
  var line_start = 0;
  var i = 0;
  var acc = "";
  var pending = false;
  while i <= len {
    var is_lf = false;
    if i < len {
      if ((string.byte_at(text, i) as Int) & 0xFF) == 10 {
        is_lf = true;
      }
    }
    if i == len || is_lf {
      let has_line = i < len || line_start < len;
      if has_line {
        var seg = string.str_slice(text, line_start, i);
        let seg_len = seg.len();
        if seg_len > 0 && ((string.byte_at(seg, seg_len - 1) as Int) & 0xFF) == 13 {
          seg = string.str_slice(seg, 0, seg_len - 1);
        }
        var body = seg;
        let bl = body.len();
        var cont = false;
        if bl > 0 && ((string.byte_at(body, bl - 1) as Int) & 0xFF) == 92 {
          body = string.str_slice(body, 0, bl - 1);
          cont = true;
        }
        if pending {
          acc = acc + body;
        } else {
          acc = body;
        }
        if cont {
          pending = true;
        } else {
          let r = _apply_line(&mut u, current, acc);
          match r {
            Ok(nc) => { current = nc; },
            Err(m) => { return _err_unit(m); },
          }
          acc = "";
          pending = false;
        }
      }
      line_start = i + 1;
    }
    i = i + 1;
  }
  if pending {
    return _err_unit("systemd: continuation at end of input: " + acc);
  }
  return _ok_unit(u);
}

/// Number of distinct sections (repeated headers count once).
pub fn unit_section_count(u: &Unit) -> Int {
  return u.sections.len();
}

/// Number of key/value entries in the document across all sections, counting
/// duplicate keys separately.
pub fn unit_key_count(u: &Unit) -> Int {
  return u.keys.len();
}

/// Index of `name` in first-seen section order, or -1 when the document has
/// no such section. Section names are byte-exact and case-sensitive.
pub fn unit_section_index(u: &Unit, name: Str) -> Int {
  return _section_index(u, name);
}

/// Name of the section at `index`; None when the index is out of range.
pub fn unit_section_name(u: &Unit, index: Int) -> Option[Str] {
  if index < 0 || index >= u.sections.len() {
    return None;
  }
  let s: Str = u.sections[index];
  return Some(s);
}

/// Number of entries in the section at `index`, or -1 when the index is out
/// of range. Zero means the section exists but has no entries.
pub fn unit_section_key_count(u: &Unit, index: Int) -> Int {
  if index < 0 || index >= u.sections.len() {
    return -1;
  }
  let sp = _section_span(u, index);
  return sp.count;
}

/// Keys of the section at `index` in entry order (a fresh copy); an empty
/// vector when the index is out of range.
pub fn unit_section_keys(u: &Unit, index: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  if index < 0 || index >= u.sections.len() {
    return out;
  }
  let sp = _section_span(u, index);
  var j = 0;
  while j < sp.count {
    let k: Str = u.keys[sp.start + j];
    out.push(k);
    j = j + 1;
  }
  return out;
}

/// Value of the `key`-th entry of the section at `section` index; None when
/// either index is out of range.
pub fn unit_section_value_at(u: &Unit, section: Int, key: Int) -> Option[Str] {
  if section < 0 || section >= u.sections.len() {
    return None;
  }
  let sp = _section_span(u, section);
  if key < 0 || key >= sp.count {
    return None;
  }
  let v: Str = u.values[sp.start + key];
  return Some(v);
}

/// Key at flat entry index `index` (document order across sections); None
/// when the index is out of range.
pub fn unit_key_at(u: &Unit, index: Int) -> Option[Str] {
  if index < 0 || index >= u.keys.len() {
    return None;
  }
  let k: Str = u.keys[index];
  return Some(k);
}

/// Value at flat entry index `index`, index-aligned with `unit_key_at`; None
/// when the index is out of range.
pub fn unit_value_at(u: &Unit, index: Int) -> Option[Str] {
  if index < 0 || index >= u.values.len() {
    return None;
  }
  let v: Str = u.values[index];
  return Some(v);
}

/// First value assigned to (section, key); None when the pair is absent.
/// Section names and keys are byte-exact and case-sensitive; when the key
/// repeats, `unit_get` returns the first assignment and `unit_get_last` the
/// last.
pub fn unit_get(u: &Unit, section: Str, key: Str) -> Option[Str] {
  let si = _section_index(u, section);
  if si < 0 {
    return None;
  }
  let sp = _section_span(u, si);
  var j = 0;
  while j < sp.count {
    let k: Str = u.keys[sp.start + j];
    if compare.str_compare(k, key) == 0 {
      let v: Str = u.values[sp.start + j];
      return Some(v);
    }
    j = j + 1;
  }
  return None;
}

/// Last value assigned to (section, key); None when the pair is absent.
pub fn unit_get_last(u: &Unit, section: Str, key: Str) -> Option[Str] {
  let si = _section_index(u, section);
  if si < 0 {
    return None;
  }
  let sp = _section_span(u, si);
  var found = -1;
  var j = 0;
  while j < sp.count {
    let k: Str = u.keys[sp.start + j];
    if compare.str_compare(k, key) == 0 {
      found = sp.start + j;
    }
    j = j + 1;
  }
  if found < 0 {
    return None;
  }
  let v: Str = u.values[found];
  return Some(v);
}

/// Emit the canonical unit text.
/// Params: u - the document to serialize.
/// Returns: for every section in order, "[Name]" followed by one
/// "Key=Value" line per entry; exactly one blank line separates two sections
/// and there is no trailing LF. An empty document emits "". Keys, values and
/// section names are written verbatim (comments and continuation markers are
/// not reconstructed).
/// Error case: none.
/// Complexity: O(total output length).
pub fn unit_emit(u: &Unit) -> Str {
  var out = Vec[UInt8].new();
  let n = _min_int(u.keys.len(), u.values.len());
  var i = 0;
  while i < u.sections.len() {
    let name: Str = u.sections[i];
    if i > 0 {
      out.push(_SD_LF);
      out.push(_SD_LF);
    }
    out.push(_SD_LBRACKET);
    builder.sb_push_str(&mut out, name);
    out.push(_SD_RBRACKET);
    var start = 0;
    var count = 0;
    if i < u.sec_starts.len() && i < u.sec_counts.len() {
      start = u.sec_starts[i];
      count = u.sec_counts[i];
    }
    if start < 0 {
      start = 0;
    }
    if start > n {
      start = n;
    }
    if count < 0 {
      count = 0;
    }
    if start + count > n {
      count = n - start;
    }
    var j = 0;
    while j < count {
      out.push(_SD_LF);
      let k: Str = u.keys[start + j];
      let v: Str = u.values[start + j];
      builder.sb_push_str(&mut out, k);
      out.push(_SD_EQ);
      builder.sb_push_str(&mut out, v);
      j = j + 1;
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}
