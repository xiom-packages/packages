// XIOM -- xiom.iban: strict IBAN parsing, validation, formatting and
// MOD-97 check-digit computation for a documented country table.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: iban_parse accepts exactly the compact uppercase form "CCkkBBAN"
// (no spaces, no lowercase). The country code must be two ASCII uppercase
// letters present in the table, the total length must equal the country's
// registered length, the two check digits must be ASCII digits, the BBAN
// must use the country's documented character class (numeric-only or
// uppercase alphanumeric), and the MOD-97-10 remainder of the rearranged
// string must be 1.
//
// MOD-97-10 is evaluated digit-wise: each BBAN character contributes one or
// two decimal digits, so the running remainder stays below 97 and no
// arbitrary-length integer is ever built.
//
// Out of scope: bank/branch semantics, SEPA rules, BIC, lowercase or
// space-separated input (see SPEC.md).

module xiom.iban

use xiom.string;
use xiom.string.compare;
use xiom.convert;

const _IBAN_ZERO: UInt8 = 48u8;
const _IBAN_NINE: UInt8 = 57u8;
const _IBAN_UPPER_A: UInt8 = 65u8;
const _IBAN_UPPER_Z: UInt8 = 90u8;

/// Parsed and fully validated IBAN. `country` is the two-letter ASCII
/// uppercase country code, `check` the numeric value of the two check
/// digits (0..99; iban_format and iban_compact zero-pad it to two digits),
/// and `bban` the basic bank account number exactly as written (uppercase).
pub type Iban = {
  country: Str;
  check: Int;
  bban: Str;
}

