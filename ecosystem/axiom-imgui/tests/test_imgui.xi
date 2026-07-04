// XIOM — ImGui Conformance Tests
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

module imgui_tests
use xiom.test;
use xiom.imgui;

fn test_create_context() -> TestResult {
  create_context();
  return assert(true, "imgui create context");
}

fn main() -> Int {
  var tests = [test_create_context];
  return test.run_all(tests);
}
