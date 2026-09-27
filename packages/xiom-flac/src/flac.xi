// XIOM -- xiom.flac: FLAC metadata blocks and frame headers (no audio decode)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: structural FLAC parsing only -- no audio decoding.
//   * the 4-byte "fLaC" stream marker;
//   * metadata block walk: 4-byte header (last-metadata-block flag + 7-bit
//     type + 24-bit big-endian length) with payload parsing for STREAMINFO
//     (0), PADDING (1), APPLICATION (2), SEEKTABLE (3), VORBIS_COMMENT (4),
//     CUESHEET (5, opaque but length-checked) and PICTURE (6); types 7..126
//     are invalid and 127 is forbidden;
//   * STREAMINFO fields: 16-bit min/max block size, 24-bit min/max frame
//     size, 20-bit sample rate, 3-bit channels-1, 5-bit bits-per-sample-1,
//     36-bit total samples and the 16-byte MD5 (lowercase hex);
//   * frame header: 14-bit sync 0x3FFE, reserved bit, blocking strategy,
//     block-size code with optional 8/16-bit extra, sample-rate code with
//     optional 8/16-bit extra, channel assignment (independent 0..7,
//     left/side 8, right/side 9, mid/side 10), sample-size code, UTF-8
//     coded frame/sample number (1..7 bytes with validated continuation
//     bytes) and the CRC-8 byte (polynomial 0x07).
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read is widened with `(data[pos] as Int) & 0xFF`; bit fields
//     are extracted with division and modulo, never with shifts or `&` on
//     signed values.
//   * a Str is built from file bytes only after the NUL hazard is removed:
//     builder.sb_to_str hands out a NUL-terminated C string, so every text
//     helper stops at the first 0x00 while still consuming the stored
//     length.
//   * parallel Vec fields replace Vec[StructType]; every push is mirrored on
//     its sibling vectors (block index, seek entries, pictures, cuesheets).
//   * Str values read from Vec[Str] are only ever compared by callers with
//     string.compare.str_compare (BUG 17: `==` lowers to a pointer compare).
// See SPEC.md for the byte layout tables, the error catalog and the test
// matrix.

module xiom.flac

use xiom.string.builder;
use xiom.convert;
use xiom.encoding.hex;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Parsed STREAMINFO metadata block payload (34 bytes).
///
/// `min_block_size` and `max_block_size` are the raw 16-bit fields;
/// `min_frame_size` and `max_frame_size` the raw 24-bit fields (0 means
/// unknown); `sample_rate` is the 20-bit field (0 means invalid/unset);
/// `channels` is 1..8; `bits_per_sample` is 1..32; `total_samples` is the
/// 36-bit field (0 means unknown). `md5_hex` is the 16-byte MD5 rendered as
/// 32 lowercase hex characters.
pub type FlacStreamInfo = {
  min_block_size: Int;
  max_block_size: Int;
  min_frame_size: Int;
  max_frame_size: Int;
  sample_rate: Int;
  channels: Int;
  bits_per_sample: Int;
  total_samples: Int;
  md5_hex: Str;
}

/// One parsed VORBIS_COMMENT payload (also used by the standalone
/// flac_parse_vorbis_comment).
///
/// `vendor` is the vendor string and `comments` the comment strings, in
/// stored order. Both are truncated at the first 0x00 (the stored lengths
/// are still consumed); raw bytes are otherwise copied verbatim, so UTF-8
/// content passes through unchanged.
pub type FlacVorbisComment = {
  vendor: Str;
  comments: Vec[Str];
}

/// One parsed PICTURE payload (also used by the standalone
/// flac_parse_picture).
///
/// `picture_type` is the raw 32-bit type (0..20 defined by the FLAC spec);
/// `mime` and `description` are truncated at the first 0x00; `width`,
/// `height`, `depth` and `colors` are the 32-bit dimension fields (0 when
/// absent); `data_length` is the declared byte length of the picture data
/// itself (the bytes are not copied and are not inspected).
pub type FlacPicture = {
  picture_type: Int;
  mime: Str;
  description: Str;
  width: Int;
  height: Int;
  depth: Int;
  colors: Int;
  data_length: Int;
}

/// Parsed frame header.
///
/// `blocking_strategy` is 0 (fixed, `number` is the frame number) or 1
/// (variable, `number` is the first sample number). `block_size_code`,
/// `sample_rate_code` and `sample_size_code` are the raw 4/4/3-bit codes;
/// `channel_assignment` is the raw 4-bit field (0..7 independent, 8
/// left/side, 9 right/side, 10 mid/side). `channels` is the derived channel
/// count (1..8 for independent, 2 for the stereo assignments).
///
/// `block_size` is always resolved (> 0). `sample_rate` is 0 when the code
/// says "from STREAMINFO" and `bits_per_sample` is 0 the same way; the
/// caller supplies those two from flac_parse_metadata/flac_parse_streaminfo
/// in that case. `number_bytes` is the UTF-8 coded number length (1..7);
/// `crc8` is the stored CRC-8 byte (polynomial 0x07, initial 0, MSB-first)
/// over everything from the sync code up to (not including) itself and
/// `crc8_ok` says whether it matches the recomputation. `header_size` is
/// the total header length in bytes, CRC included.
pub type FlacFrameHeader = {
  blocking_strategy: Int;
  block_size_code: Int;
  sample_rate_code: Int;
  channel_assignment: Int;
  sample_size_code: Int;
  channels: Int;
  block_size: Int;
  sample_rate: Int;
  bits_per_sample: Int;
  number: Int;
  number_bytes: Int;
  crc8: Int;
  crc8_ok: Bool;
  header_size: Int;
}

