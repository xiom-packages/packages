// XIOM -- xiom.luhn: Luhn (mod-10) check-digit validation and computation
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: luhn_parse accepts exactly the canonical ASCII digit form of a
// Luhn-coded number and verifies its trailing check digit. The check digit of
// a body (all but the last digit) is computed by walking the body from the
// right, doubling every second digit starting with the rightmost body digit,
// subtracting 9 from any doubled value above 9, summing, and returning
// (10 - sum mod 10) mod 10. A complete number is verified by walking it from
// the right with the trailing check digit not doubled: the number is valid
// exactly when that total is a multiple of 10.
//
// Input is strict by default: only ASCII digits are accepted, so raw spaced or
// hyphenated display forms are rejected. luhn_normalize strips exactly the two
// documented separators (space, hyphen), and luhn_parse_normalized normalizes
// first and then applies the same canonical rules; any other separator is a
// bad-character error.
//
// The minimum accepted length is LUHN_MIN_DIGITS (2): a one-digit input is
// rejected as too short because every single digit is its own check digit.
// There is no maximum length beyond the platform's string and Int capacities;
// one digit contributes at most 9 to the running sum, so Int never overflows.
//
// Out of scope: card-brand rules, IBAN/IMEI/ISBN semantics, BigInt, and any
// issuer-specific structure (see SPEC.md).

module xiom.luhn

use xiom.string;
use xiom.convert;

// Minimum accepted total digit count. One-digit inputs are excluded because a
// single digit always verifies against itself; two digits (one body digit plus
// its check digit) is the smallest input with a meaningful check relation.
pub const LUHN_MIN_DIGITS: Int = 2;

const _LUHN_ZERO: UInt8 = 48u8;
const _LUHN_NINE: UInt8 = 57u8;
const _LUHN_SPACE: UInt8 = 32u8;
const _LUHN_HYPHEN: UInt8 = 45u8;

/// Parsed and fully validated Luhn number. `digits` is the canonical ASCII
/// digit text including the trailing check digit, exactly as validated (no
/// separators).
pub type Luhn = {
  digits: Str;
}

