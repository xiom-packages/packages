// XIOM -- xiom.tokenizer conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.tokenizer module against its SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module tokenizer_tests
use xiom.io; use xiom.test; use xiom.tokenizer;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every element check
// below is routed through streq/vec_eq instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn vec_eq(got: &Vec[Str], want: &Vec[Str]) -> Bool {
  if got.len() != want.len() { return false; }
  var i = 0;
  while i < got.len() {
    if !streq(got[i], want[i]) { return false; }
    i = i + 1;
  }
  return true;
}

fn t1() -> TestResult {
  var got = tokenize_words("Hello, world!");
  var want = Vec[Str].new();
  want.push("Hello");
  want.push("world");
  return assert(vec_eq(&got, &want), "words: split on punctuation and space");
}

fn t2() -> TestResult {
  var got = tokenize_words("a.b,c;d:e / (f)");
  var want = Vec[Str].new();
  want.push("a");
  want.push("b");
  want.push("c");
  want.push("d");
  want.push("e");
  want.push("f");
  return assert(vec_eq(&got, &want), "words: every non-word byte is a separator");
}

fn t3() -> TestResult {
  var got = tokenize_words("var_name2 3x4 x_y_z");
  var want = Vec[Str].new();
  want.push("var_name2");
  want.push("3x4");
  want.push("x_y_z");
  return assert(vec_eq(&got, &want), "words: digits and underscores are kept");
}

fn t4() -> TestResult {
  var got = tokenize_words("don't isn't it's");
  var want = Vec[Str].new();
  want.push("don't");
  want.push("isn't");
  want.push("it's");
  return assert(vec_eq(&got, &want), "words: apostrophe between word bytes is kept");
}

fn t5() -> TestResult {
  var edges = tokenize_words("'tis cats' ''quoted''");
  var want = Vec[Str].new();
  want.push("tis");
  want.push("cats");
  want.push("quoted");
  var ok = vec_eq(&edges, &want);
  var doubled = tokenize_words("don''t");
  var want2 = Vec[Str].new();
  want2.push("don");
  want2.push("t");
  if !vec_eq(&doubled, &want2) { ok = false; }
  return assert(ok, "words: apostrophes at edges and doubled apostrophes separate");
}

fn t6() -> TestResult {
  var got = tokenize_words("  ...one,,,two---  ");
  var want = Vec[Str].new();
  want.push("one");
  want.push("two");
  return assert(vec_eq(&got, &want), "words: leading, trailing and repeated separators collapse");
}

fn t7() -> TestResult {
  var got = tokenize_words("");
  var ok = got.len() == 0;
  if tokenize_count_words("") != 0 { ok = false; }
  return assert(ok, "words: empty text yields no tokens");
}

fn t8() -> TestResult {
  var ws = tokenize_words(" \t\n ");
  var ok = ws.len() == 0;
  var punct = tokenize_words("!!!...???,,,---");
  if punct.len() != 0 { ok = false; }
  return assert(ok, "words: whitespace-only and punctuation-only text yield nothing");
}

fn t9() -> TestResult {
  var cafe = tokenize_words("café");
  var want = Vec[Str].new();
  want.push("caf");
  var ok = vec_eq(&cafe, &want);
  var naive = tokenize_words("naïve");
  var want2 = Vec[Str].new();
  want2.push("na");
  want2.push("ve");
  if !vec_eq(&naive, &want2) { ok = false; }
  var cjk = tokenize_words("中文");
  if cjk.len() != 0 { ok = false; }
  var dash = tokenize_words("a—b");
  var want3 = Vec[Str].new();
  want3.push("a");
  want3.push("b");
  if !vec_eq(&dash, &want3) { ok = false; }
  return assert(ok, "words: non-ASCII bytes act as separators");
}

fn t10() -> TestResult {
  var got = tokenize_lines("a\nb\nc");
  var want = Vec[Str].new();
  want.push("a");
  want.push("b");
  want.push("c");
  return assert(vec_eq(&got, &want), "lines: split on LF");
}

fn t11() -> TestResult {
  var got = tokenize_lines("a\r\nb\r\nc");
  var want = Vec[Str].new();
  want.push("a");
  want.push("b");
  want.push("c");
  var ok = vec_eq(&got, &want);
  var lone = tokenize_lines("a\rb");
  var want2 = Vec[Str].new();
  want2.push("a\rb");
  if !vec_eq(&lone, &want2) { ok = false; }
  return assert(ok, "lines: CRLF normalizes, lone CR is kept");
}

fn t12() -> TestResult {
  var got = tokenize_lines("a\nb\n");
  var want = Vec[Str].new();
  want.push("a");
  want.push("b");
  var ok = vec_eq(&got, &want);
  var one = tokenize_lines("a\n");
  var want2 = Vec[Str].new();
  want2.push("a");
  if !vec_eq(&one, &want2) { ok = false; }
  return assert(ok, "lines: a trailing newline adds no empty line");
}

fn t13() -> TestResult {
  var none = tokenize_lines("");
  var ok = none.len() == 0;
  var blank = tokenize_lines("\n");
  var want = Vec[Str].new();
  want.push("");
  if !vec_eq(&blank, &want) { ok = false; }
  var middle = tokenize_lines("a\n\nb");
  var want2 = Vec[Str].new();
  want2.push("a");
  want2.push("");
  want2.push("b");
  if !vec_eq(&middle, &want2) { ok = false; }
  var tail = tokenize_lines("a\n\n");
  var want3 = Vec[Str].new();
  want3.push("a");
  want3.push("");
  if !vec_eq(&tail, &want3) { ok = false; }
  return assert(ok, "lines: empty text has no lines, blank lines are kept");
}