/// Parsed metadata section: the block index plus every block payload,
/// flattened into scalar fields and index-aligned parallel vectors.
///
/// `metadata_size` and `audio_offset` are both the offset one past the last
/// metadata block (= 4 + the sum of every 4-byte header and payload), i.e.
/// where audio frames begin. `block_offsets[i]`/`block_types[i]`/
/// `block_lengths[i]` describe metadata block `i` in stream order (offset
/// of the 4-byte header, raw type 0..6, declared payload length).
///
/// STREAMINFO is mandatory and must be the first block, so `has_streaminfo`
/// is always true for a successful parse; its fields are the flattened
/// `min_block_size` .. `md5_hex` (see FlacStreamInfo). `padding_bytes` is
/// the total PADDING payload. APPLICATION blocks contribute one entry each
/// to `app_ids`/`app_data_lengths` (id truncated at the first 0x00, data
/// length = payload length - 4). SEEKTABLE entries are the index-aligned
/// `seek_samples`/`seek_offsets`/`seek_frame_samples` triplets; 64-bit
/// placeholder values (0xFFFFFFFFFFFFFFFF) are clamped to Int max. Every
/// VORBIS_COMMENT block appends its comments to `comments`; `vendor` is the
/// vendor of the last one parsed. Cuesheets contribute
/// `cue_track_counts`/`cue_lengths` (the payload is not exposed further).
/// Pictures contribute the index-aligned `picture_*` summary vectors
/// (type, mime, description, width, height, depth, colors, data length).
pub type FlacMetadata = {
  metadata_size: Int;
  audio_offset: Int;
  has_streaminfo: Bool;
  min_block_size: Int;
  max_block_size: Int;
  min_frame_size: Int;
  max_frame_size: Int;
  sample_rate: Int;
  channels: Int;
  bits_per_sample: Int;
  total_samples: Int;
  md5_hex: Str;
  block_offsets: Vec[Int];
  block_types: Vec[Int];
  block_lengths: Vec[Int];
  padding_bytes: Int;
  app_ids: Vec[Str];
  app_data_lengths: Vec[Int];
  seek_samples: Vec[Int];
  seek_offsets: Vec[Int];
  seek_frame_samples: Vec[Int];
  vendor: Str;
  comments: Vec[Str];
  cue_track_counts: Vec[Int];
  cue_lengths: Vec[Int];
  picture_types: Vec[Int];
  picture_mimes: Vec[Str];
  picture_descriptions: Vec[Str];
  picture_widths: Vec[Int];
  picture_heights: Vec[Int];
  picture_depths: Vec[Int];
  picture_colors: Vec[Int];
  picture_data_lengths: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[FlacMetadata, Str].
fn _ok_metadata(v: FlacMetadata) -> Result[FlacMetadata, Str] {
  return Ok(v);
}

// Err(m) for Result[FlacMetadata, Str].
fn _err_metadata(m: Str) -> Result[FlacMetadata, Str] {
  return Err(m);
}

// Ok(v) for Result[FlacStreamInfo, Str].
fn _ok_streaminfo(v: FlacStreamInfo) -> Result[FlacStreamInfo, Str] {
  return Ok(v);
}

// Err(m) for Result[FlacStreamInfo, Str].
fn _err_streaminfo(m: Str) -> Result[FlacStreamInfo, Str] {
  return Err(m);
}

// Ok(v) for Result[FlacVorbisComment, Str].
fn _ok_vorbis(v: FlacVorbisComment) -> Result[FlacVorbisComment, Str] {
  return Ok(v);
}

// Err(m) for Result[FlacVorbisComment, Str].
fn _err_vorbis(m: Str) -> Result[FlacVorbisComment, Str] {
  return Err(m);
}

// Ok(v) for Result[FlacPicture, Str].
fn _ok_picture(v: FlacPicture) -> Result[FlacPicture, Str] {
  return Ok(v);
}

// Err(m) for Result[FlacPicture, Str].
fn _err_picture(m: Str) -> Result[FlacPicture, Str] {
  return Err(m);
}

// Ok(v) for Result[FlacFrameHeader, Str].
fn _ok_frame(v: FlacFrameHeader) -> Result[FlacFrameHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[FlacFrameHeader, Str].
fn _err_frame(m: Str) -> Result[FlacFrameHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte and string helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned big-endian u16 at `pos`; callers guarantee the bounds.
fn _be_u16(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 256 + _byte(data, pos + 1);
}

// Unsigned big-endian u24 at `pos`; callers guarantee the bounds.
fn _be_u24(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 65536 + _byte(data, pos + 1) * 256 + _byte(data, pos + 2);
}

// Unsigned big-endian u32 at `pos`; callers guarantee the bounds.
fn _be_u32(data: &Vec[UInt8], pos: Int) -> Int {
  var v: Int = 0;
  var i = 0;
  while i < 4 {
    v = v * 256 + _byte(data, pos + i);
    i = i + 1;
  }
  return v;
}

// Unsigned little-endian u32 at `pos`; callers guarantee the bounds.
fn _le_u32(data: &Vec[UInt8], pos: Int) -> Int {
  var v: Int = 0;
  var i = 3;
  while i >= 0 {
    v = v * 256 + _byte(data, pos + i);
    i = i - 1;
  }
  return v;
}

// Big-endian u64 at `pos` clamped to Int max (9223372036854775807): any
// value with bit 63 set -- including the 0xFFFFFFFFFFFFFFFF placeholder used
// in seek tables -- is reported as Int max. Callers guarantee the bounds.
fn _be_u64_clamped(data: &Vec[UInt8], pos: Int) -> Int {
  if _byte(data, pos) >= 128 {
    return 9223372036854775807;
  }
  var v: Int = 0;
  var i = 0;
  while i < 8 {
    v = v * 256 + _byte(data, pos + i);
    i = i + 1;
  }
  return v;
}

// Build a Str from at most `n` bytes at `pos`, stopping before the first
// 0x00. Callers guarantee the range is inside `data`. The stop-at-NUL rule
// is what keeps builder.sb_to_str's `result.len() == sb.len()` contract:
// a raw 0x00 would terminate the C string early.
fn _str_until_nul(data: &Vec[UInt8], pos: Int, n: Int) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let b = _byte(data, pos + i);
    if b == 0 {
      i = n;
    } else {
      out.push(b as UInt8);
      i = i + 1;
    }
  }
  return builder.sb_to_str(&out);
}

// Error text with the byte offset appended: "<msg> at <off>".
fn _at(msg: Str, off: Int) -> Str {
  return msg + " at " + convert.int_to_string(off);
}

// --------------------------------------------------
//  CRC-8 (polynomial 0x07, initial value 0, MSB-first, no reflection,
//  no final xor) -- the FLAC frame-header checksum
// --------------------------------------------------

// One CRC-8 step for byte `b`: xor into the register, then eight MSB-first
// shifts with the polynomial 0x07 fed back on overflow. The register never
// leaves 0..255, so the result is always a non-negative Int.
fn _crc8_byte(crc_in: Int, b: Int) -> Int {
  var crc = crc_in ^ b;
  var k = 0;
  while k < 8 {
    if crc >= 128 {
      crc = ((crc - 128) * 2) ^ 7;
    } else {
      crc = crc * 2;
    }
    k = k + 1;
  }
  return crc;
}

// CRC-8 over [start, start + size) of `data`; callers guarantee the bounds.
fn _crc8_range(data: &Vec[UInt8], start: Int, size: Int) -> Int {
  var crc: Int = 0;
  var i = 0;
  while i < size {
    crc = _crc8_byte(crc, _byte(data, start + i));
    i = i + 1;
  }
  return crc;
}

/// CRC-8 over the `size` bytes of `data` starting at `start`: polynomial
/// 0x07 (x^8 + x^2 + x + 1), initial value 0, MSB-first, no reflection and
/// no final xor. Returns -1 (an impossible checksum) when `start` or `size`
/// is negative or the range leaves the buffer. flac_crc8(empty) == 0 and
/// the CRC-8/SMBUS check vector "123456789" is 244 (0xF4).
/// Complexity: O(size).
pub fn flac_crc8(data: &Vec[UInt8], start: Int, size: Int) -> Int {
  if start < 0 || size < 0 {
    return -1;
  }
  if start + size > data.len() {
    return -1;
  }
  return _crc8_range(data, start, size);
}

// --------------------------------------------------
//  UTF-8 coded numbers (1..7 bytes; FLAC frame/sample numbers)
// --------------------------------------------------

/// Length in bytes of a UTF-8 coded number whose first byte is `first`:
/// 1..7 for a valid leading byte, -1 for a continuation byte (0x80..0xBF)
/// or 0xFF. This is the length implied by the lead byte only; overlong
/// forms are rejected by flac_parse_utf8_number.
/// Complexity: O(1).
pub fn flac_utf8_size(first: Int) -> Int {
  if first < 0 || first > 255 {
    return -1;
  }
  if first < 128 {
    return 1;
  }
  if first < 192 {
    return -1;
  }
  if first < 224 {
    return 2;
  }
  if first < 240 {
    return 3;
  }
  if first < 248 {
    return 4;
  }
  if first < 252 {
    return 5;
  }
  if first < 254 {
    return 6;
  }
  if first == 254 {
    return 7;
  }
  return -1;
}

/// Decode the UTF-8 coded number at `offset`.
///
/// Validates the full form: a legal leading byte (1..7 bytes), every
/// continuation byte in 0x80..0xBF, and no overlong encoding (a 2-byte form
/// encodes at least 0x80, a 3-byte form at least 0x800, ... a 7-byte form at
/// least 0x80000000; the 7-byte form tops out at the 36-bit 0xFFFFFFFFF).
/// The number range is deliberately not limited here: the frame-header
/// parser enforces 31 bits for a fixed-blocksize frame number.
///
/// Errors: Err("flac: offset out of range") for a negative offset;
/// Err("flac: truncated utf8 number at N") when the coded bytes leave the
/// buffer (N = `offset`); Err("flac: invalid utf8 number at N") for a bad
/// leading byte or a bad continuation byte (N = the offending byte);
/// Err("flac: overlong utf8 number at N") for an overlong encoding
/// (N = `offset`).
/// Complexity: O(1).
pub fn flac_parse_utf8_number(data: &Vec[UInt8], offset: Int) -> Result[Int, Str] {
  if offset < 0 {
    return _err_int("flac: offset out of range");
  }
  if offset >= data.len() {
    return _err_int(_at("flac: truncated utf8 number", offset));
  }
  let first = _byte(data, offset);
  let n = flac_utf8_size(first);
  if n < 0 {
    return _err_int(_at("flac: invalid utf8 number", offset));
  }
  if offset + n > data.len() {
    return _err_int(_at("flac: truncated utf8 number", offset));
  }
  if n == 1 {
    return _ok_int(first);
  }
  // Payload bits in the lead byte: 7 - n. `modv` = 2^(7-n).
  var modv = 1;
  var lead_bits = 7 - n;
  var k = 0;
  while k < lead_bits {
    modv = modv * 2;
    k = k + 1;
  }
  var value: Int = first % modv;
  var i = 1;
  while i < n {
    let b = _byte(data, offset + i);
    if b < 128 || b > 191 {
      return _err_int(_at("flac: invalid utf8 number", offset + i));
    }
    value = value * 64 + (b % 64);
    i = i + 1;
  }
  var vmin = 0;
  if n == 2 {
    vmin = 128;
  } elif n == 3 {
    vmin = 2048;
  } elif n == 4 {
    vmin = 65536;
  } elif n == 5 {
    vmin = 2097152;
  } elif n == 6 {
    vmin = 67108864;
  } elif n == 7 {
    vmin = 2147483648;
  }
  if value < vmin {
    return _err_int(_at("flac: overlong utf8 number", offset));
  }
  return _ok_int(value);
}

// --------------------------------------------------
//  Table helpers
// --------------------------------------------------

/// Metadata block type name: 0 "STREAMINFO", 1 "PADDING", 2 "APPLICATION",
/// 3 "SEEKTABLE", 4 "VORBIS_COMMENT", 5 "CUESHEET", 6 "PICTURE", anything
/// else "". Complexity: O(1).
pub fn flac_metadata_type_name(btype: Int) -> Str {
  if btype == 0 { return "STREAMINFO"; }
  if btype == 1 { return "PADDING"; }
  if btype == 2 { return "APPLICATION"; }
  if btype == 3 { return "SEEKTABLE"; }
  if btype == 4 { return "VORBIS_COMMENT"; }
  if btype == 5 { return "CUESHEET"; }
  if btype == 6 { return "PICTURE"; }
  return "";
}

/// Block size in samples for a frame-header block-size code: 0 (reserved)
/// maps to 0, the codes 6 and 7 (8/16-bit extra follows) map to -1, and
/// every other valid code maps to its table value (192, 576, 1152, 2304,
/// 4608, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768).
/// Complexity: O(1).
pub fn flac_block_size_for_code(code: Int) -> Int {
  if code == 1 { return 192; }
  if code == 2 { return 576; }
  if code == 3 { return 1152; }
  if code == 4 { return 2304; }
  if code == 5 { return 4608; }
  if code == 6 { return -1; }
  if code == 7 { return -1; }
  if code == 8 { return 256; }
  if code == 9 { return 512; }
  if code == 10 { return 1024; }
  if code == 11 { return 2048; }
  if code == 12 { return 4096; }
  if code == 13 { return 8192; }
  if code == 14 { return 16384; }
  if code == 15 { return 32768; }
  return 0;
}

/// Sample rate in Hz for a frame-header sample-rate code: 0 means "from
/// STREAMINFO" and maps to 0, codes 1..11 map to their table values
/// (88200, 176400, 192000, 8000, 16000, 22050, 24000, 32000, 44100, 48000,
/// 96000), codes 12..14 have an 8/16-bit extra field and map to -1, and 15
/// (forbidden) maps to -2. Complexity: O(1).
pub fn flac_sample_rate_for_code(code: Int) -> Int {
  if code == 1 { return 88200; }
  if code == 2 { return 176400; }
  if code == 3 { return 192000; }
  if code == 4 { return 8000; }
  if code == 5 { return 16000; }
  if code == 6 { return 22050; }
  if code == 7 { return 24000; }
  if code == 8 { return 32000; }
  if code == 9 { return 44100; }
  if code == 10 { return 48000; }
  if code == 11 { return 96000; }
  if code == 12 { return -1; }
  if code == 13 { return -1; }
  if code == 14 { return -1; }
  if code == 15 { return -2; }
  return 0;
}

/// Bits per sample for a frame-header sample-size code: 0 means "from
/// STREAMINFO" and maps to 0; 1/2/4/5/6/7 map to 8/12/16/20/24/32; 3
/// (reserved) and out-of-range codes map to -1. Complexity: O(1).
pub fn flac_bits_per_sample_for_code(code: Int) -> Int {
  if code == 1 { return 8; }
  if code == 2 { return 12; }
  if code == 4 { return 16; }
  if code == 5 { return 20; }
  if code == 6 { return 24; }
  if code == 7 { return 32; }
  if code == 0 { return 0; }
  return -1;
}

/// Channel count for a frame-header channel assignment: 0..7 independent
/// (1..8 channels), 8 left/side, 9 right/side and 10 mid/side (2 channels);
/// anything else -1. Complexity: O(1).
pub fn flac_channel_assignment_channels(assignment: Int) -> Int {
  if assignment < 0 {
    return -1;
  }
  if assignment <= 7 {
    return assignment + 1;
  }
  if assignment == 8 || assignment == 9 || assignment == 10 {
    return 2;
  }
  return -1;
}

/// Channel assignment name: 0..7 "independent", 8 "left/side stereo",
/// 9 "right/side stereo", 10 "mid/side stereo", anything else "".
/// Complexity: O(1).
pub fn flac_channel_assignment_name(assignment: Int) -> Str {
  if assignment >= 0 && assignment <= 7 {
    return "independent";
  }
  if assignment == 8 { return "left/side stereo"; }
  if assignment == 9 { return "right/side stereo"; }
  if assignment == 10 { return "mid/side stereo"; }
  return "";
}

/// Blocking strategy name: 0 "fixed", 1 "variable", anything else "".
/// Complexity: O(1).
pub fn flac_blocking_strategy_name(strategy: Int) -> Str {
  if strategy == 0 { return "fixed"; }
  if strategy == 1 { return "variable"; }
  return "";
}

// --------------------------------------------------
//  STREAMINFO
// --------------------------------------------------

// Parse the 34-byte STREAMINFO payload at `start`; callers guarantee the
// bounds. Bit layout (MSB-first across bytes 10..17): 20-bit sample rate,
// 3-bit channels-1, 5-bit bits-per-sample-1, 36-bit total samples.
fn _streaminfo_at(data: &Vec[UInt8], start: Int) -> FlacStreamInfo {
  let b10 = _byte(data, start + 10);
  let b11 = _byte(data, start + 11);
  let b12 = _byte(data, start + 12);
  let b13 = _byte(data, start + 13);
  var md5 = Vec[UInt8].new();
  var i = 0;
  while i < 16 {
    md5.push(data[start + 18 + i]);
    i = i + 1;
  }
  return FlacStreamInfo{
    min_block_size: _be_u16(data, start);
    max_block_size: _be_u16(data, start + 2);
    min_frame_size: _be_u24(data, start + 4);
    max_frame_size: _be_u24(data, start + 7);
    sample_rate: b10 * 4096 + b11 * 16 + b12 / 16;
    channels: (b12 / 2) % 8 + 1;
    bits_per_sample: (b12 % 2) * 16 + b13 / 16 + 1;
    total_samples: (b13 % 16) * 4294967296 + _be_u32(data, start + 14);
    md5_hex: hex.hex_encode(&md5);
  };
}

/// Parse one STREAMINFO payload.
///
/// `block` must be exactly the 34-byte payload (no 4-byte metadata header):
/// Err("flac: bad streaminfo length at 0") otherwise. The fields are read
/// verbatim; no semantic validation is applied (a zero sample rate or a
/// min block size below 16 is reported as stored). For streams use
/// flac_parse_metadata, which takes the payload from its block header.
/// Complexity: O(1).
pub fn flac_parse_streaminfo(block: &Vec[UInt8]) -> Result[FlacStreamInfo, Str] {
  if block.len() != 34 {
    return _err_streaminfo("flac: bad streaminfo length at 0");
  }
  return _ok_streaminfo(_streaminfo_at(block, 0));
}

// --------------------------------------------------
//  VORBIS_COMMENT and PICTURE payload parsers
// --------------------------------------------------

// Parse the VORBIS_COMMENT payload in [start, end); `ebase` is the offset
// reported in structural errors (the block header offset when called from
// flac_parse_metadata, 0 from the standalone wrapper). Little-endian
// lengths: vendor, comment count, then each comment. The payload must be
// consumed exactly; trailing bytes are a structural error.
fn _vorbis_range(data: &Vec[UInt8], start: Int, end: Int, ebase: Int) -> Result[FlacVorbisComment, Str] {
  var comments = Vec[Str].new();
  var vendor = "";
  var p = start;
  if p + 4 > end {
    return _err_vorbis(_at("flac: vorbis comment overrun", ebase));
  }
  let vendor_len = _le_u32(data, p);
  p = p + 4;
  if vendor_len > end - p {
    return _err_vorbis(_at("flac: vorbis comment overrun", ebase));
  }
  vendor = _str_until_nul(data, p, vendor_len);
  p = p + vendor_len;
  if p + 4 > end {
    return _err_vorbis(_at("flac: vorbis comment overrun", ebase));
  }
  let count = _le_u32(data, p);
  p = p + 4;
  var i = 0;
  while i < count {
    if p + 4 > end {
      return _err_vorbis(_at("flac: vorbis comment overrun", ebase));
    }
    let clen = _le_u32(data, p);
    p = p + 4;
    if clen > end - p {
      return _err_vorbis(_at("flac: vorbis comment overrun", ebase));
    }
    let text = _str_until_nul(data, p, clen);
    comments.push(text);
    p = p + clen;
    i = i + 1;
  }
  if p != end {
    return _err_vorbis(_at("flac: vorbis comment overrun", ebase));
  }
  return _ok_vorbis(FlacVorbisComment{ vendor: vendor; comments: comments; });
}

/// Parse one VORBIS_COMMENT payload (the bytes after the 4-byte block
/// header).
///
/// Layout: u32 LE vendor length, vendor bytes, u32 LE comment count, then
/// per comment a u32 LE length and that many bytes. The payload must be
/// consumed exactly: every overrun and any trailing byte is
/// Err("flac: vorbis comment overrun at 0"). Strings stop at the first
/// 0x00; other bytes pass through unchanged (UTF-8 is not validated).
/// Complexity: O(payload).
pub fn flac_parse_vorbis_comment(payload: &Vec[UInt8]) -> Result[FlacVorbisComment, Str] {
  return _vorbis_range(payload, 0, payload.len(), 0);
}

// Parse the PICTURE payload in [start, end); `ebase` is the offset reported
// in structural errors. Big-endian fields: type, MIME length + bytes,
// description length + bytes, width, height, depth, colors, data length +
// bytes. The payload must be consumed exactly; trailing bytes are a
// structural error.
fn _picture_range(data: &Vec[UInt8], start: Int, end: Int, ebase: Int) -> Result[FlacPicture, Str] {
  if start + 8 > end {
    return _err_picture(_at("flac: picture block overrun", ebase));
  }
  let ptype = _be_u32(data, start);
  let mime_len = _be_u32(data, start + 4);
  var p = start + 8;
  if mime_len > end - p {
    return _err_picture(_at("flac: picture block overrun", ebase));
  }
  let mime = _str_until_nul(data, p, mime_len);
  p = p + mime_len;
  if p + 4 > end {
    return _err_picture(_at("flac: picture block overrun", ebase));
  }
  let desc_len = _be_u32(data, p);
  p = p + 4;
  if desc_len > end - p {
    return _err_picture(_at("flac: picture block overrun", ebase));
  }
  let desc = _str_until_nul(data, p, desc_len);
  p = p + desc_len;
  if p + 20 > end {
    return _err_picture(_at("flac: picture block overrun", ebase));
  }
  let width = _be_u32(data, p);
  let height = _be_u32(data, p + 4);
  let depth = _be_u32(data, p + 8);
  let colors = _be_u32(data, p + 12);
  let dlen = _be_u32(data, p + 16);
  p = p + 20;
  if dlen > end - p {
    return _err_picture(_at("flac: picture block overrun", ebase));
  }
  p = p + dlen;
  if p != end {
    return _err_picture(_at("flac: picture block overrun", ebase));
  }
  return _ok_picture(FlacPicture{
    picture_type: ptype;
    mime: mime;
    description: desc;
    width: width;
    height: height;
    depth: depth;
    colors: colors;
    data_length: dlen;
  });
}

/// Parse one PICTURE payload (the bytes after the 4-byte block header).
///
/// Layout: u32 BE type, u32 BE MIME length + bytes, u32 BE description
/// length + bytes, u32 BE width, u32 BE height, u32 BE color depth, u32 BE
/// indexed-color count, u32 BE data length + that many data bytes. The
/// payload must be consumed exactly: every overrun and any trailing byte is
/// Err("flac: picture block overrun at 0"). The picture data itself is not
/// copied and not inspected; only its declared length is reported.
/// Complexity: O(payload).
pub fn flac_parse_picture(payload: &Vec[UInt8]) -> Result[FlacPicture, Str] {
  return _picture_range(payload, 0, payload.len(), 0);
}

// Walk a CUESHEET payload in [start, start + size) and return its declared
// track count. The fixed part is 396 bytes (128 catalog + 8 lead-in + 1 CD
// flag + 258 reserved + 1 track count); each track is 36 bytes plus 12 per
// index point. The walk must consume the payload exactly. Opaque: only the
// track count is exposed. `ebase` is the offset reported in errors.
fn _cuesheet_check(data: &Vec[UInt8], start: Int, size: Int, ebase: Int) -> Result[Int, Str] {
  if size < 396 {
    return _err_int(_at("flac: bad cuesheet length", ebase));
  }
  let end = start + size;
  let ntracks = _byte(data, start + 395);
  var p = start + 396;
  var t = 0;
  while t < ntracks {
    if p + 36 > end {
      return _err_int(_at("flac: bad cuesheet length", ebase));
    }
    let nidx = _byte(data, p + 35);
    if p + 36 + nidx * 12 > end {
      return _err_int(_at("flac: bad cuesheet length", ebase));
    }
    p = p + 36 + nidx * 12;
    t = t + 1;
  }
  if p != end {
    return _err_int(_at("flac: bad cuesheet length", ebase));
  }
  return _ok_int(ntracks);
}

// --------------------------------------------------
//  Public API: metadata
// --------------------------------------------------

/// Parse the "fLaC" marker and the whole metadata section of `data`.
///
/// Validation order (first failure wins; N is the relevant byte offset --
/// the block header offset for every per-block structural error):
/// `data` empty -> Err("flac: empty input"); fewer than 4 bytes ->
/// Err("flac: truncated stream marker at 0"); missing "fLaC" ->
/// Err("flac: bad stream marker at 0"); a block header would start past the
/// end of the buffer without a last-block flag -> Err("flac: missing last
/// metadata block at N"); fewer than 4 header bytes -> Err("flac: truncated
/// block header at N"); type 127 -> Err("flac: forbidden block type at N");
/// type 7..126 -> Err("flac: invalid block type at N"); declared payload
/// past the end of the buffer -> Err("flac: block overrun at N"); the first
/// block is not STREAMINFO -> Err("flac: missing streaminfo at N"); a later
/// STREAMINFO -> Err("flac: duplicate streaminfo at N"); STREAMINFO length
/// other than 34 -> Err("flac: bad streaminfo length at N"); APPLICATION
/// payload shorter than 4 bytes -> Err("flac: short application block at
/// N"); SEEKTABLE length not a multiple of 18 -> Err("flac: bad seektable
/// length at N"); malformed VORBIS_COMMENT -> Err("flac: vorbis comment
/// overrun at N"); malformed PICTURE -> Err("flac: picture block overrun at
/// N"); malformed CUESHEET -> Err("flac: bad cuesheet length at N").
///
/// On success every metadata block is recorded in stream order and every
/// payload is exposed (see FlacMetadata). Metadata parsing stops after the
/// block with the last-block flag; bytes after it (the audio frames) are
/// not inspected, and flac_parse_frame_header starts at `audio_offset`.
/// Complexity: O(metadata size).
pub fn flac_parse_metadata(data: &Vec[UInt8]) -> Result[FlacMetadata, Str] {
  let n = data.len();
  if n == 0 {
    return _err_metadata("flac: empty input");
  }
  if n < 4 {
    return _err_metadata(_at("flac: truncated stream marker", 0));
  }
  if _byte(data, 0) != 102 {
    return _err_metadata(_at("flac: bad stream marker", 0));
  }
  if _byte(data, 1) != 76 {
    return _err_metadata(_at("flac: bad stream marker", 0));
  }
  if _byte(data, 2) != 97 {
    return _err_metadata(_at("flac: bad stream marker", 0));
  }
  if _byte(data, 3) != 67 {
    return _err_metadata(_at("flac: bad stream marker", 0));
  }
  var block_offsets = Vec[Int].new();
  var block_types = Vec[Int].new();
  var block_lengths = Vec[Int].new();
  var has_streaminfo = false;
  var min_block_size = 0;
  var max_block_size = 0;
  var min_frame_size = 0;
  var max_frame_size = 0;
  var sample_rate = 0;
  var channels = 0;
  var bits_per_sample = 0;
  var total_samples = 0;
  var md5_hex = "";
  var padding_bytes = 0;
  var app_ids = Vec[Str].new();
  var app_data_lengths = Vec[Int].new();
  var seek_samples = Vec[Int].new();
  var seek_offsets = Vec[Int].new();
  var seek_frame_samples = Vec[Int].new();
  var vendor = "";
  var comments = Vec[Str].new();
  var cue_track_counts = Vec[Int].new();
  var cue_lengths = Vec[Int].new();
  var picture_types = Vec[Int].new();
  var picture_mimes = Vec[Str].new();
  var picture_descriptions = Vec[Str].new();
  var picture_widths = Vec[Int].new();
  var picture_heights = Vec[Int].new();
  var picture_depths = Vec[Int].new();
  var picture_colors = Vec[Int].new();
  var picture_data_lengths = Vec[Int].new();
  var pos = 4;
  var done = false;
  while !done {
    if pos == n {
      return _err_metadata(_at("flac: missing last metadata block", pos));
    }
    if n - pos < 4 {
      return _err_metadata(_at("flac: truncated block header", pos));
    }
    let hb = _byte(data, pos);
    var is_last = false;
    if hb >= 128 {
      is_last = true;
    }
    let btype = hb % 128;
    let blen = _be_u24(data, pos + 1);
    if btype == 127 {
      return _err_metadata(_at("flac: forbidden block type", pos));
    }
    if btype >= 7 {
      return _err_metadata(_at("flac: invalid block type", pos));
    }
    let dstart = pos + 4;
    if dstart + blen > n {
      return _err_metadata(_at("flac: block overrun", pos));
    }
    if block_offsets.len() == 0 && btype != 0 {
      return _err_metadata(_at("flac: missing streaminfo", pos));
    }
    if block_offsets.len() > 0 && btype == 0 {
      return _err_metadata(_at("flac: duplicate streaminfo", pos));
    }
    if btype == 0 {
      if blen != 34 {
        return _err_metadata(_at("flac: bad streaminfo length", pos));
      }
      let si = _streaminfo_at(data, dstart);
      has_streaminfo = true;
      min_block_size = si.min_block_size;
      max_block_size = si.max_block_size;
      min_frame_size = si.min_frame_size;
      max_frame_size = si.max_frame_size;
      sample_rate = si.sample_rate;
      channels = si.channels;
      bits_per_sample = si.bits_per_sample;
      total_samples = si.total_samples;
      md5_hex = si.md5_hex;
    } elif btype == 1 {
      padding_bytes = padding_bytes + blen;
    } elif btype == 2 {
      if blen < 4 {
        return _err_metadata(_at("flac: short application block", pos));
      }
      let app_id = _str_until_nul(data, dstart, 4);
      app_ids.push(app_id);
      app_data_lengths.push(blen - 4);
    } elif btype == 3 {
      if blen % 18 != 0 {
        return _err_metadata(_at("flac: bad seektable length", pos));
      }
      let entries = blen / 18;
      var j = 0;
      while j < entries {
        let base = dstart + j * 18;
        seek_samples.push(_be_u64_clamped(data, base));
        seek_offsets.push(_be_u64_clamped(data, base + 8));
        seek_frame_samples.push(_be_u16(data, base + 16));
        j = j + 1;
      }
    } elif btype == 4 {
      let vr = _vorbis_range(data, dstart, dstart + blen, pos);
      if !vr.is_ok {
        return _err_metadata(vr.error);
      }
      let vc = vr.value;
      vendor = vc.vendor;
      var ci = 0;
      while ci < vc.comments.len() {
        let e: Str = vc.comments[ci];
        comments.push(e);
        ci = ci + 1;
      }
    } elif btype == 5 {
      let cr = _cuesheet_check(data, dstart, blen, pos);
      if !cr.is_ok {
        return _err_metadata(cr.error);
      }
      cue_track_counts.push(cr.value);
      cue_lengths.push(blen);
    } else {
      let pr = _picture_range(data, dstart, dstart + blen, pos);
      if !pr.is_ok {
        return _err_metadata(pr.error);
      }
      let pic = pr.value;
      picture_types.push(pic.picture_type);
      picture_mimes.push(pic.mime);
      picture_descriptions.push(pic.description);
      picture_widths.push(pic.width);
      picture_heights.push(pic.height);
      picture_depths.push(pic.depth);
      picture_colors.push(pic.colors);
      picture_data_lengths.push(pic.data_length);
    }
    block_offsets.push(pos);
    block_types.push(btype);
    block_lengths.push(blen);
    pos = dstart + blen;
    if is_last {
      done = true;
    }
  }
  return _ok_metadata(FlacMetadata{
    metadata_size: pos;
    audio_offset: pos;
    has_streaminfo: has_streaminfo;
    min_block_size: min_block_size;
    max_block_size: max_block_size;
    min_frame_size: min_frame_size;
    max_frame_size: max_frame_size;
    sample_rate: sample_rate;
    channels: channels;
    bits_per_sample: bits_per_sample;
    total_samples: total_samples;
    md5_hex: md5_hex;
    block_offsets: block_offsets;
    block_types: block_types;
    block_lengths: block_lengths;
    padding_bytes: padding_bytes;
    app_ids: app_ids;
    app_data_lengths: app_data_lengths;
    seek_samples: seek_samples;
    seek_offsets: seek_offsets;
    seek_frame_samples: seek_frame_samples;
    vendor: vendor;
    comments: comments;
    cue_track_counts: cue_track_counts;
    cue_lengths: cue_lengths;
    picture_types: picture_types;
    picture_mimes: picture_mimes;
    picture_descriptions: picture_descriptions;
    picture_widths: picture_widths;
    picture_heights: picture_heights;
    picture_depths: picture_depths;
    picture_colors: picture_colors;
    picture_data_lengths: picture_data_lengths;
  });
}

// --------------------------------------------------
//  Public API: metadata accessors
// --------------------------------------------------

/// Offset one past the last metadata block (where audio frames begin), as
/// recorded by flac_parse_metadata. Complexity: O(1).
pub fn flac_audio_offset(m: &FlacMetadata) -> Int {
  return m.audio_offset;
}

/// Total metadata size in bytes (marker included); equal to
/// flac_audio_offset(m). Complexity: O(1).
pub fn flac_metadata_size(m: &FlacMetadata) -> Int {
  return m.metadata_size;
}

/// Number of metadata blocks in stream order. Complexity: O(1).
pub fn flac_block_count(m: &FlacMetadata) -> Int {
  return m.block_offsets.len();
}

/// Absolute offset of the 4-byte header of metadata block `i`, or -1 when
/// `i` is negative or >= flac_block_count(m). Complexity: O(1).
pub fn flac_block_offset(m: &FlacMetadata, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.block_offsets.len() {
    return -1;
  }
  let v: Int = m.block_offsets[i];
  return v;
}

/// Raw type (0..6) of metadata block `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn flac_block_type(m: &FlacMetadata, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.block_types.len() {
    return -1;
  }
  let v: Int = m.block_types[i];
  return v;
}

