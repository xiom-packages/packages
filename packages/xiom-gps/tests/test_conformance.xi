// XIOM -- xiom.gps conformance tests.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage:
//   * every recorded gpsd JSON line in tests/fixtures/gpsd-json-upstream.jsonl
//     parses and dispatches (VERSION, DEVICES, WATCH, TPV, SKY, ERROR);
//   * typed field values pinned against the upstream recordings (daemon
//     output captured in the gpsd regression suite);
//   * error paths: malformed JSON, wrong class, missing required fields,
//     trailing bytes after a value;
//   * NMEA checksum validation (well-formed, mismatch, non-hex, truncated,
//     trailing bytes, case-insensitive hex) and the GGA/RMC/GSA/GSV parsers
//     pinned against upstream sentence recordings, plus crafted sentences
//     for the upstream value rules (magvar 0.0,E, DOP sentinel gates,
//     GSV both-or-neither el/az, az 360 -> 0);
//   * the client SKIP classification: with no gpsd daemon on this host,
//     gpsd_client_open("127.0.0.1", 2947) reports GPS_ERR_ABSENT (SKIP).
//
// Compiler discipline on v0.64.5 (see AUDIT.md "v0.64.5 traps", all
// reproduced with scratch probes): Option-typed struct fields are passed
// to helper functions straight off the field expression and are never
// hoisted into locals; helper results are bound to Bool locals before
// negation.

module gps_tests

use xiom.io;
use xiom.convert;
use xiom.string;
use xiom.string.compare;
use xiom.string.split;
use xiom.gps;

const JSON_FIXTURE: Str = "tests/fixtures/gpsd-json-upstream.jsonl";
const NMEA_FIXTURE: Str = "tests/fixtures/nmea-upstream.log";

// ---------------------------------------------------------------------------
// Harness helpers
// ---------------------------------------------------------------------------

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn flt_ok(v: Float64, want: Float64, eps: Float64) -> Bool {
  var d = v - want;
  if d < 0.0 { d = -d; }
  return d <= eps;
}

fn opt_f_eq(o: Option[Float64], want: Float64, eps: Float64) -> Bool {
  let some = o.is_some;
  if !some { return false; }
  let v = o.value;
  return flt_ok(v, want, eps);
}

fn opt_f_absent(o: Option[Float64]) -> Bool {
  let some = o.is_some;
  return !some;
}

fn opt_i_eq(o: Option[Int], want: Int) -> Bool {
  let some = o.is_some;
  if !some { return false; }
  let v = o.value;
  return v == want;
}

fn opt_i_absent(o: Option[Int]) -> Bool {
  let some = o.is_some;
  return !some;
}

fn opt_s_eq(o: Option[Str], want: Str) -> Bool {
  let some = o.is_some;
  if !some { return false; }
  let v: Str = o.value;
  return streq(v, want);
}

fn opt_s_absent(o: Option[Str]) -> Bool {
  let some = o.is_some;
  return !some;
}

fn opt_b_eq(o: Option[Bool], want: Bool) -> Bool {
  let some = o.is_some;
  if !some { return false; }
  let v = o.value;
  return v == want;
}

fn err_has(msg: Str, frag: Str) -> Bool {
  return string.str_contains(msg, frag);
}

fn res_msg_has(r: Result[JsonValue, Str], frag: Str) -> Bool {
  let ok = r.is_ok;
  if ok { return false; }
  let m: Str = r.error;
  return err_has(m, frag);
}

// Build a hex char for a value 0..15.
fn hex_char(v: Int) -> Str {
  if v < 10 { return string.str_slice("0123456789", v, v + 1); }
  return string.str_slice("ABCDEF", v - 10, v - 9);
}

fn hex2(n: Int) -> Str {
  return hex_char(n / 16) + hex_char(n % 16);
}

// XOR of the bytes between '$' and '*' for a sentence body.
fn xor_body(body: Str) -> Int {
  var x = 0;
  var i = 0;
  while i < body.len() {
    x = x ^ ((string.byte_at(body, i) as Int) & 0xFF);
    i = i + 1;
  }
  return x;
}

// Craft a checksummed sentence from a body like "GPRMC,123519,A,...".
fn mk_sentence(body: Str) -> Str {
  return "$" + body + "*" + hex2(xor_body(body));
}

// ---------------------------------------------------------------------------
// Recorded lines (upstream gpsd captures; see tests/fixtures/ headers)
// ---------------------------------------------------------------------------

fn tpv_line_rec() -> Str {
  return "{\"class\":\"TPV\",\"status\":2,\"mode\":3,\"time\":\"2020-03-18T13:28:20.600Z\",\"ept\":0.005,\"lat\":41.574970205,\"lon\":-93.750558641,\"altHAE\":246.5780,\"altMSL\":278.0200,\"alt\":278.0200,\"track\":92.3080,\"magtrack\":103.9065,\"magvar\":11.6,\"speed\":1.673,\"geoidSep\":-31.442,\"eph\":4.750,\"dgpsAge\":7.6,\"dgpsSta\":133}";
}

fn tpv_nofix_line_rec() -> Str {
  return "{\"class\":\"TPV\",\"status\":2,\"mode\":3,\"lat\":41.574970205,\"lon\":-93.750558641,\"altHAE\":246.5780,\"altMSL\":278.0200,\"alt\":278.0200,\"magvar\":0.7,\"geoidSep\":-31.442,\"eph\":4.750,\"dgpsAge\":7.6,\"dgpsSta\":133}";
}

fn sky_big_line_rec() -> Str {
  return "{\"class\":\"SKY\",\"gdop\":2.70,\"hdop\":0.54,\"pdop\":0.99,\"tdop\":1.37,\"xdop\":0.66,\"ydop\":0.84,\"vdop\":0.83,\"nSat\":16,\"uSat\":8,\"satellites\":[{\"PRN\":5,\"gnssid\":0,\"svid\":5,\"az\":47.0,\"el\":1.0,\"used\":false},{\"PRN\":10,\"gnssid\":0,\"svid\":10,\"az\":224.0,\"el\":29.0,\"used\":false},{\"PRN\":13,\"gnssid\":0,\"svid\":13,\"az\":62.0,\"el\":22.0,\"ss\":23.0,\"used\":true},{\"PRN\":15,\"gnssid\":0,\"svid\":15,\"az\":94.0,\"el\":40.0,\"used\":false},{\"PRN\":16,\"gnssid\":0,\"svid\":16,\"az\":306.0,\"el\":25.0,\"ss\":30.0,\"used\":true},{\"PRN\":18,\"gnssid\":0,\"svid\":18,\"az\":358.0,\"el\":68.0,\"ss\":39.0,\"used\":true},{\"PRN\":20,\"gnssid\":0,\"svid\":20,\"az\":235.0,\"el\":63.0,\"ss\":37.0,\"used\":true},{\"PRN\":21,\"gnssid\":0,\"svid\":21,\"az\":292.0,\"el\":35.0,\"used\":false},{\"PRN\":23,\"gnssid\":0,\"svid\":23,\"az\":225.0,\"el\":58.0,\"used\":false},{\"PRN\":25,\"gnssid\":0,\"svid\":25,\"az\":179.0,\"el\":0.0,\"used\":false},{\"PRN\":26,\"gnssid\":0,\"svid\":26,\"az\":265.0,\"el\":33.0,\"ss\":35.0,\"used\":true},{\"PRN\":27,\"gnssid\":0,\"svid\":27,\"az\":316.0,\"el\":7.0,\"used\":false},{\"PRN\":29,\"gnssid\":0,\"svid\":29,\"az\":133.0,\"el\":46.0,\"ss\":43.0,\"used\":true},{\"PRN\":44,\"gnssid\":1,\"svid\":131,\"az\":171.0,\"el\":45.0,\"ss\":45.0,\"used\":true},{\"PRN\":46,\"gnssid\":1,\"svid\":133,\"az\":191.0,\"el\":45.0,\"ss\":43.0,\"used\":false},{\"PRN\":51,\"gnssid\":1,\"svid\":138,\"az\":156.0,\"el\":43.0,\"ss\":43.0,\"used\":true}]}";
}

