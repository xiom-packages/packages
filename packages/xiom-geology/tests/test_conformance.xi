// XIOM -- xiom.geology conformance tests (26 checks)
// Port task: prove the pure-XIOM xiom.geology LAS 2.0 parser against SPEC.md:
// sections ~V/~W/~C/~P/~A/~O, CRLF/LF lines, comments, case-insensitive
// mnemonics, quoted and dotted values, WRAP YES/NO depth semantics, the NULL
// model with per-cell flags, fixed-point truncation toward zero, accessor
// bounds, and the error catalog with line numbers and byte offsets.
// Every fixture is built in-test; there are no data files.
//
// All Str equality goes through xiom.string.compare.str_compare (BUG 17:
// `==` on Str values read from Vec[Str] elements lowers to a pointer
// comparison), and every Vec[Str]/Vec[Int] element read binds a typed local
// first.

module geology_tests
use xiom.io; use xiom.test; use xiom.geology;
use xiom.string.compare;
use xiom.convert;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Error path check: las_parse must fail, and the message must carry the
// wanted 1-based line and 0-based byte offset.
fn err_at(s: Str, want_line: Int, want_off: Int) -> Bool {
  let r = las_parse(s);
  match r {
    Ok(_) => { return false; },
    Err(e) => {
      if geology_error_line(e) != want_line { return false; }
      return geology_error_offset(e) == want_off;
    },
  }
  return false;
}

