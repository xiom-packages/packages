// XIOM -- xiom.geology: LAS 2.0 (Log ASCII Standard) well-log text parser
// Port task: replace the xiom.geology placeholder with a real, tested,
// pure-XIOM LAS 2.0 parser (sections ~V ~W ~C ~P ~A, opaque ~O).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: one LAS 2.0 document in, one LasLog value out (or a deterministic
// Err carrying a line number and a byte offset). The parser is stateless and
// byte-oriented; there is no partially initialized state and every accessor
// is total (out-of-range probes return empty/zero/null values).
//
// Numeric model: every value is a fixed-point scaled integer in thousandths
// (scale = 1000, see las_value_scale). Depth fields follow the units declared
// on the ~W STRT/STOP/STEP rows. Extra fraction digits beyond three are
// truncated toward zero ("1.2345" -> 1234, "-1.2345" -> -1234); there is no
// rounding and no Float64 anywhere. Row depth under WRAP YES is computed as
// strt + row * step with exact scaled-integer arithmetic (las_depth), while
// the depth column actually written on an unwrapped row is kept verbatim in
// las_depth_read (LAS 2.0 implies the same value; the parser does not force
// them to agree, but las_depth_is_expected answers the exact-integer check).
//
// Null model: a data cell is null when its token is empty/blank, or when its
// scaled value equals the NULL declaration of the ~W section (default
// -999.25 = -999250 when no NULL row is present). las_cell_value returns the
// raw scaled magnitude even for null cells; callers must consult
// las_cell_is_null (or las_cell).
//
// Line model: lines are split on LF, a trailing CR is stripped (CRLF and LF
// are equivalent). Within a section, a line whose first non-blank byte is '#'
// is a comment and is skipped; an inline '#' on a data row starts a trailing
// comment. Lines in ~O are preserved verbatim (comments included). Section
// letters and mnemonics are compared case-insensitively; curve names and well
// mnemonics are stored exactly as written. See SPEC.md for the full grammar,
// the section table and the error catalog.
//
// Language notes (XIOM v0.61.3), same discipline as xiom.nmea:
//   * free functions only: no self methods, no lambdas, no Vec[StructType];
//     variable-length data is carried by parallel Vec fields with mirrored
//     pushes;
//   * Str equality always goes through xiom.string.compare.str_compare (BUG
//     17: `==` on a Str read from a Vec[Str] element lowers to a pointer
//     comparison); Vec[Str]/Vec[Int] element reads bind a typed `let` first;
//   * Ok/Err for LasLog are constructed only in the leaf helpers _ok_log and
//     _err_log (constructing a Result inside a larger function miscompiles);
//   * all arithmetic is 64-bit signed integer math; no Vec[Float64];
//   * byte_at results are widened through _widen (mask 255) before arithmetic
//     and are never compared against a UInt8 constant >= 128;
//   * no function or variable is named `log`.

module xiom.geology

use xiom.string;
use xiom.string.compare;
use xiom.convert;
use xiom.math;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _GEO_SCALE: Int = 1000;
const _GEO_DEFAULT_NULL: Int = -999250;
const _GEO_HEAD_MAX: Int = 16;
const _GEO_UNIT_MAX: Int = 8;
const _GEO_MAG_DIV10: Int = 922337203685477580;
const _GEO_MAG_LAST: Int = 7;
const _GEO_INT_PART_MAX: Int = 9223372036854775;
const _GEO_ASCII_A: Int = 65;
const _GEO_ASCII_Z: Int = 90;
const _GEO_ASCII_ZERO: Int = 48;

const _GEO_TAB: UInt8 = 9u8;
const _GEO_LF: UInt8 = 10u8;
const _GEO_CR: UInt8 = 13u8;
const _GEO_SPACE: UInt8 = 32u8;
const _GEO_DQUOTE: UInt8 = 34u8;
const _GEO_HASH: UInt8 = 35u8;
const _GEO_SQUOTE: UInt8 = 39u8;
const _GEO_PLUS: UInt8 = 43u8;
const _GEO_MINUS: UInt8 = 45u8;
const _GEO_DOT: UInt8 = 46u8;
const _GEO_ZERO: UInt8 = 48u8;
const _GEO_NINE: UInt8 = 57u8;
const _GEO_COLON: UInt8 = 58u8;
const _GEO_UPPER_A: UInt8 = 65u8;
const _GEO_UPPER_Z: UInt8 = 90u8;
const _GEO_UNDERSCORE: UInt8 = 95u8;
const _GEO_LOWER_A: UInt8 = 97u8;
const _GEO_LOWER_Z: UInt8 = 122u8;
const _GEO_TILDE: UInt8 = 126u8;

// Section letters, lowered.
const _GEO_SEC_V: Int = 118;
const _GEO_SEC_W: Int = 119;
const _GEO_SEC_C: Int = 99;
const _GEO_SEC_P: Int = 112;
const _GEO_SEC_A: Int = 97;
const _GEO_SEC_O: Int = 111;

// Section ids.
const _GEO_SEC_NONE: Int = 0;
const _GEO_SEC_VERSION: Int = 1;
const _GEO_SEC_WELL: Int = 2;
const _GEO_SEC_CURVE: Int = 3;
const _GEO_SEC_PARAM: Int = 4;
const _GEO_SEC_ASCII: Int = 5;
const _GEO_SEC_OTHER: Int = 6;

// ---------------------------------------------------------------------------
// Public data model
// ---------------------------------------------------------------------------

/// A parsed LAS 2.0 document. Every numeric field is a fixed-point scaled
/// integer in thousandths (scale = 1000). The list fields are parallel
/// vectors: index i of each list describes the same curve, well or parameter
/// row. Data cells are row-major: cell (row, curve) lives at index
/// row * curve.len() + curve, with nulls mirroring cells one-to-one.
/// See SPEC.md section 4 for the field table.
pub type LasLog = {
  version: Str;
  wrap: Bool;
  strt: Int;
  stop: Int;
  step: Int;
  depth_unit: Str;
  null_value: Int;
  have_strt: Bool;
  have_stop: Bool;
  have_step: Bool;
  curve: Vec[Str];
  curve_unit: Vec[Str];
  curve_type: Vec[Str];
  curve_desc: Vec[Str];
  well: Vec[Str];
  well_unit: Vec[Str];
  well_value: Vec[Str];
  well_desc: Vec[Str];
  param: Vec[Str];
  param_unit: Vec[Str];
  param_value: Vec[Str];
  param_desc: Vec[Str];
  row_count: Int;
  cells: Vec[Int];
  nulls: Vec[Int];
  depths: Vec[Int];
  depths_read: Vec[Int];
  row_line: Vec[Int];
  other: Vec[Str];
}

