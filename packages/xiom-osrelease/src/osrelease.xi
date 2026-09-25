// XIOM -- xiom.osrelease: /etc/os-release (systemd spec) parsing and
// canonical emitting
// Greenfield package: pure XIOM, no FFI, no file I/O (in-memory Str only).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: one parsed file is two parallel vectors. `keys` holds every
// assignment in document order; `values` holds the decoded value text,
// aligned by index. Repeats are preserved: the systemd spec forbids repeating
// keys but tells readers to prefer the later entry, so `osrelease_first` and
// `osrelease_last` expose both ends of a repeated key. Vec[StructType] is
// unsupported in this compiler, so the file is deliberately flat (two
// Vec[Str]) instead of a list of entry structs.
//
// Grammar (see SPEC.md for the full statement):
//   document   = *( line )                        ; LF or CRLF terminated
//   line       = blank / comment / assignment
//   blank      = SP*                              ; empty or spaces only
//   comment    = "#" *( byte except LF )          ; "#" must be byte 0
//   assignment = key "=" value
//   key        = ( ALPHA / "_" ) *( ALPHA / DIGIT / "_" )
//   value      = dquoted / squoted / unquoted
//   dquoted    = '"' *( escaped / byte-except-'"'-and-'\' ) '"'
//   escaped    = "\"" / "\\" / "\$" / "\`"
//   squoted    = "'" *( byte-except-"'" ) "'"
//   unquoted   = 1 *( byte-except-SP )            ; controls rejected below
// A control byte (0x00-0x1F or 0x7F) anywhere in a line is rejected, so TAB
// and a bare CR are not representable, inside quotes included. An unquoted
// value runs to end of line and may not contain a space; there are no
// trailing comments ("#" is a comment only as byte 0 of a line).
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Output bytes are collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str.
//   * Ok/Err are constructed only in the tiny leaf helpers _ok_rel/_err_rel
//     (Result[OsRelease, Str]) and _ok_str/_err_str (Result[Str, Str]);
//     constructing Results directly inside larger functions miscompiles in
//     this compiler.
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison).

module xiom.osrelease

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(r) for Result[OsRelease, Str].
fn _ok_rel(r: OsRelease) -> Result[OsRelease, Str] {
  return Ok(r);
}