/// Declared payload length of metadata block `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn flac_block_length(m: &FlacMetadata, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.block_lengths.len() {
    return -1;
  }
  let v: Int = m.block_lengths[i];
  return v;
}

/// Total PADDING payload bytes. Complexity: O(1).
pub fn flac_padding_bytes(m: &FlacMetadata) -> Int {
  return m.padding_bytes;
}

/// Number of APPLICATION blocks. Complexity: O(1).
pub fn flac_application_count(m: &FlacMetadata) -> Int {
  return m.app_ids.len();
}

/// 4-byte application id of APPLICATION block `i` truncated at the first
/// 0x00, or "" when out of range. Complexity: O(1).
pub fn flac_application_id(m: &FlacMetadata, i: Int) -> Str {
  if i < 0 {
    return "";
  }
  if i >= m.app_ids.len() {
    return "";
  }
  let v: Str = m.app_ids[i];
  return v;
}

/// Data length (payload length - 4) of APPLICATION block `i`, or -1 when
/// out of range. Complexity: O(1).
pub fn flac_application_data_length(m: &FlacMetadata, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.app_data_lengths.len() {
    return -1;
  }
  let v: Int = m.app_data_lengths[i];
  return v;
}

/// Number of SEEKTABLE entries. Complexity: O(1).
pub fn flac_seek_count(m: &FlacMetadata) -> Int {
  return m.seek_samples.len();
}

