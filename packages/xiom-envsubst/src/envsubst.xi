// XIOM -- xiom.envsubst: shell-style ${VAR} expansion
// Greenfield package: pure XIOM, no FFI, no environment access. Every variable
// table is supplied by the caller (parallel name/value vectors or "NAME=VALUE"
// pair strings), so expansion is deterministic and fully testable.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model (full grammar, semantics and error catalog in SPEC.md):
//   * "${NAME}" substitutes the value of NAME. NAME = [A-Za-z_][A-Za-z0-9_]*;
//     lookups are byte-exact and case-sensitive. The first duplicate name in
//     the table wins, and a name whose parallel value is missing is treated
//     as undefined.
//   * A missing name is Err("envsubst: undefined variable: NAME") when
//     `missing_empty` is false, and expands to "" when it is true. A name
//     that is present with the empty value expands to "" in both modes.
//   * "$$" expands to a literal "$".
//   * "${" with no "}" after it is always
//     Err("envsubst: unterminated variable reference"), even in lenient mode.
//   * "${<content>}" whose content is not a valid NAME is always
//     Err("envsubst: invalid variable name"), even in lenient mode. The
//     content is everything up to the first "}", so the nested-looking
//     "${A${B}}" has content "A${B" and fails validation.
//   * Every other byte is copied literally: a "{" not preceded by "$", a
//     lone "$", and any text after a reference (including an extra "}").
//   * Expansion is a single left-to-right pass: substituted values are copied
//     into the output as-is and are never re-scanned, so a value containing
//     "${X}" is emitted literally.
//   * envsubst_names reports referenced names in first-seen order; malformed
//     or invalid references are skipped and an unterminated "${" stops the
//     scan (names seen before it are still reported).
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Ok/Err for Result[Str, Str] are constructed only in the tiny leaf
//     helpers _ok_str/_err_str (constructing Results directly inside other
//     functions miscompiles in this compiler).
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison).
//   * Bytes are read as (string.byte_at(s, i) as Int) & 0xFF and compared in
//     the Int domain; output is collected in a xiom.string.builder buffer
//     (one allocation per expanded Str).

module xiom.envsubst

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants and low-level helpers
// --------------------------------------------------

const _ENVSUBST_DOLLAR: Int = 36;     // $
const _ENVSUBST_LBRACE: Int = 123;    // {
const _ENVSUBST_RBRACE: Int = 125;    // }
const _ENVSUBST_EQ: Int = 61;         // =

