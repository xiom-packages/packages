// XIOM -- xiom.astronomy: Julian dates, days since J2000, moon phase, zodiac
// Port task: replace the xiom.astronomy placeholder with a real, tested,
// pure-XIOM package (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Integer-only astronomy helpers for civil dates (no floating point, no FFI):
//
//   * astro_is_leap_year        -- proleptic Gregorian leap-year rule,
//   * astro_julian_day          -- integer Julian Day Number (Fliegel-Van
//                                  Flandern) of a civil date,
//   * astro_days_since_j2000    -- JD(year, month, day) - 2451545,
//   * astro_moon_phase_permille -- day-granularity synodic phase 0..999,
//   * astro_moon_phase_name     -- phase interval -> name,
//   * astro_zodiac_sign         -- tropical zodiac sign of a month/day.
//
// Conventions (full details in SPEC.md):
//   * "Julian day" is the integer JDN anchored at JD(2000-01-01) = 2451545
//     (the J2000.0 epoch value); the .5-day fraction of a 00:00 UTC instant
//     is not represented. Dates are proleptic Gregorian, read as UTC civil
//     dates, valid for years >= -4799.
//   * The moon phase assumes one mean synodic month of 29.530589 days
//     (29530589 millionths of a day) and day granularity: expect about +-1
//     day of error against a true ephemeris. No time of day, no perturbation
//     terms, no timescale conversion (UT/TT/Delta-T).
//
// XIOM v0.61.3 constraints honored here: free functions only (no methods,
// no lambdas), no Vec[StructType], no Vec[fn], every match is exhaustive,
// Ok/Err are built only inside the _ok_*/_err_* leaf helpers, and no
// floating point is used.

module xiom.astronomy

use xiom.convert;

// --- constants --------------------------------------------------------------

// JD of 2000-01-01, the J2000 reference date used by this package.
const _JD_J2000: Int = 2451545;
// JD of the moon-phase epoch 2000-01-06, a reference new moon.
const _JD_PHASE_EPOCH: Int = 2451550;
// 1 day expressed in the sub-day unit used by _SYNODIC_MILLI.
const _UNITS_PER_DAY: Int = 1000000;
// One mean synodic month: 29.530589 days = 29530589 sub-day units.
const _SYNODIC_MILLI: Int = 29530589;
// Permille scale (1000 = one whole cycle).
const _PERMILLE: Int = 1000;

// --- Result constructors (leaf helpers; see the module header) --------------

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

// --- integer floor helpers (negative inputs stay correct) -------------------

// Floor division; callers pass b > 0.
fn _floor_div(a: Int, b: Int) -> Int {
  var q = a / b;
  let r = a - q * b;
  if r < 0 { q = q - 1; }
  return q;
}

fn _floor_mod(a: Int, b: Int) -> Int {
  let q = _floor_div(a, b);
  return a - q * b;
}

// --- date helpers -----------------------------------------------------------

// Longest possible length of a month across all years (February 29 is
// possible in a leap year). Used where no year is available.
fn _month_max_days(month: Int) -> Int {
  if month == 2 { return 29; }
  if month == 4 || month == 6 || month == 9 || month == 11 { return 30; }
  return 31;
}

fn _days_in_month(year: Int, month: Int) -> Int {
  if month == 2 {
    if astro_is_leap_year(year) { return 29; }
    return 28;
  }
  return _month_max_days(month);
}

fn _date_text(year: Int, month: Int, day: Int) -> Str {
  return convert.int_to_string(year) + "-" + convert.int_to_string(month) + "-" + convert.int_to_string(day);
}

fn _md_text(month: Int, day: Int) -> Str {
  return convert.int_to_string(month) + "-" + convert.int_to_string(day);
}

// --- public API -------------------------------------------------------------

/// True when `year` is a leap year in the proleptic Gregorian calendar.
/// The rule: divisible by 4, except centuries, except every 400 years.
/// Params: year - any Int (divisibility is sign-symmetric).
/// Returns: true for a leap year: 2000 and 2024 yes; 1900 and 2100 no.
/// Complexity: O(1).
pub fn astro_is_leap_year(year: Int) -> Bool {
  if year % 4 != 0 { return false; }
  if year % 100 != 0 { return true; }
  return year % 400 == 0;
}

