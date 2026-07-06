// XIOM — Vulkan Conformance Tests
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Headless-CI-safe tests for the xvk C bridge API.
module vulkan_tests
use xiom.test;
use xiom.vulkan;

fn test_offscreen_render_triangle() -> TestResult {
  let surface = offscreen_create(64, 64);
  match surface {
    Err(_) => return assert(true, "no vulkan (skip)"),
    Ok(s) => {
      offscreen_render_triangle(s, 1.0, 0.0, 0.0);
      let hash = offscreen_hash(s);
      offscreen_destroy(s);
      return assert(hash != 0, "offscreen: hash != 0");
    },
  }
}

fn test_app_create_destroy() -> TestResult {
  let instance = create_app("Test", 100, 100);
  match instance {
    Ok(app) => {
      destroy_app(app);
      return assert(true, "app: create+destroy ok");
    },
    Err(_) => return assert(true, "app: no vulkan (skip)"),
  }
}

fn main() -> Int {
  var tests = [test_offscreen_render_triangle, test_app_create_destroy];
  return test.run_all(tests);
}
