// XIOM -- xiom.dotenv: dotenv (.env) parsing and emitting with quoting and
// comment rules
// Greenfield package: pure XIOM, no FFI, no file I/O (in-memory Str only).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: one parsed file is two parallel vectors. `keys` holds every key in
// first-occurrence order; `values` holds the decoded scalar text, aligned by
// index. A duplicate key replaces its value in place, so the key keeps its
// first position and the last assignment wins. Vec[StructType] is unsupported
// in this compiler, so the file is deliberately flat (two Vec[Str]) instead of
// a list of key/value entry structs.
//
// Grammar (see SPEC.md for the full statement):
//   line       = ws* [ "export" ws+ ] key ws* "=" ws* value? [ comment ]
//   comment    = "#" ... EOL          (full-line: after leading ws; trailing:
//                                      "#" preceded by ws, outside quotes)
//   key        = ( ALPHA / "_" ) *( ALPHA / DIGIT / "_" )
//   value      = double-quoted (escapes \n \t \r \\ \") / single-quoted
//                (literal) / unquoted (trimmed; "#" preceded by ws starts a
//                trailing comment).
// Malformed lines, bad escapes and unterminated quotes are Err("dotenv: ...").
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Output bytes are collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str.
//   * Ok/Err for Result[EnvFile, Str] are constructed only in the tiny leaf
//     helpers _ok_env/_err_env (constructing Results directly inside other
//     functions miscompiles in this compiler).
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison).

module xiom.dotenv

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(f) for Result[EnvFile, Str].
fn _ok_env(f: EnvFile) -> Result[EnvFile, Str] {
  return Ok(f);
}

