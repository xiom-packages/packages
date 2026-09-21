// XIOM -- Zstandard Compression Safe Wrappers
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Safe wrappers around libzstd via extern "C" FFI.
// Vec[UInt8]-based API with design-by-contract.
// Compiles cleanly; links against system-installed libzstd at link time.
//
// Compiler gap: Vec[UInt8] <-> raw pointer marshaling is blocked on
// compiler *UInt8 dereference support. Until resolved, FFI calls use
// zero (null) as placeholder and return error codes.

module xiom.zstd

extern "C" {
  fn ZSTD_compress(dst: Int, dstCapacity: Int, src: Int, srcSize: Int, compressionLevel: Int) -> Int;
  fn ZSTD_decompress(dst: Int, dstCapacity: Int, src: Int, compressedSize: Int) -> Int;
  fn ZSTD_compressBound(srcSize: Int) -> Int;
  fn ZSTD_isError(code: Int) -> Int;
  fn ZSTD_getErrorName(code: Int) -> Int;
}

// =========================================================================
// compress_bound -- worst-case compressed size
//
// The ZSTD_compressBound() result is guaranteed to be >= the compressed
// size of any srcSize-byte input. Used to size the output buffer before
// calling compress().
// =========================================================================

pub fn compress_bound(size: Int) -> Int
  requires: size > 0
{
  return unsafe { ZSTD_compressBound(size) };
}

// =========================================================================
// compress -- compress data with given compression level (1..22)
//
// Returns Ok(compressed_data) on success or Err(message) on failure.
// Level 1 = fastest, level 22 = maximum compression (slowest).
// =========================================================================

pub fn compress(src: &Vec[UInt8], level: Int) -> Result[Vec[UInt8], Str]
  requires: src.len() > 0
  requires: level >= 1
  requires: level <= 22
{
  let srcSize = src.len();
  let dstCapacity = unsafe { ZSTD_compressBound(srcSize) };
  if dstCapacity <= 0 {
    return Err("ZSTD_compressBound returned invalid bound");
  }
  let compressedSize: Int = unsafe { ZSTD_compress(0, dstCapacity, 0, srcSize, level) };
  let zstdErr: Int = unsafe { ZSTD_isError(compressedSize) };
  if zstdErr != 0 {
    return Err("ZSTD_compress failed: library not linked or compression error");
  }
  return Err("ZSTD_compress: Vec[UInt8] result construction requires compiler *UInt8 support");
}

// =========================================================================
// decompress -- decompress zstd-compressed data
//
// Returns Ok(original_data) on success or Err(message) on failure.
// =========================================================================

pub fn decompress(src: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
  requires: src.len() > 0
{
  let srcSize = src.len();
  let estCapacity = srcSize * 4;
  let decompressedSize: Int = unsafe { ZSTD_decompress(0, estCapacity, 0, srcSize) };
  let zstdErr: Int = unsafe { ZSTD_isError(decompressedSize) };
  if zstdErr != 0 {
    return Err("ZSTD_decompress failed: library not linked or decompression error");
  }
  return Err("ZSTD_decompress: Vec[UInt8] result construction requires compiler *UInt8 support");
}
