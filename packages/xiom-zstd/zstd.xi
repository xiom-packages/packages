// XIOM -- xiom.zstd: Zstandard bindings (vendored single-file amalgamation).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: vendored C path (same pattern as xiom.sqlite). The official
// single-file amalgamation `vendor/zstd.c` (generated with the upstream
// combine.py from release v1.5.7, BSD-3-Clause) is compiled into the test
// binary via `--c-source` (port.args.json); `vendor/zstd.h` and the upstream
// LICENSE are vendored alongside. No system library, no runtime DLL.
//
// G5 confinement: this is the ONE module in the package with `extern "C"`;
// every foreign call is wrapped here. Other modules are pure XIOM.
//
// G2 pin (SPEC.md): upstream release v1.5.7 (tar.gz SHA256 verified against
// the published .sha256) + generated `vendor/zstd.c` SHA256 + `vendor/zstd.h`
// SHA256 + BSD-3-Clause license.
//
// API subset (pilot): version, compressBound, one-shot compress/decompress,
// frame content size, error detection/naming. Streaming CCtx/DCtx and
// dictionaries are Phase 2 (ROADMAP.md).

module xiom.zstd

extern "C" {
  fn ZSTD_versionNumber() -> UInt32;
  fn ZSTD_compressBound(srcSize: Int) -> Int;
  fn ZSTD_compress(dst: *UInt8, dstCapacity: Int, src: *UInt8, srcSize: Int, compressionLevel: Int) -> Int;
  fn ZSTD_decompress(dst: *UInt8, dstCapacity: Int, src: *UInt8, compressedSize: Int) -> Int;
  fn ZSTD_getFrameContentSize(src: *UInt8, srcSize: Int) -> UInt64;
  fn ZSTD_isError(code: Int) -> UInt32;
  fn ZSTD_getErrorName(code: Int) -> *UInt8;
}

// ZSTD_getFrameContentSize sentinels (zstd.h).
pub const ZSTD_CONTENTSIZE_UNKNOWN: Int = -1;
pub const ZSTD_CONTENTSIZE_ERROR: Int = -2;

/// Runtime zstd version as an integer (e.g. 10507 for 1.5.7).
/// Complexity: O(1).
pub fn zstd_version_number() -> Int
  requires: true
{
  unsafe { return ZSTD_versionNumber() as Int; }
}

/// Human version string derived from the version number.
/// Complexity: O(1).
pub fn zstd_version() -> Str
  requires: true
{
  let v = zstd_version_number();
  return int_to_str(v / 10000) + "." + int_to_str((v / 100) % 100) + "." + int_to_str(v % 100);
}

/// Worst-case compressed size for an input of `src_size` bytes.
/// Complexity: O(1).
pub fn zstd_compress_bound(src_size: Int) -> Int
  requires: src_size >= 0
{
  unsafe { return ZSTD_compressBound(src_size); }
}

/// True when a returned size_t is an error code.
/// Complexity: O(1).
pub fn zstd_is_error(code: Int) -> Bool
  requires: true
{
  unsafe { return (ZSTD_isError(code) as Int) != 0; }
}

/// Error name for an error code ("" when the code is not an error).
/// Complexity: O(len).
pub fn zstd_error_name(code: Int) -> Str
  requires: true
{
  unsafe {
    let p = ZSTD_getErrorName(code);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// Content size declared by a zstd frame, or ZSTD_CONTENTSIZE_UNKNOWN (-1) /
/// ZSTD_CONTENTSIZE_ERROR (-2).
/// Complexity: O(1).
pub fn zstd_frame_content_size(src: &mut Vec[UInt8]) -> Int
  requires: src.len() > 0
{
  unsafe {
    let v = ZSTD_getFrameContentSize(src.as_mut_ptr(), src.len());
    if v == 18446744073709551615 { return ZSTD_CONTENTSIZE_UNKNOWN; }
    if v == 18446744073709551614 { return ZSTD_CONTENTSIZE_ERROR; }
    return v as Int;
  }
}

/// One-shot compression of `src` at `level` (1..22; 3 is the default).
/// Returns the compressed frame as a new buffer.
/// Complexity: O(len(src)) plus compression work.
pub fn zstd_compress(src: &mut Vec[UInt8], level: Int) -> Result[Vec[UInt8], Str]
  requires: src.len() >= 0
  requires: level >= 1
  requires: level <= 22
{
  let bound = zstd_compress_bound(src.len());
  var dst: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < bound {
    dst.push(0 as UInt8);
    i = i + 1;
  }
  let rc = unsafe { ZSTD_compress(dst.as_mut_ptr(), bound, src.as_mut_ptr(), src.len(), level) };
  if zstd_is_error(rc) {
    return Err(zstd_error_name(rc));
  }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var k: Int = 0;
  while k < rc {
    out.push(dst[k]);
    k = k + 1;
  }
  return Ok(out);
}

/// One-shot decompression into a buffer of `out_capacity` bytes.
/// Returns the decompressed bytes as a new buffer.
/// Complexity: O(compressed) plus decompression work.
pub fn zstd_decompress(src: &mut Vec[UInt8], out_capacity: Int) -> Result[Vec[UInt8], Str]
  requires: src.len() > 0
  requires: out_capacity > 0
{
  var dst: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < out_capacity {
    dst.push(0 as UInt8);
    i = i + 1;
  }
  let rc = unsafe { ZSTD_decompress(dst.as_mut_ptr(), out_capacity, src.as_mut_ptr(), src.len()) };
  if zstd_is_error(rc) {
    return Err(zstd_error_name(rc));
  }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var k: Int = 0;
  while k < rc {
    out.push(dst[k]);
    k = k + 1;
  }
  return Ok(out);
}

/// Decompress using the frame content size recorded in the zstd frame
/// (single-shot frames record it).  Err when the size is unknown.
/// Complexity: O(compressed) plus decompression work.
pub fn zstd_decompress_auto(src: &mut Vec[UInt8]) -> Result[Vec[UInt8], Str]
  requires: src.len() > 0
{
  let size = zstd_frame_content_size(src);
  if size == ZSTD_CONTENTSIZE_UNKNOWN {
    return Err("zstd: frame content size unknown");
  }
  if size == ZSTD_CONTENTSIZE_ERROR {
    return Err("zstd: not a valid zstd frame");
  }
  if size <= 0 {
    return Err("zstd: frame content size is not positive");
  }
  return zstd_decompress(src, size);
}

// Local integer-to-string (avoids cross-module const/convert pitfalls in the
// confined module; see docs/BINDINGS-COMPILER-FINDINGS.md).
fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var neg = false;
  if num < 0 { neg = true; num = 0 - num; }
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
  if neg { return "-" + out; }
  return out;
}
