// XIOM -- xiom-stb Conformance Tests
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Comprehensive conformance suite for xiom-stb pure-XIOM components.
// Tests: Image type construction/invariants, pixel_at, pixel_index,
// failure_reason, free_image, FFI stub error paths, contract enforcement.
//
// FFI-dependent functions (load_image, write_png, etc.) are tested
// for correct error-path behavior with unlinked bridge.

module stb_conformance
use xiom.io; use xiom.test; use xiom.stb;

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; } var num = n; var out = "";
  while num > 0 { let d = num % 10; var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out; num = num / 10; }
  return out;
}
fn report(passed: Bool, name: Str) -> Int {
  if passed { io.println("  [PASS] " + name); return 0; }
  io.println("  [FAIL] " + name); return 1;
}

// === 1. Image type construction + field access ===

fn run_image_construct() -> Int {
  var d = Vec[UInt8].new();
  d.push(255); d.push(0); d.push(0); d.push(255);
  d.push(0); d.push(255); d.push(0); d.push(255);
  d.push(0); d.push(0); d.push(255); d.push(255);
  d.push(128); d.push(128); d.push(128); d.push(255);
  var img = Image{ width: 2, height: 2, channels: 4, data: d };
  if img.width != 2 { return 1; }
  if img.height != 2 { return 2; }
  if img.channels != 4 { return 3; }
  if img.data.len() != 16 { return 4; }
  return 0;
}
fn t1() -> TestResult {
  if run_image_construct() == 0 { return assert(true, "stb: Image construct + field access"); }
  return assert(false, "stb: Image construction failed");
}

// === 2. Image data invariant: len == width * height * channels ===

fn run_image_invariant() -> Int {
  var d = Vec[UInt8].new();
  var i = 0; while i < 120 { d.push(0); i = i + 1; }
  var img = Image{ width: 10, height: 3, channels: 4, data: d };
  if img.data.len() != img.width * img.height * img.channels { return 1; }
  return 0;
}
fn t2() -> TestResult {
  if run_image_invariant() == 0 { return assert(true, "stb: Image data invariant (len == w*h*c)"); }
  return assert(false, "stb: Image invariant violated");
}

// === 3. Image with single-pixel (1x1 RGBA) ===

fn run_image_1x1() -> Int {
  var d = Vec[UInt8].new();
  d.push(255); d.push(128); d.push(64); d.push(0);
  var img = Image{ width: 1, height: 1, channels: 4, data: d };
  if img.data.len() != 4 { return 1; }
  if img.data[0] != 255 { return 2; }
  if img.data[3] != 0 { return 3; }
  return 0;
}
fn t3() -> TestResult {
  if run_image_1x1() == 0 { return assert(true, "stb: Image 1x1 RGBA"); }
  return assert(false, "stb: 1x1 image failed");
}

// === 4. failure_reason returns a Str ===

fn run_failure_reason_str() -> Int {
  let reason = failure_reason();
  if reason.len() >= 0 { return 0; }
  return 1;
}
fn t4() -> TestResult {
  if run_failure_reason_str() == 0 { return assert(true, "stb: failure_reason returns Str"); }
  return assert(false, "stb: failure_reason failed");
}

// === 5. pixel_index formula: index = (y * width + x) * channels ===

fn run_pixel_index_formula() -> Int {
  var d = Vec[UInt8].new();
  var i = 0; while i < 64 { d.push(0); i = i + 1; }
  var img = Image{ width: 4, height: 4, channels: 4, data: d };
  let idx00 = pixel_index(&img, 0, 0);
  let idx10 = pixel_index(&img, 1, 0);
  let idx01 = pixel_index(&img, 0, 1);
  let idx33 = pixel_index(&img, 3, 3);
  if idx00 != 0 { return 1; }
  if idx10 != 4 { return 2; }
  if idx01 != 16 { return 3; }
  if idx33 != 60 { return 4; }
  return 0;
}
fn t5() -> TestResult {
  if run_pixel_index_formula() == 0 { return assert(true, "stb: pixel_index formula (y*w+x)*c"); }
  return assert(false, "stb: pixel_index formula wrong");
}

