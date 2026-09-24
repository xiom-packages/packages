// XIOM -- xiom.nmea conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.nmea module against its SPEC.md:
// checksum arithmetic, sentence type and field splitting, the dm -> micro
// degree conversion and the GGA/RMC field accessors.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every fixture below carries its checksum built into the literal; the values
// were derived from the XOR definition and are pinned by t1, t2 and t21.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below (sentence types, fields, error messages) is routed through streq
// instead of `==`.

module nmea_tests
use xiom.io; use xiom.test; use xiom.nmea;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn ok_int(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok { return false; }
  return r.value == want;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn ok_bool(r: Result[Bool, Str], want: Bool) -> Bool {
  if !r.is_ok { return false; }
  return r.value == want;
}

fn err_bool_is(r: Result[Bool, Str], want: Str) -> Bool {
  if r.is_ok { return false; }
  return streq(r.error, want);
}

fn sentence_type_is(s: Str, want: Str) -> Bool {
  let t: Str = nmea_sentence_type(s);
  return streq(t, want);
}

fn field_is(s: Str, i: Int, want: Str) -> Bool {
  let v: Str = nmea_field(s, i);
  return streq(v, want);
}

// --- fixtures ---------------------------------------------------------------

// Standard GPGGA sample: checksum 0x47 = 71.
fn gga() -> Str {
  return "$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47";
}

// Standard GPRMC sample: checksum 0x6A = 106.
fn rmc() -> Str {
  return "$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A";
}

// AIS sentence using the '!' start delimiter: checksum 0x23 = 35.
fn ais() -> Str {
  return "!AIVDM,1,1,,A,13HOI:0P0000VOHLCnHQKwvL05Ip,0*23";
}

fn gga_zero_quality() -> Str {
  return "$GPGGA,120000,6000.000,N,02431.000,E,0,08,0.9,545.4,M,46.9,M,,*48";
}

fn gga_sats12() -> Str {
  return "$GPGGA,120000,6000.000,N,02431.000,E,1,12,0.9,545.4,M,46.9,M,,*42";
}

fn gga_neg_alt() -> Str {
  return "$GPGGA,120000,6000.000,N,02431.000,E,1,09,0.9,-10.5,M,46.9,M,,*51";
}

fn gga_long_alt() -> Str {
  return "$GPGGA,120000,6000.000,N,02431.000,E,1,09,0.9,545.456,M,46.9,M,,*4B";
}

fn gga_no_quality() -> Str {
  return "$GPGGA,120000,6000.000,N,02431.000,E*40";
}

fn gga_bad_quality() -> Str {
  return "$GPGGA,120000,6000.000,N,02431.000,E,x2,08,0.9,545.4,M,46.9,M,,*32";
}

fn gga_bad_sats() -> Str {
  return "$GPGGA,120000,6000.000,N,02431.000,E,1,x2,0.9,545.4,M,46.9,M,,*0B";
}

fn gga_empty_sats() -> Str {
  return "$GPGGA,120000,6000.000,N,02431.000,E,1,,0.9,545.4,M,46.9,M,,*41";
}

fn gga_missing_alt() -> Str {
  return "$GPGGA,120000,6000.000,N,02431.000,E,1,09,0.9,,M,46.9,M,,*66";
}

fn gga_dot_alt() -> Str {
  return "$GPGGA,120000,6000.000,N,02431.000,E,1,09,0.9,.,M,46.9,M,,*48";
}

fn gga_bad_alt() -> Str {
  return "$GPGGA,120000,6000.000,N,02431.000,E,1,09,0.9,abc,M,46.9,M,,*06";
}

fn gga_lower_type() -> Str {
  return "$gpgga,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*67";
}

fn rmc_void() -> Str {
  return "$GPRMC,123519,V,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*7D";
}

fn rmc_lower() -> Str {
  return "$GPRMC,123519,a,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*4A";
}

fn rmc_empty_status() -> Str {
  return "$GPRMC,123519,,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*2B";
}

fn rmc_bad_status() -> Str {
  return "$GPRMC,123519,X,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*73";
}

// --- tests ------------------------------------------------------------------

fn t1() -> TestResult {
  let s = gga();
  var ok = sentence_type_is(s, "GPGGA");
  if nmea_field_count(s) != 14 { ok = false; }
  if !field_is(s, 0, "123519") { ok = false; }
  if !field_is(s, 1, "4807.038") { ok = false; }
  if !field_is(s, 2, "N") { ok = false; }
  if !field_is(s, 3, "01131.000") { ok = false; }
  if !field_is(s, 4, "E") { ok = false; }
  if !field_is(s, 5, "1") { ok = false; }
  if !field_is(s, 6, "08") { ok = false; }
  if !field_is(s, 7, "0.9") { ok = false; }
  if !field_is(s, 8, "545.4") { ok = false; }
  if !field_is(s, 9, "M") { ok = false; }
  if !field_is(s, 10, "46.9") { ok = false; }
  if !field_is(s, 11, "M") { ok = false; }
  if !field_is(s, 12, "") { ok = false; }
  if !field_is(s, 13, "") { ok = false; }
  if !nmea_checksum_ok(s) { ok = false; }
  if nmea_compute_checksum(s) != 71 { ok = false; }
  return assert(ok, "GPGGA fixture: type, 14 fields, checksum 0x47");
}

fn t2() -> TestResult {
  let s = rmc();
  var ok = sentence_type_is(s, "GPRMC");
  if nmea_field_count(s) != 11 { ok = false; }
  if !field_is(s, 0, "123519") { ok = false; }
  if !field_is(s, 1, "A") { ok = false; }
  if !field_is(s, 2, "4807.038") { ok = false; }
  if !field_is(s, 3, "N") { ok = false; }
  if !field_is(s, 4, "01131.000") { ok = false; }
  if !field_is(s, 5, "E") { ok = false; }
  if !field_is(s, 6, "022.4") { ok = false; }
  if !field_is(s, 7, "084.4") { ok = false; }
  if !field_is(s, 8, "230394") { ok = false; }
  if !field_is(s, 9, "003.1") { ok = false; }
  if !field_is(s, 10, "W") { ok = false; }
  if !nmea_checksum_ok(s) { ok = false; }
  if nmea_compute_checksum(s) != 106 { ok = false; }
  return assert(ok, "GPRMC fixture: type, 11 fields, checksum 0x6A");
}

fn t3() -> TestResult {
  var ok = nmea_checksum_ok(gga());
  if nmea_checksum_ok("$GPGGB,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47") { ok = false; }
  if nmea_checksum_ok("$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*48") { ok = false; }
  return assert(ok, "checksum fails on a flipped payload byte and a flipped digit");
}

fn t4() -> TestResult {
  var ok = nmea_checksum_ok(rmc_lower());
  if !nmea_checksum_ok("$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6a") { ok = false; }
  if nmea_checksum_ok("$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6G") { ok = false; }
  if nmea_checksum_ok("$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6") { ok = false; }
  if nmea_checksum_ok("$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*") { ok = false; }
  return assert(ok, "checksum accepts either hex case and rejects malformed suffixes");
}

fn t5() -> TestResult {
  var ok = nmea_compute_checksum(gga()) == 71;
  if nmea_compute_checksum(rmc()) != 106 { ok = false; }
  if nmea_compute_checksum(ais()) != 35 { ok = false; }
  if nmea_compute_checksum("$GPGGA,1,2*55") != 85 { ok = false; }
  if nmea_compute_checksum("$GPGGA,1,2") != 85 { ok = false; }
  if nmea_compute_checksum("") != 0 { ok = false; }
  if nmea_compute_checksum("hello") != 0 { ok = false; }
  return assert(ok, "compute_checksum pins and the absent-start case");
}

fn t6() -> TestResult {
  var ok = sentence_type_is(gga(), "GPGGA");
  if !sentence_type_is(rmc(), "GPRMC") { ok = false; }
  if !sentence_type_is(ais(), "AIVDM") { ok = false; }
  if !sentence_type_is("$GPTXT,hello*00", "GPTXT") { ok = false; }
  if !sentence_type_is("GPGGA,1,2", "") { ok = false; }
  if !sentence_type_is("$GPGGA", "") { ok = false; }
  if !sentence_type_is("$GPGGA*47", "") { ok = false; }
  if !sentence_type_is("", "") { ok = false; }
  return assert(ok, "sentence type extraction and malformed cases");
}

fn t7() -> TestResult {
  var ok = nmea_field_count("$GPGGA,,1,,2,*79") == 5;
  if !field_is("$GPGGA,,1,,2,*79", 0, "") { ok = false; }
  if !field_is("$GPGGA,,1,,2,*79", 1, "1") { ok = false; }
  if !field_is("$GPGGA,,1,,2,*79", 2, "") { ok = false; }
  if !field_is("$GPGGA,,1,,2,*79", 3, "2") { ok = false; }
  if !field_is("$GPGGA,,1,,2,*79", 4, "") { ok = false; }
  if nmea_field_count("$GPGGA,") != 1 { ok = false; }
  if !field_is("$GPGGA,", 0, "") { ok = false; }
  if nmea_field_count("$GPGGA,1,2*55") != 2 { ok = false; }
  if !field_is("$GPGGA,1,2*55", 1, "2") { ok = false; }
  return assert(ok, "fields keep empty entries and drop the checksum");
}

fn t8() -> TestResult {
  var ok = streq(nmea_field(gga(), 14), "");
  if !streq(nmea_field(gga(), 99), "") { ok = false; }
  if !streq(nmea_field(gga(), -1), "") { ok = false; }
  if nmea_field_count("") != 0 { ok = false; }
  if nmea_field_count("abc") != 0 { ok = false; }
  if !streq(nmea_field("abc", 0), "") { ok = false; }
  return assert(ok, "field and field_count out-of-range behavior");
}

fn t9() -> TestResult {
  var ok = !nmea_checksum_ok("$GPGGA,1,2");
  if !sentence_type_is("$GPGGA,1,2", "GPGGA") { ok = false; }
  if nmea_field_count("$GPGGA,1,2") != 2 { ok = false; }
  if !field_is("$GPGGA,1,2", 0, "1") { ok = false; }
  if !nmea_checksum_ok("$GPGGA,1,2*55\r\n") { ok = false; }
  if nmea_field_count("$GPGGA,1,2*55\r\n") != 2 { ok = false; }
  if !field_is("$GPGGA,1,2*55\r\n", 1, "2") { ok = false; }
  return assert(ok, "missing checksum and trailing CRLF");
}

fn t10() -> TestResult {
  var ok = ok_int(nmea_dm_to_micro_deg("6011.000", "N"), 60183333);
  if !ok_int(nmea_dm_to_micro_deg("02431.000", "E"), 24516666) { ok = false; }
  if !ok_int(nmea_dm_to_micro_deg("4807.038", "N"), 48117300) { ok = false; }
  if !ok_int(nmea_dm_to_micro_deg("6011", "N"), 60183333) { ok = false; }
  if !ok_int(nmea_dm_to_micro_deg("2431", "E"), 24516666) { ok = false; }
  return assert(ok, "dm to micro degrees: north/east pins");
}

fn t11() -> TestResult {
  var ok = ok_int(nmea_dm_to_micro_deg("6011.000", "S"), -60183333);
  if !ok_int(nmea_dm_to_micro_deg("02431.000", "W"), -24516666) { ok = false; }
  if !ok_int(nmea_dm_to_micro_deg("6011.000", "s"), -60183333) { ok = false; }
  if !ok_int(nmea_dm_to_micro_deg("6011.000", "n"), 60183333) { ok = false; }
  if !ok_int(nmea_dm_to_micro_deg("02431.000", "w"), -24516666) { ok = false; }
  if !ok_int(nmea_dm_to_micro_deg("02431.000", "e"), 24516666) { ok = false; }
  return assert(ok, "dm south/west negatives and hemisphere case");
}

fn t12() -> TestResult {
  var ok = ok_int(nmea_dm_to_micro_deg("6011.9", "N"), 60198333);
  if !ok_int(nmea_dm_to_micro_deg("6011.999", "N"), 60199983) { ok = false; }
  if !ok_int(nmea_dm_to_micro_deg("6011.9999", "N"), 60199998) { ok = false; }
  if !ok_int(nmea_dm_to_micro_deg("6011.99999", "N"), 60199998) { ok = false; }
  return assert(ok, "dm fraction scaling and truncation past four digits");
}

fn t13() -> TestResult {
  var ok = err_int_is(nmea_dm_to_micro_deg("", "N"), "nmea: empty coordinate");
  if !err_int_is(nmea_dm_to_micro_deg("601.000", "N"), "nmea: invalid coordinate: 601.000") { ok = false; }
  if !err_int_is(nmea_dm_to_micro_deg("60a1.000", "N"), "nmea: invalid coordinate: 60a1.000") { ok = false; }
  if !err_int_is(nmea_dm_to_micro_deg("6070.000", "N"), "nmea: invalid coordinate: 6070.000") { ok = false; }
  if !err_int_is(nmea_dm_to_micro_deg("6011.0.0", "N"), "nmea: invalid coordinate: 6011.0.0") { ok = false; }
  if !err_int_is(nmea_dm_to_micro_deg("123456.0", "N"), "nmea: invalid coordinate: 123456.0") { ok = false; }
  if !err_int_is(nmea_dm_to_micro_deg("6011.00x", "N"), "nmea: invalid coordinate: 6011.00x") { ok = false; }
  if !err_int_is(nmea_dm_to_micro_deg("", "X"), "nmea: empty coordinate") { ok = false; }
  return assert(ok, "dm bad value errors");
}

fn t14() -> TestResult {
  var ok = err_int_is(nmea_dm_to_micro_deg("6011.000", ""), "nmea: invalid hemisphere: ");
  if !err_int_is(nmea_dm_to_micro_deg("6011.000", "X"), "nmea: invalid hemisphere: X") { ok = false; }
  if !err_int_is(nmea_dm_to_micro_deg("6011.000", "NS"), "nmea: invalid hemisphere: NS") { ok = false; }
  if !err_int_is(nmea_dm_to_micro_deg("6011.000", "north"), "nmea: invalid hemisphere: north") { ok = false; }
  return assert(ok, "dm bad hemisphere errors");
}

fn t15() -> TestResult {
  var ok = ok_int(nmea_gga_quality(gga()), 1);
  if !ok_int(nmea_gga_quality(gga_zero_quality()), 0) { ok = false; }
  if !err_int_is(nmea_gga_quality(gga_no_quality()), "nmea: missing GGA quality") { ok = false; }
  if !err_int_is(nmea_gga_quality(gga_bad_quality()), "nmea: invalid GGA quality: x2") { ok = false; }
  if !err_int_is(nmea_gga_quality(rmc()), "nmea: not a GGA sentence") { ok = false; }
  return assert(ok, "GGA quality field");
}

fn t16() -> TestResult {
  var ok = ok_int(nmea_gga_satellites(gga()), 8);
  if !ok_int(nmea_gga_satellites(gga_sats12()), 12) { ok = false; }
  if !err_int_is(nmea_gga_satellites(gga_empty_sats()), "nmea: missing GGA satellites") { ok = false; }
  if !err_int_is(nmea_gga_satellites(gga_bad_sats()), "nmea: invalid GGA satellites: x2") { ok = false; }
  if !err_int_is(nmea_gga_satellites(ais()), "nmea: not a GGA sentence") { ok = false; }
  return assert(ok, "GGA satellites field");
}

fn t17() -> TestResult {
  var ok = ok_int(nmea_gga_altitude_cm(gga()), 54540);
  if !ok_int(nmea_gga_altitude_cm(gga_zero_quality()), 54540) { ok = false; }
  if !ok_int(nmea_gga_altitude_cm(gga_neg_alt()), -1050) { ok = false; }
  if !ok_int(nmea_gga_altitude_cm(gga_long_alt()), 54545) { ok = false; }
  if !err_int_is(nmea_gga_altitude_cm(gga_missing_alt()), "nmea: missing GGA altitude") { ok = false; }
  if !err_int_is(nmea_gga_altitude_cm(gga_dot_alt()), "nmea: invalid GGA altitude: .") { ok = false; }
  if !err_int_is(nmea_gga_altitude_cm(gga_bad_alt()), "nmea: invalid GGA altitude: abc") { ok = false; }
  if !err_int_is(nmea_gga_altitude_cm(rmc()), "nmea: not a GGA sentence") { ok = false; }
  return assert(ok, "GGA altitude in centimeters");
}

fn t18() -> TestResult {
  var ok = ok_bool(nmea_rmc_valid(rmc()), true);
  if !ok_bool(nmea_rmc_valid(rmc_void()), false) { ok = false; }
  if !ok_bool(nmea_rmc_valid(rmc_lower()), true) { ok = false; }
  if !err_bool_is(nmea_rmc_valid(rmc_empty_status()), "nmea: missing RMC status") { ok = false; }
  if !err_bool_is(nmea_rmc_valid(rmc_bad_status()), "nmea: invalid RMC status: X") { ok = false; }
  if !err_bool_is(nmea_rmc_valid(gga()), "nmea: not an RMC sentence") { ok = false; }
  return assert(ok, "RMC status A/V");
}

fn t19() -> TestResult {
  var ok = sentence_type_is("", "");
  if nmea_field_count("") != 0 { ok = false; }
  if !streq(nmea_field("", 0), "") { ok = false; }
  if nmea_compute_checksum("") != 0 { ok = false; }
  if nmea_checksum_ok("") { ok = false; }
  return assert(ok, "empty input is inert");
}

fn t20() -> TestResult {
  let mid = "$GPGGA,1*,2*00";
  var ok = sentence_type_is(mid, "GPGGA");
  if nmea_checksum_ok(mid) { ok = false; }
  if nmea_field_count(mid) != 1 { ok = false; }
  if !field_is(mid, 0, "1") { ok = false; }
  if nmea_checksum_ok("$GPGGA,1,2*") { ok = false; }
  if nmea_field_count("$GPGGA,1,2*") != 2 { ok = false; }
  if nmea_checksum_ok("GPGGA,1,2*55") { ok = false; }
  return assert(ok, "malformed sentences do not trap");
}

fn t21() -> TestResult {
  let s = ais();
  var ok = sentence_type_is(s, "AIVDM");
  if nmea_field_count(s) != 6 { ok = false; }
  if !field_is(s, 0, "1") { ok = false; }
  if !field_is(s, 1, "1") { ok = false; }
  if !field_is(s, 2, "") { ok = false; }
  if !field_is(s, 3, "A") { ok = false; }
  if !field_is(s, 4, "13HOI:0P0000VOHLCnHQKwvL05Ip") { ok = false; }
  if !field_is(s, 5, "0") { ok = false; }
  if !nmea_checksum_ok(s) { ok = false; }
  if nmea_compute_checksum(s) != 35 { ok = false; }
  return assert(ok, "AIS '!' sentence: type, six fields, checksum 0x23");
}

fn t22() -> TestResult {
  var ok = err_int_is(nmea_gga_quality(rmc()), "nmea: not a GGA sentence");
  if !err_int_is(nmea_gga_satellites(rmc()), "nmea: not a GGA sentence") { ok = false; }
  if !err_int_is(nmea_gga_altitude_cm(rmc()), "nmea: not a GGA sentence") { ok = false; }
  if !err_bool_is(nmea_rmc_valid(gga()), "nmea: not an RMC sentence") { ok = false; }
  if !err_int_is(nmea_gga_quality(""), "nmea: not a GGA sentence") { ok = false; }
  if !err_bool_is(nmea_rmc_valid(""), "nmea: not an RMC sentence") { ok = false; }
  return assert(ok, "accessors reject the wrong sentence type");
}

fn t23() -> TestResult {
  let s = gga_lower_type();
  var ok = sentence_type_is(s, "gpgga");
  if !ok_int(nmea_gga_quality(s), 1) { ok = false; }
  if !ok_int(nmea_gga_satellites(s), 8) { ok = false; }
  if !ok_int(nmea_gga_altitude_cm(s), 54540) { ok = false; }
  if !nmea_checksum_ok(s) { ok = false; }
  return assert(ok, "talker and type case-insensitivity in accessors");
}

fn t24() -> TestResult {
  var ok = field_is(gga(), 13, "");
  if !field_is(gga(), 11, "M") { ok = false; }
  if !field_is(gga(), 12, "") { ok = false; }
  if !field_is(rmc(), 10, "W") { ok = false; }
  if !field_is("$GPGGA,1,2*55", 1, "2") { ok = false; }
  if !streq(nmea_field("$GPGGA,1,2*55", 2), "") { ok = false; }
  return assert(ok, "checksum digits are not part of the last field");
}

fn main() -> Int {
  io.println("=== xiom.nmea conformance tests ===");
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
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.nmea: all tests passed");
  } else {
    io.println("xiom.nmea: tests failed");
  }
  return failed;
}
