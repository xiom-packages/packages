// XIOM -- xiom.brotli: real RFC 7932 brotli decoder/encoder bindings.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: vendored-C path (same pattern as xiom.zstd / xiom.lz4 / xiom.opus).
// The upstream C sources (google/brotli v1.2.0, MIT; see PROVENANCE.md for
// the pin and the one mechanical angle-include rewrite) are vendored under
// vendor/brotli and compiled into the test binary via `--c-source`
// (port.args.json). No system library, no runtime DLL, no dl-load.
//
// G5 confinement: this is the ONE module in the package with `extern "C"`;
// every foreign call is wrapped here. Handles are opaque Int values produced
// by the C bridge (never `x as *UInt8`, B-25); out-params are read from
// dedicated owned Vec[UInt8] slots, byte-indexed little-endian (one slot per
// out-param, B-11/B-16/B-17); no bare `null` crosses to C (B-23); all inputs
// and outputs are caller-owned buffers (byte-indexed reads; the bridge copies
// every foreign-sourced byte). Flat outcome structs only -- no nested
// `Result[Option[T]]` (B-26).
//
// Declared C surface (100%; see SPEC.md section 4): 7 decoder functions
// (CreateInstance/DecompressStream/Decompress/Destroy/GetErrorCode/
// ErrorString/Version), 9 encoder functions (CreateInstance/Compress/
// CompressStream/SetParameter/TakeOutput/IsFinished/MaxCompressedSize/
// Destroy/Version). Everything else in decode.h/encode.h is an explicit
// non-goal (dictionaries, decoder parameters, metadata callbacks).
//
// Error mapping: decoder failures carry the real upstream error code +
// `BrotliDecoderErrorString` text (e.g. `_ERROR_FORMAT_EXUBERANT_NIBBLE`);
// truncation is detected by the stream loops; encoder failures are typed.

module xiom.brotli

use xiom.string.compare;

// -----------------------------------------------------------------------
//  foreign declarations
// -----------------------------------------------------------------------
//
// Direct entry points: signatures already expressible on this toolchain
// (handles as Int; BROTLI_BOOL ints as Int; size_t as Int; uint32 as UInt32).
extern "C" {
  fn BrotliDecoderDestroyInstance(state: Int);
  fn BrotliDecoderVersion() -> UInt32;
  fn BrotliEncoderDestroyInstance(state: Int);
  fn BrotliEncoderIsFinished(state: Int) -> Int;
  fn BrotliEncoderMaxCompressedSize(input_size: Int) -> Int;
  fn BrotliEncoderSetParameter(state: Int, param: Int, value: Int) -> Int;
  fn BrotliEncoderVersion() -> UInt32;

  // Bridge helpers (src/brotli_bridge.c) for shapes XIOM cannot express:
  // NULL allocators, pointer-to-pointer stream cursors, size_t in/out,
  // foreign-pointer copies (TakeOutput, error strings), signed error codes.
  fn xb_decoder_create() -> Int;
  fn xb_decoder_stream(state: Int, src: *UInt8, src_len: Int, src_offset: Int, out: *UInt8, out_cap: Int, consumed_slot: *UInt8, written_slot: *UInt8) -> Int;
  fn xb_decoder_decompress_oneshot(src: *UInt8, src_len: Int, dst: *UInt8, dst_cap: Int, size_slot: *UInt8) -> Int;
  fn xb_decoder_error_code(state: Int) -> Int;
  fn xb_decoder_error_string(code: Int, out: *UInt8, cap: Int) -> Int;
  fn xb_encoder_create(quality: Int, lgwin: Int, mode: Int) -> Int;
  fn xb_encoder_stream(state: Int, op: Int, src: *UInt8, src_len: Int, src_offset: Int, out: *UInt8, out_cap: Int, consumed_slot: *UInt8, written_slot: *UInt8) -> Int;
  fn xb_encoder_take_output(state: Int, dst: *UInt8, dst_cap: Int) -> Int;
  fn xb_encoder_compress_oneshot(quality: Int, lgwin: Int, mode: Int, src: *UInt8, src_len: Int, dst: *UInt8, dst_cap: Int, size_slot: *UInt8) -> Int;
}

