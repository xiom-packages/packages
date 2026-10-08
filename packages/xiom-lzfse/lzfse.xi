// XIOM -- xiom.lzfse: LZFSE bindings (vendored Apple sources).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: vendored C path (same pattern as xiom.zstd / xiom.sqlite). The
// upstream `lzfse-1.0` library sources (Apple, BSD-3-Clause) are vendored
// into `vendor/` and compiled into the test binary via `--c-source`
// (port.args.json lists the seven library sources; no system library, no
// runtime DLL).
//
// G5 confinement: this is the ONE module in the package with `extern "C"`;
// every foreign call is wrapped here. Other files are pure XIOM.
//
// G2 pin (SPEC.md): upstream tag `lzfse-1.0` (archive SHA256) + per-file
// SHA256 of the vendored sources + BSD-3-Clause license.
//
// API subset (pilot): encode/decode scratch sizes + one-shot
// encode/decode into XIOM-owned buffers.  Streaming/chunked decode is
// Phase 2 (ROADMAP.md): the LZFSE stream does not expose a frame content
// size, so callers pass the output capacity.

module xiom.lzfse

extern "C" {
  fn lzfse_encode_scratch_size() -> Int;
  fn lzfse_decode_scratch_size() -> Int;
  fn lzfse_encode_buffer(dst: *UInt8, dst_size: Int, src: *UInt8, src_size: Int, scratch: *UInt8) -> Int;
  fn lzfse_decode_buffer(dst: *UInt8, dst_size: Int, src: *UInt8, src_size: Int, scratch: *UInt8) -> Int;
}

/// Required encode scratch-buffer size.
/// Complexity: O(1).
pub fn lzfse_encode_scratch_required() -> Int
  requires: true
{
  unsafe { return lzfse_encode_scratch_size() as Int; }
}

/// Required decode scratch-buffer size.
/// Complexity: O(1).
pub fn lzfse_decode_scratch_required() -> Int
  requires: true
{
  unsafe { return lzfse_decode_scratch_size() as Int; }
}

/// One-shot LZFSE encode of `src` into a buffer of `dst_capacity` bytes
/// (use >= src.len() + slack; LZFSE may expand incompressible input
/// slightly).  Returns the encoded bytes as a new buffer.
/// Complexity: O(len(src)) plus encode work.
pub fn lzfse_encode(src: &mut Vec[UInt8], dst_capacity: Int) -> Result[Vec[UInt8], Str]
  requires: src.len() >= 0
  requires: dst_capacity > 0
{
  var dst: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < dst_capacity {
    dst.push(0 as UInt8);
    i = i + 1;
  }
  let scratch_size = lzfse_encode_scratch_required();
  var scratch: Vec[UInt8] = Vec[UInt8].new();
  var j: Int = 0;
  while j < scratch_size {
    scratch.push(0 as UInt8);
    j = j + 1;
  }
  let rc = unsafe {
    lzfse_encode_buffer(dst.as_mut_ptr(), dst_capacity, src.as_mut_ptr(), src.len(), scratch.as_mut_ptr())
  };
  if rc <= 0 {
    return Err("lzfse: encode failed (destination capacity too small?)");
  }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var k: Int = 0;
  while k < rc {
    out.push(dst[k]);
    k = k + 1;
  }
  return Ok(out);
}

/// One-shot LZFSE decode of `src` into a buffer of `dst_capacity` bytes.
/// Returns the decoded bytes as a new buffer.
/// Complexity: O(len(src)) plus decode work.
pub fn lzfse_decode(src: &mut Vec[UInt8], dst_capacity: Int) -> Result[Vec[UInt8], Str]
  requires: src.len() > 0
  requires: dst_capacity > 0
{
  var dst: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < dst_capacity {
    dst.push(0 as UInt8);
    i = i + 1;
  }
  let scratch_size = lzfse_decode_scratch_required();
  var scratch: Vec[UInt8] = Vec[UInt8].new();
  var j: Int = 0;
  while j < scratch_size {
    scratch.push(0 as UInt8);
    j = j + 1;
  }
  let rc = unsafe {
    lzfse_decode_buffer(dst.as_mut_ptr(), dst_capacity, src.as_mut_ptr(), src.len(), scratch.as_mut_ptr())
  };
  if rc <= 0 {
    return Err("lzfse: decode failed (invalid stream or capacity too small)");
  }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var k: Int = 0;
  while k < rc {
    out.push(dst[k]);
    k = k + 1;
  }
  return Ok(out);
}