fn gga_line_rec() -> Str {
  return "$GPGGA,132820.60,4134.49821229,N,09345.03351845,W,2,09,1.0,278.020,M,-31.442,M,7.6,0133*7E";
}

fn rmc_line_rec() -> Str {
  return "$GPRMC,132820.60,A,4134.49821229,N,09345.03351845,W,3.252,92.308,180320,11.5985,E,D*1A";
}

fn gsa_line_rec() -> Str {
  return "$GNGSA,A,3,02,07,14,15,17,20,22,30,,,,,1.5,0.9,1.2,1*3C";
}

fn gsv_line_rec() -> Str {
  return "$GPGSV,3,1,12,01,17,083,03,02,20,056,27,07,18,123,25,08,,,15,0*58";
}

// ---------------------------------------------------------------------------
// Fixture sweeps
// ---------------------------------------------------------------------------

fn test_json_fixture_sweep() -> Int {
  let fr = io.read_file(JSON_FIXTURE);
  let have = fr.is_ok;
  if !have {
    let fe: Str = fr.error;
    return report(false, "json-fixture: cannot read " + JSON_FIXTURE + " (" + fe + ")");
  }
  let text: Str = fr.value;
  let lines = string.lines(text);
  var n = 0;
  var ok = true;
  var i = 0;
  while i < lines.len() {
    let ln: Str = lines[i];
    if ln.len() > 0 {
      let c0 = (string.byte_at(ln, 0) as Int) & 0xFF;
      if c0 != 35 {
        let r = gpsd_parse_line(ln);
        let rok = r.is_ok;
        if !rok { ok = false; }
        n = n + 1;
      }
    }
    i = i + 1;
  }
  if n < 8 { ok = false; }
  return report(ok, "json-fixture: " + to_string(n) + " recorded daemon lines parse and dispatch");
}

fn test_nmea_fixture_sweep() -> Int {
  let fr = io.read_file(NMEA_FIXTURE);
  let have = fr.is_ok;
  if !have {
    let fe: Str = fr.error;
    return report(false, "nmea-fixture: cannot read " + NMEA_FIXTURE + " (" + fe + ")");
  }
  let text: Str = fr.value;
  let lines = string.lines(text);
  var n = 0;
  var ok = true;
  var i = 0;
  while i < lines.len() {
    let ln: Str = lines[i];
    if ln.len() > 0 {
      let c0 = (string.byte_at(ln, 0) as Int) & 0xFF;
      if c0 == 36 {
        let cv = nmea_checksum_valid(ln);
        if !cv { ok = false; }
        let r = nmea_parse_line(ln);
        let rok = r.is_ok;
        if !rok { ok = false; }
        n = n + 1;
      }
    }
    i = i + 1;
  }
  if n != 12 { ok = false; }
  return report(ok, "nmea-fixture: " + to_string(n) + " recorded sentences checksum + parse");
}

// ---------------------------------------------------------------------------
// gpsd TPV
// ---------------------------------------------------------------------------

fn test_tpv_values() -> Int {
  let r = gpsd_parse_tpv(tpv_line_rec());
  let rok = r.is_ok;
  if !rok {
    let re: Str = r.error;
    return report(false, "tpv: recorded line parses (" + re + ")");
  }
  let t: GpsTpv = r.value;
  var ok = true;
  let mode_ok = t.mode == 3;
  if !mode_ok { ok = false; }
  let c1 = opt_i_eq(t.status, 2);
  if !c1 { ok = false; }
  let c2 = opt_s_eq(t.time, "2020-03-18T13:28:20.600Z");
  if !c2 { ok = false; }
  let c3 = opt_s_absent(t.device);
  if !c3 { ok = false; }
  let f1 = opt_f_eq(t.lat, 41.574970205, 0.000001);
  if !f1 { ok = false; }
  let f2 = opt_f_eq(t.lon, -93.750558641, 0.000001);
  if !f2 { ok = false; }
  let f3 = opt_f_eq(t.alt_hae, 246.578, 0.0001);
  if !f3 { ok = false; }
  let f4 = opt_f_eq(t.alt_msl, 278.020, 0.0001);
  if !f4 { ok = false; }
  let f5 = opt_f_eq(t.speed, 1.673, 0.0001);
  if !f5 { ok = false; }
  let f6 = opt_f_eq(t.track, 92.308, 0.0001);
  if !f6 { ok = false; }
  let z1 = opt_f_absent(t.climb);
  if !z1 { ok = false; }
  let f7 = opt_f_eq(t.ept, 0.005, 0.0001);
  if !f7 { ok = false; }
  let f8 = opt_f_eq(t.eph, 4.750, 0.0001);
  if !f8 { ok = false; }
  let z2 = opt_f_absent(t.epv);
  if !z2 { ok = false; }
  let f9 = opt_f_eq(t.geoid_sep, -31.442, 0.0001);
  if !f9 { ok = false; }
  let f10 = opt_f_eq(t.magvar, 11.6, 0.0001);
  if !f10 { ok = false; }
  let f11 = opt_f_eq(t.dgps_age, 7.6, 0.0001);
  if !f11 { ok = false; }
  let d1 = opt_i_eq(t.dgps_sta, 133);
  if !d1 { ok = false; }
  let z3 = opt_i_absent(t.leapseconds);
  if !z3 { ok = false; }
  return report(ok, "tpv: recorded values pinned (mode/status/time/lat/lon/alt/eph/dgps)");
}

fn test_tpv_optional_absence() -> Int {
  let r = gpsd_parse_tpv(tpv_nofix_line_rec());
  let rok = r.is_ok;
  if !rok {
    let re: Str = r.error;
    return report(false, "tpv-options: recorded line parses (" + re + ")");
  }
  let t: GpsTpv = r.value;
  var ok = true;
  let a1 = opt_s_absent(t.time);
  if !a1 { ok = false; }
  let a2 = opt_f_absent(t.speed);
  if !a2 { ok = false; }
  let a3 = opt_f_absent(t.track);
  if !a3 { ok = false; }
  let a4 = opt_f_absent(t.ept);
  if !a4 { ok = false; }
  let f1 = opt_f_eq(t.lat, 41.574970205, 0.000001);
  if !f1 { ok = false; }
  return report(ok, "tpv-options: absent attributes decode to None");
}

fn test_tpv_errors() -> Int {
  var ok = true;
  let r1 = gpsd_parse_tpv("{\"class\":\"TPV\"}");
  let r1ok = r1.is_ok;
  if r1ok { ok = false; } else {
    let e: Str = r1.error;
    if !err_has(e, "missing mode") { ok = false; }
  }
  let r2 = gpsd_parse_tpv("{\"class\":\"SKY\",\"hdop\":1.0}");
  let r2ok = r2.is_ok;
  if r2ok { ok = false; } else {
    let e2: Str = r2.error;
    if !err_has(e2, "expected class TPV") { ok = false; }
  }
  let r3 = gpsd_parse_tpv("{\"class\":\"TPV\",");
  let r3ok = r3.is_ok;
  if r3ok { ok = false; }
  let r4 = gpsd_parse_tpv("42");
  let r4ok = r4.is_ok;
  if r4ok { ok = false; }
  let r5 = gpsd_parse_tpv("");
  let r5ok = r5.is_ok;
  if r5ok { ok = false; } else {
    let e5: Str = r5.error;
    if !err_has(e5, "empty") { ok = false; }
  }
  return report(ok, "tpv-errors: missing mode / wrong class / truncated / non-object / empty");
}

// ---------------------------------------------------------------------------
// gpsd SKY
// ---------------------------------------------------------------------------