// Result constructors live in these leaves: constructing Ok/Err inline in a
// function that also returns a struct value miscompiles on XIOM v0.61.3.
fn _luhn_ok(v: Luhn) -> Result[Luhn, Str] { return Ok(v); }
fn _luhn_err(m: Str) -> Result[Luhn, Str] { return Err(m); }
fn _int_ok(n: Int) -> Result[Int, Str] { return Ok(n); }
fn _int_err(m: Str) -> Result[Int, Str] { return Err(m); }
fn _str_ok(s: Str) -> Result[Str, Str] { return Ok(s); }
fn _str_err(m: Str) -> Result[Str, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Character predicates and digit arithmetic
// ---------------------------------------------------------------------------

fn _is_digit(b: UInt8) -> Bool {
  return b >= _LUHN_ZERO && b <= _LUHN_NINE;
}

// True when every byte of `s` is an ASCII digit.
fn _all_digits(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if !_is_digit(string.byte_at(s, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// Numeric value of one validated digit byte ('0'-'9' -> 0-9). Every widening
// masks to 0xFF per the v0.61.3 byte rules.
fn _digit_value(b: UInt8) -> Int {
  return ((b as Int) & 255) - 48;
}

// Doubled-digit value with the Luhn 9-subtraction rule: 2*d, minus 9 when the
// result exceeds 9, so 0-4 map to 0,2,4,6,8 and 5-9 map to 1,3,5,7,9.
fn _double_digit(d: Int) -> Int {
  let v = d * 2;
  if v > 9 { return v - 9; }
  return v;
}

// Weighted sum of a body whose rightmost digit is doubled: that position sits
// immediately left of the check digit appended by the caller.
fn _body_sum(body: Str) -> Int {
  var sum = 0;
  var double_next = true;
  var i = body.len() - 1;
  while i >= 0 {
    let d = _digit_value(string.byte_at(body, i));
    if double_next {
      sum = sum + _double_digit(d);
    } else {
      sum = sum + d;
    }
    double_next = !double_next;
    i = i - 1;
  }
  return sum;
}

// Weighted sum of a complete number whose rightmost digit is the check digit
// and is therefore never doubled.
fn _full_sum(digits: Str) -> Int {
  var sum = 0;
  var double_next = false;
  var i = digits.len() - 1;
  while i >= 0 {
    let d = _digit_value(string.byte_at(digits, i));
    if double_next {
      sum = sum + _double_digit(d);
    } else {
      sum = sum + d;
    }
    double_next = !double_next;
    i = i - 1;
  }
  return sum;
}

// Check digit that completes `body`: (10 - body sum mod 10) mod 10. The body
// must be non-empty and all-digit; callers establish both preconditions.
fn _check_digit(body: Str) -> Int {
  return (10 - (_body_sum(body) % 10)) % 10;
}

// ---------------------------------------------------------------------------
// Canonical parsing
// ---------------------------------------------------------------------------

// Shared strict validation of already-normalized digit text. Validation order:
// empty input, digit charset, minimum length, then the check digit.
fn _parse_canonical(s: Str) -> Result[Luhn, Str] {
  if s.len() == 0 { return _luhn_err("luhn: empty input"); }
  if !_all_digits(s) { return _luhn_err("luhn: bad characters: " + s); }
  if s.len() < LUHN_MIN_DIGITS {
    return _luhn_err("luhn: too short: " + s + " (minimum " + convert.int_to_string(LUHN_MIN_DIGITS) + " digits)");
  }
  if (_full_sum(s) % 10) != 0 { return _luhn_err("luhn: bad check digit: " + s); }
  let v = Luhn{ digits: s };
  return _luhn_ok(v);
}

// ---------------------------------------------------------------------------
// Public API -- canonical parsing and verification
// ---------------------------------------------------------------------------

/// Parse and fully validate a canonical Luhn number: two or more ASCII digits
/// whose last digit equals the Luhn check digit computed over the body.
/// Params: s - candidate number text in canonical form (ASCII digits only; no
/// separators, call luhn_normalize or luhn_parse_normalized for display text).
/// Returns: Ok(Luhn) with the canonical digits as parsed; Err("luhn: ...")
/// otherwise (see SPEC.md for the message catalog). Validation order: empty
/// input, digit charset, minimum length, then the check digit.
/// Error case: empty input, a non-digit byte, fewer than LUHN_MIN_DIGITS
/// digits, or a check-digit mismatch.
/// Complexity: O(len(s)) time, O(1) space.
pub fn luhn_parse(s: Str) -> Result[Luhn, Str] {
  return _parse_canonical(s);
}

/// True when luhn_parse accepts `s`, false for every error class.
/// Params: s - candidate number text in canonical form.
/// Returns: Bool.
/// Error case: none (errors collapse to false).
/// Complexity: O(len(s)).
pub fn luhn_is_valid(s: Str) -> Bool {
  match luhn_parse(s) {
    Ok(v) => { return true; },
    Err(e) => { return false; },
  }
}

/// Normalize display text to canonical form by removing exactly the two
/// documented separators: U+0020 space and U+002D hyphen-minus. Every other
/// byte, including other separators, is copied through unchanged; this helper
/// performs no validation.
/// Params: s - any text.
/// Returns: `s` with every space and hyphen removed.
/// Error case: none.
/// Complexity: O(len(s)) time and output.
pub fn luhn_normalize(s: Str) -> Str {
  var out = "";
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i);
    if b != _LUHN_SPACE && b != _LUHN_HYPHEN {
      out = out + string.str_slice(s, i, i + 1);
    }
    i = i + 1;
  }
  return out;
}

/// Parse and fully validate display text after normalization: strip the
/// documented separators (space, hyphen) and then apply the canonical rules.
/// Params: s - candidate number text, canonical or grouped with spaces and/or
/// hyphens (for example "4532-0151-1283-0366").
/// Returns: Ok(Luhn) with the normalized canonical digits; Err("luhn: ...")
/// otherwise. Validation order: raw empty input, normalization, only
/// separators, then the canonical rules (charset, minimum length, check
/// digit). Every message except the only-separators case echoes the normalized
/// digit text; the only-separators case echoes the raw input.
/// Error case: empty input, input made only of separators, a non-digit byte
/// outside the separator set, fewer than LUHN_MIN_DIGITS digits, or a
/// check-digit mismatch.
/// Complexity: O(len(s)) time and output.
pub fn luhn_parse_normalized(s: Str) -> Result[Luhn, Str] {
  if s.len() == 0 { return _luhn_err("luhn: empty input"); }
  let n = luhn_normalize(s);
  if n.len() == 0 { return _luhn_err("luhn: only separators: " + s); }
  return _parse_canonical(n);
}

/// True when luhn_parse_normalized accepts `s`, false for every error class.
/// Params: s - candidate display text.
/// Returns: Bool.
/// Error case: none (errors collapse to false).
/// Complexity: O(len(s)).
pub fn luhn_is_valid_normalized(s: Str) -> Bool {
  match luhn_parse_normalized(s) {
    Ok(v) => { return true; },
    Err(e) => { return false; },
  }
}

// ---------------------------------------------------------------------------
// Public API -- check-digit computation and appending
// ---------------------------------------------------------------------------

/// Compute the Luhn check digit for a body of one or more ASCII digits (the
/// number without its check digit). The rightmost body digit is doubled, then
/// every second digit to the left, with the 9-subtraction rule; the check digit
/// is (10 - sum mod 10) mod 10.
/// Params: body - one or more ASCII digits.
/// Returns: Ok(check) with check in 0..9; Err("luhn: ...") for an empty body
/// or a non-digit byte.
/// Error case: empty input or a non-digit byte.
/// Complexity: O(len(body)).
pub fn luhn_compute_check_digit(body: Str) -> Result[Int, Str] {
  if body.len() == 0 { return _int_err("luhn: empty input"); }
  if !_all_digits(body) { return _int_err("luhn: bad characters: " + body); }
  return _int_ok(_check_digit(body));
}

/// Append the Luhn check digit to a body, producing a canonical number that
/// luhn_parse accepts.
/// Params: body - one or more ASCII digits.
/// Returns: Ok(body + check) as decimal text; Err("luhn: ...") with the same
/// catalog as luhn_compute_check_digit.
/// Error case: empty input or a non-digit byte.
/// Complexity: O(len(body)) time and output.
pub fn luhn_append_check_digit(body: Str) -> Result[Str, Str] {
  match luhn_compute_check_digit(body) {
    Ok(k) => { return _str_ok(body + convert.int_to_string(k)); },
    Err(e) => { return _str_err(e); },
  }
}

// ---------------------------------------------------------------------------
// Public API -- structure access
// ---------------------------------------------------------------------------

/// Complete canonical digit text of a parsed number, including the check
/// digit.
/// Params: v - a parsed number.
/// Returns: at least LUHN_MIN_DIGITS ASCII digits, as validated.
/// Error case: none.
/// Complexity: O(1).
pub fn luhn_digits(v: &Luhn) -> Str {
  return v.digits;
}

/// Number of digits of a parsed number, including the check digit.
/// Params: v - a parsed number.
/// Returns: at least LUHN_MIN_DIGITS.
/// Error case: none.
/// Complexity: O(1).
pub fn luhn_digit_count(v: &Luhn) -> Int {
  return v.digits.len();
}

/// Body of a parsed number: every digit except the trailing check digit.
/// Params: v - a parsed number.
/// Returns: digit count minus one ASCII digits.
/// Error case: none.
/// Complexity: O(len) time and output.
pub fn luhn_body(v: &Luhn) -> Str {
  let d = v.digits;
  return string.str_slice(d, 0, d.len() - 1);
}

/// Numeric value of the check digit of a parsed number.
/// Params: v - a parsed number.
/// Returns: 0..9.
/// Error case: none.
/// Complexity: O(1).
pub fn luhn_check_digit(v: &Luhn) -> Int {
  let d = v.digits;
  return _digit_value(string.byte_at(d, d.len() - 1));
}
