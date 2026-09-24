// XIOM -- xiom.ngram conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.ngram module against its SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module ngram_tests
use xiom.io; use xiom.test; use xiom.ngram;
use xiom.string;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every element check
// below is routed through streq/vec_eq instead of `==`. Every Vec element
// read is pinned with a typed `let`.

fn streq(a: Str, b: Str) -> Bool {
  return str_compare(a, b) == 0;
}

fn vec_eq(got: &Vec[Str], want: &Vec[Str]) -> Bool {
  if got.len() != want.len() { return false; }
  var i = 0;
  while i < want.len() {
    let g: Str = got[i];
    let w: Str = want[i];
    if !streq(g, w) { return false; }
    i = i + 1;
  }
  return true;
}

fn ints_eq(got: &Vec[Int], want: &Vec[Int]) -> Bool {
  if got.len() != want.len() { return false; }
  var i = 0;
  while i < want.len() {
    let g: Int = got[i];
    let w: Int = want[i];
    if g != w { return false; }
    i = i + 1;
  }
  return true;
}

fn all_zeros(v: &Vec[Int]) -> Bool {
  var i = 0;
  while i < v.len() {
    let x: Int = v[i];
    if x != 0 { return false; }
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

fn vec5(a: Str, b: Str, c: Str, d: Str, e: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  return v;
}

// MinHash similarity of two texts through the full pipeline (2-word shingles,
// 32 slots, one fixed seed).
fn sim_of(a: Str, b: Str) -> Int {
  var wa = ngram_words(a);
  var wb = ngram_words(b);
  var sa = ngram_shingles(&wa, 2);
  var sb = ngram_shingles(&wb, 2);
  var ma = ngram_minhash_signature(&sa, 32, 12345);
  var mb = ngram_minhash_signature(&sb, 32, 12345);
  return ngram_signature_similarity(&ma, &mb);
}

fn t1() -> TestResult {
  var got = ngram_words("Hello, World!");
  var want = vec2("hello", "world");
  return assert(vec_eq(&got, &want), "words: scan and lowercase ASCII letters");
}

fn t2() -> TestResult {
  var got = ngram_words("var_name2 3x4 a_b");
  var want = vec5("var", "name2", "3x4", "a", "b");
  return assert(vec_eq(&got, &want), "words: underscore separates, digits are word bytes");
}

fn t3() -> TestResult {
  var cafe = ngram_words("café");
  var ok = vec_eq(&cafe, &vec1("caf"));
  var naive = ngram_words("naïve");
  if !vec_eq(&naive, &vec2("na", "ve")) { ok = false; }
  var cjk = ngram_words("中文");
  if cjk.len() != 0 { ok = false; }
  var dash = ngram_words("a—b");
  if !vec_eq(&dash, &vec2("a", "b")) { ok = false; }
  return assert(ok, "words: every non-ASCII byte is a separator");
}

fn t4() -> TestResult {
  var got = ngram_words("  ...one,,,two---  ");
  var ok = vec_eq(&got, &vec2("one", "two"));
  var empty = ngram_words("");
  if empty.len() != 0 { ok = false; }
  var punct = ngram_words("!!!...");
  if punct.len() != 0 { ok = false; }
  var digits = ngram_words("12 34x");
  if !vec_eq(&digits, &vec2("12", "34x")) { ok = false; }
  return assert(ok, "words: separator runs collapse, digit runs are tokens");
}

fn t5() -> TestResult {
  var words = ngram_words("The quick brown fox");
  var got = ngram_shingles(&words, 2);
  var ok = vec_eq(&got, &vec3("the quick", "quick brown", "brown fox"));
  if got.len() != 3 { ok = false; }
  return assert(ok, "shingles: bigrams of a known sentence");
}

fn t6() -> TestResult {
  var words = ngram_words("the quick brown fox");
  var one = ngram_shingles(&words, 1);
  var ok = vec_eq(&one, &words);
  var three = ngram_shingles(&words, 3);
  if !vec_eq(&three, &vec2("the quick brown", "quick brown fox")) { ok = false; }
  var four = ngram_shingles(&words, 4);
  if !vec_eq(&four, &vec1("the quick brown fox")) { ok = false; }
  return assert(ok, "shingles: n = 1, n = 3 and n = words.len()");
}

fn t7() -> TestResult {
  var words = ngram_words("the quick brown fox");
  var ok = ngram_shingles(&words, 5).len() == 0;
  if ngram_shingles(&words, 0).len() != 0 { ok = false; }
  if ngram_shingles(&words, -2).len() != 0 { ok = false; }
  var empty = Vec[Str].new();
  if ngram_shingles(&empty, 1).len() != 0 { ok = false; }
  if ngram_shingles(&empty, 3).len() != 0 { ok = false; }
  return assert(ok, "shingles: too few words or n < 1 yield nothing");
}

fn t8() -> TestResult {
  var two = ngram_char_shingles("abcde", 2);
  var ok = vec_eq(&two, &vec4("ab", "bc", "cd", "de"));
  var one = ngram_char_shingles("abcde", 1);
  if one.len() != 5 { ok = false; }
  var five = ngram_char_shingles("abcde", 5);
  if !vec_eq(&five, &vec1("abcde")) { ok = false; }
  if ngram_char_shingles("abcde", 6).len() != 0 { ok = false; }
  if ngram_char_shingles("abcde", 0).len() != 0 { ok = false; }
  if ngram_char_shingles("", 1).len() != 0 { ok = false; }
  return assert(ok, "char shingles: byte windows, exact counts and edges");
}

fn t9() -> TestResult {
  var text = "héllo";
  var got = ngram_char_shingles(text, 2);
  var ok = text.len() == 6;
  if got.len() != 5 { ok = false; }
  let first: Str = got[0];
  let expect_first = str_slice(text, 0, 2);
  if !streq(first, expect_first) { ok = false; }
  let last: Str = got[4];
  if !streq(last, "lo") { ok = false; }
  var i = 0;
  while i < got.len() {
    let s: Str = got[i];
    if s.len() != 2 { ok = false; }
    i = i + 1;
  }
  return assert(ok, "char shingles: UTF-8 slices are verbatim byte windows");
}

fn t10() -> TestResult {
  var src = Vec[Str].new();
  src.push("b"); src.push("a"); src.push("b"); src.push("c"); src.push("a"); src.push("b");
  var got = ngram_unique(&src);
  var ok = vec_eq(&got, &vec3("b", "a", "c"));
  var empty = Vec[Str].new();
  if ngram_unique(&empty).len() != 0 { ok = false; }
  var one = vec1("x");
  var one_out = ngram_unique(&one);
  if one_out.len() != 1 { ok = false; }
  let only: Str = one_out[0];
  if !streq(only, "x") { ok = false; }
  var dup = vec2("y", "y");
  if ngram_unique(&dup).len() != 1 { ok = false; }
  return assert(ok, "unique: first-seen order with duplicates collapsed");
}

fn t11() -> TestResult {
  var a = vec3("a", "b", "c");
  var b = vec3("a", "b", "c");
  var ok = ngram_jaccard(&a, &b) == 1000;
  var dup = vec5("a", "a", "b", "c", "b");
  if ngram_jaccard(&a, &dup) != 1000 { ok = false; }
  var e1 = Vec[Str].new();
  var e2 = Vec[Str].new();
  if ngram_jaccard(&e1, &e2) != 0 { ok = false; }
  return assert(ok, "jaccard: identical sets score 1000, empty pair scores 0");
}

fn t12() -> TestResult {
  var a = vec2("a", "b");
  var b = vec2("c", "d");
  var ok = ngram_jaccard(&a, &b) == 0;
  var e = Vec[Str].new();
  if ngram_jaccard(&a, &e) != 0 { ok = false; }
  if ngram_jaccard(&e, &a) != 0 { ok = false; }
  return assert(ok, "jaccard: disjoint or empty-side pairs score 0");
}

fn t13() -> TestResult {
  var a = vec4("a", "b", "c", "d");
  var b = vec4("c", "d", "e", "f");
  var ok = ngram_jaccard(&a, &b) == 333;
  var x = vec2("a", "b");
  var y = vec2("b", "c");
  if ngram_jaccard(&x, &y) != 333 { ok = false; }
  var s = vec3("a", "b", "c");
  var t = vec4("a", "b", "c", "d");
  if ngram_jaccard(&s, &t) != 750 { ok = false; }
  if ngram_jaccard(&a, &b) != ngram_jaccard(&b, &a) { ok = false; }
  return assert(ok, "jaccard: half and bounded overlaps pinned in permille");
}

fn t14() -> TestResult {
  var a = vec3("a", "b", "c");
  var b = vec3("a", "b", "c");
  var ok = ngram_dice(&a, &b) == 1000;
  var x = vec4("a", "b", "c", "d");
  var y = vec4("c", "d", "e", "f");
  if ngram_dice(&x, &y) != 500 { ok = false; }
  var p = vec2("a", "b");
  var q = vec2("b", "c");
  if ngram_dice(&p, &q) != 500 { ok = false; }
  return assert(ok, "dice: identical 1000, half overlap 500");
}

fn t15() -> TestResult {
  var one = vec1("a");
  var two = vec2("a", "b");
  var ok = ngram_dice(&one, &two) == 666;
  var e1 = Vec[Str].new();
  var e2 = Vec[Str].new();
  if ngram_dice(&e1, &e2) != 0 { ok = false; }
  if ngram_dice(&one, &e1) != 0 { ok = false; }
  var c = vec2("c", "c");
  if ngram_dice(&c, &one) != 0 { ok = false; }
  return assert(ok, "dice: subset pinned, empty and disjoint cases score 0");
}

fn t16() -> TestResult {
  var empty = Vec[Str].new();
  var zeros = ngram_minhash_signature(&empty, 8, 42);
  var ok = zeros.len() == 8;
  if !all_zeros(&zeros) { ok = false; }
  var one = ngram_minhash_signature(&empty, 1, 0);
  if one.len() != 1 { ok = false; }
  let z: Int = one[0];
  if z != 0 { ok = false; }
  var none = ngram_minhash_signature(&empty, 0, 7);
  if none.len() != 0 { ok = false; }
  return assert(ok, "minhash: empty shingles give a zero signature of length hashes");
}

fn t17() -> TestResult {
  var words = ngram_words("the quick brown fox jumps over the lazy dog");
  var shingles = ngram_shingles(&words, 2);
  var a = ngram_minhash_signature(&shingles, 16, 7);
  var b = ngram_minhash_signature(&shingles, 16, 7);
  var ok = ints_eq(&a, &b);
  if a.len() != 16 { ok = false; }
  var c = ngram_minhash_signature(&shingles, 16, 8);
  if ints_eq(&a, &c) { ok = false; }
  var d = ngram_minhash_signature(&shingles, 4, 7);
  if d.len() != 4 { ok = false; }
  return assert(ok, "minhash: deterministic per (seed, hashes) and seed-sensitive");
}

fn t18() -> TestResult {
  var words = ngram_words("Alpha beta gamma delta epsilon zeta");
  var shingles = ngram_shingles(&words, 3);
  var sig = ngram_minhash_signature(&shingles, 12, 99);
  var ok = sig.len() == 12;
  var i = 0;
  while i < sig.len() {
    let v: Int = sig[i];
    if v < 0 { ok = false; }
    if v > 4294967295 { ok = false; }
    i = i + 1;
  }
  return assert(ok, "minhash: every slot is a 32-bit unsigned value");
}

fn t19() -> TestResult {
  var a = Vec[Int].new(); a.push(1); a.push(2); a.push(3);
  var b = Vec[Int].new(); b.push(1); b.push(2); b.push(3);
  var ok = ngram_signature_similarity(&a, &b) == 1000;
  var c = Vec[Int].new(); c.push(4); c.push(5); c.push(6);
  if ngram_signature_similarity(&a, &c) != 0 { ok = false; }
  var d = Vec[Int].new(); d.push(1); d.push(9); d.push(3); d.push(8);
  var e = Vec[Int].new(); e.push(1); e.push(2); e.push(3); e.push(4);
  if ngram_signature_similarity(&e, &d) != 500 { ok = false; }
  var short_v = Vec[Int].new(); short_v.push(1);
  if ngram_signature_similarity(&a, &short_v) != 0 { ok = false; }
  var e1 = Vec[Int].new();
  var e2 = Vec[Int].new();
  if ngram_signature_similarity(&e1, &e2) != 0 { ok = false; }
  return assert(ok, "signature similarity: identical 1000, disjoint 0, mismatch 0");
}

fn t20() -> TestResult {
  let near = sim_of("the quick brown fox jumps over the lazy dog",
                    "the quick brown fox sleeps over the lazy dog");
  let far = sim_of("the quick brown fox jumps over the lazy dog",
                   "totally unrelated content about quantum chromodynamics");
  var ok = near > far;
  if near <= 0 { ok = false; }
  return assert(ok, "minhash: near-duplicate sentence outranks unrelated text");
}

fn t21() -> TestResult {
  let near = sim_of("machine learning models require data",
                    "machine learning models need data");
  let far = sim_of("machine learning models require data",
                   "completely different subject matter entirely");
  var ok = near > far;
  if near <= 0 { ok = false; }
  return assert(ok, "minhash: second near-duplicate pair preserves ordering");
}

fn t22() -> TestResult {
  var words = ngram_words("The quick brown fox");
  var ok = words.len() == 4;
  var shingles = ngram_shingles(&words, 2);
  var uniq = ngram_unique(&shingles);
  if uniq.len() != 3 { ok = false; }
  if ngram_jaccard(&shingles, &uniq) != 1000 { ok = false; }
  if ngram_dice(&shingles, &uniq) != 1000 { ok = false; }
  var sig = ngram_minhash_signature(&shingles, 8, 3);
  var sig2 = ngram_minhash_signature(&shingles, 8, 3);
  if ngram_signature_similarity(&sig, &sig2) != 1000 { ok = false; }
  var cs = ngram_char_shingles("the quick brown fox", 5);
  if cs.len() != 15 { ok = false; }
  return assert(ok, "pipeline: words -> shingles -> unique/similarity/minhash");
}

fn main() -> Int {
  io.println("=== xiom.ngram conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.ngram: all tests passed");
  } else {
    io.println("xiom.ngram: tests failed");
  }
  return failed;
}