// One byte of `s` at `i`, zero-extended to Int (0..255).
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// Index of the first "}" at or after `start`, or -1 when there is none.
fn _find_close(s: Str, start: Int) -> Int {
  var i = start;
  while i < s.len() {
    if _byte(s, i) == _ENVSUBST_RBRACE {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the first "=" in `s`, or -1.
fn _find_eq(s: Str) -> Int {
  var i = 0;
  while i < s.len() {
    if _byte(s, i) == _ENVSUBST_EQ {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True for a NAME start byte: A-Z a-z _.
fn _is_name_start(c: Int) -> Bool {
  if c >= 65 && c <= 90 {
    return true;
  }
  if c >= 97 && c <= 122 {
    return true;
  }
  return c == 95;
}

// True for a NAME continuation byte: A-Z a-z 0-9 _.
fn _is_name_char(c: Int) -> Bool {
  if _is_name_start(c) {
    return true;
  }
  return c >= 48 && c <= 57;
}

// True when `s` matches [A-Za-z_][A-Za-z0-9_]* exactly (so "" is invalid).
fn _is_valid_name(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  if !_is_name_start(_byte(s, 0)) {
    return false;
  }
  var i = 1;
  while i < n {
    if !_is_name_char(_byte(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Index of the first entry in `names` that equals `name` and also has a
// parallel value, or -1. Duplicates resolve to the first match; a name whose
// value is missing (names longer than values) does not match.
fn _lookup(names: &Vec[Str], values: &Vec[Str], name: Str) -> Int {
  var lim = names.len();
  if values.len() < lim {
    lim = values.len();
  }
  var i = 0;
  while i < lim {
    let n: Str = names[i];
    if compare.str_compare(n, name) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when `items` holds `name` (comparison via str_compare, never `==`).
fn _contains(items: &Vec[Str], name: Str) -> Bool {
  var i = 0;
  while i < items.len() {
    let item: Str = items[i];
    if compare.str_compare(item, name) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  Expansion
// --------------------------------------------------

// Shared single-pass expander. See the module header for the full byte-level
// rules; `missing_empty` only decides what an undefined NAME yields.
fn _expand(text: Str, names: &Vec[Str], values: &Vec[Str], missing_empty: Bool) -> Result[Str, Str] {
  var sb = builder.sb_new();
  let len = text.len();
  var i = 0;
  while i < len {
    let b = _byte(text, i);
    if b == _ENVSUBST_DOLLAR && i + 1 < len && _byte(text, i + 1) == _ENVSUBST_DOLLAR {
      builder.sb_push_byte(&mut sb, _ENVSUBST_DOLLAR as UInt8);
      i = i + 2;
    } elif b == _ENVSUBST_DOLLAR && i + 1 < len && _byte(text, i + 1) == _ENVSUBST_LBRACE {
      let close = _find_close(text, i + 2);
      if close < 0 {
        return _err_str("envsubst: unterminated variable reference");
      }
      let name = string.str_slice(text, i + 2, close);
      if !_is_valid_name(name) {
        return _err_str("envsubst: invalid variable name");
      }
      let idx = _lookup(names, values, name);
      if idx >= 0 {
        let v: Str = values[idx];
        builder.sb_push_str(&mut sb, v);
      } elif !missing_empty {
        return _err_str("envsubst: undefined variable: " + name);
      }
      i = close + 1;
    } else {
      builder.sb_push_byte(&mut sb, b as UInt8);
      i = i + 1;
    }
  }
  return _ok_str(builder.sb_to_str(&sb));
}

/// Expand every "${NAME}" in `text` from the parallel `names`/`values` table.
/// Params: text - the input text; names, values - index-aligned vectors (the
/// first entry whose name matches wins; entries without a parallel value do
/// not match); missing_empty - false => an undefined NAME is an Err, true =>
/// it expands to "".
/// Returns: Ok(expanded text). "$$" expands to a literal "$"; a "{" not
/// preceded by "$" and a lone "$" are literal; substituted values are copied
/// verbatim and never re-scanned (single pass); text after a "}" is literal.
/// Error case: Err("envsubst: undefined variable: <NAME>") for an undefined
/// name when missing_empty is false; Err("envsubst: unterminated variable
/// reference") for a "${" with no closing "}"; Err("envsubst: invalid
/// variable name") when the brace content is not [A-Za-z_][A-Za-z0-9_]*.
/// The last two errors are raised in both modes.
/// Complexity: O(input length + references * table length).
pub fn envsubst_expand(text: Str, names: &Vec[Str], values: &Vec[Str], missing_empty: Bool) -> Result[Str, Str] {
  return _expand(text, names, values, missing_empty);
}

/// Expand `text` from "NAME=VALUE" entries.
/// Params: text - the input text; pairs - entries split at the first "="; an
/// entry with no "=" or with an empty name part is skipped (malformed pairs
/// are ignored, not an error); missing_empty - as in envsubst_expand.
/// Returns: Ok(expanded text) with the same semantics as envsubst_expand. The
/// key part is stored verbatim (only exact lookups can reach it), the value
/// part may itself contain "="; the first pair for a repeated name wins.
/// Error case: same as envsubst_expand.
/// Complexity: O(text + pair bytes + references * table length).
pub fn envsubst_expand_pairs(text: Str, pairs: &Vec[Str], missing_empty: Bool) -> Result[Str, Str] {
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  var i = 0;
  while i < pairs.len() {
    let p: Str = pairs[i];
    let eq = _find_eq(p);
    if eq > 0 {
      names.push(string.str_slice(p, 0, eq));
      values.push(string.str_slice(p, eq + 1, p.len()));
    }
    i = i + 1;
  }
  return _expand(text, &names, &values, missing_empty);
}

// --------------------------------------------------
//  Inspection
// --------------------------------------------------

/// True when `text` contains the byte pair "${" (so envsubst_expand has a
/// reference candidate to look at).
/// Params: text - the input text.
/// Returns: true at the first "$" immediately followed by "{".
/// This is a cheap raw scan, not a validator: it also reports true for "${"
/// without a closing "}", for an invalid name such as "${1}", and for the
/// literal "$${" sequence that envsubst_expand duplicates into "${".
/// Error case: none.
/// Complexity: O(input length).
pub fn envsubst_has_vars(text: Str) -> Bool {
  let len = text.len();
  var i = 0;
  while i + 1 < len {
    if _byte(text, i) == _ENVSUBST_DOLLAR && _byte(text, i + 1) == _ENVSUBST_LBRACE {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Distinct referenced names in `text`, first-seen order. "$" followed by "$"
// is skipped as a literal; a "${" with no closing "}" stops the scan; invalid
// brace content is skipped.
fn _collect_names(text: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let len = text.len();
  var i = 0;
  while i < len {
    let b = _byte(text, i);
    if b == _ENVSUBST_DOLLAR && i + 1 < len && _byte(text, i + 1) == _ENVSUBST_DOLLAR {
      i = i + 2;
    } elif b == _ENVSUBST_DOLLAR && i + 1 < len && _byte(text, i + 1) == _ENVSUBST_LBRACE {
      let close = _find_close(text, i + 2);
      if close < 0 {
        return out;
      }
      let name = string.str_slice(text, i + 2, close);
      if _is_valid_name(name) && !_contains(&out, name) {
        out.push(name);
      }
      i = close + 1;
    } else {
      i = i + 1;
    }
  }
  return out;
}

/// Distinct variable names referenced by `text`, first-seen order.
/// Params: text - the input text.
/// Returns: valid "${NAME}" names with duplicates removed; "$$" is a literal
/// and contributes nothing; invalid brace content (for example "${}" or
/// "${A-B}") is skipped; an unterminated "${" stops the scan, so names seen
/// before it are still reported.
/// Error case: none.
/// Complexity: O(input length * distinct names).
pub fn envsubst_names(text: Str) -> Vec[Str] {
  return _collect_names(text);
}
