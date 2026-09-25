// XIOM -- xiom.hl7 conformance tests (23 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: segment splitting and ordering, MSH separator declaration,
// 1-based field access with bounds, repetitions, components, subcomponents,
// custom separators, LF/CRLF terminators, trailing terminators, empty
// messages, missing MSH, malformed MSH shape, invalid separators, empty
// segment names, name-only segments, empty fields, the builder (happy path,
// escaping, error catalog, custom separators), UTF-8 passthrough and a
// byte-exact parse/write round trip.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq/opt_str_is/opt_eq instead of `==`.

module hl7_tests
use xiom.io; use xiom.test; use xiom.hl7;
use xiom.string.compare;

// A canonical ADT^A01 message: CR segment terminators, trailing CR, MSH with
// the default separators, a repeated PID.3 and a two-level PV1.3.
const M1: Str = "MSH|^~\\&|SENDAPP|SENDFAC|RECVAPP|RECVFAC|20260101000000||ADT^A01|MSG00001|P|2.5.1\rPID|1||123456^^^MRN~789012^^^SSN||DOE^JOHN^A||19800101|M\rPV1|1|I|WARD^101^1||||1234^SMITH^JOHN\r";

// The same shape with custom separators (field "*", component "%",
// repetition "~", escape "\", subcomponent "$").
const M7: Str = "MSH*%~\\$*SENDAPP*SENDFAC\rPID*1*DOE%JOHN~ROE%JANE\rOBX*1*X$Y\r";

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn opt_str_is(o: Option[Str], want: Str) -> Bool {
  match o {
    Some(v) => { return streq(v, want); },
    None => { return false; },
  }
  return false;
}

