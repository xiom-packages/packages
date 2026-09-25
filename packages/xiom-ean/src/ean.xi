// XIOM -- xiom.ean: EAN-13, EAN-8 and UPC-A validation and check digits
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: ean_parse accepts exactly the ASCII digit forms of the three
// canonical EAN/UPC code lengths -- EAN-13 (13 digits), UPC-A (12 digits)
// and EAN-8 (8 digits) -- and rejects everything else. The last digit must
// equal the check digit computed over the body (all but the last digit):
// body digits are weighted from the right with the alternating 3, 1, 3, 1,
// ... sequence, summed, and the check digit is (10 - sum mod 10) mod 10.
//
// Every type also has strict typed entry points: ean13_*, upca_* and ean8_*
// each provide a declared-length parser (wrong length is a named error), an
// is_valid shorthand and a *_compute_check_digit helper for the body.
//
// The GS1 country prefix accessor is informational only: it reports the
// first three digits and deliberately carries no prefix-to-country table.
// UPC-A and EAN-13 are the same code space: a UPC-A code is exactly an
// EAN-13 code with a leading zero, and the equivalence helpers expose that
// mapping in both directions.
//
// Out of scope: barcode rendering, GS1 registry or company-prefix
// validation, ITF/Code128 and other symbologies, and ISBN conversion (see
// SPEC.md).

module xiom.ean

use xiom.string;
use xiom.convert;

// Digit-length identities of the three supported code types. `Ean.kind` is
// always one of these values, so kind doubles as the full digit length.
pub const EAN_KIND_EAN8: Int = 8;
pub const EAN_KIND_UPCA: Int = 12;
pub const EAN_KIND_EAN13: Int = 13;

const _DIGIT_ZERO: UInt8 = 48u8;
const _DIGIT_NINE: UInt8 = 57u8;

/// Parsed and fully validated EAN/UPC code. `kind` is the declared code type
/// (EAN_KIND_EAN8, EAN_KIND_UPCA or EAN_KIND_EAN13, equal to the full digit
/// length), and `digits` is the complete code text including the check
/// digit, exactly as parsed (canonical: ASCII digits only).
pub type Ean = {
  kind: Int;
  digits: Str;
}

