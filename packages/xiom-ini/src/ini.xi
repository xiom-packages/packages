// XIOM -- xiom.ini: INI file parsing, editing and emitting with ordered
// sections
// Greenfield package: pure XIOM, no FFI, no file I/O (in-memory Str only).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: one parsed file is three parallel vectors. `sections`, `keys` and
// `values` are index-aligned: entry i lives in section sections[i] under key
// keys[i] with value values[i]. The empty section ("") is the global /
// top-level area. Entries keep first-seen order; when a (section, key) pair
// repeats, the value is replaced in place, so the entry keeps its first
// position and the last assignment wins. Vec[StructType] is unsupported in
// this compiler, so the file is deliberately flat (three Vec[Str]) instead of
// a list of section/entry structs.
//
// Grammar (see SPEC.md for the full statement):
//   line       = ws* ( header / pair / comment / blank )
//   header     = "[" ws* name ws* "]"
//   pair       = key ws* ( "=" / ":" ) ws* value
//   comment    = ( ";" / "#" ) *( byte except LF )     (full line only)
//   ws         = SP | TAB
// The whole line is trimmed first; a line whose first byte is "[" must be a
// well-formed header, and any other non-blank, non-comment line without a
// separator is Err("ini: ..."). Key and value are trimmed; an empty key is
// Err. CRLF is accepted (one trailing CR is removed).
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Output bytes are collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str.
//   * Ok/Err for Result[Ini, Str] are constructed only in the tiny leaf
//     helpers _ok_ini/_err_ini (constructing Results directly inside other
//     functions miscompiles in this compiler).
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison).

module xiom.ini

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(i) for Result[Ini, Str].
fn _ok_ini(i: Ini) -> Result[Ini, Str] {
  return Ok(i);
}

