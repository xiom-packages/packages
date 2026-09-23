// XIOM -- xiom.spell conformance tests (26 checks)
// Port task: prove the pure-XIOM xiom.spell module against its SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module spell_tests
use xiom.io; use xiom.test; use xiom.spell;
use xiom.string.compare;

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

fn vec5(a: Str, b: Str, c: Str, d: Str, e: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  v.push(e);
  return v;
}

fn t1() -> TestResult {
  var ok = spell_distance("", "") == 0;
  if spell_distance("cat", "cat") != 0 { ok = false; }
  if spell_distance("kitten", "kitten") != 0 { ok = false; }
  if spell_distance("a", "a") != 0 { ok = false; }
  return assert(ok, "identical strings have distance 0");
}

fn t2() -> TestResult {
  var ok = spell_distance("cat", "cats") == 1;
  if spell_distance("ab", "abc") != 1 { ok = false; }
  if spell_distance("", "a") != 1 { ok = false; }
  return assert(ok, "one insertion costs 1");
}

fn t3() -> TestResult {
  var ok = spell_distance("cats", "cat") == 1;
  if spell_distance("abc", "ab") != 1 { ok = false; }
  if spell_distance("a", "") != 1 { ok = false; }
  return assert(ok, "one deletion costs 1");
}

fn t4() -> TestResult {
  var ok = spell_distance("cat", "cut") == 1;
  if spell_distance("cat", "bat") != 1 { ok = false; }
  if spell_distance("a", "b") != 1 { ok = false; }
  return assert(ok, "one substitution costs 1");
}

fn t5() -> TestResult {
  return assert(spell_distance("kitten", "sitting") == 3, "kitten to sitting is 3");
}

fn t6() -> TestResult {
  var ok = spell_distance("", "") == 0;
  if spell_distance("", "abc") != 3 { ok = false; }
  if spell_distance("abc", "") != 3 { ok = false; }
  if spell_distance("", "word") != 4 { ok = false; }
  return assert(ok, "empty string distance is the other length");
}

fn t7() -> TestResult {
  var ok = spell_distance("kitten", "sitting") == spell_distance("sitting", "kitten");
  if spell_distance("cat", "dog") != spell_distance("dog", "cat") { ok = false; }
  if spell_distance("flaw", "lawn") != spell_distance("lawn", "flaw") { ok = false; }
  if spell_distance("abcde", "abxde") != spell_distance("abxde", "abcde") { ok = false; }
  return assert(ok, "distance is symmetric");
}

fn t8() -> TestResult {
  var ok = spell_distance("flaw", "lawn") == 2;
  if spell_distance("sunday", "saturday") != 3 { ok = false; }
  if spell_distance("cat", "dog") != 3 { ok = false; }
  return assert(ok, "multi-edit distances: flaw/lawn 2, sunday/saturday 3");
}

fn t9() -> TestResult {
  var ok = spell_distance_bounded("cat", "cut", 1) == 1;
  if spell_distance_bounded("kitten", "sitting", 3) != 3 { ok = false; }
  if spell_distance_bounded("kitten", "sitting", 5) != 3 { ok = false; }
  if spell_distance_bounded("flaw", "lawn", 2) != 2 { ok = false; }
  if spell_distance_bounded("abc", "abc", 0) != 0 { ok = false; }
  return assert(ok, "bounded returns the exact distance within budget");
}

fn t10() -> TestResult {
  var ok = spell_distance_bounded("kitten", "sitting", 2) == 3;
  if spell_distance_bounded("cat", "dog", 2) != 3 { ok = false; }
  if spell_distance_bounded("abc", "xyz", 0) != 1 { ok = false; }
  if spell_distance_bounded("abc", "xyz", 1) != 2 { ok = false; }
  return assert(ok, "bounded returns max_dist + 1 over budget");
}

fn t11() -> TestResult {
  var ok = spell_distance_bounded("cat", "cat", 0) == 0;
  if spell_distance_bounded("cat", "cut", 0) != 1 { ok = false; }
  if spell_distance_bounded("", "abc", 0) != 1 { ok = false; }
  if spell_distance_bounded("abc", "", 0) != 1 { ok = false; }
  if spell_distance_bounded("cat", "cat", -5) != 0 { ok = false; }
  if spell_distance_bounded("cat", "cut", -5) != 1 { ok = false; }
  if spell_distance_bounded("", "", -1) != 0 { ok = false; }
  return assert(ok, "bounded budget 0 and negative budget clamp");
}

fn t12() -> TestResult {
  let d = vec3("cat", "dog", "bird");
  var ok = spell_contains(&d, "cat");
  if !spell_contains(&d, "dog") { ok = false; }
  if !spell_contains(&d, "bird") { ok = false; }
  return assert(ok, "contains finds every exact entry");
}

fn t13() -> TestResult {
  let d = vec3("cat", "dog", "bird");
  let empty = Vec[Str].new();
  var ok = !spell_contains(&d, "catt");
  if spell_contains(&d, "Cat") { ok = false; }
  if spell_contains(&d, "") { ok = false; }
  if spell_contains(&d, "do") { ok = false; }
  if spell_contains(&empty, "cat") { ok = false; }
  return assert(ok, "contains rejects absent, case-changed and empty words");
}

