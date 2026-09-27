// XIOM -- xiom.aviation conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixtures are real Mode S / ADS-B frames written as hex text and converted
// byte by byte, so the parser is exercised against bytes this test file
// controls and no library code is used to build them. Error strings are
// compared through compare.str_compare (BUG 17 discipline: `==` on a Str
// read from a Vec lowers to a pointer comparison).

module aviation_tests
use xiom.io; use xiom.test;
use xiom.aviation;
use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Helpers (independent of src/aviation.xi)
// --------------------------------------------------

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_frame_is(r: Result[AviationFrame, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_emergency_is(r: Result[AviationEmergency, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_position_is(r: Result[AviationPosition, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_surface_is(r: Result[AviationSurface, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_velocity_is(r: Result[AviationVelocity, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_fix_is(r: Result[AviationFix, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// True when |a - b| <= tol.
fn near(a: Int, b: Int, tol: Int) -> Bool {
  if a >= b {
    return a - b <= tol;
  }
  return b - a <= tol;
}

fn err_target_is(r: Result[AviationTargetState, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

fn err_opstatus_is(r: Result[AviationOpStatus, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return str_eq(r.error, want);
}

// Hex value of one ASCII hex digit, or -1.
fn hex_digit(b: UInt8) -> Int {
  if b >= 48u8 && b <= 57u8 { return (b as Int) - 48; }
  if b >= 65u8 && b <= 70u8 { return (b as Int) - 55; }
  if b >= 97u8 && b <= 102u8 { return (b as Int) - 87; }
  return -1;
}

// Byte vector from a hex string (two hex digits per byte).
fn from_hex(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i + 1 < s.len() {
    let hi = hex_digit(string.byte_at(s, i));
    let lo = hex_digit(string.byte_at(s, i + 1));
    v.push((hi * 16 + lo) as UInt8);
    i = i + 2;
  }
  return v;
}

// Unsigned integer from a hex string.
fn hex_int(s: Str) -> Int {
  var acc = 0;
  var i = 0;
  while i < s.len() {
    acc = acc * 16 + hex_digit(string.byte_at(s, i));
    i = i + 1;
  }
  return acc;
}

// The first `n` bytes of `v`.
fn prefix(v: Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// A copy of `v` with byte `pos` replaced.
fn with_byte(v: Vec[UInt8], pos: Int, b: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    if i == pos {
      out.push(b as UInt8);
    } else {
      out.push(v[i]);
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Part 1: bit reader, DF table, frame intake
// --------------------------------------------------

fn t1() -> TestResult {
  let fx = from_hex("8D40621D58C382D690C8AC2863A7");
  var ok = fx.len() == 14;
  let b0 = aviation_bit(&fx, 0);
  if !b0.is_ok { ok = false; } else { if b0.value != 1 { ok = false; } }
  let b4 = aviation_bit(&fx, 4);
  if !b4.is_ok { ok = false; } else { if b4.value != 1 { ok = false; } }
  let b5 = aviation_bit(&fx, 5);
  if !b5.is_ok { ok = false; } else { if b5.value != 1 { ok = false; } }
  let df = aviation_bits(&fx, 0, 5);
  if !df.is_ok { ok = false; } else { if df.value != 17 { ok = false; } }
  let ca = aviation_bits(&fx, 5, 3);
  if !ca.is_ok { ok = false; } else { if ca.value != 5 { ok = false; } }
  let aa = aviation_bits(&fx, 8, 24);
  if !aa.is_ok { ok = false; } else { if aa.value != 4219421 { ok = false; } }
  if !err_int_is(aviation_bit(&fx, -1), "aviation: bit offset out of range") { ok = false; }
  if !err_int_is(aviation_bit(&fx, 112), "aviation: bit offset out of range") { ok = false; }
  if !err_int_is(aviation_bits(&fx, 108, 8), "aviation: bit offset out of range") { ok = false; }
  if !err_int_is(aviation_bits(&fx, 0, 57), "aviation: bit width out of range") { ok = false; }
  if !err_int_is(aviation_bits(&fx, 0, -1), "aviation: bit width out of range") { ok = false; }
  let z = aviation_bits(&fx, 112, 0);
  if !z.is_ok { ok = false; } else { if z.value != 0 { ok = false; } }
  return assert(ok, "MSB-first bit reader: bits, spans and range errors");
}

fn t2() -> TestResult {
  var ok = aviation_df_length(0) == 7;
  if aviation_df_length(4) != 7 { ok = false; }
  if aviation_df_length(5) != 7 { ok = false; }
  if aviation_df_length(11) != 7 { ok = false; }
  if aviation_df_length(16) != 14 { ok = false; }
  if aviation_df_length(17) != 14 { ok = false; }
  if aviation_df_length(18) != 14 { ok = false; }
  if aviation_df_length(19) != 14 { ok = false; }
  if aviation_df_length(20) != 14 { ok = false; }
  if aviation_df_length(21) != 14 { ok = false; }
  if aviation_df_length(24) != 14 { ok = false; }
  if aviation_df_length(1) != -1 { ok = false; }
  if aviation_df_length(25) != -1 { ok = false; }
  if aviation_df_length(-1) != -1 { ok = false; }
  if !str_eq(aviation_df_name(17), "DF17 extended squitter (ADS-B)") { ok = false; }
  if !str_eq(aviation_df_name(11), "DF11 all-call reply") { ok = false; }
  if !str_eq(aviation_df_name(24), "DF24 Comm-D extended length message") { ok = false; }
  if !str_eq(aviation_df_name(1), "DF? reserved") { ok = false; }
  if !str_eq(aviation_df_name(99), "DF? out of range") { ok = false; }
  return assert(ok, "DF table: encoded lengths 7/14 and reserved values");
}

fn t3() -> TestResult {
  let fx = from_hex("8D40621D58C382D690C8AC2863A7");
  let r = aviation_parse_frame(&fx);
  if !r.is_ok { return assert(false, "DF17 frame must parse"); }
  let f: AviationFrame = r.value;
  var ok = aviation_frame_df(&f) == 17;
  if aviation_frame_ca(&f) != 5 { ok = false; }
  if aviation_frame_icao(&f) != 4219421 { ok = false; }
  if aviation_frame_tc(&f) != 11 { ok = false; }
  return assert(ok, "DF17 frame intake: DF, CA, ICAO, TC");
}

fn t4() -> TestResult {
  let fx = from_hex("8D40621D58C382D690C8AC2863A7");
  let r = aviation_parse_frame(&fx);
  if !r.is_ok { return assert(false, "DF17 frame must parse"); }
  let f: AviationFrame = r.value;
  var ok = aviation_frame_bits(&f) == 112;
  if aviation_frame_bytes(&f) != 14 { ok = false; }
  if aviation_frame_consumed(&f) != 14 { ok = false; }
  if aviation_frame_payload(&f) != hex_int("58C382D690C8AC") { ok = false; }
  if aviation_frame_parity(&f) != hex_int("2863A7") { ok = false; }
  var stream = Vec[UInt8].new();
  var i = 0;
  while i < fx.len() {
    stream.push(fx[i]);
    i = i + 1;
  }
  stream.push(255u8);
  stream.push(0u8);
  let r2 = aviation_parse_frame(&stream);
  if !r2.is_ok { ok = false; } else {
    let g: AviationFrame = r2.value;
    if aviation_frame_consumed(&g) != 14 { ok = false; }
    if aviation_frame_icao(&g) != 4219421 { ok = false; }
  }
  return assert(ok, "112-bit payload, raw parity, and stream consumption");
}

// --------------------------------------------------
//  Part 2: identification, altitude, emergency, TC table
// --------------------------------------------------

fn t5() -> TestResult {
  let fx = from_hex("8D4840D6202CC371C32CE0576098");
  let r = aviation_parse_frame(&fx);
  if !r.is_ok { return assert(false, "identification frame must parse"); }
  let f: AviationFrame = r.value;
  var ok = aviation_frame_df(&f) == 17;
  if aviation_frame_tc(&f) != 4 { ok = false; }
  let idr = aviation_ident_decode(&f);
  if !idr.is_ok { ok = false; } else {
    let id: AviationIdent = idr.value;
    if aviation_ident_tc(&id) != 4 { ok = false; }
    if aviation_ident_category(&id) != 0 { ok = false; }
    if !str_eq(aviation_ident_callsign(&id), "KLM1023 ") { ok = false; }
    if !str_eq(aviation_ident_callsign_trim(&id), "KLM1023") { ok = false; }
  }
  if !str_eq(aviation_callsign_char(11), "K") { ok = false; }
  if !str_eq(aviation_callsign_char(48), "0") { ok = false; }
  if !str_eq(aviation_callsign_char(32), " ") { ok = false; }
  if !str_eq(aviation_callsign_char(0), "#") { ok = false; }
  if !str_eq(aviation_callsign_char(27), "#") { ok = false; }
  if !str_eq(aviation_callsign_char(63), "#") { ok = false; }
  return assert(ok, "TC4 identification: KLM1023, charset, category");
}

fn t6() -> TestResult {
  var ok = aviation_ac12_qbit(3128) == 1;
  let a12 = aviation_ac12_altitude_ft(3128);
  if !a12.is_ok { ok = false; } else { if a12.value != 38000 { ok = false; } }
  if !err_int_is(aviation_ac12_altitude_ft(3112), "aviation: gillham altitude code unsupported") { ok = false; }
  if !err_int_is(aviation_ac12_altitude_ft(4096), "aviation: altitude field out of range") { ok = false; }
  if !err_int_is(aviation_ac12_altitude_ft(-1), "aviation: altitude field out of range") { ok = false; }
  if aviation_ac13_qbit(6200) != 1 { ok = false; }
  if aviation_ac13_metric_flag(6200) != 0 { ok = false; }
  let a13 = aviation_ac13_altitude_ft(6200);
  if !a13.is_ok { ok = false; } else { if a13.value != 38000 { ok = false; } }
  if !err_int_is(aviation_ac13_altitude_ft(6264), "aviation: metric altitude unsupported") { ok = false; }
  if !err_int_is(aviation_ac13_altitude_ft(6184), "aviation: gillham altitude code unsupported") { ok = false; }
  if !err_int_is(aviation_ac13_altitude_ft(8192), "aviation: altitude field out of range") { ok = false; }
  if aviation_gnss_altitude_m(1200) != 1200 { ok = false; }
  if aviation_gnss_altitude_ft(1200) != 3937 { ok = false; }
  return assert(ok, "AC12/AC13 Q-bit altitude decode, GNSS metres/feet, documented errors");
}

fn t7() -> TestResult {
  let fx = from_hex("88ABCDEFE1600000000000000000");
  let r = aviation_parse_frame(&fx);
  if !r.is_ok { return assert(false, "emergency frame must parse"); }
  let f: AviationFrame = r.value;
  var ok = aviation_frame_df(&f) == 17;
  if aviation_frame_icao(&f) != hex_int("ABCDEF") { ok = false; }
  if aviation_frame_tc(&f) != 28 { ok = false; }
  let er = aviation_emergency_decode(&f);
  if !er.is_ok { ok = false; } else {
    let e: AviationEmergency = er.value;
    if aviation_emergency_subtype(&e) != 1 { ok = false; }
    if aviation_emergency_state(&e) != 3 { ok = false; }
  }
  if !str_eq(aviation_emergency_state_name(3), "minimum fuel") { ok = false; }
  if !str_eq(aviation_emergency_state_name(5), "unlawful interference") { ok = false; }
  if !str_eq(aviation_emergency_state_name(9), "unknown") { ok = false; }
  let fx2 = from_hex("8D40621D58C382D690C8AC2863A7");
  let r2 = aviation_parse_frame(&fx2);
  if !r2.is_ok { ok = false; } else {
    let g: AviationFrame = r2.value;
    if !err_emergency_is(aviation_emergency_decode(&g), "aviation: not an aircraft status message") { ok = false; }
  }
  let fx3 = from_hex("5D4840D6202CC3");
  let r3 = aviation_parse_frame(&fx3);
  if !r3.is_ok { ok = false; } else {
    let h2: AviationFrame = r3.value;
    if !err_emergency_is(aviation_emergency_decode(&h2), "aviation: not an extended squitter frame") { ok = false; }
  }
  return assert(ok, "TC28 emergency decode, subtype gating and frame guards");
}

fn t8() -> TestResult {
  var ok = str_eq(aviation_tc_name(0), "TC0 no position information");
  if !str_eq(aviation_tc_name(4), "TC1-4 aircraft identification and category") { ok = false; }
  if !str_eq(aviation_tc_name(8), "TC5-8 surface position") { ok = false; }
  if !str_eq(aviation_tc_name(11), "TC9-18 airborne position (barometric altitude)") { ok = false; }
  if !str_eq(aviation_tc_name(19), "TC19 airborne velocity") { ok = false; }
  if !str_eq(aviation_tc_name(20), "TC20-22 airborne position (GNSS height)") { ok = false; }
  if !str_eq(aviation_tc_name(28), "TC28 aircraft status (emergency / TCAS RA)") { ok = false; }
  if !str_eq(aviation_tc_name(29), "TC29 target state and status") { ok = false; }
  if !str_eq(aviation_tc_name(31), "TC31 aircraft operational status") { ok = false; }
  if !str_eq(aviation_tc_name(-1), "TC? out of range") { ok = false; }
  if !str_eq(aviation_tc_name(32), "TC? out of range") { ok = false; }
  return assert(ok, "type code table names every range 0..31");
}

// --------------------------------------------------
//  Bit-level frame builders (used by part 3+ fixtures)
// --------------------------------------------------

// Append `len` bits of `value` (len = 1..56), MSB-first.
fn bits_add(bits: &mut Vec[Int], value: Int, len: Int) {
  var k = 0;
  while k < len {
    var w = 1;
    var i = 0;
    while i < len - 1 - k {
      w = w * 2;
      i = i + 1;
    }
    bits.push((value / w) % 2);
    k = k + 1;
  }
}

// Pack a bit vector whose length is a multiple of 8 into bytes.
fn bits_to_bytes(bits: Vec[Int]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i + 8 <= bits.len() {
    var b = 0;
    var j = 0;
    while j < 8 {
      let bit: Int = bits[i + j];
      b = b * 2 + bit;
      j = j + 1;
    }
    out.push(b as UInt8);
    i = i + 8;
  }
  return out;
}

// ME payload bits: type code followed by the rest of the bits.
fn me_of(tc: Int, rest: Vec[Int]) -> Vec[Int] {
  var bits = Vec[Int].new();
  bits_add(&mut bits, tc, 5);
  var i = 0;
  while i < rest.len() {
    let b: Int = rest[i];
    bits.push(b);
    i = i + 1;
  }
  return bits;
}

// A 14-byte DF17/DF18 frame: DF, CA, ICAO, 56 ME bits, parity.
fn build_long(df: Int, ca: Int, icao: Int, me: Vec[Int], parity: Int) -> Vec[UInt8] {
  var bits = Vec[Int].new();
  bits_add(&mut bits, df, 5);
  bits_add(&mut bits, ca, 3);
  bits_add(&mut bits, icao, 24);
  var i = 0;
  while i < me.len() {
    let b: Int = me[i];
    bits.push(b);
    i = i + 1;
  }
  bits_add(&mut bits, parity, 24);
  return bits_to_bytes(bits);
}

// A 7-byte short frame: DF, CA, ICAO, parity.
fn build_short(df: Int, ca: Int, icao: Int, parity: Int) -> Vec[UInt8] {
  var bits = Vec[Int].new();
  bits_add(&mut bits, df, 5);
  bits_add(&mut bits, ca, 3);
  bits_add(&mut bits, icao, 24);
  bits_add(&mut bits, parity, 24);
  return bits_to_bytes(bits);
}

// --------------------------------------------------
//  Part 3: surface, airborne position, velocity
// --------------------------------------------------

fn t9() -> TestResult {
  var rb = Vec[Int].new();
  bits_add(&mut rb, 39, 7);
  bits_add(&mut rb, 1, 1);
  bits_add(&mut rb, 64, 7);
  bits_add(&mut rb, 0, 1);
  bits_add(&mut rb, 1, 1);
  bits_add(&mut rb, 80000, 17);
  bits_add(&mut rb, 90000, 17);
  let fx = build_long(17, 4, hex_int("123456"), me_of(5, rb), 0);
  var ok = fx.len() == 14;
  let r = aviation_parse_frame(&fx);
  if !r.is_ok { return assert(false, "synthetic surface frame must parse"); }
  let f: AviationFrame = r.value;
  if aviation_frame_tc(&f) != 5 { ok = false; }
  let sr = aviation_surface_decode(&f);
  if !sr.is_ok { ok = false; } else {
    let s: AviationSurface = sr.value;
    if aviation_surface_tc(&s) != 5 { ok = false; }
    if aviation_surface_movement(&s) != 39 { ok = false; }
    if aviation_surface_speed_k8(&s) != 120 { ok = false; }
    if aviation_surface_track_status(&s) != 1 { ok = false; }
    if aviation_surface_track_raw(&s) != 64 { ok = false; }
    if aviation_surface_track_deg100(&s) != 18000 { ok = false; }
    if aviation_surface_time_flag(&s) != 0 { ok = false; }
    if aviation_surface_odd(&s) != 1 { ok = false; }
    if aviation_surface_cpr_lat(&s) != 80000 { ok = false; }
    if aviation_surface_cpr_lon(&s) != 90000 { ok = false; }
  }
  return assert(ok, "TC5 surface position: movement, track, CPR fields");
}

fn t10() -> TestResult {
  var ok = aviation_movement_k8(0) == -1;
  if aviation_movement_k8(1) != 0 { ok = false; }
  if aviation_movement_k8(2) != 1 { ok = false; }
  if aviation_movement_k8(8) != 7 { ok = false; }
  if aviation_movement_k8(9) != 8 { ok = false; }
  if aviation_movement_k8(12) != 14 { ok = false; }
  if aviation_movement_k8(13) != 16 { ok = false; }
  if aviation_movement_k8(38) != 116 { ok = false; }
  if aviation_movement_k8(39) != 120 { ok = false; }
  if aviation_movement_k8(93) != 552 { ok = false; }
  if aviation_movement_k8(94) != 560 { ok = false; }
  if aviation_movement_k8(108) != 784 { ok = false; }
  if aviation_movement_k8(109) != 800 { ok = false; }
  if aviation_movement_k8(123) != 1360 { ok = false; }
  if aviation_movement_k8(124) != 1400 { ok = false; }
  if aviation_movement_k8(125) != -2 { ok = false; }
  if aviation_movement_k8(127) != -2 { ok = false; }
  if aviation_track_deg100(0) != 0 { ok = false; }
  if aviation_track_deg100(64) != 18000 { ok = false; }
  if aviation_track_deg100(127) != 35719 { ok = false; }
  return assert(ok, "movement table boundaries and track scale");
}

fn t11() -> TestResult {
  let fxe = from_hex("8D40621D58C382D690C8AC2863A7");
  let fxo = from_hex("8D40621D58C386435CC412692AD6");
  let re = aviation_parse_frame(&fxe);
  let ro = aviation_parse_frame(&fxo);
  if !re.is_ok { return assert(false, "even golden frame must parse"); }
  if !ro.is_ok { return assert(false, "odd golden frame must parse"); }
  let fe: AviationFrame = re.value;
  let fo: AviationFrame = ro.value;
  var ok = aviation_frame_tc(&fe) == 11;
  if aviation_frame_tc(&fo) != 11 { ok = false; }
  let pe = aviation_position_decode(&fe);
  let po = aviation_position_decode(&fo);
  if !pe.is_ok { ok = false; } else {
    let p: AviationPosition = pe.value;
    if aviation_position_tc(&p) != 11 { ok = false; }
    if aviation_position_ss(&p) != 0 { ok = false; }
    if aviation_position_saf(&p) != 0 { ok = false; }
    if aviation_position_alt_raw(&p) != 3128 { ok = false; }
    if aviation_position_alt_ft(&p) != 38000 { ok = false; }
    if aviation_position_gnss_m(&p) != -1 { ok = false; }
    if aviation_position_time_flag(&p) != 0 { ok = false; }
    if aviation_position_odd(&p) != 0 { ok = false; }
    if aviation_position_cpr_lat(&p) != 93000 { ok = false; }
    if aviation_position_cpr_lon(&p) != 51372 { ok = false; }
  }
  if !po.is_ok { ok = false; } else {
    let p: AviationPosition = po.value;
    if aviation_position_alt_raw(&p) != 3128 { ok = false; }
    if aviation_position_alt_ft(&p) != 38000 { ok = false; }
    if aviation_position_odd(&p) != 1 { ok = false; }
    if aviation_position_cpr_lat(&p) != 74158 { ok = false; }
    if aviation_position_cpr_lon(&p) != 50194 { ok = false; }
  }
  return assert(ok, "golden airborne position pair: 38000 ft, CPR even/odd fields");
}

fn t12() -> TestResult {
  var rb = Vec[Int].new();
  bits_add(&mut rb, 0, 2);
  bits_add(&mut rb, 0, 1);
  bits_add(&mut rb, 1200, 12);
  bits_add(&mut rb, 1, 1);
  bits_add(&mut rb, 0, 1);
  bits_add(&mut rb, 12345, 17);
  bits_add(&mut rb, 54321, 17);
  let fx = build_long(17, 0, hex_int("A1B2C3"), me_of(20, rb), 0);
  let r = aviation_parse_frame(&fx);
  if !r.is_ok { return assert(false, "synthetic TC20 frame must parse"); }
  let f: AviationFrame = r.value;
  var ok = aviation_frame_tc(&f) == 20;
  let pr = aviation_position_decode(&f);
  if !pr.is_ok { ok = false; } else {
    let p: AviationPosition = pr.value;
    if aviation_position_gnss_m(&p) != 1200 { ok = false; }
    if aviation_position_alt_ft(&p) != -1 { ok = false; }
    if aviation_position_time_flag(&p) != 1 { ok = false; }
    if aviation_position_cpr_lat(&p) != 12345 { ok = false; }
    if aviation_position_cpr_lon(&p) != 54321 { ok = false; }
  }
  let idf = from_hex("8D4840D6202CC371C32CE0576098");
  let ri = aviation_parse_frame(&idf);
  if !ri.is_ok { ok = false; } else {
    let g: AviationFrame = ri.value;
    if !err_position_is(aviation_position_decode(&g), "aviation: not an airborne position message") { ok = false; }
    if !err_surface_is(aviation_surface_decode(&g), "aviation: not a surface position message") { ok = false; }
    if !err_velocity_is(aviation_velocity_decode(&g), "aviation: not an airborne velocity message") { ok = false; }
  }
  let sh = build_short(4, 0, hex_int("0F0F0F"), 0);
  let rs = aviation_parse_frame(&sh);
  if !rs.is_ok { ok = false; } else {
    let h2: AviationFrame = rs.value;
    if !err_position_is(aviation_position_decode(&h2), "aviation: not an extended squitter frame") { ok = false; }
  }
  return assert(ok, "TC20 GNSS position and decoder frame guards");
}

fn t13() -> TestResult {
  let fx = from_hex("8D485020994409940838175B284F");
  let r = aviation_parse_frame(&fx);
  if !r.is_ok { return assert(false, "golden velocity frame must parse"); }
  let f: AviationFrame = r.value;
  var ok = aviation_frame_tc(&f) == 19;
  let vr = aviation_velocity_decode(&f);
  if !vr.is_ok { ok = false; } else {
    let v: AviationVelocity = vr.value;
    if aviation_velocity_tc(&v) != 19 { ok = false; }
    if aviation_velocity_subtype(&v) != 1 { ok = false; }
    if aviation_velocity_ew_sign(&v) != 1 { ok = false; }
    if aviation_velocity_ew_kt(&v) != 8 { ok = false; }
    if aviation_velocity_ns_sign(&v) != 1 { ok = false; }
    if aviation_velocity_ns_kt(&v) != 159 { ok = false; }
    if aviation_velocity_gs_kt(&v) != 159 { ok = false; }
    if aviation_velocity_vr_source(&v) != 0 { ok = false; }
    if aviation_velocity_vr_fpm(&v) != -832 { ok = false; }
    if aviation_velocity_dif_ft(&v) != 550 { ok = false; }
    if aviation_velocity_heading_deg100(&v) != -1 { ok = false; }
    if aviation_velocity_airspeed_kt(&v) != -1 { ok = false; }
  }
  return assert(ok, "golden TC19 subtype 1: 8 kt W, 159 kt S, -832 fpm, +550 ft");
}

fn t14() -> TestResult {
  var rb = Vec[Int].new();
  bits_add(&mut rb, 3, 3);
  bits_add(&mut rb, 0, 1);
  bits_add(&mut rb, 1, 1);
  bits_add(&mut rb, 2, 3);
  bits_add(&mut rb, 1, 1);
  bits_add(&mut rb, 512, 10);
  bits_add(&mut rb, 1, 1);
  bits_add(&mut rb, 251, 10);
  bits_add(&mut rb, 1, 1);
  bits_add(&mut rb, 0, 1);
  bits_add(&mut rb, 33, 9);
  bits_add(&mut rb, 0, 2);
  bits_add(&mut rb, 0, 1);
  bits_add(&mut rb, 0, 7);
  let fx = build_long(17, 0, hex_int("C0FFEE"), me_of(19, rb), 0);
  let r = aviation_parse_frame(&fx);
  if !r.is_ok { return assert(false, "synthetic TC19 subtype 3 frame must parse"); }
  let f: AviationFrame = r.value;
  var ok = aviation_frame_tc(&f) == 19;
  let vr = aviation_velocity_decode(&f);
  if !vr.is_ok { ok = false; } else {
    let v: AviationVelocity = vr.value;
    if aviation_velocity_subtype(&v) != 3 { ok = false; }
    if aviation_velocity_heading_status(&v) != 1 { ok = false; }
    if aviation_velocity_heading_deg100(&v) != 18000 { ok = false; }
    if aviation_velocity_airspeed_type(&v) != 1 { ok = false; }
    if aviation_velocity_airspeed_kt(&v) != 250 { ok = false; }
    if aviation_velocity_ew_kt(&v) != -1 { ok = false; }
    if aviation_velocity_gs_kt(&v) != -1 { ok = false; }
    if aviation_velocity_vr_source(&v) != 1 { ok = false; }
    if aviation_velocity_vr_fpm(&v) != 2048 { ok = false; }
    if aviation_velocity_dif_ft(&v) != -1 { ok = false; }
  }
  var rb2 = Vec[Int].new();
  bits_add(&mut rb2, 1, 3);
  bits_add(&mut rb2, 0, 1);
  bits_add(&mut rb2, 0, 1);
  bits_add(&mut rb2, 0, 3);
  bits_add(&mut rb2, 0, 1);
  bits_add(&mut rb2, 0, 10);
  bits_add(&mut rb2, 0, 1);
  bits_add(&mut rb2, 0, 10);
  bits_add(&mut rb2, 0, 1);
  bits_add(&mut rb2, 1, 1);
  bits_add(&mut rb2, 0, 9);
  bits_add(&mut rb2, 0, 2);
  bits_add(&mut rb2, 1, 1);
  bits_add(&mut rb2, 0, 7);
  let fx2 = build_long(17, 0, hex_int("C0FFEE"), me_of(19, rb2), 0);
  let r2 = aviation_parse_frame(&fx2);
  if !r2.is_ok { ok = false; } else {
    let g: AviationFrame = r2.value;
    let vr2 = aviation_velocity_decode(&g);
    if !vr2.is_ok { ok = false; } else {
      let v2: AviationVelocity = vr2.value;
      if aviation_velocity_ew_kt(&v2) != -1 { ok = false; }
      if aviation_velocity_ns_kt(&v2) != -1 { ok = false; }
      if aviation_velocity_gs_kt(&v2) != -1 { ok = false; }
      if aviation_velocity_vr_fpm(&v2) != -1 { ok = false; }
      if aviation_velocity_dif_ft(&v2) != -1 { ok = false; }
    }
  }
  return assert(ok, "TC19 subtype 3 heading/airspeed and all-zero unknowns");
}

// --------------------------------------------------
//  Part 4: CPR NL table and position decode
// --------------------------------------------------

fn t15() -> TestResult {
  var ok = aviation_cpr_nl(0) == 59;
  if aviation_cpr_nl(1047047) != 59 { ok = false; }
  if aviation_cpr_nl(1047048) != 58 { ok = false; }
  if aviation_cpr_nl(5225720) != 36 { ok = false; }
  if aviation_cpr_nl(5884763) != 31 { ok = false; }
  if aviation_cpr_nl(5884764) != 30 { ok = false; }
  if aviation_cpr_nl(8699999) != 2 { ok = false; }
  if aviation_cpr_nl(8700000) != 1 { ok = false; }
  if aviation_cpr_nl(9000000) != 1 { ok = false; }
  if aviation_cpr_nl(-5225720) != 36 { ok = false; }
  if aviation_cpr_nl(-9000000) != 1 { ok = false; }
  return assert(ok, "CPR NL boundaries 0 / 10.47 / 52.26 / 58.85 / 87 degrees");
}

fn t16() -> TestResult {
  let even = aviation_cpr_pack(93000, 51372);
  let odd = aviation_cpr_pack(74158, 50194);
  var ok = aviation_cpr_pack_lat(even) == 93000;
  if aviation_cpr_pack_lon(even) != 51372 { ok = false; }
  if aviation_cpr_pack(0, 0) != 0 { ok = false; }
  if aviation_cpr_pack(131071, 131071) != 17179869183 { ok = false; }
  let ge = aviation_cpr_decode_global(even, odd, 0);
  if !ge.is_ok { ok = false; } else {
    let f: AviationFix = ge.value;
    if !near(aviation_fix_lat(&f), 5225720, 2) { ok = false; }
    if !near(aviation_fix_lon(&f), 391937, 2) { ok = false; }
    if aviation_fix_nl(&f) != 36 { ok = false; }
    if aviation_fix_odd(&f) != 0 { ok = false; }
  }
  let go = aviation_cpr_decode_global(even, odd, 1);
  if !go.is_ok { ok = false; } else {
    let f2: AviationFix = go.value;
    if !near(aviation_fix_lat(&f2), 5226578, 5) { ok = false; }
    if !near(aviation_fix_lon(&f2), 393891, 5) { ok = false; }
    if aviation_fix_nl(&f2) != 36 { ok = false; }
    if aviation_fix_odd(&f2) != 1 { ok = false; }
  }
  if !err_fix_is(aviation_cpr_decode_global(17179869184, 0, 0), "aviation: cpr field out of range") { ok = false; }
  if !err_fix_is(aviation_cpr_decode_global(0, -1, 0), "aviation: cpr field out of range") { ok = false; }
  return assert(ok, "CPR global decode of the golden pair: 52.2572 N, 3.91937 E");
}

fn t17() -> TestResult {
  let even = aviation_cpr_pack(93000, 51372);
  let odd = aviation_cpr_pack(74158, 50194);
  var ok = true;
  let le = aviation_cpr_decode_local(odd, even, 0, 5220000, 390000);
  if !le.is_ok { ok = false; } else {
    let f: AviationFix = le.value;
    if !near(aviation_fix_lat(&f), 5225720, 2) { ok = false; }
    if !near(aviation_fix_lon(&f), 391937, 2) { ok = false; }
    if aviation_fix_nl(&f) != 36 { ok = false; }
    if aviation_fix_odd(&f) != 0 { ok = false; }
  }
  let lo = aviation_cpr_decode_local(odd, even, 1, 5220000, 390000);
  if !lo.is_ok { ok = false; } else {
    let f2: AviationFix = lo.value;
    if !near(aviation_fix_lat(&f2), 5226578, 5) { ok = false; }
    if !near(aviation_fix_lon(&f2), 393891, 5) { ok = false; }
    if aviation_fix_odd(&f2) != 1 { ok = false; }
  }
  let ls = aviation_cpr_decode_local(odd, even, 0, -5200000, 390000);
  if !ls.is_ok { ok = false; } else {
    let f3: AviationFix = ls.value;
    if !near(aviation_fix_lat(&f3), -4974280, 3) { ok = false; }
    if aviation_fix_lat(&f3) > 0 { ok = false; }
    if aviation_fix_nl(&f3) != 38 { ok = false; }
  }
  if !err_fix_is(aviation_cpr_decode_local(odd, 17179869184, 0, 0, 0), "aviation: cpr field out of range") { ok = false; }
  return assert(ok, "CPR local decode from a northern and a southern reference");
}

// --------------------------------------------------
//  Part 5: target state (TC29) and operational status (TC31)
// --------------------------------------------------

fn t18() -> TestResult {
  var rb = Vec[Int].new();
  bits_add(&mut rb, 1, 2);
  bits_add(&mut rb, 0, 1);
  bits_add(&mut rb, 1000, 11);
  bits_add(&mut rb, 100, 9);
  bits_add(&mut rb, 1, 1);
  bits_add(&mut rb, 256, 9);
  bits_add(&mut rb, 9, 4);
  bits_add(&mut rb, 0, 1);
  bits_add(&mut rb, 2, 2);
  bits_add(&mut rb, 0, 2);
  bits_add(&mut rb, 1, 1);
  bits_add(&mut rb, 0, 1);
  bits_add(&mut rb, 1, 1);
  bits_add(&mut rb, 0, 1);
  bits_add(&mut rb, 1, 1);
  bits_add(&mut rb, 1, 1);
  bits_add(&mut rb, 0, 3);
  let fx = build_long(17, 0, hex_int("A0A0A0"), me_of(29, rb), 0);
  let r = aviation_parse_frame(&fx);
  if !r.is_ok { return assert(false, "synthetic TC29 frame must parse"); }
  let f: AviationFrame = r.value;
  var ok = aviation_frame_tc(&f) == 29;
  let tr = aviation_target_state_decode(&f);
  if !tr.is_ok { ok = false; } else {
    let t: AviationTargetState = tr.value;
    if aviation_target_state_subtype(&t) != 1 { ok = false; }
    if aviation_target_state_alt_raw(&t) != 1000 { ok = false; }
    if aviation_target_state_baro_hpa10(&t) != 8800 { ok = false; }
    if aviation_target_state_heading_status(&t) != 1 { ok = false; }
    if aviation_target_state_heading_deg100(&t) != 18000 { ok = false; }
    if aviation_target_state_nacp(&t) != 9 { ok = false; }
    if aviation_target_state_autopilot(&t) != 1 { ok = false; }
    if aviation_target_state_vnav(&t) != 0 { ok = false; }
    if aviation_target_state_alt_hold(&t) != 1 { ok = false; }
    if aviation_target_state_approach(&t) != 0 { ok = false; }
    if aviation_target_state_tcas(&t) != 1 { ok = false; }
    if aviation_target_state_lnav(&t) != 1 { ok = false; }
  }
  if aviation_baro_hpa10(0) != 8000 { ok = false; }
  if aviation_baro_hpa10(511) != 12088 { ok = false; }
  if aviation_selected_heading_deg100(0) != 0 { ok = false; }
  if aviation_selected_heading_deg100(512) != 36000 { ok = false; }
  var rb2 = Vec[Int].new();
  bits_add(&mut rb2, 2, 2);
  bits_add(&mut rb2, 0, 1);
  bits_add(&mut rb2, 0, 11);
  bits_add(&mut rb2, 0, 9);
  bits_add(&mut rb2, 0, 1);
  bits_add(&mut rb2, 0, 9);
  bits_add(&mut rb2, 0, 4);
  bits_add(&mut rb2, 0, 1);
  bits_add(&mut rb2, 0, 2);
  bits_add(&mut rb2, 0, 2);
  bits_add(&mut rb2, 0, 1);
  bits_add(&mut rb2, 0, 1);
  bits_add(&mut rb2, 0, 1);
  bits_add(&mut rb2, 0, 1);
  bits_add(&mut rb2, 0, 1);
  bits_add(&mut rb2, 0, 1);
  bits_add(&mut rb2, 0, 3);
  let fx2 = build_long(17, 0, hex_int("A0A0A0"), me_of(29, rb2), 0);
  let r2 = aviation_parse_frame(&fx2);
  if !r2.is_ok { ok = false; } else {
    let g: AviationFrame = r2.value;
    if !err_target_is(aviation_target_state_decode(&g), "aviation: unsupported target state subtype") { ok = false; }
  }
  return assert(ok, "TC29 target state: altitude, pressure, heading, mode bits");
}

fn t19() -> TestResult {
  var rb = Vec[Int].new();
  bits_add(&mut rb, 0, 3);
  bits_add(&mut rb, hex_int("1234"), 16);
  bits_add(&mut rb, hex_int("5678"), 16);
  bits_add(&mut rb, 2, 3);
  bits_add(&mut rb, 1, 1);
  bits_add(&mut rb, 9, 4);
  bits_add(&mut rb, 2, 2);
  bits_add(&mut rb, 3, 2);
  bits_add(&mut rb, 0, 1);
  bits_add(&mut rb, 0, 1);
  bits_add(&mut rb, 0, 2);
  let fx = build_long(17, 0, hex_int("B1B1B1"), me_of(31, rb), 0);
  let r = aviation_parse_frame(&fx);
  if !r.is_ok { return assert(false, "synthetic TC31 frame must parse"); }
  let f: AviationFrame = r.value;
  var ok = aviation_frame_tc(&f) == 31;
  let orr = aviation_op_status_decode(&f);
  if !orr.is_ok { ok = false; } else {
    let o: AviationOpStatus = orr.value;
    if aviation_op_status_subtype(&o) != 0 { ok = false; }
    if aviation_op_status_cc(&o) != hex_int("1234") { ok = false; }
    if aviation_op_status_om(&o) != hex_int("5678") { ok = false; }
    if aviation_op_status_version(&o) != 2 { ok = false; }
    if aviation_op_status_nic_a(&o) != 1 { ok = false; }
    if aviation_op_status_nacp(&o) != 9 { ok = false; }
    if aviation_op_status_sil(&o) != 3 { ok = false; }
  }
  var rb2 = Vec[Int].new();
  bits_add(&mut rb2, 1, 3);
  bits_add(&mut rb2, 0, 16);
  bits_add(&mut rb2, 0, 16);
  bits_add(&mut rb2, 0, 3);
  bits_add(&mut rb2, 0, 1);
  bits_add(&mut rb2, 0, 4);
  bits_add(&mut rb2, 0, 2);
  bits_add(&mut rb2, 0, 2);
  bits_add(&mut rb2, 0, 1);
  bits_add(&mut rb2, 0, 1);
  bits_add(&mut rb2, 0, 2);
  let fx2 = build_long(17, 0, hex_int("B1B1B1"), me_of(31, rb2), 0);
  let r2 = aviation_parse_frame(&fx2);
  if !r2.is_ok { ok = false; } else {
    let g: AviationFrame = r2.value;
    if !err_opstatus_is(aviation_op_status_decode(&g), "aviation: unsupported operational status subtype") { ok = false; }
  }
  let fx3 = from_hex("8D40621D58C382D690C8AC2863A7");
  let r3 = aviation_parse_frame(&fx3);
  if !r3.is_ok { ok = false; } else {
    let h2: AviationFrame = r3.value;
    if !err_target_is(aviation_target_state_decode(&h2), "aviation: not a target state message") { ok = false; }
    if !err_opstatus_is(aviation_op_status_decode(&h2), "aviation: not an operational status message") { ok = false; }
  }
  return assert(ok, "TC31 operational status: version, NIC-A, NACp, SIL, subtype guard");
}

fn zeros(n: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  var i = 0;
  while i < n {
    v.push(0);
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Part 6: short-frame shapes and malformed inputs
// --------------------------------------------------

fn t20() -> TestResult {
  let df4 = build_short(4, 0, 6200, hex_int("DEF456"));
  let r4 = aviation_parse_frame(&df4);
  var ok = df4.len() == 7;
  if !r4.is_ok { return assert(false, "synthetic DF4 frame must parse"); }
  let f4: AviationFrame = r4.value;
  if aviation_frame_df(&f4) != 4 { ok = false; }
  if aviation_frame_ca(&f4) != 0 { ok = false; }
  if aviation_frame_icao(&f4) != 6200 { ok = false; }
  if aviation_frame_payload(&f4) != -1 { ok = false; }
  if aviation_frame_tc(&f4) != -1 { ok = false; }
  if aviation_frame_bits(&f4) != 56 { ok = false; }
  if aviation_frame_bytes(&f4) != 7 { ok = false; }
  if aviation_frame_consumed(&f4) != 7 { ok = false; }
  if aviation_frame_parity(&f4) != hex_int("DEF456") { ok = false; }
  let ac = aviation_bits(&df4, 19, 13);
  if !ac.is_ok { ok = false; } else {
    if ac.value != 6200 { ok = false; }
    let a = aviation_ac13_altitude_ft(ac.value);
    if !a.is_ok { ok = false; } else { if a.value != 38000 { ok = false; } }
  }
  let df11 = build_short(11, 5, hex_int("4840D6"), hex_int("ABC123"));
  let r11 = aviation_parse_frame(&df11);
  if !r11.is_ok { ok = false; } else {
    let f11: AviationFrame = r11.value;
    if aviation_frame_df(&f11) != 11 { ok = false; }
    if aviation_frame_ca(&f11) != 5 { ok = false; }
    if aviation_frame_icao(&f11) != hex_int("4840D6") { ok = false; }
    if aviation_frame_parity(&f11) != hex_int("ABC123") { ok = false; }
    if aviation_frame_payload(&f11) != -1 { ok = false; }
  }
  let df24 = build_long(24, 0, hex_int("111111"), zeros(56), hex_int("222222"));
  let r24 = aviation_parse_frame(&df24);
  if !r24.is_ok { ok = false; } else {
    let f24: AviationFrame = r24.value;
    if aviation_frame_df(&f24) != 24 { ok = false; }
    if aviation_frame_bits(&f24) != 112 { ok = false; }
    if aviation_frame_payload(&f24) != 0 { ok = false; }
    if aviation_frame_parity(&f24) != hex_int("222222") { ok = false; }
  }
  return assert(ok, "DF4/DF11/DF24 shapes: AC13 field, raw parity, no ME for short");
}

fn t21() -> TestResult {
  var empty = Vec[UInt8].new();
  var ok = err_frame_is(aviation_parse_frame(&empty), "aviation: truncated frame");
  let fx = from_hex("8D40621D58C382D690C8AC2863A7");
  let p6 = prefix(fx, 6);
  if !err_frame_is(aviation_parse_frame(&p6), "aviation: truncated frame") { ok = false; }
  let p13 = prefix(fx, 13);
  if !err_frame_is(aviation_parse_frame(&p13), "aviation: truncated frame") { ok = false; }
  let short17 = build_short(17, 5, 0, 0);
  if !err_frame_is(aviation_parse_frame(&short17), "aviation: truncated frame") { ok = false; }
  let df1 = build_short(1, 0, 0, 0);
  if !err_frame_is(aviation_parse_frame(&df1), "aviation: unknown df") { ok = false; }
  let df25 = build_short(25, 0, 0, 0);
  if !err_frame_is(aviation_parse_frame(&df25), "aviation: unknown df") { ok = false; }
  let df31 = build_long(31, 0, 0, zeros(56), 0);
  if !err_frame_is(aviation_parse_frame(&df31), "aviation: unknown df") { ok = false; }
  let df6 = from_hex("30000000000000");
  if !err_frame_is(aviation_parse_frame(&df6), "aviation: unknown df") { ok = false; }
  return assert(ok, "truncated frames and reserved DF values are rejected");
}

fn main() -> Int {
  io.println("=== xiom.aviation conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.aviation: all tests passed");
  } else {
    io.println("xiom.aviation: tests failed");
  }
  return failed;
}
