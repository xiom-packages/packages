// XIOM -- xiom.ffi Conformance Tests
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Comprehensive conformance suite for xiom.ffi stdlib module.
// Covers: raw C interop (alloc/free/memcpy), SafePtr lifecycle,
// FFIBuffer write/read/clear, FFIError translation, marshal primitives.
//
// STUB functions (safe_ptr_read_*, safe_ptr_write_*, write_*_at,
// size_of, align_of, extern_c) are tested for signature correctness
// (no crash) but not for functional correctness (blocked on compiler).

module ffi_conformance
use xiom.io;
use xiom.test;
use xiom.ffi;

// ===========================================================================
// Helpers
// ===========================================================================

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

// ===========================================================================
// 1. Raw C Interop: alloc + free
// ===========================================================================

fn run_alloc_free() -> Int {
  let ptr = alloc(64);
  if ptr == null { return 1; }
  free(ptr);
  return 0;
}

fn test_alloc_free() -> TestResult {
  let rc = run_alloc_free();
  if rc == 0 { return assert(true, "raw: alloc 64B + free"); }
  return assert(false, "raw: alloc returned null");
}

fn run_alloc_large() -> Int {
  let ptr = alloc(65536);
  if ptr == null { return 1; }
  free(ptr);
  return 0;
}

fn test_alloc_large() -> TestResult {
  let rc = run_alloc_large();
  if rc == 0 { return assert(true, "raw: alloc 64KB + free"); }
  return assert(false, "raw: large alloc failed");
}

fn run_alloc_multiple() -> Int {
  let p1 = alloc(128);
  let p2 = alloc(256);
  let p3 = alloc(512);
  if p1 == null || p2 == null || p3 == null {
    if p1 != null { free(p1); }
    if p2 != null { free(p2); }
    if p3 != null { free(p3); }
    return 1;
  }
  if p1 == p2 || p2 == p3 || p1 == p3 {
    free(p1); free(p2); free(p3); return 1;
  }
  free(p3); free(p2); free(p1);
  return 0;
}

fn test_alloc_multiple() -> TestResult {
  let rc = run_alloc_multiple();
  if rc == 0 { return assert(true, "raw: 3 distinct allocations"); }
  return assert(false, "raw: allocs collided or failed");
}

// ===========================================================================
// 2. Raw C Interop: memcpy
// ===========================================================================

fn run_memcpy_roundtrip() -> Int {
  let src = alloc(16);
  let dst = alloc(16);
  if src == null || dst == null {
    if src != null { free(src); }
    if dst != null { free(dst); }
    return 1;
  }
  memcpy(dst, src, 16);
  free(dst); free(src);
  return 0;
}

fn test_memcpy_roundtrip() -> TestResult {
  let rc = run_memcpy_roundtrip();
  if rc == 0 { return assert(true, "raw: memcpy 16B no crash"); }
  return assert(false, "raw: memcpy failed");
}

// ===========================================================================
// 3. SafePtr: alloc, from_raw, free
// ===========================================================================

fn run_safe_ptr_alloc_free() -> Int {
  let sp = safe_ptr_alloc(128);
  match sp {
    Err(e) => { return 1; }
    Ok(ptr) => {
      safe_ptr_free(ptr);
      return 0;
    }
  }
}

fn test_safe_ptr_alloc_free() -> TestResult {
  let rc = run_safe_ptr_alloc_free();
  if rc == 0 { return assert(true, "SafePtr: alloc + free"); }
  return assert(false, "SafePtr: alloc failed");
}

fn run_safe_ptr_from_raw() -> Int {
  let raw = alloc(64);
  if raw == null { return 1; }
  let sp = safe_ptr_from_raw(raw, 64);
  match sp {
    Err(e) => { free(raw); return 1; }
    Ok(ptr) => {
      safe_ptr_free(ptr);
      return 0;
    }
  }
}

fn test_safe_ptr_from_raw() -> TestResult {
  let rc = run_safe_ptr_from_raw();
  if rc == 0 { return assert(true, "SafePtr: from_raw + free"); }
  return assert(false, "SafePtr: from_raw failed");
}

