// XIOM -- xiom.roman: Roman numeral parsing, formatting and canonical validation
// Greenfield package (text/data); pure XIOM, no FFI.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: the standard Roman numeral system over 1..3999. Symbols are the
// seven ASCII letters I, V, X, L, C, D, M in either case; values are formed
// additively (VIII = 5 + 3) and subtractively (IV = 5 - 1) inside the
// canonical grammar
//   M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})
//
// roman_parse is case-insensitive but canonical: it validates the letters,
// evaluates the numeral right to left and then requires the input to spell
// (ignoring case) the canonical form of its value, so IIII, VX, IL, XD and
// MMMM are rejected. roman_format emits the unique uppercase subtractive
// form. roman_is_canonical is strict: parse must succeed AND the input must
// already be the exact uppercase canonical form, so IIII, VX and every
// lowercase spelling are false.
//
// Compiler notes (XIOM v0.61.3): free functions only; Ok/Err are constructed
// only in the leaf helpers _roman_parse_ok/_roman_parse_err and
// _roman_format_ok/_roman_format_err; no self methods, no lambdas, no
// Vec[StructType]; matches are exhaustive; Str comparisons go through
// xiom.string.str_compare (never `==`).

module xiom.roman

use xiom.string;

const _ROMAN_UPPER_I: UInt8 = 73u8;
const _ROMAN_UPPER_V: UInt8 = 86u8;
const _ROMAN_UPPER_X: UInt8 = 88u8;
const _ROMAN_UPPER_L: UInt8 = 76u8;
const _ROMAN_UPPER_C: UInt8 = 67u8;
const _ROMAN_UPPER_D: UInt8 = 68u8;
const _ROMAN_UPPER_M: UInt8 = 77u8;
const _ROMAN_LOWER_I: UInt8 = 105u8;
const _ROMAN_LOWER_V: UInt8 = 118u8;
const _ROMAN_LOWER_X: UInt8 = 120u8;
const _ROMAN_LOWER_L: UInt8 = 108u8;
const _ROMAN_LOWER_C: UInt8 = 99u8;
const _ROMAN_LOWER_D: UInt8 = 100u8;
const _ROMAN_LOWER_M: UInt8 = 109u8;
const _ROMAN_MIN: Int = 1;
const _ROMAN_MAX: Int = 3999;

/// Parse a Roman numeral.
/// Params: s - the numeral text, spelled with I,V,X,L,C,D,M in either case.
/// Returns: Ok(value) with value in 1..3999 when s is a case-insensitive
/// spelling of the canonical form of its value; Err("roman: ...") otherwise.
/// Error case: Err("roman: empty input") for ""; Err("roman: invalid
/// character: <c>") for the first non-symbol byte in left-to-right order;
/// Err("roman: out of range") when the evaluated magnitude leaves 1..3999
/// (e.g. "MMMM"); Err("roman: not canonical") when every letter is valid and
/// the magnitude is in range but the spelling is not canonical ("IIII",
/// "VX", "IL", "XD", "IIX", ...).
/// Examples: ("MCMXCIV") -> Ok(1994); ("iv") -> Ok(4); ("IIII") ->
/// Err("roman: not canonical"); ("MMMM") -> Err("roman: out of range").
/// Complexity: O(len(s)) time, O(1) extra space.
pub fn roman_parse(s: Str) -> Result[Int, Str] {
  let n = s.len();
  if n == 0 {
    return _roman_parse_err("roman: empty input");
  }
  var k = 0;
  while k < n {
    if _roman_symbol_value(string.byte_at(s, k)) == 0 {
      return _roman_parse_err("roman: invalid character: " + string.str_slice(s, k, k + 1));
    }
    k = k + 1;
  }
  var total = 0;
  var prev = 0;
  var i = n - 1;
  while i >= 0 {
    let v = _roman_symbol_value(string.byte_at(s, i));
    if v < prev {
      total = total - v;
    } else {
      total = total + v;
    }
    prev = v;
    i = i - 1;
  }
  if total < _ROMAN_MIN || total > _ROMAN_MAX {
    return _roman_parse_err("roman: out of range");
  }
  let canonical = _roman_canonical(total);
  if string.str_compare(canonical, string.str_upper(s)) == 0 {
    return _roman_parse_ok(total);
  }
  return _roman_parse_err("roman: not canonical");
}

