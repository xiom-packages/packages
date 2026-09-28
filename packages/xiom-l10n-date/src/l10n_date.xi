// XIOM -- xiom.l10n.date: locale-aware civil-date formatting and parsing
// Port task: replace the xiom.l10n.date placeholder with a pure-XIOM module.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model (pinned in SPEC.md, exercised by tests/test_conformance.xi):
//
//   A civil date is three Int fields (year, month, day); `date_make`
//   validates month 1..12 and day 1..days_in_month(year, month) with the
//   Gregorian leap rule (divisible by 4, except centuries not divisible by
//   400). Every calendar function assumes a valid CivilDate; only `date_make`,
//   `date_parse` and `date_iso_parse` create validated values.
//
//   Epoch days count days since 1970-01-01 (Gregorian, proleptic); dates
//   before the epoch yield negative values, and the JDN path keeps them
//   exact. Weekdays are 0=Sunday .. 6=Saturday; day-of-year is 1..365/366.
//
//   The Julian Day Number (JDN) is the common astronomical day count used by
//   the calendar conversions. For a civil date the Gregorian JDN is
//
//     a  = (14 - month) / 12 ; y = year + 4800 - a ; m = month + 12a - 3
//     jdn = day + (153m + 2)/5 + 365y + y/4 - y/100 + y/400 - 32045
//
//   and the Julian-calendar JDN is the same without the y/100 and y/400
//   terms and with the epoch constant -32083. The inverse formulas (used by
//   date_gregorian_from_jdn / date_julian_from_jdn) are the classic
//   Fliegel-Van Flandern inverses; all divisions are truncating Int division
//   and every operand stays non-negative for years >= -4700.
//
//   Offset rule (Gregorian <-> Julian calendar): the same physical day is an
//   earlier date in the Julian calendar. The offset starts at 10 days at the
//   1582-10-15 reform (Gregorian 1582-10-15 = Julian 1582-10-05) and grows by
//   one day on 1700-03-01, 1800-03-01, 1900-03-01 and 2100-03-01 (Gregorian):
//   the Julian date is 11, 12, 13 and 14 days behind respectively. Both
//   directions are computed through the JDN, so the rules hold for every year
//   in the supported range, including proleptic dates before 1582.
//
//   Formatting/parsing is token-based over caller-supplied month-name tables:
//   `month_names` (full names) and `month_abbrs` (abbreviations), each a
//   Vec[Str] of exactly 12 entries. Tokens: YYYY YY MMMM MMM MM M DD D;
//   every non-letter byte of the pattern is a literal. There is no locale
//   database, no clock, no IO and no FFI; the locale is exactly the two
//   month-name vectors the caller passes in.
//
// v0.62.0 notes that shaped this module: free functions only (no self
// methods, no Vec[StructType] fields in results are avoided by leaf builders);
// Ok/Err live only in the leaf helpers below; every string comparison goes
// through xiom.string.compare (never `==`); every byte read is widened with
// `as Int` and masked with 255; `Str` values read from Vec[Str] are always
// bound to typed locals before comparison.

module xiom.l10n.date

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// ASCII bytes (Int constants, so every comparison is an Int comparison).
const _DATE_DASH: Int = 45;
const _DATE_ZERO: Int = 48;
const _DATE_NINE: Int = 57;
const _DATE_UPPER_A: Int = 65;
const _DATE_UPPER_Z: Int = 90;
const _DATE_LOWER_A: Int = 97;
const _DATE_LOWER_Z: Int = 122;

// JDN of 1970-01-01 (Gregorian): the epoch-day origin.
const _DATE_EPOCH_JDN: Int = 2440588;

// Largest year YYYY/YY can render or parse.
const _DATE_YEAR_MAX: Int = 9999;

// Required month-table length.
const _DATE_TABLE_LEN: Int = 12;

/// A civil (proleptic Gregorian) calendar date. The fields are not validated
/// on construction; use `date_make`, `date_parse` or `date_iso_parse` to
/// obtain a checked value, or build the struct directly when the date is
/// known good.
pub type CivilDate = {
  year: Int;
  month: Int;
  day: Int;
}

// Result constructors live in these leaves: constructing Ok/Err inline in a
// function that also returns a struct value miscompiles on XIOM v0.62.0.
fn _date_ok(v: CivilDate) -> Result[CivilDate, Str] { return Ok(v); }
fn _date_err(m: Str) -> Result[CivilDate, Str] { return Err(m); }
fn _str_ok(v: Str) -> Result[Str, Str] { return Ok(v); }
fn _str_err(m: Str) -> Result[Str, Str] { return Err(m); }

