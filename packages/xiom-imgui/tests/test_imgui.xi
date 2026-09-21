// XIOM -- ImGui Conformance Tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
module imgui_tests
use xiom.test;
use xiom.imgui;

fn test_create_context_null_window() -> TestResult {
  // Null window: should return false gracefully without crashing
  let ok = create_context(0);
  return assert(!ok, "imgui: null window rejected gracefully (no crash)");
}

fn main() -> Int {
  var tests = [test_create_context_null_window];
  return test.run_all(tests);
}