fn run_safe_ptr_read_write_stubs() -> Int {
  let sp = safe_ptr_alloc(64);
  match sp {
    Err(_) => { return 1; }
    Ok(ptr) => {
      // STUB functions -- verify they don't crash (return Ok with dummy values)
      let rb = safe_ptr_read_byte(&ptr, 0);
      let wb = safe_ptr_write_byte(&mut ptr, 0, 42);
      let ri = safe_ptr_read_i32(&ptr, 0);
      let wi = safe_ptr_write_i32(&mut ptr, 0, 100);
      safe_ptr_free(ptr);
      return 0;
    }
  }
}

fn test_safe_ptr_read_write_stubs() -> TestResult {
  let rc = run_safe_ptr_read_write_stubs();
  if rc == 0 { return assert(true, "SafePtr: read/write stubs no crash"); }
  return assert(false, "SafePtr: stubs crashed");
}

// ===========================================================================
// 4. FFIBuffer: new, write, read, clear, len, is_empty
// ===========================================================================

fn run_buffer_new_clear() -> Int {
  let buf = buffer_new(64);
  match buf {
    Err(e) => { return 1; }
    Ok(mut b) => {
      if !buffer_is_empty(&b) { return 1; }
      if buffer_len(&b) != 0 { return 1; }
      buffer_clear(&mut b);
      if !buffer_is_empty(&b) { return 1; }
      return 0;
    }
  }
}

fn test_buffer_new_clear() -> TestResult {
  let rc = run_buffer_new_clear();
  if rc == 0 { return assert(true, "FFIBuffer: new empty + clear"); }
  return assert(false, "FFIBuffer: not empty after new");
}

fn run_buffer_capacity() -> Int {
  let buf = buffer_new(256);
  match buf {
    Err(_) => { return 1; }
    Ok(mut b) => {
      // capacity should be stored
      if b.capacity != 256 { return 1; }
      return 0;
    }
  }
}

fn test_buffer_capacity() -> TestResult {
  let rc = run_buffer_capacity();
  if rc == 0 { return assert(true, "FFIBuffer: capacity matches creation"); }
  return assert(false, "FFIBuffer: capacity mismatch");
}

// ===========================================================================
// 5. FFIError: check, check_ptr, check_nonzero, ok, error
// ===========================================================================

fn run_ffi_check_negative() -> Int {
  // Negative return codes = error in C convention
  let r = ffi_check(-1, "test_op");
  match r {
    Ok(_) => { return 1; } // negative should be error
    Err(err) => {
      if err.code == -1 { return 0; }
      return 1;
    }
  }
}

fn test_ffi_check_negative() -> TestResult {
  let rc = run_ffi_check_negative();
  if rc == 0 { return assert(true, "FFIError: negative code = Err"); }
  return assert(false, "FFIError: negative not rejected");
}

fn run_ffi_check_positive() -> Int {
  let r = ffi_check(42, "test_op");
  match r {
    Ok(val) => {
      if val == 42 { return 0; }
      return 1;
    }
    Err(_) => { return 1; }
  }
}

fn test_ffi_check_positive() -> TestResult {
  let rc = run_ffi_check_positive();
  if rc == 0 { return assert(true, "FFIError: positive code = Ok"); }
  return assert(false, "FFIError: positive rejected");
}

fn run_ffi_check_zero() -> Int {
  let r = ffi_check(0, "test_op");
  match r {
    Ok(val) => {
      if val == 0 { return 0; }
      return 1;
    }
    Err(_) => { return 1; }
  }
}

fn test_ffi_check_zero() -> TestResult {
  let rc = run_ffi_check_zero();
  if rc == 0 { return assert(true, "FFIError: zero code = Ok"); }
  return assert(false, "FFIError: zero rejected");
}

fn run_ffi_check_ptr_null() -> Int {
  let r = ffi_check_ptr(null, "null_ptr");
  match r {
    Ok(_) => { return 1; } // null should be error
    Err(err) => {
      if err.code == 0 { return 0; }
      return 1;
    }
  }
}