/// Sample number of seek entry `i` (0xFFFFFFFFFFFFFFFF placeholders clamped
/// to Int max), or -1 when out of range. Complexity: O(1).
pub fn flac_seek_sample(m: &FlacMetadata, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.seek_samples.len() {
    return -1;
  }
  let v: Int = m.seek_samples[i];
  return v;
}

/// Byte offset of seek entry `i` (clamped like flac_seek_sample), or -1 when
/// out of range. Complexity: O(1).
pub fn flac_seek_offset(m: &FlacMetadata, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.seek_offsets.len() {
    return -1;
  }
  let v: Int = m.seek_offsets[i];
  return v;
}

/// Number of samples in the target frame of seek entry `i`, or -1 when out
/// of range. Complexity: O(1).
pub fn flac_seek_frame_samples(m: &FlacMetadata, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.seek_frame_samples.len() {
    return -1;
  }
  let v: Int = m.seek_frame_samples[i];
  return v;
}

/// Vendor string of the last VORBIS_COMMENT block parsed ("" when none).
/// Complexity: O(1).
pub fn flac_vendor(m: &FlacMetadata) -> Str {
  return m.vendor;
}

/// Number of Vorbis comments across all VORBIS_COMMENT blocks.
/// Complexity: O(1).
pub fn flac_comment_count(m: &FlacMetadata) -> Int {
  return m.comments.len();
}

