// XIOM -- xiom.android-sys: libz (zlib) head (A12 compression surface).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: runtime-load unit for the zlib C API (zlib.h of NDK r27b,
// ZLIB_VERSION "1.3.0.1-motley" -> libz.so), backed by the
// self-contained bridge `src/zlib_bridge.c`.  Buffer work happens in
// caller-owned byte slots (B-series discipline); the z_stream lives
// C-side behind an opaque Int handle.
//
//   core (ABI-gated, 12 symbols)
//     zlibVersion, compress, uncompress, compressBound, crc32, adler32,
//     deflateInit_, deflate, deflateEnd, inflateInit_, inflate,
//     inflateEnd
//
// Functional head: compress -> uncompress roundtrip (the required
// fixture), crc32/adler32 checksums, and streaming deflate / inflate
// through explicit begin / set-input / step (Z_FINISH) / end loops
// composed here from the declared primitives.
//
// Classification (the suite maps it to markers):
//   ZLIB_LOAD_ABSENT -> SKIP  (runtime missing; CI stays green)
//   ZLIB_LOAD_ABI    -> FAIL  (present but core exports broken)
//   ZLIB_CALL        -> Err   (live call failure, rc named)

module xiom.android_sys.zlib

use xiom.android_sys;

extern "C" {
  fn xzl_load_named(soname: *UInt8) -> Int32;
  fn xzl_load() -> Int32;
  fn xzl_error() -> *UInt8;
  fn xzl_core_missing_count() -> Int32;
  fn xzl_core_missing() -> *UInt8;
  fn xzl_version() -> *UInt8;
  fn xzl_compress_bound(src_len: Int64) -> Int64;
  fn xzl_compress(src: *UInt8, src_len: Int64, dst: *UInt8, dst_cap: Int64, size_slot: *UInt8) -> Int32;
  fn xzl_uncompress(src: *UInt8, src_len: Int64, dst: *UInt8, dst_cap: Int64, size_slot: *UInt8) -> Int32;
  fn xzl_crc32(init: Int64, src: *UInt8, len: Int64) -> Int64;
  fn xzl_adler32(init: Int64, src: *UInt8, len: Int64) -> Int64;
  fn xzl_deflate_begin(level: Int32) -> Int64;
  fn xzl_deflate_input(h: Int64, src: *UInt8, len: Int64) -> Int32;
  fn xzl_deflate_step(h: Int64, dst: *UInt8, cap: Int64, flush: Int32, size_slot: *UInt8) -> Int32;
  fn xzl_deflate_end(h: Int64) -> Int32;
  fn xzl_inflate_begin() -> Int64;
  fn xzl_inflate_input(h: Int64, src: *UInt8, len: Int64) -> Int32;
  fn xzl_inflate_step(h: Int64, dst: *UInt8, cap: Int64, flush: Int32, size_slot: *UInt8) -> Int32;
  fn xzl_inflate_end(h: Int64) -> Int32;
  fn xzl_rc_name(rc: Int32) -> *UInt8;
  fn xzl_unload();
}

// =========================================================================
// Identity and classification
// =========================================================================

pub const ZLIB_SONAME: Str = "libz.so";

pub const ZLIB_LOAD_ABSENT: Int = 0; // runtime lib missing -> SKIP
pub const ZLIB_LOAD_ABI: Int = 1;    // present but core exports broken -> FAIL
pub const ZLIB_CALL: Int = 2;        // live call failed (rc named)

const ZLIB_UNRESOLVED: Int = -1000; // bridge sentinel, outside the rc range

pub type ZlibRuntime = {
  core_missing: Int;       // unresolved count; 0 = full cover
  core_missing_names: Str;
}

// =========================================================================
// zlib constants (zlib.h r27b)
// =========================================================================

pub const ZLIB_OK: Int = 0;
pub const ZLIB_STREAM_END: Int = 1;
pub const ZLIB_NEED_DICT: Int = 2;
pub const ZLIB_ERRNO: Int = -1;
pub const ZLIB_STREAM_ERROR: Int = -2;
pub const ZLIB_DATA_ERROR: Int = -3;
pub const ZLIB_MEM_ERROR: Int = -4;
pub const ZLIB_BUF_ERROR: Int = -5;
pub const ZLIB_VERSION_ERROR: Int = -6;