// === 6. pixel_index on non-zero origin ===

fn run_pixel_index_offset() -> Int {
  var d = Vec[UInt8].new();
  var i = 0; while i < 27 { d.push(0); i = i + 1; }
  var img = Image{ width: 3, height: 3, channels: 3, data: d };
  let idx22 = pixel_index(&img, 2, 2);
  if idx22 != 24 { return 1; }
  let idx21 = pixel_index(&img, 2, 1);
  if idx21 != 15 { return 2; }
  let idx10 = pixel_index(&img, 1, 0);
  if idx10 != 3 { return 3; }
  return 0;
}
fn t6() -> TestResult {
  if run_pixel_index_offset() == 0 { return assert(true, "stb: pixel_index offset positions"); }
  return assert(false, "stb: pixel_index offset wrong");
}

// === 7. pixel_at on known RGBA data ===

fn run_pixel_at_basic() -> Int {
  var d = Vec[UInt8].new();
  d.push(255); d.push(0); d.push(0); d.push(255);
  d.push(0); d.push(255); d.push(0); d.push(128);
  d.push(0); d.push(0); d.push(255); d.push(64);
  d.push(128); d.push(128); d.push(128); d.push(255);
  var img = Image{ width: 2, height: 2, channels: 4, data: d };
  let (r0, g0, b0, a0) = pixel_at(&img, 0, 0);
  if r0 != 255 || g0 != 0 || b0 != 0 || a0 != 255 { return 1; }
  let (r1, g1, b1, a1) = pixel_at(&img, 1, 0);
  if r1 != 0 || g1 != 255 || b1 != 0 || a1 != 128 { return 2; }
  let (r2, g2, b2, a2) = pixel_at(&img, 0, 1);
  if r2 != 0 || g2 != 0 || b2 != 255 || a2 != 64 { return 3; }
  let (r3, g3, b3, a3) = pixel_at(&img, 1, 1);
  if r3 != 128 || g3 != 128 || b3 != 128 || a3 != 255 { return 4; }
  return 0;
}
fn t7() -> TestResult {
  if run_pixel_at_basic() == 0 { return assert(true, "stb: pixel_at known RGBA values"); }
  return assert(false, "stb: pixel_at values wrong");
}

// === 8. pixel_at on 3-channel (RGB) image ===

fn run_pixel_at_rgb() -> Int {
  var d = Vec[UInt8].new();
  d.push(16); d.push(32); d.push(48);
  d.push(64); d.push(80); d.push(96);
  var img = Image{ width: 2, height: 1, channels: 3, data: d };
  let (r0, g0, b0, a0) = pixel_at(&img, 0, 0);
  if r0 != 16 || g0 != 32 || b0 != 48 { return 1; }
  let (r1, g1, b1, a1) = pixel_at(&img, 1, 0);
  if r1 != 64 || g1 != 80 || b1 != 96 { return 2; }
  return 0;
}
fn t8() -> TestResult {
  if run_pixel_at_rgb() == 0 { return assert(true, "stb: pixel_at 3-channel RGB"); }
  return assert(false, "stb: pixel_at RGB wrong");
}

// === 9. free_image on manually constructed Image ===

fn run_free_image_local() -> Int {
  var d = Vec[UInt8].new();
  d.push(255); d.push(0); d.push(0); d.push(255);
  var img = Image{ width: 1, height: 1, channels: 4, data: d };
  free_image(&mut img);
  return 0;
}
fn t9() -> TestResult {
  if run_free_image_local() == 0 { return assert(true, "stb: free_image on local Image"); }
  return assert(false, "stb: free_image crashed");
}

// === 10. load_image with empty path (contract violation -> Err) ===

fn run_load_empty_path() -> Int {
  let r = load_image("");
  match r { Ok(_) => return 1, Err(_) => return 0 }
}
fn t10() -> TestResult {
  if run_load_empty_path() == 0 { return assert(true, "stb: load_image empty path -> Err"); }
  return assert(false, "stb: load_image empty path returned Ok");
}