/// Integer Julian Day Number of the civil date `year-month-day` in the
/// proleptic Gregorian calendar (Fliegel-Van Flandern):
///   a = (14 - month) / 12
///   y = year + 4800 - a
///   m = month + 12*a - 3
///   JD = day + (153*m + 2)/5 + 365*y + y/4 - y/100 + y/400 - 32045
/// The value is the integer JDN anchored at JD(2000-01-01) = 2451545 (the
/// J2000.0 epoch value); it equals the astronomical JD of the date at noon,
/// so a 00:00 UTC instant is JDN - 0.5 and is not represented here.
/// Params: year - Gregorian year (>= -4799 for the formula);
///         month - 1..12;
///         day - 1..days_in_month(year, month).
/// Returns: Ok(JDN); Err("astronomy: invalid date: Y-M-D") when the month is
/// outside 1..12 or the day is outside 1..days_in_month (this rejects
/// February 30 and February 29 in a common year).
/// Complexity: O(1).
pub fn astro_julian_day(year: Int, month: Int, day: Int) -> Result[Int, Str] {
  if month < 1 || month > 12 {
    return _err_int("astronomy: invalid date: " + _date_text(year, month, day));
  }
  if day < 1 || day > _days_in_month(year, month) {
    return _err_int("astronomy: invalid date: " + _date_text(year, month, day));
  }
  let a = (14 - month) / 12;
  let y = year + 4800 - a;
  let m = month + 12 * a - 3;
  return _ok_int(day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045);
}

/// Whole days from the J2000 reference date 2000-01-01 to `year-month-day`:
/// 2000-01-01 -> 0, 1999-12-31 -> -1, 2026-01-01 -> 9497.
/// Params: as astro_julian_day.
/// Returns: Ok(days); Err (the astro_julian_day message) for an invalid date.
/// Complexity: O(1).
pub fn astro_days_since_j2000(year: Int, month: Int, day: Int) -> Result[Int, Str] {
  let jd = astro_julian_day(year, month, day);
  match jd {
    Ok(v) => { return _ok_int(v - _JD_J2000); },
    Err(e) => { return _err_int(e); },
  }
  return _err_int("astronomy: invalid date: " + _date_text(year, month, day));
}

/// Day-granularity moon-phase estimate in permille of the synodic cycle.
/// Model: whole days since the reference new moon 2000-01-06 (JD 2451550)
/// are scaled to the _SYNODIC_MILLI unit (1,000,000 units per day) and
/// divided by one mean synodic month of 29.530589 days:
///   phase = floor(((JD - 2451550) * 1000000 * 1000) / 29530589) mod 1000
/// so 0 permille is new moon and 500 is full moon. The result is always in
/// 0..999 (floor semantics, so dates before the epoch wrap forward). The
/// estimate is accurate to about +-1 day: no time of day, no perturbation
/// terms, no timescales.
/// Params: as astro_julian_day.
/// Returns: Ok(permille in 0..999); Err for an invalid date.
/// Complexity: O(1).
pub fn astro_moon_phase_permille(year: Int, month: Int, day: Int) -> Result[Int, Str] {
  let jd = astro_julian_day(year, month, day);
  var elapsed_units: Int = 0;
  match jd {
    Ok(v) => { elapsed_units = (v - _JD_PHASE_EPOCH) * _UNITS_PER_DAY; },
    Err(e) => { return _err_int(e); },
  }
  let cycles_in_permille = _floor_div(elapsed_units * _PERMILLE, _SYNODIC_MILLI);
  return _ok_int(_floor_mod(cycles_in_permille, _PERMILLE));
}

