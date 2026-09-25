// XIOM -- xiom.bibtex: BibTeX bibliography parser and canonical emitter
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: one bibliography is ten parallel vectors. Entries keep their own
// vectors (types, keys, field slices); fields and @string macros share two
// flat pools (names/values); @preamble and @comment bodies each get their
// own Vec[Str]. Vec[StructType] is unsupported in this compiler, so the
// document is deliberately flat instead of a tree of entry structs.
//
// Subset: @type{key, field = {value}, field = "value", field = 123, ...}
// entries with balanced-brace and quoted values (nested braces preserved),
// @string macros with case-insensitive reference expansion (macros must be
// defined before use), @comment and @preamble pass-through, and whitespace
// between entries. Text outside entries must be whitespace; anything else
// is Err("bibtex: ..."). No LaTeX macro/escape processing, no citation
// styles, no .bib merging, no '#' concatenation, no parenthesis entries.
// See SPEC.md for the exact grammar and error catalog.
//
// Language notes (XIOM v0.61.3): free functions only; Str values read from
// Vec[Str] elements are compared through str_compare / str_eq_ignore_case
// after binding a typed local (BUG 17: `==` on such elements lowers to a
// pointer comparison). Entries, fields and macros are stored in parallel
// vectors, never in a Vec[StructType].

module xiom.bibtex

use xiom.string;
use xiom.string.compare;

// ---------------------------------------------------------------------------
// Byte constants
// ---------------------------------------------------------------------------

const _BT_AT: UInt8 = 64u8;
const _BT_HASH: UInt8 = 35u8;
const _BT_QUOTE: UInt8 = 34u8;
const _BT_LPAREN: UInt8 = 40u8;
const _BT_RPAREN: UInt8 = 41u8;
const _BT_COMMA: UInt8 = 44u8;
const _BT_DOT: UInt8 = 46u8;
const _BT_COLON: UInt8 = 58u8;
const _BT_EQUALS: UInt8 = 61u8;
const _BT_BACKSLASH: UInt8 = 92u8;
const _BT_UNDERSCORE: UInt8 = 95u8;
const _BT_LBRACE: UInt8 = 123u8;
const _BT_RBRACE: UInt8 = 125u8;

// ---------------------------------------------------------------------------
// Document model
// ---------------------------------------------------------------------------

/// Parsed BibTeX bibliography. Entry `e` owns the field pool slice
/// field_names[field_starts[e] .. field_starts[e] + field_counts[e]] (and the
/// same slice of field_values); field names and entry types are stored
/// lowercased, citation keys and field values as written (values expanded).
/// `macro_names`/`macro_values` hold @string definitions, `preambles` and
/// `comments` hold @preamble values and @comment bodies.
pub type BibDoc = {
  entry_types: Vec[Str];
  entry_keys: Vec[Str];
  field_starts: Vec[Int];
  field_counts: Vec[Int];
  field_names: Vec[Str];
  field_values: Vec[Str];
  macro_names: Vec[Str];
  macro_values: Vec[Str];
  preambles: Vec[Str];
  comments: Vec[Str];
}

// ---------------------------------------------------------------------------
// Byte predicates
// ---------------------------------------------------------------------------

// True for the whitespace bytes BibTeX treats as separators: SP TAB LF CR.
fn _is_ws_byte(b: UInt8) -> Bool {
  return b == 32u8 || b == 9u8 || b == 10u8 || b == 13u8;
}

// True for an ASCII letter: A-Z a-z.
fn _is_alpha_byte(b: UInt8) -> Bool {
  if b >= 65u8 && b <= 90u8 { return true; }
  return b >= 97u8 && b <= 122u8;
}

// True for an ASCII digit: 0-9.
fn _is_digit_byte(b: UInt8) -> Bool {
  return b >= 48u8 && b <= 57u8;
}

// True for a field/macro name byte: A-Z a-z 0-9 - _ : .
fn _is_name_byte(b: UInt8) -> Bool {
  if _is_alpha_byte(b) { return true; }
  if _is_digit_byte(b) { return true; }
  if b == 45u8 { return true; }
  if b == _BT_UNDERSCORE { return true; }
  if b == _BT_COLON { return true; }
  return b == _BT_DOT;
}

