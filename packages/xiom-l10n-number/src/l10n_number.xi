// XIOM -- xiom.l10n.number: locale-style integer and decimal formatting
// Port task: replace the xiom.l10n.number placeholder with a pure-XIOM module.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a decimal number is carried as a scaled integer. `scaled` with
// `decimals` fraction digits denotes the value scaled / 10^decimals (so
// scaled=12345, decimals=2 is 123.45). Nothing here uses floating point,
// locale databases or FFI; the module depends only on xiom.string and
// xiom.convert from xiom.std.
//
// Grouping: l10n_int_format inserts `group_sep` between digit groups of three,
// counted from the right; an empty separator disables grouping. Decimal
// separators are caller-supplied strings, so a locale is a (group_sep,
// decimal_sep) pair rather than a database row.

module xiom.l10n.number

use xiom.string;
use xiom.convert;

const _L10N_MINUS: UInt8 = 45u8;
const _L10N_PLUS: UInt8 = 43u8;
const _L10N_ZERO: UInt8 = 48u8;
const _L10N_NINE: UInt8 = 57u8;
const _L10N_FIVE: UInt8 = 53u8;
const _L10N_COMMA: UInt8 = 44u8;
const _L10N_UNDERSCORE: UInt8 = 95u8;
const _L10N_SPACE: UInt8 = 32u8;
const _L10N_INT_MAX: Int = 9223372036854775807;
const _L10N_INT_MAX_DIV10: Int = 922337203685477580;
const _L10N_INT_MAX_LAST_DIGIT: Int = 7;

/// Format an integer with thousands-style grouping.
/// Params: value - any 64-bit signed integer, including the minimum; group_sep
/// - the separator inserted every three digits counted from the right ("," for
/// en-US, "." for de-DE, " " for fr-FR). An empty group_sep disables grouping
/// entirely.
/// Returns: the sign (when negative) followed by the magnitude's digits in
/// groups of three separated by group_sep; 0 -> "0"; -0 cannot occur.
/// Examples: (1000, ",") -> "1,000"; (-999, ",") -> "-999"; (0, ",") -> "0".
/// Error case: none.
/// Complexity: O(number of digits).
pub fn l10n_int_format(value: Int, group_sep: Str) -> Str {
  let neg = value < 0;
  let grouped = _group_digits(_abs_digits(value), group_sep);
  if neg {
    return "-" + grouped;
  }
  return grouped;
}

/// Format a scaled integer as a fixed-decimal number.
/// Params: scaled - the scaled value (sign is handled once, on the whole
/// number); decimals - number of fraction digits, clamped to >= 0; group_sep -
/// thousands separator passed to l10n_int_format; decimal_sep - the string
/// placed between the integer and fraction digits.
/// Returns: sign + grouped integer digits + decimal_sep + zero-padded fraction
/// digits. decimals == 0 (or negative) behaves exactly like l10n_int_format.
/// The digits are emitted as given: no rounding, no carry, no overflow-prone
/// scaling, so any value/decimals combination is exact.
/// Examples: (12345, 2, ",", ".") -> "123.45"; (5, 3, ",", ".") -> "0.005";
/// (-12345, 0, ",", ".") -> "-12,345"; (1234, 2, ",", "") -> "1234".
/// Error case: none.
/// Complexity: O(digits + decimals).
pub fn l10n_decimal_format(scaled: Int, decimals: Int, group_sep: Str, decimal_sep: Str) -> Str {
  var dec = decimals;
  if dec < 0 {
    dec = 0;
  }
  if dec == 0 {
    return l10n_int_format(scaled, group_sep);
  }
  var body = _abs_digits(scaled);
  while body.len() <= dec {
    body = "0" + body;
  }
  let split = body.len() - dec;
  let int_digits = string.str_slice(body, 0, split);
  let frac_digits = string.str_slice(body, split, body.len());
  var out = _group_digits(int_digits, group_sep) + decimal_sep + frac_digits;
  if scaled < 0 {
    out = "-" + out;
  }
  return out;
}

