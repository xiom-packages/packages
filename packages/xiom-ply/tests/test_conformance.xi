// XIOM -- xiom.ply conformance tests (25 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map (see SPEC.md section 8): happy-path header/body parsing,
// token preservation, integer conversion, every declared scalar type and its
// boundaries, round-trip re-emission, CRLF and whitespace normalization,
// comments, zero-count and multi-element documents, the full error catalog
// (missing magic, unsupported format, unknown property type, malformed
// element/property/header record, missing end_header, element count
// mismatch, row token-count mismatch, malformed value, bad integer range,
// trailing rows) and accessor defaults.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// comparison below is routed through streq/err_is/val_is/build_is.

module ply_tests
use xiom.io; use xiom.test; use xiom.ply;
use xiom.string.compare;

// --------------------------------------------------
//  Fixtures
// --------------------------------------------------

// Canonical vertex+face document: LF endings, single spaces, final LF.
const F_FULL: Str = "ply\nformat ascii 1.0\ncomment made by xiom\ncomment\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty uchar vertex_count\nproperty int vertex_index_0\nproperty int vertex_index_1\nproperty int vertex_index_2\nend_header\n0 0 0\n1.5 -2.25 3e2\n0.5 .5 5.\n3 0 1 2\n";
// The header block of F_FULL, up to and including end_header.
const F_HEADER: Str = "ply\nformat ascii 1.0\ncomment made by xiom\ncomment\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty uchar vertex_count\nproperty int vertex_index_0\nproperty int vertex_index_1\nproperty int vertex_index_2\nend_header\n";
// A minimal empty document (no elements, no rows).
const F_EMPTY: Str = "ply\nformat ascii 1.0\nend_header\n";

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when parsing fails with exactly `want`.
fn err_is(r: Result[PlyDoc, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when the stored token at (e, r, j) is exactly `want`.
fn val_is(doc: &PlyDoc, e: Int, r: Int, j: Int, want: Str) -> Bool {
  return streq(ply_row_value(doc, e, r, j), want);
}

// True when the integer value at (e, r, j) converts to exactly `want`.
fn int_is(doc: &PlyDoc, e: Int, r: Int, j: Int, want: Int) -> Bool {
  let v = ply_value_int(doc, e, r, j);
  match v {
    Ok(x) => { return x == want; },
    Err(_) => { return false; },
  }
  return false;
}

// True when the integer conversion at (e, r, j) fails with exactly `want`.
fn int_err_is(doc: &PlyDoc, e: Int, r: Int, j: Int, want: Str) -> Bool {
  let v = ply_value_int(doc, e, r, j);
  match v {
    Ok(_) => { return false; },
    Err(em) => { return streq(em, want); },
  }
  return false;
}

// Built document text, or "" when the build failed.
fn build_str(doc: &PlyDoc) -> Str {
  let r = ply_build(doc);
  match r {
    Ok(s) => { return s; },
    Err(_) => {},
  }
  return "";
}

// True when the canonical build equals `want`.
fn build_is(doc: &PlyDoc, want: Str) -> Bool {
  return streq(build_str(doc), want);
}

// One-element, one-property document: `element e 1` with `property <ty> v`.
fn one_doc(ty: Str, value: Str) -> Str {
  return "ply\nformat ascii 1.0\nelement e 1\nproperty " + ty + " v\nend_header\n" + value + "\n";
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let r = ply_parse(F_FULL);
  match r {
    Ok(m) => {
      var ok = ply_element_count(&m) == 2;
      if !streq(ply_element_name(&m, 0), "vertex") { ok = false; }
      if !streq(ply_element_name(&m, 1), "face") { ok = false; }
      if ply_element_rows(&m, 0) != 3 { ok = false; }
      if ply_element_rows(&m, 1) != 1 { ok = false; }
      if ply_element_property_count(&m, 0) != 3 { ok = false; }
      if ply_element_property_count(&m, 1) != 4 { ok = false; }
      if ply_element_property(&m, 0, 0) != 0 { ok = false; }
      if ply_element_property(&m, 1, 0) != 3 { ok = false; }
      if ply_element_property(&m, 1, 3) != 6 { ok = false; }
      if ply_element_property(&m, 1, 4) != -1 { ok = false; }
      if !streq(ply_property_name(&m, 1), "y") { ok = false; }
      if !streq(ply_property_name(&m, 6), "vertex_index_2") { ok = false; }
      if ply_property_type(&m, 1) != 7 { ok = false; }
      if ply_property_type(&m, 3) != 2 { ok = false; }
      if ply_property_type(&m, 6) != 5 { ok = false; }
      if ply_property_element(&m, 0) != 0 { ok = false; }
      if ply_property_element(&m, 3) != 1 { ok = false; }
      if ply_property_index(&m, 0, "z") != 2 { ok = false; }
      if ply_property_index(&m, 1, "vertex_index_2") != 6 { ok = false; }
      if ply_property_index(&m, 0, "nope") != -1 { ok = false; }
      if ply_token_count(&m) != 13 { ok = false; }
      if ply_comment_count(&m) != 2 { ok = false; }
      if !streq(ply_comment(&m, 0), "made by xiom") { ok = false; }
      if !streq(ply_comment(&m, 1), "") { ok = false; }
      return assert(ok, "header: elements, properties, comments and lookups");
    },
    Err(_) => {
      return assert(false, "header: elements, properties, comments and lookups");
    },
  }
  return assert(false, "unreachable");
}

fn t2() -> TestResult {
  let r = ply_parse(F_FULL);
  match r {
    Ok(m) => {
      var ok = val_is(&m, 0, 0, 0, "0");
      if !val_is(&m, 0, 1, 0, "1.5") { ok = false; }
      if !val_is(&m, 0, 1, 1, "-2.25") { ok = false; }
      if !val_is(&m, 0, 1, 2, "3e2") { ok = false; }
      if !val_is(&m, 0, 2, 1, ".5") { ok = false; }
      if !val_is(&m, 0, 2, 2, "5.") { ok = false; }
      if !val_is(&m, 1, 0, 0, "3") { ok = false; }
      if !val_is(&m, 1, 0, 3, "2") { ok = false; }
      if !streq(ply_row_value(&m, 0, 3, 0), "") { ok = false; }
      if !streq(ply_row_value(&m, 0, 0, 3), "") { ok = false; }
      if !streq(ply_row_value(&m, -1, 0, 0), "") { ok = false; }
      if !int_is(&m, 1, 0, 1, 0) { ok = false; }
      if !int_is(&m, 1, 0, 3, 2) { ok = false; }
      if !int_err_is(&m, 0, 0, 0, "ply: value is not an integer") { ok = false; }
      if !int_err_is(&m, 1, 0, 9, "ply: property out of range") { ok = false; }
      if !int_err_is(&m, 1, 5, 0, "ply: value out of range") { ok = false; }
      return assert(ok, "body: tokens preserved verbatim; integers convert");
    },
    Err(_) => {
      return assert(false, "body: tokens preserved verbatim; integers convert");
    },
  }
  return assert(false, "unreachable");
}

fn t3() -> TestResult {
  let r = ply_parse(F_FULL);
  match r {
    Ok(m) => {
      var ok = streq(ply_build_header(&m), F_HEADER);
      if !build_is(&m, F_FULL) { ok = false; }
      let r2 = ply_parse(build_str(&m));
      match r2 {
        Ok(m2) => {
          if ply_token_count(&m2) != 13 { ok = false; }
          if !streq(ply_comment(&m2, 0), "made by xiom") { ok = false; }
          if !val_is(&m2, 0, 1, 1, "-2.25") { ok = false; }
          if !build_is(&m2, F_FULL) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
      return assert(ok, "round-trip: header and document rebuild byte-exact");
    },
    Err(_) => {
      return assert(false, "round-trip: header and document rebuild byte-exact");
    },
  }
  return assert(false, "unreachable");
}

fn t4() -> TestResult {
  let text = "ply\r\nformat ascii 1.0\r\nelement vertex 1\r\nproperty int a\r\nend_header\r\n7\r\n";
  let want = "ply\nformat ascii 1.0\nelement vertex 1\nproperty int a\nend_header\n7\n";
  let r = ply_parse(text);
  match r {
    Ok(m) => {
      var ok = val_is(&m, 0, 0, 0, "7");
      if !int_is(&m, 0, 0, 0, 7) { ok = false; }
      if !build_is(&m, want) { ok = false; }
      return assert(ok, "CRLF is accepted and canonicalized to LF");
    },
    Err(_) => {
      return assert(false, "CRLF is accepted and canonicalized to LF");
    },
  }
  return assert(false, "unreachable");
}

fn t5() -> TestResult {
  let text = "ply\nformat   ascii\t1.0\nelement\tvertex 1\nproperty   int\ta\nend_header\n  42  \n";
  let want = "ply\nformat ascii 1.0\nelement vertex 1\nproperty int a\nend_header\n42\n";
  let r = ply_parse(text);
  match r {
    Ok(m) => {
      var ok = val_is(&m, 0, 0, 0, "42");
      if !build_is(&m, want) { ok = false; }
      return assert(ok, "extra spaces and TABs are accepted and canonicalized");
    },
    Err(_) => {
      return assert(false, "extra spaces and TABs are accepted and canonicalized");
    },
  }
  return assert(false, "unreachable");
}

fn t6() -> TestResult {
  var ok = err_is(ply_parse(""), "ply: missing magic");
  if !err_is(ply_parse("nope\nformat ascii 1.0\nend_header\n"), "ply: missing magic") { ok = false; }
  if !err_is(ply_parse("PLY\nformat ascii 1.0\nend_header\n"), "ply: missing magic") { ok = false; }
  if !err_is(ply_parse("ply extra\nformat ascii 1.0\nend_header\n"), "ply: missing magic") { ok = false; }
  if !err_is(ply_parse("\nply\nformat ascii 1.0\nend_header\n"), "ply: missing magic") { ok = false; }
  if !err_is(ply_parse("plyx\nformat ascii 1.0\nend_header\n"), "ply: missing magic") { ok = false; }
  return assert(ok, "missing magic is rejected");
}

fn t7() -> TestResult {
  var ok = err_is(ply_parse("ply\n"), "ply: unsupported format line");
  if !err_is(ply_parse("ply\nformat ascii 1.1\nend_header\n"), "ply: unsupported format line") { ok = false; }
  if !err_is(ply_parse("ply\nformat binary_little_endian 1.0\nend_header\n"), "ply: unsupported format line") { ok = false; }
  if !err_is(ply_parse("ply\nformat ascii\nend_header\n"), "ply: unsupported format line") { ok = false; }
  if !err_is(ply_parse("ply\nformat ascii 1.0 x\nend_header\n"), "ply: unsupported format line") { ok = false; }
  if !err_is(ply_parse("ply\ncomment c\nend_header\n"), "ply: unsupported format line") { ok = false; }
  return assert(ok, "only `format ascii 1.0` is accepted");
}

fn t8() -> TestResult {
  let a = "ply\nformat ascii 1.0\nelement vertex 1\nproperty list uchar int vertex_indices\nend_header\n";
  var ok = err_is(ply_parse(a), "ply: unknown property type at line 4");
  let b = "ply\nformat ascii 1.0\nelement vertex 1\nproperty int64 x\nend_header\n";
  if !err_is(ply_parse(b), "ply: unknown property type at line 4") { ok = false; }
  let c = "ply\nformat ascii 1.0\nelement vertex 1\nproperty Int x\nend_header\n";
  if !err_is(ply_parse(c), "ply: unknown property type at line 4") { ok = false; }
  let d = "ply\nformat ascii 1.0\nelement vertex 1\nproperty uint8 x\nend_header\n";
  if !err_is(ply_parse(d), "ply: unknown property type at line 4") { ok = false; }
  let e = "ply\nformat ascii 1.0\nelement vertex 1\nproperty float x\nproperty string s\nend_header\n";
  if !err_is(ply_parse(e), "ply: unknown property type at line 5") { ok = false; }
  return assert(ok, "unknown property types (including list) are rejected");
}

fn t9() -> TestResult {
  let a = "ply\nformat ascii 1.0\nelement vertex\nend_header\n";
  var ok = err_is(ply_parse(a), "ply: malformed element at line 3");
  let b = "ply\nformat ascii 1.0\nelement vertex -1\nend_header\n";
  if !err_is(ply_parse(b), "ply: malformed element at line 3") { ok = false; }
  let c = "ply\nformat ascii 1.0\nelement vertex 1.5\nend_header\n";
  if !err_is(ply_parse(c), "ply: malformed element at line 3") { ok = false; }
  let d = "ply\nformat ascii 1.0\nelement vertex x\nend_header\n";
  if !err_is(ply_parse(d), "ply: malformed element at line 3") { ok = false; }
  let e = "ply\nformat ascii 1.0\nelement vertex +1\nend_header\n";
  if !err_is(ply_parse(e), "ply: malformed element at line 3") { ok = false; }
  let f = "ply\nformat ascii 1.0\nelement vertex 0x2\nend_header\n";
  if !err_is(ply_parse(f), "ply: malformed element at line 3") { ok = false; }
  return assert(ok, "malformed element declarations are rejected");
}

fn t10() -> TestResult {
  let a = "ply\nformat ascii 1.0\nproperty int x\nend_header\n";
  var ok = err_is(ply_parse(a), "ply: malformed property at line 3");
  let b = "ply\nformat ascii 1.0\nelement vertex 1\nproperty int\nend_header\n";
  if !err_is(ply_parse(b), "ply: malformed property at line 4") { ok = false; }
  let c = "ply\nformat ascii 1.0\nelement vertex 1\nproperty int x y\nend_header\n";
  if !err_is(ply_parse(c), "ply: malformed property at line 4") { ok = false; }
  let d = "ply\nformat ascii 1.0\nelement vertex 1\nproperty\nend_header\n";
  if !err_is(ply_parse(d), "ply: malformed property at line 4") { ok = false; }
  return assert(ok, "malformed property lines are rejected");
}

fn t11() -> TestResult {
  let a = "ply\nformat ascii 1.0\n\nend_header\n";
  var ok = err_is(ply_parse(a), "ply: unknown header record at line 3");
  let b = "ply\nformat ascii 1.0\nwhatever 1\nend_header\n";
  if !err_is(ply_parse(b), "ply: unknown header record at line 3") { ok = false; }
  let c = "ply\nformat ascii 1.0\nelementx 1\nend_header\n";
  if !err_is(ply_parse(c), "ply: unknown header record at line 3") { ok = false; }
  let d = "ply\nformat ascii 1.0\nelement vertex 0\nend_header extra\n";
  if !err_is(ply_parse(d), "ply: unknown header record at line 4") { ok = false; }
  let e = "ply\nformat ascii 1.0\nelement vertex 0\nply\n";
  if !err_is(ply_parse(e), "ply: unknown header record at line 4") { ok = false; }
  return assert(ok, "unknown and malformed header records are rejected");
}

fn t12() -> TestResult {
  var ok = err_is(ply_parse("ply\nformat ascii 1.0\n"), "ply: missing end_header");
  if !err_is(ply_parse("ply\nformat ascii 1.0\nelement vertex 0\n"), "ply: missing end_header") { ok = false; }
  if !err_is(ply_parse("ply\nformat ascii 1.0\nelement vertex 0"), "ply: missing end_header") { ok = false; }
  if !err_is(ply_parse("ply\nformat ascii 1.0\ncomment c"), "ply: missing end_header") { ok = false; }
  return assert(ok, "a header without end_header is rejected");
}

fn t13() -> TestResult {
  let a = "ply\nformat ascii 1.0\nelement vertex 2\nproperty int a\nend_header\n1\n";
  var ok = err_is(ply_parse(a), "ply: element count mismatch");
  let b = "ply\nformat ascii 1.0\nelement vertex 1\nproperty int a\nelement face 1\nproperty int n\nend_header\n1\n";
  if !err_is(ply_parse(b), "ply: element count mismatch") { ok = false; }
  let c = "ply\nformat ascii 1.0\nelement vertex 1\nproperty int a\nend_header\n";
  if !err_is(ply_parse(c), "ply: element count mismatch") { ok = false; }
  return assert(ok, "fewer rows than declared are an element count mismatch");
}

fn t14() -> TestResult {
  let a = "ply\nformat ascii 1.0\nelement vertex 1\nproperty int a\nproperty int b\nend_header\n1\n";
  var ok = err_is(ply_parse(a), "ply: row token-count mismatch at line 7");
  let b = "ply\nformat ascii 1.0\nelement vertex 1\nproperty int a\nproperty int b\nend_header\n1 2 3\n";
  if !err_is(ply_parse(b), "ply: row token-count mismatch at line 7") { ok = false; }
  let c = "ply\nformat ascii 1.0\nelement vertex 2\nproperty int a\nend_header\n1\n1 2\n";
  if !err_is(ply_parse(c), "ply: row token-count mismatch at line 7") { ok = false; }
  return assert(ok, "rows must carry exactly one token per property");
}

fn t15() -> TestResult {
  var ok = err_is(ply_parse(one_doc("uchar", "256")), "ply: bad integer range at line 6");
  if !err_is(ply_parse(one_doc("uchar", "-1")), "ply: bad integer range at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("char", "128")), "ply: bad integer range at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("char", "-129")), "ply: bad integer range at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("short", "32768")), "ply: bad integer range at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("short", "-32769")), "ply: bad integer range at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("ushort", "65536")), "ply: bad integer range at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("int", "2147483648")), "ply: bad integer range at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("int", "-2147483649")), "ply: bad integer range at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("uint", "4294967296")), "ply: bad integer range at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("uint", "-1")), "ply: bad integer range at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("uint", "99999999999999999999")), "ply: bad integer range at line 6") { ok = false; }
  return assert(ok, "integer tokens outside the declared type range are rejected");
}

