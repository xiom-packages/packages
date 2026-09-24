// XIOM -- xiom.querystring: application/x-www-form-urlencoded codec
// Greenfield package: pure XIOM, no FFI, no file I/O (in-memory Str only).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a query string is an ORDERED, FLAT list of name/value pairs. The
// compiler does not support Vec[StructType], so the Query struct holds two
// index-aligned parallel vectors (names[i], values[i]) instead of a list of
// pair structs. Pairs may repeat and order is preserved exactly as written;
// duplicates are never collapsed.
//
// Grammar (full statement in SPEC.md):
//   query      = [ "?" ] segment *( "&" segment )
//   segment    = decoded-name [ "=" decoded-value ]   ; first '=' splits
//   decoded    = form-decoded text                     ; '+' -> ' ', %XX -> byte
//   empty segment is skipped
//
// Decisions pinned by the conformance suite and SPEC.md:
//   * One optional leading '?' is dropped; '?' bytes after it are literal.
//   * Segments split on '&' only. An empty segment is skipped.
//   * A segment without '=' is a pair whose value is "".
//   * Empty names and empty values are preserved (only empty segments vanish).
//   * '+' decodes to a space; a well-formed "%XX" escape (hex in either case)
//     decodes to that byte; a malformed escape is kept literally -- the '%'
//     is emitted and scanning resumes at the next byte. Decoding is byte-wise
//     and error-free (a lone '%', "%2" and "%zz" all pass through unchanged).
//   * Names are compared byte-exactly and case-sensitively.
//   * Serialization always renders "name=value"; the space is '+' and every
//     byte outside the unreserved set [A-Za-z0-9-._~] becomes %XX with
//     uppercase hex digits.
//   * qs_set returns a NEW query (the source is never mutated): it replaces
//     the FIRST matching pair in place and appends otherwise. qs_remove
//     returns a NEW query with every pair of that name removed.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison); Vec elements are read into typed locals first.
//   * Bytes are read as (string.byte_at(s, i) as Int) & 0xFF and compared in
//     the Int domain; encoded output is collected in a plain Vec[UInt8] and
//     materialized once with xiom.string.builder.sb_to_str.

module xiom.querystring

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// An ordered, flat query string: `names` and `values` are index-aligned and
/// entry i is the pair `names[i]=values[i]`. Pairs may repeat; order is
/// preserved. A hand-built query that is ragged (unequal vector lengths) is
/// read only up to the shortest vector.
pub type Query = {
  names: Vec[Str];
  values: Vec[Str];
}

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _QS_SPACE: Int = 32;   // ' '
const _QS_PCT: Int = 37;     // '%'
const _QS_AMP: Int = 38;     // '&'
const _QS_PLUS: Int = 43;    // '+'
const _QS_EQ: Int = 61;      // '='
const _QS_QMARK: Int = 63;   // '?'

// --------------------------------------------------
//  Low-level helpers
// --------------------------------------------------