// ---------------------------------------------------------------------------
// Byte and digit helpers
// ---------------------------------------------------------------------------

// Widen and mask one byte of `s`.
fn _date_byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 255;
}

fn _date_is_digit(b: Int) -> Bool {
  return b >= _DATE_ZERO && b <= _DATE_NINE;
}

fn _date_is_alpha(b: Int) -> Bool {
  if b >= _DATE_UPPER_A && b <= _DATE_UPPER_Z { return true; }
  return b >= _DATE_LOWER_A && b <= _DATE_LOWER_Z;
}

// True when `count` ASCII digits start at byte `at`.
fn _date_digits_at(s: Str, at: Int, count: Int) -> Bool {
  if at < 0 { return false; }
  if at + count > s.len() { return false; }
  var i = 0;
  while i < count {
    if !_date_is_digit(_date_byte(s, at + i)) { return false; }
    i = i + 1;
  }
  return true;
}

// Value of exactly `count` ASCII digits at byte `at` (callers check first).
fn _date_read_digits(s: Str, at: Int, count: Int) -> Int {
  var acc = 0;
  var i = 0;
  while i < count {
    acc = acc * 10 + (_date_byte(s, at + i) - _DATE_ZERO);
    i = i + 1;
  }
  return acc;
}

// Number of consecutive ASCII digits at byte `at`, capped at `max`.
fn _date_digit_run(s: Str, at: Int, max: Int) -> Int {
  var i = 0;
  while i < max {
    if at + i >= s.len() { break; }
    if !_date_is_digit(_date_byte(s, at + i)) { break; }
    i = i + 1;
  }
  return i;
}

// End of the ASCII letter run starting at `start`.
fn _date_letters_end(s: Str, start: Int) -> Int {
  var i = start;
  while i < s.len() {
    if !_date_is_alpha(_date_byte(s, i)) { break; }
    i = i + 1;
  }
  return i;
}

