// XIOM -- xiom.electronics conformance tests (24 checks)
// Port task: prove the pure-XIOM xiom.electronics module (color codes, E24,
// voltage dividers, LED resistors) against its SPEC.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// All Str equality goes through str_compare (BUG 17: `==` on Str values read
// from a Vec lowers to a pointer comparison); Err strings are compared
// exactly; Vec[Int] element reads use typed `let` bindings.

module electronics_tests
use xiom.io; use xiom.test; use xiom.electronics;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn opt_is(o: Option[Int], want: Int) -> Bool {
  match o {
    Some(v) => { return v == want; },
    None => { return false; },
  }
  return false;
}

fn opt_none(o: Option[Int]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

fn ok_int(r: Result[Int, Str], want: Int) -> Bool {
  if !r.is_ok {
    return false;
  }
  return r.value == want;
}

fn err_int_is(r: Result[Int, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

fn bands3(a: Str, b: Str, c: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

fn bands4(a: Str, b: Str, c: Str, d: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  v.push(d);
  return v;
}

// The canonical E24 table, spelled out independently of the module.
fn e24_expected() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(10);
  v.push(11);
  v.push(12);
  v.push(13);
  v.push(15);
  v.push(16);
  v.push(18);
  v.push(20);
  v.push(22);
  v.push(24);
  v.push(27);
  v.push(30);
  v.push(33);
  v.push(36);
  v.push(39);
  v.push(43);
  v.push(47);
  v.push(51);
  v.push(56);
  v.push(62);
  v.push(68);
  v.push(75);
  v.push(82);
  v.push(91);
  return v;
}

fn t1() -> TestResult {
  var ok = opt_is(electron_color_digit("black"), 0);
  if !opt_is(electron_color_digit("brown"), 1) { ok = false; }
  if !opt_is(electron_color_digit("red"), 2) { ok = false; }
  if !opt_is(electron_color_digit("orange"), 3) { ok = false; }
  if !opt_is(electron_color_digit("yellow"), 4) { ok = false; }
  if !opt_is(electron_color_digit("green"), 5) { ok = false; }
  if !opt_is(electron_color_digit("blue"), 6) { ok = false; }
  if !opt_is(electron_color_digit("violet"), 7) { ok = false; }
  if !opt_is(electron_color_digit("grey"), 8) { ok = false; }
  if !opt_is(electron_color_digit("gray"), 8) { ok = false; }
  if !opt_is(electron_color_digit("white"), 9) { ok = false; }
  return assert(ok, "digit codes: ten colors 0..9 plus the gray alias");
}

fn t2() -> TestResult {
  var ok = opt_none(electron_color_digit("chartreuse"));
  if !opt_none(electron_color_digit("purple")) { ok = false; }
  if !opt_none(electron_color_digit("Red")) { ok = false; }
  if !opt_none(electron_color_digit("grey ")) { ok = false; }
  if !opt_none(electron_color_digit("")) { ok = false; }
  return assert(ok, "digit lookup rejects unknown, uppercase, padded and empty");
}

fn t3() -> TestResult {
  var ok = opt_is(electron_color_multiplier("black"), 0);
  if !opt_is(electron_color_multiplier("brown"), 1) { ok = false; }
  if !opt_is(electron_color_multiplier("red"), 2) { ok = false; }
  if !opt_is(electron_color_multiplier("violet"), 7) { ok = false; }
  if !opt_is(electron_color_multiplier("gray"), 8) { ok = false; }
  if !opt_is(electron_color_multiplier("white"), 9) { ok = false; }
  if !opt_none(electron_color_multiplier("gold")) { ok = false; }
  if !opt_none(electron_color_multiplier("silver")) { ok = false; }
  return assert(ok, "multiplier codes are the digit decades; gold/silver rejected");
}

fn t4() -> TestResult {
  let b1 = bands3("brown", "black", "red");
  let b2 = bands3("red", "violet", "brown");
  let b3 = bands3("brown", "black", "black");
  var ok = ok_int(electron_resistor_value(&b1), 1000);
  if !ok_int(electron_resistor_value(&b2), 270) { ok = false; }
  if !ok_int(electron_resistor_value(&b3), 10) { ok = false; }
  return assert(ok, "3-band: brown-black-red=1000, red-violet-brown=270, brown-black-black=10");
}

fn t5() -> TestResult {
  let b1 = bands3("green", "blue", "orange");
  let b2 = bands3("yellow", "violet", "orange");
  let b3 = bands3("black", "black", "black");
  let b4 = bands3("blue", "grey", "white");
  var ok = ok_int(electron_resistor_value(&b1), 56000);
  if !ok_int(electron_resistor_value(&b2), 47000) { ok = false; }
  if !ok_int(electron_resistor_value(&b3), 0) { ok = false; }
  if !ok_int(electron_resistor_value(&b4), 68000000000) { ok = false; }
  return assert(ok, "3-band: mixed decades, all-zero bands, 68 Gohm");
}

fn t6() -> TestResult {
  let b1 = bands4("brown", "black", "red", "brown");
  let b2 = bands4("brown", "black", "red", "red");
  let b3 = bands4("brown", "black", "red", "gold");
  let b4 = bands4("brown", "black", "red", "silver");
  let b5 = bands4("brown", "black", "red", "green");
  var ok = ok_int(electron_resistor_value(&b1), 1000);
  if !ok_int(electron_resistor_value(&b2), 1000) { ok = false; }
  if !ok_int(electron_resistor_value(&b3), 1000) { ok = false; }
  if !ok_int(electron_resistor_value(&b4), 1000) { ok = false; }
  if !ok_int(electron_resistor_value(&b5), 1000) { ok = false; }
  return assert(ok, "4-band: value ignores all five tolerance colors");
}

fn t7() -> TestResult {
  let b1 = bands4("red", "violet", "brown", "gold");
  let b2 = bands4("green", "blue", "orange", "silver");
  var ok = ok_int(electron_resistor_value(&b1), 270);
  if !ok_int(electron_resistor_value(&b2), 56000) { ok = false; }
  return assert(ok, "4-band values use only the first three bands");
}

fn t8() -> TestResult {
  let b1 = bands3("chartreuse", "black", "red");
  let b2 = bands3("brown", "purple", "red");
  let b3 = bands3("brown", "black", "gold");
  let b4 = bands4("brown", "black", "red", "grey");
  var ok = err_int_is(electron_resistor_value(&b1), "electronics: unknown color code");
  if !err_int_is(electron_resistor_value(&b2), "electronics: unknown color code") { ok = false; }
  if !err_int_is(electron_resistor_value(&b3), "electronics: unknown color code") { ok = false; }
  if !err_int_is(electron_resistor_value(&b4), "electronics: unknown color code") { ok = false; }
  return assert(ok, "unknown digit, multiplier and tolerance colors are Err");
}

fn t9() -> TestResult {
  var v0 = Vec[Str].new();
  var v1 = Vec[Str].new();
  v1.push("brown");
  var v2 = Vec[Str].new();
  v2.push("brown");
  v2.push("black");
  var v5 = Vec[Str].new();
  v5.push("brown");
  v5.push("black");
  v5.push("red");
  v5.push("gold");
  v5.push("red");
  var ok = err_int_is(electron_resistor_value(&v0), "electronics: resistor bands must be 3 or 4");
  if !err_int_is(electron_resistor_value(&v1), "electronics: resistor bands must be 3 or 4") { ok = false; }
  if !err_int_is(electron_resistor_value(&v2), "electronics: resistor bands must be 3 or 4") { ok = false; }
  if !err_int_is(electron_resistor_value(&v5), "electronics: resistor bands must be 3 or 4") { ok = false; }
  return assert(ok, "band counts 0, 1, 2 and 5 are Err");
}

fn t10() -> TestResult {
  var ok = opt_is(electron_resistor_tolerance("brown"), 10);
  if !opt_is(electron_resistor_tolerance("red"), 20) { ok = false; }
  if !opt_is(electron_resistor_tolerance("gold"), 50) { ok = false; }
  if !opt_is(electron_resistor_tolerance("silver"), 100) { ok = false; }
  if !opt_is(electron_resistor_tolerance("green"), 5) { ok = false; }
  if !opt_none(electron_resistor_tolerance("black")) { ok = false; }
  if !opt_none(electron_resistor_tolerance("blue")) { ok = false; }
  if !opt_none(electron_resistor_tolerance("grey")) { ok = false; }
  if !opt_none(electron_resistor_tolerance("gray")) { ok = false; }
  if !opt_none(electron_resistor_tolerance("white")) { ok = false; }
  if !opt_none(electron_resistor_tolerance("")) { ok = false; }
  return assert(ok, "tolerance permille: 1%,2%,5%,10%,0.5% -> 10,20,50,100,5");
}

fn t11() -> TestResult {
  let vals = electron_e24_values();
  var ok = vals.len() == 24;
  let first: Int = vals[0];
  let last: Int = vals[23];
  if first != 10 { ok = false; }
  if last != 91 { ok = false; }
  return assert(ok, "E24 list: 24 values, 10 first, 91 last");
}

fn t12() -> TestResult {
  let got = electron_e24_values();
  let want = e24_expected();
  var n = got.len();
  if want.len() < n { n = want.len(); }
  var ok = got.len() == want.len();
  var i = 0;
  while i < n {
    let g: Int = got[i];
    let w: Int = want[i];
    if g != w { ok = false; }
    i = i + 1;
  }
  return assert(ok, "E24 list matches the canonical 24 values in order");
}

fn t13() -> TestResult {
  let vals = electron_e24_values();
  if vals.len() == 0 {
    return assert(false, "E24 list is strictly ascending");
  }
  var ok = vals.len() == 24;
  var prev: Int = vals[0];
  var i = 1;
  while i < vals.len() {
    let cur: Int = vals[i];
    if cur <= prev { ok = false; }
    prev = cur;
    i = i + 1;
  }
  return assert(ok, "E24 list is strictly ascending");
}

fn t14() -> TestResult {
  var ok = electron_nearest_e24(10) == 10;
  if electron_nearest_e24(11) != 11 { ok = false; }
  if electron_nearest_e24(47) != 47 { ok = false; }
  if electron_nearest_e24(91) != 91 { ok = false; }
  if electron_nearest_e24(470) != 470 { ok = false; }
  if electron_nearest_e24(4700) != 4700 { ok = false; }
  if electron_nearest_e24(91000) != 91000 { ok = false; }
  return assert(ok, "nearest E24 returns exact nominals unchanged");
}

fn t15() -> TestResult {
  var ok = electron_nearest_e24(48) == 47;
  if electron_nearest_e24(50) != 51 { ok = false; }
  if electron_nearest_e24(53) != 51 { ok = false; }
  if electron_nearest_e24(5000) != 5100 { ok = false; }
  if electron_nearest_e24(48000) != 47000 { ok = false; }
  return assert(ok, "nearest E24 rounds between nominals");
}

fn t16() -> TestResult {
  var ok = electron_nearest_e24(14) == 15;
  if electron_nearest_e24(19) != 20 { ok = false; }
  if electron_nearest_e24(21) != 22 { ok = false; }
  if electron_nearest_e24(140) != 150 { ok = false; }
  if electron_nearest_e24(1400000) != 1500000 { ok = false; }
  return assert(ok, "nearest E24 resolves ties to the larger nominal");
}

fn t17() -> TestResult {
  var ok = electron_nearest_e24(100) == 100;
  if electron_nearest_e24(999) != 910 { ok = false; }
  if electron_nearest_e24(99999) != 91000 { ok = false; }
  if electron_nearest_e24(9999999) != 9100000 { ok = false; }
  return assert(ok, "nearest E24 is decade-scaled and clamps to the decade top");
}

fn t18() -> TestResult {
  var ok = electron_nearest_e24(0) == 0;
  if electron_nearest_e24(9) != 9 { ok = false; }
  if electron_nearest_e24(1) != 1 { ok = false; }
  if electron_nearest_e24(-5) != -5 { ok = false; }
  return assert(ok, "values below 10 ohms pass through unchanged");
}

fn t19() -> TestResult {
  var ok = electron_voltage_divider_mv(1000, 1000, 1000) == 500;
  if electron_voltage_divider_mv(5000, 4700, 4700) != 2500 { ok = false; }
  if electron_voltage_divider_mv(3300, 1, 1) != 1650 { ok = false; }
  if electron_voltage_divider_mv(0, 1000, 1000) != 0 { ok = false; }
  return assert(ok, "equal divider resistors halve the input voltage");
}

fn t20() -> TestResult {
  var ok = electron_voltage_divider_mv(9000, 1000000, 1) == 0;
  if electron_voltage_divider_mv(9000, 1, 1000000) != 8999 { ok = false; }
  if electron_voltage_divider_mv(9000, 0, 1000) != 9000 { ok = false; }
  if electron_voltage_divider_mv(9000, 1000, 0) != 0 { ok = false; }
  return assert(ok, "divider extreme ratios truncate toward zero");
}

fn t21() -> TestResult {
  var ok = electron_voltage_divider_mv(5000, 0, 0) == 0;
  if electron_voltage_divider_mv(5000, 5, -5) != 0 { ok = false; }
  if electron_voltage_divider_mv(0, 0, 0) != 0 { ok = false; }
  return assert(ok, "zero total resistance yields 0 mV");
}

fn t22() -> TestResult {
  var ok = ok_int(electron_led_resistor_ohm(5000, 2000, 20000), 150);
  if !ok_int(electron_led_resistor_ohm(9000, 3200, 20000), 290) { ok = false; }
  if !ok_int(electron_led_resistor_ohm(3300, 2000, 10000), 130) { ok = false; }
  if !ok_int(electron_led_resistor_ohm(5000, 2000, 15000), 200) { ok = false; }
  if !ok_int(electron_led_resistor_ohm(12000, 2000, 1000), 10000) { ok = false; }
  return assert(ok, "LED resistor: known supply/forward/current cases");
}

fn t23() -> TestResult {
  var ok = err_int_is(electron_led_resistor_ohm(5000, 2000, 0), "electronics: current must be positive");
  if !err_int_is(electron_led_resistor_ohm(5000, 2000, -5), "electronics: current must be positive") { ok = false; }
  if !err_int_is(electron_led_resistor_ohm(5000, 5000, 20000), "electronics: supply must exceed forward voltage") { ok = false; }
  if !err_int_is(electron_led_resistor_ohm(2000, 5000, 20000), "electronics: supply must exceed forward voltage") { ok = false; }
  if !err_int_is(electron_led_resistor_ohm(5000, 5000, 0), "electronics: current must be positive") { ok = false; }
  return assert(ok, "LED resistor error paths with current checked first");
}

fn t24() -> TestResult {
  let b = bands3("white", "white", "white");
  var ok = ok_int(electron_resistor_value(&b), 99000000000);
  if electron_nearest_e24(99000000000) != 91000000000 { ok = false; }
  if electron_voltage_divider_mv(1000000, 1000000, 1000000) != 500000 { ok = false; }
  if !ok_int(electron_led_resistor_ohm(1000000, 0, 1), 1000000000) { ok = false; }
  return assert(ok, "large values stay exact in 64-bit integer math");
}

fn main() -> Int {
  io.println("=== xiom.electronics conformance tests ===");
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
    io.println("xiom.electronics: all tests passed");
  } else {
    io.println("xiom.electronics: tests failed");
  }
  return failed;
}
