// XIOM -- xiom.radix: base 2..36 integer text conversion
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI) radix codec for signed 64-bit integers over the
// canonical lowercase alphabet 0123456789abcdefghijklmnopqrstuvwxyz:
//   * radix_to_int: strict signed parse. The base must be 2..36; an optional
//     leading '+'/'-' is accepted; leading zeros are accepted (and dropped by
//     any subsequent format); uppercase A-Z is accepted as the same digit
//     values as a-z. There are no prefixes (0x/0b/0o), no whitespace and no
//     separators.
//   * radix_from_int: canonical emit. Lowercase digits only, no leading
//     zeros (the single digit '0' for zero), '-' for negative values and
//     never a '+' prefix.
//   * radix_convert: base-to-base conversion through Int. Values that do not
//     fit the signed 64-bit Int range are rejected with "radix: overflow";
//     there is no arbitrary-precision fallback.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; no methods, no lambdas, no Vec[StructType].
//   * Every raw byte read via xiom.string.byte_at is widened with
//     `(x as Int) & 0xFF` before comparison or arithmetic: comparing a raw
//     UInt8 against a constant >= 128 miscompiles.
//   * Ok/Err for the Result-returning functions are constructed only in the
//     tiny leaf helpers _ok_int/_err_int/_ok_str/_err_str; constructing
//     Results directly inside larger functions miscompiles.
//   * Overflow is detected by accumulating the magnitude NEGATIVELY (Int is
//     two's-complement, so the negative side holds one extra value). The
//     bound test `acc < (INT_MIN + digit) / base` is exact for both signs; a
//     non-negative result equal to INT_MIN after the loop is the only extra
//     overflow case (positive magnitudes top out at INT_MAX).
//
// This module never compares Str values (no `==` on Str); callers/tests use
// xiom.string.compare.str_compare.

module xiom.radix

use xiom.string;
use xiom.string.builder;
use xiom.core;

// --------------------------------------------------
//  Alphabet and digit classification
// --------------------------------------------------

/// The canonical radix alphabet (36 characters in value order).
/// Returns: "0123456789abcdefghijklmnopqrstuvwxyz"; index 0 is '0' and
/// index 35 is 'z'.
/// Error case: none.
/// Complexity: O(1).
pub fn radix_alphabet() -> Str {
  return "0123456789abcdefghijklmnopqrstuvwxyz";
}

