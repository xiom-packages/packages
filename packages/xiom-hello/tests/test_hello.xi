// XIOM -- xiom.hello conformance tests
// Copyright (c) 2026 Eleftherios Notas and XIOM Foundation
// SPDX-License-Identifier: MIT OR Apache-2.0

module hello_tests
use xiom.io; use xiom.test;
use xiom.hello;

fn t1() -> TestResult {
  return assert(greeting() == "Hello from xiom.hello!", "greeting text");
}
fn t2() -> TestResult {
  return assert(greet("Ada") == "Hello, Ada!", "greet by name");
}
fn t3() -> TestResult {
  return assert(greet("") == greeting(), "greet empty falls back to greeting");
}
fn t4() -> TestResult {
  return assert(greeting().len() > 0, "greeting is not empty");
}

fn main() -> Int {
  io.println("=== xiom.hello conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.hello: all tests passed");
  } else {
    io.println("xiom.hello: tests failed");
  }
  return failed;
}