/// Rescale a scaled integer to fewer fraction digits, rounding half away from
/// zero.
/// Params: scaled - the scaled value; from_decimals - its current fraction
/// digit count; to_decimals - the wanted fraction digit count. Both counts are
/// clamped to >= 0. When to_decimals >= from_decimals the value is already
/// exact and is returned unchanged.
/// Returns: round(scaled / 10^(from-to)) with halves rounded away from zero:
/// 15 -> 2, -15 -> -2, 14 -> 1, 25 -> 3. A drop of exactly 19 digits yields a
/// signed 1 when the magnitude is at least 5*10^18, else 0; larger drops yield
/// 0 because no 64-bit magnitude can reach half of them.
/// Examples: (12345, 2, 0) -> 123; (12355, 2, 0) -> 124; (-12355, 2, 0) ->
/// -124; (1234, 2, 5) -> 1234.
/// Error case: none.
/// Complexity: O(min(from - to, 19)).
pub fn l10n_decimal_round(scaled: Int, from_decimals: Int, to_decimals: Int) -> Int {
  var from_d = from_decimals;
  if from_d < 0 {
    from_d = 0;
  }
  var to_d = to_decimals;
  if to_d < 0 {
    to_d = 0;
  }
  if to_d >= from_d {
    return scaled;
  }
  let drop = from_d - to_d;
  if drop > 19 {
    return 0;
  }
  if drop == 19 {
    let digits = _abs_digits(scaled);
    if digits.len() < 19 {
      return 0;
    }
    if string.byte_at(digits, 0) < _L10N_FIVE {
      return 0;
    }
    if scaled < 0 {
      return 0 - 1;
    }
    return 1;
  }
  var div: Int = 1;
  var k = 0;
  while k < drop {
    div = div * 10;
    k = k + 1;
  }
  let q = scaled / div;
  let r = scaled % div;
  if scaled >= 0 {
    if r * 2 >= div {
      return q + 1;
    }
    return q;
  }
  if (0 - r) * 2 >= div {
    return q - 1;
  }
  return q;
}