// True for a byte that terminates a citation key or field-name token.
fn _is_key_stop(b: UInt8) -> Bool {
  if _is_ws_byte(b) { return true; }
  if b == _BT_COMMA { return true; }
  if b == _BT_LBRACE || b == _BT_RBRACE { return true; }
  if b == _BT_LPAREN || b == _BT_RPAREN { return true; }
  if b == _BT_EQUALS { return true; }
  if b == _BT_QUOTE { return true; }
  return b == _BT_HASH;
}

// ---------------------------------------------------------------------------
// Scanning helpers
// ---------------------------------------------------------------------------

// First index at or after `i` holding a non-whitespace byte, or text.len().
fn _skip_ws(text: Str, i: Int) -> Int {
  let n = text.len();
  var j = i;
  while j < n && _is_ws_byte(string.byte_at(text, j)) {
    j = j + 1;
  }
  return j;
}

// At most 24 bytes of the non-whitespace run starting at `i` (for messages).
fn _snippet(text: Str, i: Int) -> Str {
  let n = text.len();
  var j = i;
  while j < n && j - i < 24 && !_is_ws_byte(string.byte_at(text, j)) {
    j = j + 1;
  }
  return string.str_slice(text, i, j);
}

// Run of name bytes starting at `i` (possibly empty).
fn _read_name(text: Str, i: Int) -> Str {
  let n = text.len();
  var j = i;
  while j < n && _is_name_byte(string.byte_at(text, j)) {
    j = j + 1;
  }
  return string.str_slice(text, i, j);
}

// Run of ASCII digits starting at `i` (possibly empty).
fn _read_digits(text: Str, i: Int) -> Str {
  let n = text.len();
  var j = i;
  while j < n && _is_digit_byte(string.byte_at(text, j)) {
    j = j + 1;
  }
  return string.str_slice(text, i, j);
}

// Citation-key run starting at `i`: bytes up to the next key stop (possibly
// empty, e.g. when the entry body starts with ',' or '}').
fn _read_key(text: Str, i: Int) -> Str {
  let n = text.len();
  var j = i;
  while j < n && !_is_key_stop(string.byte_at(text, j)) {
    j = j + 1;
  }
  return string.str_slice(text, i, j);
}

// End position of the value token starting at `i` (exclusive). Assumes the
// token was accepted by _parse_value; mirrors its scanning exactly.
fn _value_end(text: Str, i: Int) -> Int {
  let n = text.len();
  if i >= n { return n; }
  let b = string.byte_at(text, i);
  if b == _BT_LBRACE {
    var depth = 1;
    var j = i + 1;
    while j < n {
      let c = string.byte_at(text, j);
      if c == _BT_LBRACE {
        depth = depth + 1;
      } elif c == _BT_RBRACE {
        depth = depth - 1;
        if depth == 0 { return j + 1; }
      }
      j = j + 1;
    }
    return n;
  }
  if b == _BT_QUOTE {
    var j = i + 1;
    while j < n {
      let c = string.byte_at(text, j);
      if c == _BT_BACKSLASH {
        j = j + 2;
      } elif c == _BT_QUOTE {
        return j + 1;
      } else {
        j = j + 1;
      }
    }
    return n;
  }
  if _is_digit_byte(b) {
    return _read_digits(text, i).len() + i;
  }
  return _read_name(text, i).len() + i;
}

// ---------------------------------------------------------------------------
// Value parsing
// ---------------------------------------------------------------------------

// Read a braced value starting at '{': return the bytes between the outer
// braces with nested braces preserved. Err on end of input.
fn _read_braced(text: Str, i: Int) -> Result[Str, Str] {
  let n = text.len();
  var out = Vec[UInt8].new();
  var depth = 1;
  var j = i + 1;
  while j < n {
    let c = string.byte_at(text, j);
    if c == _BT_LBRACE {
      depth = depth + 1;
      out.push(c);
    } elif c == _BT_RBRACE {
      depth = depth - 1;
      if depth == 0 { return Ok(Str::from_utf8(out)); }
      out.push(c);
    } else {
      out.push(c);
    }
    j = j + 1;
  }
  return Err("bibtex: unterminated value");
}

