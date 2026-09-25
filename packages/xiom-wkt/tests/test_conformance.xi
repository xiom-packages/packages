// XIOM -- xiom.wkt conformance tests (27 checks)
// Port task: prove the pure-XIOM xiom.wkt codec against its SPEC.md subset.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module wkt_tests
use xiom.io; use xiom.test; use xiom.wkt;
use xiom.string;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every text check
// below is routed through streq or a helper that calls it.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when the document parses without error.
fn parses(text: Str) -> Bool {
  let r = wkt_parse(text);
  match r {
    Ok(_) => { return true; },
    Err(_) => { return false; },
  }
  return false;
}

// True when parsing fails with exactly the error `want`.
fn err_is(text: Str, want: Str) -> Bool {
  let r = wkt_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when parsing fails with an error that starts with `want`.
fn err_prefix(text: Str, want: Str) -> Bool {
  let r = wkt_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => {
      if e.len() < want.len() { return false; }
      return streq(string.str_slice(e, 0, want.len()), want);
    },
  }
  return false;
}

// True when parse-then-canonical-emit yields exactly `want`.
fn emits(text: Str, want: Str) -> Bool {
  let r = wkt_parse(text);
  match r {
    Ok(d) => { return streq(wkt_write(&d), want); },
    Err(_) => { return false; },
  }
  return false;
}

// True when `text`, its canonical form, and the canonical form re-parsed all
// describe the same document.
fn roundtrip(text: Str) -> Bool {
  let r = wkt_parse(text);
  match r {
    Ok(d) => {
      let first = wkt_write(&d);
      let r2 = wkt_parse(first);
      match r2 {
        Ok(d2) => { return streq(wkt_write(&d2), first); },
        Err(_) => { return false; },
      }
      return false;
    },
    Err(_) => { return false; },
  }
  return false;
}

// True when wkt_normalize(text) returns exactly `want`.
fn norm_is(text: Str, want: Str) -> Bool {
  let r = wkt_normalize(text);
  match r {
    Ok(s) => { return streq(s, want); },
    Err(_) => { return false; },
  }
  return false;
}

fn type_of(text: Str, i: Int) -> Str {
  let r = wkt_parse(text);
  match r {
    Ok(d) => { return wkt_type(&d, i); },
    Err(_) => { return "<error>"; },
  }
  return "<error>";
}

fn child_type_of(text: Str, i: Int, k: Int) -> Str {
  let r = wkt_parse(text);
  match r {
    Ok(d) => { return wkt_type(&d, wkt_child(&d, i, k)); },
    Err(_) => { return "<error>"; },
  }
  return "<error>";
}

fn child_of(text: Str, i: Int, k: Int) -> Int {
  let r = wkt_parse(text);
  match r {
    Ok(d) => { return wkt_child(&d, i, k); },
    Err(_) => { return -99; },
  }
  return -99;
}

fn marker_of(text: Str, i: Int) -> Int {
  let r = wkt_parse(text);
  match r {
    Ok(d) => { return wkt_marker(&d, i); },
    Err(_) => { return -99; },
  }
  return -99;
}

fn arity_of(text: Str, i: Int) -> Int {
  let r = wkt_parse(text);
  match r {
    Ok(d) => { return wkt_coord_arity(&d, i); },
    Err(_) => { return -99; },
  }
  return -99;
}

fn empty_of(text: Str, i: Int) -> Bool {
  let r = wkt_parse(text);
  match r {
    Ok(d) => { return wkt_is_empty(&d, i); },
    Err(_) => { return false; },
  }
  return false;
}

fn parent_of(text: Str, i: Int) -> Int {
  let r = wkt_parse(text);
  match r {
    Ok(d) => { return wkt_parent(&d, i); },
    Err(_) => { return -99; },
  }
  return -99;
}

fn geom_count_of(text: Str) -> Int {
  let r = wkt_parse(text);
  match r {
    Ok(d) => { return wkt_geometry_count(&d); },
    Err(_) => { return -99; },
  }
  return -99;
}

fn coord_count_of(text: Str) -> Int {
  let r = wkt_parse(text);
  match r {
    Ok(d) => { return wkt_coord_count(&d); },
    Err(_) => { return -99; },
  }
  return -99;
}

