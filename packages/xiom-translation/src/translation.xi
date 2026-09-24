// XIOM -- xiom.translation: message catalogs with locale fallback and
// {name} placeholder interpolation
// Greenfield package: pure XIOM, no FFI, no file I/O (in-memory Str only).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: one catalog is three parallel vectors. Entry i is the triple
// (locales[i], keys[i], values[i]); a (locale, key) pair is unique because
// every write replaces in place, so a catalog is a sparse locale x key grid.
// Vec[StructType] is unsupported in this compiler, so the catalog is
// deliberately flat (three Vec[Str]) instead of a list of entry structs.
//
// Grammar (full statement in SPEC.md):
//   document  = *( line )                     ; LF or CRLF terminated
//   line      = ws* ( comment / pair )?       ; blank lines are ignored
//   comment   = ( ";" / "#" ) *byte           ; only as the first non-ws byte
//   pair      = key sep value?                ; value may be empty
//   sep       = "=" / ":"                     ; first occurrence wins
//   key       = non-empty text before sep, trimmed; dots/dashes are ordinary
//   value     = text after sep, trimmed; may contain '=', ':' and braces
// Malformed lines are Err("translation: ...") including the offending line.
//
// Fallback chain for catalog_translate: locale -> fallback -> the key itself.
// The resolved text is then scanned once, left to right: "{name}" is replaced
// by the first matching name from the parallel names/values vectors; an
// unknown name renders empty; a "{" with no later "}" is literal; "{{" is
// NOT special (the placeholder name starts with "{"); substituted text is
// never re-scanned.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Ok/Err for Result[Catalog, Str] are constructed only in the tiny leaf
//     helpers _ok_catalog/_err_catalog (constructing Results directly inside
//     other functions miscompiles in this compiler).
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison).
//   * Bytes are read as (string.byte_at(s, i) as Int) & 0xFF and compared in
//     the Int domain; output is collected in a xiom.string.builder buffer.

module xiom.translation

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(c) for Result[Catalog, Str].
fn _ok_catalog(c: Catalog) -> Result[Catalog, Str] {
  return Ok(c);
}

