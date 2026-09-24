// XIOM -- xiom.electronics: resistor color codes, E24 series, voltage dividers, LED resistors
// Port task: replace the xiom.electronics placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure integer arithmetic -- no floats anywhere -- and every unit is spelled
// out in the API or documented per function: resistance in ohms, voltages in
// millivolts (mV), LED current in microamps (uA), tolerance in permille
// (1 permille = 0.1%).
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * all Str comparisons route through xiom.string.compare.str_compare,
//     never `==` (BUG 17: `==` on Str values read from a Vec lowers to a
//     pointer comparison).
//   * the color tables are if-chains, not matches on Str.
// See SPEC.md for the color tables, formulas, rounding rules, the error
// catalog and the test plan.

module xiom.electronics

use xiom.string.compare;

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

// --------------------------------------------------
//  Internal helpers
// --------------------------------------------------

// True when `a` and `b` are byte-equal. BUG 17 discipline: never `==` on Str.
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when `v` is one of the five tolerance-band colors.
// (green is both a digit color and a tolerance color.)
fn _is_tolerance_color(v: Str) -> Bool {
  if _streq(v, "brown") { return true; }
  if _streq(v, "red") { return true; }
  if _streq(v, "gold") { return true; }
  if _streq(v, "silver") { return true; }
  if _streq(v, "green") { return true; }
  return false;
}

// Digit for `color`, or `fallback` when the color is unknown. The fallback is
// chosen by the caller to be outside the digit range (0..9).
fn _digit_or(color: Str, fallback: Int) -> Int {
  let d = electron_color_digit(color);
  match d {
    Some(v) => { return v; },
    None => {},
  }
  return fallback;
}

// Decade exponent for `color`, or `fallback` when unknown.
fn _multiplier_or(color: Str, fallback: Int) -> Int {
  let d = electron_color_multiplier(color);
  match d {
    Some(v) => { return v; },
    None => {},
  }
  return fallback;
}

// 10^e, e in 0..9 (the multiplier-band decade exponents). O(e).
fn _pow10(e: Int) -> Int {
  var r = 1;
  var i = 0;
  while i < e {
    r = r * 10;
    i = i + 1;
  }
  return r;
}

// The i-th nominal E24 value, i in 0..23, ascending; -1 when out of range.
fn _e24_at(i: Int) -> Int {
  if i == 0 { return 10; }
  if i == 1 { return 11; }
  if i == 2 { return 12; }
  if i == 3 { return 13; }
  if i == 4 { return 15; }
  if i == 5 { return 16; }
  if i == 6 { return 18; }
  if i == 7 { return 20; }
  if i == 8 { return 22; }
  if i == 9 { return 24; }
  if i == 10 { return 27; }
  if i == 11 { return 30; }
  if i == 12 { return 33; }
  if i == 13 { return 36; }
  if i == 14 { return 39; }
  if i == 15 { return 43; }
  if i == 16 { return 47; }
  if i == 17 { return 51; }
  if i == 18 { return 56; }
  if i == 19 { return 62; }
  if i == 20 { return 68; }
  if i == 21 { return 75; }
  if i == 22 { return 82; }
  if i == 23 { return 91; }
  return -1;
}

// Nearest nominal to the mantissa `m` in [10, 100]. The scan walks the sorted
// table and accepts a later nominal on a tie (`<=`), so ties resolve to the
// LARGER nominal. Callers guarantee 10 <= m <= 99.
fn _e24_nearest(m: Int) -> Int {
  var best = 10;
  var best_dist = -1;
  var i = 0;
  while i < 24 {
    let n = _e24_at(i);
    var d = n - m;
    if d < 0 { d = 0 - d; }
    if best_dist < 0 || d <= best_dist {
      best = n;
      best_dist = d;
    }
    i = i + 1;
  }
  return best;
}

// --------------------------------------------------
//  Public API
// --------------------------------------------------

/// Digit encoded by a color band: black=0, brown=1, ..., white=9.
/// Params: color - lowercase color name.
/// Returns: Some(digit) for black, brown, red, orange, yellow, green, blue,
/// violet, grey (gray is an alias), white; None otherwise, including the
/// empty string and any non-lowercase spelling.
/// Error case: none.
/// Complexity: O(1).
pub fn electron_color_digit(color: Str) -> Option[Int] {
  if _streq(color, "black") { return Some(0); }
  if _streq(color, "brown") { return Some(1); }
  if _streq(color, "red") { return Some(2); }
  if _streq(color, "orange") { return Some(3); }
  if _streq(color, "yellow") { return Some(4); }
  if _streq(color, "green") { return Some(5); }
  if _streq(color, "blue") { return Some(6); }
  if _streq(color, "violet") { return Some(7); }
  if _streq(color, "grey") { return Some(8); }
  if _streq(color, "gray") { return Some(8); }
  if _streq(color, "white") { return Some(9); }
  return None;
}

/// Decade exponent encoded by a multiplier band: the same ten digit colors as
/// electron_color_digit, read as powers of ten (red => 2 => x100).
/// Gold (-1) and silver (-2) multipliers of 5-band resistors are out of scope
/// for this 3/4-band model and return None.
/// Params: color - lowercase color name.
/// Returns: Some(exponent 0..9) for the ten digit colors; None otherwise.
/// Error case: none.
/// Complexity: O(1).
pub fn electron_color_multiplier(color: Str) -> Option[Int] {
  return electron_color_digit(color);
}