fn test_sky_values() -> Int {
  let r = gpsd_parse_sky(sky_big_line_rec());
  let rok = r.is_ok;
  if !rok {
    let re: Str = r.error;
    return report(false, "sky: recorded line parses (" + re + ")");
  }
  let s: GpsSky = r.value;
  var ok = true;
  let c1 = opt_f_eq(s.gdop, 2.70, 0.0001);
  if !c1 { ok = false; }
  let c2 = opt_f_eq(s.hdop, 0.54, 0.0001);
  if !c2 { ok = false; }
  let c3 = opt_f_eq(s.pdop, 0.99, 0.0001);
  if !c3 { ok = false; }
  let c4 = opt_f_eq(s.tdop, 1.37, 0.0001);
  if !c4 { ok = false; }
  let c5 = opt_f_eq(s.xdop, 0.66, 0.0001);
  if !c5 { ok = false; }
  let c6 = opt_f_eq(s.ydop, 0.84, 0.0001);
  if !c6 { ok = false; }
  let c7 = opt_f_eq(s.vdop, 0.83, 0.0001);
  if !c7 { ok = false; }
  let c8 = opt_i_eq(s.n_sat, 16);
  if !c8 { ok = false; }
  let c9 = opt_i_eq(s.u_sat, 8);
  if !c9 { ok = false; }
  let n = s.satellites.len();
  let n_ok = n == 16;
  if !n_ok { ok = false; }
  if n == 16 {
    let s0_ok = opt_i_eq(s.satellites[0].gnssid, 0);
    if !s0_ok { ok = false; }
    let s0_prn = s.satellites[0].prn == 5;
    if !s0_prn { ok = false; }
    let s0_used = s.satellites[0].used == false;
    if !s0_used { ok = false; }
    let s0_svid = opt_i_eq(s.satellites[0].svid, 5);
    if !s0_svid { ok = false; }
    let s0_az = opt_f_eq(s.satellites[0].az, 47.0, 0.0001);
    if !s0_az { ok = false; }
    let s0_el = opt_f_eq(s.satellites[0].el, 1.0, 0.0001);
    if !s0_el { ok = false; }
    let s0_ss = opt_f_absent(s.satellites[0].ss);
    if !s0_ss { ok = false; }
    let s13_prn = s.satellites[13].prn == 44;
    if !s13_prn { ok = false; }
    let s13_used = s.satellites[13].used == true;
    if !s13_used { ok = false; }
    let s13_gnssid = opt_i_eq(s.satellites[13].gnssid, 1);
    if !s13_gnssid { ok = false; }
    let s13_svid = opt_i_eq(s.satellites[13].svid, 131);
    if !s13_svid { ok = false; }
    let s13_ss = opt_f_eq(s.satellites[13].ss, 45.0, 0.0001);
    if !s13_ss { ok = false; }
    let s15_prn = s.satellites[15].prn == 51;
    if !s15_prn { ok = false; }
    let s15_az = opt_f_eq(s.satellites[15].az, 156.0, 0.0001);
    if !s15_az { ok = false; }
  }
  return report(ok, "sky: recorded 16-satellite skyview pinned (DOPs + entry fields)");
}

fn test_sky_minimal_and_errors() -> Int {
  var ok = true;
  let r = gpsd_parse_sky("{\"class\":\"SKY\",\"hdop\":1.00,\"uSat\":9}");
  let rok = r.is_ok;
  if !rok { ok = false; } else {
    let s: GpsSky = r.value;
    let c1 = opt_f_eq(s.hdop, 1.00, 0.0001);
    if !c1 { ok = false; }
    let c2 = opt_i_eq(s.u_sat, 9);
    if !c2 { ok = false; }
    let n = s.satellites.len();
    let n_ok = n == 0;
    if !n_ok { ok = false; }
  }
  let r2 = gpsd_parse_sky("{\"class\":\"SKY\",\"satellites\":[{\"PRN\":5}]}");
  let r2ok = r2.is_ok;
  if r2ok { ok = false; } else {
    let e2: Str = r2.error;
    if !err_has(e2, "missing used") { ok = false; }
  }
  let r3 = gpsd_parse_sky("{\"class\":\"SKY\",\"satellites\":42}");
  let r3ok = r3.is_ok;
  if r3ok { ok = false; } else {
    let e3: Str = r3.error;
    if !err_has(e3, "not an array") { ok = false; }
  }
  return report(ok, "sky-errors: minimal SKY, satellite missing used, satellites not an array");
}

// ---------------------------------------------------------------------------
// gpsd VERSION / DEVICES / WATCH / ERROR / dispatch
// ---------------------------------------------------------------------------

fn test_version() -> Int {
  let line = "{\"class\":\"VERSION\",\"release\":\"3.23.1~dev\",\"rev\":\"release-3.23-3-g10de777bb\",\"proto_major\":3,\"proto_minor\":14}";
  let r = gpsd_parse_version(line);
  let rok = r.is_ok;
  if !rok {
    let re: Str = r.error;
    return report(false, "version: recorded line parses (" + re + ")");
  }
  let v: GpsVersion = r.value;
  var ok = true;
  let release: Str = v.release;
  if !streq(release, "3.23.1~dev") { ok = false; }
  let c1 = opt_s_eq(v.rev, "release-3.23-3-g10de777bb");
  if !c1 { ok = false; }
  let pm = v.proto_major == 3;
  if !pm { ok = false; }
  let pn = v.proto_minor == 14;
  if !pn { ok = false; }
  let c2 = opt_s_absent(v.remote);
  if !c2 { ok = false; }
  // legacy "version" spelling from the manual example
  let r2 = gpsd_parse_version("{\"class\":\"VERSION\",\"version\":\"2.40dev\",\"rev\":\"06f62e14\",\"proto_major\":3,\"proto_minor\":1}");
  let r2ok = r2.is_ok;
  if !r2ok { ok = false; } else {
    let v2: GpsVersion = r2.value;
    let rel2: Str = v2.release;
    if !streq(rel2, "2.40dev") { ok = false; }
  }
  let r3 = gpsd_parse_version("{\"class\":\"VERSION\",\"proto_major\":3,\"proto_minor\":14}");
  let r3ok = r3.is_ok;
  if r3ok { ok = false; }
  return report(ok, "version: recorded + legacy spellings; release required");
}

fn test_proto_compatible() -> Int {
  var ok = true;
  if !gpsd_proto_compatible(3, 15) { ok = false; }
  if !gpsd_proto_compatible(3, 99) { ok = false; }
  if gpsd_proto_compatible(3, 14) { ok = false; }
  if gpsd_proto_compatible(4, 15) { ok = false; }
  if gpsd_proto_compatible(2, 15) { ok = false; }
  if GPSD_PROTO_MAJOR != 3 { ok = false; }
  if GPSD_PROTO_MINOR != 15 { ok = false; }
  return report(ok, "proto: cgps compatibility rule (major equal, daemon minor >= 15)");
}

fn test_devices() -> Int {
  let line = "{\"class\":\"DEVICES\",\"devices\":[{\"class\":\"DEVICE\",\"path\":\"/dev/gps0\",\"driver\":\"NMEA0183\",\"activated\":\"2021-08-12T01:22:37.048Z\",\"flags\":1,\"native\":0,\"bps\":115200,\"parity\":\"N\",\"stopbits\":1,\"cycle\":1.00}]}";
  let r = gpsd_parse_devices(line);
  let rok = r.is_ok;
  if !rok {
    let re: Str = r.error;
    return report(false, "devices: recorded line parses (" + re + ")");
  }
  let d: GpsDevices = r.value;
  var ok = true;
  let n = d.devices.len();
  let n_ok = n == 1;
  if !n_ok { ok = false; }
  let rem = opt_s_absent(d.remote);
  if !rem { ok = false; }
  if n == 1 {
    let d0: GpsDevice = d.devices[0];
    let path_ok = opt_s_eq(d0.path, "/dev/gps0");
    if !path_ok { ok = false; }
    let drv_ok = opt_s_eq(d0.driver, "NMEA0183");
    if !drv_ok { ok = false; }
    let act_ok = opt_s_eq(d0.activated, "2021-08-12T01:22:37.048Z");
    if !act_ok { ok = false; }
    let actn = opt_f_absent(d0.activated_num);
    if !actn { ok = false; }
    let fl_ok = opt_i_eq(d0.flags, 1);
    if !fl_ok { ok = false; }
    let nat_ok = opt_i_eq(d0.native, 0);
    if !nat_ok { ok = false; }
    let bps_ok = opt_i_eq(d0.bps, 115200);
    if !bps_ok { ok = false; }
    let par_ok = opt_s_eq(d0.parity, "N");
    if !par_ok { ok = false; }
    let stb_ok = opt_i_eq(d0.stopbits, 1);
    if !stb_ok { ok = false; }
    let cyc_ok = opt_f_eq(d0.cycle, 1.00, 0.0001);
    if !cyc_ok { ok = false; }
    let ser = opt_s_absent(d0.sernum);
    if !ser { ok = false; }
  }
  // legacy numeric activation stamp (multipacket.log capture form)
  let r2 = gpsd_parse_device("{\"class\":\"DEVICE\",\"path\":\"/dev/pts1\",\"activated\":0}");
  let r2ok = r2.is_ok;
  if !r2ok { ok = false; } else {
    let dev2: GpsDevice = r2.value;
    let a1 = opt_s_absent(dev2.activated);
    if !a1 { ok = false; }
    let a2 = opt_f_eq(dev2.activated_num, 0.0, 0.0001);
    if !a2 { ok = false; }
  }
  let r3 = gpsd_parse_devices("{\"class\":\"DEVICES\"}");
  let r3ok = r3.is_ok;
  if r3ok { ok = false; }
  return report(ok, "devices: recorded fleet + legacy numeric activated + missing list error");
}

