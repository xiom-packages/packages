// XIOM -- xiom.geohash conformance tests (20 checks)
// Port task: prove the pure-XIOM geohash codec against the rules pinned in
// SPEC.md: integer-microdegree encode/decode, canonical lowercase output,
// uppercase input folding, exact boxes and centers, the error catalog, and
// round trips across precisions and range edges.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Expected hashes and box values were cross-checked against an independent
// reference implementation of the documented integer algorithm (and against
// the classic Float64 bisector for every vector below).
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq instead of `==`. No Vec is used by this suite.

module geohash_tests
use xiom.io; use xiom.test; use xiom.geohash;
use xiom.string; use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when r is an Err whose message is exactly `want`.
fn encode_err_eq(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// True when r is an Err whose message is exactly `want`.
fn decode_err_eq(r: Result[GeoBox, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// True when the box bounds are exactly the four expected microdegrees.
fn box_bounds_ok(b: GeoBox, min_lat: Int, min_lon: Int, max_lat: Int, max_lon: Int) -> Bool {
  if b.min_lat_ud != min_lat { return false; }
  if b.min_lon_ud != min_lon { return false; }
  if b.max_lat_ud != max_lat { return false; }
  if b.max_lon_ud != max_lon { return false; }
  return true;
}

// True when the box center is exactly the expected microdegree pair.
fn box_center_ok(b: GeoBox, center_lat: Int, center_lon: Int) -> Bool {
  return b.center_lat_ud == center_lat && b.center_lon_ud == center_lon;
}

// Encode, decode and re-encode a point at precision p: the box must be
// non-empty and contain the point, and the point, the center and both box
// corners must all re-encode to the same hash.
fn roundtrip_p(point_lat: Int, point_lon: Int, p: Int) -> Bool {
  let e = geohash_encode(point_lat, point_lon, p);
  if !e.is_ok {
    return false;
  }
  let h = e.value;
  let d = geohash_decode(h);
  if !d.is_ok {
    return false;
  }
  let b: GeoBox = d.value;
  if b.precision != p { return false; }
  if geohash_box_is_empty(b) { return false; }
  if !geohash_box_contains(b, point_lat, point_lon) { return false; }
  let c = geohash_encode(b.center_lat_ud, b.center_lon_ud, p);
  if !c.is_ok { return false; }
  if !streq(c.value, h) { return false; }
  let lo = geohash_encode(b.min_lat_ud, b.min_lon_ud, p);
  if !lo.is_ok { return false; }
  if !streq(lo.value, h) { return false; }
  let hi = geohash_encode(b.max_lat_ud, b.max_lon_ud, p);
  if !hi.is_ok { return false; }
  if !streq(hi.value, h) { return false; }
  return true;
}

fn t1() -> TestResult {
  let h11 = geohash_encode(57649110, 10407440, 11);
  var ok = h11.is_ok;
  if ok && !streq(h11.value, "u4pruydqqvj") { ok = false; }
  let h12 = geohash_encode(57649110, 10407440, 12);
  if !h12.is_ok { ok = false; }
  if h12.is_ok && !streq(h12.value, "u4pruydqqvj8") { ok = false; }
  let h7 = geohash_encode(57649110, 10407440, 7);
  if !h7.is_ok { ok = false; }
  if h7.is_ok && !streq(h7.value, "u4pruyd") { ok = false; }
  let h1 = geohash_encode(57649110, 10407440, 1);
  if !h1.is_ok { ok = false; }
  if h1.is_ok && !streq(h1.value, "u") { ok = false; }
  return assert(ok, "encode known vector u4pruydqqvj across precisions");
}

fn t2() -> TestResult {
  var p = 1;
  var ok = true;
  while p <= 12 {
    let h = geohash_encode(57649110, 10407440, p);
    if !h.is_ok {
      ok = false;
    } elif h.value.len() != p {
      ok = false;
    }
    p = p + 1;
  }
  return assert(ok, "encode precision 1..12 yields exactly p characters");
}

fn t3() -> TestResult {
  let one = geohash_encode(0, 0, 1);
  var ok = one.is_ok;
  if ok && !streq(one.value, "s") { ok = false; }
  let full = geohash_encode(0, 0, 12);
  if !full.is_ok { ok = false; }
  if full.is_ok && !streq(full.value, "s00000000000") { ok = false; }
  return assert(ok, "encode (0,0) -> s and s00000000000");
}

fn t4() -> TestResult {
  let ne = geohash_encode(90000000, 180000000, 12);
  var ok = ne.is_ok;
  if ok && !streq(ne.value, "zzzzzzzzzzzz") { ok = false; }
  let sw = geohash_encode(-90000000, -180000000, 12);
  if !sw.is_ok { ok = false; }
  if sw.is_ok && !streq(sw.value, "000000000000") { ok = false; }
  let nw = geohash_encode(-90000000, 180000000, 12);
  if !nw.is_ok { ok = false; }
  if nw.is_ok && !streq(nw.value, "pbpbpbpbpbpb") { ok = false; }
  let se = geohash_encode(90000000, -180000000, 12);
  if !se.is_ok { ok = false; }
  if se.is_ok && !streq(se.value, "bpbpbpbpbpbp") { ok = false; }
  return assert(ok, "encode the four range corners at precision 12");
}

fn t5() -> TestResult {
  var ok = encode_err_eq(geohash_encode(0, 0, 0), "geohash: invalid precision");
  if !encode_err_eq(geohash_encode(0, 0, 13), "geohash: invalid precision") { ok = false; }
  if !encode_err_eq(geohash_encode(0, 0, -1), "geohash: invalid precision") { ok = false; }
  if !encode_err_eq(geohash_encode(90000001, 180000001, 0), "geohash: invalid precision") { ok = false; }
  return assert(ok, "encode rejects precision outside 1..12 (checked first)");
}

fn t6() -> TestResult {
  var ok = encode_err_eq(geohash_encode(90000001, 0, 12), "geohash: latitude out of range");
  if !encode_err_eq(geohash_encode(-90000001, 0, 12), "geohash: latitude out of range") { ok = false; }
  if !encode_err_eq(geohash_encode(90000001, 0, 1), "geohash: latitude out of range") { ok = false; }
  return assert(ok, "encode rejects |lat| > 90 degrees in microdegrees");
}

fn t7() -> TestResult {
  var ok = encode_err_eq(geohash_encode(0, 180000001, 12), "geohash: longitude out of range");
  if !encode_err_eq(geohash_encode(0, -180000001, 12), "geohash: longitude out of range") { ok = false; }
  return assert(ok, "encode rejects |lon| > 180 degrees in microdegrees");
}

fn t8() -> TestResult {
  let d = geohash_decode("u4pruydqqvj");
  var ok = d.is_ok;
  if ok {
    let b: GeoBox = d.value;
    if !box_bounds_ok(b, 57649110, 10407440, 57649111, 10407440) { ok = false; }
    if !box_center_ok(b, 57649110, 10407440) { ok = false; }
    if b.precision != 11 { ok = false; }
    if geohash_box_is_empty(b) { ok = false; }
    if !geohash_box_contains(b, 57649110, 10407440) { ok = false; }
    if !geohash_box_contains(b, 57649111, 10407440) { ok = false; }
    if geohash_box_contains(b, 57649109, 10407440) { ok = false; }
    if geohash_box_contains(b, 57649112, 10407440) { ok = false; }
    if geohash_box_contains(b, 57649110, 10407439) { ok = false; }
    if geohash_box_contains(b, 57649110, 10407441) { ok = false; }
    if geohash_box_precision(b) != 11 { ok = false; }
    if geohash_box_min_lat(b) != 57649110 { ok = false; }
    if geohash_box_min_lon(b) != 10407440 { ok = false; }
    if geohash_box_max_lat(b) != 57649111 { ok = false; }
    if geohash_box_max_lon(b) != 10407440 { ok = false; }
  }
  return assert(ok, "decode known vector box, center and containment");
}

fn t9() -> TestResult {
  let d = geohash_decode("u4pruydqqvj8");
  var ok = d.is_ok;
  if ok {
    let b: GeoBox = d.value;
    if !box_bounds_ok(b, 57649110, 10407440, 57649110, 10407440) { ok = false; }
    if !box_center_ok(b, 57649110, 10407440) { ok = false; }
    if b.precision != 12 { ok = false; }
    if geohash_box_is_empty(b) { ok = false; }
    if !geohash_box_contains(b, 57649110, 10407440) { ok = false; }
    if geohash_box_contains(b, 57649111, 10407440) { ok = false; }
  }
  return assert(ok, "decode 12-char extension collapses to a singleton box");
}

fn t10() -> TestResult {
  let d = geohash_decode("s00000000000");
  var ok = d.is_ok;
  if ok {
    let b: GeoBox = d.value;
    if !box_bounds_ok(b, 0, 0, 0, 0) { ok = false; }
    if !box_center_ok(b, 0, 0) { ok = false; }
    if b.precision != 12 { ok = false; }
    if geohash_box_is_empty(b) { ok = false; }
    if !geohash_box_contains(b, 0, 0) { ok = false; }
    if geohash_box_contains(b, 1, 0) { ok = false; }
    if geohash_box_contains(b, 0, 1) { ok = false; }
  }
  return assert(ok, "decode s00000000000 -> singleton (0,0) box");
}

fn t11() -> TestResult {
  var ok = true;
  let d1 = geohash_decode("zzzzzzzzzzzz");
  if !d1.is_ok { ok = false; }
  if d1.is_ok && !box_bounds_ok(d1.value, 90000000, 180000000, 90000000, 180000000) { ok = false; }
  let d2 = geohash_decode("000000000000");
  if !d2.is_ok { ok = false; }
  if d2.is_ok && !box_bounds_ok(d2.value, -90000000, -180000000, -90000000, -180000000) { ok = false; }
  let d3 = geohash_decode("xbpbpbpbpbpb");
  if !d3.is_ok { ok = false; }
  if d3.is_ok && !box_bounds_ok(d3.value, 0, 180000000, 0, 180000000) { ok = false; }
  let d4 = geohash_decode("h00000000000");
  if !d4.is_ok { ok = false; }
  if d4.is_ok && !box_bounds_ok(d4.value, -90000000, 0, -90000000, 0) { ok = false; }
  return assert(ok, "decode pole and antimeridian edge cells");
}

fn t12() -> TestResult {
  var ok = decode_err_eq(geohash_decode(""), "geohash: empty geohash");
  if !decode_err_eq(geohash_decode("u4pruydqqvj8x"), "geohash: geohash too long") { ok = false; }
  return assert(ok, "decode rejects empty and 13-character hashes");
}

fn t13() -> TestResult {
  var ok = decode_err_eq(geohash_decode("u4pruydqqv!"), "geohash: invalid geohash character");
  if !decode_err_eq(geohash_decode("a"), "geohash: invalid geohash character") { ok = false; }
  if !decode_err_eq(geohash_decode("i"), "geohash: invalid geohash character") { ok = false; }
  if !decode_err_eq(geohash_decode("l"), "geohash: invalid geohash character") { ok = false; }
  if !decode_err_eq(geohash_decode("o"), "geohash: invalid geohash character") { ok = false; }
  if !decode_err_eq(geohash_decode("I"), "geohash: invalid geohash character") { ok = false; }
  if !decode_err_eq(geohash_decode("u4pruydqqv "), "geohash: invalid geohash character") { ok = false; }
  if !decode_err_eq(geohash_decode("U4PRUYDQQV!"), "geohash: invalid geohash character") { ok = false; }
  return assert(ok, "decode rejects bytes outside the base32 alphabet");
}

fn t14() -> TestResult {
  let lo = geohash_decode("u4pruydqqvj");
  let up = geohash_decode("U4PRUYDQQVJ");
  var ok = lo.is_ok && up.is_ok;
  if ok {
    let a: GeoBox = lo.value;
    let b: GeoBox = up.value;
    if a.precision != b.precision { ok = false; }
    if a.min_lat_ud != b.min_lat_ud { ok = false; }
    if a.min_lon_ud != b.min_lon_ud { ok = false; }
    if a.max_lat_ud != b.max_lat_ud { ok = false; }
    if a.max_lon_ud != b.max_lon_ud { ok = false; }
    if a.center_lat_ud != b.center_lat_ud { ok = false; }
    if a.center_lon_ud != b.center_lon_ud { ok = false; }
  }
  let norm = geohash_normalize("U4PRUYDQQVJ");
  if !norm.is_ok { ok = false; }
  if norm.is_ok && !streq(norm.value, "u4pruydqqvj") { ok = false; }
  return assert(ok, "decode and normalize fold uppercase input");
}

fn t15() -> TestResult {
  let plain = geohash_normalize("u4pruydqqvj");
  var ok = plain.is_ok;
  if ok && !streq(plain.value, "u4pruydqqvj") { ok = false; }
  if !encode_err_eq(geohash_normalize(""), "geohash: empty geohash") { ok = false; }
  if !encode_err_eq(geohash_normalize("u4pruydqqvj8x"), "geohash: geohash too long") { ok = false; }
  if !encode_err_eq(geohash_normalize("a"), "geohash: invalid geohash character") { ok = false; }
  if !encode_err_eq(geohash_normalize("U4PRUYDQQVI"), "geohash: invalid geohash character") { ok = false; }
  return assert(ok, "normalize is idempotent and shares the decode error catalog");
}

fn t16() -> TestResult {
  let d1 = geohash_decode("ny6100000000");
  var ok = d1.is_ok;
  if ok {
    let b: GeoBox = d1.value;
    if !box_bounds_ok(b, -54667968, 126562500, -54667969, 126562500) { ok = false; }
    if !box_center_ok(b, -54667968, 126562500) { ok = false; }
    if !geohash_box_is_empty(b) { ok = false; }
    if geohash_box_contains(b, -54667968, 126562500) { ok = false; }
  }
  let d2 = geohash_decode("9qh100000000");
  if !d2.is_ok { ok = false; }
  if d2.is_ok {
    let c: GeoBox = d2.value;
    if !box_bounds_ok(c, 33925782, -118125000, 33925781, -118125000) { ok = false; }
    if !box_center_ok(c, 33925781, -118125000) { ok = false; }
    if !geohash_box_is_empty(c) { ok = false; }
  }
  return assert(ok, "precision-12 sub-microdegree cells decode to empty boxes");
}

fn t17() -> TestResult {
  var ok = true;
  let d1 = geohash_decode("u");
  if !d1.is_ok { ok = false; }
  if d1.is_ok {
    if !box_bounds_ok(d1.value, 45000000, 0, 90000000, 44999999) { ok = false; }
    if !box_center_ok(d1.value, 67500000, 22499999) { ok = false; }
  }
  let d2 = geohash_decode("x");
  if !d2.is_ok { ok = false; }
  if d2.is_ok {
    if !box_bounds_ok(d2.value, 0, 135000000, 44999999, 180000000) { ok = false; }
    if !box_center_ok(d2.value, 22499999, 157500000) { ok = false; }
  }
  let d3 = geohash_decode("8");
  if !d3.is_ok { ok = false; }
  if d3.is_ok {
    if !box_bounds_ok(d3.value, 0, -180000000, 44999999, -135000001) { ok = false; }
    if !box_center_ok(d3.value, 22499999, -157500000) { ok = false; }
  }
  return assert(ok, "precision-1 cells and truncating center division");
}

fn t18() -> TestResult {
  var p = 1;
  var ok = true;
  var prev = "";
  while p <= 12 {
    if !roundtrip_p(37983800, 23727500, p) {
      ok = false;
    }
    let h = geohash_encode(37983800, 23727500, p);
    if !h.is_ok {
      ok = false;
    } else {
      let hs: Str = h.value;
      if p > 1 && !streq(prev, string.str_slice(hs, 0, p - 1)) {
        ok = false;
      }
      prev = hs;
    }
    p = p + 1;
  }
  return assert(ok, "round trip and prefix nesting at every precision 1..12");
}

fn t19() -> TestResult {
  var ok = roundtrip_p(57649110, 10407440, 11);
  if !roundtrip_p(0, 0, 11) { ok = false; }
  if !roundtrip_p(-33868800, 151209300, 11) { ok = false; }
  if !roundtrip_p(60169900, 24938400, 11) { ok = false; }
  return assert(ok, "round trip four world points at precision 11");
}

fn t20() -> TestResult {
  var ok = true;
  let east = geohash_encode(0, 180000000, 1);
  if !east.is_ok { ok = false; }
  if east.is_ok && !streq(east.value, "x") { ok = false; }
  let west = geohash_encode(0, -180000000, 1);
  if !west.is_ok { ok = false; }
  if west.is_ok && !streq(west.value, "8") { ok = false; }
  let np = geohash_encode(90000000, 0, 12);
  if !np.is_ok { ok = false; }
  if np.is_ok && !streq(np.value, "upbpbpbpbpbp") { ok = false; }
  let sp = geohash_encode(-90000000, 0, 12);
  if !sp.is_ok { ok = false; }
  if sp.is_ok && !streq(sp.value, "h00000000000") { ok = false; }
  if !roundtrip_p(90000000, 0, 12) { ok = false; }
  if !roundtrip_p(-90000000, 0, 12) { ok = false; }
  if !roundtrip_p(0, 180000000, 12) { ok = false; }
  if !roundtrip_p(0, -180000000, 12) { ok = false; }
  return assert(ok, "antimeridian and pole edges stay distinct and round-trip");
}

fn main() -> Int {
  io.println("=== xiom.geohash conformance tests ===");
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
    io.println("xiom.geohash: all tests passed");
  } else {
    io.println("xiom.geohash: tests failed");
  }
  return failed;
}