fn test_ffi_check_ptr_null() -> TestResult {
  let rc = run_ffi_check_ptr_null();
  if rc == 0 { return assert(true, "FFIError: null ptr = Err"); }
  return assert(false, "FFIError: null ptr not rejected");
}

fn run_ffi_check_ptr_valid() -> Int {
  let ptr = alloc(8);
  if ptr == null { return 1; }
  let r = ffi_check_ptr(ptr, "valid_ptr");
  match r {
    Ok(p) => {
      if p == ptr { free(ptr); return 0; }
      free(ptr); return 1;
    }
    Err(_) => { free(ptr); return 1; }
  }
}

fn test_ffi_check_ptr_valid() -> TestResult {
  let rc = run_ffi_check_ptr_valid();
  if rc == 0 { return assert(true, "FFIError: valid ptr = Ok"); }
  return assert(false, "FFIError: valid ptr rejected");
}

fn run_ffi_check_nonzero_error() -> Int {
  let r = ffi_check_nonzero(5, "nonzero_err");
  match r {
    Ok(_) => { return 1; } // nonzero should be error
    Err(err) => {
      if err.code == 5 { return 0; }
      return 1;
    }
  }
}

fn test_ffi_check_nonzero_error() -> TestResult {
  let rc = run_ffi_check_nonzero_error();
  if rc == 0 { return assert(true, "FFIError: nonzero = Err"); }
  return assert(false, "FFIError: nonzero not rejected");
}

fn run_ffi_ok_error() -> Int {
  let ok = ffi_ok();
  if ok != 0 { return 1; }
  let err = ffi_error(-5, "custom error");
  if err.code != -5 { return 1; }
  return 0;
}

fn test_ffi_ok_error() -> TestResult {
  let rc = run_ffi_ok_error();
  if rc == 0 { return assert(true, "FFIError: ffi_ok=0, ffi_error preserves code"); }
  return assert(false, "FFIError: ffi_ok or ffi_error incorrect");
}

// ===========================================================================
// 6. Marshal: write stubs (signature correctness only)
// ===========================================================================

fn run_marshal_stubs() -> Int {
  let buf = alloc(64);
  if buf == null { return 1; }
  let buf_int = unsafe { buf as Int };
  // All marshal functions are STUB -- verify they don't crash
  write_u32_at(buf_int, 0, 0xDEAD);
  write_u64_at(buf_int, 4, 0xBEEF);
  write_f32_at(buf_int, 8, 3.14);
  write_str_at(buf_int, 16, "hello");
  free(buf);
  return 0;
}

fn test_marshal_stubs() -> TestResult {
  let rc = run_marshal_stubs();
  if rc == 0 { return assert(true, "Marshal: write stubs no crash"); }
  return assert(false, "Marshal: stubs crashed");
}

// ===========================================================================
// 7. Compile-time utilities (stub correctness)
// ===========================================================================

fn run_size_align_stubs() -> Int {
  // size_of and align_of return 0 -- verify they don't crash
  let sz = size_of[Int]();
  let al = align_of[Int]();
  // Skip actual value check -- these are known stubs
  return 0;
}

fn test_size_align_stubs() -> TestResult {
  let rc = run_size_align_stubs();
  if rc == 0 { return assert(true, "Utility: size_of/align_of stubs no crash"); }
  return assert(false, "Utility: size_of/align_of crashed");
}

fn run_extern_c_stub() -> Int {
  let addr = extern_c("malloc");
  // extern_c returns 0 -- STUB, verify no crash
  return 0;
}

fn test_extern_c_stub() -> TestResult {
  let rc = run_extern_c_stub();
  if rc == 0 { return assert(true, "Utility: extern_c stub no crash"); }
  return assert(false, "Utility: extern_c crashed");
}

// ===========================================================================
// 8. Edge Cases
// ===========================================================================

fn run_alloc_zero() -> Int {
  // alloc(0) should be rejected by contract (requires: size > 0)
  // Contract trap means we can't test this in the runner
  // Test that alloc(1) works as minimal allocation
  let ptr = alloc(1);
  if ptr == null { return 1; }
  free(ptr);
  return 0;
}

