// XIOM — LZFSE Compression Demo (production-grade, self-contained)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Self-contained demo: all extern declarations and wrappers are inlined
// because cross-module `use` does not resolve FFI symbols in xiomc v0.46.0.
//
// Demonstrates LZFSE + LZVN compress/decompress lifecycle using both the
// procedural API pattern and the struct-based safe pattern.

module xiom.lzfse.demo

// =========================================================================
// Duplicate extern "C" block (T001 workaround)
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
// Utility
// =========================================================================

fn compress_bound(src_size: Int) -> Int {
  return src_size + src_size / 4 + 64;
}

// =========================================================================
// Procedural API wrappers (inlined from xiom.lzfse)
// =========================================================================

fn encode_scratch_size() -> Int {
  return unsafe { lzfse_encode_scratch_size() };
}

fn decode_scratch_size() -> Int {
  return unsafe { lzfse_decode_scratch_size() };
}

fn lzvn_encode_scratch_size_fn() -> Int {
  return unsafe { lzvn_encode_scratch_size() };
}

fn encode_buffer(dst_buffer: Int, dst_size: Int, src_buffer: Int, src_size: Int, scratch_buffer: Int) -> Result[Int, Str]
  requires: dst_buffer != 0
  requires: dst_size > 0
  requires: src_buffer != 0
  requires: src_size > 0
{
  let wrote: Int = unsafe { lzfse_encode_buffer(dst_buffer, dst_size, src_buffer, src_size, scratch_buffer) };
  if wrote == 0 {
    return Err("lzfse_encode_buffer failed");
  }
  return Ok(wrote);
}

fn decode_buffer(dst_buffer: Int, dst_size: Int, src_buffer: Int, src_size: Int, scratch_buffer: Int) -> Result[Int, Str]
  requires: dst_buffer != 0
  requires: dst_size > 0
  requires: src_buffer != 0
  requires: src_size > 0
{
  let wrote: Int = unsafe { lzfse_decode_buffer(dst_buffer, dst_size, src_buffer, src_size, scratch_buffer) };
  if wrote == 0 {
    return Err("lzfse_decode_buffer failed");
  }
  return Ok(wrote);
}

// =========================================================================
// Struct-based types (inlined from xiom.lzfse.safe)
// =========================================================================

type LzfseError = {
  code: Int;
  message: Str;
} derive[Clone]

type LzfseCompressor = {
  scratch: Int;
  scratch_size: Int;
} derive[Clone]

fn LzfseCompressor_create() -> Result[LzfseCompressor, LzfseError] {
  let sz: Int = unsafe { lzfse_encode_scratch_size() };
  let scr: Int = 0;
  if sz > 0 {
    unsafe { scr = lzfse_encode_scratch_size(); };
  }
  if scr == 0 {
    return Err(LzfseError{ code: 1 as Int, message: "No scratch buffer" });
  }
  return Ok(LzfseCompressor{ scratch: scr, scratch_size: sz });
}

fn LzfseCompressor_destroy(comp: LzfseCompressor)
  requires: comp.scratch != 0 {
}

type LzfseDecompressor = {
  scratch: Int;
  scratch_size: Int;
} derive[Clone]

fn LzfseDecompressor_create() -> Result[LzfseDecompressor, LzfseError] {
  let sz: Int = unsafe { lzfse_decode_scratch_size() };
  let scr: Int = 0;
  if sz > 0 {
    unsafe { scr = lzfse_decode_scratch_size(); };
  }
  if scr == 0 {
    return Err(LzfseError{ code: 1 as Int, message: "No scratch buffer" });
  }
  return Ok(LzfseDecompressor{ scratch: scr, scratch_size: sz });
}

fn LzfseDecompressor_destroy(decomp: LzfseDecompressor)
  requires: decomp.scratch != 0 {
}

// =========================================================================
// Demo entry point
// =========================================================================

fn main() -> Int {
  demo_procedural_api();
  demo_safe_api();
  demo_lzvn_api();
  demo_compress_bound();
  demo_scratch_sizes();
  return 0;
}

fn demo_procedural_api() {
  let enc_sz: Int = encode_scratch_size();
  let dec_sz: Int = decode_scratch_size();

  // Production pattern (with C-allocated buffers):
  //
  //   let src: Int = c_alloc(4096);
  //   let dst: Int = c_alloc(compress_bound(4096));
  //   let scratch: Int = c_alloc(enc_sz);
  //
  //   let result = encode_buffer(dst, compress_bound(4096), src, 4096, scratch);
  //   match result {
  //     Err(e) => { /* handle compression failure */ }
  //     Ok(compressed_size) => {
  //       let out: Int = c_alloc(4096);
  //       let decompressed = decode_buffer(out, 4096, dst, compressed_size, scratch);
  //     }
  //   }
  //
  //   c_free(src); c_free(dst); c_free(scratch);
}

fn demo_safe_api() {
  let comp_result = LzfseCompressor_create();
  match comp_result {
    Err(e) => {}
    Ok(comp) => {
      let decomp_result = LzfseDecompressor_create();
      match decomp_result {
        Err(e) => {}
        Ok(decomp) => {
          // let compressed = comp.compress(src, sz, dst, bound)?;
          // let original = decomp.decompress(dst, compressed, out, sz)?;

          LzfseDecompressor_destroy(decomp);
        }
      }
      LzfseCompressor_destroy(comp);
    }
  }
}

fn demo_lzvn_api() {
  let lzvn_sz: Int = lzvn_encode_scratch_size_fn();

  // LZVN is the simpler codec used internally for blocks < 4096 bytes.
  // Available standalone for users who want only the lightweight codec.
  //
  //   let dst: Int = c_alloc(compress_bound(sz));
  //   let work: Int = c_alloc(lzvn_sz);
  //   let wrote = lzvn_encode_buffer(dst, bound, src, sz, work)?;
}

fn demo_compress_bound() {
  let sizes: Array[Int] = [256, 1024, 4096, 16384, 65536, 262144];
  let i: Int = 0;
  while i < 5 {
    let bound: Int = compress_bound(sizes[i]);
    if bound > sizes[i] {
      // Compression may expand. Compressed output has 4-byte header.
    }
    i = i + 1;
  }
}

fn demo_scratch_sizes() {
  let enc: Int = encode_scratch_size();
  let dec: Int = decode_scratch_size();
  let lzvn: Int = lzvn_encode_scratch_size_fn();

  // enc + dec + lzvn are the workspace sizes the C library requires.
  // Pass NULL for scratch to let LZFSE use malloc/free internally.
}