fn child_count_of(text: Str, i: Int) -> Int {
  let r = wkt_parse(text);
  match r {
    Ok(d) => { return wkt_child_count(&d, i); },
    Err(_) => { return -99; },
  }
  return -99;
}

fn count_of(text: Str, i: Int) -> Int {
  let r = wkt_parse(text);
  match r {
    Ok(d) => { return wkt_point_count(&d, i); },
    Err(_) => { return -99; },
  }
  return -99;
}

fn ring_count_of(text: Str, i: Int) -> Int {
  let r = wkt_parse(text);
  match r {
    Ok(d) => { return wkt_ring_count(&d, i); },
    Err(_) => { return -99; },
  }
  return -99;
}

fn ring_pt_count_of(text: Str, r: Int) -> Int {
  let r2 = wkt_parse(text);
  match r2 {
    Ok(d) => { return wkt_ring_point_count(&d, r); },
    Err(_) => { return -99; },
  }
  return -99;
}

fn ring_parent_of(text: Str, r: Int) -> Int {
  let rr = wkt_parse(text);
  match rr {
    Ok(d) => { return wkt_ring_parent(&d, r); },
    Err(_) => { return -99; },
  }
  return -99;
}

fn ring_pt_start_of(text: Str, r: Int) -> Int {
  let rr = wkt_parse(text);
  match rr {
    Ok(d) => { return wkt_ring_point_start(&d, r); },
    Err(_) => { return -99; },
  }
  return -99;
}

fn x_of(text: Str, p: Int) -> Str {
  let r = wkt_parse(text);
  match r {
    Ok(d) => { return wkt_x(&d, p); },
    Err(_) => { return "<error>"; },
  }
  return "<error>";
}

fn y_of(text: Str, p: Int) -> Str {
  let r = wkt_parse(text);
  match r {
    Ok(d) => { return wkt_y(&d, p); },
    Err(_) => { return "<error>"; },
  }
  return "<error>";
}

fn z_of(text: Str, p: Int) -> Str {
  let r = wkt_parse(text);
  match r {
    Ok(d) => { return wkt_z(&d, p); },
    Err(_) => { return "<error>"; },
  }
  return "<error>";
}

fn m_of(text: Str, p: Int) -> Str {
  let r = wkt_parse(text);
  match r {
    Ok(d) => { return wkt_m(&d, p); },
    Err(_) => { return "<error>"; },
  }
  return "<error>";
}

const _P_CIRCLE: Str = "GEOMETRYCOLLECTION (POINT (40 10), LINESTRING (10 10, 20 20, 10 40), POLYGON ((40 40, 20 45, 45 30, 40 40)))";
const _P_NESTED: Str = "GEOMETRYCOLLECTION (POINT (1 2), GEOMETRYCOLLECTION (LINESTRING (0 0, 1 1)), POLYGON ((0 0, 1 0, 1 1, 0 0)))";
const _P_POLY: Str = "POLYGON ((35 10, 45 45, 15 40, 10 20, 35 10), (20 30, 35 35, 30 20, 20 30))";
const _P_MPOINT: Str = "MULTIPOINT ((10 40), (40 30), (20 20), (30 10))";
const _P_MLINE: Str = "MULTILINESTRING ((10 10, 20 20, 10 40), (40 40, 30 30, 40 20, 30 10))";
const _P_MPOLY: Str = "MULTIPOLYGON (((30 20, 45 40, 10 40, 30 20)), ((15 5, 40 10, 10 20, 5 10, 15 5)))";

fn t1() -> TestResult {
  let p = "POINT (30 10)";
  var ok = parses(p);
  if geom_count_of(p) != 1 { ok = false; }
  if !streq(type_of(p, 0), "POINT") { ok = false; }
  if empty_of(p, 0) { ok = false; }
  if parent_of(p, 0) != -1 { ok = false; }
  if marker_of(p, 0) != 0 { ok = false; }
  if arity_of(p, 0) != 2 { ok = false; }
  if count_of(p, 0) != 1 { ok = false; }
  if coord_count_of(p) != 1 { ok = false; }
  if !streq(x_of(p, 0), "30") { ok = false; }
  if !streq(y_of(p, 0), "10") { ok = false; }
  if !streq(z_of(p, 0), "") { ok = false; }
  if !streq(m_of(p, 0), "") { ok = false; }
  return assert(ok, "point: element, arity, coordinate text and z/m absence");
}