// Result constructors live in these leaves: constructing Ok/Err inline in a
// function that also returns a struct value miscompiles on XIOM v0.61.3.
fn _ean_ok(v: Ean) -> Result[Ean, Str] { return Ok(v); }
fn _ean_err(m: Str) -> Result[Ean, Str] { return Err(m); }
fn _int_ok(n: Int) -> Result[Int, Str] { return Ok(n); }
fn _int_err(m: Str) -> Result[Int, Str] { return Err(m); }
fn _str_ok(s: Str) -> Result[Str, Str] { return Ok(s); }
fn _str_err(m: Str) -> Result[Str, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Shared validation helpers
// ---------------------------------------------------------------------------

fn _is_digit(b: UInt8) -> Bool {
  return b >= _DIGIT_ZERO && b <= _DIGIT_NINE;
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

// Display name of a code type, used in error messages. Only called with a
// validated kind (8, 12 or 13).
fn _kind_name(kind: Int) -> Str {
  if kind == EAN_KIND_EAN8 { return "EAN-8"; }
  if kind == EAN_KIND_UPCA { return "UPC-A"; }
  return "EAN-13";
}

// Check digit of a body: weight the body digits from the right with the
// alternating 3, 1, 3, 1, ... sequence, sum, and return
// (10 - sum mod 10) mod 10. The body must be non-empty and contain only
// ASCII digits; both preconditions are established by the callers.
fn _check_digit(body: Str) -> Int {
  var sum = 0;
  var weight = 3;
  var i = body.len() - 1;
  while i >= 0 {
    let digit = ((string.byte_at(body, i) as Int) & 255) - 48;
    sum = sum + digit * weight;
    if weight == 3 { weight = 1; } else { weight = 3; }
    i = i - 1;
  }
  return (10 - (sum % 10)) % 10;
}

// Shared implementation of the three typed parsers. `kind` is one of
// EAN_KIND_EAN8 / EAN_KIND_UPCA / EAN_KIND_EAN13. Validation order: empty
// input, declared length, digit charset, then the check digit.
fn _parse_declared(s: Str, kind: Int) -> Result[Ean, Str] {
  let n = s.len();
  if n == 0 { return _ean_err("ean: empty input"); }
  if n != kind {
    return _ean_err("ean: bad length for " + _kind_name(kind) + ": expected " + convert.int_to_string(kind) + ", got " + convert.int_to_string(n));
  }
  if !_all_digits(s) { return _ean_err("ean: bad characters: " + s); }
  let body = string.str_slice(s, 0, kind - 1);
  let last = ((string.byte_at(s, kind - 1) as Int) & 255) - 48;
  if _check_digit(body) != last { return _ean_err("ean: bad check digit: " + s); }
  let v = Ean{ kind: kind; digits: s };
  return _ean_ok(v);
}

// Shared implementation of the three check-digit helpers. `body_len` is the
// declared full length minus one. Validation order: empty input, declared
// body length, digit charset.
fn _compute_declared(body: Str, kind: Int, body_len: Int) -> Result[Int, Str] {
  if body.len() == 0 { return _int_err("ean: empty input"); }
  if body.len() != body_len {
    return _int_err("ean: bad body length for " + _kind_name(kind) + ": expected " + convert.int_to_string(body_len) + ", got " + convert.int_to_string(body.len()));
  }
  if !_all_digits(body) { return _int_err("ean: bad characters: " + body); }
  return _int_ok(_check_digit(body));
}

// ---------------------------------------------------------------------------
// Public API -- generic parse
// ---------------------------------------------------------------------------

/// Parse and validate an EAN/UPC code of any supported type, selected by the
/// input length: 13 digits (EAN-13), 12 digits (UPC-A) or 8 digits (EAN-8).
/// Params: s - candidate code text.
/// Returns: Ok(Ean) with `kind` set to the detected type, digits only in
/// canonical compact form; Err("ean: ...") otherwise (see SPEC.md for the
/// catalog). Validation order: empty input, supported length, digit charset,
/// then the check digit.
/// Error case: empty input, unsupported length, non-digit byte, or check
/// digit mismatch.
/// Complexity: O(1) time and space (the length is at most 13).
pub fn ean_parse(s: Str) -> Result[Ean, Str] {
  let n = s.len();
  if n == 0 { return _ean_err("ean: empty input"); }
  if n == EAN_KIND_EAN8 { return _parse_declared(s, EAN_KIND_EAN8); }
  if n == EAN_KIND_UPCA { return _parse_declared(s, EAN_KIND_UPCA); }
  if n == EAN_KIND_EAN13 { return _parse_declared(s, EAN_KIND_EAN13); }
  return _ean_err("ean: bad length: " + convert.int_to_string(n) + " (expected 8, 12 or 13)");
}

/// True when ean_parse accepts `s`, false for every error class.
/// Params: s - candidate code text.
/// Returns: Bool.
/// Error case: none (errors collapse to false).
/// Complexity: O(1).
pub fn ean_is_valid(s: Str) -> Bool {
  match ean_parse(s) {
    Ok(v) => { return true; },
    Err(e) => { return false; },
  }
}

// ---------------------------------------------------------------------------
// Public API -- typed parse
// ---------------------------------------------------------------------------

/// Parse and validate an EAN-13 code: exactly 13 ASCII digits whose last
/// digit is the check digit over the first 12.
/// Params: s - candidate EAN-13 text.
/// Returns: Ok(Ean) with kind EAN_KIND_EAN13; Err("ean: ...") otherwise.
/// Error case: empty input, wrong length, non-digit byte, or check digit
/// mismatch.
/// Complexity: O(1).
pub fn ean13_parse(s: Str) -> Result[Ean, Str] {
  return _parse_declared(s, EAN_KIND_EAN13);
}

/// True when ean13_parse accepts `s`, false for every error class.
/// Params: s - candidate EAN-13 text.
/// Returns: Bool.
/// Error case: none (errors collapse to false).
/// Complexity: O(1).
pub fn ean13_is_valid(s: Str) -> Bool {
  match ean13_parse(s) {
    Ok(v) => { return true; },
    Err(e) => { return false; },
  }
}

/// Parse and validate a UPC-A code: exactly 12 ASCII digits whose last digit
/// is the check digit over the first 11.
/// Params: s - candidate UPC-A text.
/// Returns: Ok(Ean) with kind EAN_KIND_UPCA; Err("ean: ...") otherwise.
/// Error case: empty input, wrong length, non-digit byte, or check digit
/// mismatch.
/// Complexity: O(1).
pub fn upca_parse(s: Str) -> Result[Ean, Str] {
  return _parse_declared(s, EAN_KIND_UPCA);
}

/// True when upca_parse accepts `s`, false for every error class.
/// Params: s - candidate UPC-A text.
/// Returns: Bool.
/// Error case: none (errors collapse to false).
/// Complexity: O(1).
pub fn upca_is_valid(s: Str) -> Bool {
  match upca_parse(s) {
    Ok(v) => { return true; },
    Err(e) => { return false; },
  }
}

/// Parse and validate an EAN-8 code: exactly 8 ASCII digits whose last digit
/// is the check digit over the first 7.
/// Params: s - candidate EAN-8 text.
/// Returns: Ok(Ean) with kind EAN_KIND_EAN8; Err("ean: ...") otherwise.
/// Error case: empty input, wrong length, non-digit byte, or check digit
/// mismatch.
/// Complexity: O(1).
pub fn ean8_parse(s: Str) -> Result[Ean, Str] {
  return _parse_declared(s, EAN_KIND_EAN8);
}

/// True when ean8_parse accepts `s`, false for every error class.
/// Params: s - candidate EAN-8 text.
/// Returns: Bool.
/// Error case: none (errors collapse to false).
/// Complexity: O(1).
pub fn ean8_is_valid(s: Str) -> Bool {
  match ean8_parse(s) {
    Ok(v) => { return true; },
    Err(e) => { return false; },
  }
}

// ---------------------------------------------------------------------------
// Public API -- check-digit computation
// ---------------------------------------------------------------------------

/// Compute the EAN-13 check digit for a body of exactly 12 ASCII digits
/// (the code without its check digit).
/// Params: body - 12 ASCII digits.
/// Returns: Ok(check) with check in 0..9; Err("ean: ...") for an empty body,
/// a wrong body length, or a non-digit byte.
/// Error case: see above.
/// Complexity: O(1).
pub fn ean13_compute_check_digit(body: Str) -> Result[Int, Str] {
  return _compute_declared(body, EAN_KIND_EAN13, 12);
}

/// Compute the UPC-A check digit for a body of exactly 11 ASCII digits.
/// Params: body - 11 ASCII digits.
/// Returns: Ok(check) with check in 0..9; Err("ean: ...") for an empty body,
/// a wrong body length, or a non-digit byte.
/// Error case: see above.
/// Complexity: O(1).
pub fn upca_compute_check_digit(body: Str) -> Result[Int, Str] {
  return _compute_declared(body, EAN_KIND_UPCA, 11);
}

/// Compute the EAN-8 check digit for a body of exactly 7 ASCII digits.
/// Params: body - 7 ASCII digits.
/// Returns: Ok(check) with check in 0..9; Err("ean: ...") for an empty body,
/// a wrong body length, or a non-digit byte.
/// Error case: see above.
/// Complexity: O(1).
pub fn ean8_compute_check_digit(body: Str) -> Result[Int, Str] {
  return _compute_declared(body, EAN_KIND_EAN8, 7);
}

// ---------------------------------------------------------------------------
// Public API -- structure access
// ---------------------------------------------------------------------------

/// Code type of a parsed code: EAN_KIND_EAN8, EAN_KIND_UPCA or
/// EAN_KIND_EAN13 (equal to the full digit length).
/// Params: v - a parsed code.
/// Returns: 8, 12 or 13.
/// Error case: none.
/// Complexity: O(1).
pub fn ean_kind(v: &Ean) -> Int {
  return v.kind;
}

/// Complete digit text of a parsed code, including the check digit.
/// Params: v - a parsed code.
/// Returns: exactly kind ASCII digits, as parsed.
/// Error case: none.
/// Complexity: O(1).
pub fn ean_digits(v: &Ean) -> Str {
  return v.digits;
}

/// Body of a parsed code: every digit except the trailing check digit.
/// Params: v - a parsed code.
/// Returns: kind - 1 ASCII digits.
/// Error case: none.
/// Complexity: O(kind) time, O(kind) output.
pub fn ean_body(v: &Ean) -> Str {
  let d = v.digits;
  return string.str_slice(d, 0, d.len() - 1);
}

/// Numeric value of the check digit of a parsed code.
/// Params: v - a parsed code.
/// Returns: 0..9.
/// Error case: none.
/// Complexity: O(1).
pub fn ean_check_digit(v: &Ean) -> Int {
  let d = v.digits;
  return ((string.byte_at(d, d.len() - 1) as Int) & 255) - 48;
}

/// Informational GS1 prefix field: the first three digits of the body.
/// Params: v - a parsed code.
/// Returns: a three-character digit string. For EAN-13 and UPC-A this is the
/// nominal GS1 prefix field; for EAN-8 there is no GS1 company prefix and
/// the digits are not meaningful. No prefix-to-country table is built in: a
/// GS1 prefix only indicates the issuing member organization, it does not
/// identify where a product was made, and this accessor is not an
/// authoritative GS1 statement. Lengths of 2 digits are not modeled.
/// Error case: none.
/// Complexity: O(1).
pub fn ean_country_prefix(v: &Ean) -> Str {
  let d = v.digits;
  return string.str_slice(d, 0, 3);
}

// ---------------------------------------------------------------------------
// Public API -- canonical formatting
// ---------------------------------------------------------------------------

/// Canonical compact form: the digit text exactly as ean_parse accepted it.
/// Params: v - a parsed code.
/// Returns: kind ASCII digits, no separators.
/// Error case: none.
/// Complexity: O(1).
pub fn ean_compact(v: &Ean) -> Str {
  return v.digits;
}

/// Canonical grouped display form, matching the human-readable grouping used
/// under a printed symbol: EAN-13 as 1-6-6, UPC-A as 1-5-5-1 and EAN-8 as
/// 4-4, with single spaces. This is display text only; strip the spaces
/// before feeding it back to a parser.
/// Params: v - a parsed code.
/// Returns: for example "4006381333931" -> "4 006381 333931",
/// "036000291452" -> "0 36000 29145 2", "96385074" -> "9638 5074".
/// Error case: none.
/// Complexity: O(1).
pub fn ean_format(v: &Ean) -> Str {
  let d = v.digits;
  if v.kind == EAN_KIND_EAN13 {
    return string.str_slice(d, 0, 1) + " " + string.str_slice(d, 1, 7) + " " + string.str_slice(d, 7, 13);
  }
  if v.kind == EAN_KIND_UPCA {
    return string.str_slice(d, 0, 1) + " " + string.str_slice(d, 1, 6) + " " + string.str_slice(d, 6, 11) + " " + string.str_slice(d, 11, 12);
  }
  return string.str_slice(d, 0, 4) + " " + string.str_slice(d, 4, 8);
}

// ---------------------------------------------------------------------------
// Public API -- UPC-A / EAN-13 equivalence
// ---------------------------------------------------------------------------

/// UPC-A -> EAN-13 equivalence: validate a UPC-A code and return its EAN-13
/// zero-prefix form. Adding a leading zero to a valid UPC-A always yields a
/// valid EAN-13 with the same check digit, because the added zero carries
/// weight 1 and shifts every existing weight by one position.
/// Params: s - candidate UPC-A text.
/// Returns: Ok(ean13) with the 13-digit zero-prefixed code; Err("ean: ...")
/// with the upca_parse error when `s` is not a valid UPC-A.
/// Error case: see upca_parse.
/// Complexity: O(1).
pub fn upca_to_ean13(s: Str) -> Result[Str, Str] {
  match upca_parse(s) {
    Ok(v) => {
      let d = v.digits;
      return _str_ok("0" + d);
    },
    Err(e) => { return _str_err(e); },
  }
}

/// EAN-13 -> UPC-A equivalence: validate an EAN-13 code that uses the
/// zero-prefix form (first digit "0") and return the corresponding 12-digit
/// UPC-A code.
/// Params: s - candidate EAN-13 text.
/// Returns: Ok(upca) with the 12-digit UPC-A code; Err("ean: ...") with the
/// ean13_parse error when `s` is not a valid EAN-13, or
/// Err("ean: not UPC-A equivalent: <s>") when it is valid but does not start
/// with "0" (and therefore is not in the UPC-A code space).
/// Error case: see above.
/// Complexity: O(1).
pub fn ean13_to_upca(s: Str) -> Result[Str, Str] {
  match ean13_parse(s) {
    Ok(v) => {
      let d = v.digits;
      if ((string.byte_at(d, 0) as Int) & 255) != 48 {
        return _str_err("ean: not UPC-A equivalent: " + s);
      }
      return _str_ok(string.str_slice(d, 1, EAN_KIND_EAN13));
    },
    Err(e) => { return _str_err(e); },
  }
}

/// True when `s` is a valid EAN-13 code in the zero-prefix form and therefore
/// maps to a UPC-A code.
/// Params: s - candidate EAN-13 text.
/// Returns: Bool; false for every invalid or non-zero-prefixed input.
/// Error case: none (errors collapse to false).
/// Complexity: O(1).
pub fn ean13_is_upca_equivalent(s: Str) -> Bool {
  match ean13_parse(s) {
    Ok(v) => {
      let d = v.digits;
      return ((string.byte_at(d, 0) as Int) & 255) == 48;
    },
    Err(e) => { return false; },
  }
}