/// Parse a grouped, localized decimal string into a scaled integer.
/// Params: text - the number text; decimal_sep - the string that marks the
/// fraction boundary (a single ASCII byte in practice; multi-byte separators
/// are matched whole); decimals - the target fraction digit count, clamped to
/// >= 0.
/// Grammar: an optional leading '+' or '-' (first byte only), then ASCII
/// digits and the ignored grouping separators ',' '_' and ' ' (ignored both
/// before and after the decimal separator), with at most one occurrence of
/// decimal_sep. The integer part may be empty when a fraction is present
/// (".5"); a trailing decimal_sep is allowed ("5."); when decimal_sep is empty
/// no fraction boundary is recognized, so the whole text is an integer and
/// decimals > 0 right-pads with zeros.
/// Returns: Ok(value) where value = integer_digits * 10^decimals + fraction
/// digits right-padded with zeros to exactly `decimals` digits. The sign is
/// applied once; "-0" parses to 0.
/// Error case: Err("l10n: ...") -- left-to-right, first error wins: empty
/// input, no digits, a second decimal_sep, any byte that is not a digit, a
/// grouping separator or the decimal_sep, more fraction digits than `decimals`,
/// or a magnitude that would not fit the 64-bit signed range.
/// Examples: ("1,234.5", ".", 2) -> Ok(123450); ("1.23", ".", 3) ->
/// Ok(1230); ("-0.5", ",", 1) -> Ok(-5); ("1.234", ".", 2) ->
/// Err("l10n: too many decimals").
/// Complexity: O(len(text) + decimals).
pub fn l10n_decimal_parse(text: Str, decimal_sep: Str, decimals: Int) -> Result[Int, Str] {
  var dec = decimals;
  if dec < 0 {
    dec = 0;
  }
  let n = text.len();
  if n == 0 {
    return _parse_err("l10n: empty input");
  }
  var neg = false;
  var i = 0;
  let first = string.byte_at(text, 0);
  if first == _L10N_MINUS {
    neg = true;
    i = 1;
  } elif first == _L10N_PLUS {
    i = 1;
  }
  var int_mag: Int = 0;
  var frac_mag: Int = 0;
  var frac_digits = 0;
  var seen_sep = false;
  var seen_digit = false;
  while i < n {
    let b = string.byte_at(text, i);
    if b >= _L10N_ZERO && b <= _L10N_NINE {
      let d = (b as Int) - 48;
      if seen_sep {
        if frac_digits >= dec {
          return _parse_err("l10n: too many decimals");
        }
        if frac_mag > _L10N_INT_MAX_DIV10 {
          return _parse_err("l10n: number too large");
        }
        if frac_mag == _L10N_INT_MAX_DIV10 && d > _L10N_INT_MAX_LAST_DIGIT {
          return _parse_err("l10n: number too large");
        }
        frac_mag = frac_mag * 10 + d;
        frac_digits = frac_digits + 1;
      } else {
        if int_mag > _L10N_INT_MAX_DIV10 {
          return _parse_err("l10n: number too large");
        }
        if int_mag == _L10N_INT_MAX_DIV10 && d > _L10N_INT_MAX_LAST_DIGIT {
          return _parse_err("l10n: number too large");
        }
        int_mag = int_mag * 10 + d;
      }
      seen_digit = true;
      i = i + 1;
    } elif decimal_sep.len() > 0 && _matches_at(text, i, decimal_sep) {
      if seen_sep {
        return _parse_err("l10n: multiple decimal separators");
      }
      seen_sep = true;
      i = i + decimal_sep.len();
    } elif _is_group_sep(b) {
      i = i + 1;
    } else {
      return _parse_err("l10n: unexpected character: " + string.str_slice(text, i, i + 1));
    }
  }
  if !seen_digit {
    return _parse_err("l10n: no digits");
  }
  var frac_scaled = frac_mag;
  var k = frac_digits;
  while k < dec && frac_scaled != 0 {
    if frac_scaled > _L10N_INT_MAX_DIV10 {
      return _parse_err("l10n: number too large");
    }
    frac_scaled = frac_scaled * 10;
    k = k + 1;
  }
  var value = int_mag;
  var m = 0;
  while m < dec && value != 0 {
    if value > _L10N_INT_MAX_DIV10 {
      return _parse_err("l10n: number too large");
    }
    value = value * 10;
    m = m + 1;
  }
  if value > _L10N_INT_MAX - frac_scaled {
    return _parse_err("l10n: number too large");
  }
  value = value + frac_scaled;
  if neg {
    if value == 0 {
      return _parse_ok(0);
    }
    return _parse_ok(0 - value);
  }
  return _parse_ok(value);
}

