// XIOM -- xiom.flags conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// 18 tests covering the documented xiom.flags API: value forms, short flags,
// booleans, error paths, duplicates, the `--` terminator, positionals,
// integer values, help text, and environment fallback.

module flags_tests
use xiom.io; use xiom.test;
use xiom.string; use xiom.string.compare;
use xiom.env;
use xiom.flags;

fn argv0() -> Vec[Str] {
  return Vec[Str].new();
}
fn argv1(a: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  return v;
}
fn argv2(a: Str, b: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  return v;
}
fn argv3(a: Str, b: Str, c: Str) -> Vec[Str] {
  var v = Vec[Str].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}
fn is_ok(r: Result[Unit, Str]) -> Bool {
  match r {
    Ok(_) => return true;
    Err(_) => return false;
  }
}
fn is_err(r: Result[Unit, Str]) -> Bool {
  match r {
    Ok(_) => return false;
    Err(_) => return true;
  }
}
fn err_text(r: Result[Unit, Str]) -> Str {
  match r {
    Ok(_) => return "";
    Err(e) => return e;
  }
}
fn val_ok(p: &FlagParser, n: Str, expect: Str) -> Bool {
  let v = flags_value(p, n);
  match v {
    Some(s) => return str_compare(s, expect) == 0;
    None => return false;
  }
}
fn val_none(p: &FlagParser, n: Str) -> Bool {
  let v = flags_value(p, n);
  match v {
    Some(_) => return false;
    None => return true;
  }
}
fn intval_ok(p: &FlagParser, n: Str, expect: Int) -> Bool {
  let r = flags_int_value(p, n);
  match r {
    Ok(x) => return x == expect;
    Err(_) => return false;
  }
}
fn intval_err(p: &FlagParser, n: Str) -> Bool {
  let r = flags_int_value(p, n);
  match r {
    Ok(_) => return false;
    Err(_) => return true;
  }
}
fn pos_at_ok(p: &FlagParser, idx: Int, expect: Str) -> Bool {
  let pos = flags_positionals(p);
  if idx >= pos.len() { return false; }
  return str_compare(pos[idx], expect) == 0;
}