// True when `sub` occurs in `s` at byte offset `at` (byte-wise).
fn _date_starts_at(s: Str, at: Int, sub: Str) -> Bool {
  if at < 0 { return false; }
  if at + sub.len() > s.len() { return false; }
  var i = 0;
  while i < sub.len() {
    if _date_byte(s, at + i) != _date_byte(sub, i) { return false; }
    i = i + 1;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Validation and construction
// ---------------------------------------------------------------------------

/// True when `year` is a Gregorian leap year: divisible by 4, except
/// centuries that are not divisible by 400 (2000 and 2024 leap; 1900 not).
/// Error case: none.
/// Complexity: O(1).
pub fn date_is_leap_year(year: Int) -> Bool {
  if year % 4 != 0 { return false; }
  if year % 100 != 0 { return true; }
  return year % 400 == 0;
}

/// Number of days in `month` of `year` (28..31), or 0 when `month` is not in
/// 1..12 (invalid months are never silently treated as 31 days).
/// Error case: none.
/// Complexity: O(1).
pub fn date_days_in_month(year: Int, month: Int) -> Int {
  if month < 1 || month > 12 { return 0; }
  if month == 2 {
    if date_is_leap_year(year) { return 29; }
    return 28;
  }
  if month == 4 || month == 6 || month == 9 || month == 11 { return 30; }
  return 31;
}

// "" when (year, month, day) is a valid civil date, else the exact error
// message. Month is checked before day, so 2023-13-99 reports the month.
fn _date_invalid_reason(year: Int, month: Int, day: Int) -> Str {
  if month < 1 || month > 12 {
    return "date: invalid month: " + convert.int_to_string(month);
  }
  if day < 1 || day > date_days_in_month(year, month) {
    return "date: invalid day: " + convert.int_to_string(day);
  }
  return "";
}

/// Validate a triplet and build a CivilDate.
/// Params: year - any Int; month - 1..12; day - 1..days_in_month(year,
/// month), with February 29 accepted only in leap years.
/// Returns: Ok(CivilDate) for a valid date; Err("date: invalid month: <m>")
/// or Err("date: invalid day: <d>") otherwise (month is checked first).
/// Examples: (2024, 2, 29) -> Ok; (2023, 2, 29) -> Err("date: invalid day:
/// 29"); (2024, 13, 1) -> Err("date: invalid month: 13").
/// Complexity: O(1).
pub fn date_make(year: Int, month: Int, day: Int) -> Result[CivilDate, Str] {
  let reason = _date_invalid_reason(year, month, day);
  if reason.len() > 0 {
    return _date_err(reason);
  }
  let out = CivilDate{ year: year; month: month; day: day; };
  return _date_ok(out);
}

/// True when (year, month, day) is a valid civil date.
/// Error case: none.
/// Complexity: O(1).
pub fn date_is_valid(year: Int, month: Int, day: Int) -> Bool {
  let reason = _date_invalid_reason(year, month, day);
  return reason.len() == 0;
}

/// Year field of a date.
/// Error case: none. Complexity: O(1).
pub fn date_year(d: &CivilDate) -> Int { return d.year; }

/// Month field of a date (1..12 for validated dates).
/// Error case: none. Complexity: O(1).
pub fn date_month(d: &CivilDate) -> Int { return d.month; }

/// Day field of a date (1..31 for validated dates).
/// Error case: none. Complexity: O(1).
pub fn date_day(d: &CivilDate) -> Int { return d.day; }

// ---------------------------------------------------------------------------
// Julian day numbers and calendar conversion
// ---------------------------------------------------------------------------

// Gregorian civil date -> JDN (Fliegel-Van Flandern).
fn _date_gregorian_to_jdn(year: Int, month: Int, day: Int) -> Int {
  let a = (14 - month) / 12;
  let y = year + 4800 - a;
  let m = month + 12 * a - 3;
  return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045;
}

// Julian calendar date -> JDN (same formula, Julian leap rule and epoch).
fn _date_julian_to_jdn(year: Int, month: Int, day: Int) -> Int {
  let a = (14 - month) / 12;
  let y = year + 4800 - a;
  let m = month + 12 * a - 3;
  return day + (153 * m + 2) / 5 + 365 * y + y / 4 - 32083;
}

// JDN -> Gregorian civil date (Fliegel-Van Flandern inverse).
fn _date_jdn_to_gregorian(jdn: Int) -> CivilDate {
  let a = jdn + 32044;
  let b = (4 * a + 3) / 146097;
  let c = a - (146097 * b) / 4;
  let d = (4 * c + 3) / 1461;
  let e = c - (1461 * d) / 4;
  let m = (5 * e + 2) / 153;
  let day = e - (153 * m + 2) / 5 + 1;
  let month = m + 3 - 12 * (m / 10);
  let year = 100 * b + d - 4800 + m / 10;
  let out = CivilDate{ year: year; month: month; day: day; };
  return out;
}

// JDN -> Julian calendar date.
fn _date_jdn_to_julian(jdn: Int) -> CivilDate {
  let c = jdn + 32082;
  let d = (4 * c + 3) / 1461;
  let e = c - (1461 * d) / 4;
  let m = (5 * e + 2) / 153;
  let day = e - (153 * m + 2) / 5 + 1;
  let month = m + 3 - 12 * (m / 10);
  let year = d - 4800 + m / 10;
  let out = CivilDate{ year: year; month: month; day: day; };
  return out;
}

/// Julian Day Number of a proleptic Gregorian date.
/// Params: d - a valid CivilDate (year >= -4700 keeps the division operands
/// non-negative).
/// Returns: the integer JDN; 1970-01-01 is 2440588, 2000-01-01 is 2451545.
/// Error case: none.
/// Complexity: O(1).
pub fn date_jdn_from_gregorian(d: &CivilDate) -> Int {
  return _date_gregorian_to_jdn(d.year, d.month, d.day);
}

/// Julian Day Number of a proleptic Julian-calendar date.
/// Returns: the integer JDN; Julian 1900-01-01 is 2415033, the same physical
/// day as Gregorian 1900-01-13.
/// Error case: none.
/// Complexity: O(1).
pub fn date_jdn_from_julian(d: &CivilDate) -> Int {
  return _date_julian_to_jdn(d.year, d.month, d.day);
}

/// Gregorian civil date of a Julian Day Number (inverse of
/// date_jdn_from_gregorian).
/// Error case: none.
/// Complexity: O(1).
pub fn date_gregorian_from_jdn(jdn: Int) -> CivilDate {
  return _date_jdn_to_gregorian(jdn);
}

/// Julian-calendar date of a Julian Day Number (inverse of
/// date_jdn_from_julian).
/// Error case: none.
/// Complexity: O(1).
pub fn date_julian_from_jdn(jdn: Int) -> CivilDate {
  return _date_jdn_to_julian(jdn);
}

/// Convert a Gregorian date to the same physical day in the Julian calendar.
/// Params: d - a valid Gregorian CivilDate.
/// Returns: the Julian-calendar date via the shared JDN. Offset examples:
/// Gregorian 1582-10-15 -> 1582-10-05 (10 days), 1900-01-13 -> 1900-01-01
/// (13 days), 2024-01-01 -> 2023-12-19 (13 days), 2100-03-01 -> 2100-02-16
/// (14 days). See the module header for the full offset rule.
/// Error case: none.
/// Complexity: O(1).
pub fn date_gregorian_to_julian(d: &CivilDate) -> CivilDate {
  let jdn = _date_gregorian_to_jdn(d.year, d.month, d.day);
  return _date_jdn_to_julian(jdn);
}

/// Convert a Julian-calendar date to the same physical day in the Gregorian
/// calendar (inverse of date_gregorian_to_julian).
/// Error case: none.
/// Complexity: O(1).
pub fn date_julian_to_gregorian(d: &CivilDate) -> CivilDate {
  let jdn = _date_julian_to_jdn(d.year, d.month, d.day);
  return _date_jdn_to_gregorian(jdn);
}

// ---------------------------------------------------------------------------
// Epoch days, weekday, day of year
// ---------------------------------------------------------------------------

/// Days from 1970-01-01 (Gregorian, proleptic) to `d`; negative before the
/// epoch.
/// Params: d - a valid CivilDate.
/// Returns: JDN(d) - 2440588. Examples: 1970-01-01 -> 0; 1969-12-31 -> -1;
/// 1969-01-01 -> -365; 2000-03-01 -> 11017; 1582-10-15 -> -141427.
/// Error case: none.
/// Complexity: O(1).
pub fn date_to_epoch_day(d: &CivilDate) -> Int {
  let jdn = _date_gregorian_to_jdn(d.year, d.month, d.day);
  return jdn - _DATE_EPOCH_JDN;
}

/// Gregorian date at an epoch-day offset (inverse of date_to_epoch_day).
/// Error case: none.
/// Complexity: O(1).
pub fn date_from_epoch_day(z: Int) -> CivilDate {
  return _date_jdn_to_gregorian(z + _DATE_EPOCH_JDN);
}

/// Weekday of a date: 0=Sunday, 1=Monday, ... 6=Saturday.
/// Params: d - a valid CivilDate.
/// Returns: ((epoch_day(d) + 4) mod 7) with a floored remainder, so
/// pre-1970 dates are correct. Examples: 1970-01-01 -> 4 (Thursday);
/// 2024-01-01 -> 1 (Monday); 2024-02-29 -> 4; 1900-01-01 -> 1.
/// Error case: none.
/// Complexity: O(1).
pub fn date_weekday(d: &CivilDate) -> Int {
  let z = date_to_epoch_day(d);
  var w = (z % 7) + 4;
  if w < 0 { w = w + 7; }
  if w >= 7 { w = w - 7; }
  return w;
}

/// Day of the year, 1..365 (366 in leap years).
/// Params: d - a valid CivilDate.
/// Examples: 2024-01-01 -> 1; 2024-03-01 -> 61; 2023-12-31 -> 365;
/// 2024-12-31 -> 366.
/// Error case: none.
/// Complexity: O(month).
pub fn date_day_of_year(d: &CivilDate) -> Int {
  var total = d.day;
  var m = 1;
  while m < d.month {
    total = total + date_days_in_month(d.year, m);
    m = m + 1;
  }
  return total;
}

// ---------------------------------------------------------------------------
// Pattern tokens
// ---------------------------------------------------------------------------

// Longest known token at byte `at` ("YYYY" "MMMM" "YY" "MMM" "MM" "DD" "M"
// "D"), or "" when none matches. Longest-match order makes "YYYYMMDD" scan as
// YYYY MM DD.
fn _date_token_at(pattern: Str, at: Int) -> Str {
  if _date_starts_at(pattern, at, "YYYY") { return "YYYY"; }
  if _date_starts_at(pattern, at, "MMMM") { return "MMMM"; }
  if _date_starts_at(pattern, at, "YY") { return "YY"; }
  if _date_starts_at(pattern, at, "MMM") { return "MMM"; }
  if _date_starts_at(pattern, at, "MM") { return "MM"; }
  if _date_starts_at(pattern, at, "DD") { return "DD"; }
  if _date_starts_at(pattern, at, "M") { return "M"; }
  if _date_starts_at(pattern, at, "D") { return "D"; }
  return "";
}

// Index of the longest table entry that occurs in `text` at byte `at`, or -1.
fn _date_match_month(tbl: &Vec[Str], text: Str, at: Int) -> Int {
  var best = -1;
  var best_len = 0;
  var i = 0;
  while i < tbl.len() {
    let cand: Str = tbl[i];
    if cand.len() > best_len {
      if _date_starts_at(text, at, cand) {
        best = i;
        best_len = cand.len();
      }
    }
    i = i + 1;
  }
  return best;
}

fn _date_pad2(v: Int) -> Str {
  if v < 10 { return "0" + convert.int_to_string(v); }
  return convert.int_to_string(v);
}

fn _date_pad4(v: Int) -> Str {
  var s = convert.int_to_string(v);
  while s.len() < 4 { s = "0" + s; }
  return s;
}

// ---------------------------------------------------------------------------
// Pattern formatting
// ---------------------------------------------------------------------------

/// Format a date with a pattern over caller-supplied month tables.
/// Params: d - the date to render (validated first); pattern - tokens YYYY
/// (4-digit year), YY (last two year digits), MMMM (full month name from
/// month_names), MMM (abbreviation from month_abbrs), MM/M (zero-padded /
/// plain month), DD/D (zero-padded / plain day); every non-letter byte is a
/// literal copied verbatim. month_names and month_abbrs must each hold
/// exactly 12 Str entries.
/// Returns: Ok(text) with every token expanded; Err("date: month table must
/// have 12 entries"), Err(<validation error>) for an invalid date,
/// Err("date: year out of range: <y>") when YYYY/YY is used and the year is
/// outside 0..9999, Err("date: unknown pattern token: <run>") for a letter
/// run that is not a token.
/// Examples: "YYYY-MM-DD" -> "2024-02-29"; "D MMMM YYYY" -> "29 February
/// 2024"; "M/D/YY" -> "2/29/24".
/// Complexity: O(len(pattern) + len(output)).
pub fn date_format(d: &CivilDate, pattern: Str, month_names: &Vec[Str], month_abbrs: &Vec[Str]) -> Result[Str, Str] {
  if month_names.len() != _DATE_TABLE_LEN || month_abbrs.len() != _DATE_TABLE_LEN {
    return _str_err("date: month table must have 12 entries");
  }
  let reason = _date_invalid_reason(d.year, d.month, d.day);
  if reason.len() > 0 {
    return _str_err(reason);
  }
  var out = "";
  var i = 0;
  while i < pattern.len() {
    let c = _date_byte(pattern, i);
    if !_date_is_alpha(c) {
      out = out + string.str_slice(pattern, i, i + 1);
      i = i + 1;
      continue;
    }
    let tok = _date_token_at(pattern, i);
    if tok.len() == 0 {
      let run_end = _date_letters_end(pattern, i);
      return _str_err("date: unknown pattern token: " + string.str_slice(pattern, i, run_end));
    }
    if compare.str_compare(tok, "YYYY") == 0 {
      if d.year < 0 || d.year > _DATE_YEAR_MAX {
        return _str_err("date: year out of range: " + convert.int_to_string(d.year));
      }
      out = out + _date_pad4(d.year);
    } elif compare.str_compare(tok, "YY") == 0 {
      if d.year < 0 || d.year > _DATE_YEAR_MAX {
        return _str_err("date: year out of range: " + convert.int_to_string(d.year));
      }
      out = out + _date_pad2(d.year % 100);
    } elif compare.str_compare(tok, "MMMM") == 0 {
      let name: Str = month_names[d.month - 1];
      out = out + name;
    } elif compare.str_compare(tok, "MMM") == 0 {
      let abbr: Str = month_abbrs[d.month - 1];
      out = out + abbr;
    } elif compare.str_compare(tok, "MM") == 0 {
      out = out + _date_pad2(d.month);
    } elif compare.str_compare(tok, "M") == 0 {
      out = out + convert.int_to_string(d.month);
    } elif compare.str_compare(tok, "DD") == 0 {
      out = out + _date_pad2(d.day);
    } else {
      out = out + convert.int_to_string(d.day);
    }
    i = i + tok.len();
  }
  return _str_ok(out);
}

// ---------------------------------------------------------------------------
// Pattern parsing
// ---------------------------------------------------------------------------

/// Parse a date from text against a pattern over caller-supplied month
/// tables.
/// Params: text - the input; pattern - as in date_format; month_names /
/// month_abbrs - exactly 12 entries each, matched byte-wise (MMMM against
/// month_names, MMM against month_abbrs, longest match wins inside a table).
/// Fields absent from the pattern default to 1970-01-01, and the assembled
/// date is validated as a whole.
/// Grammar: YYYY reads exactly 4 digits (year 0..9999); YY reads exactly 2
/// digits and maps 00..68 -> 2000..2068 and 69..99 -> 1969..1999; MM/DD read
/// exactly 2 digits; M/D read 1..2 digits; literals must match byte-wise.
/// Returns: Ok(CivilDate); Err("date: empty pattern"), Err("date: month
/// table must have 12 entries"), Err("date: unknown pattern token: <run>"),
/// Err("date: expected 4 digits for YYYY at byte <i>") (and the YY/MM/DD
/// two-digit variants), Err("date: expected digits for M at byte <i>") (and
/// the D variant), Err("date: bad month name at byte <i>"), Err("date:
/// literal mismatch at byte <i>"), Err("date: trailing text at byte <i>"),
/// Err("date: invalid month: <m>") or Err("date: invalid day: <d>").
/// Examples: ("2024-02-29", "YYYY-MM-DD") -> Ok; ("29 February 2024",
/// "D MMMM YYYY") -> Ok; ("70/01/01", "YY/MM/DD") -> Ok(1970-01-01).
/// Complexity: O(len(text) + len(pattern)).
pub fn date_parse(text: Str, pattern: Str, month_names: &Vec[Str], month_abbrs: &Vec[Str]) -> Result[CivilDate, Str] {
  if month_names.len() != _DATE_TABLE_LEN || month_abbrs.len() != _DATE_TABLE_LEN {
    return _date_err("date: month table must have 12 entries");
  }
  if pattern.len() == 0 {
    return _date_err("date: empty pattern");
  }
  var year = 1970;
  var month = 1;
  var day = 1;
  var i = 0;
  var p = 0;
  while i < pattern.len() {
    let c = _date_byte(pattern, i);
    if !_date_is_alpha(c) {
      if p >= text.len() {
        return _date_err("date: literal mismatch at byte " + convert.int_to_string(p));
      }
      if _date_byte(text, p) != c {
        return _date_err("date: literal mismatch at byte " + convert.int_to_string(p));
      }
      p = p + 1;
      i = i + 1;
      continue;
    }
    let tok = _date_token_at(pattern, i);
    if tok.len() == 0 {
      let run_end = _date_letters_end(pattern, i);
      return _date_err("date: unknown pattern token: " + string.str_slice(pattern, i, run_end));
    }
    if compare.str_compare(tok, "YYYY") == 0 {
      if !_date_digits_at(text, p, 4) {
        return _date_err("date: expected 4 digits for YYYY at byte " + convert.int_to_string(p));
      }
      year = _date_read_digits(text, p, 4);
      p = p + 4;
    } elif compare.str_compare(tok, "YY") == 0 {
      if !_date_digits_at(text, p, 2) {
        return _date_err("date: expected 2 digits for YY at byte " + convert.int_to_string(p));
      }
      let yy = _date_read_digits(text, p, 2);
      if yy <= 68 {
        year = 2000 + yy;
      } else {
        year = 1900 + yy;
      }
      p = p + 2;
    } elif compare.str_compare(tok, "MMMM") == 0 {
      let idx = _date_match_month(month_names, text, p);
      if idx < 0 {
        return _date_err("date: bad month name at byte " + convert.int_to_string(p));
      }
      let name: Str = month_names[idx];
      month = idx + 1;
      p = p + name.len();
    } elif compare.str_compare(tok, "MMM") == 0 {
      let idx = _date_match_month(month_abbrs, text, p);
      if idx < 0 {
        return _date_err("date: bad month name at byte " + convert.int_to_string(p));
      }
      let abbr: Str = month_abbrs[idx];
      month = idx + 1;
      p = p + abbr.len();
    } elif compare.str_compare(tok, "MM") == 0 {
      if !_date_digits_at(text, p, 2) {
        return _date_err("date: expected 2 digits for MM at byte " + convert.int_to_string(p));
      }
      month = _date_read_digits(text, p, 2);
      p = p + 2;
    } elif compare.str_compare(tok, "M") == 0 {
      let cnt = _date_digit_run(text, p, 2);
      if cnt == 0 {
        return _date_err("date: expected digits for M at byte " + convert.int_to_string(p));
      }
      month = _date_read_digits(text, p, cnt);
      p = p + cnt;
    } elif compare.str_compare(tok, "DD") == 0 {
      if !_date_digits_at(text, p, 2) {
        return _date_err("date: expected 2 digits for DD at byte " + convert.int_to_string(p));
      }
      day = _date_read_digits(text, p, 2);
      p = p + 2;
    } else {
      let cnt = _date_digit_run(text, p, 2);
      if cnt == 0 {
        return _date_err("date: expected digits for D at byte " + convert.int_to_string(p));
      }
      day = _date_read_digits(text, p, cnt);
      p = p + cnt;
    }
    i = i + tok.len();
  }
  if p < text.len() {
    return _date_err("date: trailing text at byte " + convert.int_to_string(p));
  }
  let reason = _date_invalid_reason(year, month, day);
  if reason.len() > 0 {
    return _date_err(reason);
  }
  let out = CivilDate{ year: year; month: month; day: day; };
  return _date_ok(out);
}

// ---------------------------------------------------------------------------
// ISO 8601 convenience pair
// ---------------------------------------------------------------------------

/// Render a date as "YYYY-MM-DD" (the exact inverse of date_iso_parse).
/// Params: d - the date; year must be in 0..9999.
/// Returns: Ok(text) of exactly 10 bytes; Err(<validation error>) for an
/// invalid date; Err("date: year out of range: <y>") outside 0..9999.
/// Examples: (2024-02-29) -> "2024-02-29"; (1970-01-01) -> "1970-01-01".
/// Error case: see above.
/// Complexity: O(1).
pub fn date_iso_format(d: &CivilDate) -> Result[Str, Str] {
  let reason = _date_invalid_reason(d.year, d.month, d.day);
  if reason.len() > 0 {
    return _str_err(reason);
  }
  if d.year < 0 || d.year > _DATE_YEAR_MAX {
    return _str_err("date: year out of range: " + convert.int_to_string(d.year));
  }
  return _str_ok(_date_pad4(d.year) + "-" + _date_pad2(d.month) + "-" + _date_pad2(d.day));
}

/// Parse a strict "YYYY-MM-DD" date (10 bytes, two '-' separators, 4/2/2
/// digits; no signs, no surrounding text).
/// Params: text - exactly 10 ASCII bytes.
/// Returns: Ok(CivilDate); Err("date: expected 10 bytes for iso date: <text>")
/// for any other length; Err("date: bad iso separator at byte 4") / (byte 7)
/// when a '-' is missing; Err("date: expected 4 digits for iso year at byte
/// 0"), Err("date: expected 2 digits for iso month at byte 5"), Err("date:
/// expected 2 digits for iso day at byte 8") for non-digit fields; then the
/// same month/day validation errors as date_make.
/// Examples: ("2024-02-29") -> Ok; ("2024-2-29") -> Err (9 bytes).
/// Error case: see above.
/// Complexity: O(1).
pub fn date_iso_parse(text: Str) -> Result[CivilDate, Str] {
  if text.len() != 10 {
    return _date_err("date: expected 10 bytes for iso date: " + text);
  }
  if _date_byte(text, 4) != _DATE_DASH {
    return _date_err("date: bad iso separator at byte 4");
  }
  if _date_byte(text, 7) != _DATE_DASH {
    return _date_err("date: bad iso separator at byte 7");
  }
  if !_date_digits_at(text, 0, 4) {
    return _date_err("date: expected 4 digits for iso year at byte 0");
  }
  if !_date_digits_at(text, 5, 2) {
    return _date_err("date: expected 2 digits for iso month at byte 5");
  }
  if !_date_digits_at(text, 8, 2) {
    return _date_err("date: expected 2 digits for iso day at byte 8");
  }
  let year = _date_read_digits(text, 0, 4);
  let month = _date_read_digits(text, 5, 2);
  let day = _date_read_digits(text, 8, 2);
  let reason = _date_invalid_reason(year, month, day);
  if reason.len() > 0 {
    return _date_err(reason);
  }
  let out = CivilDate{ year: year; month: month; day: day; };
  return _date_ok(out);
}