/// Format permille (parts per thousand) as a percent-like number.
/// Params: permille - the integer permille value (12345 means 12.345, i.e.
/// 1234.5 percent); decimals - fraction digits of the percent number, clamped
/// to >= 0; group_sep / decimal_sep - separators used by the formatter.
/// Returns: permille/10 rendered with exactly `decimals` fraction digits,
/// where decimals >= 1 shifts the permille digits exactly (no overflow; the
/// tenths digit becomes the first fraction digit and further zeros are
/// appended), and decimals == 0 rounds half away from zero to whole percent
/// (12345 -> "1235"; -4 -> "0", the sign is dropped when nothing remains).
/// Examples: (12345, 1, ",", ".") -> "1,234.5"; (12345, 2, ",", ".") ->
/// "1,234.50"; (5, 1, ",", ".") -> "0.5"; (-12345, 0, ",", ".") -> "-1235".
/// Error case: none.
/// Complexity: O(digits + decimals).
pub fn l10n_permille_format(permille: Int, decimals: Int, group_sep: Str, decimal_sep: Str) -> Str {
  var dec = decimals;
  if dec < 0 {
    dec = 0;
  }
  let neg = permille < 0;
  let digits = _abs_digits(permille);
  var int_digits = "0";
  var tenth = digits;
  if digits.len() >= 2 {
    int_digits = string.str_slice(digits, 0, digits.len() - 1);
    tenth = string.str_slice(digits, digits.len() - 1, digits.len());
  }
  if dec == 0 {
    let mag = _round_tenth_up(int_digits, tenth);
    if _digits_is_zero(mag) {
      return mag;
    }
    if neg {
      return "-" + _group_digits(mag, group_sep);
    }
    return _group_digits(mag, group_sep);
  }
  var frac = tenth;
  var k = 1;
  while k < dec {
    frac = frac + "0";
    k = k + 1;
  }
  var out = _group_digits(int_digits, group_sep) + decimal_sep + frac;
  if neg {
    out = "-" + out;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Magnitude digit string of n with no sign, exact for every 64-bit value
// including the minimum (which has no representable positive counterpart).
fn _abs_digits(n: Int) -> Str {
  let s = convert.int_to_string(n);
  if s.len() > 0 {
    if string.byte_at(s, 0) == _L10N_MINUS {
      return string.str_slice(s, 1, s.len());
    }
  }
  return s;
}

// Insert sep every three digits counted from the right; an empty sep returns
// the digits untouched.
fn _group_digits(digits: Str, sep: Str) -> Str {
  let n = digits.len();
  if sep.len() == 0 {
    return digits;
  }
  var out = "";
  var i = 0;
  while i < n {
    if i > 0 && (n - i) % 3 == 0 {
      out = out + sep;
    }
    out = out + string.str_slice(digits, i, i + 1);
    i = i + 1;
  }
  return out;
}

// True when every byte of s is an ASCII '0'. s is non-empty by construction.
fn _digits_is_zero(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if string.byte_at(s, i) != _L10N_ZERO {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Add one to a non-empty ASCII digit string, propagating the carry.
fn _inc_digits(s: Str) -> Str {
  var i = s.len() - 1;
  while i >= 0 {
    let b = string.byte_at(s, i);
    if b == _L10N_NINE {
      i = i - 1;
    } else {
      let head = string.str_slice(s, 0, i);
      let mid = _digit_char(b + 1);
      var tail = "";
      var j = i + 1;
      while j < s.len() {
        tail = tail + "0";
        j = j + 1;
      }
      return head + mid + tail;
    }
  }
  var zeros = "";
  var z = 0;
  while z < s.len() {
    zeros = zeros + "0";
    z = z + 1;
  }
  return "1" + zeros;
}

// ASCII digit for a byte in '0'..'9' (callers pass '0'+1..'9'), one byte long.
fn _digit_char(b: UInt8) -> Str {
  let v = (b as Int) - 48;
  return string.str_slice("0123456789", v, v + 1);
}

// Round int_digits.tenth away from zero at the units digit: increment the
// integer digits when the tenths digit is 5 or more.
fn _round_tenth_up(int_digits: Str, tenth: Str) -> Str {
  if tenth.len() == 0 {
    return int_digits;
  }
  if string.byte_at(tenth, 0) < _L10N_FIVE {
    return int_digits;
  }
  return _inc_digits(int_digits);
}

// True when sub occurs in text at byte offset at (byte-wise comparison).
fn _matches_at(text: Str, at: Int, sub: Str) -> Bool {
  if sub.len() == 0 {
    return false;
  }
  if at + sub.len() > text.len() {
    return false;
  }
  var i = 0;
  while i < sub.len() {
    if string.byte_at(text, at + i) != string.byte_at(sub, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// The ignored grouping bytes: comma, underscore and space.
fn _is_group_sep(b: UInt8) -> Bool {
  if b == _L10N_COMMA {
    return true;
  }
  if b == _L10N_UNDERSCORE {
    return true;
  }
  if b == _L10N_SPACE {
    return true;
  }
  return false;
}

// Result constructors live in these leaves: constructing Ok/Err inline in a
// function that also returns a struct value miscompiles on XIOM v0.61.3.
fn _parse_ok(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

fn _parse_err(m: Str) -> Result[Int, Str] {
  return Err(m);
}
