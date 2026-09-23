// XIOM -- xiom.option conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage: option_map_int, option_flat_map_int, option_filter_int,
// option_unwrap_or_int, option_unwrap_or_else_int, option_or_else_int,
// option_to_result_int, option_from_result_int, option_map_str,
// option_unwrap_or_str, option_to_result_str, result_map_int,
// result_unwrap_or_int, result_ok_int, result_err_str, result_to_option_int.
//
// Every callback is a NAMED top-level function: the compiler rejects (and
// miscompiles) inline lambdas in function-pointer position.

module option_tests
use xiom.io; use xiom.test;
use xiom.option;

// --- named callbacks -------------------------------------------------------

fn double(x: &Int) -> Int { return *x * 2; }

fn is_even(x: &Int) -> Bool { return *x % 2 == 0; }

fn zero() -> Int { return 0; }

fn shout(s: &Str) -> Str {
  let t = *s;
  return t + "!";
}

fn double_if_even(x: &Int) -> Option[Int] {
  if *x % 2 == 0 {
    return Some(*x * 2);
  }
  return None;
}

// Ok/Err are constructed through these helpers: constructing them directly
// inside a function that returns a struct (TestResult here) miscompiles in
// compiler v0.61.3 (IR temp gets the enclosing return struct type).
// See SPEC.md "Known limitations" (compiler issue).
fn make_ok(v: Int) -> Result[Int, Str] { return Ok(v); }

fn make_err(msg: Str) -> Result[Int, Str] { return Err(msg); }

// --- Option[Int]: map / flat_map / filter ----------------------------------

fn t1() -> TestResult {
  let o: Option[Int] = Some(3);
  let r = option_map_int(o, double);
  var ok = false;
  match r {
    Some(v) => { ok = v == 6; },
    None => { ok = false; },
  }
  return assert(ok, "map Some(3) => Some(6)");
}

fn t2() -> TestResult {
  let o: Option[Int] = None;
  let r = option_map_int(o, double);
  var saw_some = false;
  match r {
    Some(_) => { saw_some = true; },
    None => {},
  }
  return assert(!saw_some, "map None => None");
}

fn t3() -> TestResult {
  let o: Option[Int] = Some(4);
  let r = option_flat_map_int(o, double_if_even);
  var ok = false;
  match r {
    Some(v) => { ok = v == 8; },
    None => { ok = false; },
  }
  return assert(ok, "flat_map Some(4) => Some(8)");
}

fn t4() -> TestResult {
  let o: Option[Int] = Some(5);
  let r = option_flat_map_int(o, double_if_even);
  var ok = false;
  match r {
    Some(_) => { ok = false; },
    None => { ok = true; },
  }
  return assert(ok, "flat_map Some(5) => None");
}

fn t5() -> TestResult {
  let o: Option[Int] = Some(4);
  let r = option_filter_int(o, is_even);
  var ok = false;
  match r {
    Some(v) => { ok = v == 4; },
    None => { ok = false; },
  }
  return assert(ok, "filter Some(4) is_even => Some(4)");
}

fn t6() -> TestResult {
  let o: Option[Int] = Some(5);
  let r = option_filter_int(o, is_even);
  var ok = false;
  match r {
    Some(_) => { ok = false; },
    None => { ok = true; },
  }
  return assert(ok, "filter Some(5) is_even => None");
}

// --- Option[Int]: unwrap / or_else -----------------------------------------

fn t7() -> TestResult {
  let o: Option[Int] = Some(9);
  let r = option_unwrap_or_int(o, 0);
  return assert(r == 9, "unwrap_or Some(9) => 9");
}

fn t8() -> TestResult {
  let o: Option[Int] = None;
  let r = option_unwrap_or_int(o, 7);
  return assert(r == 7, "unwrap_or None fallback => 7");
}

fn t9() -> TestResult {
  let o: Option[Int] = Some(9);
  let r = option_unwrap_or_else_int(o, zero);
  return assert(r == 9, "unwrap_or_else Some(9) => 9");
}

fn t10() -> TestResult {
  let o: Option[Int] = None;
  let r = option_unwrap_or_else_int(o, zero);
  return assert(r == 0, "unwrap_or_else None => zero()");
}

fn t11() -> TestResult {
  let o: Option[Int] = Some(1);
  let alt: Option[Int] = Some(2);
  let r = option_or_else_int(o, alt);
  var ok = false;
  match r {
    Some(v) => { ok = v == 1; },
    None => { ok = false; },
  }
  return assert(ok, "or_else Some(1) keeps Some(1)");
}

fn t12() -> TestResult {
  let o: Option[Int] = None;
  let alt: Option[Int] = Some(2);
  let r = option_or_else_int(o, alt);
  var ok = false;
  match r {
    Some(v) => { ok = v == 2; },
    None => { ok = false; },
  }
  return assert(ok, "or_else None falls back to Some(2)");
}

// --- Option[Int] <-> Result[Int, Str] --------------------------------------

fn t13() -> TestResult {
  let o: Option[Int] = Some(5);
  let r = option_to_result_int(o, "missing");
  var ok = false;
  match r {
    Ok(v) => { ok = v == 5; },
    Err(_) => { ok = false; },
  }
  return assert(ok, "to_result Some(5) => Ok(5)");
}

fn t14() -> TestResult {
  let o: Option[Int] = None;
  let r = option_to_result_int(o, "missing");
  var ok = false;
  match r {
    Ok(_) => { ok = false; },
    Err(e) => { ok = e == "missing"; },
  }
  return assert(ok, "to_result None => Err(message)");
}