// -----------------------------------------------------------------------
//  constants (pinned headers: brotli/decode.h, brotli/encode.h)
// -----------------------------------------------------------------------

/// BrotliDecoderResult: decoding error (corrupt input or OOM).
pub const BROTLI_DECODER_RESULT_ERROR: Int = 0;

/// BrotliDecoderResult: decoding successfully completed.
pub const BROTLI_DECODER_RESULT_SUCCESS: Int = 1;

/// BrotliDecoderResult: partially done; more input required.
pub const BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT: Int = 2;

/// BrotliDecoderResult: partially done; more output space required.
pub const BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT: Int = 3;

// BrotliDecoderErrorCode -- the full upstream enum (30 codes; -17 and the
// reserved -23..-24, -28..-29 gaps exist upstream and are intentionally not
// invented here). Values are the pinned header's values.

/// No error so far. Complexity: O(1).
pub const BROTLI_DECODER_NO_ERROR: Int = 0;
/// Same as BROTLI_DECODER_RESULT_SUCCESS. Complexity: O(1).
pub const BROTLI_DECODER_SUCCESS: Int = 1;
/// Same as BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT. Complexity: O(1).
pub const BROTLI_DECODER_NEEDS_MORE_INPUT: Int = 2;
/// Same as BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT. Complexity: O(1).
pub const BROTLI_DECODER_NEEDS_MORE_OUTPUT: Int = 3;
/// Corrupt stream: exuberant nibble. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_FORMAT_EXUBERANT_NIBBLE: Int = -1;
/// Corrupt stream: reserved value. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_FORMAT_RESERVED: Int = -2;
/// Corrupt stream: exuberant meta nibble. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_FORMAT_EXUBERANT_META_NIBBLE: Int = -3;
/// Corrupt stream: simple Huffman alphabet. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_FORMAT_SIMPLE_HUFFMAN_ALPHABET: Int = -4;
/// Corrupt stream: simple Huffman same. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_FORMAT_SIMPLE_HUFFMAN_SAME: Int = -5;
/// Corrupt stream: CL space. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_FORMAT_CL_SPACE: Int = -6;
/// Corrupt stream: Huffman space. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_FORMAT_HUFFMAN_SPACE: Int = -7;
/// Corrupt stream: context map repeat. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_FORMAT_CONTEXT_MAP_REPEAT: Int = -8;
/// Corrupt stream: block length 1. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_FORMAT_BLOCK_LENGTH_1: Int = -9;
/// Corrupt stream: block length 2. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_FORMAT_BLOCK_LENGTH_2: Int = -10;
/// Corrupt stream: transform. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_FORMAT_TRANSFORM: Int = -11;
/// Corrupt stream: dictionary. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_FORMAT_DICTIONARY: Int = -12;
/// Corrupt stream: window bits. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_FORMAT_WINDOW_BITS: Int = -13;
/// Corrupt stream: padding 1. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_FORMAT_PADDING_1: Int = -14;
/// Corrupt stream: padding 2. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_FORMAT_PADDING_2: Int = -15;
/// Corrupt stream: distance. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_FORMAT_DISTANCE: Int = -16;
/// Compound dictionary error. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_COMPOUND_DICTIONARY: Int = -18;
/// Dictionary not set error. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_DICTIONARY_NOT_SET: Int = -19;
/// Invalid arguments. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_INVALID_ARGUMENTS: Int = -20;
/// Allocation failure: context modes. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_ALLOC_CONTEXT_MODES: Int = -21;
/// Allocation failure: tree groups. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_ALLOC_TREE_GROUPS: Int = -22;
/// Allocation failure: context map. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_ALLOC_CONTEXT_MAP: Int = -25;
/// Allocation failure: ring buffer 1. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_ALLOC_RING_BUFFER_1: Int = -26;
/// Allocation failure: ring buffer 2. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_ALLOC_RING_BUFFER_2: Int = -27;
/// Allocation failure: block type trees. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_ALLOC_BLOCK_TYPE_TREES: Int = -30;
/// "Impossible" state reached. Complexity: O(1).
pub const BROTLI_DECODER_ERROR_UNREACHABLE: Int = -31;