// Read a quoted value starting at '"': return the bytes between the quotes.
// A backslash escapes the next byte, which is kept verbatim; braces must be
// balanced inside the quotes. Err on end of input or imbalanced braces.
fn _read_quoted(text: Str, i: Int) -> Result[Str, Str] {
  let n = text.len();
  var out = Vec[UInt8].new();
  var depth = 0;
  var j = i + 1;
  while j < n {
    let c = string.byte_at(text, j);
    if c == _BT_BACKSLASH {
      if j + 1 >= n { return Err("bibtex: unterminated quote"); }
      out.push(c);
      out.push(string.byte_at(text, j + 1));
      j = j + 2;
    } elif c == _BT_QUOTE {
      if depth != 0 { return Err("bibtex: unbalanced braces in value"); }
      return Ok(Str::from_utf8(out));
    } elif c == _BT_LBRACE {
      depth = depth + 1;
      out.push(c);
      j = j + 1;
    } elif c == _BT_RBRACE {
      if depth == 0 { return Err("bibtex: unbalanced braces in value"); }
      depth = depth - 1;
      out.push(c);
      j = j + 1;
    } else {
      out.push(c);
      j = j + 1;
    }
  }
  return Err("bibtex: unterminated quote");
}

// Parse one value token at `i`: braced group, quoted string, nonnegative
// number, or macro reference (expanded, case-insensitively). Err with a
// "bibtex: ..." message on malformed or unterminated values, on '#' and on
// an undefined macro.
fn _parse_value(text: Str, i: Int, d: &BibDoc) -> Result[Str, Str] {
  let n = text.len();
  if i >= n { return Err("bibtex: missing value"); }
  let b = string.byte_at(text, i);
  if b == _BT_LBRACE { return _read_braced(text, i); }
  if b == _BT_QUOTE { return _read_quoted(text, i); }
  if b == _BT_HASH { return Err("bibtex: unsupported concatenation"); }
  if _is_digit_byte(b) { return Ok(_read_digits(text, i)); }
  if _is_alpha_byte(b) { return _expand_macro(d, _read_name(text, i)); }
  return Err("bibtex: malformed value: " + _snippet(text, i));
}

// ---------------------------------------------------------------------------
// Pool lookups
// ---------------------------------------------------------------------------

// Index of the entry whose citation key matches `key` case-insensitively
// (BibTeX treats citation keys case-insensitively), or -1.
fn _find_entry(d: &BibDoc, key: Str) -> Int {
  var i = 0;
  while i < d.entry_keys.len() {
    let have: Str = d.entry_keys[i];
    if compare.str_eq_ignore_case(have, key) { return i; }
    i = i + 1;
  }
  return -1;
}

// Index of the @string macro `name` (case-insensitive), or -1.
fn _find_macro(d: &BibDoc, name: Str) -> Int {
  var i = 0;
  while i < d.macro_names.len() {
    let have: Str = d.macro_names[i];
    if compare.str_eq_ignore_case(have, name) { return i; }
    i = i + 1;
  }
  return -1;
}

// Index of field `name` within the `count` fields starting at pool `start`,
// matched case-insensitively, or -1.
fn _field_index(d: &BibDoc, start: Int, count: Int, name: Str) -> Int {
  var j = 0;
  while j < count {
    let have: Str = d.field_names[start + j];
    if compare.str_eq_ignore_case(have, name) { return j; }
    j = j + 1;
  }
  return -1;
}

// Expand a macro reference: Ok(value) when defined, Err otherwise.
fn _expand_macro(d: &BibDoc, name: Str) -> Result[Str, Str] {
  let i = _find_macro(d, name);
  if i < 0 { return Err("bibtex: undefined macro: " + name); }
  let v: Str = d.macro_values[i];
  return Ok(v);
}

// ---------------------------------------------------------------------------
// Document mutation helpers (same module only)
// ---------------------------------------------------------------------------

// Append one entry with its already-pushed field slice.
fn _push_entry(d: &mut BibDoc, etype: Str, key: Str, start: Int, count: Int) {
  d.entry_types.push(string.str_lower(etype));
  d.entry_keys.push(key);
  d.field_starts.push(start);
  d.field_counts.push(count);
}

// Append one @string macro; `name` is stored lowercased.
fn _push_macro(d: &mut BibDoc, name: Str, value: Str) {
  d.macro_names.push(string.str_lower(name));
  d.macro_values.push(value);
}

// ---------------------------------------------------------------------------
// Command parsers (positions point just after the opening '{')
// ---------------------------------------------------------------------------