fn t16() -> TestResult {
  let text = "ply\nformat ascii 1.0\nelement e 2\nproperty char a\nproperty uchar b\nproperty short c\nproperty ushort d\nproperty int f\nproperty uint g\nend_header\n-128 0 -32768 0 -2147483648 0\n127 255 32767 65535 2147483647 4294967295\n";
  let r = ply_parse(text);
  match r {
    Ok(m) => {
      var ok = int_is(&m, 0, 0, 0, -128);
      if !int_is(&m, 0, 0, 1, 0) { ok = false; }
      if !int_is(&m, 0, 0, 2, -32768) { ok = false; }
      if !int_is(&m, 0, 0, 3, 0) { ok = false; }
      if !int_is(&m, 0, 0, 4, -2147483648) { ok = false; }
      if !int_is(&m, 0, 0, 5, 0) { ok = false; }
      if !int_is(&m, 0, 1, 0, 127) { ok = false; }
      if !int_is(&m, 0, 1, 1, 255) { ok = false; }
      if !int_is(&m, 0, 1, 2, 32767) { ok = false; }
      if !int_is(&m, 0, 1, 3, 65535) { ok = false; }
      if !int_is(&m, 0, 1, 4, 2147483647) { ok = false; }
      if !int_is(&m, 0, 1, 5, 4294967295) { ok = false; }
      let r2 = ply_parse("ply\nformat ascii 1.0\nelement e 4\nproperty int a\nend_header\n+5\n-0\n007\n0000000000000000000005\n");
      match r2 {
        Ok(m2) => {
          if !int_is(&m2, 0, 0, 0, 5) { ok = false; }
          if !int_is(&m2, 0, 1, 0, 0) { ok = false; }
          if !int_is(&m2, 0, 2, 0, 7) { ok = false; }
          if !int_is(&m2, 0, 3, 0, 5) { ok = false; }
          if !val_is(&m2, 0, 1, 0, "-0") { ok = false; }
        },
        Err(_) => { ok = false; },
      }
      return assert(ok, "integer boundaries and sign/zero forms are accepted");
    },
    Err(_) => {
      return assert(false, "integer boundaries and sign/zero forms are accepted");
    },
  }
  return assert(false, "unreachable");
}

