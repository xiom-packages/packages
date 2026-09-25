// XIOM -- xiom.ris conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Every check pins a decision from SPEC.md: happy paths, boundaries, error
// paths and round-trips. All Str equality goes through str_compare: BUG 17
// lowers `==` on Str values read from Vec[Str] elements to a pointer
// comparison, so element checks are routed through streq/field_is instead of
// `==`. Tests are dispatched directly (t1() ... t20()); indexed Vec[fn] calls
// are not used because they miscompile.

module ris_tests
use xiom.io; use xiom.test; use xiom.ris;
use xiom.string.compare;

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

// True when parsing `text` fails with exactly `want`.
fn parse_err_is(text: Str, want: Str) -> Bool {
  let r = ris_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when field j of record r has exactly the wanted tag and value.
fn field_is(d: &RisDoc, r: Int, j: Int, tag: Str, value: Str) -> Bool {
  if !streq(ris_field_tag(d, r, j), tag) { return false; }
  return streq(ris_field_value(d, r, j), value);
}

// True when two documents expose identical records and fields (value-wise;
// used by the round-trip checks).
fn same_doc(a: &RisDoc, b: &RisDoc) -> Bool {
  if ris_record_count(a) != ris_record_count(b) { return false; }
  var r = 0;
  while r < ris_record_count(a) {
    if ris_field_count(a, r) != ris_field_count(b, r) { return false; }
    var j = 0;
    while j < ris_field_count(a, r) {
      if !streq(ris_field_tag(a, r, j), ris_field_tag(b, r, j)) { return false; }
      if !streq(ris_field_value(a, r, j), ris_field_value(b, r, j)) { return false; }
      j = j + 1;
    }
    r = r + 1;
  }
  return true;
}

// True when parse -> emit -> parse preserves the document.
fn roundtrip_ok(text: Str) -> Bool {
  let r1 = ris_parse(text);
  match r1 {
    Ok(d1) => {
      let emitted = ris_emit(&d1);
      let r2 = ris_parse(emitted);
      match r2 {
        Ok(d2) => { return same_doc(&d1, &d2); },
        Err(_) => { return false; },
      }
    },
    Err(_) => { return false; },
  }
  return false;
}

fn t1() -> TestResult {
  let r = ris_parse("TY  - JOUR\nAU  - Knuth, Donald E.\nTI  - Literate Programming\nER  - \n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = ris_record_count(&d) == 1;
      if ris_field_count(&d, 0) != 3 { ok = false; }
      if !field_is(&d, 0, 0, "TY", "JOUR") { ok = false; }
      if !field_is(&d, 0, 1, "AU", "Knuth, Donald E.") { ok = false; }
      if !field_is(&d, 0, 2, "TI", "Literate Programming") { ok = false; }
      if !opt_str_is(ris_get_field(&d, 0, "TI"), "Literate Programming") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "simple record: tags, values and document order");
}

fn t2() -> TestResult {
  let r = ris_parse("TY  - JOUR\nTI  - A\nER  - \n\nTY  - BOOK\nTI  - B\nER  - \n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = ris_record_count(&d) == 2;
      if ris_field_count(&d, 0) != 2 { ok = false; }
      if ris_field_count(&d, 1) != 2 { ok = false; }
      if !field_is(&d, 0, 1, "TI", "A") { ok = false; }
      if !field_is(&d, 1, 0, "TY", "BOOK") { ok = false; }
      if !field_is(&d, 1, 1, "TI", "B") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "blank lines separate records");
}

fn t3() -> TestResult {
  let r = ris_parse("TY  - JOUR\nPB  - ACM\nN1  - a note\nZZ  - custom\nER  -\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = ris_field_count(&d, 0) == 4;
      if !field_is(&d, 0, 1, "PB", "ACM") { ok = false; }
      if !field_is(&d, 0, 2, "N1", "a note") { ok = false; }
      if !field_is(&d, 0, 3, "ZZ", "custom") { ok = false; }
      if !opt_str_is(ris_get_field(&d, 0, "ZZ"), "custom") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "unknown tags are preserved and ER may end without a space");
}

fn t4() -> TestResult {
  let r = ris_parse("TY  -   JOUR  \nTI  - \nAB  -   spaced   out  \nER  - \n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = ris_field_count(&d, 0) == 3;
      if !field_is(&d, 0, 0, "TY", "JOUR") { ok = false; }
      if !field_is(&d, 0, 1, "TI", "") { ok = false; }
      if !field_is(&d, 0, 2, "AB", "spaced   out") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "values are trimmed and inner spacing is kept");
}

fn t5() -> TestResult {
  let r = ris_parse("TY  - JOUR\nAB  - first line\n      second line\n\n      third line\nER  - \n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = ris_field_count(&d, 0) == 2;
      if !field_is(&d, 0, 1, "AB", "first line second line third line") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "continuation lines join with one space and blank lines are ignored");
}

fn t6() -> TestResult {
  let crlf = "TY  - JOUR\r\nTI  - A\r\nER  - \r\n";
  var ok = roundtrip_ok(crlf);
  let r = ris_parse(crlf);
  match r {
    Ok(d) => {
      if ris_record_count(&d) != 1 { ok = false; }
      if !field_is(&d, 0, 1, "TI", "A") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let mixed = "TY  - JOUR\r\nTI  - A\nER  - \r\n";
  let r2 = ris_parse(mixed);
  match r2 {
    Ok(d2) => {
      if ris_record_count(&d2) != 1 { ok = false; }
      if !field_is(&d2, 0, 1, "TI", "A") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CRLF, LF and mixed line endings normalize");
}

fn t7() -> TestResult {
  let r = ris_parse("TY  - JOUR\nAU  - First\nAU  - Second\nER  - \n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = ris_field_count(&d, 0) == 3;
      if !field_is(&d, 0, 1, "AU", "First") { ok = false; }
      if !field_is(&d, 0, 2, "AU", "Second") { ok = false; }
      if !opt_str_is(ris_get_field(&d, 0, "AU"), "First") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "duplicate tags are kept and the first value wins");
}

fn t8() -> TestResult {
  let r = ris_parse("TY  - JOUR\nTI  - A  - B\nER  - \n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = ris_field_count(&d, 0) == 2;
      if !field_is(&d, 0, 1, "TI", "A  - B") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a delimiter inside a value is data");
}

fn t9() -> TestResult {
  var ok = parse_err_is("AU  - X\nER  - \n", "ris: missing TY at 1: AU");
  if !parse_err_is("ER  - \n", "ris: missing TY at 1: ER") { ok = false; }
  if !parse_err_is("TY  - JOUR\nER  - \nAU  - X\n", "ris: missing TY at 3: AU") { ok = false; }
  return assert(ok, "a record must start with TY");
}

fn t10() -> TestResult {
  var ok = parse_err_is("TY  - JOUR\nAU  - X\n", "ris: missing ER");
  if !parse_err_is("TY  - JOUR", "ris: missing ER") { ok = false; }
  if !parse_err_is("\nTY  - JOUR\n", "ris: missing ER") { ok = false; }
  if !parse_err_is("TY  - JOUR\nTY  - BOOK\nER  - \n", "ris: missing ER at 2") { ok = false; }
  return assert(ok, "an open record is missing ER before a new TY or end of input");
}

fn t11() -> TestResult {
  var ok = parse_err_is("ABC  - x\n", "ris: tag not 2 chars at 1: ABC");
  if !parse_err_is("A  - x\n", "ris: tag not 2 chars at 1: A") { ok = false; }
  if !parse_err_is("TY  - JOUR\nABC  - x\nER  - \n", "ris: tag not 2 chars at 2: ABC") { ok = false; }
  if !parse_err_is("T!  - x\n", "ris: malformed tag line at 1: T!  - x") { ok = false; }
  return assert(ok, "tag lines are validated for tag length and tag bytes");
}

fn t12() -> TestResult {
  var ok = parse_err_is("hello\n", "ris: text before first TY at 1: hello");
  if !parse_err_is("% a comment\nTY  - JOUR\nER  - \n", "ris: text before first TY at 1: % a comment") { ok = false; }
  if !parse_err_is("TY  - JOUR\nER  - \n} junk\n", "ris: text before first TY at 3: } junk") { ok = false; }
  return assert(ok, "non-tag text outside a record is rejected");
}

fn t13() -> TestResult {
  var ok = parse_err_is("TY  - JOUR\nER  - \nER  - \n", "ris: duplicate ER at 3");
  if !parse_err_is("TY  - JOUR\nER  -\n\nER  - \n", "ris: duplicate ER at 4") { ok = false; }
  return assert(ok, "a second ER where the next TY should be is a duplicate");
}

fn t14() -> TestResult {
  let src = "TY  - JOUR\r\nAU  - Ada Lovelace\r\nTI  - Notes on the Analytical Engine\r\nAB  - First line\r\n      second line\r\nN1  - \r\nZZ  - custom\r\nER  - \r\n\r\nTY  - CONF\r\nTI  - B\r\nER  -\r\n";
  var ok = roundtrip_ok(src);
  let r = ris_parse(src);
  match r {
    Ok(d) => {
      if ris_record_count(&d) != 2 { ok = false; }
      if ris_field_count(&d, 0) != 6 { ok = false; }
      if !field_is(&d, 0, 3, "AB", "First line second line") { ok = false; }
      if !field_is(&d, 0, 4, "N1", "") { ok = false; }
      if !field_is(&d, 1, 0, "TY", "CONF") { ok = false; }
      if !field_is(&d, 1, 1, "TI", "B") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "round-trip preserves records, continuations and empty values");
}

fn t15() -> TestResult {
  let r = ris_parse("");
  var ok = false;
  match r {
    Ok(d) => {
      ok = ris_record_count(&d) == 0;
      if !streq(ris_emit(&d), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = ris_parse("   \n\n \r\n\t\n");
  match r2 {
    Ok(d2) => {
      if ris_record_count(&d2) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty and whitespace-only input yield an empty document");
}

fn t16() -> TestResult {
  let r = ris_parse("TY  - JOUR\nTI  - T\nER  - \n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = ris_field_count(&d, -1) == 0;
      if ris_field_count(&d, 1) != 0 { ok = false; }
      if !streq(ris_field_tag(&d, 0, -1), "") { ok = false; }
      if !streq(ris_field_tag(&d, 0, 2), "") { ok = false; }
      if !streq(ris_field_value(&d, 5, 0), "") { ok = false; }
      if !opt_str_none(ris_get_field(&d, 0, "ZZ")) { ok = false; }
      if !opt_str_none(ris_get_field(&d, 7, "TI")) { ok = false; }
      if !opt_str_none(ris_get_field(&d, -1, "TI")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "out-of-range accessors return 0, \"\" and None");
}

fn t17() -> TestResult {
  let r = ris_parse("TY  -  JOUR\r\nTI  -  T\r\nER  -");
  var ok = false;
  match r {
    Ok(d) => {
      ok = streq(ris_emit(&d), "TY  - JOUR\nTI  - T\nER  - \n");
    },
    Err(_) => { ok = false; },
  }
  let r2 = ris_parse("TY  - JOUR\nER  - \n\nTY  - BOOK\nER  - \n");
  match r2 {
    Ok(d2) => {
      if !streq(ris_emit(&d2), "TY  - JOUR\nER  - \nTY  - BOOK\nER  - \n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "canonical emission is exact");
}

fn t18() -> TestResult {
  let r = ris_parse("TY  - JOUR\nti  - lower\nER  - \n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = ris_field_count(&d, 0) == 2;
      if !opt_str_none(ris_get_field(&d, 0, "TI")) { ok = false; }
      if !opt_str_is(ris_get_field(&d, 0, "ti"), "lower") { ok = false; }
      if !streq(ris_field_tag(&d, 0, 1), "ti") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "tag lookup is case-sensitive and preserves case");
}

fn t19() -> TestResult {
  let r = ris_parse("TY  - JOUR\ncontinued\nER  - \n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = ris_field_count(&d, 0) == 1;
      if !field_is(&d, 0, 0, "TY", "JOUR continued") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = ris_parse("TY  - JOUR\nAB  - a\n   b\nER  - \n");
  match r2 {
    Ok(d2) => {
      if ris_field_count(&d2, 0) != 2 { ok = false; }
      if !field_is(&d2, 0, 1, "AB", "a b") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = ris_parse("TY  - \ncontinued\nER  - \n");
  match r3 {
    Ok(d3) => {
      if ris_field_count(&d3, 0) != 1 { ok = false; }
      if !field_is(&d3, 0, 0, "TY", "continued") { ok = false; }
      if !roundtrip_ok("TY  - \ncontinued\nER  - \n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "continuations append to the previous value with one space");
}

fn t20() -> TestResult {
  let r = ris_parse("TY  - JOUR\nN1  - 12\nTI  - T\nER  - \n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = ris_field_count(&d, 0) == 3;
      if !field_is(&d, 0, 1, "N1", "12") { ok = false; }
      if !field_is(&d, 0, 2, "TI", "T") { ok = false; }
      if !opt_str_is(ris_get_field(&d, 0, "TY"), "JOUR") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = ris_parse("TY  - JOUR\n   \nTI  - T\nER  - \n");
  match r2 {
    Ok(d2) => {
      if ris_field_count(&d2, 0) != 2 { ok = false; }
      if !field_is(&d2, 0, 1, "TI", "T") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "digit tags and whitespace-only lines inside a record");
}

fn main() -> Int {
  io.println("=== xiom.ris conformance tests ===");
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
    io.println("xiom.ris: all tests passed");
  } else {
    io.println("xiom.ris: tests failed");
  }
  return failed;
}
