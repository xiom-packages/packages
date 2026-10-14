// XIOM -- xiom.lz4: LZ4 (block, HC and frame) bindings facade.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Public ergonomic API over the complete confined surface in xiom.lz4.ffi
// (G5: the ffi module is the ONLY one with `extern "C"`; this module contains
// no `unsafe`).  The pinned upstream is lz4 v1.10.0
// (ebb370ca83af193212df4dcbadcc5d87bc0de2f0, lib/ BSD-2-Clause), vendored in
// vendor/lz4 and compiled into the test binary via --c-source.
//
// Two levels:
//   * xiom.lz4 (this module): constants, Lz4Error, slot helpers for frame
//     preferences/options, and one-shot helpers that own their buffers
//     (lz4_compress, lz4_decompress, lz4hc_compress, lz4f_compress_frame,
//     lz4f_decompress, frame info parsing).
//   * xiom.lz4.ffi: the faithful 1:1 surface (111 functions) for streaming,
//     dictionaries and every deprecated/static-linking-only entry point.
//
// Error model: block codecs signal failure with negative returns; frame
// codecs with LZ4F-encoded size_t codes.  Helpers map both to
// Result[_, Lz4Error] where `code` is the raw value and `message` is
// LZ4F_getErrorName text (bridge-copied; XIOM never reads foreign pointers).

module xiom.lz4

use xiom.string;
use xiom.lz4.ffi;

// --- header constants (lz4 v1.10.0) -----------------------------------------

pub const LZ4_VERSION_MAJOR: Int = 1;
pub const LZ4_VERSION_MINOR: Int = 10;
pub const LZ4_VERSION_RELEASE: Int = 0;
pub const LZ4_VERSION_NUMBER: Int = 11000;
pub const LZ4_MAX_INPUT_SIZE: Int = 2113929216;
pub const LZ4_MEMORY_USAGE_DEFAULT: Int = 14;
pub const LZ4_ACCELERATION_DEFAULT: Int = 1;
pub const LZ4_ACCELERATION_MAX: Int = 65537;
pub const LZ4HC_CLEVEL_MIN: Int = 2;
pub const LZ4HC_CLEVEL_DEFAULT: Int = 9;
pub const LZ4HC_CLEVEL_OPT_MIN: Int = 10;
pub const LZ4HC_CLEVEL_MAX: Int = 12;

pub const LZ4F_VERSION: Int = 100;
pub const LZ4F_MAGICNUMBER: Int = 407708164;
pub const LZ4F_MAGIC_SKIPPABLE_START: Int = 407710288;
pub const LZ4F_HEADER_SIZE_MIN: Int = 7;
pub const LZ4F_HEADER_SIZE_MAX: Int = 19;
pub const LZ4F_BLOCK_HEADER_SIZE: Int = 4;
pub const LZ4F_BLOCK_CHECKSUM_SIZE: Int = 4;
pub const LZ4F_CONTENT_CHECKSUM_SIZE: Int = 4;
pub const LZ4F_MIN_SIZE_TO_KNOW_HEADER_LENGTH: Int = 5;

// LZ4F_blockSizeID_t
pub const LZ4F_BLOCKSIZE_DEFAULT: Int = 0;
pub const LZ4F_MAX64KB: Int = 4;
pub const LZ4F_MAX256KB: Int = 5;
pub const LZ4F_MAX1MB: Int = 6;
pub const LZ4F_MAX4MB: Int = 7;
// LZ4F_blockMode_t
pub const LZ4F_BLOCK_LINKED: Int = 0;
pub const LZ4F_BLOCK_INDEPENDENT: Int = 1;
// LZ4F_contentChecksum_t / LZ4F_blockChecksum_t / LZ4F_frameType_t
pub const LZ4F_NO_CONTENT_CHECKSUM: Int = 0;
pub const LZ4F_CONTENT_CHECKSUM_ENABLED: Int = 1;
pub const LZ4F_NO_BLOCK_CHECKSUM: Int = 0;
pub const LZ4F_BLOCK_CHECKSUM_ENABLED: Int = 1;
pub const LZ4F_FRAME: Int = 0;
pub const LZ4F_SKIPPABLE_FRAME: Int = 1;