// Parse a normal entry body: key, comma, zero or more `name = value` fields,
// optional trailing comma. On success the entry is appended to `d` and the
// position after the closing '}' is returned.
fn _parse_entry(text: Str, i: Int, etype: Str, d: &mut BibDoc) -> Result[Int, Str] {
  let n = text.len();
  var j = _skip_ws(text, i);
  if j >= n { return Err("bibtex: unterminated entry"); }
  let key = _read_key(text, j);
  if key.len() == 0 { return Err("bibtex: missing key in entry"); }
  if _find_entry(d, key) >= 0 { return Err("bibtex: duplicate key: " + key); }
  let start = d.field_names.len();
  var count = 0;
  j = _skip_ws(text, j + key.len());
  if j >= n { return Err("bibtex: unterminated entry"); }
  let sep = string.byte_at(text, j);
  if sep == _BT_RBRACE {
    _push_entry(d, etype, key, start, count);
    return Ok(j + 1);
  }
  if sep != _BT_COMMA {
    return Err("bibtex: expected ',' or '}' after entry key");
  }
  j = j + 1;
  var done = false;
  while !done {
    j = _skip_ws(text, j);
    if j >= n { return Err("bibtex: unterminated entry"); }
    let b = string.byte_at(text, j);
    if b == _BT_RBRACE {
      done = true;
    } else {
      if !_is_alpha_byte(b) {
        return Err("bibtex: bad field name: " + _snippet(text, j));
      }
      let fname = _read_name(text, j);
      j = _skip_ws(text, j + fname.len());
      if j >= n { return Err("bibtex: unterminated entry"); }
      if string.byte_at(text, j) != _BT_EQUALS {
        return Err("bibtex: missing '=' after field name: " + fname);
      }
      j = _skip_ws(text, j + 1);
      if j >= n { return Err("bibtex: missing value for field: " + fname); }
      if string.byte_at(text, j) == _BT_RBRACE {
        return Err("bibtex: missing value for field: " + fname);
      }
      let vr = _parse_value(text, j, d);
      match vr {
        Ok(v) => {
          if _field_index(d, start, count, fname) >= 0 {
            return Err("bibtex: duplicate field: " + fname);
          }
          d.field_names.push(string.str_lower(fname));
          d.field_values.push(v);
          count = count + 1;
        },
        Err(e) => { return Err(e); },
      }
      j = _skip_ws(text, _value_end(text, j));
      if j >= n { return Err("bibtex: unterminated entry"); }
      let after = string.byte_at(text, j);
      if after == _BT_COMMA {
        j = j + 1;
      } elif after == _BT_RBRACE {
        done = true;
      } elif after == _BT_HASH {
        return Err("bibtex: unsupported concatenation");
      } else {
        return Err("bibtex: expected ',' or '}' after field value");
      }
    }
  }
  _push_entry(d, etype, key, start, count);
  return Ok(j + 1);
}

// Parse an @string definition: name, '=', braced/quoted/number value (or an
// earlier macro reference). Returns the position after the closing '}'.
fn _parse_string_cmd(text: Str, i: Int, d: &mut BibDoc) -> Result[Int, Str] {
  let n = text.len();
  var j = _skip_ws(text, i);
  if j >= n { return Err("bibtex: unterminated entry"); }
  if !_is_alpha_byte(string.byte_at(text, j)) {
    return Err("bibtex: bad macro name: " + _snippet(text, j));
  }
  let name = _read_name(text, j);
  j = _skip_ws(text, j + name.len());
  if j >= n { return Err("bibtex: unterminated entry"); }
  if string.byte_at(text, j) != _BT_EQUALS {
    return Err("bibtex: missing '=' after macro name: " + name);
  }
  j = _skip_ws(text, j + 1);
  if j >= n { return Err("bibtex: missing value for macro: " + name); }
  if string.byte_at(text, j) == _BT_RBRACE {
    return Err("bibtex: missing value for macro: " + name);
  }
  let vr = _parse_value(text, j, d);
  match vr {
    Ok(v) => {
      if _find_macro(d, name) >= 0 {
        return Err("bibtex: duplicate macro: " + name);
      }
      _push_macro(d, name, v);
    },
    Err(e) => { return Err(e); },
  }
  j = _skip_ws(text, _value_end(text, j));
  if j >= n { return Err("bibtex: unterminated entry"); }
  let after = string.byte_at(text, j);
  if after == _BT_HASH { return Err("bibtex: unsupported concatenation"); }
  if after != _BT_RBRACE { return Err("bibtex: expected '}' after @string"); }
  return Ok(j + 1);
}