fn test_alloc_minimal() -> TestResult {
  let rc = run_alloc_zero();
  if rc == 0 { return assert(true, "edge: alloc(1) succeeds"); }
  return assert(false, "edge: alloc(1) failed");
}

fn run_buffer_write_empty() -> Int {
  // buffer_write with empty Vec should be rejected by contract
  // Test buffer_write with actual data
  let buf = buffer_new(64);
  match buf {
    Err(_) => { return 1; }
    Ok(mut b) => {
      var data: Vec[Int] = Vec[Int].new();
      data.push(65);
      data.push(66);
      data.push(67);
      let result = buffer_write(&mut b, &data);
      match result {
        Ok(n) => {
          if n == 3 { return 0; }
          return 1;
        }
        Err(_) => { return 1; }
      }
    }
  }
}

fn test_buffer_write_bytes() -> TestResult {
  let rc = run_buffer_write_empty();
  if rc == 0 { return assert(true, "edge: buffer_write 3 bytes succeeds"); }
  return assert(false, "edge: buffer_write failed");
}

// ===========================================================================
// Main
// ===========================================================================

fn main() -> Int {
  io.println("=== XIOM FFI Conformance Tests ===");

  var failed: Int = 0;
  var total: Int = 0;

  // 1. Raw C Interop
  let r1 = test_alloc_free();
  total = total + 1; failed = failed + report(r1.passed, r1.name);

  let r2 = test_alloc_large();
  total = total + 1; failed = failed + report(r2.passed, r2.name);

  let r3 = test_alloc_multiple();
  total = total + 1; failed = failed + report(r3.passed, r3.name);

  let r4 = test_memcpy_roundtrip();
  total = total + 1; failed = failed + report(r4.passed, r4.name);

  // 2. SafePtr
  let r5 = test_safe_ptr_alloc_free();
  total = total + 1; failed = failed + report(r5.passed, r5.name);

  let r6 = test_safe_ptr_from_raw();
  total = total + 1; failed = failed + report(r6.passed, r6.name);

  let r7 = test_safe_ptr_read_write_stubs();
  total = total + 1; failed = failed + report(r7.passed, r7.name);

  // 3. FFIBuffer
  let r8 = test_buffer_new_clear();
  total = total + 1; failed = failed + report(r8.passed, r8.name);

  let r9 = test_buffer_capacity();
  total = total + 1; failed = failed + report(r9.passed, r9.name);

  // 4. FFIError
  let r10 = test_ffi_check_negative();
  total = total + 1; failed = failed + report(r10.passed, r10.name);

  let r11 = test_ffi_check_positive();
  total = total + 1; failed = failed + report(r11.passed, r11.name);

  let r12 = test_ffi_check_zero();
  total = total + 1; failed = failed + report(r12.passed, r12.name);

  let r13 = test_ffi_check_ptr_null();
  total = total + 1; failed = failed + report(r13.passed, r13.name);

  let r14 = test_ffi_check_ptr_valid();
  total = total + 1; failed = failed + report(r14.passed, r14.name);

  let r15 = test_ffi_check_nonzero_error();
  total = total + 1; failed = failed + report(r15.passed, r15.name);

  let r16 = test_ffi_ok_error();
  total = total + 1; failed = failed + report(r16.passed, r16.name);

  // 5. Marshal
  let r17 = test_marshal_stubs();
  total = total + 1; failed = failed + report(r17.passed, r17.name);

  // 6. Utilities
  let r18 = test_size_align_stubs();
  total = total + 1; failed = failed + report(r18.passed, r18.name);

  let r19 = test_extern_c_stub();
  total = total + 1; failed = failed + report(r19.passed, r19.name);

  // 7. Edge Cases
  let r20 = test_alloc_minimal();
  total = total + 1; failed = failed + report(r20.passed, r20.name);

  let r21 = test_buffer_write_bytes();
  total = total + 1; failed = failed + report(r21.passed, r21.name);

  let passed = total - failed;
  io.println("");
  io.println("XIOM FFI Conformance: " + int_to_str(passed) +
             "/" + int_to_str(total) + " passed" +
             (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