/// Comment `i` ("" when out of range). Complexity: O(1).
pub fn flac_comment(m: &FlacMetadata, i: Int) -> Str {
  if i < 0 {
    return "";
  }
  if i >= m.comments.len() {
    return "";
  }
  let v: Str = m.comments[i];
  return v;
}

/// Number of CUESHEET blocks. Complexity: O(1).
pub fn flac_cuesheet_count(m: &FlacMetadata) -> Int {
  return m.cue_lengths.len();
}

/// Declared track count of CUESHEET block `i` (including the lead-out), or
/// -1 when out of range. Complexity: O(1).
pub fn flac_cuesheet_track_count(m: &FlacMetadata, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.cue_track_counts.len() {
    return -1;
  }
  let v: Int = m.cue_track_counts[i];
  return v;
}

/// Payload length of CUESHEET block `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn flac_cuesheet_length(m: &FlacMetadata, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.cue_lengths.len() {
    return -1;
  }
  let v: Int = m.cue_lengths[i];
  return v;
}

/// Number of PICTURE blocks. Complexity: O(1).
pub fn flac_picture_count(m: &FlacMetadata) -> Int {
  return m.picture_types.len();
}

/// Raw picture type of PICTURE block `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn flac_picture_type(m: &FlacMetadata, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.picture_types.len() {
    return -1;
  }
  let v: Int = m.picture_types[i];
  return v;
}

