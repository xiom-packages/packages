// XIOM -- xiom.validation: format validators (email, IP, hex, UUID, slug, dates, ports)
// Port task: create the xiom.validation package as a real, tested, pure-XIOM
// module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// What is covered (see SPEC.md for the exact per-validator rules and the test
// plan):
//   * email: exactly one @; 1..64 byte local part of [A-Za-z0-9._%+-] with no
//     leading/trailing/consecutive dots; dotted domain labels of [A-Za-z0-9-]
//     with no leading/trailing '-', at least one dot, and a letter-only TLD of
//     length >= 2; ASCII only;
//   * IPv4: exactly four dot-separated decimal parts 0..255, no leading zeros
//     unless the part is exactly "0";
//   * IPv6: 1..4 hex digits per group, 2..8 groups, at most one "::" standing
//     for one or more zero groups, no stray single ':' at either end;
//   * hex: non-empty [0-9A-Fa-f];
//   * UUID: 8-4-4-4-12 hex groups separated by hyphens, case-insensitive;
//   * slug: non-empty [a-z0-9] words joined by single '-' separators;
//   * date: proleptic Gregorian Y-M-D with the century leap rules, year >= 1;
//   * port: 1..65535 inclusive.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; every scan is byte-wise over the input Str.
//   * All byte reads are widened to Int space once, in _byte_at_i
//     (`(string.byte_at(s, i) as Int) & 0xFF`), so no UInt8 value is ever
//     compared against an integer literal.
//   * No Vec values, no lambdas and no match arms: the validators return plain
//     Bool/Int and use only if/elif/else and while.
//   * No Str equality is performed here, so xiom.string.compare is not
//     imported (BUG 17 concerns Str comparisons in callers/tests).
//
// Pragmatic validators by design: the accepted syntax is a documented subset
// of RFC 5322 (email) and RFC 4291 (IPv6); see SPEC.md section 2.

module xiom.validation

use xiom.string;

// --------------------------------------------------
//  Byte constants (Int space)
// --------------------------------------------------

const _VAL_AT: Int = 64;
const _VAL_COLON: Int = 58;
const _VAL_DASH: Int = 45;
const _VAL_DOT: Int = 46;
const _VAL_PERCENT: Int = 37;
const _VAL_PLUS: Int = 43;
const _VAL_UNDERSCORE: Int = 95;

// --------------------------------------------------
//  Shared helpers
// --------------------------------------------------

