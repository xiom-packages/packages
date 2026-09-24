// XIOM -- xiom.thermo: exact integer unit conversions
//   temperature (Celsius / Fahrenheit / Kelvin), pressure (Pa / hPa / bar /
//   atmosphere), energy (joule / calorie) and speed (km/h <-> m/s)
// Port task: replace the xiom.thermo placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every quantity entering and leaving this module is an integer in a unit
// spelled out in the function name:
//   * temperatures in milli-degrees   (5000 = 5.000 C, 212000 = 212.000 F,
//     273150 = 273.150 K)
//   * pressure in pascal, hectopascal (pa / 100), micro-bar (1 Pa = 10 ubar,
//     1 bar = 100000 Pa) and micro-atmosphere (1 atm = 101325 Pa exactly)
//   * energy in milli-joules and milli-calories (1 cal = 4.184 J exactly,
//     the thermochemical calorie)
//   * speed in milli-km/h and milli-m/s
// All divisions are integer divisions that truncate toward zero (XIOM Int
// semantics), so every function that divides rounds toward zero -- never
// floor -- and loses at most one milli-unit. Functions that only add,
// subtract or multiply (c<->K, Pa->micro-bar) are exact for every input that
// fits Int. See SPEC.md for the formulas, the rounding rules and the test plan.

module xiom.thermo

// --------------------------------------------------
//  Temperature
// --------------------------------------------------

/// Celsius to Fahrenheit: f_milli = c_milli * 9 / 5 + 32000.
/// The scaled value c*9 is divided by 5 with truncation toward zero, so a
/// fractional milli-degree rounds toward zero (e.g. 1 mC -> 32001 mF).
/// Params: c_milli - temperature in milli-degrees Celsius.
/// Returns: temperature in milli-degrees Fahrenheit.
/// Error case: none.
/// Complexity: O(1).
pub fn thermo_c_to_f_milli(c_milli: Int) -> Int {
  return c_milli * 9 / 5 + 32000;
}

/// Fahrenheit to Celsius: c_milli = (f_milli - 32000) * 5 / 9.
/// The offset numerator (f - 32000) * 5 is divided by 9 with truncation
/// toward zero, so a fractional milli-degree rounds toward zero.
/// Params: f_milli - temperature in milli-degrees Fahrenheit.
/// Returns: temperature in milli-degrees Celsius.
/// Error case: none.
/// Complexity: O(1).
pub fn thermo_f_to_c_milli(f_milli: Int) -> Int {
  return (f_milli - 32000) * 5 / 9;
}

/// Celsius to Kelvin: k_milli = c_milli + 273150 (0 C = 273.15 K).
/// Exact: only an addition, no division.
/// Params: c_milli - temperature in milli-degrees Celsius.
/// Returns: temperature in milli-kelvin.
/// Error case: none.
/// Complexity: O(1).
pub fn thermo_c_to_k_milli(c_milli: Int) -> Int {
  return c_milli + 273150;
}

/// Kelvin to Celsius: c_milli = k_milli - 273150.
/// Exact: only a subtraction, no division.
/// Params: k_milli - temperature in milli-kelvin.
/// Returns: temperature in milli-degrees Celsius.
/// Error case: none.
/// Complexity: O(1).
pub fn thermo_k_to_c_milli(k_milli: Int) -> Int {
  return k_milli - 273150;
}

/// Fahrenheit to Kelvin: F -> C -> K, i.e. (f - 32000) * 5 / 9 + 273150.
/// Composed of the two functions above: the single division truncates toward
/// zero once, so the result can deviate by 1 mK from a float formula that
/// rounds the single real-valued result (documented in SPEC.md section 4).
/// Params: f_milli - temperature in milli-degrees Fahrenheit.
/// Returns: temperature in milli-kelvin.
/// Error case: none.
/// Complexity: O(1).
pub fn thermo_f_to_k_milli(f_milli: Int) -> Int {
  return thermo_c_to_k_milli(thermo_f_to_c_milli(f_milli));
}

/// Kelvin to Fahrenheit: K -> C -> F, i.e. (k - 273150) * 9 / 5 + 32000.
/// Composed of the two functions above: the single division truncates toward
/// zero once, so the result can deviate by 1 mF from a float formula that
/// rounds the single real-valued result (documented in SPEC.md section 4).
/// Params: k_milli - temperature in milli-kelvin.
/// Returns: temperature in milli-degrees Fahrenheit.
/// Error case: none.
/// Complexity: O(1).
pub fn thermo_k_to_f_milli(k_milli: Int) -> Int {
  return thermo_c_to_f_milli(thermo_k_to_c_milli(k_milli));
}

