// XIOM -- xiom.gedcom conformance tests (23 checks)
// Greenfield package: prove the pure-XIOM xiom.gedcom module against its
// documented line grammar, nesting rules, pointer predicate, CONT/CONC join
// helper, canonical emitter and error catalog.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: level/xref/tag/value accessors, parent indices, subtree ranges,
// first-tag lookup, pointer values and the predicate, CONT/CONC joining with
// stop-at-other-tag, byte-exact canonical emission, loose-separator
// canonicalization, LF/CRLF input, blank-line skipping, all six error classes
// with exact messages, valid downward level jumps, deep nesting, out-of-range
// accessors, UTF-8 pass-through and structure round-trips.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq/opt_str_is/parse_err_is instead of `==`.

module gedcom_tests
use xiom.io; use xiom.test; use xiom.gedcom;
use xiom.string;
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

// True when the text fails to parse with a "gedcom: " error message.
fn parse_err_prefix(text: Str) -> Bool {
  let r = gedcom_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, "gedcom: "); },
  }
  return false;
}

// True when the text fails to parse with exactly the message `want`.
fn parse_err_is(text: Str, want: Str) -> Bool {
  let r = gedcom_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn same_opt_str(a: Option[Str], b: Option[Str]) -> Bool {
  var ok = false;
  match a {
    Some(va) => {
      match b {
        Some(vb) => { ok = streq(va, vb); },
        None => { ok = false; },
      }
    },
    None => {
      match b {
        Some(_) => { ok = false; },
        None => { ok = true; },
      }
    },
  }
  return ok;
}

// True when two documents agree on every line field, in order.
fn same_shape(a: &Gedcom, b: &Gedcom) -> Bool {
  if gedcom_line_count(a) != gedcom_line_count(b) {
    return false;
  }
  var i = 0;
  while i < gedcom_line_count(a) {
    if gedcom_level(a, i) != gedcom_level(b, i) {
      return false;
    }
    if gedcom_parent(a, i) != gedcom_parent(b, i) {
      return false;
    }
    let ta: Str = gedcom_tag(a, i);
    let tb: Str = gedcom_tag(b, i);
    if !streq(ta, tb) {
      return false;
    }
    let va: Str = gedcom_value(a, i);
    let vb: Str = gedcom_value(b, i);
    if !streq(va, vb) {
      return false;
    }
    let xa = gedcom_xref(a, i);
    let xb = gedcom_xref(b, i);
    if !same_opt_str(xa, xb) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// The canonical fixture: two records, nested levels, xrefs, pointers and a
// CONT/CONC continuation run. Line indices are used by the checks below.
fn sample() -> Str {
  return "0 HEAD\n" +
    "1 SOUR APP\n" +
    "2 VERS 1.0\n" +
    "1 CHAR UTF-8\n" +
    "0 @I1@ INDI\n" +
    "1 NAME John /Doe/\n" +
    "2 GIVN John\n" +
    "2 SURN Doe\n" +
    "1 NOTE first line\n" +
    "2 CONT second line\n" +
    "2 CONC  and joined\n" +
    "1 FAMS @F1@\n" +
    "0 @F1@ FAM\n" +
    "1 HUSB @I1@\n" +
    "1 CHIL @I2@\n" +
    "0 TRLR\n";
}

fn t1() -> TestResult {
  let r = gedcom_parse(sample());
  var ok = false;
  match r {
    Ok(g) => {
      ok = gedcom_line_count(&g) == 16;
      if gedcom_level(&g, 0) != 0 { ok = false; }
      if gedcom_level(&g, 2) != 2 { ok = false; }
      if gedcom_level(&g, 15) != 0 { ok = false; }
      if !streq(gedcom_tag(&g, 0), "HEAD") { ok = false; }
      if !streq(gedcom_tag(&g, 4), "INDI") { ok = false; }
      if !streq(gedcom_tag(&g, 15), "TRLR") { ok = false; }
      if !streq(gedcom_value(&g, 1), "APP") { ok = false; }
      if !streq(gedcom_value(&g, 2), "1.0") { ok = false; }
      if !streq(gedcom_value(&g, 5), "John /Doe/") { ok = false; }
      if !streq(gedcom_value(&g, 0), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse sample: line count, levels, tags and values");
}

fn t2() -> TestResult {
  let r = gedcom_parse(sample());
  var ok = false;
  match r {
    Ok(g) => {
      ok = opt_str_is(gedcom_xref(&g, 4), "@I1@");
      if !opt_str_is(gedcom_xref(&g, 12), "@F1@") { ok = false; }
      if !opt_str_none(gedcom_xref(&g, 0)) { ok = false; }
      if !opt_str_none(gedcom_xref(&g, 5)) { ok = false; }
      if !streq(gedcom_value(&g, 11), "@F1@") { ok = false; }
      if !streq(gedcom_value(&g, 13), "@I1@") { ok = false; }
      if !gedcom_is_pointer("@I1@") { ok = false; }
      if !gedcom_is_pointer("@F_1@") { ok = false; }
      if gedcom_is_pointer("I1") { ok = false; }
      if gedcom_is_pointer("@@") { ok = false; }
      if gedcom_is_pointer("@I1") { ok = false; }
      if gedcom_is_pointer("@I 1@") { ok = false; }
      if gedcom_is_pointer("@I-1@") { ok = false; }
      if gedcom_is_pointer("John /Doe/") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "xref fields parse and pointer values are kept verbatim");
}

fn t3() -> TestResult {
  let r = gedcom_parse(sample());
  var ok = false;
  match r {
    Ok(g) => {
      ok = gedcom_parent(&g, 0) == -1;
      if gedcom_parent(&g, 1) != 0 { ok = false; }
      if gedcom_parent(&g, 3) != 0 { ok = false; }
      if gedcom_parent(&g, 6) != 5 { ok = false; }
      if gedcom_parent(&g, 10) != 8 { ok = false; }
      if gedcom_parent(&g, 15) != -1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parent indices point at the nearest level-1 ancestor");
}

fn t4() -> TestResult {
  let r = gedcom_parse(sample());
  var ok = false;
  match r {
    Ok(g) => {
      ok = gedcom_subtree_end(&g, 0) == 4;
      if gedcom_subtree_end(&g, 4) != 12 { ok = false; }
      if gedcom_subtree_end(&g, 5) != 8 { ok = false; }
      if gedcom_subtree_end(&g, 8) != 11 { ok = false; }
      if gedcom_subtree_end(&g, 12) != 15 { ok = false; }
      if gedcom_subtree_end(&g, 15) != 16 { ok = false; }
      if gedcom_subtree_end(&g, -1) != 16 { ok = false; }
      if gedcom_subtree_end(&g, 99) != 16 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "subtree ranges cover each record and its descendants");
}

fn t5() -> TestResult {
  let r = gedcom_parse(sample());
  var ok = false;
  match r {
    Ok(g) => {
      ok = opt_int_is(gedcom_first_tag(&g, "HEAD"), 0);
      if !opt_int_is(gedcom_first_tag(&g, "INDI"), 4) { ok = false; }
      if !opt_int_is(gedcom_first_tag(&g, "SURN"), 7) { ok = false; }
      if !opt_int_is(gedcom_first_tag(&g, "TRLR"), 15) { ok = false; }
      if !opt_int_none(gedcom_first_tag(&g, "head")) { ok = false; }
      if !opt_int_none(gedcom_first_tag(&g, "BIRT")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "first_tag finds the first byte-equal tag, case-sensitive");
}

fn t6() -> TestResult {
  var ok = false;
  let r = gedcom_parse(sample());
  match r {
    Ok(g) => {
      ok = streq(gedcom_join_text(&g, 8), "first line\nsecond line and joined");
      if !streq(gedcom_join_text(&g, 9), "second line") { ok = false; }
      if !streq(gedcom_join_text(&g, 5), "John /Doe/") { ok = false; }
      if !streq(gedcom_join_text(&g, -1), "") { ok = false; }
      if !streq(gedcom_join_text(&g, 99), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = gedcom_parse("0 NOTE a\n1 CONT b\n1 X c\n1 CONT d\n0 TRLR\n");
  match r2 {
    Ok(g2) => {
      if !streq(gedcom_join_text(&g2, 0), "a\nb") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = gedcom_parse("0 NOTE a\n1 CONC b\n1 CONC c\n");
  match r3 {
    Ok(g3) => {
      if !streq(gedcom_join_text(&g3, 0), "abc") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "join_text appends CONT with LF and CONC verbatim");
}

fn t7() -> TestResult {
  var ok = false;
  let r = gedcom_parse(sample());
  match r {
    Ok(g) => {
      ok = streq(gedcom_emit(&g), sample());
    },
    Err(_) => { ok = false; },
  }
  let re = gedcom_parse("");
  match re {
    Ok(ge) => {
      if !streq(gedcom_emit(&ge), "") { ok = false; }
      if gedcom_line_count(&ge) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "emit reproduces the canonical sample byte for byte");
}

fn t8() -> TestResult {
  let r = gedcom_parse("0   HEAD\n1\tSOUR\tAPP\n0 NOTE  padded\n");
  var ok = false;
  match r {
    Ok(g) => {
      ok = gedcom_line_count(&g) == 3;
      if !streq(gedcom_value(&g, 2), " padded") { ok = false; }
      if !streq(gedcom_emit(&g), "0 HEAD\n1 SOUR APP\n0 NOTE  padded\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = gedcom_parse("0 NOTE \n0 TRLR\n");
  match r2 {
    Ok(g2) => {
      if !streq(gedcom_value(&g2, 0), "") { ok = false; }
      if !streq(gedcom_emit(&g2), "0 NOTE\n0 TRLR\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "loose separators collapse to single spaces on emit");
}

fn t9() -> TestResult {
  let text = "0 HEAD\r\n1 SOUR APP\r\n0 @I1@ INDI\r\n1 NAME Jane\r\n0 TRLR\r\n";
  let r = gedcom_parse(text);
  var ok = false;
  match r {
    Ok(g) => {
      ok = gedcom_line_count(&g) == 5;
      if !streq(gedcom_value(&g, 1), "APP") { ok = false; }
      if !opt_str_is(gedcom_xref(&g, 2), "@I1@") { ok = false; }
      if !streq(gedcom_tag(&g, 4), "TRLR") { ok = false; }
      if !streq(gedcom_emit(&g), "0 HEAD\n1 SOUR APP\n0 @I1@ INDI\n1 NAME Jane\n0 TRLR\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "CRLF input parses with the CR stripped");
}

fn t10() -> TestResult {
  var ok = false;
  let r = gedcom_parse("0 HEAD\n\n0 TRLR\n");
  match r {
    Ok(g) => {
      ok = gedcom_line_count(&g) == 2;
      if gedcom_level(&g, 1) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = gedcom_parse("\n\n\n");
  match r2 {
    Ok(g2) => {
      if gedcom_line_count(&g2) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = gedcom_parse("");
  match r3 {
    Ok(g3) => {
      if gedcom_line_count(&g3) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "zero-length lines are ignored as record separators");
}

fn t11() -> TestResult {
  var ok = parse_err_prefix("HEAD");
  if !parse_err_prefix(" 0 HEAD") { ok = false; }
  if !parse_err_prefix("\t0 HEAD") { ok = false; }
  if !parse_err_prefix("   ") { ok = false; }
  if !parse_err_prefix("0 HEAD\n   \n0 TRLR\n") { ok = false; }
  if !parse_err_is("HEAD", "gedcom: text before level in line: HEAD") { ok = false; }
  return assert(ok, "a line that does not start with a digit is Err");
}

fn t12() -> TestResult {
  var ok = parse_err_prefix("0HEAD");
  if !parse_err_prefix("1x") { ok = false; }
  if !parse_err_prefix("12345678 HEAD") { ok = false; }
  if !parse_err_prefix("0@I1@ INDI") { ok = false; }
  if !parse_err_prefix("1.5 NAME x") { ok = false; }
  if !parse_err_is("0HEAD", "gedcom: bad level digits in line: 0HEAD") { ok = false; }
  let r = gedcom_parse("0000000 HEAD\n");
  match r {
    Ok(g) => {
      if gedcom_line_count(&g) != 1 { ok = false; }
      if gedcom_level(&g, 0) != 0 { ok = false; }
      if !streq(gedcom_emit(&g), "0 HEAD\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "level must be 1 to 7 digits followed by a separator");
}

fn t13() -> TestResult {
  var ok = parse_err_prefix("1 NAME x");
  if !parse_err_prefix("0 HEAD\n2 SOUR x") { ok = false; }
  if !parse_err_prefix("0 HEAD\n1 A\n3 B") { ok = false; }
  if !parse_err_is("2 SOUR x", "gedcom: level jump in line: 2 SOUR x") { ok = false; }
  let r = gedcom_parse("0 A\n1 B\n2 C\n0 D\n1 E\n");
  match r {
    Ok(g) => {
      if gedcom_line_count(&g) != 5 { ok = false; }
      if gedcom_parent(&g, 2) != 1 { ok = false; }
      if gedcom_parent(&g, 3) != -1 { ok = false; }
      if gedcom_parent(&g, 4) != 3 { ok = false; }
      if !streq(gedcom_tag(&g, 4), "E") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "the first line is level 0 and levels rise by at most one");
}

fn t14() -> TestResult {
  var ok = parse_err_prefix("0 @I1 INDI");
  if !parse_err_prefix("0 @@ INDI") { ok = false; }
  if !parse_err_prefix("0 @I-1@ INDI") { ok = false; }
  if !parse_err_prefix("0 @I1@INDI") { ok = false; }
  if !parse_err_prefix("0 @ INDI") { ok = false; }
  if !parse_err_prefix("0 @I1@@ INDI") { ok = false; }
  if !parse_err_is("0 @I1 INDI", "gedcom: malformed xref in line: 0 @I1 INDI") { ok = false; }
  return assert(ok, "an xref token must be exactly @id@ with an id alphabet");
}

fn t15() -> TestResult {
  var ok = parse_err_prefix("0 BAD-TAG");
  if !parse_err_prefix("0 NA@ME x") { ok = false; }
  if !parse_err_prefix("0 ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEF") { ok = false; }
  if !parse_err_prefix("0 TÄG x") { ok = false; }
  if !parse_err_is("0 BAD-TAG", "gedcom: bad tag in line: 0 BAD-TAG") { ok = false; }
  let r = gedcom_parse("0 ABCDEFGHIJKLMNOPQRSTUVWXYZABCDE v\n");
  match r {
    Ok(g) => {
      if !streq(gedcom_tag(&g, 0), "ABCDEFGHIJKLMNOPQRSTUVWXYZABCDE") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "tags are 1 to 31 bytes of [A-Za-z0-9_]");
}

fn t16() -> TestResult {
  var ok = parse_err_is("0", "gedcom: missing tag in line: 0");
  if !parse_err_is("0   ", "gedcom: missing tag in line: 0   ") { ok = false; }
  if !parse_err_prefix("0 @I1@") { ok = false; }
  if !parse_err_prefix("0 @I1@   ") { ok = false; }
  return assert(ok, "a line or xref without a tag is Err");
}

fn t17() -> TestResult {
  let r = gedcom_parse("0 TRLR\n0 NOTE \n0 NOTE x\n");
  var ok = false;
  match r {
    Ok(g) => {
      ok = gedcom_line_count(&g) == 3;
      if !streq(gedcom_value(&g, 0), "") { ok = false; }
      if !streq(gedcom_value(&g, 1), "") { ok = false; }
      if !streq(gedcom_value(&g, 2), "x") { ok = false; }
      if !streq(gedcom_emit(&g), "0 TRLR\n0 NOTE\n0 NOTE x\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "absent and empty values are both stored as empty");
}

fn t18() -> TestResult {
  var ok = false;
  let r1 = gedcom_parse(sample());
  match r1 {
    Ok(g1) => {
      let text = gedcom_emit(&g1);
      let r2 = gedcom_parse(text);
      match r2 {
        Ok(g2) => {
          ok = same_shape(&g1, &g2);
          if !streq(gedcom_emit(&g2), text) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse -> emit -> parse preserves every line field");
}

fn t19() -> TestResult {
  var ok = false;
  let r1 = gedcom_parse("0  HEAD\r\n1\tSOUR\tAPP\r\n");
  match r1 {
    Ok(g1) => {
      let text1 = gedcom_emit(&g1);
      ok = streq(text1, "0 HEAD\n1 SOUR APP\n");
      let r2 = gedcom_parse(text1);
      match r2 {
        Ok(g2) => {
          if !streq(gedcom_emit(&g2), text1) { ok = false; }
          if !same_shape(&g1, &g2) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "emit is idempotent on loosely spaced input");
}

fn t20() -> TestResult {
  let r = gedcom_parse("0 @X_Y9@ TEST v\n1 1SOUR x\n1 _CUSTOM y\n1 Head z\n");
  var ok = false;
  match r {
    Ok(g) => {
      ok = opt_str_is(gedcom_xref(&g, 0), "@X_Y9@");
      if !streq(gedcom_tag(&g, 0), "TEST") { ok = false; }
      if !streq(gedcom_value(&g, 0), "v") { ok = false; }
      if !streq(gedcom_tag(&g, 1), "1SOUR") { ok = false; }
      if !streq(gedcom_tag(&g, 2), "_CUSTOM") { ok = false; }
      if !streq(gedcom_tag(&g, 3), "Head") { ok = false; }
      if !opt_str_none(gedcom_xref(&g, 1)) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "tag alphabet accepts digits, underscores and mixed case");
}

fn t21() -> TestResult {
  let r = gedcom_parse(sample());
  var ok = false;
  match r {
    Ok(g) => {
      ok = gedcom_line_count(&g) == 16;
      if gedcom_level(&g, -1) != -1 { ok = false; }
      if gedcom_level(&g, 16) != -1 { ok = false; }
      if gedcom_level(&g, 99) != -1 { ok = false; }
      if !streq(gedcom_tag(&g, -1), "") { ok = false; }
      if !streq(gedcom_tag(&g, 99), "") { ok = false; }
      if !streq(gedcom_value(&g, -1), "") { ok = false; }
      if !streq(gedcom_value(&g, 99), "") { ok = false; }
      if gedcom_parent(&g, -1) != -1 { ok = false; }
      if gedcom_parent(&g, 99) != -1 { ok = false; }
      if !opt_str_none(gedcom_xref(&g, -1)) { ok = false; }
      if !opt_str_none(gedcom_xref(&g, 99)) { ok = false; }
      if !opt_int_none(gedcom_first_tag(&g, "")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "accessors return their sentinel for out-of-range indices");
}

fn t22() -> TestResult {
  var ok = false;
  let r = gedcom_parse("0 A\n1 B\n2 C\n3 D\n4 E\n");
  match r {
    Ok(g) => {
      ok = gedcom_line_count(&g) == 5;
      if gedcom_level(&g, 4) != 4 { ok = false; }
      if gedcom_parent(&g, 4) != 3 { ok = false; }
      if gedcom_subtree_end(&g, 0) != 5 { ok = false; }
      if gedcom_subtree_end(&g, 3) != 5 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = gedcom_parse("0 X\n1 Y\n0 Z\n");
  match r2 {
    Ok(g2) => {
      if gedcom_line_count(&g2) != 3 { ok = false; }
      if gedcom_parent(&g2, 2) != -1 { ok = false; }
      if gedcom_subtree_end(&g2, 1) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "deep nesting keeps parents while level 0 starts a new record");
}

fn t23() -> TestResult {
  let text = "0 NOTE café\n1 CONT über\n";
  let r = gedcom_parse(text);
  var ok = false;
  match r {
    Ok(g) => {
      ok = gedcom_line_count(&g) == 2;
      if !streq(gedcom_value(&g, 0), "café") { ok = false; }
      if !streq(gedcom_value(&g, 1), "über") { ok = false; }
      if !streq(gedcom_tag(&g, 1), "CONT") { ok = false; }
      if !streq(gedcom_emit(&g), text) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "non-ASCII bytes pass through values and emission");
}

fn main() -> Int {
  io.println("=== xiom.gedcom conformance tests ===");
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
    io.println("xiom.gedcom: all tests passed");
  } else {
    io.println("xiom.gedcom: tests failed");
  }
  return failed;
}
