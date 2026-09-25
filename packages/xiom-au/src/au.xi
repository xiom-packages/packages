// XIOM -- xiom.au: Sun/NeXT AU (.snd) audio header codec (header + info + span)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: structural parsing and building of Sun/NeXT AU (.snd) audio headers.
// The 24-byte big-endian header carries the magic ".snd", the absolute byte
// offset of the audio data (must be >= 24), the data size (the sentinel
// 0xFFFFFFFF means "runs to the end of the buffer"), the encoding id (see the
// table below), the sample rate in Hz and the channel count (>= 1). Every
// byte between offset 24 and the data offset is the optional info/annotation
// field; it is preserved raw and only interpreted by au_info_text, which
// requires printable ASCII. Audio bytes are opaque: no sample decoding and no
// mu-law/A-law arithmetic is performed.
//
// Encoding table (au_encoding_name / au_encoding_bits / au_encoding_bytes):
//   1  = mu-law 8-bit      2  = linear 8-bit       3  = linear 16-bit
//   4  = linear 24-bit     5  = linear 32-bit      6  = float 32-bit
//   7  = double 64-bit     27 = A-law 8-bit
// All other ids are unknown. See SPEC.md for the byte-layout tables, the
// data-size policy, the error catalog and the test matrix.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * every byte read is widened with `(data[pos] as Int) & 0xFF`; UInt8
//     values are never compared against Int constants without widening.
//   * a Str is built from file bytes only after the range has been validated
//     as printable ASCII (0x20..0x7E): builder.sb_to_str hands out a
//     NUL-terminated C string, so a raw 0x00 byte would silently truncate
//     and trip its `result.len() == sb.len()` contract at run time.
//   * AuInfo is constructed inside au_parse and crosses function boundaries
//     only by reference or through _ok_info; there is no Vec[StructType] and
//     no Vec[Float64] anywhere in the module.

module xiom.au

use xiom.string;
use xiom.string.builder;

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Format descriptor for au_build and au_build_unknown_size.
///
/// `encoding` is written to the header as given: unknown ids produce a file
/// that au_parse rejects (documented garbage-in/garbage-out behaviour for a
/// total builder). `sample_rate` is clamped to 0..4294967295 and `channels`
/// to 1..4294967295 (the u32 field range; 0 channels is never emitted).
pub type AuFormat = {
  encoding: Int;
  sample_rate: Int;
  channels: Int;
}

