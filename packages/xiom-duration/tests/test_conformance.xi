// XIOM -- xiom.duration conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.duration module against its documented
// ISO 8601 parsing, accessor and canonical-formatting contract.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module duration_tests
use xiom.io; use xiom.test; use xiom.duration;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every string check
// is routed through streq.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn ok_parse(s: Str) -> Bool {
  match duration_parse(s) {
    Ok(d) => { return true; },
    Err(e) => { return false; },
  }
}

fn err_is(s: Str, want: Str) -> Bool {
  match duration_parse(s) {
    Ok(d) => { return false; },
    Err(e) => { return streq(e, want); },
  }
}

fn sign_of(s: Str) -> Int {
  match duration_parse(s) {
    Ok(d) => { return duration_sign(&d); },
    Err(e) => { return -9; },
  }
}

fn field_of(s: Str, component: Str) -> Int {
  match duration_parse(s) {
    Ok(d) => {
      match duration_value(&d, component) {
        Ok(v) => { return v; },
        Err(e) => { return -8; },
      }
    },
    Err(e) => { return -9; },
  }
}

fn value_err_is(s: Str, component: Str, want: Str) -> Bool {
  match duration_parse(s) {
    Ok(d) => {
      match duration_value(&d, component) {
        Ok(v) => { return false; },
        Err(e) => { return streq(e, want); },
      }
    },
    Err(e) => { return false; },
  }
}

fn frac_of(s: Str) -> Str {
  match duration_parse(s) {
    Ok(d) => { return duration_fraction(&d); },
    Err(e) => { return "!"; },
  }
}

fn fmt_of(s: Str) -> Str {
  match duration_parse(s) {
    Ok(d) => { return duration_format(&d); },
    Err(e) => { return "!"; },
  }
}

fn fmt_is(s: Str, want: Str) -> Bool {
  return streq(fmt_of(s), want);
}

fn fmt_stable(s: Str) -> Bool {
  let once = fmt_of(s);
  if streq(once, "!") { return false; }
  return streq(fmt_of(once), once);
}

fn round_trip_holds(s: Str) -> Bool {
  let f = fmt_of(s);
  if streq(f, "!") { return false; }
  if sign_of(s) != sign_of(f) { return false; }
  if field_of(s, "years") != field_of(f, "years") { return false; }
  if field_of(s, "months") != field_of(f, "months") { return false; }
  if field_of(s, "weeks") != field_of(f, "weeks") { return false; }
  if field_of(s, "days") != field_of(f, "days") { return false; }
  if field_of(s, "hours") != field_of(f, "hours") { return false; }
  if field_of(s, "minutes") != field_of(f, "minutes") { return false; }
  if field_of(s, "seconds") != field_of(f, "seconds") { return false; }
  if !streq(frac_of(s), frac_of(f)) { return false; }
  return true;
}

fn total_is(s: Str, want: Int) -> Bool {
  match duration_parse(s) {
    Ok(d) => {
      match duration_total_seconds(&d) {
        Ok(v) => { return v == want; },
        Err(e) => { return false; },
      }
    },
    Err(e) => { return false; },
  }
}

fn total_err_is(s: Str, want: Str) -> Bool {
  match duration_parse(s) {
    Ok(d) => {
      match duration_total_seconds(&d) {
        Ok(v) => { return false; },
        Err(e) => { return streq(e, want); },
      }
    },
    Err(e) => { return false; },
  }
}

fn has_all_seven(s: Str) -> Bool {
  match duration_parse(s) {
    Ok(d) => {
      if !duration_has_years(&d) { return false; }
      if !duration_has_months(&d) { return false; }
      if !duration_has_weeks(&d) { return false; }
      if !duration_has_days(&d) { return false; }
      if !duration_has_hours(&d) { return false; }
      if !duration_has_minutes(&d) { return false; }
      if !duration_has_seconds(&d) { return false; }
      return true;
    },
    Err(e) => { return false; },
  }
}

