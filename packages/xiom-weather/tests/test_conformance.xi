// XIOM -- xiom.weather conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.weather METAR decoder against its
// documented token grammar, wind/visibility/altimeter conversions, cloud
// ceiling rule, flight-category thresholds and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below (stations, categories, summaries, error messages, struct Str fields)
// is routed through streq instead of `==`.

module weather_tests
use xiom.io; use xiom.test; use xiom.weather;
use xiom.string.compare; use xiom.convert;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Canonical sample: EGLL 121150Z 24012KT 9999 SCT020 18/12 Q1013.
fn egll() -> Str {
  return "EGLL 121150Z 24012KT 9999 SCT020 18/12 Q1013";
}

// 4-digit zero-padded visibility token for synthesized observations.
fn pad4(v: Int) -> Str {
  if v < 10 { return "000" + convert.int_to_string(v); }
  if v < 100 { return "00" + convert.int_to_string(v); }
  if v < 1000 { return "0" + convert.int_to_string(v); }
  return convert.int_to_string(v);
}

// 3-digit zero-padded cloud-layer height (hundreds of feet).
fn pad3(v: Int) -> Str {
  if v < 10 { return "00" + convert.int_to_string(v); }
  if v < 100 { return "0" + convert.int_to_string(v); }
  return convert.int_to_string(v);
}

// Synthesized observation with a given visibility in meters.
fn vis_raw(meters: Int) -> Str {
  return "KAAA 010000Z 00000KT " + pad4(meters) + " 10/05 Q1013";
}

// Synthesized observation with a single BKN layer, hundreds of feet.
fn ceil_raw(hundreds: Int) -> Str {
  return "KAAA 010000Z 00000KT 9999 BKN" + pad3(hundreds) + " 10/05 Q1013";
}

// --- single-aspect probes ---------------------------------------------------
// Each probe parses `raw` and checks one value group; a failed parse makes
// the probe false.

fn parse_is_ok(raw: Str) -> Bool {
  let r = metar_parse(raw);
  return r.is_ok;
}