fn t17() -> TestResult {
  var ok = err_is(ply_parse(one_doc("int", "1.5")), "ply: malformed value at line 6");
  if !err_is(ply_parse(one_doc("int", "abc")), "ply: malformed value at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("int", "+-1")), "ply: malformed value at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("int", "1x")), "ply: malformed value at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("int", "-")), "ply: malformed value at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("uint", "1.0")), "ply: malformed value at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("float", "nan")), "ply: malformed value at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("float", "inf")), "ply: malformed value at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("float", "1e")), "ply: malformed value at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("float", "1.2.3")), "ply: malformed value at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("float", ".")), "ply: malformed value at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("float", "0x10")), "ply: malformed value at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("double", "1e+")), "ply: malformed value at line 6") { ok = false; }
  if !err_is(ply_parse(one_doc("double", "--1")), "ply: malformed value at line 6") { ok = false; }
  return assert(ok, "tokens outside the number grammar are malformed values");
}

fn t18() -> TestResult {
  let text = "ply\nformat ascii 1.0\nelement e 8\nproperty double v\nend_header\n1\n-0.5\n.5\n5.\n1e3\n+1.5E-2\n-0\n1E-10\n";
  let r = ply_parse(text);
  match r {
    Ok(m) => {
      var ok = ply_token_count(&m) == 8;
      if !val_is(&m, 0, 0, 0, "1") { ok = false; }
      if !val_is(&m, 0, 1, 0, "-0.5") { ok = false; }
      if !val_is(&m, 0, 2, 0, ".5") { ok = false; }
      if !val_is(&m, 0, 3, 0, "5.") { ok = false; }
      if !val_is(&m, 0, 4, 0, "1e3") { ok = false; }
      if !val_is(&m, 0, 5, 0, "+1.5E-2") { ok = false; }
      if !val_is(&m, 0, 6, 0, "-0") { ok = false; }
      if !val_is(&m, 0, 7, 0, "1E-10") { ok = false; }
      if !int_err_is(&m, 0, 0, 0, "ply: value is not an integer") { ok = false; }
      if !build_is(&m, text) { ok = false; }
      return assert(ok, "float and double tokens are syntax-checked and kept verbatim");
    },
    Err(_) => {
      return assert(false, "float and double tokens are syntax-checked and kept verbatim");
    },
  }
  return assert(false, "unreachable");
}