fn test_watch() -> Int {
  let line = "{\"class\":\"WATCH\",\"enable\":true,\"json\":false,\"nmea\":false,\"raw\":2,\"scaled\":false,\"timing\":false,\"split24\":false,\"pps\":false}";
  let r = gpsd_parse_watch(line);
  let rok = r.is_ok;
  if !rok {
    let re: Str = r.error;
    return report(false, "watch: recorded line parses (" + re + ")");
  }
  let w: GpsWatch = r.value;
  var ok = true;
  let e1 = opt_b_eq(w.enable, true);
  if !e1 { ok = false; }
  let e2 = opt_b_eq(w.json, false);
  if !e2 { ok = false; }
  let e3 = opt_b_eq(w.nmea, false);
  if !e3 { ok = false; }
  let e4 = opt_i_eq(w.raw, 2);
  if !e4 { ok = false; }
  let e5 = opt_b_eq(w.scaled, false);
  if !e5 { ok = false; }
  let e6 = opt_b_eq(w.timing, false);
  if !e6 { ok = false; }
  let e7 = opt_b_eq(w.split24, false);
  if !e7 { ok = false; }
  let e8 = opt_b_eq(w.pps, false);
  if !e8 { ok = false; }
  let e9 = opt_s_absent(w.device);
  if !e9 { ok = false; }
  let e10 = opt_s_absent(w.remote);
  if !e10 { ok = false; }
  return report(ok, "watch: recorded policy response pinned");
}

fn test_error_msg_and_dispatch() -> Int {
  var ok = true;
  let er = gpsd_parse_error("{\"class\":\"ERROR\",\"message\":\"Unrecognized request '?FOO'\"}");
  let erok = er.is_ok;
  if !erok { ok = false; } else {
    let em: GpsErrorMsg = er.value;
    let msg: Str = em.message;
    if !streq(msg, "Unrecognized request '?FOO'") { ok = false; }
  }
  // dispatch returns the declared variants
  let m1 = gpsd_parse_line(tpv_line_rec());
  let m1ok = m1.is_ok;
  if !m1ok { ok = false; } else {
    let mv: GpsMessage = m1.value;
    match mv {
      GpsMessage.Tpv(t) => {
        let mode_ok = t.mode == 3;
        if !mode_ok { ok = false; }
      },
      _ => { ok = false; },
    }
  }
  let m2 = gpsd_parse_line("{\"class\":\"GST\",\"rms\":2.440}");
  let m2ok = m2.is_ok;
  if !m2ok { ok = false; } else {
    let mv2: GpsMessage = m2.value;
    match mv2 {
      GpsMessage.Other(c) => {
        if !streq(c, "GST") { ok = false; }
      },
      _ => { ok = false; },
    }
  }
  // a concatenated multipacket line is invalid JSON for a line parser
  let multi = "{\"class\":\"VERSION\",\"release\":\"2.90dev\",\"rev\":\"svn6614\",\"proto_major\":3,\"proto_minor\":1}{\"class\":\"WATCH\"}";
  let m3 = gpsd_parse_line(multi);
  let m3ok = m3.is_ok;
  if m3ok { ok = false; }
  let cr = gpsd_message_class(tpv_line_rec());
  let crok = cr.is_ok;
  if !crok { ok = false; } else {
    let cls: Str = cr.value;
    if !streq(cls, "TPV") { ok = false; }
  }
  let cr2 = gpsd_message_class("{\"class\":\"POLL\"}");
  let cr2ok = cr2.is_ok;
  if !cr2ok { ok = false; } else {
    let cls2: Str = cr2.value;
    if !streq(cls2, "POLL") { ok = false; }
  }
  return report(ok, "dispatch: variants, Other class, concatenated line rejected, class peek");
}

fn test_commands() -> Int {
  var ok = true;
  let c1 = gpsd_watch_command(true);
  if !streq(c1, "?WATCH={\"enable\":true,\"json\":true};") { ok = false; }
  let c2 = gpsd_watch_command(false);
  if !streq(c2, "?WATCH={\"enable\":false,\"json\":false};") { ok = false; }
  let c3 = gpsd_version_command();
  if !streq(c3, "?VERSION;") { ok = false; }
  return report(ok, "commands: ?WATCH / ?VERSION request lines byte-exact");
}

// ---------------------------------------------------------------------------
// gpsd client (SKIP leg; no daemon on this host)
// ---------------------------------------------------------------------------

fn test_client_skip_path() -> Int {
  // No local gpsd: a connection attempt must classify as GPS_ERR_ABSENT
  // (SKIP), never crash or hang. If a daemon IS present the path is
  // exercised live and closed cleanly.
  let r = gpsd_client_open("127.0.0.1", 2947, 150);
  let rok = r.is_ok;
  if !rok {
    let e: GpsError = r.error;
    let kind = e.kind;
    let msg: Str = e.message;
    if kind != GPS_ERR_ABSENT {
      return report(false, "client-skip: non-absent failure: " + msg);
    }
    if !err_has(msg, "gps:") { return report(false, "client-skip: message prefix"); }
    return report(true, "client-skip: SKIP -- no gpsd on 127.0.0.1:2947 (" + msg + ")");
  }
  var c: GpsClient = r.value;
  let wr = gpsd_client_watch(&mut c, true);
  let cr = gpsd_client_close(&mut c);
  let wrok = wr.is_ok;
  let crok = cr.is_ok;
  let ok = wrok && crok;
  return report(ok, "client-skip: live gpsd present -- watch sent and closed cleanly");
}

fn test_client_argument_and_closed_errors() -> Int {
  var ok = true;
  let r1 = gpsd_client_open("127.0.0.1", 0, 100);
  let r1ok = r1.is_ok;
  if r1ok { ok = false; } else {
    let e1: GpsError = r1.error;
    let k1 = e1.kind;
    if k1 != GPS_ERR_IO { ok = false; }
  }
  let r2 = gpsd_client_open("127.0.0.1", 2947, -1);
  let r2ok = r2.is_ok;
  if r2ok { ok = false; } else {
    let e2: GpsError = r2.error;
    let k2 = e2.kind;
    if k2 != GPS_ERR_IO { ok = false; }
  }
  // A closed client refuses send/read and close is idempotent.
  var c = GpsClient{
    fd: -1;
    host: "127.0.0.1";
    port: 2947;
    timeout_ms: 100;
    buf: Vec[UInt8].new();
  };
  let s1 = gpsd_client_send(&mut c, "?VERSION;");
  let s1ok = s1.is_ok;
  if s1ok { ok = false; } else {
    let se: GpsError = s1.error;
    let sk = se.kind;
    if sk != GPS_ERR_IO { ok = false; }
  }
  let l1 = gpsd_client_read_line(&mut c);
  let l1ok = l1.is_ok;
  if l1ok { ok = false; } else {
    let le: GpsError = l1.error;
    let lk = le.kind;
    if lk != GPS_ERR_IO { ok = false; }
  }
  let cl1 = gpsd_client_close(&mut c);
  let cl2 = gpsd_client_close(&mut c);
  let c1ok = cl1.is_ok;
  let c2ok = cl2.is_ok;
  if !c1ok || !c2ok { ok = false; }
  return report(ok, "client-errors: bad port/timeout, closed client refuses I/O, double close OK");
}