// Err(m) for Result[Catalog, Str].
fn _err_catalog(m: Str) -> Result[Catalog, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _TRANSL_LF: Int = 10;      // \n
const _TRANSL_CR: Int = 13;      // \r
const _TRANSL_HASH: Int = 35;    // #
const _TRANSL_COLON: Int = 58;   // :
const _TRANSL_SEMI: Int = 59;    // ;
const _TRANSL_EQ: Int = 61;      // =
const _TRANSL_LBRACE: Int = 123; // {
const _TRANSL_RBRACE: Int = 125; // }

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A message catalog: `locales`, `keys` and `values` are index-aligned.
/// Entry i is the translation of `keys[i]` in `locales[i]` with text
/// `values[i]`. A (locale, key) pair is written at most once; replacing a
/// value keeps the position of the first insertion.
pub type Catalog = {
  locales: Vec[Str];
  keys: Vec[Str];
  values: Vec[Str];
}

// --------------------------------------------------
//  Low-level helpers
// --------------------------------------------------

// One byte of `s` at `i`, zero-extended to Int (0..255).
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True when `items` holds `s`; comparison uses str_compare, never `==`
// (BUG 17).
fn _contains(items: &Vec[Str], s: Str) -> Bool {
  var i = 0;
  while i < items.len() {
    let item: Str = items[i];
    if compare.str_compare(item, s) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

// Number of usable entries: the three parallel vectors are only safe up to
// the shortest one (a hand-built catalog may be ragged).
fn _entry_limit(c: &Catalog) -> Int {
  var lim = c.locales.len();
  if c.keys.len() < lim {
    lim = c.keys.len();
  }
  if c.values.len() < lim {
    lim = c.values.len();
  }
  return lim;
}

// Index of the entry for (locale, key), or -1. The first match wins for a
// hand-built catalog that repeats a pair; Str comparisons go through
// str_compare (BUG 17).
fn _entry_index(c: &Catalog, locale: Str, key: Str) -> Int {
  let lim = _entry_limit(c);
  var i = 0;
  while i < lim {
    let l: Str = c.locales[i];
    if compare.str_compare(l, locale) == 0 {
      let k: Str = c.keys[i];
      if compare.str_compare(k, key) == 0 {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

// True when the catalog holds an entry for (locale, key).
fn _has_entry(c: &Catalog, locale: Str, key: Str) -> Bool {
  return _entry_index(c, locale, key) >= 0;
}

// Store one entry with last-wins semantics: an existing (locale, key) pair is
// replaced in place (keeping its first position), a new pair is appended.
fn _set_entry(c: &mut Catalog, locale: Str, key: Str, value: Str) {
  let i = _entry_index(c, locale, key);
  if i >= 0 {
    c.values[i] = value;
    return;
  }
  c.locales.push(locale);
  c.keys.push(key);
  c.values.push(value);
}

// --------------------------------------------------
//  Parsing helpers
// --------------------------------------------------

// Index of the first '=' or ':', or -1. The first separator splits a line.
fn _find_separator(s: Str) -> Int {
  var i = 0;
  while i < s.len() {
    let b = _byte(s, i);
    if b == _TRANSL_EQ || b == _TRANSL_COLON {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Parse one line into `c`. Returns "" on success (blank line, comment, or a
// stored pair) or a "translation: ..." message on a malformed line.
fn _parse_line(c: &mut Catalog, locale: Str, line: Str) -> Str {
  let t = string.str_trim(line);
  if t.len() == 0 {
    return "";
  }
  let first = _byte(t, 0);
  if first == _TRANSL_HASH || first == _TRANSL_SEMI {
    return "";
  }
  let sep = _find_separator(t);
  if sep < 0 {
    return "translation: missing separator in line: " + t;
  }
  let key = string.str_trim(string.str_slice(t, 0, sep));
  if key.len() == 0 {
    return "translation: empty key in line: " + t;
  }
  let value = string.str_trim(string.str_slice(t, sep + 1, t.len()));
  _set_entry(c, locale, key, value);
  return "";
}

// --------------------------------------------------
//  Interpolation helpers
// --------------------------------------------------

// Index of the first '}' at or after `start`, or -1.
fn _find_close(s: Str, start: Int) -> Int {
  var i = start;
  while i < s.len() {
    if _byte(s, i) == _TRANSL_RBRACE {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of the first name in `names` that equals `name` and has a parallel
// value, or -1. Duplicates resolve to the first match; a name without a
// parallel value never matches (BUG 17: str_compare, not `==`).
fn _lookup_name(names: &Vec[Str], values: &Vec[Str], name: Str) -> Int {
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

// Single left-to-right pass: "{name}" is replaced from names/values, an
// unknown name renders empty, a "{" with no later "}" is literal, and
// substituted text is copied verbatim (never re-scanned).
fn _interpolate(text: Str, names: &Vec[Str], values: &Vec[Str]) -> Str {
  var sb = builder.sb_new();
  let len = text.len();
  var i = 0;
  while i < len {
    let b = _byte(text, i);
    if b == _TRANSL_LBRACE {
      let close = _find_close(text, i + 1);
      if close < 0 {
        builder.sb_push_byte(&mut sb, b as UInt8);
        i = i + 1;
      } else {
        let name = string.str_slice(text, i + 1, close);
        let idx = _lookup_name(names, values, name);
        if idx >= 0 {
          let v: Str = values[idx];
          builder.sb_push_str(&mut sb, v);
        }
        i = close + 1;
      }
    } else {
      builder.sb_push_byte(&mut sb, b as UInt8);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&sb);
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse one in-memory catalog document for a single locale.
/// Params: locale - the locale tag stored with every entry; text - the whole
/// document (LF or CRLF line endings).
/// Returns: Ok(Catalog) for a valid document (including an empty one); Err
/// with a "translation: ..." message for a line without '=' or ':' or with
/// an empty key. A duplicate (locale, key) is not an error: the last
/// assignment wins and keeps the first position.
/// Complexity: O(total input length * entry count) because duplicate
/// detection scans the entry list per line; O(total input length) with a
/// hash index.
pub fn catalog_parse(locale: Str, text: Str) -> Result[Catalog, Str] {
  var c = Catalog{ locales: Vec[Str].new(); keys: Vec[Str].new(); values: Vec[Str].new(); };
  let len = text.len();
  var line_start = 0;
  var i = 0;
  while i <= len {
    if i == len || _byte(text, i) == _TRANSL_LF {
      var line = string.str_slice(text, line_start, i);
      let raw = line.len();
      if raw > 0 && _byte(line, raw - 1) == _TRANSL_CR {
        line = string.str_slice(line, 0, raw - 1);
      }
      let msg = _parse_line(&mut c, locale, line);
      if msg.len() > 0 {
        return _err_catalog(msg);
      }
      line_start = i + 1;
    }
    i = i + 1;
  }
  return _ok_catalog(c);
}

/// Translation of `key` in `locale`; None when the pair is absent. Locales
/// and keys are byte-exact and case-sensitive.
pub fn catalog_get(c: &Catalog, locale: Str, key: Str) -> Option[Str] {
  let i = _entry_index(c, locale, key);
  if i < 0 {
    return None;
  }
  let v: Str = c.values[i];
  return Some(v);
}

/// Locales that have at least one entry, in first-seen order (a fresh copy).
pub fn catalog_locales(c: &Catalog) -> Vec[Str] {
  var out = Vec[Str].new();
  let lim = _entry_limit(c);
  var i = 0;
  while i < lim {
    let l: Str = c.locales[i];
    if !_contains(&out, l) {
      out.push(l);
    }
    i = i + 1;
  }
  return out;
}

/// Keys stored for `locale`, in entry order (a fresh copy). Duplicates cannot
/// occur through this API, so the result is already deduplicated.
pub fn catalog_keys(c: &Catalog, locale: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let lim = _entry_limit(c);
  var i = 0;
  while i < lim {
    let l: Str = c.locales[i];
    if compare.str_compare(l, locale) == 0 {
      let k: Str = c.keys[i];
      out.push(k);
    }
    i = i + 1;
  }
  return out;
}

/// Copy of `c` with (locale, key) set to `value`: an existing pair is
/// replaced in place (keeping its position), a new pair is appended.
/// Params: c - the catalog to copy (never mutated); locale, key, value - the
/// entry to write.
/// Returns: a new catalog; the input catalog is unchanged.
/// Error case: none.
/// Complexity: O(entry count + input length).
pub fn catalog_add(c: &Catalog, locale: Str, key: Str, value: Str) -> Catalog {
  var out = Catalog{ locales: Vec[Str].new(); keys: Vec[Str].new(); values: Vec[Str].new(); };
  let lim = _entry_limit(c);
  var i = 0;
  while i < lim {
    let l: Str = c.locales[i];
    let k: Str = c.keys[i];
    let v: Str = c.values[i];
    out.locales.push(l);
    out.keys.push(k);
    out.values.push(v);
    i = i + 1;
  }
  _set_entry(&mut out, locale, key, value);
  return out;
}

/// Keys translated in `fallback` but absent from `locale`.
/// Params: c - the catalog; locale - the target locale; fallback - the
/// locale to compare against.
/// Returns: the missing keys in fallback entry order, deduplicated. A key is
/// reported once even when a hand-built fallback stores it repeatedly.
/// Error case: none.
/// Complexity: O(entries * keys).
pub fn catalog_missing(c: &Catalog, locale: Str, fallback: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let lim = _entry_limit(c);
  var i = 0;
  while i < lim {
    let l: Str = c.locales[i];
    if compare.str_compare(l, fallback) == 0 {
      let k: Str = c.keys[i];
      if !_contains(&out, k) && !_has_entry(c, locale, k) {
        out.push(k);
      }
    }
    i = i + 1;
  }
  return out;
}

/// Resolve `key` and interpolate its "{name}" placeholders.
/// Params: c - the catalog; locale - the preferred locale; fallback - the
/// locale used when `locale` has no entry for `key`; key - the lookup key
/// (also the last-resort text); names, values - parallel vectors of
/// placeholder substitutions (the first matching name wins).
/// Returns: the text resolved in this order -- 1) (locale, key), 2)
/// (fallback, key), 3) `key` itself -- after one single-pass interpolation
/// over "{name}" placeholders. An unknown name renders empty; a "{" with no
/// later "}" is literal; "{{" is not special (the first "}" closes, so the
/// placeholder name may start with "{"); substituted values are copied
/// verbatim and never re-scanned. The last-resort key is interpolated too.
/// Error case: none; a missing key resolves to the key text.
/// Complexity: O(entries) per lookup plus O(output) for interpolation.
pub fn catalog_translate(c: &Catalog, locale: Str, fallback: Str, key: Str, names: &Vec[Str], values: &Vec[Str]) -> Str {
  let i = _entry_index(c, locale, key);
  if i >= 0 {
    let v: Str = c.values[i];
    return _interpolate(v, names, values);
  }
  let j = _entry_index(c, fallback, key);
  if j >= 0 {
    let w: Str = c.values[j];
    return _interpolate(w, names, values);
  }
  return _interpolate(key, names, values);
}