// LZ4F_errorCodes (LZ4F_LIST_ERRORS order, v1.10.0)
pub const LZ4F_OK_NO_ERROR: Int = 0;
pub const LZ4F_ERROR_GENERIC: Int = 1;
pub const LZ4F_ERROR_MAX_BLOCK_SIZE_INVALID: Int = 2;
pub const LZ4F_ERROR_BLOCK_MODE_INVALID: Int = 3;
pub const LZ4F_ERROR_PARAMETER_INVALID: Int = 4;
pub const LZ4F_ERROR_COMPRESSION_LEVEL_INVALID: Int = 5;
pub const LZ4F_ERROR_HEADER_VERSION_WRONG: Int = 6;
pub const LZ4F_ERROR_BLOCK_CHECKSUM_INVALID: Int = 7;
pub const LZ4F_ERROR_RESERVED_FLAG_SET: Int = 8;
pub const LZ4F_ERROR_ALLOCATION_FAILED: Int = 9;
pub const LZ4F_ERROR_SRC_SIZE_TOO_LARGE: Int = 10;
pub const LZ4F_ERROR_DST_MAX_SIZE_TOO_SMALL: Int = 11;
pub const LZ4F_ERROR_FRAME_HEADER_INCOMPLETE: Int = 12;
pub const LZ4F_ERROR_FRAME_TYPE_UNKNOWN: Int = 13;
pub const LZ4F_ERROR_FRAME_SIZE_WRONG: Int = 14;
pub const LZ4F_ERROR_SRC_PTR_WRONG: Int = 15;
pub const LZ4F_ERROR_DECOMPRESSION_FAILED: Int = 16;
pub const LZ4F_ERROR_HEADER_CHECKSUM_INVALID: Int = 17;
pub const LZ4F_ERROR_CONTENT_CHECKSUM_INVALID: Int = 18;
pub const LZ4F_ERROR_FRAME_DECODING_ALREADY_STARTED: Int = 19;
pub const LZ4F_ERROR_COMPRESSION_STATE_UNINITIALIZED: Int = 20;
pub const LZ4F_ERROR_PARAMETER_NULL: Int = 21;
pub const LZ4F_ERROR_IO_WRITE: Int = 22;
pub const LZ4F_ERROR_IO_READ: Int = 23;
pub const LZ4F_ERROR_MAX_CODE: Int = 24;

// Slot sizes (bridge-pinned)
pub const LZ4F_FRAME_INFO_BYTES: Int = 32;
pub const LZ4F_PREFERENCES_BYTES: Int = 56;
pub const LZ4F_COMPRESS_OPTIONS_BYTES: Int = 16;
pub const LZ4F_DECOMPRESS_OPTIONS_BYTES: Int = 16;
pub const LZ4F_CUSTOM_MEM_BYTES: Int = 32;

// --- types ------------------------------------------------------------------

pub type Lz4Error = {
  code: Int;
  message: Str;
}

pub fn Lz4Error.new(code: Int, message: Str) -> Lz4Error {
  return Lz4Error{ code: code, message: message };
}

pub type Lz4fFrameInfo = {
  block_size_id: Int;
  block_mode: Int;
  content_checksum_flag: Int;
  frame_type: Int;
  content_size: Int;
  dict_id: Int;
  block_checksum_flag: Int;
}

pub fn Lz4fFrameInfo.new() -> Lz4fFrameInfo {
  return Lz4fFrameInfo{
    block_size_id: 0, block_mode: 0, content_checksum_flag: 0, frame_type: 0,
    content_size: 0, dict_id: 0, block_checksum_flag: 0
  };
}

// --- version / errors -------------------------------------------------------

/// Runtime LZ4_versionNumber() (11000 for v1.10.0).
/// Complexity: O(1).
pub fn lz4_version_number() -> Int {
  return ffi.version_number();
}

/// Runtime LZ4_versionString() (bridge-copied; no foreign-pointer reads).
/// Complexity: O(1).
pub fn lz4_version_string() -> Str {
  var buf = ffi.zero_bytes(32);
  let n = ffi.copy_version_string(&mut buf);
  if n <= 0 { return ""; }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    out.push(buf[i]);
    i = i + 1;
  }
  return Str::from_utf8(out);
}