/// One data cell: the scaled value plus its null flag. Null cells keep their
/// raw scaled magnitude; consumers must check is_null.
pub type LasCell = {
  value: Int;
  is_null: Bool;
}

// ---------------------------------------------------------------------------
// Internal parse carriers (ok = false plus safe defaults when not recognized)
// ---------------------------------------------------------------------------

type DefLine = {
  ok: Bool;
  mnem: Str;
  unit: Str;
  value: Str;
  desc: Str;
}

type CurveLine = {
  ok: Bool;
  name: Str;
  unit: Str;
  ctype: Str;
  desc: Str;
}

type ScaledParse = {
  ok: Bool;
  blank: Bool;
  value: Int;
}

type RowParse = {
  ok: Bool;
  empty: Bool;
  err: Str;
  depth_read: Int;
  tokens: Int;
  cells: Vec[Int];
  nulls: Vec[Int];
}

// ---------------------------------------------------------------------------
// Result constructors (compiler workaround; see the module header)
// ---------------------------------------------------------------------------

fn _ok_log(v: LasLog) -> Result[LasLog, Str] {
  return Ok(v);
}

fn _err_log(m: Str) -> Result[LasLog, Str] {
  return Err(m);
}

// ---------------------------------------------------------------------------
// Byte helpers
// ---------------------------------------------------------------------------

// Widen a byte to Int with an explicit 0xFF mask so bytes >= 128 never
// sign-extend (BUG: bare `as Int` on UInt8 >= 128).
fn _widen(b: UInt8) -> Int {
  return math.bit_and(b as Int, 255);
}

fn _is_space_byte(b: UInt8) -> Bool {
  if b == _GEO_SPACE { return true; }
  return b == _GEO_TAB;
}

fn _is_digit_byte(b: UInt8) -> Bool {
  return b >= _GEO_ZERO && b <= _GEO_NINE;
}

fn _is_letter_byte(b: UInt8) -> Bool {
  if b >= _GEO_UPPER_A && b <= _GEO_UPPER_Z { return true; }
  return b >= _GEO_LOWER_A && b <= _GEO_LOWER_Z;
}

// Mnemonic characters: ASCII letters, digits and '_'.
fn _is_mnem_byte(b: UInt8) -> Bool {
  if _is_letter_byte(b) { return true; }
  if _is_digit_byte(b) { return true; }
  return b == _GEO_UNDERSCORE;
}

// Lowered ASCII value of a byte (identity for non-letters).
fn _lower_i(b: UInt8) -> Int {
  let v = _widen(b);
  if v >= _GEO_ASCII_A && v <= _GEO_ASCII_Z { return v + 32; }
  return v;
}

// Case-insensitive Str comparison via str_compare_ignore_case.
fn _ci_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare_ignore_case(a, b) == 0;
}

// Exact Str equality via str_compare (never `==` on Str; BUG 17).
fn _str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Index of the first occurrence of target at or after `from`, or -1.
fn _find_byte(s: Str, from: Int, target: UInt8) -> Int {
  var i = from;
  while i < s.len() {
    if string.byte_at(s, i) == target { return i; }
    i = i + 1;
  }
  return -1;
}

// Index of the first non-space byte in [from, end), or -1 when all blank.
fn _first_nonspace(s: Str, from: Int, end: Int) -> Int {
  var i = from;
  while i < end {
    let b = string.byte_at(s, i);
    if !_is_space_byte(b) { return i; }
    i = i + 1;
  }
  return -1;
}

// Index of an end-of-token byte from `from` (space, tab or '#'), or -1.
fn _find_token_end(s: Str, from: Int, end: Int) -> Int {
  var i = from;
  while i < end {
    let b = string.byte_at(s, i);
    if _is_space_byte(b) { return i; }
    if b == _GEO_HASH { return i; }
    i = i + 1;
  }
  return -1;
}

// Trimmed slice of s[a, b); "" when the range is blank.
fn _trim_slice(s: Str, a: Int, b: Int) -> Str {
  var x = a;
  var y = b;
  while x < y && _is_space_byte(string.byte_at(s, x)) { x = x + 1; }
  while y > x && _is_space_byte(string.byte_at(s, y - 1)) { y = y - 1; }
  if y <= x { return ""; }
  return string.str_slice(s, x, y);
}

// End index (exclusive) of the leading mnemonic run of s[from, len).
fn _mnem_end(s: Str, from: Int) -> Int {
  var i = from;
  while i < s.len() {
    if !_is_mnem_byte(string.byte_at(s, i)) { break; }
    i = i + 1;
  }
  return i;
}

// Index of the first ':' outside quotes in s[from, end), or -1.
fn _unquoted_colon(s: Str, from: Int, end: Int) -> Int {
  var i = from;
  var q: UInt8 = 0u8;
  while i < end {
    let b = string.byte_at(s, i);
    if q == 0u8 {
      if b == _GEO_DQUOTE || b == _GEO_SQUOTE {
        q = b;
      } elif b == _GEO_COLON {
        return i;
      }
    } elif b == q {
      q = 0u8;
    }
    i = i + 1;
  }
  return -1;
}

// Whitespace-split tokens of s with surrounding quotes stripped; quoted
// tokens may contain spaces and colons. Used for header/definition lines.
fn _quote_tokens(s: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  let n = s.len();
  while i < n {
    let b = string.byte_at(s, i);
    if _is_space_byte(b) {
      i = i + 1;
    } elif b == _GEO_DQUOTE || b == _GEO_SQUOTE {
      let q = b;
      let start = i + 1;
      i = i + 1;
      while i < n {
        if string.byte_at(s, i) == q { break; }
        i = i + 1;
      }
      out.push(string.str_slice(s, start, i));
      if i < n { i = i + 1; }
    } else {
      let start = i;
      while i < n {
        let c = string.byte_at(s, i);
        if _is_space_byte(c) { break; }
        if c == _GEO_DQUOTE || c == _GEO_SQUOTE { break; }
        i = i + 1;
      }
      out.push(string.str_slice(s, start, i));
    }
  }
  return out;
}