pub const ZLIB_NO_FLUSH: Int = 0;
pub const ZLIB_PARTIAL_FLUSH: Int = 1;
pub const ZLIB_SYNC_FLUSH: Int = 2;
pub const ZLIB_FULL_FLUSH: Int = 3;
pub const ZLIB_FINISH: Int = 4;

pub const ZLIB_DEFAULT_COMPRESSION: Int = -1;
pub const ZLIB_NO_COMPRESSION: Int = 0;
pub const ZLIB_BEST_SPEED: Int = 1;
pub const ZLIB_BEST_COMPRESSION: Int = 9;

/// Human name of a zlib return code (e.g. "Z_OK").
/// Complexity: O(1).
pub fn zlib_rc_name(rc: Int) -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xzl_rc_name(rc as Int32)); }
}

// =========================================================================
// Internal slot helpers (module-local; B-series byte-indexed access)
// =========================================================================

fn _zl_zeros(n: Int) -> Vec[UInt8] {
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn _zl_u64_le(buf: &Vec[UInt8], pos: Int) -> Int {
  var v: Int = 0;
  var shift: Int = 1;
  var i = 0;
  while i < 8 {
    v = v + ((buf[pos + i] as Int) & 255) * shift;
    shift = shift * 256;
    i = i + 1;
  }
  return v;
}

fn _zl_append(dst: &mut Vec[UInt8], src: &Vec[UInt8], n: Int) {
  var i = 0;
  while i < n && i < src.len() {
    dst.push(src[i]);
    i = i + 1;
  }
}

fn _zl_call_error(message: Str) -> AndroidSysError {
  return AndroidSysError{ kind: ZLIB_CALL, errno_code: 0, message: message };
}

// =========================================================================
// Probe API
// =========================================================================

/// Probe an explicitly named zlib runtime (bogus names exercise the
/// ABSENT/SKIP classification deterministically).
/// Complexity: O(load + export set).
pub fn zlib_probe_named(soname: Str) -> Result[ZlibRuntime, AndroidSysError]
  requires: soname.len() > 0
{
  let rc = unsafe { xzl_load_named(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xzl_error()) };
    if rc == 1 {
      return Err(AndroidSysError{ kind: ANDROID_SYS_LOAD_ABSENT, errno_code: 0, message: msg });
    }
    return Err(AndroidSysError{ kind: ANDROID_SYS_LOAD_ABI, errno_code: 0, message: msg });
  }
  let missing = unsafe { xzl_core_missing_count() as Int };
  let names = unsafe { Str::from_c_str(xzl_core_missing()) };
  return Ok(ZlibRuntime{ core_missing: missing, core_missing_names: names });
}

/// Probe the default runtime (libz.so).  On Windows the probe classifies
/// ABSENT (SKIP).
/// Complexity: O(load + export set).
pub fn zlib_probe() -> Result[ZlibRuntime, AndroidSysError]
  requires: true
{
  return zlib_probe_named(ZLIB_SONAME);
}

/// The last bridge error summary (empty when clean).
/// Complexity: O(1).
pub fn zlib_error() -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xzl_error()); }
}

/// Release any runtime handles held by the bridge.  Safe when nothing is
/// loaded.  Streaming handles are not closed here (callers end them
/// explicitly).
/// Complexity: O(1).
pub fn zlib_unload()
  requires: true
{
  unsafe { xzl_unload(); }
}

/// The runtime zlib version string (zlibVersion).
/// Complexity: O(1).
pub fn zlib_version() -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xzl_version()); }
}

// =========================================================================
// One-shot helpers (compress/uncompress + checksums)
// =========================================================================

/// Upper bound on the compressed size (compressBound).
/// Complexity: O(1).
pub fn zlib_compress_bound(src_len: Int) -> Int
  requires: src_len >= 0
{
  let rc = unsafe { xzl_compress_bound(src_len as Int64) as Int };
  if rc == ZLIB_UNRESOLVED {
    return -1;
  }
  return rc;
}