/// Format an integer as a canonical uppercase Roman numeral.
/// Params: n - the integer value to format.
/// Returns: Ok(text) with the unique subtractive uppercase form when
/// 1 <= n <= 3999; Err("roman: out of range") otherwise (0, negatives and
/// every value above 3999 included).
/// Examples: (1994) -> Ok("MCMXCIV"); (3999) -> Ok("MMMCMXCIX"); (0) ->
/// Err("roman: out of range").
/// Complexity: O(len(result)).
pub fn roman_format(n: Int) -> Result[Str, Str] {
  if n < _ROMAN_MIN || n > _ROMAN_MAX {
    return _roman_format_err("roman: out of range");
  }
  return _roman_format_ok(_roman_canonical(n));
}

/// Strict canonicality test.
/// Params: s - the candidate text.
/// Returns: true only when roman_parse(s) succeeds AND s is already the exact
/// uppercase canonical form of that value, so "IV" and "XIV" are true while
/// "IIII", "VX", "IL", "XD", "MMMM", "iv", "mcmxciv" and "" are false.
/// Error case: none.
/// Complexity: O(len(s)).
pub fn roman_is_canonical(s: Str) -> Bool {
  let r = roman_parse(s);
  match r {
    Ok(v) => { return _roman_is_canonical_value(s, v); },
    Err(_) => { return false; },
  }
  return false;
}

/// The largest representable value: 3999, written "MMMCMXCIX".
/// Returns: 3999.
/// Error case: none. Complexity: O(1).
pub fn roman_max() -> Int {
  return _ROMAN_MAX;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// True when s equals the exact canonical form of v (case-sensitive).
fn _roman_is_canonical_value(s: Str, v: Int) -> Bool {
  let canonical = _roman_canonical(v);
  return string.str_compare(canonical, s) == 0;
}

// Numeric value of one Roman symbol byte, in either case; 0 when the byte is
// not one of I, V, X, L, C, D, M.
fn _roman_symbol_value(b: UInt8) -> Int {
  if b == _ROMAN_UPPER_I || b == _ROMAN_LOWER_I { return 1; }
  if b == _ROMAN_UPPER_V || b == _ROMAN_LOWER_V { return 5; }
  if b == _ROMAN_UPPER_X || b == _ROMAN_LOWER_X { return 10; }
  if b == _ROMAN_UPPER_L || b == _ROMAN_LOWER_L { return 50; }
  if b == _ROMAN_UPPER_C || b == _ROMAN_LOWER_C { return 100; }
  if b == _ROMAN_UPPER_D || b == _ROMAN_LOWER_D { return 500; }
  if b == _ROMAN_UPPER_M || b == _ROMAN_LOWER_M { return 1000; }
  return 0;
}

// Canonical uppercase subtractive text for 0..3999 ("" for 0). Callers pass a
// value already validated to be in range.
fn _roman_canonical(n: Int) -> Str {
  var out = "";
  var rest = n;
  while rest >= 1000 {
    out = out + "M";
    rest = rest - 1000;
  }
  if rest >= 900 {
    out = out + "CM";
    rest = rest - 900;
  }
  if rest >= 500 {
    out = out + "D";
    rest = rest - 500;
  }
  if rest >= 400 {
    out = out + "CD";
    rest = rest - 400;
  }
  while rest >= 100 {
    out = out + "C";
    rest = rest - 100;
  }
  if rest >= 90 {
    out = out + "XC";
    rest = rest - 90;
  }
  if rest >= 50 {
    out = out + "L";
    rest = rest - 50;
  }
  if rest >= 40 {
    out = out + "XL";
    rest = rest - 40;
  }
  while rest >= 10 {
    out = out + "X";
    rest = rest - 10;
  }
  if rest >= 9 {
    out = out + "IX";
    rest = rest - 9;
  }
  if rest >= 5 {
    out = out + "V";
    rest = rest - 5;
  }
  if rest >= 4 {
    out = out + "IV";
    rest = rest - 4;
  }
  while rest >= 1 {
    out = out + "I";
    rest = rest - 1;
  }
  return out;
}

// Result constructors live in these leaves: constructing Ok/Err inline in a
// function that also returns a struct value miscompiles on XIOM v0.61.3.
fn _roman_parse_ok(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _roman_parse_err(m: Str) -> Result[Int, Str] {
  return Err(m);
}

fn _roman_format_ok(s: Str) -> Result[Str, Str] {
  return Ok(s);
}

fn _roman_format_err(m: Str) -> Result[Str, Str] {
  return Err(m);
}