fn has_none_seven(s: Str) -> Bool {
  match duration_parse(s) {
    Ok(d) => {
      if duration_has_years(&d) { return false; }
      if duration_has_months(&d) { return false; }
      if duration_has_weeks(&d) { return false; }
      if duration_has_days(&d) { return false; }
      if duration_has_hours(&d) { return false; }
      if duration_has_minutes(&d) { return false; }
      if duration_has_seconds(&d) { return false; }
      return true;
    },
    Err(e) => { return false; },
  }
}

fn has_seconds_of(s: Str) -> Bool {
  match duration_parse(s) {
    Ok(d) => { return duration_has_seconds(&d); },
    Err(e) => { return false; },
  }
}

fn has_days_of(s: Str) -> Bool {
  match duration_parse(s) {
    Ok(d) => { return duration_has_days(&d); },
    Err(e) => { return false; },
  }
}

fn has_hours_of(s: Str) -> Bool {
  match duration_parse(s) {
    Ok(d) => { return duration_has_hours(&d); },
    Err(e) => { return false; },
  }
}

fn t1() -> TestResult {
  var ok = field_of("P1Y", "years") == 1;
  if field_of("P2M", "months") != 2 { ok = false; }
  if field_of("P3W", "weeks") != 3 { ok = false; }
  if field_of("P4D", "days") != 4 { ok = false; }
  if field_of("P1Y2M3W4D", "days") != 4 { ok = false; }
  if field_of("P1Y2M3W4D", "years") != 1 { ok = false; }
  if field_of("P1Y", "months") != 0 { ok = false; }
  if field_of("P1Y", "weeks") != 0 { ok = false; }
  if field_of("P1Y", "hours") != 0 { ok = false; }
  if !ok_parse("P1Y") { ok = false; }
  if !ok_parse("P1Y2M3W4D") { ok = false; }
  return assert(ok, "parse: date components in Y M W D order");
}

fn t2() -> TestResult {
  var ok = field_of("PT5H", "hours") == 5;
  if field_of("PT6M", "minutes") != 6 { ok = false; }
  if field_of("PT7S", "seconds") != 7 { ok = false; }
  if field_of("PT5H6M7S", "hours") != 5 { ok = false; }
  if field_of("PT5H6M7S", "minutes") != 6 { ok = false; }
  if field_of("PT5H6M7S", "seconds") != 7 { ok = false; }
  if field_of("P1DT2H", "days") != 1 { ok = false; }
  if field_of("P1DT2H", "hours") != 2 { ok = false; }
  if field_of("PT1H", "years") != 0 { ok = false; }
  if field_of("PT1H", "days") != 0 { ok = false; }
  if !ok_parse("PT1H") { ok = false; }
  return assert(ok, "parse: time components in H M S order");
}

fn t3() -> TestResult {
  var ok = field_of("P1Y2M3W4DT5H6M7S", "years") == 1;
  if field_of("P1Y2M3W4DT5H6M7S", "months") != 2 { ok = false; }
  if field_of("P1Y2M3W4DT5H6M7S", "weeks") != 3 { ok = false; }
  if field_of("P1Y2M3W4DT5H6M7S", "days") != 4 { ok = false; }
  if field_of("P1Y2M3W4DT5H6M7S", "hours") != 5 { ok = false; }
  if field_of("P1Y2M3W4DT5H6M7S", "minutes") != 6 { ok = false; }
  if field_of("P1Y2M3W4DT5H6M7S", "seconds") != 7 { ok = false; }
  if sign_of("P1D") != 1 { ok = false; }
  if sign_of("+P1D") != 1 { ok = false; }
  if sign_of("-P1D") != -1 { ok = false; }
  if sign_of("-PT0.5S") != -1 { ok = false; }
  return assert(ok, "parse: full combined duration and signs");
}