/// True when a frame result encodes an LZ4F error (LZ4F_isError).
/// Complexity: O(1).
pub fn lz4f_is_error(code: Int) -> Bool {
  return (ffi.is_error(code) as Int) != 0;
}

/// LZ4F error code name, bridge-copied into an owned Str.
/// Complexity: O(1).
pub fn lz4f_error_message(code: Int) -> Str {
  var buf = ffi.zero_bytes(96);
  let n = ffi.copy_error_name(code, &mut buf);
  if n <= 0 { return "lz4f: unknown error"; }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    out.push(buf[i]);
    i = i + 1;
  }
  return Str::from_utf8(out);
}

/// Typed error for a raw LZ4F code (LZ4F_getErrorCode value or negative).
/// Complexity: O(1).
pub fn lz4f_error(code: Int) -> Lz4Error {
  return Lz4Error.new(code, lz4f_error_message(code));
}

/// Typed error for a block-codec return value.
/// Complexity: O(1).
pub fn lz4_block_error(rc: Int) -> Lz4Error {
  return Lz4Error.new(rc, "lz4: block codec failed (negative return; corrupt/truncated input or output capacity too small)");
}

/// LZ4_decoderRingBufferSize(maxBlockSize) = 65536 + 14 + maxBlockSize.
/// Complexity: O(1).
pub fn lz4_decoder_ring_buffer_size(max_block_size: Int) -> Int
  requires: max_block_size >= 0
{
  return 65536 + 14 + max_block_size;
}

// --- bounds -----------------------------------------------------------------

/// LZ4_compressBound (also the HC bound).
/// Complexity: O(1).
pub fn lz4_compress_bound(input_size: Int) -> Int
  requires: input_size >= 0
{
  return ffi.compress_bound(input_size);
}

/// LZ4F_compressFrameBound over an owned 56-byte preferences slot.
/// Complexity: O(1).
pub fn lz4f_compress_frame_bound(src_size: Int, prefs: &mut Vec[UInt8]) -> Int
  requires: src_size >= 0
  requires: prefs.len() >= LZ4F_PREFERENCES_BYTES
{
  return ffi.compress_frame_bound(src_size, prefs);
}

// --- one-shot block codec ---------------------------------------------------

/// One-shot block compression (LZ4_compress_fast, default acceleration = 1).
/// Complexity: O(len).
pub fn lz4_compress(src: &mut Vec[UInt8], acceleration: Int) -> Result[Vec[UInt8], Lz4Error]
  requires: acceleration > 0
{
  if src.len() > LZ4_MAX_INPUT_SIZE {
    return Err(Lz4Error.new(LZ4F_ERROR_SRC_SIZE_TOO_LARGE, "lz4: input larger than LZ4_MAX_INPUT_SIZE"));
  }
  let bound = ffi.compress_bound(src.len());
  var dst = ffi.zero_bytes(bound);
  let rc = ffi.compress_fast(src, &mut dst, src.len(), bound, acceleration);
  if rc <= 0 { return Err(lz4_block_error(rc)); }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < rc {
    out.push(dst[i]);
    i = i + 1;
  }
  return Ok(out);
}

/// One-shot block decompression into an owned buffer of `dst_capacity` bytes.
/// Complexity: O(dst_capacity).
pub fn lz4_decompress(src: &mut Vec[UInt8], dst_capacity: Int) -> Result[Vec[UInt8], Lz4Error]
  requires: dst_capacity > 0
{
  var dst = ffi.zero_bytes(dst_capacity);
  let rc = ffi.decompress_safe(src, &mut dst, src.len(), dst_capacity);
  if rc < 0 { return Err(lz4_block_error(rc)); }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < rc {
    out.push(dst[i]);
    i = i + 1;
  }
  return Ok(out);
}

