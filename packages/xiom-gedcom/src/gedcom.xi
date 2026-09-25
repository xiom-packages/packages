// XIOM -- xiom.gedcom: GEDCOM 5.5.1 line codec (line grammar, nesting
// validation, pointers, CONT/CONC joining, canonical emission)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: pure XIOM, no FFI, no file I/O (in-memory Str only).
//
// Model: a parsed transmission is five index-aligned vectors. Line i has
// level levels[i], optional xref id xrefs[i] ("" when absent), tag tags[i],
// verbatim value values[i] and parent index parents[i] (-1 for a level-0
// record). Vec[StructType] is unsupported in this compiler, so the file is
// deliberately flat instead of a list of line structs.
//
// Grammar (see SPEC.md for the full statement):
//   document = *( line )                        ; LF or CRLF terminated
//   line     = level [ sep xref ] sep tag [ sep value ]
//   level    = 1*7DIGIT
//   xref     = "@" 1*64( ALPHA / DIGIT / "_" ) "@"
//   tag      = 1*31( ALPHA / DIGIT / "_" )
//   sep      = 1*( SP / TAB )
//   value    = *( byte except LF )              ; verbatim after one sep
// Zero-length lines are ignored (record separators). Nesting rules: the first
// line is level 0 and every later level is at most previous + 1; parents[i]
// is the nearest preceding line at level levels[i] - 1.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all scanning is byte-wise over the input Str.
//   * Output bytes are collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str.
//   * Ok/Err for Result[Gedcom, Str] are constructed only in the tiny leaf
//     helpers _ok_gedcom/_err_gedcom (constructing Results directly inside
//     other functions miscompiles in this compiler).
//   * Str equality goes through xiom.string.compare.str_compare (BUG 17:
//     `==` on Str values read from Vec[Str] elements lowers to a pointer
//     comparison).

module xiom.gedcom

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(g) for Result[Gedcom, Str].
fn _ok_gedcom(g: Gedcom) -> Result[Gedcom, Str] {
  return Ok(g);
}