/// One-shot zlib deflate (compress) into a buffer sized by
/// `zlib_compress_bound`.  Ok(bytes) = the compressed stream.
/// Complexity: O(src + compressed).
pub fn zlib_compress(src: &mut Vec[UInt8]) -> Result[Vec[UInt8], AndroidSysError]
  requires: true
{
  let bound = zlib_compress_bound(src.len());
  if bound < 0 {
    return Err(AndroidSysError{ kind: ZLIB_LOAD_ABI, errno_code: 0, message: zlib_error() });
  }
  var dst = _zl_zeros(bound);
  var slot = _zl_zeros(8);
  let rc = unsafe {
    xzl_compress(src.as_mut_ptr(), src.len() as Int64, dst.as_mut_ptr(), bound as Int64, slot.as_mut_ptr()) as Int
  };
  if rc == ZLIB_UNRESOLVED {
    return Err(AndroidSysError{ kind: ZLIB_LOAD_ABI, errno_code: 0, message: zlib_error() });
  }
  if rc != ZLIB_OK {
    return Err(_zl_call_error("compress -> " + zlib_rc_name(rc)));
  }
  let n = _zl_u64_le(&slot, 0);
  var out: Vec[UInt8] = Vec[UInt8].new();
  _zl_append(&mut out, &dst, n);
  return Ok(out);
}

/// One-shot zlib inflate (uncompress) with an explicit expected size
/// (uncompress needs the destination capacity up front).
/// Ok(bytes) = the decompressed payload.  Err(ZLIB_CALL, rc named) for
/// Z_DATA_ERROR (corrupt) / Z_BUF_ERROR (capacity too small).
/// Complexity: O(src + expected_len).
pub fn zlib_uncompress(src: &mut Vec[UInt8], expected_len: Int) -> Result[Vec[UInt8], AndroidSysError]
  requires: expected_len > 0
{
  var dst = _zl_zeros(expected_len);
  var slot = _zl_zeros(8);
  let rc = unsafe {
    xzl_uncompress(src.as_mut_ptr(), src.len() as Int64, dst.as_mut_ptr(), expected_len as Int64, slot.as_mut_ptr()) as Int
  };
  if rc == ZLIB_UNRESOLVED {
    return Err(AndroidSysError{ kind: ZLIB_LOAD_ABI, errno_code: 0, message: zlib_error() });
  }
  if rc != ZLIB_OK {
    return Err(_zl_call_error("uncompress -> " + zlib_rc_name(rc)));
  }
  let n = _zl_u64_le(&slot, 0);
  var out: Vec[UInt8] = Vec[UInt8].new();
  _zl_append(&mut out, &dst, n);
  return Ok(out);
}

/// Running CRC-32 (crc32; start with seed 0).  -1 when unresolved.
/// Complexity: O(src).
pub fn zlib_crc32(seed: Int, src: &mut Vec[UInt8]) -> Int
  requires: true
{
  let rc = unsafe { xzl_crc32(seed as Int64, src.as_mut_ptr(), src.len() as Int64) as Int };
  return rc;
}

/// Running Adler-32 (adler32; start with seed 1).  -1 when unresolved.
/// Complexity: O(src).
pub fn zlib_adler32(seed: Int, src: &mut Vec[UInt8]) -> Int
  requires: true
{
  let rc = unsafe { xzl_adler32(seed as Int64, src.as_mut_ptr(), src.len() as Int64) as Int };
  return rc;
}

// =========================================================================
// Streaming basics (deflateInit_/deflate/deflateEnd +
// inflateInit_/inflate/inflateEnd composed here)
// =========================================================================

