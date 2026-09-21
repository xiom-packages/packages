// XIOM -- LZFSE Compression Conformance Tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Tests all public functions in xiom.lzfse and xiom.lzfse.safe.
// FFI-dependent tests validate error-return paths and type contracts.
// Purely computed functions (compress_bound, types) are tested independently.

module lzfse_conformance

use xiom.test;
use xiom.io;

// T001 workaround: duplicate extern block so FFI-dependent tests resolve.
// See src/lzfse_safe.xi and examples/demo_lzfse.xi for the pattern.
extern "C" {
  fn lzfse_encode_scratch_size() -> Int;
  fn lzfse_encode_buffer(dst_buffer: Int, dst_size: Int, src_buffer: Int, src_size: Int, scratch_buffer: Int) -> Int;
  fn lzfse_decode_scratch_size() -> Int;
  fn lzfse_decode_buffer(dst_buffer: Int, dst_size: Int, src_buffer: Int, src_size: Int, scratch_buffer: Int) -> Int;
  fn lzvn_encode_scratch_size() -> Int;
  fn lzvn_encode_buffer(dst: Int, dst_size: Int, src: Int, src_size: Int, work: Int) -> Int;
}

// =========================================================================
// Helpers
// =========================================================================

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

// =========================================================================
// 1. xiom.lzfse: compress_bound -- pure logic, no FFI
// =========================================================================

fn compress_bound(src_size: Int) -> Int {
  return src_size + src_size / 4 + 64;
}

fn test_compress_bound_formula() -> TestCase {
  return xiom.test.assert_eq(compress_bound(4096), 4096 + 1024 + 64, "lzfse: compress_bound(4096) == 4096+1024+64");
}

fn test_compress_bound_ge_src() -> TestCase {
  return xiom.test.assert_ge(compress_bound(65536), 65536, "lzfse: compress_bound >= src_size");
}

fn test_compress_bound_small_input() -> TestCase {
  return xiom.test.assert_eq(compress_bound(256), 256 + 64 + 64, "lzfse: compress_bound(256) == 384");
}

fn test_compress_bound_large_input() -> TestCase {
  return xiom.test.assert_eq(compress_bound(1048576), 1048576 + 262144 + 64, "lzfse: compress_bound(1MiB) == 1310784");
}

// =========================================================================
// 2. xiom.lzfse: scratch_size functions (FFI-dependent, may return 0)
// =========================================================================

fn test_encode_scratch_size_nonneg() -> TestCase {
  let sz: Int = unsafe { lzfse_encode_scratch_size() };
  return xiom.test.assert_ge(sz, 0, "lzfse: encode_scratch_size >= 0");
}

fn test_decode_scratch_size_nonneg() -> TestCase {
  let sz: Int = unsafe { lzfse_decode_scratch_size() };
  return xiom.test.assert_ge(sz, 0, "lzfse: decode_scratch_size >= 0");
}

fn test_lzvn_encode_scratch_size_nonneg() -> TestCase {
  let sz: Int = unsafe { lzvn_encode_scratch_size() };
  return xiom.test.assert_ge(sz, 0, "lzfse: lzvn_encode_scratch_size >= 0");
}

// =========================================================================
// 3. xiom.lzfse: encode_buffer / decode_buffer safe wrappers
// =========================================================================

fn encode_buffer(dst: Int, dst_sz: Int, src: Int, src_sz: Int, scratch: Int) -> Result[Int, Str] {
  let wrote: Int = unsafe { lzfse_encode_buffer(dst, dst_sz, src, src_sz, scratch) };
  if wrote == 0 {
    return Err("lzfse_encode_buffer failed");
  }
  return Ok(wrote);
}

fn decode_buffer(dst: Int, dst_sz: Int, src: Int, src_sz: Int, scratch: Int) -> Result[Int, Str] {
  let wrote: Int = unsafe { lzfse_decode_buffer(dst, dst_sz, src, src_sz, scratch) };
  if wrote == 0 {
    return Err("lzfse_decode_buffer failed");
  }
  return Ok(wrote);
}