// One byte of `s` at `i`, zero-extended to Int (0..255).
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// Index of the first occurrence of byte `target` in `s`, or -1.
fn _find_byte(s: Str, target: Int) -> Int {
  var i = 0;
  while i < s.len() {
    if _byte(s, i) == target {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Number of usable entries: the two parallel vectors are only safe up to the
// shortest one (a hand-built query may be ragged).
fn _limit(q: &Query) -> Int {
  var lim = q.names.len();
  if q.values.len() < lim {
    lim = q.values.len();
  }
  return lim;
}

// Numeric value of a hex digit byte (0-9, a-f, A-F); -1 for any other byte.
fn _hex_val(b: Int) -> Int {
  if b >= 48 && b <= 57 { return b - 48; }
  if b >= 97 && b <= 102 { return b - 87; }
  if b >= 65 && b <= 70 { return b - 55; }
  return -1;
}

// Uppercase hex character for a nibble value (0-15).
fn _hex_digit(n: Int) -> UInt8 {
  if n < 10 { return (48 + n) as UInt8; }
  return (55 + n) as UInt8;
}

// True for an unreserved RFC 3986 byte: A-Z a-z 0-9 - _ . ~.
fn _is_unreserved(b: Int) -> Bool {
  if b >= 65 && b <= 90 { return true; }
  if b >= 97 && b <= 122 { return true; }
  if b >= 48 && b <= 57 { return true; }
  if b == 45 || b == 95 || b == 46 || b == 126 { return true; }
  return false;
}

// Append the form encoding of `s` to builder `sb`: space -> '+', unreserved
// bytes pass through, everything else -> %XX (uppercase). No Result channel:
// every byte is representable.
fn _push_component(sb: &mut Vec[UInt8], s: Str) {
  let n = s.len();
  var i = 0;
  while i < n {
    let b = _byte(s, i);
    if b == _QS_SPACE {
      sb.push(43u8);
    } elif _is_unreserved(b) {
      sb.push(b as UInt8);
    } else {
      sb.push(37u8);
      sb.push(_hex_digit(b >> 4));
      sb.push(_hex_digit(b & 15));
    }
    i = i + 1;
  }
}

// --------------------------------------------------
//  Component codec (public)
// --------------------------------------------------

/// Form-encode one name or value: spaces become '+', unreserved bytes
/// (A-Z a-z 0-9 - _ . ~) pass through, every other UTF-8 byte becomes %XX
/// with uppercase hex digits. Complexity: O(s.len()).
pub fn qs_encode_component(s: Str) -> Str {
  var sb = builder.sb_new();
  _push_component(&mut sb, s);
  return builder.sb_to_str(&sb);
}

/// Form-decode one name or value: '+' becomes a space and well-formed %XX
/// escapes (hex in either case) decode to their byte. Malformed escapes are
/// kept literally: the '%' is emitted and scanning resumes at the next byte,
/// so "%", "%2" and "%zz" pass through unchanged. Error-free by design.
/// Complexity: O(s.len()).
pub fn qs_decode_component(s: Str) -> Str {
  var sb = builder.sb_new();
  let n = s.len();
  var i = 0;
  while i < n {
    let b = _byte(s, i);
    if b == _QS_PLUS {
      sb.push(32u8);
      i = i + 1;
    } elif b == _QS_PCT && i + 2 < n {
      let hi = _hex_val(_byte(s, i + 1));
      let lo = _hex_val(_byte(s, i + 2));
      if hi < 0 || lo < 0 {
        sb.push(37u8);
        i = i + 1;
      } else {
        sb.push(((hi << 4) | lo) as UInt8);
        i = i + 3;
      }
    } else {
      sb.push(b as UInt8);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&sb);
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

// Store one '&'-separated segment into `q`. An empty segment is skipped; a
// segment without '=' is a pair whose value is "". Both sides are decoded.
fn _add_pair(q: &mut Query, seg: Str) {
  if seg.len() == 0 {
    return;
  }
  let eq = _find_byte(seg, _QS_EQ);
  var raw_name = seg;
  var raw_value = "";
  if eq >= 0 {
    raw_name = string.str_slice(seg, 0, eq);
    raw_value = string.str_slice(seg, eq + 1, seg.len());
  }
  let name = qs_decode_component(raw_name);
  let value = qs_decode_component(raw_value);
  q.names.push(name);
  q.values.push(value);
}

/// Parse an application/x-www-form-urlencoded query string into a fresh Query.
/// One optional leading '?' is dropped. Segments split on '&'; empty segments
/// are skipped; a segment without '=' gets the empty value "". '+' decodes to
/// a space and well-formed %XX escapes decode to bytes (malformed escapes are
/// kept literally); empty names and values are preserved and names may repeat
/// in first-seen order. Error case: none; every input yields a Query.
/// Complexity: O(text length).
pub fn qs_parse(text: Str) -> Query {
  var q = Query{ names: Vec[Str].new(); values: Vec[Str].new(); };
  let n = text.len();
  var start = 0;
  if n > 0 && _byte(text, 0) == _QS_QMARK {
    start = 1;
  }
  var i = start;
  while i <= n {
    if i == n || _byte(text, i) == _QS_AMP {
      let seg = string.str_slice(text, start, i);
      _add_pair(&mut q, seg);
      start = i + 1;
    }
    i = i + 1;
  }
  return q;
}

// --------------------------------------------------
//  Query inspection
// --------------------------------------------------

/// Number of pairs in `q` (min of the two parallel vector lengths, so a
/// hand-built ragged query never over-counts).
pub fn qs_count(q: &Query) -> Int {
  return _limit(q);
}

/// Value of the FIRST pair named `name`; None when absent. Names are compared
/// byte-exactly and case-sensitively via str_compare.
pub fn qs_get(q: &Query, name: Str) -> Option[Str] {
  let lim = _limit(q);
  var i = 0;
  while i < lim {
    let n: Str = q.names[i];
    if compare.str_compare(n, name) == 0 {
      let v: Str = q.values[i];
      return Some(v);
    }
    i = i + 1;
  }
  return None;
}

/// Values of EVERY pair named `name`, in pair order; an empty Vec when the
/// name is absent. Names are compared byte-exactly and case-sensitively.
pub fn qs_get_all(q: &Query, name: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let lim = _limit(q);
  var i = 0;
  while i < lim {
    let n: Str = q.names[i];
    if compare.str_compare(n, name) == 0 {
      let v: Str = q.values[i];
      out.push(v);
    }
    i = i + 1;
  }
  return out;
}

/// True when at least one pair is named `name` (byte-exact, case-sensitive).
pub fn qs_has(q: &Query, name: Str) -> Bool {
  let lim = _limit(q);
  var i = 0;
  while i < lim {
    let n: Str = q.names[i];
    if compare.str_compare(n, name) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  Immutable edits
// --------------------------------------------------

/// Return a NEW query (the source is never mutated) where the FIRST pair
/// named `name` has its value replaced by `value` in place; when `name` is
/// absent the pair `name=value` is appended. Later duplicates are kept as-is.
/// Complexity: O(pairs).
pub fn qs_set(q: &Query, name: Str, value: Str) -> Query {
  var out = Query{ names: Vec[Str].new(); values: Vec[Str].new(); };
  let lim = _limit(q);
  var replaced = false;
  var i = 0;
  while i < lim {
    let n: Str = q.names[i];
    if !replaced && compare.str_compare(n, name) == 0 {
      out.names.push(n);
      out.values.push(value);
      replaced = true;
    } else {
      let v: Str = q.values[i];
      out.names.push(n);
      out.values.push(v);
    }
    i = i + 1;
  }
  if !replaced {
    out.names.push(name);
    out.values.push(value);
  }
  return out;
}

/// Return a NEW query (the source is never mutated) with EVERY pair named
/// `name` removed; identical pairs of other names keep their order.
/// Complexity: O(pairs).
pub fn qs_remove(q: &Query, name: Str) -> Query {
  var out = Query{ names: Vec[Str].new(); values: Vec[Str].new(); };
  let lim = _limit(q);
  var i = 0;
  while i < lim {
    let n: Str = q.names[i];
    if compare.str_compare(n, name) != 0 {
      let v: Str = q.values[i];
      out.names.push(n);
      out.values.push(v);
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Serialization
// --------------------------------------------------

/// Render `q` as an application/x-www-form-urlencoded string: pairs joined
/// with '&', always "name=value", each side form-encoded (space -> '+',
/// unreserved kept, everything else %XX uppercase). An empty query renders
/// "". Complexity: O(total text length).
pub fn qs_serialize(q: &Query) -> Str {
  var sb = builder.sb_new();
  let lim = _limit(q);
  var i = 0;
  while i < lim {
    if i > 0 {
      sb.push(38u8);
    }
    let n: Str = q.names[i];
    let v: Str = q.values[i];
    _push_component(&mut sb, n);
    sb.push(61u8);
    _push_component(&mut sb, v);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}
