// XIOM -- xiom.humanize conformance tests (24 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Proves the pure-XIOM xiom.humanize module against the rules pinned in
// SPEC.md: byte units and half-away rounding, duration buckets and trailing
// component omission, count agreement, ordinal suffixes, and list joins.

module humanize_tests
use xiom.io; use xiom.test; use xiom.humanize;
use xiom.string.compare;

// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every output check
// below is routed through streq instead of `==`.

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn t1() -> TestResult {
  var ok = streq(humanize_bytes(0, 0, false), "0 B");
  if !streq(humanize_bytes(0, 0, true), "0 B") { ok = false; }
  if !streq(humanize_bytes(0, 2, false), "0.00 B") { ok = false; }
  if !streq(humanize_bytes(999, 0, false), "999 B") { ok = false; }
  if !streq(humanize_bytes(999, 0, true), "999 B") { ok = false; }
  if !streq(humanize_bytes(512, 2, false), "512.00 B") { ok = false; }
  return assert(ok, "bytes: zero and sub-unit values keep their base unit");
}

fn t2() -> TestResult {
  var ok = streq(humanize_bytes(1000, 0, false), "1 KB");
  if !streq(humanize_bytes(1024, 0, false), "1 KB") { ok = false; }
  if !streq(humanize_bytes(1024, 0, true), "1 KiB") { ok = false; }
  if !streq(humanize_bytes(1023, 0, true), "1023 B") { ok = false; }
  return assert(ok, "bytes: the unit ladder starts at the base");
}

fn t3() -> TestResult {
  var ok = streq(humanize_bytes(1536, 0, false), "2 KB");
  if !streq(humanize_bytes(1536, 1, false), "1.5 KB") { ok = false; }
  if !streq(humanize_bytes(1536, 0, true), "2 KiB") { ok = false; }
  if !streq(humanize_bytes(1536, 1, true), "1.5 KiB") { ok = false; }
  return assert(ok, "bytes: 1536 rounds up on both bases");
}

fn t4() -> TestResult {
  var ok = streq(humanize_bytes(1000, 0, false), "1 KB");
  if !streq(humanize_bytes(1000000, 0, false), "1 MB") { ok = false; }
  if !streq(humanize_bytes(1000000000, 0, false), "1 GB") { ok = false; }
  if !streq(humanize_bytes(1000000000000, 0, false), "1 TB") { ok = false; }
  if !streq(humanize_bytes(1000000000000000, 0, false), "1 PB") { ok = false; }
  return assert(ok, "bytes: decimal suffix ladder KB..PB");
}

fn t5() -> TestResult {
  var ok = streq(humanize_bytes(1024, 0, true), "1 KiB");
  if !streq(humanize_bytes(1048576, 0, true), "1 MiB") { ok = false; }
  if !streq(humanize_bytes(1073741824, 0, true), "1 GiB") { ok = false; }
  if !streq(humanize_bytes(1099511627776, 0, true), "1 TiB") { ok = false; }
  if !streq(humanize_bytes(1125899906842624, 0, true), "1 PiB") { ok = false; }
  return assert(ok, "bytes: binary suffix ladder KiB..PiB");
}

fn t6() -> TestResult {
  var ok = streq(humanize_bytes(1000000, 0, false), "1 MB");
  if !streq(humanize_bytes(1000000, 0, true), "977 KiB") { ok = false; }
  if !streq(humanize_bytes(1000000, 1, true), "976.6 KiB") { ok = false; }
  if !streq(humanize_bytes(1000000, 2, true), "976.56 KiB") { ok = false; }
  return assert(ok, "bytes: one megabyte differs between decimal and binary");
}

fn t7() -> TestResult {
  var ok = streq(humanize_bytes(1500000, 0, false), "2 MB");
  if !streq(humanize_bytes(1500000, 1, false), "1.5 MB") { ok = false; }
  if !streq(humanize_bytes(1500000, 2, false), "1.50 MB") { ok = false; }
  if !streq(humanize_bytes(1500000, 3, false), "1.500 MB") { ok = false; }
  return assert(ok, "bytes: decimals 0..3 print exactly that many digits");
}

fn t8() -> TestResult {
  var ok = streq(humanize_bytes(1536, -5, false), "2 KB");
  if !streq(humanize_bytes(1536, -1, false), "2 KB") { ok = false; }
  if !streq(humanize_bytes(1536, 9, false), "1.536 KB") { ok = false; }
  if !streq(humanize_bytes(1500000, 7, false), "1.500 MB") { ok = false; }
  return assert(ok, "bytes: decimals are clamped to 0..3");
}

