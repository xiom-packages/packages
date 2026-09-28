// XIOM -- xiom.config: in-memory configuration model
// Port task: promote the xiom.config placeholder to a real, tested, pure-XIOM
// package: sectioned key/value parsing, overlay merge, typed getters, schema
// validation and canonical rendering.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a configuration is two parallel Vec[Str] fields -- `keys` holds the
// normalized dotted keys in first-occurrence order; `values` holds the value
// text aligned by index. A duplicate key replaces its value in place, so the
// key keeps its first position and the last assignment wins. Vec[StructType]
// is unsupported in this compiler, so the entries are parallel vectors rather
// than a list of entry structs.
//
// Grammar (see SPEC.md for the full statement):
//   document    = *( line )                      ; LF, CRLF or lone CR lines
//   line        = ws* ( comment / section / pair ) [ ws* comment ]
//   comment     = ( "#" / ";" ) byte*
//   section     = "[" dotted-name "]"
//   pair        = key ws* "=" ws* value?
//   key         = dotted-name                    ; internal whitespace rejected
//   dotted-name = segment *( "." segment )       ; every segment non-empty
//   segment     = byte except ws, "=", "[", "]", "#", ";"
//   value       = byte*                          ; trimmed; a "#" or ";" after
//                                                ; a ws byte starts a comment;
//                                                ; a leading "#" is literal
//   ws          = SP | TAB
// Plain strings only: the format has no quotes and no escape sequences.
//
// v0.62.0 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Ok/Err for Result[...] are constructed only in the tiny leaf helpers
//     _cfg_ok/_cfg_err, _str_ok/_str_err, _int_ok/_int_err and
//     _bool_ok/_bool_err (constructing Results directly inside larger
//     functions miscompiles in this compiler).
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison); every comparison is routed through _streq.
//   * Every byte read is widened and masked ((b as Int) & 0xFF) by the _byte
//     helper before any comparison (byte comparisons at >= 128 miscompile).
//   * Rendering concatenates Str directly (no sb_to_str), so no NUL sentinel
//     can ever truncate the output; parse rejects NUL input up front.

module xiom.config

use xiom.string;
use xiom.convert;
use xiom.string.compare;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(c) for Result[Config, Str].
fn _cfg_ok(c: Config) -> Result[Config, Str] {
  return Ok(c);
}

// Err(m) for Result[Config, Str].
fn _cfg_err(m: Str) -> Result[Config, Str] {
  return Err(m);
}

// Ok(s) for Result[Str, Str].
fn _str_ok(s: Str) -> Result[Str, Str] {
  return Ok(s);
}