fn t1() -> TestResult {
  var p = flags_new();
  let _ = flags_flag(&mut p, "name", "", true, false, "", "the name");
  let r = flags_parse(&mut p, &argv1("--name=alice"));
  if !is_ok(r) { return assert(false, "inline --name=alice parses"); }
  return assert(val_ok(&p, "name", "alice"), "inline --name=alice value");
}
fn t2() -> TestResult {
  var p = flags_new();
  let _ = flags_flag(&mut p, "name", "", true, false, "", "");
  let r = flags_parse(&mut p, &argv2("--name", "bob"));
  if !is_ok(r) { return assert(false, "spaced --name bob parses"); }
  return assert(val_ok(&p, "name", "bob"), "spaced --name bob value");
}
fn t3() -> TestResult {
  var p = flags_new();
  let _ = flags_flag(&mut p, "output", "o", true, false, "", "");
  let r = flags_parse(&mut p, &argv2("-o", "out.txt"));
  if !is_ok(r) { return assert(false, "short -o value parses"); }
  return assert(val_ok(&p, "output", "out.txt"), "short -o out.txt value");
}
fn t4() -> TestResult {
  var p = flags_new();
  let _ = flags_flag(&mut p, "verbose", "v", false, false, "", "");
  let r = flags_parse(&mut p, &argv1("-v"));
  if !is_ok(r) { return assert(false, "short -v parses"); }
  return assert(flags_has(&p, "verbose") && val_ok(&p, "verbose", "true"), "boolean short -v presence");
}
fn t5() -> TestResult {
  var p = flags_new();
  let _ = flags_flag(&mut p, "name", "", true, false, "", "");
  let r = flags_parse(&mut p, &argv1("--bogus"));
  if !is_err(r) { return assert(false, "unknown --bogus is Err"); }
  return assert(str_compare(err_text(r), "unknown flag: --bogus") == 0, "unknown flag message");
}
fn t6() -> TestResult {
  var p = flags_new();
  let _ = flags_flag(&mut p, "out", "o", true, false, "", "");
  let r = flags_parse(&mut p, &argv1("--out"));
  if !is_err(r) { return assert(false, "missing --out value is Err"); }
  return assert(str_compare(err_text(r), "missing value for: --out") == 0, "missing value message");
}
fn t7() -> TestResult {
  var p = flags_new();
  let _ = flags_flag(&mut p, "must", "", true, true, "", "");
  let r = flags_parse(&mut p, &argv0());
  if !is_err(r) { return assert(false, "missing required flag is Err"); }
  return assert(str_compare(err_text(r), "missing required flag: --must") == 0, "required missing message");
}
fn t8() -> TestResult {
  var p = flags_new();
  let _ = flags_flag(&mut p, "token", "", true, true, "XIOM_FLAGS_TEST_TOKEN", "");
  set_var("XIOM_FLAGS_TEST_TOKEN", "s3cr3t");
  let r = flags_parse(&mut p, &argv0());
  let ok = is_ok(r);
  let vok = val_ok(&p, "token", "s3cr3t");
  let h = flags_has(&p, "token");
  clear_var("XIOM_FLAGS_TEST_TOKEN");
  return assert(ok && vok && h, "required satisfied by environment");
}
fn t9() -> TestResult {
  var p = flags_new();
  let _ = flags_flag(&mut p, "name", "", true, false, "", "");
  let r = flags_parse(&mut p, &argv2("--name=bob", "--name=carol"));
  if !is_ok(r) { return assert(false, "duplicate --name parses"); }
  return assert(val_ok(&p, "name", "carol"), "duplicate occurrences: last one wins");
}
fn t10() -> TestResult {
  var p = flags_new();
  let _ = flags_flag(&mut p, "name", "", true, false, "", "");
  let r = flags_parse(&mut p, &argv3("--", "--name=x", "-z"));
  if !is_ok(r) { return assert(false, "-- terminator parses"); }
  let n = flags_positionals(&p).len();
  let quiet = !flags_has(&p, "name");
  return assert(n == 2 && quiet && pos_at_ok(&p, 0, "--name=x") && pos_at_ok(&p, 1, "-z"), "-- terminator: rest are positionals");
}
fn t11() -> TestResult {
  var p = flags_new();
  let _ = flags_flag(&mut p, "name", "", true, false, "", "");
  let r = flags_parse(&mut p, &argv3("build", "--name=alice", "extra"));
  if !is_ok(r) { return assert(false, "positionals sample parses"); }
  let n = flags_positionals(&p).len();
  return assert(n == 2 && pos_at_ok(&p, 0, "build") && pos_at_ok(&p, 1, "extra"), "positionals preserved in order");
}
fn t12() -> TestResult {
  var p = flags_new();
  let _ = flags_flag(&mut p, "count", "", true, false, "", "");
  let r = flags_parse(&mut p, &argv1("--count=42"));
  if !is_ok(r) { return assert(false, "--count=42 parses"); }
  return assert(intval_ok(&p, "count", 42), "int_value ok for 42");
}
fn t13() -> TestResult {
  var p = flags_new();
  let _ = flags_flag(&mut p, "count", "", true, false, "", "");
  let r = flags_parse(&mut p, &argv1("--count=abc"));
  if !is_ok(r) { return assert(false, "--count=abc parses"); }
  return assert(intval_err(&p, "count"), "int_value malformed is Err");
}
fn t14() -> TestResult {
  var p = flags_new();
  let _ = flags_flag(&mut p, "output", "o", true, true, "XIOM_FLAGS_HP", "write output");
  let h = flags_help(&p);
  let all = str_contains(h, "--output") && str_contains(h, "-o") && str_contains(h, "VALUE");
  return assert(all && str_contains(h, "(required)") && str_contains(h, "[env: XIOM_FLAGS_HP]"), "help lists flag metadata");
}
fn t15() -> TestResult {
  var p = flags_new();
  let _ = flags_flag(&mut p, "region", "", true, false, "XIOM_FLAGS_TEST_REGION", "");
  set_var("XIOM_FLAGS_TEST_REGION", "eu-west-1");
  let r = flags_parse(&mut p, &argv0());
  let ok = is_ok(r);
  let vok = val_ok(&p, "region", "eu-west-1");
  clear_var("XIOM_FLAGS_TEST_REGION");
  return assert(ok && vok, "env fallback value when flag absent");
}
fn t16() -> TestResult {
  var p = flags_new();
  let _ = flags_flag(&mut p, "count", "", true, false, "", "");
  let r = flags_parse(&mut p, &argv0());
  if !is_ok(r) { return assert(false, "empty args parse"); }
  let e = flags_int_value(&p, "count");
  let msg_ok = match e {
    Ok(_) => false;
    Err(m) => str_compare(m, "flag not provided: count") == 0;
  };
  return assert(val_none(&p, "count") && msg_ok, "value None and int_value Err when not provided");
}
fn t17() -> TestResult {
  var p = flags_new();
  let _ = flags_flag(&mut p, "verbose", "", false, false, "", "");
  let r = flags_parse(&mut p, &argv1("--verbose"));
  if !is_ok(r) { return assert(false, "long --verbose parses"); }
  return assert(flags_has(&p, "verbose"), "boolean long --verbose presence");
}
fn t18() -> TestResult {
  var p = flags_new();
  let r = flags_parse_process(&mut p);
  return assert(is_ok(r), "parse_process runs with no declared flags");
}

fn main() -> Int {
  io.println("=== xiom.flags conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.flags: all tests passed");
  } else {
    io.println("xiom.flags: tests failed");
  }
  return failed;
}
