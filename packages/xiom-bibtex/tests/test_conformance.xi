// XIOM -- xiom.bibtex conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module bibtex_tests
use xiom.io; use xiom.test; use xiom.bibtex;
use xiom.string;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every element check
// below is routed through streq/opt_str_is instead of `==`.

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
  let r = bib_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when parsing `text` fails with a message starting with `prefix`.
fn parse_err_prefix(text: Str, prefix: Str) -> Bool {
  let r = bib_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return string.str_starts_with(e, prefix); },
  }
  return false;
}

// True when parsing `text` succeeds with exactly `want` entries.
fn parse_entry_count(text: Str, want: Int) -> Bool {
  let r = bib_parse(text);
  match r {
    Ok(d) => { return bib_entry_count(&d) == want; },
    Err(_) => { return false; },
  }
  return false;
}

// True when two documents expose identical entries, fields, macros,
// preambles and comments (value-wise; used by the round-trip checks).
fn same_doc(a: &BibDoc, b: &BibDoc) -> Bool {
  if bib_entry_count(a) != bib_entry_count(b) { return false; }
  if bib_macro_count(a) != bib_macro_count(b) { return false; }
  if bib_preamble_count(a) != bib_preamble_count(b) { return false; }
  if bib_comment_count(a) != bib_comment_count(b) { return false; }
  var i = 0;
  while i < bib_entry_count(a) {
    if !streq(bib_entry_type(a, i), bib_entry_type(b, i)) { return false; }
    if !streq(bib_entry_key(a, i), bib_entry_key(b, i)) { return false; }
    if bib_field_count(a, i) != bib_field_count(b, i) { return false; }
    var j = 0;
    while j < bib_field_count(a, i) {
      if !streq(bib_field_name(a, i, j), bib_field_name(b, i, j)) { return false; }
      if !streq(bib_field_value(a, i, j), bib_field_value(b, i, j)) { return false; }
      j = j + 1;
    }
    i = i + 1;
  }
  var k = 0;
  while k < bib_macro_count(a) {
    if !streq(bib_macro_name(a, k), bib_macro_name(b, k)) { return false; }
    if !streq(bib_macro_value(a, k), bib_macro_value(b, k)) { return false; }
    k = k + 1;
  }
  var p = 0;
  while p < bib_preamble_count(a) {
    if !streq(bib_preamble(a, p), bib_preamble(b, p)) { return false; }
    p = p + 1;
  }
  var c = 0;
  while c < bib_comment_count(a) {
    if !streq(bib_comment(a, c), bib_comment(b, c)) { return false; }
    c = c + 1;
  }
  return true;
}