// ---------------------------------------------------------------------------
// NMEA -- checksum
// ---------------------------------------------------------------------------

fn test_checksum() -> Int {
  var ok = true;
  let cv = nmea_checksum(gga_line_rec());
  let cvok = cv.is_ok;
  if !cvok { ok = false; } else {
    let v = cv.value;
    let v_ok = v == 0x7E;
    if !v_ok { ok = false; }
  }
  // lowercase hex accepted; trailing bytes after the checksum ignored
  if !nmea_checksum_valid("$GPGGA,132820.60,4134.49821229,N,09345.03351845,W,2,09,1.0,278.020,M,-31.442,M,7.6,0133*7e") { ok = false; }
  if !nmea_checksum_valid(gga_line_rec() + "\r\n") { ok = false; }
  if !nmea_checksum_valid("$GPGGA,132820.60,4134.49821229,N,09345.03351845,W,2,09,1.0,278.020,M,-31.442,M,7.6,0133*7Etrailing") { ok = false; }
  // mismatch
  let bad = "$GPGGA,132820.60,4134.49821229,N,09345.03351845,W,2,09,1.0,278.020,M,-31.442,M,7.6,0133*00";
  let mv = nmea_checksum(bad);
  let mvok = mv.is_ok;
  if mvok { ok = false; } else {
    let me: Str = mv.error;
    if !err_has(me, "mismatch") { ok = false; }
  }
  // non-hex digits
  let nh = nmea_checksum("$GPGGA,1*ZZ");
  let nhok = nh.is_ok;
  if nhok { ok = false; } else {
    let ne: Str = nh.error;
    if !err_has(ne, "not hex") { ok = false; }
  }
  // truncated / missing
  let tr = nmea_checksum("$GPGGA,1*7");
  let trok = tr.is_ok;
  if trok { ok = false; } else {
    let te: Str = tr.error;
    if !err_has(te, "truncated") { ok = false; }
  }
  let ms = nmea_checksum("$GPGGA,1");
  let msok = ms.is_ok;
  if msok { ok = false; } else {
    let mse: Str = ms.error;
    if !err_has(mse, "missing") { ok = false; }
  }
  return report(ok, "checksum: value 0x7E, case-insensitive hex, trailing bytes, mismatch/hex/truncated/missing errors");
}

// ---------------------------------------------------------------------------
// NMEA -- GGA
// ---------------------------------------------------------------------------

fn test_gga_values() -> Int {
  let r = nmea_parse_gga(gga_line_rec());
  let rok = r.is_ok;
  if !rok {
    let re: Str = r.error;
    return report(false, "gga: recorded line parses (" + re + ")");
  }
  let g: NmeaGga = r.value;
  var ok = true;
  let talker: Str = g.talker;
  if !streq(talker, "GP") { ok = false; }
  let c1 = opt_i_eq(g.fix_quality, 2);
  if !c1 { ok = false; }
  let c2 = opt_i_eq(g.num_sats, 9);
  if !c2 { ok = false; }
  let f1 = opt_f_eq(g.lat, 41.574970205, 0.000001);
  if !f1 { ok = false; }
  let f2 = opt_f_eq(g.lon, -93.750558641, 0.000001);
  if !f2 { ok = false; }
  let f3 = opt_f_eq(g.hdop, 1.0, 0.0001);
  if !f3 { ok = false; }
  let f4 = opt_f_eq(g.alt_msl, 278.020, 0.0001);
  if !f4 { ok = false; }
  let f5 = opt_f_eq(g.geoid_sep, -31.442, 0.0001);
  if !f5 { ok = false; }
  let f6 = opt_f_eq(g.dgps_age, 7.6, 0.0001);
  if !f6 { ok = false; }
  let c3 = opt_i_eq(g.dgps_sta, 133);
  if !c3 { ok = false; }
  // time of day
  let ts = g.time.is_some;
  if ts {
    let tv: NmeaTime = g.time.value;
    let hh = tv.hour == 13;
    let mm = tv.minute == 28;
    let ss = tv.second == 20;
    let ms = tv.millis == 600;
    if !hh { ok = false; }
    if !mm { ok = false; }
    if !ss { ok = false; }
    if !ms { ok = false; }
  } else {
    ok = false;
  }
  return report(ok, "gga: recorded values pinned (time/lat/lon/quality/hdop/alt/geoid/dgps)");
}

fn test_gga_nofix_and_southern() -> Int {
  var ok = true;
  // Quectel-style no-fix sentence (upstream manual comment form)
  let nofix = mk_sentence("GPGGA,,,,,,0,,,,,,,");
  let r = nmea_parse_gga(nofix);
  let rok = r.is_ok;
  if !rok { ok = false; } else {
    let g: NmeaGga = r.value;
    let a1 = g.talker.len() == 2;
    if !a1 { ok = false; }
    let a2 = g.time.is_some;
    if a2 { ok = false; }
    let a3 = g.lat.is_some;
    if a3 { ok = false; }
    let a4 = g.lon.is_some;
    if a4 { ok = false; }
    let a5 = opt_f_absent(g.alt_msl);
    if !a5 { ok = false; }
    let c1 = opt_i_eq(g.fix_quality, 0);
    if !c1 { ok = false; }
  }
  // southern/eastern hemisphere sign handling
  let sw2 = mk_sentence("GPGGA,015438.00,3857.9894,S,17448.1553,E,1,08,0.9,12.4,M,20.0,M,,");
  let r2 = nmea_parse_gga(sw2);
  let r2ok = r2.is_ok;
  if !r2ok { ok = false; } else {
    let g2: NmeaGga = r2.value;
    let f1 = opt_f_eq(g2.lat, -38.96649, 0.00001);
    if !f1 { ok = false; }
    let f2 = opt_f_eq(g2.lon, 174.802588, 0.00001);
    if !f2 { ok = false; }
  }
  return report(ok, "gga-nofix: empty no-fix fields decode as absent; S hemispheres negate lat");
}

fn test_gga_errors() -> Int {
  var ok = true;
  // minutes field out of range (99)
  let b1 = mk_sentence("GPGGA,132820.60,4199.49821229,N,09345.03351845,W,2,09,1.0,278.020,M,-31.442,M,7.6,0133");
  let b1r = nmea_parse_gga(b1);
  let b1ok = b1r.is_ok;
  if b1ok { ok = false; }
  // partial lat/lon pair
  let b2 = mk_sentence("GPGGA,132820.60,4134.49821229,,09345.03351845,W,2,09,1.0,278.020,M,-31.442,M,7.6,0133");
  let b2r = nmea_parse_gga(b2);
  let b2ok = b2r.is_ok;
  if b2ok { ok = false; }
  // bad fix quality
  let b3 = mk_sentence("GPGGA,132820.60,4134.49821229,N,09345.03351845,W,x,09,1.0,278.020,M,-31.442,M,7.6,0133");
  let r3 = nmea_parse_gga(b3);
  let r3ok = r3.is_ok;
  if r3ok { ok = false; } else {
    let e3: Str = r3.error;
    if !err_has(e3, "fix quality") { ok = false; }
  }
  // not a GGA
  let r4 = nmea_parse_gga(rmc_line_rec());
  let r4ok = r4.is_ok;
  if r4ok { ok = false; } else {
    let e4: Str = r4.error;
    if !err_has(e4, "not a GGA") { ok = false; }
  }
  // missing '$' prefix
  let r5 = nmea_parse_gga("GPGGA,1*00");
  let r5ok = r5.is_ok;
  if r5ok { ok = false; } else {
    let e5: Str = r5.error;
    if !err_has(e5, "must start with $") { ok = false; }
  }
  return report(ok, "gga-errors: bad minutes, partial pair, bad quality, wrong kind, missing $");
}

// ---------------------------------------------------------------------------
// NMEA -- RMC
// ---------------------------------------------------------------------------

