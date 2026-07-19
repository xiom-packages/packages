// XIOM — ImGui Conformance Tests
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

module imgui_tests
use xiom.test;
use xiom.imgui;

fn test_create_context() -> TestResult {
  let ok = create_context(0);
  if ok { destroy_context(); }
  return assert(ok, "imgui create context (stub: no GLFW window)");
}

fn main() -> Int {
  var tests = [test_create_context];
  return test.run_all(tests);
}