/// Parsed AU header plus the resolved audio span.
///
/// `encoding`, `sample_rate` (Hz) and `channels` are the validated header
/// fields. `size_known` is false when the data-size field held the 0xFFFFFFFF
/// "unknown" sentinel; `stored_size` is the raw data-size field (0xFFFFFFFF
/// when unknown) and `data_size` is the resolved span length: the declared
/// size when known, or `data.len() - data_offset` for the sentinel.
/// `data_offset` is the absolute offset of the first audio byte and
/// `info_bytes` is the raw, uninterpreted info field (offsets
/// 24..data_offset); use au_info_text for a printable-ASCII-checked Str.
pub type AuInfo = {
  encoding: Int;
  sample_rate: Int;
  channels: Int;
  size_known: Bool;
  stored_size: Int;
  data_offset: Int;
  data_size: Int;
  info_bytes: Vec[UInt8];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[AuInfo, Str].
fn _ok_info(v: AuInfo) -> Result[AuInfo, Str] {
  return Ok(v);
}

// Err(m) for Result[AuInfo, Str].
fn _err_info(m: Str) -> Result[AuInfo, Str] {
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

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Encoding table
// --------------------------------------------------

/// Canonical name of an encoding id, or "" when the id is unknown.
/// Known ids: 1 mu-law 8-bit, 2 linear 8-bit, 3 linear 16-bit, 4 linear
/// 24-bit, 5 linear 32-bit, 6 float 32-bit, 7 double 64-bit, 27 A-law 8-bit.
/// Complexity: O(1).
pub fn au_encoding_name(encoding: Int) -> Str {
  if encoding == 1 { return "mu-law 8-bit"; }
  if encoding == 2 { return "linear 8-bit"; }
  if encoding == 3 { return "linear 16-bit"; }
  if encoding == 4 { return "linear 24-bit"; }
  if encoding == 5 { return "linear 32-bit"; }
  if encoding == 6 { return "float 32-bit"; }
  if encoding == 7 { return "double 64-bit"; }
  if encoding == 27 { return "A-law 8-bit"; }
  return "";
}

/// Bits per sample of an encoding id, or 0 when the id is unknown.
/// Known sizes: 1 -> 8, 2 -> 8, 3 -> 16, 4 -> 24, 5 -> 32, 6 -> 32,
/// 7 -> 64, 27 -> 8. Complexity: O(1).
pub fn au_encoding_bits(encoding: Int) -> Int {
  if encoding == 1 { return 8; }
  if encoding == 2 { return 8; }
  if encoding == 3 { return 16; }
  if encoding == 4 { return 24; }
  if encoding == 5 { return 32; }
  if encoding == 6 { return 32; }
  if encoding == 7 { return 64; }
  if encoding == 27 { return 8; }
  return 0;
}

/// Bytes per sample of an encoding id, or 0 when the id is unknown.
/// The value is `ceil(bits / 8)`; every known encoding has a byte-multiple
/// size, so it is a plain division with an explicit remainder guard.
/// Complexity: O(1).
pub fn au_encoding_bytes(encoding: Int) -> Int {
  let bits = au_encoding_bits(encoding);
  if bits <= 0 {
    return 0;
  }
  let q = bits / 8;
  let r = bits % 8;
  if r > 0 {
    return q + 1;
  }
  return q;
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
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

// Byte number `k` of `v` (0 = least significant). Arithmetic only: `& 0xFF`
// on values with bit 31 set miscompiles in v0.61.3, and this form is exact
// for negative two's-complement values too.
fn _byte_of(v: Int, k: Int) -> UInt8 {
  var q = v;
  var i = 0;
  while i < k {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    i = i + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

// Append the low `size` bytes of `v` in BIG-endian order.
fn _push_be(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = size - 1;
  while i >= 0 {
    out.push(_byte_of(v, i));
    i = i - 1;
  }
}

// True when the buffer starts with the AU magic ".snd" (2E 73 6E 64).
fn _has_magic(data: &Vec[UInt8]) -> Bool {
  if _byte(data, 0) != 46 { return false; }
  if _byte(data, 1) != 115 { return false; }
  if _byte(data, 2) != 110 { return false; }
  if _byte(data, 3) != 100 { return false; }
  return true;
}

// True when the `n` bytes at `pos` of `data` are all printable ASCII.
fn _printable_range(data: &Vec[UInt8], pos: Int, n: Int) -> Bool {
  var i = 0;
  while i < n {
    let b = _byte(data, pos + i);
    if b < 32 { return false; }
    if b > 126 { return false; }
    i = i + 1;
  }
  return true;
}

// Build a Str from `n` printable bytes at `pos`. Callers guarantee the bytes
// are printable ASCII, so the NUL-terminated result preserves every byte.
fn _str_range(data: &Vec[UInt8], pos: Int, n: Int) -> Str {
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < n {
    builder.sb_push_byte(&mut sb, _byte(data, pos + i) as UInt8);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Unsigned 32-bit clamp for the builder fields.
fn _clamp_u32(v: Int) -> Int {
  if v < 0 { return 0; }
  if v > 4294967295 { return 4294967295; }
  return v;
}

// Channel clamp: the header field is u32 with a documented minimum of 1.
fn _clamp_channels(c: Int) -> Int {
  if c < 1 { return 1; }
  if c > 4294967295 { return 4294967295; }
  return c;
}

// --------------------------------------------------
//  Public API: parsing
// --------------------------------------------------

/// Parse and validate a Sun/NeXT AU (.snd) header.
///
/// Checks, in order (first failure wins): non-empty buffer; at least 24
/// bytes; magic ".snd"; data offset >= 24; data offset <= data.len();
/// known encoding id (1..7 or 27); nonzero channels; nonzero sample rate;
/// then the data-size policy: the 0xFFFFFFFF sentinel resolves to the rest
/// of the buffer, a declared size larger than the remaining bytes is
/// Err("au: data size overrun"), and a smaller declared size is accepted
/// (the bytes between the declared end and the buffer end are ignored).
/// The info field is not interpreted here; every byte from 24 to the data
/// offset is copied raw into AuInfo.info_bytes.
/// Complexity: O(data_offset) (the info copy).
pub fn au_parse(data: &Vec[UInt8]) -> Result[AuInfo, Str] {
  let n = data.len();
  if n == 0 {
    return _err_info("au: empty input");
  }
  if n < 24 {
    return _err_info("au: truncated header");
  }
  if !_has_magic(data) {
    return _err_info("au: bad magic");
  }
  let off = _be_u32(data, 4);
  if off < 24 {
    return _err_info("au: bad data offset");
  }
  if off > n {
    return _err_info("au: data offset past end");
  }
  let enc = _be_u32(data, 12);
  if au_encoding_bits(enc) == 0 {
    return _err_info("au: unknown encoding");
  }
  let ch = _be_u32(data, 20);
  if ch == 0 {
    return _err_info("au: zero channels");
  }
  let rate = _be_u32(data, 16);
  if rate == 0 {
    return _err_info("au: zero sample rate");
  }
  let stored = _be_u32(data, 8);
  var known = true;
  var dsize: Int = 0;
  if stored == 4294967295 {
    known = false;
    dsize = n - off;
  } else {
    if stored > n - off {
      return _err_info("au: data size overrun");
    }
    dsize = stored;
  }
  var info = Vec[UInt8].new();
  var i = 24;
  while i < off {
    info.push(data[i]);
    i = i + 1;
  }
  let parsed = AuInfo{
    encoding: enc;
    sample_rate: rate;
    channels: ch;
    size_known: known;
    stored_size: stored;
    data_offset: off;
    data_size: dsize;
    info_bytes: info;
  };
  return _ok_info(parsed);
}

/// True when au_parse succeeds. Complexity: O(data.len()).
pub fn au_is_valid(data: &Vec[UInt8]) -> Bool {
  let pr = au_parse(data);
  return pr.is_ok;
}

// --------------------------------------------------
//  Public API: building
// --------------------------------------------------

// Shared builder body: canonical 24-byte header, `size_field` written to the
// data-size slot, then the info bytes and the samples verbatim.
fn _build(samples: &Vec[UInt8], f: &AuFormat, info: Str, size_field: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, ".snd");
  _push_be(&mut out, _clamp_u32(24 + info.len()), 4);
  _push_be(&mut out, _clamp_u32(size_field), 4);
  _push_be(&mut out, _clamp_u32(f.encoding), 4);
  _push_be(&mut out, _clamp_u32(f.sample_rate), 4);
  _push_be(&mut out, _clamp_channels(f.channels), 4);
  builder.sb_push_str(&mut out, info);
  var i = 0;
  while i < samples.len() {
    out.push(samples[i]);
    i = i + 1;
  }
  return out;
}

/// Build a complete AU file: the canonical 24-byte header, the `info` bytes
/// (verbatim, possibly empty) and `samples` verbatim. The data-size field is
/// written as `samples.len()` and the data offset as `24 + info.len()`; both
/// are clamped to the u32 range, `sample_rate` to 0..4294967295 and
/// `channels` to 1..4294967295. `encoding` is written as given, so unknown
/// ids produce output that au_parse rejects. A sample buffer of 2^32 bytes or
/// more cannot be represented (32-bit size field; out of scope).
/// Complexity: O(info.len() + samples.len()).
pub fn au_build(samples: &Vec[UInt8], f: &AuFormat, info: Str) -> Vec[UInt8] {
  return _build(samples, f, info, samples.len());
}

/// Like au_build, but writes the 0xFFFFFFFF "unknown size" sentinel into the
/// data-size field. au_parse resolves it to `data.len() - data_offset` (the
/// rest of the buffer), which makes the round-trip exact for a file that ends
/// with its audio data. Complexity: O(info.len() + samples.len()).
pub fn au_build_unknown_size(samples: &Vec[UInt8], f: &AuFormat, info: Str) -> Vec[UInt8] {
  return _build(samples, f, info, 4294967295);
}

// --------------------------------------------------
//  Public API: accessors
// --------------------------------------------------

/// Copy of the raw info field bytes (offsets 24..data_offset), exactly as
/// stored. Complexity: O(info_bytes.len()).
pub fn au_info_bytes(info: &AuInfo) -> Vec[UInt8] {
  let src = info.info_bytes;
  var out = Vec[UInt8].new();
  var i = 0;
  while i < src.len() {
    out.push(src[i]);
    i = i + 1;
  }
  return out;
}

/// The info field as text. Ok("") for an empty field; Ok(text) when every
/// byte is printable ASCII (0x20..0x7E); Err("au: bad info text") otherwise
/// (control bytes, DEL and non-ASCII bytes are rejected; the raw bytes remain
/// available through au_info_bytes). Complexity: O(info_bytes.len()).
pub fn au_info_text(info: &AuInfo) -> Result[Str, Str] {
  let bytes = info.info_bytes;
  if !_printable_range(&bytes, 0, bytes.len()) {
    return _err_str("au: bad info text");
  }
  return _ok_str(_str_range(&bytes, 0, bytes.len()));
}

/// Absolute byte offset of the first audio byte. Complexity: O(1).
pub fn au_data_offset(info: &AuInfo) -> Int {
  return info.data_offset;
}

/// Resolved audio span length (`data_size`): the declared size when known,
/// the rest of the buffer for the 0xFFFFFFFF sentinel. Complexity: O(1).
pub fn au_data_size(info: &AuInfo) -> Int {
  return info.data_size;
}

/// True when the header carried a real data size; false for the sentinel.
/// Complexity: O(1).
pub fn au_size_known(info: &AuInfo) -> Bool {
  return info.size_known;
}

/// Raw data-size field (0xFFFFFFFF when unknown). Complexity: O(1).
pub fn au_stored_size(info: &AuInfo) -> Int {
  return info.stored_size;
}

/// Channel count of a parsed header. Complexity: O(1).
pub fn au_channels(info: &AuInfo) -> Int {
  return info.channels;
}

/// Sample rate in Hz of a parsed header. Complexity: O(1).
pub fn au_sample_rate(info: &AuInfo) -> Int {
  return info.sample_rate;
}

/// Copy the audio bytes: `data_size` bytes at `data_offset` (for the
/// unknown-size sentinel that is the rest of the buffer after the offset).
/// Err("au: data size overrun") when that span does not fit `data` (e.g.
/// `info` was parsed from a different or truncated buffer).
/// Complexity: O(data_size).
pub fn au_audio_data(data: &Vec[UInt8], info: &AuInfo) -> Result[Vec[UInt8], Str] {
  let off = info.data_offset;
  let size = info.data_size;
  if off < 0 {
    return _err_bytes("au: data size overrun");
  }
  if size < 0 {
    return _err_bytes("au: data size overrun");
  }
  if off + size > data.len() {
    return _err_bytes("au: data size overrun");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < size {
    out.push(data[off + i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Frame count: `data_size / (channels * bytes_per_sample)`, floor division
/// (an incomplete trailing frame is ignored). Err("au: zero channels") for
/// channels <= 0, Err("au: unknown encoding") when the encoding id has no
/// documented byte size, Err("au: data size overrun") for a negative span;
/// au_parse never returns those, so they are only reachable for hand-built
/// AuInfo values. Complexity: O(1).
pub fn au_frame_count(info: &AuInfo) -> Result[Int, Str] {
  if info.channels <= 0 {
    return _err_int("au: zero channels");
  }
  let bps = au_encoding_bytes(info.encoding);
  if bps <= 0 {
    return _err_int("au: unknown encoding");
  }
  let frame = info.channels * bps;
  if frame <= 0 {
    return _err_int("au: zero channels");
  }
  if info.data_size < 0 {
    return _err_int("au: data size overrun");
  }
  return _ok_int(info.data_size / frame);
}

/// Playback duration in whole milliseconds: `frames * 1000 / sample_rate`
/// (floor division). Err("au: zero sample rate") when the rate is <= 0 (this
/// check runs first); otherwise the au_frame_count errors propagate
/// (Err("au: unknown encoding") / Err("au: zero channels")). Both are
/// unreachable from au_parse, so they only affect hand-built AuInfo values.
/// Complexity: O(1).
pub fn au_duration_ms(info: &AuInfo) -> Result[Int, Str] {
  if info.sample_rate <= 0 {
    return _err_int("au: zero sample rate");
  }
  let fr = au_frame_count(info);
  if !fr.is_ok {
    return _err_int(fr.error);
  }
  return _ok_int(fr.value * 1000 / info.sample_rate);
}