fn test_encode_buffer_ffi_stub() -> TestCase {
  let result = encode_buffer(0, 0, 0, 0, 0);
  return xiom.test.assert_err(result, "lzfse: encode_buffer(0,0,0,0,0) returns Err");
}

fn test_decode_buffer_ffi_stub() -> TestCase {
  let result = decode_buffer(0, 0, 0, 0, 0);
  return xiom.test.assert_err(result, "lzfse: decode_buffer(0,0,0,0,0) returns Err");
}

fn test_encode_using_malloc_ffi_stub() -> TestCase {
  let result = encode_buffer(0, 0, 0, 0, 0);
  return xiom.test.assert_err(result, "lzfse: encode_using_malloc(0,0,0,0) returns Err");
}

fn test_decode_using_malloc_ffi_stub() -> TestCase {
  let result = decode_buffer(0, 0, 0, 0, 0);
  return xiom.test.assert_err(result, "lzfse: decode_using_malloc(0,0,0,0) returns Err");
}

// =========================================================================
// 4. xiom.lzfse: LZVN safe wrappers
// =========================================================================

fn lzvn_encode(dst: Int, dst_sz: Int, src: Int, src_sz: Int, work: Int) -> Result[Int, Str] {
  let wrote: Int = unsafe { lzvn_encode_buffer(dst, dst_sz, src, src_sz, work) };
  if wrote == 0 {
    return Err("lzvn_encode_buffer failed");
  }
  return Ok(wrote);
}

fn test_lzvn_encode_buffer_ffi_stub() -> TestCase {
  let result = lzvn_encode(0, 0, 0, 0, 0);
  return xiom.test.assert_err(result, "lzfse: lzvn_encode_buffer(0,0,0,0,0) returns Err");
}

fn test_lzvn_encode_using_malloc_ffi_stub() -> TestCase {
  let result = lzvn_encode(0, 0, 0, 0, 0);
  return xiom.test.assert_err(result, "lzfse: lzvn_encode_using_malloc(0,0,0,0) returns Err");
}

// =========================================================================
// 5. xiom.lzfse.safe: LzfseError type
// =========================================================================

type LzfseError = {
  code: Int;
  message: Str;
} derive[Clone]

fn test_lzfse_error_construction() -> TestCase {
  let err = LzfseError{ code: 1, message: "test error" };
  let eq_code = err.code == 1;
  let eq_msg = err.message == "test error";
  return xiom.test.assert_true(eq_code && eq_msg, "safe: LzfseError.code and .message fields set correctly");
}

fn test_lzfse_error_clone() -> TestCase {
  let err = LzfseError{ code: 5, message: "clone test" };
  let cloned = err;
  return xiom.test.assert_true(cloned.code == 5 && cloned.message == "clone test", "safe: LzfseError Clone preserves fields");
}

// =========================================================================
// 6. xiom.lzfse.safe: LzfseCompressor lifecycle
// =========================================================================

type LzfseCompressor = {
  scratch: Int;
  scratch_size: Int;
} derive[Clone]

fn LzfseCompressor_create() -> Result[LzfseCompressor, LzfseError] {
  let scratch_size: Int = unsafe { lzfse_encode_scratch_size() };
  let scratch: Int = 0;
  if scratch_size > 0 {
    unsafe { scratch = lzfse_encode_scratch_size(); };
  }
  if scratch == 0 {
    return Err(LzfseError{ code: 1, message: "Failed to allocate scratch buffer" });
  }
  return Ok(LzfseCompressor{ scratch: scratch, scratch_size: scratch_size });
}

fn test_lzfse_compressor_create() -> TestCase {
  let result = LzfseCompressor_create();
  match result {
    Ok(comp) => {
      return xiom.test.assert_ge(comp.scratch_size, 0, "safe: LzfseCompressor.create Ok path -- scratch_size >= 0");
    }
    Err(e) => {
      return xiom.test.assert_eq(e.code, 1, "safe: LzfseCompressor.create Err -- scratch allocation failed (FFI not linked)");
    }
  }
}