fn t2() -> TestResult {
  var ok = emits("  point(30   10)  ", "POINT (30 10)");
  if !emits("PoInT ( 1.5 2 )", "POINT (1.5 2)") { ok = false; }
  if !emits("Linestring(0 0,1 1)", "LINESTRING (0 0, 1 1)") { ok = false; }
  return assert(ok, "keywords are case-insensitive and whitespace is canonicalized");
}

fn t3() -> TestResult {
  let p = "POINT (+1.50E-2 -0.5)";
  var ok = emits(p, "POINT (+1.50E-2 -0.5)");
  if !streq(x_of(p, 0), "+1.50E-2") { ok = false; }
  if !streq(y_of(p, 0), "-0.5") { ok = false; }
  if !emits("POINT (001 -0)", "POINT (001 -0)") { ok = false; }
  if !emits("POINT (1e3 2E+4)", "POINT (1e3 2E+4)") { ok = false; }
  return assert(ok, "coordinate tokens are kept verbatim (no float conversion)");
}

fn t4() -> TestResult {
  let l = "LINESTRING(30 10,10 30,  40 40)";
  var ok = emits(l, "LINESTRING (30 10, 10 30, 40 40)");
  if geom_count_of(l) != 1 { ok = false; }
  if count_of(l, 0) != 3 { ok = false; }
  if coord_count_of(l) != 3 { ok = false; }
  if !streq(x_of(l, 1), "10") { ok = false; }
  if !streq(y_of(l, 2), "40") { ok = false; }
  return assert(ok, "linestring: vertices, counts and canonical spacing");
}

fn t5() -> TestResult {
  var ok = emits("POINT EMPTY", "POINT EMPTY");
  if !emits("linestring empty", "LINESTRING EMPTY") { ok = false; }
  if !emits("POLYGON EMPTY", "POLYGON EMPTY") { ok = false; }
  if !emits("MULTIPOINT EMPTY", "MULTIPOINT EMPTY") { ok = false; }
  if !emits("MULTILINESTRING EMPTY", "MULTILINESTRING EMPTY") { ok = false; }
  if !emits("MULTIPOLYGON EMPTY", "MULTIPOLYGON EMPTY") { ok = false; }
  if !emits("GEOMETRYCOLLECTION EMPTY", "GEOMETRYCOLLECTION EMPTY") { ok = false; }
  if !empty_of("POINT EMPTY", 0) { ok = false; }
  if count_of("POINT EMPTY", 0) != 0 { ok = false; }
  if ring_count_of("POLYGON EMPTY", 0) != 0 { ok = false; }
  if child_count_of("MULTIPOINT EMPTY", 0) != 0 { ok = false; }
  return assert(ok, "EMPTY variants: flag set, no spans, canonical emit");
}

fn t6() -> TestResult {
  var ok = emits(_P_POLY, _P_POLY);
  if ring_count_of(_P_POLY, 0) != 2 { ok = false; }
  if ring_pt_count_of(_P_POLY, 0) != 5 { ok = false; }
  if ring_pt_count_of(_P_POLY, 1) != 4 { ok = false; }
  if ring_parent_of(_P_POLY, 1) != 0 { ok = false; }
  if ring_pt_start_of(_P_POLY, 1) != 5 { ok = false; }
  if count_of(_P_POLY, 0) != 9 { ok = false; }
  if !streq(x_of(_P_POLY, 0), "35") { ok = false; }
  if !streq(y_of(_P_POLY, 8), "30") { ok = false; }
  return assert(ok, "polygon: rings, per-ring spans and coordinate access");
}

