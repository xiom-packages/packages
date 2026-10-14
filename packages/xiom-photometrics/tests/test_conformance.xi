// XIOM -- xiom.photometrics conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Fixtures are small hand-written documents assembled from the publicly
// documented LM-63 line layout and the Adobe Cube LUT Specification 1.0
// semantics (see SPEC.md sections 3-4 and PROVENANCE.md). No upstream
// implementation or generated file is consumed: every expectation below
// is computed from the documented structure itself.
//
// Str equality binds a typed local / goes through compare.str_compare
// (BUG 17 discipline); all error checks assert the typed numeric code.

module photometrics_tests

use xiom.io;
use xiom.test;
use xiom.string;
use xiom.string.compare;
use xiom.math;
use xiom.photometrics;

// -------------------------------------------------- helpers

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn close(a: Float64, b: Float64) -> Bool {
  return math.abs_float(a - b) < 0.000001;
}

fn ies_fail(text: Str, code: Int) -> Bool {
  let r = ies_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return e.code == code; },
  }
  return false;
}

fn cube_fail(text: Str, code: Int) -> Bool {
  let r = cube_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return e.code == code; },
  }
  return false;
}

fn opt_is(o: Option[Str], want: Str) -> Bool {
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

fn opt_none(o: Option[Str]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

// -------------------------------------------------- IES fixtures

fn ies_2002_full() -> Str {
  return "IESNA:LM-63-2002\n" +
    "[TEST] LTL-0001\n" +
    "[MANUFAC] XIOM Labs\n" +
    "[LUMCAT] XIOM-DOWN-01\n" +
    "TILT=NONE\n" +
    "1 3000 1 2 1 1 1 0.6 0.3 0.1\n" +
    "1.0 1.0 25.5\n" +
    "0 180\n" +
    "0\n" +
    "1000 500\n";
}

// -------------------------------------------------- t1: 2002 full parse

fn t1() -> TestResult {
  let r = ies_parse(ies_2002_full());
  var ok = false;
  match r {
    Ok(d) => {
      ok = ies_version(&d) == IES_VERSION_2002;
      if !streq(ies_version_label(&d), "IESNA:LM-63-2002") { ok = false; }
      if ies_num_lamps(&d) != 1 { ok = false; }
      if !close(ies_lumens_per_lamp(&d), 3000.0) { ok = false; }
      if !close(ies_candela_multiplier(&d), 1.0) { ok = false; }
      if !close(ies_input_watts(&d), 25.5) { ok = false; }
      if !close(ies_ballast_factor(&d), 1.0) { ok = false; }
      if !close(ies_ballast_lamp_factor(&d), 1.0) { ok = false; }
      if ies_photometric_type(&d) != IES_TYPE_C { ok = false; }
      if ies_units_type(&d) != IES_UNITS_FEET { ok = false; }
      if !close(ies_width(&d), 0.6) { ok = false; }
      if !close(ies_length(&d), 0.3) { ok = false; }
      if !close(ies_height(&d), 0.1) { ok = false; }
      if ies_vertical_count(&d) != 2 { ok = false; }
      if ies_horizontal_count(&d) != 1 { ok = false; }
      if ies_candela_count(&d) != 2 { ok = false; }
      if !close(ies_vertical_angle(&d, 0), 0.0) { ok = false; }
      if !close(ies_vertical_angle(&d, 1), 180.0) { ok = false; }
      if !close(ies_horizontal_angle(&d, 0), 0.0) { ok = false; }
      if !close(ies_candela(&d, 0, 0), 1000.0) { ok = false; }
      if !close(ies_candela(&d, 0, 1), 500.0) { ok = false; }
      if ies_keyword_count(&d) != 3 { ok = false; }
      if ies_description_count(&d) != 0 { ok = false; }
      if ies_tilt_kind(&d) != IES_TILT_NONE { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "ies: 2002 file parses with all parameters");
}

// -------------------------------------------------- t2-t4: revision variants

fn t2() -> TestResult {
  let src = "IESNA:LM-63-1986\n" +
    "[TEST] LTL-0002\n" +
    "TILT=NONE\n" +
    "1 1000 1 2 1 1 1 1 1 1\n" +
    "1 1 10\n" +
    "0 90\n" +
    "0\n" +
    "100 50\n";
  let r = ies_parse(src);
  var ok = false;
  match r {
    Ok(d) => {
      ok = ies_version(&d) == IES_VERSION_1986;
      if !streq(ies_version_label(&d), "IESNA:LM-63-1986") { ok = false; }
      if ies_vertical_count(&d) != 2 { ok = false; }
      if !close(ies_candela(&d, 0, 1), 50.0) { ok = false; }
      if !close(ies_input_watts(&d), 10.0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "ies: 1986 revision header parses");
}

fn t3() -> TestResult {
  let src = "IESNA91\n" +
    "[TEST] LTL-0003\n" +
    "TILT=NONE\n" +
    "1 1000 1 2 1 1 1 1 1 1\n" +
    "1 1 10\n" +
    "0 90\n" +
    "0\n" +
    "100 50\n";
  let r = ies_parse(src);
  var ok = false;
  match r {
    Ok(d) => {
      ok = ies_version(&d) == IES_VERSION_1991;
      if !streq(ies_version_label(&d), "IESNA91") { ok = false; }
      if ies_candela_count(&d) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "ies: IESNA91 (1991) header parses");
}

fn t4() -> TestResult {
  let src = "IESNA:LM-63-1995\n" +
    "[TEST] LTL-0004\n" +
    "TILT=NONE\n" +
    "1 1000 1 1 1 1 1 1 1 1\n" +
    "1 1 10\n" +
    "90\n" +
    "0\n" +
    "500\n";
  let r = ies_parse(src);
  var ok = false;
  match r {
    Ok(d) => {
      ok = ies_version(&d) == IES_VERSION_1995;
      if !streq(ies_version_label(&d), "IESNA:LM-63-1995") { ok = false; }
      if !close(ies_candela(&d, 0, 0), 500.0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "ies: 1995 revision header parses");
}

// -------------------------------------------------- t5: metadata

fn t5() -> TestResult {
  let src = "IESNA:LM-63-2002\n" +
    "plain descriptive line\n" +
    "TILTAGE note text\n" +
    "[TEST] T-1\n" +
    "[MANUFAC] ACME Lighting\n" +
    "[ISSUEDATE] 2026-10-14\n" +
    "TILT=NONE\n" +
    "1 1000 1 1 1 1 1 0 0 0\n" +
    "1 1 10\n" +
    "90\n" +
    "0\n" +
    "500\n";
  let r = ies_parse(src);
  var ok = false;
  match r {
    Ok(d) => {
      ok = ies_keyword_count(&d) == 3;
      if !streq(ies_keyword_name(&d, 0), "TEST") { ok = false; }
      if !streq(ies_keyword_name(&d, 1), "MANUFAC") { ok = false; }
      if !streq(ies_keyword_value(&d, 1), "ACME Lighting") { ok = false; }
      if ies_description_count(&d) != 2 { ok = false; }
      if !streq(ies_description(&d, 0), "plain descriptive line") { ok = false; }
      if !streq(ies_description(&d, 1), "TILTAGE note text") { ok = false; }
      if !opt_is(ies_get_keyword(&d, "MANUFAC"), "ACME Lighting") { ok = false; }
      if !opt_is(ies_get_keyword(&d, "manufac"), "ACME Lighting") { ok = false; }
      if !opt_none(ies_get_keyword(&d, "NOPE")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "ies: keywords and descriptions parse");
}

// -------------------------------------------------- t6: multi-plane grid

fn t6() -> TestResult {
  let src = "IESNA:LM-63-2002\n" +
    "TILT=NONE\n" +
    "1 1000 1 3 2 1 2 0 0 0\n" +
    "1 1 10\n" +
    "0 45 90\n" +
    "0 90\n" +
    "100 80 60 50 40 30\n";
  let r = ies_parse(src);
  var ok = false;
  match r {
    Ok(d) => {
      ok = ies_vertical_count(&d) == 3;
      if ies_horizontal_count(&d) != 2 { ok = false; }
      if ies_candela_count(&d) != 6 { ok = false; }
      if ies_units_type(&d) != IES_UNITS_METERS { ok = false; }
      if !close(ies_vertical_angle(&d, 1), 45.0) { ok = false; }
      if !close(ies_horizontal_angle(&d, 1), 90.0) { ok = false; }
      if !close(ies_candela(&d, 0, 0), 100.0) { ok = false; }
      if !close(ies_candela(&d, 0, 2), 60.0) { ok = false; }
      if !close(ies_candela(&d, 1, 0), 50.0) { ok = false; }
      if !close(ies_candela(&d, 1, 2), 30.0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "ies: multi-plane candela indexing is plane-major");
}

// -------------------------------------------------- t7: exact lookup + multiplier

fn t7() -> TestResult {
  let src = "IESNA:LM-63-2002\n" +
    "TILT=NONE\n" +
    "1 1000 2.5 2 1 1 1 0 0 0\n" +
    "1 1 10\n" +
    "0 90\n" +
    "0\n" +
    "100 50\n";
  let r = ies_parse(src);
  var ok = false;
  match r {
    Ok(d) => {
      ok = close(ies_candela(&d, 0, 0), 100.0);
      if !close(ies_candela_scaled(&d, 0, 0), 250.0) { ok = false; }
      if !close(ies_sample(&d, 0.0, 0.0), 100.0) { ok = false; }
      if !close(ies_sample(&d, 90.0, 0.0), 50.0) { ok = false; }
      if !close(ies_sample_scaled(&d, 90.0, 0.0), 125.0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "ies: exact-grid lookup and candela multiplier");
}

// -------------------------------------------------- t8: vertical interpolation

fn t8() -> TestResult {
  let src = "IESNA:LM-63-2002\n" +
    "TILT=NONE\n" +
    "1 1000 1 2 1 1 1 0 0 0\n" +
    "1 1 10\n" +
    "0 90\n" +
    "0\n" +
    "100 50\n";
  let r = ies_parse(src);
  var ok = false;
  match r {
    Ok(d) => {
      ok = close(ies_sample(&d, 45.0, 0.0), 75.0);
      if !close(ies_sample(&d, -10.0, 0.0), 100.0) { ok = false; }
      if !close(ies_sample(&d, 200.0, 0.0), 50.0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "ies: vertical interpolation and clamping");
}

// -------------------------------------------------- t9: horizontal ring wrap

fn t9() -> TestResult {
  let src = "IESNA:LM-63-2002\n" +
    "TILT=NONE\n" +
    "1 1000 1 1 5 1 1 0 0 0\n" +
    "1 1 10\n" +
    "90\n" +
    "0 90 180 270 360\n" +
    "100 200 300 400 100\n";
  let r = ies_parse(src);
  var ok = false;
  match r {
    Ok(d) => {
      ok = ies_horizontal_count(&d) == 5;
      if !close(ies_sample(&d, 90.0, 0.0), 100.0) { ok = false; }
      if !close(ies_sample(&d, 90.0, 45.0), 150.0) { ok = false; }
      if !close(ies_sample(&d, 90.0, 180.0), 300.0) { ok = false; }
      if !close(ies_sample(&d, 90.0, 315.0), 250.0) { ok = false; }
      if !close(ies_sample(&d, 90.0, 360.0), 100.0) { ok = false; }
      if !close(ies_sample(&d, 90.0, 720.0), 100.0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "ies: closed horizontal ring wraps modulo 360");
}

// -------------------------------------------------- t10: open grid clamping

fn t10() -> TestResult {
  let src = "IESNA:LM-63-2002\n" +
    "TILT=NONE\n" +
    "1 1000 1 1 3 1 1 0 0 0\n" +
    "1 1 10\n" +
    "90\n" +
    "0 90 180\n" +
    "100 200 300\n";
  let r = ies_parse(src);
  var ok = false;
  match r {
    Ok(d) => {
      ok = close(ies_sample(&d, 90.0, 45.0), 150.0);
      if !close(ies_sample(&d, 90.0, -30.0), 100.0) { ok = false; }
      if !close(ies_sample(&d, 90.0, 270.0), 300.0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "ies: open horizontal grids clamp at the ends");
}

// -------------------------------------------------- t11: TILT=INCLUDE

fn t11() -> TestResult {
  let src = "IESNA:LM-63-2002\n" +
    "[TEST] T3\n" +
    "TILT=INCLUDE\n" +
    "3\n" +
    "1\n" +
    "0\n" +
    "1.0\n" +
    "1 1000 1 1 1 1 1 0 0 0\n" +
    "1 1 10\n" +
    "90\n" +
    "0\n" +
    "500\n";
  let r = ies_parse(src);
  var ok = false;
  match r {
    Ok(d) => {
      ok = ies_tilt_kind(&d) == IES_TILT_INCLUDE;
      if ies_tilt_geometry(&d) != 3 { ok = false; }
      if ies_tilt_pair_count(&d) != 1 { ok = false; }
      if !close(ies_tilt_angle(&d, 0), 0.0) { ok = false; }
      if !close(ies_tilt_factor(&d, 0), 1.0) { ok = false; }
      if !close(ies_candela(&d, 0, 0), 500.0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "ies: TILT=INCLUDE block parses and stores data");
}

// -------------------------------------------------- t12: TILT=file

fn t12() -> TestResult {
  let src = "IESNA:LM-63-2002\n" +
    "TILT=/data/tilt.dat\n" +
    "1 1000 1 1 1 1 1 0 0 0\n" +
    "1 1 10\n" +
    "90\n" +
    "0\n" +
    "500\n";
  let r = ies_parse(src);
  var ok = false;
  match r {
    Ok(d) => {
      ok = ies_tilt_kind(&d) == IES_TILT_FILE;
      if !streq(ies_tilt_ref(&d), "/data/tilt.dat") { ok = false; }
      if ies_tilt_pair_count(&d) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "ies: TILT=<file> reference is stored");
}

// -------------------------------------------------- t13: wrapped value lines

fn t13() -> TestResult {
  let src = "IESNA:LM-63-2002\n" +
    "TILT=NONE\n" +
    "1 1000 1 4 2 1 1 0 0 0\n" +
    "1 1 10\n" +
    "0 30 60 90\n" +
    "0 90\n" +
    "10 20\n" +
    "30 40\n" +
    "50 60 70 80\n";
  let r = ies_parse(src);
  var ok = false;
  match r {
    Ok(d) => {
      ok = ies_candela_count(&d) == 8;
      if !close(ies_candela(&d, 0, 3), 40.0) { ok = false; }
      if !close(ies_candela(&d, 1, 0), 50.0) { ok = false; }
      if !close(ies_candela(&d, 1, 3), 80.0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "ies: candela values may span multiple lines");
}

// -------------------------------------------------- t14: CRLF input

fn t14() -> TestResult {
  let src = "IESNA:LM-63-2002\r\n" +
    "[TEST] CRLF\r\n" +
    "TILT=NONE\r\n" +
    "1 1000 1 2 1 1 1 0 0 0\r\n" +
    "1 1 10\r\n" +
    "0 90\r\n" +
    "0\r\n" +
    "100 50\r\n";
  let r = ies_parse(src);
  var ok = false;
  match r {
    Ok(d) => {
      ok = ies_vertical_count(&d) == 2;
      if !close(ies_candela(&d, 0, 1), 50.0) { ok = false; }
      if !streq(ies_keyword_value(&d, 0), "CRLF") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "ies: CRLF line endings parse");
}

// -------------------------------------------------- t15: UTF-8 BOM

fn t15() -> TestResult {
  let src = "\u{FEFF}IESNA:LM-63-2002\n" +
    "TILT=NONE\n" +
    "1 1000 1 1 1 1 1 0 0 0\n" +
    "1 1 10\n" +
    "90\n" +
    "0\n" +
    "500\n";
  let r = ies_parse(src);
  var ok = false;
  match r {
    Ok(d) => {
      ok = ies_version(&d) == IES_VERSION_2002;
      if !close(ies_candela(&d, 0, 0), 500.0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "ies: a UTF-8 BOM is skipped");
}

// -------------------------------------------------- t16-t28: typed IES errors

fn t16() -> TestResult {
  let ok = ies_fail("", IES_ERR_EMPTY) && ies_fail("   \n\n  \n", IES_ERR_EMPTY);
  return assert(ok, "ies: empty and blank-only input -> IES_ERR_EMPTY");
}

fn t17() -> TestResult {
  let ok = ies_fail("NOTANIESFILE\nTILT=NONE\n", IES_ERR_MISSING_VERSION);
  return assert(ok, "ies: non-IES first line -> IES_ERR_MISSING_VERSION");
}

fn t18() -> TestResult {
  let ok = ies_fail("IESNA:LM-63-9999\nTILT=NONE\n", IES_ERR_UNSUPPORTED_VERSION);
  return assert(ok, "ies: unknown revision -> IES_ERR_UNSUPPORTED_VERSION");
}

fn t19() -> TestResult {
  let ok = ies_fail("IESNA:LM-63-2002\n[TEST] x\n", IES_ERR_MISSING_TILT);
  return assert(ok, "ies: no TILT= line -> IES_ERR_MISSING_TILT");
}

fn t20() -> TestResult {
  let ok = ies_fail("IESNA:LM-63-2002\nTILT=\n", IES_ERR_BAD_TILT);
  return assert(ok, "ies: empty TILT= value -> IES_ERR_BAD_TILT");
}

fn t21() -> TestResult {
  let a = ies_fail("IESNA:LM-63-2002\nTILT=INCLUDE\n3\n", IES_ERR_BAD_TILT_BLOCK);
  let b = ies_fail("IESNA:LM-63-2002\nTILT=INCLUDE\nX\n1\n0\n1.0\n", IES_ERR_BAD_TILT_BLOCK);
  let c = ies_fail("IESNA:LM-63-2002\nTILT=INCLUDE\n3\n5\n0 0 0 0 0\n1 1 1 1\n", IES_ERR_BAD_TILT_BLOCK);
  let ok = a && b && c;
  return assert(ok, "ies: malformed TILT=INCLUDE block -> IES_ERR_BAD_TILT_BLOCK");
}

fn t22() -> TestResult {
  let a = ies_fail("IESNA:LM-63-2002\nTILT=NONE\n1 1000 1 2 2 1 1 1 1\n1 1 10\n0 90\n0 90\n1 2 3 4\n", IES_ERR_BAD_NUMBER);
  let b = ies_fail("IESNA:LM-63-2002\nTILT=NONE\nX 1000 1 1 1 1 1 0 0 0\n1 1 10\n90\n0\n5\n", IES_ERR_BAD_NUMBER);
  let ok = a && b;
  return assert(ok, "ies: malformed parameter lines -> IES_ERR_BAD_NUMBER");
}

fn t23() -> TestResult {
  let ok = ies_fail("IESNA:LM-63-2002\nTILT=NONE\n1 1000 1 0 1 1 1 0 0 0\n1 1 10\n", IES_ERR_BAD_COUNT);
  return assert(ok, "ies: zero vertical angles -> IES_ERR_BAD_COUNT");
}

fn t24() -> TestResult {
  let a = ies_fail("IESNA:LM-63-2002\nTILT=NONE\n1 1000 1 1 1 9 1 0 0 0\n1 1 10\n90\n0\n5\n", IES_ERR_BAD_ENUM);
  let b = ies_fail("IESNA:LM-63-2002\nTILT=NONE\n1 1000 1 1 1 1 7 0 0 0\n1 1 10\n90\n0\n5\n", IES_ERR_BAD_ENUM);
  let ok = a && b;
  return assert(ok, "ies: photometric/units type outside 1..3 / 1..2 -> IES_ERR_BAD_ENUM");
}

fn t25() -> TestResult {
  let ok = ies_fail("IESNA:LM-63-2002\nTILT=NONE\n1 1000 1 2 1 1 1 0 0 0\n1 1 10\n0 90\n0\n100\n", IES_ERR_TRUNCATED);
  return assert(ok, "ies: missing candela values -> IES_ERR_TRUNCATED");
}

fn t26() -> TestResult {
  let ok = ies_fail("IESNA:LM-63-2002\nTILT=NONE\n1 1000 1 2 1 1 1 0 0 0\n1 1 10\n0 90\n0\n100 50 999\n", IES_ERR_TRAILING);
  return assert(ok, "ies: data after the candela table -> IES_ERR_TRAILING");
}

fn t27() -> TestResult {
  let a = ies_fail("IESNA:LM-63-2002\nTILT=NONE\n1 1000 1 20000 1 1 1 0 0 0\n", IES_ERR_BAD_COUNT);
  let b = ies_fail("IESNA:LM-63-2002\nTILT=NONE\n1 1000 1 4000 400 1 1 0 0 0\n", IES_ERR_LIMIT);
  let ok = a && b;
  return assert(ok, "ies: implausible counts -> IES_ERR_BAD_COUNT / IES_ERR_LIMIT");
}

fn t28() -> TestResult {
  let r = ies_parse(ies_2002_full());
  var ok = false;
  match r {
    Ok(d) => {
      ok = streq(ies_keyword_name(&d, 99), "");
      if !streq(ies_keyword_value(&d, -1), "") { ok = false; }
      if !streq(ies_description(&d, 5), "") { ok = false; }
      if !close(ies_vertical_angle(&d, 9), 0.0) { ok = false; }
      if !close(ies_horizontal_angle(&d, -3), 0.0) { ok = false; }
      if !close(ies_candela(&d, 9, 9), 0.0) { ok = false; }
      if !close(ies_candela_scaled(&d, 9, 9), 0.0) { ok = false; }
      if !close(ies_tilt_angle(&d, 0), 0.0) { ok = false; }
      if !close(ies_tilt_factor(&d, 0), 0.0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "ies: out-of-range accessors return documented defaults");
}

// -------------------------------------------------- cube fixtures

fn cube_identity_3d() -> Str {
  return "# identity 2x2x2\n" +
    "TITLE \"identity\"\n" +
    "LUT_3D_SIZE 2\n" +
    "DOMAIN_MIN 0 0 0\n" +
    "DOMAIN_MAX 1 1 1\n" +
    "0 0 0\n" +
    "1 0 0\n" +
    "0 1 0\n" +
    "1 1 0\n" +
    "0 0 1\n" +
    "1 0 1\n" +
    "0 1 1\n" +
    "1 1 1\n";
}

// -------------------------------------------------- t29: size-2 3D cube

fn t29() -> TestResult {
  let r = cube_parse(cube_identity_3d());
  var ok = false;
  match r {
    Ok(d) => {
      ok = cube_is_3d(&d);
      if cube_size(&d) != 2 { ok = false; }
      if cube_dim(&d) != 3 { ok = false; }
      if cube_entry_count(&d) != 8 { ok = false; }
      if !streq(cube_title(&d), "identity") { ok = false; }
      if !cube_has_title(&d) { ok = false; }
      if !close(cube_domain_min(&d, 0), 0.0) { ok = false; }
      if !close(cube_domain_max(&d, 2), 1.0) { ok = false; }
      if cube_3d_index(&d, 1, 0, 0) != 1 { ok = false; }
      if cube_3d_index(&d, 0, 1, 0) != 2 { ok = false; }
      if cube_3d_index(&d, 0, 0, 1) != 4 { ok = false; }
      if cube_3d_index(&d, 2, 0, 0) != -1 { ok = false; }
      if !close(cube_value(&d, 3, 0), 1.0) { ok = false; }
      if !close(cube_value(&d, 3, 1), 1.0) { ok = false; }
      if !close(cube_value(&d, 3, 2), 0.0) { ok = false; }
      if !close(cube_entry(&d, 1).r, 1.0) { ok = false; }
      if !close(cube_entry(&d, 2).g, 1.0) { ok = false; }
      if !close(cube_entry(&d, 4).b, 1.0) { ok = false; }
      if !close(cube_entry(&d, 7).r, 1.0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "cube: size-2 3D LUT parses (red varies fastest)");
}

// -------------------------------------------------- t30: 1D cube

fn t30() -> TestResult {
  let src = "TITLE \"ramp\"\n" +
    "LUT_1D_SIZE 2\n" +
    "0.25 0.5 0.75\n" +
    "1.0 0.5 0.0\n";
  let r = cube_parse(src);
  var ok = false;
  match r {
    Ok(d) => {
      ok = !cube_is_3d(&d);
      if cube_dim(&d) != 1 { ok = false; }
      if cube_size(&d) != 2 { ok = false; }
      if cube_entry_count(&d) != 2 { ok = false; }
      if !streq(cube_title(&d), "ramp") { ok = false; }
      if !close(cube_entry(&d, 0).r, 0.25) { ok = false; }
      if !close(cube_entry(&d, 0).g, 0.5) { ok = false; }
      if !close(cube_entry(&d, 0).b, 0.75) { ok = false; }
      if !close(cube_entry(&d, 1).r, 1.0) { ok = false; }
      if !close(cube_entry(&d, 1).b, 0.0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "cube: 1D LUT parses with values in order");
}

// -------------------------------------------------- t31: comments and defaults

fn t31() -> TestResult {
  let src = "# a comment\n\n" +
    "LUT_3D_SIZE 2\n" +
    "# another comment\n" +
    "0 0 0\n1 0 0\n0 1 0\n1 1 0\n" +
    "0 0 1\n1 0 1\n0 1 1\n1 1 1\n";
  let r = cube_parse(src);
  var ok = false;
  match r {
    Ok(d) => {
      ok = !cube_has_title(&d);
      if !streq(cube_title(&d), "") { ok = false; }
      if !close(cube_domain_min(&d, 1), 0.0) { ok = false; }
      if !close(cube_domain_max(&d, 1), 1.0) { ok = false; }
      if cube_entry_count(&d) != 8 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "cube: comments are skipped and domains default to 0..1");
}

// -------------------------------------------------- t32-t40: typed cube errors

fn t32() -> TestResult {
  let ok = cube_fail("", CUBE_ERR_EMPTY) && cube_fail("# only comments\n\n", CUBE_ERR_EMPTY);
  return assert(ok, "cube: empty/comment-only input -> CUBE_ERR_EMPTY");
}

fn t33() -> TestResult {
  let ok = cube_fail("0 0 0\n1 1 1\n", CUBE_ERR_MISSING_SIZE);
  return assert(ok, "cube: no size declaration -> CUBE_ERR_MISSING_SIZE");
}

fn t34() -> TestResult {
  let a = cube_fail("LUT_1D_SIZE 2\nLUT_1D_SIZE 2\n0 0 0\n1 1 1\n", CUBE_ERR_DUPLICATE_SIZE);
  let b = cube_fail("LUT_1D_SIZE 2\nLUT_3D_SIZE 2\n0 0 0\n1 1 1\n", CUBE_ERR_DUPLICATE_SIZE);
  let ok = a && b;
  return assert(ok, "cube: repeated or mixed size declarations -> CUBE_ERR_DUPLICATE_SIZE");
}

fn t35() -> TestResult {
  let a = cube_fail("LUT_3D_SIZE 1\n0 0 0\n", CUBE_ERR_BAD_SIZE);
  let b = cube_fail("LUT_3D_SIZE 200\n0 0 0\n", CUBE_ERR_BAD_SIZE);
  let c = cube_fail("LUT_1D_SIZE X\n0 0 0\n", CUBE_ERR_BAD_SIZE);
  let ok = a && b && c;
  return assert(ok, "cube: size below 2, over cap, or non-integer -> CUBE_ERR_BAD_SIZE");
}

fn t36() -> TestResult {
  let a = cube_fail("LUT_1D_SIZE 2\n0.5 0.5\n1 1 1\n", CUBE_ERR_BAD_DATA);
  let b = cube_fail("LUT_1D_SIZE 2\n0 0 0\n1 xx 1\n", CUBE_ERR_BAD_DATA);
  let ok = a && b;
  return assert(ok, "cube: data line without three numbers -> CUBE_ERR_BAD_DATA");
}

fn t37() -> TestResult {
  let a = cube_fail("LUT_1D_SIZE 2\n0 0 0\n", CUBE_ERR_TRUNCATED);
  let b = cube_fail("LUT_1D_SIZE 2\n0 0 0\n1 1 1\n2 2 2\n", CUBE_ERR_TRAILING);
  let ok = a && b;
  return assert(ok, "cube: too few / too many triples -> CUBE_ERR_TRUNCATED / TRAILING");
}

fn t38() -> TestResult {
  let a = cube_fail("TITLE noquote\nLUT_1D_SIZE 2\n0 0 0\n1 1 1\n", CUBE_ERR_BAD_TITLE);
  let b = cube_fail("TITLE \"a\nTITLE \"b\"\nLUT_1D_SIZE 2\n0 0 0\n1 1 1\n", CUBE_ERR_BAD_TITLE);
  let ok = a && b;
  return assert(ok, "cube: unquoted or duplicate TITLE -> CUBE_ERR_BAD_TITLE");
}

fn t39() -> TestResult {
  let a = cube_fail("LUT_1D_SIZE 2\nDOMAIN_MIN 0 0\n0 0 0\n1 1 1\n", CUBE_ERR_BAD_DOMAIN);
  let b = cube_fail("LUT_1D_SIZE 2\nDOMAIN_MIN 0 0 0\nDOMAIN_MIN 0 0 0\n0 0 0\n1 1 1\n", CUBE_ERR_DUPLICATE_DOMAIN);
  let c = cube_fail("LUT_1D_SIZE 2\nDOMAIN_MIN 1 0 0\nDOMAIN_MAX 1 1 1\n0 0 0\n1 1 1\n", CUBE_ERR_BAD_DOMAIN);
  let ok = a && b && c;
  return assert(ok, "cube: malformed/duplicate/degenerate domains -> typed errors");
}

fn t40() -> TestResult {
  let ok = cube_fail("LUT_1D_SIZE 2\nFOO 1 2\n0 0 0\n1 1 1\n", CUBE_ERR_BAD_KEYWORD);
  return assert(ok, "cube: unknown keyword -> CUBE_ERR_BAD_KEYWORD");
}

// -------------------------------------------------- t41: 3D sampling

fn t41() -> TestResult {
  let src = "LUT_3D_SIZE 2\n" +
    "DOMAIN_MIN 0 0 0\n" +
    "DOMAIN_MAX 2 2 2\n" +
    "0 0 0\n1 0 0\n0 1 0\n1 1 0\n" +
    "0 0 1\n1 0 1\n0 1 1\n1 1 1\n";
  let r = cube_parse(src);
  var ok = false;
  match r {
    Ok(d) => {
      let mid = cube_sample_3d(&d, 1.0, 1.0, 1.0);
      ok = close(mid.r, 0.5);
      if !close(mid.g, 0.5) { ok = false; }
      if !close(mid.b, 0.5) { ok = false; }
      let lo = cube_sample_3d(&d, -5.0, -5.0, -5.0);
      if !close(lo.r, 0.0) { ok = false; }
      let hi = cube_sample_3d(&d, 2.0, 2.0, 2.0);
      if !close(hi.r, 1.0) { ok = false; }
      let q = cube_sample_3d(&d, 0.5, 1.0, 1.0);
      if !close(q.r, 0.25) { ok = false; }
      if !close(q.g, 0.5) { ok = false; }
      if !close(q.b, 0.5) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "cube: trilinear sampling with domain mapping and clamping");
}

// -------------------------------------------------- t42: 1D sampling

fn t42() -> TestResult {
  let src = "LUT_1D_SIZE 2\n" +
    "DOMAIN_MIN 0 0 0\n" +
    "DOMAIN_MAX 2 2 2\n" +
    "0 0 0\n" +
    "2 2 2\n";
  let r = cube_parse(src);
  var ok = false;
  match r {
    Ok(d) => {
      ok = close(cube_sample_1d(&d, 0, 1.0), 1.0);
      if !close(cube_sample_1d(&d, 1, 1.0), 1.0) { ok = false; }
      if !close(cube_sample_1d(&d, 2, 0.5), 0.5) { ok = false; }
      if !close(cube_sample_1d(&d, 0, 9.0), 2.0) { ok = false; }
      if !close(cube_sample_1d(&d, 0, -9.0), 0.0) { ok = false; }
      if !close(cube_sample_1d(&d, 7, 1.0), 0.0) { ok = false; }
      let z = cube_sample_3d(&d, 1.0, 1.0, 1.0);
      if !close(z.r, 0.0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "cube: 1D sampling with domain mapping; 3D sample on 1D is zero");
}

// -------------------------------------------------- t43: cube accessor safety

fn t43() -> TestResult {
  let r = cube_parse(cube_identity_3d());
  var ok = false;
  match r {
    Ok(d) => {
      let e0 = cube_entry(&d, -1);
      ok = close(e0.r, 0.0);
      if !close(cube_value(&d, 99, 0), 0.0) { ok = false; }
      if !close(cube_value(&d, 0, 9), 0.0) { ok = false; }
      if !close(cube_domain_min(&d, 5), 0.0) { ok = false; }
      if !close(cube_domain_max(&d, -1), 0.0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "cube: out-of-range accessors return documented defaults");
}

fn main() -> Int {
  io.println("=== xiom.photometrics conformance tests ===");
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
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  let r29 = t29();
  if r29.passed { io.println("  [PASS] " + r29.name); } else { io.println("  [FAIL] " + r29.name); failed = failed + 1; }
  let r30 = t30();
  if r30.passed { io.println("  [PASS] " + r30.name); } else { io.println("  [FAIL] " + r30.name); failed = failed + 1; }
  let r31 = t31();
  if r31.passed { io.println("  [PASS] " + r31.name); } else { io.println("  [FAIL] " + r31.name); failed = failed + 1; }
  let r32 = t32();
  if r32.passed { io.println("  [PASS] " + r32.name); } else { io.println("  [FAIL] " + r32.name); failed = failed + 1; }
  let r33 = t33();
  if r33.passed { io.println("  [PASS] " + r33.name); } else { io.println("  [FAIL] " + r33.name); failed = failed + 1; }
  let r34 = t34();
  if r34.passed { io.println("  [PASS] " + r34.name); } else { io.println("  [FAIL] " + r34.name); failed = failed + 1; }
  let r35 = t35();
  if r35.passed { io.println("  [PASS] " + r35.name); } else { io.println("  [FAIL] " + r35.name); failed = failed + 1; }
  let r36 = t36();
  if r36.passed { io.println("  [PASS] " + r36.name); } else { io.println("  [FAIL] " + r36.name); failed = failed + 1; }
  let r37 = t37();
  if r37.passed { io.println("  [PASS] " + r37.name); } else { io.println("  [FAIL] " + r37.name); failed = failed + 1; }
  let r38 = t38();
  if r38.passed { io.println("  [PASS] " + r38.name); } else { io.println("  [FAIL] " + r38.name); failed = failed + 1; }
  let r39 = t39();
  if r39.passed { io.println("  [PASS] " + r39.name); } else { io.println("  [FAIL] " + r39.name); failed = failed + 1; }
  let r40 = t40();
  if r40.passed { io.println("  [PASS] " + r40.name); } else { io.println("  [FAIL] " + r40.name); failed = failed + 1; }
  let r41 = t41();
  if r41.passed { io.println("  [PASS] " + r41.name); } else { io.println("  [FAIL] " + r41.name); failed = failed + 1; }
  let r42 = t42();
  if r42.passed { io.println("  [PASS] " + r42.name); } else { io.println("  [FAIL] " + r42.name); failed = failed + 1; }
  let r43 = t43();
  if r43.passed { io.println("  [PASS] " + r43.name); } else { io.println("  [FAIL] " + r43.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.photometrics: all tests passed");
  } else {
    io.println("xiom.photometrics: tests failed");
  }
  return failed;
}