// Err(m) for Result[Str, Str].
fn _str_err(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _int_ok(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _int_err(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Bool, Str].
fn _bool_ok(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _bool_err(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants (widened Int values; see _byte)
// --------------------------------------------------

const _CFG_TAB: Int = 9;
const _CFG_LF: Int = 10;
const _CFG_CR: Int = 13;
const _CFG_SPACE: Int = 32;
const _CFG_HASH: Int = 35;
const _CFG_COMMA: Int = 44;
const _CFG_PLUS: Int = 43;
const _CFG_MINUS: Int = 45;
const _CFG_DOT: Int = 46;
const _CFG_ZERO: Int = 48;
const _CFG_NINE: Int = 57;
const _CFG_SEMI: Int = 59;
const _CFG_EQ: Int = 61;
const _CFG_LBRACKET: Int = 91;
const _CFG_RBRACKET: Int = 93;
const _CFG_NUL: Int = 0;
const _CFG_INT_MAX_DIV10: Int = 922337203685477580;
const _CFG_INT_MAX_LAST_DIGIT: Int = 7;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed configuration: `keys` and `values` are index-aligned parallel
/// vectors. Duplicate keys keep the position of their first occurrence and
/// the value of the last assignment.
pub type Config = {
  keys: Vec[Str];
  values: Vec[Str];
}

/// A validation schema: `keys` lists the dotted key names, `types` the
/// expected type names ("str", "int" or "bool"), `required` the required
/// flags as 1/0 and `allowed` comma-separated allowed values ("" = any).
/// All four vectors are index-aligned; build schemas with
/// config_schema_new/config_schema_add to keep them aligned.
pub type Schema = {
  keys: Vec[Str];
  types: Vec[Str];
  required: Vec[Int];
  allowed: Vec[Str];
}

// --------------------------------------------------
//  Byte and Str primitives
// --------------------------------------------------

// Widen and mask one byte of `s`. byte_at returns UInt8 and comparisons on
// bytes >= 128 miscompile unless widened to Int and masked first, so every
// byte read in this module goes through here.
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// Byte-exact Str equality through str_compare (BUG 17: `==` on Str values
// read from Vec[Str] elements lowers to a pointer comparison).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ASCII lowercase fold of a widened byte value: A-Z -> a-z, everything else
// unchanged. Only used for the case-insensitive boolean keywords.
fn _fold_ascii(c: Int) -> Int {
  if c >= 65 && c <= 90 {
    return c + 32;
  }
  return c;
}

// Case-insensitive (ASCII) Str equality.
fn _streq_ci(a: Str, b: Str) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let ca = _fold_ascii(_byte(a, i));
    let cb = _fold_ascii(_byte(b, i));
    if ca != cb {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True for an ASCII space or horizontal tab (the only intra-line whitespace).
fn _is_ws(c: Int) -> Bool {
  return c == _CFG_SPACE || c == _CFG_TAB;
}

// True when `s` contains a NUL byte. Parse rejects such input so no rendered
// value can ever carry a NUL sentinel.
fn _has_nul(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if _byte(s, i) == _CFG_NUL {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Left-trim ASCII space/tab.
fn _ltrim_ws(s: Str) -> Str {
  var i = 0;
  while i < s.len() && _is_ws(_byte(s, i)) {
    i = i + 1;
  }
  if i == 0 {
    return s;
  }
  return string.str_slice(s, i, s.len());
}

// Right-trim ASCII space/tab.
fn _rtrim_ws(s: Str) -> Str {
  var n = s.len();
  while n > 0 && _is_ws(_byte(s, n - 1)) {
    n = n - 1;
  }
  if n == s.len() {
    return s;
  }
  return string.str_slice(s, 0, n);
}

// Trim ASCII space/tab from both ends.
fn _trim_ws(s: Str) -> Str {
  return _rtrim_ws(_ltrim_ws(s));
}

// Split `text` into lines. LF, CRLF and a lone CR each terminate a line; a
// final line without a terminator is still returned, and a trailing
// terminator does not produce an extra empty line.
fn _split_lines(text: Str) -> Vec[Str] {
  var lines = Vec[Str].new();
  let n = text.len();
  var start = 0;
  var i = 0;
  while i < n {
    let b = _byte(text, i);
    if b == _CFG_LF || b == _CFG_CR {
      lines.push(string.str_slice(text, start, i));
      if b == _CFG_CR && i + 1 < n && _byte(text, i + 1) == _CFG_LF {
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

// --------------------------------------------------
//  Key, section and value helpers
// --------------------------------------------------

// True when `k` is a valid dotted name: one or more non-empty segments of
// bytes above 32 that are not '=', '[', ']', '#' or ';'. Sections and keys
// share this rule.
fn _dotted_ok(k: Str) -> Bool {
  let n = k.len();
  if n == 0 {
    return false;
  }
  var prev_dot = true;
  var i = 0;
  while i < n {
    let c = _byte(k, i);
    if c == _CFG_DOT {
      if prev_dot {
        return false;
      }
      prev_dot = true;
    } else {
      if c <= _CFG_SPACE {
        return false;
      }
      if c == _CFG_EQ || c == _CFG_LBRACKET || c == _CFG_RBRACKET {
        return false;
      }
      if c == _CFG_HASH || c == _CFG_SEMI {
        return false;
      }
      prev_dot = false;
    }
    i = i + 1;
  }
  if prev_dot {
    return false;
  }
  return true;
}

// Index of the first '=' in `line`, or -1.
fn _find_eq(line: Str) -> Int {
  var i = 0;
  while i < line.len() {
    if _byte(line, i) == _CFG_EQ {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Cut a trailing comment from a trimmed value span: a '#' or ';' preceded by
// an ASCII space/tab starts a comment. A '#' or ';' as the first byte of the
// span is literal (so "color = #ff0000" keeps its value).
fn _cut_value_comment(v: Str) -> Str {
  var i = 1;
  while i < v.len() {
    let c = _byte(v, i);
    if (c == _CFG_HASH || c == _CFG_SEMI) && _is_ws(_byte(v, i - 1)) {
      return _rtrim_ws(string.str_slice(v, 0, i));
    }
    i = i + 1;
  }
  return v;
}

// Parse one section header line (already trimmed, starts with '[').
// Returns the (possibly dotted) section name. The text after ']' must be
// blank or a comment.
fn _parse_section(line: Str) -> Result[Str, Str] {
  let n = line.len();
  var close = -1;
  var i = 1;
  while i < n {
    if _byte(line, i) == _CFG_RBRACKET {
      close = i;
      break;
    }
    i = i + 1;
  }
  if close < 0 {
    return _str_err("config: malformed section header in line: " + line);
  }
  let inner = _trim_ws(string.str_slice(line, 1, close));
  if inner.len() == 0 {
    return _str_err("config: empty section header in line: " + line);
  }
  if !_dotted_ok(inner) {
    return _str_err("config: malformed section header in line: " + line);
  }
  let rest = _trim_ws(string.str_slice(line, close + 1, n));
  if rest.len() > 0 {
    let rc = _byte(rest, 0);
    if rc != _CFG_HASH && rc != _CFG_SEMI {
      return _str_err("config: unexpected text after section header in line: " + line);
    }
  }
  return _str_ok(inner);
}

// --------------------------------------------------
//  Config mutation helpers
// --------------------------------------------------

// Index of `key` in c.keys, or -1. Str comparisons go through str_compare.
fn _key_index(c: &Config, key: Str) -> Int {
  var i = 0;
  while i < c.keys.len() {
    let k: Str = c.keys[i];
    if compare.str_compare(k, key) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Store one pair with last-wins semantics: an existing key is replaced in
// place (keeping its first position), a new key is appended. The parallel
// vectors are always pushed together here.
fn _set_pair(c: &mut Config, key: Str, value: Str) {
  let i = _key_index(c, key);
  if i >= 0 {
    c.values[i] = value;
    return;
  }
  c.keys.push(key);
  c.values.push(value);
}

// Deep copy of `c` (keys and values in order).
fn _copy_config(c: &Config) -> Config {
  var out = Config{ keys: Vec[Str].new(); values: Vec[Str].new(); };
  var i = 0;
  while i < c.keys.len() {
    let k: Str = c.keys[i];
    let v: Str = c.values[i];
    out.keys.push(k);
    out.values.push(v);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Constructors
// --------------------------------------------------

/// An empty configuration (no entries).
pub fn config_new() -> Config {
  return Config{ keys: Vec[Str].new(); values: Vec[Str].new(); };
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

/// Parse one in-memory configuration document.
/// Params: text - the whole document (LF, CRLF or lone CR line endings).
/// Returns: Ok(Config) for a valid document (including an empty one); Err
/// with a "config: ..." message on the first malformed line or on a NUL
/// byte in the input. `[section]` headers prefix every following plain key
/// with `section.`; a dotted key is stored as written; duplicate keys are
/// not an error (last assignment wins, first position kept).
/// Examples: "[server]\nport = 8080\n" -> key "server.port" with value
/// "8080"; "color = #ff0000 # note" -> value "#ff0000".
/// Error case: see SPEC.md section 5 for the full catalog.
/// Complexity: O(total input length * key count) because duplicate
/// detection scans the key list per pair; O(total input length) with a
/// hash index.
pub fn config_parse(text: Str) -> Result[Config, Str] {
  if _has_nul(text) {
    return _cfg_err("config: NUL byte in input");
  }
  var cfg = Config{ keys: Vec[Str].new(); values: Vec[Str].new(); };
  var section = "";
  let lines = _split_lines(text);
  let n = lines.len();
  var li = 0;
  while li < n {
    let raw: Str = lines[li];
    let line = _trim_ws(raw);
    if line.len() == 0 {
      li = li + 1;
      continue;
    }
    let first = _byte(line, 0);
    if first == _CFG_HASH || first == _CFG_SEMI {
      li = li + 1;
      continue;
    }
    if first == _CFG_LBRACKET {
      let sr = _parse_section(line);
      match sr {
        Ok(name) => { section = name; },
        Err(e) => { return _cfg_err(e); },
      }
      li = li + 1;
      continue;
    }
    let eq = _find_eq(line);
    if eq < 0 {
      return _cfg_err("config: expected '=' in line: " + line);
    }
    let raw_key = _trim_ws(string.str_slice(line, 0, eq));
    if raw_key.len() == 0 {
      return _cfg_err("config: missing key in line: " + line);
    }
    if !_dotted_ok(raw_key) {
      return _cfg_err("config: malformed key in line: " + line);
    }
    let raw_value = _cut_value_comment(_trim_ws(string.str_slice(line, eq + 1, line.len())));
    var key = raw_key;
    if section.len() > 0 {
      key = section + "." + raw_key;
    }
    _set_pair(&mut cfg, key, raw_value);
    li = li + 1;
  }
  return _cfg_ok(cfg);
}

// --------------------------------------------------
//  Lookup and enumeration
// --------------------------------------------------

/// Value of `key`; None when the key is absent. Keys are byte-exact,
/// case-sensitive dotted names ("server.port").
pub fn config_get(c: &Config, key: Str) -> Option[Str] {
  let i = _key_index(c, key);
  if i < 0 {
    return None;
  }
  let v: Str = c.values[i];
  return Some(v);
}

/// True when the configuration contains `key`.
pub fn config_has(c: &Config, key: Str) -> Bool {
  return _key_index(c, key) >= 0;
}

/// Number of entries.
pub fn config_len(c: &Config) -> Int {
  return c.keys.len();
}

/// Keys in first-occurrence order (a fresh copy).
pub fn config_keys(c: &Config) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < c.keys.len() {
    let k: Str = c.keys[i];
    out.push(k);
    i = i + 1;
  }
  return out;
}

/// Values in key order (a fresh copy).
pub fn config_values(c: &Config) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < c.values.len() {
    let v: Str = c.values[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

/// All entries as index-aligned parallel vectors: (keys, values). Both
/// vectors are fresh copies; mutating them does not change the config.
pub fn config_entries(c: &Config) -> (Vec[Str], Vec[Str]) {
  var ks = Vec[Str].new();
  var vs = Vec[Str].new();
  var i = 0;
  while i < c.keys.len() {
    let k: Str = c.keys[i];
    let v: Str = c.values[i];
    ks.push(k);
    vs.push(v);
    i = i + 1;
  }
  return (ks, vs);
}

// --------------------------------------------------
//  Merge and set
// --------------------------------------------------

/// Merge two sources with later-source-wins precedence: every overlay entry
/// replaces the value of the same key in the base (keeping the base
/// position); overlay-only keys append in overlay order. Neither input is
/// modified. Resolve the full precedence chain defaults <- file <-
/// overrides by merging in that order, e.g. config_merge(&file_overrides,
/// ...) or the convenience config_resolve.
pub fn config_merge(base: &Config, overlay: &Config) -> Config {
  var out = _copy_config(base);
  var j = 0;
  while j < overlay.keys.len() {
    let k: Str = overlay.keys[j];
    let v: Str = overlay.values[j];
    _set_pair(&mut out, k, v);
    j = j + 1;
  }
  return out;
}

/// Resolve a three-source precedence chain: defaults <- file <- overrides.
/// Equivalent to config_merge(&config_merge(defaults, file), overrides).
pub fn config_resolve(defaults: &Config, file: &Config, overrides: &Config) -> Config {
  let merged = config_merge(defaults, file);
  return config_merge(&merged, overrides);
}

/// Set `key` to `value` in a new Config: an existing key is replaced in
/// place (its position is kept), a new key is appended. `c` itself is
/// untouched. The key is used exactly as given (no section prefixing or
/// validation); pass a normalized dotted key.
pub fn config_set(c: &Config, key: Str, value: Str) -> Config {
  var out = _copy_config(c);
  _set_pair(&mut out, key, value);
  return out;
}

// --------------------------------------------------
//  Typed getters
// --------------------------------------------------

/// Parse the text of one setting as a signed decimal integer.
/// Grammar: an optional leading '+' or '-' followed by one or more ASCII
/// digits. The accepted range is -9223372036854775807..=9223372036854775807;
/// the two's-complement minimum is rejected because its magnitude is not
/// representable in a signed 64-bit Int (same choice as xiom.l10n.number).
fn _parse_int_value(key: Str, v: Str) -> Result[Int, Str] {
  let n = v.len();
  if n == 0 {
    return _int_err("config: invalid integer for key " + key + ": " + v);
  }
  var neg = false;
  var i = 0;
  let first = _byte(v, 0);
  if first == _CFG_MINUS {
    neg = true;
    i = 1;
  } elif first == _CFG_PLUS {
    i = 1;
  }
  if i >= n {
    return _int_err("config: invalid integer for key " + key + ": " + v);
  }
  var mag: Int = 0;
  while i < n {
    let c = _byte(v, i);
    if c < _CFG_ZERO || c > _CFG_NINE {
      return _int_err("config: invalid integer for key " + key + ": " + v);
    }
    let d = c - _CFG_ZERO;
    if mag > _CFG_INT_MAX_DIV10 {
      return _int_err("config: integer out of range for key " + key + ": " + v);
    }
    if mag == _CFG_INT_MAX_DIV10 && d > _CFG_INT_MAX_LAST_DIGIT {
      return _int_err("config: integer out of range for key " + key + ": " + v);
    }
    mag = mag * 10 + d;
    i = i + 1;
  }
  if neg {
    return _int_ok(0 - mag);
  }
  return _int_ok(mag);
}

// Parse the text of one setting as a boolean, ASCII case-insensitively:
// true/false, yes/no and 1/0.
fn _parse_bool_value(key: Str, v: Str) -> Result[Bool, Str] {
  if _streq_ci(v, "true") || _streq_ci(v, "yes") || _streq_ci(v, "1") {
    return _bool_ok(true);
  }
  if _streq_ci(v, "false") || _streq_ci(v, "no") || _streq_ci(v, "0") {
    return _bool_ok(false);
  }
  return _bool_err("config: invalid boolean for key " + key + ": " + v);
}

// Integer value of `v`, or `default` when absent or malformed.
fn _int_or_default(key: Str, v: Str, default: Int) -> Int {
  let r = _parse_int_value(key, v);
  match r {
    Ok(nv) => { return nv; },
    Err(_) => { return default; },
  }
  return default;
}

// Boolean value of `v`, or `default` when absent or malformed.
fn _bool_or_default(key: Str, v: Str, default: Bool) -> Bool {
  let r = _parse_bool_value(key, v);
  match r {
    Ok(bv) => { return bv; },
    Err(_) => { return default; },
  }
  return default;
}

/// String value of `key`, or `default` when the key is absent. An empty
/// stored value is returned as "".
pub fn config_get_str(c: &Config, key: Str, default: Str) -> Str {
  let o = config_get(c, key);
  match o {
    Some(v) => { return v; },
    None => { return default; },
  }
  return default;
}

/// String value of `key` as Result: Ok(value) when present,
/// Err("config: missing key: <key>") when absent.
pub fn config_try_str(c: &Config, key: Str) -> Result[Str, Str] {
  let o = config_get(c, key);
  match o {
    Some(v) => { return _str_ok(v); },
    None => { return _str_err("config: missing key: " + key); },
  }
  return _str_err("config: missing key: " + key);
}

/// Integer value of `key`, or `default` when the key is absent or its value
/// is not a valid signed decimal integer (see config_try_int for errors).
pub fn config_get_int(c: &Config, key: Str, default: Int) -> Int {
  let o = config_get(c, key);
  match o {
    Some(v) => { return _int_or_default(key, v, default); },
    None => { return default; },
  }
  return default;
}

/// Boolean value of `key`, or `default` when the key is absent or its value
/// is not true/false, yes/no or 1/0 (ASCII case-insensitive).
pub fn config_get_bool(c: &Config, key: Str, default: Bool) -> Bool {
  let o = config_get(c, key);
  match o {
    Some(v) => { return _bool_or_default(key, v, default); },
    None => { return default; },
  }
  return default;
}

/// Integer value of `key` as Result. Err messages: "config: missing key:
/// <key>", "config: invalid integer for key <key>: <value>" and "config:
/// integer out of range for key <key>: <value>".
pub fn config_try_int(c: &Config, key: Str) -> Result[Int, Str] {
  let o = config_get(c, key);
  match o {
    Some(v) => { return _parse_int_value(key, v); },
    None => { return _int_err("config: missing key: " + key); },
  }
  return _int_err("config: missing key: " + key);
}

/// Boolean value of `key` as Result. Err messages: "config: missing key:
/// <key>" and "config: invalid boolean for key <key>: <value>".
pub fn config_try_bool(c: &Config, key: Str) -> Result[Bool, Str] {
  let o = config_get(c, key);
  match o {
    Some(v) => { return _parse_bool_value(key, v); },
    None => { return _bool_err("config: missing key: " + key); },
  }
  return _bool_err("config: missing key: " + key);
}

// --------------------------------------------------
//  Schema validation
// --------------------------------------------------

/// An empty validation schema.
pub fn config_schema_new() -> Schema {
  return Schema{ keys: Vec[Str].new(); types: Vec[Str].new(); required: Vec[Int].new(); allowed: Vec[Str].new(); };
}

/// Append one schema row in a new Schema: `key` must have the given `typ`
/// ("str", "int" or "bool"), must be present when `required` is true, and
/// when `allowed` is non-empty its value must be one of the comma-separated
/// tokens listed there. `s` itself is untouched.
pub fn config_schema_add(s: &Schema, key: Str, typ: Str, required: Bool, allowed: Str) -> Schema {
  var out = Schema{ keys: Vec[Str].new(); types: Vec[Str].new(); required: Vec[Int].new(); allowed: Vec[Str].new(); };
  var i = 0;
  while i < s.keys.len() {
    let k: Str = s.keys[i];
    let t: Str = s.types[i];
    let r: Int = s.required[i];
    let a: Str = s.allowed[i];
    out.keys.push(k);
    out.types.push(t);
    out.required.push(r);
    out.allowed.push(a);
    i = i + 1;
  }
  var req: Int = 0;
  if required {
    req = 1;
  }
  out.keys.push(key);
  out.types.push(typ);
  out.required.push(req);
  out.allowed.push(allowed);
  return out;
}

// True for the three known type names.
fn _known_type(t: Str) -> Bool {
  if _streq(t, "str") {
    return true;
  }
  if _streq(t, "int") {
    return true;
  }
  return _streq(t, "bool");
}

// True when `v` equals one of the comma-separated tokens of `list` (each
// token is trimmed; comparison is byte-exact).
fn _in_list(list: Str, v: Str) -> Bool {
  let n = list.len();
  var i = 0;
  while i <= n {
    var j = i;
    while j < n && _byte(list, j) != _CFG_COMMA {
      j = j + 1;
    }
    let tok = _trim_ws(string.str_slice(list, i, j));
    if _streq(tok, v) {
      return true;
    }
    if j >= n {
      return false;
    }
    i = j + 1;
  }
  return false;
}

// The allowed-value error message for one value, or "" when the value is
// allowed (or the list is empty).
fn _allowed_error(key: Str, allow: Str, v: Str) -> Str {
  if allow.len() == 0 {
    return "";
  }
  if _in_list(allow, v) {
    return "";
  }
  return "config: value not allowed for key " + key + ": " + v;
}

// Validate one present value against its type and allowed list, pushing
// every error found onto `errs`.
fn _validate_value(errs: &mut Vec[Str], key: Str, typ: Str, allow: Str, v: Str) {
  if _streq(typ, "str") {
    let msg = _allowed_error(key, allow, v);
    if msg.len() > 0 {
      errs.push(msg);
    }
    return;
  }
  if _streq(typ, "int") {
    let r = _parse_int_value(key, v);
    match r {
      Ok(_) => {
        let msg = _allowed_error(key, allow, v);
        if msg.len() > 0 {
          errs.push(msg);
        }
      },
      Err(e) => { errs.push(e); },
    }
    return;
  }
  let r = _parse_bool_value(key, v);
  match r {
    Ok(_) => {
      let msg = _allowed_error(key, allow, v);
      if msg.len() > 0 {
        errs.push(msg);
      }
    },
    Err(e) => { errs.push(e); },
  }
  return;
}

/// Validate `c` against `s`, returning ALL errors (not just the first) in
/// schema order; an empty vector means valid. Checks per row: unknown type
/// name, missing required key, value not matching its type, value not in
/// the allowed list. Absent optional keys are fine; config keys not listed
/// in the schema are ignored (validation is schema-closed).
/// If the schema's parallel vectors are not aligned, a "config: schema
/// vectors are not aligned at index <i>" error is appended and validation
/// stops there.
pub fn config_validate(c: &Config, s: &Schema) -> Vec[Str] {
  var errs = Vec[Str].new();
  let n = s.keys.len();
  var i = 0;
  while i < n {
    if i >= s.types.len() || i >= s.required.len() || i >= s.allowed.len() {
      errs.push("config: schema vectors are not aligned at index " + convert.int_to_string(i));
      return errs;
    }
    let key: Str = s.keys[i];
    let typ: Str = s.types[i];
    let req: Int = s.required[i];
    let allow: Str = s.allowed[i];
    if !_known_type(typ) {
      errs.push("config: unknown schema type for key " + key + ": " + typ);
      i = i + 1;
      continue;
    }
    let has = config_has(c, key);
    if req != 0 && !has {
      errs.push("config: missing required key: " + key);
      i = i + 1;
      continue;
    }
    if !has {
      i = i + 1;
      continue;
    }
    let o = config_get(c, key);
    match o {
      Some(v) => { _validate_value(&mut errs, key, typ, allow, v); },
      None => {},
    }
    i = i + 1;
  }
  return errs;
}

/// True when config_validate finds no error.
pub fn config_valid(c: &Config, s: &Schema) -> Bool {
  let errs = config_validate(c, s);
  return errs.len() == 0;
}

// --------------------------------------------------
//  Rendering
// --------------------------------------------------

/// Render a configuration back to canonical text: one `key = value` line
/// per entry, in insertion (first-occurrence) order, LF separated with no
/// trailing LF. Sections are NOT reconstructed -- normalized dotted keys
/// are written as-is, so parse -> render -> parse is stable for any parsed
/// document. Values are written verbatim (no quoting exists in the
/// format); an empty config renders as "".
/// Round-trip caveat: a value that contains a space/tab immediately
/// followed by '#' or ';', a leading/trailing space/tab, or a line break
/// cannot be represented (parse never produces those; config_set callers
/// must keep values to the grammar).
/// Complexity: O(total output length) amortized for config-sized inputs.
pub fn config_render(c: &Config) -> Str {
  var out = "";
  var i = 0;
  while i < c.keys.len() {
    if i > 0 {
      out = out + "\n";
    }
    let k: Str = c.keys[i];
    let v: Str = c.values[i];
    out = out + k + " = " + v;
    i = i + 1;
  }
  return out;
}
