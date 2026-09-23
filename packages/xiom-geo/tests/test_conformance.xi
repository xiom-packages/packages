// XIOM -- xiom.geo conformance tests (21 checks)
// Port task: prove the pure-XIOM xiom.geo module against its documented API.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: the canonical Wikipedia vector
// (57.64911, 10.40744) -> "u4pruydqqvj", precision lengths 1..12, decode
// centers and round trips, the encode/decode error catalog, the 8-neighborhood
// (count, validity, distinctness, N/E/S/W sign checks), inclusive bounding-box
// containment including antimeridian-crossing boxes, and clamping.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq instead of `==`.

module geo_tests
use xiom.io; use xiom.test; use xiom.geo;
use xiom.string;
use xiom.string.compare;

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
fn decode_err_eq(r: Result[GeoPoint, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// Encode then decode a point; true when the decoded center is within 1e-4
// degrees of the input on both axes (a precision-12 cell is smaller).
fn roundtrip_ok(lat: Float64, lon: Float64) -> Bool {
  let e = geo_geohash_encode(lat, lon, 12);
  if !e.is_ok {
    return false;
  }
  let d = geo_geohash_decode(e.value);
  if !d.is_ok {
    return false;
  }
  var dlat = d.value.lat - lat;
  if dlat < 0.0 { dlat = -dlat; }
  var dlon = d.value.lon - lon;
  if dlon < 0.0 { dlon = -dlon; }
  return dlat < 0.0001 && dlon < 0.0001;
}

// True when decoding `hash` moves from `c` with the requested signs:
// lat_sign/lon_sign are -1, 0 or 1; 0 means the axis must stay put (within
// 1e-9 degrees, far below one precision-12 cell).
fn dir_ok(c: GeoPoint, hash: Str, lat_sign: Int, lon_sign: Int) -> Bool {
  let d = geo_geohash_decode(hash);
  if !d.is_ok {
    return false;
  }
  let p = d.value;
  var dlat = p.lat - c.lat;
  if dlat < 0.0 { dlat = -dlat; }
  var dlon = p.lon - c.lon;
  if dlon < 0.0 { dlon = -dlon; }
  if lat_sign > 0 && !(p.lat > c.lat) { return false; }
  if lat_sign < 0 && !(p.lat < c.lat) { return false; }
  if lon_sign > 0 && !(p.lon > c.lon) { return false; }
  if lon_sign < 0 && !(p.lon < c.lon) { return false; }
  if lat_sign == 0 && dlat > 0.000000001 { return false; }
  if lon_sign == 0 && dlon > 0.000000001 { return false; }
  return true;
}

fn t1() -> TestResult {
  let h11 = geo_geohash_encode(57.64911, 10.40744, 11);
  var ok = h11.is_ok;
  if ok && !streq(h11.value, "u4pruydqqvj") { ok = false; }
  let h12 = geo_geohash_encode(57.64911, 10.40744, 12);
  if !h12.is_ok { ok = false; }
  if h12.is_ok && !streq(h12.value, "u4pruydqqvj8") { ok = false; }
  return assert(ok, "encode known vector -> u4pruydqqvj (and 12th char 8)");
}

fn t2() -> TestResult {
  let h = geo_geohash_encode(57.64911, 10.40744, 12);
  var ok = h.is_ok;
  if ok {
    let full = h.value;
    if full.len() != 12 { ok = false; }
    if !streq(string.str_slice(full, 0, 7), "u4pruyd") { ok = false; }
    if !streq(string.str_slice(full, 0, 11), "u4pruydqqvj") { ok = false; }
  }
  return assert(ok, "encode known vector is 12 chars with prefix u4pruyd");
}

fn t3() -> TestResult {
  var p = 1;
  var ok = true;
  while p <= 12 {
    let h = geo_geohash_encode(57.64911, 10.40744, p);
    if !h.is_ok {
      ok = false;
    } elif h.value.len() != p {
      ok = false;
    }
    p = p + 1;
  }
  return assert(ok, "encode precision 1..12 yields exactly p characters");
}

fn t4() -> TestResult {
  let one = geo_geohash_encode(0.0, 0.0, 1);
  var ok = one.is_ok;
  if ok && !streq(one.value, "s") { ok = false; }
  let full = geo_geohash_encode(0.0, 0.0, 12);
  if !full.is_ok { ok = false; }
  if full.is_ok && !streq(full.value, "s00000000000") { ok = false; }
  return assert(ok, "encode (0,0) -> s and s00000000000");
}

fn t5() -> TestResult {
  let d = geo_geohash_decode("u4pruydqqvj");
  var ok = d.is_ok;
  if ok {
    let p = d.value;
    var dlat = p.lat - 57.64911;
    if dlat < 0.0 { dlat = -dlat; }
    var dlon = p.lon - 10.40744;
    if dlon < 0.0 { dlon = -dlon; }
    if dlat > 0.0001 { ok = false; }
    if dlon > 0.0001 { ok = false; }
  }
  return assert(ok, "decode u4pruydqqvj center within 1e-4 of input");
}

fn t6() -> TestResult {
  var ok = roundtrip_ok(57.64911, 10.40744);
  if !roundtrip_ok(0.0, 0.0) { ok = false; }
  if !roundtrip_ok(-33.8688, 151.2093) { ok = false; }
  if !roundtrip_ok(60.1699, 24.9384) { ok = false; }
  return assert(ok, "encode/decode round trip for four points");
}

fn t7() -> TestResult {
  var ok = encode_err_eq(geo_geohash_encode(10.0, 20.0, 0), "geo: invalid precision");
  if !encode_err_eq(geo_geohash_encode(10.0, 20.0, 13), "geo: invalid precision") { ok = false; }
  if !encode_err_eq(geo_geohash_encode(10.0, 20.0, -1), "geo: invalid precision") { ok = false; }
  return assert(ok, "encode rejects precision outside 1..12");
}

fn t8() -> TestResult {
  var ok = encode_err_eq(geo_geohash_encode(90.5, 0.0, 5), "geo: latitude out of range");
  if !encode_err_eq(geo_geohash_encode(-90.5, 0.0, 5), "geo: latitude out of range") { ok = false; }
  if !encode_err_eq(geo_geohash_encode(0.0, 180.5, 5), "geo: longitude out of range") { ok = false; }
  if !encode_err_eq(geo_geohash_encode(0.0, -180.5, 5), "geo: longitude out of range") { ok = false; }
  return assert(ok, "encode rejects out-of-range lat/lon");
}

fn t9() -> TestResult {
  var ok = geo_geohash_encode(-90.0, -180.0, 12).is_ok;
  if !geo_geohash_encode(90.0, 180.0, 12).is_ok { ok = false; }
  if !geo_geohash_encode(0.0, -180.0, 1).is_ok { ok = false; }
  return assert(ok, "encode accepts inclusive lat/lon bounds");
}

fn t10() -> TestResult {
  let d = geo_geohash_decode("");
  return assert(decode_err_eq(d, "geo: empty geohash"), "decode empty hash -> Err");
}

fn t11() -> TestResult {
  var ok = decode_err_eq(geo_geohash_decode("u4pruydqqv!"), "geo: invalid geohash character");
  if !decode_err_eq(geo_geohash_decode("a"), "geo: invalid geohash character") { ok = false; }
  if !decode_err_eq(geo_geohash_decode("u4pruydqqvU"), "geo: invalid geohash character") { ok = false; }
  return assert(ok, "decode rejects bytes outside the base32 alphabet");
}

fn t12() -> TestResult {
  let d = geo_geohash_decode("u4pruydqqvj8x");
  var ok = decode_err_eq(d, "geo: geohash too long");
  if ok {
    let d13 = "u4pruydqqvj8x";
    if string.str_len(d13) != 13 { ok = false; }
  }
  return assert(ok, "decode hash longer than 12 -> Err");
}

fn t13() -> TestResult {
  let h = geo_geohash_encode(57.64911, 10.40744, 1);
  var ok = h.is_ok;
  if ok && !streq(h.value, "u") { ok = false; }
  let d = geo_geohash_decode("u");
  if !d.is_ok { ok = false; }
  if d.is_ok {
    let p = d.value;
    if p.lat < 45.0 || p.lat > 90.0 { ok = false; }
    if p.lon < 0.0 || p.lon > 45.0 { ok = false; }
  }
  return assert(ok, "precision-1 hash u decodes into its 45-degree cell");
}

fn t14() -> TestResult {
  // Exact expected set for the 11-character known vector, in N, NE, E, SE, S,
  // SW, W, NW order; independently cross-checked against a Python reference
  // implementation. Element lengths are pinned by the 11-character literals
  // (BUG 17-family: Str.len() is unreliable on Vec[Str] elements, so exact
  // comparison is used instead of a length read).
  let ns = geo_geohash_neighbors("u4pruydqqvj");
  var ok = ns.len() == 8;
  if ok {
    if !streq(ns[0], "u4pruydqqvm") { ok = false; }
    if !streq(ns[1], "u4pruydqqvq") { ok = false; }
    if !streq(ns[2], "u4pruydqqvn") { ok = false; }
    if !streq(ns[3], "u4pruydqquy") { ok = false; }
    if !streq(ns[4], "u4pruydqquv") { ok = false; }
    if !streq(ns[5], "u4pruydqquu") { ok = false; }
    if !streq(ns[6], "u4pruydqqvh") { ok = false; }
    if !streq(ns[7], "u4pruydqqvk") { ok = false; }
  }
  var i = 0;
  while i < ns.len() {
    let d = geo_geohash_decode(ns[i]);
    if !d.is_ok { ok = false; }
    i = i + 1;
  }
  return assert(ok, "neighbors: 8 exact N..NW hashes, all decodable");
}

fn t15() -> TestResult {
  let ns = geo_geohash_neighbors("u4pruydqqvj");
  var ok = ns.len() == 8;
  var i = 0;
  while i < ns.len() {
    if streq(ns[i], "u4pruydqqvj") { ok = false; }
    var j = i + 1;
    while j < ns.len() {
      if streq(ns[i], ns[j]) { ok = false; }
      j = j + 1;
    }
    i = i + 1;
  }
  return assert(ok, "neighbors are 8 distinct hashes, none the center");
}

fn t16() -> TestResult {
  let center = geo_geohash_decode("u4pruydqqvj");
  let ns = geo_geohash_neighbors("u4pruydqqvj");
  var ok = center.is_ok && ns.len() == 8;
  if ok {
    let c = center.value;
    if !dir_ok(c, ns[0], 1, 0) { ok = false; }
    if !dir_ok(c, ns[2], 0, 1) { ok = false; }
    if !dir_ok(c, ns[4], -1, 0) { ok = false; }
    if !dir_ok(c, ns[6], 0, -1) { ok = false; }
  }
  return assert(ok, "neighbors N/E/S/W differ in the expected direction");
}

fn t17() -> TestResult {
  var ok = geo_geo_bbox_contains(10.0, 20.0, 30.0, 40.0, 20.0, 30.0);
  if !geo_geo_bbox_contains(10.0, 20.0, 30.0, 40.0, 10.5, 39.5) { ok = false; }
  if geo_geo_bbox_contains(10.0, 20.0, 30.0, 40.0, 9.9, 30.0) { ok = false; }
  if geo_geo_bbox_contains(10.0, 20.0, 30.0, 40.0, 20.0, 40.1) { ok = false; }
  return assert(ok, "bbox: inside true, outside false");
}

fn t18() -> TestResult {
  var ok = geo_geo_bbox_contains(10.0, 20.0, 30.0, 40.0, 10.0, 20.0);
  if !geo_geo_bbox_contains(10.0, 20.0, 30.0, 40.0, 30.0, 40.0) { ok = false; }
  if !geo_geo_bbox_contains(10.0, 20.0, 30.0, 40.0, 10.0, 40.0) { ok = false; }
  return assert(ok, "bbox: bounds are inclusive");
}

fn t19() -> TestResult {
  var ok = geo_geo_bbox_contains(5.0, 5.0, 5.0, 5.0, 5.0, 5.0);
  if geo_geo_bbox_contains(5.0, 5.0, 5.0, 5.0, 5.0, 5.1) { ok = false; }
  return assert(ok, "bbox: degenerate point box contains only itself");
}

fn t20() -> TestResult {
  var ok = geo_geo_bbox_contains(-10.0, 170.0, 10.0, -170.0, 0.0, 175.0);
  if !geo_geo_bbox_contains(-10.0, 170.0, 10.0, -170.0, 0.0, -175.0) { ok = false; }
  if geo_geo_bbox_contains(-10.0, 170.0, 10.0, -170.0, 0.0, 0.0) { ok = false; }
  if !geo_geo_bbox_contains(-10.0, 170.0, 10.0, -170.0, 0.0, 170.0) { ok = false; }
  if !geo_geo_bbox_contains(-10.0, 170.0, 10.0, -170.0, 0.0, -170.0) { ok = false; }
  return assert(ok, "bbox: antimeridian box wraps lon 170..-170");
}

fn t21() -> TestResult {
  var ok = geo_clamp_lat(100.0) == 90.0;
  if geo_clamp_lat(-100.0) != -90.0 { ok = false; }
  if geo_clamp_lat(45.0) != 45.0 { ok = false; }
  if geo_clamp_lon(200.0) != 180.0 { ok = false; }
  if geo_clamp_lon(-200.0) != -180.0 { ok = false; }
  if geo_clamp_lon(-45.0) != -45.0 { ok = false; }
  return assert(ok, "clamp lat/lon into the inclusive WGS84 ranges");
}

fn main() -> Int {
  io.println("=== xiom.geo conformance tests ===");
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
    io.println("xiom.geo: all tests passed");
  } else {
    io.println("xiom.geo: tests failed");
  }
  return failed;
}