fn test_rmc_values() -> Int {
  let r = nmea_parse_rmc(rmc_line_rec());
  let rok = r.is_ok;
  if !rok {
    let re: Str = r.error;
    return report(false, "rmc: recorded line parses (" + re + ")");
  }
  let m: NmeaRmc = r.value;
  var ok = true;
  let talker: Str = m.talker;
  if !streq(talker, "GP") { ok = false; }
  let c1 = opt_s_eq(m.status, "A");
  if !c1 { ok = false; }
  let f1 = opt_f_eq(m.lat, 41.574970205, 0.000001);
  if !f1 { ok = false; }
  let f2 = opt_f_eq(m.lon, -93.750558641, 0.000001);
  if !f2 { ok = false; }
  let f3 = opt_f_eq(m.speed_knots, 3.252, 0.0001);
  if !f3 { ok = false; }
  let f4 = opt_f_eq(m.track_deg, 92.308, 0.0001);
  if !f4 { ok = false; }
  let f5 = opt_f_eq(m.magvar_deg, 11.5985, 0.0001);
  if !f5 { ok = false; }
  let c2 = opt_s_eq(m.mode_ind, "D");
  if !c2 { ok = false; }
  let c3 = opt_s_absent(m.nav_status);
  if !c3 { ok = false; }
  // time of day
  let ts = m.time.is_some;
  if ts {
    let tv: NmeaTime = m.time.value;
    let hh = tv.hour == 13;
    let mm = tv.minute == 28;
    let ss = tv.second == 20;
    let ms = tv.millis == 600;
    if !hh { ok = false; }
    if !mm { ok = false; }
    if !ss { ok = false; }
    if !ms { ok = false; }
  } else {
    ok = false;
  }
  // date
  let ds = m.date.is_some;
  if ds {
    let dv: NmeaDate = m.date.value;
    let dd = dv.day == 18;
    let mo = dv.month == 3;
    let yr = dv.year == 2020;
    if !dd { ok = false; }
    if !mo { ok = false; }
    if !yr { ok = false; }
  } else {
    ok = false;
  }
  return report(ok, "rmc: recorded values pinned (status/time/date/lat/lon/speed/track/magvar/mode)");
}

fn test_rmc_magvar_and_century_rules() -> Int {
  var ok = true;
  // upstream rule: 0.0,E / tiny variation reads as absent
  let r1 = nmea_parse_rmc(mk_sentence("GPRMC,225446.33,A,4916.45,N,12311.12,W,0.5,54.7,191194,0.0,E,A"));
  let r1ok = r1.is_ok;
  if !r1ok { ok = false; } else {
    let m1: NmeaRmc = r1.value;
    let z1 = opt_f_absent(m1.magvar_deg);
    if !z1 { ok = false; }
  }
  let r2 = nmea_parse_rmc(mk_sentence("GPRMC,225446.33,A,4916.45,N,12311.12,W,0.5,54.7,191194,0.05,W,A"));
  let r2ok = r2.is_ok;
  if !r2ok { ok = false; } else {
    let m2: NmeaRmc = r2.value;
    let z2 = opt_f_absent(m2.magvar_deg);
    if !z2 { ok = false; }
  }
  // W negates
  let r3 = nmea_parse_rmc(mk_sentence("GPRMC,225446.33,A,4916.45,N,12311.12,W,0.5,54.7,191194,10.5,W,A"));
  let r3ok = r3.is_ok;
  if !r3ok { ok = false; } else {
    let m3: NmeaRmc = r3.value;
    let f3 = opt_f_eq(m3.magvar_deg, -10.5, 0.0001);
    if !f3 { ok = false; }
  }
  // century window: yy >= 69 -> 19xx; yy < 69 -> 20xx
  let r4 = nmea_parse_rmc(mk_sentence("GPRMC,225446.33,A,4916.45,N,12311.12,W,0.5,54.7,010169,10.5,E,A"));
  let r4ok = r4.is_ok;
  if !r4ok { ok = false; } else {
    let m4: NmeaRmc = r4.value;
    let ds4 = m4.date.is_some;
    if ds4 {
      let dv4: NmeaDate = m4.date.value;
      let y4 = dv4.year == 1969;
      if !y4 { ok = false; }
    } else {
      ok = false;
    }
  }
  let r5 = nmea_parse_rmc(mk_sentence("GPRMC,225446.33,A,4916.45,N,12311.12,W,0.5,54.7,010168,10.5,E,A"));
  let r5ok = r5.is_ok;
  if !r5ok { ok = false; } else {
    let m5: NmeaRmc = r5.value;
    let ds5 = m5.date.is_some;
    if ds5 {
      let dv5: NmeaDate = m5.date.value;
      let y5 = dv5.year == 2068;
      if !y5 { ok = false; }
    } else {
      ok = false;
    }
  }
  return report(ok, "rmc-rules: magvar 0.0/E absent + W sign; 1969/2068 century window edges");
}

fn test_rmc_errors() -> Int {
  var ok = true;
  let r1 = nmea_parse_rmc(mk_sentence("GPRMC,225446.33,X,4916.45,N,12311.12,W,0.5,54.7,191194,10.5,E,A"));
  let r1ok = r1.is_ok;
  if r1ok { ok = false; } else {
    let e1: Str = r1.error;
    if !err_has(e1, "status") { ok = false; }
  }
  let r2 = nmea_parse_rmc(mk_sentence("GPRMC,225446.33,A,4916.45,N,12311.12,W,0.5,54.7,191394,10.5,E,A"));
  let r2ok = r2.is_ok;
  if r2ok { ok = false; } else {
    let e2: Str = r2.error;
    if !err_has(e2, "date") { ok = false; }
  }
  let r3 = nmea_parse_rmc(mk_sentence("GPRMC,225446.33,A,4916.45,N,12311.12,W,0.5,54.7,191194,10.5,Z,A"));
  let r3ok = r3.is_ok;
  if r3ok { ok = false; } else {
    let e3: Str = r3.error;
    if !err_has(e3, "hemisphere") { ok = false; }
  }
  let r4 = nmea_parse_rmc(mk_sentence("GPRMC,225446.33,A,4916.45,N,12311.12,W,x.5,54.7,191194,10.5,E,A"));
  let r4ok = r4.is_ok;
  if r4ok { ok = false; } else {
    let e4: Str = r4.error;
    if !err_has(e4, "speed") { ok = false; }
  }
  let r5 = nmea_parse_rmc(mk_sentence("GPRMC,225446.33,A,4916.45,N,12311.12,W,0.5,54.7,191194,10.5,E,Z"));
  let r5ok = r5.is_ok;
  if r5ok { ok = false; } else {
    let e5: Str = r5.error;
    if !err_has(e5, "mode indicator") { ok = false; }
  }
  return report(ok, "rmc-errors: status/date/hemisphere/speed/mode-indicator failures typed");
}

// ---------------------------------------------------------------------------
// NMEA -- GSA
// ---------------------------------------------------------------------------