fn t7() -> TestResult {
  var ok = emits(_P_MPOINT, _P_MPOINT);
  if geom_count_of(_P_MPOINT) != 5 { ok = false; }
  if child_count_of(_P_MPOINT, 0) != 4 { ok = false; }
  if !streq(child_type_of(_P_MPOINT, 0, 0), "POINT") { ok = false; }
  if !streq(child_type_of(_P_MPOINT, 0, 3), "POINT") { ok = false; }
  if parent_of(_P_MPOINT, 3) != 0 { ok = false; }
  if count_of(_P_MPOINT, 0) != 4 { ok = false; }
  if !streq(x_of(_P_MPOINT, 0), "10") { ok = false; }
  if !streq(y_of(_P_MPOINT, 3), "10") { ok = false; }
  return assert(ok, "multipoint: parenthesized points become POINT children");
}

fn t8() -> TestResult {
  var ok = emits(_P_MLINE, _P_MLINE);
  if geom_count_of(_P_MLINE) != 3 { ok = false; }
  if child_count_of(_P_MLINE, 0) != 2 { ok = false; }
  if !streq(child_type_of(_P_MLINE, 0, 0), "LINESTRING") { ok = false; }
  if count_of(_P_MLINE, 0) != 7 { ok = false; }
  if count_of(_P_MLINE, 1) != 3 { ok = false; }
  if count_of(_P_MLINE, 2) != 4 { ok = false; }
  if parent_of(_P_MLINE, 2) != 0 { ok = false; }
  return assert(ok, "multilinestring: children, subtree counts and parents");
}

fn t9() -> TestResult {
  var ok = emits(_P_MPOLY, _P_MPOLY);
  if geom_count_of(_P_MPOLY) != 3 { ok = false; }
  if !streq(child_type_of(_P_MPOLY, 0, 1), "POLYGON") { ok = false; }
  if ring_count_of(_P_MPOLY, 0) != 2 { ok = false; }
  if ring_count_of(_P_MPOLY, 1) != 1 { ok = false; }
  if ring_pt_count_of(_P_MPOLY, 0) != 4 { ok = false; }
  if ring_pt_count_of(_P_MPOLY, 1) != 5 { ok = false; }
  if ring_parent_of(_P_MPOLY, 1) != 2 { ok = false; }
  return assert(ok, "multipolygon: polygons, rings and ring ownership");
}

fn t10() -> TestResult {
  var ok = emits(_P_CIRCLE, _P_CIRCLE);
  if geom_count_of(_P_CIRCLE) != 4 { ok = false; }
  if child_count_of(_P_CIRCLE, 0) != 3 { ok = false; }
  if !streq(child_type_of(_P_CIRCLE, 0, 0), "POINT") { ok = false; }
  if !streq(child_type_of(_P_CIRCLE, 0, 1), "LINESTRING") { ok = false; }
  if !streq(child_type_of(_P_CIRCLE, 0, 2), "POLYGON") { ok = false; }
  if count_of(_P_CIRCLE, 0) != 8 { ok = false; }
  if parent_of(_P_CIRCLE, 3) != 0 { ok = false; }
  return assert(ok, "geometrycollection: mixed members and subtree totals");
}

fn t11() -> TestResult {
  let z = "POINT Z (1 2 3)";
  var ok = emits(z, z);
  if marker_of(z, 0) != 1 { ok = false; }
  if arity_of(z, 0) != 3 { ok = false; }
  if !streq(z_of(z, 0), "3") { ok = false; }
  if !streq(m_of(z, 0), "") { ok = false; }
  let m = "POINT M (1 2 3)";
  if !emits(m, m) { ok = false; }
  if marker_of(m, 0) != 2 { ok = false; }
  if !streq(z_of(m, 0), "") { ok = false; }
  if !streq(m_of(m, 0), "3") { ok = false; }
  let zm = "POINT ZM (1 2 3 4)";
  if !emits(zm, zm) { ok = false; }
  if marker_of(zm, 0) != 3 { ok = false; }
  if arity_of(zm, 0) != 4 { ok = false; }
  if !streq(z_of(zm, 0), "3") { ok = false; }
  if !streq(m_of(zm, 0), "4") { ok = false; }
  if !emits("point z empty", "POINT Z EMPTY") { ok = false; }
  if marker_of("POINT Z EMPTY", 0) != 1 { ok = false; }
  if !empty_of("POINT Z EMPTY", 0) { ok = false; }
  return assert(ok, "ordinate markers Z/M/ZM pass through and set the arity");
}

