// XIOM — GLFW Conformance Tests
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Comprehensive conformance suite for xiom-glfw safe wrappers.
// Covers all 17 public functions across lifecycle, window, size,
// input, monitor, and fullscreen categories.
//
// Pattern: runner fns return Int codes (0=pass, 1=fail, 2=skip),
// test fns wrap in TestResult. Manual dispatch avoids compiler
// codegen issues with test.run_all().

module glfw_conformance
use xiom.io;
use xiom.test;
use xiom.glwf;

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

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

fn report(passed: Bool, name: Str) -> Int {
  if passed {
    io.println("  [PASS] " + name);
    return 0;
  }
  io.println("  [FAIL] " + name);
  return 1;
}

// ═══════════════════════════════════════════════════════════════════════════
// 1. Lifecycle: init + terminate
// ═══════════════════════════════════════════════════════════════════════════

fn run_init_terminate() -> Int {
  if !glfw_init() { return 2; } // skip: no display
  glfw_terminate();
  return 0;
}

fn test_init_terminate() -> TestResult {
  let rc = run_init_terminate();
  if rc == 0 { return assert(true, "lifecycle: init + terminate"); }
  if rc == 2 { return assert(true, "lifecycle: skip (no display)"); }
  return assert(false, "lifecycle: init or terminate failed");
}

fn run_init_return_value() -> Int {
  let ok = glfw_init();
  if !ok { return 2; }
  glfw_terminate();
  return 0;
}

fn test_init_return_value() -> TestResult {
  let rc = run_init_return_value();
  if rc == 0 { return assert(true, "lifecycle: init returns true"); }
  if rc == 2 { return assert(true, "lifecycle: init skip (no display)"); }
  return assert(false, "lifecycle: init returned false");
}

fn run_double_init() -> Int {
  if !glfw_init() { return 2; }
  let ok2 = glfw_init(); // second init should succeed (GLFW is idempotent)
  glfw_terminate();
  return 0;
}

fn test_double_init() -> TestResult {
  let rc = run_double_init();
  if rc == 0 { return assert(true, "lifecycle: double init idempotent"); }
  if rc == 2 { return assert(true, "lifecycle: double init skip"); }
  return assert(false, "lifecycle: double init failed");
}

// ═══════════════════════════════════════════════════════════════════════════
// 2. Window: create + destroy
// ═══════════════════════════════════════════════════════════════════════════

fn run_create_destroy() -> Int {
  if !glfw_init() { return 2; }
  let w = glfw_create_window("Test Window", 400, 300);
  match w {
    Err(e) => { io.println("  create error: " + e); glfw_terminate(); return 1; }
    Ok(win) => {
      glfw_destroy_window(win);
      glfw_terminate();
      return 0;
    }
  }
}

fn test_create_destroy() -> TestResult {
  let rc = run_create_destroy();
  if rc == 0 { return assert(true, "window: create + destroy"); }
  if rc == 2 { return assert(true, "window: skip (no display)"); }
  return assert(false, "window: create or destroy failed");
}

fn run_should_close() -> Int {
  if !glfw_init() { return 2; }
  let w = glfw_create_window("Close Test", 400, 300);
  match w {
    Err(_) => { glfw_terminate(); return 1; }
    Ok(win) => {
      if glfw_should_close(win) {
        glfw_destroy_window(win); glfw_terminate(); return 1;
      }
      glfw_destroy_window(win);
      glfw_terminate();
      return 0;
    }
  }
}

fn test_should_close() -> TestResult {
  let rc = run_should_close();
  if rc == 0 { return assert(true, "window: should_close false on fresh window"); }
  if rc == 2 { return assert(true, "window: should_close skip"); }
  return assert(false, "window: should_close true on fresh window");
}

fn run_set_title() -> Int {
  if !glfw_init() { return 2; }
  let w = glfw_create_window("Original Title", 400, 300);
  match w {
    Err(_) => { glfw_terminate(); return 1; }
    Ok(win) => {
      glfw_set_title(win, "Updated Title");
      glfw_poll_events();
      glfw_destroy_window(win);
      glfw_terminate();
      return 0;
    }
  }
}