fn t9() -> TestResult {
  var ok = streq(humanize_bytes(1550, 1, false), "1.6 KB");
  if !streq(humanize_bytes(1450, 1, false), "1.5 KB") { ok = false; }
  if !streq(humanize_bytes(1449, 1, false), "1.4 KB") { ok = false; }
  if !streq(humanize_bytes(2500, 0, false), "3 KB") { ok = false; }
  if !streq(humanize_bytes(2400, 0, false), "2 KB") { ok = false; }
  return assert(ok, "bytes: rounding is half away from zero");
}

fn t10() -> TestResult {
  var ok = streq(humanize_bytes(-1536, 1, false), "-1.5 KB");
  if !streq(humanize_bytes(-1500000, 1, false), "-1.5 MB") { ok = false; }
  if !streq(humanize_bytes(-500, 0, false), "-500 B") { ok = false; }
  if !streq(humanize_bytes(-1024, 0, true), "-1 KiB") { ok = false; }
  if !streq(humanize_bytes(-2048, 0, true), "-2 KiB") { ok = false; }
  return assert(ok, "bytes: negative values keep the sign");
}

fn t11() -> TestResult {
  let int_max = 9223372036854775807;
  let int_min = 0 - 9223372036854775807 - 1;
  var ok = streq(humanize_bytes(int_max, 0, false), "9223 PB");
  if !streq(humanize_bytes(int_min, 0, false), "-9223 PB") { ok = false; }
  if !streq(humanize_bytes(int_max, 0, true), "8192 PiB") { ok = false; }
  if !streq(humanize_bytes(int_min, 0, true), "-8192 PiB") { ok = false; }
  return assert(ok, "bytes: 64-bit edges format exactly");
}

fn t12() -> TestResult {
  var ok = streq(humanize_duration_ms(0), "0ms");
  if !streq(humanize_duration_ms(-5), "0ms") { ok = false; }
  if !streq(humanize_duration_ms(-100000), "0ms") { ok = false; }
  if !streq(humanize_duration_ms(1), "1ms") { ok = false; }
  if !streq(humanize_duration_ms(850), "850ms") { ok = false; }
  if !streq(humanize_duration_ms(999), "999ms") { ok = false; }
  return assert(ok, "duration: zero, negative and millisecond bucket");
}

fn t13() -> TestResult {
  var ok = streq(humanize_duration_ms(1000), "1s");
  if !streq(humanize_duration_ms(1500), "1s") { ok = false; }
  if !streq(humanize_duration_ms(45000), "45s") { ok = false; }
  if !streq(humanize_duration_ms(59999), "59s") { ok = false; }
  if !streq(humanize_duration_ms(60000), "1m") { ok = false; }
  return assert(ok, "duration: seconds bucket floors; 60000 is the minute edge");
}

fn t14() -> TestResult {
  var ok = streq(humanize_duration_ms(61000), "1m 1s");
  if !streq(humanize_duration_ms(125000), "2m 5s") { ok = false; }
  if !streq(humanize_duration_ms(120000), "2m") { ok = false; }
  if !streq(humanize_duration_ms(3599999), "59m 59s") { ok = false; }
  return assert(ok, "duration: minutes bucket omits a zero seconds component");
}

fn t15() -> TestResult {
  var ok = streq(humanize_duration_ms(3600000), "1h");
  if !streq(humanize_duration_ms(3780000), "1h 3m") { ok = false; }
  if !streq(humanize_duration_ms(7200000), "2h") { ok = false; }
  if !streq(humanize_duration_ms(86399999), "23h 59m") { ok = false; }
  return assert(ok, "duration: hours bucket omits a zero minutes component");
}

fn t16() -> TestResult {
  var ok = streq(humanize_duration_ms(86400000), "1d");
  if !streq(humanize_duration_ms(90000000), "1d 1h") { ok = false; }
  if !streq(humanize_duration_ms(187200000), "2d 4h") { ok = false; }
  if !streq(humanize_duration_ms(2678400000), "31d") { ok = false; }
  return assert(ok, "duration: days bucket omits a zero hours component");
}