// Join tokens[from..] with single spaces, skipping empty tokens.
fn _join_tokens(toks: Vec[Str], from: Int) -> Str {
  var out = "";
  var i = from;
  while i < toks.len() {
    let t: Str = toks[i];
    if t.len() > 0 {
      if out.len() > 0 { out = out + " "; }
      out = out + t;
    }
    i = i + 1;
  }
  return out;
}

// A unit-shaped token: 1..8 bytes, at least one letter, no whitespace, and
// not itself a number ("M", "GAPI", "G/C3", "US/F", "OHMM").
fn _unit_like(tok: Str) -> Bool {
  let n = tok.len();
  if n < 1 || n > _GEO_UNIT_MAX { return false; }
  var letters = 0;
  var i = 0;
  while i < n {
    let b = string.byte_at(tok, i);
    if _is_letter_byte(b) { letters = letters + 1; }
    elif _is_digit_byte(b) { }
    elif b == _GEO_DOT { }
    elif b == _GEO_MINUS { }
    elif b == 47u8 { }
    elif b == 37u8 { }
    elif b == _GEO_UNDERSCORE { }
    else { return false; }
    i = i + 1;
  }
  if letters == 0 { return false; }
  let num = _parse_scaled(tok);
  return !num.ok;
}

// ---------------------------------------------------------------------------
// Scaled fixed-point parsing
// ---------------------------------------------------------------------------

fn _scaled_miss() -> ScaledParse {
  return ScaledParse{ ok: false; blank: false; value: 0 };
}

fn _scaled_blank() -> ScaledParse {
  return ScaledParse{ ok: false; blank: true; value: 0 };
}

// Parse "[+-]?digits[.digits]" into thousandths. Extra fraction digits are
// truncated toward zero; an empty token is `blank`. No exponent notation.
fn _parse_scaled(tok: Str) -> ScaledParse {
  let n = tok.len();
  if n == 0 { return _scaled_blank(); }
  var i = 0;
  var neg = false;
  let first = string.byte_at(tok, 0);
  if first == _GEO_MINUS {
    neg = true;
    i = 1;
  } elif first == _GEO_PLUS {
    i = 1;
  }
  var int_mag = 0;
  var frac_mag = 0;
  var frac_digits = 0;
  var seen_digit = false;
  var seen_dot = false;
  var bad = false;
  while i < n {
    let b = string.byte_at(tok, i);
    if _is_digit_byte(b) {
      let d = _widen(b) - _GEO_ASCII_ZERO;
      seen_digit = true;
      if seen_dot {
        if frac_digits < 3 {
          frac_mag = frac_mag * 10 + d;
          frac_digits = frac_digits + 1;
        }
      } else {
        if int_mag > _GEO_MAG_DIV10 { return _scaled_miss(); }
        if int_mag == _GEO_MAG_DIV10 && d > _GEO_MAG_LAST { return _scaled_miss(); }
        int_mag = int_mag * 10 + d;
      }
    } elif b == _GEO_DOT {
      if seen_dot { bad = true; }
      seen_dot = true;
    } else {
      bad = true;
    }
    i = i + 1;
  }
  if bad || !seen_digit { return _scaled_miss(); }
  if int_mag > _GEO_INT_PART_MAX { return _scaled_miss(); }
  while frac_digits < 3 {
    frac_mag = frac_mag * 10;
    frac_digits = frac_digits + 1;
  }
  var mag = int_mag * _GEO_SCALE + frac_mag;
  if neg { mag = 0 - mag; }
  return ScaledParse{ ok: true; blank: false; value: mag };
}

// ---------------------------------------------------------------------------
// Header-line recognizers
// ---------------------------------------------------------------------------

fn _no_def() -> DefLine {
  return DefLine{ ok: false; mnem: ""; unit: ""; value: ""; desc: "" };
}

fn _no_curve() -> CurveLine {
  return CurveLine{ ok: false; name: ""; unit: ""; ctype: ""; desc: "" };
}

// Definition line "MNEM.UNIT VALUE : DESCRIPTION" (units and dots in values
// tolerated). The value is the last token when the last token is numeric,
// otherwise the remaining text joined with single spaces.
fn _parse_def_line(s: Str, from: Int, end: Int) -> DefLine {
  let cut = _unquoted_colon(s, from, end);
  var head_end = end;
  if cut >= 0 { head_end = cut; }
  let head = _trim_slice(s, from, head_end);
  let m_end = _mnem_end(head, 0);
  if m_end <= 0 { return _no_def(); }
  let mnem = string.str_slice(head, 0, m_end);
  var rest_start = m_end;
  if rest_start < head.len() && string.byte_at(head, rest_start) == _GEO_DOT {
    rest_start = rest_start + 1;
  }
  var rest = _trim_slice(head, rest_start, head.len());
  if rest.len() > 0 {
    let r0 = string.byte_at(rest, 0);
    if r0 == _GEO_DOT {
      if rest.len() == 1 {
        rest = "";
      } else {
        let r1 = string.byte_at(rest, 1);
        if !_is_digit_byte(r1) { rest = _trim_slice(rest, 1, rest.len()); }
      }
    }
  }
  let toks = _quote_tokens(rest);
  var unit = "";
  var value = "";
  let nt = toks.len();
  if nt == 1 {
    let t0: Str = toks[0];
    value = t0;
  } elif nt >= 2 {
    let t0: Str = toks[0];
    let tl: Str = toks[nt - 1];
    let num = _parse_scaled(tl);
    if num.ok && _unit_like(t0) {
      unit = t0;
      value = tl;
    } elif num.ok {
      value = tl;
    } else {
      value = _join_tokens(toks, 0);
    }
  }
  var desc = "";
  if cut >= 0 { desc = _trim_slice(s, cut + 1, end); }
  return DefLine{ ok: true; mnem: mnem; unit: unit; value: value; desc: desc };
}

