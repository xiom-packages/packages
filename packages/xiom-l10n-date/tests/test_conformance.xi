// XIOM -- xiom.l10n.date conformance tests (18 checks)
// Port task: prove the pure-XIOM xiom.l10n.date module against its documented
// civil-date arithmetic, calendar conversion, formatting and parsing contract.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixtures were cross-checked against the .NET proleptic Gregorian and
// JulianCalendar implementations plus the Fliegel-Van Flandern JDN formulas.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every string check
// is routed through streq and every Vec[Str] read is bound to a typed local.
// Test dispatch is a direct call chain (t1..t18 from main), never a Vec[fn]
// table. The two parallel month-name tables are pushed month by month inside
// each builder and cross-checked in t18.

module l10n_date_tests
use xiom.io; use xiom.test;
use xiom.l10n.date;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// ---------------------------------------------------------------------------
// English fixture tables
// ---------------------------------------------------------------------------

fn names_en() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("January");
  v.push("February");
  v.push("March");
  v.push("April");
  v.push("May");
  v.push("June");
  v.push("July");
  v.push("August");
  v.push("September");
  v.push("October");
  v.push("November");
  v.push("December");
  return v;
}

fn abbrs_en() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("Jan");
  v.push("Feb");
  v.push("Mar");
  v.push("Apr");
  v.push("May");
  v.push("Jun");
  v.push("Jul");
  v.push("Aug");
  v.push("Sep");
  v.push("Oct");
  v.push("Nov");
  v.push("Dec");
  return v;
}

// German fixture tables: \u{...} escapes keep the expectations exact UTF-8
// byte sequences (three names carry multi-byte characters).
fn names_de() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("Januar");
  v.push("Februar");
  v.push("M\u{00E4}rz");
  v.push("April");
  v.push("Mai");
  v.push("Juni");
  v.push("Juli");
  v.push("August");
  v.push("September");
  v.push("Oktober");
  v.push("November");
  v.push("Dezember");
  return v;
}

fn abbrs_de() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("Jan");
  v.push("Feb");
  v.push("M\u{00E4}r");
  v.push("Apr");
  v.push("Mai");
  v.push("Jun");
  v.push("Jul");
  v.push("Aug");
  v.push("Sep");
  v.push("Okt");
  v.push("Nov");
  v.push("Dez");
  return v;
}

// ---------------------------------------------------------------------------
// Construction and field probes
// ---------------------------------------------------------------------------

fn mk(y: Int, m: Int, d: Int) -> CivilDate {
  match date_make(y, m, d) {
    Ok(v) => { return v; },
    Err(e) => {
      let bad = CivilDate{ year: 0; month: 0; day: 0; };
      return bad;
    },
  }
  let bad = CivilDate{ year: 0; month: 0; day: 0; };
  return bad;
}