fn t12() -> TestResult {
  let mp = "MULTIPOINT Z ((1 2 3), (4 5 6))";
  var ok = emits(mp, mp);
  if arity_of(mp, 0) != 3 { ok = false; }
  if arity_of(mp, 1) != 3 { ok = false; }
  if marker_of(mp, 1) != 0 { ok = false; }
  if !streq(z_of(mp, 1), "6") { ok = false; }
  let ml = "MULTILINESTRING Z ((1 2 3, 4 5 6))";
  if !emits(ml, ml) { ok = false; }
  if arity_of(ml, 1) != 3 { ok = false; }
  let gc = "GEOMETRYCOLLECTION Z (GEOMETRYCOLLECTION (POINT (1 2 3)))";
  if !emits(gc, gc) { ok = false; }
  if arity_of(gc, 1) != 3 { ok = false; }
  if arity_of(gc, 2) != 3 { ok = false; }
  let plain = "GEOMETRYCOLLECTION (POINT Z (1 2 3))";
  if !emits(plain, plain) { ok = false; }
  if arity_of(plain, 1) != 3 { ok = false; }
  return assert(ok, "markers are inherited by children that declare none");
}

fn t13() -> TestResult {
  var ok = err_is("CIRCLE (1 2)", "wkt: unknown geometry type at 0");
  if !err_is("POINTY (1 2)", "wkt: unknown geometry type at 0") { ok = false; }
  if !err_is("", "wkt: unknown geometry type at 0") { ok = false; }
  if !err_is("   ", "wkt: unknown geometry type at 3") { ok = false; }
  if !err_is("12 34", "wkt: unknown geometry type at 0") { ok = false; }
  return assert(ok, "error: unknown geometry type reports the keyword position");
}

fn t14() -> TestResult {
  var ok = err_is("POINT (1 2", "wkt: unbalanced parentheses at 6");
  if !err_is("MULTIPOINT ((1 2)", "wkt: unbalanced parentheses at 11") { ok = false; }
  if !err_is("POLYGON ((0 0, 1 0, 1 1, 0 1, 0 0)", "wkt: unbalanced parentheses at 8") { ok = false; }
  if !err_is("GEOMETRYCOLLECTION (POINT (1 2)", "wkt: unbalanced parentheses at 19") { ok = false; }
  return assert(ok, "error: unbalanced parentheses report the unclosed (");
}

fn t15() -> TestResult {
  var ok = err_is("POINT (1.)", "wkt: invalid number at 7");
  if !err_is("POINT (1e)", "wkt: invalid number at 7") { ok = false; }
  if !err_is("POINT (.5 1)", "wkt: invalid number at 7") { ok = false; }
  if !err_is("POINT (abc 1)", "wkt: invalid number at 7") { ok = false; }
  if !err_is("POINT (1 2.)", "wkt: invalid number at 9") { ok = false; }
  if !err_is("POINT (1e+ 2)", "wkt: invalid number at 7") { ok = false; }
  return assert(ok, "error: invalid number shape is rejected at its position");
}

fn t16() -> TestResult {
  var ok = err_is("POINT (1)", "wkt: expected 2 ordinates at 7");
  if !err_is("POINT (1 2 3)", "wkt: expected 2 ordinates at 7") { ok = false; }
  if !err_is("POINT Z (1 2)", "wkt: expected 3 ordinates at 9") { ok = false; }
  if !err_is("POINT ZM (1 2 3)", "wkt: expected 4 ordinates at 10") { ok = false; }
  if !err_is("LINESTRING (1 2 3, 4 5)", "wkt: expected 2 ordinates at 12") { ok = false; }
  return assert(ok, "error: ordinate count must match the declared arity");
}

fn t17() -> TestResult {
  var ok = err_is("POINT ()", "wkt: empty coordinate list at 7");
  if !err_is("LINESTRING (  )", "wkt: empty coordinate list at 14") { ok = false; }
  if !err_is("POLYGON (())", "wkt: empty coordinate list at 10") { ok = false; }
  if !err_is("GEOMETRYCOLLECTION ()", "wkt: empty coordinate list at 20") { ok = false; }
  if !err_is("MULTIPOINT (())", "wkt: empty coordinate list at 13") { ok = false; }
  return assert(ok, "error: empty parenthesized lists are rejected");
}