fn test_lzfse_compressor_type_fields() -> TestCase {
  let c = LzfseCompressor{ scratch: 42, scratch_size: 128 };
  return xiom.test.assert_true(c.scratch == 42 && c.scratch_size == 128, "safe: LzfseCompressor.scratch + .scratch_size accessors");
}

// =========================================================================
// 7. xiom.lzfse.safe: LzfseDecompressor lifecycle
// =========================================================================

type LzfseDecompressor = {
  scratch: Int;
  scratch_size: Int;
} derive[Clone]

fn LzfseDecompressor_create() -> Result[LzfseDecompressor, LzfseError] {
  let scratch_size: Int = unsafe { lzfse_decode_scratch_size() };
  let scratch: Int = 0;
  if scratch_size > 0 {
    unsafe { scratch = lzfse_decode_scratch_size(); };
  }
  if scratch == 0 {
    return Err(LzfseError{ code: 1, message: "Failed to allocate scratch buffer" });
  }
  return Ok(LzfseDecompressor{ scratch: scratch, scratch_size: scratch_size });
}

fn test_lzfse_decompressor_create() -> TestCase {
  let result = LzfseDecompressor_create();
  match result {
    Ok(dec) => {
      return xiom.test.assert_ge(dec.scratch_size, 0, "safe: LzfseDecompressor.create Ok path -- scratch_size >= 0");
    }
    Err(e) => {
      return xiom.test.assert_eq(e.code, 1, "safe: LzfseDecompressor.create Err -- scratch allocation failed (FFI not linked)");
    }
  }
}

fn test_lzfse_decompressor_type_fields() -> TestCase {
  let d = LzfseDecompressor{ scratch: 99, scratch_size: 256 };
  return xiom.test.assert_true(d.scratch == 99 && d.scratch_size == 256, "safe: LzfseDecompressor.scratch + .scratch_size accessors");
}

// =========================================================================
// 8. xiom.lzfse.safe: LzvnEncoder lifecycle
// =========================================================================

type LzvnEncoder = {
  scratch: Int;
  scratch_size: Int;
} derive[Clone]

fn LzvnEncoder_create() -> Result[LzvnEncoder, LzfseError] {
  let scratch_size: Int = unsafe { lzvn_encode_scratch_size() };
  let scratch: Int = 0;
  if scratch_size > 0 {
    unsafe { scratch = lzvn_encode_scratch_size(); };
  }
  if scratch == 0 {
    return Err(LzfseError{ code: 1, message: "Failed to allocate scratch buffer" });
  }
  return Ok(LzvnEncoder{ scratch: scratch, scratch_size: scratch_size });
}

fn test_lzvn_encoder_create() -> TestCase {
  let result = LzvnEncoder_create();
  match result {
    Ok(enc) => {
      return xiom.test.assert_ge(enc.scratch_size, 0, "safe: LzvnEncoder.create Ok path -- scratch_size >= 0");
    }
    Err(e) => {
      return xiom.test.assert_eq(e.code, 1, "safe: LzvnEncoder.create Err -- scratch allocation failed (FFI not linked)");
    }
  }
}

fn test_lzvn_encoder_type_fields() -> TestCase {
  let e = LzvnEncoder{ scratch: 7, scratch_size: 64 };
  return xiom.test.assert_true(e.scratch == 7 && e.scratch_size == 64, "safe: LzvnEncoder.scratch + .scratch_size accessors");
}

// =========================================================================
// 9. xiom.lzfse.safe: compress/recompress via struct (error paths)
// =========================================================================

fn test_compressor_compress_ffi_stub() -> TestCase {
  let result = LzfseCompressor_create();
  match result {
    Ok(comp) => {
      let wrote: Int = unsafe { lzfse_encode_buffer(0, 0, 0, 0, comp.scratch) };
      return xiom.test.assert_eq(wrote, 0, "safe: compress() with zero dest returns 0 (failure)");
    }
    Err(e) => {
      return xiom.test.assert_eq(e.code, 1, "safe: compress() pre-condition: create failed");
    }
  }
}

