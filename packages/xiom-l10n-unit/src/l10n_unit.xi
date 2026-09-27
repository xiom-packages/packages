// XIOM -- xiom.l10n.unit: exact integer unit conversion over an embedded
// rational-factor table, with affine temperatures and micro-unit values.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: a unit is an immutable table row -- category index, canonical
// symbol, English name, an exact rational factor num/den to the category
// base, and an affine offset in micro-units of the unit itself (temperature
// rows only, 0 elsewhere). A value is a signed fixed-point integer in
// micro-units (value_micro = value * 10^6). Nothing here uses floating
// point; the module depends only on xiom.string, xiom.string.compare and
// xiom.convert from xiom.std.
//
// Categories and bases (13): length (m), mass (kg), time (s), temperature
// (K), volume (l), area (m2), speed (m/s), pressure (Pa), energy (J),
// power (W), data (bit), angle (rad), frequency (Hz).
//
// Exactness policy: every factor is the exact SI/definitional rational for
// its unit, reduced, EXCEPT:
//   * deg/grad/turn depend on pi (irrational); the table uses the convergent
//     245850922/78256779 (relative error ~1.3e-17), documented in SPEC.md.
//   * eV = 1.602176634e-19 J exactly is 1602176634/10^28, whose reduced
//     denominator exceeds Int; the table stores the truncated reciprocal
//     1/6241509074460762607 (relative error < 1.6e-19).
//
// Affine temperatures: base_micro = (value_micro + offset) * num / den, so
// the offset is applied in the SOURCE unit before the rational factor. K has
// offset 0; degC adds 273150000 micro-K; degF adds 459670000 micro-degF
// (32 degF -> 0 degC -> 273.15 K exactly). Reverse conversions apply the
// factor first and subtract the offset afterwards.
//
// Rounding: every division truncates toward zero (C-style integer
// division). Conversion stages and their truncation points are documented
// in SPEC.md; conversions that would overflow Int are reported as typed
// errors, never silently wrapped.
//
// Naming: the package manifest is "xiom.l10n-unit", but the compiler module
// must be a dotted identifier (v0.61.3 rejects '-' in `module`
// declarations, error[P001] at 1:17), so the module is xiom.l10n.unit.

module xiom.l10n.unit

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _UN_ZERO: UInt8 = 48u8;
const _UN_NINE: UInt8 = 57u8;
const _UN_SPACE: UInt8 = 32u8;
const _UN_PLUS: UInt8 = 43u8;
const _UN_MINUS: UInt8 = 45u8;
const _UN_DOT: UInt8 = 46u8;
const _UN_INT_MAX: Int = 9223372036854775807;
const _UN_INT_MIN: Int = -9223372036854775807 - 1;
const _UN_INT_MAX_DIV10: Int = 922337203685477580;
const _UN_INT_MAX_LAST_DIGIT: Int = 7;
const _UN_MICRO: Int = 1000000;

const _UN_CAT_LENGTH: Int = 0;
const _UN_CAT_MASS: Int = 1;
const _UN_CAT_TIME: Int = 2;
const _UN_CAT_TEMPERATURE: Int = 3;
const _UN_CAT_VOLUME: Int = 4;
const _UN_CAT_AREA: Int = 5;
const _UN_CAT_SPEED: Int = 6;
const _UN_CAT_PRESSURE: Int = 7;
const _UN_CAT_ENERGY: Int = 8;
const _UN_CAT_POWER: Int = 9;
const _UN_CAT_DATA: Int = 10;
const _UN_CAT_ANGLE: Int = 11;
const _UN_CAT_FREQUENCY: Int = 12;
const _UN_CAT_COUNT: Int = 13;
const _UN_TOTAL: Int = 82;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// One unit row. `category` is 0..12 (see the category constants), `symbol`
/// the canonical case-sensitive ASCII symbol, `name` the English name, `num`
/// and `den` the exact positive rational factor to the category base (base =
/// value * num / den), and `offset` the affine offset in micro-units of the
/// unit itself, applied before the factor (temperature only; 0 elsewhere).
pub type Unit = {
  category: Int;
  symbol: Str;
  name: Str;
  num: Int;
  den: Int;
  offset: Int;
}

/// A parsed measurement: a micro-unit value plus the exact unit symbol it
/// was written with.
pub type Measurement = {
  symbol: Str;
  value_micro: Int;
}