fn t19() -> TestResult {
  let a = "ply\nformat ascii 1.0\nelement vertex 1\nproperty int a\nend_header\n1\n2\n";
  var ok = err_is(ply_parse(a), "ply: trailing rows at line 7");
  let b = "ply\nformat ascii 1.0\nelement vertex 1\nproperty int a\nend_header\n1\n\n";
  if !err_is(ply_parse(b), "ply: trailing rows at line 7") { ok = false; }
  let c = "ply\nformat ascii 1.0\nelement vertex 1\nproperty int a\nend_header\n1\njunk\n";
  if !err_is(ply_parse(c), "ply: trailing rows at line 7") { ok = false; }
  return assert(ok, "lines after the declared rows are trailing rows");
}

fn t20() -> TestResult {
  let r = ply_parse(F_EMPTY);
  match r {
    Ok(m) => {
      var ok = ply_element_count(&m) == 0;
      if ply_element_rows(&m, 0) != 0 { ok = false; }
      if !streq(ply_element_name(&m, 0), "") { ok = false; }
      if !streq(ply_element_name(&m, -1), "") { ok = false; }
      if ply_element_property_count(&m, 0) != 0 { ok = false; }
      if ply_element_property(&m, 0, 0) != -1 { ok = false; }
      if !streq(ply_property_name(&m, 0), "") { ok = false; }
      if ply_property_type(&m, 0) != 0 { ok = false; }
      if ply_property_element(&m, 0) != -1 { ok = false; }
      if ply_property_index(&m, 0, "x") != -1 { ok = false; }
      if !streq(ply_row_value(&m, 0, 0, 0), "") { ok = false; }
      if !streq(ply_comment(&m, 0), "") { ok = false; }
      if ply_comment_count(&m) != 0 { ok = false; }
      if ply_token_count(&m) != 0 { ok = false; }
      if !build_is(&m, F_EMPTY) { ok = false; }
      return assert(ok, "empty document and accessor defaults");
    },
    Err(_) => {
      return assert(false, "empty document and accessor defaults");
    },
  }
  return assert(false, "unreachable");
}