// Result constructors live in these leaves: constructing Ok/Err inline in a
// function that also returns a struct value miscompiles on XIOM v0.61.3.
fn _iban_ok(v: Iban) -> Result[Iban, Str] { return Ok(v); }
fn _iban_err(m: Str) -> Result[Iban, Str] { return Err(m); }
fn _int_ok(n: Int) -> Result[Int, Str] { return Ok(n); }
fn _int_err(m: Str) -> Result[Int, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Character predicates and the documented country table
// ---------------------------------------------------------------------------

fn _is_digit(b: UInt8) -> Bool {
  return b >= _IBAN_ZERO && b <= _IBAN_NINE;
}

fn _is_upper_letter(b: UInt8) -> Bool {
  return b >= _IBAN_UPPER_A && b <= _IBAN_UPPER_Z;
}

fn _is_alnum_upper(b: UInt8) -> Bool {
  if _is_digit(b) { return true; }
  return _is_upper_letter(b);
}

// Registered total IBAN length for a country code, or 0 when the code is not
// in the table. The argument is compared as-is, so a lowercase code is
// unknown. Table (SPEC.md): AT 20, BE 16, CH 21, CZ 24, DE 22, DK 18, ES 24,
// FI 18, FR 27, GB 22, GR 27, IE 22, IT 27, LU 20, NL 18, NO 15, PL 28,
// PT 25, SE 24.
fn _country_length(cc: Str) -> Int {
  if compare.str_compare(cc, "AT") == 0 { return 20; }
  if compare.str_compare(cc, "BE") == 0 { return 16; }
  if compare.str_compare(cc, "CH") == 0 { return 21; }
  if compare.str_compare(cc, "CZ") == 0 { return 24; }
  if compare.str_compare(cc, "DE") == 0 { return 22; }
  if compare.str_compare(cc, "DK") == 0 { return 18; }
  if compare.str_compare(cc, "ES") == 0 { return 24; }
  if compare.str_compare(cc, "FI") == 0 { return 18; }
  if compare.str_compare(cc, "FR") == 0 { return 27; }
  if compare.str_compare(cc, "GB") == 0 { return 22; }
  if compare.str_compare(cc, "GR") == 0 { return 27; }
  if compare.str_compare(cc, "IE") == 0 { return 22; }
  if compare.str_compare(cc, "IT") == 0 { return 27; }
  if compare.str_compare(cc, "LU") == 0 { return 20; }
  if compare.str_compare(cc, "NL") == 0 { return 18; }
  if compare.str_compare(cc, "NO") == 0 { return 15; }
  if compare.str_compare(cc, "PL") == 0 { return 28; }
  if compare.str_compare(cc, "PT") == 0 { return 25; }
  if compare.str_compare(cc, "SE") == 0 { return 24; }
  return 0;
}

// True when the country's BBAN may contain only ASCII digits. The
// numeric-only table (SPEC.md) is AT, BE, CZ, DE, DK, ES, FI, NO, PL, PT,
// SE; the remaining table countries accept uppercase letters as well.
// Unknown countries return false; callers validate the country first.
fn _bban_numeric_only(cc: Str) -> Bool {
  if compare.str_compare(cc, "AT") == 0 { return true; }
  if compare.str_compare(cc, "BE") == 0 { return true; }
  if compare.str_compare(cc, "CZ") == 0 { return true; }
  if compare.str_compare(cc, "DE") == 0 { return true; }
  if compare.str_compare(cc, "DK") == 0 { return true; }
  if compare.str_compare(cc, "ES") == 0 { return true; }
  if compare.str_compare(cc, "FI") == 0 { return true; }
  if compare.str_compare(cc, "NO") == 0 { return true; }
  if compare.str_compare(cc, "PL") == 0 { return true; }
  if compare.str_compare(cc, "PT") == 0 { return true; }
  if compare.str_compare(cc, "SE") == 0 { return true; }
  return false;
}

// ---------------------------------------------------------------------------
// MOD-97-10
// ---------------------------------------------------------------------------

// Decimal value of one validated BBAN character: '0'-'9' -> 0-9,
// 'A'-'Z' -> 10-35. Every widening masks to 0xFF per the v0.61.3 byte rules.
fn _alnum_value(b: UInt8) -> Int {
  if _is_digit(b) { return ((b as Int) & 255) - 48; }
  return ((b as Int) & 255) - 55;
}

// Remainder of `s` read as one huge decimal number, MOD 97, computed digit
// by digit: a letter contributes two decimal digits (10..35), a digit one
// (0..9), so the running remainder stays below 97 and Int never overflows.
fn _mod97(s: Str) -> Int {
  var r = 0;
  var i = 0;
  while i < s.len() {
    let v = _alnum_value(string.byte_at(s, i));
    if v < 10 {
      r = (r * 10 + v) % 97;
    } else {
      r = (r * 100 + v) % 97;
    }
    i = i + 1;
  }
  return r;
}

// True when every byte of `bban` belongs to the character class selected by
// `numeric_only` (digits only, or uppercase letters and digits).
fn _bban_is_valid(bban: Str, numeric_only: Bool) -> Bool {
  var i = 0;
  while i < bban.len() {
    let b = string.byte_at(bban, i);
    if numeric_only {
      if !_is_digit(b) { return false; }
    } else {
      if !_is_alnum_upper(b) { return false; }
    }
    i = i + 1;
  }
  return true;
}

// Two-digit zero-padded decimal text for a check-digit value 0..99.
fn _two_digits(n: Int) -> Str {
  if n < 10 { return "0" + convert.int_to_string(n); }
  return convert.int_to_string(n);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Parse and fully validate an IBAN.
/// Params: s - compact IBAN text, exactly the uppercase form "CCkkBBAN"
/// without spaces (for example "DE89370400440532013000"); lowercase and
/// space-separated forms are rejected.
/// Returns: Ok(Iban) for a valid IBAN; Err("iban: ...") otherwise (see
/// SPEC.md for the message catalog). Validation order: empty input, country
/// code letters, country membership, total length, check digits and BBAN
/// characters, then the MOD-97-10 check.
/// Error case: see above.
/// Complexity: O(len(s)).
pub fn iban_parse(s: Str) -> Result[Iban, Str] {
  let n = s.len();
  if n == 0 { return _iban_err("iban: empty input"); }
  if n < 2 { return _iban_err("iban: bad characters: " + s); }
  let b0 = string.byte_at(s, 0);
  let b1 = string.byte_at(s, 1);
  if !_is_upper_letter(b0) || !_is_upper_letter(b1) {
    return _iban_err("iban: bad characters: " + s);
  }
  let cc = string.str_slice(s, 0, 2);
  let expected = _country_length(cc);
  if expected == 0 { return _iban_err("iban: unknown country: " + cc); }
  if n != expected {
    return _iban_err("iban: bad length for " + cc + ": expected " + convert.int_to_string(expected) + ", got " + convert.int_to_string(n));
  }
  if !_is_digit(string.byte_at(s, 2)) || !_is_digit(string.byte_at(s, 3)) {
    return _iban_err("iban: bad characters: " + s);
  }
  let bban = string.str_slice(s, 4, n);
  if !_bban_is_valid(bban, _bban_numeric_only(cc)) {
    return _iban_err("iban: bad characters: " + s);
  }
  let rearranged = bban + cc + string.str_slice(s, 2, 4);
  if _mod97(rearranged) != 1 {
    return _iban_err("iban: bad check digits: " + s);
  }
  let d0 = ((string.byte_at(s, 2) as Int) & 255) - 48;
  let d1 = ((string.byte_at(s, 3) as Int) & 255) - 48;
  let v = Iban{ country: cc; check: d0 * 10 + d1; bban: bban };
  return _iban_ok(v);
}

/// Canonical compact form: country code, zero-padded two-digit check value
/// and BBAN, uppercase and without separators.
/// Params: v - a parsed IBAN.
/// Returns: "CCkkBBAN", exactly the text iban_parse accepted.
/// Error case: none.
/// Complexity: O(len).
pub fn iban_compact(v: &Iban) -> Str {
  return v.country + _two_digits(v.check) + v.bban;
}

/// Canonical display form: the compact uppercase IBAN split into
/// space-separated groups of four characters.
/// Params: v - a parsed IBAN.
/// Returns: for example "DE89 3704 0044 0532 0130 00"; the final group may
/// be shorter than four characters.
/// Error case: none.
/// Complexity: O(len).
pub fn iban_format(v: &Iban) -> Str {
  let compact = v.country + _two_digits(v.check) + v.bban;
  var out = "";
  var i = 0;
  let n = compact.len();
  while i < n {
    if i > 0 && i % 4 == 0 { out = out + " "; }
    out = out + string.str_slice(compact, i, i + 1);
    i = i + 1;
  }
  return out;
}

/// Country code of a parsed IBAN.
/// Params: v - a parsed IBAN.
/// Returns: two uppercase ASCII letters.
/// Error case: none.
/// Complexity: O(1).
pub fn iban_country(v: &Iban) -> Str {
  return v.country;
}

/// Numeric value of the two check digits of a parsed IBAN.
/// Params: v - a parsed IBAN.
/// Returns: 0..99; iban_format and iban_compact render it zero-padded.
/// Error case: none.
/// Complexity: O(1).
pub fn iban_check_digits(v: &Iban) -> Int {
  return v.check;
}

/// BBAN of a parsed IBAN.
/// Params: v - a parsed IBAN.
/// Returns: the basic bank account number exactly as written, uppercase.
/// Error case: none.
/// Complexity: O(1).
pub fn iban_bban(v: &Iban) -> Str {
  return v.bban;
}

/// True when iban_parse accepts `s`, false for every error.
/// Params: s - candidate IBAN text.
/// Returns: Bool.
/// Error case: none (errors collapse to false).
/// Complexity: O(len(s)).
pub fn iban_is_valid(s: Str) -> Bool {
  match iban_parse(s) {
    Ok(v) => { return true; },
    Err(e) => { return false; },
  }
}

/// Registered total IBAN length for a country code.
/// Params: country - two-letter code, compared as-is (uppercase).
/// Returns: the registered total length (15..28) for a table country, or 0
/// when the code is unknown.
/// Error case: none.
/// Complexity: O(1).
pub fn iban_length_for_country(country: Str) -> Int {
  return _country_length(country);
}

/// Compute the two check digits for a country and a BBAN.
/// Params: country - two uppercase ASCII letters present in the table;
/// bban - the BBAN with the country's documented character class and length.
/// Returns: Ok(check) with check in 2..98; Err("iban: ...") for an empty
/// argument, a malformed or unknown country, a wrong BBAN length, or
/// characters outside the country's class. The result is the value that
/// makes "CCkkBBAN" pass iban_parse.
/// Error case: see above.
/// Complexity: O(len(bban)).
pub fn iban_compute_check_digits(country: Str, bban: Str) -> Result[Int, Str] {
  if country.len() == 0 || bban.len() == 0 { return _int_err("iban: empty input"); }
  if country.len() != 2 { return _int_err("iban: bad characters: " + country); }
  let b0 = string.byte_at(country, 0);
  let b1 = string.byte_at(country, 1);
  if !_is_upper_letter(b0) || !_is_upper_letter(b1) {
    return _int_err("iban: bad characters: " + country);
  }
  let expected = _country_length(country);
  if expected == 0 { return _int_err("iban: unknown country: " + country); }
  let got = bban.len() + 4;
  if got != expected {
    return _int_err("iban: bad length for " + country + ": expected " + convert.int_to_string(expected) + ", got " + convert.int_to_string(got));
  }
  if !_bban_is_valid(bban, _bban_numeric_only(country)) {
    return _int_err("iban: bad characters: " + bban);
  }
  let rearranged = bban + country + "00";
  return _int_ok(98 - _mod97(rearranged));
}
