// XIOM -- xiom.humanize: human-readable bytes, durations, counts, ordinals, lists
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure integer formatting: no floating point, no locale data. Every rule is
// pinned in SPEC.md and exercised by tests/test_conformance.xi; the module
// depends only on xiom.convert's int_to_string from xiom.std.
//
// Design notes:
// - bytes: the magnitude selects a unit index 0..5 (1000- or 1024-based); the
//   scaled magnitude is rounded half away from zero using integer arithmetic,
//   and the sign is applied last, so every 64-bit input -- including the
//   minimum -- is exact.
// - durations: a fixed bucket stack (ms, s, m, h, d); the leading component is
//   always printed and the trailing one only when non-zero.
// - lists: elements are joined with ", " and the last pair with the caller's
//   conjunction; the Oxford comma is omitted.

module xiom.humanize

use xiom.convert;

/// Humanize a byte count with binary (1024) or decimal (1000) units.
/// Params: n - the byte count, any 64-bit signed integer (the sign is kept);
/// decimals - fraction digits, clamped to 0..3; binary - true selects 1024
/// with suffixes B, KiB, MiB, GiB, TiB, PiB, false selects 1000 with B, KB,
/// MB, GB, TB, PB.
/// Returns: the magnitude rounded half away from zero at `decimals` fraction
/// digits, one space, then the unit suffix. decimals == 0 prints an integer,
/// so base-unit values keep integer form ("999 B"); decimals > 0 always
/// prints exactly that many fraction digits, zero-padded.
/// Examples: (1500000, 1, false) -> "1.5 MB"; (2048, 0, true) -> "2 KiB";
/// (1536, 1, false) -> "1.5 KB"; (0, 0, false) -> "0 B";
/// (-1536, 1, false) -> "-1.5 KB"; (1536, 9, false) -> "1.536 KB" (clamped).
/// Error case: none.
/// Complexity: O(1).
pub fn humanize_bytes(n: Int, decimals: Int, binary: Bool) -> Str {
  let dec = _clamp_decimals(decimals);
  let base = _base_for(binary);
  let unit = _byte_unit(n, base);
  let pow = _byte_pow(base, unit);
  let scaled = _scaled_mag(n, pow, dec);
  let body = _format_scaled(scaled, dec) + " " + _byte_suffix(unit, binary);
  if n < 0 {
    return "-" + body;
  }
  return body;
}

/// Humanize a millisecond count as a compact duration.
/// Params: ms - the duration in milliseconds; non-positive input maps to
/// "0ms".
/// Returns: "Nms" for 0..999 (inclusive of 0 -> "0ms"), "Ns" with floored
/// seconds for 1000..59999, "Nm Ns" for 60000..3599999, "Nh Nm" for
/// 3600000..86399999, "Nd Nh" above. In the multi-component buckets the
/// trailing component is omitted when zero, so 60000 -> "1m",
/// 3600000 -> "1h", 86400000 -> "1d".
/// Examples: (850) -> "850ms"; (45000) -> "45s"; (125000) -> "2m 5s";
/// (3780000) -> "1h 3m"; (187200000) -> "2d 4h"; (0) -> "0ms";
/// (-5) -> "0ms".
/// Error case: none.
/// Complexity: O(1).
pub fn humanize_duration_ms(ms: Int) -> Str {
  if ms <= 0 {
    return "0ms";
  }
  if ms < 1000 {
    return int_to_string(ms) + "ms";
  }
  let secs = ms / 1000;
  if secs < 60 {
    return int_to_string(secs) + "s";
  }
  let mins = secs / 60;
  let rem_secs = secs % 60;
  if mins < 60 {
    if rem_secs == 0 {
      return int_to_string(mins) + "m";
    }
    return int_to_string(mins) + "m " + int_to_string(rem_secs) + "s";
  }
  let hours = mins / 60;
  let rem_mins = mins % 60;
  if hours < 24 {
    if rem_mins == 0 {
      return int_to_string(hours) + "h";
    }
    return int_to_string(hours) + "h " + int_to_string(rem_mins) + "m";
  }
  let days = hours / 24;
  let rem_hours = hours % 24;
  if rem_hours == 0 {
    return int_to_string(days) + "d";
  }
  return int_to_string(days) + "d " + int_to_string(rem_hours) + "h";
}

/// Humanize a count with an explicit singular and plural form.
/// Params: n - the count, any 64-bit signed integer; singular - used when the
/// magnitude is 1; plural_form - used otherwise (including 0).
/// Returns: "<n> <form>" with the sign kept: "1 item", "2 items", "-1 item",
/// "0 items".
/// Error case: none.
/// Complexity: O(digits(n)).
pub fn humanize_count(n: Int, singular: Str, plural_form: Str) -> Str {
  if n == 1 || n == -1 {
    return int_to_string(n) + " " + singular;
  }
  return int_to_string(n) + " " + plural_form;
}

/// Humanize an integer as an English ordinal.
/// Params: n - any 64-bit signed integer; the sign is kept and the suffix is
/// chosen from the magnitude's last two digits.
/// Returns: the decimal digits plus st/nd/rd/th: 1st, 2nd, 3rd, 4th, 11th,
/// 12th, 13th, 21st, 101st, 111th; negatives keep the sign and the magnitude
/// suffix ("-21st").
/// Error case: none.
/// Complexity: O(digits(n)).
pub fn humanize_ordinal(n: Int) -> Str {
  var mag = n % 100;
  if mag < 0 {
    mag = 0 - mag;
  }
  let last = mag % 10;
  var suffix = "th";
  if mag == 11 || mag == 12 || mag == 13 {
    suffix = "th";
  } elif last == 1 {
    suffix = "st";
  } elif last == 2 {
    suffix = "nd";
  } elif last == 3 {
    suffix = "rd";
  }
  return int_to_string(n) + suffix;
}

