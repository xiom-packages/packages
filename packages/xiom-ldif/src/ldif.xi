// XIOM -- xiom.ldif: LDIF (RFC 2849) content-entry codec
// Greenfield package: pure XIOM, no FFI, no file I/O (in-memory Str only).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: one parsed document is a flat set of parallel vectors. The range
// vectors `entry_start`/`entry_count` are index-aligned per entry: entry e
// owns the contiguous attribute range
// [entry_start[e], entry_start[e] + entry_count[e]). The attribute vectors
// `names`, `kinds`, `text`, `pool_start` and `pool_len` are index-aligned and
// hold every attribute of every entry in document order. `names` keeps the
// attribute description exactly as written, `kinds` is one of
// LDIF_KIND_PLAIN / LDIF_KIND_BASE64 / LDIF_KIND_URL, and `text` keeps the
// value text exactly as written (the plain value, the base64 text, or the URL
// token). For a base64 value the decoded bytes live in the shared `pool` at
// [pool_start[i], pool_start[i] + pool_len[i]); plain and URL values have
// pool_len == 0. A byte pool is used because base64 payloads are binary and
// may contain NUL, which a Str cannot carry. Vec[StructType] is unsupported
// in this compiler, so the structure is deliberately flat instead of a list
// of entry structs.
//
// Grammar (see SPEC.md for the full statement):
//   document   = *( blank / comment / entry )
//   blank      = *( SP / TAB ) LF              ; record separator
//   comment    = "#" *( byte except LF )       ; ignored, never folded
//   entry      = dn-line 1*( attr-line )       ; dn must be the first attribute
//   dn-line    = "dn" value-spec               ; matched case-insensitively
//   attr-line  = name value-spec
//   value-spec = ":" FILL plain / "::" FILL base64 / ":<" FILL url
//   name       = ALPHA *( ALPHA / DIGIT / HYPHEN )
//                *( ";" 1*( ALPHA / DIGIT / HYPHEN ) )
//   FILL       = *( SP )
//   fold       = SP byte*                      ; appends to the previous line
// Physical lines end at LF or CRLF; a final line without LF is still a line.
// A record is a maximal run of non-blank lines; comments are skipped
// everywhere and a blank line ends the record. `dn` is required as the first
// attribute (case-insensitive). `changetype` (case-insensitive) is rejected:
// change records are out of scope. Duplicate dn in one entry is rejected.
// Base64 is decoded by a strict self-contained decoder: canonical alphabet
// A-Z a-z 0-9 + /, length a positive multiple of 4, '=' only as the final
// one or two padding characters. No LDAP schema semantics, no URL fetching.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; every byte read goes through _ldif_byte_at, which
//     widens with `(x as Int) & 0xFF` (comparing a raw UInt8 above 0x7F
//     miscompiles).
//   * No bitwise shifts: base64 grouping uses multiplication, division and
//     modulo only (shifts on values with the high bit set miscompile).
//   * Free functions, no Vec[StructType], no Vec[fn]; Ok/Err are constructed
//     only in the tiny leaf helpers _ok_ldif/_err_ldif, _ok_rec/_err_rec and
//     _ok_bytes/_err_bytes (constructing Results directly inside larger
//     functions miscompiles).
//   * Str equality goes through xiom.string.compare (BUG 17: `==` on Str
//     values read from Vec[Str] elements lowers to a pointer comparison), and
//     Vec[Str] elements are read into typed locals before use.
//   * sb_to_str is never called on decoded payloads (its Str is
//     NUL-terminated); binary access is ldif_attr_bytes.

module xiom.ldif

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(l) for Result[Ldif, Str].
fn _ok_ldif(l: Ldif) -> Result[Ldif, Str] {
  return Ok(l);
}

// Err(m) for Result[Ldif, Str].
fn _err_ldif(m: Str) -> Result[Ldif, Str] {
  return Err(m);
}

// Ok(c) for Result[Int, Str] (a scalar payload: one entry's attribute count).
fn _ok_rec(c: Int) -> Result[Int, Str] {
  return Ok(c);
}

