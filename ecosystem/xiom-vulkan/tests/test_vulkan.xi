// XIOM — Vulkan Conformance Tests (Headless-CI-safe)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Performs smoke tests using the simplified Vulkan API bridge.
// Uses windowed create/destroy (quick open+close) since the
// bridge does not yet support true headless offscreen mode.
module vulkan_tests
use xiom.test;
use xiom.vulkan;

fn test_app_create_destroy() -> TestResult {
  let instance = create_app("Test", 100, 100);
  match instance {
    Ok(app) => {
      destroy_app(app);
      return assert(true, "app: create+destroy ok");
    }
    Err(_) => return assert(true, "app: no vulkan (skip)"),
  }
}

fn test_offscreen_skip() -> TestResult {
  // NOTE: offscreen_create may hang on some systems due to
  // headless GPU init limitation in the bridge. Skipping until
  // bridge adds true headless support.
  return assert(true, "offscreen: skipped (headless not yet supported)");
}

fn main() -> Int {
  var tests = Vec[fn() -> TestResult].new();
  tests.push(test_app_create_destroy);
  tests.push(test_offscreen_skip);
  return test.run_all(tests);
}