/// True when k_milli is at or above absolute zero (0 K).
/// Purely a comparison: no clamping is applied by any conversion function.
/// Params: k_milli - temperature in milli-kelvin.
/// Returns: true iff k_milli >= 0.
/// Error case: none.
/// Complexity: O(1).
pub fn thermo_above_absolute_zero_k_milli(k_milli: Int) -> Bool {
  return k_milli >= 0;
}

// --------------------------------------------------
//  Pressure
// --------------------------------------------------

/// Pascal to hectopascal: hpa = pa / 100 (1 hPa = 100 Pa = 1 mbar).
/// Integer division truncates toward zero (101325 Pa -> 1013 hPa).
/// Params: pa - pressure in pascal.
/// Returns: pressure in hectopascal.
/// Error case: none.
/// Complexity: O(1).
pub fn thermo_pa_to_hpa(pa: Int) -> Int {
  return pa / 100;
}

/// Pascal to micro-bar: ubar = pa * 10 (1 Pa = 10 ubar, 1 bar = 100000 Pa).
/// Exact: only a multiplication, no division.
/// Params: pa - pressure in pascal.
/// Returns: pressure in micro-bar.
/// Error case: none.
/// Complexity: O(1).
pub fn thermo_pa_to_bar_micro(pa: Int) -> Int {
  return pa * 10;
}

/// Pascal to micro-atmosphere: uatm = pa * 1000000 / 101325.
/// One standard atmosphere is 101325 Pa exactly; the division truncates
/// toward zero, so 101325 Pa -> 1000000 uatm exactly and 1 Pa -> 9 uatm.
/// Params: pa - pressure in pascal.
/// Returns: pressure in micro-atmosphere.
/// Error case: none.
/// Complexity: O(1).
pub fn thermo_pa_to_atm_micro(pa: Int) -> Int {
  return pa * 1000000 / 101325;
}

// --------------------------------------------------
//  Energy
// --------------------------------------------------

/// Joule to calorie: mcal = j_milli * 1000 / 4184 (1 cal = 4.184 J).
/// The division truncates toward zero: 1 J -> 239 mcal (from 239.005 mcal).
/// Params: j_milli - energy in milli-joules.
/// Returns: energy in milli-calories.
/// Error case: none.
/// Complexity: O(1).
pub fn thermo_j_to_cal_milli(j_milli: Int) -> Int {
  return j_milli * 1000 / 4184;
}

/// Calorie to joule: j_milli = cal_milli * 4184 / 1000 (1 cal = 4.184 J).
/// The division truncates toward zero: 1 mcal -> 4 mJ (from 4.184 mJ).
/// Params: cal_milli - energy in milli-calories.
/// Returns: energy in milli-joules.
/// Error case: none.
/// Complexity: O(1).
pub fn thermo_cal_to_j_milli(cal_milli: Int) -> Int {
  return cal_milli * 4184 / 1000;
}

// --------------------------------------------------
//  Speed
// --------------------------------------------------

/// Kilometres per hour to metres per second: ms = kmh * 1000 / 3600.
/// The division truncates toward zero: 36 km/h -> 10 m/s exactly,
/// 10 km/h -> 2777 mm/s (from 2777.77 mm/s).
/// Params: kmh_milli - speed in milli-km/h.
/// Returns: speed in milli-m/s.
/// Error case: none.
/// Complexity: O(1).
pub fn thermo_kmh_to_ms_milli(kmh_milli: Int) -> Int {
  return kmh_milli * 1000 / 3600;
}

/// Metres per second to kilometres per hour: kmh = ms * 3600 / 1000.
/// The division truncates toward zero: 1 m/s -> 3600 mkm/h exactly,
/// 1 mm/s -> 3 mkm/h (from 3.6 mkm/h).
/// Params: ms_milli - speed in milli-m/s.
/// Returns: speed in milli-km/h.
/// Error case: none.
/// Complexity: O(1).
pub fn thermo_ms_to_kmh_milli(ms_milli: Int) -> Int {
  return ms_milli * 3600 / 1000;
}