fn t4() -> TestResult {
  var ok = ok_parse("P0D");
  if !ok_parse("PT0S") { ok = false; }
  if !ok_parse("P0Y") { ok = false; }
  if !ok_parse("P0M") { ok = false; }
  if !ok_parse("P0W") { ok = false; }
  if !ok_parse("PT0H") { ok = false; }
  if !ok_parse("PT0M") { ok = false; }
  if !ok_parse("P0Y0M0W0D") { ok = false; }
  if !ok_parse("PT0H0M0S") { ok = false; }
  if !ok_parse("P0000D") { ok = false; }
  if !has_none_seven("P0D") { ok = false; }
  if !has_none_seven("P0Y0M0W0DT0H0M0S") { ok = false; }
  if field_of("PT0S", "seconds") != 0 { ok = false; }
  return assert(ok, "parse: zero durations are accepted");
}

fn t5() -> TestResult {
  var ok = field_of("P01D", "days") == 1;
  if field_of("P000000001D", "days") != 1 { ok = false; }
  if !ok_parse("P000000000Y") { ok = false; }
  if field_of("PT0001H", "hours") != 1 { ok = false; }
  if field_of("P9223372036854775807D", "days") != 9223372036854775807 { ok = false; }
  if !ok_parse("PT9223372036854775807S") { ok = false; }
  if !err_is("P9223372036854775808D", "duration: number too large: P9223372036854775808D") { ok = false; }
  if !err_is("PT99999999999999999999S", "duration: number too large: PT99999999999999999999S") { ok = false; }
  if !err_is("P12345678901234567890Y", "duration: number too large: P12345678901234567890Y") { ok = false; }
  return assert(ok, "parse: leading zeros accepted, magnitude bounded to Int");
}

fn t6() -> TestResult {
  var ok = field_of("PT0.5S", "seconds") == 0;
  if !streq(frac_of("PT0.5S"), "5") { ok = false; }
  if field_of("PT1.250S", "seconds") != 1 { ok = false; }
  if !streq(frac_of("PT1.250S"), "250") { ok = false; }
  if !streq(frac_of("PT0.05S"), "05") { ok = false; }
  if !streq(frac_of("PT1.123456789S"), "123456789") { ok = false; }
  if !streq(frac_of("PT0.000000001S"), "000000001") { ok = false; }
  if !streq(frac_of("P1D"), "") { ok = false; }
  if field_of("PT1.5S", "minutes") != 0 { ok = false; }
  return assert(ok, "parse: seconds fraction kept as validated text");
}

fn t7() -> TestResult {
  var ok = err_is("P1Y1Y", "duration: duplicate component: P1Y1Y");
  if !err_is("P1M1M", "duration: duplicate component: P1M1M") { ok = false; }
  if !err_is("P1W1W", "duration: duplicate component: P1W1W") { ok = false; }
  if !err_is("P1D1D", "duration: duplicate component: P1D1D") { ok = false; }
  if !err_is("PT1H1H", "duration: duplicate component: PT1H1H") { ok = false; }
  if !err_is("PT1M1M", "duration: duplicate component: PT1M1M") { ok = false; }
  if !err_is("PT1S1S", "duration: duplicate component: PT1S1S") { ok = false; }
  if !err_is("PT1.5S1.5S", "duration: duplicate component: PT1.5S1.5S") { ok = false; }
  return assert(ok, "errors: duplicate components are rejected");
}

fn t8() -> TestResult {
  var ok = err_is("P1D2Y", "duration: bad component order: P1D2Y");
  if !err_is("P1M2Y", "duration: bad component order: P1M2Y") { ok = false; }
  if !err_is("P1W2M", "duration: bad component order: P1W2M") { ok = false; }
  if !err_is("P1D2W", "duration: bad component order: P1D2W") { ok = false; }
  if !err_is("P1Y2W3M", "duration: bad component order: P1Y2W3M") { ok = false; }
  if !ok_parse("P1Y2M3W4D") { ok = false; }
  if !ok_parse("P1Y2W3D") { ok = false; }
  return assert(ok, "errors: date component order is enforced");
}

