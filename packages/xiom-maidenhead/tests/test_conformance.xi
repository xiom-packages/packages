// XIOM -- xiom.maidenhead conformance tests (21 checks)
// Port task: prove the pure-XIOM Maidenhead locator codec against the rules
// pinned in SPEC.md: integer-microdegree encode/decode at lengths 2/4/6/8,
// canonical uppercase output, case-insensitive input folding, exact boxes and
// centers, the error catalog, boundary behavior (upper-cell selection and
// top-edge clamping) and round trips at every length incl. poles and the
// antimeridian.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Expected locators, boxes and centers were cross-checked against an
// independent exact-rational reference implementation of the classic
// Maidenhead subdivision algorithm; a 30k-point encode sweep, a 73k-locator
// decode sweep and a corner/center round-trip sweep all agreed.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq instead of `==`. No Vec is used by this suite.

module maidenhead_tests
use xiom.io; use xiom.test; use xiom.maidenhead;
use xiom.string; use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  let left: Str = a;
  let right: Str = b;
  return compare.str_compare(left, right) == 0;
}

// True when r is an Err whose message is exactly `want` (Result[Str, Str]).
fn str_err_eq(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got: Str = r.error;
  return streq(got, want);
}

// True when r is an Err whose message is exactly `want`.
fn decode_err_eq(r: Result[MaidenheadBox, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got: Str = r.error;
  return streq(got, want);
}

// True when r is an Err whose message is exactly `want`.
fn int_err_eq(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let got: Str = r.error;
  return streq(got, want);
}

// True when the box has exactly the expected length, bounds and center.
fn box_ok(b: MaidenheadBox, length: Int, min_lat: Int, max_lat: Int, min_lon: Int, max_lon: Int, center_lat: Int, center_lon: Int) -> Bool {
  if b.length != length { return false; }
  if b.min_lat_ud != min_lat { return false; }
  if b.max_lat_ud != max_lat { return false; }
  if b.min_lon_ud != min_lon { return false; }
  if b.max_lon_ud != max_lon { return false; }
  if b.center_lat_ud != center_lat { return false; }
  if b.center_lon_ud != center_lon { return false; }
  return true;
}

// Encode, decode and re-encode a point at length L: the box must be
// non-empty and contain the point, and the center and all four box corners
// must re-encode to the same locator.
fn roundtrip_p(point_lat: Int, point_lon: Int, length: Int) -> Bool {
  let e: Result[Str, Str] = maidenhead_encode(point_lat, point_lon, length);
  if !e.is_ok {
    return false;
  }
  let loc: Str = e.value;
  let d: Result[MaidenheadBox, Str] = maidenhead_decode(loc);
  if !d.is_ok {
    return false;
  }
  let b: MaidenheadBox = d.value;
  if b.length != length { return false; }
  if b.min_lat_ud > b.max_lat_ud { return false; }
  if b.min_lon_ud > b.max_lon_ud { return false; }
  if !maidenhead_box_contains(b, point_lat, point_lon) { return false; }
  let c: Result[Str, Str] = maidenhead_encode(b.center_lat_ud, b.center_lon_ud, length);
  if !c.is_ok { return false; }
  if !streq(c.value, loc) { return false; }
  let sw: Result[Str, Str] = maidenhead_encode(b.min_lat_ud, b.min_lon_ud, length);
  if !sw.is_ok { return false; }
  if !streq(sw.value, loc) { return false; }
  let se: Result[Str, Str] = maidenhead_encode(b.min_lat_ud, b.max_lon_ud, length);
  if !se.is_ok { return false; }
  if !streq(se.value, loc) { return false; }
  let nw: Result[Str, Str] = maidenhead_encode(b.max_lat_ud, b.min_lon_ud, length);
  if !nw.is_ok { return false; }
  if !streq(nw.value, loc) { return false; }
  let ne: Result[Str, Str] = maidenhead_encode(b.max_lat_ud, b.max_lon_ud, length);
  if !ne.is_ok { return false; }
  if !streq(ne.value, loc) { return false; }
  return true;
}

fn t1() -> TestResult {
  let l2: Result[Str, Str] = maidenhead_encode(51500700, -127800, 2);
  var ok = l2.is_ok;
  if ok && !streq(l2.value, "IO") { ok = false; }
  let l4: Result[Str, Str] = maidenhead_encode(51500700, -127800, 4);
  if !l4.is_ok { ok = false; }
  if l4.is_ok && !streq(l4.value, "IO91") { ok = false; }
  let l6: Result[Str, Str] = maidenhead_encode(51500700, -127800, 6);
  if !l6.is_ok { ok = false; }
  if l6.is_ok && !streq(l6.value, "IO91WM") { ok = false; }
  let l8: Result[Str, Str] = maidenhead_encode(51500700, -127800, 8);
  if !l8.is_ok { ok = false; }
  if l8.is_ok && !streq(l8.value, "IO91WM40") { ok = false; }
  return assert(ok, "encode London 51.5007N 0.1278W at lengths 2/4/6/8");
}

fn t2() -> TestResult {
  let a: Result[Str, Str] = maidenhead_encode(52370216, 4895168, 6);
  var ok = a.is_ok;
  if ok && !streq(a.value, "JO22KI") { ok = false; }
  let s: Result[Str, Str] = maidenhead_encode(-33868800, 151209300, 8);
  if !s.is_ok { ok = false; }
  if s.is_ok && !streq(s.value, "QF56OD51") { ok = false; }
  let n: Result[Str, Str] = maidenhead_encode(40712800, -74006000, 6);
  if !n.is_ok { ok = false; }
  if n.is_ok && !streq(n.value, "FN20XR") { ok = false; }
  let h: Result[Str, Str] = maidenhead_encode(60169900, 24938400, 6);
  if !h.is_ok { ok = false; }
  if h.is_ok && !streq(h.value, "KP20LE") { ok = false; }
  return assert(ok, "encode Amsterdam, Sydney, New York and Helsinki");
}

fn t3() -> TestResult {
  let e: Result[Str, Str] = maidenhead_encode(0, 0, 8);
  var ok = e.is_ok;
  if ok && !streq(e.value, "JJ00AA00") { ok = false; }
  let d: Result[MaidenheadBox, Str] = maidenhead_decode("JJ00AA00");
  if !d.is_ok { ok = false; }
  if d.is_ok {
    let b: MaidenheadBox = d.value;
    if !box_ok(b, 8, 0, 4166, 0, 8333, 2083, 4166) { ok = false; }
    if !maidenhead_box_contains(b, 0, 0) { ok = false; }
    if !maidenhead_box_contains(b, 4166, 8333) { ok = false; }
    if maidenhead_box_contains(b, 4167, 0) { ok = false; }
    if maidenhead_box_contains(b, 0, 8334) { ok = false; }
    if maidenhead_box_contains(b, -1, 0) { ok = false; }
    if maidenhead_box_contains(b, 0, -1) { ok = false; }
  }
  return assert(ok, "null island encodes to JJ00AA00 with box [0,4166]x[0,8333]");
}

fn t4() -> TestResult {
  let sw: Result[Str, Str] = maidenhead_encode(-90000000, -180000000, 8);
  var ok = sw.is_ok;
  if ok && !streq(sw.value, "AA00AA00") { ok = false; }
  let ne: Result[Str, Str] = maidenhead_encode(90000000, 180000000, 8);
  if !ne.is_ok { ok = false; }
  if ne.is_ok && !streq(ne.value, "RR99XX99") { ok = false; }
  let nw: Result[Str, Str] = maidenhead_encode(90000000, -180000000, 8);
  if !nw.is_ok { ok = false; }
  if nw.is_ok && !streq(nw.value, "AR09AX09") { ok = false; }
  let se: Result[Str, Str] = maidenhead_encode(-90000000, 180000000, 8);
  if !se.is_ok { ok = false; }
  if se.is_ok && !streq(se.value, "RA90XA90") { ok = false; }
  let r2: Result[Str, Str] = maidenhead_encode(90000000, 180000000, 2);
  if !r2.is_ok { ok = false; }
  if r2.is_ok && !streq(r2.value, "RR") { ok = false; }
  let r4: Result[Str, Str] = maidenhead_encode(90000000, 180000000, 4);
  if !r4.is_ok { ok = false; }
  if r4.is_ok && !streq(r4.value, "RR99") { ok = false; }
  let r6: Result[Str, Str] = maidenhead_encode(90000000, 180000000, 6);
  if !r6.is_ok { ok = false; }
  if r6.is_ok && !streq(r6.value, "RR99XX") { ok = false; }
  return assert(ok, "the four range corners and the north-east prefixes");
}

fn t5() -> TestResult {
  let w: Result[Str, Str] = maidenhead_encode(0, -1, 8);
  var ok = w.is_ok;
  if ok && !streq(w.value, "IJ90XA90") { ok = false; }
  let s: Result[Str, Str] = maidenhead_encode(-1, 0, 8);
  if !s.is_ok { ok = false; }
  if s.is_ok && !streq(s.value, "JI09AX09") { ok = false; }
  let c: Result[Str, Str] = maidenhead_encode(0, 0, 8);
  if !c.is_ok { ok = false; }
  if c.is_ok && !streq(c.value, "JJ00AA00") { ok = false; }
  let e: Result[Str, Str] = maidenhead_encode(0, 1, 8);
  if !e.is_ok { ok = false; }
  if e.is_ok && !streq(e.value, "JJ00AA00") { ok = false; }
  let n: Result[Str, Str] = maidenhead_encode(1, 0, 8);
  if !n.is_ok { ok = false; }
  if n.is_ok && !streq(n.value, "JJ00AA00") { ok = false; }
  let i: Result[Str, Str] = maidenhead_encode(89999999, 179999999, 8);
  if !i.is_ok { ok = false; }
  if i.is_ok && !streq(i.value, "RR99XX99") { ok = false; }
  return assert(ok, "edges select the upper cell and the top edge clamps");
}

fn t6() -> TestResult {
  var ok = str_err_eq(maidenhead_encode(0, 0, 0), "maidenhead: invalid length");
  if !str_err_eq(maidenhead_encode(0, 0, 1), "maidenhead: invalid length") { ok = false; }
  if !str_err_eq(maidenhead_encode(0, 0, 3), "maidenhead: invalid length") { ok = false; }
  if !str_err_eq(maidenhead_encode(0, 0, 5), "maidenhead: invalid length") { ok = false; }
  if !str_err_eq(maidenhead_encode(0, 0, 7), "maidenhead: invalid length") { ok = false; }
  if !str_err_eq(maidenhead_encode(0, 0, 9), "maidenhead: invalid length") { ok = false; }
  if !str_err_eq(maidenhead_encode(0, 0, 10), "maidenhead: invalid length") { ok = false; }
  if !str_err_eq(maidenhead_encode(0, 0, -2), "maidenhead: invalid length") { ok = false; }
  if !str_err_eq(maidenhead_encode(90000001, 180000001, 3), "maidenhead: invalid length") { ok = false; }
  return assert(ok, "encode rejects lengths outside 2/4/6/8 (checked first)");
}

fn t7() -> TestResult {
  var ok = str_err_eq(maidenhead_encode(90000001, 0, 8), "maidenhead: latitude out of range");
  if !str_err_eq(maidenhead_encode(-90000001, 0, 8), "maidenhead: latitude out of range") { ok = false; }
  if !str_err_eq(maidenhead_encode(90000001, 0, 2), "maidenhead: latitude out of range") { ok = false; }
  let hi: Result[Str, Str] = maidenhead_encode(90000000, 0, 8);
  if !hi.is_ok { ok = false; }
  let lo: Result[Str, Str] = maidenhead_encode(-90000000, 0, 8);
  if !lo.is_ok { ok = false; }
  return assert(ok, "encode rejects |lat| > 90 degrees; bounds are inclusive");
}

fn t8() -> TestResult {
  var ok = str_err_eq(maidenhead_encode(0, 180000001, 8), "maidenhead: longitude out of range");
  if !str_err_eq(maidenhead_encode(0, -180000001, 8), "maidenhead: longitude out of range") { ok = false; }
  if !str_err_eq(maidenhead_encode(0, 180000001, 2), "maidenhead: longitude out of range") { ok = false; }
  let hi: Result[Str, Str] = maidenhead_encode(0, 180000000, 8);
  if !hi.is_ok { ok = false; }
  let lo: Result[Str, Str] = maidenhead_encode(0, -180000000, 8);
  if !lo.is_ok { ok = false; }
  return assert(ok, "encode rejects |lon| > 180 degrees; bounds are inclusive");
}

fn t9() -> TestResult {
  let d: Result[MaidenheadBox, Str] = maidenhead_decode("JO22KI");
  var ok = d.is_ok;
  if ok {
    let b: MaidenheadBox = d.value;
    if !box_ok(b, 6, 52333334, 52374999, 4833334, 4916666, 52354166, 4875000) { ok = false; }
    if maidenhead_box_length(b) != 6 { ok = false; }
    if maidenhead_box_min_lat(b) != 52333334 { ok = false; }
    if maidenhead_box_max_lat(b) != 52374999 { ok = false; }
    if maidenhead_box_min_lon(b) != 4833334 { ok = false; }
    if maidenhead_box_max_lon(b) != 4916666 { ok = false; }
    if !maidenhead_box_contains(b, 52354166, 4875000) { ok = false; }
    if !maidenhead_box_contains(b, 52333334, 4833334) { ok = false; }
    if !maidenhead_box_contains(b, 52374999, 4916666) { ok = false; }
    if maidenhead_box_contains(b, 52333333, 4875000) { ok = false; }
    if maidenhead_box_contains(b, 52354166, 4916667) { ok = false; }
  }
  return assert(ok, "decode JO22KI box, center and inclusive containment");
}

fn t10() -> TestResult {
  let d2: Result[MaidenheadBox, Str] = maidenhead_decode("JO");
  var ok = d2.is_ok;
  if ok {
    let b: MaidenheadBox = d2.value;
    if !box_ok(b, 2, 50000000, 59999999, 0, 19999999, 54999999, 9999999) { ok = false; }
  }
  let d4: Result[MaidenheadBox, Str] = maidenhead_decode("IO91");
  if !d4.is_ok { ok = false; }
  if d4.is_ok {
    let c: MaidenheadBox = d4.value;
    if !box_ok(c, 4, 51000000, 51999999, -2000000, -1, 51499999, -1000000) { ok = false; }
  }
  return assert(ok, "decode the field and square boxes JO and IO91");
}

fn t11() -> TestResult {
  let a: Result[MaidenheadBox, Str] = maidenhead_decode("AA00AA00");
  var ok = a.is_ok;
  if ok {
    let b: MaidenheadBox = a.value;
    if !box_ok(b, 8, -90000000, -89995834, -180000000, -179991667, -89997917, -179995833) { ok = false; }
  }
  let r: Result[MaidenheadBox, Str] = maidenhead_decode("RR99XX99");
  if !r.is_ok { ok = false; }
  if r.is_ok {
    let c: MaidenheadBox = r.value;
    if !box_ok(c, 8, 89995834, 90000000, 179991667, 180000000, 89997917, 179995833) { ok = false; }
  }
  let nw: Result[MaidenheadBox, Str] = maidenhead_decode("AR09AX09");
  if !nw.is_ok { ok = false; }
  if nw.is_ok {
    let e: MaidenheadBox = nw.value;
    if !box_ok(e, 8, 89995834, 90000000, -180000000, -179991667, 89997917, -179995833) { ok = false; }
  }
  let se: Result[MaidenheadBox, Str] = maidenhead_decode("RA90XA90");
  if !se.is_ok { ok = false; }
  if se.is_ok {
    let f: MaidenheadBox = se.value;
    if !box_ok(f, 8, -90000000, -89995834, 179991667, 180000000, -89997917, 179995833) { ok = false; }
  }
  return assert(ok, "corner cells: top maxima clamp and negative centers truncate");
}

fn t12() -> TestResult {
  var ok = decode_err_eq(maidenhead_decode(""), "maidenhead: empty locator");
  if !decode_err_eq(maidenhead_decode("J"), "maidenhead: invalid locator length") { ok = false; }
  if !decode_err_eq(maidenhead_decode("JO2"), "maidenhead: invalid locator length") { ok = false; }
  if !decode_err_eq(maidenhead_decode("JO22K"), "maidenhead: invalid locator length") { ok = false; }
  if !decode_err_eq(maidenhead_decode("JO22KI7"), "maidenhead: invalid locator length") { ok = false; }
  if !decode_err_eq(maidenhead_decode("JO22KI7890"), "maidenhead: invalid locator length") { ok = false; }
  if !decode_err_eq(maidenhead_decode("!!!!!!!!!!!"), "maidenhead: invalid locator length") { ok = false; }
  return assert(ok, "decode rejects empty and non-2/4/6/8 lengths before characters");
}

fn t13() -> TestResult {
  var ok = decode_err_eq(maidenhead_decode("SO"), "maidenhead: invalid field letter");
  if !decode_err_eq(maidenhead_decode("1O"), "maidenhead: invalid field letter") { ok = false; }
  if !decode_err_eq(maidenhead_decode("J1"), "maidenhead: invalid field letter") { ok = false; }
  if !decode_err_eq(maidenhead_decode("so"), "maidenhead: invalid field letter") { ok = false; }
  if !decode_err_eq(maidenhead_decode("S022"), "maidenhead: invalid field letter") { ok = false; }
  if !decode_err_eq(maidenhead_decode("J!"), "maidenhead: invalid field letter") { ok = false; }
  let good: Result[MaidenheadBox, Str] = maidenhead_decode("JO");
  if !good.is_ok { ok = false; }
  return assert(ok, "decode rejects field letters outside A-R");
}

fn t14() -> TestResult {
  var ok = decode_err_eq(maidenhead_decode("JO2A"), "maidenhead: invalid square digit");
  if !decode_err_eq(maidenhead_decode("JOAA"), "maidenhead: invalid square digit") { ok = false; }
  if !decode_err_eq(maidenhead_decode("JO 2"), "maidenhead: invalid square digit") { ok = false; }
  if !decode_err_eq(maidenhead_decode("JO-2"), "maidenhead: invalid square digit") { ok = false; }
  let good: Result[MaidenheadBox, Str] = maidenhead_decode("JO22");
  if !good.is_ok { ok = false; }
  return assert(ok, "decode rejects square digits outside 0-9");
}

fn t15() -> TestResult {
  var ok = decode_err_eq(maidenhead_decode("JO22YY"), "maidenhead: invalid subsquare letter");
  if !decode_err_eq(maidenhead_decode("JO22K1"), "maidenhead: invalid subsquare letter") { ok = false; }
  if !decode_err_eq(maidenhead_decode("JO221X"), "maidenhead: invalid subsquare letter") { ok = false; }
  if !decode_err_eq(maidenhead_decode("JO22y!"), "maidenhead: invalid subsquare letter") { ok = false; }
  let good: Result[MaidenheadBox, Str] = maidenhead_decode("JO22KI");
  if !good.is_ok { ok = false; }
  return assert(ok, "decode rejects subsquare letters outside A-X");
}

fn t16() -> TestResult {
  var ok = decode_err_eq(maidenhead_decode("JO22KIAA"), "maidenhead: invalid extended square digit");
  if !decode_err_eq(maidenhead_decode("JO22KI7A"), "maidenhead: invalid extended square digit") { ok = false; }
  if !decode_err_eq(maidenhead_decode("JO22KI!0"), "maidenhead: invalid extended square digit") { ok = false; }
  let good: Result[MaidenheadBox, Str] = maidenhead_decode("JO22KI78");
  if !good.is_ok { ok = false; }
  return assert(ok, "decode rejects extended square digits outside 0-9");
}

fn t17() -> TestResult {
  let low: Result[MaidenheadBox, Str] = maidenhead_decode("jo22ki");
  let up: Result[MaidenheadBox, Str] = maidenhead_decode("JO22KI");
  var ok = low.is_ok && up.is_ok;
  if ok {
    let a: MaidenheadBox = low.value;
    let b: MaidenheadBox = up.value;
    if a.length != b.length { ok = false; }
    if a.min_lat_ud != b.min_lat_ud { ok = false; }
    if a.max_lat_ud != b.max_lat_ud { ok = false; }
    if a.min_lon_ud != b.min_lon_ud { ok = false; }
    if a.max_lon_ud != b.max_lon_ud { ok = false; }
    if a.center_lat_ud != b.center_lat_ud { ok = false; }
    if a.center_lon_ud != b.center_lon_ud { ok = false; }
  }
  let n1: Result[Str, Str] = maidenhead_normalize("jo22ki");
  if !n1.is_ok { ok = false; }
  if n1.is_ok && !streq(n1.value, "JO22KI") { ok = false; }
  let n2: Result[Str, Str] = maidenhead_normalize("Jo22kI");
  if !n2.is_ok { ok = false; }
  if n2.is_ok && !streq(n2.value, "JO22KI") { ok = false; }
  return assert(ok, "decode and normalize fold lowercase input to uppercase");
}

fn t18() -> TestResult {
  let plain: Result[Str, Str] = maidenhead_normalize("JO22KI78");
  var ok = plain.is_ok;
  if ok && !streq(plain.value, "JO22KI78") { ok = false; }
  if !str_err_eq(maidenhead_normalize(""), "maidenhead: empty locator") { ok = false; }
  if !str_err_eq(maidenhead_normalize("J"), "maidenhead: invalid locator length") { ok = false; }
  if !str_err_eq(maidenhead_normalize("JO2!"), "maidenhead: invalid square digit") { ok = false; }
  if !str_err_eq(maidenhead_normalize("JO22YZ"), "maidenhead: invalid subsquare letter") { ok = false; }
  if !str_err_eq(maidenhead_normalize("JO22KI9A"), "maidenhead: invalid extended square digit") { ok = false; }
  return assert(ok, "normalize is idempotent and shares the decode error catalog");
}

fn t19() -> TestResult {
  let f: Result[Str, Str] = maidenhead_field("jo22ki78");
  var ok = f.is_ok;
  if ok && !streq(f.value, "JO") { ok = false; }
  let sq: Result[Str, Str] = maidenhead_square("jo22ki78");
  if !sq.is_ok { ok = false; }
  if sq.is_ok && !streq(sq.value, "22") { ok = false; }
  let ss: Result[Str, Str] = maidenhead_subsquare("jo22ki78");
  if !ss.is_ok { ok = false; }
  if ss.is_ok && !streq(ss.value, "KI") { ok = false; }
  let ex: Result[Str, Str] = maidenhead_ext_square("jo22ki78");
  if !ex.is_ok { ok = false; }
  if ex.is_ok && !streq(ex.value, "78") { ok = false; }
  let l2: Result[Int, Str] = maidenhead_locator_length("jo");
  if !l2.is_ok { ok = false; }
  if l2.is_ok && l2.value != 2 { ok = false; }
  let l4: Result[Int, Str] = maidenhead_locator_length("JO22");
  if !l4.is_ok { ok = false; }
  if l4.is_ok && l4.value != 4 { ok = false; }
  let l6: Result[Int, Str] = maidenhead_locator_length("JO22KI");
  if !l6.is_ok { ok = false; }
  if l6.is_ok && l6.value != 6 { ok = false; }
  let l8: Result[Int, Str] = maidenhead_locator_length("JO22KI78");
  if !l8.is_ok { ok = false; }
  if l8.is_ok && l8.value != 8 { ok = false; }
  if !str_err_eq(maidenhead_square("JO"), "maidenhead: square part missing") { ok = false; }
  if !str_err_eq(maidenhead_subsquare("JO22"), "maidenhead: subsquare part missing") { ok = false; }
  if !str_err_eq(maidenhead_ext_square("JO22KI"), "maidenhead: extended square part missing") { ok = false; }
  if !int_err_eq(maidenhead_locator_length("J!"), "maidenhead: invalid field letter") { ok = false; }
  return assert(ok, "part accessors split a locator and report missing levels");
}

fn t20() -> TestResult {
  var ok = true;
  var p: Int = 2;
  while p <= 8 {
    if !roundtrip_p(57649110, 10407440, p) { ok = false; }
    if !roundtrip_p(0, 0, p) { ok = false; }
    if !roundtrip_p(90000000, 0, p) { ok = false; }
    if !roundtrip_p(-90000000, 0, p) { ok = false; }
    if !roundtrip_p(0, 180000000, p) { ok = false; }
    if !roundtrip_p(0, -180000000, p) { ok = false; }
    if !roundtrip_p(90000000, 180000000, p) { ok = false; }
    if !roundtrip_p(-90000000, -180000000, p) { ok = false; }
    p = p + 2;
  }
  return assert(ok, "round trip points, poles and the antimeridian at every length");
}

fn t21() -> TestResult {
  let two: Result[Str, Str] = maidenhead_encode(51500700, -127800, 2);
  let four: Result[Str, Str] = maidenhead_encode(51500700, -127800, 4);
  let six: Result[Str, Str] = maidenhead_encode(51500700, -127800, 6);
  let eight: Result[Str, Str] = maidenhead_encode(51500700, -127800, 8);
  var ok = two.is_ok && four.is_ok && six.is_ok && eight.is_ok;
  if ok {
    let a: Str = two.value;
    let b: Str = four.value;
    let c: Str = six.value;
    let d: Str = eight.value;
    if !streq(a, string.str_slice(b, 0, 2)) { ok = false; }
    if !streq(b, string.str_slice(c, 0, 4)) { ok = false; }
    if !streq(c, string.str_slice(d, 0, 6)) { ok = false; }
    if d.len() != 8 { ok = false; }
  }
  let sq: Result[MaidenheadBox, Str] = maidenhead_decode("JO22");
  if !sq.is_ok { ok = false; }
  if sq.is_ok {
    let s: MaidenheadBox = sq.value;
    if s.max_lat_ud - s.min_lat_ud != 999999 { ok = false; }
    if s.max_lon_ud - s.min_lon_ud != 1999999 { ok = false; }
  }
  let us: Result[MaidenheadBox, Str] = maidenhead_decode("JO22KI");
  if !us.is_ok { ok = false; }
  if us.is_ok {
    let u: MaidenheadBox = us.value;
    if u.max_lat_ud - u.min_lat_ud != 41665 { ok = false; }
    if u.max_lon_ud - u.min_lon_ud != 83332 { ok = false; }
  }
  return assert(ok, "locators nest by prefix and cell spans match the precision table");
}

fn main() -> Int {
  io.println("=== xiom.maidenhead conformance tests ===");
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
    io.println("xiom.maidenhead: all tests passed");
  } else {
    io.println("xiom.maidenhead: tests failed");
  }
  return failed;
}
