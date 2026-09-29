// XIOM -- xiom.pwm conformance tests (20 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: prove the pure-XIOM xiom.pwm integer math against the
// documented rounding rules, validation order and error catalog in SPEC.md.
//
// Every expected number is hand-computed integer arithmetic; nothing depends
// on hardware, time or floating point. Str comparisons go through
// str_compare.

module pwm_tests
use xiom.io; use xiom.test; use xiom.pwm;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when the result fails with exactly the message `want`.
fn err_is(r: Result[Int, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// True when an int-result succeeds with exactly `want`.
fn set_is(r: Result[Int, Str], want: Int) -> Bool {
  match r {
    Ok(v) => { return v == want; },
    Err(_) => { return false; },
  }
  return false;
}

// True when the channel result fails with exactly the message `want`.
fn ch_err_is(r: Result[PwmChannel, Str], want: Str) -> Bool {
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

// A channel or a zero-value placeholder when construction fails.
fn channel_or_zero(clock: Int, freq: Int, duty: Int) -> PwmChannel {
  let r = pwm_channel(clock, freq, duty);
  match r {
    Ok(c) => { return c; },
    Err(_) => {},
  }
  return PwmChannel{ clock_hz: 0; freq_hz: 0; period_ticks: 0; duty_permille: 0; };
}

fn t1() -> TestResult {
  let r = pwm_channel(1000000, 1000, 250);
  var ok = false;
  match r {
    Ok(c) => {
      ok = pwm_clock_hz(&c) == 1000000;
      if pwm_freq_hz(&c) != 1000 { ok = false; }
      if pwm_period_ticks(&c) != 1000 { ok = false; }
      if pwm_duty_permille(&c) != 250 { ok = false; }
      if pwm_duty_ticks(&c) != 250 { ok = false; }
      if pwm_period_micros(&c) != 1000 { ok = false; }
      if pwm_duty_micros(&c) != 250 { ok = false; }
      if pwm_actual_freq_hz(&c) != 1000 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a 1 MHz clock at 1 kHz gives a 1000-tick period");
}

fn t2() -> TestResult {
  let c = channel_or_zero(1000, 300, 500);
  var ok = pwm_period_ticks(&c) == 3;
  if pwm_duty_ticks(&c) != 1 { ok = false; }
  if pwm_actual_freq_hz(&c) != 333 { ok = false; }
  return assert(ok, "a non-dividing frequency floors the period and reports it");
}

fn t3() -> TestResult {
  var ok = ch_err_is(pwm_channel(0, 100, 0), "pwm: bad clock 0");
  if !ch_err_is(pwm_channel(1000000001, 100, 0), "pwm: bad clock 1000000001") { ok = false; }
  if !ch_err_is(pwm_channel(1000, 0, 0), "pwm: bad frequency 0") { ok = false; }
  if !ch_err_is(pwm_channel(1000, 2000, 0), "pwm: frequency 2000 exceeds clock 1000") { ok = false; }
  if !ch_err_is(pwm_channel(1000, 100, -1), "pwm: bad duty -1") { ok = false; }
  if !ch_err_is(pwm_channel(1000, 100, 1001), "pwm: bad duty 1001") { ok = false; }
  if !ch_err_is(pwm_channel(1000, 2000, 5000), "pwm: frequency 2000 exceeds clock 1000") { ok = false; }
  return assert(ok, "channel validation follows the documented order and messages");
}

fn t4() -> TestResult {
  var c = channel_or_zero(1000000, 1000, 0);
  var ok = set_is(pwm_set_duty(&mut c, 250), 250);
  if pwm_duty_permille(&c) != 250 { ok = false; }
  if pwm_duty_ticks(&c) != 250 { ok = false; }
  if !set_is(pwm_set_duty(&mut c, 0), 0) { ok = false; }
  if pwm_duty_ticks(&c) != 0 { ok = false; }
  if !set_is(pwm_set_duty(&mut c, 1000), 1000) { ok = false; }
  if pwm_duty_ticks(&c) != 1000 { ok = false; }
  return assert(ok, "set_duty accepts the 0..1000 range and updates the ticks");
}

fn t5() -> TestResult {
  let c = channel_or_zero(1000000, 1000, 333);
  var ok = pwm_duty_ticks(&c) == 333;
  var c3 = channel_or_zero(1000, 300, 999);
  if pwm_duty_ticks(&c3) != 2 { ok = false; }
  if !set_is(pwm_set_duty(&mut c3, 1000), 1000) { ok = false; }
  if pwm_duty_ticks(&c3) != 3 { ok = false; }
  return assert(ok, "duty ticks floor (period * duty / 1000)");
}

fn t6() -> TestResult {
  var c = channel_or_zero(1000000, 1000, 0);
  var ok = set_is(pwm_set_duty_ticks(&mut c, 250), 250);
  if pwm_duty_permille(&c) != 250 { ok = false; }
  if !set_is(pwm_set_duty_ticks(&mut c, 1000), 1000) { ok = false; }
  if !set_is(pwm_set_duty_ticks(&mut c, 0), 0) { ok = false; }
  if !err_is(pwm_set_duty_ticks(&mut c, 1001), "pwm: bad duty ticks 1001 for period 1000") { ok = false; }
  if !err_is(pwm_set_duty_ticks(&mut c, -1), "pwm: bad duty ticks -1 for period 1000") { ok = false; }
  if pwm_duty_permille(&c) != 0 { ok = false; }
  return assert(ok, "set_duty_ticks bounds ticks to the period");
}

fn t7() -> TestResult {
  var c = channel_or_zero(1000, 300, 0);
  var ok = set_is(pwm_set_duty_ticks(&mut c, 1), 333);
  if pwm_duty_ticks(&c) != 0 { ok = false; }
  return assert(ok, "duty ticks convert back with documented loss");
}

fn t8() -> TestResult {
  let c = channel_or_zero(3, 1, 333);
  var ok = pwm_period_ticks(&c) == 3;
  if pwm_period_micros(&c) != 1000000 { ok = false; }
  if pwm_duty_micros(&c) != 0 { ok = false; }
  let fast = channel_or_zero(1000000, 1000, 250);
  if pwm_duty_micros(&fast) != 250 { ok = false; }
  return assert(ok, "microsecond conversions divide by the clock");
}

fn t9() -> TestResult {
  let slow = channel_or_zero(1000000000, 1, 500);
  var ok = pwm_period_ticks(&slow) == 1000000000;
  if pwm_actual_freq_hz(&slow) != 1 { ok = false; }
  let floored = channel_or_zero(1000, 300, 0);
  if pwm_actual_freq_hz(&floored) != 333 { ok = false; }
  return assert(ok, "actual frequency is clock / floored period");
}

fn t10() -> TestResult {
  let c = channel_or_zero(8000000, 4000, 125);
  var ok = pwm_clock_hz(&c) == 8000000;
  if pwm_freq_hz(&c) != 4000 { ok = false; }
  if pwm_period_ticks(&c) != 2000 { ok = false; }
  if pwm_duty_permille(&c) != 125 { ok = false; }
  if pwm_duty_ticks(&c) != 250 { ok = false; }
  return assert(ok, "channel accessors report the constructed fields");
}

fn t11() -> TestResult {
  var ok = false;
  let r = pwm_servo_duty(90, 0, 180, 0, 1000);
  match r {
    Ok(v) => { ok = v == 500; },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a centered servo maps to half duty");
}

fn t12() -> TestResult {
  var ok = false;
  let a = pwm_servo_duty(0, 0, 180, 0, 1000);
  match a {
    Ok(v) => { ok = v == 0; },
    Err(_) => { ok = false; },
  }
  let b = pwm_servo_duty(180, 0, 180, 0, 1000);
  match b {
    Ok(v) => { if v != 1000 { ok = false; } },
    Err(_) => { ok = false; },
  }
  let c = pwm_servo_duty(0, 0, 180, 50, 100);
  match c {
    Ok(v) => { if v != 50 { ok = false; } },
    Err(_) => { ok = false; },
  }
  let d = pwm_servo_duty(90, 0, 180, 50, 100);
  match d {
    Ok(v) => { if v != 75 { ok = false; } },
    Err(_) => { ok = false; },
  }
  let e = pwm_servo_duty(180, 0, 180, 50, 100);
  match e {
    Ok(v) => { if v != 100 { ok = false; } },
    Err(_) => { ok = false; },
  }
  return assert(ok, "servo endpoints and midpoint interpolate exactly");
}

fn t13() -> TestResult {
  var ok = err_is(pwm_servo_duty(90, 90, 90, 0, 1000), "pwm: bad angle range [90, 90]");
  if !err_is(pwm_servo_duty(90, 0, 180, 0, 1001), "pwm: bad duty range [0, 1001]") { ok = false; }
  if !err_is(pwm_servo_duty(90, 0, 180, 500, 100), "pwm: bad duty range [500, 100]") { ok = false; }
  if !err_is(pwm_servo_duty(200, 0, 180, 0, 1000), "pwm: angle 200 outside [0, 180]") { ok = false; }
  if !err_is(pwm_servo_duty(-1, 0, 180, 0, 1000), "pwm: angle -1 outside [0, 180]") { ok = false; }
  return assert(ok, "servo mapping validates ranges and the angle");
}

fn t14() -> TestResult {
  var ok = false;
  let r = pwm_servo_duty(1, 0, 3, 0, 1000);
  match r {
    Ok(v) => { ok = v == 333; },
    Err(_) => { ok = false; },
  }
  return assert(ok, "servo interpolation floors");
}

fn t15() -> TestResult {
  let r = pwm_servo_channel(1000000, 50, 90, 0, 180, 50, 100);
  var ok = false;
  match r {
    Ok(c) => {
      ok = pwm_period_ticks(&c) == 20000;
      if pwm_duty_permille(&c) != 75 { ok = false; }
      if pwm_duty_ticks(&c) != 1500 { ok = false; }
      if pwm_period_micros(&c) != 20000 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a 50 Hz servo channel maps the angle to ticks");
}

fn t16() -> TestResult {
  var c = channel_or_zero(1000, 1000, 500);
  var ok = pwm_period_ticks(&c) == 1;
  if pwm_duty_ticks(&c) != 0 { ok = false; }
  if !set_is(pwm_set_duty(&mut c, 1000), 1000) { ok = false; }
  if pwm_duty_ticks(&c) != 1 { ok = false; }
  return assert(ok, "a one-tick period still resolves full-on duty");
}

fn t17() -> TestResult {
  let c = channel_or_zero(1000000000, 1, 500);
  var ok = pwm_duty_ticks(&c) == 500000000;
  if pwm_duty_micros(&c) != 500000 { ok = false; }
  if pwm_period_micros(&c) != 1000000 { ok = false; }
  return assert(ok, "the clock guard keeps microsecond math in range");
}

fn t18() -> TestResult {
  var c = channel_or_zero(1000000, 1000, 0);
  let r = pwm_set_duty(&mut c, 750);
  var ok = false;
  match r {
    Ok(v) => { ok = v == 750; },
    Err(_) => { ok = false; },
  }
  if pwm_duty_permille(&c) != 750 { ok = false; }
  if pwm_duty_ticks(&c) != 750 { ok = false; }
  return assert(ok, "set_duty returns the stored duty and mutates the channel");
}

fn t19() -> TestResult {
  var c = channel_or_zero(1000000, 1000, 200);
  var ok = err_is(pwm_set_duty(&mut c, 1001), "pwm: bad duty 1001");
  if pwm_duty_permille(&c) != 200 { ok = false; }
  if !err_is(pwm_set_duty(&mut c, -5), "pwm: bad duty -5") { ok = false; }
  if pwm_duty_permille(&c) != 200 { ok = false; }
  return assert(ok, "a failed set_duty leaves the channel unchanged");
}

fn t20() -> TestResult {
  var ok = ch_err_is(pwm_servo_channel(0, 50, 90, 0, 180, 50, 100), "pwm: bad clock 0");
  if !ch_err_is(pwm_servo_channel(1000000, 50, 200, 0, 180, 50, 100), "pwm: angle 200 outside [0, 180]") { ok = false; }
  return assert(ok, "servo_channel propagates mapping and channel errors");
}

fn main() -> Int {
  io.println("=== xiom.pwm conformance tests ===");
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
    io.println("xiom.pwm: all tests passed");
  } else {
    io.println("xiom.pwm: tests failed");
  }
  return failed;
}