// Parse an @comment body: any text with balanced braces, stored trimmed.
// Returns the position after the closing '}'.
fn _parse_comment_cmd(text: Str, i: Int, d: &mut BibDoc) -> Result[Int, Str] {
  let n = text.len();
  var out = Vec[UInt8].new();
  var depth = 1;
  var j = i;
  while j < n {
    let c = string.byte_at(text, j);
    if c == _BT_LBRACE {
      depth = depth + 1;
      out.push(c);
    } elif c == _BT_RBRACE {
      depth = depth - 1;
      if depth == 0 {
        d.comments.push(string.str_trim(Str::from_utf8(out)));
        return Ok(j + 1);
      }
      out.push(c);
    } else {
      out.push(c);
    }
    j = j + 1;
  }
  return Err("bibtex: unterminated comment");
}

// Parse an @preamble value and append it to `d`. Returns the position after
// the closing '}'.
fn _parse_preamble_cmd(text: Str, i: Int, d: &mut BibDoc) -> Result[Int, Str] {
  let n = text.len();
  var j = _skip_ws(text, i);
  if j >= n { return Err("bibtex: unterminated entry"); }
  if string.byte_at(text, j) == _BT_RBRACE {
    return Err("bibtex: missing value for @preamble");
  }
  let vr = _parse_value(text, j, d);
  match vr {
    Ok(v) => { d.preambles.push(v); },
    Err(e) => { return Err(e); },
  }
  j = _skip_ws(text, _value_end(text, j));
  if j >= n { return Err("bibtex: unterminated entry"); }
  let after = string.byte_at(text, j);
  if after == _BT_HASH { return Err("bibtex: unsupported concatenation"); }
  if after != _BT_RBRACE { return Err("bibtex: expected '}' after @preamble"); }
  return Ok(j + 1);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Parse a whole BibTeX bibliography.
/// Params: text - the complete .bib source.
/// Returns: Ok(BibDoc) for valid input, including empty or whitespace-only
/// text; Err with a "bibtex: ..." message on the first error in document
/// order (see SPEC.md for the catalog). Citation keys are matched
/// case-insensitively; entry types, field names and macro names are stored
/// lowercased; field values are stored expanded with their braces or quotes
/// removed.
/// Error case: unterminated entry/value/quote/comment, missing entry type or
/// key, missing '=', bad field/macro name, missing value, unbalanced braces,
/// duplicate key/field/macro, undefined macro, concatenation and text outside
/// entries.
/// Complexity: O(total input length).
pub fn bib_parse(text: Str) -> Result[BibDoc, Str] {
  var doc = BibDoc{
    entry_types: Vec[Str].new();
    entry_keys: Vec[Str].new();
    field_starts: Vec[Int].new();
    field_counts: Vec[Int].new();
    field_names: Vec[Str].new();
    field_values: Vec[Str].new();
    macro_names: Vec[Str].new();
    macro_values: Vec[Str].new();
    preambles: Vec[Str].new();
    comments: Vec[Str].new();
  };
  let n = text.len();
  var i = 0;
  while i < n {
    let b = string.byte_at(text, i);
    if _is_ws_byte(b) {
      i = i + 1;
    } elif b == _BT_AT {
      var j = _skip_ws(text, i + 1);
      if j >= n { return Err("bibtex: missing entry type"); }
      if !_is_alpha_byte(string.byte_at(text, j)) {
        return Err("bibtex: bad entry type: " + _snippet(text, j));
      }
      let ty = _read_name(text, j);
      j = _skip_ws(text, j + ty.len());
      if j >= n { return Err("bibtex: expected '{' after entry type"); }
      if string.byte_at(text, j) != _BT_LBRACE {
        return Err("bibtex: expected '{' after entry type");
      }
      j = j + 1;
      var step: Result[Int, Str] = Ok(j);
      if compare.str_eq_ignore_case(ty, "string") {
        step = _parse_string_cmd(text, j, &mut doc);
      } elif compare.str_eq_ignore_case(ty, "comment") {
        step = _parse_comment_cmd(text, j, &mut doc);
      } elif compare.str_eq_ignore_case(ty, "preamble") {
        step = _parse_preamble_cmd(text, j, &mut doc);
      } else {
        step = _parse_entry(text, j, ty, &mut doc);
      }
      match step {
        Ok(pos) => { i = pos; },
        Err(e) => { return Err(e); },
      }
    } else {
      return Err("bibtex: text outside entries: " + _snippet(text, i));
    }
  }
  return Ok(doc);
}

/// Number of entries in the bibliography.
/// Params: d - the parsed document.
/// Returns: the entry count; 0 for an empty document.
/// Error case: none.
/// Complexity: O(1).
pub fn bib_entry_count(d: &BibDoc) -> Int {
  return d.entry_keys.len();
}

/// Lowercased type of entry `i` ("article", "book", ...).
/// Params: d - the parsed document; i - the zero-based entry index.
/// Returns: the type; "" when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn bib_entry_type(d: &BibDoc, i: Int) -> Str {
  if i < 0 || i >= d.entry_types.len() { return ""; }
  let t: Str = d.entry_types[i];
  return t;
}