/// MIME string of PICTURE block `i`, or "" when out of range.
/// Complexity: O(1).
pub fn flac_picture_mime(m: &FlacMetadata, i: Int) -> Str {
  if i < 0 {
    return "";
  }
  if i >= m.picture_mimes.len() {
    return "";
  }
  let v: Str = m.picture_mimes[i];
  return v;
}

/// Description of PICTURE block `i`, or "" when out of range.
/// Complexity: O(1).
pub fn flac_picture_description(m: &FlacMetadata, i: Int) -> Str {
  if i < 0 {
    return "";
  }
  if i >= m.picture_descriptions.len() {
    return "";
  }
  let v: Str = m.picture_descriptions[i];
  return v;
}

/// Pixel width of PICTURE block `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn flac_picture_width(m: &FlacMetadata, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.picture_widths.len() {
    return -1;
  }
  let v: Int = m.picture_widths[i];
  return v;
}

/// Pixel height of PICTURE block `i`, or -1 when out of range.
/// Complexity: O(1).
pub fn flac_picture_height(m: &FlacMetadata, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.picture_heights.len() {
    return -1;
  }
  let v: Int = m.picture_heights[i];
  return v;
}

/// Color depth (bits per pixel) of PICTURE block `i`, or -1 when out of
/// range. Complexity: O(1).
pub fn flac_picture_depth(m: &FlacMetadata, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.picture_depths.len() {
    return -1;
  }
  let v: Int = m.picture_depths[i];
  return v;
}

