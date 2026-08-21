// XIOM -- Apple LZFSE Compression Library Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Low-level FFI declarations for LZFSE (lzfse.h + lzfse_internal.h).
// LZFSE is Apple's LZ-style compression with Finite State Entropy coding.
// Reference: https://github.com/lzfse/lzfse
//
// Types: size_t -> Int. uint8_t* -> Int. void* -> Int.
// Naming follows the C API verbatim.

module xiom.lzfse

// =========================================================================
// FFI: 6 extern C functions covering all exported symbols
// =========================================================================

extern "C" {
  fn lzfse_encode_scratch_size() -> Int;
  fn lzfse_encode_buffer(dst_buffer: Int, dst_size: Int, src_buffer: Int, src_size: Int, scratch_buffer: Int) -> Int;
  fn lzfse_decode_scratch_size() -> Int;
  fn lzfse_decode_buffer(dst_buffer: Int, dst_size: Int, src_buffer: Int, src_size: Int, scratch_buffer: Int) -> Int;
  fn lzvn_encode_scratch_size() -> Int;
  fn lzvn_encode_buffer(dst: Int, dst_size: Int, src: Int, src_size: Int, work: Int) -> Int;
}

// =========================================================================
// Compression bound -- worst-case estimate for the compressed size
// =========================================================================

pub fn compress_bound(src_size: Int) -> Int
  requires: src_size > 0
{
  return src_size + src_size / 4 + 64;
}

// =========================================================================
// LZFSE safe wrapper functions -- for direct procedural use
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

// =========================================================================
// LZVN safe wrapper functions -- simpler codec for blocks < 4096 bytes
// =========================================================================

pub fn lzvn_encode_scratch_size() -> Int {
  return unsafe { lzvn_encode_scratch_size() };
}

pub fn lzvn_encode_buffer(dst: Int, dst_size: Int, src: Int, src_size: Int, work: Int) -> Result[Int, Str]
  requires: dst != 0
  requires: dst_size > 0
  requires: src != 0
  requires: src_size > 0
{
  let wrote: Int = unsafe { lzvn_encode_buffer(dst, dst_size, src, src_size, work) };
  if wrote == 0 {
    return Err("lzvn_encode_buffer failed: output buffer too small or encode error");
  }
  return Ok(wrote);
}

pub fn lzvn_encode_using_malloc(dst: Int, dst_size: Int, src: Int, src_size: Int) -> Result[Int, Str]
  requires: dst != 0
  requires: dst_size > 0
  requires: src != 0
  requires: src_size > 0
{
  let wrote: Int = unsafe { lzvn_encode_buffer(dst, dst_size, src, src_size, 0) };
  if wrote == 0 {
    return Err("lzvn_encode_buffer failed: output buffer too small or encode error");
  }
  return Ok(wrote);
}
