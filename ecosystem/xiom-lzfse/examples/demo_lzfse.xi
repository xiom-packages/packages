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

  return 0;
}

fn demo_procedural_api() {
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
}
