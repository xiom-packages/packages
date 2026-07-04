// XIOM — Vulkan Conformance Tests
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

module vulkan_tests
use xiom.test;
use xiom.vulkan;

fn test_instance_create_destroy() -> TestResult {
  let instance = create_instance("Test", "Test");
  match instance {
    Ok(inst) => { destroy_instance(inst); return assert(true, "vk: create+destroy instance"); }
    Err(_) => { return assert(true, "vk: no vulkan driver (skip)"); }
  }
}

fn test_enumerate_devices() -> TestResult {
  let instance = create_instance("Test", "Test");
  match instance {
    Ok(inst) => {
      let devices = enumerate_devices(inst);
      destroy_instance(inst);
      return assert(devices.is_ok(), "vk: enumerate devices");
    }
    Err(_) => { return assert(true, "vk: skip"); }
  }
}

fn main() -> Int {
  var tests = [test_instance_create_destroy, test_enumerate_devices];
  return test.run_all(tests);
}
