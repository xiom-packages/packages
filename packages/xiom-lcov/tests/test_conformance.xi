// XIOM -- xiom.lcov conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: prove the pure-XIOM xiom.lcov module against the
// documented LCOV tracefile subset, its error catalog and its canonical
// emitter.
//
// Coverage: the full record set (TN/SF/FN/FNDA/FNF/FNH/DA/LF/LH/BRDA/BRF/
// BRH/end_of_record), per-file ranges across multiple sections, optional DA
// checksums, the "-" branch sentinel, blank/CRLF tolerance, canonical record
// order, TN labeling, duplicate declared records, declared-vs-computed
// mismatch tolerance, numeric boundaries (0, 1000000000, leading zeros,
// overflow), every error catalog entry (unknown record, bad field count,
// empty field, non-numeric, negative, record outside source file, missing
// end_of_record), accessor bounds and full round trips.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// comparison below is routed through streq or a doc_equal helper.

module lcov_tests
use xiom.io; use xiom.test; use xiom.lcov;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when `text` fails to parse with exactly the message `want`.
fn err_is(text: Str, want: Str) -> Bool {
  let r = lcov_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// Structural equality of the FN records of file `f` in two documents.
fn fn_equal(a: &LcovDoc, b: &LcovDoc, f: Int) -> Bool {
  if lcov_fn_count(a, f) != lcov_fn_count(b, f) { return false; }
  var i = 0;
  while i < lcov_fn_count(a, f) {
    if lcov_fn_line(a, f, i) != lcov_fn_line(b, f, i) { return false; }
    if !streq(lcov_fn_name(a, f, i), lcov_fn_name(b, f, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// Structural equality of the FNDA records of file `f` in two documents.
fn fnda_equal(a: &LcovDoc, b: &LcovDoc, f: Int) -> Bool {
  if lcov_fnda_count(a, f) != lcov_fnda_count(b, f) { return false; }
  var i = 0;
  while i < lcov_fnda_count(a, f) {
    if lcov_fnda_hits(a, f, i) != lcov_fnda_hits(b, f, i) { return false; }
    if !streq(lcov_fnda_name(a, f, i), lcov_fnda_name(b, f, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// Structural equality of the DA records of file `f` in two documents.
fn da_equal(a: &LcovDoc, b: &LcovDoc, f: Int) -> Bool {
  if lcov_da_count(a, f) != lcov_da_count(b, f) { return false; }
  var i = 0;
  while i < lcov_da_count(a, f) {
    if lcov_da_line(a, f, i) != lcov_da_line(b, f, i) { return false; }
    if lcov_da_hits(a, f, i) != lcov_da_hits(b, f, i) { return false; }
    if lcov_da_has_checksum(a, f, i) != lcov_da_has_checksum(b, f, i) { return false; }
    if !streq(lcov_da_checksum(a, f, i), lcov_da_checksum(b, f, i)) { return false; }
    i = i + 1;
  }
  return true;
}

// Structural equality of the BRDA records of file `f` in two documents.
fn brda_equal(a: &LcovDoc, b: &LcovDoc, f: Int) -> Bool {
  if lcov_brda_count(a, f) != lcov_brda_count(b, f) { return false; }
  var i = 0;
  while i < lcov_brda_count(a, f) {
    if lcov_brda_line(a, f, i) != lcov_brda_line(b, f, i) { return false; }
    if !streq(lcov_brda_block(a, f, i), lcov_brda_block(b, f, i)) { return false; }
    if !streq(lcov_brda_branch(a, f, i), lcov_brda_branch(b, f, i)) { return false; }
    if lcov_brda_taken(a, f, i) != lcov_brda_taken(b, f, i) { return false; }
    i = i + 1;
  }
  return true;
}

// Structural equality of two parsed tracefiles.
fn doc_equal(a: &LcovDoc, b: &LcovDoc) -> Bool {
  if lcov_file_count(a) != lcov_file_count(b) { return false; }
  var f = 0;
  while f < lcov_file_count(a) {
    if !streq(lcov_file_source(a, f), lcov_file_source(b, f)) { return false; }
    if !streq(lcov_file_test_name(a, f), lcov_file_test_name(b, f)) { return false; }
    if lcov_declared_fnf(a, f) != lcov_declared_fnf(b, f) { return false; }
    if lcov_declared_fnh(a, f) != lcov_declared_fnh(b, f) { return false; }
    if lcov_declared_lf(a, f) != lcov_declared_lf(b, f) { return false; }
    if lcov_declared_lh(a, f) != lcov_declared_lh(b, f) { return false; }
    if lcov_declared_brf(a, f) != lcov_declared_brf(b, f) { return false; }
    if lcov_declared_brh(a, f) != lcov_declared_brh(b, f) { return false; }
    if !fn_equal(a, b, f) { return false; }
    if !fnda_equal(a, b, f) { return false; }
    if !da_equal(a, b, f) { return false; }
    if !brda_equal(a, b, f) { return false; }
    f = f + 1;
  }
  return true;
}

// parse -> emit -> parse is structure-preserving and emit is idempotent.
fn round_trip(text: Str) -> Bool {
  let r1 = lcov_parse(text);
  match r1 {
    Ok(d1) => {
      let once = lcov_emit(&d1);
      let r2 = lcov_parse(once);
      match r2 {
        Ok(d2) => {
          if !doc_equal(&d1, &d2) { return false; }
          let twice = lcov_emit(&d2);
          return streq(once, twice);
        },
        Err(_) => { return false; },
      }
    },
    Err(_) => { return false; },
  }
  return false;
}

// The complete happy-path tracefile reused by several checks.
fn full_text() -> Str {
  return "TN:unit\nSF:src/a.c\nFN:3,main\nFN:10,helper\nFNDA:2,main\nFNDA:0,helper\nFNF:2\nFNH:1\nDA:3,2\nDA:10,0\nDA:11,5,abc123\nLF:3\nLH:2\nBRDA:3,0,0,2\nBRDA:3,0,1,-\nBRDA:10,1,0,0\nBRF:3\nBRH:1\nend_of_record\n";
}

fn t1() -> TestResult {
  let r = lcov_parse(full_text());
  var ok = false;
  match r {
    Ok(d) => {
      ok = lcov_file_count(&d) == 1;
      if !streq(lcov_file_source(&d, 0), "src/a.c") { ok = false; }
      if !streq(lcov_file_test_name(&d, 0), "unit") { ok = false; }
      if lcov_fn_count(&d, 0) != 2 { ok = false; }
      if lcov_fn_line(&d, 0, 0) != 3 { ok = false; }
      if !streq(lcov_fn_name(&d, 0, 0), "main") { ok = false; }
      if lcov_fn_line(&d, 0, 1) != 10 { ok = false; }
      if !streq(lcov_fn_name(&d, 0, 1), "helper") { ok = false; }
      if lcov_fnda_count(&d, 0) != 2 { ok = false; }
      if lcov_fnda_hits(&d, 0, 0) != 2 { ok = false; }
      if !streq(lcov_fnda_name(&d, 0, 0), "main") { ok = false; }
      if lcov_fnda_hits(&d, 0, 1) != 0 { ok = false; }
      if lcov_da_count(&d, 0) != 3 { ok = false; }
      if lcov_da_line(&d, 0, 1) != 10 { ok = false; }
      if lcov_da_hits(&d, 0, 2) != 5 { ok = false; }
      if !lcov_da_has_checksum(&d, 0, 2) { ok = false; }
      if !streq(lcov_da_checksum(&d, 0, 2), "abc123") { ok = false; }
      if lcov_da_has_checksum(&d, 0, 1) { ok = false; }
      if !streq(lcov_da_checksum(&d, 0, 1), "") { ok = false; }
      if lcov_brda_count(&d, 0) != 3 { ok = false; }
      if lcov_brda_taken(&d, 0, 0) != 2 { ok = false; }
      if lcov_brda_taken(&d, 0, 1) != -1 { ok = false; }
      if lcov_brda_taken(&d, 0, 2) != 0 { ok = false; }
      if lcov_declared_fnf(&d, 0) != 2 { ok = false; }
      if lcov_declared_fnh(&d, 0) != 1 { ok = false; }
      if lcov_declared_lf(&d, 0) != 3 { ok = false; }
      if lcov_declared_lh(&d, 0) != 2 { ok = false; }
      if lcov_declared_brf(&d, 0) != 3 { ok = false; }
      if lcov_declared_brh(&d, 0) != 1 { ok = false; }
      if lcov_computed_fnf(&d, 0) != 2 { ok = false; }
      if lcov_computed_fnh(&d, 0) != 1 { ok = false; }
      if lcov_computed_lf(&d, 0) != 3 { ok = false; }
      if lcov_computed_lh(&d, 0) != 2 { ok = false; }
      if lcov_computed_brf(&d, 0) != 3 { ok = false; }
      if lcov_computed_brh(&d, 0) != 1 { ok = false; }
      if lcov_fnf_mismatch(&d, 0) { ok = false; }
      if lcov_fnh_mismatch(&d, 0) { ok = false; }
      if lcov_lf_mismatch(&d, 0) { ok = false; }
      if lcov_lh_mismatch(&d, 0) { ok = false; }
      if lcov_brf_mismatch(&d, 0) { ok = false; }
      if lcov_brh_mismatch(&d, 0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "every record kind parses with aligned accessors and computed summaries");
}

fn t2() -> TestResult {
  let r = lcov_parse("TN:a\nSF:one.c\nDA:1,1\nend_of_record\nTN:b\nSF:two.c\nDA:2,0\nDA:3,4\nend_of_record\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = lcov_file_count(&d) == 2;
      if !streq(lcov_file_source(&d, 0), "one.c") { ok = false; }
      if !streq(lcov_file_test_name(&d, 0), "a") { ok = false; }
      if lcov_da_count(&d, 0) != 1 { ok = false; }
      if lcov_da_count(&d, 1) != 2 { ok = false; }
      if !streq(lcov_file_source(&d, 1), "two.c") { ok = false; }
      if !streq(lcov_file_test_name(&d, 1), "b") { ok = false; }
      if lcov_da_line(&d, 1, 0) != 2 { ok = false; }
      if lcov_da_hits(&d, 1, 1) != 4 { ok = false; }
      if lcov_da_line(&d, 0, 1) != -1 { ok = false; }
      if lcov_fn_count(&d, 1) != 0 { ok = false; }
      if lcov_fnda_count(&d, 0) != 0 { ok = false; }
      if lcov_brda_count(&d, 1) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "per-file ranges index each section independently");
}

fn t3() -> TestResult {
  let r = lcov_parse("TN:merged\nSF:x.c\nDA:5,1\nFNF:1\nFN:5,f\nFNDA:1,f\nBRDA:5,0,0,-\nBRH:0\nend_of_record\n");
  var ok = false;
  match r {
    Ok(d) => {
      let wanted = "TN:merged\nSF:x.c\nFN:5,f\nFNDA:1,f\nFNF:1\nDA:5,1\nBRDA:5,0,0,-\nBRH:0\nend_of_record\n";
      ok = streq(lcov_emit(&d), wanted);
    },
    Err(_) => { ok = false; },
  }
  if !round_trip("TN:merged\nSF:x.c\nDA:5,1\nFNF:1\nFN:5,f\nFNDA:1,f\nBRDA:5,0,0,-\nBRH:0\nend_of_record\n") {
    ok = false;
  }
  return assert(ok, "emit writes the canonical record order regardless of input order");
}

fn t4() -> TestResult {
  let r = lcov_parse("\r\nTN:t\r\nSF:a.c\r\n\r\n   \r\nDA:1,1\r\n\t\r\nend_of_record\r\n\r\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = lcov_file_count(&d) == 1;
      if !streq(lcov_file_test_name(&d, 0), "t") { ok = false; }
      if lcov_da_count(&d, 0) != 1 { ok = false; }
      if !streq(lcov_emit(&d), "TN:t\nSF:a.c\nDA:1,1\nend_of_record\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CRLF and blank lines are tolerated and canonicalized");
}

fn t5() -> TestResult {
  let r = lcov_parse("TN:first\nSF:a\nend_of_record\nSF:b\nend_of_record\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = lcov_file_count(&d) == 2;
      if !streq(lcov_file_test_name(&d, 0), "first") { ok = false; }
      if !streq(lcov_file_test_name(&d, 1), "first") { ok = false; }
      let wanted = "TN:first\nSF:a\nend_of_record\nTN:first\nSF:b\nend_of_record\n";
      if !streq(lcov_emit(&d), wanted) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = lcov_parse("TN:\nSF:c\nend_of_record\n");
  var ok2 = false;
  match r2 {
    Ok(d) => {
      ok2 = streq(lcov_file_test_name(&d, 0), "");
      if !streq(lcov_emit(&d), "SF:c\nend_of_record\n") { ok2 = false; }
    },
    Err(_) => { ok2 = false; },
  }
  return assert(ok && ok2, "TN labels every following section; an empty TN is omitted");
}

fn t6() -> TestResult {
  let text = "SF:m.c\nDA:1,1\nDA:2,0\nFNF:9\nFNH:9\nLF:9\nLH:9\nBRDA:1,0,0,3\nBRF:9\nBRH:9\nend_of_record\n";
  let r = lcov_parse(text);
  var ok = false;
  match r {
    Ok(d) => {
      ok = lcov_declared_lf(&d, 0) == 9;
      if lcov_declared_lh(&d, 0) != 9 { ok = false; }
      if lcov_declared_fnf(&d, 0) != 9 { ok = false; }
      if lcov_declared_fnh(&d, 0) != 9 { ok = false; }
      if lcov_declared_brf(&d, 0) != 9 { ok = false; }
      if lcov_declared_brh(&d, 0) != 9 { ok = false; }
      if lcov_computed_fnf(&d, 0) != 0 { ok = false; }
      if lcov_computed_fnh(&d, 0) != 0 { ok = false; }
      if lcov_computed_lf(&d, 0) != 2 { ok = false; }
      if lcov_computed_lh(&d, 0) != 1 { ok = false; }
      if lcov_computed_brf(&d, 0) != 1 { ok = false; }
      if lcov_computed_brh(&d, 0) != 1 { ok = false; }
      if !lcov_fnf_mismatch(&d, 0) { ok = false; }
      if !lcov_fnh_mismatch(&d, 0) { ok = false; }
      if !lcov_lf_mismatch(&d, 0) { ok = false; }
      if !lcov_lh_mismatch(&d, 0) { ok = false; }
      if !lcov_brf_mismatch(&d, 0) { ok = false; }
      if !lcov_brh_mismatch(&d, 0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !round_trip(text) { ok = false; }
  return assert(ok, "declared/computed mismatches parse, stay exposed and round-trip");
}

fn t7() -> TestResult {
  let r = lcov_parse("TN:x\nTN:y\nSF:d.c\nDA:1,1\nDA:2,1\nDA:3,0\nLF:1\nLF:3\nend_of_record\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = streq(lcov_file_test_name(&d, 0), "y");
      if lcov_declared_lf(&d, 0) != 3 { ok = false; }
      if lcov_computed_lf(&d, 0) != 3 { ok = false; }
      if lcov_lf_mismatch(&d, 0) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a duplicate TN or declared record overwrites the previous value");
}

fn t8() -> TestResult {
  let r = lcov_parse("SF:b.c\nBRDA:4,0,0,-\nBRDA:4,0,1,0\nBRDA:4,1,0,17\nBRF:3\nBRH:1\nend_of_record\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = lcov_brda_taken(&d, 0, 0) == -1;
      if lcov_brda_taken(&d, 0, 1) != 0 { ok = false; }
      if lcov_brda_taken(&d, 0, 2) != 17 { ok = false; }
      if !streq(lcov_brda_block(&d, 0, 2), "1") { ok = false; }
      if !streq(lcov_brda_branch(&d, 0, 2), "0") { ok = false; }
      if lcov_computed_brh(&d, 0) != 1 { ok = false; }
      if lcov_brh_mismatch(&d, 0) { ok = false; }
      let wanted = "SF:b.c\nBRDA:4,0,0,-\nBRDA:4,0,1,0\nBRDA:4,1,0,17\nBRF:3\nBRH:1\nend_of_record\n";
      if !streq(lcov_emit(&d), wanted) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "the branch taken field keeps '-', 0 and positive counts distinct");
}

fn t9() -> TestResult {
  let r = lcov_parse("SF:n.c\nDA:1000000000,1000000000\nLH:1\nend_of_record\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = lcov_da_line(&d, 0, 0) == 1000000000;
      if lcov_da_hits(&d, 0, 0) != 1000000000 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = lcov_parse("SF:z.c\nDA:007,01\nend_of_record\n");
  var ok2 = false;
  match r2 {
    Ok(d) => {
      ok2 = lcov_da_line(&d, 0, 0) == 7;
      if lcov_da_hits(&d, 0, 0) != 1 { ok2 = false; }
      if !streq(lcov_emit(&d), "SF:z.c\nDA:7,1\nend_of_record\n") { ok2 = false; }
    },
    Err(_) => { ok2 = false; },
  }
  var ok3 = err_is("SF:n.c\nDA:1000000001,0\nend_of_record\n", "lcov: non-numeric field at 2");
  if !err_is("SF:n.c\nDA:0,99999999999999999999\nend_of_record\n", "lcov: non-numeric field at 2") { ok3 = false; }
  if !err_is("SF:n.c\nLF:1000000001\nend_of_record\n", "lcov: non-numeric field at 2") { ok3 = false; }
  if !err_is("SF:n.c\nLF:\nend_of_record\n", "lcov: non-numeric field at 2") { ok3 = false; }
  return assert(ok && ok2 && ok3, "numeric fields accept 0..1000000000, leading zeros, reject overflow");
}

fn t10() -> TestResult {
  var ok = err_is("SF:a\nFOO:1\nend_of_record\n", "lcov: unknown record at 2");
  if !err_is("SF:a\nDA 1,1\nend_of_record\n", "lcov: unknown record at 2") { ok = false; }
  if !err_is("SF:a\na plain text line\nend_of_record\n", "lcov: unknown record at 2") { ok = false; }
  if !err_is("HELLO\n", "lcov: unknown record at 1") { ok = false; }
  if !err_is("SF:a\nend_of_record\nZAP\n", "lcov: unknown record at 3") { ok = false; }
  return assert(ok, "lines that match no record prefix are unknown records");
}

fn t11() -> TestResult {
  var ok = err_is("SF:a\nFN:3\nend_of_record\n", "lcov: bad field count at 2");
  if !err_is("SF:a\nFN:1,a,b\nend_of_record\n", "lcov: bad field count at 2") { ok = false; }
  if !err_is("SF:a\nDA:3\nend_of_record\n", "lcov: bad field count at 2") { ok = false; }
  if !err_is("SF:a\nDA:1,2,3,4\nend_of_record\n", "lcov: bad field count at 2") { ok = false; }
  if !err_is("SF:a\nBRDA:1,0,0\nend_of_record\n", "lcov: bad field count at 2") { ok = false; }
  if !err_is("SF:a\nBRDA:1,0,0,1,2\nend_of_record\n", "lcov: bad field count at 2") { ok = false; }
  if !err_is("SF:a\nLF:1,2\nend_of_record\n", "lcov: bad field count at 2") { ok = false; }
  if !err_is("SF:a\nFNDA:1\nend_of_record\n", "lcov: bad field count at 2") { ok = false; }
  if !err_is("SF:a\nBRF:1,2\nend_of_record\n", "lcov: bad field count at 2") { ok = false; }
  return assert(ok, "wrong comma counts are bad field count errors");
}

fn t12() -> TestResult {
  var ok = err_is("SF:a\nDA:a,1\nend_of_record\n", "lcov: non-numeric field at 2");
  if !err_is("SF:a\nDA:1,b\nend_of_record\n", "lcov: non-numeric field at 2") { ok = false; }
  if !err_is("SF:a\nLF:x\nend_of_record\n", "lcov: non-numeric field at 2") { ok = false; }
  if !err_is("SF:a\nFNF:\nend_of_record\n", "lcov: non-numeric field at 2") { ok = false; }
  if !err_is("SF:a\nBRDA:1,0,0,x\nend_of_record\n", "lcov: non-numeric field at 2") { ok = false; }
  if !err_is("SF:a\nFNDA:c,f\nend_of_record\n", "lcov: non-numeric field at 2") { ok = false; }
  if !err_is("SF:a\nDA:1,1 \nend_of_record\n", "lcov: non-numeric field at 2") { ok = false; }
  return assert(ok, "non-digit bytes in a numeric field are non-numeric errors");
}

fn t13() -> TestResult {
  var ok = err_is("SF:a\nDA:-1,2\nend_of_record\n", "lcov: negative number at 2");
  if !err_is("SF:a\nFNDA:-3,f\nend_of_record\n", "lcov: negative number at 2") { ok = false; }
  if !err_is("SF:a\nBRDA:1,0,0,-4\nend_of_record\n", "lcov: negative number at 2") { ok = false; }
  if !err_is("SF:a\nLF:-1\nend_of_record\n", "lcov: negative number at 2") { ok = false; }
  if !err_is("SF:a\nDA:-,2\nend_of_record\n", "lcov: non-numeric field at 2") { ok = false; }
  return assert(ok, "negative numbers are rejected; '-' is only the branch sentinel");
}

fn t14() -> TestResult {
  var ok = err_is("DA:1,1\n", "lcov: record outside source file at 1");
  if !err_is("end_of_record\n", "lcov: record outside source file at 1") { ok = false; }
  if !err_is("SF:a\nend_of_record\nFNF:0\n", "lcov: record outside source file at 3") { ok = false; }
  if !err_is("SF:a\nend_of_record\nBRDA:1,0,0,-\n", "lcov: record outside source file at 3") { ok = false; }
  if !err_is("SF:a\nend_of_record\nFN:1,f\n", "lcov: record outside source file at 3") { ok = false; }
  if !err_is("TN:t\nLF:0\n", "lcov: record outside source file at 2") { ok = false; }
  return assert(ok, "file-scoped records outside an open SF section are rejected");
}

fn t15() -> TestResult {
  var ok = err_is("SF:a\nDA:1,1\n", "lcov: missing end_of_record at 1");
  if !err_is("\n\nSF:a\nDA:1,1\n", "lcov: missing end_of_record at 3") { ok = false; }
  if !err_is("SF:a\nDA:1,1\nSF:b\n", "lcov: missing end_of_record at 1") { ok = false; }
  if !err_is("TN:t\nSF:a\nFN:1,f\n", "lcov: missing end_of_record at 2") { ok = false; }
  let r = lcov_parse("SF:a\nend_of_record\n");
  var ok2 = false;
  match r {
    Ok(d) => { ok2 = lcov_file_count(&d) == 1; },
    Err(_) => { ok2 = false; },
  }
  return assert(ok && ok2, "an unclosed SF section is an error naming the SF line");
}

fn t16() -> TestResult {
  var ok = err_is("SF:\n", "lcov: empty field at 1");
  if !err_is("SF:a\nFN:1,\nend_of_record\n", "lcov: empty field at 2") { ok = false; }
  if !err_is("SF:a\nFNDA:1,\nend_of_record\n", "lcov: empty field at 2") { ok = false; }
  if !err_is("SF:a\nBRDA:1,,0,-\nend_of_record\n", "lcov: empty field at 2") { ok = false; }
  if !err_is("SF:a\nBRDA:1,0,,-\nend_of_record\n", "lcov: empty field at 2") { ok = false; }
  if !err_is("SF:a\nDA:1,2,\nend_of_record\n", "lcov: empty field at 2") { ok = false; }
  return assert(ok, "an empty required field is an empty field error");
}

fn t17() -> TestResult {
  let r = lcov_parse("");
  var ok = false;
  match r {
    Ok(d) => {
      ok = lcov_file_count(&d) == 0;
      if !streq(lcov_emit(&d), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = lcov_parse("\n \n\t\n\r\n");
  var ok2 = false;
  match r2 {
    Ok(d) => { ok2 = lcov_file_count(&d) == 0; },
    Err(_) => { ok2 = false; },
  }
  let r3 = lcov_parse("TN:x\n");
  var ok3 = false;
  match r3 {
    Ok(d) => { ok3 = lcov_file_count(&d) == 0; },
    Err(_) => { ok3 = false; },
  }
  return assert(ok && ok2 && ok3, "empty, blank-only and TN-only inputs parse to an empty doc");
}

fn t18() -> TestResult {
  let r = lcov_parse("SF:a\nFN:1,f\nFNDA:1,f\nDA:1,1\nBRDA:1,0,0,1\nend_of_record\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = lcov_file_count(&d) == 1;
      if !streq(lcov_file_source(&d, 1), "") { ok = false; }
      if !streq(lcov_file_source(&d, -1), "") { ok = false; }
      if !streq(lcov_file_test_name(&d, 9), "") { ok = false; }
      if lcov_declared_lf(&d, 0) != -1 { ok = false; }
      if lcov_declared_lf(&d, 9) != -1 { ok = false; }
      if lcov_computed_lf(&d, 9) != 0 { ok = false; }
      if lcov_fn_count(&d, -1) != 0 { ok = false; }
      if lcov_fn_count(&d, 9) != 0 { ok = false; }
      if lcov_fn_line(&d, 0, 0) != 1 { ok = false; }
      if lcov_fn_line(&d, 0, 1) != -1 { ok = false; }
      if !streq(lcov_fn_name(&d, 0, -1), "") { ok = false; }
      if lcov_fnda_hits(&d, 0, 9) != -1 { ok = false; }
      if !streq(lcov_fnda_name(&d, 0, 9), "") { ok = false; }
      if lcov_da_line(&d, 0, 9) != -1 { ok = false; }
      if lcov_da_hits(&d, 0, -2) != -1 { ok = false; }
      if lcov_da_has_checksum(&d, 0, 0) { ok = false; }
      if !streq(lcov_da_checksum(&d, 0, 0), "") { ok = false; }
      if lcov_brda_taken(&d, 0, 9) != -1 { ok = false; }
      if !streq(lcov_brda_block(&d, 0, 9), "") { ok = false; }
      if !streq(lcov_brda_branch(&d, 0, 9), "") { ok = false; }
      if lcov_lf_mismatch(&d, 0) { ok = false; }
      if lcov_lf_mismatch(&d, 9) { ok = false; }
      if lcov_fnf_mismatch(&d, -1) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "out-of-range accessors return their documented sentinels");
}

fn t19() -> TestResult {
  var ok = round_trip(full_text());
  if !round_trip("TN:merged\nSF:x.c\nDA:5,1\nFNF:1\nFN:5,f\nFNDA:1,f\nBRDA:5,0,0,-\nBRH:0\nend_of_record\n") { ok = false; }
  if !round_trip("SF:z.c\nDA:007,01\nend_of_record\n") { ok = false; }
  if !round_trip("SF:m.c\nDA:1,1\nDA:2,0\nFNF:9\nFNH:9\nLF:9\nLH:9\nBRDA:1,0,0,3\nBRF:9\nBRH:9\nend_of_record\n") { ok = false; }
  if !round_trip("TN:a\nSF:one.c\nDA:1,1\nend_of_record\nTN:b\nSF:two.c\nDA:2,0\nend_of_record\n") { ok = false; }
  if !round_trip("\r\nTN:t\r\nSF:a.c\r\n\r\nDA:1,1\r\nend_of_record\r\n") { ok = false; }
  if !round_trip("TN:x\nTN:y\nSF:d.c\nLF:1\nLF:7\nend_of_record\n") { ok = false; }
  if !round_trip("SF:a\nend_of_record\n") { ok = false; }
  if !round_trip("") { ok = false; }
  return assert(ok, "round trip preserves structure and emit is idempotent");
}

fn t20() -> TestResult {
  let text = "SF:zero.c\nFNF:0\nFNH:0\nLF:0\nLH:0\nBRF:0\nBRH:0\nend_of_record\n";
  let r = lcov_parse(text);
  var ok = false;
  match r {
    Ok(d) => {
      ok = lcov_declared_fnf(&d, 0) == 0;
      if lcov_declared_fnh(&d, 0) != 0 { ok = false; }
      if lcov_declared_lf(&d, 0) != 0 { ok = false; }
      if lcov_declared_lh(&d, 0) != 0 { ok = false; }
      if lcov_declared_brf(&d, 0) != 0 { ok = false; }
      if lcov_declared_brh(&d, 0) != 0 { ok = false; }
      if lcov_fnf_mismatch(&d, 0) { ok = false; }
      if lcov_lf_mismatch(&d, 0) { ok = false; }
      if !streq(lcov_emit(&d), "SF:zero.c\nFNF:0\nFNH:0\nLF:0\nLH:0\nBRF:0\nBRH:0\nend_of_record\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !round_trip(text) { ok = false; }
  return assert(ok, "declared zero values are present (not absent) and are emitted");
}

fn t21() -> TestResult {
  let text = "TN:my suite 1\nSF:a b/c.c\nDA:1,0,c0ffee00\nend_of_record\n";
  let r = lcov_parse(text);
  var ok = false;
  match r {
    Ok(d) => {
      ok = streq(lcov_file_test_name(&d, 0), "my suite 1");
      if !streq(lcov_file_source(&d, 0), "a b/c.c") { ok = false; }
      if !streq(lcov_da_checksum(&d, 0, 0), "c0ffee00") { ok = false; }
      if !streq(lcov_emit(&d), text) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !round_trip(text) { ok = false; }
  return assert(ok, "test names, paths and checksums may contain spaces and punctuation");
}

fn main() -> Int {
  io.println("=== xiom.lcov conformance tests ===");
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
    io.println("xiom.lcov: all tests passed");
  } else {
    io.println("xiom.lcov: tests failed");
  }
  return failed;
}
