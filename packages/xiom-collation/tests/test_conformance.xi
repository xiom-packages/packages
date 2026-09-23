// XIOM -- xiom.collation conformance tests (20 checks)
// Port task: prove the pure-XIOM xiom.collation module against its SPEC.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

module collation_tests
use xiom.io; use xiom.test; use xiom.collation;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every element check
// below is routed through streq/vec_is instead of `==`. Non-ASCII test data
// uses \u{...} escapes so the expectations are the UTF-8 byte sequences.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn vec_is(v: &Vec[Str], i: Int, want: Str) -> Bool {
  if i < 0 || i >= v.len() { return false; }
  return streq(v[i], want);
}

fn t1() -> TestResult {
  var ok = collate_compare("apple", "Banana") == -1;
  if collate_compare("Banana", "apple") != 1 { ok = false; }
  if collate_compare("Apple", "banana") != -1 { ok = false; }
  if collate_compare("apple", "BANANA") != -1 { ok = false; }
  return assert(ok, "case-insensitive order ignores case in the primary pass");
}

fn t2() -> TestResult {
  var ok = collate_compare("apple", "Apple") == -1;
  if collate_compare("Apple", "apple") != 1 { ok = false; }
  if collate_compare("a", "A") != -1 { ok = false; }
  if collate_compare("B", "b") != 1 { ok = false; }
  if collate_compare("ABC", "abc") != 1 { ok = false; }
  return assert(ok, "case tie-break orders lowercase before uppercase");
}

fn t3() -> TestResult {
  var ok = collate_compare("abc", "abc") == 0;
  if !collate_equal("abc", "abc") { ok = false; }
  if collate_equal("abc", "abd") { ok = false; }
  if collate_compare("", "") != 0 { ok = false; }
  if collate_compare("abc", "ab") != 1 { ok = false; }
  return assert(ok, "identical strings compare equal, prefixes sort first");
}

fn t4() -> TestResult {
  var ok = collate_compare("", "a") == -1;
  if collate_compare("a", "") != 1 { ok = false; }
  if collate_compare("", "A") != -1 { ok = false; }
  if !collate_equal("", "") { ok = false; }
  if collate_compare("", "0") != -1 { ok = false; }
  return assert(ok, "empty string sorts before any non-empty string");
}

fn t5() -> TestResult {
  var ok = collate_natural_compare("file2", "file10") == -1;
  if collate_natural_compare("file10", "file2") != 1 { ok = false; }
  if collate_natural_compare("file2", "file2") != 0 { ok = false; }
  if collate_natural_compare("File2", "file10") != -1 { ok = false; }
  return assert(ok, "natural order compares digit runs numerically");
}

fn t6() -> TestResult {
  var ok = collate_natural_compare("a9", "a10") == -1;
  if collate_natural_compare("a10", "a9") != 1 { ok = false; }
  if collate_natural_compare("v1.2.9", "v1.2.10") != -1 { ok = false; }
  if collate_natural_compare("v1.2.10", "v1.2.9") != 1 { ok = false; }
  return assert(ok, "a9 sorts before a10");
}

fn t7() -> TestResult {
  var ok = collate_natural_compare("x007", "x7") == -1;
  if collate_natural_compare("x7", "x007") != 1 { ok = false; }
  if collate_natural_compare("007", "7") != -1 { ok = false; }
  if collate_natural_compare("07", "7") != -1 { ok = false; }
  return assert(ok, "leading zeros: equal values order longer run first");
}

fn t8() -> TestResult {
  let c1 = collate_natural_compare("run007", "run7");
  let c2 = collate_natural_compare("run7", "run007");
  var ok = c1 == -1;
  if c2 != 1 { ok = false; }
  if c1 == 0 || c2 == 0 { ok = false; }
  if collate_natural_compare("a0007", "a7") != -1 { ok = false; }
  return assert(ok, "natural compare of equal values is never 0");
}

fn t9() -> TestResult {
  var ok = collate_natural_compare("2abc", "10abc") == -1;
  if collate_natural_compare("10abc", "2abc") != 1 { ok = false; }
  if collate_natural_compare("007x", "7x") != -1 { ok = false; }
  if collate_natural_compare("9", "10") != -1 { ok = false; }
  if collate_natural_compare("99", "100") != -1 { ok = false; }
  return assert(ok, "digit run at the start of a string");
}

fn t10() -> TestResult {
  var words = Vec[Str].new();
  words.push("banana");
  words.push("Apple");
  words.push("apple");
  words.push("Banana");
  let sorted = collate_sort(&words);
  var ok = sorted.len() == 4;
  if !vec_is(&sorted, 0, "apple") { ok = false; }
  if !vec_is(&sorted, 1, "Apple") { ok = false; }
  if !vec_is(&sorted, 2, "banana") { ok = false; }
  if !vec_is(&sorted, 3, "Banana") { ok = false; }
  return assert(ok, "collate_sort orders case-insensitively with case tie-break");
}

fn t11() -> TestResult {
  var words = Vec[Str].new();
  words.push("b");
  words.push("a");
  words.push("b");
  words.push("a");
  words.push("a");
  let sorted = collate_sort(&words);
  var ok = sorted.len() == 5;
  if !vec_is(&sorted, 0, "a") { ok = false; }
  if !vec_is(&sorted, 1, "a") { ok = false; }
  if !vec_is(&sorted, 2, "a") { ok = false; }
  if !vec_is(&sorted, 3, "b") { ok = false; }
  if !vec_is(&sorted, 4, "b") { ok = false; }
  return assert(ok, "collate_sort is stable on duplicates");
}