fn t14() -> TestResult {
  var got = tokenize_sentences("One. Two! Three?");
  var want = Vec[Str].new();
  want.push("One.");
  want.push("Two!");
  want.push("Three?");
  return assert(vec_eq(&got, &want), "sentences: split after . ! ?");
}

fn t15() -> TestResult {
  var got = tokenize_sentences("  Hello.  ");
  var want = Vec[Str].new();
  want.push("Hello.");
  var ok = vec_eq(&got, &want);
  var spaced = tokenize_sentences("Hi.  Bye.");
  var want2 = Vec[Str].new();
  want2.push("Hi.");
  want2.push("Bye.");
  if !vec_eq(&spaced, &want2) { ok = false; }
  return assert(ok, "sentences: outer whitespace is trimmed, inner runs split once");
}

fn t16() -> TestResult {
  var plain = tokenize_sentences("just some words");
  var want = Vec[Str].new();
  want.push("just some words");
  var ok = vec_eq(&plain, &want);
  var end = tokenize_sentences("End.");
  var want2 = Vec[Str].new();
  want2.push("End.");
  if !vec_eq(&end, &want2) { ok = false; }
  var dot = tokenize_sentences(".");
  var want3 = Vec[Str].new();
  want3.push(".");
  if !vec_eq(&dot, &want3) { ok = false; }
  return assert(ok, "sentences: no terminator is one sentence, end terminator included");
}

fn t17() -> TestResult {
  var joined = tokenize_sentences("a.b c");
  var want = Vec[Str].new();
  want.push("a.b c");
  var ok = vec_eq(&joined, &want);
  var ellipsis = tokenize_sentences("Wait... what?");
  var want2 = Vec[Str].new();
  want2.push("Wait...");
  want2.push("what?");
  if !vec_eq(&ellipsis, &want2) { ok = false; }
  return assert(ok, "sentences: terminator needs whitespace or end to split");
}

fn t18() -> TestResult {
  var got = tokenize_sentences("Hello, world. Bye.");
  var want = Vec[Str].new();
  want.push("Hello, world.");
  want.push("Bye.");
  var ok = vec_eq(&got, &want);
  var crlf = tokenize_sentences("One.\r\nTwo.");
  var want2 = Vec[Str].new();
  want2.push("One.");
  want2.push("Two.");
  if !vec_eq(&crlf, &want2) { ok = false; }
  return assert(ok, "sentences: interior punctuation and CRLF whitespace are handled");
}

fn t19() -> TestResult {
  var none = tokenize_sentences("");
  var ok = none.len() == 0;
  var ws = tokenize_sentences("   \t ");
  if ws.len() != 0 { ok = false; }
  return assert(ok, "sentences: empty and whitespace-only text yield nothing");
}

fn t20() -> TestResult {
  var words = Vec[Str].new();
  words.push("a");
  words.push("b");
  words.push("c");
  words.push("d");
  var got = tokenize_ngrams(&words, 2);
  var want = Vec[Str].new();
  want.push("a b");
  want.push("b c");
  want.push("c d");
  return assert(vec_eq(&got, &want), "ngrams: n = 2 slides over the words");
}

fn t21() -> TestResult {
  var words = Vec[Str].new();
  words.push("a");
  words.push("b");
  words.push("c");
  words.push("d");
  var uni = tokenize_ngrams(&words, 1);
  var want = Vec[Str].new();
  want.push("a");
  want.push("b");
  want.push("c");
  want.push("d");
  var ok = vec_eq(&uni, &want);
  var tri = tokenize_ngrams(&words, 3);
  var want2 = Vec[Str].new();
  want2.push("a b c");
  want2.push("b c d");
  if !vec_eq(&tri, &want2) { ok = false; }
  return assert(ok, "ngrams: n = 1 returns the words, n = 3 joins triples");
}

fn t22() -> TestResult {
  var words = Vec[Str].new();
  words.push("a");
  words.push("b");
  words.push("c");
  words.push("d");
  var big = tokenize_ngrams(&words, 5);
  var ok = big.len() == 0;
  var zero = tokenize_ngrams(&words, 0);
  if zero.len() != 0 { ok = false; }
  var negative = tokenize_ngrams(&words, -1);
  if negative.len() != 0 { ok = false; }
  var empty = Vec[Str].new();
  var none = tokenize_ngrams(&empty, 1);
  if none.len() != 0 { ok = false; }
  return assert(ok, "ngrams: too few words or n < 1 yield nothing");
}

fn t23() -> TestResult {
  var ok = tokenize_count_words("Hello, world!") == 2;
  if tokenize_count_words("don't stop") != 2 { ok = false; }
  if tokenize_count_words("  ...  ") != 0 { ok = false; }
  if tokenize_count_words("a_b 3") != 2 { ok = false; }
  if tokenize_count_words("") != 0 { ok = false; }
  return assert(ok, "count_words: counts tokenize_words tokens");
}

fn t24() -> TestResult {
  var tokens = tokenize_words("the quick brown fox");
  var got = tokenize_ngrams(&tokens, 2);
  var want = Vec[Str].new();
  want.push("the quick");
  want.push("quick brown");
  want.push("brown fox");
  return assert(vec_eq(&got, &want), "ngrams: pipelines from tokenize_words output");
}

fn main() -> Int {
  io.println("=== xiom.tokenizer conformance tests ===");
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
    io.println("xiom.tokenizer: all tests passed");
  } else {
    io.println("xiom.tokenizer: tests failed");
  }
  return failed;
}