/// Citation key of entry `i`, exactly as written.
/// Params: d - the parsed document; i - the zero-based entry index.
/// Returns: the key; "" when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn bib_entry_key(d: &BibDoc, i: Int) -> Str {
  if i < 0 || i >= d.entry_keys.len() { return ""; }
  let k: Str = d.entry_keys[i];
  return k;
}

/// Index of the entry whose citation key is `key` (case-insensitive, as in
/// BibTeX).
/// Params: d - the parsed document; key - the citation key to find.
/// Returns: the zero-based entry index, or -1 when no entry matches.
/// Error case: none.
/// Complexity: O(entries).
pub fn bib_find_entry(d: &BibDoc, key: Str) -> Int {
  return _find_entry(d, key);
}

/// Number of fields on entry `i`.
/// Params: d - the parsed document; i - the zero-based entry index.
/// Returns: the field count; 0 when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn bib_field_count(d: &BibDoc, i: Int) -> Int {
  if i < 0 || i >= d.field_counts.len() { return 0; }
  let c: Int = d.field_counts[i];
  return c;
}

/// Lowercased name of field `j` on entry `i`.
/// Params: d - the parsed document; i - the entry index; j - the zero-based
/// field index within the entry.
/// Returns: the field name; "" when `i` or `j` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn bib_field_name(d: &BibDoc, i: Int, j: Int) -> Str {
  if i < 0 || i >= d.entry_keys.len() { return ""; }
  let start: Int = d.field_starts[i];
  let count: Int = d.field_counts[i];
  if j < 0 || j >= count { return ""; }
  let nm: Str = d.field_names[start + j];
  return nm;
}

/// Expanded value of field `j` on entry `i` (braces or quotes removed,
/// nested braces preserved, macros resolved at parse time).
/// Params: d - the parsed document; i - the entry index; j - the zero-based
/// field index within the entry.
/// Returns: the value; "" when `i` or `j` is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn bib_field_value(d: &BibDoc, i: Int, j: Int) -> Str {
  if i < 0 || i >= d.entry_keys.len() { return ""; }
  let start: Int = d.field_starts[i];
  let count: Int = d.field_counts[i];
  if j < 0 || j >= count { return ""; }
  let v: Str = d.field_values[start + j];
  return v;
}

/// Value of the field `name` on entry `i` (case-insensitive field match).
/// Params: d - the parsed document; i - the entry index; name - the field
/// name.
/// Returns: Some(value) when entry `i` has the field; None when the entry is
/// out of range or the field is absent.
/// Error case: none.
/// Complexity: O(fields of entry i).
pub fn bib_get_field(d: &BibDoc, i: Int, name: Str) -> Option[Str] {
  if i < 0 || i >= d.entry_keys.len() { return None; }
  let start: Int = d.field_starts[i];
  let count: Int = d.field_counts[i];
  let k = _field_index(d, start, count, name);
  if k < 0 { return None; }
  let v: Str = d.field_values[start + k];
  return Some(v);
}

/// Number of @string macros defined in the document.
/// Params: d - the parsed document.
/// Returns: the macro count; 0 when none are defined.
/// Error case: none.
/// Complexity: O(1).
pub fn bib_macro_count(d: &BibDoc) -> Int {
  return d.macro_names.len();
}