// BrotliEncoderMode.
/// Default mode: nothing known about the input in advance.
pub const BROTLI_MODE_GENERIC: Int = 0;
/// UTF-8 text mode.
pub const BROTLI_MODE_TEXT: Int = 1;
/// WOFF 2.0 font mode.
pub const BROTLI_MODE_FONT: Int = 2;

// BrotliEncoderParameter -- the full upstream enum (10 values).
/// Tune encoder for a specific input type (value: BROTLI_MODE_*).
pub const BROTLI_PARAM_MODE: Int = 0;
/// Quality (0..11); the main speed/density lever.
pub const BROTLI_PARAM_QUALITY: Int = 1;
/// Recommended sliding window (10..24).
pub const BROTLI_PARAM_LGWIN: Int = 2;
/// Recommended input block size (16..24).
pub const BROTLI_PARAM_LGBLOCK: Int = 3;
/// Disable literal context modeling (0/1).
pub const BROTLI_PARAM_DISABLE_LITERAL_CONTEXT_MODELING: Int = 4;
/// Estimated total input size (0 = unknown).
pub const BROTLI_PARAM_SIZE_HINT: Int = 5;
/// Large-window brotli flag (0/1).
pub const BROTLI_PARAM_LARGE_WINDOW: Int = 6;
/// Recommended NPOSTFIX (0..3).
pub const BROTLI_PARAM_NPOSTFIX: Int = 7;
/// Recommended NDIRECT (0..(15 << NPOSTFIX)).
pub const BROTLI_PARAM_NDIRECT: Int = 8;
/// Predecessor stream byte count (0..2^30).
pub const BROTLI_PARAM_STREAM_OFFSET: Int = 9;

// BrotliEncoderOperation.
/// Process input (output may be postponed).
pub const BROTLI_OPERATION_PROCESS: Int = 0;
/// Flush: emit enough output to decode everything given so far.
pub const BROTLI_OPERATION_FLUSH: Int = 1;
/// Finish the stream.
pub const BROTLI_OPERATION_FINISH: Int = 2;
/// Emit a metadata block (upstream limit: 16 MiB).
pub const BROTLI_OPERATION_EMIT_METADATA: Int = 3;

// Ranges and defaults (encode.h).
/// Minimum BROTLI_PARAM_LGWIN.
pub const BROTLI_MIN_WINDOW_BITS: Int = 10;
/// Maximum RFC 7932 BROTLI_PARAM_LGWIN.
pub const BROTLI_MAX_WINDOW_BITS: Int = 24;
/// Maximum BROTLI_PARAM_LGWIN with BROTLI_PARAM_LARGE_WINDOW.
pub const BROTLI_LARGE_MAX_WINDOW_BITS: Int = 30;
/// Minimum BROTLI_PARAM_LGBLOCK.
pub const BROTLI_MIN_INPUT_BLOCK_BITS: Int = 16;
/// Maximum BROTLI_PARAM_LGBLOCK.
pub const BROTLI_MAX_INPUT_BLOCK_BITS: Int = 24;
/// Minimum BROTLI_PARAM_QUALITY.
pub const BROTLI_MIN_QUALITY: Int = 0;
/// Maximum BROTLI_PARAM_QUALITY.
pub const BROTLI_MAX_QUALITY: Int = 11;
/// Default quality.
pub const BROTLI_DEFAULT_QUALITY: Int = 11;
/// Default window (lgwin).
pub const BROTLI_DEFAULT_WINDOW: Int = 22;
/// Default mode.
pub const BROTLI_DEFAULT_MODE: Int = 0;

// -----------------------------------------------------------------------
//  types
// -----------------------------------------------------------------------

/// One `BrotliDecoderDecompressStream` step, as reported by
/// `brotli_decoder_push`. `result` is a BROTLI_DECODER_RESULT_* value;
/// `consumed` = input bytes consumed this step; `written` = output bytes
/// appended to the caller's buffer this step.
pub type BrotliDecodeProgress = {
  result: Int;
  consumed: Int;
  written: Int;
}

/// One `BrotliEncoderCompressStream` step, as reported by
/// `brotli_encoder_push`. `consumed`/`written` as in BrotliDecodeProgress;
/// `finished` = 1 when `BrotliEncoderIsFinished` holds after the step
/// (stream complete AND all output emitted).
pub type BrotliEncodeProgress = {
  consumed: Int;
  written: Int;
  finished: Int;
}

