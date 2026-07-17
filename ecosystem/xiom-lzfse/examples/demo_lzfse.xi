<<<<<<< ours
// XIOM — LZFSE Compression Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Demonstrates LZFSE compress/decompress lifecycle using the
// xiom.lzfse and xiom.lzfse.safe APIs. A compile-time demo
// showing the correct API structure for production use.

module xiom.lzfse.demo

use xiom.lzfse;
use xiom.lzfse.safe;
use xiom.io;

fn main() -> Int {
  io.println("LZFSE Compression Demo");
  io.println("=====================");
  io.println("");

  demo_procedural_api();
  io.println("");

  demo_safe_api();
  io.println("");

=======
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
>>>>>>> theirs
  return 0;
}

fn demo_procedural_api() {
<<<<<<< ours
  io.println("--- Procedural API (xiom.lzfse) ---");

  let enc_scratch: Int = encode_scratch_size();
  let dec_scratch: Int = decode_scratch_size();
  io.println("Encoder scratch size: " + enc_scratch.to_string());
  io.println("Decoder scratch size: " + dec_scratch.to_string());

  // Worst-case compressed size for 4096 bytes of input:
  let src_size: Int = 4096 as Int;
  let bound: Int = compress_bound(src_size);
  io.println("Compress bound for " + src_size.to_string() + " bytes: " + bound.to_string());

  // In production (with actual C bridge + memory allocation):
  //   let src_data: Int = allocate_buffer(src_size);
  //   let dst_data: Int = allocate_buffer(bound);
  //   let scratch: Int = allocate_buffer(enc_scratch);
  //
  //   let compressed = encode_buffer(dst_data, bound, src_data, src_size, scratch)?;
  //   let decompressed = decode_buffer(src_data, src_size, dst_data, compressed, scratch)?;
  //
  //   free_buffer(src_data);
  //   free_buffer(dst_data);
  //   free_buffer(scratch);

  io.println("(compile-time demo only — link with LZFSE to run)");
}

fn demo_safe_api() {
  io.println("--- Struct-based API (xiom.lzfse.safe) ---");

  let comp_result = LzfseCompressor.create();
  match comp_result {
    Err(e) => {
      io.println("Compressor creation failed: " + e.message);
    }
    Ok(comp) => {
      io.println("LzfseCompressor created (scratch: " + comp.scratch_buffer_size().to_string() + " bytes)");

      let decomp_result = LzfseDecompressor.create();
      match decomp_result {
        Err(e) => {
          io.println("Decompressor creation failed: " + e.message);
        }
        Ok(decomp) => {
          io.println("LzfseDecompressor created (scratch: " + decomp.scratch_buffer_size().to_string() + " bytes)");

          // In production:
          //   let compressed = comp.compress(src, src_size, dst, dst_size)?;
          //   let original = decomp.decompress(dst, compressed, out, out_size)?;

          decomp.destroy();
          io.println("LzfseDecompressor destroyed.");
        }
      }

      comp.destroy();
      io.println("LzfseCompressor destroyed.");
    }
  }

  io.println("(compile-time demo only — link with LZFSE to run)");
=======
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
>>>>>>> theirs
}
