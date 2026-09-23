// XIOM -- xiom.summary conformance tests (23 checks)
// Port task: prove the pure-XIOM xiom.summary module against its SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module summary_tests
use xiom.io; use xiom.test; use xiom.summary;
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

fn ints_eq(got: &Vec[Int], want: &Vec[Int]) -> Bool {
  if got.len() != want.len() { return false; }
  var i = 0;
  while i < got.len() {
    let a: Int = got[i];
    let b: Int = want[i];
    if a != b { return false; }
    i = i + 1;
  }
  return true;
}

fn t1() -> TestResult {
  var got = summary_sentences("One. Two! Three?");
  var want = Vec[Str].new();
  want.push("One.");
  want.push("Two!");
  want.push("Three?");
  return assert(vec_eq(&got, &want), "sentences: split after . ! ?");
}

fn t2() -> TestResult {
  var got = summary_sentences("  Hello, world.  Bye.  ");
  var want = Vec[Str].new();
  want.push("Hello, world.");
  want.push("Bye.");
  var ok = vec_eq(&got, &want);
  var nosplit = summary_sentences("a.b c");
  var want2 = Vec[Str].new();
  want2.push("a.b c");
  if !vec_eq(&nosplit, &want2) { ok = false; }
  var plain = summary_sentences("just some words");
  var want3 = Vec[Str].new();
  want3.push("just some words");
  if !vec_eq(&plain, &want3) { ok = false; }
  return assert(ok, "sentences: trimmed, interior punctuation kept, a.b does not split");
}

fn t3() -> TestResult {
  var ok = summary_sentences("").len() == 0;
  if summary_sentences("   \t ").len() != 0 { ok = false; }
  return assert(ok, "sentences: empty and whitespace-only text yield nothing");
}

fn t4() -> TestResult {
  var got = summary_words("Hello WORLD MixEd");
  var want = Vec[Str].new();
  want.push("hello");
  want.push("world");
  want.push("mixed");
  return assert(vec_eq(&got, &want), "words: A-Z folded to a-z by the module's own fold");
}

fn t5() -> TestResult {
  var got = summary_words("abc123 42 x9y a_b");
  var want = Vec[Str].new();
  want.push("abc123");
  want.push("42");
  want.push("x9y");
  want.push("a");
  want.push("b");
  return assert(vec_eq(&got, &want), "words: letters and digits stay, underscore splits");
}

fn t6() -> TestResult {
  var cafe = summary_words("café");
  var want = Vec[Str].new();
  want.push("caf");
  var ok = vec_eq(&cafe, &want);
  var naive = summary_words("naïve");
  var want2 = Vec[Str].new();
  want2.push("na");
  want2.push("ve");
  if !vec_eq(&naive, &want2) { ok = false; }
  var dash = summary_words("a—b");
  var want3 = Vec[Str].new();
  want3.push("a");
  want3.push("b");
  if !vec_eq(&dash, &want3) { ok = false; }
  var cjk = summary_words("中文");
  if cjk.len() != 0 { ok = false; }
  return assert(ok, "words: non-ASCII bytes act as separators");
}

fn t7() -> TestResult {
  var ok = summary_words("").len() == 0;
  if summary_words("!!!...,,,").len() != 0 { ok = false; }
  if summary_words(" \t\n ").len() != 0 { ok = false; }
  return assert(ok, "words: empty and separator-only text yield nothing");
}

fn t8() -> TestResult {
  var stop = summary_stopwords();
  var ok = stop.len() == 30;
  var i = 0;
  while i + 1 < stop.len() {
    if compare.str_compare(stop[i], stop[i + 1]) >= 0 { ok = false; }
    i = i + 1;
  }
  if !streq(stop[0], "a") { ok = false; }
  if !streq(stop[stop.len() - 1], "with") { ok = false; }
  return assert(ok, "stopwords: 30 entries, strictly ascending");
}