fn t14() -> TestResult {
  let d = vec2("cat", "dog");
  var ok = spell_is_correct(&d, "cat");
  if spell_is_correct(&d, "catt") { ok = false; }
  if spell_is_correct(&d, "dog") != spell_contains(&d, "dog") { ok = false; }
  if spell_is_correct(&d, "Cat") != spell_contains(&d, "Cat") { ok = false; }
  return assert(ok, "is_correct mirrors contains");
}

fn t15() -> TestResult {
  let d = vec5("cat", "cot", "cats", "dog", "bat");
  let got = spell_suggest(&d, "cat", 1, 10);
  let want = vec4("cat", "cot", "cats", "bat");
  return assert(vec_eq(&got, &want), "suggest orders by distance then dictionary order");
}

fn t16() -> TestResult {
  let d = vec5("cat", "cot", "cats", "dog", "bat");
  let got2 = spell_suggest(&d, "cat", 1, 2);
  let want2 = vec2("cat", "cot");
  let got3 = spell_suggest(&d, "cat", 1, 3);
  let want3 = vec3("cat", "cot", "cats");
  let got_all = spell_suggest(&d, "cat", 1, 100);
  var ok = vec_eq(&got2, &want2);
  if !vec_eq(&got3, &want3) { ok = false; }
  if got_all.len() != 4 { ok = false; }
  return assert(ok, "suggest honours max_results");
}

fn t17() -> TestResult {
  let d = vec3("cat", "dog", "cut");
  let exact = spell_suggest(&d, "cat", 0, 10);
  let want_exact = vec1("cat");
  let near = spell_suggest(&d, "cat", 2, 10);
  let want_near = vec2("cat", "cut");
  var ok = vec_eq(&exact, &want_exact);
  if !vec_eq(&near, &want_near) { ok = false; }
  return assert(ok, "suggest max_dist 0 returns exact matches only");
}

fn t18() -> TestResult {
  let d = vec3("cat", "dog", "cut");
  let empty = Vec[Str].new();
  let far = vec1("dog");
  let neg = spell_suggest(&d, "cat", -1, 10);
  let no_room = spell_suggest(&d, "cat", 2, 0);
  let no_dict = spell_suggest(&empty, "cat", 2, 10);
  let no_hit = spell_suggest(&far, "cat", 1, 10);
  var ok = neg.len() == 0;
  if no_room.len() != 0 { ok = false; }
  if no_dict.len() != 0 { ok = false; }
  if no_hit.len() != 0 { ok = false; }
  return assert(ok, "suggest degenerate arguments return empty");
}

fn t19() -> TestResult {
  let d = vec3("bat", "cat", "hat");
  let got = spell_suggest(&d, "cat", 1, 10);
  let want = vec3("cat", "bat", "hat");
  return assert(vec_eq(&got, &want), "suggest ties keep dictionary order");
}

fn t20() -> TestResult {
  let d = vec3("the", "quick", "fox");
  let got = spell_unknown_words(&d, "the quick brown fox");
  let want = vec1("brown");
  return assert(vec_eq(&got, &want), "unknown_words reports words absent from the dictionary");
}

fn t21() -> TestResult {
  let d = vec1("alpha");
  let got = spell_unknown_words(&d, "beta gamma beta alpha gamma");
  let want = vec2("beta", "gamma");
  let ok = vec_eq(&got, &want);
  return assert(ok, "unknown_words dedups in first-seen order");
}

fn t22() -> TestResult {
  let d = vec2("don't", "isn't");
  let got = spell_unknown_words(&d, "don't isn't don't ain't");
  let want = vec1("ain't");
  return assert(vec_eq(&got, &want), "unknown_words keeps interior apostrophes");
}

fn t23() -> TestResult {
  let empty = Vec[Str].new();
  let got = spell_unknown_words(&empty, "'quoted' rock''n");
  let want = vec3("quoted", "rock", "n");
  return assert(vec_eq(&got, &want), "unknown_words treats edge and doubled apostrophes as separators");
}

fn t24() -> TestResult {
  let empty = Vec[Str].new();
  let ab = vec1("ab");
  let none_empty = spell_unknown_words(&empty, "");
  let none_punct = spell_unknown_words(&empty, "!!!");
  let none_known = spell_unknown_words(&ab, "ab ab ab");
  let got = spell_unknown_words(&empty, "ab cd");
  let want = vec2("ab", "cd");
  var ok = none_empty.len() == 0;
  if none_punct.len() != 0 { ok = false; }
  if none_known.len() != 0 { ok = false; }
  if !vec_eq(&got, &want) { ok = false; }
  return assert(ok, "unknown_words on empty dictionary and separator-only text");
}

fn t25() -> TestResult {
  let caf = vec1("caf");
  let got = spell_unknown_words(&caf, "café naïve");
  let want = vec2("na", "ve");
  var ok = vec_eq(&got, &want);
  if spell_distance("café", "cafe") != 2 { ok = false; }
  return assert(ok, "unknown_words treats non-ASCII bytes as separators; distance is byte-wise");
}

fn t26() -> TestResult {
  let d = vec1("var_1");
  let got = spell_unknown_words(&d, "var_1 3x4 _x");
  let want = vec2("3x4", "_x");
  return assert(vec_eq(&got, &want), "unknown_words keeps digits and underscores");
}

fn main() -> Int {
  io.println("=== xiom.spell conformance tests ===");
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
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.spell: all tests passed");
  } else {
    io.println("xiom.spell: tests failed");
  }
  return failed;
}