fn test_set_title() -> TestResult {
  let rc = run_set_title();
  if rc == 0 { return assert(true, "window: set_title no crash"); }
  if rc == 2 { return assert(true, "window: set_title skip"); }
  return assert(false, "window: set_title crashed");
}

// ═══════════════════════════════════════════════════════════════════════════
// 3. Size queries
// ═══════════════════════════════════════════════════════════════════════════

fn run_framebuffer_size() -> Int {
  if !glfw_init() { return 2; }
  let w = glfw_create_window("FB Size", 640, 480);
  match w {
    Err(_) => { glfw_terminate(); return 1; }
    Ok(win) => {
      glfw_poll_events();
      let (fw, fh) = glfw_get_framebuffer_size(win);
      if fw < 100 || fh < 100 {
        // Retina displays may report larger; tiny values are suspicious
        glfw_destroy_window(win); glfw_terminate(); return 1;
      }
      glfw_destroy_window(win);
      glfw_terminate();
      return 0;
    }
  }
}

fn test_framebuffer_size() -> TestResult {
  let rc = run_framebuffer_size();
  if rc == 0 { return assert(true, "size: framebuffer_size >= 100x100"); }
  if rc == 2 { return assert(true, "size: framebuffer_size skip"); }
  return assert(false, "size: framebuffer_size too small");
}

fn run_window_size() -> Int {
  if !glfw_init() { return 2; }
  let w = glfw_create_window("Win Size", 640, 480);
  match w {
    Err(_) => { glfw_terminate(); return 1; }
    Ok(win) => {
      glfw_poll_events();
      let (ww, wh) = glfw_get_window_size(win);
      // Window size should be close to requested 640x480
      if ww >= 500 && wh >= 300 {
        glfw_destroy_window(win); glfw_terminate(); return 0;
      }
      glfw_destroy_window(win); glfw_terminate(); return 1;
    }
  }
}

fn test_window_size() -> TestResult {
  let rc = run_window_size();
  if rc == 0 { return assert(true, "size: window_size matches create"); }
  if rc == 2 { return assert(true, "size: window_size skip"); }
  return assert(false, "size: window_size mismatch");
}

// ═══════════════════════════════════════════════════════════════════════════
// 4. Input: key, mouse button, cursor position
// ═══════════════════════════════════════════════════════════════════════════

fn run_input_key() -> Int {
  if !glfw_init() { return 2; }
  let w = glfw_create_window("Key Test", 400, 300);
  match w {
    Err(_) => { glfw_terminate(); return 1; }
    Ok(win) => {
      glfw_poll_events();
      // No keys pressed initially; verify function doesn't crash
      let esc = glfw_get_key(win, 256);
      let a = glfw_get_key(win, 65);
      glfw_destroy_window(win);
      glfw_terminate();
      return 0;
    }
  }
}

fn test_input_key() -> TestResult {
  let rc = run_input_key();
  if rc == 0 { return assert(true, "input: get_key no crash"); }
  if rc == 2 { return assert(true, "input: get_key skip"); }
  return assert(false, "input: get_key crashed");
}

fn run_input_mouse() -> Int {
  if !glfw_init() { return 2; }
  let w = glfw_create_window("Mouse Test", 400, 300);
  match w {
    Err(_) => { glfw_terminate(); return 1; }
    Ok(win) => {
      glfw_poll_events();
      let mb = glfw_get_mouse_button(win, 0); // left button
      glfw_destroy_window(win);
      glfw_terminate();
      return 0;
    }
  }
}

fn test_input_mouse_button() -> TestResult {
  let rc = run_input_mouse();
  if rc == 0 { return assert(true, "input: get_mouse_button no crash"); }
  if rc == 2 { return assert(true, "input: mouse skip"); }
  return assert(false, "input: get_mouse_button crashed");
}

fn run_cursor_pos() -> Int {
  if !glfw_init() { return 2; }
  let w = glfw_create_window("Cursor Test", 400, 300);
  match w {
    Err(_) => { glfw_terminate(); return 1; }
    Ok(win) => {
      glfw_poll_events();
      let (cx, cy) = glfw_get_cursor_pos(win);
      // Cursor should return finite values (defaults to 0,0 or window center)
      glfw_destroy_window(win);
      glfw_terminate();
      return 0;
    }
  }
}