fn t18() -> TestResult {
  var ok = err_is("MULTIPOINT ((1 2) (3 4))", "wkt: missing \",\" at 18");
  if !err_is("LINESTRING (1 2; 3 4)", "wkt: missing \",\" at 15") { ok = false; }
  if !err_is("GEOMETRYCOLLECTION (POINT (1 2) POINT (3 4))", "wkt: missing \",\" at 32") { ok = false; }
  if !err_is("POLYGON ((0 0, 1 0, 1 1, 0 0) (2 2, 3 2, 3 3, 2 2))", "wkt: missing \",\" at 30") { ok = false; }
  return assert(ok, "error: missing comma between list items");
}

fn t19() -> TestResult {
  var ok = err_is("POINT (1 2) extra", "wkt: trailing tokens at 12");
  if !err_is("POINT (1 2))", "wkt: trailing tokens at 11") { ok = false; }
  if !err_is("POINT EMPTY x", "wkt: trailing tokens at 12") { ok = false; }
  if !err_is("POINT EMPTY (1 2)", "wkt: trailing tokens at 12") { ok = false; }
  return assert(ok, "error: trailing tokens after the root geometry");
}

fn t20() -> TestResult {
  var ok = err_is("POINT X (1 2)", "wkt: unknown ordinate marker at 6");
  if !err_is("POINT EMPTYX", "wkt: unknown ordinate marker at 6") { ok = false; }
  if !err_is("POINTZ (1 2)", "wkt: unknown geometry type at 0") { ok = false; }
  if !err_is("GEOMETRYCOLLECTION Z (POINT M (1 2 3))", "wkt: conflicting ordinate markers at 28") { ok = false; }
  return assert(ok, "error: unknown markers and cross-level marker conflicts");
}

fn t21() -> TestResult {
  var ok = err_is("MULTIPOINT (1 2)", "wkt: expected \"(\" at 12");
  if !err_is("POINT (1 2, 3 4)", "wkt: expected \")\" at 10") { ok = false; }
  if !err_is("POINT 1 2", "wkt: expected \"(\" at 6") { ok = false; }
  if !err_is("LINESTRING 1 2, 3 4", "wkt: expected \"(\" at 11") { ok = false; }
  return assert(ok, "error: MULTIPOINT requires inner parens and lists close with )");
}

fn t22() -> TestResult {
  var ok = roundtrip("POINT (30 10)");
  if !roundtrip(_P_POLY) { ok = false; }
  if !roundtrip(_P_MPOINT) { ok = false; }
  if !roundtrip(_P_MLINE) { ok = false; }
  if !roundtrip(_P_MPOLY) { ok = false; }
  if !roundtrip(_P_CIRCLE) { ok = false; }
  if !roundtrip("POINT Z (1 2 3)") { ok = false; }
  if !roundtrip("POINT M (1 2 3)") { ok = false; }
  if !roundtrip("POINT ZM (1 2 3 4)") { ok = false; }
  if !roundtrip("MULTIPOINT Z ((1 2 3), (4 5 6))") { ok = false; }
  if !roundtrip("GEOMETRYCOLLECTION (POINT EMPTY, MULTIPOLYGON EMPTY)") { ok = false; }
  if !roundtrip("  polygon ( ( 0 0 , 1 0 , 1 1 , 0 0 ) )  ") { ok = false; }
  return assert(ok, "round trip: canonical emit re-parses to the same text");
}

fn t23() -> TestResult {
  let p = "POINT (1 2)";
  var ok = streq(type_of(p, -1), "");
  if !streq(type_of(p, 9), "") { ok = false; }
  if marker_of(p, 9) != -1 { ok = false; }
  if arity_of(p, 9) != -1 { ok = false; }
  if !empty_of(p, 9) { ok = false; }
  if parent_of(p, 9) != -1 { ok = false; }
  if child_count_of(p, 9) != 0 { ok = false; }
  if child_of(p, 0, 0) != -1 { ok = false; }
  if count_of(p, 9) != 0 { ok = false; }
  if ring_count_of(p, 9) != 0 { ok = false; }
  if ring_parent_of(p, 9) != -1 { ok = false; }
  if ring_pt_count_of(p, 9) != 0 { ok = false; }
  if !streq(x_of(p, 9), "") { ok = false; }
  if !streq(y_of(p, -1), "") { ok = false; }
  if !streq(z_of(p, 9), "") { ok = false; }
  if !streq(m_of(p, 9), "") { ok = false; }
  return assert(ok, "accessors: out-of-range indices have documented defaults");
}