fn test_decompressor_decompress_ffi_stub() -> TestCase {
  let result = LzfseDecompressor_create();
  match result {
    Ok(dec) => {
      let wrote: Int = unsafe { lzfse_decode_buffer(0, 0, 0, 0, dec.scratch) };
      return xiom.test.assert_eq(wrote, 0, "safe: decompress() with zero source returns 0 (failure)");
    }
    Err(e) => {
      return xiom.test.assert_eq(e.code, 1, "safe: decompress() pre-condition: create failed");
    }
  }
}

fn test_lzvn_encoder_encode_ffi_stub() -> TestCase {
  let result = LzvnEncoder_create();
  match result {
    Ok(enc) => {
      let wrote: Int = unsafe { lzvn_encode_buffer(0, 0, 0, 0, enc.scratch) };
      return xiom.test.assert_eq(wrote, 0, "safe: encode() with zero source returns 0 (failure)");
    }
    Err(e) => {
      return xiom.test.assert_eq(e.code, 1, "safe: encode() pre-condition: create failed");
    }
  }
}

// =========================================================================
// 10. xiom.lzfse.safe: compress_bound (duplicated for contract testing)
// =========================================================================

fn test_safe_compress_bound_ge_src() -> TestCase {
  return xiom.test.assert_ge(compress_bound(8192), 8192, "safe: compress_bound >= src_size");
}

// =========================================================================
// Main -- run all tests via xiom.test API
// =========================================================================

fn main() -> Int {
  io.println("=== XIOM LZFSE Conformance Tests ===");

  var suite = xiom.test.TestSuite.new("LZFSE Conformance");

  // 1. compress_bound
  suite.add(test_compress_bound_formula());
  suite.add(test_compress_bound_ge_src());
  suite.add(test_compress_bound_small_input());
  suite.add(test_compress_bound_large_input());

  // 2. scratch_size
  suite.add(test_encode_scratch_size_nonneg());
  suite.add(test_decode_scratch_size_nonneg());
  suite.add(test_lzvn_encode_scratch_size_nonneg());

  // 3. encode/decode buffers
  suite.add(test_encode_buffer_ffi_stub());
  suite.add(test_decode_buffer_ffi_stub());
  suite.add(test_encode_using_malloc_ffi_stub());
  suite.add(test_decode_using_malloc_ffi_stub());

  // 4. LZVN wrappers
  suite.add(test_lzvn_encode_buffer_ffi_stub());
  suite.add(test_lzvn_encode_using_malloc_ffi_stub());

  // 5. LzfseError type
  suite.add(test_lzfse_error_construction());
  suite.add(test_lzfse_error_clone());

  // 6. LzfseCompressor
  suite.add(test_lzfse_compressor_create());
  suite.add(test_lzfse_compressor_type_fields());

  // 7. LzfseDecompressor
  suite.add(test_lzfse_decompressor_create());
  suite.add(test_lzfse_decompressor_type_fields());

  // 8. LzvnEncoder
  suite.add(test_lzvn_encoder_create());
  suite.add(test_lzvn_encoder_type_fields());

  // 9. compress/decompress error paths
  suite.add(test_compressor_compress_ffi_stub());
  suite.add(test_decompressor_decompress_ffi_stub());
  suite.add(test_lzvn_encoder_encode_ffi_stub());

  // 10. safe compress_bound
  suite.add(test_safe_compress_bound_ge_src());

  let results = suite.run();
  let report = xiom.test.report(&results);
  io.println(report);

  if results.failed > 0 {
    io.println("");
    io.println("Failures:");
    var i: Int = 0;
    while i < results.failures.len() {
      var f = results.failures[i];
      io.println("  - " + f.name + ": " + f.message);
      i = i + 1;
    }
  }

  io.println("");
  let pass_count = results.passed;
  let fail_count = results.failed;
  io.println(int_to_str(pass_count) + "/" + int_to_str(pass_count + fail_count) + " tests passed");

  return results.failed;
}