/// Lowercased name of macro `k`.
/// Params: d - the parsed document; k - the zero-based macro index.
/// Returns: the name; "" when `k` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn bib_macro_name(d: &BibDoc, k: Int) -> Str {
  if k < 0 || k >= d.macro_names.len() { return ""; }
  let nm: Str = d.macro_names[k];
  return nm;
}

/// Expanded value of macro `k`.
/// Params: d - the parsed document; k - the zero-based macro index.
/// Returns: the value; "" when `k` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn bib_macro_value(d: &BibDoc, k: Int) -> Str {
  if k < 0 || k >= d.macro_values.len() { return ""; }
  let v: Str = d.macro_values[k];
  return v;
}

/// Value of the @string macro `name` (case-insensitive).
/// Params: d - the parsed document; name - the macro name.
/// Returns: Some(value) when the macro is defined; None otherwise.
/// Error case: none.
/// Complexity: O(macros).
pub fn bib_get_macro(d: &BibDoc, name: Str) -> Option[Str] {
  let k = _find_macro(d, name);
  if k < 0 { return None; }
  let v: Str = d.macro_values[k];
  return Some(v);
}

/// Number of @preamble blocks in the document.
/// Params: d - the parsed document.
/// Returns: the count; 0 when none.
/// Error case: none.
/// Complexity: O(1).
pub fn bib_preamble_count(d: &BibDoc) -> Int {
  return d.preambles.len();
}

/// Expanded value of @preamble `i`.
/// Params: d - the parsed document; i - the zero-based preamble index.
/// Returns: the value; "" when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn bib_preamble(d: &BibDoc, i: Int) -> Str {
  if i < 0 || i >= d.preambles.len() { return ""; }
  let v: Str = d.preambles[i];
  return v;
}

/// Number of @comment blocks in the document.
/// Params: d - the parsed document.
/// Returns: the count; 0 when none.
/// Error case: none.
/// Complexity: O(1).
pub fn bib_comment_count(d: &BibDoc) -> Int {
  return d.comments.len();
}

/// Trimmed body of @comment `i`.
/// Params: d - the parsed document; i - the zero-based comment index.
/// Returns: the body text; "" when `i` is negative or out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn bib_comment(d: &BibDoc, i: Int) -> Str {
  if i < 0 || i >= d.comments.len() { return ""; }
  let v: Str = d.comments[i];
  return v;
}

/// Render the document as canonical BibTeX text. Macros are emitted first
/// (as @string definitions), then @preamble blocks, then @comment blocks,
/// then entries; every value is emitted brace-wrapped, so the output always
/// re-parses (bib_parse(bib_emit(d)) preserves all entries, fields, macros,
/// preambles and comments).
/// Params: d - the parsed document.
/// Returns: the canonical text; "" for an empty document.
/// Error case: none.
/// Complexity: O(total emitted length).
pub fn bib_emit(d: &BibDoc) -> Str {
  var out = "";
  var k = 0;
  while k < d.macro_names.len() {
    let mn: Str = d.macro_names[k];
    let mv: Str = d.macro_values[k];
    out = out + "@string{" + mn + " = {" + mv + "}}\n";
    k = k + 1;
  }
  var p = 0;
  while p < d.preambles.len() {
    let pv: Str = d.preambles[p];
    out = out + "@preamble{{" + pv + "}}\n";
    p = p + 1;
  }
  var c = 0;
  while c < d.comments.len() {
    let cv: Str = d.comments[c];
    out = out + "@comment{" + cv + "}\n";
    c = c + 1;
  }
  var e = 0;
  while e < d.entry_types.len() {
    let ty: Str = d.entry_types[e];
    let key: Str = d.entry_keys[e];
    let start: Int = d.field_starts[e];
    let count: Int = d.field_counts[e];
    if count == 0 {
      out = out + "@" + ty + "{" + key + "}\n";
    } else {
      out = out + "@" + ty + "{" + key;
      var j = 0;
      while j < count {
        let fnm: Str = d.field_names[start + j];
        let fv: Str = d.field_values[start + j];
        out = out + ",\n  " + fnm + " = {" + fv + "}";
        j = j + 1;
      }
      out = out + "\n}\n";
    }
    e = e + 1;
  }
  return out;
}