// === 11. load_from_memory empty data (contract violation -> Err) ===

fn run_load_mem_empty() -> Int {
  var empty = Vec[UInt8].new();
  let r = load_from_memory(&empty);
  match r { Ok(_) => return 1, Err(_) => return 0 }
}
fn t11() -> TestResult {
  if run_load_mem_empty() == 0 { return assert(true, "stb: load_from_memory empty -> Err"); }
  return assert(false, "stb: load_from_memory empty returned Ok");
}

// === 12. write_png with empty image data (contract violation -> Err) ===

fn run_write_png_empty() -> Int {
  var img = Image{ width: 0, height: 0, channels: 0, data: Vec[UInt8].new() };
  let r = write_png("/nonexistent/test.png", &img);
  match r { Ok(_) => return 1, Err(_) => return 0 }
}
fn t12() -> TestResult {
  if run_write_png_empty() == 0 { return assert(true, "stb: write_png empty data -> Err"); }
  return assert(false, "stb: write_png empty data returned Ok");
}

// === 13. write_jpg invalid quality (contract violation) ===

fn run_write_jpg_bad_quality() -> Int {
  var d = Vec[UInt8].new(); d.push(0); d.push(0); d.push(0); d.push(255);
  var img = Image{ width: 1, height: 1, channels: 4, data: d };
  let r = write_jpg("/nonexistent/test.jpg", &img, 0);
  match r { Ok(_) => return 1, Err(_) => {} }
  let r2 = write_jpg("/nonexistent/test.jpg", &img, 101);
  match r2 { Ok(_) => return 2, Err(_) => return 0 }
}
fn t13() -> TestResult {
  if run_write_jpg_bad_quality() == 0 { return assert(true, "stb: write_jpg invalid quality -> Err"); }
  return assert(false, "stb: write_jpg bad quality returned Ok");
}

// === 14. FFI load path round-trip error-path (no DLL -> Err) ===

fn run_load_nonexistent() -> Int {
  let r = load_image("/nonexistent/does_not_exist.png");
  match r { Ok(_) => return 1, Err(err) => { if err.len() >= 0 { return 0; } return 1; } }
}
fn t14() -> TestResult {
  if run_load_nonexistent() == 0 { return assert(true, "stb: load_image nonexistent file -> Err"); }
  return assert(false, "stb: load_image nonexistent returned Ok");
}

// ===========================================================================
// Main
// ===========================================================================

fn main() -> Int {
  io.println("=== XIOM stb Conformance Tests ===");
  var failed: Int = 0; var total: Int = 0;

  let r1 = t1();
  total = total + 1; failed = failed + report(r1.passed, r1.name);

  let r2 = t2();
  total = total + 1; failed = failed + report(r2.passed, r2.name);

  let r3 = t3();
  total = total + 1; failed = failed + report(r3.passed, r3.name);

  let r4 = t4();
  total = total + 1; failed = failed + report(r4.passed, r4.name);

  let r5 = t5();
  total = total + 1; failed = failed + report(r5.passed, r5.name);

  let r6 = t6();
  total = total + 1; failed = failed + report(r6.passed, r6.name);

  let r7 = t7();
  total = total + 1; failed = failed + report(r7.passed, r7.name);

  let r8 = t8();
  total = total + 1; failed = failed + report(r8.passed, r8.name);

  let r9 = t9();
  total = total + 1; failed = failed + report(r9.passed, r9.name);

  let r10 = t10();
  total = total + 1; failed = failed + report(r10.passed, r10.name);

  let r11 = t11();
  total = total + 1; failed = failed + report(r11.passed, r11.name);

  let r12 = t12();
  total = total + 1; failed = failed + report(r12.passed, r12.name);

  let r13 = t13();
  total = total + 1; failed = failed + report(r13.passed, r13.name);

  let r14 = t14();
  total = total + 1; failed = failed + report(r14.passed, r14.name);

  let passed = total - failed;
  io.println(""); io.println("XIOM stb: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