// Err(m) for Result[Int, Str].
fn _err_rec(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants (Int space; see the module header)
// --------------------------------------------------

const _LDIF_TAB: Int = 9;
const _LDIF_LF: Int = 10;
const _LDIF_CR: Int = 13;
const _LDIF_SPACE: Int = 32;
const _LDIF_HASH: Int = 35;
const _LDIF_PLUS: Int = 43;
const _LDIF_HYPHEN: Int = 45;
const _LDIF_SLASH: Int = 47;
const _LDIF_ZERO: Int = 48;
const _LDIF_NINE: Int = 57;
const _LDIF_COLON: Int = 58;
const _LDIF_SEMI: Int = 59;
const _LDIF_LT: Int = 60;
const _LDIF_EQ: Int = 61;
const _LDIF_UPPER_A: Int = 65;
const _LDIF_UPPER_Z: Int = 90;
const _LDIF_LOWER_A: Int = 97;
const _LDIF_LOWER_Z: Int = 122;

// Number of base64 characters carried by one emitted physical line.
const _LDIF_WRAP: Int = 76;

// --------------------------------------------------
//  Public value-kind constants
// --------------------------------------------------

/// Plain value: `name: value` (text stored verbatim in `text`).
pub const LDIF_KIND_PLAIN: Int = 0;
/// Base64 value: `name:: base64` (decoded bytes in the pool).
pub const LDIF_KIND_BASE64: Int = 1;
/// URL value: `name:< url` (raw token stored verbatim in `text`, never
/// fetched or validated).
pub const LDIF_KIND_URL: Int = 2;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed LDIF document. `entry_start` and `entry_count` are index-aligned
/// per entry: entry e owns the attribute range
/// [entry_start[e], entry_start[e] + entry_count[e]). The attribute vectors
/// `names`, `kinds`, `text`, `pool_start` and `pool_len` are index-aligned and
/// hold every attribute of every entry in document order. For a base64 value
/// the decoded bytes are pool[pool_start[i] .. pool_start[i] + pool_len[i]);
/// plain and URL values have pool_len == 0 and their text in `text`. Values
/// only come from ldif_parse, so the vectors never drift.
pub type Ldif = {
  entry_start: Vec[Int];
  entry_count: Vec[Int];
  names: Vec[Str];
  kinds: Vec[Int];
  text: Vec[Str];
  pool: Vec[UInt8];
  pool_start: Vec[Int];
  pool_len: Vec[Int];
}

// Internal: a clamped [start, count) span inside a flat vector.
type _Span = {
  start: Int;
  count: Int;
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Read byte i of s widened to 0..255. Every byte read in this module goes
// through here (see the module header).
fn _ldif_byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True for an ASCII space or horizontal tab.
fn _ldif_is_ws(b: Int) -> Bool {
  return b == _LDIF_SPACE || b == _LDIF_TAB;
}

// True for an ASCII letter.
fn _ldif_is_alpha(b: Int) -> Bool {
  if b >= _LDIF_UPPER_A && b <= _LDIF_UPPER_Z {
    return true;
  }
  return b >= _LDIF_LOWER_A && b <= _LDIF_LOWER_Z;
}

// True for an ASCII decimal digit.
fn _ldif_is_digit(b: Int) -> Bool {
  return b >= _LDIF_ZERO && b <= _LDIF_NINE;
}

// True for an attribute-description character after the first byte: letter,
// digit or hyphen (options are not separated here; see _ldif_name_ok).
fn _ldif_is_name_byte(b: Int) -> Bool {
  return _ldif_is_alpha(b) || _ldif_is_digit(b) || b == _LDIF_HYPHEN;
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

// Reject C0 control bytes anywhere in the input: any byte < 0x20 other than
// TAB and LF is an error, and CR is accepted only immediately before LF, so a
// lone CR can never leak into a value. Returns None when the text is clean,
// Some(message) for the first offending byte.
fn _ldif_scan_ctrl(text: Str) -> Option[Str] {
  let n = text.len();
  var i = 0;
  while i < n {
    let c = _ldif_byte_at(text, i);
    if c < 32 && c != _LDIF_TAB && c != _LDIF_LF {
      if c != _LDIF_CR {
        return Some("ldif: control byte 0x" + _hex_byte(c) + " in input");
      }
      var next_is_lf = false;
      if i + 1 < n {
        if _ldif_byte_at(text, i + 1) == _LDIF_LF {
          next_is_lf = true;
        }
      }
      if !next_is_lf {
        return Some("ldif: control byte 0x0d in input");
      }
    }
    i = i + 1;
  }
  return None;
}

// --------------------------------------------------
//  Physical / logical lines
// --------------------------------------------------

// Split text into physical lines. A line ends at LF or CRLF (one trailing CR
// is removed); a final line without a terminator is still a line and a
// trailing terminator does not produce an extra empty line.
fn _ldif_split_lines(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let len = text.len();
  if len == 0 {
    return out;
  }
  var line_start = 0;
  var i = 0;
  while i <= len {
    var is_lf = false;
    if i < len {
      if _ldif_byte_at(text, i) == _LDIF_LF {
        is_lf = true;
      }
    }
    if i == len || is_lf {
      if i < len || line_start < len {
        var seg = string.str_slice(text, line_start, i);
        let seg_len = seg.len();
        if seg_len > 0 && _ldif_byte_at(seg, seg_len - 1) == _LDIF_CR {
          seg = string.str_slice(seg, 0, seg_len - 1);
        }
        out.push(seg);
      }
      line_start = i + 1;
    }
    i = i + 1;
  }
  return out;
}

// True when every byte of `s` is SP or TAB (the empty line included).
fn _ldif_is_blank(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if !_ldif_is_ws(_ldif_byte_at(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Unfold physical lines into logical lines. A physical line that starts with
// SP and is not blank appends everything after that first SP to the current
// logical line; a blank line flushes the current line and contributes an
// empty marker (the record separator); a line whose first byte is '#' is a
// comment and is ignored (it is never folded and never ends a record). A
// continuation with no current logical line (start of input or right after a
// blank line) fails the whole document: returns false. `out` receives logical
// lines where "" is the blank marker.
fn _ldif_unfold(phys: &Vec[Str], out: &mut Vec[Str]) -> Bool {
  var cur = Vec[UInt8].new();
  var have = false;
  var i = 0;
  while i < phys.len() {
    let raw: Str = phys[i];
    if _ldif_is_blank(raw) {
      if have {
        out.push(builder.sb_to_str(&cur));
        cur = Vec[UInt8].new();
        have = false;
      }
      out.push("");
    } elif _ldif_byte_at(raw, 0) == _LDIF_SPACE {
      if !have {
        return false;
      }
      var k = 1;
      while k < raw.len() {
        cur.push(_ldif_byte_at(raw, k) as UInt8);
        k = k + 1;
      }
    } elif _ldif_byte_at(raw, 0) == _LDIF_HASH {
      // Comment line: ignored, never folded, never ends a record.
    } else {
      if have {
        out.push(builder.sb_to_str(&cur));
        cur = Vec[UInt8].new();
        have = false;
      }
      builder.sb_push_str(&mut cur, raw);
      have = true;
    }
    i = i + 1;
  }
  if have {
    out.push(builder.sb_to_str(&cur));
  }
  return true;
}

// --------------------------------------------------
//  Attribute-line scanning
// --------------------------------------------------

// Index of the first ':' of a logical line, or -1. The attribute description
// ends at the first colon, so no quoting or escaping is involved.
fn _ldif_colon(line: Str) -> Int {
  var i = 0;
  while i < line.len() {
    if _ldif_byte_at(line, i) == _LDIF_COLON {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when `name` matches the accepted attribute-description subset:
// ALPHA *( ALPHA / DIGIT / HYPHEN ) *( ";" 1*( ALPHA / DIGIT / HYPHEN ) ).
// The empty name, a leading digit, a space and a trailing or empty option
// ("a;", "a;;b") are all rejected.
fn _ldif_name_ok(name: Str) -> Bool {
  let n = name.len();
  if n == 0 {
    return false;
  }
  if !_ldif_is_alpha(_ldif_byte_at(name, 0)) {
    return false;
  }
  var i = 1;
  var need_key = false;
  while i < n {
    let b = _ldif_byte_at(name, i);
    if b == _LDIF_SEMI {
      if need_key {
        return false;
      }
      if i + 1 >= n {
        return false;
      }
      need_key = true;
    } elif _ldif_is_name_byte(b) {
      need_key = false;
    } else {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when `name` is "dn" under ASCII case folding.
fn _ldif_is_dn(name: Str) -> Bool {
  return compare.str_compare_ignore_case(name, "dn") == 0;
}

// True when `name` is "changetype" under ASCII case folding.
fn _ldif_is_changetype(name: Str) -> Bool {
  return compare.str_compare_ignore_case(name, "changetype") == 0;
}

// Value kind of the line, decided by the byte after the first colon:
// ':' -> base64, '<' -> url, anything else -> plain (including end of line).
fn _ldif_kind_at(line: Str, colon: Int) -> Int {
  let n = line.len();
  if colon + 1 < n {
    let b = _ldif_byte_at(line, colon + 1);
    if b == _LDIF_COLON {
      return LDIF_KIND_BASE64;
    }
    if b == _LDIF_LT {
      return LDIF_KIND_URL;
    }
  }
  return LDIF_KIND_PLAIN;
}

// Index of the first value byte: after ':' (plain) or after '::' / ':<'
// (base64 / url), then after any run of FILL spaces. The value runs to the
// end of the line.
fn _ldif_value_start(line: Str, colon: Int, kind: Int) -> Int {
  let n = line.len();
  var i = colon + 1;
  if kind != LDIF_KIND_PLAIN {
    i = i + 1;
  }
  while i < n && _ldif_byte_at(line, i) == _LDIF_SPACE {
    i = i + 1;
  }
  return i;
}

// --------------------------------------------------
//  Storage helpers
// --------------------------------------------------

// Append one attribute to the flat attribute vectors, copying `decoded` into
// the shared pool. `pool_start` is captured before the bytes are appended so
// the span stays correct; plain and URL values pass an empty `decoded`.
fn _push_attr(l: &mut Ldif, name: Str, kind: Int, text: Str, decoded: &Vec[UInt8]) {
  l.names.push(name);
  l.kinds.push(kind);
  l.text.push(text);
  let at = l.pool.len();
  l.pool_start.push(at);
  l.pool_len.push(decoded.len());
  var k = 0;
  while k < decoded.len() {
    let b: UInt8 = decoded[k];
    l.pool.push(b);
    k = k + 1;
  }
}

// Append one entry range [start, start + count).
fn _push_entry(l: &mut Ldif, start: Int, count: Int) {
  l.entry_start.push(start);
  l.entry_count.push(count);
}

// --------------------------------------------------
//  Base64 (strict, self-contained)
// --------------------------------------------------

// Base64 digit value (0..63) of one byte of the alphabet; -1 for '=' and for
// every other byte, including whitespace and non-ASCII.
fn _b64_value(c: Int) -> Int {
  if c >= _LDIF_UPPER_A && c <= _LDIF_UPPER_Z {
    return c - _LDIF_UPPER_A;
  }
  if c >= _LDIF_LOWER_A && c <= _LDIF_LOWER_Z {
    return c - _LDIF_LOWER_A + 26;
  }
  if c >= _LDIF_ZERO && c <= _LDIF_NINE {
    return c - _LDIF_ZERO + 52;
  }
  if c == _LDIF_PLUS {
    return 62;
  }
  if c == _LDIF_SLASH {
    return 63;
  }
  return -1;
}

// Strict base64 decode. Accepted exactly: a positive multiple of 4 bytes of
// the standard alphabet with 1 or 2 '=' padding characters only in the last
// quad; the unused low bits of the padded final byte are not checked. The
// encoded text carries no whitespace: folds are removed before decoding.
fn _b64_decode(s: Str) -> Result[Vec[UInt8], Str] {
  let n = s.len();
  if n == 0 {
    return _err_bytes("ldif: empty base64 value");
  }
  if n % 4 != 0 {
    return _err_bytes("ldif: base64 length is not a multiple of 4");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let b0 = _b64_value(_ldif_byte_at(s, i));
    let b1 = _b64_value(_ldif_byte_at(s, i + 1));
    let b2 = _b64_value(_ldif_byte_at(s, i + 2));
    let b3 = _b64_value(_ldif_byte_at(s, i + 3));
    if b0 < 0 || b1 < 0 {
      return _err_bytes("ldif: invalid base64 character");
    }
    out.push((b0 * 4 + b1 / 16) as UInt8);
    if b2 < 0 {
      if i + 4 != n {
        return _err_bytes("ldif: base64 padding before the final quad");
      }
      if _ldif_byte_at(s, i + 2) != _LDIF_EQ {
        return _err_bytes("ldif: invalid base64 padding");
      }
      if _ldif_byte_at(s, i + 3) != _LDIF_EQ {
        return _err_bytes("ldif: invalid base64 padding");
      }
      return _ok_bytes(out);
    }
    out.push(((b1 % 16) * 16 + b2 / 4) as UInt8);
    if b3 < 0 {
      if i + 4 != n {
        return _err_bytes("ldif: base64 padding before the final quad");
      }
      if _ldif_byte_at(s, i + 3) != _LDIF_EQ {
        return _err_bytes("ldif: invalid base64 padding");
      }
      return _ok_bytes(out);
    }
    out.push(((b2 % 4) * 64 + b3) as UInt8);
    i = i + 4;
  }
  return _ok_bytes(out);
}

// Append one canonical base64 character for the digit `v` (0..63).
fn _b64_push(out: &mut Vec[UInt8], v: Int) {
  let alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  out.push(string.byte_at(alpha, v));
}

// Canonical base64 encoding of pool[from, from + count), with '=' padding.
// The span is clamped to the pool, so a drifted Ldif cannot read out of
// bounds. No shifts are used (see the module header).
fn _b64_encode(pool: &Vec[UInt8], from: Int, count: Int, out: &mut Vec[UInt8]) {
  let n = pool.len();
  var start = from;
  var cnt = count;
  if start < 0 {
    start = 0;
  }
  if start > n {
    start = n;
  }
  if cnt < 0 {
    cnt = 0;
  }
  if start + cnt > n {
    cnt = n - start;
  }
  var i = 0;
  while i + 3 <= cnt {
    let b0 = (pool[start + i] as Int) & 0xFF;
    let b1 = (pool[start + i + 1] as Int) & 0xFF;
    let b2 = (pool[start + i + 2] as Int) & 0xFF;
    _b64_push(out, b0 / 4);
    _b64_push(out, (b0 % 4) * 16 + b1 / 16);
    _b64_push(out, (b1 % 16) * 4 + b2 / 64);
    _b64_push(out, b2 % 64);
    i = i + 3;
  }
  let rem = cnt - i;
  if rem == 1 {
    let b0 = (pool[start + i] as Int) & 0xFF;
    _b64_push(out, b0 / 4);
    _b64_push(out, (b0 % 4) * 16);
    out.push(_LDIF_EQ as UInt8);
    out.push(_LDIF_EQ as UInt8);
  } elif rem == 2 {
    let b0 = (pool[start + i] as Int) & 0xFF;
    let b1 = (pool[start + i + 1] as Int) & 0xFF;
    _b64_push(out, b0 / 4);
    _b64_push(out, (b0 % 4) * 16 + b1 / 16);
    _b64_push(out, (b1 % 16) * 4);
    out.push(_LDIF_EQ as UInt8);
  }
}

// --------------------------------------------------
//  Entry parsing
// --------------------------------------------------

// Parse one record: logical lines [from, to) (all non-blank). The first pass
// scans every line's name and enforces the structural rules in document
// order: a line without a colon, a malformed attribute description and a
// changetype line are reported where they appear, then the entry-level dn
// policy (exactly one dn attribute, first) is checked. The second pass
// decodes values left to right and appends the attributes. Returns Ok(the
// attribute count) or Err(message).
fn _ldif_parse_record(l: &mut Ldif, lines: &Vec[Str], from: Int, to: Int) -> Result[Int, Str] {
  var i = from;
  var dn_at = -1;
  var dn_count = 0;
  while i < to {
    let line: Str = lines[i];
    let colon = _ldif_colon(line);
    if colon < 0 {
      return _err_rec("ldif: line without colon: " + line);
    }
    let name = string.str_slice(line, 0, colon);
    if !_ldif_name_ok(name) {
      return _err_rec("ldif: malformed attribute name in line: " + line);
    }
    if _ldif_is_dn(name) {
      dn_count = dn_count + 1;
      dn_at = i - from;
    }
    if _ldif_is_changetype(name) {
      return _err_rec("ldif: changetype records are not supported in line: " + line);
    }
    i = i + 1;
  }
  if dn_count == 0 {
    return _err_rec("ldif: missing dn in entry");
  }
  if dn_count > 1 {
    return _err_rec("ldif: duplicate dn in entry");
  }
  if dn_at != 0 {
    let first: Str = lines[from];
    return _err_rec("ldif: attribute before dn: " + first);
  }

  let start = l.names.len();
  i = from;
  while i < to {
    let line: Str = lines[i];
    let colon = _ldif_colon(line);
    let name = string.str_slice(line, 0, colon);
    let kind = _ldif_kind_at(line, colon);
    let vs = _ldif_value_start(line, colon, kind);
    let text = string.str_slice(line, vs, line.len());
    var decoded = Vec[UInt8].new();
    if kind == LDIF_KIND_BASE64 {
      let br = _b64_decode(text);
      match br {
        Ok(d) => { decoded = d; },
        Err(_) => { return _err_rec("ldif: bad base64 in value: " + line); },
      }
    }
    _push_attr(l, name, kind, text, &decoded);
    i = i + 1;
  }
  _push_entry(l, start, to - from);
  return _ok_rec(to - from);
}

// --------------------------------------------------
//  Span accessors (total for any Ldif; see SPEC.md)
// --------------------------------------------------

// Number of entries present in both range vectors.
fn _ldif_entry_count(l: &Ldif) -> Int {
  return _min_int(l.entry_start.len(), l.entry_count.len());
}

// Number of attributes present in all five aligned attribute vectors.
fn _ldif_attr_total(l: &Ldif) -> Int {
  var n = _min_int(l.names.len(), l.kinds.len());
  n = _min_int(n, l.text.len());
  n = _min_int(n, l.pool_start.len());
  n = _min_int(n, l.pool_len.len());
  return n;
}

// Clamped attribute range of entry `e`: a zero span when `e` is out of range
// or the range vectors drift.
fn _ldif_entry_span(l: &Ldif, e: Int) -> _Span {
  if e < 0 || e >= _ldif_entry_count(l) {
    return _Span{ start: 0; count: 0; };
  }
  var start = l.entry_start[e];
  var count = l.entry_count[e];
  let n = _ldif_attr_total(l);
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

// Flat attribute index of attribute `i` of entry `e`, or -1 when either
// index is out of range.
fn _ldif_attr_index(l: &Ldif, e: Int, i: Int) -> Int {
  let sp = _ldif_entry_span(l, e);
  if i < 0 || i >= sp.count {
    return -1;
  }
  return sp.start + i;
}

// Clamped decoded-byte span of flat attribute `idx` inside the pool.
fn _ldif_pool_span(l: &Ldif, idx: Int) -> _Span {
  if idx < 0 || idx >= l.pool_start.len() || idx >= l.pool_len.len() {
    return _Span{ start: 0; count: 0; };
  }
  var start = l.pool_start[idx];
  var count = l.pool_len[idx];
  let n = l.pool.len();
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

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse one in-memory LDIF document.
/// Params: text - the whole file contents (LF or CRLF line endings).
/// Returns: Ok(Ldif) for a valid document, including an empty one and a
/// comment-only one; Err with a "ldif: ..." message otherwise. Records are
/// separated by blank lines and comments; each entry must start with `dn`
/// (case-insensitive) and `changetype` is rejected as unsupported (change
/// records are out of scope). See SPEC.md for the full grammar, the exact
/// error catalog and the error-precedence rules.
/// Complexity: O(total input length).
pub fn ldif_parse(text: Str) -> Result[Ldif, Str] {
  let clean = _ldif_scan_ctrl(text);
  match clean {
    Some(m) => { return _err_ldif(m); },
    None => {},
  }

  var l = Ldif{
    entry_start: Vec[Int].new();
    entry_count: Vec[Int].new();
    names: Vec[Str].new();
    kinds: Vec[Int].new();
    text: Vec[Str].new();
    pool: Vec[UInt8].new();
    pool_start: Vec[Int].new();
    pool_len: Vec[Int].new();
  };

  let phys = _ldif_split_lines(text);
  var logical = Vec[Str].new();
  if !_ldif_unfold(&phys, &mut logical) {
    return _err_ldif("ldif: continuation without previous line");
  }

  let n = logical.len();
  var i = 0;
  while i < n {
    let line: Str = logical[i];
    if line.len() == 0 {
      i = i + 1;
      continue;
    }
    var j = i;
    var scanning = true;
    while scanning {
      if j >= n {
        scanning = false;
      } else {
        let s: Str = logical[j];
        if s.len() == 0 {
          scanning = false;
        } else {
          j = j + 1;
        }
      }
    }
    let r = _ldif_parse_record(&mut l, &logical, i, j);
    match r {
      Ok(_) => {},
      Err(e) => { return _err_ldif(e); },
    }
    i = j;
  }
  return _ok_ldif(l);
}

/// Number of entries in the document.
pub fn ldif_entry_count(l: &Ldif) -> Int {
  return _ldif_entry_count(l);
}

/// Number of attributes in entry `e`; 0 when `e` is out of range. A parsed
/// entry always has at least one attribute (its dn).
pub fn ldif_entry_attr_count(l: &Ldif, e: Int) -> Int {
  return _ldif_entry_span(l, e).count;
}

/// DN of entry `e`: the text form of its first attribute. "" when `e` is out
/// of range. A parsed entry always starts with dn, so this is the entry's dn
/// for every entry.
pub fn ldif_dn(l: &Ldif, e: Int) -> Str {
  return ldif_attr_value(l, e, 0);
}

/// Attribute description of attribute `i` of entry `e`, exactly as written
/// (case and options preserved). "" when either index is out of range.
pub fn ldif_attr_name(l: &Ldif, e: Int, i: Int) -> Str {
  let idx = _ldif_attr_index(l, e, i);
  if idx < 0 {
    return "";
  }
  let nm: Str = l.names[idx];
  return nm;
}

/// Value kind of attribute `i` of entry `e`: LDIF_KIND_PLAIN,
/// LDIF_KIND_BASE64 or LDIF_KIND_URL. LDIF_KIND_PLAIN when either index is
/// out of range.
pub fn ldif_attr_kind(l: &Ldif, e: Int, i: Int) -> Int {
  let idx = _ldif_attr_index(l, e, i);
  if idx < 0 {
    return LDIF_KIND_PLAIN;
  }
  let k: Int = l.kinds[idx];
  return k;
}

/// True when attribute `i` of entry `e` was written in the URL form
/// (`name:< url`); false when either index is out of range. The URL token
/// itself is never fetched or validated (see ldif_attr_value).
pub fn ldif_attr_is_url(l: &Ldif, e: Int, i: Int) -> Bool {
  return ldif_attr_kind(l, e, i) == LDIF_KIND_URL;
}

/// Text form of attribute `i` of entry `e`. Plain values are their verbatim
/// text and URL values their verbatim raw token; a base64 value is its
/// decoded bytes read as text up to the first NUL byte (Str is NUL-
/// terminated, so a decoded payload may be truncated here -- use
/// ldif_attr_bytes for binary values). "" when either index is out of range.
pub fn ldif_attr_value(l: &Ldif, e: Int, i: Int) -> Str {
  let idx = _ldif_attr_index(l, e, i);
  if idx < 0 {
    return "";
  }
  let kind: Int = l.kinds[idx];
  if kind != LDIF_KIND_BASE64 {
    let t: Str = l.text[idx];
    return t;
  }
  let ps = _ldif_pool_span(l, idx);
  var out = Vec[UInt8].new();
  var k = 0;
  var stop = false;
  while k < ps.count && !stop {
    let b: UInt8 = l.pool[ps.start + k];
    if ((b as Int) & 0xFF) == 0 {
      stop = true;
    } else {
      out.push(b);
      k = k + 1;
    }
  }
  return builder.sb_to_str(&out);
}

/// Binary-safe value bytes of attribute `i` of entry `e`: the decoded bytes
/// for a base64 value, the raw bytes of the text for a plain or URL value.
/// An empty vector when either index is out of range.
pub fn ldif_attr_bytes(l: &Ldif, e: Int, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let idx = _ldif_attr_index(l, e, i);
  if idx < 0 {
    return out;
  }
  let kind: Int = l.kinds[idx];
  if kind == LDIF_KIND_BASE64 {
    let ps = _ldif_pool_span(l, idx);
    var k = 0;
    while k < ps.count {
      let b: UInt8 = l.pool[ps.start + k];
      out.push(b);
      k = k + 1;
    }
    return out;
  }
  let t: Str = l.text[idx];
  var k = 0;
  while k < t.len() {
    out.push(_ldif_byte_at(t, k) as UInt8);
    k = k + 1;
  }
  return out;
}

/// First value of the attribute named `name` in entry `e`, in attribute
/// order; None when entry `e` is out of range or has no such attribute.
/// Name matching is ASCII case-insensitive (LDAP attribute descriptions are
/// case-insensitive); repeated attributes yield the first one. The returned
/// text follows ldif_attr_value (base64 values are decoded, truncated at the
/// first NUL).
pub fn ldif_first_value(l: &Ldif, e: Int, name: Str) -> Option[Str] {
  let sp = _ldif_entry_span(l, e);
  var j = 0;
  while j < sp.count {
    let nm: Str = l.names[sp.start + j];
    if compare.str_compare_ignore_case(nm, name) == 0 {
      let v: Str = ldif_attr_value(l, e, j);
      return Some(v);
    }
    j = j + 1;
  }
  return None;
}

/// Label of a value kind: "plain", "base64", "url" or "unknown".
pub fn ldif_kind_label(kind: Int) -> Str {
  if kind == LDIF_KIND_PLAIN {
    return "plain";
  }
  if kind == LDIF_KIND_BASE64 {
    return "base64";
  }
  if kind == LDIF_KIND_URL {
    return "url";
  }
  return "unknown";
}

/// Emit the canonical LDIF text of a parsed document.
/// Params: l - the document to serialize.
/// Returns: the attributes of every entry in document order with LF line
/// endings and exactly one blank line between two entries, no trailing LF.
/// Plain values are written as "name: value" and URL values as "name:< url"
/// with one space after the marker, both verbatim. Base64 values are
/// re-encoded canonically from the decoded pool bytes as "name:: <base64>",
/// with 76 base64 characters per physical line and every continuation line
/// starting with exactly one space. An empty document emits "". A parsed
/// document round-trips: parse(emit(l)) has the same entries, attribute
/// names, kinds and values as `l` (see SPEC.md).
/// Error case: none (total; unknown kinds are written as plain values).
/// Complexity: O(total output length).
pub fn ldif_emit(l: &Ldif) -> Str {
  var out = Vec[UInt8].new();
  let ec = _ldif_entry_count(l);
  var e = 0;
  while e < ec {
    if e > 0 {
      out.push(_LDIF_LF as UInt8);
      out.push(_LDIF_LF as UInt8);
    }
    let sp = _ldif_entry_span(l, e);
    var a = 0;
    while a < sp.count {
      if a > 0 {
        out.push(_LDIF_LF as UInt8);
      }
      let idx = sp.start + a;
      let name: Str = l.names[idx];
      let kind: Int = l.kinds[idx];
      let text: Str = l.text[idx];
      builder.sb_push_str(&mut out, name);
      if kind == LDIF_KIND_BASE64 {
        out.push(_LDIF_COLON as UInt8);
        out.push(_LDIF_COLON as UInt8);
        out.push(_LDIF_SPACE as UInt8);
        var chars = Vec[UInt8].new();
        let pstart: Int = l.pool_start[idx];
        let plen: Int = l.pool_len[idx];
        _b64_encode(&l.pool, pstart, plen, &mut chars);
        var k = 0;
        var col = 0;
        while k < chars.len() {
          if col == _LDIF_WRAP {
            out.push(_LDIF_LF as UInt8);
            out.push(_LDIF_SPACE as UInt8);
            col = 0;
          }
          let cb: UInt8 = chars[k];
          out.push(cb);
          k = k + 1;
          col = col + 1;
        }
      } elif kind == LDIF_KIND_URL {
        out.push(_LDIF_COLON as UInt8);
        out.push(_LDIF_LT as UInt8);
        out.push(_LDIF_SPACE as UInt8);
        builder.sb_push_str(&mut out, text);
      } else {
        out.push(_LDIF_COLON as UInt8);
        out.push(_LDIF_SPACE as UInt8);
        builder.sb_push_str(&mut out, text);
      }
      a = a + 1;
    }
    e = e + 1;
  }
  return builder.sb_to_str(&out);
}