// Err(m) for Result[EnvFile, Str].
fn _err_env(m: Str) -> Result[EnvFile, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _DOTENV_TAB: UInt8 = 9u8;
const _DOTENV_LF: UInt8 = 10u8;
const _DOTENV_CR: UInt8 = 13u8;
const _DOTENV_SPACE: UInt8 = 32u8;
const _DOTENV_DQUOTE: UInt8 = 34u8;
const _DOTENV_HASH: UInt8 = 35u8;
const _DOTENV_SQUOTE: UInt8 = 39u8;
const _DOTENV_EQ: UInt8 = 61u8;
const _DOTENV_BS: UInt8 = 92u8;
const _DOTENV_UNDERSCORE: UInt8 = 95u8;
const _DOTENV_LOWER_N: UInt8 = 110u8;
const _DOTENV_LOWER_R: UInt8 = 114u8;
const _DOTENV_LOWER_T: UInt8 = 116u8;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed dotenv file: `keys` and `values` are index-aligned; duplicate
/// keys keep the position of their first occurrence and the value of the
/// last assignment.
pub type EnvFile = {
  keys: Vec[Str];
  values: Vec[Str];
}

// --------------------------------------------------
//  Byte predicates
// --------------------------------------------------

// True for an ASCII space or horizontal tab (the only intra-line whitespace).
fn _is_ws(b: UInt8) -> Bool {
  return b == _DOTENV_SPACE || b == _DOTENV_TAB;
}

// True for a key start byte: A-Z a-z _.
fn _is_key_start(c: Int) -> Bool {
  if c >= 65 && c <= 90 {
    return true;
  }
  if c >= 97 && c <= 122 {
    return true;
  }
  return c == 95;
}

// True for a key continuation byte: A-Z a-z 0-9 _.
fn _is_key_char(c: Int) -> Bool {
  if _is_key_start(c) {
    return true;
  }
  return c >= 48 && c <= 57;
}

// True when `s` starts with the exact byte sequence `w` at byte index `at`.
fn _match_word(s: Str, at: Int, w: Str) -> Bool {
  if at + w.len() > s.len() {
    return false;
  }
  var i = 0;
  while i < w.len() {
    if string.byte_at(s, at + i) != string.byte_at(w, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when `export` at byte `at` is an export prefix: the word exactly
// followed by whitespace. `exportFOO=x` is a key, `export FOO=x` is not.
fn _has_export_prefix(s: Str, at: Int) -> Bool {
  if !_match_word(s, at, "export") {
    return false;
  }
  let after = at + 6;
  if after >= s.len() {
    return false;
  }
  return _is_ws(string.byte_at(s, after));
}

// True when s[from, len) is only whitespace, or whitespace followed by a
// trailing comment. Used after a closing quote to reject stray text.
fn _rest_is_blank_or_comment(s: Str, from: Int) -> Bool {
  var i = from;
  while i < s.len() && _is_ws(string.byte_at(s, i)) {
    i = i + 1;
  }
  if i >= s.len() {
    return true;
  }
  return string.byte_at(s, i) == _DOTENV_HASH;
}

// --------------------------------------------------
//  File mutation helpers
// --------------------------------------------------

// Index of `key` in f.keys, or -1. Str comparisons go through str_compare
// (BUG 17: `==` on Vec[Str] elements lowers to a pointer comparison).
fn _key_index(f: &EnvFile, key: Str) -> Int {
  var i = 0;
  while i < f.keys.len() {
    if compare.str_compare(f.keys[i], key) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Store one pair with last-wins semantics: an existing key is replaced in
// place (keeping its first position), a new key is appended.
fn _set_pair(f: &mut EnvFile, key: Str, value: Str) {
  let i = _key_index(f, key);
  if i >= 0 {
    f.values[i] = value;
    return;
  }
  f.keys.push(key);
  f.values.push(value);
}

// --------------------------------------------------
//  Emitting helpers
// --------------------------------------------------

// True when `v` must be emitted double-quoted: empty, or containing space,
// tab, LF, CR, `#`, `"`, `'` or any non-ASCII byte. The control characters
// are included so their escapes can be re-applied (a bare LF would split the
// emitted line).
fn _needs_quotes(v: Str) -> Bool {
  let n = v.len();
  if n == 0 {
    return true;
  }
  var i = 0;
  while i < n {
    let c = (string.byte_at(v, i) as Int) & 0xFF;
    if c == 32 || c == 9 || c == 10 || c == 13 || c == 35 || c == 34 || c == 39 {
      return true;
    }
    if c >= 128 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Append the escaped body of `v` (without the surrounding quotes): `\` -> `\\`,
// `"` -> `\"`, LF -> `\n`, CR -> `\r`, TAB -> `\t`; every other byte verbatim.
fn _push_quoted(out: &mut Vec[UInt8], v: Str) {
  var i = 0;
  while i < v.len() {
    let b = string.byte_at(v, i);
    if b == _DOTENV_BS {
      builder.sb_push_str(out, "\\\\");
    } elif b == _DOTENV_DQUOTE {
      builder.sb_push_str(out, "\\\"");
    } elif b == _DOTENV_LF {
      builder.sb_push_str(out, "\\n");
    } elif b == _DOTENV_CR {
      builder.sb_push_str(out, "\\r");
    } elif b == _DOTENV_TAB {
      builder.sb_push_str(out, "\\t");
    } else {
      out.push(b);
    }
    i = i + 1;
  }
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse one in-memory dotenv document.
/// Params: text - the whole file contents (LF or CRLF line endings).
/// Returns: Ok(EnvFile) for a valid document (including an empty one); Err
/// with a "dotenv: ..." message on a malformed line, a bad escape or an
/// unterminated quote. Duplicate keys are not an error: the last assignment
/// wins and keeps the first position.
/// Complexity: O(total input length * key count) because duplicate detection
/// scans the key list per line; O(total input length) with a hash index.
pub fn dotenv_parse(text: Str) -> Result[EnvFile, Str] {
  var env = EnvFile{ keys: Vec[Str].new(); values: Vec[Str].new(); };
  let len = text.len();
  var line_start = 0;
  var i = 0;
  while i <= len {
    if i == len || string.byte_at(text, i) == _DOTENV_LF {
      var line = string.str_slice(text, line_start, i);
      let raw_len = line.len();
      if raw_len > 0 && string.byte_at(line, raw_len - 1) == _DOTENV_CR {
        line = string.str_slice(line, 0, raw_len - 1);
      }
      let line_len = line.len();
      var p = 0;
      while p < line_len && _is_ws(string.byte_at(line, p)) {
        p = p + 1;
      }
      if p < line_len && string.byte_at(line, p) != _DOTENV_HASH {
        if _has_export_prefix(line, p) {
          p = p + 6;
          while p < line_len && _is_ws(string.byte_at(line, p)) {
            p = p + 1;
          }
        }
        var k = p;
        if k < line_len && _is_key_start(string.byte_at(line, k) as Int) {
          k = k + 1;
          while k < line_len && _is_key_char(string.byte_at(line, k) as Int) {
            k = k + 1;
          }
        }
        if k == p {
          return _err_env("dotenv: missing key in line: " + line);
        }
        let key = string.str_slice(line, p, k);
        var q = k;
        while q < line_len && _is_ws(string.byte_at(line, q)) {
          q = q + 1;
        }
        if q >= line_len || string.byte_at(line, q) != _DOTENV_EQ {
          return _err_env("dotenv: expected '=' in line: " + line);
        }
        q = q + 1;
        while q < line_len && _is_ws(string.byte_at(line, q)) {
          q = q + 1;
        }
        if q >= line_len {
          _set_pair(&mut env, key, "");
        } elif string.byte_at(line, q) == _DOTENV_DQUOTE {
          var out = Vec[UInt8].new();
          var j = q + 1;
          var closed = -1;
          while j < line_len {
            let b = string.byte_at(line, j);
            if b == _DOTENV_BS {
              if j + 1 >= line_len {
                return _err_env("dotenv: unterminated double quote in line: " + line);
              }
              let e = string.byte_at(line, j + 1);
              if e == _DOTENV_LOWER_N {
                out.push(_DOTENV_LF);
              } elif e == _DOTENV_LOWER_T {
                out.push(_DOTENV_TAB);
              } elif e == _DOTENV_LOWER_R {
                out.push(_DOTENV_CR);
              } elif e == _DOTENV_BS {
                out.push(_DOTENV_BS);
              } elif e == _DOTENV_DQUOTE {
                out.push(_DOTENV_DQUOTE);
              } else {
                return _err_env("dotenv: invalid escape in line: " + line);
              }
              j = j + 2;
            } elif b == _DOTENV_DQUOTE {
              closed = j;
              break;
            } else {
              out.push(b);
              j = j + 1;
            }
          }
          if closed < 0 {
            return _err_env("dotenv: unterminated double quote in line: " + line);
          }
          if !_rest_is_blank_or_comment(line, closed + 1) {
            return _err_env("dotenv: unexpected text after quoted value in line: " + line);
          }
          _set_pair(&mut env, key, builder.sb_to_str(&out));
        } elif string.byte_at(line, q) == _DOTENV_SQUOTE {
          var j = q + 1;
          var closed = -1;
          while j < line_len {
            if string.byte_at(line, j) == _DOTENV_SQUOTE {
              closed = j;
              break;
            }
            j = j + 1;
          }
          if closed < 0 {
            return _err_env("dotenv: unterminated single quote in line: " + line);
          }
          if !_rest_is_blank_or_comment(line, closed + 1) {
            return _err_env("dotenv: unexpected text after quoted value in line: " + line);
          }
          _set_pair(&mut env, key, string.str_slice(line, q + 1, closed));
        } else {
          var j = q;
          var cut = line_len;
          while j < line_len {
            if string.byte_at(line, j) == _DOTENV_HASH && j > 0 && _is_ws(string.byte_at(line, j - 1)) {
              cut = j;
              break;
            }
            j = j + 1;
          }
          _set_pair(&mut env, key, string.str_trim(string.str_slice(line, q, cut)));
        }
      }
      line_start = i + 1;
    }
    i = i + 1;
  }
  return _ok_env(env);
}

/// Value of `key`; None when the key is absent. Keys are byte-exact and
/// case-sensitive.
pub fn dotenv_get(e: &EnvFile, key: Str) -> Option[Str] {
  let i = _key_index(e, key);
  if i < 0 {
    return None;
  }
  let v: Str = e.values[i];
  return Some(v);
}

/// True when the file contains `key`.
pub fn dotenv_has(e: &EnvFile, key: Str) -> Bool {
  return _key_index(e, key) >= 0;
}

/// Keys in first-occurrence order (a fresh copy).
pub fn dotenv_keys(e: &EnvFile) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < e.keys.len() {
    let k: Str = e.keys[i];
    out.push(k);
    i = i + 1;
  }
  return out;
}

/// Number of distinct keys in the file.
pub fn dotenv_len(e: &EnvFile) -> Int {
  return e.keys.len();
}

/// Emit one KEY=VALUE line per entry (LF separated, no trailing LF).
/// Params: e - the file to serialize.
/// Returns: dotenv text. A value is double-quoted when it is empty or
/// contains a space, tab, LF, CR, `#`, `"`, `'` or a non-ASCII byte; inside
/// quotes `\` -> `\\`, `"` -> `\"`, LF -> `\n`, CR -> `\r`, TAB -> `\t` are
/// re-applied. Every emitted document parses back to the same keys/values.
/// Error case: none.
/// Complexity: O(total output length).
pub fn dotenv_emit(e: &EnvFile) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < e.keys.len() {
    if i > 0 {
      out.push(_DOTENV_LF);
    }
    let k: Str = e.keys[i];
    let v: Str = e.values[i];
    builder.sb_push_str(&mut out, k);
    out.push(_DOTENV_EQ);
    if _needs_quotes(v) {
      out.push(_DOTENV_DQUOTE);
      _push_quoted(&mut out, v);
      out.push(_DOTENV_DQUOTE);
    } else {
      builder.sb_push_str(&mut out, v);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}