fn make_err_is(y: Int, m: Int, d: Int, want: Str) -> Bool {
  match date_make(y, m, d) {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn make_ok(y: Int, m: Int, d: Int) -> Bool {
  match date_make(y, m, d) {
    Ok(v) => { return true; },
    Err(e) => { return false; },
  }
  return false;
}

fn epoch_of(y: Int, m: Int, d: Int) -> Int {
  let dt = mk(y, m, d);
  return date_to_epoch_day(&dt);
}

fn from_epoch_year(z: Int) -> Int {
  let dt = date_from_epoch_day(z);
  return date_year(&dt);
}

fn from_epoch_month(z: Int) -> Int {
  let dt = date_from_epoch_day(z);
  return date_month(&dt);
}

fn from_epoch_day(z: Int) -> Int {
  let dt = date_from_epoch_day(z);
  return date_day(&dt);
}

fn wd(y: Int, m: Int, d: Int) -> Int {
  let dt = mk(y, m, d);
  return date_weekday(&dt);
}

fn doy(y: Int, m: Int, d: Int) -> Int {
  let dt = mk(y, m, d);
  return date_day_of_year(&dt);
}

fn jdn_g(y: Int, m: Int, d: Int) -> Int {
  let dt = mk(y, m, d);
  return date_jdn_from_gregorian(&dt);
}

fn jdn_j(y: Int, m: Int, d: Int) -> Int {
  let dt = mk(y, m, d);
  return date_jdn_from_julian(&dt);
}

fn greg_from_jdn_year(z: Int) -> Int {
  let dt = date_gregorian_from_jdn(z);
  return date_year(&dt);
}

fn greg_from_jdn_month(z: Int) -> Int {
  let dt = date_gregorian_from_jdn(z);
  return date_month(&dt);
}

fn greg_from_jdn_day(z: Int) -> Int {
  let dt = date_gregorian_from_jdn(z);
  return date_day(&dt);
}

fn jul_year(y: Int, m: Int, d: Int) -> Int {
  let dt = mk(y, m, d);
  let j = date_gregorian_to_julian(&dt);
  return date_year(&j);
}

fn jul_month(y: Int, m: Int, d: Int) -> Int {
  let dt = mk(y, m, d);
  let j = date_gregorian_to_julian(&dt);
  return date_month(&j);
}

fn jul_day(y: Int, m: Int, d: Int) -> Int {
  let dt = mk(y, m, d);
  let j = date_gregorian_to_julian(&dt);
  return date_day(&j);
}

fn greg_year_j(y: Int, m: Int, d: Int) -> Int {
  let dt = mk(y, m, d);
  let g = date_julian_to_gregorian(&dt);
  return date_year(&g);
}

fn greg_month_j(y: Int, m: Int, d: Int) -> Int {
  let dt = mk(y, m, d);
  let g = date_julian_to_gregorian(&dt);
  return date_month(&g);
}

fn greg_day_j(y: Int, m: Int, d: Int) -> Int {
  let dt = mk(y, m, d);
  let g = date_julian_to_gregorian(&dt);
  return date_day(&g);
}

fn julian_roundtrip(y: Int, m: Int, d: Int) -> Bool {
  let dt = mk(y, m, d);
  let j = date_gregorian_to_julian(&dt);
  let back = date_julian_to_gregorian(&j);
  if date_year(&back) != y { return false; }
  if date_month(&back) != m { return false; }
  if date_day(&back) != d { return false; }
  return true;
}

// ---------------------------------------------------------------------------
// Pattern helpers (English tables)
// ---------------------------------------------------------------------------

fn fmt_ok(y: Int, m: Int, d: Int, pattern: Str) -> Str {
  let names = names_en();
  let abbrs = abbrs_en();
  let dt = mk(y, m, d);
  match date_format(&dt, pattern, &names, &abbrs) {
    Ok(s) => { return s; },
    Err(e) => { return "!error"; },
  }
  return "!error";
}

fn fmt_err_is(y: Int, m: Int, d: Int, pattern: Str, want: Str) -> Bool {
  let names = names_en();
  let abbrs = abbrs_en();
  let dt = mk(y, m, d);
  match date_format(&dt, pattern, &names, &abbrs) {
    Ok(s) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn fmt_struct_err_is(bad: &CivilDate, pattern: Str, want: Str) -> Bool {
  let names = names_en();
  let abbrs = abbrs_en();
  match date_format(bad, pattern, &names, &abbrs) {
    Ok(s) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn parsed_year(text: Str, pattern: Str) -> Int {
  let names = names_en();
  let abbrs = abbrs_en();
  match date_parse(text, pattern, &names, &abbrs) {
    Ok(v) => { return date_year(&v); },
    Err(e) => { return -999999; },
  }
  return -999999;
}

fn parsed_month(text: Str, pattern: Str) -> Int {
  let names = names_en();
  let abbrs = abbrs_en();
  match date_parse(text, pattern, &names, &abbrs) {
    Ok(v) => { return date_month(&v); },
    Err(e) => { return -999999; },
  }
  return -999999;
}

fn parsed_day(text: Str, pattern: Str) -> Int {
  let names = names_en();
  let abbrs = abbrs_en();
  match date_parse(text, pattern, &names, &abbrs) {
    Ok(v) => { return date_day(&v); },
    Err(e) => { return -999999; },
  }
  return -999999;
}

fn parse_err_is(text: Str, pattern: Str, want: Str) -> Bool {
  let names = names_en();
  let abbrs = abbrs_en();
  match date_parse(text, pattern, &names, &abbrs) {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn parse_ok(y: Int, m: Int, d: Int, text: Str, pattern: Str) -> Bool {
  return parsed_year(text, pattern) == y && parsed_month(text, pattern) == m && parsed_day(text, pattern) == d;
}

// ---------------------------------------------------------------------------
// Pattern helpers (German multi-byte tables)
// ---------------------------------------------------------------------------

fn fmt_de(y: Int, m: Int, d: Int, pattern: Str) -> Str {
  let names = names_de();
  let abbrs = abbrs_de();
  let dt = mk(y, m, d);
  match date_format(&dt, pattern, &names, &abbrs) {
    Ok(s) => { return s; },
    Err(e) => { return "!error"; },
  }
  return "!error";
}

fn parse_de_ok(y: Int, m: Int, d: Int, text: Str, pattern: Str) -> Bool {
  let names = names_de();
  let abbrs = abbrs_de();
  match date_parse(text, pattern, &names, &abbrs) {
    Ok(v) => {
      if date_year(&v) != y { return false; }
      if date_month(&v) != m { return false; }
      if date_day(&v) != d { return false; }
      return true;
    },
    Err(e) => { return false; },
  }
  return false;
}

// ---------------------------------------------------------------------------
// ISO helpers
// ---------------------------------------------------------------------------

fn iso_ok(y: Int, m: Int, d: Int) -> Str {
  let dt = mk(y, m, d);
  match date_iso_format(&dt) {
    Ok(s) => { return s; },
    Err(e) => { return "!error"; },
  }
  return "!error";
}

fn iso_struct_err_is(bad: &CivilDate, want: Str) -> Bool {
  match date_iso_format(bad) {
    Ok(s) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn iso_parse_err_is(text: Str, want: Str) -> Bool {
  match date_iso_parse(text) {
    Ok(v) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn iso_parse_ok(y: Int, m: Int, d: Int, text: Str) -> Bool {
  match date_iso_parse(text) {
    Ok(v) => {
      if date_year(&v) != y { return false; }
      if date_month(&v) != m { return false; }
      if date_day(&v) != d { return false; }
      return true;
    },
    Err(e) => { return false; },
  }
  return false;
}

fn iso_roundtrip(y: Int, m: Int, d: Int) -> Bool {
  let dt = mk(y, m, d);
  match date_iso_format(&dt) {
    Ok(s) => {
      return iso_parse_ok(y, m, d, s);
    },
    Err(e) => { return false; },
  }
  return false;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  var ok = date_is_leap_year(2024);
  if !date_is_leap_year(2000) { ok = false; }
  if !date_is_leap_year(1600) { ok = false; }
  if !date_is_leap_year(1968) { ok = false; }
  if date_is_leap_year(1900) { ok = false; }
  if date_is_leap_year(1700) { ok = false; }
  if date_is_leap_year(2100) { ok = false; }
  if date_is_leap_year(2023) { ok = false; }
  if date_is_leap_year(1969) { ok = false; }
  return assert(ok, "leap years: 2024/2000/1600/1968 leap; 1900/1700/2100/2023/1969 not");
}

fn t2() -> TestResult {
  var ok = date_days_in_month(2024, 1) == 31;
  if date_days_in_month(2024, 3) != 31 { ok = false; }
  if date_days_in_month(2024, 4) != 30 { ok = false; }
  if date_days_in_month(2024, 6) != 30 { ok = false; }
  if date_days_in_month(2024, 9) != 30 { ok = false; }
  if date_days_in_month(2024, 11) != 30 { ok = false; }
  if date_days_in_month(2024, 12) != 31 { ok = false; }
  if date_days_in_month(2024, 2) != 29 { ok = false; }
  if date_days_in_month(1900, 2) != 28 { ok = false; }
  if date_days_in_month(2000, 2) != 29 { ok = false; }
  if date_days_in_month(2024, 0) != 0 { ok = false; }
  if date_days_in_month(2024, 13) != 0 { ok = false; }
  return assert(ok, "month lengths: 28..31 per month, 0 for invalid months");
}

fn t3() -> TestResult {
  var ok = make_ok(2024, 2, 29);
  if !make_ok(2000, 2, 29) { ok = false; }
  if !make_ok(2024, 12, 31) { ok = false; }
  if !make_ok(1, 1, 1) { ok = false; }
  if !make_err_is(2023, 2, 29, "date: invalid day: 29") { ok = false; }
  if !make_err_is(1900, 2, 29, "date: invalid day: 29") { ok = false; }
  if !make_err_is(2024, 4, 31, "date: invalid day: 31") { ok = false; }
  if !make_err_is(2024, 1, 0, "date: invalid day: 0") { ok = false; }
  if !make_err_is(2024, 1, 32, "date: invalid day: 32") { ok = false; }
  if !make_err_is(2024, 0, 10, "date: invalid month: 0") { ok = false; }
  if !make_err_is(2024, 13, 1, "date: invalid month: 13") { ok = false; }
  if !date_is_valid(2024, 2, 29) { ok = false; }
  if date_is_valid(2023, 2, 29) { ok = false; }
  let dt = mk(2024, 2, 29);
  if date_year(&dt) != 2024 { ok = false; }
  if date_month(&dt) != 2 { ok = false; }
  if date_day(&dt) != 29 { ok = false; }
  return assert(ok, "date_make: leap-aware validation with exact error strings");
}

fn t4() -> TestResult {
  var ok = epoch_of(1970, 1, 1) == 0;
  if epoch_of(1969, 12, 31) != -1 { ok = false; }
  if epoch_of(1969, 12, 30) != -2 { ok = false; }
  if epoch_of(1969, 1, 1) != -365 { ok = false; }
  if epoch_of(1900, 1, 1) != -25567 { ok = false; }
  if epoch_of(1582, 10, 15) != -141427 { ok = false; }
  if epoch_of(1858, 11, 17) != -40587 { ok = false; }
  if epoch_of(2000, 1, 1) != 10957 { ok = false; }
  if epoch_of(2000, 3, 1) != 11017 { ok = false; }
  if epoch_of(2024, 2, 29) != 19782 { ok = false; }
  if epoch_of(2024, 12, 31) != 20088 { ok = false; }
  return assert(ok, "epoch days: positive values and exact pre-1970 negatives");
}

fn t5() -> TestResult {
  var ok = from_epoch_year(0) == 1970 && from_epoch_month(0) == 1 && from_epoch_day(0) == 1;
  if from_epoch_year(-1) != 1969 { ok = false; }
  if from_epoch_month(-1) != 12 { ok = false; }
  if from_epoch_day(-1) != 31 { ok = false; }
  if from_epoch_year(-365) != 1969 { ok = false; }
  if from_epoch_year(-25567) != 1900 { ok = false; }
  if from_epoch_year(11017) != 2000 { ok = false; }
  if from_epoch_month(11017) != 3 { ok = false; }
  if from_epoch_year(-141427) != 1582 { ok = false; }
  if from_epoch_month(-141427) != 10 { ok = false; }
  if from_epoch_day(-141427) != 15 { ok = false; }
  if from_epoch_day(19782) != 29 { ok = false; }
  if epoch_of(1969, 12, 31) != -1 { ok = false; }
  if from_epoch_year(19783) != 2024 { ok = false; }
  return assert(ok, "epoch days: from_epoch_day inverts pre- and post-1970 dates");
}

fn t6() -> TestResult {
  var ok = wd(1970, 1, 1) == 4;
  if wd(1969, 12, 31) != 3 { ok = false; }
  if wd(1969, 12, 30) != 2 { ok = false; }
  if wd(1969, 1, 1) != 3 { ok = false; }
  if wd(1900, 1, 1) != 1 { ok = false; }
  if wd(2000, 1, 1) != 6 { ok = false; }
  if wd(2000, 3, 1) != 3 { ok = false; }
  if wd(2024, 2, 29) != 4 { ok = false; }
  if wd(2024, 12, 31) != 2 { ok = false; }
  if wd(1582, 10, 15) != 5 { ok = false; }
  if wd(2023, 12, 31) != 0 { ok = false; }
  return assert(ok, "weekday: 0=Sunday for known dates in four centuries");
}

fn t7() -> TestResult {
  var ok = doy(2024, 1, 1) == 1;
  if doy(2024, 2, 29) != 60 { ok = false; }
  if doy(2024, 3, 1) != 61 { ok = false; }
  if doy(2023, 12, 31) != 365 { ok = false; }
  if doy(2024, 12, 31) != 366 { ok = false; }
  if doy(1900, 3, 1) != 60 { ok = false; }
  if doy(2000, 3, 1) != 61 { ok = false; }
  if doy(1969, 12, 31) != 365 { ok = false; }
  return assert(ok, "day of year: 1..365/366 across leap and common years");
}

fn t8() -> TestResult {
  var ok = jdn_g(1970, 1, 1) == 2440588;
  if jdn_g(2000, 1, 1) != 2451545 { ok = false; }
  if jdn_g(1858, 11, 17) != 2400001 { ok = false; }
  if jdn_g(1582, 10, 15) != 2299161 { ok = false; }
  if jdn_g(2024, 2, 29) != 2460370 { ok = false; }
  if jdn_g(1900, 1, 1) != 2415021 { ok = false; }
  if jdn_g(2024, 2, 29) - jdn_g(2024, 2, 28) != 1 { ok = false; }
  if jdn_g(1969, 12, 31) - jdn_g(1970, 1, 1) != -1 { ok = false; }
  return assert(ok, "JDN: Gregorian day numbers match the reference values");
}

fn t9() -> TestResult {
  var ok = greg_from_jdn_year(2440588) == 1970;
  if greg_from_jdn_month(2440588) != 1 { ok = false; }
  if greg_from_jdn_day(2440588) != 1 { ok = false; }
  if greg_from_jdn_year(2451545) != 2000 { ok = false; }
  if greg_from_jdn_month(2451545) != 1 { ok = false; }
  if greg_from_jdn_year(2400001) != 1858 { ok = false; }
  if greg_from_jdn_month(2400001) != 11 { ok = false; }
  if greg_from_jdn_day(2400001) != 17 { ok = false; }
  if greg_from_jdn_year(2299161) != 1582 { ok = false; }
  if greg_from_jdn_month(2299161) != 10 { ok = false; }
  if greg_from_jdn_day(2299161) != 15 { ok = false; }
  if greg_from_jdn_year(2415021) != 1900 { ok = false; }
  if jdn_g(greg_from_jdn_year(2460370), greg_from_jdn_month(2460370), greg_from_jdn_day(2460370)) != 2460370 { ok = false; }
  return assert(ok, "JDN inverse: gregorian_from_jdn round-trips reference values");
}

fn t10() -> TestResult {
  var ok = jul_year(1900, 1, 13) == 1900 && jul_month(1900, 1, 13) == 1 && jul_day(1900, 1, 13) == 1;
  if jul_year(1582, 10, 15) != 1582 { ok = false; }
  if jul_month(1582, 10, 15) != 10 { ok = false; }
  if jul_day(1582, 10, 15) != 5 { ok = false; }
  if jul_year(2024, 1, 1) != 2023 { ok = false; }
  if jul_month(2024, 1, 1) != 12 { ok = false; }
  if jul_day(2024, 1, 1) != 19 { ok = false; }
  if jul_year(1700, 3, 1) != 1700 { ok = false; }
  if jul_month(1700, 3, 1) != 2 { ok = false; }
  if jul_day(1700, 3, 1) != 19 { ok = false; }
  if jul_month(1800, 3, 1) != 2 { ok = false; }
  if jul_day(1800, 3, 1) != 18 { ok = false; }
  if jul_month(2100, 3, 1) != 2 { ok = false; }
  if jul_day(2100, 3, 1) != 16 { ok = false; }
  if jul_year(1900, 1, 1) != 1899 { ok = false; }
  if jul_month(1900, 1, 1) != 12 { ok = false; }
  if jul_day(1900, 1, 1) != 20 { ok = false; }
  if jdn_j(1900, 1, 1) != jdn_g(1900, 1, 13) { ok = false; }
  if jdn_j(1582, 10, 5) != jdn_g(1582, 10, 15) { ok = false; }
  if jdn_j(2023, 12, 19) != jdn_g(2024, 1, 1) { ok = false; }
  return assert(ok, "Gregorian -> Julian: reform, 12/13/14-day drift and shared JDN");
}

fn t11() -> TestResult {
  var ok = greg_year_j(1900, 1, 1) == 1900 && greg_month_j(1900, 1, 1) == 1 && greg_day_j(1900, 1, 1) == 13;
  if greg_year_j(1582, 10, 5) != 1582 { ok = false; }
  if greg_month_j(1582, 10, 5) != 10 { ok = false; }
  if greg_day_j(1582, 10, 5) != 15 { ok = false; }
  if greg_year_j(2023, 12, 19) != 2024 { ok = false; }
  if greg_month_j(2023, 12, 19) != 1 { ok = false; }
  if greg_day_j(2023, 12, 19) != 1 { ok = false; }
  if greg_year_j(1899, 12, 20) != 1900 { ok = false; }
  if greg_month_j(1899, 12, 20) != 1 { ok = false; }
  if greg_day_j(1899, 12, 20) != 1 { ok = false; }
  if !julian_roundtrip(2024, 2, 29) { ok = false; }
  if !julian_roundtrip(1969, 12, 31) { ok = false; }
  if !julian_roundtrip(1900, 3, 1) { ok = false; }
  if !julian_roundtrip(1582, 10, 15) { ok = false; }
  if !julian_roundtrip(2100, 2, 28) { ok = false; }
  return assert(ok, "Julian -> Gregorian: inverse pairs and full round-trips");
}

fn t12() -> TestResult {
  var ok = streq(fmt_ok(2024, 2, 29, "YYYY-MM-DD"), "2024-02-29");
  if !streq(fmt_ok(2024, 2, 29, "D MMMM YYYY"), "29 February 2024") { ok = false; }
  if !streq(fmt_ok(2024, 2, 29, "MMMM D, YYYY"), "February 29, 2024") { ok = false; }
  if !streq(fmt_ok(2024, 2, 29, "MMM D YYYY"), "Feb 29 2024") { ok = false; }
  if !streq(fmt_ok(2024, 2, 29, "M/D/YY"), "2/29/24") { ok = false; }
  if !streq(fmt_ok(2024, 2, 29, "YYYYMMDD"), "20240229") { ok = false; }
  if !streq(fmt_ok(1999, 1, 5, "D.M.YYYY"), "5.1.1999") { ok = false; }
  if !streq(fmt_ok(1969, 12, 31, "YY"), "69") { ok = false; }
  if !streq(fmt_ok(2068, 1, 1, "YY"), "68") { ok = false; }
  if !streq(fmt_ok(1970, 1, 1, "YYYY-MM-DD"), "1970-01-01") { ok = false; }
  return assert(ok, "format: tokens, literals, padding and adjacent tokens");
}

fn t13() -> TestResult {
  var ok = fmt_err_is(2024, 2, 29, "YYYY-QQ", "date: unknown pattern token: QQ");
  if !fmt_err_is(2024, 2, 29, "Y", "date: unknown pattern token: Y") { ok = false; }
  if !fmt_err_is(2024, 2, 29, "YYYYY", "date: unknown pattern token: Y") { ok = false; }
  let big = CivilDate{ year: 10000; month: 1; day: 1; };
  if !fmt_struct_err_is(&big, "YYYY", "date: year out of range: 10000") { ok = false; }
  if !fmt_struct_err_is(&big, "YY", "date: year out of range: 10000") { ok = false; }
  let neg = CivilDate{ year: -1; month: 1; day: 1; };
  if !fmt_struct_err_is(&neg, "YYYY", "date: year out of range: -1") { ok = false; }
  let bad = CivilDate{ year: 2023; month: 2; day: 29; };
  if !fmt_struct_err_is(&bad, "YYYY-MM-DD", "date: invalid day: 29") { ok = false; }
  let bad2 = CivilDate{ year: 2024; month: 13; day: 1; };
  if !fmt_struct_err_is(&bad2, "MM", "date: invalid month: 13") { ok = false; }
  let names = names_en();
  let abbrs = abbrs_en();
  var short_table = Vec[Str].new();
  var i = 0;
  while i < 11 {
    let entry: Str = names[i];
    short_table.push(entry);
    i = i + 1;
  }
  let dt = mk(2024, 2, 29);
  match date_format(&dt, "YYYY", &short_table, &abbrs) {
    Ok(s) => { ok = false; },
    Err(e) => {
      if !streq(e, "date: month table must have 12 entries") { ok = false; }
    },
  }
  return assert(ok, "format errors: unknown tokens, year range, invalid date, table size");
}

fn t14() -> TestResult {
  var ok = parse_ok(2024, 2, 29, "2024-02-29", "YYYY-MM-DD");
  if !parse_ok(2024, 2, 29, "29 February 2024", "D MMMM YYYY") { ok = false; }
  if !parse_ok(2024, 2, 29, "February 29, 2024", "MMMM D, YYYY") { ok = false; }
  if !parse_ok(2024, 2, 29, "Feb 29 2024", "MMM D YYYY") { ok = false; }
  if !parse_ok(2024, 2, 29, "20240229", "YYYYMMDD") { ok = false; }
  if !parse_ok(2024, 2, 29, "2/29/2024", "M/D/YYYY") { ok = false; }
  if !parse_ok(1969, 12, 31, "31 Dec 1969", "D MMM YYYY") { ok = false; }
  if !parse_ok(1970, 7, 4, "07-04", "MM-DD") { ok = false; }
  if !parse_ok(1970, 1, 1, "01-01", "MM-DD") { ok = false; }
  if !parse_ok(1999, 1, 5, "5.1.1999", "D.M.YYYY") { ok = false; }
  if parsed_year("garbage", "YYYY-MM-DD") != -999999 { ok = false; }
  return assert(ok, "parse: full-name, abbreviated, numeric and default-field patterns");
}

fn t15() -> TestResult {
  var ok = parsed_year("69/12/31", "YY/MM/DD") == 1969;
  if parsed_year("68/01/01", "YY/MM/DD") != 2068 { ok = false; }
  if parsed_year("00/01/01", "YY/MM/DD") != 2000 { ok = false; }
  if parsed_year("99/12/31", "YY/MM/DD") != 1999 { ok = false; }
  if parsed_year("70/01/01", "YY/MM/DD") != 1970 { ok = false; }
  if parsed_month("69/12/31", "YY/MM/DD") != 12 { ok = false; }
  if parsed_day("69/12/31", "YY/MM/DD") != 31 { ok = false; }
  if !streq(fmt_ok(1969, 12, 31, "YY/MM/DD"), "69/12/31") { ok = false; }
  if !streq(fmt_ok(2068, 1, 1, "YY/MM/DD"), "68/01/01") { ok = false; }
  return assert(ok, "YY: parses 00..68 -> 2000s and 69..99 -> 1900s, formats last two digits");
}

fn t16() -> TestResult {
  var ok = parse_err_is("x", "", "date: empty pattern");
  if !parse_err_is("2024-02-29", "YYYY-QQ", "date: unknown pattern token: QQ") { ok = false; }
  if !parse_err_is("2024-02-29", "YYYY/MM/DD", "date: literal mismatch at byte 4") { ok = false; }
  if !parse_err_is("2024-02-29x", "YYYY-MM-DD", "date: trailing text at byte 10") { ok = false; }
  if !parse_err_is("2024-2-29", "YYYY-MM-DD", "date: expected 2 digits for MM at byte 5") { ok = false; }
  if !parse_err_is("20x4-02-29", "YYYY-MM-DD", "date: expected 4 digits for YYYY at byte 0") { ok = false; }
  if !parse_err_is("2024-02-2", "YYYY-MM-DD", "date: expected 2 digits for DD at byte 8") { ok = false; }
  if !parse_err_is("2024-02-29", "YYYY-MM", "date: trailing text at byte 7") { ok = false; }
  if !parse_err_is("29 Foo 2024", "D MMMM YYYY", "date: bad month name at byte 3") { ok = false; }
  if !parse_err_is("2024-13-01", "YYYY-MM-DD", "date: invalid month: 13") { ok = false; }
  if !parse_err_is("2023-02-29", "YYYY-MM-DD", "date: invalid day: 29") { ok = false; }
  if !parse_err_is("2024-04-31", "YYYY-MM-DD", "date: invalid day: 31") { ok = false; }
  if !parse_err_is("31 February 2024", "D MMMM YYYY", "date: invalid day: 31") { ok = false; }
  if !parse_err_is("5x", "D", "date: trailing text at byte 1") { ok = false; }
  if !parse_err_is("x", "D", "date: expected digits for D at byte 0") { ok = false; }
  return assert(ok, "parse errors: the full documented catalog with byte offsets");
}

fn t17() -> TestResult {
  var ok = streq(iso_ok(2024, 2, 29), "2024-02-29");
  if !streq(iso_ok(1970, 1, 1), "1970-01-01") { ok = false; }
  if !streq(iso_ok(1582, 10, 15), "1582-10-15") { ok = false; }
  if !streq(iso_ok(9999, 12, 31), "9999-12-31") { ok = false; }
  if !iso_roundtrip(2024, 2, 29) { ok = false; }
  if !iso_roundtrip(1969, 12, 31) { ok = false; }
  if !iso_roundtrip(1900, 3, 1) { ok = false; }
  if !iso_parse_ok(2024, 2, 29, "2024-02-29") { ok = false; }
  if !iso_parse_err_is("2024-2-29", "date: expected 10 bytes for iso date: 2024-2-29") { ok = false; }
  if !iso_parse_err_is("2024x02-29", "date: bad iso separator at byte 4") { ok = false; }
  if !iso_parse_err_is("2024-02x29", "date: bad iso separator at byte 7") { ok = false; }
  if !iso_parse_err_is("20x4-02-29", "date: expected 4 digits for iso year at byte 0") { ok = false; }
  if !iso_parse_err_is("2024-x2-29", "date: expected 2 digits for iso month at byte 5") { ok = false; }
  if !iso_parse_err_is("2024-02-x9", "date: expected 2 digits for iso day at byte 8") { ok = false; }
  if !iso_parse_err_is("2023-02-29", "date: invalid day: 29") { ok = false; }
  if !iso_parse_err_is("2024-00-10", "date: invalid month: 0") { ok = false; }
  let big = CivilDate{ year: 10000; month: 1; day: 1; };
  if !iso_struct_err_is(&big, "date: year out of range: 10000") { ok = false; }
  let bad = CivilDate{ year: 2024; month: 13; day: 1; };
  if !iso_struct_err_is(&bad, "date: invalid month: 13") { ok = false; }
  return assert(ok, "iso_format/iso_parse: exact 10-byte pair, round-trips and errors");
}

fn t18() -> TestResult {
  var ok = fmt_de(2024, 3, 1, "D. MMMM YYYY") == "1. M\u{00E4}rz 2024";
  if !streq(fmt_de(2024, 3, 1, "DD MMM YYYY"), "01 M\u{00E4}r 2024") { ok = false; }
  if !parse_de_ok(2024, 3, 1, "1. M\u{00E4}rz 2024", "D. MMMM YYYY") { ok = false; }
  if !parse_de_ok(2024, 3, 1, "01 M\u{00E4}r 2024", "DD MMM YYYY") { ok = false; }
  let names = names_de();
  let abbrs = abbrs_de();
  if names.len() != 12 { ok = false; }
  if abbrs.len() != 12 { ok = false; }
  var i = 0;
  while i < 12 {
    let full: Str = names[i];
    let ab: Str = abbrs[i];
    if full.len() == 0 { ok = false; }
    if ab.len() == 0 { ok = false; }
    if !string.str_starts_with(full, ab) { ok = false; }
    if !streq(fmt_de(2024, i + 1, 15, "MMMM"), full) { ok = false; }
    if !streq(fmt_de(2024, i + 1, 15, "MMM"), ab) { ok = false; }
    i = i + 1;
  }
  return assert(ok, "non-ASCII tables: multi-byte name match, mirror integrity, 12 entries");
}

fn main() -> Int {
  io.println("=== xiom.l10n.date conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.l10n.date: all tests passed");
  } else {
    io.println("xiom.l10n.date: tests failed");
  }
  return failed;
}