fn parse_err_is(raw: Str, want: Str) -> Bool {
  let r = metar_parse(raw);
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn station_is(raw: Str, want: Str) -> Bool {
  let r = metar_parse(raw);
  if !r.is_ok { return false; }
  let m = r.value;
  return streq(m.station, want);
}

fn time_is(raw: Str, want_day: Int, want_hour: Int, want_minute: Int) -> Bool {
  let r = metar_parse(raw);
  if !r.is_ok { return false; }
  let m = r.value;
  return m.day == want_day && m.hour == want_hour && m.minute == want_minute;
}

fn wind_is(raw: Str, dir: Int, speed: Int, gust: Int) -> Bool {
  let r = metar_parse(raw);
  if !r.is_ok { return false; }
  let m = r.value;
  return m.wind_dir_deg == dir && m.wind_speed_kt == speed && m.wind_gust_kt == gust;
}

fn visibility_is(raw: Str, want: Int) -> Bool {
  let r = metar_parse(raw);
  if !r.is_ok { return false; }
  let m = r.value;
  return m.visibility_m == want;
}

fn ceiling_is(raw: Str, want: Int) -> Bool {
  let r = metar_parse(raw);
  if !r.is_ok { return false; }
  let m = r.value;
  return m.ceiling_ft == want;
}

fn altimeter_is(raw: Str, want: Int) -> Bool {
  let r = metar_parse(raw);
  if !r.is_ok { return false; }
  let m = r.value;
  return m.altimeter_hpa == want;
}

fn temperature_is(raw: Str, want_temp: Int, want_dew: Int) -> Bool {
  let r = metar_parse(raw);
  if !r.is_ok { return false; }
  let m = r.value;
  return m.temp_c == want_temp && m.dewpoint_c == want_dew;
}

fn category_is(raw: Str, want: Str) -> Bool {
  let r = metar_parse(raw);
  if !r.is_ok { return false; }
  let m = r.value;
  return streq(metar_flight_category(&m), want);
}

fn summary_is(raw: Str, want: Str) -> Bool {
  let r = metar_parse(raw);
  if !r.is_ok { return false; }
  let m = r.value;
  return streq(metar_summary(&m), want);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn t1() -> TestResult {
  let r = metar_parse(egll());
  var ok = r.is_ok;
  if ok {
    let m = r.value;
    if !streq(m.station, "EGLL") { ok = false; }
    if m.day != 12 { ok = false; }
    if m.hour != 11 { ok = false; }
    if m.minute != 50 { ok = false; }
    if m.wind_dir_deg != 240 { ok = false; }
    if m.wind_speed_kt != 12 { ok = false; }
    if m.wind_gust_kt != -1 { ok = false; }
    if m.visibility_m != 9999 { ok = false; }
    if m.temp_c != 18 { ok = false; }
    if m.dewpoint_c != 12 { ok = false; }
    if m.altimeter_hpa != 1013 { ok = false; }
    if m.ceiling_ft != -1 { ok = false; }
    if metar_wind_kt(&m) != 12 { ok = false; }
    if metar_temperature_c(&m) != 18 { ok = false; }
    if !streq(metar_flight_category(&m), "VFR") { ok = false; }
    if !streq(metar_summary(&m), "EGLL 240/12kt vis=9999m 18/12 Q1013 VFR") { ok = false; }
  }
  return assert(ok, "EGLL sample fills every field and pins the summary");
}

fn t2() -> TestResult {
  let raw = "CYYZ 121200Z 00000KT 15SM M05/M10 A2992";
  var ok = temperature_is(raw, -5, -10);
  if !visibility_is(raw, 24135) { ok = false; }
  if !altimeter_is(raw, 1013) { ok = false; }
  if !wind_is(raw, 0, 0, -1) { ok = false; }
  if !summary_is(raw, "CYYZ 000/0kt vis=24135m -5/-10 Q1013 VFR") { ok = false; }
  return assert(ok, "negative temps, 15SM and A2992 -> 1013 hPa");
}

fn t3() -> TestResult {
  let raw = "EGLL 121150Z 24012G25KT 9999 SCT020 18/12 Q1013";
  var ok = wind_is(raw, 240, 12, 25);
  let r = metar_parse(raw);
  if r.is_ok {
    let m = r.value;
    if metar_wind_kt(&m) != 12 { ok = false; }
  } else {
    ok = false;
  }
  return assert(ok, "gust token records speed and gust; wind_kt is sustained");
}

fn t4() -> TestResult {
  let raw = "EGLL 121150Z VRB03KT 9999 SCT020 18/12 Q1013";
  var ok = wind_is(raw, -1, 3, -1);
  if !summary_is(raw, "EGLL VRB/3kt vis=9999m 18/12 Q1013 VFR") { ok = false; }
  return assert(ok, "VRB wind has direction -1 and renders as VRB");
}

fn t5() -> TestResult {
  let raw = "EGLL 121150Z 24012KT CAVOK 18/12 Q1013";
  var ok = visibility_is(raw, 10000);
  if !ceiling_is(raw, -1) { ok = false; }
  if !category_is(raw, "VFR") { ok = false; }
  if !summary_is(raw, "EGLL 240/12kt vis=10000m 18/12 Q1013 VFR") { ok = false; }
  return assert(ok, "CAVOK is 10000 m visibility and an open ceiling");
}

fn t6() -> TestResult {
  var ok = visibility_is("KJFK 121151Z 09008KT 10SM FEW020 24/18 A3005", 16090);
  if !visibility_is("KAAA 010000Z 00000KT 1SM 10/05 Q1013", 1609) { ok = false; }
  if !visibility_is("KAAA 010000Z 00000KT 0SM 10/05 Q1013", 0) { ok = false; }
  if !altimeter_is("KJFK 121151Z 09008KT 10SM FEW020 24/18 A3005", 1017) { ok = false; }
  return assert(ok, "statute-mile visibility converts at 1609 m/SM");
}

fn t7() -> TestResult {
  var ok = altimeter_is("KAAA 010000Z 00000KT 10SM 10/05 Q0998", 998);
  if !altimeter_is("KAAA 010000Z 00000KT 10SM 10/05 A2992", 1013) { ok = false; }
  if !altimeter_is("KAAA 010000Z 00000KT 10SM 10/05 Q1013", 1013) { ok = false; }
  if !altimeter_is("KAAA 010000Z 00000KT 10SM 10/05 A3005", 1017) { ok = false; }
  if !altimeter_is("KAAA 010000Z 00000KT 10SM 10/05 2992", -1) { ok = false; }
  return assert(ok, "Q is hPa as-is; A is hundredths of inHg truncated to hPa");
}

fn t8() -> TestResult {
  var ok = ceiling_is("EGLL 121150Z 24012KT 9999 BKN005 OVC012 18/12 Q1013", 500);
  if !ceiling_is("EGLL 121150Z 24012KT 9999 OVC012 BKN005 18/12 Q1013", 500) { ok = false; }
  if !ceiling_is("EGLL 121150Z 24012KT 9999 SCT003 FEW002 BKN020 18/12 Q1013", 2000) { ok = false; }
  if !ceiling_is("EGLL 121150Z 24012KT 9999 FEW003 SCT008 18/12 Q1013", -1) { ok = false; }
  if !ceiling_is("EGLL 121150Z 24012KT 9999 BKN000 18/12 Q1013", 0) { ok = false; }
  return assert(ok, "ceiling is the lowest BKN/OVC layer; FEW/SCT never count");
}

fn t9() -> TestResult {
  var ok = category_is(vis_raw(1599), "LIFR");
  if !category_is(vis_raw(1600), "IFR") { ok = false; }
  if !category_is(vis_raw(4799), "IFR") { ok = false; }
  if !category_is(vis_raw(4800), "MVFR") { ok = false; }
  if !category_is(vis_raw(7999), "MVFR") { ok = false; }
  if !category_is(vis_raw(8000), "VFR") { ok = false; }
  return assert(ok, "visibility category boundaries 1600/4800/8000 m");
}

fn t10() -> TestResult {
  var ok = category_is(ceil_raw(4), "LIFR");
  if !category_is(ceil_raw(5), "IFR") { ok = false; }
  if !category_is(ceil_raw(9), "IFR") { ok = false; }
  if !category_is(ceil_raw(10), "MVFR") { ok = false; }
  if !category_is(ceil_raw(29), "MVFR") { ok = false; }
  if !category_is(ceil_raw(30), "VFR") { ok = false; }
  return assert(ok, "ceiling category boundaries 500/1000/3000 ft");
}

fn t11() -> TestResult {
  var ok = category_is("KAAA 010000Z 00000KT 9999 BKN003 10/05 Q1013", "LIFR");
  if !category_is("KAAA 010000Z 00000KT 2000 BKN050 10/05 Q1013", "IFR") { ok = false; }
  if !category_is("KAAA 010000Z 00000KT 6000 BKN010 10/05 Q1013", "MVFR") { ok = false; }
  if !category_is("KAAA 010000Z 00000KT 9999 BKN050 10/05 Q1013", "VFR") { ok = false; }
  if !category_is("KAAA 010000Z", "VFR") { ok = false; }
  return assert(ok, "the most restrictive of visibility and ceiling wins");
}

fn t12() -> TestResult {
  let raw = "EGLL 24012KT";
  var ok = time_is(raw, -1, -1, -1);
  if !visibility_is(raw, -1) { ok = false; }
  if !temperature_is(raw, -1, -1) { ok = false; }
  if !altimeter_is(raw, -1) { ok = false; }
  if !ceiling_is(raw, -1) { ok = false; }
  if !category_is(raw, "VFR") { ok = false; }
  if !summary_is(raw, "EGLL 240/12kt vis=/// /////// Q/// VFR") { ok = false; }
  return assert(ok, "values the report omits are -1 and render as ///");
}

fn t13() -> TestResult {
  var ok = station_is("EGLL", "EGLL");
  if !station_is("egll 121150Z", "egll") { ok = false; }
  if !parse_is_ok("EGLL") { ok = false; }
  if !visibility_is("EGLL", -1) { ok = false; }
  if parse_is_ok("EGL 121150Z") { ok = false; }
  if parse_is_ok("EGLLL 121150Z") { ok = false; }
  if parse_is_ok("EG1L 121150Z") { ok = false; }
  return assert(ok, "station is exactly four letters (either case), stored verbatim");
}

fn t14() -> TestResult {
  var ok = parse_err_is("", "metar: empty observation");
  if !parse_err_is("   ", "metar: empty observation") { ok = false; }
  if !parse_err_is("\t \t", "metar: empty observation") { ok = false; }
  if !parse_err_is("EGL 121150Z", "metar: invalid station: EGL") { ok = false; }
  if !parse_err_is("METAR 121150Z", "metar: invalid station: METAR") { ok = false; }
  if !parse_err_is("1234 121150Z", "metar: invalid station: 1234") { ok = false; }
  return assert(ok, "empty input and bad station produce the documented errors");
}

fn t15() -> TestResult {
  let raw = "EGLL 121150Z 24012KT 9999 SCT020 18/12 Q1013 RMK AO2 SLP123 T01800120";
  var ok = summary_is(raw, "EGLL 240/12kt vis=9999m 18/12 Q1013 VFR");
  if !ceiling_is("EGLL 121150Z 24012KT 9999 FEW020TCU 18/12 Q1013", -1) { ok = false; }
  if !visibility_is("EGLL 121150Z 24012KT P6SM SCT020 18/12 Q1013", -1) { ok = false; }
  if !visibility_is("EGLL 121150Z 24012KT R06L/2000 SCT020 18/12 Q1013", -1) { ok = false; }
  return assert(ok, "unknown tokens (remarks, trends, RVR, suffixed clouds) are ignored");
}

fn t16() -> TestResult {
  var ok = visibility_is("KAAA 010000Z 00000KT 0000 10/05 Q1013", 0);
  if !visibility_is("KAAA 010000Z 00000KT 0750 10/05 Q1013", 750) { ok = false; }
  if !visibility_is("KAAA 010000Z 00000KT 2400 10/05 Q1013", 2400) { ok = false; }
  if !visibility_is("KAAA 010000Z 00000KT 9999 10/05 Q1013", 9999) { ok = false; }
  if !visibility_is("KAAA 010000Z 00000KT 12000 10/05 Q1013", -1) { ok = false; }
  return assert(ok, "4-digit meters accepted exactly; 5 digits is not a visibility");
}

fn t17() -> TestResult {
  var ok = wind_is("KAAA 010000Z 00000KT 10/05 Q1013", 0, 0, -1);
  if !wind_is("KAAA 010000Z 09010G20KT 10/05 Q1013", 90, 10, 20) { ok = false; }
  if !wind_is("KAAA 010000Z 36015KT 10/05 Q1013", 360, 15, -1) { ok = false; }
  if !wind_is("KAAA 010000Z 36112KT 10/05 Q1013", -1, -1, -1) { ok = false; }
  if !wind_is("KAAA 010000Z 24012G25 10/05 Q1013", -1, -1, -1) { ok = false; }
  return assert(ok, "calm, gust and 360 deg accepted; 361 and missing KT ignored");
}

fn t18() -> TestResult {
  var ok = temperature_is("KAAA 010000Z 18/12 Q1013", 18, 12);
  if !temperature_is("KAAA 010000Z M05/M10 Q1013", -5, -10) { ok = false; }
  if !temperature_is("KAAA 010000Z M00/M02 Q1013", 0, -2) { ok = false; }
  if !temperature_is("KAAA 010000Z M5/M10 Q1013", -5, -10) { ok = false; }
  if !temperature_is("KAAA 010000Z 18/ Q1013", 18, -1) { ok = false; }
  if !temperature_is("KAAA 010000Z /12 Q1013", -1, 12) { ok = false; }
  if !temperature_is("KAAA 010000Z 123/45 Q1013", -1, -1) { ok = false; }
  return assert(ok, "M-prefixed and missing temp/dew sides decode as documented");
}

fn t19() -> TestResult {
  var ok = time_is("KAAA 121150Z", 12, 11, 50);
  if !time_is("KAAA 011200Z", 1, 12, 0) { ok = false; }
  if !time_is("KAAA 311223Z", 31, 12, 23) { ok = false; }
  if !time_is("KAAA 321200Z", -1, -1, -1) { ok = false; }
  if !time_is("KAAA 121260Z", -1, -1, -1) { ok = false; }
  if !time_is("KAAA 121150", -1, -1, -1) { ok = false; }
  if !time_is("KAAA 1250Z", -1, -1, -1) { ok = false; }
  return assert(ok, "DDHHMMZ requires valid ranges; malformed time is ignored");
}

fn t20() -> TestResult {
  var ok = wind_is("EGLL 24012KT 18005KT 9999 18/12 Q1013", 180, 5, -1);
  if !altimeter_is("EGLL 24012KT 9999 18/12 Q1013 Q0998", 998) { ok = false; }
  if !visibility_is("EGLL 24012KT 9999 3000 18/12 Q1013", 3000) { ok = false; }
  if !summary_is(egll(), "EGLL 240/12kt vis=9999m 18/12 Q1013 VFR") { ok = false; }
  return assert(ok, "a later recognized token of a kind overwrites the earlier one");
}

fn main() -> Int {
  io.println("=== xiom.weather conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.weather: all tests passed");
  } else {
    io.println("xiom.weather: tests failed");
  }
  return failed;
}