/// One-shot HC block compression at `level` (2..12, 9 = default).
/// Complexity: O(len).
pub fn lz4hc_compress(src: &mut Vec[UInt8], level: Int) -> Result[Vec[UInt8], Lz4Error]
  requires: level >= LZ4HC_CLEVEL_MIN
  requires: level <= LZ4HC_CLEVEL_MAX
{
  let bound = ffi.compress_bound(src.len());
  var dst = ffi.zero_bytes(bound);
  let rc = ffi.compress_hc(src, &mut dst, src.len(), bound, level);
  if rc <= 0 { return Err(lz4_block_error(rc)); }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < rc {
    out.push(dst[i]);
    i = i + 1;
  }
  return Ok(out);
}

/// LZ4_compress_destSize: fill `target_dst_size` bytes with as much of src as
/// fits (the consumed byte count is exposed by the raw ffi call's srcSizePtr
/// slot); the returned buffer is the compressed block.
/// Complexity: O(len).
pub fn lz4_compress_dest_size(src: &mut Vec[UInt8],
    target_dst_size: Int) -> Result[Vec[UInt8], Lz4Error]
  requires: target_dst_size >= 1
{
  var dst = ffi.zero_bytes(target_dst_size);
  var slot = ffi.zero_bytes(8);
  ffi.write_u32_le(&mut slot, 0, src.len());
  let rc = ffi.compress_dest_size(src, &mut dst, &mut slot, target_dst_size);
  if rc <= 0 { return Err(lz4_block_error(rc)); }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < rc {
    out.push(dst[i]);
    i = i + 1;
  }
  return Ok(out);
}

// --- frame preferences / options slots --------------------------------------

/// 56-byte preferences slot initialized to defaults.
/// Complexity: O(1).
pub fn lz4f_prefs_new() -> Vec[UInt8] {
  var slot = ffi.zero_bytes(LZ4F_PREFERENCES_BYTES);
  var rc = ffi.prefs_default(&mut slot);
  return slot;
}

/// 32-byte frameInfo slot initialized to defaults.
/// Complexity: O(1).
pub fn lz4f_frame_info_slot_new() -> Vec[UInt8] {
  var slot = ffi.zero_bytes(LZ4F_FRAME_INFO_BYTES);
  var rc = ffi.frame_info_default(&mut slot);
  return slot;
}

/// 16-byte compressOptions slot initialized to defaults.
/// Complexity: O(1).
pub fn lz4f_compress_options_new() -> Vec[UInt8] {
  var slot = ffi.zero_bytes(LZ4F_COMPRESS_OPTIONS_BYTES);
  var rc = ffi.compress_options_default(&mut slot);
  return slot;
}

/// 16-byte decompressOptions slot initialized to defaults.
/// Complexity: O(1).
pub fn lz4f_decompress_options_new() -> Vec[UInt8] {
  var slot = ffi.zero_bytes(LZ4F_DECOMPRESS_OPTIONS_BYTES);
  var rc = ffi.decompress_options_default(&mut slot);
  return slot;
}

/// 32-byte CustomMem slot (all zeros = default allocators).
/// Complexity: O(1).
pub fn lz4f_custom_mem_new() -> Vec[UInt8] {
  var slot = ffi.zero_bytes(LZ4F_CUSTOM_MEM_BYTES);
  var rc = ffi.custom_mem_default(&mut slot);
  return slot;
}

/// Set the 10 preferences fields on a prefs slot.
/// Complexity: O(1).
pub fn lz4f_prefs_set(slot: &mut Vec[UInt8], block_size_id: Int, block_mode: Int,
    content_checksum: Int, content_size: Int, dict_id: Int, block_checksum: Int,
    compression_level: Int, auto_flush: Int, favor_dec_speed: Int) -> Bool
  requires: slot.len() >= LZ4F_PREFERENCES_BYTES
{
  let rc = ffi.prefs_set(slot, block_size_id, block_mode, content_checksum, LZ4F_FRAME,
    content_size, dict_id, block_checksum, compression_level, auto_flush, favor_dec_speed);
  return rc == 0;
}


// --- one-shot frame codec ---------------------------------------------------