// Err(m) for Result[Ini, Str].
fn _err_ini(m: Str) -> Result[Ini, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _INI_TAB: UInt8 = 9u8;
const _INI_LF: UInt8 = 10u8;
const _INI_CR: UInt8 = 13u8;
const _INI_HASH: UInt8 = 35u8;
const _INI_COLON: UInt8 = 58u8;
const _INI_SEMI: UInt8 = 59u8;
const _INI_EQ: UInt8 = 61u8;
const _INI_LBRACKET: UInt8 = 91u8;
const _INI_RBRACKET: UInt8 = 93u8;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed INI file: `sections`, `keys` and `values` are index-aligned.
/// The empty section ("") is the global/top-level area; a duplicate
/// (section, key) pair keeps the position of its first occurrence and the
/// value of the last assignment.
pub type Ini = {
  sections: Vec[Str];
  keys: Vec[Str];
  values: Vec[Str];
}

// --------------------------------------------------
//  Scanning helpers
// --------------------------------------------------

// Byte index of the first '=' or ':' in `s`, or -1. INI has no quoting, so
// the first separator on the line splits key from value.
fn _find_separator(s: Str) -> Int {
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b == _INI_EQ || b == _INI_COLON {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Entry lookup / mutation helpers
// --------------------------------------------------

// Index of the (section, key) pair in the parallel vectors, or -1. Str
// comparisons go through str_compare (BUG 17: `==` on Str values read from
// Vec[Str] elements lowers to a pointer comparison).
fn _entry_index(i: &Ini, section: Str, key: Str) -> Int {
  var j = 0;
  while j < i.keys.len() {
    if compare.str_compare(i.sections[j], section) == 0 && compare.str_compare(i.keys[j], key) == 0 {
      return j;
    }
    j = j + 1;
  }
  return -1;
}

// Store one pair with last-wins semantics: an existing (section, key) keeps
// its position and gets the new value; a new pair is appended.
fn _set_pair(i: &mut Ini, section: Str, key: Str, value: Str) {
  let idx = _entry_index(i, section, key);
  if idx >= 0 {
    i.values[idx] = value;
    return;
  }
  i.sections.push(section);
  i.keys.push(key);
  i.values.push(value);
}

// Remove entry `idx` from the parallel vectors by shifting the tail left,
// then popping the trailing slots (there is no Vec.remove element method for
// library code in this compiler). The arrays stay compact.
fn _drop_entry(i: &mut Ini, idx: Int) {
  let n = i.keys.len();
  var j = idx;
  while j + 1 < n {
    i.sections[j] = i.sections[j + 1];
    i.keys[j] = i.keys[j + 1];
    i.values[j] = i.values[j + 1];
    j = j + 1;
  }
  i.sections.pop();
  i.keys.pop();
  i.values.pop();
}

// --------------------------------------------------
//  Emitting helpers
// --------------------------------------------------

// Append one "key = value" line for every entry of `section`, in entry
// order, separated by LF. Returns the number of lines appended.
fn _emit_group(out: &mut Vec[UInt8], i: &Ini, section: Str) -> Int {
  var count = 0;
  var j = 0;
  while j < i.keys.len() {
    if compare.str_compare(i.sections[j], section) == 0 {
      if count > 0 {
        out.push(_INI_LF);
      }
      let k: Str = i.keys[j];
      let v: Str = i.values[j];
      builder.sb_push_str(out, k);
      builder.sb_push_str(out, " = ");
      builder.sb_push_str(out, v);
      count = count + 1;
    }
    j = j + 1;
  }
  return count;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse one in-memory INI document.
/// Params: text - the whole file contents (LF or CRLF line endings).
/// Returns: Ok(Ini) for a valid document (including an empty one); Err with
/// an "ini: ..." message on a malformed section header, an empty key or a
/// non-blank, non-comment line without a '=' or ':' separator. Duplicate
/// (section, key) pairs are not an error: the last assignment wins and keeps
/// the first position.
/// Complexity: O(total input length * entry count) because duplicate
/// detection scans the entry list per assignment; O(total input length) with
/// a hash index.
pub fn ini_parse(text: Str) -> Result[Ini, Str] {
  var ini = Ini{ sections: Vec[Str].new(); keys: Vec[Str].new(); values: Vec[Str].new(); };
  var section = "";
  let len = text.len();
  var line_start = 0;
  var i = 0;
  while i <= len {
    if i == len || string.byte_at(text, i) == _INI_LF {
      var line = string.str_slice(text, line_start, i);
      let raw_len = line.len();
      if raw_len > 0 && string.byte_at(line, raw_len - 1) == _INI_CR {
        line = string.str_slice(line, 0, raw_len - 1);
      }
      let trimmed = string.str_trim(line);
      let n = trimmed.len();
      if n > 0 {
        let b0 = string.byte_at(trimmed, 0);
        if b0 != _INI_SEMI && b0 != _INI_HASH {
          if b0 == _INI_LBRACKET {
            if string.byte_at(trimmed, n - 1) != _INI_RBRACKET {
              return _err_ini("ini: malformed section header: " + trimmed);
            }
            let name = string.str_trim(string.str_slice(trimmed, 1, n - 1));
            if name.len() == 0 {
              return _err_ini("ini: empty section name: " + trimmed);
            }
            if string.str_contains(name, "[") || string.str_contains(name, "]") {
              return _err_ini("ini: malformed section header: " + trimmed);
            }
            section = name;
          } else {
            let sep = _find_separator(trimmed);
            if sep < 0 {
              return _err_ini("ini: expected '=' or ':' in line: " + trimmed);
            }
            let key = string.str_trim(string.str_slice(trimmed, 0, sep));
            if key.len() == 0 {
              return _err_ini("ini: empty key in line: " + trimmed);
            }
            let value = string.str_trim(string.str_slice(trimmed, sep + 1, n));
            _set_pair(&mut ini, section, key, value);
          }
        }
      }
      line_start = i + 1;
    }
    i = i + 1;
  }
  return _ok_ini(ini);
}

/// Value of the (section, key) pair; None when it is absent. Keys and
/// section names are byte-exact and case-sensitive. The empty section ("")
/// is the global/top-level area.
pub fn ini_get(i: &Ini, section: Str, key: Str) -> Option[Str] {
  let idx = _entry_index(i, section, key);
  if idx < 0 {
    return None;
  }
  let v: Str = i.values[idx];
  return Some(v);
}

/// True when the document contains the (section, key) pair.
pub fn ini_has(i: &Ini, section: Str, key: Str) -> Bool {
  return _entry_index(i, section, key) >= 0;
}

/// Keys of `section` in entry order (a fresh copy).
pub fn ini_keys(i: &Ini, section: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  var j = 0;
  while j < i.keys.len() {
    if compare.str_compare(i.sections[j], section) == 0 {
      let k: Str = i.keys[j];
      out.push(k);
    }
    j = j + 1;
  }
  return out;
}

/// Sections in first-seen order (a fresh copy). The empty global section
/// ("") appears only when it has at least one entry; a section that has lost
/// all its entries is absent.
pub fn ini_sections(i: &Ini) -> Vec[Str] {
  var out = Vec[Str].new();
  var j = 0;
  while j < i.sections.len() {
    let s: Str = i.sections[j];
    var seen = false;
    var k = 0;
    while k < out.len() {
      let o: Str = out[k];
      if compare.str_compare(o, s) == 0 {
        seen = true;
        break;
      }
      k = k + 1;
    }
    if !seen {
      out.push(s);
    }
    j = j + 1;
  }
  return out;
}

/// Set (section, key) to value: an existing pair is replaced in place (its
/// position is kept), a new pair is appended. Arguments are stored verbatim;
/// no validation is performed.
pub fn ini_set(i: &mut Ini, section: Str, key: Str, value: Str) {
  _set_pair(i, section, key, value);
}

/// Remove (section, key). Returns false when the pair is absent; on success
/// the three parallel vectors are compacted, so no gap remains.
pub fn ini_remove(i: &mut Ini, section: Str, key: Str) -> Bool {
  let idx = _entry_index(i, section, key);
  if idx < 0 {
    return false;
  }
  _drop_entry(i, idx);
  return true;
}

/// Emit one INI document from `i`.
/// Params: i - the document to serialize.
/// Returns: global entries first (no header), then each section of
/// `ini_sections` as "[name]" followed by its entries; exactly one blank
/// line separates two groups and "key = value" lines are LF-terminated with
/// no trailing LF. An empty document emits "". Values are written verbatim;
/// a value that carries leading/trailing whitespace or an embedded LF does
/// not survive a parse(emit(x)) round trip (see SPEC.md).
/// Error case: none.
/// Complexity: O(total output length * section count + entry count).
pub fn ini_emit(i: &Ini) -> Str {
  var out = Vec[UInt8].new();
  var wrote = _emit_group(&mut out, i, "");
  var secs = ini_sections(i);
  var s = 0;
  while s < secs.len() {
    let name: Str = secs[s];
    if name.len() > 0 {
      if wrote > 0 {
        out.push(_INI_LF);
        out.push(_INI_LF);
      }
      out.push(_INI_LBRACKET);
      builder.sb_push_str(&mut out, name);
      out.push(_INI_RBRACKET);
      out.push(_INI_LF);
      let count = _emit_group(&mut out, i, name);
      if count > 0 {
        wrote = wrote + 1;
      }
    }
    s = s + 1;
  }
  return builder.sb_to_str(&out);
}