// Curve line "NAME.UNIT [TYPE/API] : DESCRIPTION". The first token after the
// mnemonic is the unit when it is unit-shaped; all remaining tokens form the
// type/item text (LAS 2.0 API codes such as "00 000 00 00" land here).
fn _parse_curve_line(s: Str, from: Int, end: Int) -> CurveLine {
  let cut = _unquoted_colon(s, from, end);
  var head_end = end;
  if cut >= 0 { head_end = cut; }
  let head = _trim_slice(s, from, head_end);
  let m_end = _mnem_end(head, 0);
  if m_end <= 0 { return _no_curve(); }
  let name = string.str_slice(head, 0, m_end);
  var rest_start = m_end;
  if rest_start < head.len() && string.byte_at(head, rest_start) == _GEO_DOT {
    rest_start = rest_start + 1;
  }
  var rest = _trim_slice(head, rest_start, head.len());
  if rest.len() > 0 {
    let r0 = string.byte_at(rest, 0);
    if r0 == _GEO_DOT {
      if rest.len() == 1 {
        rest = "";
      } else {
        let r1 = string.byte_at(rest, 1);
        if !_is_digit_byte(r1) { rest = _trim_slice(rest, 1, rest.len()); }
      }
    }
  }
  let toks = _quote_tokens(rest);
  var unit = "";
  var ctype = "";
  let nt = toks.len();
  if nt == 1 {
    let t0: Str = toks[0];
    unit = t0;
  } elif nt >= 2 {
    let t0: Str = toks[0];
    if _unit_like(t0) {
      unit = t0;
      ctype = _join_tokens(toks, 1);
    } else {
      ctype = _join_tokens(toks, 0);
    }
  }
  var desc = "";
  if cut >= 0 { desc = _trim_slice(s, cut + 1, end); }
  return CurveLine{ ok: true; name: name; unit: unit; ctype: ctype; desc: desc };
}

// First 16 bytes of a trimmed header line, for the unknown-section message.
fn _head_text(s: Str, from: Int, end: Int) -> Str {
  let a = _first_nonspace(s, from, end);
  if a < 0 { return ""; }
  var b = end;
  while b > a && _is_space_byte(string.byte_at(s, b - 1)) { b = b - 1; }
  if b - a > _GEO_HEAD_MAX { b = a + _GEO_HEAD_MAX; }
  return string.str_slice(s, a, b);
}

// ---------------------------------------------------------------------------
// Data rows
// ---------------------------------------------------------------------------

// Tokenize one data line: whitespace-separated runs, inline '#' comments,
// surrounding quotes stripped from each token. Absolute byte offsets of the
// token starts are mirrored into out_offs.
fn _row_tokens(s: Str, from: Int, end: Int, out_texts: &mut Vec[Str], out_offs: &mut Vec[Int]) {
  var i = from;
  while i < end {
    let b = string.byte_at(s, i);
    if _is_space_byte(b) {
      i = i + 1;
    } elif b == _GEO_HASH {
      return;
    } elif b == _GEO_DQUOTE || b == _GEO_SQUOTE {
      let q = b;
      let start = i + 1;
      var j = start;
      while j < end {
        if string.byte_at(s, j) == q { break; }
        j = j + 1;
      }
      out_texts.push(string.str_slice(s, start, j));
      out_offs.push(i);
      if j < end { i = j + 1; } else { i = j; }
    } else {
      let start = i;
      var j = i;
      while j < end {
        let c = string.byte_at(s, j);
        if _is_space_byte(c) { break; }
        if c == _GEO_HASH { break; }
        j = j + 1;
      }
      var a = start;
      var z = j;
      while a < z {
        let c0 = string.byte_at(s, a);
        if c0 != _GEO_DQUOTE && c0 != _GEO_SQUOTE { break; }
        a = a + 1;
      }
      while z > a {
        let c1 = string.byte_at(s, z - 1);
        if c1 != _GEO_DQUOTE && c1 != _GEO_SQUOTE { break; }
        z = z - 1;
      }
      out_texts.push(string.str_slice(s, a, z));
      out_offs.push(start);
      i = j;
    }
  }
}

// Parse one data row into fresh cells/nulls vectors. A token that is empty is
// null with value 0; a token equal to the NULL declaration is null with its
// raw scaled magnitude; anything else must be a scaled number.
//
// Row shape: WRAP YES rows carry exactly curve_count values (depth implied).
// WRAP NO rows carry the depth first; the first data row fixes whether the
// depth token is a dedicated leading column (curve_count + 1 tokens) or the
// value of the first curve (curve_count tokens, the conventional LAS layout
// where DEPT is listed in ~C). Later rows must match that count exactly.
fn _parse_row(s: Str, pos: Int, line_end: Int, line_no: Int, curve_count: Int, wrap: Bool, null_value: Int, row_expected: Int) -> RowParse {
  var toks = Vec[Str].new();
  var offs = Vec[Int].new();
  _row_tokens(s, pos, line_end, &mut toks, &mut offs);
  var cells = Vec[Int].new();
  var nulls = Vec[Int].new();
  let nt = toks.len();
  if nt == 0 {
    return RowParse{ ok: true; empty: true; err: ""; depth_read: -1; tokens: 0; cells: cells; nulls: nulls };
  }
  var expected = 0;
  var have_conv = false;
  if wrap {
    expected = curve_count;
    have_conv = true;
  } elif row_expected >= 0 {
    expected = row_expected;
    have_conv = true;
  }
  if have_conv {
    if nt != expected {
      return RowParse{ ok: false; empty: false;
        err: _err_at("ragged row: expected " + convert.int_to_string(expected) + " values, got " + convert.int_to_string(nt), line_no, pos);
        depth_read: -1; tokens: nt; cells: cells; nulls: nulls };
    }
  } else {
    if nt != curve_count && nt != curve_count + 1 {
      return RowParse{ ok: false; empty: false;
        err: _err_at("ragged row: expected " + convert.int_to_string(curve_count) + " or " + convert.int_to_string(curve_count + 1) + " values, got " + convert.int_to_string(nt), line_no, pos);
        depth_read: -1; tokens: nt; cells: cells; nulls: nulls };
    }
  }
  var depth_read = -1;
  var base = 0;
  if !wrap {
    let dt: Str = toks[0];
    let dp = _parse_scaled(dt);
    if dp.blank || !dp.ok {
      let doff: Int = offs[0];
      return RowParse{ ok: false; empty: false;
        err: _err_at("invalid depth token: " + dt, line_no, doff);
        depth_read: -1; tokens: nt; cells: cells; nulls: nulls };
    }
    depth_read = dp.value;
    base = nt - curve_count;
  }
  var k = 0;
  while k < curve_count {
    let tok: Str = toks[base + k];
    let tp = _parse_scaled(tok);
    if tp.blank {
      cells.push(0);
      nulls.push(1);
    } elif !tp.ok {
      let toff: Int = offs[base + k];
      return RowParse{ ok: false; empty: false;
        err: _err_at("invalid numeric token: " + tok, line_no, toff);
        depth_read: depth_read; tokens: nt; cells: cells; nulls: nulls };
    } else {
      cells.push(tp.value);
      if tp.value == null_value { nulls.push(1); } else { nulls.push(0); }
    }
    k = k + 1;
  }
  return RowParse{ ok: true; empty: false; err: ""; depth_read: depth_read; tokens: nt; cells: cells; nulls: nulls };
}