fn t9() -> TestResult {
  var ok = err_is("PT1S2H", "duration: bad component order: PT1S2H");
  if !err_is("PT1M2H", "duration: bad component order: PT1M2H") { ok = false; }
  if !err_is("PT1S2M", "duration: bad component order: PT1S2M") { ok = false; }
  if !err_is("P1H", "duration: bad component order: P1H") { ok = false; }
  if !err_is("P1S", "duration: bad component order: P1S") { ok = false; }
  if !err_is("PT1D", "duration: bad component order: PT1D") { ok = false; }
  if !err_is("PT1Y", "duration: bad component order: PT1Y") { ok = false; }
  if !err_is("PT1W", "duration: bad component order: PT1W") { ok = false; }
  if !ok_parse("PT2H1M1S") { ok = false; }
  if !err_is("P1T1H", "duration: bad number: P1T1H") { ok = false; }
  return assert(ok, "errors: time order and section placement");
}

fn t10() -> TestResult {
  var ok = err_is("", "duration: empty input");
  if !err_is("P", "duration: empty duration: P") { ok = false; }
  if !err_is("+P", "duration: empty duration: +P") { ok = false; }
  if !err_is("-P", "duration: empty duration: -P") { ok = false; }
  if !err_is("PT", "duration: T without components: PT") { ok = false; }
  if !err_is("P1DT", "duration: T without components: P1DT") { ok = false; }
  if !err_is("P1YT", "duration: T without components: P1YT") { ok = false; }
  if !err_is("P0DT", "duration: T without components: P0DT") { ok = false; }
  if !ok_parse("P1DT2H") { ok = false; }
  return assert(ok, "errors: empty input, bare P and T without components");
}

fn t11() -> TestResult {
  var ok = err_is("1D", "duration: missing P: 1D");
  if !err_is("-1D", "duration: missing P: -1D") { ok = false; }
  if !err_is("+D", "duration: missing P: +D") { ok = false; }
  if !err_is("p1d", "duration: missing P: p1d") { ok = false; }
  if !err_is("D1", "duration: missing P: D1") { ok = false; }
  if !err_is("T1H", "duration: missing P: T1H") { ok = false; }
  if !err_is(" 1D", "duration: missing P:  1D") { ok = false; }
  if !err_is("1P1D", "duration: missing P: 1P1D") { ok = false; }
  if !err_is("+", "duration: missing P: +") { ok = false; }
  if !err_is("-", "duration: missing P: -") { ok = false; }
  if !ok_parse("+P1D") { ok = false; }
  return assert(ok, "errors: P is required after the optional sign");
}

fn t12() -> TestResult {
  var ok = err_is("P1X", "duration: bad number: P1X");
  if !err_is("P1", "duration: bad number: P1") { ok = false; }
  if !err_is("P1YD", "duration: bad number: P1YD") { ok = false; }
  if !err_is("PD", "duration: bad number: PD") { ok = false; }
  if !err_is("PT1H2", "duration: bad number: PT1H2") { ok = false; }
  if !err_is("P1D2", "duration: bad number: P1D2") { ok = false; }
  if !err_is("PT1Q", "duration: bad number: PT1Q") { ok = false; }
  if !err_is("PT1H2M3", "duration: bad number: PT1H2M3") { ok = false; }
  return assert(ok, "errors: component numbers need a designator");
}

fn t13() -> TestResult {
  var ok = err_is("PT1.S", "duration: bad fraction: PT1.S");
  if !err_is("PT1.", "duration: bad fraction: PT1.") { ok = false; }
  if !err_is("PT1.1234567890S", "duration: bad fraction: PT1.1234567890S") { ok = false; }
  if !err_is("PT1.5H", "duration: bad fraction: PT1.5H") { ok = false; }
  if !err_is("P1.5D", "duration: bad fraction: P1.5D") { ok = false; }
  if !err_is("PT1.5", "duration: bad fraction: PT1.5") { ok = false; }
  if !err_is("PT1..5S", "duration: bad fraction: PT1..5S") { ok = false; }
  if !ok_parse("PT1.5S") { ok = false; }
  if !ok_parse("PT0.123456789S") { ok = false; }
  return assert(ok, "errors: fractions need 1..9 digits and an S designator");
}