fn t9() -> TestResult {
  var stop = summary_stopwords();
  var ok = summary_is_stopword("the", &stop);
  if !summary_is_stopword("The", &stop) { ok = false; }
  if !summary_is_stopword("AND", &stop) { ok = false; }
  if summary_is_stopword("computer", &stop) { ok = false; }
  if summary_is_stopword("", &stop) { ok = false; }
  if summary_is_stopword("thes", &stop) { ok = false; }
  return assert(ok, "is_stopword: true for stopwords in any case, false otherwise");
}

fn t10() -> TestResult {
  var stop = Vec[Str].new();
  var words = summary_words("b a b c a");
  var got = summary_unique_words(&words, &stop);
  var want = Vec[Str].new();
  want.push("b");
  want.push("a");
  want.push("c");
  return assert(vec_eq(&got, &want), "unique: deduplicated in first-seen order");
}

fn t11() -> TestResult {
  var stop = summary_stopwords();
  var words = summary_words("The cat and the dog");
  var got = summary_unique_words(&words, &stop);
  var want = Vec[Str].new();
  want.push("cat");
  want.push("dog");
  return assert(vec_eq(&got, &want), "unique: stopwords are excluded");
}

fn t12() -> TestResult {
  var stop = Vec[Str].new();
  var words = summary_words("b a b c a b");
  var unique = summary_unique_words(&words, &stop);
  var freqs = summary_word_frequencies(&words, &stop);
  var want_unique = Vec[Str].new();
  want_unique.push("b");
  want_unique.push("a");
  want_unique.push("c");
  var want_freqs = Vec[Int].new();
  want_freqs.push(3);
  want_freqs.push(2);
  want_freqs.push(1);
  var ok = vec_eq(&unique, &want_unique);
  if !ints_eq(&freqs, &want_freqs) { ok = false; }
  if freqs.len() != unique.len() { ok = false; }
  return assert(ok, "frequencies: parallel to unique, in first-seen order");
}

fn t13() -> TestResult {
  var stop = summary_stopwords();
  var words = summary_words("the cat the dog the");
  var unique = summary_unique_words(&words, &stop);
  var freqs = summary_word_frequencies(&words, &stop);
  var want_unique = Vec[Str].new();
  want_unique.push("cat");
  want_unique.push("dog");
  var want_freqs = Vec[Int].new();
  want_freqs.push(1);
  want_freqs.push(1);
  var ok = vec_eq(&unique, &want_unique);
  if !ints_eq(&freqs, &want_freqs) { ok = false; }
  return assert(ok, "frequencies: stopwords are never counted");
}

fn t14() -> TestResult {
  var unique = Vec[Str].new();
  unique.push("cat");
  unique.push("dog");
  unique.push("bird");
  var freqs = Vec[Int].new();
  freqs.push(3);
  freqs.push(2);
  freqs.push(1);
  var stop = Vec[Str].new();
  var ok = summary_sentence_score("cat dog", &unique, &freqs, &stop) == 5;
  if summary_sentence_score("bird", &unique, &freqs, &stop) != 1 { ok = false; }
  if summary_sentence_score("absent", &unique, &freqs, &stop) != 0 { ok = false; }
  if summary_sentence_score("", &unique, &freqs, &stop) != 0 { ok = false; }
  return assert(ok, "score: sums the frequencies of the sentence's words");
}

fn t15() -> TestResult {
  var stop = summary_stopwords();
  var unique = Vec[Str].new();
  unique.push("cat");
  var freqs = Vec[Int].new();
  freqs.push(2);
  var ok = summary_sentence_score("the cat and the cat", &unique, &freqs, &stop) == 4;
  if summary_sentence_score("the and of", &unique, &freqs, &stop) != 0 { ok = false; }
  if summary_sentence_score("... !!!", &unique, &freqs, &stop) != 0 { ok = false; }
  return assert(ok, "score: stopwords and non-words contribute nothing");
}

