// XIOM -- xiom.sentiment conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.sentiment module against its SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module sentiment_tests
use xiom.io; use xiom.test; use xiom.sentiment;
use xiom.string; use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every element check
// below is routed through streq/vec_eq instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return str_compare(a, b) == 0;
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

fn vec1(a: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  return v;
}

fn vec2(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}

fn vec3(a: Str, b: Str, c: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn vec4(a: Str, b: Str, c: Str, d: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

fn vec8(a: Str, b: Str, c: Str, d: Str, e: Str, f: Str, g: Str, h: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  v.push(g);
  v.push(h);
  return v;
}

fn vec6(a: Str, b: Str, c: Str, d: Str, e: Str, f: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  v.push(f);
  return v;
}

fn has_word(lex: &Vec[Str], word: Str) -> Bool {
  var i = 0;
  while i < lex.len() {
    if streq(lex[i], word) { return true; }
    i = i + 1;
  }
  return false;
}

fn sorted_asc(v: &Vec[Str]) -> Bool {
  var i = 1;
  while i < v.len() {
    if str_compare(v[i - 1], v[i]) > 0 { return false; }
    i = i + 1;
  }
  return true;
}

fn unique_words(v: &Vec[Str]) -> Bool {
  var i = 0;
  while i < v.len() {
    var j = i + 1;
    while j < v.len() {
      if streq(v[i], v[j]) { return false; }
      j = j + 1;
    }
    i = i + 1;
  }
  return true;
}

fn lowercase_words(v: &Vec[Str]) -> Bool {
  var i = 0;
  while i < v.len() {
    let w: Str = v[i];
    if !streq(w, str_lower(w)) { return false; }
    i = i + 1;
  }
  return true;
}

fn disjoint(a: &Vec[Str], b: &Vec[Str]) -> Bool {
  var i = 0;
  while i < a.len() {
    if has_word(b, a[i]) { return false; }
    i = i + 1;
  }
  return true;
}

fn counts_are(text: Str, want_pos: Int, want_neg: Int, want_negations: Int) -> Bool {
  let (pos_hits, neg_hits, negations) = sentiment_counts(text);
  if pos_hits != want_pos { return false; }
  if neg_hits != want_neg { return false; }
  if negations != want_negations { return false; }
  return true;
}

fn t1() -> TestResult {
  let p = sentiment_positive_words();
  var ok = p.len() >= 30;
  if !sorted_asc(&p) { ok = false; }
  if !unique_words(&p) { ok = false; }
  if !lowercase_words(&p) { ok = false; }
  if !has_word(&p, "good") { ok = false; }
  if !has_word(&p, "great") { ok = false; }
  if !has_word(&p, "love") { ok = false; }
  if !has_word(&p, "wonderful") { ok = false; }
  return assert(ok, "positive lexicon: >= 30 lowercase, sorted, unique entries");
}

fn t2() -> TestResult {
  let n = sentiment_negative_words();
  var ok = n.len() >= 30;
  if !sorted_asc(&n) { ok = false; }
  if !unique_words(&n) { ok = false; }
  if !lowercase_words(&n) { ok = false; }
  if !has_word(&n, "bad") { ok = false; }
  if !has_word(&n, "terrible") { ok = false; }
  if !has_word(&n, "awful") { ok = false; }
  if !has_word(&n, "worst") { ok = false; }
  return assert(ok, "negative lexicon: >= 30 lowercase, sorted, unique entries");
}

fn t3() -> TestResult {
  let g = sentiment_negators();
  let want = vec8("barely", "hardly", "neither", "never", "no", "nor", "not", "without");
  var ok = g.len() >= 8;
  if !sorted_asc(&g) { ok = false; }
  if !unique_words(&g) { ok = false; }
  if !lowercase_words(&g) { ok = false; }
  if !has_word(&g, "barely") { ok = false; }
  if !has_word(&g, "hardly") { ok = false; }
  if !has_word(&g, "neither") { ok = false; }
  if !has_word(&g, "never") { ok = false; }
  if !has_word(&g, "no") { ok = false; }
  if !has_word(&g, "nor") { ok = false; }
  if !has_word(&g, "not") { ok = false; }
  if !has_word(&g, "without") { ok = false; }
  if !vec_eq(&g, &want) { ok = false; }
  return assert(ok, "negators: the 8 documented lowercase entries, sorted");
}

fn t4() -> TestResult {
  let p = sentiment_positive_words();
  let n = sentiment_negative_words();
  let g = sentiment_negators();
  var ok = p.len() >= 30;
  if n.len() < 30 { ok = false; }
  if g.len() < 8 { ok = false; }
  if !disjoint(&p, &n) { ok = false; }
  if !disjoint(&p, &g) { ok = false; }
  if !disjoint(&n, &g) { ok = false; }
  return assert(ok, "positive, negative and negator lexicons are pairwise disjoint");
}

fn t5() -> TestResult {
  let got = sentiment_words("Good GREAT bAd");
  let want = vec3("good", "great", "bad");
  return assert(vec_eq(&got, &want), "words: ASCII case folds to lowercase");
}

fn t6() -> TestResult {
  let got = sentiment_words("Well, this is 10/10 -- nice!");
  let want = vec6("well", "this", "is", "10", "10", "nice");
  return assert(vec_eq(&got, &want), "words: punctuation separates, digits are kept");
}

fn t7() -> TestResult {
  let naive = sentiment_words("naïve café");
  let want = vec3("na", "ve", "caf");
  var ok = vec_eq(&naive, &want);
  let cjk = sentiment_words("中文");
  if cjk.len() != 0 { ok = false; }
  let dashes = sentiment_words("a—b");
  let want2 = vec2("a", "b");
  if !vec_eq(&dashes, &want2) { ok = false; }
  let seps = sentiment_words("don't stop_now");
  let want3 = vec4("don", "t", "stop", "now");
  if !vec_eq(&seps, &want3) { ok = false; }
  return assert(ok, "words: non-ASCII bytes, apostrophes and underscores separate");
}

fn t8() -> TestResult {
  let none = sentiment_words("");
  var ok = none.len() == 0;
  let punct = sentiment_words(" ...!? ");
  if punct.len() != 0 { ok = false; }
  if sentiment_score("") != 0 { ok = false; }
  if !counts_are("", 0, 0, 0) { ok = false; }
  if !streq(sentiment_label_text(""), "neutral") { ok = false; }
  return assert(ok, "empty and separator-only text: no words, score 0, neutral");
}

fn t9() -> TestResult {
  let text = "I love this great and wonderful book";
  var ok = sentiment_score(text) == 3;
  if !counts_are(text, 3, 0, 0) { ok = false; }
  if !streq(sentiment_label_text(text), "positive") { ok = false; }
  return assert(ok, "positive-only text scores +1 per positive word");
}

fn t10() -> TestResult {
  let text = "This awful terrible movie is boring";
  var ok = sentiment_score(text) == -3;
  if !counts_are(text, 0, 3, 0) { ok = false; }
  if !streq(sentiment_label_text(text), "negative") { ok = false; }
  return assert(ok, "negative-only text scores -1 per negative word");
}

fn t11() -> TestResult {
  let text = "the cat sat on the mat";
  var ok = sentiment_score(text) == 0;
  if !counts_are(text, 0, 0, 0) { ok = false; }
  if !streq(sentiment_label(sentiment_score(text)), "neutral") { ok = false; }
  if !streq(sentiment_label_text(text), "neutral") { ok = false; }
  return assert(ok, "text without lexicon words scores 0 and is neutral");
}

fn t12() -> TestResult {
  let text = "good good bad";
  var ok = sentiment_score(text) == 1;
  if !counts_are(text, 2, 1, 0) { ok = false; }
  if !streq(sentiment_label_text(text), "positive") { ok = false; }
  let even = sentiment_score("good bad");
  if even != 0 { ok = false; }
  return assert(ok, "mixed text sums the signed contributions");
}

fn t13() -> TestResult {
  let text = "I love this great book but it has a terrible plot";
  var ok = sentiment_score(text) == 1;
  if !counts_are(text, 2, 1, 0) { ok = false; }
  if !streq(sentiment_label_text(text), "positive") { ok = false; }
  return assert(ok, "mixed sentence: love + great - terrible == +1");
}

fn t14() -> TestResult {
  var ok = streq(sentiment_label(-3), "negative");
  if !streq(sentiment_label(-1), "negative") { ok = false; }
  if !streq(sentiment_label(0), "neutral") { ok = false; }
  if !streq(sentiment_label(1), "positive") { ok = false; }
  if !streq(sentiment_label(7), "positive") { ok = false; }
  return assert(ok, "label thresholds: <0 negative, 0 neutral, >0 positive");
}

fn t15() -> TestResult {
  var ok = streq(sentiment_label_text("great"), "positive");
  if !streq(sentiment_label_text("terrible"), "negative") { ok = false; }
  if !streq(sentiment_label_text("the cat sat"), "neutral") { ok = false; }
  if !streq(sentiment_label_text("great bad"), "neutral") { ok = false; }
  return assert(ok, "label_text maps the score of the text");
}

fn t16() -> TestResult {
  var ok = sentiment_score("not good") == -1;
  if !counts_are("not good", 1, 0, 1) { ok = false; }
  if !streq(sentiment_label_text("this is not good"), "negative") { ok = false; }
  return assert(ok, "not good: one negation flips the positive to negative");
}

fn t17() -> TestResult {
  var ok = sentiment_score("not bad") == 1;
  if !counts_are("not bad", 0, 1, 1) { ok = false; }
  if !streq(sentiment_label_text("this is not bad"), "positive") { ok = false; }
  return assert(ok, "not bad: one negation flips the negative to positive");
}

fn t18() -> TestResult {
  var ok = sentiment_score("not good") == -1;
  if sentiment_score("not very good") != -1 { ok = false; }
  if sentiment_score("no the cat good") != -1 { ok = false; }
  if !counts_are("no the cat good", 1, 0, 1) { ok = false; }
  return assert(ok, "negator up to three words before the polarity word applies");
}

fn t19() -> TestResult {
  var ok = sentiment_score("not a very very good") == 1;
  if sentiment_score("no the cat sat good") != 1 { ok = false; }
  if !counts_are("no the cat sat good", 1, 0, 0) { ok = false; }
  if sentiment_score("without any serious doubt terrible") != -1 { ok = false; }
  return assert(ok, "negator four or more words before does not apply");
}

fn t20() -> TestResult {
  var ok = sentiment_score("not never no good") == -1;
  if !counts_are("not never no good", 1, 0, 1) { ok = false; }
  if sentiment_score("not never bad") != 1 { ok = false; }
  if sentiment_score("not never no bad") != 1 { ok = false; }
  return assert(ok, "multiple negators in the window do not stack");
}

fn t21() -> TestResult {
  var ok = sentiment_score("NOT GOOD") == -1;
  if sentiment_score("Great") != 1 { ok = false; }
  if sentiment_score("No Bad") != 1 { ok = false; }
  if !streq(sentiment_label_text("GREAT"), "positive") { ok = false; }
  let got = sentiment_words("Not GOOD");
  let want = vec2("not", "good");
  if !vec_eq(&got, &want) { ok = false; }
  return assert(ok, "scoring and scanning are case-insensitive");
}

fn t22() -> TestResult {
  var ok = sentiment_score("good, bad!") == 0;
  if sentiment_score("good-bad") != 0 { ok = false; }
  if sentiment_score("not, good") != -1 { ok = false; }
  let got = sentiment_words("(good).");
  let want = vec1("good");
  if !vec_eq(&got, &want) { ok = false; }
  return assert(ok, "punctuation separates words but not negators");
}

fn t23() -> TestResult {
  var ok = sentiment_score("good not terrible") == 2;
  if !counts_are("good not terrible", 1, 1, 1) { ok = false; }
  if !streq(sentiment_label_text("good not terrible"), "positive") { ok = false; }
  let window = sentiment_score("not good bad");
  if window != 0 { ok = false; }
  if !counts_are("not good bad", 1, 1, 2) { ok = false; }
  return assert(ok, "counts triple: hits before flipping, one negation per flip");
}

fn t24() -> TestResult {
  let text = "not very good but not bad either, and great terrible";
  let s1 = sentiment_score(text);
  let s2 = sentiment_score(text);
  let w1 = sentiment_words(text);
  let w2 = sentiment_words(text);
  let l1 = sentiment_label_text(text);
  let l2 = sentiment_label_text(text);
  let (a1, b1, g1) = sentiment_counts(text);
  let (a2, b2, g2) = sentiment_counts(text);
  var ok = s1 == s2;
  if !vec_eq(&w1, &w2) { ok = false; }
  if !streq(l1, l2) { ok = false; }
  if a1 != a2 { ok = false; }
  if b1 != b2 { ok = false; }
  if g1 != g2 { ok = false; }
  if s1 != sentiment_score(text) { ok = false; }
  return assert(ok, "scoring, scanning and labelling are deterministic");
}

fn main() -> Int {
  io.println("=== xiom.sentiment conformance tests ===");
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
    io.println("xiom.sentiment: all tests passed");
  } else {
    io.println("xiom.sentiment: tests failed");
  }
  return failed;
}