// Err(m) for Result[OsRelease, Str].
fn _err_rel(m: Str) -> Result[OsRelease, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _OSR_LF: UInt8 = 10u8;
const _OSR_CR: UInt8 = 13u8;
const _OSR_SPACE: UInt8 = 32u8;
const _OSR_DQUOTE: UInt8 = 34u8;
const _OSR_HASH: UInt8 = 35u8;
const _OSR_DOLLAR: UInt8 = 36u8;
const _OSR_SQUOTE: UInt8 = 39u8;
const _OSR_EQ: UInt8 = 61u8;
const _OSR_BS: UInt8 = 92u8;
const _OSR_BACKTICK: UInt8 = 96u8;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed os-release file: `keys` and `values` are index-aligned and
/// preserve document order, including repeated keys (the spec forbids them
/// but asks readers to prefer the later entry).
pub type OsRelease = {
  keys: Vec[Str];
  values: Vec[Str];
}

// --------------------------------------------------
//  Byte predicates
// --------------------------------------------------

// True for a key start byte: A-Z a-z _.
fn _osr_is_key_start(c: Int) -> Bool {
  if c >= 65 && c <= 90 {
    return true;
  }
  if c >= 97 && c <= 122 {
    return true;
  }
  return c == 95;
}

// True for a key continuation byte: A-Z a-z 0-9 _.
fn _osr_is_key_char(c: Int) -> Bool {
  if _osr_is_key_start(c) {
    return true;
  }
  return c >= 48 && c <= 57;
}

// True for a C0 control byte or DEL. LF never reaches a line (lines are split
// on it) and a trailing CR has already been removed from CRLF input.
fn _osr_is_control(v: Int) -> Bool {
  if v < 32 {
    return true;
  }
  return v == 127;
}

// Byte index of the first control byte in `line`, or -1.
fn _osr_control_index(line: Str) -> Int {
  var i = 0;
  while i < line.len() {
    let v = (string.byte_at(line, i) as Int) & 0xFF;
    if _osr_is_control(v) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when the line is empty or contains only space bytes (0x20).
fn _osr_is_blank(line: Str) -> Bool {
  var i = 0;
  while i < line.len() {
    if string.byte_at(line, i) != _OSR_SPACE {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True for a byte that may appear in an unquoted emitted value: ASCII
// letters, digits and the URL-ish punctuation `. / : - _`. Everything else
// is emitted double-quoted (SPEC.md section on emission).
fn _osr_is_bare_byte(c: Int) -> Bool {
  if c >= 65 && c <= 90 {
    return true;
  }
  if c >= 97 && c <= 122 {
    return true;
  }
  if c >= 48 && c <= 57 {
    return true;
  }
  if c == 46 || c == 47 || c == 58 || c == 45 || c == 95 {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  Value decoding
// --------------------------------------------------

// Decode the value region line[from, line.len()): empty, single-quoted
// (literal), double-quoted (the four shell escapes) or unquoted (no space).
// Ok(v) on success; Err(full message) keeps the offending line text.
fn _osr_parse_value(line: Str, from: Int) -> Result[Str, Str] {
  let n = line.len();
  if from >= n {
    return _ok_str("");
  }
  let first = string.byte_at(line, from);
  if first == _OSR_DQUOTE {
    var out = Vec[UInt8].new();
    var j = from + 1;
    while j < n {
      let b = string.byte_at(line, j);
      if b == _OSR_BS {
        if j + 1 >= n {
          return _err_str("osrelease: unterminated double quote in line: " + line);
        }
        let e = string.byte_at(line, j + 1);
        if e == _OSR_DQUOTE {
          out.push(_OSR_DQUOTE);
        } elif e == _OSR_BS {
          out.push(_OSR_BS);
        } elif e == _OSR_DOLLAR {
          out.push(_OSR_DOLLAR);
        } elif e == _OSR_BACKTICK {
          out.push(_OSR_BACKTICK);
        } else {
          return _err_str("osrelease: invalid escape in line: " + line);
        }
        j = j + 2;
      } elif b == _OSR_DQUOTE {
        if j + 1 < n {
          return _err_str("osrelease: unexpected text after quoted value in line: " + line);
        }
        let v = builder.sb_to_str(&out);
        return _ok_str(v);
      } else {
        out.push(b);
        j = j + 1;
      }
    }
    return _err_str("osrelease: unterminated double quote in line: " + line);
  }
  if first == _OSR_SQUOTE {
    var j = from + 1;
    while j < n {
      if string.byte_at(line, j) == _OSR_SQUOTE {
        if j + 1 < n {
          return _err_str("osrelease: unexpected text after quoted value in line: " + line);
        }
        let v = string.str_slice(line, from + 1, j);
        return _ok_str(v);
      }
      j = j + 1;
    }
    return _err_str("osrelease: unterminated single quote in line: " + line);
  }
  var j = from;
  while j < n {
    if string.byte_at(line, j) == _OSR_SPACE {
      return _err_str("osrelease: whitespace in unquoted value in line: " + line);
    }
    j = j + 1;
  }
  let v = string.str_slice(line, from, n);
  return _ok_str(v);
}

// --------------------------------------------------
//  Lookup helpers
// --------------------------------------------------

// Index of the first `key` in r.keys, or -1. Str comparisons go through
// str_compare (BUG 17: `==` on Vec[Str] elements lowers to a pointer
// comparison).
fn _osr_first_index(r: &OsRelease, key: Str) -> Int {
  var i = 0;
  while i < r.keys.len() {
    let k: Str = r.keys[i];
    if compare.str_compare(k, key) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the last `key` in r.keys, or -1.
fn _osr_last_index(r: &OsRelease, key: Str) -> Int {
  var found = -1;
  var i = 0;
  while i < r.keys.len() {
    let k: Str = r.keys[i];
    if compare.str_compare(k, key) == 0 {
      found = i;
    }
    i = i + 1;
  }
  return found;
}

// --------------------------------------------------
//  Emitting helpers
// --------------------------------------------------

// True when `v` must be emitted double-quoted: any byte outside the bare
// alphabet [A-Za-z0-9./:-_]. The empty value stays bare (`KEY=`).
fn _osr_needs_quotes(v: Str) -> Bool {
  var i = 0;
  while i < v.len() {
    let c = (string.byte_at(v, i) as Int) & 0xFF;
    if !_osr_is_bare_byte(c) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Append the escaped body of `v` (without the surrounding quotes): `\` -> `\\`,
// `"` -> `\"`, `$` -> `\$`, backtick -> `\``; every other byte verbatim.
fn _osr_push_quoted(out: &mut Vec[UInt8], v: Str) {
  var i = 0;
  while i < v.len() {
    let b = string.byte_at(v, i);
    if b == _OSR_BS {
      builder.sb_push_str(out, "\\\\");
    } elif b == _OSR_DQUOTE {
      builder.sb_push_str(out, "\\\"");
    } elif b == _OSR_DOLLAR {
      builder.sb_push_str(out, "\\$");
    } elif b == _OSR_BACKTICK {
      builder.sb_push_str(out, "\\`");
    } else {
      out.push(b);
    }
    i = i + 1;
  }
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse one in-memory os-release document.
/// Params: text - the whole file contents (LF or CRLF line endings).
/// Returns: Ok(OsRelease) for a valid document (including an empty one); Err
/// with an "osrelease: ..." message on a malformed assignment, an invalid
/// key, an unterminated quote, an invalid escape, a control byte or an
/// unquoted whitespace byte. Repeated keys are not an error: every
/// assignment is preserved in document order.
/// Complexity: O(total input length).
pub fn osrelease_parse(text: Str) -> Result[OsRelease, Str] {
  var rel = OsRelease{ keys: Vec[Str].new(); values: Vec[Str].new(); };
  let len = text.len();
  var line_start = 0;
  var i = 0;
  while i <= len {
    if i == len || string.byte_at(text, i) == _OSR_LF {
      var line = string.str_slice(text, line_start, i);
      let raw_len = line.len();
      if raw_len > 0 && string.byte_at(line, raw_len - 1) == _OSR_CR {
        line = string.str_slice(line, 0, raw_len - 1);
      }
      let ctrl = _osr_control_index(line);
      if ctrl >= 0 {
        return _err_rel("osrelease: control byte in line: " + line);
      }
      let n = line.len();
      if !_osr_is_blank(line) && string.byte_at(line, 0) != _OSR_HASH {
        let c0 = (string.byte_at(line, 0) as Int) & 0xFF;
        if !_osr_is_key_start(c0) {
          return _err_rel("osrelease: invalid key in line: " + line);
        }
        var k = 1;
        while k < n && _osr_is_key_char((string.byte_at(line, k) as Int) & 0xFF) {
          k = k + 1;
        }
        if k >= n {
          return _err_rel("osrelease: missing '=' in line: " + line);
        }
        if string.byte_at(line, k) != _OSR_EQ {
          return _err_rel("osrelease: invalid key in line: " + line);
        }
        let key = string.str_slice(line, 0, k);
        let vr = _osr_parse_value(line, k + 1);
        match vr {
          Ok(v) => {
            rel.keys.push(key);
            rel.values.push(v);
          },
          Err(m) => {
            return _err_rel(m);
          },
        }
      }
      line_start = i + 1;
    }
    i = i + 1;
  }
  return _ok_rel(rel);
}

/// Number of assignments, repeats included.
pub fn osrelease_len(r: &OsRelease) -> Int {
  return r.keys.len();
}

/// Key of assignment `index`; None when index < 0 or index >= len.
pub fn osrelease_key_at(r: &OsRelease, index: Int) -> Option[Str] {
  if index < 0 || index >= r.keys.len() {
    return None;
  }
  let k: Str = r.keys[index];
  return Some(k);
}

/// Decoded value of assignment `index`; None when index < 0 or index >= len.
pub fn osrelease_value_at(r: &OsRelease, index: Int) -> Option[Str] {
  if index < 0 || index >= r.values.len() {
    return None;
  }
  let v: Str = r.values[index];
  return Some(v);
}

/// First value assigned to `key`; None when the key is absent. Keys are
/// byte-exact and case-sensitive.
pub fn osrelease_first(r: &OsRelease, key: Str) -> Option[Str] {
  let idx = _osr_first_index(r, key);
  if idx < 0 {
    return None;
  }
  let v: Str = r.values[idx];
  return Some(v);
}

/// Last value assigned to `key`; None when the key is absent. This is the
/// spec-recommended reader behavior for a repeated key.
pub fn osrelease_last(r: &OsRelease, key: Str) -> Option[Str] {
  let idx = _osr_last_index(r, key);
  if idx < 0 {
    return None;
  }
  let v: Str = r.values[idx];
  return Some(v);
}

/// True when the file contains `key` (repeats included).
pub fn osrelease_has(r: &OsRelease, key: Str) -> Bool {
  return _osr_first_index(r, key) >= 0;
}

/// Convenience for the `ID` field: its last value (spec readers prefer the
/// later entry), None when unset.
pub fn osrelease_id(r: &OsRelease) -> Option[Str] {
  return osrelease_last(r, "ID");
}

/// Convenience for the `ID_LIKE` field: its last value, None when unset.
pub fn osrelease_id_like(r: &OsRelease) -> Option[Str] {
  return osrelease_last(r, "ID_LIKE");
}

/// Convenience for the `VERSION_ID` field: its last value, None when unset.
pub fn osrelease_version_id(r: &OsRelease) -> Option[Str] {
  return osrelease_last(r, "VERSION_ID");
}

/// Emit one canonical os-release document from `r`.
/// Params: r - the file to serialize (`keys` and `values` index-aligned).
/// Returns: one `KEY=VALUE` line per assignment, LF separated, no trailing
/// LF. A value is written bare only when every byte is in [A-Za-z0-9./:-_];
/// otherwise it is double-quoted, with `\` -> `\\`, `"` -> `\"`, `$` -> `\$`
/// and backtick -> `\`` re-applied. The empty value is written as `KEY=`.
/// Every document emitted from a parsed file parses back to the same
/// entries. Values carrying C0 control bytes are written verbatim inside
/// quotes and are outside the accepted value domain (SPEC.md).
/// Error case: none.
/// Complexity: O(total output length).
pub fn osrelease_emit(r: &OsRelease) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < r.keys.len() {
    if i > 0 {
      out.push(_OSR_LF);
    }
    let k: Str = r.keys[i];
    let v: Str = r.values[i];
    builder.sb_push_str(&mut out, k);
    out.push(_OSR_EQ);
    if _osr_needs_quotes(v) {
      out.push(_OSR_DQUOTE);
      _osr_push_quoted(&mut out, v);
      out.push(_OSR_DQUOTE);
    } else {
      builder.sb_push_str(&mut out, v);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}