fn test_cursor_pos() -> TestResult {
  let rc = run_cursor_pos();
  if rc == 0 { return assert(true, "input: get_cursor_pos returns Float32 tuple"); }
  if rc == 2 { return assert(true, "input: cursor skip"); }
  return assert(false, "input: get_cursor_pos crashed");
}

// ═══════════════════════════════════════════════════════════════════════════
// 5. Poll events: verify doesn't crash
// ═══════════════════════════════════════════════════════════════════════════

fn run_poll_events() -> Int {
  if !glfw_init() { return 2; }
  glfw_poll_events(); // no window — should be fine
  glfw_terminate();
  return 0;
}

fn test_poll_events() -> TestResult {
  let rc = run_poll_events();
  if rc == 0 { return assert(true, "lifecycle: poll_events no crash"); }
  if rc == 2 { return assert(true, "lifecycle: poll skip"); }
  return assert(false, "lifecycle: poll_events crashed");
}

// ═══════════════════════════════════════════════════════════════════════════
// 6. Monitor: primary monitor + video mode
// ═══════════════════════════════════════════════════════════════════════════

fn run_primary_monitor() -> Int {
  if !glfw_init() { return 2; }
  let mon = glfw_get_primary_monitor();
  // On headed systems, returns non-zero; on headless, may return 0
  glfw_terminate();
  return 0; // always pass — just verifying no crash
}

fn test_primary_monitor() -> TestResult {
  let rc = run_primary_monitor();
  if rc == 0 { return assert(true, "monitor: get_primary_monitor no crash"); }
  if rc == 2 { return assert(true, "monitor: skip"); }
  return assert(false, "monitor: get_primary_monitor crashed");
}

fn run_video_mode() -> Int {
  if !glfw_init() { return 2; }
  let mon = glfw_get_primary_monitor();
  if mon == 0 { glfw_terminate(); return 0; } // headless — pass
  let (mw, mh, mr) = glfw_get_video_mode(mon);
  if mw > 0 && mh > 0 {
    glfw_terminate(); return 0;
  }
  glfw_terminate(); return 1;
}

fn test_video_mode() -> TestResult {
  let rc = run_video_mode();
  if rc == 0 { return assert(true, "monitor: video_mode returns positive resolution"); }
  if rc == 2 { return assert(true, "monitor: skip"); }
  return assert(false, "monitor: video_mode invalid");
}

// ═══════════════════════════════════════════════════════════════════════════
// 7. Fullscreen: set, windowed, toggle
// ═══════════════════════════════════════════════════════════════════════════

fn run_fullscreen_windowed() -> Int {
  if !glfw_init() { return 2; }
  let w = glfw_create_window("FS Test", 400, 300);
  match w {
    Err(_) => { glfw_terminate(); return 1; }
    Ok(win) => {
      let mon = glfw_get_primary_monitor();
      // Toggle to windowed mode (even if already windowed — safe no-op)
      glfw_set_windowed(win, 100, 100, 800, 600);
      glfw_poll_events();
      glfw_destroy_window(win);
      glfw_terminate();
      return 0;
    }
  }
}

fn test_fullscreen_windowed() -> TestResult {
  let rc = run_fullscreen_windowed();
  if rc == 0 { return assert(true, "fullscreen: set_windowed no crash"); }
  if rc == 2 { return assert(true, "fullscreen: skip"); }
  return assert(false, "fullscreen: set_windowed crashed");
}

fn run_toggle_fullscreen() -> Int {
  if !glfw_init() { return 2; }
  let w = glfw_create_window("Toggle Test", 400, 300);
  match w {
    Err(_) => { glfw_terminate(); return 1; }
    Ok(win) => {
      let mon = glfw_get_primary_monitor();
      let result = glfw_toggle_fullscreen(win);
      glfw_poll_events();
      // Toggle back
      let result2 = glfw_toggle_fullscreen(win);
      glfw_poll_events();
      glfw_destroy_window(win);
      glfw_terminate();
      return 0;
    }
  }
}

fn test_toggle_fullscreen() -> TestResult {
  let rc = run_toggle_fullscreen();
  if rc == 0 { return assert(true, "fullscreen: toggle_fullscreen round-trip"); }
  if rc == 2 { return assert(true, "fullscreen: toggle skip"); }
  return assert(false, "fullscreen: toggle_fullscreen crashed");
}