fn t12() -> TestResult {
  var words = Vec[Str].new();
  words.push("file10");
  words.push("file2");
  words.push("File1");
  let sorted = collate_natural_sort(&words);
  var ok = sorted.len() == 3;
  if !vec_is(&sorted, 0, "File1") { ok = false; }
  if !vec_is(&sorted, 1, "file2") { ok = false; }
  if !vec_is(&sorted, 2, "file10") { ok = false; }
  return assert(ok, "natural_sort orders numeric runs by value");
}

fn t13() -> TestResult {
  var ok = streq(collate_key("Apple"), "apple");
  if !streq(collate_key("ABCxyz"), "abcxyz") { ok = false; }
  if !streq(collate_key(""), "") { ok = false; }
  if !streq(collate_key("a1-!Z"), "a1-!z") { ok = false; }
  return assert(ok, "collate_key folds ASCII letters to lowercase");
}

fn t14() -> TestResult {
  let key = collate_key("\u{00C9}");
  var ok = key.len() == 2;
  if !streq(key, "\u{00C9}") { ok = false; }
  if !streq(collate_key("\u{00E9}"), "\u{00E9}") { ok = false; }
  if streq(collate_key("\u{00C9}"), "\u{00E9}") { ok = false; }
  if collate_key("").len() != 0 { ok = false; }
  if collate_key("AB").len() != 2 { ok = false; }
  return assert(ok, "collate_key preserves bytes and length");
}

fn t15() -> TestResult {
  var ok = collate_compare("file10", "file2") == -1;
  if collate_natural_compare("file10", "file2") != 1 { ok = false; }
  var words = Vec[Str].new();
  words.push("file10");
  words.push("file2");
  let plain = collate_sort(&words);
  let nat = collate_natural_sort(&words);
  if !vec_is(&plain, 0, "file10") { ok = false; }
  if !vec_is(&plain, 1, "file2") { ok = false; }
  if !vec_is(&nat, 0, "file2") { ok = false; }
  if !vec_is(&nat, 1, "file10") { ok = false; }
  return assert(ok, "natural and plain order differ on digit runs");
}

fn t16() -> TestResult {
  var ok = collate_compare("z", "\u{00E9}") == -1;
  if collate_compare("\u{00E9}", "z") != 1 { ok = false; }
  if collate_compare("\u{00E9}", "\u{00E9}") != 0 { ok = false; }
  if collate_compare("e", "\u{00E9}") != -1 { ok = false; }
  if collate_compare("\u{00C9}", "\u{00E9}") != -1 { ok = false; }
  if collate_natural_compare("z", "\u{00E9}") != -1 { ok = false; }
  return assert(ok, "non-ASCII compares as unsigned UTF-8 bytes");
}

fn t17() -> TestResult {
  var words = Vec[Str].new();
  words.push("10");
  words.push("7");
  words.push("007");
  words.push("2");
  let sorted = collate_natural_sort(&words);
  var ok = sorted.len() == 4;
  if !vec_is(&sorted, 0, "2") { ok = false; }
  if !vec_is(&sorted, 1, "007") { ok = false; }
  if !vec_is(&sorted, 2, "7") { ok = false; }
  if !vec_is(&sorted, 3, "10") { ok = false; }
  var plain = collate_sort(&words);
  if !vec_is(&plain, 0, "007") { ok = false; }
  if !vec_is(&plain, 1, "10") { ok = false; }
  return assert(ok, "natural_sort of bare number strings");
}

fn t18() -> TestResult {
  var ok = collate_natural_compare("a1b2", "a1b10") == -1;
  if collate_natural_compare("a1b10", "a1b2") != 1 { ok = false; }
  if collate_natural_compare("a1b2", "a1b2") != 0 { ok = false; }
  if collate_natural_compare("a1b", "a1b2") != -1 { ok = false; }
  if collate_natural_compare("a1b2", "a1b") != 1 { ok = false; }
  if collate_natural_compare("a1", "A1") != -1 { ok = false; }
  if collate_natural_compare("A1", "a1") != 1 { ok = false; }
  return assert(ok, "natural comparator is antisymmetric and ties only on identical");
}

fn t19() -> TestResult {
  var ok = collate_equal("same", "same");
  if collate_equal("Same", "same") { ok = false; }
  if !streq(collate_key("Same"), collate_key("same")) { ok = false; }
  if !streq(collate_key("Same"), "same") { ok = false; }
  if collate_equal("file2", "file10") { ok = false; }
  return assert(ok, "collate_equal is exact; keys give case-insensitive equality");
}

fn t20() -> TestResult {
  var words = Vec[Str].new();
  words.push("b");
  words.push("a");
  let sorted = collate_sort(&words);
  let nat = collate_natural_sort(&words);
  var ok = sorted.len() == 2;
  if !vec_is(&sorted, 0, "a") { ok = false; }
  if !vec_is(&sorted, 1, "b") { ok = false; }
  if !vec_is(&words, 0, "b") { ok = false; }
  if !vec_is(&words, 1, "a") { ok = false; }
  if nat.len() != 2 { ok = false; }
  var none = Vec[Str].new();
  if collate_sort(&none).len() != 0 { ok = false; }
  if collate_natural_sort(&none).len() != 0 { ok = false; }
  var one = Vec[Str].new();
  one.push("only");
  let single = collate_sort(&one);
  if single.len() != 1 { ok = false; }
  if !vec_is(&single, 0, "only") { ok = false; }
  return assert(ok, "sorts return fresh vectors and leave the input unchanged");
}

fn main() -> Int {
  io.println("=== xiom.collation conformance tests ===");
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
    io.println("xiom.collation: all tests passed");
  } else {
    io.println("xiom.collation: tests failed");
  }
  return failed;
}