// Read byte i of s widened to Int space (0..255). Every byte read in this
// module goes through here, so byte comparisons never touch UInt8 values.
fn _byte_at_i(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// True for an ASCII digit byte (0x30-0x39).
fn _is_ascii_digit(c: Int) -> Bool {
  return c >= 48 && c <= 57;
}

// True for an ASCII uppercase letter byte (0x41-0x5A).
fn _is_ascii_upper(c: Int) -> Bool {
  return c >= 65 && c <= 90;
}

// True for an ASCII lowercase letter byte (0x61-0x7A).
fn _is_ascii_lower(c: Int) -> Bool {
  return c >= 97 && c <= 122;
}

// True for an ASCII letter byte (either case).
fn _is_ascii_alpha(c: Int) -> Bool {
  if _is_ascii_upper(c) {
    return true;
  }
  return _is_ascii_lower(c);
}

// True for [A-Za-z0-9].
fn _is_ascii_alnum(c: Int) -> Bool {
  if _is_ascii_alpha(c) {
    return true;
  }
  return _is_ascii_digit(c);
}

// True for a hex digit byte (0-9, a-f, A-F).
fn _is_hex_digit(c: Int) -> Bool {
  if _is_ascii_digit(c) {
    return true;
  }
  if c >= 65 && c <= 70 {
    return true;
  }
  return c >= 97 && c <= 102;
}

// True for an email local-part byte: [A-Za-z0-9._%+-].
fn _is_email_local_char(c: Int) -> Bool {
  if _is_ascii_alnum(c) {
    return true;
  }
  if c == _VAL_DOT {
    return true;
  }
  if c == _VAL_UNDERSCORE {
    return true;
  }
  if c == _VAL_PERCENT {
    return true;
  }
  if c == _VAL_PLUS {
    return true;
  }
  return c == _VAL_DASH;
}

// True for a slug byte: [a-z0-9].
fn _is_slug_char(c: Int) -> Bool {
  if _is_ascii_lower(c) {
    return true;
  }
  return _is_ascii_digit(c);
}

// Proleptic Gregorian leap-year rule: divisible by 4, except centuries,
// except every 400 years. 2000 and 2024 are leap; 1900 and 2100 are not.
fn _is_leap_year(y: Int) -> Bool {
  if y % 4 != 0 {
    return false;
  }
  if y % 100 != 0 {
    return true;
  }
  return y % 400 == 0;
}

// Days in `month` of `year`; the caller has already checked month 1..12.
fn _days_in_month(y: Int, m: Int) -> Int {
  if m == 2 {
    if _is_leap_year(y) {
      return 29;
    }
    return 28;
  }
  if m == 4 {
    return 30;
  }
  if m == 6 {
    return 30;
  }
  if m == 9 {
    return 30;
  }
  if m == 11 {
    return 30;
  }
  return 31;
}

// Count the hex groups in s[start..stop) for one side of an IPv6 address,
// with each group 1..4 hex digits and single ':' separators. Returns the
// group count, or -1 when the slice is malformed. An empty slice yields 0
// (the caller decides whether that is allowed).
fn _v6_scan_groups(s: Str, start: Int, stop: Int) -> Int {
  if start >= stop {
    return 0;
  }
  var groups = 0;
  var digits = 0;
  var i = start;
  while i < stop {
    let c = _byte_at_i(s, i);
    if c == _VAL_COLON {
      if digits == 0 {
        return -1;
      }
      groups = groups + 1;
      digits = 0;
    } else {
      if !_is_hex_digit(c) {
        return -1;
      }
      digits = digits + 1;
      if digits > 4 {
        return -1;
      }
    }
    i = i + 1;
  }
  if digits == 0 {
    return -1;
  }
  return groups + 1;
}

// --------------------------------------------------
//  Email
// --------------------------------------------------

/// True when `s` is an ASCII email address of the documented pragmatic subset.
/// Params: s - candidate address.
/// Returns: true when s has exactly one `@`; a 1..64 byte local part made of
/// [A-Za-z0-9._%+-] that does not start or end with `.` and has no `..`; and a
/// domain of dot-separated labels of [A-Za-z0-9-] (no leading/trailing `-`)
/// with at least one dot and a final label of >= 2 ASCII letters. Bytes >=
/// 0x80 anywhere make the result false (ASCII only).
/// Error case: none.
/// Complexity: O(s.len()).
pub fn valid_is_email(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  var at = -1;
  var i = 0;
  while i < n {
    let c = _byte_at_i(s, i);
    if c >= 128 {
      return false;
    }
    if c == _VAL_AT {
      if at >= 0 {
        return false;
      }
      at = i;
    }
    i = i + 1;
  }
  if at < 0 {
    return false;
  }
  if at == 0 {
    return false;
  }
  if at == n - 1 {
    return false;
  }
  if at > 64 {
    return false;
  }
  // Local part: 1..64 bytes, no leading/trailing dot, no consecutive dots.
  var j = 0;
  var prev_dot = false;
  while j < at {
    let c = _byte_at_i(s, j);
    if c == _VAL_DOT {
      if j == 0 {
        return false;
      }
      if prev_dot {
        return false;
      }
      prev_dot = true;
    } elif _is_email_local_char(c) {
      prev_dot = false;
    } else {
      return false;
    }
    j = j + 1;
  }
  if prev_dot {
    return false;
  }
  // Domain: dotted labels of [A-Za-z0-9-], no leading/trailing '-'.
  var k = at + 1;
  var label_len = 0;
  var label_first_dash = false;
  var label_last_dash = false;
  var last_dot = at;
  while k < n {
    let c = _byte_at_i(s, k);
    if c == _VAL_DOT {
      if label_len == 0 {
        return false;
      }
      if label_first_dash {
        return false;
      }
      if label_last_dash {
        return false;
      }
      last_dot = k;
      label_len = 0;
      label_first_dash = false;
      label_last_dash = false;
    } else {
      if _is_ascii_alnum(c) {
        label_last_dash = false;
      } elif c == _VAL_DASH {
        if label_len == 0 {
          label_first_dash = true;
        }
        label_last_dash = true;
      } else {
        return false;
      }
      label_len = label_len + 1;
    }
    k = k + 1;
  }
  if label_len == 0 {
    return false;
  }
  if label_first_dash {
    return false;
  }
  if label_last_dash {
    return false;
  }
  if last_dot == at {
    return false;
  }
  // TLD: at least two ASCII letters.
  let tld_start = last_dot + 1;
  if n - tld_start < 2 {
    return false;
  }
  var t = tld_start;
  while t < n {
    if !_is_ascii_alpha(_byte_at_i(s, t)) {
      return false;
    }
    t = t + 1;
  }
  return true;
}

// --------------------------------------------------
//  IPv4
// --------------------------------------------------

/// True when `s` is a dotted-quad IPv4 address.
/// Params: s - candidate address.
/// Returns: true when s is exactly four dot-separated decimal parts, each
/// with value 0..255 and no leading zero unless the part is exactly "0"
/// (so "0.0.0.0" and "255.255.255.255" pass, "01.2.3.4" and "256.0.0.1"
/// fail). Empty parts, missing/extra parts, signs and non-digits fail.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn valid_is_ipv4(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  var parts = 0;
  var value = 0;
  var digits = 0;
  var lead_zero = false;
  var i = 0;
  while i < n {
    let c = _byte_at_i(s, i);
    if c == _VAL_DOT {
      if digits == 0 {
        return false;
      }
      if digits > 1 && lead_zero {
        return false;
      }
      parts = parts + 1;
      value = 0;
      digits = 0;
      lead_zero = false;
    } else {
      if !_is_ascii_digit(c) {
        return false;
      }
      if digits == 0 && c == 48 {
        lead_zero = true;
      }
      value = value * 10 + (c - 48);
      if value > 255 {
        return false;
      }
      digits = digits + 1;
      if digits > 3 {
        return false;
      }
    }
    i = i + 1;
  }
  if digits == 0 {
    return false;
  }
  if digits > 1 && lead_zero {
    return false;
  }
  parts = parts + 1;
  return parts == 4;
}