/// Indexed-color count of PICTURE block `i` (0 for non-indexed images), or
/// -1 when out of range. Complexity: O(1).
pub fn flac_picture_colors(m: &FlacMetadata, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.picture_colors.len() {
    return -1;
  }
  let v: Int = m.picture_colors[i];
  return v;
}

/// Declared picture data length of PICTURE block `i`, or -1 when out of
/// range. Complexity: O(1).
pub fn flac_picture_data_length(m: &FlacMetadata, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= m.picture_data_lengths.len() {
    return -1;
  }
  let v: Int = m.picture_data_lengths[i];
  return v;
}

// --------------------------------------------------
//  Public API: frame header
// --------------------------------------------------

/// Parse and validate the FLAC frame header at `offset`.
///
/// The header is scanned field by field: 14-bit sync (0xFF plus top six
/// bits 111110 -> second byte 0xF8..0xFB), reserved bit (must be 0),
/// blocking strategy, block-size code (0 reserved), sample-rate code (15
/// forbidden), channel assignment (11..15 reserved), sample-size code (3
/// reserved), the second reserved bit (must be 0), the UTF-8 coded number
/// (1..7 bytes; a fixed-blocksize frame number must fit 31 bits), the
/// optional 8/16-bit block-size extra and the optional 8/16-bit sample-rate
/// extra, and finally the CRC-8 byte.
///
/// Errors (first failure wins): Err("flac: offset out of range") for a
/// negative offset; Err("flac: truncated frame header at N") for anything
/// that runs past the end of the buffer (N = `offset`, including a missing
/// UTF-8 continuation byte, a missing extra field and a missing CRC byte);
/// Err("flac: bad sync at N"); Err("flac: reserved bit set at N");
/// Err("flac: reserved block size at N"); Err("flac: reserved sample rate
/// at N"); Err("flac: reserved channel assignment at N"); Err("flac:
/// reserved sample size at N"); the UTF-8 errors of flac_parse_utf8_number;
/// Err("flac: frame number out of range at N") (N = the number start) for a
/// fixed-blocksize number above 2^31-1.
///
/// A CRC-8 mismatch is NOT an error: the header is returned with
/// `crc8_ok == false`, which lets callers inspect damaged headers.
/// Complexity: O(1).
pub fn flac_parse_frame_header(data: &Vec[UInt8], offset: Int) -> Result[FlacFrameHeader, Str] {
  if offset < 0 {
    return _err_frame("flac: offset out of range");
  }
  if offset + 4 > data.len() {
    return _err_frame(_at("flac: truncated frame header", offset));
  }
  let b0 = _byte(data, offset);
  let b1 = _byte(data, offset + 1);
  if b0 != 255 {
    return _err_frame(_at("flac: bad sync", offset));
  }
  if b1 < 248 || b1 > 251 {
    return _err_frame(_at("flac: bad sync", offset));
  }
  if (b1 / 2) % 2 == 1 {
    return _err_frame(_at("flac: reserved bit set", offset));
  }
  let strategy = b1 % 2;
  let b2 = _byte(data, offset + 2);
  let bs_code = b2 / 16;
  let sr_code = b2 % 16;
  if bs_code == 0 {
    return _err_frame(_at("flac: reserved block size", offset));
  }
  if sr_code == 15 {
    return _err_frame(_at("flac: reserved sample rate", offset));
  }
  let b3 = _byte(data, offset + 3);
  let assignment = b3 / 16;
  let ss_code = (b3 / 2) % 8;
  if assignment >= 11 {
    return _err_frame(_at("flac: reserved channel assignment", offset));
  }
  if ss_code == 3 {
    return _err_frame(_at("flac: reserved sample size", offset));
  }
  if b3 % 2 == 1 {
    return _err_frame(_at("flac: reserved bit set", offset));
  }
  let num_start = offset + 4;
  if num_start >= data.len() {
    return _err_frame(_at("flac: truncated frame header", offset));
  }
  let first_num = _byte(data, num_start);
  let num_bytes = flac_utf8_size(first_num);
  if num_bytes < 0 {
    return _err_frame(_at("flac: invalid utf8 number", num_start));
  }
  if num_start + num_bytes > data.len() {
    return _err_frame(_at("flac: truncated frame header", offset));
  }
  let numr = flac_parse_utf8_number(data, num_start);
  if !numr.is_ok {
    return _err_frame(numr.error);
  }
  let number = numr.value;
  if strategy == 0 && number > 2147483647 {
    return _err_frame(_at("flac: frame number out of range", num_start));
  }
  var p = num_start + num_bytes;
  var block_size = flac_block_size_for_code(bs_code);
  if bs_code == 6 {
    if p >= data.len() {
      return _err_frame(_at("flac: truncated frame header", offset));
    }
    block_size = _byte(data, p) + 1;
    p = p + 1;
  }
  if bs_code == 7 {
    if p + 2 > data.len() {
      return _err_frame(_at("flac: truncated frame header", offset));
    }
    block_size = _be_u16(data, p) + 1;
    p = p + 2;
  }
  var sample_rate = flac_sample_rate_for_code(sr_code);
  if sr_code == 12 {
    if p >= data.len() {
      return _err_frame(_at("flac: truncated frame header", offset));
    }
    sample_rate = _byte(data, p) * 1000;
    p = p + 1;
  }
  if sr_code == 13 {
    if p + 2 > data.len() {
      return _err_frame(_at("flac: truncated frame header", offset));
    }
    sample_rate = _be_u16(data, p);
    p = p + 2;
  }
  if sr_code == 14 {
    if p + 2 > data.len() {
      return _err_frame(_at("flac: truncated frame header", offset));
    }
    sample_rate = _be_u16(data, p) * 10;
    p = p + 2;
  }
  if p >= data.len() {
    return _err_frame(_at("flac: truncated frame header", offset));
  }
  let stored_crc = _byte(data, p);
  let computed = _crc8_range(data, offset, p - offset);
  return _ok_frame(FlacFrameHeader{
    blocking_strategy: strategy;
    block_size_code: bs_code;
    sample_rate_code: sr_code;
    channel_assignment: assignment;
    sample_size_code: ss_code;
    channels: flac_channel_assignment_channels(assignment);
    block_size: block_size;
    sample_rate: sample_rate;
    bits_per_sample: flac_bits_per_sample_for_code(ss_code);
    number: number;
    number_bytes: num_bytes;
    crc8: stored_crc;
    crc8_ok: stored_crc == computed;
    header_size: p + 1 - offset;
  });
}