// ---------------------------------------------------------------------------
// Error message helpers
// ---------------------------------------------------------------------------

// Canonical error text: "geology: <msg> at line <1-based> offset <0-based>".
fn _err_at(msg: Str, line: Int, off: Int) -> Str {
  return "geology: " + msg + " at line " + convert.int_to_string(line) + " offset " + convert.int_to_string(off);
}

// Index of needle in haystack at or after `from`, or -1.
fn _find_sub(s: Str, needle: Str, from: Int) -> Int {
  let n = s.len();
  let m = needle.len();
  if m == 0 || m > n { return -1; }
  var i = from;
  while i + m <= n {
    var j = 0;
    var hit = true;
    while j < m {
      if string.byte_at(s, i + j) != string.byte_at(needle, j) { hit = false; break; }
      j = j + 1;
    }
    if hit { return i; }
    i = i + 1;
  }
  return -1;
}

// Decimal run at s[from..]; -1 when there is no digit there.
fn _digits_after(s: Str, from: Int) -> Int {
  var i = from;
  var acc = 0;
  var seen = false;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if !_is_digit_byte(b) { break; }
    acc = acc * 10 + (_widen(b) - _GEO_ASCII_ZERO);
    seen = true;
    i = i + 1;
  }
  if !seen { return -1; }
  return acc;
}

/// Line number carried by a canonical geology error message, or -1 when the
/// message carries none ("... at line 12 offset 30" -> 12).
/// Complexity: O(len(e)).
pub fn geology_error_line(e: Str) -> Int {
  let p = _find_sub(e, " at line ", 0);
  if p < 0 { return -1; }
  return _digits_after(e, p + 9);
}

/// Byte offset carried by a canonical geology error message, or -1 when the
/// message carries none ("... at line 12 offset 30" -> 30).
/// Complexity: O(len(e)).
pub fn geology_error_offset(e: Str) -> Int {
  let p = _find_sub(e, " offset ", 0);
  if p < 0 { return -1; }
  return _digits_after(e, p + 8);
}

// ---------------------------------------------------------------------------
// Main parser
// ---------------------------------------------------------------------------