fn test_gsa_values() -> Int {
  let r = nmea_parse_gsa(gsa_line_rec());
  let rok = r.is_ok;
  if !rok {
    let re: Str = r.error;
    return report(false, "gsa: recorded line parses (" + re + ")");
  }
  let g: NmeaGsa = r.value;
  var ok = true;
  let talker: Str = g.talker;
  if !streq(talker, "GN") { ok = false; }
  let c1 = opt_s_eq(g.mode, "A");
  if !c1 { ok = false; }
  let ft = g.fix_type == 3;
  if !ft { ok = false; }
  let f1 = opt_f_eq(g.pdop, 1.5, 0.0001);
  if !f1 { ok = false; }
  let f2 = opt_f_eq(g.hdop, 0.9, 0.0001);
  if !f2 { ok = false; }
  let f3 = opt_f_eq(g.vdop, 1.2, 0.0001);
  if !f3 { ok = false; }
  let c2 = opt_i_eq(g.system_id, 1);
  if !c2 { ok = false; }
  let n = g.prns.len();
  let n_ok = n == 8;
  if !n_ok { ok = false; }
  if n == 8 {
    let p0 = g.prns[0] == 2;
    let p1 = g.prns[1] == 7;
    let p2 = g.prns[2] == 14;
    let p3 = g.prns[3] == 15;
    let p4 = g.prns[4] == 17;
    let p5 = g.prns[5] == 20;
    let p6 = g.prns[6] == 22;
    let p7 = g.prns[7] == 30;
    if !p0 { ok = false; }
    if !p1 { ok = false; }
    if !p2 { ok = false; }
    if !p3 { ok = false; }
    if !p4 { ok = false; }
    if !p5 { ok = false; }
    if !p6 { ok = false; }
    if !p7 { ok = false; }
  }
  // second recorded flavor: 3 PRNs, system id 4
  let r2 = nmea_parse_gsa("$GNGSA,A,3,13,27,37,,,,,,,,,,1.5,0.9,1.2,4*39");
  let r2ok = r2.is_ok;
  if !r2ok { ok = false; } else {
    let g2: NmeaGsa = r2.value;
    let n2 = g2.prns.len();
    let n2ok = n2 == 3;
    if !n2ok { ok = false; }
    let c3 = opt_i_eq(g2.system_id, 4);
    if !c3 { ok = false; }
  }
  return report(ok, "gsa: recorded line pinned (mode/type/prns/dops/system id) + second flavor");
}

fn test_gsa_rules() -> Int {
  var ok = true;
  // dead-reckoning 'E' fix type reads as 0 (upstream atoi), zero PRNs skipped
  let r1 = nmea_parse_gsa(mk_sentence("GPGSA,A,E,00,16,,,,,,,,,,1.2,0.9,0.9"));
  let r1ok = r1.is_ok;
  if !r1ok { ok = false; } else {
    let g: NmeaGsa = r1.value;
    let ft = g.fix_type == 0;
    if !ft { ok = false; }
    let c1 = opt_i_absent(g.system_id);
    if !c1 { ok = false; }
    let n = g.prns.len();
    let n_ok = n == 1;
    if !n_ok { ok = false; }
    if n == 1 {
      let p0 = g.prns[0] == 16;
      if !p0 { ok = false; }
    }
  }
  // DOP sentinel gates: 0.00 and 99.99 read as absent (0 < v < 90)
  let r2 = nmea_parse_gsa(mk_sentence("GPGSA,A,1,,,,,,,,,,,,,0.00,99.99,89.99"));
  let r2ok = r2.is_ok;
  if !r2ok { ok = false; } else {
    let g2: NmeaGsa = r2.value;
    let z1 = opt_f_absent(g2.pdop);
    if !z1 { ok = false; }
    let z2 = opt_f_absent(g2.hdop);
    if !z2 { ok = false; }
    let f = opt_f_eq(g2.vdop, 89.99, 0.0001);
    if !f { ok = false; }
  }
  // manual mode, prn gate 600
  let r3 = nmea_parse_gsa(mk_sentence("GPGSA,M,2,601,600,1,,,,,,,,1.1,1.2,1.3"));
  let r3ok = r3.is_ok;
  if !r3ok { ok = false; } else {
    let g3: NmeaGsa = r3.value;
    let c2 = opt_s_eq(g3.mode, "M");
    if !c2 { ok = false; }
    let n3 = g3.prns.len();
    let n3ok = n3 == 2;
    if !n3ok { ok = false; }
    if n3 == 2 {
      let q0 = g3.prns[0] == 600;
      let q1 = g3.prns[1] == 1;
      if !q0 { ok = false; }
      if !q1 { ok = false; }
    }
  }
  return report(ok, "gsa-rules: E->0, zero PRN skipped, 601 gated out, sentinel DOPs absent, manual mode");
}

fn test_gsa_errors() -> Int {
  var ok = true;
  let r1 = nmea_parse_gsa(mk_sentence("GPGSA,X,3,,,,,,,,,,,1.2,0.9,0.9"));
  let r1ok = r1.is_ok;
  if r1ok { ok = false; } else {
    let e1: Str = r1.error;
    if !err_has(e1, "mode") { ok = false; }
  }
  let r2 = nmea_parse_gsa(mk_sentence("GPGSA,A,3,1x,,,,,,,,,,1.2,0.9,0.9"));
  let r2ok = r2.is_ok;
  if r2ok { ok = false; } else {
    let e2: Str = r2.error;
    if !err_has(e2, "prn") { ok = false; }
  }
  let r3 = nmea_parse_gsa(gsv_line_rec());
  let r3ok = r3.is_ok;
  if r3ok { ok = false; } else {
    let e3: Str = r3.error;
    if !err_has(e3, "not a GSA") { ok = false; }
  }
  return report(ok, "gsa-errors: bad mode, bad PRN digit, wrong sentence kind");
}

// ---------------------------------------------------------------------------
// NMEA -- GSV
// ---------------------------------------------------------------------------

fn test_gsv_values() -> Int {
  let r = nmea_parse_gsv(gsv_line_rec());
  let rok = r.is_ok;
  if !rok {
    let re: Str = r.error;
    return report(false, "gsv: recorded line parses (" + re + ")");
  }
  let g: NmeaGsv = r.value;
  var ok = true;
  let talker: Str = g.talker;
  if !streq(talker, "GP") { ok = false; }
  let nm = g.num_msgs == 3;
  let mn = g.msg_num == 1;
  let sv = g.sats_in_view == 12;
  if !nm { ok = false; }
  if !mn { ok = false; }
  if !sv { ok = false; }
  let c1 = opt_i_eq(g.signal_id, 0);
  if !c1 { ok = false; }
  let c2 = opt_i_absent(g.system_id);
  if !c2 { ok = false; }
  let n = g.satellites.len();
  let n_ok = n == 4;
  if !n_ok { ok = false; }
  if n == 4 {
    let a0 = g.satellites[0].prn == 1;
    if !a0 { ok = false; }
    let a1 = opt_i_eq(g.satellites[0].el, 17);
    if !a1 { ok = false; }
    let a2 = opt_i_eq(g.satellites[0].az, 83);
    if !a2 { ok = false; }
    let a3 = opt_i_eq(g.satellites[0].snr, 3);
    if !a3 { ok = false; }
    let b0 = g.satellites[3].prn == 8;
    if !b0 { ok = false; }
    let b1 = opt_i_absent(g.satellites[3].el);
    if !b1 { ok = false; }
    let b2 = opt_i_absent(g.satellites[3].az);
    if !b2 { ok = false; }
    let b3 = opt_i_eq(g.satellites[3].snr, 15);
    if !b3 { ok = false; }
  }
  // GLONASS flavor with trailing signal id
  let r2 = nmea_parse_gsv("$GLGSV,3,1,10,74,52,302,,82,25,034,33,73,59,049,31,80,10,081,21,0*71");
  let r2ok = r2.is_ok;
  if !r2ok { ok = false; } else {
    let g2: NmeaGsv = r2.value;
    let t2: Str = g2.talker;
    if !streq(t2, "GL") { ok = false; }
    let n2 = g2.satellites.len();
    let n2ok = n2 == 4;
    if !n2ok { ok = false; }
    if n2 == 4 {
      let c0 = g2.satellites[0].prn == 74;
      if !c0 { ok = false; }
      let c1b = opt_i_absent(g2.satellites[0].snr);
      if !c1b { ok = false; }
      let c2b = opt_i_eq(g2.satellites[3].el, 10);
      if !c2b { ok = false; }
    }
  }
  // 3-satellite BeiDou last message
  let r3 = nmea_parse_gsv("$BDGSV,1,1,03,13,19,043,17,27,38,127,33,37,36,091,24,0*49");
  let r3ok = r3.is_ok;
  if !r3ok { ok = false; } else {
    let g3: NmeaGsv = r3.value;
    let n3 = g3.satellites.len();
    let n3ok = n3 == 3;
    if !n3ok { ok = false; }
    if n3 == 3 {
      let d0 = g3.satellites[2].prn == 37;
      if !d0 { ok = false; }
      let d1 = opt_i_eq(g3.satellites[2].az, 91);
      if !d1 { ok = false; }
    }
  }
  return report(ok, "gsv: recorded GP/GL/BD sentences pinned (records, empty el/az, signal id)");
}

