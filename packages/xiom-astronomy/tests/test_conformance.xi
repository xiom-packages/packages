// XIOM -- xiom.astronomy conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.astronomy module against its documented
// integer algorithms (Fliegel-Van Flandern Julian day, J2000 day offsets,
// day-granularity synodic moon phase, tropical zodiac).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// These tests pin THIS package's documented algorithms, not an external
// ephemeris: where an anchor is uncertain (moon phase, exotic Julian days)
// the expected value is derived from the formulas in src/astronomy.xi and
// SPEC.md, and computed the same way (integer, floor semantics). Verified
// independent anchors: JD(1970-01-01) = 2440588, JD(2000-01-01) = 2451545,
// JD(2026-01-01) = 2461042 = 2440588 + 1767225600/86400.
//
// All Str equality goes through str_compare (BUG 17 discipline: `==` on Str
// values read from a Vec lowers to a pointer comparison); nothing here reads
// Str out of a Vec, but the suite keeps the uniform convention.

module astronomy_tests
use xiom.io; use xiom.test; use xiom.astronomy;
use xiom.string;
use xiom.string.compare;

const _JD_2000_01_01: Int = 2451545;
const _JD_1970_01_01: Int = 2440588;
const _JD_2026_01_01: Int = 2461042;
const _UNIX_2026_01_01: Int = 1767225600;
const _SECS_PER_DAY: Int = 86400;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Ok(JDN) equality for a date.
fn jd_is(y: Int, m: Int, d: Int, want: Int) -> Bool {
  let r = astro_julian_day(y, m, d);
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

// Err for a date.
fn jd_err(y: Int, m: Int, d: Int) -> Bool {
  let r = astro_julian_day(y, m, d);
  match r {
    Ok(_) => { return false; },
    Err(_) => { return true; },
  }
  return false;
}

// Exact Err message for a date.
fn jd_err_msg_is(y: Int, m: Int, d: Int, want: Str) -> Bool {
  let r = astro_julian_day(y, m, d);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// JDN, or -1 on an invalid date (a real JDN is positive here).
fn jd_of(y: Int, m: Int, d: Int) -> Int {
  let r = astro_julian_day(y, m, d);
  match r {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

// Ok(days-since-J2000) equality for a date.
fn d2000_is(y: Int, m: Int, d: Int, want: Int) -> Bool {
  let r = astro_days_since_j2000(y, m, d);
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

// Err for a date (days-since-J2000 channel).
fn d2000_err(y: Int, m: Int, d: Int) -> Bool {
  let r = astro_days_since_j2000(y, m, d);
  match r {
    Ok(_) => { return false; },
    Err(_) => { return true; },
  }
  return false;
}

// Phase in permille, or -1 on an invalid date (a phase is never negative).
fn phase_of(y: Int, m: Int, d: Int) -> Int {
  let r = astro_moon_phase_permille(y, m, d);
  match r {
    Ok(v) => { return v; },
    Err(_) => { return -1; },
  }
  return -1;
}

// Err for a date (moon-phase channel).
fn phase_err(y: Int, m: Int, d: Int) -> Bool {
  let r = astro_moon_phase_permille(y, m, d);
  match r {
    Ok(_) => { return false; },
    Err(_) => { return true; },
  }
  return false;
}

// Ok(sign) equality for a month/day.
fn zodiac_is(m: Int, d: Int, want: Str) -> Bool {
  let r = astro_zodiac_sign(m, d);
  match r {
    Ok(v) => { return streq(v, want); },
    Err(_) => { return false; },
  }
  return false;
}

// Err for a month/day (zodiac channel).
fn zodiac_err(m: Int, d: Int) -> Bool {
  let r = astro_zodiac_sign(m, d);
  match r {
    Ok(_) => { return false; },
    Err(_) => { return true; },
  }
  return false;
}

// Exact Err message for a month/day.
fn zodiac_err_msg_is(m: Int, d: Int, want: Str) -> Bool {
  let r = astro_zodiac_sign(m, d);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// Phase name equality.
fn name_is(p: Int, want: Str) -> Bool {
  return streq(astro_moon_phase_name(p), want);
}

fn t1() -> TestResult {
  var ok = astro_is_leap_year(2000);
  if !astro_is_leap_year(2024) { ok = false; }
  if astro_is_leap_year(1900) { ok = false; }
  if astro_is_leap_year(2100) { ok = false; }
  return assert(ok, "leap years: 2000 and 2024 yes; 1900 and 2100 no");
}

fn t2() -> TestResult {
  var ok = astro_is_leap_year(1600);
  if !astro_is_leap_year(2400) { ok = false; }
  if !astro_is_leap_year(1996) { ok = false; }
  if astro_is_leap_year(1700) { ok = false; }
  if astro_is_leap_year(2023) { ok = false; }
  if astro_is_leap_year(2025) { ok = false; }
  return assert(ok, "leap years: 1600/2400/1996 yes; 1700/2023/2025 no");
}

fn t3() -> TestResult {
  var ok = jd_is(2000, 1, 1, _JD_2000_01_01);
  if !jd_is(1970, 1, 1, _JD_1970_01_01) { ok = false; }
  if !jd_is(2026, 1, 1, _JD_2026_01_01) { ok = false; }
  return assert(ok, "JD anchors: 2000-01-01 = 2451545, 1970-01-01 = 2440588, 2026-01-01 = 2461042");
}

fn t4() -> TestResult {
  var ok = jd_is(1900, 2, 28, 2415079);
  if !jd_is(1900, 3, 1, 2415080) { ok = false; }
  if !jd_is(2000, 2, 28, 2451603) { ok = false; }
  if !jd_is(2000, 2, 29, 2451604) { ok = false; }
  if !jd_is(2000, 3, 1, 2451605) { ok = false; }
  if !jd_is(2100, 2, 28, 2488128) { ok = false; }
  if !jd_is(2100, 3, 1, 2488129) { ok = false; }
  return assert(ok, "JD respects century leap rules (1900 and 2100 skip Feb 29; 2000 has it)");
}

fn t5() -> TestResult {
  var ok = jd_is(2000, 1, 6, 2451550);
  if !jd_is(1999, 12, 31, 2451544) { ok = false; }
  if !jd_is(2000, 1, 2, 2451546) { ok = false; }
  if !jd_is(2026, 1, 2, 2461043) { ok = false; }
  return assert(ok, "JD epoch neighbors: 2000-01-06 = 2451550, 1999-12-31 = 2451544");
}

fn t6() -> TestResult {
  var ok = jd_err(2000, 0, 15);
  if !jd_err(2000, 13, 15) { ok = false; }
  if !jd_err(2000, 1, 0) { ok = false; }
  if !jd_err(2000, 1, 32) { ok = false; }
  if !jd_err(2001, 2, 30) { ok = false; }
  if !jd_err(1900, 2, 29) { ok = false; }
  if !jd_err(2100, 2, 29) { ok = false; }
  if !jd_err(2000, 4, 31) { ok = false; }
  if jd_err(2000, 2, 29) { ok = false; }
  if jd_err(2024, 2, 29) { ok = false; }
  return assert(ok, "invalid dates are Err (month 0/13, day 0/32, Feb 30, non-leap Feb 29, Apr 31)");
}

fn t7() -> TestResult {
  var ok = d2000_is(2000, 1, 1, 0);
  if !d2000_is(1999, 12, 31, -1) { ok = false; }
  if !d2000_is(2000, 1, 6, 5) { ok = false; }
  if !d2000_is(2026, 1, 1, 9497) { ok = false; }
  if !d2000_is(1970, 1, 1, -10957) { ok = false; }
  return assert(ok, "days since J2000: 2000-01-01 = 0, 1999-12-31 = -1, 2026-01-01 = 9497");
}

fn t8() -> TestResult {
  var ok = d2000_err(2000, 13, 1);
  if !d2000_err(2000, 2, 30) { ok = false; }
  if !phase_err(2000, 0, 1) { ok = false; }
  if !phase_err(2000, 1, 32) { ok = false; }
  if d2000_err(2000, 1, 1) { ok = false; }
  return assert(ok, "invalid dates propagate Err through days_since_j2000 and moon phase");
}

fn t9() -> TestResult {
  let p = phase_of(2000, 1, 6);
  var near_new = p <= 50 || p >= 950;
  var ok = near_new;
  if p != 0 { ok = false; }
  let q = phase_of(2000, 2, 5);
  var q_new = q <= 50 || q >= 950;
  if !q_new { ok = false; }
  if q != 15 { ok = false; }
  if phase_of(2000, 2, 4) != 982 { ok = false; }
  return assert(ok, "2000-01-06 is new moon (0 permille); 2000-02-05 = 15 (new again)");
}

fn t10() -> TestResult {
  let p = phase_of(2000, 1, 21);
  var in_window = p >= 440 && p <= 560;
  var ok = in_window;
  if p != 507 { ok = false; }
  let prev = phase_of(2000, 1, 20);
  var prev_in = prev >= 440 && prev <= 560;
  if !prev_in { ok = false; }
  let next = phase_of(2000, 1, 22);
  var next_in = next >= 440 && next <= 560;
  if !next_in { ok = false; }
  return assert(ok, "2000-01-21 is full moon (507 permille, within 500 +- 60)");
}

fn t11() -> TestResult {
  let fq = phase_of(2000, 1, 14);
  var fq_ok = fq >= 188 && fq <= 312;
  var ok = fq_ok;
  if fq != 270 { ok = false; }
  let lq = phase_of(2000, 1, 29);
  var lq_ok = lq >= 688 && lq <= 812;
  if !lq_ok { ok = false; }
  if lq != 778 { ok = false; }
  return assert(ok, "first quarter 2000-01-14 = 270; last quarter 2000-01-29 = 778");
}

fn t12() -> TestResult {
  var ok = phase_of(1999, 12, 31) == 796;
  if phase_of(1900, 1, 1) != 11 { ok = false; }
  var dates_ok = true;
  if phase_of(2026, 9, 24) < 0 || phase_of(2026, 9, 24) > 999 { dates_ok = false; }
  if phase_of(2160, 1, 1) < 0 || phase_of(2160, 1, 1) > 999 { dates_ok = false; }
  if !dates_ok { ok = false; }
  return assert(ok, "phase is always in 0..999 and floor-wraps before the epoch (1999-12-31 = 796)");
}

fn t13() -> TestResult {
  var ok = name_is(0, "new");
  if !name_is(62, "new") { ok = false; }
  if !name_is(63, "waxing crescent") { ok = false; }
  if !name_is(187, "waxing crescent") { ok = false; }
  if !name_is(188, "first quarter") { ok = false; }
  if !name_is(312, "first quarter") { ok = false; }
  if !name_is(313, "waxing gibbous") { ok = false; }
  if !name_is(437, "waxing gibbous") { ok = false; }
  if !name_is(438, "full") { ok = false; }
  if !name_is(562, "full") { ok = false; }
  if !name_is(563, "waning gibbous") { ok = false; }
  if !name_is(687, "waning gibbous") { ok = false; }
  if !name_is(688, "last quarter") { ok = false; }
  if !name_is(812, "last quarter") { ok = false; }
  if !name_is(813, "waning crescent") { ok = false; }
  if !name_is(937, "waning crescent") { ok = false; }
  if !name_is(938, "new") { ok = false; }
  if !name_is(999, "new") { ok = false; }
  return assert(ok, "phase-name boundaries at 0, 62, 63, 187, 188, 312, 313, 437, 438, 562, 563, 687, 688, 812, 813, 937, 938, 999");
}

fn t14() -> TestResult {
  var ok = name_is(1000, "new");
  if !name_is(-1, "new") { ok = false; }
  if !name_is(-63, "waning crescent") { ok = false; }
  if !name_is(1562, "full") { ok = false; }
  if !name_is(1563, "waning gibbous") { ok = false; }
  return assert(ok, "phase names normalize any Int into 0..999 (1000 -> new, -63 -> waning crescent)");
}

fn t15() -> TestResult {
  var ok = zodiac_is(3, 20, "Pisces");
  if !zodiac_is(3, 21, "Aries") { ok = false; }
  if !zodiac_is(12, 21, "Sagittarius") { ok = false; }
  if !zodiac_is(12, 22, "Capricorn") { ok = false; }
  if !zodiac_is(1, 19, "Capricorn") { ok = false; }
  if !zodiac_is(1, 20, "Aquarius") { ok = false; }
  return assert(ok, "zodiac boundaries: Mar 20/21, Dec 21/22, Jan 19/20");
}

fn t16() -> TestResult {
  var ok = zodiac_is(1, 5, "Capricorn");
  if !zodiac_is(2, 5, "Aquarius") { ok = false; }
  if !zodiac_is(3, 10, "Pisces") { ok = false; }
  if !zodiac_is(4, 10, "Aries") { ok = false; }
  if !zodiac_is(5, 5, "Taurus") { ok = false; }
  if !zodiac_is(5, 25, "Gemini") { ok = false; }
  if !zodiac_is(7, 1, "Cancer") { ok = false; }
  if !zodiac_is(8, 1, "Leo") { ok = false; }
  if !zodiac_is(9, 1, "Virgo") { ok = false; }
  if !zodiac_is(10, 1, "Libra") { ok = false; }
  if !zodiac_is(11, 1, "Scorpio") { ok = false; }
  if !zodiac_is(11, 30, "Sagittarius") { ok = false; }
  return assert(ok, "all twelve tropical signs are reachable");
}

fn t17() -> TestResult {
  var ok = zodiac_is(2, 18, "Aquarius");
  if !zodiac_is(2, 19, "Pisces") { ok = false; }
  if !zodiac_is(4, 19, "Aries") { ok = false; }
  if !zodiac_is(4, 20, "Taurus") { ok = false; }
  if !zodiac_is(5, 20, "Taurus") { ok = false; }
  if !zodiac_is(5, 21, "Gemini") { ok = false; }
  if !zodiac_is(6, 20, "Gemini") { ok = false; }
  if !zodiac_is(6, 21, "Cancer") { ok = false; }
  if !zodiac_is(7, 22, "Cancer") { ok = false; }
  if !zodiac_is(7, 23, "Leo") { ok = false; }
  if !zodiac_is(8, 22, "Leo") { ok = false; }
  if !zodiac_is(8, 23, "Virgo") { ok = false; }
  if !zodiac_is(9, 22, "Virgo") { ok = false; }
  if !zodiac_is(9, 23, "Libra") { ok = false; }
  if !zodiac_is(10, 22, "Libra") { ok = false; }
  if !zodiac_is(10, 23, "Scorpio") { ok = false; }
  if !zodiac_is(11, 21, "Scorpio") { ok = false; }
  if !zodiac_is(11, 22, "Sagittarius") { ok = false; }
  return assert(ok, "every remaining sign boundary is pinned exactly");
}

fn t18() -> TestResult {
  var ok = zodiac_err(0, 15);
  if !zodiac_err(13, 1) { ok = false; }
  if !zodiac_err(1, 0) { ok = false; }
  if !zodiac_err(1, 32) { ok = false; }
  if !zodiac_err(2, 30) { ok = false; }
  if !zodiac_err(4, 31) { ok = false; }
  if !zodiac_err(6, 31) { ok = false; }
  if !zodiac_err(9, 31) { ok = false; }
  if !zodiac_err(11, 31) { ok = false; }
  if !zodiac_is(2, 29, "Pisces") { ok = false; }
  if !zodiac_is(4, 30, "Taurus") { ok = false; }
  return assert(ok, "zodiac rejects invalid month/day (0, 13, 0, 32, Feb 30, 30-day month day 31)");
}

fn t19() -> TestResult {
  var ok = jd_err_msg_is(2000, 13, 15, "astronomy: invalid date: 2000-13-15");
  if !zodiac_err_msg_is(2, 30, "astronomy: invalid date: 2-30") { ok = false; }
  let r = astro_julian_day(2000, 1, 1);
  var prefixed = false;
  match r {
    Ok(_) => { prefixed = false; },
    Err(_) => { prefixed = true; },
  }
  if prefixed { ok = false; }
  if !string.str_starts_with("astronomy: invalid date: 0-0", "astronomy: ") { ok = false; }
  return assert(ok, "every error carries the exact \"astronomy: invalid date: Y-M-D\" message");
}

fn t20() -> TestResult {
  let epoch_days = _JD_2026_01_01 - _JD_1970_01_01;
  var ok = epoch_days == 20454;
  if _UNIX_2026_01_01 / _SECS_PER_DAY != epoch_days { ok = false; }
  if _JD_2026_01_01 - _JD_2000_01_01 != 9497 { ok = false; }
  if _JD_2000_01_01 - _JD_1970_01_01 != 10957 { ok = false; }
  return assert(ok, "JD differences agree with Unix days (2026-01-01 = epoch + 20454 days)");
}

fn t21() -> TestResult {
  var ok = jd_of(2024, 3, 1) - jd_of(2024, 2, 1) == 29;
  if jd_of(1900, 3, 1) - jd_of(1900, 2, 1) != 28 { ok = false; }
  if jd_of(2000, 3, 1) - jd_of(2000, 2, 1) != 29 { ok = false; }
  if jd_of(2100, 3, 1) - jd_of(2100, 2, 1) != 28 { ok = false; }
  return assert(ok, "February has 29 days in 2000/2024 and 28 days in 1900/2100");
}

fn t22() -> TestResult {
  var ok = phase_of(2000, 1, 7) - phase_of(2000, 1, 6) == 33;
  if phase_of(2024, 2, 29) - phase_of(2024, 2, 28) != 34 { ok = false; }
  let wrap = phase_of(2000, 2, 5) - phase_of(2000, 2, 4);
  if wrap != -967 { ok = false; }
  if wrap + 1000 != 33 { ok = false; }
  return assert(ok, "phase advances 33/34 permille per day (1000 * 1000000 / 29530589) and wraps");
}

fn main() -> Int {
  io.println("=== xiom.astronomy conformance tests ===");
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
    io.println("xiom.astronomy: all tests passed");
  } else {
    io.println("xiom.astronomy: tests failed");
  }
  return failed;
}