/// Numeric value of one digit byte.
/// Params: c - the byte to classify.
/// Returns: 0..9 for '0'..'9', 10..35 for 'a'..'z' and the same 10..35 for
/// 'A'..'Z' (uppercase accepted on input); -1 for every other byte,
/// including whitespace, '+', '-', ':' and all bytes >= 0x80.
/// Error case: none.
/// Complexity: O(1).
pub fn radix_digit_value(c: UInt8) -> Int {
  return _digit_value((c as Int) & 0xFF);
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
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
//  Internal helpers
// --------------------------------------------------

// Digit value (0..35) of an already-widened byte; -1 when it is not a digit.
// This is the single classification table used by radix_digit_value and the
// parser: '0'..'9' = 0..9, 'a'..'z' = 10..35, 'A'..'Z' = 10..35.
fn _digit_value(b: Int) -> Int {
  if b >= 48 && b <= 57 {
    return b - 48;
  }
  if b >= 97 && b <= 122 {
    return b - 87;
  }
  if b >= 65 && b <= 90 {
    return b - 55;
  }
  return -1;
}

// True when `base` is a usable radix (2..36).
fn _base_ok(base: Int) -> Bool {
  return base >= 2 && base <= 36;
}

// Decimal text of a non-negative Int (used only for error positions).
fn _dec_str(n: Int) -> Str {
  if n == 0 {
    return "0";
  }
  var x = n;
  var ds = Vec[Int].new();
  while x > 0 {
    ds.push(x % 10);
    x = x / 10;
  }
  var out = Vec[UInt8].new();
  let digits = "0123456789";
  var k = ds.len() - 1;
  while k >= 0 {
    let d: Int = ds[k];
    out.push(string.byte_at(digits, d));
    k = k - 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Text -> Int
// --------------------------------------------------

/// Parse signed integer text in base 2..36.
/// Params: s - the digit text; base - the radix, 2..36.
/// Returns: Ok(value) for a well-formed signed string. An optional leading
/// '+' or '-' is accepted; leading zeros are accepted. Every digit value must
/// be below `base`.
/// Error case: Err("radix: base out of range") when base < 2 or base > 36
/// (checked before the input is scanned);
/// Err("radix: empty input") for "";
/// Err("radix: lone sign") for "+" or "-" alone;
/// Err("radix: invalid digit at position N") where N is the 0-based byte
/// index of the first byte that is not a digit or is a digit >= base;
/// Err("radix: overflow") when the value is outside
/// [-9223372036854775808, 9223372036854775807].
/// Complexity: O(n), n = s.len().
pub fn radix_to_int(s: Str, base: Int) -> Result[Int, Str] {
  if !_base_ok(base) {
    return _err_int("radix: base out of range");
  }
  let n = s.len();
  if n == 0 {
    return _err_int("radix: empty input");
  }
  var i = 0;
  var negative = false;
  let first = (string.byte_at(s, 0) as Int) & 0xFF;
  if first == 45 {
    negative = true;
    i = 1;
  } elif first == 43 {
    i = 1;
  }
  if i >= n {
    return _err_int("radix: lone sign");
  }
  let min_int: Int = core.INT_MIN;
  var acc = 0;
  while i < n {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    let d = _digit_value(b);
    if d < 0 || d >= base {
      return _err_int("radix: invalid digit at position " + _dec_str(i));
    }
    if acc < (min_int + d) / base {
      return _err_int("radix: overflow");
    }
    acc = acc * base - d;
    i = i + 1;
  }
  if !negative {
    if acc == min_int {
      return _err_int("radix: overflow");
    }
    return _ok_int(0 - acc);
  }
  return _ok_int(acc);
}

// --------------------------------------------------
//  Int -> text
// --------------------------------------------------

/// Format an Int in base 2..36.
/// Params: n - the value; base - the radix, 2..36.
/// Returns: Ok(text) with canonical output: lowercase digits, no leading
/// zeros (zero is "0"), a '-' prefix for negative values and no '+' prefix.
/// Error case: Err("radix: base out of range") when base < 2 or base > 36.
/// Complexity: O(log_base |n|).
pub fn radix_from_int(n: Int, base: Int) -> Result[Str, Str] {
  if !_base_ok(base) {
    return _err_str("radix: base out of range");
  }
  if n == 0 {
    return _ok_str("0");
  }
  var negative = false;
  var x = n;
  if x < 0 {
    negative = true;
  } else {
    x = 0 - x;
  }
  var digits = Vec[Int].new();
  while x != 0 {
    var d = x % base;
    if d < 0 {
      d = 0 - d;
    }
    digits.push(d);
    x = x / base;
  }
  var out = Vec[UInt8].new();
  if negative {
    out.push(45u8);
  }
  let alpha = radix_alphabet();
  var k = digits.len() - 1;
  while k >= 0 {
    let d: Int = digits[k];
    out.push(string.byte_at(alpha, d));
    k = k - 1;
  }
  return _ok_str(builder.sb_to_str(&out));
}

// --------------------------------------------------
//  Base-to-base conversion
// --------------------------------------------------

/// Convert between bases through Int.
/// Params: s - the digit text; from_base - source radix, 2..36;
/// to_base - target radix, 2..36.
/// Returns: Ok(text) with `s` parsed in from_base and emitted in to_base
/// (canonical output). Both bases are validated before `s` is scanned, in
/// the order from_base then to_base (same message for either).
/// Error case: Err("radix: base out of range") when either base is outside
/// 2..36; otherwise every radix_to_int error is propagated verbatim
/// ("radix: empty input", "radix: lone sign",
/// "radix: invalid digit at position N", "radix: overflow"). Values outside
/// the Int range cannot be converted; there is no arbitrary-precision
/// fallback.
/// Complexity: O(n) plus O(log_to_base |v|), n = s.len().
pub fn radix_convert(s: Str, from_base: Int, to_base: Int) -> Result[Str, Str] {
  if !_base_ok(from_base) {
    return _err_str("radix: base out of range");
  }
  if !_base_ok(to_base) {
    return _err_str("radix: base out of range");
  }
  let parsed = radix_to_int(s, from_base);
  if !parsed.is_ok {
    return _err_str(parsed.error);
  }
  let value: Int = parsed.value;
  return radix_from_int(value, to_base);
}

// --------------------------------------------------
//  Validation
// --------------------------------------------------

/// True when `s` is valid signed text in `base`.
/// Params: s - the candidate text; base - the radix, 2..36.
/// Returns: true exactly when radix_to_int(s, base) returns Ok; false for
/// every error, including a base outside 2..36.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn radix_is_valid(s: Str, base: Int) -> Bool {
  let r = radix_to_int(s, base);
  return r.is_ok;
}