/// Parse one LAS 2.0 document.
/// Grammar: lines split on LF (a trailing CR is stripped); optional preamble
/// text before the first section is ignored; sections start with '~' followed
/// by V/W/C/P/A/O (case-insensitive, first letter only) and run until the
/// next section header. '#'-prefixed lines are comments (except inside ~O,
/// where every line is preserved verbatim). WRAP YES data lines carry exactly
/// one value per curve (depth implied by strt + row * step). WRAP NO data
/// lines carry the depth first: either curve_count tokens, where the first
/// curve (conventionally DEPT) doubles as the depth column, or curve_count + 1
/// tokens, where the leading token is a dedicated depth column; the first
/// data row fixes which of the two shapes the file uses and later rows must
/// match it. See SPEC.md section 2.
/// Returns: Ok(LasLog) when the document has a non-empty ~C section and every
/// definition line and data row parses.
/// Error case: Err("geology: <reason> at line L offset B") -- missing ~C,
/// empty ~C, unknown or duplicated section, invalid definition line, invalid
/// WRAP value, bad STRT/STOP/STEP/NULL number, ragged row (wrong token count),
/// blank or non-numeric depth token, non-numeric cell token. L is 1-based;
/// B is a 0-based byte offset (line start for line-level errors, token start
/// for token-level errors).
/// Complexity: O(len(text)) time, O(cells) memory.
pub fn las_parse(text: Str) -> Result[LasLog, Str] {
  var version = "";
  var wrap = false;
  var strt = 0;
  var stop = 0;
  var step = 0;
  var depth_unit = "";
  var null_value = _GEO_DEFAULT_NULL;
  var have_strt = false;
  var have_stop = false;
  var have_step = false;
  var saw_v = false;
  var saw_w = false;
  var saw_c = false;
  var saw_p = false;
  var c_line = 0;
  var c_off = 0;
  var section = _GEO_SEC_NONE;
  var curve_count = 0;
  var row_count = 0;
  var row_expected = -1;
  var curve = Vec[Str].new();
  var curve_unit = Vec[Str].new();
  var curve_type = Vec[Str].new();
  var curve_desc = Vec[Str].new();
  var well = Vec[Str].new();
  var well_unit = Vec[Str].new();
  var well_value = Vec[Str].new();
  var well_desc = Vec[Str].new();
  var param = Vec[Str].new();
  var param_unit = Vec[Str].new();
  var param_value = Vec[Str].new();
  var param_desc = Vec[Str].new();
  var cells = Vec[Int].new();
  var nulls = Vec[Int].new();
  var depths = Vec[Int].new();
  var depths_read = Vec[Int].new();
  var row_line = Vec[Int].new();
  var other = Vec[Str].new();
  let total = text.len();
  var pos = 0;
  var line_no = 1;
  while pos < total {
    let eol = _find_byte(text, pos, _GEO_LF);
    var line_end = total;
    var next_pos = total;
    if eol >= 0 {
      line_end = eol;
      next_pos = eol + 1;
    }
    if line_end > pos && string.byte_at(text, line_end - 1) == _GEO_CR {
      line_end = line_end - 1;
    }
    let s0 = _first_nonspace(text, pos, line_end);
    var handled = false;
    if s0 >= 0 && string.byte_at(text, s0) == _GEO_TILDE {
      let h = _first_nonspace(text, s0 + 1, line_end);
      if h < 0 {
        return _err_log(_err_at("empty section header", line_no, pos));
      }
      let sec_letter = _lower_i(string.byte_at(text, h));
      if sec_letter == _GEO_SEC_V {
        if saw_v { return _err_log(_err_at("duplicate ~V section", line_no, pos)); }
        saw_v = true;
        section = _GEO_SEC_VERSION;
      } elif sec_letter == _GEO_SEC_W {
        if saw_w { return _err_log(_err_at("duplicate ~W section", line_no, pos)); }
        saw_w = true;
        section = _GEO_SEC_WELL;
      } elif sec_letter == _GEO_SEC_C {
        if saw_c { return _err_log(_err_at("duplicate ~C section", line_no, pos)); }
        saw_c = true;
        c_line = line_no;
        c_off = pos;
        section = _GEO_SEC_CURVE;
      } elif sec_letter == _GEO_SEC_P {
        if saw_p { return _err_log(_err_at("duplicate ~P section", line_no, pos)); }
        saw_p = true;
        section = _GEO_SEC_PARAM;
      } elif sec_letter == _GEO_SEC_A {
        section = _GEO_SEC_ASCII;
      } elif sec_letter == _GEO_SEC_O {
        section = _GEO_SEC_OTHER;
      } else {
        return _err_log(_err_at("unknown section: " + _head_text(text, s0, line_end), line_no, pos));
      }
      handled = true;
    }
    if !handled {
      if section == _GEO_SEC_OTHER {
        other.push(string.str_slice(text, pos, line_end));
      } elif s0 < 0 {
        handled = true;
      } elif string.byte_at(text, s0) == _GEO_HASH {
        handled = true;
      } elif section == _GEO_SEC_NONE {
        handled = true;
      } elif section == _GEO_SEC_VERSION {
        let def = _parse_def_line(text, pos, line_end);
        if !def.ok { return _err_log(_err_at("invalid definition", line_no, pos)); }
        if _ci_eq(def.mnem, "VERS") {
          version = def.value;
        } elif _ci_eq(def.mnem, "WRAP") {
          if _ci_eq(def.value, "YES") {
            wrap = true;
          } elif _ci_eq(def.value, "NO") {
            wrap = false;
          } else {
            return _err_log(_err_at("invalid WRAP value: " + def.value, line_no, pos));
          }
        }
      } elif section == _GEO_SEC_WELL {
        let def = _parse_def_line(text, pos, line_end);
        if !def.ok { return _err_log(_err_at("invalid definition", line_no, pos)); }
        if _ci_eq(def.mnem, "STRT") {
          let v = _parse_scaled(def.value);
          if v.blank || !v.ok {
            return _err_log(_err_at("invalid STRT value: " + def.value, line_no, pos));
          }
          strt = v.value;
          have_strt = true;
          if !_str_eq(def.unit, "") { depth_unit = def.unit; }
        } elif _ci_eq(def.mnem, "STOP") {
          let v = _parse_scaled(def.value);
          if v.blank || !v.ok {
            return _err_log(_err_at("invalid STOP value: " + def.value, line_no, pos));
          }
          stop = v.value;
          have_stop = true;
          if !_str_eq(def.unit, "") { depth_unit = def.unit; }
        } elif _ci_eq(def.mnem, "STEP") {
          let v = _parse_scaled(def.value);
          if v.blank || !v.ok {
            return _err_log(_err_at("invalid STEP value: " + def.value, line_no, pos));
          }
          step = v.value;
          have_step = true;
          if !_str_eq(def.unit, "") { depth_unit = def.unit; }
        } elif _ci_eq(def.mnem, "NULL") {
          let v = _parse_scaled(def.value);
          if v.blank || !v.ok {
            return _err_log(_err_at("invalid NULL value: " + def.value, line_no, pos));
          }
          null_value = v.value;
        } else {
          well.push(def.mnem);
          well_unit.push(def.unit);
          well_value.push(def.value);
          well_desc.push(def.desc);
        }
      } elif section == _GEO_SEC_CURVE {
        let cl = _parse_curve_line(text, pos, line_end);
        if !cl.ok { return _err_log(_err_at("invalid curve definition", line_no, pos)); }
        curve.push(cl.name);
        curve_unit.push(cl.unit);
        curve_type.push(cl.ctype);
        curve_desc.push(cl.desc);
        curve_count = curve_count + 1;
      } elif section == _GEO_SEC_PARAM {
        let def = _parse_def_line(text, pos, line_end);
        if !def.ok { return _err_log(_err_at("invalid definition", line_no, pos)); }
        param.push(def.mnem);
        param_unit.push(def.unit);
        param_value.push(def.value);
        param_desc.push(def.desc);
      } elif section == _GEO_SEC_ASCII {
        if curve_count == 0 {
          return _err_log(_err_at("missing ~C curve section", line_no, pos));
        }
        let rp = _parse_row(text, pos, line_end, line_no, curve_count, wrap, null_value, row_expected);
        if !rp.ok { return _err_log(rp.err); }
        if !rp.empty {
          if row_expected < 0 { row_expected = rp.tokens; }
          var k = 0;
          while k < rp.cells.len() {
            let cv: Int = rp.cells[k];
            cells.push(cv);
            k = k + 1;
          }
          k = 0;
          while k < rp.nulls.len() {
            let nv: Int = rp.nulls[k];
            nulls.push(nv);
            k = k + 1;
          }
          depths_read.push(rp.depth_read);
          if have_strt && have_step {
            depths.push(strt + row_count * step);
          } else {
            depths.push(-1);
          }
          row_line.push(line_no);
          row_count = row_count + 1;
        }
      }
    }
    pos = next_pos;
    line_no = line_no + 1;
  }
  if !saw_c {
    return _err_log(_err_at("missing ~C curve section", line_no, total));
  }
  if curve_count == 0 {
    return _err_log(_err_at("empty ~C curve section", c_line, c_off));
  }
  return _ok_log(LasLog{
    version: version;
    wrap: wrap;
    strt: strt;
    stop: stop;
    step: step;
    depth_unit: depth_unit;
    null_value: null_value;
    have_strt: have_strt;
    have_stop: have_stop;
    have_step: have_step;
    curve: curve;
    curve_unit: curve_unit;
    curve_type: curve_type;
    curve_desc: curve_desc;
    well: well;
    well_unit: well_unit;
    well_value: well_value;
    well_desc: well_desc;
    param: param;
    param_unit: param_unit;
    param_value: param_value;
    param_desc: param_desc;
    row_count: row_count;
    cells: cells;
    nulls: nulls;
    depths: depths;
    depths_read: depths_read;
    row_line: row_line;
    other: other;
  });
}