fn t15() -> TestResult {
  let r = make_ok(6);
  let o = option_from_result_int(r);
  var ok = false;
  match o {
    Some(v) => { ok = v == 6; },
    None => { ok = false; },
  }
  return assert(ok, "from_result Ok(6) => Some(6)");
}

fn t16() -> TestResult {
  let r = make_err("boom");
  let o = option_from_result_int(r);
  var saw_some = false;
  match o {
    Some(_) => { saw_some = true; },
    None => {},
  }
  return assert(!saw_some, "from_result Err => None");
}

// --- Option[Str] ------------------------------------------------------------

fn t17() -> TestResult {
  let o: Option[Str] = Some("hi");
  let r = option_map_str(o, shout);
  var ok = false;
  match r {
    Some(v) => { ok = v == "hi!"; },
    None => { ok = false; },
  }
  return assert(ok, "map_str Some(\"hi\") => Some(\"hi!\")");
}

fn t18() -> TestResult {
  let o: Option[Str] = None;
  let r = option_map_str(o, shout);
  var saw_some = false;
  match r {
    Some(_) => { saw_some = true; },
    None => {},
  }
  return assert(!saw_some, "map_str None => None");
}

fn t19() -> TestResult {
  let o: Option[Str] = Some("hi");
  let r = option_unwrap_or_str(o, "fallback");
  return assert(r == "hi", "unwrap_or_str Some(\"hi\") => \"hi\"");
}

fn t20() -> TestResult {
  let o: Option[Str] = None;
  let r = option_unwrap_or_str(o, "fallback");
  return assert(r == "fallback", "unwrap_or_str None => fallback");
}

fn t21() -> TestResult {
  let o: Option[Str] = Some("hi");
  let r = option_to_result_str(o, "nostr");
  var ok = false;
  match r {
    Ok(v) => { ok = v == "hi"; },
    Err(_) => { ok = false; },
  }
  return assert(ok, "to_result_str Some(\"hi\") => Ok(\"hi\")");
}

fn t22() -> TestResult {
  let o: Option[Str] = None;
  let r = option_to_result_str(o, "nostr");
  var ok = false;
  match r {
    Ok(_) => { ok = false; },
    Err(e) => { ok = e == "nostr"; },
  }
  return assert(ok, "to_result_str None => Err(\"nostr\")");
}

// --- Result[Int, Str] -------------------------------------------------------

fn t23() -> TestResult {
  let r = make_ok(4);
  let m = result_map_int(r, double);
  var ok = false;
  match m {
    Ok(v) => { ok = v == 8; },
    Err(_) => { ok = false; },
  }
  return assert(ok, "result_map Ok(4) => Ok(8)");
}

fn t24() -> TestResult {
  let r = make_err("bad");
  let m = result_map_int(r, double);
  var ok = false;
  match m {
    Ok(_) => { ok = false; },
    Err(e) => { ok = e == "bad"; },
  }
  return assert(ok, "result_map Err passes through");
}

fn t25() -> TestResult {
  let r = make_ok(3);
  let v = result_unwrap_or_int(r, 0);
  return assert(v == 3, "result_unwrap_or Ok(3) => 3");
}

fn t26() -> TestResult {
  let r = make_err("x");
  let v = result_unwrap_or_int(r, 12);
  return assert(v == 12, "result_unwrap_or Err => fallback");
}

fn t27() -> TestResult {
  let r = make_ok(8);
  let o = result_ok_int(r);
  var ok = false;
  match o {
    Some(v) => { ok = v == 8; },
    None => { ok = false; },
  }
  return assert(ok, "result_ok Ok(8) => Some(8)");
}

fn t28() -> TestResult {
  let r = make_err("x");
  let o = result_ok_int(r);
  var saw_some = false;
  match o {
    Some(_) => { saw_some = true; },
    None => {},
  }
  return assert(!saw_some, "result_ok Err => None");
}

fn t29() -> TestResult {
  let r = make_err("boom");
  let o = result_err_str(r);
  var ok = false;
  match o {
    Some(e) => { ok = e == "boom"; },
    None => { ok = false; },
  }
  return assert(ok, "result_err Err(\"boom\") => Some(\"boom\")");
}

fn t30() -> TestResult {
  let r = make_ok(1);
  let o = result_err_str(r);
  var saw_some = false;
  match o {
    Some(_) => { saw_some = true; },
    None => {},
  }
  return assert(!saw_some, "result_err Ok => None");
}

fn t31() -> TestResult {
  let r = make_ok(11);
  let o = result_to_option_int(r);
  var ok = false;
  match o {
    Some(v) => { ok = v == 11; },
    None => { ok = false; },
  }
  return assert(ok, "result_to_option Ok(11) => Some(11)");
}

fn t32() -> TestResult {
  let r = make_err("no");
  let o = result_to_option_int(r);
  var saw_some = false;
  match o {
    Some(_) => { saw_some = true; },
    None => {},
  }
  return assert(!saw_some, "result_to_option Err => None");
}

fn main() -> Int {
  io.println("=== xiom.option conformance tests ===");
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
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  let r29 = t29();
  if r29.passed { io.println("  [PASS] " + r29.name); } else { io.println("  [FAIL] " + r29.name); failed = failed + 1; }
  let r30 = t30();
  if r30.passed { io.println("  [PASS] " + r30.name); } else { io.println("  [FAIL] " + r30.name); failed = failed + 1; }
  let r31 = t31();
  if r31.passed { io.println("  [PASS] " + r31.name); } else { io.println("  [FAIL] " + r31.name); failed = failed + 1; }
  let r32 = t32();
  if r32.passed { io.println("  [PASS] " + r32.name); } else { io.println("  [FAIL] " + r32.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.option: all tests passed");
  } else {
    io.println("xiom.option: tests failed");
  }
  return failed;
}