fn t21() -> TestResult {
  let text = "ply\nformat ascii 1.0\nelement vertex 2\nproperty int a\nelement camera 0\nproperty double fov\nelement face 1\nproperty int n\nend_header\n1\n2\n5\n";
  let r = ply_parse(text);
  match r {
    Ok(m) => {
      var ok = ply_element_count(&m) == 3;
      if ply_element_rows(&m, 0) != 2 { ok = false; }
      if ply_element_rows(&m, 1) != 0 { ok = false; }
      if ply_element_rows(&m, 2) != 1 { ok = false; }
      if ply_token_count(&m) != 3 { ok = false; }
      if ply_property_index(&m, 1, "fov") != 1 { ok = false; }
      if ply_property_element(&m, 2) != 2 { ok = false; }
      if !val_is(&m, 2, 0, 0, "5") { ok = false; }
      if !int_is(&m, 0, 1, 0, 2) { ok = false; }
      if !build_is(&m, text) { ok = false; }
      return assert(ok, "zero-count elements consume no rows and keep property order");
    },
    Err(_) => {
      return assert(false, "zero-count elements consume no rows and keep property order");
    },
  }
  return assert(false, "unreachable");
}

fn t22() -> TestResult {
  var ok = streq(ply_type_name(1), "char");
  if !streq(ply_type_name(2), "uchar") { ok = false; }
  if !streq(ply_type_name(3), "short") { ok = false; }
  if !streq(ply_type_name(4), "ushort") { ok = false; }
  if !streq(ply_type_name(5), "int") { ok = false; }
  if !streq(ply_type_name(6), "uint") { ok = false; }
  if !streq(ply_type_name(7), "float") { ok = false; }
  if !streq(ply_type_name(8), "double") { ok = false; }
  if !streq(ply_type_name(0), "") { ok = false; }
  if !streq(ply_type_name(9), "") { ok = false; }
  if ply_type_code("char") != 1 { ok = false; }
  if ply_type_code("uchar") != 2 { ok = false; }
  if ply_type_code("short") != 3 { ok = false; }
  if ply_type_code("ushort") != 4 { ok = false; }
  if ply_type_code("int") != 5 { ok = false; }
  if ply_type_code("uint") != 6 { ok = false; }
  if ply_type_code("float") != 7 { ok = false; }
  if ply_type_code("double") != 8 { ok = false; }
  if ply_type_code("Char") != 0 { ok = false; }
  if ply_type_code("") != 0 { ok = false; }
  if ply_type_code("list") != 0 { ok = false; }
  if !ply_type_is_integer(1) { ok = false; }
  if !ply_type_is_integer(6) { ok = false; }
  if ply_type_is_integer(7) { ok = false; }
  if ply_type_is_integer(8) { ok = false; }
  if ply_type_is_integer(0) { ok = false; }
  if ply_type_is_integer(9) { ok = false; }
  return assert(ok, "type name/code table and integer classification");
}

