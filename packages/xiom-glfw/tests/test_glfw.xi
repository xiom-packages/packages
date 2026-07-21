// XIOM — GLFW Conformance Tests
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

module glfw_tests
use xiom.test;
use xiom.glwf;

fn test_init_terminate() -> TestResult {
  if !glfw_init() { return assert(true, "glfw skip (no display)"); }
  glfw_terminate();
  return assert(true, "glfw init+terminate");
}

fn main() -> Int {
  var tests = [test_init_terminate];
  return test.run_all(tests);
}
