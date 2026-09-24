// XIOM -- xiom.preprocess conformance tests (21 checks)
// Port task: prove the pure-XIOM xiom.preprocess module against its SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq instead of `==`.

module preprocess_tests
use xiom.io; use xiom.test; use xiom.preprocess;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn t1() -> TestResult {
  var ok = streq(pp_fold_ascii("HELLO World 123"), "hello world 123");
  if !streq(pp_fold_ascii("café ÄÖÜ"), "café ÄÖÜ") { ok = false; }
  if pp_fold_ascii("café").len() != "café".len() { ok = false; }
  return assert(ok, "fold: A-Z fold, non-ASCII bytes pass through");
}

fn t2() -> TestResult {
  var ok = streq(pp_fold_ascii("AZaz09-_ ,."), "azaz09-_ ,.");
  let twice = pp_fold_ascii(pp_fold_ascii("MiXeD"));
  if !streq(twice, "mixed") { ok = false; }
  return assert(ok, "fold: only letters change, folding is idempotent");
}

fn t3() -> TestResult {
  var ok = streq(pp_strip_punct("Order #42: $19.99!"), "Order 42 1999");
  if !streq(pp_strip_punct("v1.2.3"), "v123") { ok = false; }
  if !streq(pp_strip_punct("a_b"), "ab") { ok = false; }
  return assert(ok, "strip_punct: digits and spaces kept, marks dropped");
}

fn t4() -> TestResult {
  var ok = streq(pp_strip_punct("Hello, world!"), "Hello world");
  if !streq(pp_strip_punct("café!"), "caf") { ok = false; }
  if !streq(pp_strip_punct("a\tb\nc\rd"), "abcd") { ok = false; }
  return assert(ok, "strip_punct: letters/space kept, tabs/newlines/non-ASCII dropped");
}

fn t5() -> TestResult {
  var ok = streq(pp_collapse_ws("  a   b\t\tc \r\n d  "), "a b c d");
  if !streq(pp_collapse_ws(" \t\r\n "), "") { ok = false; }
  return assert(ok, "collapse_ws: runs collapse, both ends trimmed");
}

fn t6() -> TestResult {
  var ok = streq(pp_collapse_ws("solo"), "solo");
  if !streq(pp_collapse_ws(" one "), "one") { ok = false; }
  if !streq(pp_collapse_ws("\r\n\t"), "") { ok = false; }
  return assert(ok, "collapse_ws: single token and whitespace-only input");
}

fn t7() -> TestResult {
  let once = pp_collapse_ws("\t hello \n\n world \t");
  var ok = streq(once, "hello world");
  if !streq(pp_collapse_ws(once), once) { ok = false; }
  return assert(ok, "collapse_ws: output is already collapsed (idempotent)");
}

fn t8() -> TestResult {
  var pad = "";
  var i = 0;
  while i < 64 {
    pad = pad + " \t";
    i = i + 1;
  }
  var ok = streq(pp_collapse_ws("a" + pad + "b"), "a b");
  if !streq(pp_collapse_ws(pad), "") { ok = false; }
  return assert(ok, "collapse_ws: long whitespace runs become one space");
}

fn t9() -> TestResult {
  var stops = Vec[Str].new();
  stops.push("the");
  stops.push("fox");
  var ok = streq(pp_remove_stopwords("The quick brown FOX", &stops), "quick brown");
  if !streq(pp_remove_stopwords("THE THE THE", &stops), "") { ok = false; }
  return assert(ok, "stopwords: matching is case-insensitive");
}

fn t10() -> TestResult {
  var stops = Vec[Str].new();
  stops.push("b");
  stops.push("d");
  var ok = streq(pp_remove_stopwords("a b c d e", &stops), "a c e");
  var one = Vec[Str].new();
  one.push("middle");
  if !streq(pp_remove_stopwords("first middle last", &one), "first last") { ok = false; }
  return assert(ok, "stopwords: kept tokens preserve their order");
}

fn t11() -> TestResult {
  var stops = Vec[Str].new();
  stops.push("the");
  var ok = streq(pp_remove_stopwords("theater the thespian", &stops), "theater thespian");
  var a = Vec[Str].new();
  a.push("a");
  if !streq(pp_remove_stopwords("aa a", &a), "aa") { ok = false; }
  var he = Vec[Str].new();
  he.push("he");
  if !streq(pp_remove_stopwords("the he", &he), "the") { ok = false; }
  return assert(ok, "stopwords: exact match, no substring removal");
}

fn t12() -> TestResult {
  var empty_entry = Vec[Str].new();
  empty_entry.push("");
  var ok = streq(pp_remove_stopwords("a  b", &empty_entry), "a b");
  var mixed = Vec[Str].new();
  mixed.push("");
  mixed.push("the");
  if !streq(pp_remove_stopwords("the theater", &mixed), "theater") { ok = false; }
  var double = Vec[Str].new();
  double.push("");
  double.push("");
  if !streq(pp_remove_stopwords("x", &double), "x") { ok = false; }
  return assert(ok, "stopwords: empty entries remove nothing and normalize spaces");
}