fn t16() -> TestResult {
  var text = "Cats are great. The cat sat on the mat with cats. Dogs bark.";
  var got = summary_extract(text, 1);
  var want = Vec[Str].new();
  want.push("The cat sat on the mat with cats.");
  return assert(vec_eq(&got, &want), "extract: picks the highest-scoring sentence");
}

fn t17() -> TestResult {
  var text = "Dogs bark. Cats are great. The cat sat on the mat with cats.";
  var got = summary_extract(text, 2);
  var want = Vec[Str].new();
  want.push("Cats are great.");
  want.push("The cat sat on the mat with cats.");
  return assert(vec_eq(&got, &want), "extract: selected sentences keep original order");
}

fn t18() -> TestResult {
  var got = summary_extract("Alpha beta. Gamma delta.", 1);
  var want = Vec[Str].new();
  want.push("Alpha beta.");
  var ok = vec_eq(&got, &want);
  var zeros = summary_extract("Red blue. Green gold. White black.", 2);
  var want2 = Vec[Str].new();
  want2.push("Red blue.");
  want2.push("Green gold.");
  if !vec_eq(&zeros, &want2) { ok = false; }
  return assert(ok, "extract: ties keep the earlier sentence");
}

fn t19() -> TestResult {
  var got = summary_extract("One. Two.", 5);
  var want = Vec[Str].new();
  want.push("One.");
  want.push("Two.");
  var ok = vec_eq(&got, &want);
  if got.len() != 2 { ok = false; }
  return assert(ok, "extract: fewer sentences than max returns all, in order");
}

fn t20() -> TestResult {
  var ok = summary_extract("One. Two.", 0).len() == 0;
  if summary_extract("One. Two.", -3).len() != 0 { ok = false; }
  if summary_extract("", 3).len() != 0 { ok = false; }
  if summary_extract("   \t ", 3).len() != 0 { ok = false; }
  return assert(ok, "extract: empty for max <= 0 and for empty text");
}

fn t21() -> TestResult {
  var text = "One. Two.";
  var ok = streq(summary_extract_text(text, 2), "One. Two.");
  if !streq(summary_extract_text(text, 1), "One.") { ok = false; }
  if !streq(summary_extract_text("", 2), "") { ok = false; }
  var ranked = "Cats are great. The cat sat on the mat with cats. Dogs bark.";
  if !streq(summary_extract_text(ranked, 2), "Cats are great. The cat sat on the mat with cats.") { ok = false; }
  return assert(ok, "extract_text: joins selected sentences with single spaces");
}

fn t22() -> TestResult {
  var text = "Cats are great. The cat sat on the mat with cats. Dogs bark.";
  var a = summary_extract(text, 2);
  var b = summary_extract(text, 2);
  var ok = vec_eq(&a, &b);
  var wa = summary_words(text);
  var wb = summary_words(text);
  if !vec_eq(&wa, &wb) { ok = false; }
  if !streq(summary_extract_text(text, 3), summary_extract_text(text, 3)) { ok = false; }
  return assert(ok, "determinism: same input twice yields the same output");
}

fn t23() -> TestResult {
  var words = summary_words("... !!! ,,,");
  var ok = words.len() == 0;
  var sentences = summary_sentences("...!!!");
  var want = Vec[Str].new();
  want.push("...!!!");
  if !vec_eq(&sentences, &want) { ok = false; }
  var extracted = summary_extract("...!!!", 2);
  if !vec_eq(&extracted, &want) { ok = false; }
  if summary_extract("...!!!", 0).len() != 0 { ok = false; }
  return assert(ok, "punctuation-only text has no words and is its own sentence");
}

fn main() -> Int {
  io.println("=== xiom.summary conformance tests ===");
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
    io.println("xiom.summary: all tests passed");
  } else {
    io.println("xiom.summary: tests failed");
  }
  return failed;
}
