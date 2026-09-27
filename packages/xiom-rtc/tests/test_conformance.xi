// XIOM -- xiom.rtc conformance tests (18 checks)
// Port task: prove the pure-XIOM xiom.rtc codecs against the register tables
// pinned in SPEC.md: BCD pack/unpack, the leap-year rules and epoch-day
// conversions, the DS1307 7-register and PCF8563 9-register layouts
// (including control/status registers, 12/24-hour modes, the AM/PM bit, the
// century flag and the clock-halt bits), the register read orders and the
// full error catalog for malformed and impossible fields.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every pinned byte string below was derived by hand from the bit tables in
// SPEC.md. All synthetic register buffers are built in-test from hex strings;
// no file or device is touched (the library is codec-only).
//
// BUG 17 discipline: no Str value is compared with `==`; error messages go
// through xiom.string.compare.str_compare. All Vec element reads are bound to
// typed locals, and every flag comparison uses the Bool-safe helper bool_eq
// instead of `==` on Bool.

module rtc_tests
use xiom.io; use xiom.test;
use xiom.rtc;
use xiom.string.compare;
use xiom.convert;
use xiom.encoding.hex;

// --------------------------------------------------
//  Fixture helpers (independent of src/rtc.xi)
// --------------------------------------------------

// Bytes for a hex string; "" on malformed input (the test then fails on the
// byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = r.value;
  return v;
}

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bool_eq(a: Bool, b: Bool) -> Bool {
  if a {
    if b {
      return true;
    }
    return false;
  }
  if b {
    return false;
  }
  return true;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = (a[i] as Int) & 0xFF;
    let y: Int = (b[i] as Int) & 0xFF;
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn int_is(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Int = r.value;
  return v == want;
}

fn bool_is(r: Result[Bool, Str], want: Bool) -> Bool {
  if !r.is_ok {
    return false;
  }
  let v: Bool = r.value;
  return bool_eq(v, want);
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn err_bool_is(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn err_time_is(r: Result[RtcTime, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn err_pcf_is(r: Result[Pcf8563Time, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// Typed read of one Vec[Int] element.
fn int_at(v: &Vec[Int], i: Int) -> Int {
  let x: Int = v[i];
  return x;
}

// RtcTime fixture builder (11 fields on purpose: every call site spells out
// exactly what it exercises).
fn mk_t(year: Int, month: Int, day: Int, weekday: Int, hours: Int, minutes: Int, seconds: Int, hour12: Bool, pm: Bool, century: Int, halted: Bool) -> RtcTime {
  return RtcTime{
    year: year;
    month: month;
    day: day;
    weekday: weekday;
    hours: hours;
    minutes: minutes;
    seconds: seconds;
    hour12: hour12;
    pm: pm;
    century: century;
    halted: halted;
  };
}

fn mk_pcf(c1: Int, c2: Int, vl: Bool, t: RtcTime) -> Pcf8563Time {
  return Pcf8563Time{ control1: c1; control2: c2; vl: vl; time: t; };
}

fn time_eq(a: RtcTime, b: RtcTime) -> Bool {
  if a.year != b.year { return false; }
  if a.month != b.month { return false; }
  if a.day != b.day { return false; }
  if a.weekday != b.weekday { return false; }
  if a.hours != b.hours { return false; }
  if a.minutes != b.minutes { return false; }
  if a.seconds != b.seconds { return false; }
  if !bool_eq(a.hour12, b.hour12) { return false; }
  if !bool_eq(a.pm, b.pm) { return false; }
  if a.century != b.century { return false; }
  if !bool_eq(a.halted, b.halted) { return false; }
  return true;
}

// --------------------------------------------------
//  BCD and civil-date tests
// --------------------------------------------------

fn t1() -> TestResult {
  var ok = int_is(rtc_bcd_encode(0), 0);
  if !int_is(rtc_bcd_encode(9), 9) { ok = false; }
  if !int_is(rtc_bcd_encode(10), 16) { ok = false; }
  if !int_is(rtc_bcd_encode(23), 35) { ok = false; }
  if !int_is(rtc_bcd_encode(59), 89) { ok = false; }
  if !int_is(rtc_bcd_encode(99), 153) { ok = false; }
  if !int_is(rtc_bcd_decode(0), 0) { ok = false; }
  if !int_is(rtc_bcd_decode(35), 23) { ok = false; }
  if !int_is(rtc_bcd_decode(89), 59) { ok = false; }
  if !int_is(rtc_bcd_decode(153), 99) { ok = false; }
  if !err_int_is(rtc_bcd_encode(-1), "rtc.bcd: value -1 out of range 0..99") { ok = false; }
  if !err_int_is(rtc_bcd_encode(100), "rtc.bcd: value 100 out of range 0..99") { ok = false; }
  if !err_int_is(rtc_bcd_decode(256), "rtc.bcd: byte 256 out of range 0..255") { ok = false; }
  if !err_int_is(rtc_bcd_decode(-1), "rtc.bcd: byte -1 out of range 0..255") { ok = false; }
  // 0x1A, 0xA0 and 0xFF have at least one non-decimal nibble.
  if !err_int_is(rtc_bcd_decode(26), "rtc.bcd: byte 26 is not valid BCD") { ok = false; }
  if !err_int_is(rtc_bcd_decode(160), "rtc.bcd: byte 160 is not valid BCD") { ok = false; }
  if !err_int_is(rtc_bcd_decode(255), "rtc.bcd: byte 255 is not valid BCD") { ok = false; }
  if rtc_bcd_is_valid(26) { ok = false; }
  if rtc_bcd_is_valid(160) { ok = false; }
  if rtc_bcd_is_valid(-1) { ok = false; }
  if rtc_bcd_is_valid(256) { ok = false; }
  if !rtc_bcd_is_valid(153) { ok = false; }
  return assert(ok, "bcd: pack/unpack table and nibble validation");
}

fn t2() -> TestResult {
  var ok = rtc_is_leap(2000);
  if !rtc_is_leap(2024) { ok = false; }
  if rtc_is_leap(1900) { ok = false; }
  if rtc_is_leap(2100) { ok = false; }
  if rtc_is_leap(2023) { ok = false; }
  if rtc_is_leap(2001) { ok = false; }
  if rtc_days_in_month(2024, 2) != 29 { ok = false; }
  if rtc_days_in_month(2001, 2) != 28 { ok = false; }
  if rtc_days_in_month(2024, 4) != 30 { ok = false; }
  if rtc_days_in_month(2024, 6) != 30 { ok = false; }
  if rtc_days_in_month(2024, 9) != 30 { ok = false; }
  if rtc_days_in_month(2024, 11) != 30 { ok = false; }
  if rtc_days_in_month(2024, 1) != 31 { ok = false; }
  if rtc_days_in_month(2024, 12) != 31 { ok = false; }
  if rtc_days_in_month(2024, 13) != 0 { ok = false; }
  if rtc_days_in_month(2024, 0) != 0 { ok = false; }
  if rtc_days_in_month(2100, 2) != 28 { ok = false; }
  return assert(ok, "civil: leap-year rule (2000/1900/2100/2024) and month lengths");
}

fn t3() -> TestResult {
  var ok = rtc_is_valid_date(2000, 2, 29);
  if !rtc_is_valid_date(2024, 2, 29) { ok = false; }
  if rtc_is_valid_date(2001, 2, 29) { ok = false; }
  if rtc_is_valid_date(2001, 2, 30) { ok = false; }
  if rtc_is_valid_date(2001, 4, 31) { ok = false; }
  if rtc_is_valid_date(2001, 13, 1) { ok = false; }
  if rtc_is_valid_date(2001, 0, 1) { ok = false; }
  if rtc_is_valid_date(2001, 1, 0) { ok = false; }
  if rtc_is_valid_date(2001, 1, 32) { ok = false; }
  if rtc_is_valid_date(2100, 2, 29) { ok = false; }
  if !rtc_is_valid_time(0, 0, 0) { ok = false; }
  if !rtc_is_valid_time(23, 59, 59) { ok = false; }
  if rtc_is_valid_time(24, 0, 0) { ok = false; }
  if rtc_is_valid_time(-1, 0, 0) { ok = false; }
  if rtc_is_valid_time(0, 60, 0) { ok = false; }
  if rtc_is_valid_time(0, 0, 60) { ok = false; }
  return assert(ok, "civil: impossible fields rejected (Feb 30, month 13, hour 24, minute 60)");
}

fn t4() -> TestResult {
  var ok = int_is(rtc_days_from_civil(1970, 1, 1), 0);
  if !int_is(rtc_days_from_civil(1970, 1, 2), 1) { ok = false; }
  if !int_is(rtc_days_from_civil(1969, 12, 31), -1) { ok = false; }
  if !int_is(rtc_days_from_civil(2000, 2, 29), 11016) { ok = false; }
  if !int_is(rtc_days_from_civil(2000, 3, 1), 11017) { ok = false; }
  if !int_is(rtc_days_from_civil(2024, 2, 29), 19782) { ok = false; }
  if !int_is(rtc_days_from_civil(2026, 9, 27), 20723) { ok = false; }
  // 2100 is not a leap year: 2100-01-01 = 47482, so 2100-03-01 = 47541.
  if !int_is(rtc_days_from_civil(2100, 1, 1), 47482) { ok = false; }
  if !int_is(rtc_days_from_civil(2100, 3, 1), 47541) { ok = false; }
  if !err_int_is(rtc_days_from_civil(2000, 13, 1), "rtc: month 13 out of range 1..12") { ok = false; }
  if !err_int_is(rtc_days_from_civil(2000, 0, 1), "rtc: month 0 out of range 1..12") { ok = false; }
  if !err_int_is(rtc_days_from_civil(2001, 2, 30), "rtc: impossible date 2001-02-30") { ok = false; }
  if !err_int_is(rtc_days_from_civil(2001, 2, 29), "rtc: impossible date 2001-02-29") { ok = false; }
  if !err_int_is(rtc_days_from_civil(2000, 1, 0), "rtc: impossible date 2000-01-00") { ok = false; }
  if !err_int_is(rtc_days_from_civil(2000, 4, 31), "rtc: impossible date 2000-04-31") { ok = false; }
  if !err_int_is(rtc_days_from_civil(2100, 2, 29), "rtc: impossible date 2100-02-29") { ok = false; }
  return assert(ok, "civil: days since epoch pinned values and date errors");
}

fn t5() -> TestResult {
  var ok = true;
  let d0 = rtc_civil_from_days(0);
  if d0.year != 1970 { ok = false; }
  if d0.month != 1 { ok = false; }
  if d0.day != 1 { ok = false; }
  let dm1 = rtc_civil_from_days(-1);
  if dm1.year != 1969 { ok = false; }
  if dm1.month != 12 { ok = false; }
  if dm1.day != 31 { ok = false; }
  let d1 = rtc_civil_from_days(11017);
  if d1.year != 2000 { ok = false; }
  if d1.month != 3 { ok = false; }
  if d1.day != 1 { ok = false; }
  let d2 = rtc_civil_from_days(19782);
  if d2.year != 2024 { ok = false; }
  if d2.month != 2 { ok = false; }
  if d2.day != 29 { ok = false; }
  let d3 = rtc_civil_from_days(20723);
  if d3.year != 2026 { ok = false; }
  if d3.month != 9 { ok = false; }
  if d3.day != 27 { ok = false; }
  let d4 = rtc_civil_from_days(47541);
  if d4.year != 2100 { ok = false; }
  if d4.month != 3 { ok = false; }
  if d4.day != 1 { ok = false; }
  // Round trip across the epoch and a century boundary.
  var i = -50;
  while i <= 1500 {
    let c = rtc_civil_from_days(i);
    let r = rtc_days_from_civil(c.year, c.month, c.day);
    if !r.is_ok {
      ok = false;
    } else {
      let dd: Int = r.value;
      if dd != i { ok = false; }
    }
    i = i + 37;
  }
  return assert(ok, "civil: civil_from_days pinned values and epoch round trips");
}

fn t6() -> TestResult {
  var ok = rtc_weekday_from_days(0) == 4;
  if rtc_weekday_from_days(1) != 5 { ok = false; }
  if rtc_weekday_from_days(-1) != 3 { ok = false; }
  if rtc_weekday_from_days(19782) != 4 { ok = false; }
  if rtc_weekday_from_days(20723) != 7 { ok = false; }
  if rtc_weekday_from_days(47482) != 5 { ok = false; }
  if rtc_weekday_from_days(47541) != 1 { ok = false; }
  return assert(ok, "civil: ISO weekday pinned values (1970-01-01 Thursday)");
}

fn t7() -> TestResult {
  var ok = int_is(rtc_twelve_hour_to_24(12, false), 0);
  if !int_is(rtc_twelve_hour_to_24(12, true), 12) { ok = false; }
  if !int_is(rtc_twelve_hour_to_24(1, false), 1) { ok = false; }
  if !int_is(rtc_twelve_hour_to_24(1, true), 13) { ok = false; }
  if !int_is(rtc_twelve_hour_to_24(11, true), 23) { ok = false; }
  if !err_int_is(rtc_twelve_hour_to_24(0, false), "rtc: 12-hour value 0 out of range 1..12") { ok = false; }
  if !err_int_is(rtc_twelve_hour_to_24(13, true), "rtc: 12-hour value 13 out of range 1..12") { ok = false; }
  if !int_is(rtc_24_to_twelve_hours(0), 12) { ok = false; }
  if !int_is(rtc_24_to_twelve_hours(11), 11) { ok = false; }
  if !int_is(rtc_24_to_twelve_hours(12), 12) { ok = false; }
  if !int_is(rtc_24_to_twelve_hours(13), 1) { ok = false; }
  if !int_is(rtc_24_to_twelve_hours(23), 11) { ok = false; }
  if !err_int_is(rtc_24_to_twelve_hours(24), "rtc: hours 24 out of range 0..23") { ok = false; }
  if !bool_is(rtc_24_to_twelve_pm(0), false) { ok = false; }
  if !bool_is(rtc_24_to_twelve_pm(11), false) { ok = false; }
  if !bool_is(rtc_24_to_twelve_pm(12), true) { ok = false; }
  if !bool_is(rtc_24_to_twelve_pm(23), true) { ok = false; }
  if !err_bool_is(rtc_24_to_twelve_pm(-1), "rtc: hours -1 out of range 0..23") { ok = false; }
  return assert(ok, "mode: 12/24-hour conversion with the AM/PM boundary");
}

// --------------------------------------------------
//  DS1307 tests
// --------------------------------------------------

fn t8() -> TestResult {
  // 2099-12-31 23:59:45, weekday 5; register order seconds..year.
  let r = rtc_ds1307_decode(&hb("45592305311299"));
  if !r.is_ok {
    return assert(false, "ds1307 pinned frame must decode");
  }
  let t: RtcTime = r.value;
  var ok = t.seconds == 45;
  if t.minutes != 59 { ok = false; }
  if t.hours != 23 { ok = false; }
  if t.weekday != 5 { ok = false; }
  if t.day != 31 { ok = false; }
  if t.month != 12 { ok = false; }
  if t.year != 99 { ok = false; }
  if t.century != 0 { ok = false; }
  if !bool_eq(t.hour12, false) { ok = false; }
  if !bool_eq(t.pm, false) { ok = false; }
  if !bool_eq(t.halted, false) { ok = false; }
  if rtc_full_year(&t) != 2099 { ok = false; }
  // Bytes beyond the first 7 are ignored.
  let r2 = rtc_ds1307_decode(&hb("45592305311299AA"));
  if !r2.is_ok { ok = false; }
  return assert(ok, "ds1307: decode 7-register 24-hour frame, extra bytes ignored");
}

fn t9() -> TestResult {
  // 2000-02-18 12:48:00 with CH set: bit 7 of 0x80 is halt, seconds decode 0.
  let fr = hb("80301203180200");
  let r = rtc_ds1307_decode(&fr);
  if !r.is_ok {
    return assert(false, "ds1307 halted frame must decode");
  }
  let t: RtcTime = r.value;
  var ok = bool_eq(t.halted, true);
  if t.seconds != 0 { ok = false; }
  if t.minutes != 30 { ok = false; }
  if t.hours != 12 { ok = false; }
  if t.year != 0 { ok = false; }
  if t.month != 2 { ok = false; }
  if t.day != 18 { ok = false; }
  if rtc_full_year(&t) != 2000 { ok = false; }
  if !bool_is(rtc_ds1307_is_halted(&fr), true) { ok = false; }
  if !bool_is(rtc_ds1307_is_halted(&hb("00301203180200")), false) { ok = false; }
  // Clear CH: only byte 0 changes.
  let clr = rtc_ds1307_set_halted(&fr, false);
  if !clr.is_ok { ok = false; } else {
    let cb: Vec[UInt8] = clr.value;
    if !bytes_equal(cb, hb("00301203180200")) { ok = false; }
  }
  // Set CH on a running frame.
  let setr = rtc_ds1307_set_halted(&hb("00301203180200"), true);
  if !setr.is_ok { ok = false; } else {
    let sb: Vec[UInt8] = setr.value;
    if !bytes_equal(sb, fr) { ok = false; }
  }
  // Extra bytes survive set_halted untouched.
  let ext = rtc_ds1307_set_halted(&hb("45592305311299AA"), true);
  if !ext.is_ok { ok = false; } else {
    let eb: Vec[UInt8] = ext.value;
    if !bytes_equal(eb, hb("C5592305311299AA")) { ok = false; }
  }
  if !err_bool_is(rtc_ds1307_is_halted(&hb("455923053112")), "rtc.ds1307: need 7 registers, have 6") { ok = false; }
  if !err_bytes_is(rtc_ds1307_set_halted(&hb("455923053112"), true), "rtc.ds1307: need 7 registers, have 6") { ok = false; }
  return assert(ok, "ds1307: CH halt semantics decode, is_halted, set_halted");
}

fn t10() -> TestResult {
  // 2024-06-15 11:30:00 PM in 12-hour mode: hour byte 0x71 = 0x40 mode +
  // 0x20 PM + BCD 0x11.
  let fr = hb("00307102150624");
  let r = rtc_ds1307_decode(&fr);
  if !r.is_ok {
    return assert(false, "ds1307 12-hour PM frame must decode");
  }
  let t: RtcTime = r.value;
  var ok = bool_eq(t.hour12, true);
  if !bool_eq(t.pm, true) { ok = false; }
  if t.hours != 11 { ok = false; }
  if !int_is(rtc_twelve_hour_to_24(t.hours, t.pm), 23) { ok = false; }
  let enc = rtc_ds1307_encode(&t);
  if !enc.is_ok { ok = false; } else {
    let eb: Vec[UInt8] = enc.value;
    if !bytes_equal(eb, fr) { ok = false; }
  }
  // 2001-01-01 12:00:00 AM: hour byte 0x52 = 0x40 mode + BCD 12, PM clear.
  let fr2 = hb("00005201010101");
  let r2 = rtc_ds1307_decode(&fr2);
  if !r2.is_ok { ok = false; } else {
    let t2: RtcTime = r2.value;
    if !bool_eq(t2.hour12, true) { ok = false; }
    if !bool_eq(t2.pm, false) { ok = false; }
    if t2.hours != 12 { ok = false; }
    if !int_is(rtc_twelve_hour_to_24(t2.hours, t2.pm), 0) { ok = false; }
    let e2 = rtc_ds1307_encode(&t2);
    if !e2.is_ok { ok = false; } else {
      let b2: Vec[UInt8] = e2.value;
      if !bytes_equal(b2, fr2) { ok = false; }
    }
  }
  return assert(ok, "ds1307: 12-hour AM/PM decode, 24-hour conversion, encode round trip");
}

fn t11() -> TestResult {
  // 2024-02-29 (leap day) 23:59:58, weekday 4, 24-hour, running.
  let t = mk_t(24, 2, 29, 4, 23, 59, 58, false, false, 0, false);
  let r = rtc_ds1307_encode(&t);
  if !r.is_ok {
    return assert(false, "ds1307 encode must build a frame");
  }
  let b: Vec[UInt8] = r.value;
  var ok = bytes_equal(b, hb("58592304290224"));
  let d = rtc_ds1307_decode(&b);
  if !d.is_ok { ok = false; } else {
    let t2: RtcTime = d.value;
    if !time_eq(t, t2) { ok = false; }
  }
  // Halted flips bit 7 of the seconds byte: 0xD8.
  let th = mk_t(24, 2, 29, 4, 23, 59, 58, false, false, 0, true);
  let rh = rtc_ds1307_encode(&th);
  if !rh.is_ok { ok = false; } else {
    let bh: Vec[UInt8] = rh.value;
    if !bytes_equal(bh, hb("D8592304290224")) { ok = false; }
  }
  // Determinism: repeated encodes agree byte for byte.
  let r3 = rtc_ds1307_encode(&t);
  if !r3.is_ok { ok = false; } else {
    let b3: Vec[UInt8] = r3.value;
    if !bytes_equal(b3, b) { ok = false; }
  }
  return assert(ok, "ds1307: encode pinned leap-day frame, halt bit, determinism");
}

fn t12() -> TestResult {
  var ok = true;
  if !err_time_is(rtc_ds1307_decode(&hb("455923053112")), "rtc.ds1307: need 7 registers, have 6") { ok = false; }
  if !err_time_is(rtc_ds1307_decode(&hb("7A592305311299")), "rtc.ds1307 seconds register 122 is not valid BCD") { ok = false; }
  if !err_time_is(rtc_ds1307_decode(&hb("00602305311299")), "rtc.ds1307 minutes value 60 out of range 0..59") { ok = false; }
  if !err_time_is(rtc_ds1307_decode(&hb("00002405311299")), "rtc.ds1307 hours value 24 out of range 0..23") { ok = false; }
  if !err_time_is(rtc_ds1307_decode(&hb("00008005311299")), "rtc.ds1307 hours register 128 has reserved bits set") { ok = false; }
  if !err_time_is(rtc_ds1307_decode(&hb("00000000311299")), "rtc.ds1307 weekday value 0 out of range 1..7") { ok = false; }
  if !err_time_is(rtc_ds1307_decode(&hb("00000008311299")), "rtc.ds1307 weekday register 8 has reserved bits set") { ok = false; }
  if !err_time_is(rtc_ds1307_decode(&hb("00000005001299")), "rtc.ds1307 date value 0 out of range 1..31") { ok = false; }
  if !err_time_is(rtc_ds1307_decode(&hb("00000005311399")), "rtc.ds1307 month value 13 out of range 1..12") { ok = false; }
  if !err_time_is(rtc_ds1307_decode(&hb("00000005312099")), "rtc.ds1307 month register 32 has reserved bits set") { ok = false; }
  if !err_time_is(rtc_ds1307_decode(&hb("000000053112A0")), "rtc.ds1307 year register 160 is not valid BCD") { ok = false; }
  // Impossible cross-field date: 2001-02-30 (full year 2000 + year 1).
  if !err_time_is(rtc_ds1307_decode(&hb("00000001300201")), "rtc.ds1307: impossible date 2001-02-30") { ok = false; }
  return assert(ok, "ds1307: decode error catalog (length, BCD, ranges, reserved bits, Feb 30)");
}

fn t13() -> TestResult {
  var ok = true;
  let e_year = mk_t(100, 1, 1, 1, 0, 0, 0, false, false, 0, false);
  if !err_bytes_is(rtc_ds1307_encode(&e_year), "rtc.ds1307: year 100 out of range 0..99") { ok = false; }
  let e_month = mk_t(24, 13, 1, 1, 0, 0, 0, false, false, 0, false);
  if !err_bytes_is(rtc_ds1307_encode(&e_month), "rtc.ds1307: month 13 out of range 1..12") { ok = false; }
  let e_feb = mk_t(1, 2, 30, 1, 0, 0, 0, false, false, 0, false);
  if !err_bytes_is(rtc_ds1307_encode(&e_feb), "rtc.ds1307: impossible date 2001-02-30") { ok = false; }
  let e_feb29 = mk_t(1, 2, 29, 1, 0, 0, 0, false, false, 0, false);
  if !err_bytes_is(rtc_ds1307_encode(&e_feb29), "rtc.ds1307: impossible date 2001-02-29") { ok = false; }
  let e_wd8 = mk_t(24, 1, 1, 8, 0, 0, 0, false, false, 0, false);
  if !err_bytes_is(rtc_ds1307_encode(&e_wd8), "rtc.ds1307: weekday 8 out of range 1..7") { ok = false; }
  let e_wd0 = mk_t(24, 1, 1, 0, 0, 0, 0, false, false, 0, false);
  if !err_bytes_is(rtc_ds1307_encode(&e_wd0), "rtc.ds1307: weekday 0 out of range 1..7") { ok = false; }
  let e_min = mk_t(24, 1, 1, 1, 0, 60, 0, false, false, 0, false);
  if !err_bytes_is(rtc_ds1307_encode(&e_min), "rtc.ds1307: minutes 60 out of range 0..59") { ok = false; }
  let e_sec = mk_t(24, 1, 1, 1, 0, 0, 60, false, false, 0, false);
  if !err_bytes_is(rtc_ds1307_encode(&e_sec), "rtc.ds1307: seconds 60 out of range 0..59") { ok = false; }
  let e_h24 = mk_t(24, 1, 1, 1, 24, 0, 0, false, false, 0, false);
  if !err_bytes_is(rtc_ds1307_encode(&e_h24), "rtc.ds1307: hours 24 out of range 0..23") { ok = false; }
  let e_h0 = mk_t(24, 1, 1, 1, 0, 0, 0, true, false, 0, false);
  if !err_bytes_is(rtc_ds1307_encode(&e_h0), "rtc.ds1307: 12-hour hours 0 out of range 1..12") { ok = false; }
  let e_h13 = mk_t(24, 1, 1, 1, 13, 0, 0, true, false, 0, false);
  if !err_bytes_is(rtc_ds1307_encode(&e_h13), "rtc.ds1307: 12-hour hours 13 out of range 1..12") { ok = false; }
  let e_pm = mk_t(24, 1, 1, 1, 12, 0, 0, false, true, 0, false);
  if !err_bytes_is(rtc_ds1307_encode(&e_pm), "rtc.ds1307: PM flag set in 24-hour mode") { ok = false; }
  // The DS1307 has no century register: the century field is ignored.
  let c0 = mk_t(24, 1, 1, 1, 0, 0, 0, false, false, 0, false);
  let c2 = mk_t(24, 1, 1, 1, 0, 0, 0, false, false, 2, false);
  let r0 = rtc_ds1307_encode(&c0);
  let r2 = rtc_ds1307_encode(&c2);
  if !r0.is_ok || !r2.is_ok {
    ok = false;
  } else {
    let b0: Vec[UInt8] = r0.value;
    let b2: Vec[UInt8] = r2.value;
    if !bytes_equal(b0, b2) { ok = false; }
  }
  return assert(ok, "ds1307: encode error catalog and ignored century field");
}

// --------------------------------------------------
//  PCF8563 tests
// --------------------------------------------------

fn t14() -> TestResult {
  // control 1 0x20 (STOP set), control 2 0x13, 2124-05-25 12:30:45,
  // weekday 6, century 1 in the month register (0x85).
  let fr = hb("201345301225068524");
  let r = rtc_pcf8563_decode(&fr);
  if !r.is_ok {
    return assert(false, "pcf8563 pinned frame must decode");
  }
  let s: Pcf8563Time = r.value;
  var ok = s.control1 == 32;
  if s.control2 != 19 { ok = false; }
  if !bool_eq(s.vl, false) { ok = false; }
  let t: RtcTime = s.time;
  if !bool_eq(t.halted, true) { ok = false; }
  if t.seconds != 45 { ok = false; }
  if t.minutes != 30 { ok = false; }
  if t.hours != 12 { ok = false; }
  if !bool_eq(t.hour12, false) { ok = false; }
  if t.day != 25 { ok = false; }
  if t.weekday != 6 { ok = false; }
  if t.month != 5 { ok = false; }
  if t.year != 24 { ok = false; }
  if t.century != 1 { ok = false; }
  if rtc_full_year(&t) != 2124 { ok = false; }
  // Encode round-trips the frame byte for byte, control registers included.
  let enc = rtc_pcf8563_encode(&s);
  if !enc.is_ok { ok = false; } else {
    let eb: Vec[UInt8] = enc.value;
    if !bytes_equal(eb, fr) { ok = false; }
  }
  return assert(ok, "pcf8563: decode 9-register frame, STOP bit, century flag, round trip");
}

fn t15() -> TestResult {
  // VL set (seconds 0x80 -> vl true, seconds 0): 2000-01-01 00:00:00.
  let fr = hb("000080000001000100");
  let r = rtc_pcf8563_decode(&fr);
  if !r.is_ok {
    return assert(false, "pcf8563 VL frame must decode");
  }
  let s: Pcf8563Time = r.value;
  var ok = bool_eq(s.vl, true);
  if s.control1 != 0 { ok = false; }
  if s.control2 != 0 { ok = false; }
  let t: RtcTime = s.time;
  if t.seconds != 0 { ok = false; }
  if t.minutes != 0 { ok = false; }
  if t.hours != 0 { ok = false; }
  if t.day != 1 { ok = false; }
  if t.weekday != 0 { ok = false; }
  if t.month != 1 { ok = false; }
  if t.year != 0 { ok = false; }
  if t.century != 0 { ok = false; }
  if !bool_eq(t.halted, false) { ok = false; }
  if rtc_full_year(&t) != 2000 { ok = false; }
  if !bool_is(rtc_pcf8563_is_voltage_low(&fr), true) { ok = false; }
  if !bool_is(rtc_pcf8563_is_voltage_low(&hb("000045000001000100")), false) { ok = false; }
  if !err_bool_is(rtc_pcf8563_is_voltage_low(&hb("0000800000010001")), "rtc.pcf8563: need 9 registers, have 8") { ok = false; }
  return assert(ok, "pcf8563: VL voltage-low flag and 24-hour midnight decode");
}

fn t16() -> TestResult {
  // 2099-12-31 11:59:59 PM, 12-hour mode, VL set, AF bit in control 2,
  // century 0, running (STOP clear): c1 0x20 -> 0x00, hour 0xCB.
  let t = mk_t(99, 12, 31, 4, 11, 59, 59, true, true, 0, false);
  let s = mk_pcf(32, 8, true, t);
  let r = rtc_pcf8563_encode(&s);
  if !r.is_ok {
    return assert(false, "pcf8563 encode must build a frame");
  }
  let b: Vec[UInt8] = r.value;
  var ok = bytes_equal(b, hb("0008D959D131041299"));
  let d = rtc_pcf8563_decode(&b);
  if !d.is_ok { ok = false; } else {
    let s2: Pcf8563Time = d.value;
    if !bool_eq(s2.vl, true) { ok = false; }
    if s2.control2 != 8 { ok = false; }
    let t2: RtcTime = s2.time;
    if !time_eq(t, t2) { ok = false; }
    let e2 = rtc_pcf8563_encode(&s2);
    if !e2.is_ok { ok = false; } else {
      let b2: Vec[UInt8] = e2.value;
      if !bytes_equal(b2, b) { ok = false; }
    }
  }
  // STOP is driven by time.halted: the same sample halted sets c1 bit 5.
  let th = mk_t(99, 12, 31, 4, 11, 59, 59, true, true, 0, true);
  let sh = mk_pcf(32, 8, true, th);
  let rh = rtc_pcf8563_encode(&sh);
  if !rh.is_ok { ok = false; } else {
    let bh: Vec[UInt8] = rh.value;
    if !bytes_equal(bh, hb("2008D959D131041299")) { ok = false; }
  }
  return assert(ok, "pcf8563: encode pinned 12-hour PM frame, VL/century bits, STOP drive");
}

fn t17() -> TestResult {
  var ok = true;
  if !err_pcf_is(rtc_pcf8563_decode(&hb("0000000000000000")), "rtc.pcf8563: need 9 registers, have 8") { ok = false; }
  if !err_pcf_is(rtc_pcf8563_decode(&hb("00E000000000000000")), "rtc.pcf8563 control 2 register 224 has reserved bits set") { ok = false; }
  if !err_pcf_is(rtc_pcf8563_decode(&hb("00007B000000000000")), "rtc.pcf8563 seconds register 123 is not valid BCD") { ok = false; }
  if !err_pcf_is(rtc_pcf8563_decode(&hb("000000004100000000")), "rtc.pcf8563 hours register 65 has reserved bits set") { ok = false; }
  if !err_pcf_is(rtc_pcf8563_decode(&hb("000000002400000000")), "rtc.pcf8563 hours value 24 out of range 0..23") { ok = false; }
  if !err_pcf_is(rtc_pcf8563_decode(&hb("000000008000000000")), "rtc.pcf8563 12-hour value 0 out of range 1..12") { ok = false; }
  if !err_pcf_is(rtc_pcf8563_decode(&hb("000000000000070000")), "rtc.pcf8563 weekday value 7 out of range 0..6") { ok = false; }
  if !err_pcf_is(rtc_pcf8563_decode(&hb("000000000000080000")), "rtc.pcf8563 weekday register 8 has reserved bits set") { ok = false; }
  if !err_pcf_is(rtc_pcf8563_decode(&hb("000000000001001300")), "rtc.pcf8563 month value 13 out of range 1..12") { ok = false; }
  if !err_pcf_is(rtc_pcf8563_decode(&hb("000000000001003900")), "rtc.pcf8563 month register 57 has reserved bits set") { ok = false; }
  if !err_pcf_is(rtc_pcf8563_decode(&hb("000000000000000100")), "rtc.pcf8563 date value 0 out of range 1..31") { ok = false; }
  if !err_pcf_is(rtc_pcf8563_decode(&hb("000000000030010201")), "rtc.pcf8563: impossible date 2001-02-30") { ok = false; }
  // 2100 is not a leap year; the century flag selects the 21xx full year.
  if !err_pcf_is(rtc_pcf8563_decode(&hb("000000000029008200")), "rtc.pcf8563: impossible date 2100-02-29") { ok = false; }
  // Encode error catalog.
  let good = mk_t(99, 12, 31, 4, 23, 59, 59, false, false, 0, false);
  let e_c1 = mk_pcf(256, 0, false, good);
  if !err_bytes_is(rtc_pcf8563_encode(&e_c1), "rtc.pcf8563: control 1 value 256 out of range 0..255") { ok = false; }
  let e_c2 = mk_pcf(0, 256, false, good);
  if !err_bytes_is(rtc_pcf8563_encode(&e_c2), "rtc.pcf8563: control 2 value 256 out of range 0..255") { ok = false; }
  let e_c2r = mk_pcf(0, 224, false, good);
  if !err_bytes_is(rtc_pcf8563_encode(&e_c2r), "rtc.pcf8563: control 2 register 224 has reserved bits set") { ok = false; }
  let e_cen = mk_t(99, 12, 31, 4, 23, 59, 59, false, false, 2, false);
  if !err_bytes_is(rtc_pcf8563_encode(&mk_pcf(0, 0, false, e_cen)), "rtc.pcf8563: century 2 out of range 0..1") { ok = false; }
  let e_mon = mk_t(99, 13, 1, 4, 23, 59, 59, false, false, 0, false);
  if !err_bytes_is(rtc_pcf8563_encode(&mk_pcf(0, 0, false, e_mon)), "rtc.pcf8563: month 13 out of range 1..12") { ok = false; }
  let e_wd = mk_t(99, 12, 1, 7, 23, 59, 59, false, false, 0, false);
  if !err_bytes_is(rtc_pcf8563_encode(&mk_pcf(0, 0, false, e_wd)), "rtc.pcf8563: weekday 7 out of range 0..6") { ok = false; }
  let e_h0 = mk_t(99, 12, 1, 4, 0, 59, 59, true, false, 0, false);
  if !err_bytes_is(rtc_pcf8563_encode(&mk_pcf(0, 0, false, e_h0)), "rtc.pcf8563: 12-hour hours 0 out of range 1..12") { ok = false; }
  let e_pm = mk_t(99, 12, 1, 4, 12, 59, 59, false, true, 0, false);
  if !err_bytes_is(rtc_pcf8563_encode(&mk_pcf(0, 0, false, e_pm)), "rtc.pcf8563: PM flag set in 24-hour mode") { ok = false; }
  let e_2100 = mk_t(0, 2, 29, 4, 23, 59, 59, false, false, 1, false);
  if !err_bytes_is(rtc_pcf8563_encode(&mk_pcf(0, 0, false, e_2100)), "rtc.pcf8563: impossible date 2100-02-29") { ok = false; }
  return assert(ok, "pcf8563: decode/encode error catalog (reserved bits, ranges, century, Feb 29 2100)");
}

// --------------------------------------------------
//  Read orders and integration
// --------------------------------------------------

fn t18() -> TestResult {
  var ok = true;
  // DS1307 order visits every register 0..6 exactly once, seconds last.
  let dord = rtc_ds1307_read_order();
  if dord.len() != 7 { ok = false; }
  if int_at(&dord, 0) != 1 { ok = false; }
  if int_at(&dord, 6) != 0 { ok = false; }
  var i = 0;
  while i < dord.len() {
    let x: Int = int_at(&dord, i);
    if x < 0 || x > 6 { ok = false; }
    var j = i + 1;
    while j < dord.len() {
      let y: Int = int_at(&dord, j);
      if x == y { ok = false; }
      j = j + 1;
    }
    i = i + 1;
  }
  // PCF8563 order: control pair first, seconds (2) last.
  let pord = rtc_pcf8563_read_order();
  if pord.len() != 9 { ok = false; }
  if int_at(&pord, 0) != 0 { ok = false; }
  if int_at(&pord, 1) != 1 { ok = false; }
  if int_at(&pord, 8) != 2 { ok = false; }
  i = 0;
  while i < pord.len() {
    let x2: Int = int_at(&pord, i);
    if x2 < 0 || x2 > 8 { ok = false; }
    var j2 = i + 1;
    while j2 < pord.len() {
      let y2: Int = int_at(&pord, j2);
      if x2 == y2 { ok = false; }
      j2 = j2 + 1;
    }
    i = i + 1;
  }
  // Full-year helper for both century values.
  let t0 = mk_t(24, 1, 1, 1, 0, 0, 0, false, false, 0, false);
  let t1 = mk_t(24, 1, 1, 1, 0, 0, 0, false, false, 1, false);
  if rtc_full_year(&t0) != 2024 { ok = false; }
  if rtc_full_year(&t1) != 2124 { ok = false; }
  // Decoded register dates agree with the epoch-day math: 2099-12-31 is
  // 47481 days after the epoch (2100-01-01 = 47482) and a Thursday.
  let dd = rtc_days_from_civil(2099, 12, 31);
  if !int_is(dd, 47481) { ok = false; }
  let c = rtc_civil_from_days(47481);
  if c.year != 2099 { ok = false; }
  if c.month != 12 { ok = false; }
  if c.day != 31 { ok = false; }
  if rtc_weekday_from_days(47481) != 4 { ok = false; }
  return assert(ok, "orders: register read orders, century full year, epoch integration");
}

fn main() -> Int {
  io.println("=== xiom.rtc conformance tests ===");
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
    io.println("xiom.rtc: all tests passed");
  } else {
    io.println("xiom.rtc: tests failed");
  }
  return failed;
}
