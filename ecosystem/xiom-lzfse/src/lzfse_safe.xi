// XIOM — LZFSE Compression Safe Wrappers
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Struct-based safe resource management for LZFSE.
// Create/destroy pairs with Result[T, LzfseError] + design-by-contract.

module xiom.lzfse.safe

// Compiler gap T001: duplicate extern "C" block from lzfse.xi
// because cross-module extern resolution resolves to () in xiomc v0.45.3.

extern "C" {
  fn lzfse_encode_scratch_size() -> Int;
  fn lzfse_encode_buffer(dst_buffer: Int, dst_size: Int, src_buffer: Int, src_size: Int, scratch_buffer: Int) -> Int;
  fn lzfse_decode_scratch_size() -> Int;
  fn lzfse_decode_buffer(dst_buffer: Int, dst_size: Int, src_buffer: Int, src_size: Int, scratch_buffer: Int) -> Int;
}

// =========================================================================
// LzfseError
// =========================================================================

pub type LzfseError = {
  code: Int;
  message: Str;
} derive[Clone]

// =========================================================================
// LzfseCompressor — manages scratch buffer for encoding
// =========================================================================

pub type LzfseCompressor = {
  scratch: Int;
  scratch_size: Int;
} derive[Clone]

pub fn LzfseCompressor.create() -> Result[LzfseCompressor, LzfseError]
  ensures: result is Ok => result.unwrap().scratch != 0
{
  let scratch_size: Int = unsafe { lzfse_encode_scratch_size() };
  let scratch: Int = 0;
  if scratch_size > 0 {
    unsafe {
      scratch = lzfse_encode_scratch_size();
    };
  }
  if scratch == 0 {
    return Err(LzfseError{ code: 1 as Int, message: "Failed to allocate scratch buffer" });
  }
  return Ok(LzfseCompressor{ scratch: scratch, scratch_size: scratch_size });
}

pub fn LzfseCompressor.destroy()
  requires: scratch != 0
{
  scratch = 0;
}

pub fn LzfseCompressor.compress(src: Int, src_size: Int, dst: Int, dst_size: Int) -> Result[Int, LzfseError]
  requires: scratch != 0
  requires: src != 0
  requires: src_size > 0
  requires: dst != 0
  requires: dst_size > 0
{
  let wrote: Int = unsafe { lzfse_encode_buffer(dst, dst_size, src, src_size, scratch) };
  if wrote == 0 {
    return Err(LzfseError{ code: 2 as Int, message: "Compression failed: output buffer too small" });
  }
  return Ok(wrote);
}

pub fn LzfseCompressor.compress_oom(src: Int, src_size: Int, dst: Int, dst_size: Int) -> Result[Int, LzfseError]
  requires: src != 0
  requires: src_size > 0
  requires: dst != 0
  requires: dst_size > 0
{
  let wrote: Int = unsafe { lzfse_encode_buffer(dst, dst_size, src, src_size, 0) };
  if wrote == 0 {
    return Err(LzfseError{ code: 2 as Int, message: "Compression failed: output buffer too small" });
  }
  return Ok(wrote);
}

pub fn LzfseCompressor.scratch_buffer_size() -> Int
  requires: scratch != 0
{
  return scratch_size;
}

// =========================================================================
// LzfseDecompressor — manages scratch buffer for decoding
// =========================================================================

pub type LzfseDecompressor = {
  scratch: Int;
  scratch_size: Int;
} derive[Clone]

pub fn LzfseDecompressor.create() -> Result[LzfseDecompressor, LzfseError]
  ensures: result is Ok => result.unwrap().scratch != 0
{
  let scratch_size: Int = unsafe { lzfse_decode_scratch_size() };
  let scratch: Int = 0;
  if scratch_size > 0 {
    unsafe {
      scratch = lzfse_decode_scratch_size();
    };
  }
  if scratch == 0 {
    return Err(LzfseError{ code: 1 as Int, message: "Failed to allocate scratch buffer" });
  }
  return Ok(LzfseDecompressor{ scratch: scratch, scratch_size: scratch_size });
}

pub fn LzfseDecompressor.destroy()
  requires: scratch != 0
{
  scratch = 0;
}

pub fn LzfseDecompressor.decompress(src: Int, src_size: Int, dst: Int, dst_size: Int) -> Result[Int, LzfseError]
  requires: scratch != 0
  requires: src != 0
  requires: src_size > 0
  requires: dst != 0
  requires: dst_size > 0
{
  let wrote: Int = unsafe { lzfse_decode_buffer(dst, dst_size, src, src_size, scratch) };
  if wrote == 0 {
    return Err(LzfseError{ code: 3 as Int, message: "Decompression failed: decode error" });
  }
  return Ok(wrote);
}

pub fn LzfseDecompressor.decompress_oom(src: Int, src_size: Int, dst: Int, dst_size: Int) -> Result[Int, LzfseError]
  requires: src != 0
  requires: src_size > 0
  requires: dst != 0
  requires: dst_size > 0
{
  let wrote: Int = unsafe { lzfse_decode_buffer(dst, dst_size, src, src_size, 0) };
  if wrote == 0 {
    return Err(LzfseError{ code: 3 as Int, message: "Decompression failed: decode error" });
  }
  return Ok(wrote);
}

pub fn LzfseDecompressor.scratch_buffer_size() -> Int
  requires: scratch != 0
{
  return scratch_size;
}

// =========================================================================
// Utility: worst-case compressed size bound
// =========================================================================

pub fn compress_bound(src_size: Int) -> Int
  requires: src_size > 0
{
  return src_size + src_size / 4 as Int + 64 as Int;
}