// Exact error message check (format, line and offset together).
fn err_is(s: Str, want: Str) -> Bool {
  let r = las_parse(s);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// --- fixtures ---------------------------------------------------------------

// Unwrapped, fully specified log: 3 curves, 3 rows, one NULL declaration.
fn las_basic() -> Str {
  return "~Version Information\nVERS. 2.0 : CWLS LOG ASCII STANDARD\nWRAP. NO : ONE LINE PER DEPTH STEP\n~Well Information\nSTRT.M 1000.0000 : START DEPTH\nSTOP.M 1002.5000 : STOP DEPTH\nSTEP.M 0.5000 : STEP\nNULL. -999.25 : NULL VALUE\nWELL. WELL-1 : WELL NAME\nCOMP. COMPANY-X : COMPANY\n~Curve Information\nDEPT.M : DEPTH\nGR.GAPI : GAMMA RAY\nRHOB.G/C3 : BULK DENSITY\n~Parameter Information\nBHT.DEGC 85.5 : BOTTOM HOLE TEMPERATURE\n~ASCII\n1000.0 -999.25 2.5\n1000.5 45.5 -999.25\n1001.0 46.0 2.55\n";
}

// Wrapped log: WRAP YES, depth implied by STRT + row * STEP.
fn las_wrapped() -> Str {
  return "~V\nVERS. 2.0 : X\nWRAP. YES : WRAPPED\n~W\nSTRT.M 0.0 : START\nSTOP.M 2.0 : STOP\nSTEP.M 1.0 : STEP\nNULL. -999.25 : NULL\n~C\nGR.GAPI : GR\nRHOB.G/C3 : RH\n~A\n10.0 2.0\n20.0 -999.25\n30.0 2.5\n";
}

// CRLF lines, lowercase section letters and mnemonics, tabs, comments,
// a negative STEP and a custom NULL.
fn las_crlf() -> Str {
  return "\r\n# full line comment\r\n~version\r\nvers.\t2.0\t: X\r\nwrap.\tno\t: N\r\n~well\r\nstrt.m\t10.0\t: S\r\nstep.m\t-0.5\t: T\r\nnull.\t-9.99\t: N\r\nwell.\twell-9\t: W\r\n~curve\r\ngr.gapi\t: G\r\n~ascii\r\n10.0\t1.5\r\n9.5\t2.5\r\n";
}

// Quoted string values with dots and an embedded colon; API-code curve row.
fn las_quoted() -> Str {
  return "~V\nVERS. 2.0 : X\nWRAP. NO : N\n~W\nSTRT.M 1.0 : S\nSTEP.M 1.0 : T\nWELL. \"WELL-A.1 : NORTH\" : WELL\n~C\nGR.GAPI 00 000 00 00 : GAMMA RAY\nRHOB.G/C3 : RHOB\nCALI.IN : CALI\n~A\n1.0 \"2.5\" 3.0\n";
}

// NULL variants: one dedicated depth column, explicit NULL value, a blank
// quoted cell, and default NULL.
fn las_nulls() -> Str {
  return "~V\nVERS. 2.0 : X\nWRAP. NO : N\n~W\nSTRT.M 0.0 : S\nSTEP.M 1.0 : T\nNULL. -999.0 : N\n~C\nGR.GAPI : G\nRHOB.G/C3 : R\nCALI.IN : C\n~A\n0.0 -999.0 1.0 2.0\n1.0 2.0 \"\" 3.0\n2.0 -999.0 -999.0 4.0\n";
}

// Fixed-point truncation toward zero (no rounding, no floats).
fn las_numbers() -> Str {
  return "~V\nVERS. 2.0 : X\nWRAP. NO : N\n~W\nSTRT.M 0.0 : S\nSTEP.M 1.0 : T\n~C\nA : A\nB : B\nC : C\nD : D\nE : E\nF : F\n~A\n0.0 1.2345 -1.2345 -0.125 +2.5 0.0009 -0.0009\n";
}

// ~O block interleaved before ~A; comments and spacing preserved verbatim.
fn las_other() -> Str {
  return "~V\nVERS. 2.0 : X\nWRAP. NO : N\n~C\nGR.GAPI : G\n~O\n# kept verbatim\n  raw line  \n~A\n0.0 1.5\n";
}

// Multiple well rows (one with a space in the value) and two parameters.
fn las_meta() -> Str {
  return "~V\nVERS. 2.0 : X\nWRAP. NO : N\n~W\nSTRT.M 0.0 : S\nSTEP.M 1.0 : T\nWELL. WELL-7 : W\nCOMP. COMPANY NAME : C\n~P\nBHT.DEGC 85.5 : TEMP\nMD.M 1200.0 : DEPTH\n~C\nGR.GAPI : G\n~A\n0.0 1.5\n";
}

// Trailing comments on data rows, blank lines, multiple spaces.
fn las_inline_comments() -> Str {
  return "~V\nVERS. 2.0 : X\nWRAP. NO : N\n~C\nGR.GAPI : G\n~A\n0.0 1.5 # trailing comment\n# full comment\n1.0   2.5\n\n2.0 3.5\n";
}

// No ~V section at all: defaults only.
fn las_no_version() -> Str {
  return "~C\nGR.GAPI : G\n~A\n0.0 1.5\n";
}

// --- tests ------------------------------------------------------------------

fn t1() -> TestResult {
  let r = las_parse(las_basic());
  var ok = false;
  match r {
    Ok(g) => {
      ok = streq(las_version(&g), "2.0");
      if las_wrap(&g) { ok = false; }
      if las_start_depth(&g) != 1000000 { ok = false; }
      if las_stop_depth(&g) != 1002500 { ok = false; }
      if las_step(&g) != 500 { ok = false; }
      if !streq(las_depth_unit(&g), "M") { ok = false; }
      if las_null_value(&g) != -999250 { ok = false; }
      if !las_depth_known(&g) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "basic: version 2.0, WRAP NO, STRT/STOP/STEP/NULL scaled -999.25");
}

fn t2() -> TestResult {
  let r = las_parse(las_basic());
  var ok = false;
  match r {
    Ok(g) => {
      ok = las_curve_count(&g) == 3;
      if !streq(las_curve_name(&g, 0), "DEPT") { ok = false; }
      if !streq(las_curve_name(&g, 1), "GR") { ok = false; }
      if !streq(las_curve_name(&g, 2), "RHOB") { ok = false; }
      if !streq(las_curve_unit(&g, 0), "M") { ok = false; }
      if !streq(las_curve_unit(&g, 1), "GAPI") { ok = false; }
      if !streq(las_curve_unit(&g, 2), "G/C3") { ok = false; }
      if !streq(las_curve_desc(&g, 1), "GAMMA RAY") { ok = false; }
      if !streq(las_curve_desc(&g, 2), "BULK DENSITY") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "basic: curve count, names, units and descriptions");
}

fn t3() -> TestResult {
  let r = las_parse(las_basic());
  var ok = false;
  match r {
    Ok(g) => {
      ok = las_row_count(&g) == 3;
      if las_cell_value(&g, 0, 0) != 1000000 { ok = false; }
      if las_cell_value(&g, 2, 0) != 1001000 { ok = false; }
      if las_cell_value(&g, 1, 0) != 1000500 { ok = false; }
      if las_cell_value(&g, 1, 1) != 45500 { ok = false; }
      if las_cell_value(&g, 2, 2) != 2550 { ok = false; }
      if !las_cell_is_null(&g, 1, 2) { ok = false; }
      if las_depth(&g, 0) != 1000000 { ok = false; }
      if las_depth(&g, 2) != 1001000 { ok = false; }
      if las_depth_read(&g, 2) != 1001000 { ok = false; }
      if !las_depth_is_expected(&g, 1, 1000500) { ok = false; }
      if las_depth_is_expected(&g, 1, 1000501) { ok = false; }
      if las_row_line(&g, 0) != 18 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "basic: rows, scaled cells, depths and exact depth comparisons");
}

fn t4() -> TestResult {
  let r = las_parse(las_basic());
  var ok = false;
  match r {
    Ok(g) => {
      ok = las_cell_is_null(&g, 0, 1);
      if las_cell_value(&g, 0, 1) != -999250 { ok = false; }
      if !las_cell_is_null(&g, 1, 2) { ok = false; }
      let c01 = las_cell(&g, 0, 1);
      if !c01.is_null { ok = false; }
      if c01.value != -999250 { ok = false; }
      let c11 = las_cell(&g, 1, 1);
      if c11.is_null { ok = false; }
      if c11.value != 45500 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "basic: NULL cells keep raw scaled magnitude and a null flag");
}

fn t5() -> TestResult {
  let r = las_parse(las_basic());
  var ok = false;
  match r {
    Ok(g) => {
      ok = las_well_count(&g) == 2;
      if !streq(las_well_lookup(&g, "well"), "WELL-1") { ok = false; }
      if !streq(las_well_lookup(&g, "COMP"), "COMPANY-X") { ok = false; }
      if !streq(las_well_lookup(&g, "MISSING"), "") { ok = false; }
      if !streq(las_well_mnemonic(&g, 0), "WELL") { ok = false; }
      if las_param_count(&g) != 1 { ok = false; }
      if !streq(las_param_lookup(&g, "bht"), "85.5") { ok = false; }
      if !streq(las_param_unit(&g, 0), "DEGC") { ok = false; }
      if las_curve_index(&g, "gr") != 1 { ok = false; }
      if las_curve_index(&g, "NOPE") != -1 { ok = false; }
      if las_other_count(&g) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "basic: well/param lookups are case-insensitive; curve index");
}

fn t6() -> TestResult {
  let r = las_parse(las_wrapped());
  var ok = false;
  match r {
    Ok(g) => {
      ok = las_wrap(&g);
      if !las_depth_known(&g) { ok = false; }
      if las_curve_count(&g) != 2 { ok = false; }
      if las_row_count(&g) != 3 { ok = false; }
      if las_depth(&g, 0) != 0 { ok = false; }
      if las_depth(&g, 1) != 1000 { ok = false; }
      if las_depth(&g, 2) != 2000 { ok = false; }
      if las_depth_read(&g, 0) != -1 { ok = false; }
      if las_cell_value(&g, 0, 0) != 10000 { ok = false; }
      if las_cell_value(&g, 2, 0) != 30000 { ok = false; }
      if las_cell_value(&g, 2, 1) != 2500 { ok = false; }
      if !las_cell_is_null(&g, 1, 1) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "wrapped: depth implied by STRT + row * STEP, depth_read -1");
}

fn t7() -> TestResult {
  let r = las_parse(las_crlf());
  var ok = false;
  match r {
    Ok(g) => {
      ok = streq(las_version(&g), "2.0");
      if las_wrap(&g) { ok = false; }
      if las_curve_count(&g) != 1 { ok = false; }
      if !streq(las_curve_name(&g, 0), "gr") { ok = false; }
      if !streq(las_curve_unit(&g, 0), "gapi") { ok = false; }
      if las_row_count(&g) != 2 { ok = false; }
      if las_cell_value(&g, 0, 0) != 1500 { ok = false; }
      if las_cell_value(&g, 1, 0) != 2500 { ok = false; }
      if las_null_value(&g) != -9990 { ok = false; }
      if las_depth(&g, 1) != 9500 { ok = false; }
      if las_depth_read(&g, 1) != 9500 { ok = false; }
      if !streq(las_well_lookup(&g, "WELL"), "well-9") { ok = false; }
      if !streq(las_depth_unit(&g), "m") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CRLF, lowercase sections, tabs, comment, negative STEP");
}

fn t8() -> TestResult {
  let r = las_parse(las_quoted());
  var ok = false;
  match r {
    Ok(g) => {
      ok = streq(las_well_lookup(&g, "WELL"), "WELL-A.1 : NORTH");
      if !streq(las_curve_type(&g, 0), "00 000 00 00") { ok = false; }
      if !streq(las_curve_unit(&g, 0), "GAPI") { ok = false; }
      if !streq(las_curve_desc(&g, 0), "GAMMA RAY") { ok = false; }
      if !streq(las_curve_unit(&g, 2), "IN") { ok = false; }
      if las_cell_value(&g, 0, 1) != 2500 { ok = false; }
      if las_cell_value(&g, 0, 2) != 3000 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "quoted values keep dots and colons; API-code curve rows");
}

fn t9() -> TestResult {
  let r = las_parse(las_nulls());
  var ok = false;
  match r {
    Ok(g) => {
      ok = las_null_value(&g) == -999000;
      if !las_cell_is_null(&g, 0, 0) { ok = false; }
      if las_cell_value(&g, 0, 0) != -999000 { ok = false; }
      if !las_cell_is_null(&g, 1, 1) { ok = false; }
      if las_cell_value(&g, 1, 1) != 0 { ok = false; }
      if !las_cell_is_null(&g, 2, 0) { ok = false; }
      if !las_cell_is_null(&g, 2, 1) { ok = false; }
      if las_cell_is_null(&g, 1, 2) { ok = false; }
      if las_cell_value(&g, 1, 0) != 2000 { ok = false; }
      if las_cell_value(&g, 1, 2) != 3000 { ok = false; }
      if las_cell_value(&g, 2, 2) != 4000 { ok = false; }
      if las_depth_read(&g, 1) != 1000 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "nulls: declared NULL, blank quoted cell, non-null neighbor");
}

fn t10() -> TestResult {
  let r = las_parse(las_numbers());
  var ok = false;
  match r {
    Ok(g) => {
      ok = las_cell_value(&g, 0, 0) == 1234;
      if las_cell_value(&g, 0, 1) != -1234 { ok = false; }
      if las_cell_value(&g, 0, 2) != -125 { ok = false; }
      if las_cell_value(&g, 0, 3) != 2500 { ok = false; }
      if las_cell_value(&g, 0, 4) != 0 { ok = false; }
      if las_cell_value(&g, 0, 5) != 0 { ok = false; }
      if las_cell_is_null(&g, 0, 4) { ok = false; }
      if las_cell_is_null(&g, 0, 5) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "scaled parsing truncates toward zero: 1.2345/-1.2345/-0.125/+2.5");
}

fn t11() -> TestResult {
  let prefix = "~V\nVERS. 2.0 : X\nWRAP. NO : N\n~W\nSTRT.M 0.0 : S\nSTEP.M 1.0 : T\n~C\nGR.GAPI : G\nRHOB.G/C3 : R\n~A\n0.0 1.0 2.0\n1.0 ";
  let fixture = prefix + "abc 3.0\n";
  let want = "geology: invalid numeric token: abc at line 12 offset " + convert.int_to_string(prefix.len());
  let ok = err_is(fixture, want);
  return assert(ok, "error: bad numeric token carries exact message, line and offset");
}

fn t12() -> TestResult {
  let head = "~V\nVERS. 2.0 : X\nWRAP. NO : N\n~W\nSTRT.M 0.0 : S\nSTEP.M 1.0 : T\n~C\nGR.GAPI : G\nRHOB.G/C3 : R\n~A\n";
  let off = head.len() + 12;
  let off_short = head.len() + 8;
  var ok = err_at(head + "0.0 1.0 2.0\n1.0 2.0\n", 12, off);
  if !err_at(head + "0.0 1.0 2.0\n1.0\n", 12, off) { ok = false; }
  if !err_at(head + "0.0 1.0 2.0\n1.0 2.0 3.0 4.0\n", 12, off) { ok = false; }
  if !err_at(head + "1.0 2.0\n1.0 2.0 3.0\n", 12, off_short) { ok = false; }
  let want = "geology: ragged row: expected 3 values, got 2 at line 12 offset " + convert.int_to_string(off);
  if !err_is(head + "0.0 1.0 2.0\n1.0 2.0\n", want) { ok = false; }
  return assert(ok, "error: ragged rows rejected against the file's row shape");
}

fn t13() -> TestResult {
  let head = "~V\nVERS. 2.0 : X\nWRAP. YES : W\n~W\nSTRT.M 0.0 : S\nSTEP.M 1.0 : T\n~C\nGR.GAPI : G\nRHOB.G/C3 : R\n~A\n";
  let fixture = head + "1.0 2.0 3.0\n";
  let ok = err_at(fixture, 11, head.len());
  return assert(ok, "error: wrapped ragged row (3 of 2 values)");
}

fn t14() -> TestResult {
  let head = "~V\nVERS. 2.0 : X\nWRAP. NO : N\n~W\nSTRT.M 0.0 : S\nSTEP.M 1.0 : T\n~C\nGR.GAPI : G\nRHOB.G/C3 : R\n~A\n";
  let fixture = head + "\"\" 1.0 2.0\n";
  let want = "geology: invalid depth token:  at line 11 offset " + convert.int_to_string(head.len());
  let ok = err_is(fixture, want);
  return assert(ok, "error: blank quoted depth token is rejected");
}

fn t15() -> TestResult {
  let fixture = "~V\nVERS. 2.0 : X\nWRAP. NO : N\n";
  let ok = err_at(fixture, 4, fixture.len());
  return assert(ok, "error: missing ~C is rejected at one-past-last line");
}

fn t16() -> TestResult {
  let head = "~V\nVERS. 2.0 : X\n";
  let ok = err_at(head + "~C\n", 3, head.len());
  return assert(ok, "error: empty ~C curve section points at the ~C header");
}

fn t17() -> TestResult {
  let head = "~V\nVERS. 2.0 : X\n";
  let ok = err_at(head + "~Z stuff\n", 3, head.len());
  return assert(ok, "error: unknown section letter is rejected");
}

fn t18() -> TestResult {
  let head = "~C\nGR : G\n";
  let ok = err_at(head + "~C\n", 3, head.len());
  return assert(ok, "error: duplicate ~C section is rejected");
}

fn t19() -> TestResult {
  let r = las_parse(las_other());
  var ok = false;
  match r {
    Ok(g) => {
      ok = las_other_count(&g) == 2;
      if !streq(las_other_line(&g, 0), "# kept verbatim") { ok = false; }
      if !streq(las_other_line(&g, 1), "  raw line  ") { ok = false; }
      if las_row_count(&g) != 1 { ok = false; }
      if las_cell_value(&g, 0, 0) != 1500 { ok = false; }
      if !streq(las_other_line(&g, 9), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "~O lines are preserved verbatim, comments included");
}

fn t20() -> TestResult {
  let r = las_parse(las_meta());
  var ok = false;
  match r {
    Ok(g) => {
      ok = las_well_count(&g) == 2;
      if !streq(las_well_lookup(&g, "COMP"), "COMPANY NAME") { ok = false; }
      if !streq(las_well_value(&g, 0), "WELL-7") { ok = false; }
      if las_param_count(&g) != 2 { ok = false; }
      if !streq(las_param_lookup(&g, "md"), "1200.0") { ok = false; }
      if !streq(las_param_mnemonic(&g, 0), "BHT") { ok = false; }
      if !streq(las_param_desc(&g, 1), "DEPTH") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "~W/~P metadata rows and lookups (values with spaces)");
}

fn t21() -> TestResult {
  let r = las_parse(las_inline_comments());
  var ok = false;
  match r {
    Ok(g) => {
      ok = las_row_count(&g) == 3;
      if las_cell_value(&g, 0, 0) != 1500 { ok = false; }
      if las_cell_value(&g, 1, 0) != 2500 { ok = false; }
      if las_cell_value(&g, 2, 0) != 3500 { ok = false; }
      if las_row_line(&g, 0) != 7 { ok = false; }
      if las_row_line(&g, 1) != 9 { ok = false; }
      if las_row_line(&g, 2) != 11 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "inline '#' comments, blank lines and multi-space rows");
}

fn t22() -> TestResult {
  let r = las_parse(las_no_version());
  var ok = false;
  match r {
    Ok(g) => {
      ok = streq(las_version(&g), "");
      if las_wrap(&g) { ok = false; }
      if las_null_value(&g) != -999250 { ok = false; }
      if las_row_count(&g) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "missing ~V: empty version, WRAP NO and default NULL -999.25");
}

fn t23() -> TestResult {
  let r = las_parse(las_basic());
  var ok = false;
  match r {
    Ok(g) => {
      ok = las_cell_is_null(&g, 99, 0);
      let nm0 = las_curve_name(&g, 99);
      let nm1 = las_curve_name(&g, -1);
      if nm0.len() != 0 { ok = false; }
      if !streq(nm1, "") { ok = false; }
      if las_depth(&g, 99) != -1 { ok = false; }
      if las_depth_read(&g, 99) != -1 { ok = false; }
      if las_row_line(&g, -1) != -1 { ok = false; }
      let wm = las_well_mnemonic(&g, 99);
      let pm = las_param_mnemonic(&g, 99);
      let ol = las_other_line(&g, 0);
      if wm.len() != 0 { ok = false; }
      if pm.len() != 0 { ok = false; }
      if ol.len() != 0 { ok = false; }
      let oc = las_cell(&g, 99, 0);
      if oc.value != 0 { ok = false; }
      if !oc.is_null { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "out-of-range accessors are total (empty, -1, null cell)");
}

fn t24() -> TestResult {
  let r = las_parse("~W\nSTRT.M 500.0 : S\nNULL. -999.25 : N\n~C\nGR.GAPI : G\n~A\n500.0 1.0\n502.0 3.0\n");
  var ok = false;
  match r {
    Ok(g) => {
      ok = las_has_start(&g);
      if las_has_step(&g) { ok = false; }
      if las_depth_known(&g) { ok = false; }
      if las_depth(&g, 1) != -1 { ok = false; }
      if las_depth_read(&g, 1) != 502000 { ok = false; }
      if las_depth_is_expected(&g, 1, 502000) { ok = false; }
      if las_step(&g) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "missing STEP: depth arithmetic unknown, raw depth still kept");
}

fn t25() -> TestResult {
  var ok = streq(las_scaled_to_string(-999250), "-999.250");
  if !streq(las_scaled_to_string(45500), "45.500") { ok = false; }
  if !streq(las_scaled_to_string(0), "0.000") { ok = false; }
  if !streq(las_scaled_to_string(1234), "1.234") { ok = false; }
  if !streq(las_scaled_to_string(-125), "-0.125") { ok = false; }
  if !streq(las_scaled_to_string(7), "0.007") { ok = false; }
  if las_value_scale() != 1000 { ok = false; }
  return assert(ok, "las_scaled_to_string renders thousandths with a sign");
}

fn t26() -> TestResult {
  var ok = geology_error_line("geology: ragged row: expected 3 values, got 2 at line 12 offset 240") == 12;
  if geology_error_offset("geology: ragged row: expected 3 values, got 2 at line 12 offset 240") != 240 { ok = false; }
  if geology_error_line("no markers here") != -1 { ok = false; }
  if geology_error_offset("no markers here") != -1 { ok = false; }
  if geology_error_line("geology: x at line 0 offset 0") != 0 { ok = false; }
  let head = "~V\nVERS. 2.0 : X\n";
  if !err_at(head + "~Q\n", 3, head.len()) { ok = false; }
  let head2 = "~V\n";
  if !err_at(head2 + "WRAP. MAYBE : X\n~C\nGR : G\n", 2, head2.len()) { ok = false; }
  return assert(ok, "error helpers parse line/offset; invalid WRAP rejected");
}

fn report(res: TestResult) -> Int {
  if res.passed { io.println("  [PASS] " + res.name); return 0; }
  io.println("  [FAIL] " + res.name);
  return 1;
}

fn main() -> Int {
  io.println("=== xiom.geology conformance tests ===");
  var failed: Int = 0;
  failed = failed + report(t1());
  failed = failed + report(t2());
  failed = failed + report(t3());
  failed = failed + report(t4());
  failed = failed + report(t5());
  failed = failed + report(t6());
  failed = failed + report(t7());
  failed = failed + report(t8());
  failed = failed + report(t9());
  failed = failed + report(t10());
  failed = failed + report(t11());
  failed = failed + report(t12());
  failed = failed + report(t13());
  failed = failed + report(t14());
  failed = failed + report(t15());
  failed = failed + report(t16());
  failed = failed + report(t17());
  failed = failed + report(t18());
  failed = failed + report(t19());
  failed = failed + report(t20());
  failed = failed + report(t21());
  failed = failed + report(t22());
  failed = failed + report(t23());
  failed = failed + report(t24());
  failed = failed + report(t25());
  failed = failed + report(t26());
  if failed == 0 {
    io.println("xiom.geology: all tests passed");
  } else {
    io.println("xiom.geology: tests failed");
  }
  return failed;
}