fn t17() -> TestResult {
  var ok = streq(humanize_count(1, "item", "items"), "1 item");
  if !streq(humanize_count(2, "item", "items"), "2 items") { ok = false; }
  if !streq(humanize_count(0, "item", "items"), "0 items") { ok = false; }
  if !streq(humanize_count(-1, "item", "items"), "-1 item") { ok = false; }
  if !streq(humanize_count(-2, "item", "items"), "-2 items") { ok = false; }
  if !streq(humanize_count(100, "item", "items"), "100 items") { ok = false; }
  return assert(ok, "count: magnitude 1 is singular, everything else plural");
}

fn t18() -> TestResult {
  var ok = streq(humanize_ordinal(1), "1st");
  if !streq(humanize_ordinal(2), "2nd") { ok = false; }
  if !streq(humanize_ordinal(3), "3rd") { ok = false; }
  if !streq(humanize_ordinal(4), "4th") { ok = false; }
  if !streq(humanize_ordinal(5), "5th") { ok = false; }
  if !streq(humanize_ordinal(10), "10th") { ok = false; }
  if !streq(humanize_ordinal(11), "11th") { ok = false; }
  if !streq(humanize_ordinal(12), "12th") { ok = false; }
  if !streq(humanize_ordinal(13), "13th") { ok = false; }
  return assert(ok, "ordinal: 1..13 including the 11..13 exceptions");
}

fn t19() -> TestResult {
  var ok = streq(humanize_ordinal(21), "21st");
  if !streq(humanize_ordinal(101), "101st") { ok = false; }
  if !streq(humanize_ordinal(111), "111th") { ok = false; }
  if !streq(humanize_ordinal(112), "112th") { ok = false; }
  if !streq(humanize_ordinal(113), "113th") { ok = false; }
  if !streq(humanize_ordinal(120), "120th") { ok = false; }
  if !streq(humanize_ordinal(121), "121st") { ok = false; }
  return assert(ok, "ordinal: suffix uses the magnitude's last two digits");
}

fn t20() -> TestResult {
  var ok = streq(humanize_ordinal(-1), "-1st");
  if !streq(humanize_ordinal(-2), "-2nd") { ok = false; }
  if !streq(humanize_ordinal(-3), "-3rd") { ok = false; }
  if !streq(humanize_ordinal(-11), "-11th") { ok = false; }
  if !streq(humanize_ordinal(-21), "-21st") { ok = false; }
  if !streq(humanize_ordinal(-101), "-101st") { ok = false; }
  if !streq(humanize_ordinal(-111), "-111th") { ok = false; }
  return assert(ok, "ordinal: negatives keep the sign and magnitude suffix");
}

fn t21() -> TestResult {
  var empty = Vec[Str].new();
  var one = Vec[Str].new();
  one.push("solo");
  var ok = streq(humanize_list(&empty, "and"), "");
  if !streq(humanize_list(&one, "and"), "solo") { ok = false; }
  return assert(ok, "list: empty renders empty, a single item renders itself");
}

fn t22() -> TestResult {
  var two = Vec[Str].new();
  two.push("a");
  two.push("b");
  var three = Vec[Str].new();
  three.push("a");
  three.push("b");
  three.push("c");
  var ok = streq(humanize_list(&two, "and"), "a and b");
  if !streq(humanize_list(&two, "or"), "a or b") { ok = false; }
  if !streq(humanize_list(&three, "and"), "a, b and c") { ok = false; }
  if !streq(humanize_list(&three, "or"), "a, b or c") { ok = false; }
  return assert(ok, "list: two and three items, Oxford comma omitted");
}

fn t23() -> TestResult {
  var four = Vec[Str].new();
  four.push("a");
  four.push("b");
  four.push("c");
  four.push("d");
  var five = Vec[Str].new();
  five.push("a");
  five.push("b");
  five.push("c");
  five.push("d");
  five.push("e");
  var ok = streq(humanize_list(&four, "and"), "a, b, c and d");
  if !streq(humanize_list(&five, "and"), "a, b, c, d and e") { ok = false; }
  return assert(ok, "list: four and five items join every element");
}

fn t24() -> TestResult {
  var three = Vec[Str].new();
  three.push("x");
  three.push("y");
  three.push("z");
  var two = Vec[Str].new();
  two.push("1");
  two.push("2");
  var ok = streq(humanize_list(&three, "&"), "x, y & z");
  if !streq(humanize_list(&two, "plus"), "1 plus 2") { ok = false; }
  return assert(ok, "list: the conjunction word is used verbatim");
}

fn main() -> Int {
  io.println("=== xiom.humanize conformance tests ===");
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
    io.println("xiom.humanize: all tests passed");
  } else {
    io.println("xiom.humanize: tests failed");
  }
  return failed;
}