// ---------------------------------------------------------------------------
// Accessors
// ---------------------------------------------------------------------------

/// Value scale: 1000 (thousandths). Complexity: O(1).
pub fn las_value_scale() -> Int {
  return _GEO_SCALE;
}

/// VERS value from ~V ("" when the section or row is absent).
/// Complexity: O(1).
pub fn las_version(r: &LasLog) -> Str {
  let v: Str = r.version;
  return v;
}

/// True when WRAP was declared YES (default false). Complexity: O(1).
pub fn las_wrap(r: &LasLog) -> Bool {
  return r.wrap;
}

/// STRT in scaled thousandths (0 when absent; check las_has_start).
/// Complexity: O(1).
pub fn las_start_depth(r: &LasLog) -> Int {
  return r.strt;
}

/// STOP in scaled thousandths (0 when absent; check las_has_stop).
/// Complexity: O(1).
pub fn las_stop_depth(r: &LasLog) -> Int {
  return r.stop;
}

/// STEP in scaled thousandths (0 when absent; check las_has_step).
/// Complexity: O(1).
pub fn las_step(r: &LasLog) -> Int {
  return r.step;
}

/// Depth unit declared on the last STRT/STOP/STEP row with a unit ("" when
/// none was declared). Complexity: O(1).
pub fn las_depth_unit(r: &LasLog) -> Str {
  let v: Str = r.depth_unit;
  return v;
}

/// True when a STRT row was present. Complexity: O(1).
pub fn las_has_start(r: &LasLog) -> Bool {
  return r.have_strt;
}

/// True when a STOP row was present. Complexity: O(1).
pub fn las_has_stop(r: &LasLog) -> Bool {
  return r.have_stop;
}

/// True when a STEP row was present. Complexity: O(1).
pub fn las_has_step(r: &LasLog) -> Bool {
  return r.have_step;
}

/// True when depth arithmetic (strt + row * step) is available.
/// Complexity: O(1).
pub fn las_depth_known(r: &LasLog) -> Bool {
  return r.have_strt && r.have_step;
}

/// The NULL declaration in scaled thousandths; -999250 (-999.25) when no
/// NULL row was present. Complexity: O(1).
pub fn las_null_value(r: &LasLog) -> Int {
  return r.null_value;
}

/// Number of ~C curves. Complexity: O(1).
pub fn las_curve_count(r: &LasLog) -> Int {
  return r.curve.len();
}

/// Curve name as written ("" when out of range). Complexity: O(1).
pub fn las_curve_name(r: &LasLog, i: Int) -> Str {
  if i < 0 || i >= r.curve.len() { return ""; }
  let v: Str = r.curve[i];
  return v;
}

/// Curve unit as written ("" when out of range). Complexity: O(1).
pub fn las_curve_unit(r: &LasLog, i: Int) -> Str {
  if i < 0 || i >= r.curve_unit.len() { return ""; }
  let v: Str = r.curve_unit[i];
  return v;
}

/// Curve data-type/API text, the tokens between the unit and the colon
/// ("" when out of range). Complexity: O(1).
pub fn las_curve_type(r: &LasLog, i: Int) -> Str {
  if i < 0 || i >= r.curve_type.len() { return ""; }
  let v: Str = r.curve_type[i];
  return v;
}

/// Curve description, the text after the colon ("" when out of range).
/// Complexity: O(1).
pub fn las_curve_desc(r: &LasLog, i: Int) -> Str {
  if i < 0 || i >= r.curve_desc.len() { return ""; }
  let v: Str = r.curve_desc[i];
  return v;
}

/// Index of the first curve whose name equals `name` ignoring case, or -1.
/// Complexity: O(curve count).
pub fn las_curve_index(r: &LasLog, name: Str) -> Int {
  var i = 0;
  while i < r.curve.len() {
    let v: Str = r.curve[i];
    if _ci_eq(v, name) { return i; }
    i = i + 1;
  }
  return -1;
}

/// Number of data rows. Complexity: O(1).
pub fn las_row_count(r: &LasLog) -> Int {
  return r.row_count;
}

/// Scaled value of cell (row, curve); 0 when out of range (and the null flag
/// is then true -- check with las_cell_is_null or las_cell).
/// Complexity: O(1).
pub fn las_cell_value(r: &LasLog, row: Int, curve: Int) -> Int {
  if row < 0 || row >= r.row_count { return 0; }
  if curve < 0 || curve >= r.curve.len() { return 0; }
  let idx = row * r.curve.len() + curve;
  if idx < 0 || idx >= r.cells.len() { return 0; }
  let v: Int = r.cells[idx];
  return v;
}

/// Null flag of cell (row, curve); true when out of range (there is no such
/// cell), when the token was blank, or when the value equals the NULL
/// declaration. Complexity: O(1).
pub fn las_cell_is_null(r: &LasLog, row: Int, curve: Int) -> Bool {
  if row < 0 || row >= r.row_count { return true; }
  if curve < 0 || curve >= r.curve.len() { return true; }
  let idx = row * r.curve.len() + curve;
  if idx < 0 || idx >= r.nulls.len() { return true; }
  let v: Int = r.nulls[idx];
  return v == 1;
}

/// Cell (row, curve) as a LasCell; out-of-range probes return
/// LasCell{ value: 0; is_null: true }.
/// Complexity: O(1).
pub fn las_cell(r: &LasLog, row: Int, curve: Int) -> LasCell {
  if row < 0 || row >= r.row_count {
    return LasCell{ value: 0; is_null: true };
  }
  if curve < 0 || curve >= r.curve.len() {
    return LasCell{ value: 0; is_null: true };
  }
  let idx = row * r.curve.len() + curve;
  if idx < 0 || idx >= r.cells.len() {
    return LasCell{ value: 0; is_null: true };
  }
  let v: Int = r.cells[idx];
  let n: Int = r.nulls[idx];
  var isn = false;
  if n == 1 { isn = true; }
  return LasCell{ value: v; is_null: isn };
}