/// LZ4F_compressFrame with an explicit 56-byte preferences slot.
/// Complexity: O(len).
pub fn lz4f_compress_frame(src: &mut Vec[UInt8], prefs: &mut Vec[UInt8]) -> Result[Vec[UInt8], Lz4Error]
  requires: prefs.len() >= LZ4F_PREFERENCES_BYTES
{
  let bound = ffi.compress_frame_bound(src.len(), prefs);
  var dst = ffi.zero_bytes(bound);
  let rc = ffi.compress_frame(&mut dst, bound, src, src.len(), prefs);
  if lz4f_is_error(rc) { return Err(lz4f_error(rc)); }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < rc {
    out.push(dst[i]);
    i = i + 1;
  }
  return Ok(out);
}

/// LZ4F_compressFrame with default preferences (a zeroed default slot;
/// upstream treats contentSize == 0 as unknown, identical to NULL prefs).
/// Complexity: O(len).
pub fn lz4f_compress_frame_default(src: &mut Vec[UInt8]) -> Result[Vec[UInt8], Lz4Error] {
  var prefs = lz4f_prefs_new();
  return lz4f_compress_frame(src, &mut prefs);
}

/// Decompress the first frame in `src` into an owned buffer of
/// `dst_capacity` bytes (fresh dctx + the bridge loop over LZ4F_decompress).
/// Complexity: O(len).
pub fn lz4f_decompress(src: &mut Vec[UInt8], dst_capacity: Int) -> Result[Vec[UInt8], Lz4Error]
  requires: dst_capacity > 0
{
  var ctx_slot = ffi.zero_bytes(8);
  let rc0 = ffi.create_decompression_context(&mut ctx_slot, LZ4F_VERSION);
  if lz4f_is_error(rc0) { return Err(lz4f_error(rc0)); }
  let dctx = ffi.read_u64_le(&ctx_slot, 0);
  if dctx == 0 { return Err(Lz4Error.new(LZ4F_ERROR_ALLOCATION_FAILED, "lz4f: context allocation failed")); }
  var dst = ffi.zero_bytes(dst_capacity);
  let rc = ffi.lz4f_decompress_all(dctx, src, &mut dst);
  var ig = ffi.free_decompression_context(dctx);
  if lz4f_is_error(rc) { return Err(lz4f_error(rc)); }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < rc {
    out.push(dst[i]);
    i = i + 1;
  }
  return Ok(out);
}

/// Parse the frame header of `src` into an owned Lz4fFrameInfo.
/// Complexity: O(1).
pub fn lz4f_frame_info(src: &mut Vec[UInt8]) -> Result[Lz4fFrameInfo, Lz4Error] {
  var ctx_slot = ffi.zero_bytes(8);
  let rc0 = ffi.create_decompression_context(&mut ctx_slot, LZ4F_VERSION);
  if lz4f_is_error(rc0) { return Err(lz4f_error(rc0)); }
  let dctx = ffi.read_u64_le(&ctx_slot, 0);
  if dctx == 0 { return Err(Lz4Error.new(LZ4F_ERROR_ALLOCATION_FAILED, "lz4f: context allocation failed")); }
  var info_slot = ffi.zero_bytes(LZ4F_FRAME_INFO_BYTES);
  var size_slot = ffi.zero_bytes(8);
  ffi.write_u64_le(&mut size_slot, 0, src.len());
  let rc = ffi.get_frame_info(dctx, &mut info_slot, src, &mut size_slot);
  var ig = ffi.free_decompression_context(dctx);
  if lz4f_is_error(rc) { return Err(lz4f_error(rc)); }
  var out = ffi.zero_bytes(56);
  var get_rc = ffi.frame_info_get(&mut info_slot, &mut out);
  return Ok(Lz4fFrameInfo{
    block_size_id: ffi.read_u64_le(&out, 0),
    block_mode: ffi.read_u64_le(&out, 8),
    content_checksum_flag: ffi.read_u64_le(&out, 16),
    frame_type: ffi.read_u64_le(&out, 24),
    content_size: ffi.read_u64_le(&out, 32),
    dict_id: ffi.read_u64_le(&out, 40),
    block_checksum_flag: ffi.read_u64_le(&out, 48)
  });
}

/// Content size declared in the frame header (0 = unknown).
/// Complexity: O(1).
pub fn lz4f_content_size(src: &mut Vec[UInt8]) -> Int {
  let info = lz4f_frame_info(src);
  if !info.is_ok { return 0; }
  return info.value.content_size;
}
