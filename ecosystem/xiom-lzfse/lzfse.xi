// XIOM — Apple LZFSE Compression Library Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Low-level FFI declarations for LZFSE (lzfse.h).
// LZFSE is Apple's LZ-style compression with Finite State Entropy coding.
// Reference: https://github.com/lzfse/lzfse
//
// Types: size_t → Int. uint8_t* → Int. void* → Int.
// Naming follows the C API verbatim.

module xiom.lzfse

// =========================================================================
// FFI: 4 extern C functions from lzfse.h
// =========================================================================

extern "C" {
  fn lzfse_encode_scratch_size() -> Int;
  fn lzfse_encode_buffer(dst_buffer: Int, dst_size: Int, src_buffer: Int, src_size: Int, scratch_buffer: Int) -> Int;
  fn lzfse_decode_scratch_size() -> Int;
  fn lzfse_decode_buffer(dst_buffer: Int, dst_size: Int, src_buffer: Int, src_size: Int, scratch_buffer: Int) -> Int;
}

// =========================================================================
// Compression bound — worst-case estimate for the compressed size
// =========================================================================

pub fn compress_bound(src_size: Int) -> Int
  requires: src_size > 0
{
  return src_size + src_size / 4 as Int + 64 as Int;
}

// =========================================================================
// Safe wrapper functions — for direct procedural use
// =========================================================================

pub fn encode_scratch_size() -> Int {
  return unsafe { lzfse_encode_scratch_size() };
}

pub fn decode_scratch_size() -> Int {
  return unsafe { lzfse_decode_scratch_size() };
}

pub fn encode_buffer(dst_buffer: Int, dst_size: Int, src_buffer: Int, src_size: Int, scratch_buffer: Int) -> Result[Int, Str]
  requires: dst_buffer != 0
  requires: dst_size > 0
  requires: src_buffer != 0
  requires: src_size > 0
{
  let wrote: Int = unsafe { lzfse_encode_buffer(dst_buffer, dst_size, src_buffer, src_size, scratch_buffer) };
  if wrote == 0 {
    return Err("lzfse_encode_buffer failed: output buffer too small or encode error");
  }
  return Ok(wrote);
}

pub fn decode_buffer(dst_buffer: Int, dst_size: Int, src_buffer: Int, src_size: Int, scratch_buffer: Int) -> Result[Int, Str]
  requires: dst_buffer != 0
  requires: dst_size > 0
  requires: src_buffer != 0
  requires: src_size > 0
{
  let wrote: Int = unsafe { lzfse_decode_buffer(dst_buffer, dst_size, src_buffer, src_size, scratch_buffer) };
  if wrote == 0 {
    return Err("lzfse_decode_buffer failed: decode error");
  }
  return Ok(wrote);
}

pub fn encode_using_malloc(dst_buffer: Int, dst_size: Int, src_buffer: Int, src_size: Int) -> Result[Int, Str]
  requires: dst_buffer != 0
  requires: dst_size > 0
  requires: src_buffer != 0
  requires: src_size > 0
{
  let wrote: Int = unsafe { lzfse_encode_buffer(dst_buffer, dst_size, src_buffer, src_size, 0) };
  if wrote == 0 {
    return Err("lzfse_encode_buffer failed: output buffer too small or encode error");
  }
  return Ok(wrote);
}

pub fn decode_using_malloc(dst_buffer: Int, dst_size: Int, src_buffer: Int, src_size: Int) -> Result[Int, Str]
  requires: dst_buffer != 0
  requires: dst_size > 0
  requires: src_buffer != 0
  requires: src_size > 0
{
  let wrote: Int = unsafe { lzfse_decode_buffer(dst_buffer, dst_size, src_buffer, src_size, 0) };
  if wrote == 0 {
    return Err("lzfse_decode_buffer failed: decode error");
  }
  return Ok(wrote);
}