// Err(m) for Result[Gedcom, Str].
fn _err_gedcom(m: Str) -> Result[Gedcom, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Byte constants
// --------------------------------------------------

const _GED_TAB: UInt8 = 9u8;
const _GED_LF: UInt8 = 10u8;
const _GED_CR: UInt8 = 13u8;
const _GED_SPACE: UInt8 = 32u8;
const _GED_ZERO: UInt8 = 48u8;
const _GED_NINE: UInt8 = 57u8;
const _GED_AT: UInt8 = 64u8;
const _GED_UPPER_A: UInt8 = 65u8;
const _GED_UPPER_Z: UInt8 = 90u8;
const _GED_UNDER: UInt8 = 95u8;
const _GED_LOWER_A: UInt8 = 97u8;
const _GED_LOWER_Z: UInt8 = 122u8;

// Level is 1..7 ASCII digits (0..9999999); xref ids are 1..64 bytes; tags are
// 1..31 bytes (GEDCOM 5.5.1 limits).
const _GED_MAX_LEVEL_DIGITS: Int = 7;
const _GED_MAX_XREF_LEN: Int = 64;
const _GED_MAX_TAG_LEN: Int = 31;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed GEDCOM transmission: five parallel vectors, index-aligned by line
/// number (0-based, document order). `xrefs[i]` is "" when line i has no xref
/// id; `parents[i]` is -1 for a level-0 line, otherwise the nearest preceding
/// line whose level is one less.
pub type Gedcom = {
  levels: Vec[Int];
  xrefs: Vec[Str];
  tags: Vec[Str];
  values: Vec[Str];
  parents: Vec[Int];
}

// Internal result of _scan_line: either an error (ok == false, err set) or
// the four decoded fields of one physical line.
type LineScan = {
  ok: Bool;
  err: Str;
  level: Int;
  xref: Str;
  tag: Str;
  value: Str;
}

// A malformed-line result carrying the "gedcom: ..." message.
fn _bad_line(m: Str) -> LineScan {
  return LineScan{ ok: false; err: m; level: 0; xref: ""; tag: ""; value: ""; };
}

// A successfully decoded line.
fn _good_line(level: Int, xref: Str, tag: Str, value: Str) -> LineScan {
  return LineScan{ ok: true; err: ""; level: level; xref: xref; tag: tag; value: value; };
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// True for an ASCII space or horizontal tab.
fn _ged_ws(b: UInt8) -> Bool {
  return b == _GED_SPACE || b == _GED_TAB;
}

// True for an ASCII decimal digit.
fn _ged_digit(b: UInt8) -> Bool {
  return b >= _GED_ZERO && b <= _GED_NINE;
}

// True for the xref id / tag alphabet: ALPHA / DIGIT / "_".
fn _ged_word_byte(b: UInt8) -> Bool {
  if _ged_digit(b) {
    return true;
  }
  if b == _GED_UNDER {
    return true;
  }
  if b >= _GED_UPPER_A && b <= _GED_UPPER_Z {
    return true;
  }
  if b >= _GED_LOWER_A && b <= _GED_LOWER_Z {
    return true;
  }
  return false;
}

// Index just past the whitespace-delimited token starting at `i`.
fn _ged_token_end(line: Str, i: Int) -> Int {
  var j = i;
  while j < line.len() && !_ged_ws(string.byte_at(line, j)) {
    j = j + 1;
  }
  return j;
}

// True when `s` is exactly "@" id "@" with an id of 1..64 bytes of
// [A-Za-z0-9_]. This is the xref-field grammar and, by definition, the
// pointer-value predicate of `gedcom_is_pointer`.
fn _ged_is_xref(s: Str) -> Bool {
  let n = s.len();
  if n < 3 || n > _GED_MAX_XREF_LEN + 2 {
    return false;
  }
  if string.byte_at(s, 0) != _GED_AT || string.byte_at(s, n - 1) != _GED_AT {
    return false;
  }
  var k = 1;
  while k < n - 1 {
    if !_ged_word_byte(string.byte_at(s, k)) {
      return false;
    }
    k = k + 1;
  }
  return true;
}

// True when `tag` is 1..31 bytes of [A-Za-z0-9_].
fn _ged_is_tag(tag: Str) -> Bool {
  let n = tag.len();
  if n < 1 || n > _GED_MAX_TAG_LEN {
    return false;
  }
  var k = 0;
  while k < n {
    if !_ged_word_byte(string.byte_at(tag, k)) {
      return false;
    }
    k = k + 1;
  }
  return true;
}

// --------------------------------------------------
//  Line scanning
// --------------------------------------------------

// Decode one physical line (line terminator already removed). Total: every
// shape either yields the four fields or a "gedcom: ..." message.
fn _scan_line(line: Str) -> LineScan {
  let n = line.len();
  if n == 0 {
    return _bad_line("gedcom: text before level in line: " + line);
  }
  if !_ged_digit(string.byte_at(line, 0)) {
    return _bad_line("gedcom: text before level in line: " + line);
  }
  var i = 0;
  while i < n && _ged_digit(string.byte_at(line, i)) {
    i = i + 1;
  }
  if i > _GED_MAX_LEVEL_DIGITS {
    return _bad_line("gedcom: bad level digits in line: " + line);
  }
  if i < n && !_ged_ws(string.byte_at(line, i)) {
    return _bad_line("gedcom: bad level digits in line: " + line);
  }
  var level = 0;
  var k = 0;
  while k < i {
    level = level * 10 + (((string.byte_at(line, k) as Int) & 0xFF) - 48);
    k = k + 1;
  }
  while i < n && _ged_ws(string.byte_at(line, i)) {
    i = i + 1;
  }
  if i >= n {
    return _bad_line("gedcom: missing tag in line: " + line);
  }
  var xref = "";
  if string.byte_at(line, i) == _GED_AT {
    let xend = _ged_token_end(line, i);
    xref = string.str_slice(line, i, xend);
    if !_ged_is_xref(xref) {
      return _bad_line("gedcom: malformed xref in line: " + line);
    }
    i = xend;
    while i < n && _ged_ws(string.byte_at(line, i)) {
      i = i + 1;
    }
    if i >= n {
      return _bad_line("gedcom: missing tag in line: " + line);
    }
  }
  let tag_start = i;
  let tag_end = _ged_token_end(line, i);
  let tag = string.str_slice(line, tag_start, tag_end);
  if !_ged_is_tag(tag) {
    return _bad_line("gedcom: bad tag in line: " + line);
  }
  i = tag_end;
  var value = "";
  if i < n {
    // Exactly one separator byte belongs to the grammar; any further leading
    // whitespace is part of the verbatim value.
    i = i + 1;
    value = string.str_slice(line, i, n);
  }
  return _good_line(level, xref, tag, value);
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Parse one in-memory GEDCOM 5.5.1 transmission. Params: text - the whole
/// document (LF or CRLF line endings). Returns: Ok(Gedcom) whose five vectors
/// are index-aligned in document order; Err with a "gedcom: ..." message on
/// the first malformed line. Zero-length lines are ignored (record
/// separators); whitespace-only lines are not. The first parsed line must be
/// level 0 and every later level is at most the previous level + 1; a level
/// that decreases back to any smaller value is allowed. Values are kept
/// byte-for-byte after the single separator byte that follows the tag: a
/// value such as "@I1@" is stored verbatim and recognised by
/// `gedcom_is_pointer`. No semantic record validation is performed.
/// Complexity: O(total input length).
pub fn gedcom_parse(text: Str) -> Result[Gedcom, Str] {
  var g = Gedcom{ levels: Vec[Int].new(); xrefs: Vec[Str].new(); tags: Vec[Str].new(); values: Vec[Str].new(); parents: Vec[Int].new(); };
  // last_at[L] is the index of the most recent line at level L; it grows by at
  // most one slot per parsed line because levels never jump up by more than 1.
  var last_at = Vec[Int].new();
  let n = text.len();
  var line_start = 0;
  var i = 0;
  while i <= n {
    if i == n || string.byte_at(text, i) == _GED_LF {
      var line = string.str_slice(text, line_start, i);
      let raw_len = line.len();
      if raw_len > 0 && string.byte_at(line, raw_len - 1) == _GED_CR {
        line = string.str_slice(line, 0, raw_len - 1);
      }
      if line.len() > 0 {
        let scan = _scan_line(line);
        if !scan.ok {
          return _err_gedcom(scan.err);
        }
        let count = g.levels.len();
        if count == 0 {
          if scan.level != 0 {
            return _err_gedcom("gedcom: level jump in line: " + line);
          }
        } else {
          let prev: Int = g.levels[count - 1];
          if scan.level > prev + 1 {
            return _err_gedcom("gedcom: level jump in line: " + line);
          }
        }
        var parent = -1;
        if scan.level > 0 && last_at.len() >= scan.level {
          parent = last_at[scan.level - 1];
        }
        while last_at.len() <= scan.level {
          last_at.push(-1);
        }
        last_at[scan.level] = count;
        g.levels.push(scan.level);
        g.xrefs.push(scan.xref);
        g.tags.push(scan.tag);
        g.values.push(scan.value);
        g.parents.push(parent);
      }
      if i == n {
        break;
      }
      line_start = i + 1;
    }
    i = i + 1;
  }
  return _ok_gedcom(g);
}

/// Number of stored lines (zero-length input lines are not counted).
pub fn gedcom_line_count(g: &Gedcom) -> Int {
  return g.levels.len();
}

/// Level of line `i`, or -1 when `i` is out of range. Levels are always >= 0
/// for stored lines.
pub fn gedcom_level(g: &Gedcom, i: Int) -> Int {
  if i < 0 || i >= g.levels.len() {
    return -1;
  }
  let v: Int = g.levels[i];
  return v;
}

/// Xref id of line `i` including both "@" delimiters; None when the line has
/// no xref id or when `i` is out of range. Ids are never empty.
pub fn gedcom_xref(g: &Gedcom, i: Int) -> Option[Str] {
  if i < 0 || i >= g.xrefs.len() {
    return None;
  }
  let v: Str = g.xrefs[i];
  if v.len() == 0 {
    return None;
  }
  return Some(v);
}

/// Tag of line `i`; "" when `i` is out of range.
pub fn gedcom_tag(g: &Gedcom, i: Int) -> Str {
  if i < 0 || i >= g.tags.len() {
    return "";
  }
  let v: Str = g.tags[i];
  return v;
}

/// Verbatim value of line `i`; "" when the line has no value or when `i` is
/// out of range.
pub fn gedcom_value(g: &Gedcom, i: Int) -> Str {
  if i < 0 || i >= g.values.len() {
    return "";
  }
  let v: Str = g.values[i];
  return v;
}

/// Parent index of line `i`: the nearest preceding line whose level is one
/// less. -1 for a level-0 line and for an out-of-range `i`.
pub fn gedcom_parent(g: &Gedcom, i: Int) -> Int {
  if i < 0 || i >= g.parents.len() {
    return -1;
  }
  let v: Int = g.parents[i];
  return v;
}

/// Index of the first line (document order) whose tag is byte-equal to `tag`;
/// None when no line matches. Matching is case-sensitive.
pub fn gedcom_first_tag(g: &Gedcom, tag: Str) -> Option[Int] {
  let n = g.tags.len();
  var i = 0;
  while i < n {
    let t: Str = g.tags[i];
    if compare.str_compare(t, tag) == 0 {
      return Some(i);
    }
    i = i + 1;
  }
  return None;
}

/// Exclusive end of the subtree rooted at line `i`: the first later line whose
/// level is <= levels[i], or the line count when no such line exists. For an
/// out-of-range `i` the line count is returned; the subtree of `i` is the
/// half-open range [i, subtree_end(i)).
pub fn gedcom_subtree_end(g: &Gedcom, i: Int) -> Int {
  let n = g.levels.len();
  if i < 0 || i >= n {
    return n;
  }
  let base: Int = g.levels[i];
  var j = i + 1;
  while j < n {
    let lv: Int = g.levels[j];
    if lv <= base {
      return j;
    }
    j = j + 1;
  }
  return n;
}

/// True when `v` is a GEDCOM pointer value: exactly "@" id "@" with an id of
/// 1..64 bytes of [A-Za-z0-9_]. Pointer values are stored verbatim; this
/// predicate only classifies them.
pub fn gedcom_is_pointer(v: Str) -> Bool {
  return _ged_is_xref(v);
}

/// Join the text of line `i` with its CONT/CONC continuation children.
/// Returns values[i] followed by the direct children of `i`, in order: a CONT
/// child appends LF + its value, a CONC child appends its value verbatim.
/// Scanning stops at the first direct child with any other tag; descendants
/// of continuation children are ignored. Out-of-range `i` yields "".
/// Complexity: O(subtree size).
pub fn gedcom_join_text(g: &Gedcom, i: Int) -> Str {
  var out = Vec[UInt8].new();
  let n = g.levels.len();
  if i < 0 || i >= n {
    return "";
  }
  let base: Str = g.values[i];
  builder.sb_push_str(&mut out, base);
  let end = gedcom_subtree_end(g, i);
  var j = i + 1;
  while j < end {
    let p: Int = g.parents[j];
    if p == i {
      let t: Str = g.tags[j];
      let is_cont = compare.str_compare(t, "CONT") == 0;
      let is_conc = compare.str_compare(t, "CONC") == 0;
      if is_cont {
        out.push(_GED_LF);
        let v: Str = g.values[j];
        builder.sb_push_str(&mut out, v);
      } else if is_conc {
        let v: Str = g.values[j];
        builder.sb_push_str(&mut out, v);
      } else {
        break;
      }
    }
    j = j + 1;
  }
  return builder.sb_to_str(&out);
}

/// Canonical emission: every line is `level [xref] tag [value]` with exactly
/// one space between fields, LF-terminated; a missing xref or value adds no
/// separator. An empty document emits "". Values are written verbatim, so a
/// value built by hand that contains LF is not round-trip safe (parsed values
/// never can).
/// Complexity: O(total output length).
pub fn gedcom_emit(g: &Gedcom) -> Str {
  var out = Vec[UInt8].new();
  let n = g.levels.len();
  var i = 0;
  while i < n {
    let level: Int = g.levels[i];
    builder.sb_push_int(&mut out, level);
    let xref: Str = g.xrefs[i];
    if xref.len() > 0 {
      out.push(_GED_SPACE);
      builder.sb_push_str(&mut out, xref);
    }
    out.push(_GED_SPACE);
    let tag: Str = g.tags[i];
    builder.sb_push_str(&mut out, tag);
    let value: Str = g.values[i];
    if value.len() > 0 {
      out.push(_GED_SPACE);
      builder.sb_push_str(&mut out, value);
    }
    out.push(_GED_LF);
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}