fn t14() -> TestResult {
  var ok = err_is("P1D!", "duration: trailing tokens: P1D!");
  if !err_is("P1D 2H", "duration: trailing tokens: P1D 2H") { ok = false; }
  if !err_is("P1DX", "duration: trailing tokens: P1DX") { ok = false; }
  if !err_is("PT1HT2H", "duration: trailing tokens: PT1HT2H") { ok = false; }
  if !err_is("P1DZT", "duration: trailing tokens: P1DZT") { ok = false; }
  if !err_is("P1Y-1M", "duration: trailing tokens: P1Y-1M") { ok = false; }
  if !err_is("P1D T2H", "duration: trailing tokens: P1D T2H") { ok = false; }
  if !err_is("PT1H P", "duration: trailing tokens: PT1H P") { ok = false; }
  return assert(ok, "errors: trailing tokens are rejected");
}

fn t15() -> TestResult {
  var ok = has_all_seven("P1Y2M3W4DT5H6M7S");
  if !has_none_seven("P0D") { ok = false; }
  if !has_none_seven("PT0S") { ok = false; }
  if !has_seconds_of("PT1S") { ok = false; }
  if !has_seconds_of("PT0.5S") { ok = false; }
  if has_seconds_of("P1D") { ok = false; }
  if has_seconds_of("PT0S") { ok = false; }
  if !has_days_of("P1D") { ok = false; }
  if !has_days_of("P1DT1H") { ok = false; }
  if has_days_of("PT1H") { ok = false; }
  if !has_hours_of("PT1H") { ok = false; }
  if has_hours_of("P1D") { ok = false; }
  return assert(ok, "accessors: has-* flags track non-zero components");
}

fn t16() -> TestResult {
  var ok = field_of("P1Y2M3W4DT5H6M7S", "years") == 1;
  if field_of("P1Y2M3W4DT5H6M7S", "months") != 2 { ok = false; }
  if field_of("P1Y2M3W4DT5H6M7S", "weeks") != 3 { ok = false; }
  if field_of("P1Y2M3W4DT5H6M7S", "days") != 4 { ok = false; }
  if field_of("P1Y2M3W4DT5H6M7S", "hours") != 5 { ok = false; }
  if field_of("P1Y2M3W4DT5H6M7S", "minutes") != 6 { ok = false; }
  if field_of("P1Y2M3W4DT5H6M7S", "seconds") != 7 { ok = false; }
  if field_of("PT0.5S", "seconds") != 0 { ok = false; }
  if !value_err_is("P1D", "centuries", "duration: unknown component: centuries") { ok = false; }
  if !value_err_is("P1D", "Years", "duration: unknown component: Years") { ok = false; }
  if !value_err_is("P1D", "", "duration: unknown component: ") { ok = false; }
  return assert(ok, "accessors: value by component name");
}

fn t17() -> TestResult {
  var ok = streq(frac_of("P1D"), "");
  if !streq(frac_of("PT0.5S"), "5") { ok = false; }
  if !streq(frac_of("PT0.0500S"), "0500") { ok = false; }
  if !streq(frac_of("PT1.123456789S"), "123456789") { ok = false; }
  if streq(frac_of("PT0.5S"), "50") { ok = false; }
  return assert(ok, "accessors: fraction text is preserved verbatim");
}

fn t18() -> TestResult {
  var ok = fmt_is("P1D", "P1D");
  if !fmt_is("PT1H", "PT1H") { ok = false; }
  if !fmt_is("P1Y2M3W4DT5H6M7S", "P1Y2M3W4DT5H6M7S") { ok = false; }
  if !fmt_is("-P1Y", "-P1Y") { ok = false; }
  if !fmt_is("PT0.5S", "PT0.5S") { ok = false; }
  if !fmt_is("-PT0.50S", "-PT0.50S") { ok = false; }
  if !fmt_is("P0D", "P0D") { ok = false; }
  if !fmt_stable("P1D") { ok = false; }
  if !fmt_stable("-PT0.50S") { ok = false; }
  return assert(ok, "format: canonical durations round-trip unchanged");
}

