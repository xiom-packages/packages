// XIOM -- xiom.properties: Java .properties parsing and emitting with escapes
// and line continuations
// Greenfield package: pure XIOM, no FFI, no file I/O (in-memory Str only).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: one parsed file is two parallel vectors. `keys` holds every key in
// first-occurrence order; `values` holds the decoded value text, aligned by
// index. A duplicate key replaces its value in place, so the key keeps its
// first position and the last assignment wins. Vec[StructType] is unsupported
// in this compiler, so the file is deliberately flat (two Vec[Str]) instead of
// a list of key/value entry structs.
//
// Grammar (see SPEC.md for the full statement):
//   physical line = bytes* terminated by LF, CRLF or CR (a final line without
//                   a terminator is still a line)
//   logical line  = physical lines joined while the current one ends with an
//                   odd number of backslashes; the joining backslash is
//                   removed and the leading whitespace of each continuation
//                   line is stripped
//   line          = blank / comment / pair
//   comment       = ws* ( "#" / "!" ) bytes*     (a comment ends at the
//                   physical line end; a trailing backslash does not
//                   continue it, matching java.util.Properties)
//   pair          = ws* key [ ws* ( "=" / ":" )? ws* value ]
//   key           = ( escaped / byte-except-"="-":"-ws )*
//   value         = ( escaped / byte )*
//   escaped       = "\t" / "\n" / "\r" / "\f" / "\\" / "\u" HEX{4}
//                   / "\" byte          (unknown escape -> the byte itself)
//   ws            = SP | TAB | FF
// A malformed "\uXXXX" escape (truncated or non-hex) is
// Err("properties: malformed \\uxxxx escape in line: ...").
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Output bytes are collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str.
//   * Ok/Err for Result[Props, Str] and Result[Str, Str] are constructed only
//     in the tiny leaf helpers _ok_props/_err_props/_ok_str/_err_str
//     (constructing Results directly inside other functions miscompiles in
//     this compiler).
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison).

module xiom.properties

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(p) for Result[Props, Str].
fn _ok_props(p: Props) -> Result[Props, Str] {
  return Ok(p);
}

// Err(m) for Result[Props, Str].
fn _err_props(m: Str) -> Result[Props, Str] {
  return Err(m);
}