/// Name of the phase interval containing `permille`.
/// `permille` is first normalized with floor semantics into 0..999, so any
/// Int is accepted (1000 -> 0, -1 -> 999). Intervals: new 0..62,
/// waxing crescent 63..187, first quarter 188..312, waxing gibbous 313..437,
/// full 438..562, waning gibbous 563..687, last quarter 688..812,
/// waning crescent 813..937, new 938..999.
/// Params: permille - the phase estimate (any Int; see
///         astro_moon_phase_permille).
/// Returns: one of "new", "waxing crescent", "first quarter",
/// "waxing gibbous", "full", "waning gibbous", "last quarter",
/// "waning crescent".
/// Complexity: O(1).
pub fn astro_moon_phase_name(permille: Int) -> Str {
  let p = _floor_mod(permille, _PERMILLE);
  if p <= 62 { return "new"; }
  if p <= 187 { return "waxing crescent"; }
  if p <= 312 { return "first quarter"; }
  if p <= 437 { return "waxing gibbous"; }
  if p <= 562 { return "full"; }
  if p <= 687 { return "waning gibbous"; }
  if p <= 812 { return "last quarter"; }
  if p <= 937 { return "waning crescent"; }
  return "new";
}

// Tropical zodiac name for a month/day that passed validation. Boundaries:
// Aries Mar 21, Taurus Apr 20, Gemini May 21, Cancer Jun 21, Leo Jul 23,
// Virgo Aug 23, Libra Sep 23, Scorpio Oct 23, Sagittarius Nov 22,
// Capricorn Dec 22, Aquarius Jan 20, Pisces Feb 19.
fn _zodiac_name(month: Int, day: Int) -> Str {
  if month == 1 {
    if day <= 19 { return "Capricorn"; }
    return "Aquarius";
  }
  if month == 2 {
    if day <= 18 { return "Aquarius"; }
    return "Pisces";
  }
  if month == 3 {
    if day <= 20 { return "Pisces"; }
    return "Aries";
  }
  if month == 4 {
    if day <= 19 { return "Aries"; }
    return "Taurus";
  }
  if month == 5 {
    if day <= 20 { return "Taurus"; }
    return "Gemini";
  }
  if month == 6 {
    if day <= 20 { return "Gemini"; }
    return "Cancer";
  }
  if month == 7 {
    if day <= 22 { return "Cancer"; }
    return "Leo";
  }
  if month == 8 {
    if day <= 22 { return "Leo"; }
    return "Virgo";
  }
  if month == 9 {
    if day <= 22 { return "Virgo"; }
    return "Libra";
  }
  if month == 10 {
    if day <= 22 { return "Libra"; }
    return "Scorpio";
  }
  if month == 11 {
    if day <= 21 { return "Scorpio"; }
    return "Sagittarius";
  }
  if day <= 21 { return "Sagittarius"; }
  return "Capricorn";
}

/// Tropical zodiac sign of `month-day` (no year is involved).
/// Ranges: Aries Mar 21-Apr 19, Taurus Apr 20-May 20, Gemini May 21-Jun 20,
/// Cancer Jun 21-Jul 22, Leo Jul 23-Aug 22, Virgo Aug 23-Sep 22,
/// Libra Sep 23-Oct 22, Scorpio Oct 23-Nov 21, Sagittarius Nov 22-Dec 21,
/// Capricorn Dec 22-Jan 19, Aquarius Jan 20-Feb 18, Pisces Feb 19-Mar 20.
/// Without a year, February accepts day 29 (a leap day is possible) and
/// April/June/September/November reject day 31, so a month/day pair is
/// validated against the longest possible month.
/// Params: month - 1..12; day - 1..31 (bounded by the month).
/// Returns: Ok(sign name); Err("astronomy: invalid date: M-D") for an
/// out-of-range month or day.
/// Complexity: O(1).
pub fn astro_zodiac_sign(month: Int, day: Int) -> Result[Str, Str] {
  if month < 1 || month > 12 {
    return _err_str("astronomy: invalid date: " + _md_text(month, day));
  }
  if day < 1 || day > _month_max_days(month) {
    return _err_str("astronomy: invalid date: " + _md_text(month, day));
  }
  return _ok_str(_zodiac_name(month, day));
}