fn test_gsv_rules_and_errors() -> Int {
  var ok = true;
  // no trailing signal id: plain pre-4.10 shape (20 fields)
  let r1 = nmea_parse_gsv(mk_sentence("GPGSV,1,1,04,01,40,083,46,02,17,308,41,12,07,344,39,14,22,228,45"));
  let r1ok = r1.is_ok;
  if !r1ok { ok = false; } else {
    let g: NmeaGsv = r1.value;
    let z1 = opt_i_absent(g.signal_id);
    if !z1 { ok = false; }
    let n = g.satellites.len();
    let n_ok = n == 4;
    if !n_ok { ok = false; }
    if n == 4 {
      let e0 = opt_i_eq(g.satellites[0].el, 40);
      if !e0 { ok = false; }
      let e3 = opt_i_eq(g.satellites[3].snr, 45);
      if !e3 { ok = false; }
    }
  }
  // az 360 normalizes to 0; el outside 0..90 reads absent
  let r2 = nmea_parse_gsv(mk_sentence("GPGSV,1,1,02,01,95,360,40,02,80,0,41"));
  let r2ok = r2.is_ok;
  if !r2ok { ok = false; } else {
    let g2: NmeaGsv = r2.value;
    let n2 = g2.satellites.len();
    let n2ok = n2 == 2;
    if !n2ok { ok = false; } else {
      let z0 = opt_i_absent(g2.satellites[0].el);
      if !z0 { ok = false; }
      let a0 = opt_i_eq(g2.satellites[0].az, 0);
      if !a0 { ok = false; }
      let a1 = opt_i_eq(g2.satellites[1].el, 80);
      if !a1 { ok = false; }
    }
  }
  // Quectel two-extra-field form: signal id + system id (5 = QZSS)
  let r3 = nmea_parse_gsv(mk_sentence("PQGSV,4,2,15,09,16,120,,10,26,049,,16,07,123,,19,34,212,,0,5"));
  let r3ok = r3.is_ok;
  if !r3ok { ok = false; } else {
    let g3: NmeaGsv = r3.value;
    let t3: Str = g3.talker;
    if !streq(t3, "PQ") { ok = false; }
    let s1 = opt_i_eq(g3.signal_id, 0);
    if !s1 { ok = false; }
    let s2 = opt_i_eq(g3.system_id, 5);
    if !s2 { ok = false; }
    let n3 = g3.satellites.len();
    let n3ok = n3 == 4;
    if !n3ok { ok = false; }
  }
  // errors: num_msgs 0; msg_num > num_msgs; hex signal id; bad modulus
  let r4 = nmea_parse_gsv(mk_sentence("GPGSV,0,1,04,01,40,083,46"));
  let r4ok = r4.is_ok;
  if r4ok { ok = false; }
  let r5 = nmea_parse_gsv(mk_sentence("GPGSV,2,3,04,01,40,083,46"));
  let r5ok = r5.is_ok;
  if r5ok { ok = false; }
  let r6 = nmea_parse_gsv(mk_sentence("GPGSV,1,1,04,01,40,083,46,z"));
  let r6ok = r6.is_ok;
  if r6ok { ok = false; }
  let r7 = nmea_parse_gsv(mk_sentence("GPGSV,1,1,04,01,40,083,46,7,8,9"));
  let r7ok = r7.is_ok;
  if r7ok { ok = false; }
  // Quectel system id gate (only 4 or 5)
  let r8 = nmea_parse_gsv(mk_sentence("PQGSV,4,2,15,09,16,120,,10,26,049,,16,07,123,,19,34,212,,0,7"));
  let r8ok = r8.is_ok;
  if r8ok { ok = false; }
  return report(ok, "gsv-rules: plain/360-el/PQGSV forms + framing and id errors");
}

// ---------------------------------------------------------------------------
// NMEA -- dispatch and identity
// ---------------------------------------------------------------------------

fn test_nmea_dispatch_and_ids() -> Int {
  var ok = true;
  let tk = nmea_talker(gsa_line_rec());
  let tkok = tk.is_ok;
  if !tkok { ok = false; } else {
    let tks: Str = tk.value;
    if !streq(tks, "GN") { ok = false; }
  }
  let kd = nmea_kind(gsa_line_rec());
  let kdok = kd.is_ok;
  if !kdok { ok = false; } else {
    let kds: Str = kd.value;
    if !streq(kds, "GSA") { ok = false; }
  }
  let r1 = nmea_parse_line(gga_line_rec());
  let r1ok = r1.is_ok;
  if !r1ok { ok = false; } else {
    let mv: NmeaMessage = r1.value;
    match mv {
      NmeaMessage.Gga(g) => {
        let fq = opt_i_eq(g.fix_quality, 2);
        if !fq { ok = false; }
      },
      _ => { ok = false; },
    }
  }
  let r2 = nmea_parse_line(rmc_line_rec());
  let r2ok = r2.is_ok;
  if !r2ok { ok = false; } else {
    let mv2: NmeaMessage = r2.value;
    match mv2 {
      NmeaMessage.Rmc(m) => {
        let st = opt_s_eq(m.status, "A");
        if !st { ok = false; }
      },
      _ => { ok = false; },
    }
  }
  let r3 = nmea_parse_line(gsa_line_rec());
  let r3ok = r3.is_ok;
  if !r3ok { ok = false; } else {
    let mv3: NmeaMessage = r3.value;
    match mv3 {
      NmeaMessage.Gsa(g) => {
        let ft = g.fix_type == 3;
        if !ft { ok = false; }
      },
      _ => { ok = false; },
    }
  }
  let r4 = nmea_parse_line(gsv_line_rec());
  let r4ok = r4.is_ok;
  if !r4ok { ok = false; } else {
    let mv4: NmeaMessage = r4.value;
    match mv4 {
      NmeaMessage.Gsv(g) => {
        let n = g.satellites.len();
        let n_ok = n == 4;
        if !n_ok { ok = false; }
      },
      _ => { ok = false; },
    }
  }
  // undeclared kind passes through as Other with talker + kind
  let r5 = nmea_parse_line(mk_sentence("GPVTG,054.7,T,034.4,M,005.5,N,010.2,K,A"));
  let r5ok = r5.is_ok;
  if !r5ok { ok = false; } else {
    let mv5: NmeaMessage = r5.value;
    match mv5 {
      NmeaMessage.Other(t, k) => {
        if !streq(t, "GP") { ok = false; }
        if !streq(k, "VTG") { ok = false; }
      },
      _ => { ok = false; },
    }
  }
  return report(ok, "nmea-dispatch: talker/kind helpers, 4 typed variants, VTG -> Other");
}

// ---------------------------------------------------------------------------
// Driver
// ---------------------------------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.gps conformance tests ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + test_json_fixture_sweep();
  failed = failed + test_nmea_fixture_sweep();
  failed = failed + test_tpv_values();
  failed = failed + test_tpv_optional_absence();
  failed = failed + test_tpv_errors();
  failed = failed + test_sky_values();
  failed = failed + test_sky_minimal_and_errors();
  failed = failed + test_version();
  failed = failed + test_proto_compatible();
  failed = failed + test_devices();
  failed = failed + test_watch();
  failed = failed + test_error_msg_and_dispatch();
  failed = failed + test_commands();
  failed = failed + test_client_skip_path();
  failed = failed + test_client_argument_and_closed_errors();
  failed = failed + test_checksum();
  failed = failed + test_gga_values();
  failed = failed + test_gga_nofix_and_southern();
  failed = failed + test_gga_errors();
  failed = failed + test_rmc_values();
  failed = failed + test_rmc_magvar_and_century_rules();
  failed = failed + test_rmc_errors();
  failed = failed + test_gsa_values();
  failed = failed + test_gsa_rules();
  failed = failed + test_gsa_errors();
  failed = failed + test_gsv_values();
  failed = failed + test_gsv_rules_and_errors();
  failed = failed + test_nmea_dispatch_and_ids();

  if failed == 0 {
    io.println("xiom.gps: all tests passed");
  } else {
    io.println("xiom.gps: tests failed");
  }
  return failed;
}