fn t13() -> TestResult {
  var stops = Vec[Str].new();
  stops.push("the");
  var none = Vec[Str].new();
  var ok = streq(pp_remove_stopwords("", &stops), "");
  if !streq(pp_remove_stopwords("a b", &none), "a b") { ok = false; }
  if !streq(pp_remove_stopwords("", &none), "") { ok = false; }
  return assert(ok, "stopwords: empty input and empty stop list are safe");
}

fn t14() -> TestResult {
  var stops = Vec[Str].new();
  stops.push("Ä");
  var ok = streq(pp_remove_stopwords("Ä Ö", &stops), "Ö");
  if !streq(pp_remove_stopwords("ä Ö", &stops), "ä Ö") { ok = false; }
  if !streq(pp_remove_stopwords("ÄÄ Ä", &stops), "ÄÄ") { ok = false; }
  return assert(ok, "stopwords: non-ASCII matches byte-exact, folding is ASCII-only");
}

fn t15() -> TestResult {
  var ok = pp_word_count("") == 0;
  if pp_word_count("   \t\n") != 0 { ok = false; }
  if pp_word_count("solo") != 1 { ok = false; }
  if pp_word_count(" a  b ") != 2 { ok = false; }
  if pp_word_count("a\tb\nc") != 3 { ok = false; }
  return assert(ok, "word_count: counts collapse_ws tokens, 0 for empty");
}

fn t16() -> TestResult {
  let sentence = "  The QUICK, brown   FOX!!\t";
  var stops = Vec[Str].new();
  stops.push("the");
  stops.push("fox");
  var ok = streq(pp_pipeline(sentence, &stops, true, true, true, true), "quick brown");
  let manual = pp_remove_stopwords(pp_collapse_ws(pp_strip_punct(pp_fold_ascii(sentence))), &stops);
  if !streq(manual, "quick brown") { ok = false; }
  return assert(ok, "pipeline: all steps on the fixed sentence");
}

fn t17() -> TestResult {
  let sentence = "  The QUICK, brown   FOX!!\t";
  var stops = Vec[Str].new();
  stops.push("the");
  stops.push("fox");
  var ok = streq(pp_pipeline(sentence, &stops, false, false, false, false), sentence);
  if !streq(pp_pipeline(sentence, &stops, true, false, false, false), "  the quick, brown   fox!!\t") { ok = false; }
  if !streq(pp_pipeline(sentence, &stops, true, true, false, false), "  the quick brown   fox") { ok = false; }
  if !streq(pp_pipeline(sentence, &stops, true, true, true, false), "the quick brown fox") { ok = false; }
  return assert(ok, "pipeline: each step can be switched off");
}

fn t18() -> TestResult {
  let sentence = "  The QUICK, brown   FOX!!\t";
  var stops = Vec[Str].new();
  stops.push("the");
  stops.push("fox");
  var ok = streq(pp_normalize_default(sentence), "the quick brown fox");
  if !streq(pp_pipeline(sentence, &stops, true, true, true, true), "quick brown") { ok = false; }
  if !streq(pp_normalize_default("HELLO,   World!"), "hello world") { ok = false; }
  return assert(ok, "default: fold+punct+ws only, no stopwords");
}

fn t19() -> TestResult {
  var stops = Vec[Str].new();
  stops.push("the");
  var ok = streq(pp_fold_ascii(""), "");
  if !streq(pp_strip_punct(""), "") { ok = false; }
  if !streq(pp_collapse_ws(""), "") { ok = false; }
  if !streq(pp_remove_stopwords("", &stops), "") { ok = false; }
  if pp_word_count("") != 0 { ok = false; }
  if !streq(pp_pipeline("", &stops, true, true, true, true), "") { ok = false; }
  if !streq(pp_normalize_default(""), "") { ok = false; }
  return assert(ok, "empty inputs produce empty results");
}

fn t20() -> TestResult {
  var stops = Vec[Str].new();
  stops.push("the");
  var ok = streq(pp_strip_punct("!!!...???,,,---"), "");
  if !streq(pp_collapse_ws("!?\t"), "!?") { ok = false; }
  if !streq(pp_normalize_default("!!!"), "") { ok = false; }
  if pp_word_count(pp_strip_punct("...,,,")) != 0 { ok = false; }
  if !streq(pp_pipeline("!!!...", &stops, true, true, true, true), "") { ok = false; }
  if !streq(pp_remove_stopwords("!!! ...", &stops), "!!! ...") { ok = false; }
  return assert(ok, "punctuation-only input is emptied, nothing crashes");
}

fn t21() -> TestResult {
  var stops = Vec[Str].new();
  stops.push("a");
  var ok = streq(pp_pipeline("A, B", &stops, true, true, true, true), "b");
  if !streq(pp_pipeline("A, B", &stops, true, false, false, true), "a, b") { ok = false; }
  if !streq(pp_pipeline("A, B", &stops, true, true, true, false), "a b") { ok = false; }
  return assert(ok, "pipeline: fixed order fold->punct->ws->stopwords");
}

fn main() -> Int {
  io.println("=== xiom.preprocess conformance tests ===");
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
    io.println("xiom.preprocess: all tests passed");
  } else {
    io.println("xiom.preprocess: tests failed");
  }
  return failed;
}