/// Canonical depth of a row in scaled thousandths: strt + row * step under
/// exact integer arithmetic; -1 when STRT/STEP are missing or the row is out
/// of range. Complexity: O(1).
pub fn las_depth(r: &LasLog, row: Int) -> Int {
  if row < 0 || row >= r.row_count { return -1; }
  let v: Int = r.depths[row];
  return v;
}

/// Depth column as actually written on the row, in scaled thousandths; -1
/// for wrapped rows (depth implied) and out-of-range probes.
/// Complexity: O(1).
pub fn las_depth_read(r: &LasLog, row: Int) -> Int {
  if row < 0 || row >= r.row_count { return -1; }
  let v: Int = r.depths_read[row];
  return v;
}

/// Exact scaled-integer check that `depth` equals strt + row * step (false
/// when STRT/STEP are missing or the row is out of range). No tolerance.
/// Complexity: O(1).
pub fn las_depth_is_expected(r: &LasLog, row: Int, depth: Int) -> Bool {
  if !r.have_strt || !r.have_step { return false; }
  if row < 0 || row >= r.row_count { return false; }
  return depth == r.strt + row * r.step;
}

/// 1-based physical line of data row (the line the row started on); -1 when
/// out of range. Complexity: O(1).
pub fn las_row_line(r: &LasLog, row: Int) -> Int {
  if row < 0 || row >= r.row_count { return -1; }
  let v: Int = r.row_line[row];
  return v;
}

/// Number of ~W well rows (excluding STRT/STOP/STEP/NULL).
/// Complexity: O(1).
pub fn las_well_count(r: &LasLog) -> Int {
  return r.well.len();
}

/// Well mnemonic as written ("" when out of range). Complexity: O(1).
pub fn las_well_mnemonic(r: &LasLog, i: Int) -> Str {
  if i < 0 || i >= r.well.len() { return ""; }
  let v: Str = r.well[i];
  return v;
}

/// Well row unit ("" when out of range). Complexity: O(1).
pub fn las_well_unit(r: &LasLog, i: Int) -> Str {
  if i < 0 || i >= r.well_unit.len() { return ""; }
  let v: Str = r.well_unit[i];
  return v;
}

/// Well row value as written ("" when out of range). Complexity: O(1).
pub fn las_well_value(r: &LasLog, i: Int) -> Str {
  if i < 0 || i >= r.well_value.len() { return ""; }
  let v: Str = r.well_value[i];
  return v;
}

/// Well row description ("" when out of range). Complexity: O(1).
pub fn las_well_desc(r: &LasLog, i: Int) -> Str {
  if i < 0 || i >= r.well_desc.len() { return ""; }
  let v: Str = r.well_desc[i];
  return v;
}

/// Value of the first ~W row whose mnemonic equals `mnem` ignoring case
/// ("" when absent). Complexity: O(well count).
pub fn las_well_lookup(r: &LasLog, mnem: Str) -> Str {
  var i = 0;
  while i < r.well.len() {
    let m: Str = r.well[i];
    if _ci_eq(m, mnem) {
      let v: Str = r.well_value[i];
      return v;
    }
    i = i + 1;
  }
  return "";
}

/// Number of ~P parameter rows. Complexity: O(1).
pub fn las_param_count(r: &LasLog) -> Int {
  return r.param.len();
}

/// Parameter mnemonic as written ("" when out of range). Complexity: O(1).
pub fn las_param_mnemonic(r: &LasLog, i: Int) -> Str {
  if i < 0 || i >= r.param.len() { return ""; }
  let v: Str = r.param[i];
  return v;
}

/// Parameter unit ("" when out of range). Complexity: O(1).
pub fn las_param_unit(r: &LasLog, i: Int) -> Str {
  if i < 0 || i >= r.param_unit.len() { return ""; }
  let v: Str = r.param_unit[i];
  return v;
}

/// Parameter value as written ("" when out of range). Complexity: O(1).
pub fn las_param_value(r: &LasLog, i: Int) -> Str {
  if i < 0 || i >= r.param_value.len() { return ""; }
  let v: Str = r.param_value[i];
  return v;
}

/// Parameter description ("" when out of range). Complexity: O(1).
pub fn las_param_desc(r: &LasLog, i: Int) -> Str {
  if i < 0 || i >= r.param_desc.len() { return ""; }
  let v: Str = r.param_desc[i];
  return v;
}

/// Value of the first ~P row whose mnemonic equals `mnem` ignoring case
/// ("" when absent). Complexity: O(param count).
pub fn las_param_lookup(r: &LasLog, mnem: Str) -> Str {
  var i = 0;
  while i < r.param.len() {
    let m: Str = r.param[i];
    if _ci_eq(m, mnem) {
      let v: Str = r.param_value[i];
      return v;
    }
    i = i + 1;
  }
  return "";
}

/// Number of ~O lines preserved verbatim. Complexity: O(1).
pub fn las_other_count(r: &LasLog) -> Int {
  return r.other.len();
}

/// ~O line i, verbatim except for a stripped CR ("" when out of range).
/// Complexity: O(1).
pub fn las_other_line(r: &LasLog, i: Int) -> Str {
  if i < 0 || i >= r.other.len() { return ""; }
  let v: Str = r.other[i];
  return v;
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

fn _pad3(n: Int) -> Str {
  if n < 10 { return "00" + convert.int_to_string(n); }
  if n < 100 { return "0" + convert.int_to_string(n); }
  return convert.int_to_string(n);
}

/// Render a scaled thousandths integer as a signed fixed-point decimal:
/// -999250 -> "-999.250", 45500 -> "45.500", 0 -> "0.000".
/// Complexity: O(len(result)).
pub fn las_scaled_to_string(v: Int) -> Str {
  var neg = false;
  var mag = v;
  if v < 0 {
    neg = true;
    mag = 0 - v;
  }
  let whole = mag / _GEO_SCALE;
  let frac = mag % _GEO_SCALE;
  var out = convert.int_to_string(whole) + "." + _pad3(frac);
  if neg { out = "-" + out; }
  return out;
}