// --------------------------------------------------
//  IPv6
// --------------------------------------------------

/// True when `s` is an IPv6 address in the documented textual subset.
/// Params: s - candidate address.
/// Returns: true when s is 2..8 groups of 1..4 hex digits separated by single
/// colons, with at most one `::` that stands for one or more zero groups
/// (`::` alone means all-zero), and no stray single ':' at either end. An
/// embedded dotted-quad tail (e.g. "::ffff:192.168.0.1") is NOT accepted.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn valid_is_ipv6(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  // Locate a "::" run (if any); runs longer than two colons are malformed.
  var run = 0;
  var dc = -1;
  var dc_count = 0;
  var i = 0;
  while i < n {
    let c = _byte_at_i(s, i);
    if c == _VAL_COLON {
      run = run + 1;
    } else {
      if run > 2 {
        return false;
      }
      if run == 2 {
        if dc_count > 0 {
          return false;
        }
        dc = i - 2;
        dc_count = 1;
      }
      run = 0;
    }
    i = i + 1;
  }
  if run > 2 {
    return false;
  }
  if run == 2 {
    if dc_count > 0 {
      return false;
    }
    dc = n - 2;
  }
  if dc < 0 {
    return _v6_scan_groups(s, 0, n) == 8;
  }
  // With "::" the explicit groups must leave room for at least one zero group.
  let left = _v6_scan_groups(s, 0, dc);
  if left < 0 {
    return false;
  }
  let right = _v6_scan_groups(s, dc + 2, n);
  if right < 0 {
    return false;
  }
  return left + right <= 7;
}

// --------------------------------------------------
//  Hex and UUID
// --------------------------------------------------

/// True when `s` is a non-empty run of hex digits.
/// Params: s - candidate text.
/// Returns: true when every byte is in [0-9A-Fa-f] and s is non-empty.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn valid_is_hex(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  var i = 0;
  while i < n {
    if !_is_hex_digit(_byte_at_i(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// True when `s` is a canonical hyphenated UUID.
/// Params: s - candidate text.
/// Returns: true when s is exactly 36 bytes in the 8-4-4-4-12 shape with
/// hyphens at positions 8, 13, 18 and 23 and hex digits elsewhere; hex digit
/// case is not significant.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn valid_is_uuid(s: Str) -> Bool {
  if s.len() != 36 {
    return false;
  }
  var i = 0;
  while i < 36 {
    let c = _byte_at_i(s, i);
    if i == 8 || i == 13 || i == 18 || i == 23 {
      if c != _VAL_DASH {
        return false;
      }
    } else {
      if !_is_hex_digit(c) {
        return false;
      }
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Slug
// --------------------------------------------------

/// True when `s` is a lowercase dash-separated slug.
/// Params: s - candidate text.
/// Returns: true when s is non-empty and made of [a-z0-9] words joined by
/// single '-' separators: no leading, trailing or doubled dashes, and no
/// uppercase, underscore, space or non-ASCII byte.
/// Error case: none.
/// Complexity: O(s.len()).
pub fn valid_is_slug(s: Str) -> Bool {
  let n = s.len();
  if n == 0 {
    return false;
  }
  var i = 0;
  while i < n {
    let c = _byte_at_i(s, i);
    if c == _VAL_DASH {
      if i == 0 {
        return false;
      }
      if i == n - 1 {
        return false;
      }
      if _byte_at_i(s, i - 1) == _VAL_DASH {
        return false;
      }
    } elif !_is_slug_char(c) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Date and port
// --------------------------------------------------

/// True when (y, m, d) is a valid proleptic Gregorian calendar date.
/// Params: y - year, at least 1; m - month 1..12; d - day.
/// Returns: true when the month is in 1..12 and the day is in
/// 1..days_in_month(y, m), where February has 29 days only in a leap year
/// (2000 and 2024 yes; 1900 and 2100 no).
/// Error case: none.
/// Complexity: O(1).
pub fn valid_is_date_ymd(y: Int, m: Int, d: Int) -> Bool {
  if y < 1 {
    return false;
  }
  if m < 1 || m > 12 {
    return false;
  }
  if d < 1 {
    return false;
  }
  return d <= _days_in_month(y, m);
}

/// True when `n` is a usable TCP/UDP port number.
/// Params: n - candidate port.
/// Returns: true for 1..65535 inclusive; false for 0, negatives and values
/// above 65535.
/// Error case: none.
/// Complexity: O(1).
pub fn valid_is_port(n: Int) -> Bool {
  if n < 1 {
    return false;
  }
  return n <= 65535;
}