fn t19() -> TestResult {
  var ok = fmt_is("P1Y0M0W0DT0H0M0S", "P1Y");
  if !fmt_is("PT0S", "P0D") { ok = false; }
  if !fmt_is("P0D", "P0D") { ok = false; }
  if !fmt_is("P01D", "P1D") { ok = false; }
  if !fmt_is("+P1D", "P1D") { ok = false; }
  if !fmt_is("P0Y1D", "P1D") { ok = false; }
  if !fmt_is("PT0H0M1S", "PT1S") { ok = false; }
  if !fmt_is("PT3H0M5S", "PT3H5S") { ok = false; }
  if !fmt_is("P1DT0S", "P1D") { ok = false; }
  if !fmt_is("P0DT0H", "P0D") { ok = false; }
  return assert(ok, "format: zero components are omitted, zero is P0D");
}

fn t20() -> TestResult {
  var ok = fmt_is("-P0D", "-P0D");
  if !fmt_is("-PT1H", "-PT1H") { ok = false; }
  if !fmt_is("PT0.50S", "PT0.50S") { ok = false; }
  if !fmt_is("-PT0.0500S", "-PT0.0500S") { ok = false; }
  let hand = Duration{ sign: -1; years: 0; months: 0; weeks: 0; days: 0; hours: 1; minutes: 0; seconds: 0; fraction: "" };
  if !streq(duration_format(&hand), "-PT1H") { ok = false; }
  let frac = Duration{ sign: 1; years: 0; months: 0; weeks: 0; days: 0; hours: 0; minutes: 0; seconds: 0; fraction: "25" };
  if !streq(duration_format(&frac), "PT0.25S") { ok = false; }
  let zero = Duration{ sign: 1; years: 0; months: 0; weeks: 0; days: 0; hours: 0; minutes: 0; seconds: 0; fraction: "" };
  if !streq(duration_format(&zero), "P0D") { ok = false; }
  return assert(ok, "format: sign, fraction and hand-built structs");
}

fn t21() -> TestResult {
  var ok = total_is("PT5H6M7S", 18367);
  if !total_is("PT0S", 0) { ok = false; }
  if !total_is("P0D", 0) { ok = false; }
  if !total_is("-PT1H", -3600) { ok = false; }
  if !total_is("+PT1M30S", 90) { ok = false; }
  if !total_is("PT59S", 59) { ok = false; }
  if !total_is("PT2M", 120) { ok = false; }
  if !total_is("PT24H", 86400) { ok = false; }
  if !total_is("P0DT1H", 3600) { ok = false; }
  return assert(ok, "total seconds: time-only durations convert");
}

fn t22() -> TestResult {
  var ok = total_err_is("P1D", "duration: has date components: P1D");
  if !total_err_is("P1Y", "duration: has date components: P1Y") { ok = false; }
  if !total_err_is("P1WT1H", "duration: has date components: P1WT1H") { ok = false; }
  if !total_err_is("PT0.5S", "duration: has fractional seconds: PT0.5S") { ok = false; }
  if !total_err_is("P1DT0.5S", "duration: has date components: P1DT0.5S") { ok = false; }
  if !total_is("PT2562047788015215H", 9223372036854774000) { ok = false; }
  if !total_is("PT2562047788015215H1807S", 9223372036854775807) { ok = false; }
  if !total_err_is("PT2562047788015215H1808S", "duration: total seconds overflow: PT2562047788015215H1808S") { ok = false; }
  if !total_err_is("PT2562047788015216H", "duration: total seconds overflow: PT2562047788015216H") { ok = false; }
  if !total_err_is("PT153722867280912931M", "duration: total seconds overflow: PT153722867280912931M") { ok = false; }
  if !total_err_is("PT2562047788015215H153722867280912930M", "duration: total seconds overflow: PT2562047788015215H153722867280912930M") { ok = false; }
  return assert(ok, "total seconds: date, fraction and overflow errors");
}

fn main() -> Int {
  io.println("=== xiom.duration conformance tests ===");
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
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.duration: all tests passed");
  } else {
    io.println("xiom.duration: tests failed");
  }
  return failed;
}