/// Humanize a list of strings with a conjunction word.
/// Params: items - the elements, read only; conjunction - the joining word
/// ("and", "or", ...), used verbatim.
/// Returns: "" for no items; the item itself for one; "a and b" for two; for
/// three or more every element except the last is followed by ", " and the
/// last is joined with the conjunction (the Oxford comma is omitted):
/// "a, b and c".
/// Examples: (["a"], "and") -> "a"; (["a", "b"], "and") -> "a and b";
/// (["a", "b", "c"], "or") -> "a, b or c".
/// Error case: none.
/// Complexity: O(total bytes of items).
pub fn humanize_list(items: &Vec[Str], conjunction: Str) -> Str {
  let n = items.len();
  if n == 0 {
    return "";
  }
  if n == 1 {
    let only: Str = items[0];
    return only;
  }
  if n == 2 {
    let first: Str = items[0];
    let second: Str = items[1];
    return first + " " + conjunction + " " + second;
  }
  var out = "";
  var i = 0;
  while i < n - 2 {
    let part: Str = items[i];
    out = out + part + ", ";
    i = i + 1;
  }
  let penultimate: Str = items[n - 2];
  let last: Str = items[n - 1];
  return out + penultimate + " " + conjunction + " " + last;
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

// Fraction digits are pinned to 0..3; anything outside is clamped.
fn _clamp_decimals(decimals: Int) -> Int {
  if decimals < 0 {
    return 0;
  }
  if decimals > 3 {
    return 3;
  }
  return decimals;
}

// 10^dec for dec in 0..3.
fn _pow10(dec: Int) -> Int {
  var p: Int = 1;
  var k = 0;
  while k < dec {
    p = p * 10;
    k = k + 1;
  }
  return p;
}

// The unit base: 1024 for binary units, 1000 for decimal ones.
fn _base_for(binary: Bool) -> Int {
  if binary {
    return 1024;
  }
  return 1000;
}

// True when |v| >= p, without ever negating v (safe for the 64-bit minimum).
fn _mag_at_least(v: Int, p: Int) -> Bool {
  if v < 0 {
    return v <= 0 - p;
  }
  return v >= p;
}

// Largest unit index 0..5 with |n| >= base^index; 0 for |n| below the base.
fn _byte_unit(n: Int, base: Int) -> Int {
  var u = 0;
  var p = base;
  var k = 1;
  while k <= 5 {
    if _mag_at_least(n, p) {
      u = k;
    }
    if k < 5 {
      p = p * base;
    }
    k = k + 1;
  }
  return u;
}

// base^unit for unit in 0..5 (at most 10^15 or 2^50, so this cannot overflow).
fn _byte_pow(base: Int, unit: Int) -> Int {
  var p: Int = 1;
  var k = 0;
  while k < unit {
    p = p * base;
    k = k + 1;
  }
  return p;
}

// |v| for values already bounded well below the 64-bit minimum (quotients and
// remainders of a 64-bit value divided by base^unit, so |v| <= max(base, 8)).
fn _abs_small(v: Int) -> Int {
  if v < 0 {
    return 0 - v;
  }
  return v;
}

// |n| scaled by 10^dec in units of pow = base^unit, rounded half away from
// zero. q and r are n/pow and n%pow; their magnitudes are bounded by base, so
// the multiplications below are exact for every 64-bit n.
fn _scaled_mag(n: Int, pow: Int, dec: Int) -> Int {
  let q = n / pow;
  let r = n % pow;
  let mul = _pow10(dec);
  let whole = _abs_small(q) * mul;
  let frac_num = _abs_small(r) * mul;
  let floor_part = frac_num / pow;
  let rem = frac_num % pow;
  if rem * 2 >= pow {
    return whole + floor_part + 1;
  }
  return whole + floor_part;
}

// A non-negative scaled value as a fixed-point string with exactly `dec`
// fraction digits (dec == 0 prints a plain integer).
fn _format_scaled(scaled: Int, dec: Int) -> Str {
  if dec == 0 {
    return int_to_string(scaled);
  }
  let div = _pow10(dec);
  let int_part = scaled / div;
  let frac = scaled % div;
  var frac_str = int_to_string(frac);
  while frac_str.len() < dec {
    frac_str = "0" + frac_str;
  }
  return int_to_string(int_part) + "." + frac_str;
}

// Unit suffix for index 0..5; index >= 5 is PiB/PB.
fn _byte_suffix(unit: Int, binary: Bool) -> Str {
  if unit == 0 {
    return "B";
  }
  if unit == 1 {
    if binary {
      return "KiB";
    }
    return "KB";
  }
  if unit == 2 {
    if binary {
      return "MiB";
    }
    return "MB";
  }
  if unit == 3 {
    if binary {
      return "GiB";
    }
    return "GB";
  }
  if unit == 4 {
    if binary {
      return "TiB";
    }
    return "TB";
  }
  if binary {
    return "PiB";
  }
  return "PB";
}