/// Tolerance band, in permille of the nominal value (1 permille = 0.1%):
/// brown 1% -> 10, red 2% -> 20, gold 5% -> 50, silver 10% -> 100,
/// green 0.5% -> 5.
/// Params: color - lowercase color name.
/// Returns: Some(permille) for the five tolerance colors; None otherwise
/// (grey/gray, black, blue, ... are not tolerance colors).
/// Error case: none.
/// Complexity: O(1).
pub fn electron_resistor_tolerance(color: Str) -> Option[Int] {
  if _streq(color, "brown") { return Some(10); }
  if _streq(color, "red") { return Some(20); }
  if _streq(color, "gold") { return Some(50); }
  if _streq(color, "silver") { return Some(100); }
  if _streq(color, "green") { return Some(5); }
  return None;
}

/// Resistance in ohms from 3 or 4 color bands.
/// 3 bands: digit, digit, multiplier => (d1*10 + d2) * 10^multiplier.
/// 4 bands: the 4th band is the tolerance; it does not change the value but
/// must still be a known tolerance color (brown, red, gold, silver, green).
/// Params: bands - the band colors, lowercase.
/// Returns: Ok(ohms) for a well-formed band list; Err("electronics: ...")
/// otherwise.
/// Error cases: band count not 3 or 4
/// ("electronics: resistor bands must be 3 or 4"); unknown digit, multiplier
/// or tolerance color, including gold/silver in the multiplier position
/// ("electronics: unknown color code").
/// Complexity: O(1).
pub fn electron_resistor_value(bands: &Vec[Str]) -> Result[Int, Str] {
  let n = bands.len();
  if n != 3 && n != 4 {
    return _err_int("electronics: resistor bands must be 3 or 4");
  }
  let d1 = _digit_or(bands[0], -1);
  let d2 = _digit_or(bands[1], -1);
  let m = _multiplier_or(bands[2], -1);
  if d1 < 0 || d2 < 0 || m < 0 {
    return _err_int("electronics: unknown color code");
  }
  if n == 4 {
    if !_is_tolerance_color(bands[3]) {
      return _err_int("electronics: unknown color code");
    }
  }
  return _ok_int((d1 * 10 + d2) * _pow10(m));
}

/// The 24 nominal E24 (5% series) values in the base decade, ascending:
/// 10, 11, 12, 13, 15, 16, 18, 20, 22, 24, 27, 30, 33, 36, 39, 43, 47, 51,
/// 56, 62, 68, 75, 82, 91.
/// Returns: a fresh Vec[Int] with exactly those 24 values.
/// Error case: none.
/// Complexity: O(1).
pub fn electron_e24_values() -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < 24 {
    out.push(_e24_at(i));
    i = i + 1;
  }
  return out;
}

/// Nearest E24 nominal, decade-scaled, for a resistance in ohms.
/// The value is normalised with integer division to a mantissa in [10, 100);
/// the nearest nominal to that mantissa is chosen (ties resolve to the LARGER
/// nominal) and multiplied back by the same power of ten. Because the search
/// stays inside the same decade, values above the decade top clamp to 91
/// scaled (e.g. 999 -> 910).
/// Examples: 47 -> 47, 50 -> 51, 14 -> 15, 5000 -> 5100, 999 -> 910.
/// Params: value - resistance in ohms.
/// Returns: the nearest E24 value; values below 10 ohms (including 0 and
/// negatives) pass through unchanged, the integer model covers the E24
/// decades from 10 ohms up.
/// Error case: none.
/// Complexity: O(1).
pub fn electron_nearest_e24(value: Int) -> Int {
  if value < 10 {
    return value;
  }
  var scale = 1;
  while value / scale >= 100 {
    scale = scale * 10;
  }
  let mantissa = value / scale;
  let nominal = _e24_nearest(mantissa);
  return nominal * scale;
}

/// Unloaded voltage divider output in millivolts: vin_mv * r2 / (r1 + r2).
/// Integer division truncates toward zero.
/// Params: vin_mv - input voltage in mV; r1_ohm - top resistor in ohms;
/// r2_ohm - bottom resistor (the one measured across) in ohms.
/// Returns: output voltage in mV; 0 when r1 + r2 == 0 (no division occurs).
/// Error case: none.
/// Complexity: O(1).
pub fn electron_voltage_divider_mv(vin_mv: Int, r1_ohm: Int, r2_ohm: Int) -> Int {
  let total = r1_ohm + r2_ohm;
  if total == 0 {
    return 0;
  }
  return vin_mv * r2_ohm / total;
}

/// Series resistor for an LED, in ohms: (supply_mv - forward_mv) * 1000 /
/// current_ua. Integer division truncates toward zero.
/// Params: supply_mv - supply voltage in mV; forward_mv - LED forward voltage
/// in mV; current_ua - target LED current in microamps.
/// Returns: Ok(ohms) on success, Err("electronics: ...") otherwise.
/// Error cases: current_ua <= 0 ("electronics: current must be positive",
/// checked first); supply_mv <= forward_mv
/// ("electronics: supply must exceed forward voltage"). Both checks run
/// before any division.
/// Complexity: O(1).
pub fn electron_led_resistor_ohm(supply_mv: Int, forward_mv: Int, current_ua: Int) -> Result[Int, Str] {
  if current_ua <= 0 {
    return _err_int("electronics: current must be positive");
  }
  if supply_mv <= forward_mv {
    return _err_int("electronics: supply must exceed forward voltage");
  }
  return _ok_int((supply_mv - forward_mv) * 1000 / current_ua);
}