// Ok(s) for Result[Str, Str].
fn _ok_str(s: Str) -> Result[Str, Str] {
  return Ok(s);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _PROP_TAB: UInt8 = 9u8;
const _PROP_LF: UInt8 = 10u8;
const _PROP_FF: UInt8 = 12u8;
const _PROP_CR: UInt8 = 13u8;
const _PROP_SPACE: UInt8 = 32u8;
const _PROP_BANG: UInt8 = 33u8;
const _PROP_HASH: UInt8 = 35u8;
const _PROP_COLON: UInt8 = 58u8;
const _PROP_EQ: UInt8 = 61u8;
const _PROP_BS: UInt8 = 92u8;
const _PROP_LOWER_F: UInt8 = 102u8;
const _PROP_LOWER_N: UInt8 = 110u8;
const _PROP_LOWER_R: UInt8 = 114u8;
const _PROP_LOWER_T: UInt8 = 116u8;
const _PROP_LOWER_U: UInt8 = 117u8;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed .properties file: `keys` and `values` are index-aligned;
/// duplicate keys keep the position of their first occurrence and the value
/// of the last assignment.
pub type Props = {
  keys: Vec[Str];
  values: Vec[Str];
}

// --------------------------------------------------
//  Byte predicates
// --------------------------------------------------

// True for the intra-line whitespace bytes java.util.Properties skips:
// space, horizontal tab and form feed.
fn _is_ws(b: UInt8) -> Bool {
  return b == _PROP_SPACE || b == _PROP_TAB || b == _PROP_FF;
}

// Numeric value of a hex digit byte (0-9, a-f, A-F); -1 for any other byte.
fn _hex_value(b: UInt8) -> Int {
  let c = (b as Int) & 0xFF;
  if c >= 48 && c <= 57 {
    return c - 48;
  }
  if c >= 97 && c <= 102 {
    return c - 87;
  }
  if c >= 65 && c <= 70 {
    return c - 55;
  }
  return -1;
}

// Append the UTF-8 encoding of `code` (a BMP code point here) to `out`.
fn _push_utf8(out: &mut Vec[UInt8], code: Int) {
  if code <= 127 {
    out.push(code as UInt8);
    return;
  }
  if code <= 2047 {
    out.push((192 + code / 64) as UInt8);
    out.push((128 + code % 64) as UInt8);
    return;
  }
  if code <= 65535 {
    out.push((224 + code / 4096) as UInt8);
    out.push((128 + (code / 64) % 64) as UInt8);
    out.push((128 + code % 64) as UInt8);
    return;
  }
  out.push((240 + code / 262144) as UInt8);
  out.push((128 + (code / 4096) % 64) as UInt8);
  out.push((128 + (code / 64) % 64) as UInt8);
  out.push((128 + code % 64) as UInt8);
}

// --------------------------------------------------
//  Physical / logical line helpers
// --------------------------------------------------

// Split `text` into physical lines. LF, CRLF and a lone CR each terminate a
// line; a final line without a terminator is still returned, and a trailing
// terminator does not produce an extra empty line.
fn _split_lines(text: Str) -> Vec[Str] {
  var lines = Vec[Str].new();
  let n = text.len();
  var start = 0;
  var i = 0;
  while i < n {
    let b = string.byte_at(text, i);
    if b == _PROP_LF || b == _PROP_CR {
      lines.push(string.str_slice(text, start, i));
      if b == _PROP_CR && i + 1 < n && string.byte_at(text, i + 1) == _PROP_LF {
        i = i + 2;
      } else {
        i = i + 1;
      }
      start = i;
    } else {
      i = i + 1;
    }
  }
  if start < n {
    lines.push(string.str_slice(text, start, n));
  }
  return lines;
}

// True when `s` is empty or only whitespace.
fn _is_blank(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if !_is_ws(string.byte_at(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Left-strip whitespace (the continuation-line rule).
fn _lstrip_ws(s: Str) -> Str {
  var i = 0;
  while i < s.len() && _is_ws(string.byte_at(s, i)) {
    i = i + 1;
  }
  if i == 0 {
    return s;
  }
  return string.str_slice(s, i, s.len());
}

// True when the first non-whitespace byte is '#' or '!'.
fn _is_comment(s: Str) -> Bool {
  let t = _lstrip_ws(s);
  if t.len() == 0 {
    return false;
  }
  let b = string.byte_at(t, 0);
  return b == _PROP_HASH || b == _PROP_BANG;
}

// True when `s` ends with an odd number of backslashes: the last one is a
// line-continuation marker, while a trailing run of two is an escaped
// backslash and ends the logical line.
fn _ends_with_odd_backslash(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  var count = 0;
  var i = n;
  while i > 0 && string.byte_at(s, i - 1) == _PROP_BS {
    count = count + 1;
    i = i - 1;
  }
  return count % 2 == 1;
}

// --------------------------------------------------
//  Escape decoding
// --------------------------------------------------

// Decode the escapes of raw[from, to) into a Str.
// `\t` `\n` `\r` `\f` `\\` are single bytes; `\uXXXX` is four hex digits
// (case-insensitive) encoded to UTF-8; any other byte after a backslash is
// literal (Java behavior, so `\=`, `\:`, `\#`, `\!` and `\ ` decode to that
// byte). A truncated or non-hex `\u` is Err("properties: ...").
fn _decode_span(raw: Str, from: Int, to: Int) -> Result[Str, Str] {
  var out = Vec[UInt8].new();
  var i = from;
  while i < to {
    let b = string.byte_at(raw, i);
    if b != _PROP_BS {
      out.push(b);
      i = i + 1;
    } else {
      if i + 1 >= to {
        return _err_str("properties: trailing backslash in line: " + raw);
      }
      let e = string.byte_at(raw, i + 1);
      if e == _PROP_LOWER_T {
        out.push(_PROP_TAB);
        i = i + 2;
      } elif e == _PROP_LOWER_N {
        out.push(_PROP_LF);
        i = i + 2;
      } elif e == _PROP_LOWER_R {
        out.push(_PROP_CR);
        i = i + 2;
      } elif e == _PROP_LOWER_F {
        out.push(_PROP_FF);
        i = i + 2;
      } elif e == _PROP_LOWER_U {
        if i + 5 >= to {
          return _err_str("properties: malformed \\uxxxx escape in line: " + raw);
        }
        let h0 = _hex_value(string.byte_at(raw, i + 2));
        let h1 = _hex_value(string.byte_at(raw, i + 3));
        let h2 = _hex_value(string.byte_at(raw, i + 4));
        let h3 = _hex_value(string.byte_at(raw, i + 5));
        if h0 < 0 || h1 < 0 || h2 < 0 || h3 < 0 {
          return _err_str("properties: malformed \\uxxxx escape in line: " + raw);
        }
        let code = (h0 << 12) | (h1 << 8) | (h2 << 4) | h3;
        _push_utf8(&mut out, code);
        i = i + 6;
      } else {
        out.push(e);
        i = i + 2;
      }
    }
  }
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Pair parsing / mutation helpers
// --------------------------------------------------

// Parse one logical line into a single-pair Props. Leading whitespace is
// skipped; the key runs to the first unescaped '=', ':' or whitespace; the
// whitespace run and/or one optional '=' or ':' are consumed, plus the
// whitespace after it; the rest of the line is the value (escapes decoded,
// trailing whitespace kept, Java behavior).
fn _parse_line(line: Str) -> Result[Props, Str] {
  let n = line.len();
  var i = 0;
  while i < n && _is_ws(string.byte_at(line, i)) {
    i = i + 1;
  }
  let key_start = i;
  while i < n {
    let b = string.byte_at(line, i);
    if b == _PROP_EQ || b == _PROP_COLON || _is_ws(b) {
      break;
    }
    if b == _PROP_BS {
      i = i + 2;
    } else {
      i = i + 1;
    }
  }
  let key_end = i;
  while i < n && _is_ws(string.byte_at(line, i)) {
    i = i + 1;
  }
  if i < n {
    let b = string.byte_at(line, i);
    if b == _PROP_EQ || b == _PROP_COLON {
      i = i + 1;
    }
  }
  while i < n && _is_ws(string.byte_at(line, i)) {
    i = i + 1;
  }
  let val_start = i;
  var key = "";
  let kr = _decode_span(line, key_start, key_end);
  match kr {
    Ok(ks) => { key = ks; },
    Err(ke) => { return _err_props(ke); },
  }
  var value = "";
  let vr = _decode_span(line, val_start, n);
  match vr {
    Ok(vs) => { value = vs; },
    Err(ve) => { return _err_props(ve); },
  }
  var out = Props{ keys: Vec[Str].new(); values: Vec[Str].new(); };
  out.keys.push(key);
  out.values.push(value);
  return _ok_props(out);
}

// Index of `key` in p.keys, or -1. Str comparisons go through str_compare
// (BUG 17: `==` on Vec[Str] elements lowers to a pointer comparison).
fn _key_index(p: &Props, key: Str) -> Int {
  var i = 0;
  while i < p.keys.len() {
    let k: Str = p.keys[i];
    if compare.str_compare(k, key) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Store one pair with last-wins semantics: an existing key is replaced in
// place (keeping its first position), a new key is appended.
fn _set_pair(p: &mut Props, key: Str, value: Str) {
  let i = _key_index(p, key);
  if i >= 0 {
    p.values[i] = value;
    return;
  }
  p.keys.push(key);
  p.values.push(value);
}

// --------------------------------------------------
//  Emitting helpers
// --------------------------------------------------

// Append the emitted form of `s` (no quotes are used by .properties): `\` ->
// `\\`, LF -> `\n`, TAB -> `\t`, CR -> `\r`; every space is escaped as `\ `
// in a key (Java behavior; an interior space would otherwise end the key);
// spaces are escaped in a value only while they lead it; '=' ':' '#' '!' get
// a backslash in a key always, in a value only as the first byte. Non-ASCII
// bytes pass through verbatim as UTF-8.
fn _push_escaped(out: &mut Vec[UInt8], s: Str, is_key: Bool) {
  let n = s.len();
  var at_start = true;
  var i = 0;
  while i < n {
    let b = string.byte_at(s, i);
    if b == _PROP_BS {
      builder.sb_push_str(out, "\\\\");
    } elif b == _PROP_LF {
      builder.sb_push_str(out, "\\n");
    } elif b == _PROP_TAB {
      builder.sb_push_str(out, "\\t");
    } elif b == _PROP_CR {
      builder.sb_push_str(out, "\\r");
    } elif b == _PROP_SPACE && (is_key || at_start) {
      builder.sb_push_str(out, "\\ ");
    } elif (b == _PROP_EQ || b == _PROP_COLON || b == _PROP_HASH || b == _PROP_BANG) && (is_key || i == 0) {
      out.push(_PROP_BS);
      out.push(b);
    } else {
      out.push(b);
    }
    if b != _PROP_SPACE {
      at_start = false;
    }
    i = i + 1;
  }
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse one in-memory .properties document.
/// Params: text - the whole file contents (LF, CRLF or CR line endings).
/// Returns: Ok(Props) for a valid document (including an empty one); Err with
/// a "properties: ..." message on a malformed "\uXXXX" escape. Duplicate keys
/// are not an error: the last assignment wins and keeps the first position.
/// Complexity: O(total input length * key count) because duplicate detection
/// scans the key list per pair; O(total input length) with a hash index.
pub fn props_parse(text: Str) -> Result[Props, Str] {
  var props = Props{ keys: Vec[Str].new(); values: Vec[Str].new(); };
  let lines = _split_lines(text);
  let n = lines.len();
  var li = 0;
  while li < n {
    let raw: Str = lines[li];
    if _is_blank(raw) {
      li = li + 1;
      continue;
    }
    if _is_comment(raw) {
      li = li + 1;
      continue;
    }
    var buf = Vec[UInt8].new();
    var cur = raw;
    var joining = true;
    while joining {
      if _ends_with_odd_backslash(cur) {
        builder.sb_push_str(&mut buf, string.str_slice(cur, 0, cur.len() - 1));
        li = li + 1;
        if li >= n {
          joining = false;
        } else {
          let nxt: Str = lines[li];
          cur = _lstrip_ws(nxt);
        }
      } else {
        builder.sb_push_str(&mut buf, cur);
        li = li + 1;
        joining = false;
      }
    }
    let line = builder.sb_to_str(&buf);
    let pr = _parse_line(line);
    match pr {
      Ok(one) => {
        let k: Str = one.keys[0];
        let v: Str = one.values[0];
        _set_pair(&mut props, k, v);
      },
      Err(e) => { return _err_props(e); },
    }
  }
  return _ok_props(props);
}

/// Value of `key`; None when the key is absent. Keys are byte-exact and
/// case-sensitive.
pub fn props_get(p: &Props, key: Str) -> Option[Str] {
  let i = _key_index(p, key);
  if i < 0 {
    return None;
  }
  let v: Str = p.values[i];
  return Some(v);
}

/// Number of distinct keys.
pub fn props_count(p: &Props) -> Int {
  return p.keys.len();
}

/// Keys in first-occurrence order (a fresh copy).
pub fn props_keys(p: &Props) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < p.keys.len() {
    let k: Str = p.keys[i];
    out.push(k);
    i = i + 1;
  }
  return out;
}

/// Set `key` to `value` in a new Props: an existing key is replaced in place
/// (its position is kept), a new key is appended. `p` itself is untouched.
pub fn props_set(p: &Props, key: Str, value: Str) -> Props {
  var out = Props{ keys: Vec[Str].new(); values: Vec[Str].new(); };
  var i = 0;
  while i < p.keys.len() {
    let k: Str = p.keys[i];
    let v: Str = p.values[i];
    out.keys.push(k);
    out.values.push(v);
    i = i + 1;
  }
  _set_pair(&mut out, key, value);
  return out;
}

/// Emit one "key=value" line per entry (LF separated, no trailing LF) in
/// insertion order.
/// Params: p - the props to serialize.
/// Returns: properties text. `\` -> `\\`, LF -> `\n`, TAB -> `\t`, CR ->
/// `\r`; in a key every space becomes `\ `, in a value only leading spaces
/// are escaped; '=' ':' '#' '!' are escaped in a key and when they lead a
/// value. Non-ASCII bytes are written verbatim as UTF-8. Every parseable
/// document (and any Props built by props_set) round-trips through
/// props_emit and props_parse.
/// Error case: none.
/// Complexity: O(total output length).
pub fn props_emit(p: &Props) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < p.keys.len() {
    if i > 0 {
      out.push(_PROP_LF);
    }
    let k: Str = p.keys[i];
    let v: Str = p.values[i];
    _push_escaped(&mut out, k, true);
    out.push(_PROP_EQ);
    _push_escaped(&mut out, v, false);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}
