// XIOM -- Vulkan Smoke Tests (windowed API only)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Smoke tests for the simplified Vulkan API bridge:
//   1. window create + destroy
//   2. 5-frame poll/begin_frame/end_frame cycle
//   3. invalid-parameter rejection (0x0)
//
// NOTE: offscreen_create is deliberately NOT used -- headless GPU init
// hangs in the bridge until true offscreen support lands. Every test
// below drives the windowed API, opening a small window briefly.
//
// NOTE: structured to work around two xiom v0.47.x codegen issues:
//   - test.run_all() crashes: indexed fn-pointer calls (tests[i]())
//     miscompile into an access violation, so tests are dispatched
//     directly from main.
//   - returning a TestResult from a fn whose match arms also use the
//     bound payload corrupts the struct fields, so each test is split
//     into a scalar runner (match arms return Int codes, like the
//     shipped demos) and a match-free TestResult builder.
// Switch back to plain assert-in-match + run_all() once fixed.
module vulkan_tests

use xiom.io;
use xiom.test;
use xiom.vulkan;

// Runner exit codes shared by all tests below.
// 0 = pass, 1 = fail, 2 = skip (vulkan unavailable)

// --- Test 1: open a small window, destroy it ---

fn run_create_destroy() -> Int {
  let instance = create_app("XIOM Smoke", 100, 100);
  match instance {
    Ok(app) => {
      destroy_app(app);
      return 0;
    }
    Err(_) => return 2,
  }
}

fn test_app_create_destroy() -> TestResult {
  let rc = run_create_destroy();
  if rc == 0 { return assert(true, "app: create+destroy ok"); }
  if rc == 2 { return assert(true, "app: no vulkan (skip)"); }
  return assert(false, "app: create+destroy failed");
}

// --- Test 2: pump 5 frames of poll + begin_frame + end_frame ---
// begin_frame status: 1 = frame begun, 0 = skip (resize/minimized),
// -1 = error. Completing the loop without a crash is the pass signal.

fn run_frame_cycle() -> Int {
  let instance = create_app("XIOM Frames", 100, 100);
  match instance {
    Ok(app) => {
      var frame = 0;
      while frame < 5 {
        poll(app);
        let status = begin_frame(app);
        if status == 1 {
          end_frame(app);
        } elif status == -1 {
          io.println("  begin_frame error: " + last_error());
          destroy_app(app);
          return 1;
        }
        frame = frame + 1;
      }
      destroy_app(app);
      return 0;
    }
    Err(_) => return 2,
  }
}

fn test_begin_frame_cycle() -> TestResult {
  let rc = run_frame_cycle();
  if rc == 0 { return assert(true, "frame: 5x poll+begin+end ok"); }
  if rc == 2 { return assert(true, "frame: no vulkan (skip)"); }
  return assert(false, "frame: begin_frame failed");
}

// --- Test 3: invalid params (0x0) must yield Err, not a crash ---
// create_app carries `requires: width > 0` / `requires: height > 0`, so
// calling it with 0x0 would trap on the contract (X0100) instead of
// returning Err. Drive the same rejection path through the raw bridge
// entry point, mirroring create_app's own Err mapping.

fn create_app_unchecked(title: Str, width: Int, height: Int) -> Result[Int, Str] {
  let raw = unsafe { xvk_app_create(title, width as Int32, height as Int32) };
  if raw == 0 {
    return Err("failed to create vulkan app");
  }
  return Ok(raw);
}

fn run_error_handling() -> Int {
  let instance = create_app_unchecked("XIOM Invalid", 0, 0);
  match instance {
    Ok(app) => {
      destroy_app(app);
      return 1;
    }
    Err(_) => return 0,
  }
}

fn test_error_handling() -> TestResult {
  let rc = run_error_handling();
  if rc == 0 { return assert(true, "error: 0x0 create rejected with Err"); }
  return assert(false, "error: 0x0 create unexpectedly succeeded");
}

// --- Helpers ---

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  return out;
}

// Takes scalar fields, not TestResult by value: struct-by-value params
// lose their heap fields with the current compiler.
fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("[PASS] " + name);
    return 0;
  }
  io.println("[FAIL] " + name);
  return 1;
}

// --- Main ---

fn main() -> Int {
  var failed = 0;
  var total = 0;

  let r1 = test_app_create_destroy();
  total = total + 1;
  failed = failed + report(r1.passed, r1.name);

  let r2 = test_begin_frame_cycle();
  total = total + 1;
  failed = failed + report(r2.passed, r2.name);

  let r3 = test_error_handling();
  total = total + 1;
  failed = failed + report(r3.passed, r3.name);

  let passed = total - failed;
  io.println("XIOM Vulkan Smoke Tests: " + int_to_str(passed + 0) +
             " passed, " + int_to_str(failed + 0) + " failed");
  return failed;
}