/// Streaming deflate of the whole buffer with Z_FINISH (level:
/// ZLIB_DEFAULT_COMPRESSION or 0..9).  Exercises deflateInit_ /
/// deflate / deflateEnd through the handle API.
/// Complexity: O(src + compressed).
pub fn zlib_deflate_stream(src: &mut Vec[UInt8], level: Int) -> Result[Vec[UInt8], AndroidSysError]
  requires: level >= -1
  requires: level <= 9
{
  let h = unsafe { xzl_deflate_begin(level as Int32) as Int };
  if h == 0 {
    return Err(_zl_call_error("deflate_begin: " + zlib_error()));
  }
  let set_rc = unsafe { xzl_deflate_input(h as Int64, src.as_mut_ptr(), src.len() as Int64) as Int };
  if set_rc != 0 {
    let msg = "deflate_input: " + zlib_error();
    unsafe { xzl_deflate_end(h as Int64); }
    return Err(_zl_call_error(msg));
  }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var done: Int = 0;
  var failed: Int = 0;
  var message: Str = "";
  var iterations: Int = 0;
  while done == 0 && failed == 0 {
    iterations = iterations + 1;
    if iterations > 4096 {
      failed = 1;
      message = "deflate loop did not converge";
    } else {
      var chunk = _zl_zeros(65536);
      var slot = _zl_zeros(8);
      let rc = unsafe {
        xzl_deflate_step(h as Int64, chunk.as_mut_ptr(), 65536, ZLIB_FINISH as Int32, slot.as_mut_ptr()) as Int
      };
      let n = _zl_u64_le(&slot, 0);
      _zl_append(&mut out, &chunk, n);
      if rc == ZLIB_STREAM_END {
        done = 1;
      } elif rc < 0 {
        failed = 1;
        message = "deflate step -> " + zlib_rc_name(rc);
      } elif n == 0 {
        failed = 1;
        message = "deflate step made no progress";
      }
    }
  }
  let end_rc = unsafe { xzl_deflate_end(h as Int64) as Int };
  if failed != 0 {
    return Err(_zl_call_error(message));
  }
  if end_rc != ZLIB_OK {
    return Err(_zl_call_error("deflate_end -> " + zlib_rc_name(end_rc)));
  }
  return Ok(out);
}

/// Streaming inflate of the whole buffer with Z_FINISH, expecting at most
/// `expected_len` bytes of payload (the loop stops at Z_STREAM_END).
/// Exercises inflateInit_ / inflate / inflateEnd through the handle API.
/// Complexity: O(src + decompressed).
pub fn zlib_inflate_stream(src: &mut Vec[UInt8], expected_len: Int) -> Result[Vec[UInt8], AndroidSysError]
  requires: expected_len > 0
{
  let h = unsafe { xzl_inflate_begin() as Int };
  if h == 0 {
    return Err(_zl_call_error("inflate_begin: " + zlib_error()));
  }
  let set_rc = unsafe { xzl_inflate_input(h as Int64, src.as_mut_ptr(), src.len() as Int64) as Int };
  if set_rc != 0 {
    let msg = "inflate_input: " + zlib_error();
    unsafe { xzl_inflate_end(h as Int64); }
    return Err(_zl_call_error(msg));
  }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var done: Int = 0;
  var failed: Int = 0;
  var message: Str = "";
  var iterations: Int = 0;
  while done == 0 && failed == 0 {
    iterations = iterations + 1;
    if iterations > 4096 {
      failed = 1;
      message = "inflate loop did not converge";
    } else {
      var chunk = _zl_zeros(65536);
      var slot = _zl_zeros(8);
      let rc = unsafe {
        xzl_inflate_step(h as Int64, chunk.as_mut_ptr(), 65536, ZLIB_FINISH as Int32, slot.as_mut_ptr()) as Int
      };
      let n = _zl_u64_le(&slot, 0);
      _zl_append(&mut out, &chunk, n);
      if rc == ZLIB_STREAM_END {
        done = 1;
      } elif rc < 0 {
        failed = 1;
        message = "inflate step -> " + zlib_rc_name(rc);
      } elif n == 0 {
        failed = 1;
        message = "inflate step made no progress";
      }
    }
  }
  let end_rc = unsafe { xzl_inflate_end(h as Int64) as Int };
  if failed != 0 {
    return Err(_zl_call_error(message));
  }
  if end_rc != ZLIB_OK {
    return Err(_zl_call_error("inflate_end -> " + zlib_rc_name(end_rc)));
  }
  return Ok(out);
}