fn opt_str_none(o: Option[Str]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn opt_int_is(o: Option[Int], want: Int) -> Bool {
  match o {
    Some(v) => { return v == want; },
    None => { return false; },
  }
  return false;
}

fn opt_int_none(o: Option[Int]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn opt_eq(a: Option[Str], b: Option[Str]) -> Bool {
  match a {
    Some(x) => { return opt_str_is(b, x); },
    None => { return opt_str_none(b); },
  }
  return false;
}

// Parse text, or fall back to an empty builder message when it does not
// parse; assertions that expect values fail loudly in that case.
fn parse_msg(text: Str) -> Message {
  let r = hl7_parse(text);
  match r {
    Ok(m) => { return m; },
    Err(_) => { return hl7_builder_new(); },
  }
  return hl7_builder_new();
}

// The parse error message, or "" when the text parsed.
fn parse_err(text: Str) -> Str {
  let r = hl7_parse(text);
  match r {
    Ok(_) => { return ""; },
    Err(e) => { return e; },
  }
  return "";
}

// The builder setup error message, or "" when the separators were accepted.
fn builder_err(field_sep: Str, encoding: Str) -> Str {
  let r = hl7_builder_with_separators(field_sep, encoding);
  match r {
    Ok(_) => { return ""; },
    Err(e) => { return e; },
  }
  return "";
}

fn t1() -> TestResult {
  let m = parse_msg(M1);
  var ok = hl7_seg_count(&m) == 3;
  if !opt_str_is(hl7_seg_name(&m, 0), "MSH") { ok = false; }
  if !opt_str_is(hl7_seg_name(&m, 1), "PID") { ok = false; }
  if !opt_str_is(hl7_seg_name(&m, 2), "PV1") { ok = false; }
  if !opt_str_none(hl7_seg_name(&m, 3)) { ok = false; }
  if !opt_str_none(hl7_seg_name(&m, -1)) { ok = false; }
  if !opt_int_is(hl7_seg_index(&m, "PID"), 1) { ok = false; }
  if !opt_int_none(hl7_seg_index(&m, "OBX")) { ok = false; }
  return assert(ok, "parse yields the three segments in order");
}

fn t2() -> TestResult {
  let m = parse_msg(M1);
  var ok = streq(hl7_field_sep(&m), "|");
  if !streq(hl7_encoding(&m), "^~\\&") { ok = false; }
  if !opt_str_is(hl7_field(&m, 0, 1), "|") { ok = false; }
  if !opt_str_is(hl7_field(&m, 0, 2), "^~\\&") { ok = false; }
  if !opt_str_is(hl7_field(&m, 0, 3), "SENDAPP") { ok = false; }
  if hl7_seg_field_count(&m, 0) != 12 { ok = false; }
  return assert(ok, "MSH.1 and MSH.2 declare the separators");
}

fn t3() -> TestResult {
  let m = parse_msg(M1);
  var ok = hl7_seg_field_count(&m, 1) == 8;
  if !opt_str_is(hl7_field(&m, 1, 1), "1") { ok = false; }
  if !opt_str_is(hl7_field(&m, 1, 2), "") { ok = false; }
  if !opt_str_is(hl7_field(&m, 1, 5), "DOE^JOHN^A") { ok = false; }
  if !opt_str_is(hl7_field(&m, 1, 8), "M") { ok = false; }
  if !opt_str_none(hl7_field(&m, 1, 9)) { ok = false; }
  if !opt_str_none(hl7_field(&m, 1, 0)) { ok = false; }
  if !opt_str_none(hl7_field(&m, 9, 1)) { ok = false; }
  if hl7_seg_field_count(&m, 9) != 0 { ok = false; }
  return assert(ok, "field access is 1-based and bounds-checked");
}

fn t4() -> TestResult {
  let m = parse_msg("MSH|^~\\&|A\rPID|a~b~c~");
  var ok = hl7_rep_count(&m, 1, 1) == 4;
  if !opt_str_is(hl7_rep(&m, 1, 1, 1), "a") { ok = false; }
  if !opt_str_is(hl7_rep(&m, 1, 1, 2), "b") { ok = false; }
  if !opt_str_is(hl7_rep(&m, 1, 1, 3), "c") { ok = false; }
  if !opt_str_is(hl7_rep(&m, 1, 1, 4), "") { ok = false; }
  if !opt_str_none(hl7_rep(&m, 1, 1, 5)) { ok = false; }
  if !opt_str_none(hl7_rep(&m, 1, 1, 0)) { ok = false; }
  if hl7_rep_count(&m, 1, 2) != 0 { ok = false; }
  return assert(ok, "repetitions split on the repetition separator");
}

fn t5() -> TestResult {
  let m = parse_msg("MSH|^~\\&|A\rPID|DOE^JOHN^A\rOBX|X^^Z");
  var ok = hl7_comp_count(&m, 1, 1, 1) == 3;
  if !opt_str_is(hl7_comp(&m, 1, 1, 1, 1), "DOE") { ok = false; }
  if !opt_str_is(hl7_comp(&m, 1, 1, 1, 2), "JOHN") { ok = false; }
  if !opt_str_is(hl7_comp(&m, 1, 1, 1, 3), "A") { ok = false; }
  if !opt_str_none(hl7_comp(&m, 1, 1, 1, 4)) { ok = false; }
  if hl7_comp_count(&m, 2, 1, 1) != 3 { ok = false; }
  if !opt_str_is(hl7_comp(&m, 2, 1, 1, 2), "") { ok = false; }
  if !opt_str_is(hl7_comp(&m, 2, 1, 1, 3), "Z") { ok = false; }
  return assert(ok, "components split on the component separator");
}

fn t6() -> TestResult {
  let m = parse_msg("MSH|^~\\&|A\rPID|DOE^JOHN~ROE^JANE\rOBX|A&B^C");
  var ok = hl7_comp_count(&m, 1, 1, 2) == 2;
  if !opt_str_is(hl7_comp(&m, 1, 1, 2, 1), "ROE") { ok = false; }
  if !opt_str_is(hl7_comp(&m, 1, 1, 2, 2), "JANE") { ok = false; }
  if hl7_sub_count(&m, 2, 1, 1, 1) != 2 { ok = false; }
  if !opt_str_is(hl7_sub(&m, 2, 1, 1, 1, 1), "A") { ok = false; }
  if !opt_str_is(hl7_sub(&m, 2, 1, 1, 1, 2), "B") { ok = false; }
  if hl7_sub_count(&m, 2, 1, 1, 2) != 1 { ok = false; }
  if !opt_str_is(hl7_sub(&m, 2, 1, 1, 2, 1), "C") { ok = false; }
  if !opt_str_none(hl7_sub(&m, 2, 1, 1, 2, 2)) { ok = false; }
  return assert(ok, "repetition-aware components and subcomponents");
}

fn t7() -> TestResult {
  let m = parse_msg(M7);
  var ok = streq(hl7_field_sep(&m), "*");
  if !streq(hl7_encoding(&m), "%~\\$") { ok = false; }
  if hl7_rep_count(&m, 1, 2) != 2 { ok = false; }
  if !opt_str_is(hl7_comp(&m, 1, 2, 2, 1), "ROE") { ok = false; }
  if !opt_str_is(hl7_comp(&m, 1, 2, 2, 2), "JANE") { ok = false; }
  if hl7_sub_count(&m, 2, 2, 1, 1) != 2 { ok = false; }
  if !opt_str_is(hl7_sub(&m, 2, 2, 1, 1, 2), "Y") { ok = false; }
  if !streq(hl7_write(&m), M7) { ok = false; }
  return assert(ok, "custom separators parse, split and round-trip");
}

fn t8() -> TestResult {
  let lf = parse_msg("MSH|^~\\&|A\nPID|1\n");
  let crlf = parse_msg("MSH|^~\\&|A\r\nPID|1\r\n");
  var ok = hl7_seg_count(&lf) == 2;
  if hl7_seg_count(&crlf) != 2 { ok = false; }
  if !opt_str_is(hl7_seg_name(&lf, 1), "PID") { ok = false; }
  if !opt_str_is(hl7_field(&crlf, 1, 1), "1") { ok = false; }
  if !streq(hl7_write(&lf), "MSH|^~\\&|A\rPID|1\r") { ok = false; }
  return assert(ok, "LF and CRLF are accepted and normalize to CR on write");
}

fn t9() -> TestResult {
  let m = parse_msg("MSH|^~\\&|A");
  var ok = hl7_seg_count(&m) == 1;
  if !streq(hl7_write(&m), "MSH|^~\\&|A\r") { ok = false; }
  let m2 = parse_msg("MSH|^~\\&|A\r");
  if hl7_seg_count(&m2) != 1 { ok = false; }
  let m3 = parse_msg("MSH|^~\\&");
  if hl7_seg_count(&m3) != 1 { ok = false; }
  if hl7_seg_field_count(&m3, 0) != 2 { ok = false; }
  if !streq(hl7_write(&m3), "MSH|^~\\&\r") { ok = false; }
  return assert(ok, "a trailing terminator adds no segment");
}

fn t10() -> TestResult {
  var ok = streq(parse_err(""), "hl7: empty message");
  if !streq(parse_err("\r"), "hl7: empty message") { ok = false; }
  if !streq(parse_err("\n"), "hl7: empty message") { ok = false; }
  if !streq(parse_err("\r\n"), "hl7: empty message") { ok = false; }
  return assert(ok, "empty and terminator-only input is an empty message");
}

fn t11() -> TestResult {
  var ok = streq(parse_err("PID|1"), "hl7: missing MSH segment");
  if !streq(parse_err("msh|^~\\&|A"), "hl7: missing MSH segment") { ok = false; }
  if !streq(parse_err("M|A"), "hl7: missing MSH segment") { ok = false; }
  return assert(ok, "the first segment must be MSH, case-sensitively");
}

fn t12() -> TestResult {
  var ok = streq(parse_err("MSH"), "hl7: malformed MSH segment: too short");
  if !streq(parse_err("MSH|"), "hl7: malformed MSH segment: expected 4 encoding characters, got 0") { ok = false; }
  if !streq(parse_err("MSH|^~"), "hl7: malformed MSH segment: expected 4 encoding characters, got 2") { ok = false; }
  if !streq(parse_err("MSH|^~\\&X"), "hl7: malformed MSH segment: expected 4 encoding characters, got 5") { ok = false; }
  return assert(ok, "MSH must carry exactly four encoding characters");
}

fn t13() -> TestResult {
  var ok = streq(parse_err("MSH1^~\\&|A"), "hl7: invalid separator");
  if !streq(parse_err("MSH|ABCD|A"), "hl7: invalid separator") { ok = false; }
  if !streq(parse_err("MSH|^^\\&|A"), "hl7: invalid separator") { ok = false; }
  if !streq(parse_err("MSH ^~\\&|A"), "hl7: invalid separator") { ok = false; }
  return assert(ok, "separators must be printable ASCII and not alphanumeric");
}

fn t14() -> TestResult {
  var ok = streq(parse_err("MSH|^~\\&|A\r\rPID|1"), "hl7: empty segment name");
  if !streq(parse_err("MSH|^~\\&|A\r|X"), "hl7: empty segment name") { ok = false; }
  if !streq(parse_err("MSH|^~\\&|A\r\n\r\nPID|1"), "hl7: empty segment name") { ok = false; }
  return assert(ok, "empty segment lines and names are rejected");
}

fn t15() -> TestResult {
  let m = parse_msg("MSH|^~\\&|A\rNTE\rPID|1|2");
  var ok = hl7_seg_count(&m) == 3;
  if !opt_str_is(hl7_seg_name(&m, 1), "NTE") { ok = false; }
  if hl7_seg_field_count(&m, 1) != 0 { ok = false; }
  if !opt_str_none(hl7_field(&m, 1, 1)) { ok = false; }
  if hl7_seg_field_count(&m, 2) != 2 { ok = false; }
  if !opt_str_is(hl7_field(&m, 2, 2), "2") { ok = false; }
  if !streq(hl7_write(&m), "MSH|^~\\&|A\rNTE\rPID|1|2\r") { ok = false; }
  return assert(ok, "a name-only segment has zero fields; counts are per segment");
}

fn t16() -> TestResult {
  let m = parse_msg("MSH|^~\\&|A\rPID||B|");
  var ok = hl7_seg_field_count(&m, 1) == 3;
  if !opt_str_is(hl7_field(&m, 1, 1), "") { ok = false; }
  if !opt_str_is(hl7_field(&m, 1, 2), "B") { ok = false; }
  if !opt_str_is(hl7_field(&m, 1, 3), "") { ok = false; }
  if !streq(hl7_write(&m), "MSH|^~\\&|A\rPID||B|\r") { ok = false; }
  return assert(ok, "empty leading, middle and trailing fields are preserved");
}

fn t17() -> TestResult {
  var b = hl7_builder_new();
  let e1 = hl7_builder_segment(&mut b, "MSH");
  let e2 = hl7_builder_field(&mut b, "SENDAPP");
  let e3 = hl7_builder_field(&mut b, "SENDFAC");
  let e4 = hl7_builder_segment(&mut b, "PID");
  let e5 = hl7_builder_field(&mut b, "1");
  let e6 = hl7_builder_field_structured(&mut b, "DOE^JOHN");
  var ok = streq(e1, "");
  if !streq(e2, "") { ok = false; }
  if !streq(e3, "") { ok = false; }
  if !streq(e4, "") { ok = false; }
  if !streq(e5, "") { ok = false; }
  if !streq(e6, "") { ok = false; }
  let w = hl7_write(&b);
  if !streq(w, "MSH|^~\\&|SENDAPP|SENDFAC\rPID|1|DOE^JOHN\r") { ok = false; }
  let m = parse_msg(w);
  if !opt_str_is(hl7_field(&m, 0, 3), "SENDAPP") { ok = false; }
  if !opt_str_is(hl7_field(&m, 1, 2), "DOE^JOHN") { ok = false; }
  if hl7_comp_count(&m, 1, 2, 1) != 2 { ok = false; }
  if !opt_str_is(hl7_comp(&m, 1, 2, 1, 2), "JOHN") { ok = false; }
  return assert(ok, "builder writes MSH positionally and appends fields");
}

fn t18() -> TestResult {
  var b = hl7_builder_new();
  let s0 = hl7_builder_segment(&mut b, "MSH");
  let f0 = hl7_builder_field(&mut b, "S");
  let s1 = hl7_builder_segment(&mut b, "PID");
  let f1 = hl7_builder_field(&mut b, "A|B^C~D\\E&F");
  var ok = streq(s0, "");
  if !streq(f0, "") { ok = false; }
  if !streq(s1, "") { ok = false; }
  if !streq(f1, "") { ok = false; }
  let w = hl7_write(&b);
  if !streq(w, "MSH|^~\\&|S\rPID|A\\F\\B\\S\\C\\R\\D\\E\\E\\T\\F\r") { ok = false; }
  let m = parse_msg(w);
  if hl7_seg_field_count(&m, 1) != 1 { ok = false; }
  if hl7_rep_count(&m, 1, 1) != 1 { ok = false; }
  if hl7_comp_count(&m, 1, 1, 1) != 1 { ok = false; }
  if !opt_str_is(hl7_field(&m, 1, 1), "A\\F\\B\\S\\C\\R\\D\\E\\E\\T\\F") { ok = false; }
  var b2 = hl7_builder_new();
  let t0 = hl7_builder_segment(&mut b2, "MSH");
  let t1 = hl7_builder_field(&mut b2, "S");
  let t2 = hl7_builder_segment(&mut b2, "PID");
  let t3 = hl7_builder_field_structured(&mut b2, "A|B\\C^D~E&F");
  if !streq(t0, "") { ok = false; }
  if !streq(t1, "") { ok = false; }
  if !streq(t2, "") { ok = false; }
  if !streq(t3, "") { ok = false; }
  let w2 = hl7_write(&b2);
  if !streq(w2, "MSH|^~\\&|S\rPID|A\\F\\B\\E\\C^D~E&F\r") { ok = false; }
  let m2 = parse_msg(w2);
  if hl7_seg_field_count(&m2, 1) != 1 { ok = false; }
  if hl7_rep_count(&m2, 1, 1) != 2 { ok = false; }
  if hl7_comp_count(&m2, 1, 1, 1) != 2 { ok = false; }
  if !opt_str_is(hl7_comp(&m2, 1, 1, 1, 1), "A\\F\\B\\E\\C") { ok = false; }
  if !opt_str_is(hl7_comp(&m2, 1, 1, 1, 2), "D") { ok = false; }
  if hl7_sub_count(&m2, 1, 1, 2, 1) != 2 { ok = false; }
  if !opt_str_is(hl7_sub(&m2, 1, 1, 2, 1, 2), "F") { ok = false; }
  return assert(ok, "builder escaping is data-safe or structure-preserving");
}

fn t19() -> TestResult {
  var b = hl7_builder_new();
  let no_seg = hl7_builder_field(&mut b, "X");
  let empty_name = hl7_builder_segment(&mut b, "");
  let first_not_msh = hl7_builder_segment(&mut b, "PID");
  var ok = streq(no_seg, "hl7: no open segment");
  if !streq(empty_name, "hl7: empty segment name") { ok = false; }
  if !streq(first_not_msh, "hl7: missing MSH segment") { ok = false; }
  let ok_msh = hl7_builder_segment(&mut b, "MSH");
  let dup_msh = hl7_builder_segment(&mut b, "MSH");
  let cr_field = hl7_builder_field(&mut b, "A\rB");
  let lf_field = hl7_builder_field(&mut b, "A\nB");
  if !streq(ok_msh, "") { ok = false; }
  if !streq(dup_msh, "hl7: malformed MSH segment: MSH must be the first segment") { ok = false; }
  if !streq(cr_field, "hl7: field contains a line terminator") { ok = false; }
  if !streq(lf_field, "hl7: field contains a line terminator") { ok = false; }
  return assert(ok, "builder rejects invalid state with deterministic messages");
}

fn t20() -> TestResult {
  var ok = streq(builder_err("||", "^~\\&"), "hl7: invalid separator");
  if !streq(builder_err("a", "^~\\&"), "hl7: invalid separator") { ok = false; }
  if !streq(builder_err("|", "abc"), "hl7: malformed MSH segment: expected 4 encoding characters, got 3") { ok = false; }
  if !streq(builder_err("|", "^~|&"), "hl7: invalid separator") { ok = false; }
  if !streq(builder_err("|", "^~^&"), "hl7: invalid separator") { ok = false; }
  if !streq(builder_err("*", "%~\\$"), "") { ok = false; }
  return assert(ok, "builder_with_separators validates every separator");
}

fn t21() -> TestResult {
  let text = "MSH|^~\\&|A\rPID|Müller^José\r";
  let m = parse_msg(text);
  var ok = hl7_seg_count(&m) == 2;
  if !opt_str_is(hl7_comp(&m, 1, 1, 1, 1), "Müller") { ok = false; }
  if !opt_str_is(hl7_comp(&m, 1, 1, 1, 2), "José") { ok = false; }
  if !streq(hl7_write(&m), text) { ok = false; }
  return assert(ok, "UTF-8 field bytes pass through byte-exact");
}

fn t22() -> TestResult {
  let m1 = parse_msg(M1);
  let w1 = hl7_write(&m1);
  let m2 = parse_msg(w1);
  var ok = streq(w1, M1);
  if hl7_seg_count(&m2) != hl7_seg_count(&m1) { ok = false; }
  var i = 0;
  while i < hl7_seg_count(&m1) {
    if !opt_eq(hl7_seg_name(&m1, i), hl7_seg_name(&m2, i)) { ok = false; }
    if hl7_seg_field_count(&m1, i) != hl7_seg_field_count(&m2, i) { ok = false; }
    var f = 1;
    while f <= hl7_seg_field_count(&m1, i) {
      if !opt_eq(hl7_field(&m1, i, f), hl7_field(&m2, i, f)) { ok = false; }
      f = f + 1;
    }
    i = i + 1;
  }
  if hl7_rep_count(&m2, 1, 3) != 2 { ok = false; }
  if !opt_str_is(hl7_rep(&m2, 1, 3, 2), "789012^^^SSN") { ok = false; }
  if hl7_comp_count(&m2, 1, 3, 2) != 4 { ok = false; }
  if !opt_str_is(hl7_comp(&m2, 1, 3, 2, 1), "789012") { ok = false; }
  if !opt_str_is(hl7_comp(&m2, 1, 3, 2, 4), "SSN") { ok = false; }
  if hl7_sub_count(&m1, 2, 3, 1, 1) != 1 { ok = false; }
  return assert(ok, "parse -> write -> parse preserves every level byte-exact");
}

fn t23() -> TestResult {
  let r = hl7_builder_with_separators("*", "%~\\$");
  var b = hl7_builder_new();
  var got = false;
  match r {
    Ok(b0) => {
      b = b0;
      got = true;
    },
    Err(_) => {},
  }
  if !got {
    return assert(false, "custom-separator builder round-trips");
  }
  let s0 = hl7_builder_segment(&mut b, "MSH");
  let f0 = hl7_builder_field(&mut b, "APP");
  let s1 = hl7_builder_segment(&mut b, "PID");
  let f1 = hl7_builder_field_structured(&mut b, "DOE%JOHN");
  var ok = streq(s0, "");
  if !streq(f0, "") { ok = false; }
  if !streq(s1, "") { ok = false; }
  if !streq(f1, "") { ok = false; }
  let w = hl7_write(&b);
  if !streq(w, "MSH*%~\\$*APP\rPID*DOE%JOHN\r") { ok = false; }
  let m = parse_msg(w);
  if !streq(hl7_field_sep(&m), "*") { ok = false; }
  if hl7_comp_count(&m, 1, 1, 1) != 2 { ok = false; }
  if !opt_str_is(hl7_comp(&m, 1, 1, 1, 2), "JOHN") { ok = false; }
  return assert(ok, "custom-separator builder round-trips");
}

fn main() -> Int {
  io.println("=== xiom.hl7 conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.hl7: all tests passed");
  } else {
    io.println("xiom.hl7: tests failed");
  }
  return failed;
}