fn t24() -> TestResult {
  var ok = norm_is("  point(1 2) ", "POINT (1 2)");
  if !norm_is("LINESTRING(0 0,1 1)", "LINESTRING (0 0, 1 1)") { ok = false; }
  if !err_prefix("POINT (1 2", "wkt: unbalanced parentheses") { ok = false; }
  if !err_prefix("CIRCLE (1 2)", "wkt: unknown geometry type") { ok = false; }
  return assert(ok, "wkt_normalize returns the canonical text or the parse error");
}

fn t25() -> TestResult {
  var ok = geom_count_of(_P_NESTED) == 5;
  if child_count_of(_P_NESTED, 0) != 3 { ok = false; }
  if child_of(_P_NESTED, 0, 1) != 2 { ok = false; }
  if child_count_of(_P_NESTED, 2) != 1 { ok = false; }
  if !streq(child_type_of(_P_NESTED, 2, 0), "LINESTRING") { ok = false; }
  if count_of(_P_NESTED, 0) != 7 { ok = false; }
  if ring_count_of(_P_NESTED, 0) != 1 { ok = false; }
  if coord_count_of(_P_NESTED) != 7 { ok = false; }
  if parent_of(_P_NESTED, 4) != 0 { ok = false; }
  return assert(ok, "nested collections: element order, child ranges and totals");
}

fn t26() -> TestResult {
  let g = "GEOMETRYCOLLECTION (POINT EMPTY, MULTIPOLYGON EMPTY)";
  var ok = emits(g, g);
  if geom_count_of(g) != 3 { ok = false; }
  if empty_of(g, 0) { ok = false; }
  if !empty_of(g, 1) { ok = false; }
  if !empty_of(g, 2) { ok = false; }
  if count_of(g, 0) != 0 { ok = false; }
  if ring_count_of(g, 2) != 0 { ok = false; }
  if !streq(child_type_of(g, 0, 1), "MULTIPOLYGON") { ok = false; }
  if !roundtrip(g) { ok = false; }
  return assert(ok, "EMPTY members inside a collection keep their structure");
}

fn t27() -> TestResult {
  let g = "GEOMETRYCOLLECTION ZM (MULTIPOLYGON (((1 2 3 4, 5 6 7 8, 9 10 11 12, 1 2 3 4)), ((0 0 0 0, 1 0 0 0, 1 1 0 0, 0 0 0 0))), POINT (1 2 3 4))";
  var ok = emits(g, g);
  if !roundtrip(g) { ok = false; }
  if geom_count_of(g) != 5 { ok = false; }
  if child_count_of(g, 0) != 2 { ok = false; }
  if !streq(child_type_of(g, 0, 0), "MULTIPOLYGON") { ok = false; }
  if !streq(child_type_of(g, 0, 1), "POINT") { ok = false; }
  if arity_of(g, 1) != 4 { ok = false; }
  if ring_count_of(g, 0) != 2 { ok = false; }
  if ring_count_of(g, 1) != 2 { ok = false; }
  if ring_parent_of(g, 1) != 3 { ok = false; }
  if ring_pt_count_of(g, 1) != 4 { ok = false; }
  if ring_pt_start_of(g, 1) != 4 { ok = false; }
  if coord_count_of(g) != 9 { ok = false; }
  if !streq(z_of(g, 0), "3") { ok = false; }
  if !streq(m_of(g, 0), "4") { ok = false; }
  return assert(ok, "ZM inheritance reaches polygon children inside a collection");
}

fn main() -> Int {
  io.println("=== xiom.wkt conformance tests ===");
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
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.wkt: all tests passed");
  } else {
    io.println("xiom.wkt: tests failed");
  }
  return failed;
}