fn t23() -> TestResult {
  let text = "ply\nformat ascii 1.0\nelement vertex 1\ncomment after element\nproperty int a\nend_header\n1\n";
  let want = "ply\nformat ascii 1.0\ncomment after element\nelement vertex 1\nproperty int a\nend_header\n1\n";
  let r = ply_parse(text);
  match r {
    Ok(m) => {
      var ok = ply_comment_count(&m) == 1;
      if !streq(ply_comment(&m, 0), "after element") { ok = false; }
      if !streq(ply_build_header(&m), "ply\nformat ascii 1.0\ncomment after element\nelement vertex 1\nproperty int a\nend_header\n") { ok = false; }
      if !build_is(&m, want) { ok = false; }
      return assert(ok, "comments are accepted anywhere and re-emitted after format");
    },
    Err(_) => {
      return assert(false, "comments are accepted anywhere and re-emitted after format");
    },
  }
  return assert(false, "unreachable");
}

fn t24() -> TestResult {
  let a = "ply\nformat ascii 1.0\ncomment c\nelement vertex 1\nproperty int a\nend_header\n1 2\n";
  var ok = err_is(ply_parse(a), "ply: row token-count mismatch at line 7");
  let b = "ply\nformat ascii 1.0\ncomment c\ncomment d\nelement vertex 1\nproperty uchar a\nend_header\n300\n";
  if !err_is(ply_parse(b), "ply: bad integer range at line 8") { ok = false; }
  let c = "ply\nformat ascii 1.0\ncomment c\nelement vertex 1\nproperty list uchar int idx\nend_header\n";
  if !err_is(ply_parse(c), "ply: unknown property type at line 5") { ok = false; }
  return assert(ok, "error line numbers count every physical header line");
}

fn t25() -> TestResult {
  var bad = PlyDoc{
    elem_names: Vec[Str].new();
    elem_counts: Vec[Int].new();
    elem_prop_starts: Vec[Int].new();
    elem_prop_ends: Vec[Int].new();
    prop_types: Vec[Int].new();
    prop_names: Vec[Str].new();
    comments: Vec[Str].new();
    tokens: Vec[Str].new();
  };
  bad.elem_names.push("e");
  bad.elem_counts.push(1);
  bad.elem_prop_starts.push(0);
  bad.elem_prop_ends.push(1);
  bad.prop_types.push(5);
  bad.prop_names.push("a");
  let r = ply_build(&bad);
  var ok = false;
  match r {
    Ok(_) => { ok = false; },
    Err(e) => { ok = streq(e, "ply: element count mismatch"); },
  }
  if !streq(ply_build_header(&bad), "ply\nformat ascii 1.0\nelement e 1\nproperty int a\nend_header\n") { ok = false; }
  return assert(ok, "build rejects an element/token mismatch");
}

fn main() -> Int {
  io.println("=== xiom.ply conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.ply: all tests passed");
  } else {
    io.println("xiom.ply: tests failed");
  }
  return failed;
}