// Result constructors live in these leaves: constructing Ok/Err inline in a
// function that also returns a struct value miscompiles on XIOM v0.61.3.
fn _un_ok(v: Unit) -> Result[Unit, Str] { return Ok(v); }
fn _un_err(m: Str) -> Result[Unit, Str] { return Err(m); }
fn _ms_ok(v: Measurement) -> Result[Measurement, Str] { return Ok(v); }
fn _ms_err(m: Str) -> Result[Measurement, Str] { return Err(m); }
fn _str_ok(s: Str) -> Result[Str, Str] { return Ok(s); }
fn _str_err(m: Str) -> Result[Str, Str] { return Err(m); }
fn _int_ok(n: Int) -> Result[Int, Str] { return Ok(n); }
fn _int_err(m: Str) -> Result[Int, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Character helpers
// ---------------------------------------------------------------------------

fn _is_digit(b: UInt8) -> Bool {
  return b >= _UN_ZERO && b <= _UN_NINE;
}

fn _is_space(b: UInt8) -> Bool {
  return b == _UN_SPACE;
}

// Decimal text of an Int with no sign, exact for every 64-bit value
// including the minimum (which has no representable positive counterpart).
fn _abs_digits(n: Int) -> Str {
  let s = convert.int_to_string(n);
  if s.len() > 0 {
    if string.byte_at(s, 0) == _UN_MINUS {
      return string.str_slice(s, 1, s.len());
    }
  }
  return s;
}

// True when `a` occurs in `text` at byte offset `at` (byte-wise compare).
fn _matches_at(text: Str, at: Int, a: Str) -> Bool {
  if a.len() == 0 { return false; }
  if at < 0 { return false; }
  if at + a.len() > text.len() { return false; }
  var i = 0;
  while i < a.len() {
    if string.byte_at(text, at + i) != string.byte_at(a, i) { return false; }
    i = i + 1;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Embedded unit table (see the header for the exactness policy)
// ---------------------------------------------------------------------------
//
// The table is three explicit if-chains of one-line rows in global index
// order; module-level table initializers are mis-materialized by v0.61.3,
// so the rows are compiled into comparison chains, as in xiom.iban.

fn _mk_un(cat: Int, sym: Str, nm: Str, n: Int, d: Int, off: Int) -> Unit {
  let v = Unit{ category: cat; symbol: sym; name: nm; num: n; den: d; offset: off };
  return v;
}

fn _missing() -> Unit {
  return _mk_un(0 - 1, "", "", 1, 1, 0);
}

// Global rows 0..24: length 0..9, mass 10..16, time 17..24.
fn _tab_a(i: Int) -> Unit {
  if i == 0 { return _mk_un(_UN_CAT_LENGTH, "m", "meter", 1, 1, 0); }
  if i == 1 { return _mk_un(_UN_CAT_LENGTH, "km", "kilometer", 1000, 1, 0); }
  if i == 2 { return _mk_un(_UN_CAT_LENGTH, "cm", "centimeter", 1, 100, 0); }
  if i == 3 { return _mk_un(_UN_CAT_LENGTH, "mm", "millimeter", 1, 1000, 0); }
  if i == 4 { return _mk_un(_UN_CAT_LENGTH, "um", "micrometer", 1, 1000000, 0); }
  if i == 5 { return _mk_un(_UN_CAT_LENGTH, "mi", "mile", 201168, 125, 0); }
  if i == 6 { return _mk_un(_UN_CAT_LENGTH, "yd", "yard", 1143, 1250, 0); }
  if i == 7 { return _mk_un(_UN_CAT_LENGTH, "ft", "foot", 381, 1250, 0); }
  if i == 8 { return _mk_un(_UN_CAT_LENGTH, "in", "inch", 127, 5000, 0); }
  if i == 9 { return _mk_un(_UN_CAT_LENGTH, "nmi", "nautical mile", 1852, 1, 0); }
  if i == 10 { return _mk_un(_UN_CAT_MASS, "kg", "kilogram", 1, 1, 0); }
  if i == 11 { return _mk_un(_UN_CAT_MASS, "g", "gram", 1, 1000, 0); }
  if i == 12 { return _mk_un(_UN_CAT_MASS, "mg", "milligram", 1, 1000000, 0); }
  if i == 13 { return _mk_un(_UN_CAT_MASS, "t", "tonne", 1000, 1, 0); }
  if i == 14 { return _mk_un(_UN_CAT_MASS, "lb", "pound", 45359237, 100000000, 0); }
  if i == 15 { return _mk_un(_UN_CAT_MASS, "oz", "ounce", 45359237, 1600000000, 0); }
  if i == 16 { return _mk_un(_UN_CAT_MASS, "st", "stone", 317514659, 50000000, 0); }
  if i == 17 { return _mk_un(_UN_CAT_TIME, "s", "second", 1, 1, 0); }
  if i == 18 { return _mk_un(_UN_CAT_TIME, "ms", "millisecond", 1, 1000, 0); }
  if i == 19 { return _mk_un(_UN_CAT_TIME, "us", "microsecond", 1, 1000000, 0); }
  if i == 20 { return _mk_un(_UN_CAT_TIME, "ns", "nanosecond", 1, 1000000000, 0); }
  if i == 21 { return _mk_un(_UN_CAT_TIME, "min", "minute", 60, 1, 0); }
  if i == 22 { return _mk_un(_UN_CAT_TIME, "h", "hour", 3600, 1, 0); }
  if i == 23 { return _mk_un(_UN_CAT_TIME, "d", "day", 86400, 1, 0); }
  if i == 24 { return _mk_un(_UN_CAT_TIME, "wk", "week", 604800, 1, 0); }
  return _missing();
}

// Global rows 25..52: temperature 25..27, volume 28..35, area 36..41,
// speed 42..45, pressure 46..52.
fn _tab_b(i: Int) -> Unit {
  if i == 0 { return _mk_un(_UN_CAT_TEMPERATURE, "K", "kelvin", 1, 1, 0); }
  if i == 1 { return _mk_un(_UN_CAT_TEMPERATURE, "degC", "degree Celsius", 1, 1, 273150000); }
  if i == 2 { return _mk_un(_UN_CAT_TEMPERATURE, "degF", "degree Fahrenheit", 5, 9, 459670000); }
  if i == 3 { return _mk_un(_UN_CAT_VOLUME, "l", "liter", 1, 1, 0); }
  if i == 4 { return _mk_un(_UN_CAT_VOLUME, "ml", "milliliter", 1, 1000, 0); }
  if i == 5 { return _mk_un(_UN_CAT_VOLUME, "m3", "cubic meter", 1000, 1, 0); }
  if i == 6 { return _mk_un(_UN_CAT_VOLUME, "gal-US", "US gallon", 473176473, 125000000, 0); }
  if i == 7 { return _mk_un(_UN_CAT_VOLUME, "qt-US", "US quart", 473176473, 500000000, 0); }
  if i == 8 { return _mk_un(_UN_CAT_VOLUME, "pt-US", "US pint", 473176473, 1000000000, 0); }
  if i == 9 { return _mk_un(_UN_CAT_VOLUME, "floz-US", "US fluid ounce", 473176473, 16000000000, 0); }
  if i == 10 { return _mk_un(_UN_CAT_VOLUME, "gal-UK", "imperial gallon", 454609, 100000, 0); }
  if i == 11 { return _mk_un(_UN_CAT_AREA, "m2", "square meter", 1, 1, 0); }
  if i == 12 { return _mk_un(_UN_CAT_AREA, "km2", "square kilometer", 1000000, 1, 0); }
  if i == 13 { return _mk_un(_UN_CAT_AREA, "ha", "hectare", 10000, 1, 0); }
  if i == 14 { return _mk_un(_UN_CAT_AREA, "acre", "acre", 316160658, 78125, 0); }
  if i == 15 { return _mk_un(_UN_CAT_AREA, "ft2", "square foot", 145161, 1562500, 0); }
  if i == 16 { return _mk_un(_UN_CAT_AREA, "in2", "square inch", 16129, 25000000, 0); }
  if i == 17 { return _mk_un(_UN_CAT_SPEED, "m/s", "meter per second", 1, 1, 0); }
  if i == 18 { return _mk_un(_UN_CAT_SPEED, "km/h", "kilometer per hour", 5, 18, 0); }
  if i == 19 { return _mk_un(_UN_CAT_SPEED, "mph", "mile per hour", 1397, 3125, 0); }
  if i == 20 { return _mk_un(_UN_CAT_SPEED, "kn", "knot", 463, 900, 0); }
  if i == 21 { return _mk_un(_UN_CAT_PRESSURE, "Pa", "pascal", 1, 1, 0); }
  if i == 22 { return _mk_un(_UN_CAT_PRESSURE, "kPa", "kilopascal", 1000, 1, 0); }
  if i == 23 { return _mk_un(_UN_CAT_PRESSURE, "bar", "bar", 100000, 1, 0); }
  if i == 24 { return _mk_un(_UN_CAT_PRESSURE, "mbar", "millibar", 100, 1, 0); }
  if i == 25 { return _mk_un(_UN_CAT_PRESSURE, "atm", "standard atmosphere", 101325, 1, 0); }
  if i == 26 { return _mk_un(_UN_CAT_PRESSURE, "psi", "pound per square inch", 8896443230521, 1290320000, 0); }
  if i == 27 { return _mk_un(_UN_CAT_PRESSURE, "mmHg", "millimeter of mercury", 26664477483, 200000000, 0); }
  return _missing();
}

// Global rows 53..81: energy 53..59, power 60..63, data 64..73, angle
// 74..77, frequency 78..81.
fn _tab_c(i: Int) -> Unit {
  if i == 0 { return _mk_un(_UN_CAT_ENERGY, "J", "joule", 1, 1, 0); }
  if i == 1 { return _mk_un(_UN_CAT_ENERGY, "kJ", "kilojoule", 1000, 1, 0); }
  if i == 2 { return _mk_un(_UN_CAT_ENERGY, "cal", "calorie", 523, 125, 0); }
  if i == 3 { return _mk_un(_UN_CAT_ENERGY, "kcal", "kilocalorie", 4184, 1, 0); }
  if i == 4 { return _mk_un(_UN_CAT_ENERGY, "kWh", "kilowatt hour", 3600000, 1, 0); }
  if i == 5 { return _mk_un(_UN_CAT_ENERGY, "BTU", "British thermal unit", 52752792631, 50000000, 0); }
  if i == 6 { return _mk_un(_UN_CAT_ENERGY, "eV", "electronvolt", 1, 6241509074460762607, 0); }
  if i == 7 { return _mk_un(_UN_CAT_POWER, "W", "watt", 1, 1, 0); }
  if i == 8 { return _mk_un(_UN_CAT_POWER, "kW", "kilowatt", 1000, 1, 0); }
  if i == 9 { return _mk_un(_UN_CAT_POWER, "MW", "megawatt", 1000000, 1, 0); }
  if i == 10 { return _mk_un(_UN_CAT_POWER, "hp", "horsepower", 37284993579113511, 50000000000000, 0); }
  if i == 11 { return _mk_un(_UN_CAT_DATA, "bit", "bit", 1, 1, 0); }
  if i == 12 { return _mk_un(_UN_CAT_DATA, "B", "byte", 8, 1, 0); }
  if i == 13 { return _mk_un(_UN_CAT_DATA, "KB", "kilobyte", 8000, 1, 0); }
  if i == 14 { return _mk_un(_UN_CAT_DATA, "KiB", "kibibyte", 8192, 1, 0); }
  if i == 15 { return _mk_un(_UN_CAT_DATA, "MB", "megabyte", 8000000, 1, 0); }
  if i == 16 { return _mk_un(_UN_CAT_DATA, "MiB", "mebibyte", 8388608, 1, 0); }
  if i == 17 { return _mk_un(_UN_CAT_DATA, "GB", "gigabyte", 8000000000, 1, 0); }
  if i == 18 { return _mk_un(_UN_CAT_DATA, "GiB", "gibibyte", 8589934592, 1, 0); }
  if i == 19 { return _mk_un(_UN_CAT_DATA, "TB", "terabyte", 8000000000000, 1, 0); }
  if i == 20 { return _mk_un(_UN_CAT_DATA, "TiB", "tebibyte", 8796093022208, 1, 0); }
  if i == 21 { return _mk_un(_UN_CAT_ANGLE, "rad", "radian", 1, 1, 0); }
  if i == 22 { return _mk_un(_UN_CAT_ANGLE, "deg", "degree", 122925461, 7043110110, 0); }
  if i == 23 { return _mk_un(_UN_CAT_ANGLE, "grad", "gradian", 122925461, 7825677900, 0); }
  if i == 24 { return _mk_un(_UN_CAT_ANGLE, "turn", "turn", 491701844, 78256779, 0); }
  if i == 25 { return _mk_un(_UN_CAT_FREQUENCY, "Hz", "hertz", 1, 1, 0); }
  if i == 26 { return _mk_un(_UN_CAT_FREQUENCY, "kHz", "kilohertz", 1000, 1, 0); }
  if i == 27 { return _mk_un(_UN_CAT_FREQUENCY, "MHz", "megahertz", 1000000, 1, 0); }
  if i == 28 { return _mk_un(_UN_CAT_FREQUENCY, "GHz", "gigahertz", 1000000000, 1, 0); }
  return _missing();
}

// Global row dispatch. `i` outside 0.._UN_TOTAL-1 yields the _missing
// sentinel (category -1).
fn _row(i: Int) -> Unit {
  if i < 0 { return _missing(); }
  if i < 25 { return _tab_a(i); }
  if i < 53 { return _tab_b(i - 25); }
  if i < _UN_TOTAL { return _tab_c(i - 53); }
  return _missing();
}

// Global index of the first row whose symbol equals `sym` byte-for-byte, or
// -1. Symbols are case-sensitive; symbols are unique in the table.
fn _find_symbol(sym: Str) -> Int {
  var i = 0;
  while i < _UN_TOTAL {
    let u = _row(i);
    let s = u.symbol;
    if compare.str_compare(s, sym) == 0 { return i; }
    i = i + 1;
  }
  return 0 - 1;
}

// Global start index of a category, or -1 when `category` is out of range.
fn _cat_start(category: Int) -> Int {
  if category == _UN_CAT_LENGTH { return 0; }
  if category == _UN_CAT_MASS { return 10; }
  if category == _UN_CAT_TIME { return 17; }
  if category == _UN_CAT_TEMPERATURE { return 25; }
  if category == _UN_CAT_VOLUME { return 28; }
  if category == _UN_CAT_AREA { return 36; }
  if category == _UN_CAT_SPEED { return 42; }
  if category == _UN_CAT_PRESSURE { return 46; }
  if category == _UN_CAT_ENERGY { return 53; }
  if category == _UN_CAT_POWER { return 60; }
  if category == _UN_CAT_DATA { return 64; }
  if category == _UN_CAT_ANGLE { return 74; }
  if category == _UN_CAT_FREQUENCY { return 78; }
  return 0 - 1;
}

// Number of rows in a category, or -1 when `category` is out of range.
fn _cat_size(category: Int) -> Int {
  if category == _UN_CAT_LENGTH { return 10; }
  if category == _UN_CAT_MASS { return 7; }
  if category == _UN_CAT_TIME { return 8; }
  if category == _UN_CAT_TEMPERATURE { return 3; }
  if category == _UN_CAT_VOLUME { return 8; }
  if category == _UN_CAT_AREA { return 6; }
  if category == _UN_CAT_SPEED { return 4; }
  if category == _UN_CAT_PRESSURE { return 7; }
  if category == _UN_CAT_ENERGY { return 7; }
  if category == _UN_CAT_POWER { return 4; }
  if category == _UN_CAT_DATA { return 10; }
  if category == _UN_CAT_ANGLE { return 4; }
  if category == _UN_CAT_FREQUENCY { return 4; }
  return 0 - 1;
}

fn _cat_name(category: Int) -> Str {
  if category == _UN_CAT_LENGTH { return "length"; }
  if category == _UN_CAT_MASS { return "mass"; }
  if category == _UN_CAT_TIME { return "time"; }
  if category == _UN_CAT_TEMPERATURE { return "temperature"; }
  if category == _UN_CAT_VOLUME { return "volume"; }
  if category == _UN_CAT_AREA { return "area"; }
  if category == _UN_CAT_SPEED { return "speed"; }
  if category == _UN_CAT_PRESSURE { return "pressure"; }
  if category == _UN_CAT_ENERGY { return "energy"; }
  if category == _UN_CAT_POWER { return "power"; }
  if category == _UN_CAT_DATA { return "data"; }
  if category == _UN_CAT_ANGLE { return "angle"; }
  if category == _UN_CAT_FREQUENCY { return "frequency"; }
  return "";
}

// ---------------------------------------------------------------------------
// Public API -- table access and lookups
// ---------------------------------------------------------------------------

/// Number of categories in the embedded table.
/// Returns: 13 (length, mass, time, temperature, volume, area, speed,
/// pressure, energy, power, data, angle, frequency).
/// Error case: none.
/// Complexity: O(1).
pub fn l10n_unit_category_count() -> Int {
  return _UN_CAT_COUNT;
}

/// Total number of unit rows in the embedded table.
/// Returns: 82.
/// Error case: none.
/// Complexity: O(1).
pub fn l10n_unit_count() -> Int {
  return _UN_TOTAL;
}

/// Number of unit rows in one category.
/// Params: category - 0 .. l10n_unit_category_count()-1.
/// Returns: Ok(count); Err("l10n-unit: category out of range: <category>").
/// Error case: see above.
/// Complexity: O(1).
pub fn l10n_unit_count_in_category(category: Int) -> Result[Int, Str] {
  let n = _cat_size(category);
  if n < 0 {
    return _int_err("l10n-unit: category out of range: " + convert.int_to_string(category));
  }
  return _int_ok(n);
}

/// Category name by index.
/// Params: category - 0 .. l10n_unit_category_count()-1.
/// Returns: Ok(name) with "length", "mass", "time", "temperature", "volume",
/// "area", "speed", "pressure", "energy", "power", "data", "angle",
/// "frequency"; Err("l10n-unit: category out of range: <category>").
/// Error case: see above.
/// Complexity: O(1).
pub fn l10n_unit_category_name(category: Int) -> Result[Str, Str] {
  if _cat_start(category) < 0 {
    return _str_err("l10n-unit: category out of range: " + convert.int_to_string(category));
  }
  return _str_ok(_cat_name(category));
}

/// Row of the embedded table by global index.
/// Params: index - 0 .. l10n_unit_count()-1.
/// Returns: Ok(Unit); Err("l10n-unit: index out of range: <index>").
/// Error case: see above.
/// Complexity: O(1).
pub fn l10n_unit_at(index: Int) -> Result[Unit, Str] {
  if index < 0 {
    return _un_err("l10n-unit: index out of range: " + convert.int_to_string(index));
  }
  if index >= _UN_TOTAL {
    return _un_err("l10n-unit: index out of range: " + convert.int_to_string(index));
  }
  let u = _row(index);
  if u.category < 0 {
    return _un_err("l10n-unit: index out of range: " + convert.int_to_string(index));
  }
  return _un_ok(u);
}

/// Row of one category by its within-category index.
/// Params: category - 0 .. 12; index - 0 .. l10n_unit_count_in_category-1.
/// Returns: Ok(Unit); Err("l10n-unit: category out of range: <category>") or
/// Err("l10n-unit: index out of range: <index>") for an out-of-range index,
/// or Err("l10n-unit: category out of range: <category>") when the category
/// itself is invalid.
/// Error case: see above.
/// Complexity: O(1).
pub fn l10n_unit_at_in_category(category: Int, index: Int) -> Result[Unit, Str] {
  let start = _cat_start(category);
  if start < 0 {
    return _un_err("l10n-unit: category out of range: " + convert.int_to_string(category));
  }
  if index < 0 {
    return _un_err("l10n-unit: index out of range: " + convert.int_to_string(index));
  }
  if index >= _cat_size(category) {
    return _un_err("l10n-unit: index out of range: " + convert.int_to_string(index));
  }
  let u = _row(start + index);
  if u.category < 0 {
    return _un_err("l10n-unit: index out of range: " + convert.int_to_string(index));
  }
  return _un_ok(u);
}

/// Look up a unit by its symbol.
/// Params: symbol - the canonical symbol exactly as stored, byte-for-byte
/// and case-sensitive ("m" is the meter, "M" is unknown; "min" is minutes,
/// "mmHg" the pressure unit). The empty string is an error.
/// Returns: Ok(Unit); Err("l10n-unit: bad symbol: ") for the empty string,
/// or Err("l10n-unit: unknown unit: <symbol>") when no row matches.
/// Error case: see above.
/// Complexity: O(1) (bounded scan of 82 rows).
pub fn l10n_unit_by_symbol(symbol: Str) -> Result[Unit, Str] {
  if symbol.len() == 0 {
    return _un_err("l10n-unit: bad symbol: " + symbol);
  }
  let idx = _find_symbol(symbol);
  if idx < 0 {
    return _un_err("l10n-unit: unknown unit: " + symbol);
  }
  let u = _row(idx);
  if u.category < 0 {
    return _un_err("l10n-unit: unknown unit: " + symbol);
  }
  return _un_ok(u);
}

/// Look up a unit by symbol restricted to one category.
/// Params: category - 0 .. 12; symbol - canonical case-sensitive symbol.
/// Returns: Ok(Unit); Err("l10n-unit: category out of range: <category>")
/// for a bad category; Err("l10n-unit: bad symbol: ") for the empty string;
/// Err("l10n-unit: unknown unit in <category-name>: <symbol>") when the
/// symbol is not in that category (including symbols known elsewhere, e.g.
/// "m" inside mass).
/// Error case: see above.
/// Complexity: O(1) (bounded scan).
pub fn l10n_unit_by_symbol_in_category(category: Int, symbol: Str) -> Result[Unit, Str] {
  let start = _cat_start(category);
  if start < 0 {
    return _un_err("l10n-unit: category out of range: " + convert.int_to_string(category));
  }
  if symbol.len() == 0 {
    return _un_err("l10n-unit: bad symbol: " + symbol);
  }
  let size = _cat_size(category);
  var i = 0;
  while i < size {
    let u = _row(start + i);
    let s = u.symbol;
    if compare.str_compare(s, symbol) == 0 {
      return _un_ok(u);
    }
    i = i + 1;
  }
  return _un_err("l10n-unit: unknown unit in " + _cat_name(category) + ": " + symbol);
}

// ---------------------------------------------------------------------------
// Public API -- Unit accessors
// ---------------------------------------------------------------------------

/// Category index of a unit (0..12).
pub fn l10n_unit_category(u: &Unit) -> Int {
  return u.category;
}

/// Canonical symbol of a unit.
pub fn l10n_unit_symbol(u: &Unit) -> Str {
  return u.symbol;
}

/// English name of a unit.
pub fn l10n_unit_name(u: &Unit) -> Str {
  return u.name;
}

/// Numerator of the unit's rational factor to the category base.
pub fn l10n_unit_factor_num(u: &Unit) -> Int {
  return u.num;
}

/// Denominator of the unit's rational factor to the category base.
pub fn l10n_unit_factor_den(u: &Unit) -> Int {
  return u.den;
}

/// Affine offset of the unit in micro-units of the unit itself (temperature
/// rows only; 0 for every other row).
pub fn l10n_unit_offset(u: &Unit) -> Int {
  return u.offset;
}

// ---------------------------------------------------------------------------
// Checked 64-bit arithmetic helpers (value-returning: `&mut Int` out-params
// are miscompiled on v0.61.3)
// ---------------------------------------------------------------------------

fn _abs_or_neg(a: Int) -> Int {
  if a < 0 {
    let x = 0 - a;
    if x < 0 { return a; }
    return x;
  }
  return a;
}

fn _gcd_abs(a: Int, b: Int) -> Int {
  var x = _abs_or_neg(a);
  var y = _abs_or_neg(b);
  if x < 0 { x = 0 - x; }
  if y < 0 { y = 0 - y; }
  while y != 0 {
    let t = x % y;
    x = y;
    y = t;
  }
  return x;
}

fn _mul_fits(a: Int, b: Int) -> Bool {
  if a == 0 { return true; }
  if b == 0 { return true; }
  let x = _abs_or_neg(a);
  let y = _abs_or_neg(b);
  if x < 0 { return false; }
  if y < 0 { return false; }
  if x > _UN_INT_MAX / y { return false; }
  return true;
}

fn _add_fits(a: Int, b: Int) -> Bool {
  if b > 0 {
    if a > _UN_INT_MAX - b { return false; }
    return true;
  }
  if a < _UN_INT_MIN - b { return false; }
  return true;
}

fn _sub_fits(a: Int, b: Int) -> Bool {
  if b < 0 {
    if a > _UN_INT_MAX + b { return false; }
    return true;
  }
  if a < _UN_INT_MIN + b { return false; }
  return true;
}

// Exact trunc(a * b / c) for c > 0, truncating toward zero. The fraction is
// reduced first (gcd of b and c, then of a and the reduced c), then a single
// checked multiply; when that overflows the exact staged identity
// trunc((q*c + r) * b / c) = q*b + trunc(r*b/c) is used. Every residual
// overflow is a typed error, never a wrap.
fn _mul_div(a: Int, b: Int, c: Int) -> Result[Int, Str] {
  if c <= 0 {
    return _int_err("l10n-unit: bad denominator: " + convert.int_to_string(c));
  }
  if a == 0 { return _int_ok(0); }
  if b == 0 { return _int_ok(0); }
  var bn = b;
  var cn = c;
  let g1 = _gcd_abs(bn, cn);
  if g1 > 1 {
    bn = bn / g1;
    cn = cn / g1;
  }
  var an = a;
  let g2 = _gcd_abs(an, cn);
  if g2 > 1 {
    an = an / g2;
    cn = cn / g2;
  }
  if _mul_fits(an, bn) {
    let p = an * bn;
    return _int_ok(p / cn);
  }
  let q = an / cn;
  let r = an % cn;
  if q == 0 {
    return _int_err("l10n-unit: conversion overflow");
  }
  if !_mul_fits(q, bn) {
    return _int_err("l10n-unit: conversion overflow");
  }
  let qb = q * bn;
  if !_mul_fits(r, bn) {
    return _int_err("l10n-unit: conversion overflow");
  }
  let rb = r * bn;
  let t = rb / cn;
  if !_add_fits(qb, t) {
    return _int_err("l10n-unit: conversion overflow");
  }
  return _int_ok(qb + t);
}

// Reduced cross-ratio of two unit rows: rn/rd = (from.num * to.den) /
// (from.den * to.num), reduced by pairwise gcd so the exact conversion
// value = trunc(value_micro * rn / rd) never needs a four-factor product.
// Both parts are positive when the input factors are positive.
type Ratio = {
  rn: Int;
  rd: Int;
}

fn _ratio_ok(rn: Int, rd: Int) -> Result[Ratio, Str] {
  let v = Ratio{ rn: rn; rd: rd };
  return Ok(v);
}

fn _ratio_err(m: Str) -> Result[Ratio, Str] {
  return Err(m);
}

fn _ratio(origin: &Unit, target: &Unit) -> Result[Ratio, Str] {
  var fnum = origin.num;
  var fden = origin.den;
  var tnum = target.num;
  var tden = target.den;
  if fnum <= 0 { return _ratio_err("l10n-unit: bad unit factor: " + origin.symbol); }
  if fden <= 0 { return _ratio_err("l10n-unit: bad unit factor: " + origin.symbol); }
  if tnum <= 0 { return _ratio_err("l10n-unit: bad unit factor: " + target.symbol); }
  if tden <= 0 { return _ratio_err("l10n-unit: bad unit factor: " + target.symbol); }
  let g1 = _gcd_abs(fnum, tnum);
  if g1 > 1 {
    fnum = fnum / g1;
    tnum = tnum / g1;
  }
  let g2 = _gcd_abs(tden, fden);
  if g2 > 1 {
    tden = tden / g2;
    fden = fden / g2;
  }
  let g3 = _gcd_abs(fnum, fden);
  if g3 > 1 {
    fnum = fnum / g3;
    fden = fden / g3;
  }
  let g4 = _gcd_abs(tden, tnum);
  if g4 > 1 {
    tden = tden / g4;
    tnum = tnum / g4;
  }
  if !_mul_fits(fnum, tden) {
    return _ratio_err("l10n-unit: conversion overflow");
  }
  if !_mul_fits(fden, tnum) {
    return _ratio_err("l10n-unit: conversion overflow");
  }
  var rn = fnum * tden;
  var rd = fden * tnum;
  let g5 = _gcd_abs(rn, rd);
  if g5 > 1 {
    rn = rn / g5;
    rd = rd / g5;
  }
  return _ratio_ok(rn, rd);
}

// ---------------------------------------------------------------------------
// Public API -- conversion
// ---------------------------------------------------------------------------

/// Convert a micro-unit value from one unit to another.
/// Params: value_micro - signed fixed-point value in micro-units of `from`;
/// from / to - unit rows of the same category.
/// Math: out = trunc((value_micro + from.offset) * from.num * to.den /
/// (from.den * to.num)) - to.offset, evaluated as one exact rational with
/// the cross-ratio reduced first; the single division truncates toward
/// zero. Offsets are 0 outside temperature. This is the documented formula
/// `value * from_num * to_den / (from_den * to_num)` with the affine
/// extension; see SPEC.md for the worked rounding points.
/// Returns: Ok(out_micro); Err("l10n-unit: category mismatch: <from> (<c>)
/// -> <to> (<c>)") when the categories differ, or
/// Err("l10n-unit: conversion overflow") when an intermediate product would
/// exceed Int (no silent wrap), or Err("l10n-unit: bad unit row") for an
/// invalid row.
/// Error case: see above.
/// Complexity: O(1).
pub fn l10n_unit_convert(value_micro: Int, origin: &Unit, target: &Unit) -> Result[Int, Str] {
  let fc: Int = origin.category;
  let tc: Int = target.category;
  if fc < 0 {
    return _int_err("l10n-unit: bad unit row");
  }
  if tc < 0 {
    return _int_err("l10n-unit: bad unit row");
  }
  if fc != tc {
    let fs: Str = origin.symbol;
    let ts: Str = target.symbol;
    return _int_err("l10n-unit: category mismatch: " + fs + " (" + _cat_name(fc) + ") -> " + ts + " (" + _cat_name(tc) + ")");
  }
  let fo: Int = origin.offset;
  let tof: Int = target.offset;
  var v = value_micro;
  if fo != 0 {
    if !_add_fits(v, fo) {
      return _int_err("l10n-unit: conversion overflow");
    }
    v = v + fo;
  }
  let rr = _ratio(origin, target);
  match rr {
    Ok(r) => {
      let rn: Int = r.rn;
      let rd: Int = r.rd;
      let rc = _mul_div(v, rn, rd);
      match rc {
        Ok(out) => {
          if tof != 0 {
            if !_sub_fits(out, tof) {
              return _int_err("l10n-unit: conversion overflow");
            }
            return _int_ok(out - tof);
          }
          return _int_ok(out);
        },
        Err(e) => { return _int_err(e); },
      }
    },
    Err(e) => { return _int_err(e); },
  }
  return _int_err("l10n-unit: conversion overflow");
}

/// Convert a micro-unit value between two symbols.
/// Params: value_micro - value in micro-units of `from_symbol`; from_symbol
/// / to_symbol - canonical case-sensitive symbols.
/// Returns: the l10n_unit_convert result, or the l10n_unit_by_symbol error
/// for a malformed or unknown symbol.
/// Error case: see above.
/// Complexity: O(1) (bounded scans).
pub fn l10n_unit_convert_by_symbol(value_micro: Int, from_symbol: Str, to_symbol: Str) -> Result[Int, Str] {
  let rf = l10n_unit_by_symbol(from_symbol);
  match rf {
    Ok(f) => {
      let ru = l10n_unit_by_symbol(to_symbol);
      match ru {
        Ok(t) => {
          let ff = f;
          let tt = t;
          return l10n_unit_convert(value_micro, &ff, &tt);
        },
        Err(e) => { return _int_err(e); },
      }
    },
    Err(e) => { return _int_err(e); },
  }
  return _int_err("l10n-unit: unknown unit: " + from_symbol);
}

/// Value of `u` expressed in its category base, in micro-units:
/// trunc((value_micro + u.offset) * u.num / u.den).
/// Params: value_micro - signed fixed-point value; u - unit row.
/// Returns: Ok(base_micro); Err("l10n-unit: conversion overflow") when the
/// product would exceed Int.
/// Error case: see above.
/// Complexity: O(1).
pub fn l10n_unit_base_micro(value_micro: Int, u: &Unit) -> Result[Int, Str] {
  let off: Int = u.offset;
  var v = value_micro;
  if off != 0 {
    if !_add_fits(v, off) {
      return _int_err("l10n-unit: conversion overflow");
    }
    v = v + off;
  }
  let num: Int = u.num;
  let den: Int = u.den;
  return _mul_div(v, num, den);
}

/// Category compatibility of two rows.
/// Returns: true iff both rows are valid and share a category.
/// Error case: none (errors collapse to false).
/// Complexity: O(1).
pub fn l10n_unit_is_compatible(origin: &Unit, target: &Unit) -> Bool {
  let fc: Int = origin.category;
  let tc: Int = target.category;
  if fc < 0 { return false; }
  if tc < 0 { return false; }
  return fc == tc;
}

// ---------------------------------------------------------------------------
// Public API -- parse / format of simple "<number> <symbol>" strings
// ---------------------------------------------------------------------------

fn _pow6_scale(mag: Int, kept: Int) -> Int {
  var m = mag;
  var k = kept;
  while k < 6 {
    m = m * 10;
    k = k + 1;
  }
  return m;
}

// Unsigned fixed-point text of a non-negative micro value: integer part,
// then a 6-digit fraction with trailing zeros trimmed ("12.5", "0.000001",
// "3").
fn _format_fixed6(mag: Int) -> Str {
  let int_part = mag / _UN_MICRO;
  let frac = mag % _UN_MICRO;
  if frac == 0 {
    return convert.int_to_string(int_part);
  }
  var digits = convert.int_to_string(frac);
  while digits.len() < 6 {
    digits = "0" + digits;
  }
  var last = digits.len();
  while last > 0 {
    if string.byte_at(digits, last - 1) != _UN_ZERO { break; }
    last = last - 1;
  }
  return convert.int_to_string(int_part) + "." + string.str_slice(digits, 0, last);
}

/// Parse a simple "<number> <symbol>" measurement string.
/// Params: text - optional ASCII spaces, then an optionally signed decimal
/// number, then optional ASCII spaces, then the canonical case-sensitive
/// unit symbol ("12.5 km/h", "0.5m", "-40 degC", " 3 ft "). The integer part
/// may be empty when a fraction is present (".5"); more than six fraction
/// digits are TRUNCATED (not an error): "1.0000009 m" is 1000000 micro-m,
/// because the value model is fixed-point micro-units.
/// Returns: Ok(Measurement{ symbol, value_micro }); errors carry the byte
/// offset of the offending element in SPEC.md's catalog:
/// "l10n-unit: empty input", "l10n-unit: no digits at byte <n>",
/// "l10n-unit: unexpected character at byte <n>",
/// "l10n-unit: multiple decimal separators at byte <n>",
/// "l10n-unit: number too large at byte <n>",
/// "l10n-unit: missing unit at byte <n>",
/// "l10n-unit: unknown unit: <symbol> at byte <n>".
/// Error case: see above.
/// Complexity: O(len(text)).
pub fn l10n_unit_parse(text: Str) -> Result[Measurement, Str] {
  let n = text.len();
  if n == 0 {
    return _ms_err("l10n-unit: empty input");
  }
  var i = 0;
  while i < n && _is_space(string.byte_at(text, i)) {
    i = i + 1;
  }
  if i >= n {
    return _ms_err("l10n-unit: no digits at byte " + convert.int_to_string(i));
  }
  var neg = false;
  let first = string.byte_at(text, i);
  if first == _UN_MINUS {
    neg = true;
    i = i + 1;
  } elif first == _UN_PLUS {
    i = i + 1;
  }
  var int_mag: Int = 0;
  var frac_mag: Int = 0;
  var kept = 0;
  var seen_dot = false;
  var seen_digit = false;
  var scanning = true;
  while i < n && scanning {
    let b = string.byte_at(text, i);
    if _is_digit(b) {
      let d = ((b as Int) & 255) - 48;
      if seen_dot {
        if kept < 6 {
          frac_mag = frac_mag * 10 + d;
          kept = kept + 1;
        }
      } else {
        if int_mag > _UN_INT_MAX_DIV10 {
          return _ms_err("l10n-unit: number too large at byte " + convert.int_to_string(i));
        }
        if int_mag == _UN_INT_MAX_DIV10 && d > _UN_INT_MAX_LAST_DIGIT {
          return _ms_err("l10n-unit: number too large at byte " + convert.int_to_string(i));
        }
        int_mag = int_mag * 10 + d;
      }
      seen_digit = true;
      i = i + 1;
    } elif b == _UN_DOT {
      if seen_dot {
        return _ms_err("l10n-unit: multiple decimal separators at byte " + convert.int_to_string(i));
      }
      seen_dot = true;
      i = i + 1;
    } else {
      scanning = false;
    }
  }
  let num_end = i;
  while i < n && _is_space(string.byte_at(text, i)) {
    i = i + 1;
  }
  if !seen_digit {
    return _ms_err("l10n-unit: no digits at byte " + convert.int_to_string(i));
  }
  var j = n;
  while j > i {
    if string.byte_at(text, j - 1) != _UN_SPACE { break; }
    j = j - 1;
  }
  if j <= i {
    return _ms_err("l10n-unit: missing unit at byte " + convert.int_to_string(i));
  }
  let sym = string.str_slice(text, i, j);
  let ru = l10n_unit_by_symbol(sym);
  match ru {
    Ok(u) => {
      let _s: Str = u.symbol;
    },
    Err(e) => {
      return _ms_err("l10n-unit: unknown unit: " + sym + " at byte " + convert.int_to_string(i));
    },
  }
  if int_mag > _UN_INT_MAX / _UN_MICRO {
    return _ms_err("l10n-unit: number too large at byte " + convert.int_to_string(num_end));
  }
  let whole = int_mag * _UN_MICRO;
  let frac = _pow6_scale(frac_mag, kept);
  if !_add_fits(whole, frac) {
    return _ms_err("l10n-unit: number too large at byte " + convert.int_to_string(num_end));
  }
  var value = whole + frac;
  if neg && value != 0 {
    value = 0 - value;
  }
  let out = Measurement{ symbol: sym; value_micro: value };
  return _ms_ok(out);
}

/// Format a micro-unit value with a canonical symbol.
/// Params: value_micro - signed fixed-point value; symbol - canonical
/// case-sensitive symbol, validated with l10n_unit_by_symbol.
/// Returns: Ok("12.5 km/h"): the sign, the integer part, and up to six
/// fraction digits with trailing zeros trimmed ("3 m", "-0.5 h",
/// "0.000001 m"); Err("l10n-unit: ...") for an unknown or empty symbol and
/// for the single unrepresentable magnitude Int.MIN.
/// Error case: see above.
/// Complexity: O(digits).
pub fn l10n_unit_format(value_micro: Int, symbol: Str) -> Result[Str, Str] {
  let ru = l10n_unit_by_symbol(symbol);
  match ru {
    Ok(u) => {
      let s: Str = u.symbol;
      if value_micro < 0 {
        let mag = 0 - value_micro;
        if mag < 0 {
          return _str_err("l10n-unit: value out of range");
        }
        return _str_ok("-" + _format_fixed6(mag) + " " + s);
      }
      return _str_ok(_format_fixed6(value_micro) + " " + s);
    },
    Err(e) => {
      return _str_err(e);
    },
  }
  return _str_err("l10n-unit: unknown unit: " + symbol);
}

/// Parse a measurement and convert it to a target symbol in one step.
/// Params: text - as l10n_unit_parse; target_symbol - canonical symbol.
/// Returns: Ok(out_micro) of the converted value; the parse error, the
/// l10n_unit_convert error (category mismatch, overflow), or the
/// l10n_unit_by_symbol error for the target.
/// Error case: see above.
/// Complexity: O(len(text)).
pub fn l10n_unit_parse_to(text: Str, target_symbol: Str) -> Result[Int, Str] {
  let rm = l10n_unit_parse(text);
  match rm {
    Ok(m) => {
      let ms: Str = m.symbol;
      let mv: Int = m.value_micro;
      return l10n_unit_convert_by_symbol(mv, ms, target_symbol);
    },
    Err(e) => {
      return _int_err(e);
    },
  }
  return _int_err("l10n-unit: parse failed");
}

/// Symbol carried by a parsed measurement.
pub fn l10n_unit_measurement_symbol(m: &Measurement) -> Str {
  return m.symbol;
}

/// Micro-unit value carried by a parsed measurement.
pub fn l10n_unit_measurement_value(m: &Measurement) -> Int {
  return m.value_micro;
}