// -----------------------------------------------------------------------
//  internal helpers (module-local; no cross-module const/convert pitfalls)
// -----------------------------------------------------------------------

// A caller-owned zero buffer of `n` bytes (push-growth; never Vec.with_len,
// B-28).
fn _br_zeros(n: Int) -> Vec[UInt8] {
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

// Little-endian unsigned value from `buf[pos..pos+8]` (callers guarantee the
// bounds; the bridge writes exactly 8 bytes).
fn _br_u64_le(buf: &Vec[UInt8], pos: Int) -> Int {
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

// Append the first `n` bytes of `src` to `dst` (byte-indexed; no pointer
// work).
fn _br_append(dst: &mut Vec[UInt8], src: &Vec[UInt8], n: Int) {
  var i = 0;
  while i < n && i < src.len() {
    dst.push(src[i]);
    i = i + 1;
  }
}

// Build a Str from the first `n` bytes of a copied slot.
fn _br_str_from_slot(buf: &Vec[UInt8], n: Int) -> Str {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n && i < buf.len() {
    out.push(buf[i]);
    i = i + 1;
  }
  return Str::from_utf8(out);
}

// Local integer-to-string (keeps the module free of xiom.convert; see the
// lane's B-02/B-03 findings).
fn _br_int_str(n: Int) -> Str {
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

// -----------------------------------------------------------------------
//  version helpers
// -----------------------------------------------------------------------

/// Runtime decoder library version as the upstream hex number
/// (BROTLI_MAKE_HEX_VERSION: major<<24 | minor<<12 | patch; 1.2.0 =
/// 16785408). Complexity: O(1).
pub fn brotli_decoder_version() -> Int
  requires: true
  ensures: result >= 0;
{
  unsafe { return BrotliDecoderVersion() as Int; }
}

/// Runtime encoder library version (same encoding as
/// `brotli_decoder_version`). Complexity: O(1).
pub fn brotli_encoder_version() -> Int
  requires: true
  ensures: result >= 0;
{
  unsafe { return BrotliEncoderVersion() as Int; }
}

/// Human version string derived from the decoder version number
/// (e.g. "1.2.0"). Complexity: O(1).
pub fn brotli_version() -> Str
  ensures: true
{
  let v = brotli_decoder_version();
  return _br_int_str(v / 16777216) + "." + _br_int_str((v / 4096) % 4096) + "." + _br_int_str(v % 4096);
}

// -----------------------------------------------------------------------
//  decoder
// -----------------------------------------------------------------------

/// Create a decoder session with the default memory manager (upstream
/// `BrotliDecoderCreateInstance(NULL, NULL, NULL)`); returns 0 when the
/// instance cannot be allocated. Destroy with `brotli_decoder_destroy`.
/// Complexity: O(1).
pub fn brotli_decoder_new() -> Int
  requires: true
{
  unsafe { return xb_decoder_create(); }
}

/// Destroy a decoder session (no-op for 0). Complexity: O(1).
pub fn brotli_decoder_destroy(d: Int) {
  if d == 0 { return; }
  unsafe { BrotliDecoderDestroyInstance(d); }
}

/// Last saved upstream error code of the session (BROTLI_DECODER_NO_ERROR
/// when none); meaningful after `brotli_decoder_push` reports
/// BROTLI_DECODER_RESULT_ERROR. Complexity: O(1).
pub fn brotli_decoder_error_code(d: Int) -> Int
  requires: true
{
  unsafe { return xb_decoder_error_code(d); }
}

/// Upstream `BrotliDecoderErrorString` text for a code, copied into an owned
/// buffer (e.g. "_ERROR_FORMAT_EXUBERANT_NIBBLE"; "INVALID" for unknown
/// codes). Complexity: O(len).
pub fn brotli_decoder_error_string(code: Int) -> Str
  ensures: true
{
  var slot = _br_zeros(64);
  var n: Int = 0;
  unsafe { n = xb_decoder_error_string(code, slot.as_mut_ptr(), 64); }
  return _br_str_from_slot(&slot, n);
}

/// One streaming decode step: feed `src` from `src_offset` (the caller keeps
/// feeding the SAME buffer with the offset returned in `consumed`), collect
/// up to `chunk` bytes of decoded output appended to `out`.
/// Error catalog: Err("brotli.decoder: invalid session") for d == 0;
/// Err("brotli.decoder: empty input") for a zero-length source;
/// Err("brotli.decoder: source offset out of range") for an offset outside
/// [0, src.len()]; Err("brotli.decoder: invalid state") when the bridge
/// rejects the call. On ERROR results, `brotli_decoder_error_code` /
/// `brotli_decoder_error_string` carry the upstream detail.
/// Complexity: O(consumed + written).
pub fn brotli_decoder_push(d: Int, src: &mut Vec[UInt8], src_offset: Int, out: &mut Vec[UInt8], chunk: Int) -> Result[BrotliDecodeProgress, Str]
  requires: chunk >= 1
{
  if d == 0 { return Err("brotli.decoder: invalid session"); }
  if src.len() == 0 { return Err("brotli.decoder: empty input"); }
  if src_offset < 0 { return Err("brotli.decoder: source offset out of range"); }
  if src_offset > src.len() { return Err("brotli.decoder: source offset out of range"); }
  var scratch = _br_zeros(chunk);
  var consumed_slot = _br_zeros(8);
  var written_slot = _br_zeros(8);
  var rc: Int = 0;
  unsafe {
    rc = xb_decoder_stream(d, src.as_mut_ptr(), src.len(), src_offset, scratch.as_mut_ptr(), chunk, consumed_slot.as_mut_ptr(), written_slot.as_mut_ptr());
  }
  if rc < 0 { return Err("brotli.decoder: invalid state"); }
  let consumed = _br_u64_le(&consumed_slot, 0);
  let written = _br_u64_le(&written_slot, 0);
  _br_append(&mut out, &scratch, written);
  return Ok(BrotliDecodeProgress{ result: rc; consumed: consumed; written: written });
}

/// One-shot decompression (the literal upstream `BrotliDecoderDecompress`):
/// decode `src` into a buffer of `out_capacity` bytes. Returns the decoded
/// bytes as an owned buffer. The one-shot API cannot report details, so a
/// failure is the single typed error below; use `brotli_decompress_auto`
/// for upstream error codes/strings.
/// Error catalog: Err("brotli.decoder: empty input") for a zero-length
/// source; Err("brotli.decoder: output capacity must be positive") for
/// out_capacity < 1; Err("brotli.decoder: one-shot decompress failed
/// (corrupt input or insufficient output capacity)") on
/// BROTLI_DECODER_RESULT_ERROR.
/// Complexity: O(src.len()) plus decompression work.
pub fn brotli_decompress_oneshot(src: &mut Vec[UInt8], out_capacity: Int) -> Result[Vec[UInt8], Str]
  requires: out_capacity >= 0
{
  if src.len() == 0 { return Err("brotli.decoder: empty input"); }
  if out_capacity < 1 { return Err("brotli.decoder: output capacity must be positive"); }
  var dst = _br_zeros(out_capacity);
  var size_slot = _br_zeros(8);
  var rc: Int = 0;
  unsafe {
    rc = xb_decoder_decompress_oneshot(src.as_mut_ptr(), src.len(), dst.as_mut_ptr(), out_capacity, size_slot.as_mut_ptr());
  }
  if rc != BROTLI_DECODER_RESULT_SUCCESS {
    return Err("brotli.decoder: one-shot decompress failed (corrupt input or insufficient output capacity)");
  }
  let n = _br_u64_le(&size_slot, 0);
  var out: Vec[UInt8] = Vec[UInt8].new();
  _br_append(&mut out, &dst, n);
  return Ok(out);
}

// Shared streaming decode loop (used by brotli_decompress /
// brotli_decompress_auto). `bounded` caps the collected output at `cap`.
fn _br_decode_stream(src: &mut Vec[UInt8], cap: Int, bounded: Bool) -> Result[Vec[UInt8], Str] {
  if src.len() == 0 { return Err("brotli.decoder: empty input"); }
  let d = brotli_decoder_new();
  if d == 0 { return Err("brotli.decoder: create failed"); }
  var out: Vec[UInt8] = Vec[UInt8].new();
  var offset: Int = 0;
  var failed: Int = 0;
  var failure: Str = "";
  var done: Int = 0;
  var iterations: Int = 0;
  while done == 0 {
    iterations = iterations + 1;
    if iterations > 1000000 {
      failed = 1;
      failure = "brotli.decoder: stream loop did not converge";
      done = 1;
    } else {
      let p = brotli_decoder_push(d, src, offset, &mut out, 65536);
      if !p.is_ok {
        failed = 1;
        failure = p.error;
        done = 1;
      } else {
        var prog: BrotliDecodeProgress = p.value;
        offset = offset + prog.consumed;
        if prog.result == BROTLI_DECODER_RESULT_SUCCESS {
          done = 1;
        } elif prog.result == BROTLI_DECODER_RESULT_ERROR {
          failed = 1;
          failure = "brotli.decoder: corrupt stream (" + brotli_decoder_error_string(brotli_decoder_error_code(d)) + ")";
          done = 1;
        } elif prog.result == BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT {
          if offset >= src.len() || prog.consumed == 0 {
            failed = 1;
            failure = "brotli.decoder: truncated stream";
            done = 1;
          }
        } else {
          if bounded && out.len() > cap {
            failed = 1;
            failure = "brotli.decoder: output exceeds capacity";
            done = 1;
          }
        }
      }
    }
  }
  brotli_decoder_destroy(d);
  if failed == 1 { return Err(failure); }
  if bounded && out.len() > cap {
    return Err("brotli.decoder: output exceeds capacity");
  }
  return Ok(out);
}

/// Streaming decompression with a caller-declared output bound: decode the
/// whole RFC 7932 stream in `src`, collecting the decoded bytes, and fail
/// with a typed error when the decoded size would exceed `out_capacity`.
/// Inputs are the caller's owned buffer; the same buffer is re-fed with the
/// session's consumed offset (never copied into the session).
/// Error catalog: Err("brotli.decoder: empty input"); Err("brotli.decoder:
/// corrupt stream (<upstream error string>)"); Err("brotli.decoder:
/// truncated stream"); Err("brotli.decoder: output exceeds capacity");
/// Err("brotli.decoder: create failed").
/// Complexity: O(src.len() + decoded size).
pub fn brotli_decompress(src: &mut Vec[UInt8], out_capacity: Int) -> Result[Vec[UInt8], Str]
  requires: out_capacity >= 0
{
  return _br_decode_stream(src, out_capacity, true);
}

/// Streaming decompression with no output bound: decode the whole RFC 7932
/// stream in `src` into a new owned buffer of exactly the decoded size.
/// Same error catalog as `brotli_decompress` except the capacity error.
/// Complexity: O(src.len() + decoded size).
pub fn brotli_decompress_auto(src: &mut Vec[UInt8]) -> Result[Vec[UInt8], Str]
  ensures: true
{
  return _br_decode_stream(src, 0, false);
}

// -----------------------------------------------------------------------
//  encoder
// -----------------------------------------------------------------------

/// Worst-case compressed size for `input_size` bytes via the upstream
/// `BrotliEncoderMaxCompressedSize` (0 when the result would not fit a
/// size_t; 2 for empty input). Complexity: O(1).
pub fn brotli_compress_bound(input_size: Int) -> Int
  ensures: input_size < 0 => result == 0;
{
  if input_size < 0 { return 0; }
  unsafe { return BrotliEncoderMaxCompressedSize(input_size); }
}

// Validate the three core encoder parameters (upstream v1.2.0 stores
// out-of-range values without complaint, so the wrapper enforces the
// pinned header's documented ranges). Returns 0 when valid, else the
// index of the first invalid parameter (1 quality, 2 lgwin, 3 mode).
fn _br_params_code(quality: Int, lgwin: Int, mode: Int) -> Int {
  if quality < BROTLI_MIN_QUALITY || quality > BROTLI_MAX_QUALITY {
    return 1;
  }
  if lgwin < BROTLI_MIN_WINDOW_BITS || lgwin > BROTLI_MAX_WINDOW_BITS {
    return 2;
  }
  if mode < BROTLI_MODE_GENERIC || mode > BROTLI_MODE_FONT {
    return 3;
  }
  return 0;
}

fn _br_params_error_str(c: Int) -> Str {
  if c == 1 { return "brotli.encoder: invalid quality"; }
  if c == 2 { return "brotli.encoder: invalid lgwin"; }
  return "brotli.encoder: invalid mode";
}

/// One-shot compression (the literal upstream `BrotliEncoderCompress`):
/// compress `src` at `quality` (0..11), `lgwin` (10..24) and `mode`
/// (BROTLI_MODE_*). Returns the compressed stream as an owned buffer sized
/// from `brotli_compress_bound`. An empty input produces the 1-byte empty
/// stream.
/// Error catalog: Err("brotli.encoder: invalid quality"/"invalid lgwin"/
/// "invalid mode"); Err("brotli.encoder: one-shot compress failed").
/// Complexity: O(src.len()) plus compression work.
pub fn brotli_compress(src: &mut Vec[UInt8], quality: Int, lgwin: Int, mode: Int) -> Result[Vec[UInt8], Str]
  ensures: true
{
  let pc = _br_params_code(quality, lgwin, mode);
  if pc != 0 {
    return Err(_br_params_error_str(pc));
  }
  let bound = brotli_compress_bound(src.len());
  var cap = bound;
  if cap < 1 { cap = 1; }
  var dst = _br_zeros(cap);
  var size_slot = _br_zeros(8);
  var rc: Int = 0;
  if src.len() == 0 {
    var guard: Vec[UInt8] = Vec[UInt8].new();
    guard.push(0 as UInt8);
    unsafe {
      rc = xb_encoder_compress_oneshot(quality, lgwin, mode, guard.as_mut_ptr(), 0, dst.as_mut_ptr(), cap, size_slot.as_mut_ptr());
    }
  } else {
    unsafe {
      rc = xb_encoder_compress_oneshot(quality, lgwin, mode, src.as_mut_ptr(), src.len(), dst.as_mut_ptr(), cap, size_slot.as_mut_ptr());
    }
  }
  if rc != 1 {
    return Err("brotli.encoder: one-shot compress failed");
  }
  let n = _br_u64_le(&size_slot, 0);
  var out: Vec[UInt8] = Vec[UInt8].new();
  _br_append(&mut out, &dst, n);
  return Ok(out);
}

/// Create a streaming encoder session with quality/lgwin/mode applied via
/// `BrotliEncoderSetParameter` (same values as the one-shot API). Returns an
/// opaque handle; destroy with `brotli_encoder_destroy`.
/// Error catalog: Err("brotli.encoder: invalid quality"/"invalid lgwin"/
/// "invalid mode"); Err("brotli.encoder: create failed").
/// Complexity: O(1).
pub fn brotli_encoder_new(quality: Int, lgwin: Int, mode: Int) -> Result[Int, Str]
  ensures: true
{
  let pc = _br_params_code(quality, lgwin, mode);
  if pc != 0 {
    return Err(_br_params_error_str(pc));
  }
  var h: Int = 0;
  unsafe { h = xb_encoder_create(quality, lgwin, mode); }
  if h == 0 { return Err("brotli.encoder: create failed"); }
  return Ok(h);
}

/// Destroy an encoder session (no-op for 0). Complexity: O(1).
pub fn brotli_encoder_destroy(e: Int) {
  if e == 0 { return; }
  unsafe { BrotliEncoderDestroyInstance(e); }
}

/// Apply one `BrotliEncoderSetParameter` (BROTLI_PARAM_* + value); false for
/// an invalid session, an unrecognized parameter, or a rejected value.
/// Upstream note: parameters can only change before encoding starts.
/// Complexity: O(1).
pub fn brotli_encoder_set_parameter(e: Int, param: Int, value: Int) -> Bool
  ensures: e == 0 => result == false;
{
  if e == 0 { return false; }
  unsafe { return (BrotliEncoderSetParameter(e, param, value) as Int) != 0; }
}

/// True when the session reached the final state AND all output has been
/// emitted (upstream `BrotliEncoderIsFinished`). Complexity: O(1).
pub fn brotli_encoder_is_finished(e: Int) -> Bool
  ensures: e == 0 => result == false;
{
  if e == 0 { return false; }
  unsafe { return (BrotliEncoderIsFinished(e) as Int) != 0; }
}

/// One streaming encode step: feed `src` from `src_offset` with operation
/// `op` (BROTLI_OPERATION_*), collecting up to `chunk` bytes of compressed
/// output appended to `out`. `src_offset == src.len()` is the legal
/// zero-input call used to drive FLUSH/FINISH to completion.
/// Error catalog: Err("brotli.encoder: invalid session") for e == 0;
/// Err("brotli.encoder: empty input") for a zero-length source;
/// Err("brotli.encoder: source offset out of range"); Err("brotli.encoder:
/// invalid operation"); Err("brotli.encoder: compress stream failed") when
/// upstream returns BROTLI_FALSE; Err("brotli.encoder: invalid state") when
/// the bridge rejects the call.
/// Complexity: O(consumed + written).
pub fn brotli_encoder_push(e: Int, src: &mut Vec[UInt8], src_offset: Int, op: Int, out: &mut Vec[UInt8], chunk: Int) -> Result[BrotliEncodeProgress, Str]
  requires: chunk >= 1
{
  if e == 0 { return Err("brotli.encoder: invalid session"); }
  if src.len() == 0 { return Err("brotli.encoder: empty input"); }
  if src_offset < 0 { return Err("brotli.encoder: source offset out of range"); }
  if src_offset > src.len() { return Err("brotli.encoder: source offset out of range"); }
  if op < BROTLI_OPERATION_PROCESS { return Err("brotli.encoder: invalid operation"); }
  if op > BROTLI_OPERATION_EMIT_METADATA { return Err("brotli.encoder: invalid operation"); }
  var scratch = _br_zeros(chunk);
  var consumed_slot = _br_zeros(8);
  var written_slot = _br_zeros(8);
  var rc: Int = 0;
  unsafe {
    rc = xb_encoder_stream(e, op, src.as_mut_ptr(), src.len(), src_offset, scratch.as_mut_ptr(), chunk, consumed_slot.as_mut_ptr(), written_slot.as_mut_ptr());
  }
  if rc < 0 { return Err("brotli.encoder: invalid state"); }
  if rc == 0 { return Err("brotli.encoder: compress stream failed"); }
  let consumed = _br_u64_le(&consumed_slot, 0);
  let written = _br_u64_le(&written_slot, 0);
  _br_append(&mut out, &scratch, written);
  var fin: Int = 0;
  if brotli_encoder_is_finished(e) { fin = 1; }
  return Ok(BrotliEncodeProgress{ consumed: consumed; written: written; finished: fin });
}

/// Drain buffered encoder output: copy up to `max_take` bytes of
/// `BrotliEncoderTakeOutput` data into `out` and return the copied byte
/// count (0 when nothing is buffered).
/// Error catalog: Err("brotli.encoder: invalid session") for e == 0;
/// Err("brotli.encoder: max_take must be positive") for max_take < 1;
/// Err("brotli.encoder: invalid state") when the bridge rejects the call.
/// Complexity: O(taken).
pub fn brotli_encoder_take_output(e: Int, out: &mut Vec[UInt8], max_take: Int) -> Result[Int, Str]
  requires: max_take >= 1
{
  if e == 0 { return Err("brotli.encoder: invalid session"); }
  if max_take < 1 { return Err("brotli.encoder: max_take must be positive"); }
  var scratch = _br_zeros(max_take);
  var n: Int = 0;
  unsafe { n = xb_encoder_take_output(e, scratch.as_mut_ptr(), max_take); }
  if n < 0 { return Err("brotli.encoder: invalid state"); }
  _br_append(&mut out, &scratch, n);
  return Ok(n);
}

// -----------------------------------------------------------------------
//  HTTP content-coding helpers (RFC 9110 / RFC 7932 "br")
// -----------------------------------------------------------------------

/// The RFC 9110 content-coding token for brotli: "br" (the value of
/// `Content-Encoding` / `Accept-Encoding` for RFC 7932 streams).
/// Complexity: O(1).
pub fn brotli_content_encoding() -> Str
  ensures: true
{
  return "br";
}

/// True when `name` is the brotli content-coding token ("br"), compared
/// case-insensitively per RFC 9110 content-coding semantics (exact match
/// only -- "brotli" and "gzip-br" are false). Complexity: O(len(name)).
pub fn brotli_is_content_encoding(name: Str) -> Bool
  ensures: true
{
  return compare.str_eq_ignore_case(name, "br");
}