// True when parse -> emit -> parse preserves the document.
fn roundtrip_ok(text: Str) -> Bool {
  let r1 = bib_parse(text);
  match r1 {
    Ok(d1) => {
      let emitted = bib_emit(&d1);
      let r2 = bib_parse(emitted);
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
  let r = bib_parse("@article{knuth1984, title = {Literate Programming}}");
  var ok = false;
  match r {
    Ok(d) => {
      ok = bib_entry_count(&d) == 1;
      if !streq(bib_entry_type(&d, 0), "article") { ok = false; }
      if !streq(bib_entry_key(&d, 0), "knuth1984") { ok = false; }
      if bib_field_count(&d, 0) != 1 { ok = false; }
      if !streq(bib_field_name(&d, 0, 0), "title") { ok = false; }
      if !streq(bib_field_value(&d, 0, 0), "Literate Programming") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "simple entry parses");
}

fn t2() -> TestResult {
  let r = bib_parse("@ARTICLE{KeyName, TITLE = {T}, Year = 1999}");
  var ok = false;
  match r {
    Ok(d) => {
      ok = bib_entry_count(&d) == 1;
      if !streq(bib_entry_type(&d, 0), "article") { ok = false; }
      if !streq(bib_entry_key(&d, 0), "KeyName") { ok = false; }
      if !streq(bib_field_name(&d, 0, 0), "title") { ok = false; }
      if !opt_str_is(bib_get_field(&d, 0, "TiTlE"), "T") { ok = false; }
      if !opt_str_is(bib_get_field(&d, 0, "year"), "1999") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "types and field names are case-insensitive");
}

fn t3() -> TestResult {
  let r = bib_parse("@inproceedings{a1,\n  author = {Ada},\n  title = {T},\n  year = {2020},\n}");
  var ok = false;
  match r {
    Ok(d) => {
      ok = bib_field_count(&d, 0) == 3;
      if !streq(bib_field_name(&d, 0, 0), "author") { ok = false; }
      if !streq(bib_field_value(&d, 0, 0), "Ada") { ok = false; }
      if !streq(bib_field_name(&d, 0, 1), "title") { ok = false; }
      if !streq(bib_field_name(&d, 0, 2), "year") { ok = false; }
      if !streq(bib_field_value(&d, 0, 2), "2020") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "fields keep document order and trailing commas are allowed");
}

fn t4() -> TestResult {
  let r = bib_parse("@misc{k, note = {A {B} C}, deep = {x {{y}} z}}");
  var ok = false;
  match r {
    Ok(d) => {
      ok = bib_field_count(&d, 0) == 2;
      if !streq(bib_field_value(&d, 0, 0), "A {B} C") { ok = false; }
      if !streq(bib_field_value(&d, 0, 1), "x {{y}} z") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "nested braces are preserved inside values");
}

fn t5() -> TestResult {
  let r = bib_parse("@misc{k, title = \"Hello {World}\", q = \"a\\\"b\"}");
  var ok = false;
  match r {
    Ok(d) => {
      ok = bib_field_count(&d, 0) == 2;
      if !streq(bib_field_value(&d, 0, 0), "Hello {World}") { ok = false; }
      if !streq(bib_field_value(&d, 0, 1), "a\\\"b") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "quoted values strip quotes and keep escaped quotes");
}

fn t6() -> TestResult {
  let r = bib_parse("@misc{k, year = 2020, month = 3, note = {}, x = \"\"}");
  var ok = false;
  match r {
    Ok(d) => {
      ok = bib_field_count(&d, 0) == 4;
      if !streq(bib_field_value(&d, 0, 0), "2020") { ok = false; }
      if !streq(bib_field_value(&d, 0, 1), "3") { ok = false; }
      if !streq(bib_field_value(&d, 0, 2), "") { ok = false; }
      if !streq(bib_field_value(&d, 0, 3), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "number and empty values");
}

fn t7() -> TestResult {
  let r = bib_parse("@misc{k,\n\ttitle = {line one\nline two},\n   note\n=\n{ok}\n}\r\n@misc{c, x = {v}}\r\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = bib_entry_count(&d) == 2;
      if !streq(bib_field_value(&d, 0, 0), "line one\nline two") { ok = false; }
      if !streq(bib_field_name(&d, 0, 1), "note") { ok = false; }
      if !streq(bib_field_value(&d, 0, 1), "ok") { ok = false; }
      if !streq(bib_field_value(&d, 1, 0), "v") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "multi-line values and whitespace tolerance");
}

fn t8() -> TestResult {
  var ok = parse_entry_count("@misc{a}", 1);
  if !parse_entry_count("@book{b,}", 1) { ok = false; }
  if !parse_entry_count("@book{c, title = {T},}", 1) { ok = false; }
  let r = bib_parse("@misc{a}");
  match r {
    Ok(d) => {
      if bib_field_count(&d, 0) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "zero-field entries and trailing commas");
}

fn t9() -> TestResult {
  let r = bib_parse("@string{ieee = \"IEEE Trans. Inf. Theory\"}\n@article{k, journal = ieee, note = IEEE}");
  var ok = false;
  match r {
    Ok(d) => {
      ok = bib_macro_count(&d) == 1;
      if !streq(bib_macro_name(&d, 0), "ieee") { ok = false; }
      if !streq(bib_macro_value(&d, 0), "IEEE Trans. Inf. Theory") { ok = false; }
      if !streq(bib_field_value(&d, 0, 0), "IEEE Trans. Inf. Theory") { ok = false; }
      if !streq(bib_field_value(&d, 0, 1), "IEEE Trans. Inf. Theory") { ok = false; }
      if !opt_str_is(bib_get_macro(&d, "IEEE"), "IEEE Trans. Inf. Theory") { ok = false; }
      if !opt_str_none(bib_get_macro(&d, "nope")) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "macros expand case-insensitively");
}

fn t10() -> TestResult {
  let r = bib_parse("@string{base = {X}}\n@String{derived = BASE}\n@misc{k, note = Derived}");
  var ok = false;
  match r {
    Ok(d) => {
      ok = bib_macro_count(&d) == 2;
      if !streq(bib_macro_name(&d, 1), "derived") { ok = false; }
      if !streq(bib_macro_value(&d, 1), "X") { ok = false; }
      if !streq(bib_field_value(&d, 0, 0), "X") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a @string may reference an earlier macro");
}

fn t11() -> TestResult {
  let r = bib_parse("@comment{jabref-meta: {group} stuff}\n@preamble{\"\\\\def\\\\x{y}\"}\n@misc{k}\n");
  var ok = false;
  match r {
    Ok(d) => {
      ok = bib_comment_count(&d) == 1;
      if !streq(bib_comment(&d, 0), "jabref-meta: {group} stuff") { ok = false; }
      if bib_preamble_count(&d) != 1 { ok = false; }
      if !streq(bib_preamble(&d, 0), "\\\\def\\\\x{y}") { ok = false; }
      if bib_entry_count(&d) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "@comment and @preamble pass through");
}

fn t12() -> TestResult {
  var ok = parse_entry_count("", 0);
  if !parse_entry_count("  \n\t\r\n ", 0) { ok = false; }
  if !parse_err_prefix("hello", "bibtex: text outside entries") { ok = false; }
  if !parse_err_prefix("% comment", "bibtex: text outside entries") { ok = false; }
  if !parse_err_prefix("{}", "bibtex: text outside entries") { ok = false; }
  return assert(ok, "text outside entries must be whitespace");
}

fn t13() -> TestResult {
  var ok = parse_err_is("@article{k", "bibtex: unterminated entry");
  if !parse_err_is("@article{k, title = {T}", "bibtex: unterminated entry") { ok = false; }
  if !parse_err_is("@", "bibtex: missing entry type") { ok = false; }
  if !parse_err_is("@article", "bibtex: expected '{' after entry type") { ok = false; }
  if !parse_err_is("@article (k)", "bibtex: expected '{' after entry type") { ok = false; }
  if !parse_err_is("@{x}", "bibtex: bad entry type: {x}") { ok = false; }
  return assert(ok, "unterminated entries and missing entry types");
}

fn t14() -> TestResult {
  var ok = parse_err_is("@misc{k, title = {T", "bibtex: unterminated value");
  if !parse_err_is("@misc{k, title = \"T", "bibtex: unterminated quote") { ok = false; }
  if !parse_err_is("@comment{abc", "bibtex: unterminated comment") { ok = false; }
  return assert(ok, "unterminated value, quote and comment");
}

fn t15() -> TestResult {
  var ok = parse_err_is("@misc{k, title = \"a}b\"}", "bibtex: unbalanced braces in value");
  if !parse_err_is("@misc{k, title = \"a{b\"}", "bibtex: unbalanced braces in value") { ok = false; }
  return assert(ok, "unbalanced braces in quoted values are errors");
}

fn t16() -> TestResult {
  var ok = parse_err_is("@article{}", "bibtex: missing key in entry");
  if !parse_err_is("@article{, a = {1}}", "bibtex: missing key in entry") { ok = false; }
  if !parse_err_is("@article{k = 1}", "bibtex: expected ',' or '}' after entry key") { ok = false; }
  return assert(ok, "missing keys and malformed entry heads");
}

fn t17() -> TestResult {
  var ok = parse_err_is("@article{k, title {T}}", "bibtex: missing '=' after field name: title");
  if !parse_err_is("@article{k, 1title = {T}}", "bibtex: bad field name: 1title") { ok = false; }
  if !parse_err_is("@article{k, = {T}}", "bibtex: bad field name: =") { ok = false; }
  if !parse_err_is("@article{k, title = }", "bibtex: missing value for field: title") { ok = false; }
  if !parse_err_is("@article{k, x = : }", "bibtex: malformed value: :") { ok = false; }
  if !parse_err_is("@string{x {v}}", "bibtex: missing '=' after macro name: x") { ok = false; }
  if !parse_err_is("@string{1x = {v}}", "bibtex: bad macro name: 1x") { ok = false; }
  if !parse_err_is("@string{x = }", "bibtex: missing value for macro: x") { ok = false; }
  return assert(ok, "missing '=', bad field/macro names and missing values");
}

fn t18() -> TestResult {
  var ok = parse_err_is("@article{a, x = {1}}\n@article{A, y = {2}}", "bibtex: duplicate key: A");
  if !parse_err_is("@article{a, x = {1}, X = {2}}", "bibtex: duplicate field: X") { ok = false; }
  if !parse_err_is("@string{s = {1}}\n@string{S = {2}}", "bibtex: duplicate macro: S") { ok = false; }
  return assert(ok, "duplicate keys, fields and macros");
}

fn t19() -> TestResult {
  var ok = parse_err_is("@misc{k, journal = nope}", "bibtex: undefined macro: nope");
  if !parse_err_is("@misc{k, x = \"a\" # \"b\"}", "bibtex: unsupported concatenation") { ok = false; }
  if !parse_err_is("@misc{k, x = {a} b = {c}}", "bibtex: expected ',' or '}' after field value") { ok = false; }
  if !parse_err_is("@misc{k, x = 12ab}", "bibtex: expected ',' or '}' after field value") { ok = false; }
  return assert(ok, "undefined macros, concatenation and trailing junk");
}

fn t20() -> TestResult {
  let txt = "@string{ieee = \"IEEE Trans.\"}\n@preamble{\"\\\\def\\\\x{y}\"}\n@comment{meta {nested}}\n@article{a,\n  author = {Ada {Lovelace}},\n  journal = ieee,\n  year = 1843,\n  title = \"Notes {A}\"\n}\n@book{b, publisher = {B}\n}\n";
  var ok = roundtrip_ok(txt);
  let r = bib_parse(txt);
  match r {
    Ok(d) => {
      let emitted = bib_emit(&d);
      if !string.str_starts_with(emitted, "@string{ieee = {IEEE Trans.}}") { ok = false; }
      if !string.str_contains(emitted, "@preamble{{\\\\def\\\\x{y}}}") { ok = false; }
      if bib_entry_count(&d) != 2 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "parse -> emit -> parse round-trips a full document");
}

fn t21() -> TestResult {
  let r = bib_parse("@misc{k, x = {1}}");
  var ok = false;
  match r {
    Ok(d) => {
      ok = streq(bib_entry_type(&d, 5), "");
      if !streq(bib_entry_key(&d, -1), "") { ok = false; }
      if bib_field_count(&d, 9) != 0 { ok = false; }
      if !streq(bib_field_name(&d, 0, 9), "") { ok = false; }
      if !streq(bib_field_value(&d, 0, -1), "") { ok = false; }
      if bib_find_entry(&d, "missing") != -1 { ok = false; }
      if !opt_str_none(bib_get_field(&d, 0, "nope")) { ok = false; }
      if !opt_str_none(bib_get_field(&d, 9, "x")) { ok = false; }
      if bib_macro_count(&d) != 0 { ok = false; }
      if !streq(bib_macro_name(&d, 0), "") { ok = false; }
      if !streq(bib_macro_value(&d, 0), "") { ok = false; }
      if bib_preamble_count(&d) != 0 { ok = false; }
      if !streq(bib_preamble(&d, 0), "") { ok = false; }
      if bib_comment_count(&d) != 0 { ok = false; }
      if !streq(bib_comment(&d, 0), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "out-of-range accessors are safe");
}

fn t22() -> TestResult {
  let r = bib_parse("@article{a,title={T},year=2020}");
  var ok = false;
  match r {
    Ok(d) => {
      ok = streq(bib_emit(&d), "@article{a,\n  title = {T},\n  year = {2020}\n}\n");
    },
    Err(_) => { ok = false; },
  }
  let r2 = bib_parse("@misc{k}");
  match r2 {
    Ok(d2) => {
      if !streq(bib_emit(&d2), "@misc{k}\n") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "canonical emission is exact");
}

fn t23() -> TestResult {
  let r = bib_parse("@article{Knuth1984, x = {1}}");
  var ok = false;
  match r {
    Ok(d) => {
      ok = bib_find_entry(&d, "knuth1984") == 0;
      if bib_find_entry(&d, "KNUTH1984") != 0 { ok = false; }
      if bib_find_entry(&d, "other") != -1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "citation key lookup is case-insensitive");
}

fn t24() -> TestResult {
  let r = bib_parse("");
  var ok = false;
  match r {
    Ok(d) => {
      ok = bib_entry_count(&d) == 0;
      if !streq(bib_emit(&d), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty input yields an empty document");
}

fn main() -> Int {
  io.println("=== xiom.bibtex conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.bibtex: all tests passed");
  } else {
    io.println("xiom.bibtex: tests failed");
  }
  return failed;
}