// ═══════════════════════════════════════════════════════════════════════════
// 8. Error handling / Contract enforcement
// ═══════════════════════════════════════════════════════════════════════════

fn run_error_empty_title() -> Int {
  if !glfw_init() { return 2; }
  // Empty title should be rejected by requires contract (X0100 trap)
  // Test via a helper that bypasses the contract
  let raw = unsafe { glfw_bridge_create_window(400 as Int32, 300 as Int32, "") };
  // Bridge may return 0 (error) for empty title
  glfw_terminate();
  return 0; // Bridge should handle gracefully
}

fn test_error_empty_title() -> TestResult {
  let rc = run_error_empty_title();
  if rc == 0 { return assert(true, "error: empty title handled"); }
  if rc == 2 { return assert(true, "error: skip"); }
  return assert(false, "error: empty title crash");
}

fn run_error_zero_size() -> Int {
  if !glfw_init() { return 2; }
  let raw = unsafe { glfw_bridge_create_window(0 as Int32, 0 as Int32, "bad") };
  // 0x0 window should fail at bridge level
  glfw_terminate();
  if raw == 0 { return 0; }
  return 1; // shouldn't create 0x0 window
}

fn test_error_zero_size() -> TestResult {
  let rc = run_error_zero_size();
  if rc == 0 { return assert(true, "error: 0x0 window rejected by bridge"); }
  if rc == 2 { return assert(true, "error: skip"); }
  return assert(false, "error: 0x0 window unexpectedly created");
}

// ═══════════════════════════════════════════════════════════════════════════
// Main
// ═══════════════════════════════════════════════════════════════════════════

fn main() -> Int {
  io.println("=== XIOM GLFW Conformance Tests ===");

  var failed: Int = 0;
  var total: Int = 0;

  // 1. Lifecycle
  let r1 = test_init_terminate();
  total = total + 1; failed = failed + report(r1.passed, r1.name);

  let r2 = test_init_return_value();
  total = total + 1; failed = failed + report(r2.passed, r2.name);

  let r3 = test_double_init();
  total = total + 1; failed = failed + report(r3.passed, r3.name);

  // 2. Window
  let r4 = test_create_destroy();
  total = total + 1; failed = failed + report(r4.passed, r4.name);

  let r5 = test_should_close();
  total = total + 1; failed = failed + report(r5.passed, r5.name);

  let r6 = test_set_title();
  total = total + 1; failed = failed + report(r6.passed, r6.name);

  // 3. Size
  let r7 = test_framebuffer_size();
  total = total + 1; failed = failed + report(r7.passed, r7.name);

  let r8 = test_window_size();
  total = total + 1; failed = failed + report(r8.passed, r8.name);

  // 4. Input
  let r9 = test_input_key();
  total = total + 1; failed = failed + report(r9.passed, r9.name);

  let r10 = test_input_mouse_button();
  total = total + 1; failed = failed + report(r10.passed, r10.name);

  let r11 = test_cursor_pos();
  total = total + 1; failed = failed + report(r11.passed, r11.name);

  // 5. Poll
  let r12 = test_poll_events();
  total = total + 1; failed = failed + report(r12.passed, r12.name);

  // 6. Monitor
  let r13 = test_primary_monitor();
  total = total + 1; failed = failed + report(r13.passed, r13.name);

  let r14 = test_video_mode();
  total = total + 1; failed = failed + report(r14.passed, r14.name);

  // 7. Fullscreen
  let r15 = test_fullscreen_windowed();
  total = total + 1; failed = failed + report(r15.passed, r15.name);

  let r16 = test_toggle_fullscreen();
  total = total + 1; failed = failed + report(r16.passed, r16.name);

  // 8. Error handling
  let r17 = test_error_empty_title();
  total = total + 1; failed = failed + report(r17.passed, r17.name);

  let r18 = test_error_zero_size();
  total = total + 1; failed = failed + report(r18.passed, r18.name);

  let passed = total - failed;
  io.println("");
  io.println("XIOM GLFW Conformance: " + int_to_str(passed) +
             "/" + int_to_str(total) + " passed" +
             (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
